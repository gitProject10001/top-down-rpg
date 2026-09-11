extends SceneTree
## Headless verification of the whole loop, with the real autoloads and the real scenes. Run:
##   Godot_console.exe --headless --path . --script res://scripts/traits/tests/verify_loop.gd
## Non-zero exit code on any failure.
##
## verify_traits.gd holds the MODEL still and verify_slice.gd holds the DUNGEON still. This one
## exists for the things that are only true once they are wired together — and in particular for
## the death path, which is the single piece of this feature with no prior art in the codebase:
## before it, dying set the state machine to Dead and stopped there forever.
##
## It drives main.tscn for real, which means setting current_scene by hand — World.go_to reads it,
## and a --script SceneTree does not set it for you.

const DEATH_WAIT := 20.0
const EXPECTED_SUITES := 5

var _fails: Array[String] = []
var _suites := 0
var _main: Node


func _initialize() -> void:
	_run()


## Unlike the model suite, this one drives the REAL Traits autoload, which writes to the real save
## path — and it calls reset_state(). Put the developer's own progress back afterwards.
const SAVE := "user://traits_save.dat"
const SAVE_BACKUP := "user://traits_save.dat.loop_backup"


func _run() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.copy_absolute(SAVE, SAVE_BACKUP)

	await _boot()
	if _main == null:
		print("[VERIFY] LOOP FAIL — main.tscn would not load")
		_restore_save()
		quit(1)
		return

	await _wiring_suite()
	await _descent_suite()
	await _clear_suite()
	await _death_suite()
	await _victory_suite()
	_restore_save()

	if _suites != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported — one unwound silently"
				% [_suites, EXPECTED_SUITES])
	if _fails.is_empty():
		print("[VERIFY] LOOP PASS")
		quit(0)
	else:
		print("[VERIFY] LOOP FAIL — %d problem(s):" % _fails.size())
		for f in _fails:
			print("   " + f)
		quit(1)


func _boot() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		return
	_main = packed.instantiate()
	root.add_child(_main)
	# On the SceneTree, not on `root` — root is a Window and has no such property, so setting it
	# there silently does nothing and World.go_to then fails on a null current_scene several
	# suites later, a long way from the mistake.
	current_scene = _main
	for i in 20:
		await process_frame


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _done(name_of: String, note: String) -> void:
	_suites += 1
	print("[VERIFY] %s suite: %s" % [name_of, note])


func _player() -> Node:
	return root.get_tree().get_first_node_in_group("player")


func _wait(seconds: float) -> void:
	# Real time, not frames: the death beat is a wall-clock timer and counting frames would make
	# this pass or fail depending on how fast the machine is.
	await root.get_tree().create_timer(seconds, true, false, true).timeout


# ----------------------------------------------------------------------------------------------

## Everything is registered and talking to everything else.
func _wiring_suite() -> void:
	for path in ["/root/Traits", "/root/Notice", "/root/Sheet", "/root/Run"]:
		_ok(root.get_node_or_null(path) != null, "%s is not registered as an autoload" % path)
	var p := _player()
	_ok(p != null, "no node in group 'player'")
	if p:
		var belt = p.find_child("ToolBelt", true, false)
		_ok(belt != null, "the player has no ToolBelt")
		if belt:
			_ok(belt.tools.size() == 3, "the belt built %d tools, expected 3" % belt.tools.size())
			# ONE tool at the door. The other two are the dungeon's to hand out, and a belt that
			# opens with all three quietly removes two of the run's rewards.
			_ok(belt.carried().size() == 1,
					"the belt carries %d tools before a descent, expected 1" % belt.carried().size())
			_ok(belt.active_tool() != null, "the belt has no active tool")
	var hub := 0
	for n in _walk(_main):
		if n is HubNPC:
			hub += 1
	_ok(hub == 3, "the hub has %d people in it, expected 3" % hub)
	_done("wiring", "4 autoloads, 3 tools (1 carried), 3 people in the hub")


## Walking into the crypt starts a run.
func _descent_suite() -> void:
	var traits := root.get_node_or_null("/root/Traits")
	var run := root.get_node_or_null("/root/Run")
	var world := root.get_node_or_null("/root/World")
	traits.reset_state()
	# A boon left over from an earlier descent would make the first room of this one stronger than
	# it should be, which is exactly what begin_run is for.
	traits.run_boons.append("logic_weakpoint")

	await world.go_to(load("res://scenes/world/zone_slice.tscn"), "SpawnA")
	for i in 10:
		await process_frame

	_ok(run.in_run, "walking into the crypt did not start a run")
	_ok(traits.run_boons.is_empty(), "last run's boons survived into this one")
	_ok(root.get_tree().get_first_node_in_group("dungeon") != null, "no dungeon in the tree")
	var p := _player()
	if p:
		var belt = p.find_child("ToolBelt", true, false)
		_ok(belt.carried().size() == 1, "the descent did not ration the belt back to one tool")
	_done("descent", "run begun, boons shed, belt reset")


## Clearing a room pays out and raises the offer.
func _clear_suite() -> void:
	var traits := root.get_node_or_null("/root/Traits")
	var zone := root.get_tree().get_first_node_in_group("dungeon")
	var room: Node = null
	for c in zone.get_children():
		if c is DungeonRoom:
			room = c
			break
	if room == null:
		_fails.append("the crypt built no rooms")
		_done("clear", "skipped — no rooms")
		return
	var before: int = traits.run_insight
	room.cleared.emit()
	for i in 4:
		await process_frame
	_ok(traits.run_insight > before,
			"clearing a room paid no Insight (%d -> %d)" % [before, traits.run_insight])
	var pedestals := 0
	for n in _walk(room):
		if n is BoonPedestal:
			pedestals += 1
	_ok(pedestals == 1, "a cleared room raised %d pedestals, expected 1" % pedestals)
	_done("clear", "Insight paid and one pedestal raised")


## THE PATH THAT DID NOT EXIST. Kill the player and check they arrive home able to move.
func _death_suite() -> void:
	var traits := root.get_node_or_null("/root/Traits")
	var run := root.get_node_or_null("/root/Run")
	var p := _player()
	if p == null:
		_fails.append("no player to kill")
		_done("death", "skipped")
		return
	traits.add_insight(5)
	var banked_before: int = traits.insight
	var deaths_before: int = traits.deaths

	p.health.take_damage(999, null)
	# POLLED, not slept. The journey home is a 1.7 s death beat, two 0.3 s fades and a full reload
	# of the hub scene, and that last part is however long instantiating a 570-node scene takes on
	# this machine. A fixed wait either flakes or is padded to the worst case; waiting for the
	# actual condition is neither.
	var waited := 0.0
	while waited < DEATH_WAIT and not p.health.is_alive():
		await _wait(0.1)
		waited += 0.1
	for i in 10:
		await process_frame

	_ok(not run.in_run, "the run never ended after death")
	_ok(traits.deaths == deaths_before + 1, "the death was not counted")
	_ok(traits.insight > banked_before,
			"the run's Insight was not banked on death (%d -> %d)" % [banked_before, traits.insight])
	# Dying is a source of material, not just a reset.
	_ok(not traits.convictions.is_empty(), "dying handed over no Conviction")
	_ok(traits.last_death_cause != "", "nothing recorded what killed you")

	# And the part that used to be impossible: a body that works.
	var alive: bool = p.health.is_alive()
	_ok(alive, "the player is still dead in the hub — Health._dead never cleared")
	_ok(p.health.hp == p.health.max_hp,
			"the player came home on %d of %d hp" % [p.health.hp, p.health.max_hp])
	var fsm = p.find_child("StateMachine", true, false)
	_ok(fsm != null and String(fsm.current_state.name) != "Dead",
			"the state machine is still parked in Dead — input would be frozen")
	_ok(root.get_tree().get_first_node_in_group("dungeon") == null, "the crypt was not left behind")
	_done("death", "banked %d Insight, gained a Conviction, and came home able to move"
			% (traits.insight - banked_before))


## THE ENDING. Beat the boss, walk out, and the slice should actually close — the three of them
## talk, the card comes up, and the completion sticks to the save. Before this the loop simply
## never terminated.
func _victory_suite() -> void:
	var traits := root.get_node_or_null("/root/Traits")
	var run := root.get_node_or_null("/root/Run")
	var world := root.get_node_or_null("/root/World")
	var sheet := root.get_node_or_null("/root/Sheet")
	var dialogue := root.get_node_or_null("/root/Dialogue")
	traits.slice_complete = false
	var wins_before: int = traits.victories

	await world.go_to(load("res://scenes/world/zone_slice.tscn"), "SpawnA")
	for i in 10:
		await process_frame
	_ok(run.in_run, "the victory run never started")
	# Beat the boss: find the room that owns it and clear it the way a last kill would.
	var zone := root.get_tree().get_first_node_in_group("dungeon")
	var boss: Node = null
	for c in zone.get_children():
		if c is DungeonRoom and (c as DungeonRoom).is_boss:
			boss = c
	_ok(boss != null, "the crypt built no boss room")
	if boss == null:
		_done("victory", "skipped — no boss")
		return
	boss.cleared.emit()
	for i in 4:
		await process_frame
	_ok(run.boss_down, "clearing the boss room did not record a victory")

	# Walk out the way the victory portal does.
	await world.go_to(load("res://scenes/world/room.tscn"), "SpawnFromCrypt")
	var waited := 0.0
	while waited < DEATH_WAIT and not (dialogue.active or sheet.active):
		await _wait(0.1)
		waited += 0.1
	_ok(dialogue.active or sheet.active, "nothing happened on coming home a winner")
	_ok(traits.slice_complete, "the completion was not recorded")
	_ok(traits.victories == wins_before + 1, "the victory was not counted")

	# The closing conversation, then the card.
	if dialogue.active:
		var lines := 0
		while dialogue.active and lines < 12:
			dialogue._skip()
			dialogue._advance()
			lines += 1
			await process_frame
		_ok(lines > 1, "the closing conversation was one line long")
	waited = 0.0
	while waited < 6.0 and not sheet.active:
		await _wait(0.1)
		waited += 0.1
	var notice := root.get_node_or_null("/root/Notice")
	_ok(sheet.active, "the end card never came up (dialogue.active=%s notice.active=%s)"
			% [dialogue.active, notice.active if notice else "?"])
	var rows: int = Finale.card(traits).size()
	_ok(rows >= 6, "the end card only had %d rows to report" % rows)
	sheet.close()
	_done("victory", "boss down, the three spoke, the card reported %d rows, completion saved" % rows)


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _restore_save() -> void:
	if FileAccess.file_exists(SAVE_BACKUP):
		DirAccess.copy_absolute(SAVE_BACKUP, SAVE)
		DirAccess.remove_absolute(SAVE_BACKUP)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)

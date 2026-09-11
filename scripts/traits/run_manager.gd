extends Node
## Autoload "Run" — one descent, as an object with a beginning and an end.
##
## Traits owns the numbers; this owns the LIFECYCLE: when a run starts, what a kill is worth, and —
## the part that did not exist before — what happens after you die.
##
## THE DEATH PATH IS THE WHOLE REASON THIS FILE EXISTS. Until now dying set the player's state
## machine to Dead and stopped. There was no way back: World.go_to moves a player to a spawn marker
## and touches nothing else, so a corpse arrives in the hub still a corpse — Health._dead latched,
## hp zero, FSM parked. Everything below is the ordering that undoes that, and the ordering is the
## bug: get it wrong and you spawn in the garden unable to move, which reads as a physics fault
## rather than a lifecycle one.

const HUB := "res://scenes/world/room.tscn"
const HUB_SPAWN := "SpawnFromCrypt"

## Insight is the run currency. Deliberately small numbers: a descent should be worth a point or
## two, not a shopping trip, or the hub stops being a place you have to keep coming back to.
const INSIGHT_PER_KILL := 1
const INSIGHT_PER_ROOM := 2
const INSIGHT_PER_SECRET := 3

## How long the corpse lies there before the world fades. Long enough to see what killed you,
## short enough not to be a punishment on top of a punishment.
const DEATH_BEAT := 1.7

var in_run := false
## Set when the boss room clears. The difference between "you left" and "you won", and the hub's
## dialogue cares about it even though the walk home looks the same.
var boss_down := false

var _ending := false                           ## guards the double-end (see end_run)


func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.enemy_died.connect(_on_enemy_died)
		bus.player_died.connect(_on_player_died)
		bus.zone_changed.connect(_on_zone_changed)


## Called by the slice generator as the dungeon builds, behind the portal fade.
func begin(seed_value := 0) -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.begin_run(seed_value)
		_apply_max_hp(traits)
	# The tools are the dungeon's to hand out, every descent. Without this you would keep last run's
	# finds and the second descent would open with all three, which is the pacing this rations.
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var belt = player.find_child("ToolBelt", true, false)
		if belt and belt.has_method("reset_to_start"):
			belt.reset_to_start()
	in_run = true
	boss_down = false
	_ending = false


## THE OTHER WAY A RUN ENDS: you walk out of it. The boss's victory portal and the start room's
## return portal both call World.go_to directly and know nothing about Insight — so rather than
## teaching two portals about runs, this watches for the world no longer being a dungeon.
##
## By GROUP rather than by zone name: the crypt roots itself in "dungeon", and asking whether one
## exists is the same question as "am I still down there", whatever the scene ends up being called.
func _on_zone_changed(_zone_name: String) -> void:
	if not in_run or _ending:
		return
	if get_tree().get_first_node_in_group("dungeon") != null:
		return                                 # arriving IN a dungeon, not leaving one
	in_run = false
	_ending = true
	var won := boss_down
	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.end_run(won)
	_restore_player(traits)
	_ending = false
	if won and traits:
		_finale(traits)


## THE ENDING. You beat the boss, you came up the stairs, and the three of them are waiting.
##
## Run owns the sequencing because Run is what knows the descent is over; the words live in Finale
## and the card lives in Sheet. Deliberately AFTER _restore_player, so the body is whole before
## anyone talks to it — an ending played over a corpse would be a strange note to close on.
func _finale(traits: Node) -> void:
	traits.slice_complete = true
	traits.save_state()
	# Let World.go_to's fade-in finish first. zone_changed fires before it, so opening a
	# conversation here without waiting would play the first line into a black screen.
	await get_tree().create_timer(1.1, true, false, true).timeout
	var dialogue := get_node_or_null("/root/Dialogue")
	var sheet := get_node_or_null("/root/Sheet")
	if dialogue and not dialogue.active:
		dialogue.start(Finale.convo(traits))
		await dialogue.finished
	if sheet:
		sheet.show_finale()


func note_room_cleared() -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits == null or not in_run:
		return
	traits.run_rooms_cleared += 1
	traits.add_insight(INSIGHT_PER_ROOM)


func note_secret() -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits and in_run:
		traits.add_insight(INSIGHT_PER_SECRET)


func _on_enemy_died(_enemy: Node) -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits == null or not in_run:
		return
	traits.run_kills += 1
	traits.add_insight(INSIGHT_PER_KILL)


# ----------------------------------------------------------------------------------------------

## Dying is not a reset, it is a source of material. You come home with the Insight you earned and
## an idea you did not ask for.
func _on_player_died() -> void:
	if not in_run or _ending:
		return
	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.last_death_cause = _describe_death()
		# The first death is where Fear of the Abyss comes from; after that, whichever idea the
		# descent has not handed you yet. gain_conviction is a no-op for one already held, so this
		# walks forward rather than re-offering the same thought every run.
		for id: String in ["fear_of_the_abyss", "traumatized_reflexes", "heroic_hubris"]:
			if traits.gain_conviction(id):
				break
	await get_tree().create_timer(DEATH_BEAT, true, false, true).timeout
	end_run(false)


## What the archetypes get to be sarcastic about. Read off the world at the moment of death rather
## than plumbed through the damage path — the last enemy standing next to you is very nearly always
## the right answer, and it costs nothing to be wrong about it occasionally.
func _describe_death() -> String:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return "the dark"
	var best: Node3D = null
	var best_d := 9.0
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e):
			continue
		var d := e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return "something that had already left"
	return String(best.name).to_snake_case().replace("_", " ")


## The run is over, win or lose. Order matters and is not interchangeable:
##
##   1. bank FIRST, while the run's numbers are still the run's
##   2. THEN travel — go_to frees the whole zone, so anything still reading it must be done
##   3. THEN put the player back together, because go_to's own await has to have finished before
##      the body it moved is worth touching
func end_run(victory: bool) -> void:
	if _ending or not in_run:
		return
	_ending = true
	in_run = false

	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.end_run(victory)

	var world := get_node_or_null("/root/World")
	if world:
		await world.go_to(load(HUB), HUB_SPAWN)

	_restore_player(traits)
	_ending = false


func _restore_player(traits: Node) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var health = player.get("health")
	if health:
		if traits:
			_apply_max_hp(traits)
		health.revive()
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)
	# Straight back to Idle. Dead.exit() does nothing, so there is no teardown to miss — but the FSM
	# will happily sit in Dead forever otherwise, and a state machine parked in a terminal state
	# looks exactly like frozen input.
	var fsm = player.find_child("StateMachine", true, false)
	if fsm and fsm.has_method("transition_to"):
		fsm.transition_to("Idle")


## A settled Conviction can move the ceiling. Health latches hp = max_hp in its own _ready, which
## fires before anything else can have an opinion, and the player is a static child of main.tscn so
## there is no instantiate-then-configure seam to use. So the shift is applied imperatively, from
## the authored base rather than from the current value — otherwise "+0" applied twice drifts.
func _apply_max_hp(traits: Node) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var health = player.get("health")
	if health == null:
		return
	health.max_hp = maxi(int(health.base_max_hp) + int(traits.max_hp_delta()), 1)
	health.hp = mini(int(health.hp), int(health.max_hp))

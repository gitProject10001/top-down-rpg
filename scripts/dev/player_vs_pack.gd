extends Node3D
## PLAYER VERSUS A PACK — the scene where enemies stop being a scrum.
##
## The other four benches are duels, and a duel hides the two things that break the moment you add
## a second body: every enemy steers straight at the player with `to_player.normalized()`, and
## every enemy body is on collision layer 1. Five of them converge on one point, shove each other
## off it, and all swing at once. Four enemies read as one enemy with four sprites.
##
## Two layers fix that, and only one of them is ours:
##   NAVIGATION is Godot's. A NavigationAgent3D with avoidance_enabled gives pathing, crowd
##   separation and flow-around from the engine's own RVO; `avoidance_priority` raised on whoever
##   is mid-swing is the entire "the crowd parts for the committed attacker" behaviour, in one
##   property assignment.
##   ARBITRATION is ours, because no engine ships it. CombatDirector hands out a small number of
##   attack tokens and a ring of angular slots, so the pack takes turns and encircles.
##
## THE OPT-IN IS THE AGENT. `enemy.gd` runs not one new line for a body with no NavigationAgent3D
## child — which is why the four pinned benches are provably the file that shipped, and why
## `Loner` below is in this scene at all.
##
## KEYS: WASD move · LMB attack · Space jump · Shift dash · RMB guard/parry ·
##       MMB/R3 lock · wheel-down/L3 cycle lock · R restart · F1 readout · F3 hitboxes ·
##       F5 AI graph + ring · F6 combat zones
##
## THE GATE (run as a SCENE, never --script — the --script harness registers no autoloads):
##   godot --resolution 900x760 res://scenes/dev/player_vs_pack.tscn --log-file pack.log -- --demo=probe
## Eyes:
##   ... -- --demo=shots --out=<dir>
##
## THE NAVMESH IS COMMITTED, NOT BAKED AT LOAD (scenes/dev/arena_navmesh.tres). It is baked by
## tools/bake_navmesh.gd. MOVING A ROCK OR A WALL IN THIS SCENE INVALIDATES IT AND NOTHING WILL
## TELL YOU — the enemies will simply path through the new geometry. Re-bake after any edit here.

@onready var _player: Node3D = $Player
@onready var _readout: Label = $UI/Readout

var _hits_on_player := 0
var _t := 0.0


func _ready() -> void:
	var ph := _player.get_node_or_null("Health")
	if ph:
		ph.damaged.connect(func(_a, _s): _hits_on_player += 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			_demo(a.substr(7).rstrip("/\\"))


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.is_pressed() or e.is_echo():
		return
	match (e as InputEventKey).keycode:
		KEY_R:
			get_tree().reload_current_scene()
		KEY_F1:
			($UI as CanvasLayer).visible = not ($UI as CanvasLayer).visible


## Every live Enemy in the scene, in scene order. Not the "enemy" group: the group is what the
## LOCK and the player's targeting read, and a probe that measured the same list they do could
## never catch a body that fell out of it.
func _pack() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for c in get_children():
		if c is Enemy and is_instance_valid(c):
			out.append(c as Enemy)
	return out


func _process(_delta: float) -> void:
	var dbg := get_node_or_null("/root/Dbg")
	if dbg != null and bool(dbg.clean):
		($UI as CanvasLayer).visible = false
	_t += _delta
	var pack := _pack()
	var lines := PackedStringArray()
	if pack.is_empty():
		_readout.text = "pack down after %.1f s — R to restart" % _t
		return
	lines.append("pack %d alive      %.0f s      hits on you %d" % [pack.size(), _t, _hits_on_player])
	for e in pack:
		var hp := e.get_node("Health") as Health
		var d := 0.0
		if is_instance_valid(_player):
			d = _player.global_position.distance_to(e.global_position)
		lines.append("%-11s %-8s hp %2d/%-2d  %5.2f m  nav %s" % [
				e.name,
				["IDLE", "CHASE", "ATTACK", "FLINCH", "STAGGER", "DEAD", "FEAR"][int(e.get("_state"))],
				hp.hp, hp.max_hp, d,
				"yes" if e.get("_agent") != null else "OFF"])
	lines.append("WASD · LMB attack · MMB lock · wheel cycle · F5 ring · F6 zones · R restart")
	_readout.text = "\n".join(lines)


# ---------------------------------------------------------------------------------------------
# Headless proof of the COORDINATION specifically.

func _demo(kind: String) -> void:
	match kind:
		"probe":
			await _demo_probe()
		_:
			push_warning("unknown --demo=%s" % kind)
			get_tree().quit(1)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _demo_probe() -> void:
	var fails: Array[String] = []
	var notes: Array[String] = []
	# Enough frames for the NavigationServer's first map sync AND for every agent's own
	# _arm_navigation to have come back. Four was not.
	await _settle(12)

	_probe_navmesh(fails, notes)
	await _probe_optin(fails, notes)
	_probe_static(fails, notes)
	await _probe_movement(fails, notes)
	await _probe_engagement(fails, notes)
	await _probe_encirclement(fails, notes)
	await _probe_leaks(fails, notes)
	await _probe_lock(fails, notes)

	for n in notes:
		print("[PROBE] note  " + n)
	for f in fails:
		print("[PROBE] FAIL  " + f)
	print("[PROBE] %s — %d checks failed" % ["RED" if fails.size() else "GREEN", fails.size()])
	get_tree().quit(1 if fails.size() else 0)


## BLOCK A — the navmesh is real, and is the one we think it is.
##
## The failure this exists for is silent and total: the arena floor's collider is a
## WorldBoundaryShape3D, an infinite plane the generator emits no geometry for. A bake set to
## STATIC_COLLIDERS therefore parses the walls, parses the rocks, parses no floor, and returns a
## perfectly valid EMPTY NavigationMesh that saves without an error and produces a scene in which
## every enemy stands still forever. Nothing about that looks like a bug until you play it.
func _probe_navmesh(fails: Array[String], notes: Array[String]) -> void:
	var region := $NavRegion as NavigationRegion3D
	var nm := region.navigation_mesh
	if nm == null:
		fails.append("NavRegion has no navigation_mesh at all")
		return
	var polys := nm.get_polygon_count()
	if polys == 0:
		fails.append("navmesh has 0 polygons — the bake parsed nothing (see tools/bake_navmesh.gd)")
		return
	notes.append("navmesh %d polygons, %d vertices" % [polys, nm.get_vertices().size()])

	# The settings, asserted rather than trusted. BOTH is the only parse mode that sees this
	# arena: MESH_INSTANCES misses the walls (they carry no mesh at all) and STATIC_COLLIDERS
	# misses the floor (the infinite plane above).
	if nm.geometry_parsed_geometry_type != NavigationMesh.PARSED_GEOMETRY_BOTH:
		fails.append("parsed_geometry_type is %d, must be PARSED_GEOMETRY_BOTH (2)"
				% nm.geometry_parsed_geometry_type)
	# ...and the group filter is what keeps five CHARACTER meshes out of the floor. Without it the
	# baker carves a permanent hole wherever a body happened to stand at bake time.
	if nm.geometry_source_geometry_mode != NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN:
		fails.append("source_geometry_mode is %d, must be GROUPS_WITH_CHILDREN (1)"
				% nm.geometry_source_geometry_mode)
	if nm.geometry_source_group_name != &"navmesh":
		fails.append("source_group_name is '%s', must be 'navmesh'" % nm.geometry_source_group_name)
	# One navmesh serves every body in the pack, so it must be eroded for the WIDEST of them.
	# The epsilon is not slack: resource floats are 32-bit, so an authored 0.95 reads back as
	# 0.94999999 and a `< 0.95` test fails against the value it just asked for.
	if nm.agent_radius < 0.94:
		fails.append("agent_radius %.2f — must fit the brute (0.95)" % nm.agent_radius)
	# The region will silently refuse to connect if these drift from the map's own cell size.
	if not is_equal_approx(nm.cell_size, 0.25) or not is_equal_approx(nm.cell_height, 0.25):
		fails.append("cell %.3f/%.3f must match navigation/3d/default_cell_size (0.25)"
				% [nm.cell_size, nm.cell_height])

	var map := region.get_navigation_map()
	# THE MAP SYNCS AT THE END OF A PHYSICS FRAME, and every query before that answers ZERO — not
	# an error, just the origin, for every point you ask about. Force it, then confirm the region
	# actually landed in the map: an unsynced map and a map with a hole are the same reading, and
	# only one of them is a bug in the bake.
	NavigationServer3D.map_force_update(map)
	var regions := NavigationServer3D.map_get_regions(map).size()
	if regions == 0:
		fails.append("the navigation map holds no regions — NavRegion never registered")
		return
	notes.append("navigation map: %d region(s), cell %.2f"
			% [regions, NavigationServer3D.map_get_cell_size(map)])

	# COVERAGE. Eight points on a 20 m ring — open ground the fight actually uses — each must land
	# on the mesh. A navmesh that baked only one corner passes the polygon-count check above.
	# The ARENA CENTRE is deliberately NOT sampled: RockGate stands at (0, 1), so the origin is
	# inside a carved hole and reads 1.0 m off the mesh. That is the bake working, not failing.
	var worst := 0.0
	var worst_at := Vector3.ZERO
	for i in 8:
		var q := Vector3(cos(TAU * float(i) / 8.0) * 20.0, 0.0, sin(TAU * float(i) / 8.0) * 20.0)
		var got := NavigationServer3D.map_get_closest_point(map, q)
		var off := Vector2(got.x - q.x, got.z - q.z).length()
		if off > worst:
			worst = off
			worst_at = q
	if worst > 1.5:
		fails.append("navmesh coverage: %.2f m from the mesh at %v — a hole in the arena"
				% [worst, worst_at])
	notes.append("navmesh coverage: worst of 8 ring samples %.2f m off the mesh, at %.0f,%.0f"
			% [worst, worst_at.x, worst_at.z])

	# THE ROCKS ARE IN THE BAKE — the one assertion that catches the trap this whole tool is
	# shaped around. scripts/props/rock.gd builds its mesh AND its collider in _ready(), so a bake
	# that instantiated the scene without adding it to the tree sees a rockless arena, produces a
	# navmesh that is *more* complete than the real one, passes every check above, and lets the
	# pack walk through three boulders. A carved rock is the proof the tool entered the tree.
	var gate := $Rocks/RockGate as Node3D
	var at_rock := NavigationServer3D.map_get_closest_point(map, gate.global_position)
	var carved := Vector2(at_rock.x - gate.global_position.x,
			at_rock.z - gate.global_position.z).length()
	if carved < 0.5:
		fails.append("RockGate at %v is not carved out of the navmesh (nearest mesh %.2f m) — the "
				% [gate.global_position, carved]
				+ "bake did not see the rocks; check that bake_navmesh.gd add_child()s the scene")
	notes.append("rock carving: RockGate hole extends %.2f m from its centre" % carved)

	# CONTAINMENT. The floor MESH is 90x90 but the walls stand at +-30, so without a baking AABB
	# there is 30 m of navmesh outside the arena for a slot ring to resolve onto.
	var outside := NavigationServer3D.map_get_closest_point(map, Vector3(40, 0, 40))
	if absf(outside.x) > 30.0 or absf(outside.z) > 30.0:
		fails.append("navmesh extends past the walls to %v — filter_baking_aabb did not clip the "
				% outside + "90 m floor plane back to the 60 m arena")
	notes.append("navmesh containment: (40,0,40) resolves to %.1f,%.1f" % [outside.x, outside.z])


## BLOCK B — the opt-in is the agent, and it is armed.
##
## Both halves matter. A body that never found its agent silently falls back to the straight line
## and every coordination assertion below it becomes vacuous; a body whose _arm_navigation never
## came back does the same thing for a different reason, and reads identically from outside.
func _probe_optin(fails: Array[String], notes: Array[String]) -> void:
	for e in _pack():
		var has_agent: bool = e.get("_agent") != null
		var armed: bool = bool(e.get("_nav_ready"))
		if e.name == "Loner":
			# THE CONTROL BODY. It carries no agent on purpose, so it runs the enemy.gd that
			# shipped -- and it proves that claim INSIDE this scene instead of asking you to go
			# and read four other ones.
			if has_agent:
				fails.append("Loner has a NavigationAgent3D — it is the no-op control and must not")
			continue
		if not has_agent:
			fails.append("%s has no NavigationAgent3D child — it is not opted in" % e.name)
		elif not armed:
			fails.append("%s never armed navigation (_arm_navigation did not return)" % e.name)
	var armed_count := 0
	for e in _pack():
		if e.get("_agent") != null and bool(e.get("_nav_ready")):
			armed_count += 1
	notes.append("opt-in: %d of %d bodies carry an armed agent" % [armed_count, _pack().size()])


## BLOCK H — it still moves, and the navmesh is being USED rather than merely existing.
##
## The clearance half is the only assertion in this probe that can tell a working NavigationAgent
## from a body walking a straight line with extra steps. RockGate sits exactly on the line between
## the test spawn and the player, so a body that ignores its path walks into it and stops.
func _probe_movement(fails: Array[String], notes: Array[String]) -> void:
	var sub := get_node_or_null("Swordsman1") as Enemy
	var gate := $Rocks/RockGate as Node3D
	if sub == null:
		fails.append("no Swordsman1 to measure movement with")
		return
	# Close enough to aggro (10 m), and with the rock squarely between them.
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.global_position = Vector3(0, 1.1, 5)
	sub.global_position = Vector3(0, 0, -4)
	NavigationServer3D.map_force_update((sub.get("_agent") as NavigationAgent3D).get_navigation_map())
	await _settle(4)

	var start := sub.global_position
	var closest := 99.0
	var moved := 0.0
	for i in 150:
		await get_tree().physics_frame
		if not is_instance_valid(sub):
			break
		var d := Vector2(sub.global_position.x - gate.global_position.x,
				sub.global_position.z - gate.global_position.z).length()
		closest = minf(closest, d)
		moved = maxf(moved, start.distance_to(sub.global_position))
	if moved < 0.5:
		fails.append("Swordsman1 moved %.2f m in 150 frames — it is not pathing at all" % moved)
	# 0.9 is RockGate's authored radius; 0.3 is the clearance a body walking AROUND it keeps and a
	# body walking INTO it cannot.
	if closest < 1.2:
		fails.append("Swordsman1 came within %.2f m of RockGate's centre (radius 0.9) — it walked "
				% closest + "into the rock instead of around it; the navmesh is not being used")
	notes.append("pathing: moved %.2f m, cleared RockGate by %.2f m from its 0.90 m centre"
			% [moved, closest])


## BLOCKS K and L — two single-line facts that only a multi-enemy scene can get wrong.
func _probe_static(fails: Array[String], notes: Array[String]) -> void:
	# K. hud.gd reads get_first_node_in_group("boss") — ONE bar, first found. No body in this pack
	# sets is_boss, and that must stay true: the first pack containing a boss will show a single
	# bar and silently pick a body, which is a HUD problem and not this ticket's to solve.
	if get_tree().get_first_node_in_group("boss") != null:
		fails.append("something in the pack is is_boss — the HUD boss bar is singular (hud.gd)")
	# L. Three swordsmen share one attack_anim_speed, so the ~11 ms CACHE_MODE_IGNORE_DEEP library
	# build must happen ONCE. More entries here would be the spawn stutter enemy.gd warns about.
	var libs: int = Enemy._lib_cache.size()
	if libs > 1:
		fails.append("%d clip libraries built — bodies sharing attack_anim_speed must share one"
				% libs)
	notes.append("spawn cost: %d shared clip library for %d bodies" % [libs, _pack().size()])


## Wait until somebody actually holds a turn. Returns null on timeout.
func _await_holder(frames: int) -> Enemy:
	for i in frames:
		await get_tree().physics_frame
		var snap := CombatDirector.snapshot(_player)
		if not snap.is_empty() and not snap["holders"].is_empty():
			return snap["holders"][0] as Enemy
	return null


## BLOCKS C, G and I — one sample run, three questions, because they are all questions about the
## same six seconds and running the fight three times would be three different fights.
func _probe_engagement(fails: Array[String], notes: Array[String]) -> void:
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.global_position = Vector3(0, 1.1, 5)
	# INVULNERABLE FOR THE SAMPLE, rather than healed between hits: five bodies on one player is a
	# fight the player loses, and a corpse answers none of the questions below. It changes nothing
	# about how the enemies behave — they attack a target, not a health bar.
	(_player.get_node("Health") as Health).set_invulnerable(true)
	CombatDirector.reset_counters()
	await _settle(30)

	var max_concurrent := 0
	var archer_attacked := false
	var priority_seen := false
	var archer := get_node_or_null("Archer") as Enemy
	for i in 360:
		await get_tree().physics_frame
		var snap := CombatDirector.snapshot(_player)
		if snap.is_empty():
			continue
		var holders: Array = snap["holders"]
		max_concurrent = maxi(max_concurrent, holders.size())
		if archer != null and is_instance_valid(archer):
			if int(archer.get("_state")) == Enemy.S.ATTACK:
				archer_attacked = true
			# I. A RANGED body must never consume a melee turn — it already holds its own standoff
			# band, and an archer blocking a swordsman from nine metres away is the cap doing the
			# exact opposite of its job.
			if holders.has(archer):
				fails.append("the Archer took a melee token — RANGED must never hold one")
		# G. Priority is the entire "crowd parts for the attacker" behaviour, and a silently
		# missing assignment looks like nothing at all. Catch it while a turn is actually held.
		if not holders.is_empty():
			var h := holders[0] as Enemy
			var ha := h.nav_agent()
			if ha != null and is_equal_approx(ha.avoidance_priority, CombatDirector.PRIORITY_HOLDER):
				for e in _pack():
					if e == h or e.name == "Loner" or e.nav_agent() == null:
						continue
					if is_equal_approx(e.nav_agent().avoidance_priority,
							CombatDirector.resting_priority(e)):
						priority_seen = true
						break

	# C. The cap must HOLD...
	if max_concurrent > CombatDirector.token_count:
		fails.append("%d bodies swung at once against a cap of %d"
				% [max_concurrent, CombatDirector.token_count])
	# ...and must be REACHED. A cap nobody reaches is a cap that is doing nothing, and the fight
	# would look identical with the director removed.
	if max_concurrent < CombatDirector.token_count:
		fails.append("the cap of %d was never reached (peak %d) — the token gate is not what is "
				% [CombatDirector.token_count, max_concurrent]
				+ "limiting this fight, so block F would be measuring nothing")
	notes.append("tokens: peak %d concurrent attackers against a cap of %d"
			% [max_concurrent, CombatDirector.token_count])
	if not priority_seen:
		fails.append("never observed a holder at priority %.2f beside a waiter at its authored "
				% CombatDirector.PRIORITY_HOLDER + "resting value — the avoidance_priority "
				+ "assignment is not happening")
	else:
		notes.append("priority: holder %.2f, resting values authored per body, both observed live"
				% CombatDirector.PRIORITY_HOLDER)
	if archer != null and is_instance_valid(archer) and not archer_attacked:
		fails.append("the Archer never attacked — the token gate silenced a body it must not touch")
	else:
		notes.append("ranged: the Archer fought throughout and never took a turn from the melee")

	# THE WATCHDOG, MEASURED WHERE IT WOULD ACTUALLY FIRE. Six seconds of five-body combat is the
	# load the release paths have to survive; the three staged cases in block D prove the mechanism,
	# this proves it under traffic. A reclaim here means some exit from S.ATTACK is not handing the
	# turn back and the fight is being rescued by its own safety net.
	var after := CombatDirector.snapshot(_player)
	var leaks := int(after.get("leak_reclaims", 0))
	var approach := int(after.get("approach_reclaims", 0))
	var granted := int(after.get("turns_granted", 0))
	var longest := float(after.get("max_hold_seen", 0.0))
	# THE CLASS THAT MUST BE ZERO. A turn recovered by the watchdog rather than handed back is a
	# release path in enemy.gd that did not run, and the fight only looked fine because the safety
	# net caught it.
	if leaks > 0:
		fails.append("the watchdog reclaimed %d turn(s) that should have been handed back %s — a "
				% [leaks, str(after.get("yank_reasons", {}))] + "release path in enemy.gd is not "
				+ "running")
	# THE CLASS THAT SHOULD NOT BE ZERO, AND SHOULD NOT BE MOST OF THEM. A body that is given a
	# turn and cannot close is supposed to lose it to somebody better placed -- that is the
	# approach deadline working, and in a crowd it will happen. If it happens to most turns, the
	# deadline is too short or the pack cannot reach the player at all, and the cap is being spent
	# on bodies that never swing.
	if granted > 0 and float(approach) / float(granted) > 0.4:
		fails.append("%d of %d turns expired unspent (%.0f%%) — bodies are being given turns they "
				% [approach, granted, 100.0 * float(approach) / float(granted)]
				+ "cannot reach the player to use")
	# HEADROOM, NOT JUST ABSENCE. The brute's 2.6 s cooldown plus its slam tween is the longest turn
	# in this fight; if it ever approaches token_max_hold the watchdog starts yanking live attackers
	# mid-swing, and that reads as an enemy that simply gives up halfway through an attack.
	if longest > CombatDirector.token_max_hold * 0.85:
		fails.append("longest turn %.2f s is within 15%% of token_max_hold %.1f s — raise the "
				% [longest, CombatDirector.token_max_hold]
				+ "watchdog or the brute will be yanked mid-slam")
	notes.append("turns: %d granted, %d expired unspent, %d leaked; longest %.2f s against a "
			% [granted, approach, leaks, longest] + "%.1f s watchdog"
			% CombatDirector.token_max_hold)
	(_player.get_node("Health") as Health).set_invulnerable(false)


## BLOCK D — the leaks, by name. THE MOST IMPORTANT BLOCK IN THIS PROBE.
##
## A leaked token is not a glitch, it is a fight that stops: the cap stays full, nobody swings, and
## the pack stands on its ring forever. Three paths end a turn WITHOUT the state line that normally
## hands it back, and each is asserted separately because each is a different mechanism.
##
## And then the counter. The director's watchdog would recover every one of these within 0.25 s, so
## a probe that only checked "the token came back" would still pass with every explicit release in
## enemy.gd deleted. FAILING ON A WATCHDOG RECLAIM is the only way a leak is visible from outside.
func _probe_leaks(fails: Array[String], notes: Array[String]) -> void:
	(_player.get_node("Health") as Health).set_invulnerable(true)
	for kind in ["stagger", "fear", "death"]:
		CombatDirector.reset_counters()
		var h := await _await_holder(300)
		if h == null:
			fails.append("no body ever took a turn — cannot test the %s release path" % kind)
			continue
		var who := String(h.name)
		match kind:
			"stagger":
				h.stagger()
			"fear":
				h.fear(2.0)
			"death":
				(h.get_node("Health") as Health).take_damage(999, null)
		# TWO FRAMES, not the watchdog's 0.25 s. The explicit release must be the thing that
		# recovers this, and two frames is far inside token_grace.
		await _settle(2)
		var still := is_instance_valid(h) and CombatDirector.holds_token(h)
		if still:
			fails.append("%s still held its turn 2 frames after %s" % [who, kind])
		else:
			notes.append("leak path '%s': %s handed its turn back within 2 frames" % [kind, who])

	# THE DRAIN. Everyone out of aggro: no ring should hold a turn at all.
	for e in _pack():
		e.global_position = Vector3(0, 0, -26)
		e.set("_cool", 9.0)
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.global_position = Vector3(0, 1.1, 26)
	await _settle(60)
	var snap := CombatDirector.snapshot(_player)
	if not snap.is_empty() and not snap["holders"].is_empty():
		fails.append("%d turn(s) still held after the whole pack de-aggroed" % snap["holders"].size())

	var reclaims: int = int(snap.get("leak_reclaims", 0))
	if reclaims > 0:
		fails.append("the watchdog reclaimed %d turn(s) — a leak it swallowed is still a leak; "
				% reclaims + "some release path in enemy.gd did not run")
	notes.append("drain: %d turn(s) outstanding, %d watchdog reclaims across the leak tests"
			% [snap.get("holders", []).size(), reclaims])
	(_player.get_node("Health") as Health).set_invulnerable(false)


## The four melee bodies, in a stable order. The Archer is excluded on purpose: it is never
## slotted, so including it would measure _chase_ranged's standoff band as if it were the ring.
func _melee() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in _pack():
		if e.name != "Loner" and e.nav_agent() != null \
				and int(e.get("attack_kind")) != Enemy.AttackKind.RANGED:
			out.append(e)
	return out


## The largest empty arc around the player, in degrees. Four bodies spread perfectly leave 90 deg
## gaps; four bodies stacked on one side leave one gap approaching 360. This single number is the
## difference between a pack and a queue, and it is why it is measured rather than admired.
func _max_gap_deg(bodies: Array[Enemy]) -> float:
	var angs: Array[float] = []
	for e in bodies:
		if is_instance_valid(e):
			var to := e.global_position - _player.global_position
			angs.append(atan2(to.z, to.x))
	if angs.size() < 2:
		return 360.0
	angs.sort()
	var worst := 0.0
	for i in angs.size():
		var a: float = angs[i]
		var b: float = angs[(i + 1) % angs.size()]
		var gap: float = b - a if i + 1 < angs.size() else (b + TAU) - a
		worst = maxf(worst, gap)
	return rad_to_deg(worst)


## Put the pack back where it started, all on the player's far side. THE SAME SETUP BOTH TIMES, and
## deliberately the worst case: everyone approaching from one bearing is exactly the arrangement
## that produces a conga line when nothing is arbitrating.
##
## OPEN GROUND, DELIBERATELY. The first version of this fought at the arena origin, which is 1.0 m
## from RockGate -- i.e. INSIDE the 1.68 m hole that boulder carves in the navmesh. A body sent to
## a ring position around a target standing in a hole cannot path to it, and one swordsman spent
## 100% of the sample jammed 0.83 m from the player. That measured the test's own geometry, not the
## ring. Encirclement is a claim about open ground; obstacles are block H's business.
const ARENA_OPEN := Vector3(0, 1.1, -14)

func _reset_pack() -> void:
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.global_position = ARENA_OPEN
	var z := ARENA_OPEN.z
	var spots := {"Swordsman1": Vector3(0, 0, z - 7), "Swordsman2": Vector3(-3, 0, z - 7),
			"Swordsman3": Vector3(3, 0, z - 7), "Brute": Vector3(-6, 0, z - 6),
			"Archer": Vector3(6, 0, z - 9)}
	for e in _pack():
		if spots.has(String(e.name)):
			e.global_position = spots[String(e.name)]
			e.velocity = Vector3.ZERO
			var a := e.nav_agent()
			if a != null:
				# Documented: an agent that was TELEPORTED must have its avoidance state reset, or
				# RVO keeps predicting it from the velocity it had at the old position.
				a.set_velocity_forced(Vector3.ZERO)
	await _settle(2)


## Run the same fight for `frames` and report the steady-state spread. The average over the last
## two seconds rather than a single frame: bodies orbit, and one snapshot of an orbit is a number
## you can get to say anything.
func _sample_gap(frames: int) -> Dictionary:
	var bodies := _melee()
	var gap_sum := 0.0
	var gap_n := 0
	var closest := {}
	var inside := {}
	for e in bodies:
		closest[e.name] = 99.0
		inside[e.name] = 0
	# A BYSTANDER IS NOT THE SAME THING AS "NOT CURRENTLY HOLDING A TURN". A body that has just
	# finished its swing is standing at contact range by definition and spends the next moment
	# walking back out to its ring; counting those frames as crowding measures the transit, not the
	# behaviour, and no correct implementation could pass.
	#
	# THE WINDOW IS DERIVED PER BODY, NOT PICKED. A flat half-second is right for a 3.4 m/s
	# swordsman crossing its 0.84 m gap and wrong for a 2.2 m/s brute crossing 1.58 m, which takes
	# 0.72 s -- and a flat window charged the brute for the second half of every walk-out and
	# reported 25% crowding for a body doing exactly what it was told. The window is the time this
	# body needs to cover its own ring-minus-reach at its own speed, times 1.5 for turning and
	# acceleration.
	var recovery := {}
	for e in bodies:
		var gap: float = maxf(CombatDirector.ring_min_radius,
				e.reach() * CombatDirector.ring_margin) - e.reach()
		var speed: float = maxf(float(e.get("move_speed")), 0.5)
		recovery[e.name] = int(ceil(gap / speed * 60.0 * 1.5))
	var since_turn := {}
	for e in bodies:
		since_turn[e.name] = 0
	var counted := {}
	var slotted := {}
	var off_slot := {}
	var desync := {}
	var why := {}
	for e in bodies:
		counted[e.name] = 0
		slotted[e.name] = 0
		off_slot[e.name] = 0.0
		desync[e.name] = 0
	for i in frames:
		await get_tree().physics_frame
		for e in bodies:
			if not is_instance_valid(e):
				continue
			if bool(e.get("_has_token")) != CombatDirector.holds_token(e):
				desync[e.name] = int(desync[e.name]) + 1
			if CombatDirector.holds_token(e):
				since_turn[e.name] = 0
				continue
			since_turn[e.name] = int(since_turn[e.name]) + 1
			if int(since_turn[e.name]) < int(recovery[e.name]):
				continue
			# Bodies get shoved (layer 1) and the player can walk into them, so this is a
			# measurement of crowding, not a geometric law.
			var d := Vector2(e.global_position.x - _player.global_position.x,
					e.global_position.z - _player.global_position.z).length()
			closest[e.name] = minf(closest[e.name], d)
			counted[e.name] = int(counted[e.name]) + 1
			if d < e.reach():
				inside[e.name] = int(inside[e.name]) + 1
				var k: String = "%s/%s/%s" % [e.name,
						["IDLE","CHASE","ATTACK","FLINCH","STAGGER","DEAD","FEAR"][int(e.get("_state"))],
						"toPlayer" if bool(e.get("_goal_is_player")) else "toSlot"]
				why[k] = int(why.get(k, 0)) + 1
			# DIAGNOSTIC: was this body actually GIVEN a slot this frame, and did it get there?
			# "inside its reach" has two very different causes -- never assigned a slot (so it
			# walked at the player) versus assigned one and unable to hold it (shoved, or steered
			# off it) -- and they are different bugs.
			if not bool(e.get("_goal_is_player")):
				slotted[e.name] = int(slotted[e.name]) + 1
			var sl: Vector3 = CombatDirector.assigned_slot(e)
			if sl != Vector3.INF:
				off_slot[e.name] = maxf(off_slot[e.name], Vector2(e.global_position.x - sl.x,
						e.global_position.z - sl.z).length())
		if i >= frames - 120:
			gap_sum += _max_gap_deg(bodies)
			gap_n += 1
	return {"gap": gap_sum / maxf(float(gap_n), 1.0), "closest": closest, "inside": inside,
			"frames": counted, "slotted": slotted, "off_slot": off_slot, "desync": desync,
			"recovery": recovery, "why": why}


## BLOCKS E and F — the headline, and it comes with its own control.
##
## "The pack encircles" is not a claim anyone can check without the same fight measured both ways,
## so the director has an `enabled` switch that exists for exactly this: run the identical setup
## with arbitration off, then on, and print both numbers.
func _probe_encirclement(fails: Array[String], notes: Array[String]) -> void:
	(_player.get_node("Health") as Health).set_invulnerable(true)

	CombatDirector.enabled = false
	await _reset_pack()
	await _settle(60)
	var off: Dictionary = await _sample_gap(360)

	CombatDirector.enabled = true
	await _reset_pack()
	await _settle(60)
	var on: Dictionary = await _sample_gap(360)

	# F. Four bodies perfectly spread leave 90 deg gaps. 200 is generous -- it is roughly "three of
	# the four are on the same side" -- and a conga line reads well above 300.
	if on["gap"] >= 200.0:
		fails.append("the pack still leaves a %.0f deg hole with the director ON (%.0f deg off) — "
				% [on["gap"], off["gap"]] + "it is queueing, not encircling")
	# ...and the control has to be WORSE, or the ring is not what produced the spread.
	if on["gap"] >= off["gap"]:
		fails.append("arbitration made the spread no better: %.0f deg on vs %.0f deg off"
				% [on["gap"], off["gap"]])
	notes.append("ENCIRCLEMENT: max gap %.0f deg director OFF, %.0f deg director ON"
			% [off["gap"], on["gap"]])

	# E. A body waiting its turn must not stand in the strike band -- not for damage (nothing in
	# this fight has friendly fire) but because a bystander in the lane is a body the player cannot
	# read past, and it is what makes a crowd feel like one object.
	for e in _melee():
		var nm := String(e.name)
		var near: float = on["closest"].get(nm, 99.0)
		var seen := float(on["frames"].get(nm, 0))
		if seen < 30.0:
			# Never observed as a settled bystander at all -- it fought continuously. Nothing to
			# assert, and asserting on three frames would be noise.
			notes.append("%s was never a settled bystander in this sample" % nm)
			continue
		var frac := float(on["inside"].get(nm, 0)) / seen
		if near < e.reach() * 0.8:
			fails.append("%s came within %.2f m while holding no turn (its reach is %.2f m)"
					% [nm, near, e.reach()])
		if frac > 0.05:
			fails.append("%s spent %.0f%% of its waiting frames inside its own reach"
					% [nm, frac * 100.0])
	var report := PackedStringArray()
	for e in _melee():
		report.append("%s %.2f m (%d frames, slot %.2f m)" % [e.name,
				on["closest"].get(String(e.name), 99.0), int(on["frames"].get(String(e.name), 0)),
				maxf(CombatDirector.ring_min_radius, e.reach() * CombatDirector.ring_margin)])
	notes.append("bystander distance, closest approach while settled: " + ", ".join(report))
	var diag := PackedStringArray()
	for e in _melee():
		var nm2 := String(e.name)
		var seen2 := maxf(float(on["frames"].get(nm2, 0)), 1.0)
		diag.append("%s slotted %.0f%% worst-off-slot %.2f m" % [nm2,
				100.0 * float(on["slotted"].get(nm2, 0)) / seen2, on["off_slot"].get(nm2, 0.0)])
	notes.append("slot adherence: " + ", ".join(diag))
	var ds := PackedStringArray()
	for e in _melee():
		ds.append("%s %d" % [e.name, int(on["desync"].get(String(e.name), 0))])
	notes.append("token cache desync frames (of 360): " + ", ".join(ds))
	var rec := PackedStringArray()
	for e in _melee():
		rec.append("%s %d f" % [e.name, int(on["recovery"].get(String(e.name), 0))])
	notes.append("post-turn walk-out excluded from the bystander sample: " + ", ".join(rec))
	notes.append("inside-reach frames by state/goal: " + str(on["why"]))

	(_player.get_node("Health") as Health).set_invulnerable(false)


## BLOCK J — lock cycling, which a duel never needed and a pack cannot do without.
##
## camera_rig.gd's toggle_lock() only ever takes the NEAREST enemy and had no way to change its
## mind; with five bodies orbiting at the same radius that is close to unusable, and the F5 panel
## follows the lock, so it is also how you choose what to debug.
func _probe_lock(fails: Array[String], notes: Array[String]) -> void:
	var rig := get_node_or_null("CameraRig")
	if rig == null or not rig.has_method("cycle_lock"):
		fails.append("CameraRig has no cycle_lock() — lock cycling is not wired")
		return
	# Back within lock range of the survivors: the leak block left the pack 52 m away.
	# LOCKABLE, NOT MERELY PRESENT -- and the difference is a corpse. The leak block above kills a
	# body, and Enemy keeps it around for a couple of seconds to play its death; is_instance_valid()
	# still says yes, while the rig correctly refuses to lock it. Counting it made this expect a lap
	# of five when only four were offerable, and the lap "revisited" a body it had never left.
	# EVERY LOCKABLE BODY, INCLUDING Loner. The lock knows nothing about navigation agents or the
	# director -- it takes anything in group "enemy" that is alive and in range -- so the expected
	# lap must be built the same way. Leaving the control body out made the lap end on it.
	var alive: Array[Enemy] = []
	for e in _pack():
		if not is_instance_valid(e):
			continue
		if int(e.get("_state")) == Enemy.S.DEAD:
			continue
		var h := e.get_node_or_null("Health") as Health
		if h != null and h.hp <= 0:
			continue
		alive.append(e)
	if alive.size() < 2:
		fails.append("fewer than two bodies survived — cannot test cycling")
		return
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.global_position = ARENA_OPEN
	for i in alive.size():
		var a := TAU * float(i) / float(alive.size())
		alive[i].global_position = ARENA_OPEN + Vector3(cos(a) * 5.0, -1.1, sin(a) * 5.0)
	await _settle(4)

	rig.call("toggle_lock")
	var first: Node = rig.call("locked")
	if first == null:
		fails.append("toggle_lock() acquired nothing with %d bodies in range" % alive.size())
		return
	# A FULL LAP VISITS EVERYONE EXACTLY ONCE and comes home. Ordering by bearing is what makes
	# that true; a nearest-first cycler can revisit and can strand a body it never offers.
	var seen: Array = [first]
	for i in alive.size() - 1:
		rig.call("cycle_lock", 1)
		var nxt: Node = rig.call("locked")
		if nxt == null:
			fails.append("cycle_lock() dropped the lock after %d step(s)" % (i + 1))
			return
		if seen.has(nxt):
			fails.append("cycle_lock() revisited %s after %d step(s) — a lap must visit each body "
					% [nxt.name, i + 1] + "exactly once")
			break
		seen.append(nxt)
	rig.call("cycle_lock", 1)
	var home: Node = rig.call("locked")
	if home != first:
		fails.append("a full lap of %d ended on %s, not back on %s"
				% [alive.size(), home.name if home != null else "nothing", first.name])
	notes.append("lock: a lap of %d visited %d distinct bodies and returned to the first"
			% [alive.size(), seen.size()])

	# ...and it must never offer a corpse. The lock releasing itself on a death is already proven
	# by the robot bench; this is the other half — that the CYCLER agrees with the acquirer about
	# what is lockable, which is why both read one _lock_candidates().
	var victim: Enemy = alive[alive.size() - 1]
	var vname := String(victim.name)
	(victim.get_node("Health") as Health).take_damage(999, null)
	await _settle(6)
	for i in alive.size() + 1:
		rig.call("cycle_lock", 1)
		var t: Node = rig.call("locked")
		if t != null and String(t.name) == vname:
			fails.append("cycle_lock() offered %s after it died" % vname)
			break
	notes.append("lock: a lap after killing %s never offered it again" % vname)
	# Hand the lock back. A probe that leaves state behind is a probe whose next block, or whose
	# shutdown, is testing something it did not set up.
	if rig.call("locked") != null:
		rig.call("toggle_lock")

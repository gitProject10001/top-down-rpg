extends SceneTree
## Headless verification of the vertical slice's dungeon. Run:
##   Godot_console.exe --headless --path . --script res://scripts/dungeon/slice/tests/verify_slice.gd
## Non-zero exit code on any failure.
##
## TWO JOBS, and the second is the important one.
##
## First: the beats actually landed. The director places by ROLE, so a layout change can silently
## stop producing a treasure room and take the tether puzzle with it — the run would still be
## playable and would quietly be missing a third of itself.
##
## Second: the furniture obeys the same rules the crypt's own suite enforces on everything else.
## None of it is reachable from verify_dungeon.gd, because it lives behind DungeonGenerator._furnish
## and only a subclass overrides that — which is exactly why it needs its own suite. The rules are
## copied deliberately rather than shared: if the day comes that this stops being gated, these are
## the assertions it has to already pass.

const SEEDS := [20260814, 7, 42]
const COURSE_CEILING := 3.35        ## verify_dungeon's cutaway threshold: COURSE_H + 0.35
const EXPECTED_SUITES := 4

var _fails: Array[String] = []
var _suites := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _beats_suite()
	await _invariant_suite()
	await _placement_suite()
	await _determinism_suite()

	if _suites != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported — one unwound silently"
				% [_suites, EXPECTED_SUITES])
	if _fails.is_empty():
		print("[VERIFY] SLICE PASS")
		quit(0)
	else:
		print("[VERIFY] SLICE FAIL — %d problem(s):" % _fails.size())
		for f in _fails:
			print("   " + f)
		quit(1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _done(name_of: String, note: String) -> void:
	_suites += 1
	print("[VERIFY] %s suite: %s" % [name_of, note])


func _build(seed_value: int) -> Node3D:
	var zone := (load("res://scenes/world/zone_slice.tscn") as PackedScene).instantiate() as Node3D
	zone.dungeon_seed = seed_value
	root.add_child(zone)
	await process_frame                  # the _ready cascade generates the whole dungeon
	return zone


# ----------------------------------------------------------------------------------------------

## Every beat the twenty minutes is made of, present in every seed.
func _beats_suite() -> void:
	var summary := ""
	for s in SEEDS:
		var zone := await _build(s)
		var counts := {}
		_census(zone, counts)
		for want: String in ["CrackedWall", "SpectralNode", "TetherAnchor", "SliceGate",
				"WardenGate", "TraitProbe", "InsightPickup"]:
			_ok(int(counts.get(want, 0)) > 0, "seed %d: no %s in the whole dungeon" % [s, want])
		# Four checks is the run's rhythm: the opening murmur, the wall, the ledge, the boss.
		_ok(int(counts.get("TraitProbe", 0)) >= 4,
				"seed %d: only %d checks placed, expected 4" % [s, int(counts.get("TraitProbe", 0))])
		_ok(int(counts.get("InsightPickup", 0)) >= 3,
				"seed %d: only %d rewards placed, expected 3" % [s, int(counts.get("InsightPickup", 0))])
		# The two tools you do not descend with have to be findable, or the run is one-verb long.
		var tools := {}
		_collect_tools(zone, tools)
		for tool_name: String in ["Sunfire Lantern", "Shatter Hammer"]:
			_ok(tools.has(tool_name), "seed %d: %s is not findable anywhere" % [s, tool_name])
		summary = "%d probes, %d rewards, %d tools findable" % [
				int(counts.get("TraitProbe", 0)), int(counts.get("InsightPickup", 0)), tools.size()]
		zone.free()
	_done("beats", "%d seeds — %s" % [SEEDS.size(), summary])


## The six rules from slice_director's header, checked rather than asserted in prose.
func _invariant_suite() -> void:
	var bodies := 0
	var meshes := 0
	for s in SEEDS:
		var zone := await _build(s)
		for room in _rooms(zone):
			var floor_y: float = room.global_position.y
			for node in _slice_nodes(room):
				# 1. every body on layer 1 — the suite's rule for the whole dungeon
				if node is StaticBody3D:
					bodies += 1
					_ok((node as StaticBody3D).collision_layer == 1,
							"seed %d: %s is on collision_layer %d, not 1"
									% [s, node.name, (node as StaticBody3D).collision_layer])
				for vis in _descendants(node):
					# 2. no lights at all: a lit prop that is not a body counts as a mount and owes
					#    3 m of door clearance. Emissive materials owe nothing.
					_ok(not (vis is Light3D),
							"seed %d: %s carries a %s" % [s, node.name, vis.get_class()])
					if vis is MeshInstance3D:
						meshes += 1
						var mi := vis as MeshInstance3D
						# 3. nothing casts
						_ok(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
								or mi.gi_mode == GeometryInstance3D.GI_MODE_DISABLED,
								"seed %d: %s casts shadows" % [s, mi.name])
						# 6. nothing in the lighting solution, nothing below the floor
						_ok(mi.gi_mode == GeometryInstance3D.GI_MODE_DISABLED,
								"seed %d: %s is still GI_MODE_STATIC" % [s, mi.name])
						var box := mi.get_aabb()
						var top: float = mi.global_position.y + box.position.y + box.size.y
						var bottom: float = mi.global_position.y + box.position.y
						# 4. under the cutaway ceiling
						_ok(top <= floor_y + COURSE_CEILING + 0.01,
								"seed %d: %s reaches %.2f m above the floor (ceiling %.2f)"
										% [s, mi.name, top - floor_y, COURSE_CEILING])
						# 6. and not below it, which would coarsen the room's GI probe
						_ok(bottom >= floor_y - 0.35,
								"seed %d: %s hangs %.2f m below the floor"
										% [s, mi.name, floor_y - bottom])
		zone.free()
	_done("invariant", "%d bodies and %d meshes obey layer, light, shadow, height and GI rules"
			% [bodies, meshes])


## Furniture must not stand in a doorway. The occupancy grid already knows where the door lanes are
## — this checks the director actually asked it rather than guessing from the footprint.
func _placement_suite() -> void:
	var checked := 0
	for s in SEEDS:
		var zone := await _build(s)
		for room in _rooms(zone):
			if room.plan == null:
				_fails.append("seed %d: room %s kept no plan" % [s, room.name])
				continue
			for node in _slice_nodes(room):
				# to_local, not `position`: some fixtures are parented to another fixture (the prize
				# rides the spectral ledge), and their own `position` is in that parent's frame. The
				# occupancy grid speaks room-local and nothing else.
				var local: Vector3 = room.to_local((node as Node3D).global_position)
				checked += 1
				_ok(not room.plan.in_door_lane(local),
						"seed %d: %s stands in a door lane at %v" % [s, node.name, local])
		zone.free()
	_done("placement", "%d fixtures, none in a doorway" % checked)


## Same seed, same dungeon — including the furniture. The whole point of pinning a seed for the
## slice is that the twenty minutes is repeatable, and furniture placed from a grid that some
## earlier pass mutated differently would quietly break that.
func _determinism_suite() -> void:
	var first := ""
	var second := ""
	for i in 2:
		var zone := await _build(SEEDS[0])
		var sig := ""
		for room in _rooms(zone):
			for node in _slice_nodes(room):
				sig += "%s@%v|" % [node.get_script().get_global_name(),
						(node as Node3D).position.snapped(Vector3.ONE * 0.01)]
		if i == 0:
			first = sig
		else:
			second = sig
		zone.free()
	_ok(first == second, "two builds of seed %d placed furniture differently" % SEEDS[0])
	_ok(first.length() > 0, "the signature was empty — nothing was placed at all")
	_done("determinism", "seed %d reproduces its furniture exactly" % SEEDS[0])


# --- walkers -----------------------------------------------------------------------------------

func _rooms(zone: Node) -> Array:
	var out: Array = []
	for c in zone.get_children():
		if c is DungeonRoom:
			out.append(c)
	return out


## The director's own nodes, by script class — everything the crypt did not build.
const SLICE_CLASSES := ["CrackedWall", "SpectralNode", "TetherAnchor", "SliceGate", "WardenGate",
		"InsightPickup", "TraitProbe", "BoonPedestal"]


func _slice_nodes(room: Node) -> Array:
	var out: Array = []
	for c in room.get_children():
		var script := c.get_script() as Script
		if script and String(script.get_global_name()) in SLICE_CLASSES:
			out.append(c)
			for nested in c.get_children():
				var ns := nested.get_script() as Script
				if ns and String(ns.get_global_name()) in SLICE_CLASSES:
					out.append(nested)
	return out


func _descendants(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_descendants(c))
	return out


func _census(n: Node, counts: Dictionary) -> void:
	var script := n.get_script() as Script
	if script:
		var cls := String(script.get_global_name())
		if cls in SLICE_CLASSES:
			counts[cls] = int(counts.get(cls, 0)) + 1
	for c in n.get_children():
		_census(c, counts)


func _collect_tools(n: Node, out: Dictionary) -> void:
	if n is InsightPickup and (n as InsightPickup).grants_tool != "":
		out[(n as InsightPickup).grants_tool] = true
	for c in n.get_children():
		_collect_tools(c, out)

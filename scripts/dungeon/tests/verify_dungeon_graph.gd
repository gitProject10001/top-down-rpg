extends SceneTree
## Headless verification for DungeonGraph-seeded generation. Run:
##   Godot_console.exe --headless --path . --script res://scripts/dungeon/tests/verify_dungeon_graph.gd
## Results also written to user://verify_dungeon_graph.txt. Non-zero exit code on any failure.
##
## A SEPARATE script rather than a 20th suite in verify_dungeon.gd: that file's EXPECTED_SUITES
## is its own crash detector and its pinned hashes describe the null path. This file owns the
## OTHER promise — that passing a graph seeds it faithfully, and that passing null (or nothing)
## is bit-identical to the layout that has always shipped.

const EXPECTED_SUITES := 10
const SEEDS := [7, 42, 137]

var _fails: Array[String] = []
var _log := ""
var _suites_done := 0


func _initialize() -> void:
	_null_regression_suite()
	_determinism_suite()
	_constraint_suite()
	_stair_suite()
	_hostile_suite()
	_roundtrip_suite()
	_shape_roundtrip_suite()
	_authored_shape_suite()
	_hostile_shape_suite()
	_door_into_void_suite()

	if _suites_done != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported done — one crashed silently"
				% [_suites_done, EXPECTED_SUITES])
	var f := FileAccess.open("user://verify_dungeon_graph.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log)
	if _fails.is_empty():
		_say("[VERIFY] DUNGEON GRAPH PASS")
		quit(0)
	else:
		for line in _fails:
			_say("[VERIFY] FAIL: " + line)
		quit(1)


## THE EXECUTABLE GUARANTEE: a null graph is not a slightly different code path, it is the same
## layout to the bit. Fifty seeds, every room and every edge folded.
func _null_regression_suite() -> void:
	for s in range(1, 51):
		var plain := DungeonLayout.generate(s, 9)
		var nulled := DungeonLayout.generate(s, 9, 1, 2, null)
		if _fold(plain) != _fold(nulled):
			_fails.append("seed %d: null graph moved the layout" % s)
	_done("null regression suite: 50 seeds, null graph is bit-identical")


func _determinism_suite() -> void:
	var g := _fixture()
	for s in SEEDS:
		var a := DungeonLayout.generate(s, 9, 1, 2, g)
		var b := DungeonLayout.generate(s, 9, 1, 2, g)
		if _fold(a) != _fold(b):
			_fails.append("seed %d: graph generation is not deterministic" % s)
	_done("determinism suite: %d seeds reproduce their seeded layout exactly" % SEEDS.size())


## The fixture graph's every insistence, found standing in the result.
func _constraint_suite() -> void:
	var g := _fixture()
	_check(g.check().is_empty(), "fixture graph fails its own check(): %s" % str(g.check()))
	for s in SEEDS:
		var lay := DungeonLayout.generate(s, 9, 1, 2, g)
		_check(lay.graph_unmet.is_empty(),
				"seed %d: graph_unmet %s" % [s, str(lay.graph_unmet)])
		var authored := 0
		var bosses := 0
		var treasures := 0
		var keys := 0
		var locked_pairs := 0
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			if rd.authored:
				authored += 1
			if rd.type == DungeonLayout.RoomType.BOSS:
				bosses += 1
			if rd.type == DungeonLayout.RoomType.TREASURE:
				treasures += 1
			if rd.holds_key != "":
				keys += 1
			for e: DungeonLayout.Edge in rd.edges:
				if e.type == DungeonLayout.EdgeType.LOCKED:
					_check(e.key_id == "key_0", "seed %d: lock carries key '%s'" % [s, e.key_id])
					locked_pairs += 1
		_check(authored == 4, "seed %d: %d authored rooms, drew 4" % [s, authored])
		_check(bosses == 1, "seed %d: %d bosses — the authored one must be the only one"
				% [s, bosses])
		_check(treasures == 1, "seed %d: %d treasuries" % [s, treasures])
		_check(keys == 1, "seed %d: %d key rooms" % [s, keys])
		# One lock, the authored one (stored on both rooms = 2), and _add_lock added no second.
		_check(locked_pairs == 2, "seed %d: %d locked edge halves, drew one lock" % [s,
				locked_pairs])
		_check(lay.rooms.size() >= 6, "seed %d: walk failed to fill around the graph (%d rooms)"
				% [s, lay.rooms.size()])
		_check(_connected(lay), "seed %d: seeded layout is not connected" % s)
		# The vault the author drew: still a vault, still holding the key.
		var vaults := 0
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			if rd.authored and rd.kind == "vault":
				vaults += 1
				_check(rd.holds_key == "key_0", "seed %d: authored vault lost its key" % s)
		_check(vaults == 1, "seed %d: authored vault missing" % s)
	_done("constraint suite: %d seeds honour rooms, types, lock and key" % SEEDS.size())


## An authored STAIR edge sends the dungeon upstairs the way _add_stairs does: the lower room
## becomes the stairwell, the upper room stands one floor up, and no auto-stair doubles it.
func _stair_suite() -> void:
	var g := DungeonGraph.new()
	g.rooms = [
		{"id": 0},
		{"id": 1, "label": "flight"},
		{"id": 2, "label": "upstairs"},
	]
	g.edges = [
		{"a": 0, "b": 1},
		{"a": 1, "b": 2, "type": DungeonLayout.EdgeType.STAIR},
	]
	for s in SEEDS:
		var lay := DungeonLayout.generate(s, 8, 1, 2, g)
		_check(lay.graph_unmet.is_empty(), "seed %d: stair graph unmet %s"
				% [s, str(lay.graph_unmet)])
		var floors := {}
		var stair_rooms := 0
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			floors[rd.cell.y] = true
			if rd.type == DungeonLayout.RoomType.STAIR:
				stair_rooms += 1
		_check(floors.size() >= 2, "seed %d: authored stair never left the ground floor" % s)
		# stair_count is 1 and the author drew it, so the auto pass must have added none.
		_check(stair_rooms == 1, "seed %d: %d stairwells for a budget of 1" % [s, stair_rooms])
	_done("stair suite: %d seeds climb where the author drew" % SEEDS.size())


## Hostile graphs DEGRADE — graph_unmet fills, check() names the defect, nothing crashes.
func _hostile_suite() -> void:
	# Two rooms pinned onto the same cell: the second must be refused, not stacked.
	var overlap := DungeonGraph.new()
	overlap.rooms = [
		{"id": 0},
		{"id": 1, "has_cell": true, "cell": Vector3i(1, 0, 0)},
		{"id": 2, "has_cell": true, "cell": Vector3i(1, 0, 0)},
	]
	overlap.edges = [{"a": 0, "b": 1}, {"a": 0, "b": 2}]
	var lay := DungeonLayout.generate(42, 9, 1, 2, overlap)
	_check(not lay.graph_unmet.is_empty(), "overlapping pins reported nothing unmet")

	# A pinned cell nowhere near its parent: refused for non-adjacency.
	var apart := DungeonGraph.new()
	apart.rooms = [{"id": 0}, {"id": 1, "has_cell": true, "cell": Vector3i(5, 0, 5)}]
	apart.edges = [{"a": 0, "b": 1}]
	lay = DungeonLayout.generate(42, 9, 1, 2, apart)
	_check(not lay.graph_unmet.is_empty(), "a detached pin reported nothing unmet")

	# check() catches what the seeder never sees: duplicate ids, ghost endpoints, no start,
	# disconnection.
	var bad := DungeonGraph.new()
	bad.rooms = [{"id": 1}, {"id": 1}, {"id": 2}]
	bad.edges = [{"a": 1, "b": 9}, {"a": 2, "b": 2}]
	var msgs := bad.check()
	_check(msgs.size() >= 3, "check() found %d defects in a graph carrying at least 3"
			% msgs.size())

	# An empty graph seeds nothing and breaks nothing.
	lay = DungeonLayout.generate(42, 9, 1, 2, DungeonGraph.new())
	_check(lay.rooms.size() >= 6, "an empty graph stunted the dungeon")
	_done("hostile suite: overlaps, ghosts and empties degrade without crashing")


## A DOOR INTO THE VOID: the author carves the half of the room a doorway lands in. The
## restore must dig the approach strip, not leave an island — the built shape ROUND-TRIPS
## (from_dict checks connectivity), so sculpting continues, and the deck keeps walls at every
## raised boundary. The floating-slab-then-resists-editing report, replayed forever.
func _door_into_void_suite() -> void:
	var half := RoomShape.full(11, 3)
	for i in range(7, 11):
		for j in 3:
			half.carve(Vector2i(i, j))
	half.fill(Vector2i(4, 1), 1)
	half.fill(Vector2i(5, 1), 1)
	var g := DungeonGraph.new()
	g.rooms = [{"id": 0},
			{"id": 1, "kind": "cell", "size": Vector3i(2, 1, 1), "has_cell": true,
					"cell": Vector3i(1, 0, 0), "shape": half.to_dict()},
			{"id": 2, "has_cell": true, "cell": Vector3i(3, 0, 0)}]
	g.edges = [{"a": 0, "b": 1}, {"a": 1, "b": 2}]   # the 1-2 door crosses the carved field
	for s in SEEDS:
		var lay := DungeonLayout.generate(s, 6, 0, 0, g)
		var found := false
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			if rd.graph_id != 1:
				continue
			found = true
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			_check(RoomShape.from_dict(ctx.shape.to_dict()) != null,
					"seed %d: a door into a carved field left a shape that cannot round-trip"
					% s)
			var raised := 0
			var risers := 0
			for t: Vector2i in ctx.shape.tiles():
				if ctx.shape.level_of(t) > 0:
					raised += 1
			for w: Dictionary in ctx.shape.walls():
				if String(w.role) == "riser":
					risers += 1
			_check(raised == 2, "seed %d: the deck lost tiles (%d of 2)" % [s, raised])
			_check(risers >= 4, "seed %d: only %d risers under a free-standing deck" % [s,
					risers])
		_check(found, "seed %d: the carved room was not placed" % s)
	_done("door-into-void suite: the restore digs an approach, the deck keeps its walls")


## A graph SURVIVES THE DISK: saved as .tres, loaded back, and the load generates the identical
## layout — the promise the Forge canvas's Save/Load buttons stand on.
func _roundtrip_suite() -> void:
	var g := _fixture()
	g.rooms[1]["at"] = Vector2(123.5, 67.25)          # canvas position must round-trip too
	var path := "user://verify_forge_graph_roundtrip.tres"
	var err := ResourceSaver.save(g, path)
	_check(err == OK, "save failed: %s" % error_string(err))
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as DungeonGraph
	_check(back != null, "loaded resource is not a DungeonGraph")
	if back != null:
		_check(back.rooms.size() == g.rooms.size() and back.edges.size() == g.edges.size(),
				"round trip changed the graph's size")
		_check(back.rooms[1].get("at") == Vector2(123.5, 67.25),
				"canvas position lost in the round trip")
		_check(_fold(DungeonLayout.generate(42, 9, 1, 2, back))
				== _fold(DungeonLayout.generate(42, 9, 1, 2, g)),
				"the loaded graph generates a different layout")
	_done("roundtrip suite: a saved graph loads back and generates identically")


## The fixture: a hand-drawn spine — start, a hub, an authored boss behind an authored lock,
## and an authored vault holding the key.
func _fixture() -> DungeonGraph:
	var g := DungeonGraph.new()
	g.rooms = [
		{"id": 0, "label": "start"},
		{"id": 1, "label": "hub"},
		{"id": 2, "label": "the vault", "kind": "vault",
				"type": DungeonLayout.RoomType.TREASURE, "holds_key": "key_0"},
		{"id": 3, "label": "the boss", "type": DungeonLayout.RoomType.BOSS},
	]
	g.edges = [
		{"a": 0, "b": 1},
		{"a": 1, "b": 2},
		{"a": 1, "b": 3, "type": DungeonLayout.EdgeType.LOCKED, "key_id": "key_0"},
	]
	return g


## EVERY GENERATED SHAPE SURVIVES to_dict → from_dict, order included. The dict replays through
## the guarded constructors, so equality of the tiles() SEQUENCE (not the set) plus the walls()
## emission is what proves _column order — the load-bearing order — reconstructs exactly. Rooms
## whose shape holds a wall_run compare everything except walls(): runs are deliberately not
## serialized (re-derived per generation), and their absence changes wall roles.
func _shape_roundtrip_suite() -> void:
	var shapes := 0
	for s in SEEDS:
		var lay := DungeonLayout.generate(s, 9, 1, 2)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			var shape: RoomShape = ctx.shape
			var back := RoomShape.from_dict(shape.to_dict())
			_check(back != null, "seed %d %s: round trip refused a picked shape" % [s, anchor])
			if back == null:
				continue
			shapes += 1
			_check(back.tiles() == shape.tiles(),
					"seed %d %s: tile SEQUENCE changed in the round trip" % [s, anchor])
			var has_run := false
			for w: Dictionary in shape.walls():
				if String(w.role) == "long":
					has_run = true
			for t: Vector2i in shape.tiles():
				_check(back.level_of(t) == shape.level_of(t),
						"seed %d %s: level drifted at %s" % [s, anchor, t])
				_check(back.is_chamfer(t) == shape.is_chamfer(t)
						and back.is_ramp(t) == shape.is_ramp(t)
						and back.ramp_dir(t) == shape.ramp_dir(t),
						"seed %d %s: fixture drifted at %s" % [s, anchor, t])
			if not has_run:
				_check(var_to_str(back.walls()) == var_to_str(shape.walls()),
						"seed %d %s: walls() emission changed in the round trip" % [s, anchor])
	_check(shapes > 0, "the round trip saw no shapes at all")
	_done("shape roundtrip suite: %d shapes survive the dict, order included" % shapes)


## A HAND-CARVED SHAPE, honoured by generation: pinned on a graph room, built by plan_shell,
## doorway lines restored, camera and reachability clean, deterministic — and every OTHER
## room's plan identical with and without the shape key, which is the per-room stream-isolation
## proof (skipping pick's stream draw cannot desync a neighbour).
func _authored_shape_suite() -> void:
	# 5x3 (a 1x1 cell room's grid): one corner carved, the far column raised a level, a ramp up
	# to it, a chamfer on the carved corner's neighbour.
	var authored := RoomShape.full(5, 3)
	authored.carve(Vector2i(0, 0))
	for j in 3:
		authored.fill(Vector2i(4, j), 1)
	var ramp_ok := authored.add_ramp(Vector2i(3, 1), Vector2i(1, 0), 1, 1)
	_check(ramp_ok, "fixture shape refused its own ramp")
	authored.set_chamfer(Vector2i(0, 2), Vector2i(-1, 1))
	_check(authored.is_chamfer(Vector2i(0, 2)), "fixture shape refused its own chamfer")
	var sd := authored.to_dict()

	var g := DungeonGraph.new()
	g.rooms = [{"id": 0}, {"id": 1, "kind": "cell", "shape": sd}]
	g.edges = [{"a": 0, "b": 1}]
	_check(g.check().is_empty(), "authored-shape fixture fails check(): %s" % str(g.check()))
	var bare := DungeonGraph.new()
	bare.rooms = [{"id": 0}, {"id": 1, "kind": "cell"}]
	bare.edges = [{"a": 0, "b": 1}]

	for s in SEEDS:
		var lay := DungeonLayout.generate(s, 9, 1, 2, g)
		var room: DungeonLayout.RoomData = null
		for anchor: Vector3i in lay.rooms:
			if (lay.rooms[anchor] as DungeonLayout.RoomData).graph_id == 1:
				room = lay.rooms[anchor]
		_check(room != null, "seed %d: the authored room was not placed" % s)
		if room == null:
			continue
		var ctx := RoomContext.create(room, lay.seed_used)
		RoomPlan.plan_shell(room, ctx)
		_check(ctx.shape_note == "", "seed %d: shape fell back — %s" % [s, ctx.shape_note])
		# Exactly ONE tile per edge may differ from the dict — the doorway's boundary tile,
		# computed the way _restore_protect computes it. Whole-line tolerance is gone on
		# purpose: whole-line RESTORE was the bug that pressed every centre-row deck flat.
		var probe := RoomShape.for_room(room)
		var protect := {}
		for e: DungeonLayout.Edge in room.edges:
			var door := DungeonLayout.door_local(room, e)
			if e.dir.x != 0:
				protect[Vector2i(probe.cols - 1 if e.dir.x > 0 else 0,
						probe.row_at(door.z))] = true
			elif e.dir.z != 0:
				protect[Vector2i(probe.col_at(door.x),
						probe.rows - 1 if e.dir.z > 0 else 0)] = true
		for c in sd.cells:
			var t := Vector2i((c as Vector3i).x, (c as Vector3i).z)
			if protect.has(t):
				continue
			_check(ctx.shape.is_solid(t) and ctx.shape.level_of(t) == (c as Vector3i).y,
					"seed %d: authored tile %s not honoured" % [s, t])
		if not protect.has(Vector2i(0, 0)):
			_check(not ctx.shape.is_solid(Vector2i(0, 0)),
					"seed %d: the carved corner grew back" % s)
		_check(ctx.shape.is_chamfer(Vector2i(0, 2)), "seed %d: the chamfer vanished" % s)
		_check(ctx.shape.camera_legal(), "seed %d: authored shape breaks the camera rules" % s)
		# THE DECK STANDS AND ITS WALLS EXIST: surviving raised tiles must put riser segments
		# into walls() — a deck without risers is the floating slab this suite now remembers.
		var raised := 0
		for t: Vector2i in ctx.shape.tiles():
			if ctx.shape.level_of(t) > 0:
				raised += 1
		_check(raised >= 2, "seed %d: the authored deck was flattened (%d raised tiles left)"
				% [s, raised])
		var risers := 0
		for w: Dictionary in ctx.shape.walls():
			if String(w.role) == "riser":
				risers += 1
		_check(risers >= 1, "seed %d: a standing deck emitted no riser walls" % s)
		# Determinism: a second plan of the same room is byte-identical.
		var ctx2 := RoomContext.create(room, lay.seed_used)
		RoomPlan.plan_shell(room, ctx2)
		_check(var_to_str(ctx2.shape.walls()) == var_to_str(ctx.shape.walls()),
				"seed %d: authored plan is not deterministic" % s)
		# STREAM ISOLATION: the same graph without the shape key plans every OTHER room
		# identically — the authored room skipping pick() moved nobody else's randomness.
		var lay_bare := DungeonLayout.generate(s, 9, 1, 2, bare)
		_check(lay_bare.rooms.size() == lay.rooms.size(),
				"seed %d: the shape key moved the LAYOUT itself" % s)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			if rd.graph_id == 1 or not lay_bare.rooms.has(anchor):
				continue
			var a := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, a)
			var b := RoomContext.create(lay_bare.rooms[anchor], lay_bare.seed_used)
			RoomPlan.plan_shell(lay_bare.rooms[anchor], b)
			_check(var_to_str(a.shape.walls()) == var_to_str(b.shape.walls()),
					"seed %d: the shape key desynced room %s" % [s, anchor])
	_done("authored shape suite: %d seeds honour the carve, the deck, the ramp, the bevel"
			% SEEDS.size())


## Hostile shapes DEGRADE: named by check(), refused by from_dict, fallen back from by
## plan_shell — never crash, never half-honoured.
func _hostile_shape_suite() -> void:
	# Two islands: silhouette connectivity refused.
	var split := {"cols": 5, "rows": 3, "cells": [Vector3i(0, 0, 0), Vector3i(4, 0, 2)] \
			as Array[Vector3i], "chamfers": [], "ramps": [], "v": 1}
	_check(RoomShape.from_dict(split) == null, "a two-island silhouette was accepted")
	# A pit on the outline: set_level's refusal, re-asked by from_dict.
	var pit_cells: Array[Vector3i] = []
	for i in 5:
		for j in 3:
			pit_cells.append(Vector3i(i, -1 if i == 0 and j == 1 else 0, j))
	var pit := {"cols": 5, "rows": 3, "cells": pit_cells, "chamfers": [], "ramps": [], "v": 1}
	_check(RoomShape.from_dict(pit) == null, "an outline pit was accepted")
	# A ramp past MAX_SLOPE.
	var steep_cells: Array[Vector3i] = []
	for i in 5:
		for j in 3:
			steep_cells.append(Vector3i(i, 0, j))
	var steep := {"cols": 5, "rows": 3, "cells": steep_cells, "chamfers": [],
			"ramps": [{"anchor": Vector2i(2, 1), "dir": Vector2i(1, 0), "tiles": 1, "rise": 9}],
			"v": 1}
	_check(RoomShape.from_dict(steep) == null, "a 9-level one-tile ramp was accepted")
	# check() names each of these on a graph, and a GRID MISMATCH besides.
	var g := DungeonGraph.new()
	g.rooms = [{"id": 0}, {"id": 1, "kind": "cell", "shape": split},
			{"id": 2, "kind": "hall", "shape": _grid_shape(5, 3)}]
	g.edges = [{"a": 0, "b": 1}, {"a": 0, "b": 2}]
	var msgs := g.check()
	_check(msgs.size() >= 2, "check() found %d shape defects in a graph carrying 2" % msgs.size())
	# And generation FALLS BACK rather than obeying or crashing: the mismatched room carves
	# procedurally and says so on the context.
	var lay := DungeonLayout.generate(42, 9, 1, 2, g)
	for anchor: Vector3i in lay.rooms:
		var rd: DungeonLayout.RoomData = lay.rooms[anchor]
		if rd.graph_id != 2:
			continue
		var ctx := RoomContext.create(rd, lay.seed_used)
		RoomPlan.plan_shell(rd, ctx)
		_check(ctx.shape_note != "", "a mismatched shape fell back silently")
		_check(ctx.shape != null and ctx.shape.tile_count() > 0,
				"the fallback built no floor at all")
	_done("hostile shape suite: islands, outline pits, cliffs and mismatches all degrade")


func _grid_shape(c: int, r: int) -> Dictionary:
	var cells: Array[Vector3i] = []
	for i in c:
		for j in r:
			cells.append(Vector3i(i, 0, j))
	return {"cols": c, "rows": r, "cells": cells, "chamfers": [], "ramps": [], "v": 1}


## Every room and every edge, folded to one number — the same idea as verify_dungeon's pinned
## layout hash, derived independently so the two cannot agree by construction.
func _fold(lay: DungeonLayout) -> int:
	var parts: Array = []
	var anchors: Array = lay.rooms.keys()
	anchors.sort()
	for a: Vector3i in anchors:
		var rd: DungeonLayout.RoomData = lay.rooms[a]
		parts.append([rd.cell, rd.size, rd.type, rd.dist, rd.module_id, rd.kind, rd.purpose,
				rd.template_path, rd.holds_key])
		var folded_edges: Array = []
		for e: DungeonLayout.Edge in rd.edges:
			folded_edges.append([e.dir, e.from_cell, e.type, e.key_id])
		parts.append(folded_edges)
	return hash(parts)


func _connected(lay: DungeonLayout) -> bool:
	if not lay.rooms.has(Vector3i.ZERO):
		return false
	var seen := {Vector3i.ZERO: true}
	var queue: Array = [lay.rooms[Vector3i.ZERO]]
	while not queue.is_empty():
		var r: DungeonLayout.RoomData = queue.pop_front()
		for e: DungeonLayout.Edge in r.edges:
			var n := lay.room_at(e.from_cell + e.dir)
			if n != null and not seen.has(n.cell):
				seen[n.cell] = true
				queue.append(n)
	return seen.size() == lay.rooms.size()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _done(msg: String) -> void:
	_suites_done += 1
	_say("[VERIFY] " + msg)


func _say(msg: String) -> void:
	print(msg)
	_log += msg + "\n"

extends SceneTree
## Headless map verification. Run:
##   Godot_console.exe --headless --path . --script res://scripts/map/tests/verify_map.gd
## Results also written to user://verify_map.txt (stdout capture is flaky on Windows).
## Non-zero exit code on any failure.

var _fails: Array[String] = []
var _log := ""

## Same guard verify_dungeon.gd uses: a GDScript runtime error inside an AWAITED suite unwinds it
## silently, so a crashed suite would otherwise be indistinguishable from a passing one.
const EXPECTED_SUITES := 8
var _suites_done := 0


func _initialize() -> void:
	_transform_suite()
	_stamp_suite()
	_polygon_suite()
	_walk_suite()
	_serialise_suite()
	_dungeon_suite()
	_zone_suite()      # async: instantiates room.tscn, then the crypt, and quits at the end


func _finish() -> void:
	_check(_suites_done == EXPECTED_SUITES,
			"only %d/%d suites ran to completion — one crashed" % [_suites_done, EXPECTED_SUITES])
	var verdict := "PASS" if _fails.is_empty() else "FAIL (%d)" % _fails.size()
	_out("[VERIFY] MAP %s" % verdict)
	for f in _fails:
		_out("  FAIL: " + f)
	var fa := FileAccess.open("user://verify_map.txt", FileAccess.WRITE)
	fa.store_string(_log)
	fa.close()
	quit(0 if _fails.is_empty() else 1)


func _out(s: String) -> void:
	print(s)
	_log += s + "\n"
	if s.begins_with("[VERIFY] ") and s.contains("suite"):
		_suites_done += 1


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


# --- 1. WORLD <-> GRID -------------------------------------------------------------------------


func _transform_suite() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260809
	# The last rect is the crypt case: DungeonLayout puts rooms out at multiples of CELL_PITCH from
	# a zone root parked at (500, 0, 500), and the whole design rests on to_local removing that
	# offset before any of this runs. Prove the maths survives the magnitude anyway.
	var rects := [
		Rect2(0, 0, 64, 64),
		Rect2(-48, -38, 224, 142),
		Rect2(-7.5, 3.25, 51.5, 19.75),
		Rect2(460, 460, 180, 140),
	]
	for r: Rect2 in rects:
		for cell in [0.5, 1.0, 2.0]:
			var g := MapGrid.make(r, cell)
			_check(g.rect.encloses(r) or g.rect.size >= r.size,
					"grid rect %s does not cover requested %s" % [g.rect, r])
			for i in 500:
				var p := Vector2(
					rng.randf_range(g.rect.position.x, g.rect.end.x - 0.001),
					rng.randf_range(g.rect.position.y, g.rect.end.y - 0.001))
				var c := g.local_to_cell(p)
				_check(g.in_bounds(c), "cell %s from %v is outside a grid that contains the point" % [c, p])
				var back := g.cell_to_local(c)
				_check(back.distance_to(p) <= cell * 0.7108,
						"round-trip drifted %.4f m at cell %.2f" % [back.distance_to(p), cell])

	# Out of bounds must be REJECTED, not wrapped. This is the buffer-overrun class of bug, and the
	# one whose symptom is a corrupted save file rather than a crash.
	var g2 := MapGrid.make(Rect2(0, 0, 20, 20), 1.0)
	for p in [Vector2(-5, 5), Vector2(5, -5), Vector2(25, 5), Vector2(5, 25), Vector2(-100, -100)]:
		_check(not g2.in_bounds(g2.local_to_cell(p)), "point %v outside the rect reported in bounds" % p)
		_check(g2.value_at(p) == 0, "out-of-bounds read at %v returned non-zero" % p)
	g2.stamp(Vector2(-40, -40), 8.0)              # entirely outside: must be a no-op, not a crash
	var any := false
	for b in g2.bytes:
		if b != 0:
			any = true
	_check(not any, "a stamp entirely outside the rect wrote into the grid")

	_out("[VERIFY] transform suite ok")


# --- 2. STAMPING -------------------------------------------------------------------------------


func _stamp_suite() -> void:
	var g := MapGrid.make(Rect2(-50, -50, 100, 100), 1.0)
	var mid := Vector2(0.5, 0.5)                  # a cell centre, so distance 0 is reachable
	var r := 14.0
	g.stamp(mid, r)

	_check(g.value_at(mid) == 255, "centre of a stamp is %d, not 255" % g.value_at(mid))
	_check(g.value_at(mid + Vector2(r + 3.0, 0)) == 0, "a cell beyond the radius was revealed")
	var half := g.value_at(mid + Vector2(r * 0.8, 0))
	_check(half > 0 and half < 255, "the falloff band is not soft (got %d)" % half)

	# Monotonic with distance: the reveal must fade outward, never band or invert.
	var prev := 256
	for d in range(0, int(r)):
		var v := g.value_at(mid + Vector2(float(d), 0))
		_check(v <= prev, "value rose from %d to %d at %d m out" % [prev, v, d])
		prev = v

	# MAX, not overwrite — walking back through the faint rim of an old stamp must not dim it.
	var before := g.bytes.duplicate()
	g.stamp(mid + Vector2(r * 0.9, 0), r)
	for i in g.bytes.size():
		_check(g.bytes[i] >= before[i], "a second stamp DECREASED cell %d (%d -> %d)"
				% [i, before[i], g.bytes[i]])
	g.stamp(mid, r)
	_check(g.value_at(mid) == 255, "re-stamping the same point changed its value")

	# Round, not square: the area must match a disc, not its bounding box.
	var g3 := MapGrid.make(Rect2(-50, -50, 100, 100), 1.0)
	g3.stamp(mid, r)
	var lit := 0
	for b in g3.bytes:
		if b > 0:
			lit += 1
	var want := PI * r * r
	_check(absf(float(lit) - want) / want < 0.10,
			"stamped %d cells, expected ~%d (a disc, not its bounding box)" % [lit, int(want)])

	_out("[VERIFY] stamp suite ok")


# --- 2b. POLYGON STAMPING ----------------------------------------------------------------------


## The L-shaped case, built by hand so the assertion does not depend on a generated seed: a 20x12
## room with a 8x6 bite out of its top-right corner. What must hold is that the bite stays DARK —
## a stamp that quietly filled the bounding box would leave an L-shaped room drawn inside a
## rectangular hole in the fog, which is the whole defect this replaced.
func _polygon_suite() -> void:
	var g := MapGrid.make(Rect2(-20, -20, 40, 40), 1.0)
	var ell := PackedVector2Array([
		Vector2(-10, -6), Vector2(2, -6), Vector2(2, 0), Vector2(10, 0),
		Vector2(10, 6), Vector2(-10, 6)])
	g.stamp_polygon(ell, 255, 2.5)

	for inside in [Vector2(-8, 4), Vector2(0, -4), Vector2(8, 3), Vector2(1.5, 5.5)]:
		_check(g.value_at(inside) == 255, "point %v inside the L was not fully revealed (%d)"
				% [inside, g.value_at(inside)])
	# The bite, well clear of the feather.
	for outside in [Vector2(8, -5), Vector2(6, -4), Vector2(9.5, -5.5)]:
		_check(g.value_at(outside) == 0, "point %v in the carved-out corner was revealed (%d)"
				% [outside, g.value_at(outside)])
	# ...and well outside the whole shape.
	for far in [Vector2(-18, 0), Vector2(0, 18), Vector2(18, 18)]:
		_check(g.value_at(far) == 0, "point %v far outside the polygon was revealed" % far)

	# Soft edge, same contract as the radial brush.
	var edge := g.value_at(Vector2(-10.9, 0))
	_check(edge > 0 and edge < 255, "the polygon's feathered margin is hard (got %d)" % edge)

	# A ratchet here too: re-stamping at a lower value must not dim what is already known.
	g.stamp_polygon(ell, 120, 2.5)
	_check(g.value_at(Vector2(0, 0)) == 255, "a weaker polygon stamp DECREASED a revealed cell")

	# Degenerate input must be a no-op, not a crash.
	g.stamp_polygon(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), 255, 2.0)
	g.stamp_polygon(PackedVector2Array(), 255, 2.0)

	_out("[VERIFY] polygon stamp suite ok")


# --- 3. THE WALK -------------------------------------------------------------------------------


## THE TEST THAT MATTERS MOST. Everything else here is arithmetic; this is the one that catches the
## likely tuning regression — a MOVE_STEP raised for performance until the revealed trail has holes
## in it, which nobody notices until they open the map after a long run.
func _walk_suite() -> void:
	# Tall enough to contain the dogleg with room to spare. The first version ended at z = 80.0 on a
	# rect whose end WAS 80.0, and reported one unrevealed point — a bounds question the transform
	# suite already owns, dressed up as a continuity failure. A test must fail for its own reason.
	var g := MapGrid.make(Rect2(-40, -40, 300, 170), 1.0)
	var step: float = 1.5                          # MapData.MOVE_STEP
	var reveal: float = 14.0                       # MapData.REVEAL_R
	var speed := 6.0                               # player.gd:11
	var dt := 1.0 / 60.0

	var at := Vector2(-30, 0)
	var last := Vector2.INF
	var path: Array[Vector2] = []
	for i in 2400:                                 # 40 s of walking, ~240 m
		# A dogleg, so the test covers a direction change and not just a straight line.
		var dir := Vector2.RIGHT if i < 1400 else Vector2(0.6, 0.8).normalized()
		at += dir * speed * dt
		path.append(at)
		if not last.is_finite() or at.distance_squared_to(last) >= step * step:
			g.stamp(at, reveal)
			last = at

	var holes := 0
	for p in path:
		if g.value_at(p) == 0:
			holes += 1
	_check(holes == 0, "%d of %d points on the walked path were left unrevealed" % [holes, path.size()])

	# ...and a dash, which covers ~8 m in a few frames and must not tunnel through the throttle.
	var g2 := MapGrid.make(Rect2(-40, -40, 120, 120), 1.0)
	var from := Vector2(0, 0)
	var dash: Array[Vector2] = []
	var last2 := Vector2.INF
	for i in 12:
		from += Vector2(0.75, 0) * (8.0 / 12.0) / 0.75
		dash.append(from)
		if not last2.is_finite() or from.distance_squared_to(last2) >= step * step:
			g2.stamp(from, reveal)
			last2 = from
	var dash_holes := 0
	for p in dash:
		if g2.value_at(p) == 0:
			dash_holes += 1
	_check(dash_holes == 0, "a dash left %d unrevealed points" % dash_holes)

	_out("[VERIFY] walk suite ok")


# --- 4. SERIALISATION --------------------------------------------------------------------------


func _serialise_suite() -> void:
	var bounds := Rect2(-48, -38, 224, 142)
	var g := MapGrid.make(bounds, 1.0)
	g.stamp(Vector2(0, 0), 14.0)
	g.stamp(Vector2(60, 20), 14.0)

	var markers: Array = []
	for i in 20:
		markers.append({"p": Vector2(i * 3.0, -i * 2.0), "k": i % 6, "f": 0, "n": "pin %d" % i})

	var payload := {"v": 1, "zones": {"res://scenes/world/room.tscn": g.to_dict()}}
	(payload["zones"] as Dictionary)["res://scenes/world/room.tscn"]["markers"] = markers

	# THE SECURITY PROPERTY, asserted rather than assumed: nothing in the payload may be an Object.
	# It is what makes store_var(v, false) safe on a file a player can edit.
	var offenders: Array[String] = []
	_assert_builtin(payload, "root", offenders)
	_check(offenders.is_empty(), "save payload contains non-builtin values: %s" % ", ".join(offenders))

	var path := "user://_verify_map_roundtrip.dat"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var(payload, false)
	f.close()
	f = FileAccess.open(path, FileAccess.READ)
	var back: Variant = f.get_var(false)
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_check(typeof(back) == TYPE_DICTIONARY, "save did not round-trip as a dictionary")
	var entry: Variant = ((back as Dictionary)["zones"] as Dictionary)["res://scenes/world/room.tscn"]
	var g2 := MapGrid.from_dict(entry)
	_check(g2 != null, "a valid grid failed to load")
	if g2:
		_check(g2.bytes == g.bytes, "fog bytes differ after a round-trip")
		_check(g2.w == g.w and g2.h == g.h and is_equal_approx(g2.cell, g.cell),
				"grid dimensions differ after a round-trip")
		_check(g2.matches(bounds, 1.0), "a round-tripped grid no longer matches its own bounds")
		# A grid must REFUSE the wrong rect rather than load against it — the failure that produces a
		# map which looks fine and is silently, unfixably offset.
		_check(not g2.matches(Rect2(-48, -38, 260, 142), 1.0),
				"a grid accepted a rect 36 m wider than the one it was built for")
		_check(not g2.matches(bounds, 2.0), "a grid accepted a different cell size")

	var cleaned := MapGrid.clean_markers(markers)
	_check(cleaned.size() == 20, "clean_markers dropped valid markers (%d/20)" % cleaned.size())
	# Junk must be dropped, not trusted — a String where a Vector2 belongs would crash _draw().
	var junk := [{"p": "not a vector", "k": 0}, {"k": 3}, 42, {"p": Vector2.ZERO, "k": "x"}]
	_check(MapGrid.clean_markers(junk).is_empty(), "clean_markers accepted malformed entries")
	_check(MapGrid.clean_markers(markers, 5).size() == 5, "clean_markers ignored its cap")
	_check(MapGrid.from_dict({"rect": [0, 0, 4, 4], "cell": 1.0, "w": 4, "h": 4,
			"fog": PackedByteArray([1, 2, 3])}) == null,
			"from_dict accepted a byte array of the wrong length")
	_check(MapGrid.from_dict("nonsense") == null, "from_dict accepted a non-dictionary")

	_out("[VERIFY] serialise suite ok")


## Recursive type walk. Anything that is not a container or a plain value is reported by path.
func _assert_builtin(v: Variant, path: String, out: Array[String]) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k: Variant in (v as Dictionary):
				_assert_builtin(k, path + ".<key>", out)
				_assert_builtin((v as Dictionary)[k], "%s.%s" % [path, k], out)
		TYPE_ARRAY:
			for i in (v as Array).size():
				_assert_builtin((v as Array)[i], "%s[%d]" % [path, i], out)
		TYPE_OBJECT:
			out.append(path)
		TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_BOOL, TYPE_NIL, \
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_RECT2, TYPE_PACKED_BYTE_ARRAY:
			pass
		_:
			out.append("%s (type %d)" % [path, typeof(v)])


# --- 5. THE DUNGEON PLAN -----------------------------------------------------------------------


func _dungeon_suite() -> void:
	for s in range(1, 51):
		var lay := DungeonLayout.generate(s, 9, 1, 2)
		var floors := {}
		for anchor: Vector3i in lay.rooms:
			floors[(lay.rooms[anchor] as DungeonLayout.RoomData).cell.y] = true

		var drawn := 0
		for f: int in floors:
			var plan := MapPainter.plan_from_layout(lay, f)
			drawn += (plan["rooms"] as Array).size()

			# No two rooms on a floor may overlap — if they did, the layout itself would be broken
			# and the map would be showing it.
			var rects: Array = []
			for room: Dictionary in plan["rooms"]:
				for other: Rect2 in rects:
					_check(not (room["rect"] as Rect2).intersects(other, true),
							"seed %d floor %d: room rects %s and %s overlap" % [s, f, room["rect"], other])
				rects.append(room["rect"])

			# Every drawn corridor must land inside two DIFFERENT rooms. A link with one end in
			# empty space is a passage drawn to nowhere.
			for link: Dictionary in plan["links"]:
				var ia := _room_index(rects, link["a"])
				var ib := _room_index(rects, link["b"])
				_check(ia >= 0 and ib >= 0 and ia != ib,
						"seed %d floor %d: corridor %v->%v does not join two rooms (%d, %d)"
								% [s, f, link["a"], link["b"], ia, ib])

		_check(drawn == lay.rooms.size(),
				"seed %d: drew %d rooms across %d floors, layout has %d"
						% [s, drawn, floors.size(), lay.rooms.size()])
		_check(MapPainter.plan_from_layout(lay, 9999)["rooms"].is_empty(),
				"seed %d: an empty floor returned rooms" % s)

	_out("[VERIFY] dungeon plan suite ok")


func _room_index(rects: Array, at: Vector2) -> int:
	for i in rects.size():
		if (rects[i] as Rect2).grow(2.0).has_point(at):
			return i
	return -1


# --- 6. THE HUB'S DERIVED RECT -----------------------------------------------------------------


## Instantiates the real hub and reports what the collision blockout actually yields — including
## whether the warehouse district east of the arena carries any world collision at all, which is not
## knowable from room.tscn and which decides whether the eastern third of the map can be drawn.
func _zone_suite() -> void:
	var packed: PackedScene = load("res://scenes/world/room.tscn")
	if packed == null:
		_check(false, "could not load res://scenes/world/room.tscn")
		_out("[VERIFY] zone rect suite ok")
		_finish()
		return
	var zone := packed.instantiate() as Node3D
	root.add_child(zone)
	for i in 6:
		await process_frame

	var plan := MapPainter.plan_from_collision(zone)
	var rect := MapPainter.derive_rect(zone)
	var floors := 0
	var walls := 0
	for item in plan:
		if item["kind"] == MapPainter.Kind.FLOOR:
			floors += 1
		else:
			walls += 1
	_out("  hub: %d shapes (%d floor, %d wall)  derived rect %s" % [plan.size(), floors, walls, rect])

	_check(plan.size() >= 15, "only %d collision shapes found in the hub — expected 15+" % plan.size())
	_check(floors >= 4, "only %d shapes classified as FLOOR" % floors)
	_check(walls >= 8, "only %d shapes classified as WALL" % walls)

	# Landmarks that must be inside the derived rect, in ZONE-LOCAL metres.
	for probe in [
			["garden portal", Vector2(0, -20)],
			["house centre", Vector2(0, 0)],
			["arena centre", Vector2(0, 56.38)],
			["arena south rim", Vector2(0, 96.0)]]:
		_check(rect.has_point(probe[1]), "derived rect %s excludes the %s at %v"
				% [rect, probe[0], probe[1]])

	# The classifier, on named shapes whose dimensions are pinned in room.tscn.
	var by_name := {}
	for cs in _shapes_named(zone):
		by_name[cs.name] = cs
	for pair in [["Floor", MapPainter.Kind.FLOOR], ["GardenGround", MapPainter.Kind.FLOOR],
			["FrontStrip", MapPainter.Kind.FLOOR], ["StairsRamp", MapPainter.Kind.FLOOR],
			["ArenaFloor", MapPainter.Kind.FLOOR], ["WallLeft", MapPainter.Kind.WALL],
			["HedgeLeft", MapPainter.Kind.WALL], ["ColumnL", MapPainter.Kind.WALL]]:
		var cs: CollisionShape3D = by_name.get(pair[0])
		if cs == null:
			_check(false, "collision shape '%s' is gone from room.tscn" % pair[0])
			continue
		var got := MapPainter.Kind.WALL if MapPainter._shape_height(cs.shape) > MapPainter.FLOOR_MAX_Y \
				else MapPainter.Kind.FLOOR
		_check(got == pair[1], "%s classified as %s" % [pair[0], "WALL" if got == 1 else "FLOOR"])

	# THE WAREHOUSE DISTRICT. room.tscn's hand-authored Collision body stops at the arena, so this
	# was an open question when the map was written: the east is covered only by Area3D camera and
	# fade volumes, which are deliberately invisible to MapPainter. The answer turned out to be that
	# room_kit.blend contributes -col bodies out there. Asserted rather than noted, because the day
	# that stops being true the eastern third of the hub silently vanishes off the map.
	_check(rect.end.x > 150.0,
			"derived rect stops at x=%.1f — the warehouse district (x~110-165) has lost its world "
			% rect.end.x + "collision, and the east of the hub can no longer be drawn")

	# merge_floors must reduce the slabs, not multiply them.
	var merged := MapPainter.merge_floors(plan)
	_check(not merged.is_empty(), "merge_floors produced nothing from %d floors" % floors)
	_check(merged.size() <= floors, "merge_floors returned %d outlines from %d floor shapes"
			% [merged.size(), floors])
	_out("  merged %d floor shapes into %d silhouette(s)" % [floors, merged.size()])

	zone.queue_free()
	_out("[VERIFY] zone rect suite ok")
	await _room_outline_suite()
	_finish()


## THE PROOF THAT ROOMS ARE NOT RECTANGLES. Builds a real crypt and measures every room's floor the
## way the map does, then asserts the measurement is both correct AND actually different from the
## layout's cell block — because a room_outline() that silently returned the bounding box would
## satisfy every other check here and put us back exactly where we started.
func _room_outline_suite() -> void:
	var packed: PackedScene = load("res://scenes/world/zone_crypt.tscn")
	if packed == null:
		_check(false, "could not load zone_crypt.tscn")
		_out("[VERIFY] room outline suite ok")
		return
	# A SEED THAT ACTUALLY HAS A STAIRCASE, chosen rather than hoped for.
	#
	# This suite leaves `dungeon_seed` at 0, so the crypt rolls a fresh seed every run — which is the
	# point, because the whole file exists to measure varied geometry rather than one pinned layout.
	# But it then asserts a STAIR room exists, and only about 90% of seeds produce one
	# (verify_dungeon measures 179 of 200), so roughly one run in ten failed on a degenerate seed
	# with nothing wrong. A test that cries wolf at that rate teaches you to re-run it instead of
	# reading it, which is worse than not having it.
	#
	# The layout is pure data and costs ~2 ms, so the seed can simply be PICKED before anything is
	# built: keep rolling until one has a stair, then hand that seed to the zone. Randomness is
	# preserved; the assertion below stops being a coin toss.
	var seed_value := 0
	for _try in 60:
		var probe := DungeonLayout.generate(randi() % 1000000 + 1, 9)
		var has_stair := false
		for anchor: Vector3i in probe.rooms:
			if (probe.rooms[anchor] as DungeonLayout.RoomData).type == DungeonLayout.RoomType.STAIR:
				has_stair = true
				break
		if has_stair:
			seed_value = probe.seed_used
			break
	_check(seed_value != 0, "60 layouts in a row produced no stair room — generation is broken")

	var zone := packed.instantiate() as Node3D
	zone.set("dungeon_seed", seed_value)
	root.add_child(zone)
	for i in 8:
		await process_frame

	var lay: DungeonLayout = zone.get("layout")
	if lay == null:
		_check(false, "crypt built without a layout")
		zone.queue_free()
		_out("[VERIFY] room outline suite ok")
		return

	var measured := 0
	var irregular := 0
	var stairs := 0
	for child in zone.get_children():
		if not (child is DungeonRoom):
			continue
		var cell: Vector3i = (child as DungeonRoom).cell
		var rd: DungeonLayout.RoomData = lay.rooms.get(cell)
		if rd == null:
			_check(false, "room node at cell %s is not in the layout" % cell)
			continue
		var shapes := MapPainter.room_outline(child as Node3D, zone)
		_check(not shapes.is_empty(), "room %s measured to nothing — no floor tiles found" % cell)
		if shapes.is_empty():
			continue
		measured += 1

		var mid := DungeonLayout.room_origin(rd)
		var ext := DungeonLayout.size_of(rd)
		var block := Rect2(mid.x - ext.x * 0.5, mid.z - ext.z * 0.5, ext.x, ext.z)
		var area := 0.0
		for shape: PackedVector2Array in shapes:
			# Grown only for the containment test — floating point and the tile edges land exactly
			# on the boundary.
			for p in shape:
				_check(block.grow(0.6).has_point(p),
						"room %s: outline point %v escapes its cell block %s" % [cell, p, block])
			area += absf(_area(shape))

		# AREA, not vertex count. The first version of this called anything with more than four
		# vertices "irregular" and reported 12 of 12 — but merge_polygons leaves collinear vertices
		# along a joined tile edge, so a perfectly rectangular room scores 12 corners too. Area
		# against the EXACT cell block (not a grown one, which inflates it and makes every room look
		# carved) is the honest measure: a carved room is strictly smaller, a full one matches.
		var full_area := block.get_area()
		_check(area <= full_area + 1.0,
				"room %s: measured area %.1f exceeds its cell block %.1f" % [cell, area, full_area])
		# TRUNCATION, the failure that showed up as stair rooms collapsing to a few stray tiles.
		# RoomShape's carving rule only takes corner bites no deeper than half the grid and always
		# spares the middle cross, so the smallest legal footprint is (cols + rows - 1) tiles out of
		# cols * rows — 47% for a 5x3 room. Anything under a third means geometry is being dropped,
		# not carved.
		_check(area > full_area * 0.33,
				"room %s (type %d): measured %.1f of %.1f — the floor is being TRUNCATED, not carved"
						% [cell, rd.type, area, full_area])
		if rd.type == DungeonLayout.RoomType.STAIR:
			stairs += 1
			# A stair room is never carved (RoomShape.pick keeps it full), and its walkable surface
			# is one tilted ramp collider. If it comes back small, the ramp was thrown away.
			_check(area > full_area * 0.8,
					"STAIR room %s measured %.1f of %.1f — the flight's ramp collider was dropped"
							% [cell, area, full_area])
		if area < full_area * 0.98:
			irregular += 1

	_check(measured >= 8, "only %d rooms measured" % measured)
	# Both directions matter. No carved rooms means room_outline is handing back the bounding box.
	# No FULL rooms means it is under-measuring — RoomShape.pick keeps START, BOSS, TREASURE and
	# STAIR as full rectangles on purpose, so a crypt that reports every room carved is wrong too.
	_check(irregular > 0,
			"all %d rooms measured at full cell-block area — room_outline is returning the "
			% measured + "envelope, not the carved floor")
	_check(irregular < measured,
			"all %d rooms measured as carved, but START/BOSS/TREASURE/STAIR are always full "
			% measured + "rectangles — the floor is being under-measured")
	# stair_count defaults to 1, so a crypt with none means the seed is degenerate and the stair
	# assertions above never ran — a silent pass is the thing this whole file exists to prevent.
	_check(stairs > 0, "no STAIR room in this crypt: the staircase checks did not run")
	_out("  crypt seed %d: %d rooms measured, %d carved / %d full, %d stair"
			% [lay.seed_used, measured, irregular, measured - irregular, stairs])

	zone.queue_free()
	_out("[VERIFY] room outline suite ok")


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		a += poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y
	return a * 0.5


func _shapes_named(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is CollisionShape3D and (cur as CollisionShape3D).shape != null:
			out.append(cur)
	return out

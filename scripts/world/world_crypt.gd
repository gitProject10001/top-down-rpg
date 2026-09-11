@tool
extends RefCounted
## THE CRYPT PLAN: a level's design, as plain data, from the layout system this game already has.
##
## `scripts/dungeon/` decides WHERE the rooms go — which room sits beside which, how big it is,
## which faces carry a door, what it is for, where the boss and the key are, where the loop
## closes. That system is tested by 29 suites with PINNED HASHES over its output, so **nothing
## here edits it**: this file reads its result and translates it.
##
## WHAT COMES OUT is a Dictionary of plain Variants in metres, in the zone's own frame — no
## RefCounted, no class the addon would have to know. `addons/procedural_architecture` takes it
## through `ZoneBrief.plan` and `ops/plan.gd` and never learns that a dungeon exists. That is the
## contract rule the addon keeps everywhere else ("pure data, in metres and radians; it never
## sees the other level's code") and the reason this file is in `scripts/` and not in the addon.
##
## WHY THE WALLS COME OUT STRAIGHT, structurally rather than by tuning. A `RoomShape` is a grid
## of 4 m tiles; the boundary of its solid tiles is a rectilinear polygon whose vertices sit
## exactly on the tile lattice. Tracing it and merging collinear runs is the whole geometry
## step. There is no raster to quantise a slanted edge into a staircase, no single-cell nibble,
## and no outline simplifier with an epsilon too small to remove a step — the three things that
## made the old dungeon a zigzag are not in this path at all.
##
## THE DOORWAY IS A STUB, NOT A CORRIDOR, and that took a while to see. Floorplan derives walls
## from island rings, so a separate corridor island ending inside a room's territory grows a
## sealing wall across the opening. Instead each room's floor is its tiles UNION one stub per
## door: one tile wide, half the gap long. Two neighbours' stubs meet exactly on the mid-gap
## line, each side's wall band backs onto the other's, and together they are a doorway plug
## through solid rock — with no third island and nobody owning the passage.

const Layout := preload("res://scripts/dungeon/dungeon_layout.gd")
const Shape := preload("res://scripts/dungeon/gameplay/room_shape.gd")

## Metres of clear ground kept outside the outermost room, so the rock has somewhere to be.
## A WHOLE NUMBER OF HALF-TILES, and that is not cosmetic: this is added to every point when the
## level is moved into the zone's all-positive frame, so a margin off the lattice takes every
## vertex in the level with it. At a 5 m tile the grain is 2.5 m, and 12.5 is five of them —
## 12.0 is not, and it put all 176 vertices of a level off the lattice.
const MARGIN := 12.5
## THE LEVEL IS BUILT AT 1.25x. The layout's own pitch gives rooms of 20x12 m up to 68x28; this
## is a top-down ACTION game with a 2 m melee reach and a camera framing about 15 m, and the
## smallest of those is tight for a fight. Scaling the whole plan — pitch, tiles, gaps, doors —
## puts the range at 25x15 to 85x35 without touching a number in `scripts/dungeon` and without
## bending an edge off the lattice: a 5 m tile is as orthogonal as a 4 m one.
##
## NOTHING IS TILED WITH MODULES, so nothing constrains this to the crypt kit's 4 m block. The
## walls are the bake's own geometry with a material on them; if a modular kit is ever wanted,
## THIS is the number that has to come back to 1.0 for the blocks to fit a run.
const SCALE := 1.25
## THE ROCK BETWEEN TWO ROOMS, metres — which is the only thing a wall IS from a top-down
## camera. The layout leaves `Layout.GAP` between neighbouring rooms and the bake fills it with
## the two rooms' wall bands meeting in the middle, so the gap does not merely contain the wall,
## it IS the wall. At this scale that gap is five metres, and five metres of rock under an eight
## metre ceiling is a rampart: in an isometric frame it eats more screen than the rooms do.
##
## SO EVERY ROOM GROWS INSTEAD OF MOVING. Each outline is offset outwards by `_GROW` before its
## doorways are cut, which closes the gap to this figure without touching the layout — the same
## rooms in the same cells with the same neighbours and the same doors, each a little larger.
## Moving rooms closer would have been the other way to do it and is the wrong one: the layout
## is hash-pinned level design, and its pitch is what guarantees two rooms never overlap.
##
## The doorways need no adjustment at all, which is the sign this is the right seam: a stub
## reaches to the mid-gap LINE, and growing the rooms either side of that line does not move it.
const GAP_M := 2.5
## What each room gains on every side to close the gap to `GAP_M`. A quarter of a tile, so the
## outlines stay on a grid — see `_grow`.
const _GROW := (Layout.GAP * SCALE - GAP_M) * 0.5

## Below this a room keeps its full rectangle. A 1x1 is the smallest thing the layout makes and
## carving takes a third of it away; the user asked for FEWER and BIGGER rooms, so the bites are
## spent where there is room to lose some — which is also where a silhouette reads at all.
const CARVE_ABOVE_M2 := 480.0


## The whole level as data. `room_count` is a parameter of the layout, not a change to it, so
## asking for twelve rooms instead of nine moves none of its pinned hashes.
static func build(seed_value: int, room_count := 12, stair_count := 1, loop_count := 2) -> Dictionary:
	var lay: RefCounted = Layout.generate(seed_value, room_count, stair_count, loop_count)
	var rds: Array = []
	for key in lay.rooms:
		rds.append(lay.rooms[key])
	# a stable order, so the same seed writes the same tokens whatever the Dictionary did
	rds.sort_custom(func(a: RefCounted, b: RefCounted) -> bool:
		if a.cell.y != b.cell.y:
			return a.cell.y < b.cell.y
		if a.cell.z != b.cell.z:
			return a.cell.z < b.cell.z
		return a.cell.x < b.cell.x)

	var rng := RandomNumberGenerator.new()
	var index := {}                       # the RoomData -> its position in `rooms`
	var raw: Array = []
	for i in rds.size():
		var rd: RefCounted = rds[i]
		index[rd] = i
		rng.seed = hash("%d|shape|%d,%d,%d" % [seed_value, rd.cell.x, rd.cell.y, rd.cell.z])
		var full: Vector3 = Layout.size_of(rd)
		var shape: RefCounted = null
		if full.x * full.z >= CARVE_ABOVE_M2:
			shape = Shape.pick(rd, rng, _protect_cols(rd), _protect_rows(rd))
		else:
			shape = Shape.for_room(rd)    # a small room keeps every metre it has
		raw.append({"rd": rd, "shape": shape})

	# --- the polygons, in the layout's own frame ------------------------------------------
	var box := Rect2()
	var first := true
	for r: Dictionary in raw:
		var rd: RefCounted = r.rd
		var poly := _scaled(_trace(r.shape))
		var at: Vector3 = Layout.room_origin(rd)
		var centre := Vector2(at.x, at.z) * SCALE
		poly = _shift(poly, centre)
		# BEFORE the doorways, not after: a stub is already the right length to reach the mid-gap
		# line, and growing it too would push it straight through into the neighbour.
		poly = _grow(poly)
		for e in (rd.edges as Array):
			if int(e.dir.y) != 0:
				continue                  # a stair edge goes up, not through a wall
			poly = _with_stub(poly, rd, e, centre)
		r["polygon"] = poly
		r["centre"] = centre
		for p in poly:
			box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
			first = false

	# --- into the zone's own frame: all-positive, a margin of rock all round ---------------
	var shift := -box.position + Vector2(MARGIN, MARGIN)
	var rooms: Array = []
	for i in raw.size():
		var r: Dictionary = raw[i]
		var rd: RefCounted = r.rd
		rooms.append({
			"token": "R%d" % (i + 1),
			"polygon": _shift(r.polygon, shift),
			"centre": (r.centre as Vector2) + shift,
			"floor": int(rd.cell.y),
			"kind": String(rd.kind),
			"module": String(rd.module_id),
			"purpose": String(rd.purpose),
			"type": int(rd.type),
			"dist": int(rd.dist),
			"holds_key": String(rd.holds_key),
			"cell": Vector2i(rd.cell.x, rd.cell.z),
			"size": Vector2i(rd.size.x, rd.size.z),
		})

	# --- the doors, once each ---------------------------------------------------------------
	var gates: Array = []
	var seen := {}
	for r: Dictionary in raw:
		var rd: RefCounted = r.rd
		var a := int(index[rd])
		for e in (rd.edges as Array):
			if int(e.dir.y) != 0:
				continue
			var other: RefCounted = _neighbour(lay, rd, e)
			if other == null or not index.has(other):
				continue
			var b := int(index[other])
			var pair := "%d-%d" % [mini(a, b), maxi(a, b)]
			if seen.has(pair):
				continue
			seen[pair] = true
			# THE DOORWAY IS AT THE END OF THE STUB, not at the room's wall face. The stub is
			# part of the room's floor island, so the wall face it starts at is INTERIOR — there
			# is no wall there to cut, and an opening placed on it is an opening in nothing. The
			# island's ring is at the far end of the stub, on the mid-gap line, and that is the
			# one wall between this room and its neighbour. Put the door where the wall is.
			var d: Vector3 = Layout.door_local(rd, e)
			var out := Vector2(e.dir.x, e.dir.z) * (Layout.GAP * 0.5 * SCALE)
			gates.append({
				"a": a, "b": b,
				"point": (r.centre as Vector2) + Vector2(d.x, d.z) * SCALE + out + shift,
				# the axis the passage runs along, which is NOT the line between the two rooms'
				# centres: a hall's door is on the boundary cell it leaves from, so the two can
				# be well off each other. Anything that wants to walk, aim or cast through a
				# doorway needs this rather than the centroids.
				"dir": Vector2(e.dir.x, e.dir.z),
				"floor": int(rd.cell.y),
				"type": int(e.type),
				"key_id": String(e.key_id),
			})

	var bounds := Rect2(Vector2.ZERO, box.size + Vector2(MARGIN, MARGIN) * 2.0)
	return {
		"rooms": rooms,
		"gates": gates,
		"spawn": _spawn(rooms),
		"bounds": bounds,
		"floors": _floors(rooms),
		"seed": seed_value,
	}


## THE TILE LATTICE TO A POLYGON. Every solid tile is a `TILE`-metre square; a side with no solid
## tile beyond it is a boundary edge. Emitted so the interior is always on the left, chained into
## one loop, and collinear runs merged — so a twenty-metre wall is ONE edge and not five.
static func _trace(shape: RefCounted) -> PackedVector2Array:
	var t: float = Shape.TILE
	var cols := int(shape.cols)
	var rows := int(shape.rows)
	var next := {}                        # a boundary edge's start -> its end
	for tile in (shape.tiles() as Array):
		var i := int(tile.x)
		var j := int(tile.y)
		var lo := Vector2((i - cols * 0.5) * t, (j - rows * 0.5) * t)
		var hi := lo + Vector2(t, t)
		if not shape.is_solid(Vector2i(i, j - 1)):
			next[lo] = Vector2(hi.x, lo.y)
		if not shape.is_solid(Vector2i(i + 1, j)):
			next[Vector2(hi.x, lo.y)] = hi
		if not shape.is_solid(Vector2i(i, j + 1)):
			next[hi] = Vector2(lo.x, hi.y)
		if not shape.is_solid(Vector2i(i - 1, j)):
			next[Vector2(lo.x, hi.y)] = lo
	if next.is_empty():
		return PackedVector2Array()
	var start: Vector2 = next.keys()[0]
	var loop := PackedVector2Array([start])
	var at: Vector2 = next[start]
	var guard := 0
	while at != start and guard < 4096:
		loop.append(at)
		if not next.has(at):
			break                         # a shape that is not one loop: take what there is
		at = next[at]
		guard += 1
	return _merge_collinear(loop)


## Three points in a line are two edges pretending to be one. Merging them is what makes a wall a
## wall: the bake draws one piece per edge, so an unmerged run is twenty meshes for one surface.
static func _merge_collinear(poly: PackedVector2Array) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = poly[(i - 1 + n) % n]
		var here: Vector2 = poly[i]
		var post: Vector2 = poly[(i + 1) % n]
		if absf((here - prev).normalized().cross((post - here).normalized())) > 0.0001:
			out.append(here)
	return out if out.size() >= 3 else poly


## THE ROOM, A QUARTER-TILE LARGER ALL ROUND. A mitred offset, which on a rectilinear outline
## simply moves every edge out along its own normal and puts every corner back where the two
## moved edges cross — so the result is still rectilinear, still made of the same edges, and
## every vertex still on a grid, now a quarter-tile one rather than a half-tile one. That is why
## the amount is a quarter tile and not a round number of metres.
##
## The snap afterwards is for the offset's arithmetic, not for its geometry: it only moves a
## coordinate already within a millimetre of the grid, so a genuinely diagonal edge — a chamfer,
## if the shapes ever produce one through the tile trace — is left exactly where it was rather
## than being bent into a staircase.
static func _grow(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() < 3 or _GROW <= 0.0:
		return poly
	var grown: Array = Geometry2D.offset_polygon(poly, _GROW, Geometry2D.JOIN_MITER)
	if grown.is_empty():
		return poly
	var best: PackedVector2Array = grown[0]
	var best_a := -1.0
	for m: PackedVector2Array in grown:
		var a := absf(_area(m))
		if a > best_a:
			best_a = a
			best = m
	var grid: float = Shape.TILE * SCALE * 0.25
	var out := PackedVector2Array()
	for pt: Vector2 in best:
		out.append(Vector2(_snap(pt.x, grid), _snap(pt.y, grid)))
	return _merge_collinear(out)


static func _snap(v: float, grid: float) -> float:
	var r := roundf(v / grid) * grid
	return r if absf(r - v) < 0.001 else v


## The room's floor, plus the half of the doorway that belongs to it: one tile wide, `GAP / 2`
## long, reaching out to the mid-gap line where the neighbour's own stub meets it.
static func _with_stub(poly: PackedVector2Array, rd: RefCounted, e: RefCounted,
		centre: Vector2) -> PackedVector2Array:
	var d: Vector3 = Layout.door_local(rd, e)
	var at := centre + Vector2(d.x, d.z) * SCALE
	var out := Vector2(e.dir.x, e.dir.z)
	var side := Vector2(-out.y, out.x)
	var half_w: float = Shape.TILE * 0.5 * SCALE
	var reach: float = Layout.GAP * 0.5 * SCALE
	# EVERY CORNER STAYS ON THE LATTICE. The stub starts a half-tile INSIDE the wall — so the
	# union always overlaps the room rather than merely touching it, which would leave a
	# degenerate seam — and reaches a half-gap out to the mid-gap line. Both are whole steps of
	# the same grid the tiles are on, so the merged outline gains no vertex that is not.
	var back: float = Shape.TILE * 0.5 * SCALE
	var base := at - out * back
	var rect := PackedVector2Array([
		base + side * half_w, base - side * half_w,
		base - side * half_w + out * (back + reach), base + side * half_w + out * (back + reach)])
	var merged: Array = Geometry2D.merge_polygons(poly, rect)
	if merged.is_empty():
		return poly
	var best: PackedVector2Array = merged[0]
	var best_a := -1.0
	for m: PackedVector2Array in merged:
		var a := absf(_area(m))
		if a > best_a:
			best_a = a
			best = m
	return _merge_collinear(best)


static func _neighbour(lay: RefCounted, rd: RefCounted, e: RefCounted) -> RefCounted:
	var cell: Vector3i = e.from_cell + e.dir
	var owner: Variant = lay.occupied.get(cell)
	if owner == null:
		return null
	return lay.rooms.get(owner)


## Which tile columns and rows a doorway needs kept solid, so a corner bite can never eat the
## ground a door opens onto. The shape has never known which walls are doors — that is the
## layout's business — so the caller works it out, which is what `pick`'s docstring asks for.
static func _protect_cols(rd: RefCounted) -> Array:
	var cols: Array = []
	var s: RefCounted = Shape.for_room(rd)
	for e in (rd.edges as Array):
		if int(e.dir.y) != 0 or int(e.dir.x) != 0:
			continue                      # a door on a Z face pins a COLUMN
		var d: Vector3 = Layout.door_local(rd, e)
		var c := int(s.col_at(d.x))
		if not cols.has(c):
			cols.append(c)
	return cols


static func _protect_rows(rd: RefCounted) -> Array:
	var rows: Array = []
	var s: RefCounted = Shape.for_room(rd)
	for e in (rd.edges as Array):
		if int(e.dir.y) != 0 or int(e.dir.z) != 0:
			continue                      # a door on an X face pins a ROW
		var d: Vector3 = Layout.door_local(rd, e)
		var r := int(s.row_at(d.z))
		if not rows.has(r):
			rows.append(r)
	return rows


## Where the player lands: the middle of the START room, which the layout put at the origin.
static func _spawn(rooms: Array) -> Vector2:
	for r: Dictionary in rooms:
		if int(r.type) == Layout.RoomType.START:
			return r.centre
	return (rooms[0] as Dictionary).centre if not rooms.is_empty() else Vector2.ZERO


static func _floors(rooms: Array) -> int:
	var lo := 0
	var hi := 0
	for r: Dictionary in rooms:
		lo = mini(lo, int(r.floor))
		hi = maxi(hi, int(r.floor))
	return hi - lo + 1


## The plan's own scale, applied once, to everything.
static func _scaled(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * SCALE)
	return out


static func _shift(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + by)
	return out


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

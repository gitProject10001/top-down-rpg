class_name MapPainter
extends RefCounted
## TURNS A ZONE INTO POLYGONS. Pure geometry, no drawing, no nodes kept — so the headless suite can
## assert what the map will look like without a renderer, and the view can cache the result.
##
## WHY VECTOR AND NOT A BAKED PHOTOGRAPH. The two obvious alternatives — an offline orthographic
## render, or the same thing in a runtime SubViewport — both produce a PICTURE of the level: the
## house roof occludes the house, the sun and the painterly grade bake in, and "stylizing" it means
## running an edge detect over it and hoping. A bake additionally rots the moment room.tscn is
## edited, and nothing reminds you. Building the plan from the collision blockout instead makes the
## stylization BE the construction, which is what a hand-drawn map actually is.
##
## COLLISION, NOT VISUALS, for the same reason the fog is walk-driven: where the player can walk is
## exactly what a walk-revealed map wants to show. It is also the only choice that cannot be blown
## up by a 700 x 700 m CloudSea quad or a skybox the way a VisualInstance3D union can.

enum Kind { FLOOR, WALL }

## Y extent below which a shape is ground rather than an obstacle. 1.0 m is not a round number
## picked for looks — it is measured. The floors are 0.4 m (col_floor, col_garden, col_front_strip),
## 0.6 m (col_stairs) and 1.0 m (col_arena_floor, a cylinder); the thinnest WALL in the project is
## col_hedge_lr at 1.6 m. Anything from 1.0 to 1.5 separates them; 1.0 keeps the arena floor on the
## correct side of the line with no slack to spare, which is why it is the value and not 1.5.
const FLOOR_MAX_Y := 1.0

## ONE BODY IS ONE PIECE. In `architecture` mode a thin shape counts as floor only if NOTHING else
## in its own CollisionObject3D is tall — so a piece is judged whole, by what it is, instead of
## shape by shape.
##
## This exists because neither simpler rule works. Thickness alone lets Kit._doorway's LINTEL — a
## 2.0 x 0.8 x 0.5 beam at y = 2.6 (kit.gd:282) — read as floor, and every doorway added a square
## metre of phantom ground. But a height cutoff cannot fix it either: Kit.stair gives a whole flight
## a SINGLE 0.6 m-thin collider tilted along the slope and centred at rise/2 (kit.gd:349), so its
## underside sits ~3.7 m up — above the lintel's 2.2 m. Any threshold that drops the lintel also
## drops every staircase, which is exactly what happened: stair rooms collapsed to a few stray tiles.
##
## Judged per body, the two separate cleanly and for the right reason:
##   doorway  — jambs are 6.8 m, so the piece is masonry and none of it is floor
##   stair    — its only collider IS the thin ramp, so the piece is a walkable surface
##   tile     — 0.2 m alone, floor
##
## OFF for hand-authored zones. The hub keeps its whole blockout — floors, walls, hedges, arena — in
## one StaticBody3D (room.tscn:61), so per-body judgement would condemn the entire level as wall.
const ARCHITECTURE_TALL := FLOOR_MAX_Y

## Segments used to approximate a CylinderShape3D. 24 is smooth at any zoom the map offers and keeps
## the arena (r = 40) from reading as a polygon.
const CIRCLE_SEGMENTS := 24

## Hard ceiling on a derived rect, per axis. A stray or mis-scaled shape must degrade to a warning
## and a clamped map, never a multi-gigabyte allocation in MapGrid.make().
const MAX_SPAN := 512.0


## Every world-layer collision shape under `node`, as XZ polygons.
## Returns [{poly: PackedVector2Array, kind: int, y: float}], `y` being the local height for depth
## sorting and elevation tinting.
##
## `frame` is the node the coordinates come out relative to, defaulting to `node` itself. They differ
## for a dungeon ROOM: the geometry to walk is the room, but the space everything else on that map
## lives in is the dungeon root's — the same space DungeonLayout.room_origin() returns.
## `architecture` switches on per-body judgement — see ARCHITECTURE_TALL. Right for kit-built
## dungeons, where one body is one piece; wrong for a hand-authored zone that keeps its whole
## blockout in a single StaticBody3D.
static func plan_from_collision(node: Node3D, frame: Node3D = null, architecture := false) -> Array:
	var out: Array = []
	if node == null:
		return out
	var to_zone := (frame if frame != null else node).global_transform.affine_inverse()
	var shapes := _collision_shapes(node)

	# Tallest shape per owning body, so each piece can be judged as a whole below.
	var body_tall := {}
	if architecture:
		for cs: CollisionShape3D in shapes:
			if cs.shape == null:
				continue
			var owner_id := cs.get_parent().get_instance_id()
			body_tall[owner_id] = maxf(body_tall.get(owner_id, 0.0), _shape_height(cs.shape))

	for cs: CollisionShape3D in shapes:
		var shape := cs.shape
		if shape == null:
			continue
		var local := to_zone * cs.global_transform
		var poly := _shape_to_polygon(shape, local)
		if poly.size() < 3:
			continue
		var is_floor := _shape_height(shape) <= FLOOR_MAX_Y
		if architecture and is_floor:
			is_floor = body_tall.get(cs.get_parent().get_instance_id(), 0.0) <= ARCHITECTURE_TALL
		out.append({
			"poly": poly,
			"kind": Kind.FLOOR if is_floor else Kind.WALL,
			"y": local.origin.y,
		})
	return out


## The zone's walkable footprint, unioned into as few outlines as the shapes allow.
##
## THIS IS THE MOVE THAT MAKES IT A MAP. Sixteen separate rectangles inked individually read as a
## pile of rectangles; merged into one silhouette and inked only along the OUTER boundary, they read
## as the edge of the world — and the seams between them, drawn afterwards as faint hairlines, read
## as paving. That is the distinction every hand-drawn plan makes and no bake can.
static func merge_floors(plan: Array) -> Array:
	var polys: Array = []
	for item in plan:
		if item["kind"] == Kind.FLOOR:
			polys.append(item["poly"])
	if polys.is_empty():
		return []
	var merged: Array = [polys[0]]
	for i in range(1, polys.size()):
		var next: Array = []
		var absorbed: PackedVector2Array = polys[i]
		for m in merged:
			var r := Geometry2D.merge_polygons(m, absorbed)
			# merge_polygons returns >1 polygon when the two do not touch (and can return a HOLE,
			# which is clockwise). Keep disjoint pieces separate rather than forcing a union that
			# does not exist.
			if r.size() == 1:
				absorbed = r[0]
			else:
				next.append(m)
		next.append(absorbed)
		merged = next
	return merged


## THE TRUE OUTLINE OF ONE BUILT ROOM, in `frame`-local XZ. Usually one polygon; an array because
## nothing guarantees it.
##
## Rooms have never actually been rectangles — RoomShape carves corner bites out of the 4 m tile
## grid, and RoomBuilder floors the survivors one `floor_tile` at a time precisely so irregular
## rooms are possible. The map was drawing DungeonLayout's cell-block bounding box, which is the
## room's ENVELOPE and not its shape, so every L-shaped room read as a rectangle.
##
## Derived from what was BUILT rather than from the layout, which is what makes this
## shape-agnostic: an oval room, a cross, a room with a hole in the middle all come out correct with
## no change here, because none of them are described anywhere except in the geometry.
static func room_outline(room: Node3D, frame: Node3D) -> Array:
	return merge_floors(plan_from_collision(room, frame, true))


## Union of every world-layer collision shape's zone-local XZ extent, padded and snapped.
## `pad` opens a margin so the outermost ink is not flush against the paper's edge.
static func derive_rect(zone: Node3D, pad := 6.0) -> Rect2:
	var plan := plan_from_collision(zone)
	if plan.is_empty():
		return Rect2()
	var box := Rect2(plan[0]["poly"][0], Vector2.ZERO)
	for item in plan:
		for p in (item["poly"] as PackedVector2Array):
			box = box.expand(p)
	box = box.grow(pad)
	if box.size.x > MAX_SPAN or box.size.y > MAX_SPAN:
		push_warning("MapPainter: zone extent %v exceeds %.0f m — clamping. A stray collision shape?"
				% [box.size, MAX_SPAN])
		var c := box.get_center()
		var half := Vector2(minf(box.size.x, MAX_SPAN), minf(box.size.y, MAX_SPAN)) * 0.5
		box = Rect2(c - half, half * 2.0)
	return box


# --- THE DUNGEON -------------------------------------------------------------------------------
#
# Nothing here is derived from geometry, because it does not have to be: DungeonLayout IS a map
# already — an integer cell graph with typed edges and room types — and its static helpers return
# coordinates in exactly the dungeon-local space MapGrid works in. Drawing it is a projection, not
# an analysis.


## One floor of a dungeon, as drawable data.
## Returns {rooms: [{cell: Vector3i, rect: Rect2, type: int}], links: [{a: Vector2, b: Vector2,
## type: int, key: String}]}.
static func plan_from_layout(layout: DungeonLayout, floor_index: int) -> Dictionary:
	var rooms: Array = []
	var links: Array = []
	if layout == null:
		return {"rooms": rooms, "links": links}

	for anchor: Vector3i in layout.rooms:
		var rd: DungeonLayout.RoomData = layout.rooms[anchor]
		if rd.cell.y != floor_index:
			continue
		# room_origin gives the CENTRE in world/zone-local metres; size_of gives the interior
		# extent (size * CELL_PITCH - GAP), so halls and closets come out at their true footprint
		# with no special case.
		var mid := DungeonLayout.room_origin(rd)
		var ext := DungeonLayout.size_of(rd)
		rooms.append({
			"cell": anchor,
			"rect": Rect2(mid.x - ext.x * 0.5, mid.z - ext.z * 0.5, ext.x, ext.z),
			"type": rd.type,
			"key": rd.holds_key,
		})

	for anchor: Vector3i in layout.rooms:
		var rd: DungeonLayout.RoomData = layout.rooms[anchor]
		for e: DungeonLayout.Edge in rd.edges:
			# Reuse the generator's exact ownership rule so each shared passage is emitted once.
			# Duplicating the passage would double-ink every corridor in the crypt.
			if not _owns_edge(e.dir):
				continue
			if e.dir.y != 0 or e.from_cell.y != floor_index:
				continue                       # a stair leaves this floor; drawn as a glyph instead
			# From the CELL boundary, not from room centres — a hall's exit is off-centre, and
			# centre-to-centre links would have corridors emerging from the middle of a wall.
			var a := DungeonLayout.cell_origin(e.from_cell)
			var b := DungeonLayout.cell_origin(e.from_cell + e.dir)
			links.append({
				"a": Vector2(a.x, a.z),
				"b": Vector2(b.x, b.z),
				"type": e.type,
				"key": e.key_id,
			})
	return {"rooms": rooms, "links": links}


static func _owns_edge(dir: Vector3i) -> bool:
	if dir.x != 0:
		return dir.x > 0
	if dir.z != 0:
		return dir.z > 0
	return dir.y > 0


# --- SHAPES ------------------------------------------------------------------------------------


static func _collision_shapes(zone: Node) -> Array:
	var out: Array = []
	var stack: Array = [zone]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var cs := n as CollisionShape3D
		if cs == null or cs.disabled:
			continue
		# Layer 1 is "world + bodies" (docs/architecture.md §4). Trigger volumes — camera zones,
		# roof fades, room triggers — sit on layer 0 or the hurtbox layers and are correctly
		# invisible to the map: they are not places, they are events.
		var body := cs.get_parent() as CollisionObject3D
		if body == null or (body.collision_layer & 1) == 0:
			continue
		out.append(cs)
	return out


static func _shape_height(shape: Shape3D) -> float:
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).height
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius * 2.0
	# A HULL IS AS TALL AS ITS POINTS. Without this the fallthrough below returned 0.0 for every
	# convex shape, which is not "no rule" — it is the answer FLOOR, given confidently, to a shape
	# that might be a six-metre wall. The dais (a frustum, 0.6 m) happens to want that answer and
	# would have got it for entirely the wrong reason.
	if shape is ConvexPolygonShape3D:
		var pts := (shape as ConvexPolygonShape3D).points
		if pts.is_empty():
			return 0.0
		var lo: float = pts[0].y
		var hi: float = lo
		for p: Vector3 in pts:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		return hi - lo
	return 0.0


## The shape's footprint on its own mid-plane, transformed into zone-local XZ.
##
## The mid-plane rather than the full 3-D shadow, deliberately: for the upright shapes (every wall,
## hedge and column) the two are identical, and for the one tilted shape in the project — StairsRamp,
## rotated 32 degrees about X — the mid-plane is the RAMP SURFACE, which is the thing a plan view of
## a staircase is supposed to show. The true shadow would add the slab's 0.6 m thickness as a 0.32 m
## fringe of stair that nobody can stand on.
static func _shape_to_polygon(shape: Shape3D, xf: Transform3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	if shape is BoxShape3D:
		var hs := (shape as BoxShape3D).size * 0.5
		for corner in [Vector3(-hs.x, 0, -hs.z), Vector3(hs.x, 0, -hs.z),
				Vector3(hs.x, 0, hs.z), Vector3(-hs.x, 0, hs.z)]:
			var p := xf * (corner as Vector3)
			out.append(Vector2(p.x, p.z))
	elif shape is CylinderShape3D:
		var r := (shape as CylinderShape3D).radius
		for i in CIRCLE_SEGMENTS:
			var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
			var p := xf * Vector3(cos(a) * r, 0.0, sin(a) * r)
			out.append(Vector2(p.x, p.z))
	elif shape is SphereShape3D or shape is CapsuleShape3D:
		var r2: float = (shape as SphereShape3D).radius if shape is SphereShape3D \
				else (shape as CapsuleShape3D).radius
		for i in CIRCLE_SEGMENTS:
			var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
			var p := xf * Vector3(cos(a) * r2, 0.0, sin(a) * r2)
			out.append(Vector2(p.x, p.z))
	elif shape is ConvexPolygonShape3D:
		out = _hull((shape as ConvexPolygonShape3D).points, xf)
	elif shape is ConcavePolygonShape3D:
		out = _hull((shape as ConcavePolygonShape3D).get_faces(), xf)
	else:
		push_warning("MapPainter: no footprint rule for %s — skipped" % shape.get_class())
		return out

	# Godot's polygon boolean ops want counter-clockwise input; a shape mirrored by a negative scale
	# in its transform arrives wound the other way and would be treated as a hole by merge_polygons.
	if out.size() >= 3 and _signed_area(out) < 0.0:
		out.reverse()
	return out


## Convex hull of a point soup projected to XZ. Right for both mesh-derived shape kinds: a convex
## hull is already convex so the hull is exact, and a trimesh's plan outline is what a map wants
## even where the true silhouette is concave.
static func _hull(points: PackedVector3Array, xf: Transform3D) -> PackedVector2Array:
	var flat := PackedVector2Array()
	for p in points:
		var w := xf * p
		flat.append(Vector2(w.x, w.z))
	if flat.size() < 3:
		return PackedVector2Array()
	return Geometry2D.convex_hull(flat)


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

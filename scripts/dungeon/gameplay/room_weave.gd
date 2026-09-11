@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomWeave
extends Object
## THE MEDIUM SCALE: what stands where inside one room, decided by rules instead of sprinkled.
##
## Between the macro layer (RoomModule — which rooms exist and how they join) and the micro layer
## (RoomDresser — which mesh, which colour) there was nothing. RoomPlan built a 3 m lattice of
## candidate points, subtracted the door lanes, and drew cover positions from it at random. That is
## why every room read the same: the arrangement carried no information, so the only thing a player
## could tell about a room was its outline.
##
## This is the layer that was missing. It works on the room's own 4 m tile grid, it is told what the
## room is FOR (RoomProgram), and it places cover, focal points and LIGHT MOUNTS as one composition.
## Lights especially: a candelabra spaced evenly round a perimeter is furniture, a row of them down
## the middle of a hall is an aisle, and the second one tells you what the room was.
##
## HOW THIS RELATES TO WAVE FUNCTION COLLAPSE — stated plainly, because the resemblance is real but
## partial and the difference matters for reproducibility.
##
## Taken from WFC: a small alphabet of cell states, LOCAL ADJACENCY RULES that decide which states
## may sit beside which, cells pre-collapsed before anything else runs (the aisle, the door lanes),
## and the constraint that a placement is legal only if its neighbourhood permits it.
##
## NOT taken from WFC: min-entropy collapse ordering, and with it the backtracker. Two reasons, both
## specific to this codebase rather than to the technique.
##
##   1. EDIT LOCALITY. docs/directed-proceduralism.md §4 states the law this project generates
##      under: randomness must be keyed to WHERE a decision applies, never to WHEN it is made.
##      Min-entropy ordering is definitionally the second — a tile's outcome depends on which tiles
##      collapsed before it — so adding one door to a room would re-roll its whole interior. That is
##      the slot-machine failure the doc names, and the same class of bug as the Array.shuffle()
##      regression recorded at room_plan.gd:185. Here EVERY tile draws from
##      `ctx.roll_for(seed, key, tile_centre)`. The scan order decides only what is LEGAL; the
##      position decides what is CHOSEN.
##   2. CONTRADICTIONS CANNOT HAPPEN. OPEN is compatible with everything, so any partial assignment
##      extends to a total one and no cell's domain can ever empty. A backtracker here would be code
##      that never runs — worse than absent, because the day it did run it would silently change the
##      seed-to-dungeon mapping that the printed seed promises.
##
## WHY THIS LAYER IS SAFE, which is the other half of why it is worth doing here rather than on the
## room's silhouette. Every piece it places is SUB-TILE: cover is 1 m inside a 4 m tile, so two
## pieces in adjacent tiles stand 4 m apart. It cannot disconnect a room, cannot trap an enemy in a
## concave pocket (which matters — this project has NO NAVMESH and enemies chase directly), and
## cannot change the floor outline the map measures from collision. The failure modes that make
## carving the silhouette dangerous simply do not exist down here.

## Cell states. OUTSIDE is not a choice — it is where the room has no floor.
enum Cell { OUTSIDE, AISLE, OPEN, LARGE, SMALL, MOUNT, FOCAL }

## Sub-tile footprints, matching what RoomPlan already promises the dresser.
const LARGE_SIZE := Vector2(1.0, 1.0)
const SMALL_SIZE := Vector2(1.0, 1.0)
const FOCAL_SIZE := Vector2(2.4, 2.4)
## A free-standing candelabra claims a little floor so nothing spawns inside it. Wall-mounted ones
## claim none, because they are against the wall and out of the way.
const MOUNT_SIZE := Vector2(0.8, 0.8)
## How far a wall mount steps in off the boundary. Enough to clear the 0.5 m wall piece it hangs on
## and to land inside the tile, so `RoomShape.contains` agrees the mount is in the room.
const MOUNT_INSET := 0.9

## Clearance every light mount keeps from a doorway. verify_dungeon asserts this for rooms with two
## exits or fewer (RoomDresser.MOUNT_DOOR_CLEARANCE); honoured everywhere because a torch standing
## in a passage looks like a mistake whether or not a test can prove it.
const DOOR_CLEARANCE := 3.2
## Cover keeps further back still: _plan_suite rejects any footprinted slot within 4 m of a door.
const COVER_CLEARANCE := 4.2

## Shortest gallery worth building: a ramp at each end and at least two tiles of deck between them.
const MIN_GALLERY := 4


## Furnish one room. Returns the free tile centres left over, so the encounter pass can place
## enemies against what the composition actually left — the same contract the old lattice had.
static func weave(rd: DungeonLayout.RoomData, ctx: RoomContext) -> Array[Vector3]:
	var shape := ctx.shape
	# WHAT THE ROOM SETTLED ON, not what the layout proposed. TileProgram may have demoted it at step
	# 3 because the shape could not host the zone that defined it, and the cover pattern and the
	# lighting must follow the room that exists rather than the one that was asked for.
	var prog: String = ctx.program if ctx.program != "" else RoomProgram.for_room(rd)
	var rules := RoomProgram.rules(prog)
	ctx.program = prog

	var field := _seed_field(rd, ctx)
	var long_axis := _long_axis(shape)

	match rules["cover"]:
		RoomProgram.P_FLANK:
			_flank(ctx, field, long_axis, rules)
		RoomProgram.P_COLONNADE:
			_colonnade(ctx, field, long_axis, rules)
		RoomProgram.P_CORNERS:
			_corners(ctx, field, rules)
		RoomProgram.P_RING:
			_ring(ctx, field, rules)
		RoomProgram.P_SCATTER:
			_scatter(ctx, field, rules)
		_:
			pass

	_mounts(rd, ctx, field, long_axis, rules)
	return _free_spots(ctx, field)


## Is this stretch of a row free of doorways? Both axes matter: a door in the row's own band that
## also falls inside the run's X extent is an exit the gallery would build over — an opening at
## y = 0 behind a retaining wall, which nothing downstream would notice because a doorway that leads
## nowhere still builds and still measures.
static func run_clear(rd: DungeonLayout.RoomData, ctx: RoomContext,
		row: int, from_i: int, to_i: int) -> bool:
	var shape := ctx.shape
	var z0: float = shape.tile_centre(Vector2i(from_i, row)).z - RoomShape.TILE * 0.5
	var z1: float = z0 + RoomShape.TILE
	var x0: float = shape.tile_centre(Vector2i(from_i, row)).x - RoomShape.TILE * 0.5
	var x1: float = shape.tile_centre(Vector2i(to_i, row)).x + RoomShape.TILE * 0.5
	for e: DungeonLayout.Edge in rd.edges:
		if e.dir.x == 0 and e.dir.z == 0:
			continue
		var door := DungeonLayout.door_local(rd, e)
		if door.z > z0 - 0.01 and door.z < z1 + 0.01 				and door.x > x0 - 0.01 and door.x < x1 + 0.01:
			return false
	return true


# ---------------------------------------------------------------- the field ------------------

## Pre-collapse the cells nothing may occupy, before any rule runs. This is the WFC move that
## matters most here: the circulation is decided FIRST and everything else is placed around it,
## rather than placed freely and then checked for having blocked a door.
##
## The AISLE is the room's spine along its long axis plus every door's approach lane. Keeping it
## clear is what makes a flanked room read as having a middle to walk down, and it is also what
## guarantees the composition can never wall a doorway off.
static func _seed_field(rd: DungeonLayout.RoomData, ctx: RoomContext) -> Dictionary:
	var shape := ctx.shape
	var field := {}
	for j in shape.rows:
		for i in shape.cols:
			var t := Vector2i(i, j)
			field[t] = Cell.OPEN if shape.is_solid(t) else Cell.OUTSIDE

	# the spine
	var axis := _long_axis(shape)
	var mid_col := (shape.cols - 1) / 2
	var mid_row := (shape.rows - 1) / 2
	for j in shape.rows:
		for i in shape.cols:
			var t := Vector2i(i, j)
			if field.get(t) != Cell.OPEN:
				continue
			if (axis == Vector2i(1, 0) and j == mid_row) or (axis == Vector2i(0, 1) and i == mid_col):
				field[t] = Cell.AISLE

	# A SIGHTLINE RELATION'S OWN TILES. The spine above is aimed by the room's long axis, which is a
	# guess about what the room is for; this is aimed by the program, which knows. On a church it is
	# the column running back from the apse, and it is what stops the cover pass filling the middle
	# of the nave with the very thing you are meant to be looking past.
	for t: Vector2i in ctx.sightline:
		if field.get(t) == Cell.OPEN:
			field[t] = Cell.AISLE

	# every door's approach
	for e: DungeonLayout.Edge in rd.edges:
		if e.dir.x == 0 and e.dir.z == 0:
			continue
		var door := DungeonLayout.door_local(rd, e)
		var c := shape.col_at(door.x)
		var r := shape.row_at(door.z)
		for j in shape.rows:
			for i in shape.cols:
				var t := Vector2i(i, j)
				if field.get(t) != Cell.OPEN:
					continue
				if (e.dir.x != 0 and j == r) or (e.dir.z != 0 and i == c):
					field[t] = Cell.AISLE
	return field


## The axis a room is longer on, which every linear pattern runs along. Square rooms take X, so a
## 2x2 hall still gets a definite aisle rather than an arbitrary one.
static func _long_axis(shape: RoomShape) -> Vector2i:
	return Vector2i(0, 1) if shape.rows > shape.cols else Vector2i(1, 0)


# ---------------------------------------------------------------- the patterns ---------------

## THE REFECTORY. Two rows either side of the aisle, on a regular period, with the heavier pieces at
## the ends of the run. The regularity is the whole point: scattered cover reads as debris, a row
## reads as furniture that someone put there.
static func _flank(ctx: RoomContext, field: Dictionary, axis: Vector2i,
		rules: Dictionary) -> void:
	var shape := ctx.shape
	var along := shape.cols if axis == Vector2i(1, 0) else shape.rows
	for j in shape.rows:
		for i in shape.cols:
			var t := Vector2i(i, j)
			if not _placeable(ctx, field, t):
				continue
			# one tile off the aisle, on either side
			if not _touches(field, t, Cell.AISLE):
				continue
			var step := i if axis == Vector2i(1, 0) else j
			if step % 2 == 1:
				continue                       # the period: every other bay, so it reads as rhythm
			var big := step == 0 or step == along - 1
			_place(ctx, field, t, big, rules)


## THE GALLERY. Pillars on a fixed period down both sides of the run, and nothing else — a colonnade
## is defined by what is NOT between the columns.
static func _colonnade(ctx: RoomContext, field: Dictionary, axis: Vector2i,
		rules: Dictionary) -> void:
	var shape := ctx.shape
	for j in shape.rows:
		for i in shape.cols:
			var t := Vector2i(i, j)
			if not _placeable(ctx, field, t):
				continue
			if not _touches(field, t, Cell.AISLE):
				continue
			var step := i if axis == Vector2i(1, 0) else j
			if step % 2 == 1:
				continue
			_place(ctx, field, t, true, rules)


## THE ARENA. Corners only, middle untouched — the boss needs an open floor for its area attack and
## RoomPlan has always pinned its pillars for exactly that reason. Kept as a program so the intent
## is stated once, in the same vocabulary as everything else.
static func _corners(ctx: RoomContext, field: Dictionary, rules: Dictionary) -> void:
	var shape := ctx.shape
	for j: int in [0, shape.rows - 1]:
		for i: int in [0, shape.cols - 1]:
			var t := Vector2i(i, j)
			if _placeable(ctx, field, t):
				_place(ctx, field, t, true, rules)


## THE TREASURY. A ring one tile out from the centre, around whatever the room is about. The middle
## itself is left to the focal piece RoomPlan places.
static func _ring(ctx: RoomContext, field: Dictionary, rules: Dictionary) -> void:
	var shape := ctx.shape
	var c := Vector2i((shape.cols - 1) / 2, (shape.rows - 1) / 2)
	for dj: int in [-2, -1, 0, 1, 2]:
		for di: int in [-2, -1, 0, 1, 2]:
			if maxi(absi(di), absi(dj)) != 2:
				continue                       # the ring, not the disc
			var t := c + Vector2i(di, dj)
			if not _placeable(ctx, field, t):
				continue
			if _roll(ctx, "ring", shape, t) > 0.7:
				continue                       # a gap or two, so it reads as placed not stamped
			_place(ctx, field, t, absi(di) == absi(dj), rules)


## The old behaviour, kept for rooms with no story to tell — but on the tile grid, with the aisle
## respected, so even a plain chamber no longer puts a crate in a doorway lane.
static func _scatter(ctx: RoomContext, field: Dictionary, rules: Dictionary) -> void:
	var shape := ctx.shape
	for j in shape.rows:
		for i in shape.cols:
			var t := Vector2i(i, j)
			if not _placeable(ctx, field, t):
				continue
			if _roll(ctx, "scatter", shape, t) > float(rules["density"]):
				continue
			# ADJACENCY: never two heavy pieces side by side. A pair of pillars 4 m apart reads as a
			# gate the player must choose a side of, which is a statement this program is not making.
			if _touches(field, t, Cell.LARGE):
				_place(ctx, field, t, false, rules)
			else:
				_place(ctx, field, t, _roll(ctx, "big", shape, t) < float(rules["large"]), rules)


# ---------------------------------------------------------------- the lights -----------------

## WHERE THE LIGHT GOES, which is the half of this that changes how a room reads most.
##
## RoomDresser will skip its own perimeter spacing entirely once the plan supplies any T_WALL_ANCHOR
## slot (room_dresser.gd:105), so from here on this function owns the room's sconces. That makes two
## things non-negotiable and both are asserted by verify_dungeon: at least two mounts per room, and
## every mount clear of the doorways.
static func _mounts(rd: DungeonLayout.RoomData, ctx: RoomContext, field: Dictionary,
		axis: Vector2i, rules: Dictionary) -> void:
	var shape := ctx.shape
	# SCALE THE COUNT WITH THE ROOM. The per-program numbers were chosen against a single cell
	# (20 x 12); a great hall is 68 x 28 — eight times the floor — and four candelabra at 14 m range
	# left most of it black. Square-root scaling, the same curve RoomPlan._scaled uses for props and
	# enemies, because light falls off with distance rather than with area.
	#
	# CAPPED, and the cap is not arbitrary: a candelabra casts shadows, and
	# environment-pipeline-todo.md 3 measures nine casting omnis at 2.07 ms — the largest single line
	# item in the frame. Only one room is lit at a time (show_around + set_lit), so this is a
	# per-visible-room cost, but it is the number to look at first if the crypt ever gets slower.
	var area := ctx.footprint.x * ctx.footprint.z
	var scale := sqrt(area / (DungeonLayout.ROOM_SIZE.x * DungeonLayout.ROOM_SIZE.z))
	# The cap is a SHADOW-CASTER budget, not a taste one: every candelabra casts, and
	# docs/environment-pipeline-todo.md 3 measures nine casting omnis at 2.07 ms, the largest single
	# line item in the frame. It is affordable at twelve because set_lit(false) takes every room but
	# the one the player stands in out of the shadow pass, and only one room can be a great hall.
	var want: int = clampi(int(round(int(rules["lights"]) * scale)), RoomProgram.MIN_LIGHTS, 12)
	var placed := 0

	match rules["light"]:
		RoomProgram.L_AISLE:
			# Down the middle, between the rows. This is the one that says "hall".
			#
			# SPREAD ACROSS THE RUN, not the first N bays of it. Taking bays 1, 3, 5, 7 of a
			# seventeen-tile aisle lights the near third of a sixty-eight metre hall and leaves the
			# rest dark — which reads as an unfinished room rather than as a processional way. Each
			# lamp takes the centre of its own equal share of the run, so four lamps in a long
			# gallery and four in a square hall are both evenly spaced.
			var cells := _aisle_run(field, shape, axis)
			var n := mini(want, cells.size())
			for k in n:
				var t: Vector2i = cells[int((k + 0.5) * cells.size() / n)]
				var at: Vector3 = shape.tile_centre(t)
				if _door_clear(ctx, at, DOOR_CLEARANCE) and ctx.is_free(at, MOUNT_SIZE):
					ctx.add_slot_at(RoomPlan.T_WALL_ANCHOR, at, MOUNT_SIZE)
					field[t] = Cell.MOUNT
					placed += 1
		RoomProgram.L_FOCAL:
			placed += _mount_ring(ctx, field, want)
		RoomProgram.L_DOORS:
			placed += _mount_walls(rd, ctx, want, true)
		_:
			placed += _mount_walls(rd, ctx, want, false)

	# THE FLOOR, and it is not optional. If a program's own rule could not seat two mounts — a tiny
	# room whose aisle is three tiles of door lane, a stairwell — fall back to the walls, and if even
	# that fails, hand the room back to RoomDresser by emitting nothing at all rather than leaving it
	# with one light and a failing suite.
	if placed < RoomProgram.MIN_LIGHTS:
		placed += _mount_walls(rd, ctx, RoomProgram.MIN_LIGHTS - placed, false)
	if placed < RoomProgram.MIN_LIGHTS:
		_drop_mounts(ctx)


## Wall segments, taken from the shape itself rather than from an inset ring around the bounding
## box. A carved room's bounding box runs through thin air where a corner was bitten out; its wall
## list never does.
static func _mount_walls(rd: DungeonLayout.RoomData, ctx: RoomContext, want: int,
		near_doors: bool) -> int:
	var usable: Array = []
	for w: Dictionary in ctx.shape.walls():
		# NORMALISED. A diagonal Vector2i has length sqrt(2), so on a bevelled corner the unnormalised
		# vector stepped 1.27 m in rather than 0.9 and the sconce floated off the wall it belongs to.
		# RoomDresser._clutter_spots carries the same fix and the same explanation; this call site was
		# missed when that one was made.
		var nrm := Vector3(w.out.x, 0.0, w.out.y).normalized()
		# A SCONCE GOES ON A BAY, NOT ON A RUN. Identical today, when every run is one module — but a
		# run spanning four tiles would otherwise offer one candidate where the wall has room for
		# four, and a room short of candidates does not look dim, it calls _drop_mounts and hands its
		# lighting to the dresser's perimeter ring with nothing reporting the substitution.
		for bay: Vector3 in RoomShape.wall_bays(w):
			# STEP IN OFF THE WALL LINE. `walls()` returns the boundary itself, which is where the
			# wall PIECE goes — a mount left there is half inside 0.5 m of masonry, and
			# `shape.contains` says it is over a hole, because a point exactly on the boundary floors
			# into the tile outside. The dresser's own perimeter pass insets for the same reason
			# (RoomDresser.MOUNT_INSET).
			var at: Vector3 = bay - nrm * MOUNT_INSET
			if not _door_clear(ctx, at, DOOR_CLEARANCE) or not ctx.shape.contains(at):
				continue
			usable.append({"at": at, "yaw": w.yaw})
	if usable.is_empty():
		return 0
	# Ordered by distance from the doors rather than by the order walls() happened to emit them, so
	# which segments carry a sconce is a property of WHERE they are and stays put when the room
	# changes elsewhere.
	usable.sort_custom(func(a, b):
		return _wall_key(ctx, a, near_doors) < _wall_key(ctx, b, near_doors))
	var n := mini(want, usable.size())
	var placed := 0
	for k in n:
		# Spread across the whole list rather than taking the first n, which would cluster them.
		var w: Dictionary = usable[k * usable.size() / n]
		ctx.add_slot_at(RoomPlan.T_WALL_ANCHOR, w.at, Vector2.ZERO, w.yaw)
		placed += 1
	return placed


## A threshold wants its light BY the way in; everything else wants it as far from the doors as it
## can get. Same list, opposite sort.
static func _wall_key(ctx: RoomContext, w: Dictionary, near_doors: bool) -> float:
	var d := door_distance(ctx, w.at)
	return d if near_doors else -d


static func _mount_ring(ctx: RoomContext, field: Dictionary, want: int) -> int:
	var shape := ctx.shape
	var c := Vector2i((shape.cols - 1) / 2, (shape.rows - 1) / 2)
	var placed := 0
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		if placed >= want:
			break
		var t := c + corner
		if field.get(t, Cell.OUTSIDE) != Cell.OPEN:
			continue
		var at := shape.tile_centre(t)
		if not _door_clear(ctx, at, DOOR_CLEARANCE) or not ctx.is_free(at, MOUNT_SIZE):
			continue
		ctx.add_slot_at(RoomPlan.T_WALL_ANCHOR, at, MOUNT_SIZE)
		field[t] = Cell.MOUNT
		placed += 1
	return placed


## Remove every mount this pass added, so RoomDresser's own spacing takes over. Emitting ONE anchor
## is the worst possible outcome: it suppresses the dresser's fallback (which triggers on "any
## anchor at all") and leaves the room below the two-light floor.
static func _drop_mounts(ctx: RoomContext) -> void:
	var keep: Array[RoomContext.Slot] = []
	for s: RoomContext.Slot in ctx.slots:
		if s.tag != RoomPlan.T_WALL_ANCHOR:
			keep.append(s)
	ctx.slots = keep


## The aisle tiles in run order, so lights along it come out evenly spaced rather than in the order
## a nested loop happened to visit them.
static func _aisle_run(field: Dictionary, shape: RoomShape, axis: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var mid_col := (shape.cols - 1) / 2
	var mid_row := (shape.rows - 1) / 2
	if axis == Vector2i(1, 0):
		for i in shape.cols:
			var t := Vector2i(i, mid_row)
			if field.get(t, Cell.OUTSIDE) == Cell.AISLE:
				out.append(t)
	else:
		for j in shape.rows:
			var t := Vector2i(mid_col, j)
			if field.get(t, Cell.OUTSIDE) == Cell.AISLE:
				out.append(t)
	return out


# ---------------------------------------------------------------- primitives -----------------

## May something stand on this tile? The adjacency check every pattern shares: real floor, not the
## circulation, not already taken, and far enough from a door that the piece cannot read as blocking
## it. `ctx.is_free` is the authority on the last part because earlier passes — the key, a template
## — have already claimed floor this function knows nothing about.
static func _placeable(ctx: RoomContext, field: Dictionary, t: Vector2i) -> bool:
	if field.get(t, Cell.OUTSIDE) != Cell.OPEN:
		return false
	var at := ctx.shape.tile_centre(t)
	if not _door_clear(ctx, at, COVER_CLEARANCE):
		return false
	# whole-box, so a piece on an edge tile cannot overhang a carved corner
	return ctx.shape.contains_box(at, LARGE_SIZE) and ctx.is_free(at, LARGE_SIZE)


static func _place(ctx: RoomContext, field: Dictionary, t: Vector2i, big: bool,
		rules: Dictionary) -> void:
	var at := ctx.shape.tile_centre(t)
	# JITTER, keyed to the tile. A perfectly regular grid of pillars reads as a tech demo; a row
	# that wanders by a few centimetres reads as masonry. Small enough that the rhythm survives.
	var jx := (_roll(ctx, "jx", ctx.shape, t) - 0.5) * 0.9
	var jz := (_roll(ctx, "jz", ctx.shape, t) - 0.5) * 0.9
	var jittered := at + Vector3(jx, 0.0, jz)
	if not ctx.shape.contains_box(jittered, LARGE_SIZE) or not ctx.is_free(jittered, LARGE_SIZE) \
			or not _door_clear(ctx, jittered, COVER_CLEARANCE):
		jittered = at                          # the jitter is a nicety, never a reason to fail
	ctx.add_slot_at(RoomPlan.T_COVER_LARGE if big else RoomPlan.T_COVER_SMALL, jittered,
			LARGE_SIZE if big else SMALL_SIZE)
	if big:
		# THE COLUMN'S UPPER HALF, on the same spot and one course up. Paired here rather than in a
		# later pass so the two can never disagree about where the column is, and zero-footprint so
		# the drum below keeps sole ownership of the floor.
		ctx.add_slot_at(RoomPlan.T_COVER_UPPER, jittered + Vector3(0.0, DungeonLayout.COURSE_H, 0.0))
	field[t] = Cell.LARGE if big else Cell.SMALL


## Is any 4-neighbour of `t` in state `what`? The local rule the patterns are built out of.
static func _touches(field: Dictionary, t: Vector2i, what: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if field.get(t + d, Cell.OUTSIDE) == what:
			return true
	return false


## Distance from the nearest doorway, in the room's own local space.
static func door_distance(ctx: RoomContext, at: Vector3) -> float:
	var best := INF
	for e: DungeonLayout.Edge in ctx.rd.edges:
		if e.dir.x == 0 and e.dir.z == 0:
			continue
		var door := DungeonLayout.door_local(ctx.rd, e)
		best = minf(best, Vector2(at.x - door.x, at.z - door.z).length())
	return best


static func _door_clear(ctx: RoomContext, at: Vector3, margin: float) -> bool:
	return door_distance(ctx, at) >= margin


## Every draw in this file. Keyed to the TILE, never to a counter or an iteration index — see the
## edit-locality note in the header. Two rooms that differ only in a far-away door produce identical
## furniture everywhere the door did not reach.
static func _roll(ctx: RoomContext, key: String, shape: RoomShape, t: Vector2i) -> float:
	return ctx.variant_roll("weave_" + key, shape.tile_centre(t))


## Tile centres nothing was placed on, for the encounter pass. Door lanes are excluded because an
## enemy standing in a doorway is an enemy the player fights through a wall.
static func _free_spots(ctx: RoomContext, field: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for key in field:
		var t: Vector2i = key
		if field[t] != Cell.OPEN:
			continue
		var at := ctx.shape.tile_centre(t)
		if ctx.in_door_lane(at) or ctx.near_door(at, 4.0):
			continue
		if ctx.is_free(at, LARGE_SIZE):
			out.append(at)
	return out

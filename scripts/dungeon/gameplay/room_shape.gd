@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomShape
extends RefCounted
## The FOOTPRINT of a room, as a grid of 4 m tiles — this is what stops every room being the same
## rectangle. Gameplay, not decoration: the silhouette decides where you can be shot from, where
## an archer can hide, and how a room reads the moment you step in.
##
## The tile grid is sized from the room's interior, so a hall is the same code as a closet. Walls
## are emitted along every boundary between an active tile and a hole or the outside, so carving
## tiles produces real geometry with no special cases.
##
## CARVING RULE: bites are RECTANGLES anchored at the four corners, never deeper than half the
## grid, so the middle column and row (the "cross") always survive. Two things fall out of that
## for free:
##   - CONNECTIVITY — every remaining tile reaches the cross, so any combination of bites leaves
##     one connected piece. No flood fill, no rejected shapes.
##   - DOOR COMPATIBILITY — protected lines (below) are restored after carving, and every line
##     crosses the cross, so a doorway is always reachable however the room was carved.

const TILE := 4.0

## HOW FAR BACK A CHAMFER CUTS along each of the corner's two walls. 2 m is not a look — it is the
## only value that keeps every resulting run a whole module: the corner's two 4 m walls become one
## 2.83 m diagonal (2 * sqrt(2)) plus a 2 m remainder each. Cut the FULL leg instead and the diagonal
## is 5.66 m, longer than any course module in the kit and unbuildable from it.
const CHAMFER_LEG := 2.0

## The diagonal that replaces them: CHAMFER_LEG * sqrt(2). WRITTEN OUT rather than computed because
## Kit.SIZES is a const Dictionary and GDScript will not fold a call inside one, and Kit is the place
## the number has to be exact — it is what the collider is built from. verify_dungeon asserts this
## literal against the arithmetic, so the two cannot drift.
const CHAMFER_DIAG := 2.8284271247461903

## HOW HIGH ONE LEVEL IS. Elevation is a property of the TILE, not a structure standing on it — a
## raised floor is floor, and the wall that holds it up is a wall. Before this, a platform had to be
## smuggled in after the shape was decided, which meant every kind of level change was its own
## mechanism re-solving the same problems: what the map thinks it is, what can stand on it, how
## anything gets up. A level per tile answers all three once.
##
## 1.2 m, and the number is set by what the CAMERA can see past, not by what reads as a storey.
## At the fixed 53-degree pitch a parapet hides rise/tan(53) of the deck behind it: at 1.8 m that was
## 1.35 m of a 4 m walkway, so a body standing anywhere in the front third of it was occluded to the
## head — a third of a space the player is meant to fight from where you could stand and not be seen.
## 1.2 m hides 0.90 m, still needs a flight, and still reads as a storey.
const LEVEL_RISE := 1.2


var cols := 5
var rows := 3
## Vector3i(x, LEVEL, z) -> true for every active tile. THE KEY CARRIES THE HEIGHT, so "this tile is
## at level 2" and "a tile exists at (x, 2, z)" are one statement rather than two that can disagree.
##
## They could disagree before. `_solid` said there was floor at an XZ and a parallel `_level` said how
## high it was, and nothing tied them together: a level could be set on a tile that had been carved
## away, or survive a tile being erased, and the room would build from a height nothing stood at. It
## did not happen — carving runs before levels, always — but "the order the passes happen to run in"
## is not a guarantee, it is a coincidence that holds until someone reorders two calls.
##
## WHAT THIS DOES NOT YET DO is let two tiles share a column. That is the point of the re-key and it
## is M7's to spend: an undercroft, a bridge, a gallery you walk under, an arcade that is a real
## opening rather than a recessed panel. Until a pass exists that can build the second storey AND a
## camera rule that can clear it, one tile per column is asserted rather than assumed — see
## `_column`, and verify_dungeon, which checks the two agree on every room it builds.
var _solid: Dictionary = {}
## Vector2i(x, z) -> level. A pure INDEX over `_solid`, never authored: every mutation goes through
## _set_tile/_erase_tile and rebuilds it, so it cannot drift the way `_level` could.
##
## It exists because the questions this shape is ASKED are two-dimensional. "Is there floor here",
## "how high is it", "what is the aisle" — around fifty call sites, and every one is about the room's
## plan. Answering them by scanning the 3-D keys would be O(levels) per query inside nested loops for
## no gain while `levels` is 1. It is also what preserves iteration order across the re-key: `_solid`
## re-keys when a level is set, which moves that entry to the end of its dictionary, while `_column`
## is only ever value-updated and stays where the carve put it.
var _column: Dictionary = {}
## Vector2i -> the outward diagonal of the corner that has been bevelled off it, e.g. (1, 1) for the
## +X/+Z corner. Only ever set on a tile whose two named sides are both open.
var _chamfer: Dictionary = {}
## Vector2i -> Vector2i, the direction a tile RAMPS in. A ramp tile sits at the LOWER level, its
## floor is a flight rather than a slab, and the level boundary it climbs carries no riser — which is
## the whole of "how do you get up there", expressed on the tile like everything else here.
var _ramp: Dictionary = {}


static func full(cols_ := 5, rows_ := 3) -> RoomShape:
	var s := RoomShape.new()
	s.cols = cols_
	s.rows = rows_
	for i in cols_:
		for j in rows_:
			s._set_tile(Vector2i(i, j), 0)
	return s


## Tile grid for a room's interior. Both quotients are odd by construction of CELL_PITCH, so the
## middle column and row always exist.
static func for_room(rd: DungeonLayout.RoomData) -> RoomShape:
	var size := DungeonLayout.size_of(rd)
	return full(int(round(size.x / TILE)), int(round(size.z / TILE)))


## Choose a footprint. Boss and treasure rooms stay full rectangles on purpose — the boss needs an
## open arena for its area attack, and the treasure room is a held beat, not a puzzle.
## `protect_cols` / `protect_rows` are tile lines that must stay solid because a doorway opens on
## them; they are restored after carving.
static func pick(rd: DungeonLayout.RoomData, rng: RandomNumberGenerator,
		protect_cols: Array = [], protect_rows: Array = []) -> RoomShape:
	var s := for_room(rd)
	# A handcrafted interior was authored against the full rectangle, so carving under it would
	# leave props hanging over nothing.
	if rd.template_path != "":
		return s
	match rd.type:
		DungeonLayout.RoomType.BOSS, DungeonLayout.RoomType.TREASURE, \
		DungeonLayout.RoomType.START, DungeonLayout.RoomType.STAIR:
			return s

	var max_w := (s.cols - 1) / 2
	var max_h := (s.rows - 1) / 2
	if max_w < 1 or max_h < 1:
		return s

	# Most fight rooms get carved — a plain rectangle should be the exception. Still weighted
	# toward simpler silhouettes: a dungeon of nothing but plus-shapes is as monotonous as a
	# dungeon of nothing but boxes.
	var roll := rng.randf()
	var bites := 0
	if roll > 0.12:
		bites = 1
	if roll > 0.45:
		bites = 2
	if roll > 0.72:
		bites = 3
	if roll > 0.90:
		bites = 4

	var corners: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	for b in bites:
		var corner: Vector2i = corners.pop_at(rng.randi_range(0, corners.size() - 1))
		var w := rng.randi_range(1, max_w)
		var h := rng.randi_range(1, max_h)
		for dx in w:
			for dz in h:
				var i := (s.cols - 1 - dx) if corner.x == 1 else dx
				var j := (s.rows - 1 - dz) if corner.y == 1 else dz
				s._erase_tile(Vector2i(i, j))

	for c in protect_cols:
		for j in s.rows:
			s._set_tile(Vector2i(c, j), 0)
	for r in protect_rows:
		for i in s.cols:
			s._set_tile(Vector2i(i, r), 0)
	return s


## THE ONLY TWO PLACES `_solid` AND `_column` MOVE, which is what makes the index safe to have. A
## caller that could write one without the other would be back to the two-table problem the 3-D key
## exists to end.
func _set_tile(tile: Vector2i, storey: int) -> void:
	if _column.has(tile):
		_solid.erase(Vector3i(tile.x, int(_column[tile]), tile.y))
	_solid[Vector3i(tile.x, storey, tile.y)] = true
	# ASSIGNED, not erased-and-reinserted, so the column keeps its position in the dictionary. Tile
	# order is what walls() emits in and what the dresser therefore builds in, and a piece built in a
	# different order draws a different positional roll.
	_column[tile] = storey


func _erase_tile(tile: Vector2i) -> void:
	if not _column.has(tile):
		return
	_solid.erase(Vector3i(tile.x, int(_column[tile]), tile.y))
	_column.erase(tile)


## THE PUBLIC CARVE, for the Forge's sculpt mode. A thin gate over _erase_tile that refuses
## what would corrupt the shape's own bookkeeping — a frozen grid, a tile a fixture stands on,
## the last tile — and NOTHING more: connectivity, camera and reachability are the caller's to
## assemble from the public validators (walkable, regions, camera_legal), never restated here.
func carve(tile: Vector2i) -> bool:
	if _frozen:
		push_error("RoomShape.carve(%s) after the occupancy grid was baked" % tile)
		return false
	if not _column.has(tile) or _claimed.has(tile) or _column.size() <= 1:
		return false
	_erase_tile(tile)
	return true


## The public FILL: put floor at `tile` on `storey`. Bounds-checked (the grid does not grow),
## and a sunken storey routes through set_level so the outline-pit refusal stays in its one
## home — the tile is laid at 0 first and taken back out if the sink is refused.
func fill(tile: Vector2i, storey := 0) -> bool:
	if _frozen:
		push_error("RoomShape.fill(%s) after the occupancy grid was baked" % tile)
		return false
	if tile.x < 0 or tile.x >= cols or tile.y < 0 or tile.y >= rows:
		return false
	if _claimed.has(tile):
		return false
	if storey >= 0:
		_set_tile(tile, storey)
		return true
	var was_solid := _column.has(tile)
	var was_level := level_of(tile)
	if not was_solid:
		_set_tile(tile, 0)
	set_level(tile, storey)                   # refuses outline pits; detect by re-read
	if level_of(tile) == storey:
		return true
	if was_solid:
		_set_tile(tile, was_level)
	else:
		_erase_tile(tile)
	return false


func is_solid(tile: Vector2i) -> bool:
	return _column.has(tile)


## The COLUMNS, as Vector2i, because that is what every caller wants — see `_column`. `cells()` is
## the three-dimensional view of the same thing.
func tiles() -> Array:
	return _column.keys()


## Every tile as the grid actually stores it, height included. Nothing needs this yet; it is the
## handle M7's regions and storeys reach for, and it is here so `_solid` is never read directly from
## outside and the invariant below stays enforceable.
func cells() -> Array:
	return _solid.keys()


func tile_count() -> int:
	return _column.size()


func level_of(tile: Vector2i) -> int:
	return int(_column.get(tile, 0))


## Move a tile to another storey. A LEVEL ON A TILE THAT IS NOT THERE is now impossible rather than
## merely unheard-of: there is nowhere to put it.
func set_level(tile: Vector2i, storey: int) -> void:
	if not _column.has(tile):
		push_error("RoomShape.set_level on %s, which has no floor" % tile)
		return
	# A SUNKEN TILE MAY NOT TOUCH THE ROOM'S OUTLINE, and this is a hard refusal rather than a rule
	# somebody remembers. walls() pins the shell at y = 0 — correctly, because that is what encloses
	# the void UNDER a raised perimeter tile — so a pit on the boundary gets a shell wall starting at
	# 0 and nothing at all between -1.2 and 0. That is a slot you see out of the level through, and
	# from the fixed camera it is a hole in the world at eye height. A `skirt` role that drops the
	# shell to the pit's own floor is the fix; until it exists, the case is refused.
	if storey < 0 and on_outline(tile):
		push_error("RoomShape.set_level: %s is on the outline and cannot be sunk — the shell wall "
				% tile + "starts at y = 0 and would leave a slot you can see out of the level")
		return
	_set_tile(tile, storey)


## THE STEEPEST A RAMP MAY BE. Nothing in this project has step logic — the player and every enemy
## are move_and_slide plus gravity — so the only thing that decides whether a slope is climbable is
## CharacterBody3D's floor_max_angle, which defaults to 45 degrees. 35 keeps the same margin under it
## that Kit.dais's shipped 36.9 already proves a body can walk up, and leaves room for the collider
## to be a chord across a stepped visual rather than lying exactly on it.
##
## What it actually decides is HOW MANY LEVELS A GIVEN LENGTH MAY CLIMB: one tile of run is 4 m, and
## 4 * tan(35) = 2.80 m, which is two 1.2 m levels with room to spare and not three. So a ramp that
## wants to climb further gets LONGER rather than steeper — refusing is the last resort, not the
## first.
const MAX_SLOPE := deg_to_rad(35.0)


## A ramp, as a fixture spanning `tiles` in `dir` and climbing `rise` levels from `level`.
##
## Returns false and builds nothing if the block is not free floor or the slope would be illegal —
## the caller is expected to have lengthened it first. Every ramp in the dungeon today is the 1x1
## rise-1 case that set_ramp installs, and that case is byte-identical to the side table this
## replaces.
func add_ramp(anchor: Vector2i, dir: Vector2i, tiles := 1, rise := 1) -> bool:
	if dir == Vector2i.ZERO or (dir.x != 0 and dir.y != 0):
		push_error("RoomShape.add_ramp: %s is not one of the four axes" % dir)
		return false
	var run := float(maxi(tiles, 1)) * TILE
	var climb := float(maxi(rise, 1)) * LEVEL_RISE
	if atan2(climb, run) > MAX_SLOPE:
		push_error("RoomShape.add_ramp: %.1f m over %.1f m is %.1f degrees, past the %.1f a body "
				% [climb, run, rad_to_deg(atan2(climb, run)), rad_to_deg(MAX_SLOPE)]
				+ "can walk — make it longer")
		return false
	var f := Fixture.new()
	f.kind = "ramp"
	# THE BLOCK IS AXIS-ALIGNED AND ANCHORED AT ITS -x/-z CORNER, whichever way the ramp climbs. A
	# ramp running toward -z from `anchor` occupies the tiles BEHIND it, so the anchor moves.
	var far := anchor + dir * (maxi(tiles, 1) - 1)
	f.anchor = Vector2i(mini(anchor.x, far.x), mini(anchor.y, far.y))
	f.span = Vector2i(absi(far.x - anchor.x) + 1, absi(far.y - anchor.y) + 1)
	f.dir = dir
	f.level = level_of(anchor)
	f.rise = maxi(rise, 1)
	if not add_fixture(f):
		return false
	for k in maxi(tiles, 1):
		_ramp[anchor + dir * k] = dir
	return true


## A STRETCH OF WALL BUILT AS ONE PIECE, spanning `tiles` from `anchor` along the side facing
## `out_dir`.
##
## The last of the three fixture kinds, and the only one purely about art: N tiles of wall come out
## as one N*4 m run instead of N modules, so a curved or bevelled face can cross a tile joint.
## `consumes_wall` is what makes it work — the tile loop skips exactly the boundary the run covers
## and goes on emitting every other side of those same tiles.
##
## THE DOORWAY IS NOT CHECKED HERE, and that omission is the design rather than a gap. Which walls
## carry an exit is the LAYOUT's business and this class has never known about it — corner_tiles()
## says the same of bevels. The caller rejects a run that would span a door, at the point the room is
## ZONED rather than the point it is built, and that reframing is what makes the hardest breakage the
## cheapest: a doorway is a pre-collapsed cell a run may not cross, and there is no tolerance to
## widen instead. Kit._doorway hard-codes its jambs to a 4 m module and _plan_suite asserts exactly
## one doorway slot per exit, so a run swallowing a door does not degrade the opening — it seals the
## room.
func add_wall_run(anchor: Vector2i, out_dir: Vector2i, tiles: int) -> bool:
	if out_dir == Vector2i.ZERO or (out_dir.x != 0 and out_dir.y != 0):
		push_error("RoomShape.add_wall_run: %s is not one of the four axes" % out_dir)
		return false
	if tiles < 2:
		push_error("RoomShape.add_wall_run: %d tiles is not a run — use the plain module" % tiles)
		return false
	var along := Vector2i(-out_dir.y, out_dir.x)      # along the wall, across the way it faces
	var far := anchor + along * (tiles - 1)
	for k in tiles:
		var t := anchor + along * k
		# EVERY TILE MUST ACTUALLY HAVE THIS WALL. A run over a tile whose out_dir neighbour is solid
		# would claim a boundary that is not there, and consumes_wall would then delete the level
		# change or shell wall that tile's neighbour was relying on.
		if is_solid(t + out_dir):
			push_error("RoomShape.add_wall_run: tile %s has no wall facing %s" % [t, out_dir])
			return false
	var f := Fixture.new()
	f.kind = "wall_run"
	f.anchor = Vector2i(mini(anchor.x, far.x), mini(anchor.y, far.y))
	f.span = Vector2i(absi(far.x - anchor.x) + 1, absi(far.y - anchor.y) + 1)
	f.dir = out_dir
	f.level = level_of(anchor)
	return add_fixture(f)


## One tile, one level, climbing `dir`. The shape every ramp in the dungeon has today.
func set_ramp(tile: Vector2i, dir: Vector2i) -> void:
	add_ramp(tile, dir, 1, 1)


func is_ramp(tile: Vector2i) -> bool:
	return _ramp.has(tile)


func ramp_dir(tile: Vector2i) -> Vector2i:
	return _ramp.get(tile, Vector2i.ZERO)


## How many levels the flight under this tile climbs, 0 if it is not a ramp. Read off the fixture
## rather than kept beside `_ramp`, so there is one place a ramp's height is recorded.
func ramp_rise(tile: Vector2i) -> int:
	var f: Fixture = _claimed.get(tile, null)
	return f.rise if f != null and f.kind == "ramp" else 0


## CAN A BODY WALK FROM `a` TO ITS NEIGHBOUR ACROSS `side`? The one place the answer lives, because
## it is asked by the reachability assertion and will be asked by the zone solver, and two versions
## of it would eventually disagree about a room the player is standing in.
##
## Three ways across, and only three. Same level, flat. Onto a ramp from its low end, climbing. Off a
## ramp at its high end, onto the deck it serves. Everything else is a wall — including a one-level
## step, because nothing in this project climbs a ledge.
func walkable(a: Vector2i, side: Vector2i) -> bool:
	var b := a + side
	if not (is_solid(a) and is_solid(b)):
		return false
	if level_of(a) == level_of(b):
		return true
	# A ramp tile SITS AT THE LOWER LEVEL and its floor rises toward ramp_dir, so it is the low end
	# that shares a level with the room and the high end that meets the deck.
	if is_ramp(a) and ramp_dir(a) == side and level_of(b) == level_of(a) + ramp_rise(a):
		return true
	if is_ramp(b) and ramp_dir(b) == -side and level_of(a) == level_of(b) + ramp_rise(b):
		return true
	return false


## EVERY REGION: a maximal 4-connected set of tiles at ONE level, as
## [{level: int, tiles: Array[Vector2i], outline: bool}]. `outline` is true if any tile in it has a
## side with no floor beyond, which is the test a sunken region has to fail.
##
## A ramp tile belongs to the LOWER of the two levels it joins, because that is the level it sits at
## — the same convention `level_of` uses and the one the riser suppression already relies on.
func regions() -> Array:
	const SIDES: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var seen := {}
	var out: Array = []
	for start: Vector2i in _column:
		if seen.has(start):
			continue
		var lvl := level_of(start)
		var group: Array[Vector2i] = []
		var edge := false
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var t: Vector2i = queue.pop_back()
			group.append(t)
			for side: Vector2i in SIDES:
				var n := t + side
				if not is_solid(n):
					edge = true
					continue
				if seen.has(n) or level_of(n) != lvl:
					continue
				seen[n] = true
				queue.append(n)
		out.append({"level": lvl, "tiles": group, "outline": edge})
	return out


## HOW MUCH FLOOR THE LEVEL CHANGES HIDE FROM THE CAMERA, in square metres.
##
## A BUDGET, NOT A TABOO, and that is the change. The gallery is nailed to the far row because the
## near one was tried first and every screenshot of it had the deck behind its own parapet — but "far
## row only" is a rule about one feature, not about the thing that made it wrong, so the next feature
## that raises a floor has to rediscover it. The thing that made it wrong is a number: at FRAME_PITCH
## a boundary of drop d occludes d / tan(pitch) = 0.90 d metres of whatever lies BEHIND it, and
## behind means further -Z, because the camera sits at +Z looking along -Z.
##
## THE CAMERA LEAKING INTO A GAMEPLAY CLASS is deliberate and has precedent right here: LEVEL_RISE is
## 1.2 for camera reasons and says so. What may not leak is anything about a MESH or a MATERIAL. A
## room's shape has to know what the fixed lens can see or it will keep building rooms you cannot
## play in and calling them valid.
##
## Only -Z-facing boundaries count. A boundary facing +Z has its riser turned away from the lens and
## hides nothing; the floor in front of it is lower and nearer, which the camera sees over.
func hidden_by_levels() -> float:
	var hidden := 0.0
	var reach := 1.0 / tan(DungeonRoom.FRAME_PITCH)
	for tile: Vector2i in _column:
		var behind := tile + Vector2i(0, -1)
		if not is_solid(behind):
			continue
		var drop := level_of(tile) - level_of(behind)
		if drop <= 0:
			continue
		# Never more floor than there is behind it: one tile is 4 m deep, so a drop past ~4.4 m
		# hides the whole tile and no more.
		hidden += TILE * minf(float(drop) * LEVEL_RISE * reach, TILE)
	return hidden


## The same as a fraction of the room's floor, which is the form a rule wants — a hall and a closet
## should be held to the same standard, and the hall has more floor to lose.
func hidden_fraction() -> float:
	var area := float(tile_count()) * TILE * TILE
	return hidden_by_levels() / maxf(area, 1.0)


## HOW MUCH OF A ROOM MAY BE HIDDEN BY ITS OWN LEVELS. 12% is about one tile of a twelve-tile room,
## which is a corner you cannot fight in and can still walk through. Measured, not guessed: every
## room the dungeon builds today scores exactly ZERO, because the gallery sits on the far row where
## its riser faces the lens and occludes nothing at all. This is headroom for M8, not a description
## of anything shipping.
const MAX_HIDDEN := 0.12


## Is what the levels do to the camera acceptable? Two rules, and they fail differently.
##
## The BUDGET is soft in kind — too much floor lost, spread anywhere. The DEPTH rule is hard: a
## boundary occluding the camera at two levels hides 1.8 m of the floor behind it, which is a body
## standing there entirely out of sight, and no amount of budget left over makes that playable. That
## is why one is a fraction and one is a cliff.
##
## NEAR THE CAMERA, SINK RATHER THAN RAISE. A pit's near rim is BELOW the floor in front of it, so it
## occludes nothing, and its far rim hides part of the pit — which is a smaller loss than a deck of
## the same depth, and a loss the player can see the top of. This function is what makes that a
## preference a solver can act on instead of a rule of thumb in a comment.
func camera_legal() -> bool:
	if hidden_fraction() > MAX_HIDDEN:
		return false
	for tile: Vector2i in _column:
		var behind := tile + Vector2i(0, -1)
		if is_solid(behind) and level_of(tile) - level_of(behind) >= 2:
			return false
	return true


## Does this tile sit on the room's own boundary — any side with no floor beyond it?
func on_outline(tile: Vector2i) -> bool:
	for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not is_solid(tile + side):
			return true
	return false


func level_count() -> int:
	var n := 0
	for t: Vector2i in _column:
		if int(_column[t]) != 0:
			n += 1
	return n


## Local centre of a tile, ON ITS OWN WALK SURFACE. The Y is the point of this: every pass that
## places something by tile — cover, light mounts, the encounter's spawn points — gets the right
## height for free, because it was already asking the tile where it was.
func tile_centre(tile: Vector2i) -> Vector3:
	return Vector3(
		(tile.x - (cols - 1) * 0.5) * TILE,
		float(level_of(tile)) * LEVEL_RISE,
		(tile.y - (rows - 1) * 0.5) * TILE)


## Which tile a local point falls in (may be a hole or outside — check with is_solid).
func tile_at(local: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(local.x / TILE + cols * 0.5)),
		int(floor(local.z / TILE + rows * 0.5)))


## Tile column / row a local coordinate sits in, clamped into the grid. Used to work out which
## lines a doorway needs kept solid.
func col_at(x: float) -> int:
	return clampi(int(floor(x / TILE + cols * 0.5)), 0, cols - 1)


func row_at(z: float) -> int:
	return clampi(int(floor(z / TILE + rows * 0.5)), 0, rows - 1)


## Corners that could be bevelled: a solid tile with exactly two OPEN sides, and those two
## perpendicular rather than opposite. An opposite pair is a one-tile-wide spur, which is a corridor
## and not a corner — the same distinction _inlay already draws when it picks its corner piece.
##
## A tile whose corner carries a doorway is excluded by the caller, not here: which walls are doors
## is the layout's business and the shape has never known about it.
func corner_tiles() -> Array:
	const SIDES: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var out: Array = []
	for tile: Vector2i in _column:
		var open: Array[Vector2i] = []
		for side: Vector2i in SIDES:
			if not is_solid(tile + side):
				open.append(side)
		if open.size() == 2 and open[0] + open[1] != Vector2i.ZERO:
			out.append({"tile": tile, "out": open[0] + open[1]})
	return out


## A PIECE THAT IS NOT ONE TILE. Every piece in this dungeon is a tile or a 4 m run, and that is the
## limit this class exists to lift: a stair is 2x2, a bevelled wall is 4x1, and the thing that makes
## them buildable is that the block they occupy is AXIS-ALIGNED IN TILE SPACE however the art inside
## it is turned. `span` is in room axes, already rotated — which is what lets a fixture reserve
## through RoomContext.reserve(), whose rectangles have no idea rotation exists.
##
## The chamfer is its only kind today, and converting it was the point: one mechanism with one user
## can be proved inert, and a second mechanism added later for the ramp would have been two ways of
## saying the same thing with only one of them tested.
class Fixture:
	extends RefCounted
	var kind := ""                  ## "chamfer" today; "ramp" and "wall_run" next
	var anchor := Vector2i.ZERO     ## its -x/-z tile
	var span := Vector2i.ONE        ## in TILES, in room axes
	var dir := Vector2i.ZERO        ## chamfer diagonal / ramp climb direction
	var level := 0                  ## the level its LOW end sits at
	var rise := 0                   ## levels climbed


var _fixtures: Array[Fixture] = []
## Vector2i -> the Fixture covering it, so consumes_floor/consumes_wall are one lookup rather than a
## scan of every fixture for every tile and side.
var _claimed: Dictionary = {}
## Set once the occupancy grid has been baked. RoomContext._ensure_grid SNAPSHOTS shape.contains()
## for the whole room and never re-reads it, so a fixture installed after that point changes the
## geometry and not the grid: the room builds around a bevel the cover pass, the mounts and the
## encounter all still believe is square floor. It would look right and place things inside masonry.
var _frozen := false


## Called by RoomContext the first time it bakes its grid. Nothing else should.
func freeze() -> void:
	_frozen = true


func add_fixture(f: Fixture) -> bool:
	# THE FREEZE FORBIDS WHAT THE GRID SNAPSHOTTED, not every fixture — and the distinction is the
	# rule's own reason rather than a loosening of it. RoomContext._ensure_grid snapshots
	# shape.contains() and the tiles a pass reserved; a BEVEL changes contains() by cutting a
	# half-plane out of its tile, and a RAMP changes what standing on that tile means. Either one
	# installed afterwards leaves the cover, the mounts and the encounter planning on floor that is
	# not there.
	#
	# A WALL RUN changes neither. It alters which piece is built along a boundary — `consumes_wall`
	# and nothing else — and walls were never in the grid. Refusing it was the original rule being
	# stated as "no fixtures" when what it meant was "nothing that moves the floor", and it cost the
	# wall-run pass its place in the order: runs must come after the zones, because a zone claims
	# tiles a run would otherwise take, and the zones are what bake the grid.
	if _frozen and f.kind != "wall_run":
		push_error("RoomShape.add_fixture(%s at %s) after the occupancy grid was baked — the grid "
				% [f.kind, f.anchor] + "would not know about it")
		return false
	for dx in maxi(f.span.x, 1):
		for dz in maxi(f.span.y, 1):
			var t := f.anchor + Vector2i(dx, dz)
			if not is_solid(t):
				push_error("RoomShape.add_fixture(%s): tile %s is not floor" % [f.kind, t])
				return false
			if _claimed.has(t):
				push_error("RoomShape.add_fixture(%s): tile %s is already a %s"
						% [f.kind, t, (_claimed[t] as Fixture).kind])
				return false
	for dx in maxi(f.span.x, 1):
		for dz in maxi(f.span.y, 1):
			_claimed[f.anchor + Vector2i(dx, dz)] = f
	_fixtures.append(f)
	return true


func fixture_at(tile: Vector2i) -> Fixture:
	return _claimed.get(tile, null)


## THE ENTIRE CONTRACT between the fixture layer and the passes that lay geometry. A fixture that
## consumes the floor builds its own walk surface, so the floor loop skips the slab; one that
## consumes a wall owns what happens at that boundary, so walls() skips the side.
##
## A bevel consumes NEITHER a floor nor, strictly, all four walls — it consumes the whole TILE's wall
## emission, because a chamfered tile has exactly two open sides by construction and its three runs
## are what stands on both of them. That is why this is per (tile, side) rather than per tile: the
## ramp is about to want one side of one tile and not the others.
func consumes_floor(tile: Vector2i) -> bool:
	var f: Fixture = _claimed.get(tile, null)
	# NAMED, NOT NEGATED. This was "anything that is not a bevel", written when a bevel was the only
	# fixture and a ramp the only thing that could arrive next — so the day a WALL RUN was installed
	# it silently ate the floor slabs under its own tiles, because a run is not a bevel. A wall is a
	# wall; the floor beside it is still floor. Listing what consumes rather than what does not is
	# the difference between a rule and an assumption about what will be added later.
	return f != null and f.kind == "ramp"


func consumes_wall(tile: Vector2i, side: Vector2i) -> bool:
	var f: Fixture = _claimed.get(tile, null)
	if f == null:
		return false
	match f.kind:
		"chamfer":
			# A bevelled tile has exactly two open sides by construction and its three runs stand on
			# both, so it owns the whole tile's emission.
			return true
		"wall_run":
			return side == f.dir
	return false


## A BEVELLED CORNER, as a one-tile fixture. Kept as a named call rather than making callers build a
## Fixture, because "cut this corner" is what the plan layer means and the block it occupies is an
## implementation detail of how the shape records it.
func set_chamfer(tile: Vector2i, diagonal: Vector2i) -> void:
	var f := Fixture.new()
	f.kind = "chamfer"
	f.anchor = tile
	f.dir = diagonal
	f.level = level_of(tile)
	if add_fixture(f):
		_chamfer[tile] = diagonal


## IS THE SILHOUETTE ONE PIECE? pick() makes this true by construction (no bite crosses the
## cross); a hand-carved shape voids that guarantee, so authored paths ask it explicitly. Plain
## 4-connectivity over solid tiles from any tile — levels do not matter here (that question is
## `walkable`'s, per region, and the two must not be conflated).
func silhouette_connected() -> bool:
	if _column.is_empty():
		return false
	var start: Vector2i = _column.keys()[0]
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var t: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if _column.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size() == _column.size()


# ---------------------------------------------------------------------------------------------
# SERIALIZATION — for DungeonGraph's authored shapes (the Forge's sculpt mode).
# ---------------------------------------------------------------------------------------------

## The shape as a dictionary a DungeonGraph room can carry. ORDER IS THE CONTRACT: cells are
## emitted in _column iteration order, because tile order is what walls() emits in and what the
## dresser builds in (see _set_tile) — a shape rebuilt in a different order is a different
## dungeon downstream. Wall runs are NOT serialized: they are re-derived each generation and
## are the one fixture legal after freeze; a serialized copy would collide with the fresh one.
func to_dict() -> Dictionary:
	var cell_list: Array[Vector3i] = []
	for t: Vector2i in _column:
		cell_list.append(Vector3i(t.x, level_of(t), t.y))
	var chamfer_list: Array[Dictionary] = []
	var ramp_list: Array[Dictionary] = []
	for f: Fixture in _fixtures:
		match f.kind:
			"chamfer":
				chamfer_list.append({"tile": f.anchor, "dir": f.dir})
			"ramp":
				# add_ramp normalised the anchor to the -x/-z corner; the LOW end (the original
				# anchor, where the climb starts) is the far corner when the climb runs negative
				# — the same recovery _ramp_cheeks makes.
				var low := f.anchor
				if f.dir.x < 0 or f.dir.y < 0:
					low = f.anchor + Vector2i((f.span.x - 1) * absi(f.dir.x),
							(f.span.y - 1) * absi(f.dir.y))
				ramp_list.append({"anchor": low, "dir": f.dir,
						"tiles": maxi(f.span.x * absi(f.dir.x) + f.span.y * absi(f.dir.y), 1),
						"rise": f.rise})
	return {"cols": cols, "rows": rows, "cells": cell_list, "chamfers": chamfer_list,
			"ramps": ramp_list, "v": 1}


## Rebuild a shape by REPLAYING the dict through the guarded constructors — every rule those
## guards enforce (slope, claims, outline pits via the callers) still holds, and _column order
## is reconstructed exactly because _set_tile runs in serialized order. Returns null the moment
## anything is refused or out of bounds: a half-honoured authored shape is worse than falling
## back to pick(), and the caller falls back on null. Never freezes — plan_shell's grid bake
## does that at the same point it always has.
static func from_dict(d: Dictionary) -> RoomShape:
	var s := RoomShape.new()
	s.cols = int(d.get("cols", 0))
	s.rows = int(d.get("rows", 0))
	if s.cols < 1 or s.rows < 1:
		return null
	for c in d.get("cells", []):
		if not c is Vector3i:
			return null
		var t := Vector2i((c as Vector3i).x, (c as Vector3i).z)
		if t.x < 0 or t.x >= s.cols or t.y < 0 or t.y >= s.rows or s._column.has(t):
			return null                       # out of grid, or a duplicate column
		s._set_tile(t, (c as Vector3i).y)
	if s.tile_count() == 0 or not s.silhouette_connected():
		return null
	# set_level's outline-pit refusal, re-asked over the FINISHED silhouette (replaying
	# _set_tile directly is what keeps _column order exact, but it bypasses the guard — so the
	# guard's own predicate runs here, once, when on_outline can finally answer).
	for t: Vector2i in s._column:
		if s.level_of(t) < 0 and s.on_outline(t):
			return null
	for r in d.get("ramps", []):
		if not (r is Dictionary and r.get("anchor") is Vector2i and r.get("dir") is Vector2i):
			return null
		if not s.add_ramp(r.anchor, r.dir, int(r.get("tiles", 1)), int(r.get("rise", 1))):
			return null
	for c in d.get("chamfers", []):
		if not (c is Dictionary and c.get("tile") is Vector2i and c.get("dir") is Vector2i):
			return null
		s.set_chamfer(c.tile, c.dir)          # void; refusal detected by re-read
		if not s.is_chamfer(c.tile):
			return null
	return s


func is_chamfer(tile: Vector2i) -> bool:
	return _chamfer.has(tile)


## Which corner was cut off this tile, as the outward diagonal. ZERO if none.
func chamfer_dir(tile: Vector2i) -> Vector2i:
	return _chamfer.get(tile, Vector2i.ZERO)


func chamfer_count() -> int:
	return _chamfer.size()


func fixture_count() -> int:
	return _fixtures.size()


## How many FLIGHTS, not how many ramp tiles — a 3-tile ramp is one. `_ramp` is keyed per tile
## because that is what is_ramp() is asked; this counts the fixtures behind those tiles.
## How many multi-tile wall runs, for the same reason ramp_count exists.
func run_count() -> int:
	var n := 0
	for f in _fixtures:
		if f.kind == "wall_run":
			n += 1
	return n


func ramp_count() -> int:
	var n := 0
	for f in _fixtures:
		if f.kind == "ramp":
			n += 1
	return n


## True if a local point stands on real floor.
##
## SUB-TILE, but only just, and only for a chamfer. Everything else in this file is whole tiles, and
## a bevelled corner is the one place that is not enough: the triangle between the diagonal and the
## old square corner is still inside a solid tile and is no longer inside the ROOM. Left as "floor",
## every pass that asks this question — the occupancy grid's no-floor bake, cover placement, light
## mounts, enemy spawns, clutter, debris — would happily use 2 m2 of ground standing on the far side
## of a wall.
##
## One half-plane per chamfered tile is the whole of the extra machinery, and it costs nothing that a
## true curve would: no sub-tile resolution anywhere else, no change to walls(), no change to what
## the map measures. `d` points out of the corner, so a point is inside the room when its offset from
## the tile centre, projected onto that diagonal, has not passed the cut line.
func contains(local: Vector3) -> bool:
	var tile := tile_at(local)
	if not is_solid(tile):
		return false
	if not _chamfer.has(tile):
		return true
	var d: Vector2i = _chamfer[tile]
	var c := tile_centre(tile)
	# Both ends of the cut are CHAMFER_LEG back from the corner, so both give the same value for
	# x*dx + z*dz: TILE - CHAMFER_LEG. Written that way rather than as TILE/2, which it happens to
	# equal at a 2 m leg and would stop equalling the moment the leg were retuned.
	return (local.x - c.x) * d.x + (local.z - c.z) * d.y <= TILE - CHAMFER_LEG


## True if the whole XZ box centred on `local` stands on real floor. Cover pieces and enemies must
## not hang off the edge of a carved corner.
func contains_box(local: Vector3, size: Vector2) -> bool:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	for cx in [-hx, hx]:
		for cz in [-hz, hz]:
			if not contains(local + Vector3(cx, 0.0, cz)):
				return false
	return contains(local)


## HOW LONG A RUN WITH THIS ROLE IS, in metres, and the ONLY place that answers it. The same
## question was being answered independently in Kit.SIZES (which decides the real geometry), in
## verify_dungeon's _run_ends, in the layout lab's wall drawing, and implicitly in the dresser's
## fixed 1.1 m clutter row — four tables, of which three could be right about a 4 m wall and wrong
## about a 2.83 m one without anything saying so. Every wall now CARRIES its span, this computes it,
## and verify_dungeon checks the answer against the piece the dresser will actually build.
##
## The role, not the tag: a bevelled run and a straight one are both T_WALL, and only the role tells
## them apart. Unknown roles get the full module, which is right — a role exists to select a
## VARIANT, and a variant that changed the length would need a size here anyway.
## Is this role's length FIXED, or does the wall carry its own? A fixture run is as long as the
## block it spans, so there is no per-role answer and span_of must not be asked for one.
static func has_fixed_span(role: String) -> bool:
	return role != "long"


static func span_of(role: String) -> float:
	match role:
		"long":
			# NOT AN ANSWER, a floor. A run's real length is on the wall dict; this exists so a caller
			# that has only the role gets something buildable rather than a zero.
			return TILE
		"chamfer":
			return CHAMFER_DIAG
		"half":
			return CHAMFER_LEG
		_:
			return TILE


## EACH 4 M MODULE ALONG A RUN, as its centre in room-local space.
##
## A run is one module today, so this returns exactly `[w.at]` for every wall the dungeon currently
## builds — which is the whole reason it can land now. It exists for the passes that treat a run as
## one PLACE: a sconce goes on a bay, not on a run, and a wall-run fixture spanning four tiles would
## otherwise cut the candidate pool by four. RoomWeave._mount_walls then places too few, falls back,
## fails again and calls _drop_mounts — handing the room silently to the dresser's perimeter ring.
##
## The n == 1 case returns the run's own `at` UNTOUCHED rather than computing a midpoint that ought
## to equal it. Every wall in the dungeon takes that branch, so "unchanged" is exact rather than
## within a float of exact, and the assertion that says so can use ==.
static func wall_bays(w: Dictionary) -> Array[Vector3]:
	var at: Vector3 = w.at
	var span: float = w.get("span", TILE)
	var n := maxi(1, int(round(span / TILE)))
	if n == 1:
		return [at] as Array[Vector3]
	# Perpendicular to the outward normal, which for a bevel is diagonal — so it is taken from the
	# NORMALISED vector rather than from (out.y, out.x), which is parallel on a diagonal rather than
	# perpendicular to it.
	var nrm := Vector3(w.out.x, 0.0, w.out.y).normalized()
	var along := Vector3(-nrm.z, 0.0, nrm.x)
	var step := span / float(n)
	var bays: Array[Vector3] = []
	for k in n:
		bays.append(at + along * ((k + 0.5) * step - span * 0.5))
	return bays


## Every wall segment the shape needs: one per boundary between a solid tile and a hole/outside.
## Returns [{at: Vector3 (local, on the boundary), yaw: float, out: Vector2i (outward dir),
## role: String, span: float}].
func walls() -> Array:
	const SIDES: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var out: Array = []
	for tile: Vector2i in _column:
		var centre := tile_centre(tile)
		# A FIXTURE'S RUNS COME OUT AT ITS ANCHOR, in tile order, rather than in a fixtures-first
		# block ahead of everything. The plan called for fixtures-then-tiles and this is a deliberate
		# departure from that wording: emission order is build order, and a wall list with the same
		# runs in a different sequence is not the same dungeon downstream. Anchoring keeps the order
		# byte-identical to the chamfer branch this replaces — which is the whole reason to convert
		# the one existing kind before adding a second — and it puts a fixture's geometry where the
		# fixture is, which reads better than a block at the top either way.
		var fx: Fixture = _claimed.get(tile, null)
		if fx != null and fx.anchor == tile:
			out.append_array(_fixture_walls(fx, centre))
		var here := level_of(tile)
		for side: Vector2i in SIDES:
			if consumes_wall(tile, side):
				continue
			var there := tile + side
			if not is_solid(there):
				# THE ROOM'S OWN SHELL, always from y = 0 whatever the tile above it is doing: the
				# space UNDER a raised tile at the perimeter is enclosed by this wall, so starting
				# it at the tile's own height would open a 1.8 m slot into the void behind it.
				out.append({
					"at": Vector3(centre.x, 0.0, centre.z) + Vector3(side.x, 0, side.y) * (TILE * 0.5),
					"yaw": _inward_yaw(side),
					"out": side,
					"role": "",
					"span": span_of(""),
				})
				continue
			# A LEVEL BOUNDARY IS A WALL, and this is the whole payoff of putting the level on the
			# tile: the retaining wall under a raised floor is emitted by the same loop that emits
			# every other wall, for the same reason — the floor stops here. It used to be a bespoke
			# piece placed by a bespoke pass.
			var drop := here - level_of(there)
			if drop <= 0:
				continue                          # the neighbour is level or higher; not our wall
			if ramp_dir(there) == -side:
				continue                          # the neighbour ramps UP to us; that is the way in
			# FACING THE LOW SIDE, which is the reverse of every other wall here and is worth the
			# words. An ordinary wall belongs to the room and faces IN; a riser belongs to the
			# raised mass and faces OUT of it, at the floor you look at it from. `side` runs from
			# high to low, so the face wants -side. While the piece was a symmetric greybox box this
			# was invisible; the moment it carries an arcade, getting it wrong buries the arcade
			# inside the deck.
			#
			# ONE MODULE PER LEVEL, STACKED, for any drop. The riser art is exactly LEVEL_RISE tall,
			# so a single slot against a two-level boundary is a 1.2 m wall holding back 2.4 m of
			# floor — the deck's underside visible above it and the player able to see, and shoot,
			# straight through. Stacking is what makes one art module answer any drop, which is the
			# same argument the wall courses already make about height.
			for k in drop:
				out.append({
					"at": Vector3(centre.x, float(level_of(there) + k) * LEVEL_RISE, centre.z)
							+ Vector3(side.x, 0, side.y) * (TILE * 0.5),
					"yaw": _inward_yaw(-side),
					"out": -side,
					"role": "riser",
					"span": span_of("riser"),
				})
	return out


## The runs one fixture stands on. One kind so far; the match is what the ramp and the wall run join.
func _fixture_walls(f: Fixture, centre: Vector3) -> Array:
	var out: Array = []
	match f.kind:
		"chamfer":
			# THE BEVELLED CORNER: one diagonal plus what is left of the two walls it cut into.
			# Lengths are 2.83 / 2.0 / 2.0 against the 4.0 every other segment here is, which is why
			# the run carries a ROLE — the dresser needs a differently sized piece, and a role costs
			# no tag, no ALL_TAGS entry and no change to anything that iterates tags.
			var d := f.dir
			var back := TILE * 0.5 - CHAMFER_LEG * 0.5     # centre of the surviving half-run
			out.append({
				"at": centre + Vector3(d.x * TILE * 0.5, 0.0, -d.y * back),
				"yaw": _inward_yaw(Vector2i(d.x, 0)),
				"out": Vector2i(d.x, 0),
				"role": "half",
				"span": span_of("half"),
			})
			out.append({
				"at": centre + Vector3(-d.x * back, 0.0, d.y * TILE * 0.5),
				"yaw": _inward_yaw(Vector2i(0, d.y)),
				"out": Vector2i(0, d.y),
				"role": "half",
				"span": span_of("half"),
			})
			# The diagonal's midpoint is CHAMFER_LEG/2 in from the corner along both axes.
			var m := TILE * 0.5 - CHAMFER_LEG * 0.5
			out.append({
				"at": centre + Vector3(d.x * m, 0.0, d.y * m),
				"yaw": _inward_yaw(d),
				"out": d,
				"role": "chamfer",
				"span": span_of("chamfer"),
			})
		"ramp":
			out.append_array(_ramp_cheeks(f))
		"wall_run":
			# ONE RUN ACROSS THE WHOLE BLOCK, at the centre of the face it covers. `centre` is the
			# anchor tile's, so the run's midpoint is half the remaining span further along.
			var along := Vector3(-float(f.dir.y), 0.0, float(f.dir.x))
			var n := maxi(f.span.x * absi(along.x) + f.span.y * absi(along.z), 1)
			var mid := centre + along.abs() * (float(n - 1) * TILE * 0.5)
			out.append({
				"at": Vector3(mid.x, 0.0, mid.z)
						+ Vector3(f.dir.x, 0, f.dir.y) * (TILE * 0.5),
				"yaw": _inward_yaw(f.dir),
				"out": f.dir,
				"role": "long",
				"span": float(n) * TILE,
			})
	return out


## THE WALLS DOWN A RAMP'S SIDES, and why they appear only past one level.
##
## A ramp's lateral neighbour is ordinary floor at the low level, so there is no level boundary for
## the tile loop to find and it emits nothing there. At one level that is right and wanted: the side
## of the flight is a wedge from 0 to 1.2 m, you can step onto it from the floor beside it, and
## walling it off would make a 4 m room feel like a corridor. At two it is a 2.4 m drop you can walk
## off sideways without ever seeing an edge, and the fall is silent because nothing in this project
## has a ledge to catch on.
##
## So the cheeks arrive with the second level rather than being retro-fitted after one ships. Every
## ramp the dungeon builds today is rise 1 and gets none, which is what keeps this inert.
##
## Stacked one riser module per level, exactly as a level boundary of drop >= 2 will be: one art
## module, any drop.
func _ramp_cheeks(f: Fixture) -> Array:
	var out: Array = []
	if f.rise < 2:
		return out
	var along := f.dir
	var across := Vector2i(-along.y, along.x)
	var n := maxi(f.span.x * absi(along.x) + f.span.y * absi(along.y), 1)
	# The tile the ramp starts from, recovered from the block: `anchor` is its -x/-z corner, so the
	# low end is the anchor when the ramp climbs toward +, and the far corner when it climbs toward -.
	var low := f.anchor
	if along.x < 0 or along.y < 0:
		low = f.anchor + Vector2i(f.span.x - 1, f.span.y - 1)
	for k in n:
		var tile := low + along * k
		var c := Vector3((tile.x - (cols - 1) * 0.5) * TILE, 0.0,
				(tile.y - (rows - 1) * 0.5) * TILE)
		# HOW HIGH THE FLIGHT IS AT THIS TILE'S FAR EDGE, which is what the cheek beside it has to
		# retain. Rounded DOWN to whole levels so the cheek is built from the same riser module as
		# every other level boundary rather than needing a sloping piece of its own.
		var levels := int(floor(float(f.rise) * float(k + 1) / float(n)))
		for side: Vector2i in [across, -across]:
			if is_solid(tile + side) and level_of(tile + side) >= f.level + levels:
				continue                      # the neighbour is as high; there is nothing to retain
			for step in levels:
				out.append({
					"at": Vector3(c.x, float(f.level + step) * LEVEL_RISE, c.z)
							+ Vector3(side.x, 0, side.y) * (TILE * 0.5),
					"yaw": _inward_yaw(-side),
					"out": -side,
					"role": "riser",
					"span": span_of("riser"),
				})
	return out


## Wall pieces are authored along local X with local +Z facing INTO the room — that is the art
## contract that lets a wall carry a one-sided feature (a candle niche, a relief). Symmetric
## pieces don't care, but an axis-only yaw would point half the niches at the void.
## Works for ANY direction, not just the four axes: Basis(UP, yaw) sends +Z to (sin yaw, cos yaw),
## and the contract says that vector points INTO the room, so out = -(sin yaw, cos yaw) and the yaw
## that produces a given `out` is atan2(-out.x, -out.y). On the four axes this returns exactly the
## four values the if-ladder it replaces did -- 0, PI, -PI/2, PI/2 -- and it extends to a chamfer's
## PI/4 without a special case.
## `0.0 - x` RATHER THAN `-x`, AND IT IS NOT A STYLE CHOICE. `-float(0)` is NEGATIVE zero, and
## atan2(-0.0, -1.0) is -PI where atan2(+0.0, -1.0) is +PI — so every +Z wall came out at -PI, which
## is the same rotation and a different number. `0.0 - 0.0` is +0.0, and reproduces the four values
## of the ladder this replaces exactly, which is what the suite asserts.
##
## It moved no pixels: -PI and +PI differ in the basis by about 1e-16. It is fixed because a function
## whose entire contract is "return one of these four yaws" must return those four yaws, and because
## the next thing to compare a yaw against a constant would have been silently wrong.
static func _inward_yaw(out_dir: Vector2i) -> float:
	return atan2(0.0 - float(out_dir.x), 0.0 - float(out_dir.y))


## The inverse of _inward_yaw: which way a wall faces OUT of the room, recovered from the yaw its
## slot already carries.
##
## THE FALLBACK, NOT THE ANSWER. This existed because `walls()` returned `out` and RoomPlan dropped
## it, so the side had to be recovered from the basis at dress time — sound only because _inward_yaw
## is a BIJECTION on the four axis directions. It is not one off them: `roundf` snaps any other yaw
## to the nearest quarter turn, and a chamfer at 3PI/4 and one at 5PI/4 snap to DIFFERENT sides, so
## a cut driven by this would keep one camera-facing chamfer and drop the other.
##
## RoomContext.Slot now carries `out` for exactly that reason, and RoomDresser.side_of prefers it.
## This remains correct, and remains the answer, for everything that genuinely stands at a quarter
## turn — which is every slot that carries no `out` of its own.
static func out_of_yaw(yaw: float) -> Vector2i:
	match int(roundf(fposmod(yaw, TAU) / (PI * 0.5))) % 4:
		0:
			return Vector2i(0, -1)
		1:
			return Vector2i(-1, 0)
		2:
			return Vector2i(0, 1)
		_:
			return Vector2i(1, 0)


## Is this wall segment the one the exit at `door` passes through? `door` is the room-local
## position from DungeonLayout.door_local — for a hall that is NOT the room's centre.
static func is_doorway(wall: Dictionary, d: Vector2i, door: Vector3) -> bool:
	if wall.out != d:
		return false
	var at: Vector3 = wall.at
	if d.x != 0:
		return absf(at.z - door.z) < TILE * 0.5
	return absf(at.x - door.x) < TILE * 0.5

@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomContext
extends RefCounted
## Shared scratch space for ONE room's build. Generation is a PIPELINE of passes, not a tree:
## each pass reads what earlier passes wrote and adds to it. This object is that channel.
##
## The gameplay passes (RoomPlan) fill `slots` with ABSTRACT TAGGED PLACEMENTS — "a large cover
## piece stands here, facing this way, claiming this much floor" — and never name a mesh, a scene
## or a colour. The style pass (RoomDresser) resolves each tag into real nodes via the theme.
## That split is what keeps the headless suite fast and art-free.
##
## Space is tracked as an OCCUPANCY GRID: one byte per CELL metres of the room's bounding box,
## carrying whether that cell is real floor, already claimed, or inside a doorway lane. Every pass
## asks the same question of it — "is this box free?" — which is what a tree of nested choices
## could never express, and what keeps a crate out of a pillar without any pass knowing about any
## other. Extra per-cell tags (cover, spawn-ok, focal) belong here too when they are needed.

const DOOR_LANE_HALF := 2.0                   ## keep this much clear either side of a door axis
const CELL := 1.0                             ## occupancy resolution, metres

## Per-cell occupancy flags. NO_FLOOR and DOOR_LANE are baked in from the shape and the exits when
## the grid is built; BLOCKED accumulates as passes reserve space.
const F_NO_FLOOR := 1
const F_BLOCKED := 2
const F_DOOR_LANE := 4
## THE FLOOR HERE IS NOT AT Y = 0. The grid is 2-D and cannot hold a height, but it can hold the one
## bit that matters to everything scattering things on the ground: whether the ground is where you
## think it is. Without it a dais is indistinguishable from a wide crate, and the pass that sprinkles
## pebbles across the floor sprinkles them through the middle of the platform.
const F_OFF_LEVEL := 8


## One abstract placement. `footprint` is the XZ space it claims (ZERO = claims nothing, e.g. a
## wall sconce), used both for overlap rejection and for the reservation it writes.
class Slot:
	extends RefCounted
	var tag := ""
	var transform := Transform3D.IDENTITY
	var footprint := Vector2.ZERO
	## An ADJECTIVE on the tag, never an art name: "border", "corner", "threshold". Empty is the
	## default and means today's behaviour exactly.
	##
	## A role rather than a new tag, deliberately. Tags are the plan's contract with the dresser and
	## the thing verify_dungeon iterates (ALL_TAGS), so every one added costs a DEFAULT_PIECE entry, a
	## theme entry and a greybox size. A role costs none of that: RoomDresser.piece_for falls back
	## `tag/role` -> `tag`, so a theme shipping no variant for a role renders the plain piece and the
	## socket degrades, which is the rule for every socket in this dungeon.
	var role := ""
	## HOW MANY TILES THIS PIECE COVERS, in room axes, already rotated. ONE for everything that is one
	## tile or one wall module, which is every piece but a multi-tile fixture — so a reader that has
	## never heard of fixtures gets the answer it always assumed.
	##
	## In tiles rather than metres because that is the unit the thing is decided in: a stair is "two
	## tiles long", and turning that into 8.0 here would mean the dresser dividing it back by TILE to
	## find out how many treads to build.
	var span := Vector2i.ONE
	## Which way this piece faces OUT of the room. ZERO means "recover it from the basis", which is
	## what every slot standing in open floor means and what every wall meant until now.
	##
	## A FIELD RATHER THAN A DERIVATION, because the derivation is about to stop being sound.
	## RoomShape.out_of_yaw recovers the side from the yaw, and its own docstring gives the reason it
	## is allowed to: _inward_yaw is a BIJECTION on the four axis directions. A chamfer's yaw is not
	## one of those four, and out_of_yaw has no guard — it rounds to the nearest quarter turn, so a
	## 45-degree piece is silently reported as one of its two neighbours, and the two chamfers on a
	## camera-facing corner round OPPOSITE WAYS. The diorama cut would then drop one and keep the
	## other, and verify_dungeon would agree, because it re-derives the answer the same wrong way.
	##
	## Carrying the direction the shape already knew is the fix. It costs one field and no tag.
	var out := Vector2i.ZERO

	func position() -> Vector3:
		return transform.origin


var rd: DungeonLayout.RoomData
var slots: Array[Slot] = []
var spawn_defs: Array = []                    ## [{kind: String, pos: Vector3 local}]

## What the room is FOR, chosen by RoomProgram and recorded so the bench and the suites can report
## it. A label, never a lookup key for art — the dresser must not be able to see it, or a reskin
## could change a fight.
var program := ""

## TILES A SIGHTLINE RELATION HAS CLAIMED. Written by TileProgram at step 3 and read by
## RoomWeave._seed_field at step 8, which already pre-collapses the room's spine and every door's
## approach to AISLE — a sightline is a third reason to do the same thing, aimed by the program
## instead of by the room's long axis.
##
## A TILE LIST RATHER THAN A PAIR OF ZONES, because by the time the weave runs the zones are gone:
## they were the reason, the tiles are the record. That is the same division RoomShape keeps.
var sightline: Array[Vector2i] = []

## HOW MANY ZONES THE ROOM ASKED FOR AND DID NOT GET. Counted rather than swallowed, because a
## solver that quietly falls back makes the dungeon poorer with every constraint added and says
## nothing — a program whose apse never fits becomes a plain room, looks fine, and is a feature
## nobody notices has stopped shipping. verify_dungeon holds the rate to a ceiling.
var zones_refused := 0

## Why an AUTHORED shape was not honoured ("" = it was, or none was asked for). Written by
## RoomPlan.plan_shell when rd.shape_data falls back to pick() — a grid that no longer matches
## the room's size, a replay the guards refused. Counted-not-swallowed, per-room, where the
## Forge's status line can collect it.
var shape_note := ""

var footprint := DungeonLayout.ROOM_SIZE:     ## BOUNDING extent (x, wall height, z)
	set(value):
		footprint = value
		_grid.clear()
var shape: RoomShape = RoomShape.full():      ## which of that bounding box is actually floor
	set(value):
		shape = value
		_grid.clear()

var _seed := 0
var _streams := {}
var _grid := PackedByteArray()                ## occupancy, CELL metres per entry, row-major
var _gw := 0
var _gh := 0
var _doors: Array[Vector3] = []               ## cached exit positions, room-local
var _door_axes: Array[Vector2i] = []          ## parallel to _doors


static func create(room_data: DungeonLayout.RoomData, seed_value: int) -> RoomContext:
	var ctx := RoomContext.new()
	ctx.rd = room_data
	ctx._seed = seed_value
	return ctx


## A named RNG stream. ONE STREAM PER PASS is the point: re-tuning clutter density must not
## reshuffle the encounter, and re-rolling variants must not move the pillars. Derived from
## (dungeon seed, room cell, pass name), so it is also stable across runs and room order.
func stream(pass_name: String) -> RandomNumberGenerator:
	if _streams.has(pass_name):
		return _streams[pass_name]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%s" % [_seed, rd.cell, pass_name])
	_streams[pass_name] = rng
	return rng


## Every stream that has been opened, with how far it has been drawn. READ-ONLY, and it exists so
## the promise in the docstring above can be CHECKED rather than only stated: if two passes share a
## stream, the second one's results depend on how many numbers the first happened to draw, and
## re-tuning either silently reshuffles the other. That is invisible in the output — both rooms look
## fine, they are simply different rooms than they would have been — so nothing but the RNG's own
## state can see it. Does NOT open a stream, or observing would create what it is observing.
func stream_states() -> Dictionary:
	var out := {}
	for name: String in _streams:
		out[name] = (_streams[name] as RandomNumberGenerator).state
	return out


## Stable per-position variation roll in [0, 1). The same piece at the same spot always draws the
## same value, independent of how many passes ran before it or how many variants any other tag
## has — so adding a clutter pass cannot reshuffle the pillars. DungeonTheme.pick() maps it to a
## variant (weighted, if the theme says so).
func variant_roll(tag: String, at: Vector3) -> float:
	return roll_for(_seed, "%s|%s" % [rd.cell, tag], at)


## Same roll, for things built outside any room (corridors, stairs).
static func roll_for(seed_value: int, key: String, at: Vector3) -> float:
	var h := absi(hash("%d|%s|%.2f|%.2f" % [seed_value, key, at.x, at.z]))
	return float(h % 100003) / 100003.0


func add_slot(tag: String, xform: Transform3D, slot_footprint := Vector2.ZERO) -> Slot:
	var s := Slot.new()
	s.tag = tag
	s.transform = xform
	s.footprint = slot_footprint
	slots.append(s)
	if slot_footprint != Vector2.ZERO:
		reserve(xform.origin, slot_footprint)
	return s


func add_slot_at(tag: String, at: Vector3, slot_footprint := Vector2.ZERO,
		yaw := 0.0) -> Slot:
	var basis := Basis(Vector3.UP, yaw)
	return add_slot(tag, Transform3D(basis, at), slot_footprint)


func add_spawn(kind: String, at: Vector3) -> void:
	spawn_defs.append({"kind": kind, "pos": at})


## Claim floor. Everything with a footprint goes through here, so later passes see it.
func reserve(at: Vector3, size: Vector2) -> void:
	_ensure_grid()
	var r := _cells_of(at, size)
	for j in range(maxi(r.y, 0), mini(r.w + 1, _gh)):
		for i in range(maxi(r.x, 0), mini(r.z + 1, _gw)):
			_grid[j * _gw + i] |= F_BLOCKED


## Claim floor AND declare that its surface is no longer at y = 0. Always both, in one call, because
## a tile at another level is by definition a claimed one, and remembering to write two flags is
## exactly the sort of thing that gets half-done in a later edit.
##
## `move_floor`, not `raise_floor`, and the rename is the point rather than tidiness. Both this and
## F_OFF_LEVEL were named when up was the only direction a floor could go; a sunken region is a floor
## that has moved DOWN, needs identical treatment from every 2-D searcher, and would have been passed
## to something called "raise" by everyone who read the name and believed it. The flag's own docstring
## was already direction-neutral — only the names assumed.
func move_floor(at: Vector3, size: Vector2) -> void:
	_ensure_grid()
	var r := _cells_of(at, size)
	for j in range(maxi(r.y, 0), mini(r.w + 1, _gh)):
		for i in range(maxi(r.x, 0), mini(r.z + 1, _gw)):
			_grid[j * _gw + i] |= F_BLOCKED | F_OFF_LEVEL


## Is this box standing on the ROOM'S OWN FLOOR — real, and still at y = 0?
##
## Deliberately not is_unblocked. What scatters loose debris wants to know that the ground is there,
## not that the ground is empty: a pebble at the foot of a pillar is a pebble at the foot of a
## pillar, and most of what the reference art puts on a floor is piled against something. The only
## things it must refuse are a hole it would fall through and a platform it would be buried inside.
func is_ground(at: Vector3, size: Vector2) -> bool:
	_ensure_grid()
	var r := _cells_of(at, size)
	if r.x < 0 or r.y < 0 or r.z >= _gw or r.w >= _gh:
		return false
	for j in range(r.y, r.w + 1):
		for i in range(r.x, r.z + 1):
			if _grid[j * _gw + i] & (F_NO_FLOOR | F_OFF_LEVEL) != 0:
				return false
	return true


## Free = every cell the box covers is real floor, unclaimed, and out of the door lanes.
## Whole-box, not corner-sampled: a piece can no longer straddle a hole it does not touch a
## corner of.
func is_free(at: Vector3, size: Vector2, margin := 0.0) -> bool:
	_ensure_grid()
	var r := _cells_of(at, size + Vector2(margin, margin) * 2.0)
	if r.x < 0 or r.y < 0 or r.z >= _gw or r.w >= _gh:
		return false                          # pokes outside the room's bounding box
	for j in range(r.y, r.w + 1):
		for i in range(r.x, r.z + 1):
			if _grid[j * _gw + i] != 0:
				return false
	return true


## Free of SOLID THINGS, but not of the door lanes. Real floor, nothing standing on it — and no
## opinion about whether the player walks through here.
##
## The two questions genuinely differ, and verify_dungeon already draws the line in the same place:
## the whole-lane rule is *"the stricter rule plan_interior uses to pick procedural spots"*, while
## the real requirement is only *"can the player get in"*. A pillar in a door lane is a pillar in the
## way. A pot beside the wall of a corridor is a pot beside the wall of a corridor, and it is most of
## what the reference art puts there.
##
## Without this a cross-carved room with three exits gets NO clutter at all — every one of its seven
## surviving tiles is inside somebody's lane — which is exactly how seed 42's Room_-1_0_0 came back
## bare. Callers using this must still keep their own distance from the doorway itself.
func is_unblocked(at: Vector3, size: Vector2, margin := 0.0) -> bool:
	_ensure_grid()
	var r := _cells_of(at, size + Vector2(margin, margin) * 2.0)
	if r.x < 0 or r.y < 0 or r.z >= _gw or r.w >= _gh:
		return false
	for j in range(r.y, r.w + 1):
		for i in range(r.x, r.z + 1):
			if _grid[j * _gw + i] & (F_NO_FLOOR | F_BLOCKED) != 0:
				return false
	return true


## Somewhere a box of `size` actually fits, nearest the room centre first. This is the payoff of
## keeping a grid rather than a list of rectangles: "find me space" is a question a rect list
## cannot answer, and a coarse lattice of guesses fails exactly where it matters — a carved room
## whose middle is all door lane and whose corners have been bitten off.
## Returns `fallback` if the room genuinely has nowhere left.
func find_free(size: Vector2, margin := 0.0, fallback := Vector3.ZERO) -> Vector3:
	_ensure_grid()
	var best := fallback
	var best_d := INF
	for j in _gh:
		for i in _gw:
			if _grid[j * _gw + i] != 0:
				continue                      # cheap reject before the full box test
			var c := _cell_centre(i, j)
			var d := Vector2(c.x, c.z).length_squared()
			if d >= best_d:
				continue
			if is_free(c, size, margin):
				best = c
				best_d = d
	return best


## The same search, but nearest a point you NAME rather than nearest the room centre.
##
## find_free above always answers with the middle of the room, which is right for the one thing that
## uses it (a key should be findable) and wrong for anything placed in relation to something else —
## a lever beside a particular wall, a plinth near a particular door. Asked with find_free, eight
## separate fixtures all pile onto the same central cell and then refuse each other.
func free_near(want: Vector3, size: Vector2, margin := 0.0, fallback := Vector3.ZERO) -> Vector3:
	_ensure_grid()
	var best := fallback
	var best_d := INF
	for j in _gh:
		for i in _gw:
			if _grid[j * _gw + i] != 0:
				continue                      # cheap reject before the full box test
			var c := _cell_centre(i, j)
			var d := Vector2(c.x - want.x, c.z - want.z).length_squared()
			if d >= best_d:
				continue
			if is_free(c, size, margin):
				best = c
				best_d = d
	return best


## Cells still available. Cheap health metric for the suite and for tuning clutter density.
func free_cell_count() -> int:
	_ensure_grid()
	var n := 0
	for f in _grid:
		if f == 0:
			n += 1
	return n


## Built lazily so it always reflects the final shape and footprint — both invalidate it on
## assignment, and plan_shell sets the shape before anything reserves anything.
func _ensure_grid() -> void:
	if not _grid.is_empty():
		return
	# THE SHAPE IS SETTLED FROM HERE ON. Everything below SNAPSHOTS shape.contains() for the whole
	# room and never re-reads it, so a fixture installed after this point changes the geometry and
	# not the grid: the room would build around a bevel that the cover pass, the light mounts and the
	# encounter all still believe is square floor, and every one of them would place things inside
	# masonry while looking entirely correct. The shape refuses rather than letting that happen.
	if shape != null:
		shape.freeze()
	_gw = maxi(1, int(round(footprint.x / CELL)))
	_gh = maxi(1, int(round(footprint.z / CELL)))
	_grid.resize(_gw * _gh)
	_grid.fill(0)
	for j in _gh:
		for i in _gw:
			var c := _cell_centre(i, j)
			var f := 0
			if not shape.contains(c):
				f |= F_NO_FLOOR
			if in_door_lane(c):
				f |= F_DOOR_LANE
			_grid[j * _gw + i] = f


func _cell_centre(i: int, j: int) -> Vector3:
	return Vector3(
		-footprint.x * 0.5 + (i + 0.5) * CELL,
		0.0,
		-footprint.z * 0.5 + (j + 0.5) * CELL)


## Inclusive cell range covering a box, as (x0, z0, x1, z1). May run outside the grid; callers
## clamp or reject.
func _cells_of(at: Vector3, size: Vector2) -> Vector4i:
	var min_x := at.x - size.x * 0.5 + footprint.x * 0.5
	var max_x := at.x + size.x * 0.5 + footprint.x * 0.5
	var min_z := at.z - size.y * 0.5 + footprint.z * 0.5
	var max_z := at.z + size.y * 0.5 + footprint.z * 0.5
	# nudge off exact boundaries so a piece flush against a cell edge does not claim the next one
	return Vector4i(
		int(floor(min_x / CELL + 0.001)), int(floor(min_z / CELL + 0.001)),
		int(ceil(max_x / CELL - 0.001)) - 1, int(ceil(max_z / CELL - 0.001)) - 1)


## Where each exit meets the wall, in room-local space. NOT simply the middle of each side: a hall
## spans several cells and its exits sit wherever the shared boundary is.
func doors() -> Array[Vector3]:
	if _doors.is_empty() and rd != null:
		for e: DungeonLayout.Edge in rd.edges:
			if e.dir.x == 0 and e.dir.z == 0:
				continue
			_doors.append(DungeonLayout.door_local(rd, e))
			_door_axes.append(Vector2i(e.dir.x, e.dir.z))
	return _doors


## The straight run in front of each door must stay walkable, or a room can lock the player out
## of its own exit.
func in_door_lane(at: Vector3) -> bool:
	var list := doors()
	for i in list.size():
		var d: Vector2i = _door_axes[i]
		if d.x != 0 and absf(at.z - list[i].z) < DOOR_LANE_HALF:
			return true
		if d.y != 0 and absf(at.x - list[i].x) < DOOR_LANE_HALF:
			return true
	return false


func near_door(at: Vector3, dist: float) -> bool:
	for door: Vector3 in doors():
		if Vector2(at.x - door.x, at.z - door.z).length() < dist:
			return true
	return false


func slots_tagged(tag: String) -> Array[Slot]:
	var out: Array[Slot] = []
	for s in slots:
		if s.tag == tag:
			out.append(s)
	return out



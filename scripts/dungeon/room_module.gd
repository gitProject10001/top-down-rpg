@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomModule
extends RefCounted
## A KIND OF ROOM the layout may attach, rather than an anonymous rectangle.
##
## What this replaces: `_pick_size` rolled 1x1 / 2x1 / 1x2 / 2x2 and any block could go against any
## face. Rooms therefore had no identity — a dead-end happened when the walk ran out of room, the
## boss took whichever leaf was farthest, and if the walk left only one leaf `_grow_dead_end` had to
## bolt a second one on afterwards. A module says what a room IS before it is placed, which lets the
## layout ASK for the shapes it needs instead of hoping for them.
##
## THE TWO CONSTRAINTS, and why they are the only two.
##
##   max_edges  how many LATERAL doors the room accepts. `vault` takes one, so it is a dead-end BY
##              CONSTRUCTION — that is the whole payoff. The boss and the treasure stop depending on
##              a walk that happened to strand two leaves.
##   sockets    which FACES may carry a door, as (x, z) unit steps. Empty means all four.
##
## Sockets exist for exactly one module and would not be worth the machinery for any other:
## `landing` accepts only its X faces. `DungeonLayout._add_stairs` can only lift a leaf whose run is
## along X — a 20 m flight reads as stairs where 12 m reads as a ladder — so before this, stairs
## depended on the walk happening to leave an X-facing leaf. A `landing` IS one, every time.
##
## A DELIBERATE NON-FEATURE: there is no per-module rotation. Nothing in the dungeon rotates a cell
## block, so a socket list is read in world axes and stays honest. A module that needed rotating
## would need `_anchor_beside`, `_join` and `door_local` to agree about which way it was turned, and
## none of them has anywhere to put that.
##
## VERTICAL EDGES DO NOT COUNT toward max_edges — they are tested with `dir.y != 0`. A stair edge is
## diagonal (`onward + UP`), so it registers as horizontal too if you ask `dir.x`; `dir.y` is the
## only clean discriminator. Without this a `landing` could never become the stairwell it exists to
## become.

var id := ""
var size := Vector3i.ONE
var kind := "cell"                     ## the semantic label; Milestone B keys room rules off it
var sockets: Array[Vector2i] = []      ## allowed door faces as (x, z); empty = all four
var max_edges := 99                    ## lateral doors accepted (see the note above)
var min_dist := 0                      ## BFS depth band this module may be placed in
var max_dist := 99
var max_instances := 99                ## per dungeon
var weight := 1.0


static func make(id_: String, size_: Vector3i, kind_: String, weight_: float) -> RoomModule:
	var m := RoomModule.new()
	m.id = id_
	m.size = size_
	m.kind = kind_
	m.weight = weight_
	return m


## The catalogue, built once. Weights are per PICK, not per placed room: a 3x2 fails `_block_free`
## far more often than a 1x1, so what lands is always more single-cell than these numbers read.
##
## The single-cell share is deliberately a little LOWER than the 0.62 `_pick_size` used, because
## verify_dungeon requires a hall or gallery in at least 180 of 200 seeds and the new depth bands
## can only ever reduce what is available to pick from.
static var _cat: Array[RoomModule] = []


static func catalogue() -> Array[RoomModule]:
	if not _cat.is_empty():
		return _cat
	var out: Array[RoomModule] = []

	out.append(make("cell", Vector3i(1, 1, 1), "cell", 0.40))

	# The dead-end. One door, and only past the entrance — a vault hanging off the start room is a
	# cupboard, not a destination.
	var vault := make("vault", Vector3i(1, 1, 1), "vault", 0.10)
	vault.max_edges = 1
	vault.min_dist = 2
	out.append(vault)

	# The stairwell candidate: one door, and only on an X face, which is precisely what _add_stairs
	# can lift.
	var landing := make("landing", Vector3i(1, 1, 1), "landing", 0.08)
	landing.max_edges = 1
	landing.min_dist = 1
	landing.sockets = [Vector2i(1, 0), Vector2i(-1, 0)]
	out.append(landing)

	out.append(make("gallery_x", Vector3i(2, 1, 1), "gallery", 0.17))
	out.append(make("gallery_z", Vector3i(1, 1, 2), "gallery", 0.14))

	var hall := make("hall", Vector3i(2, 1, 2), "hall", 0.07)
	hall.min_dist = 1
	out.append(hall)

	# THE BIG TWO. Capped at one each and pushed deep, because scale is a signal: a room you can see
	# across should mean something is about to happen. They are also the only footprints large enough
	# for a silhouette rule to have anything to say — an 11x7 tile grid against a 1x1's 5x3.
	var great := make("great_hall", Vector3i(3, 1, 2), "hall", 0.02)
	great.min_dist = 2
	great.max_instances = 1
	out.append(great)

	var long_gallery := make("long_gallery", Vector3i(1, 1, 3), "gallery", 0.02)
	long_gallery.min_dist = 2
	long_gallery.max_instances = 1
	out.append(long_gallery)

	_cat = out
	return _cat


## The unconstrained module with this footprint, for rooms built OUTSIDE the walk that still have to
## name what they are — a loop junction picks its size from its own list, and a room whose declared
## module disagreed with its actual extent would be a lie every later pass reads as truth.
static func for_size(size_: Vector3i) -> RoomModule:
	for m in catalogue():
		if m.size == size_ and m.sockets.is_empty() and m.max_edges >= 99:
			return m
	return plain()


static func by_id(id_: String) -> RoomModule:
	for m in catalogue():
		if m.id == id_:
			return m
	return null


## The module every room the layout builds OUTSIDE the walk falls back to — junctions, the room a
## staircase lands in, a grown dead-end. Unconstrained on purpose: those passes have already proved
## the placement is legal by their own rules, and a second veto here would only make them fail
## silently.
static func plain() -> RoomModule:
	return make("cell", Vector3i(1, 1, 1), "cell", 1.0)


## May a room built from this module take a door on `face`? Sockets only; the edge count is checked
## separately because it needs the room, not the module.
func accepts_face(face: Vector2i) -> bool:
	return sockets.is_empty() or sockets.has(face)

@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name DungeonLayout
extends RefCounted
## Pure-DATA Isaac-style dungeon layout: a tree of rooms on a 3D cell grid. No scene nodes —
## `generate()` is a static function, so the headless test suite can hammer hundreds of seeds in
## milliseconds. The generator (dungeon_generator.gd) turns this data into kit-built rooms.
##
## Cell → world mapping: cell.x → +X, cell.y → FLOOR (up), cell.z → +Z (so NORTH on the grid is
## -z = world -Z).
##
## A room occupies a BLOCK of cells (`size`, anchored at its minimum corner `cell`), so halls and
## closets are the same thing as an ordinary room with a different extent. Its interior measures
## `size * CELL_PITCH - GAP` per axis, and the GAP is the passage between neighbours.
##
## WHY THE PITCH IS 24 x 16: rooms are floored in 4 m tiles (see RoomShape), so every footprint a
## room can have must be a whole number of them. n * 24 - 4 and n * 16 - 4 are multiples of 4 for
## every n, and both quotients are ODD, which keeps a true middle column and row — the thing that
## makes the carving rule safe. A pitch of 22 x 14 gave 42 x 26 for a double room: not tileable.
##
## Typed edges and the floor axis are the vocabulary for stairs, gates and loops; today generation
## produces flat CORRIDOR edges plus the STAIR pairs that `_add_stairs` lifts.

const CELL_PITCH := Vector2(24.0, 16.0)       ## grid spacing
const GAP := 4.0                              ## passage between adjacent rooms
const FLOOR_HEIGHT := 8.0                     ## world Y per floor step

## THE WALL, IN COURSES. A room used to be a 3 m box and read as a corridor with a two-metre ceiling.
## Height alone does not fix that — a 7 m slab of one texture reads as a tall FENCE. What reads as
## architecture is the horizontal articulation: a base, a band, a different bond above it, and a
## cornice. The eye measures height by counting the bands.
##
## The band also earns its keep structurally: two identical 3 m walls stacked give an obvious mirror
## line where the brick courses restart, and a projecting string course is exactly what hides it.
##
##      6.8  ____________   cornice, overhangs CORNICE_PROJ
##           |          |
##      3.3  |  ashlar  |   upper course, smoother bond than the base
##           |==========|   string course, projects BAND_PROJ
##      3.0  |          |
##           |  rubble  |   base course — the existing wall_brick_* art, unchanged
##      0.0  |__________|
const COURSE_H := 3.0                         ## one masonry module: the base AND the upper course
const BAND_H := 0.3
const BAND_PROJ := 0.12
const CORNICE_H := 0.5
const CORNICE_PROJ := 0.30

## THE WHOLE WALL, not one module. Raising this changes no gameplay path: size_of() is the only
## producer of a `.y` and every consumer discards it — RoomContext's occupancy grid is 2-D XZ,
## DungeonRoom reads only x/z, and door_local() always returns y = 0. It is a pure art number.
## But it must stay HONEST, because RoomPlan derives the course offsets from it and the neighbour
## invariant in verify_dungeon._cutaway_suite is checked against it.
const WALL_HEIGHT := COURSE_H * 2.0 + BAND_H + CORNICE_H

## Clearance a room trigger needs above the floor to catch a walking player. NOT wall height — it
## only looked like it while the wall was 3 m, and the two have now parted company.
const HEAD_ROOM := 3.0

## THE FLAT LANDING AT THE TOP OF A FLIGHT, in metres of the room's run.
##
## A stair room's flight used to climb the room's WHOLE length, reaching the next floor's height
## exactly at the room edge. That is one metre too late: the passage's floor strip is longer than
## the 4 m GAP it spans, so it overhangs half a metre into each room — and on a stair edge that
## overhang lands on a flight that is still climbing, leaving its top surface standing about 0.3 m
## proud of it. Measured: a player-shaped body walking up the middle stops dead at 9.19 m of a 10 m
## run, every seed, with the doorway visible in front of it. move_and_slide has no step-up, so a
## 0.3 m lip is a wall.
##
## Topping out early costs nothing and is what a staircase does anyway — you arrive at a landing and
## then walk through the door, rather than taking the last step in the doorway itself.
const STAIR_LANDING := 1.2

## Interior of a single-cell room. Multi-cell rooms use size_of().
const ROOM_SIZE := Vector3(CELL_PITCH.x - GAP, WALL_HEIGHT, CELL_PITCH.y - GAP)

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Reserved for stairs. Nothing generates a bare vertical step.
const UP := Vector3i(0, 1, 0)
const DOWN := Vector3i(0, -1, 0)

enum RoomType { START, COMBAT, BOSS, TREASURE, STAIR }

## How two rooms are joined. CORRIDOR and STAIR are generated today; the rest is the vocabulary
## the dungeon needs to stop being a tree of identical hallways:
##   DOOR      rooms share a wall opening, with no passage between them
##   CORRIDOR  the short passage + portcullis we build now
##   STAIR     the edge changes floor (dir.y != 0)
##   LOCKED    needs a key — the mission layer's gate
##   SHORTCUT  an extra edge closing a loop, often one-way until opened
##   SECRET    hidden until found
enum EdgeType { DOOR, CORRIDOR, STAIR, LOCKED, SHORTCUT, SECRET }


class Edge:
	extends RefCounted
	var dir := Vector3i.ZERO          ## unit step from the owning room to its neighbour
	var from_cell := Vector3i.ZERO    ## WHICH cell of the owning room the passage leaves from —
	                                  ## a hall has several, and the doorway must land on the
	                                  ## shared boundary, not at the room's centre
	var type: int = EdgeType.CORRIDOR
	var key_id := ""                  ## LOCKED only: which key opens it

	static func make(direction: Vector3i, cell: Vector3i, edge_type := EdgeType.CORRIDOR) -> Edge:
		var e := Edge.new()
		e.dir = direction
		e.from_cell = cell
		e.type = edge_type
		return e


class RoomData:
	extends RefCounted
	var cell := Vector3i.ZERO         ## ANCHOR: the minimum corner of the room's cell block
	var size := Vector3i.ONE          ## extent in cells (y is always 1 — rooms are single-storey)
	var type: int = RoomType.COMBAT
	var edges: Array[Edge] = []
	var dist := 0                     ## BFS steps from the start room
	var template_path := ""           ## handcrafted interior scene; "" = procedural furnish
	var holds_key := ""               ## non-empty: the key to that lock is found in this room
	var module_id := "cell"           ## which RoomModule placed it
	var kind := "cell"                ## that module's semantic label
	## WHAT THE ROOM IS FOR — "church", "refectory", "prison". A third axis beside `kind` (geometry)
	## and `type` (mission role); see RoomPurpose for why it cannot be folded into either. Written
	## once, at the end of generate(), when the graph has stopped moving.
	var purpose := ""
	## True when a DungeonGraph insisted on this room; the schematic rings authored rooms so a
	## glance separates what was drawn from what the walk filled in. Hash-invisible: every pinned
	## hash folds explicit fields, never the property list.
	var authored := false
	## The purpose the author asked for, "" for none. Kept apart from `purpose` because
	## _assign_purposes overwrites that field for every room — the hint is what it honours.
	var purpose_hint := ""
	## Which DungeonGraph room this is (-1 for a walk room). How the Forge's sculpt mode finds
	## the dict an edit must land in, and how the schematic pairs unmet pins with ghosts.
	var graph_id := -1
	## An authored RoomShape as RoomShape.to_dict data, empty for "let pick() carve". Deep-
	## duplicated from the graph at seeding so generation can never mutate author data.
	var shape_data: Dictionary = {}

	## Doors that take a wall rather than a floor. Vertical steps are excluded because a stair edge
	## is DIAGONAL (`onward + UP`) and so answers yes to `dir.x != 0` as well — `dir.y` is the only
	## clean discriminator, and without it a `landing` could never become the stairwell it exists
	## to become. See RoomModule.
	func lateral_edges() -> int:
		var n := 0
		for e in edges:
			if e.dir.y == 0:
				n += 1
		return n

	## HORIZONTAL exit directions as (x, z). Kept as an accessor so interior passes never have to
	## care about floors or edge types.
	func door_dirs() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for e in edges:
			if e.dir.x != 0 or e.dir.z != 0:
				out.append(Vector2i(e.dir.x, e.dir.z))
		return out

	func has_edge(dir: Vector3i) -> bool:
		for e in edges:
			if e.dir == dir:
				return true
		return false

	## Is this room already joined to `other`, by any kind of edge?
	func linked_to(other: RoomData, lay: DungeonLayout) -> bool:
		for e in edges:
			var n := lay.room_at(e.from_cell + e.dir)
			if n != null and n.cell == other.cell:
				return true
		return false

	func cells() -> Array:
		var out: Array = []
		for dx in size.x:
			for dz in size.z:
				out.append(cell + Vector3i(dx, 0, dz))
		return out


var rooms: Dictionary = {}            ## ANCHOR Vector3i -> RoomData (one entry per room)
var occupied: Dictionary = {}         ## every occupied Vector3i -> that room's anchor
var footprint_used: Dictionary = {}   ## Vector2i (x, z) -> anchor, ACROSS floors
var seed_used := 0

## HOW HARD THE WALK HAD TO WORK. Written by generate(), read by nothing that generates — they exist
## because the walk's acceptance rate is the quantity everything about this dungeon's size depends
## on, and until now there was NO INSTRUMENT FOR IT AT ALL.
##
## The comment on the relaxation ladder says it plainly: every condition added to the accept test
## lowers the rate, and the walk is the only thing that decides how many rooms a dungeon has. The
## guard against that is verify_dungeon's 6-to-14 room bound — which is a LAGGING proxy. It fires
## after a dungeon has already come out stunted, and it cannot tell "we got lucky" from "we had
## three tries to spare". Anything that adds a constraint to this loop needs to know the margin it
## is spending BEFORE it spends it.
## What the quotas asked for and did not get, and how many rooms had to give up a purpose so a
## required one could sit beside them. Counted rather than swallowed: a dungeon short of a prison
## still builds and still looks finished, so without a count a rule can stop being honoured and
## nothing anywhere says so.
var purposes_unmet: Array[String] = []
var purposes_demoted := 0

## What an authored DungeonGraph asked for and did not get — a pinned cell already taken, an
## edge between rooms that never became neighbours. Counted rather than swallowed, exactly like
## purposes_unmet above: a dungeon missing an authored room still builds and still looks
## finished, so without a count the author's graph can stop being honoured silently.
var graph_unmet: Array[String] = []

## Which attempt produced this layout, and whether even the last one fell short. `degraded` is the
## thing that must never become common and must never be silent: a dungeon short of a prison still
## builds and still looks finished.
var attempt := 0
var degraded := false

var tries_used := 0                           ## how many candidates were considered in total
var max_streak := 0                           ## longest run of consecutive rejections
var relax_max := 0                            ## highest rung of the ladder the walk had to climb

## WHAT THE DEMAND FILTER DID, and it is instrumented rather than trusted because it is the only
## thing in this file that can lower the walk's acceptance rate on purpose.
##
## `pool_escapes` is the one that would otherwise be invisible. When _pick_module's pool comes back
## empty it returns the unconstrained 1x1 SILENTLY, by design — right for the soft constraints it was
## written for, and a trap for this one, because the fallback is exactly the shape a demand for a
## gallery was filtering against. An over-narrow filter would quietly produce the thing it was
## filtering FOR the absence of, and the only guard that could notice is a 200-seed aggregate.
var demand_steered := 0                       ## tries where the pool was narrowed to owed kinds
var demand_missed := 0                        ## narrowed to nothing, so the whole pool was used
var demand_dropped := false                   ## patience ran out; steering off for the rest of the walk
var pool_escapes := 0                         ## _pick_module fell through to RoomModule.plain()


## Build a layout. seed_value 0 = random (the chosen seed is stored in `seed_used` and printed by
## the generator for reproduction). A candidate room is accepted only if its whole block is free
## and it touches EXACTLY ONE existing room — that is what keeps the graph a tree and guarantees
## dead-ends for the specials, now stated per-ROOM rather than per-cell so halls work too.
## HOW MANY LAYOUTS A SEED MAY TRY before it ships one that does not satisfy its own rules. Four,
## and the cost is nothing: a walk finishes inside 70 tries against a budget of 1600, so four
## attempts is still under a fifth of what one layout is allowed to spend.
const MAX_ATTEMPTS := 4


## Build a layout that satisfies the dungeon's own rules, or the best of MAX_ATTEMPTS that do not.
##
## THE RE-ROLL IS THE BACKTRACK, at whole-layout granularity, and that is deliberate rather than a
## compromise. `_place` has no inverse — `rooms`, `occupied`, `footprint_used` and `edges` would all
## need one — so there is nowhere to un-place a room and try another. Regenerating is the only undo
## this generator has, and a quota that cannot be met is exactly the situation it is for.
##
## `seed_used` IS THE CALLER'S SEED AND NEVER CHANGES, on any attempt. It is printed for
## reproduction, and it is the key every room's interior randomness hangs off — RoomContext.stream
## and roll_for both derive from it. Moving it on a re-roll would reshuffle the inside of every room
## in the dungeon for a reason that has nothing to do with any room. The attempt number is carried
## separately and only ever reaches the RNG.
##
## ATTEMPT 0 IS EXACTLY WHAT IT ALWAYS WAS, seeded straight from the root. That asymmetry is what
## makes "a seed that needs no re-roll produces a bit-identical dungeon" true, which is what makes
## the measurement of this change clean: only the seeds that actually re-rolled moved.
static func generate(seed_value: int, room_count: int, stair_count := 1,
		loop_count := 2, graph: DungeonGraph = null) -> DungeonLayout:
	var root := seed_value if seed_value != 0 else (randi() % 1000000 + 1)
	var best: DungeonLayout = null
	for attempt in MAX_ATTEMPTS:
		var lay := _generate_once(root, attempt, room_count, stair_count, loop_count, graph)
		lay.attempt = attempt
		# THE INDEPENDENT VERIFIER DECIDES, not the seater's own opinion of how it did. check_purposes
		# re-derives every rule from `rooms` and `edges`, so it also catches an over-cap or a
		# forbidden adjacency the seater thought it had avoided.
		if lay.check_purposes().is_empty():
			return lay
		# Keep the least-bad, so a dungeon that can never satisfy its rules still ships the closest
		# thing rather than the last thing tried.
		if best == null or lay.check_purposes().size() < best.check_purposes().size():
			best = lay
	best.degraded = true
	return best


static func _generate_once(root: int, attempt: int, room_count: int, stair_count: int,
		loop_count: int, graph: DungeonGraph = null) -> DungeonLayout:
	var lay := DungeonLayout.new()
	lay.seed_used = root
	var rng := RandomNumberGenerator.new()
	rng.seed = root if attempt == 0 else hash("%d|reroll|%d" % [root, attempt])

	var start := RoomData.new()
	start.type = RoomType.START                          # always 1x1: the spawn should be plain
	lay._place(start)

	# THE AUTHORED ROOMS GO IN FIRST, before the walk, so the walk treats them exactly as it
	# treats anything already standing: something to attach to and route around. With no graph
	# this whole block is two comparisons — the null path is the path every pinned hash
	# describes, and the graph suite holds a hash over that equality.
	var authored_stairs := 0
	var authored_loops := 0
	if graph != null:
		var seeded := _seed_from_graph(lay, graph, rng)
		authored_stairs = seeded.stairs
		authored_loops = seeded.loops

	var tries := 0
	var used := {}                            ## module id -> how many are already standing
	var streak := 0                           ## consecutive rejections, which drives the ladder
	var demand_streak := 0                    ## consecutive rejections WHILE STEERING; see DEMAND_PATIENCE
	while lay.rooms.size() < room_count and tries < TRY_BUDGET:
		tries += 1
		var relax := _relax_level(streak)
		# BOOKKEEPING ONLY — see the fields' docstring. Recorded before the accept test so `relax_max`
		# is the rung actually USED on a try, not the one a final rejected try happened to reach.
		lay.relax_max = maxi(lay.relax_max, relax)
		lay.max_streak = maxi(lay.max_streak, streak)
		var from: RoomData = lay.rooms[lay.rooms.keys()[rng.randi_range(0, lay.rooms.size() - 1)]]
		var d := DIRS[rng.randi_range(0, 3)]
		# WHAT THIS DUNGEON STILL OWES ITSELF, asked fresh each try because the answer changes as
		# rooms land. Both gates are checked here rather than inside the filter, so `owed` empty means
		# "not steering" for every reason at once and the rejection bookkeeping below has one thing
		# to test.
		var owed: Array = []
		if not lay.demand_dropped and lay.rooms.size() + DEMAND_SLACK < room_count:
			owed = lay._owed_kinds()
		var m := lay._pick_module(rng, from.dist + 1, used, relax, owed)
		var r := RoomData.new()
		r.size = m.size
		r.module_id = m.id
		r.kind = m.kind
		r.cell = lay._anchor_beside(from, d, r.size, rng)
		if not lay._block_free(r) or lay._touching_rooms(r).size() != 1 \
				or not lay._sockets_agree(r, m, from, d, relax):
			streak += 1
			# ONLY REJECTIONS THE STEERING COULD HAVE CAUSED COUNT AGAINST ITS PATIENCE. An unsteered
			# try that fails is the walk's ordinary weather and says nothing about the filter.
			if not owed.is_empty():
				demand_streak += 1
				if demand_streak >= DEMAND_PATIENCE:
					lay.demand_dropped = true
			continue
		demand_streak = 0
		lay._place_and_join(r, lay._touching_rooms(r))
		# Depth is tracked as we go so the NEXT pick knows which band it is in. Exact while the graph
		# is a tree, which it is for the whole of this loop; _bfs_distances re-derives it afterwards
		# anyway, so nothing downstream depends on this value.
		r.dist = from.dist + 1
		used[m.id] = int(used.get(m.id, 0)) + 1
		streak = 0
	lay.tries_used = tries

	lay._bfs_distances()
	# Authored stairs and loops COUNT AGAINST THE BUDGET rather than adding to it: the caller
	# asked for a dungeon with N floor changes, and drawing one of them by hand is not a request
	# for N+1. With no graph both subtractions are zero.
	lay._add_stairs(rng, maxi(0, stair_count - authored_stairs))
	lay._bfs_distances()                      # stairs lengthen paths, so depth has to be redone

	# specials: BOSS = farthest dead-end; TREASURE = another dead-end (grow one if needed).
	# Candidates are COMBAT rooms only — on the null path that is exactly the old
	# "not START" test (a STAIR room has two edges and is never a dead-end), and on the graph
	# path it keeps the pass's hands off anything the author already typed. A dungeon that
	# already HAS an authored boss gets no second one.
	var dead_ends: Array = []
	for anchor: Vector3i in lay.rooms:
		var r: RoomData = lay.rooms[anchor]
		if r.type == RoomType.COMBAT and r.edges.size() == 1:
			dead_ends.append(r)
	dead_ends.sort_custom(func(a, b): return a.dist > b.dist)
	if not lay._has_type(RoomType.BOSS):
		if not dead_ends.is_empty():
			dead_ends.pop_front().type = RoomType.BOSS
	if not lay._has_type(RoomType.TREASURE):
		if not dead_ends.is_empty():
			dead_ends.pop_front().type = RoomType.TREASURE
		else:
			var grown := lay._grow_dead_end(rng)
			if grown:
				grown.type = RoomType.TREASURE

	# Loops go in LAST, after the specials are settled. A junction dropped next to a dead-end turns
	# it into a through-room, so running this earlier ate the very dead-ends the boss and treasure
	# are chosen from. `dist` is deliberately NOT recomputed afterwards: it is depth along the
	# intended route, which is what difficulty should scale with.
	lay._add_loop_rooms(rng, maxi(0, loop_count - authored_loops))
	lay._type_shortcuts()
	lay._add_lock(rng)
	# LAST, AND THAT IS LOAD-BEARING. Three passes above this line rewrite adjacency after the walk
	# ends — _add_loop_rooms drops a junction and _place_and_join joins EVERYTHING it touches,
	# _grow_dead_end bolts a room onto an arbitrary parent, _add_stairs re-types a leaf. A purpose
	# decided any earlier would be a purpose decided against a graph that was still moving, and the
	# adjacency rules M9 is for would be violated afterwards by a pass with no way to know about them.
	lay._assign_purposes()
	return lay


# ---------------------------------------------------------------------------------------------
# AUTHORED SEEDING — the DungeonGraph path. Nothing below runs unless a graph was passed.
# ---------------------------------------------------------------------------------------------

## Place everything the author insisted on, growing outward from the start over the authored
## edges, then let the walk fill in around it. Placement reuses the walk's own primitives
## (_block_free, _anchor_beside, _place, _join) so an authored room obeys every rule a walked
## one does; what cannot be honoured lands in graph_unmet, counted rather than swallowed.
## Returns {"stairs": n, "loops": n} — the authored share of those budgets.
static func _seed_from_graph(lay: DungeonLayout, graph: DungeonGraph,
		_rng: RandomNumberGenerator) -> Dictionary:
	var stats := {"stairs": 0, "loops": 0}
	var by_id := {}
	for r in graph.rooms:
		if r.has("id"):
			by_id[int(r.id)] = r
	if not by_id.has(0):
		if not by_id.is_empty():
			lay.graph_unmet.append("no room id 0 — nothing seeded")
		return stats

	var adj := {}                             ## id -> Array of edge dicts touching it
	for e in graph.edges:
		if not e.has("a") or not e.has("b"):
			continue
		var a := int(e.a)
		var b := int(e.b)
		if a == b or not by_id.has(a) or not by_id.has(b):
			continue
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(e)
		(adj[b] as Array).append(e)

	# id 0 wears the already-placed START: kind, size and hints apply; type and cell do not.
	var start_rd: RoomData = lay.rooms[Vector3i.ZERO]
	_dress_from_dict(start_rd, by_id[0], true)
	var placed := {0: start_rd}

	var queue: Array = [0]
	while not queue.is_empty():
		var id: int = queue.pop_front()
		for e in adj.get(id, []):
			var nid := int(e.b) if int(e.a) == id else int(e.a)
			if placed.has(nid):
				continue
			var parent: RoomData = placed[id]
			var r := RoomData.new()
			_dress_from_dict(r, by_id[nid], false)
			var etype := int(e.get("type", EdgeType.CORRIDOR))
			var ok: bool
			if etype == EdgeType.STAIR:
				ok = _seed_stair(lay, parent, r, by_id[nid])
				if ok:
					stats.stairs += 1
			else:
				ok = _seed_beside(lay, parent, r, by_id[nid])
				if ok:
					lay._join(r, parent)
					_retype_pair(r, parent, etype, String(e.get("key_id", "key_0")))
			if ok:
				placed[nid] = r
				queue.append(nid)
			else:
				lay.graph_unmet.append("room %d could not be placed" % nid)

	# Edges the BFS tree did not use — the author's LOOPS. Both ends must already stand and be
	# neighbours on the grid; a loop between rooms that never became adjacent is unmet, because
	# an edge is a shared boundary and there is nothing here to build one out of.
	for e in graph.edges:
		if not e.has("a") or not e.has("b"):
			continue
		var ra: RoomData = placed.get(int(e.a))
		var rb: RoomData = placed.get(int(e.b))
		if ra == null or rb == null or ra == rb or ra.linked_to(rb, lay):
			continue
		var before := ra.edges.size()
		lay._join(ra, rb)
		if ra.edges.size() == before:
			lay.graph_unmet.append("edge %d-%d: rooms are not neighbours" % [int(e.a), int(e.b)])
			continue
		_retype_pair(ra, rb, int(e.get("type", EdgeType.CORRIDOR)),
				String(e.get("key_id", "key_0")))
		stats.loops += 1

	lay._bfs_distances()                      # the walk reads dist for its depth bands
	return stats


## Copy what a graph room dict says onto a RoomData. The start keeps its type and its origin;
## everything else may be typed by the author. `kind` names a RoomModule when one exists, which
## brings that module's size; an explicit `size` overrides it.
static func _dress_from_dict(rd: RoomData, d: Dictionary, is_start: bool) -> void:
	rd.authored = true
	rd.graph_id = int(d.get("id", -1))
	if d.get("shape") is Dictionary:
		rd.shape_data = (d.shape as Dictionary).duplicate(true)
	var kind := String(d.get("kind", ""))
	if kind != "":
		var m := RoomModule.by_id(kind)
		if m != null:
			rd.size = m.size
			rd.module_id = m.id
			rd.kind = m.kind
		else:
			rd.kind = kind
	if d.get("size") is Vector3i:
		rd.size = d.size
		rd.size.y = 1                         # rooms are single-storey; the graph cannot change that
		rd.module_id = RoomModule.for_size(rd.size).id
	if not is_start and d.has("type"):
		rd.type = int(d.type)
	rd.holds_key = String(d.get("holds_key", ""))
	rd.purpose_hint = String(d.get("purpose", ""))


## Stand `r` against `parent`. A pinned cell is honoured or refused; otherwise every anchor on
## every face is tried in a seeded order — exhaustive rather than sampled, because an author's
## room failing to place is a much louder event than a walk candidate being rejected.
static func _seed_beside(lay: DungeonLayout, parent: RoomData, r: RoomData,
		d: Dictionary) -> bool:
	if bool(d.get("has_cell", false)) and d.get("cell") is Vector3i:
		r.cell = d.cell
		if not lay._block_free(r):
			return false
		if not lay._touching_rooms(r).has(parent.cell):
			return false                      # pinned somewhere it never meets its parent
		lay._place(r)
		return true
	var spots: Array = []
	for dir in DIRS:
		var slides: Array = []
		if dir.x != 0:
			for s in range(-(r.size.z - 1), parent.size.z):
				slides.append(s)
		else:
			for s in range(-(r.size.x - 1), parent.size.x):
				slides.append(s)
		for s: int in slides:
			var a := parent.cell
			if dir.x > 0:
				a.x = parent.cell.x + parent.size.x
			elif dir.x < 0:
				a.x = parent.cell.x - r.size.x
			if dir.z > 0:
				a.z = parent.cell.z + parent.size.z
			elif dir.z < 0:
				a.z = parent.cell.z - r.size.z
			if dir.x != 0:
				a.z = parent.cell.z + s
			else:
				a.x = parent.cell.x + s
			spots.append(a)
	# Seeded order, the same idiom every post-walk pass uses: the choice is a property of the
	# seed, not of the order DIRS happens to be declared in.
	spots.sort_custom(func(u: Vector3i, v: Vector3i) -> bool:
		return hash("%d|seed_beside|%s" % [lay.seed_used, u]) \
				< hash("%d|seed_beside|%s" % [lay.seed_used, v]))
	for a: Vector3i in spots:
		r.cell = a
		if not lay._block_free(r):
			continue
		var touching := lay._touching_rooms(r)
		# Exactly the walk's own acceptance: one neighbour, and it is the parent. Keeps every
		# authored room a tree node the later passes can reason about.
		if touching.size() == 1 and touching[0] == parent.cell:
			lay._place(r)
			return true
	return false


## An authored floor change, built the way _add_stairs builds one: the PARENT becomes the stair
## room and `r` lands one cell beyond it, one floor up. The run must be along X (the long axis —
## 20 m of run reads as stairs where 12 m reads as a ladder), so both X directions are tried in
## a seeded order. The start may not become a stairwell; it is the one room the spawn contract
## owns.
static func _seed_stair(lay: DungeonLayout, parent: RoomData, r: RoomData,
		d: Dictionary) -> bool:
	if parent.cell == Vector3i.ZERO:
		return false
	var runs: Array = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]
	runs.sort_custom(func(u: Vector3i, v: Vector3i) -> bool:
		return hash("%d|seed_stair|%s|%s" % [lay.seed_used, parent.cell, u]) \
				< hash("%d|seed_stair|%s|%s" % [lay.seed_used, parent.cell, v]))
	for onward: Vector3i in runs:
		var row := parent.cell
		var top_cell := _boundary_cell(parent, onward, row)
		r.cell = _outward_cell(parent, onward, row) + UP
		if bool(d.get("has_cell", false)) and d.get("cell") is Vector3i \
				and d.get("cell") != r.cell:
			continue
		if not lay._block_free(r):
			continue
		r.edges.append(Edge.make(-onward + DOWN, r.cell, EdgeType.STAIR))
		lay._place(r)
		parent.edges.append(Edge.make(onward + UP, top_cell, EdgeType.STAIR))
		parent.type = RoomType.STAIR
		parent.template_path = ""             # a flight of steps has no interior
		return true
	return false


## Re-type the edge pair _join just made — it appends one Edge to each room, so back() on both
## is exactly that pair.
static func _retype_pair(r: RoomData, other: RoomData, etype: int, key: String) -> void:
	if etype == EdgeType.CORRIDOR:
		return
	var mine: Edge = r.edges.back()
	var theirs: Edge = other.edges.back()
	mine.type = etype
	theirs.type = etype
	if etype == EdgeType.LOCKED:
		mine.key_id = key
		theirs.key_id = key


## The MISSION layer, laid over the space: bar one gate on the way to the boss and hide its key
## somewhere you can reach without passing it.
##
## The candidate gate must be a BRIDGE — cut it, and the boss becomes unreachable. That single
## test is what makes this survive loops: a shortcut spanning the gate would turn the lock into
## scenery, and checking reachability directly catches that without reasoning about the topology
## at all. The key then goes in the component the player is still standing in, as deep into it as
## possible, so finding it is a detour rather than a formality.
func _add_lock(rng: RandomNumberGenerator) -> bool:
	# An authored lock IS the dungeon's lock. On the null path no LOCKED edge exists before this
	# pass runs, so the scan finds nothing and behaviour is untouched.
	for anchor: Vector3i in rooms:
		for e in (rooms[anchor] as RoomData).edges:
			if e.type == EdgeType.LOCKED:
				return false
	var boss: RoomData = null
	for anchor: Vector3i in rooms:
		if (rooms[anchor] as RoomData).type == RoomType.BOSS:
			boss = rooms[anchor]
	if boss == null:
		return false

	var gates: Array = []
	for anchor: Vector3i in rooms:
		var r: RoomData = rooms[anchor]
		for e in r.edges:
			var n := room_at(e.from_cell + e.dir)
			if n == null or e.type == EdgeType.STAIR:
				continue                          # never bar a stairwell: it has nowhere else to go
			var near := _reachable_without(r.cell, n.cell)
			if near.has(boss.cell) or not near.has(Vector3i.ZERO):
				continue                          # not a bridge, or it strands the entrance
			# the reachable side must hold somewhere to hide the key that is not the start itself
			if near.size() < 2:
				continue
			gates.append({"room": r, "edge": e, "near": near,
					"k": hash("%d|%s|%s" % [seed_used, anchor, e.dir])})
	if gates.is_empty():
		return false
	gates.sort_custom(func(a, b): return a.k < b.k)
	var gate: Dictionary = gates[rng.randi_range(0, mini(3, gates.size()) - 1)]

	var key_id := "key_0"
	var r0: RoomData = gate.room
	var other := room_at((gate.edge as Edge).from_cell + (gate.edge as Edge).dir)
	for e in r0.edges:
		if room_at(e.from_cell + e.dir) == other:
			e.type = EdgeType.LOCKED
			e.key_id = key_id
	for e in other.edges:
		if room_at(e.from_cell + e.dir) == r0:
			e.type = EdgeType.LOCKED
			e.key_id = key_id

	# hide the key as deep into the still-reachable side as the layout allows
	var best: RoomData = null
	for cell: Vector3i in gate.near:
		var cand: RoomData = rooms[cell]
		if cand.type == RoomType.START or cand.type == RoomType.STAIR:
			continue
		if best == null or cand.dist > best.dist:
			best = cand
	if best == null:
		return false
	best.holds_key = key_id
	return true


## Every room reachable from the entrance if the edge between `a` and `b` did not exist.
func _reachable_without(a: Vector3i, b: Vector3i) -> Dictionary:
	var seen := {Vector3i.ZERO: true}
	var queue: Array = [rooms[Vector3i.ZERO]]
	while not queue.is_empty():
		var r: RoomData = queue.pop_front()
		for e in r.edges:
			var n := room_at(e.from_cell + e.dir)
			if n == null or seen.has(n.cell):
				continue
			if (r.cell == a and n.cell == b) or (r.cell == b and n.cell == a):
				continue                          # the cut edge
			seen[n.cell] = true
			queue.append(n)
	return seen


## GIVE EVERY ROOM A PURPOSE, in three steps: classify the default, seat the quotas, record what
## could not be seated.
##
## THIS IS WHERE THE GLOBAL AND LOCAL RULES MEET, and it runs here — after every pass that can move
## the graph — because a quota is a statement about the whole dungeon and adjacency is a statement
## about two rooms, and neither can be evaluated while rooms are still being added and joined.
func _assign_purposes() -> void:
	# An authored hint outranks the classifier — the author looked at the room and said what it
	# was for. It does NOT outrank check_purposes: an impossible hint re-rolls and degrades like
	# any other unmet rule, which is the honest failure. With no graph every hint is "" and this
	# is exactly the old classify line.
	for cell: Vector3i in rooms:
		var rd: RoomData = rooms[cell]
		rd.purpose = rd.purpose_hint if rd.purpose_hint != "" else RoomPurpose.classify(rd)

	# Hinted rooms are seated before the quotas sit down: the seater may not relabel them, and a
	# quota an author already filled by hand wants that many fewer seats from the pool.
	var seated := {}
	for cell: Vector3i in rooms:
		if (rooms[cell] as RoomData).purpose_hint != "":
			seated[cell] = true
	for id: String in RoomPurpose.CATALOGUE:
		var req: Dictionary = RoomPurpose.CATALOGUE[id]
		var hinted := 0
		for cell: Vector3i in rooms:
			if (rooms[cell] as RoomData).purpose_hint == id:
				hinted += 1
		for n in range(hinted, int(req["max"])):
			var pick := _seat_purpose(id, seated)
			if pick == null:
				break
			seated[pick.cell] = true
			pick.purpose = id
		if _count_purpose(id) < int(req["min"]):
			purposes_unmet.append(id)

	# AND NO TWO ALIKE ACROSS A DOOR. The last rule, after the quotas, because a seated purpose is
	# capped at one per dungeon and cannot twin — this is about the CLASSIFIED ones, which are as
	# many as the shapes allow. Three rooms in a row all announcing the same thing is a variety
	# failure the eye catches faster than any single wrong label.
	#
	# Ordered by the seeded hash so WHICH of a pair gives way is a property of the seed rather than
	# of the order rooms happen to sit in the dictionary — the same reason the seater sorts.
	var order: Array = rooms.keys()
	order.sort_custom(func(a, b):
		return hash("%d|twin|%s" % [seed_used, a]) < hash("%d|twin|%s" % [seed_used, b]))
	var settled := {}
	for cell: Vector3i in order:
		var rd: RoomData = rooms[cell]
		settled[cell] = true
		# A hinted room never gives way: the author twinned it on purpose or will hear about it
		# from check_purposes. Its unhinted neighbour can still be demoted.
		if not RoomPurpose.NO_TWIN.has(rd.purpose) or rd.purpose_hint != "":
			continue
		for e: Edge in rd.edges:
			var n := room_at(e.from_cell + e.dir)
			# Only against a room already settled, so a pair demotes exactly one of its two members
			# rather than both giving way to each other.
			if n == null or n.cell == rd.cell or not settled.has(n.cell):
				continue
			if n.purpose == rd.purpose:
				rd.purpose = RoomPurpose.DEMOTE_TO.get(rd.purpose, "chambers")
				purposes_demoted += 1
				break


## THE BEST ROOM FOR A PURPOSE, or null. Candidates are every room the requirement fits and no other
## quota has taken; the winner is the one that prefers the least contested host, breaks ties on a
## seeded hash, and — the local rule — has no neighbour it is forbidden to sit beside.
##
## ORDERED BY A SEEDED HASH, NOT BY DICTIONARY ORDER, which is the pattern `_add_lock` and
## `_add_loop_rooms` already use: `rooms` iterates in placement order, so picking from it directly
## would make the choice depend on the order the walk happened to succeed in rather than on the seed.
func _seat_purpose(id: String, seated: Dictionary) -> RoomData:
	var cands: Array = []
	for cell: Vector3i in rooms:
		var rd: RoomData = rooms[cell]
		if seated.has(cell) or not RoomPurpose.fits(rd, id):
			continue
		# AN OPPORTUNISTIC PURPOSE MAY NOT DELETE ANOTHER ONE. This is where the REQUIRED /
		# OPPORTUNISTIC distinction earns its keep rather than just describing the re-roll: a prison
		# is something the dungeon must have, so it may take the last vault and cost a reliquary; a
		# colosseum is something the dungeon may have, so it must not.
		#
		# Preferring a non-last room was not enough, and the measurement is why: a hall is the only
		# host `refectory` has AND most dungeons have exactly one, so "prefer" still took it every
		# time there was no alternative — refectory fell from 206 rooms in 400 seeds to 51. A
		# colosseum now appears only where a dungeon has a hall to spare.
		if int(RoomPurpose.CATALOGUE[id]["min"]) == 0 and _count_purpose(rd.purpose) <= 1:
			continue
		cands.append({
			"rd": rd,
			"rank": RoomPurpose.host_rank(rd, id),
			"clean": 0 if _neighbour_conflict(rd, id).is_empty() else 1,
			# IS THIS ROOM THE LAST OF WHAT IT CURRENTLY IS? Taking it does not just relabel a room,
			# it deletes a purpose from this dungeon entirely.
			"last": 1 if _count_purpose(rd.purpose) <= 1 else 0,
			"k": hash("%d|%s|%s" % [seed_used, rd.cell, id]),
		})
	if cands.is_empty():
		return null
	# A CLEAN SEAT FIRST, then a room that is not the last of its kind, then the preferred host, then
	# the seeded order.
	#
	# THE "LAST OF ITS KIND" RULE IS NOT A COLOSSEUM PATCH, and the measurement is why it exists. A
	# colosseum needs a hall, and a hall is the ONLY host `refectory` has — so seating one blind cut
	# refectory from 206 rooms in 400 seeds to 51, quietly deleting the dungeon's great-hall
	# statement from seven dungeons in eight. Relabelling a room is variety; relabelling the only
	# room of its type is subtraction. So a quota takes the last host of another purpose only when
	# nothing else will do, which means a dungeon with one hall keeps its refectory and a dungeon
	# with two can have both.
	cands.sort_custom(func(a, b):
		if a["clean"] != b["clean"]:
			return a["clean"] < b["clean"]
		if a["last"] != b["last"]:
			return a["last"] < b["last"]
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]
		return a["k"] < b["k"])
	var best: RoomData = cands[0]["rd"]
	# DEMOTE, and count it. If even the best seat has a forbidden neighbour, the neighbour gives up
	# its purpose rather than the dungeon giving up the rule — but a demotion is a room becoming
	# something plainer than it was, so it is recorded rather than absorbed.
	for other: RoomData in _neighbour_conflict(best, id):
		other.purpose = RoomPurpose.DEMOTE_TO.get(other.purpose, "chambers")
		purposes_demoted += 1
	return best


## Neighbours of `rd` whose purpose may not sit beside `id`.
func _neighbour_conflict(rd: RoomData, id: String) -> Array:
	var out: Array = []
	for e: Edge in rd.edges:
		var n := room_at(e.from_cell + e.dir)
		if n != null and RoomPurpose.apart(id, n.purpose):
			out.append(n)
	return out


func _count_purpose(id: String) -> int:
	var n := 0
	for cell: Vector3i in rooms:
		if (rooms[cell] as RoomData).purpose == id:
			n += 1
	return n


## EVERY RULE, RE-DERIVED FROM `rooms` AND `edges` ALONE. Written independently of the seater on
## purpose: the seater is a heuristic that tries to satisfy the rules, and this is what says whether
## it did. A verifier that shared the seater's logic would agree with it however wrong the seater
## was — the lesson already recorded in verify_dungeon about a test re-running the code's own
## predicate. It is also what the re-roll will consult.
func check_purposes() -> Array[String]:
	var bad: Array[String] = []
	for id: String in RoomPurpose.CATALOGUE:
		var req: Dictionary = RoomPurpose.CATALOGUE[id]
		var n := _count_purpose(id)
		if n < int(req["min"]):
			bad.append("%s: %d, wanted at least %d" % [id, n, req["min"]])
		if n > int(req["max"]):
			bad.append("%s: %d, over the cap of %d" % [id, n, req["max"]])
	for cell: Vector3i in rooms:
		var rd: RoomData = rooms[cell]
		if RoomPurpose.CATALOGUE.has(rd.purpose) and not RoomPurpose.fits(rd, rd.purpose):
			bad.append("%s at %s does not meet its own requirements" % [rd.purpose, rd.cell])
		for e: Edge in rd.edges:
			var n2 := room_at(e.from_cell + e.dir)
			if n2 != null and RoomPurpose.apart(rd.purpose, n2.purpose):
				bad.append("%s at %s shares a door with %s" % [rd.purpose, rd.cell, n2.purpose])
	return bad


## Which RoomModule to try next. Exactly ONE rng draw whatever the pool contains, so a filtered-out
## module cannot desynchronise the stream from one seed to the next.
##
## `relax` drops the soft constraints in order; see _relax_level for why any of them are droppable.
func _pick_module(rng: RandomNumberGenerator, dist: int, used: Dictionary,
		relax: int, owed: Array = []) -> RoomModule:
	# DEMAND CHANGES THE WEIGHTS AND NOTHING ELSE. `owed` names the KINDS an unmet required purpose
	# can live in; a pick that can house one is weighted up, and that is the whole of "purpose drives
	# placement" reaching the placement loop.
	#
	# A PREFERENCE, NOT A FILTER, and the difference was measured rather than argued. Restricting the
	# pool to the owed kinds took the re-roll rate to zero and cost the dungeon its population:
	# galleries down 63%, halls down 65%, landings down 63%, cells from 52% of all rooms to 69%. A
	# hall is the only host `refectory` has and _weave_suite requires every program to occur, so a
	# filter that starves halls deletes a program to guarantee a prison — which is a worse dungeon in
	# exchange for a rule nobody would have noticed being broken.
	#
	# The boost leaves every kind reachable and only tilts the odds, which is all the walk needed:
	# the failures it fixes are a SHORTAGE of hosts, not an absence of them.
	#
	# THE SINGLE DRAW BELOW MUST STAY SINGLE, and this is the one rule in this function that is not
	# about dungeons. The rng is one stream shared by the whole walk, so a second randf() here — or a
	# draw taken only on some branches — desynchronises every seed after it. Every pinned number in
	# the suite would move at once, and it would look exactly like a content change while being
	# nothing of the kind. So the filter runs entirely BEFORE the roll: it rewrites `pool` and
	# `total`, the roll is taken once whatever it decided, and _demand_suite asserts the rng state
	# advances identically with and without an `owed` set.
	#
	# AND IT CANNOT EMPTY THE POOL, which a filter could. Falling through to the bottom of this
	# function returns the unconstrained 1x1 — the shape a demand for a gallery is filtering FOR the
	# absence of — so an over-narrow filter would produce the very thing it was filtering against and
	# look like it had worked. A multiplier has no such failure: `pool_escapes` below still counts
	# the fall-through, and it is expected to stay at zero.
	var pool: Array[RoomModule] = []
	var wts: Array[float] = []
	var total := 0.0
	var boosted := false
	for m in RoomModule.catalogue():
		if relax < RELAX_DEPTH and (dist < m.min_dist or dist > m.max_dist):
			continue
		if relax < RELAX_CAPS and int(used.get(m.id, 0)) >= m.max_instances:
			continue
		var w := m.weight
		if owed.has(m.kind):
			w *= DEMAND_BOOST
			boosted = true
		pool.append(m)
		wts.append(w)
		total += w
	if not owed.is_empty():
		if boosted:
			demand_steered += 1
		else:
			demand_missed += 1   # the demand named kinds this depth band cannot supply

	var roll := rng.randf() * maxf(total, 0.0001)
	for i in pool.size():
		roll -= wts[i]
		if roll <= 0.0:
			return pool[i]
	# Either the pool was empty or float drift ate the last slice. Both want the same answer: the
	# unconstrained 1x1, which every gap in the grid can hold.
	pool_escapes += 1
	return RoomModule.plain()


## THE RELAXATION LADDER, and the reason it is not optional. Every condition added to the accept
## test lowers the walk's acceptance rate, and the walk is the only thing that decides how many
## rooms a dungeon has. verify_dungeon requires 6 to 14 of them; a run of bad luck against a depth
## band could otherwise return a four-room stub, and it would do it silently.
##
## So constraints are given up in order of how little the player can tell:
##   depth bands  a vault one step nearer the entrance than intended — invisible
##   instance caps a second great hall — noticeable, but only just
##   sockets      a landing entered from the side, which costs a staircase, not a dungeon
##
## At the top of the ladder the walk is exactly the old unconstrained one, so the worst case is the
## behaviour that shipped before modules existed.
const RELAX_NONE := 0
const RELAX_DEPTH := 1
const RELAX_CAPS := 2
const RELAX_SOCKETS := 3

## Rejections in a row before each rung. Generous: at 9 rooms the walk normally succeeds inside a
## handful of tries, so reaching 40 means something is genuinely wedged rather than unlucky.
const RELAX_STEP := 40
## Raised from 800 with the ladder: a try is cheap, and running out of tries is the one failure mode
## that produces a dungeon nobody asked for.
const TRY_BUDGET := 1600


static func _relax_level(streak: int) -> int:
	return clampi(streak / RELAX_STEP, RELAX_NONE, RELAX_SOCKETS)


## THE DEMAND BUDGET, AND IT IS DELIBERATELY NOT A RUNG OF THE LADDER ABOVE.
##
## The ladder gives up constraints "in order of how little the player can tell", and a missing prison
## is not one of those: it is the thing this whole layer exists to guarantee, so it belongs on the
## reject-and-re-roll side rather than in a list of things quietly surrendered. These two constants
## are the other question — not "may the walk stop wanting a prison" but "how much of the ROOM COUNT
## may wanting one cost", and the room count is what nobody can afford to lose.
##
## Why the cost is real: `kind` is chosen BEFORE the anchor, so narrowing to a shape pays that
## shape's rejection rate at _block_free, and a 1x3 fails far more often than a 1x1.
##
##   DEMAND_SLACK    stop steering when this few rooms are left to place. The demand is usually met
##                   in the first few picks, and the last rooms are the ones a run of rejections
##                   actually costs — so the end of the walk is always unsteered.
##   DEMAND_PATIENCE consecutive rejections while steering before steering is dropped for good. An
##                   over-narrow filter burns the try budget rather than the caller noticing.
##   DEMAND_MARGIN   how many hosts count as enough, and it is 3 rather than 1 on a measurement. Of
##                   33 re-rolled seeds in 400, only 7 had no host shape at all; in the other 26 the
##                   hosts existed and BOSS and TREASURE had taken them, because both are chosen
##                   from dead-ends and a `vault` is required to be one. Asking for one host would
##                   leave those 26 exactly where they were.
##   DEMAND_BOOST    how much an owed kind's weight is multiplied by. A preference, not a filter —
##                   see _pick_module for the distribution a filter cost.
##
## AND THE TWO GATES ARE PRECAUTIONARY RATHER THAN LOAD-BEARING, which is worth writing down because
## it is not what was expected. They were designed against a FILTER, which can narrow the pool to a
## shape that keeps failing _block_free and eat the room count. A multiplier cannot: every kind stays
## reachable however long the demand runs. Removing both gates entirely moves all three pinned hashes
## and breaks no floor in the suite — the room count, the aggregates and the program census all hold.
## So they bound a demand STRONGER than today's (a bigger boost, several required purposes, a filter
## if one is ever wanted) and nothing in the suite currently distinguishes them from doing nothing.
## Kept for that, and honestly labelled, rather than left looking like proven protection.
const DEMAND_SLACK := 3
const DEMAND_PATIENCE := 24
const DEMAND_MARGIN := 2
const DEMAND_BOOST := 2.0


## Which room KINDS the walk still owes a required purpose, empty when it owes none.
##
## Counted over what is already standing, by shape and depth only. Doors are not asked about because
## the walk is what decides them and they are still changing; `type` is not asked about because it is
## assigned after the walk ends — which is exactly why the margin above exists rather than a test.
func _owed_kinds() -> Array:
	var out: Array = []
	for id: String in RoomPurpose.CATALOGUE:
		var req: Dictionary = RoomPurpose.CATALOGUE[id]
		if int(req["min"]) < 1:
			continue                          # opportunistic: never a reason to steer, let alone re-roll
		var hosts: Array = req["hosts"]
		var have := 0
		for cell: Vector3i in rooms:
			var rd: RoomData = rooms[cell]
			if hosts.has(rd.kind) and rd.dist >= int(req["min_dist"]):
				have += 1
		if have >= DEMAND_MARGIN:
			continue
		for k: String in hosts:
			if not out.has(k):
				out.append(k)
	return out


## Would this join be legal for BOTH rooms? A door lands on the candidate's `-d` face and on the
## parent's `+d` face, and either module may refuse it — by face (sockets) or by count (max_edges).
##
## The parent test is the half that is easy to forget and impossible to notice: without it a `vault`
## keeps its single door and still sprouts a second one, because nothing else in the walk asks the
## room being built FROM whether it wants another neighbour.
func _sockets_agree(r: RoomData, m: RoomModule, from: RoomData, d: Vector3i, relax: int) -> bool:
	if relax >= RELAX_SOCKETS:
		return true
	var face := Vector2i(d.x, d.z)
	if not m.accepts_face(-face) or r.lateral_edges() >= m.max_edges:
		return false
	return _accepts_door(from, face)


## May an EXISTING room take one more lateral door on `face`? Asked by the walk, by the loop pass
## and by the grown dead-end, so a module's promise holds however the room is reached.
func _accepts_door(r: RoomData, face: Vector2i) -> bool:
	var m := RoomModule.by_id(r.module_id)
	if m == null:
		return true
	return m.accepts_face(face) and r.lateral_edges() < m.max_edges


## Where a block of `size` would sit if placed against `from` in direction `d`, offset randomly
## along the shared face so a hall does not always line up with its neighbour's corner.
func _anchor_beside(from: RoomData, d: Vector3i, size: Vector3i,
		rng: RandomNumberGenerator) -> Vector3i:
	var a := from.cell
	if d.x > 0:
		a.x = from.cell.x + from.size.x
	elif d.x < 0:
		a.x = from.cell.x - size.x
	if d.z > 0:
		a.z = from.cell.z + from.size.z
	elif d.z < 0:
		a.z = from.cell.z - size.z
	# slide along the face: the new block must still overlap `from`'s span on that axis
	if d.x != 0:
		a.z = from.cell.z + rng.randi_range(-(size.z - 1), from.size.z - 1)
	else:
		a.x = from.cell.x + rng.randi_range(-(size.x - 1), from.size.x - 1)
	return a


func _place(r: RoomData) -> void:
	rooms[r.cell] = r
	for c: Vector3i in r.cells():
		occupied[c] = r.cell
		footprint_used[Vector2i(c.x, c.z)] = r.cell


## Free = no cell taken, AND nothing already standing on that XZ footprint on ANY floor. The
## second half matters because the camera is fixed top-down: a room built above another would
## simply hide it, however much headroom the two have.
func _block_free(r: RoomData) -> bool:
	for c: Vector3i in r.cells():
		if occupied.has(c) or footprint_used.has(Vector2i(c.x, c.z)):
			return false
	return true


## First cell BEYOND a room in direction d, and the room's own cell on that boundary. Both have to
## respect `size`: for a two-cell hall, anchor + d is still inside the room.
static func _outward_cell(r: RoomData, d: Vector3i, row: Vector3i) -> Vector3i:
	var c := row
	if d.x > 0:
		c.x = r.cell.x + r.size.x
	elif d.x < 0:
		c.x = r.cell.x - 1
	if d.z > 0:
		c.z = r.cell.z + r.size.z
	elif d.z < 0:
		c.z = r.cell.z - 1
	return c


static func _boundary_cell(r: RoomData, d: Vector3i, row: Vector3i) -> Vector3i:
	var c := row
	if d.x > 0:
		c.x = r.cell.x + r.size.x - 1
	elif d.x < 0:
		c.x = r.cell.x
	if d.z > 0:
		c.z = r.cell.z + r.size.z - 1
	elif d.z < 0:
		c.z = r.cell.z
	return c


## Distinct existing rooms orthogonally adjacent to a candidate block.
func _touching_rooms(r: RoomData) -> Array:
	var seen := {}
	for c: Vector3i in r.cells():
		for d in DIRS:
			var anchor = occupied.get(c + d)
			if anchor != null:
				seen[anchor] = true
	return seen.keys()


func room_at(cell: Vector3i) -> RoomData:
	var anchor = occupied.get(cell)
	return rooms[anchor] if anchor != null else null


func _has_type(t: int) -> bool:
	for anchor: Vector3i in rooms:
		if (rooms[anchor] as RoomData).type == t:
			return true
	return false


## Place a room and join it to everything it touches.
func _place_and_join(r: RoomData, touching: Array) -> void:
	_place(r)
	for anchor in touching:
		_join(r, rooms[anchor])


## One reciprocal edge between two adjacent rooms, crossing at the MIDDLE cell of their shared
## boundary so the doorway sits centred on the wall the two actually share.
func _join(r: RoomData, other: RoomData) -> void:
	for d in DIRS:
		var crossings: Array = []
		for c: Vector3i in r.cells():
			var o := room_at(c + d)
			if o != null and o.cell == other.cell:
				crossings.append(c)
		if crossings.is_empty():
			continue
		crossings.sort()
		var mid: Vector3i = crossings[crossings.size() / 2]
		r.edges.append(Edge.make(d, mid))
		other.edges.append(Edge.make(-d, mid + d))
		return                            # two rectangles can only meet along one axis


## Close loops by dropping a JUNCTION room into a gap that already touches two rooms far apart in
## the tree. A pure spanning tree is a lobby with hallways: every room is entered and left the same
## way, and backtracking is the only route home. One junction turns that into a place with a way
## round — the shape Death's Door builds its whole world out of.
##
## Why a room and not just an edge: the walk accepts a candidate only if it touches EXACTLY ONE
## existing room, so the adjacency graph IS the tree — there are never two adjacent-but-unjoined
## rooms to connect after the fact. Something new has to go in the gap.
##
## The two rooms must already be at least 3 apart, or the "loop" is a second door onto the room
## next door, which reads as a mistake rather than a route.
func _add_loop_rooms(rng: RandomNumberGenerator, count: int) -> int:
	# A junction may be a hall too: a 2x1 block reaches two rooms that are offset from each other,
	# which a single cell wedged between them cannot, and those offsets are most of the gaps a
	# spindly tree leaves behind.
	const JUNCTION_SIZES: Array[Vector3i] = [
		Vector3i.ONE, Vector3i(2, 1, 1), Vector3i(1, 1, 2),
	]
	var made := 0
	for _n in count:
		var candidates: Array = []
		var seen := {}
		for anchor: Vector3i in rooms:
			for c: Vector3i in (rooms[anchor] as RoomData).cells():
				for d in DIRS:
					for js: Vector3i in JUNCTION_SIZES:
						var spot: Vector3i = c + d
						var key := [spot, js]
						if seen.has(key):
							continue
						seen[key] = true
						if _loop_candidate(spot, js):
							candidates.append({"cell": spot, "size": js})
		if candidates.is_empty():
			return made

		# seeded pick, independent of dictionary iteration order. (A sort_custom lambda cannot wrap
		# onto a second line, so the key is precomputed.)
		for cand in candidates:
			cand["k"] = hash("%d|%s|%s" % [seed_used, cand.cell, cand.size])
		candidates.sort_custom(func(a, b): return a.k < b.k)
		var chosen: Dictionary = candidates[rng.randi_range(0, mini(3, candidates.size()) - 1)]

		var junction := RoomData.new()
		junction.cell = chosen.cell
		junction.size = chosen.size
		# JUNCTION_SIZES is this pass's own list, so the module has to be looked up from the size
		# rather than chosen first. `kind` still says what the room is FOR; `module_id` says what
		# shape it is, and the two are not the same question.
		junction.module_id = RoomModule.for_size(chosen.size).id
		junction.kind = "junction"
		_place_and_join(junction, _touching_rooms(junction))
		made += 1
	return made


## Could a room of this size stand here and close a meaningful loop?
func _loop_candidate(spot: Vector3i, size: Vector3i) -> bool:
	var probe := RoomData.new()
	probe.cell = spot
	probe.size = size
	if not _block_free(probe):
		return false
	var touching := _touching_rooms(probe)
	if touching.size() < 2:
		return false
	# never hang a loop off a destination or a stairwell: the boss and treasure are meant to be
	# dead-ends, and a flight of steps has exactly two ends
	for a in touching:
		var t: int = (rooms[a] as RoomData).type
		if t == RoomType.BOSS or t == RoomType.TREASURE or t == RoomType.STAIR:
			return false
	# And no room may be given a door its module refuses. A junction joins EVERYTHING it touches, so
	# without this a vault three steps away quietly gains a second exit and stops being a dead-end —
	# after the specials have already been chosen on the strength of it being one.
	for c: Vector3i in probe.cells():
		for d in DIRS:
			var o := room_at(c + d)
			if o != null and not _accepts_door(o, Vector2i(-d.x, -d.z)):
				return false
	# and the two ends must already be far apart, or the "loop" is a second door onto the room
	# next door, which reads as a mistake rather than a route
	for i in touching.size():
		for j in range(i + 1, touching.size()):
			if _tree_distance(rooms[touching[i]], rooms[touching[j]], 3) >= 3:
				return true
	return false


## Walk the graph and label every edge that is NOT part of a spanning tree as a SHORTCUT. Doing it
## after the fact, rather than guessing at placement time, means the labelling is exactly right:
## a SHORTCUT is precisely an edge you could remove and still reach everything.
func _type_shortcuts() -> void:
	if not rooms.has(Vector3i.ZERO):
		return
	var visited := {Vector3i.ZERO: true}
	var queue: Array = [rooms[Vector3i.ZERO]]
	var tree := {}
	while not queue.is_empty():
		var r: RoomData = queue.pop_front()
		for e in r.edges:
			var n := room_at(e.from_cell + e.dir)
			if n == null or visited.has(n.cell):
				continue
			visited[n.cell] = true
			var key := [r.cell, n.cell]
			key.sort()
			tree[key] = true
			queue.append(n)
	for anchor: Vector3i in rooms:
		var r: RoomData = rooms[anchor]
		for e in r.edges:
			var n := room_at(e.from_cell + e.dir)
			if n == null:
				continue
			# Only a plain CORRIDOR may be relabelled. On the null path every edge here is
			# CORRIDOR or STAIR (and a stair edge is always a tree edge), so this changes
			# nothing; on the graph path it keeps an authored LOCKED or SECRET loop from being
			# flattened into a shortcut.
			if e.type != EdgeType.CORRIDOR:
				continue
			var key := [r.cell, n.cell]
			key.sort()
			if not tree.has(key):
				e.type = EdgeType.SHORTCUT


func _bfs_distances() -> void:
	var queue: Array[Vector3i] = [Vector3i.ZERO]
	var seen := {Vector3i.ZERO: true}
	(rooms[Vector3i.ZERO] as RoomData).dist = 0
	while not queue.is_empty():
		var anchor: Vector3i = queue.pop_front()
		var r: RoomData = rooms[anchor]
		for e in r.edges:
			var other := room_at(e.from_cell + e.dir)
			if other != null and not seen.has(other.cell):
				seen[other.cell] = true
				other.dist = r.dist + 1
				queue.append(other.cell)


## Send part of the dungeon upstairs. For a leaf room L hanging off parent P, turn L itself into
## the STAIR (it already has the right shape: one way in, one way on) and put a brand new room U
## beyond it, one cell further out AND one floor up.
##
##     P --- L --- U            becomes    P --- [stair] --- U   with U at floor+1
##
## Only 1x1 leaves whose run is along X qualify: the flight needs a straight 20 m run to read as
## stairs rather than a ladder, and a leaf's other neighbours are guaranteed free by the
## exactly-one-touching-room rule, so nothing has to be relocated.
func _add_stairs(rng: RandomNumberGenerator, count: int) -> RoomData:
	var made: RoomData = null
	for _n in count:
		var leaves: Array = []
		for anchor: Vector3i in rooms:
			var r: RoomData = rooms[anchor]
			if r.type == RoomType.START or r.type == RoomType.STAIR:
				continue
			# A vault is the layout's guaranteed dead-end, and the specials are chosen from those a
			# few lines later. Spending one on a stairwell trades the thing that was asked for
			# against the thing that was hoped for. `landing` exists to be spent here instead.
			if r.kind == "vault":
				continue
			# the run must be along X: that is the long axis, and 20 m (or 44 for a hall) of run
			# per floor reads as stairs where 12 m would read as a ladder
			if r.edges.size() != 1 or r.edges[0].dir.x == 0:
				continue
			leaves.append(r)
		# TRY THEM ALL, in a seeded order. Picking one at random and giving up if its upper cell
		# happened to be taken lost most of the stairs once rooms started varying in size.
		leaves.sort_custom(func(a, b): return _leaf_order(a, rng_salt) < _leaf_order(b, rng_salt))
		rng_salt += 1

		var built := false
		for candidate in leaves:
			var stair: RoomData = candidate
			var to_parent: Vector3i = stair.edges[0].dir
			var onward: Vector3i = -to_parent               # away from the parent, along the run
			# Walk out from the row the parent edge uses, past the room's own EXTENT — for a hall,
			# anchor + onward is still inside the stairwell.
			var row: Vector3i = stair.edges[0].from_cell
			var top_cell := _boundary_cell(stair, onward, row)
			var upper := RoomData.new()
			upper.cell = _outward_cell(stair, onward, row) + UP
			if not _block_free(upper):
				continue

			upper.edges.append(Edge.make(-onward + DOWN, upper.cell, EdgeType.STAIR))
			_place(upper)
			stair.edges.append(Edge.make(onward + UP, top_cell, EdgeType.STAIR))
			stair.type = RoomType.STAIR
			stair.template_path = ""                    # a flight of steps has no interior
			made = upper
			built = true
			break
		if not built:
			return made
	return made


var rng_salt := 0

## Deterministic shuffle key for a room, so candidate order depends on the seed but not on
## dictionary iteration order.
##
## LANDINGS FIRST. A `landing` module exists precisely to be lifted — one door, on an X face, which
## is the exact shape this pass can use — but declaring it bought nothing while the pass still shuffled
## every leaf together and took whichever came up. Sorting them to the front is the whole of the
## payoff: the module stops being a label and starts being a promise. Within each group the order is
## still seeded, so nothing becomes predictable.
func _leaf_order(r: RoomData, salt: int) -> int:
	var group := 0 if r.kind == "landing" else 1
	return group * 0x40000000 + (hash("%d|%s|%d" % [seed_used, r.cell, salt]) % 0x20000000)


## Steps between two rooms through the existing edges, giving up at `cap`.
func _tree_distance(from: RoomData, to: RoomData, cap: int) -> int:
	var queue: Array = [[from, 0]]
	var seen := {from.cell: true}
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var r: RoomData = item[0]
		var depth: int = item[1]
		if r.cell == to.cell:
			return depth
		if depth >= cap:
			continue
		for e in r.edges:
			var n := room_at(e.from_cell + e.dir)
			if n != null and not seen.has(n.cell):
				seen[n.cell] = true
				queue.append([n, depth + 1])
	return cap


## Attach one extra dead-end room somewhere (for the treasure room when the walk produced only
## one dead-end, e.g. a straight-line layout whose far end became the boss).
func _grow_dead_end(rng: RandomNumberGenerator) -> RoomData:
	var anchors := rooms.keys()
	for i in 80:
		var from: RoomData = rooms[anchors[rng.randi_range(0, anchors.size() - 1)]]
		# a flight of steps has exactly two ends; hanging a third room off one would be nonsense
		if from.type == RoomType.STAIR:
			continue
		var d := DIRS[rng.randi_range(0, 3)]
		var r := RoomData.new()
		# It is about to be the treasure room, so label it as what it is. A vault takes exactly one
		# door, which is precisely what this pass gives it.
		r.module_id = "vault"
		r.kind = "vault"
		r.cell = _anchor_beside(from, d, r.size, rng)
		if not _block_free(r) or _touching_rooms(r).size() != 1 \
				or not _accepts_door(from, Vector2i(d.x, d.z)):
			continue
		_place(r)
		# link just this pair; the rest of the graph is already wired
		var crossings: Array = []
		for c2: Vector3i in r.cells():
			var o2 := room_at(c2 - d)
			if o2 != null and o2.cell == from.cell:
				crossings.append(c2)
		crossings.sort()
		var mid: Vector3i = crossings[crossings.size() / 2]
		r.edges.append(Edge.make(-d, mid))
		from.edges.append(Edge.make(d, mid - d))
		r.dist = from.dist + 1
		return r
	return null


## Interior extent of a room: its cell block, less the passage gap on each axis.
static func size_of(rd: RoomData) -> Vector3:
	return Vector3(rd.size.x * CELL_PITCH.x - GAP, WALL_HEIGHT, rd.size.z * CELL_PITCH.y - GAP)


## World centre of one grid cell (relative to the dungeon root).
static func cell_origin(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * CELL_PITCH.x, cell.y * FLOOR_HEIGHT, cell.z * CELL_PITCH.y)


## World centre of a room — the centre of its whole cell block.
static func room_origin(rd: RoomData) -> Vector3:
	return Vector3(
		(rd.cell.x + (rd.size.x - 1) * 0.5) * CELL_PITCH.x,
		rd.cell.y * FLOOR_HEIGHT,
		(rd.cell.z + (rd.size.z - 1) * 0.5) * CELL_PITCH.y)


## Where an exit meets the wall, in ROOM-LOCAL space: centred on the cell the edge leaves from,
## pushed out to the wall on the edge's axis.
static func door_local(rd: RoomData, e: Edge) -> Vector3:
	var size := size_of(rd)
	var offset := cell_origin(e.from_cell) - room_origin(rd)
	if e.dir.x != 0:
		return Vector3(e.dir.x * size.x * 0.5, 0.0, offset.z)
	return Vector3(offset.x, 0.0, e.dir.z * size.z * 0.5)

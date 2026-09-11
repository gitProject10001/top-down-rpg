@tool
class_name DungeonGraph
extends Resource
## AUTHORED CONSTRAINTS for DungeonLayout.generate: the rooms you insist on, the edges you insist
## on, and nothing about the rest — the walk still fills the dungeon out to room_count around
## what you drew. Handed to generate() as an optional trailing argument; null means the layout
## is exactly the one that has always shipped (the graph suite holds a hash over that promise).
##
## Rooms and edges are ARRAYS OF DICTIONARIES rather than nested Resources, the same decision
## RoomContext made for Slot metadata: the editor for this data is the Forge graph canvas, not
## the inspector, and a dictionary round-trips a canvas without a class version to migrate.
##
## Room keys (all optional except id):
##   id:int        unique; id 0 IS the start room and always sits at the origin
##   label:String  display only
##   type:int      DungeonLayout.RoomType — id 0 is START regardless
##   kind:String   RoomModule id/kind ("cell", "vault", "hall", ...); picks size when known
##   size:Vector3i extent in cells (y forced to 1); overrides the kind's size
##   floor:int     display hint for the canvas; the STAIR edges are what actually change floors
##   cell:Vector3i exact anchor, honoured only with has_cell = true
##   has_cell:bool pin the room to `cell` instead of letting placement choose
##   holds_key:String  this room hides the key with that id
##   purpose:String    requested purpose ("prison", "church", ...) — a HINT the quota passes
##                     honour; an impossible one degrades honestly via check_purposes()
##   at:Vector2    canvas position, round-trips the graph editor and means nothing to layout
##
## Edge keys:  a:int  b:int  type:int (DungeonLayout.EdgeType, default CORRIDOR)  key_id:String

@export var rooms: Array[Dictionary] = []
@export var edges: Array[Dictionary] = []
@export var version := 1


## Structural validation, as messages rather than asserts — the canvas shows them and the
## seeding pass survives them. Empty = sound. Deliberately independent of DungeonLayout: this
## checks the GRAPH's own promises (ids unique, edges real, one start, connected), while
## placement failures are the layout's to report (DungeonLayout.graph_unmet).
func check() -> Array[String]:
	var bad: Array[String] = []
	var seen := {}
	for r in rooms:
		if not r.has("id"):
			bad.append("a room has no id")
			continue
		var id := int(r.id)
		if seen.has(id):
			bad.append("room id %d appears twice" % id)
		seen[id] = true
	if not rooms.is_empty() and not seen.has(0):
		bad.append("no room id 0 — the start room")
	var adj := {}
	for e in edges:
		if not e.has("a") or not e.has("b"):
			bad.append("an edge is missing an endpoint")
			continue
		var a := int(e.a)
		var b := int(e.b)
		if not seen.has(a) or not seen.has(b):
			bad.append("edge %d-%d references a room that does not exist" % [a, b])
			continue
		if a == b:
			bad.append("edge %d-%d joins a room to itself" % [a, b])
			continue
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	# Connectivity from the start: an unreachable authored room can never be placed (placement
	# grows outward from id 0), so it is a graph error, not a placement accident.
	if seen.has(0):
		var reach := {0: true}
		var queue: Array = [0]
		while not queue.is_empty():
			var id: int = queue.pop_front()
			for n: int in adj.get(id, []):
				if not reach.has(n):
					reach[n] = true
					queue.append(n)
		for id: int in seen:
			if not reach.has(id):
				bad.append("room %d is not connected to the start" % id)

	# AUTHORED SHAPES, validated by rebuilding a scratch through RoomShape's own guards and
	# asking its public validators — never by restating a rule (room_shape.gd's stated
	# contract). Doorway lines are deliberately NOT checked here: doors depend on the final
	# edges, which the walk may still add; plan_shell's protect restore is the enforcement.
	for r in rooms:
		if not r.has("shape"):
			continue
		var id := int(r.get("id", -1))
		if not r.shape is Dictionary:
			bad.append("room %d: shape is not a dictionary" % id)
			continue
		var shape := RoomShape.from_dict(r.shape)
		if shape == null:
			bad.append(("room %d: shape refused by its own guards (a cell off the grid, a "
					+ "duplicate column, a disconnected silhouette, an outline pit, or an "
					+ "illegal ramp)") % id)
			continue
		var grid := _expected_grid(r)
		if grid != Vector2i.ZERO and (shape.cols != grid.x or shape.rows != grid.y):
			bad.append("room %d: shape grid is %dx%d but the room's size gives %dx%d"
					% [id, shape.cols, shape.rows, grid.x, grid.y])
		if not shape.camera_legal():
			bad.append("room %d: shape hides more floor from the camera than MAX_HIDDEN allows"
					% id)
		var reached := _walkable_reach(shape)
		if reached < shape.tile_count():
			bad.append("room %d: %d of %d tiles unreachable across its levels — add a ramp"
					% [id, shape.tile_count() - reached, shape.tile_count()])
	return bad


## The tile grid this room's SIZE implies, mirroring _dress_from_dict's size resolution (kind's
## module size, overridden by an explicit `size`) and DungeonLayout.size_of's interior formula.
## Vector2i.ZERO = no opinion (unknown kind and no size — the walk decides).
static func _expected_grid(r: Dictionary) -> Vector2i:
	var size := Vector3i.ONE
	var kind := String(r.get("kind", ""))
	if kind != "":
		var m := RoomModule.by_id(kind)
		if m != null:
			size = m.size
		elif not r.get("size") is Vector3i:
			return Vector2i.ZERO
	if r.get("size") is Vector3i:
		size = r.size
	return Vector2i(
		int(round((size.x * DungeonLayout.CELL_PITCH.x - DungeonLayout.GAP) / RoomShape.TILE)),
		int(round((size.z * DungeonLayout.CELL_PITCH.y - DungeonLayout.GAP) / RoomShape.TILE)))


## How many tiles a body can actually REACH across the levels, by RoomShape.walkable — the one
## home of that rule. Started from a ground tile like the reach suite does.
static func _walkable_reach(shape: RoomShape) -> int:
	var start := Vector2i(-1, -1)
	for t: Vector2i in shape.tiles():
		if shape.level_of(t) == 0:
			start = t
			break
	if start == Vector2i(-1, -1):
		return 0
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var t: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if shape.is_solid(n) and not seen.has(n) and shape.walkable(t, d):
				seen[n] = true
				queue.append(n)
	return seen.size()

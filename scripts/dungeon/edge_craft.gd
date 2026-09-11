@tool # so the Dungeon Forge preview can call this in the editor. Inert at runtime; attached to no scene.
class_name EdgeCraft
extends Object
## The PASSAGE builder: floor strip, side walls, shared gate and its light, for one edge of the
## layout graph. Moved out of DungeonGenerator (it lived at dungeon_generator.gd:262-354) as
## statics over (parent, layout, theme), because two callers now need it: the generator building
## the real zone, and the Dungeon Forge editor preview building a stripped one. A preview that
## re-implemented the corridor would drift from the game one piece width at a time.
##
## The MOVE IS MECHANICAL and the output byte-identical: same RoomContext.roll_for keys, same
## positions, same piece names. The build suite instantiating zone_crypt.tscn is the proof.


## Every edge is stored on both rooms, so exactly one side must build the shared passage. Picking
## the lexicographically positive direction guarantees that: of `dir` and `-dir`, precisely one
## passes. (The obvious "skip any negative component" test does NOT — a stair edge like (-1, 1, 0)
## and its mate (1, -1, 0) each have a negative component, so BOTH sides skipped and the passage
## was never built.)
static func owns_edge(dir: Vector3i) -> bool:
	if dir.x != 0:
		return dir.x > 0
	if dir.z != 0:
		return dir.z > 0
	return dir.y > 0


## Build one connection between two rooms. Today every edge is a flat CORRIDOR; the other types
## are declared in DungeonLayout so the graph can express stairs, gates and loops before the
## geometry for them exists. Returns the shared gate, or null if the edge places no gate.
static func build_edge(parent: Node3D, layout: DungeonLayout, e: DungeonLayout.Edge,
		theme: DungeonTheme) -> DungeonDoor:
	match e.type:
		# A STAIR edge is still just a short passage — the climb happens inside the stair ROOM, so
		# by the time we get here both ends are already at the same height.
		DungeonLayout.EdgeType.CORRIDOR, DungeonLayout.EdgeType.STAIR, \
		DungeonLayout.EdgeType.SHORTCUT, DungeonLayout.EdgeType.LOCKED:
			return build_corridor(parent, layout, e, theme)
		_:
			push_warning("EdgeCraft: edge type %d not built yet" % e.type)
			return null


## The gap between adjacent rooms: floor strip, two side walls, and the shared gate. Positioned
## from the edge's own CELL boundary, not from room centres — a hall's exit is off-centre.
static func build_corridor(parent: Node3D, layout: DungeonLayout, e: DungeonLayout.Edge,
		theme: DungeonTheme) -> DungeonDoor:
	var from := DungeonLayout.cell_origin(e.from_cell)
	var to := DungeonLayout.cell_origin(e.from_cell + e.dir)
	var mid := (from + to) * 0.5
	# HEIGHT, not the average: across a stair edge the lower cell is a stair ROOM whose far door is
	# already up at the next floor, so the passage must meet the upper room's level. On a flat edge
	# both ends are equal and this is a no-op.
	mid.y = maxf(from.y, to.y)
	var along_x := e.dir.x != 0                          # corridor axis follows the edge direction
	var rot := 0.0 if along_x else PI * 0.5

	var strip := Kit.piece("corridor_floor", theme,
			RoomContext.roll_for(layout.seed_used, "corridor_floor", mid))
	strip.position = mid + Vector3(0, -(Kit.SIZES["floor_slab"] as Vector3).y, 0)
	strip.rotation.y = rot                               # the strip is authored along its length
	parent.add_child(strip)
	for side in [-1, 1]:
		var at := mid + (Vector3(0, 0, side * 1.25) if along_x else Vector3(side * 1.25, 0, 0))
		var wall := Kit.piece("corridor_wall", theme,
				RoomContext.roll_for(layout.seed_used, "corridor_wall", at))
		wall.position = at
		wall.rotation.y = rot
		parent.add_child(wall)

	# the slab is authored along local X; it must span ACROSS the passage direction
	var door := DungeonDoor.new()
	door.position = mid
	door.rotation.y = PI * 0.5 if along_x else 0.0
	parent.add_child(door)
	light_corridor(parent, layout, mid, along_x, theme)
	return door


## A LIGHT AT THE DOOR. Passages had none at all -- floor, two walls, a portcullis and nothing else
## -- so every gap between rooms was a black band the player crossed blind, and the doorway a room
## spends four course pieces framing led into nowhere.
##
## It is a FIXTURE, not a bare light. crypt.tres killed the room fill with the note "the room no
## longer has a light hanging in the middle of the air, and that is a deliberate art call": a source
## the player cannot see is the thing this crypt decided against. So this places the theme's own
## wall_anchor piece -- the candelabra -- which brings its own flames and its own themed light, and
## re-skins with everything else.
##
## SHADOWS OFF, and this one is not taste. show_around() hides ROOMS; corridor pieces are children of
## the generator and are therefore ALWAYS drawn and always lit. A shadow-casting candelabra in every
## passage is eight to eleven permanent casters, against the nine that
## docs/environment-pipeline-todo.md measures as the largest single line item in the frame at 2.07 ms.
static func light_corridor(parent: Node3D, layout: DungeonLayout, mid: Vector3, along_x: bool,
		theme: DungeonTheme) -> void:
	var piece := RoomDresser.piece_for(RoomPlan.T_WALL_ANCHOR, theme)
	if piece == "":
		return
	# Against the side wall rather than in the middle of the walk line. The passage is 2.6 m wide
	# (corridor_floor) with walls at +-1.25, so 0.85 stands it clear of both the masonry and the door.
	var side := 1.0 if RoomContext.roll_for(layout.seed_used, "corridor_light", mid) < 0.5 else -1.0
	var at := mid + (Vector3(0, 0, side * 0.85) if along_x else Vector3(side * 0.85, 0, 0))
	var lamp := Kit.piece(piece, theme, RoomContext.roll_for(layout.seed_used, "corridor_lamp", at))
	if lamp == null:
		return
	lamp.position = at
	parent.add_child(lamp)
	unshadow(lamp)


static func unshadow(node: Node) -> void:
	if node is Light3D:
		(node as Light3D).shadow_enabled = false
	for c in node.get_children():
		unshadow(c)

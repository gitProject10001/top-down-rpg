@tool
extends Node
## SPAWN AND DESPAWN, sections by distance: only the chunks around the FOCUS exist — mesh,
## collider, kit pieces and flora alike — and the rest of the map is numbers in a dictionary
## until somebody moves toward it. This is what makes a much bigger map affordable: the cost
## of the world is the cost of the visible ring, not of the map.
##
## The focus is the grouped player in game; `focus_node` overrides it — the EDITOR hands in
## its own viewport camera, so the preview ring follows wherever you fly (@tool exists for
## exactly this; the runtime zone builds this node at play time, never in a saved scene).
## When `far` is set (the whole-map backdrop), its canopy masses clear around the same focus,
## so real trees are never doubled by their own scenery.
##
## One chunk is built per physics tick (nearest first), so crossing a boundary costs a small
## slice of many frames instead of one big hitch. Chunks are deterministic by construction
## (mesh from WildsGen.mesh_chunk, flora hashed to WHERE), so despawn and respawn produce the
## same section, byte for byte — asserted in the streaming suite.
##
## Hysteresis: load inside `load_radius`, free only beyond `free_radius`. The gap is what
## stops a player pacing on a boundary from thrashing build/free every step.

const Flora := preload("res://scripts/wilds/wilds_flora.gd")

@export var load_radius := 110.0
@export var free_radius := 150.0

var spawn_cell := Vector2i(-1, -1)
var focus_node: Node3D = null                  ## overrides the player lookup (editor camera)
var far: Node3D = null                         ## optional FarLOD backdrop to clear around

var terrain: StaticBody3D = null
var flora_parent: Node3D = null
var map: WildsMap = null
var derived: Dictionary = {}
var style: WildsStyle = null

var _flora_chunks: Dictionary = {}            ## origin -> Node3D
var _player: Node3D = null


## In lazy (14-km) mode `p_derived` is EMPTY — each chunk asks the terrain for its own
## region — and `spawn_cell` must be set by the caller (a region has no global spawn).
func setup(p_terrain: StaticBody3D, p_flora: Node3D, p_map: WildsMap,
		p_derived: Dictionary, p_style: WildsStyle) -> void:
	terrain = p_terrain
	flora_parent = p_flora
	map = p_map
	derived = p_derived
	style = p_style
	if not derived.is_empty():
		spawn_cell = derived.get("spawn", spawn_cell)


## Build everything inside load_radius of a cell RIGHT NOW — the spawn ring, stood up
## synchronously before SpawnA is placed so there is ground to stand on.
func warm(cell: Vector2i) -> void:
	var focus := (Vector2(cell) + Vector2(0.5, 0.5)) * map.cell_size
	for origin in _ring(focus, load_radius):
		_grow(origin)


func _physics_process(_delta: float) -> void:
	if map == null or terrain == null:
		return
	var focus := _focus()
	if far != null and is_instance_valid(far) and far.has_method("clear_around"):
		far.call("clear_around", Vector3(focus.x, 0.0, focus.y), load_radius)
	# Free first (cheap), then build at most ONE chunk this tick, nearest first.
	for origin in _flora_chunks.keys():
		if _dist(origin, focus) > free_radius:
			terrain.drop_chunk(origin)
			(_flora_chunks[origin] as Node3D).free()
			_flora_chunks.erase(origin)
	var best := Vector2i(-1, -1)
	var best_d := load_radius
	for origin in _ring(focus, load_radius):
		if _flora_chunks.has(origin):
			continue
		var dist := _dist(origin, focus)
		if dist <= best_d:
			best_d = dist
			best = origin
	if best.x >= 0:
		_grow(best)


func _grow(origin: Vector2i) -> void:
	if _flora_chunks.has(origin):
		return
	terrain.ensure_chunk(origin)
	var src: Dictionary = derived
	if src.is_empty():
		# Lazy mode: the chunk's own region, with the zone's spawn grafted on (flora clears
		# the spawn lane and a region cannot know where that is).
		src = (terrain.region_for(origin) as Dictionary).duplicate()
		src.spawn = spawn_cell
	var holder := Node3D.new()
	holder.name = "Flora_%d_%d" % [origin.x, origin.y]
	flora_parent.add_child(holder)
	Flora.build(holder, map, src, terrain, style,
			Rect2i(origin, Vector2i(WildsGen.CHUNK, WildsGen.CHUNK)))
	_flora_chunks[origin] = holder


## The focus_node when set (the editor camera), else the grouped player, else the spawn — in
## TERRAIN-LOCAL XZ metres, the frame every distance here is measured in.
func _focus() -> Vector2:
	if focus_node != null and is_instance_valid(focus_node) and focus_node.is_inside_tree():
		var flocal := terrain.to_local(focus_node.global_position)
		return Vector2(flocal.x, flocal.z)
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null:
		var local := terrain.to_local(_player.global_position)
		return Vector2(local.x, local.z)
	return (Vector2(spawn_cell) + Vector2(0.5, 0.5)) * map.cell_size


func _dist(origin: Vector2i, focus: Vector2) -> float:
	var half := WildsGen.CHUNK * map.cell_size * 0.5
	var centre := Vector2(origin) * map.cell_size + Vector2(half, half)
	return centre.distance_to(focus)


## Every chunk origin whose centre lies within `radius` of `focus`. Bounded to the radius
## box, never the map — at 7000 cells a whole-map scan would be 48k origins per tick.
func _ring(focus: Vector2, radius: float) -> Array:
	var span := WildsGen.CHUNK * map.cell_size
	var lo_x := clampi(int(floor((focus.x - radius) / span)) * WildsGen.CHUNK, 0, map.cells_w)
	var hi_x := clampi(int(ceil((focus.x + radius) / span)) * WildsGen.CHUNK, 0, map.cells_w)
	var lo_z := clampi(int(floor((focus.y - radius) / span)) * WildsGen.CHUNK, 0, map.cells_h)
	var hi_z := clampi(int(ceil((focus.y + radius) / span)) * WildsGen.CHUNK, 0, map.cells_h)
	var out: Array = []
	for oz in range(lo_z, hi_z + 1, WildsGen.CHUNK):
		for ox in range(lo_x, hi_x + 1, WildsGen.CHUNK):
			if ox < map.cells_w and oz < map.cells_h:
				var origin := Vector2i(ox, oz)
				if _dist(origin, focus) <= radius:
					out.append(origin)
	return out

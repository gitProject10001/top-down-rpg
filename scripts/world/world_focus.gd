@tool
extends OWDBPosition
## WHERE THE WORLD IS LOADED AROUND: the one point Open World Database streams about.
##
## `OWDBPosition` is a marker that reports where it stands; it does not know how to find a
## player. This one does, in the order that survives every way a world is entered:
##
##   focus_node   an explicit target, when a tool wants to drive the stream itself
##   "player"     the group — the game's own player, wherever `World.go_to` parented it
##   the editor viewport camera, so flying through an open world loads what you fly over
##   map.spawn    nothing else exists yet: hold the ring the player is about to land in
##
## It lives on the ZONE, not on the player, on purpose. A generated world is entered two ways —
## pressed play on directly, or added under `main.tscn` by `World.go_to` — and only one of those
## has a player this scene could have been saved with a marker under. A node that goes looking
## works in both, and it is the same chain the tile streamer used before the addon replaced it.

## An explicit target. EMPTY = find one (the chain above).
@export var focus_node: Node3D = null
## Where to stand while there is no player and no camera — the world's spawn, in world XZ.
@export var home := Vector2.ZERO

var _player: Node3D = null


func _process(delta: float) -> void:
	global_position = point()
	super._process(delta)


## The point the world is streamed around, this frame.
func point() -> Vector3:
	if focus_node != null and is_instance_valid(focus_node) and focus_node.is_inside_tree():
		return focus_node.global_position
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	var cam := _editor_camera()
	if cam != null:
		return cam.global_position
	return Vector3(home.x, 0.0, home.y)


## THE DATABASE THIS POINT BELONGS TO. The addon looks one up from the CURRENT SCENE, which is
## right for a game whose world is the main scene and wrong for every way this one is entered: a
## generated world is added under `main.tscn` by `World.go_to`, instanced inside the scene you
## press play on, or stood up by a test with no current scene at all — and in the last of those
## the stock search finds nothing and this marker silently never registers. Look UP instead: the
## database is a sibling, or a sibling of an ancestor, and that is true in all three.
func _find_owdb() -> OpenWorldDatabase:
	var n: Node = get_parent()
	while n != null:
		for c: Node in n.get_children():
			if c is OpenWorldDatabase:
				return c
		n = n.get_parent()
	return super()


## The editor's own viewport camera, looked up dynamically so a release build never even parses
## the editor singleton.
func _editor_camera() -> Node3D:
	if not Engine.is_editor_hint():
		return null
	if not Engine.has_singleton("EditorInterface"):
		return null
	var ei: Object = Engine.get_singleton("EditorInterface")
	var vp: Object = ei.call("get_editor_viewport_3d", 0)
	return vp.call("get_camera_3d") as Node3D if vp != null else null


## How many units are standing. The stream is judged by this, without a profiler.
func standing() -> int:
	return int(owdb.get_currently_loaded_nodes()) if owdb != null else 0


func has_unit(id: String) -> bool:
	return owdb != null and owdb.loaded_nodes_by_uid.has(id)

class_name SeeThrough
extends Node
## KEEPS THE PLAYER VISIBLE THROUGH WHATEVER THEY WALK BEHIND.
##
## The companion to scripts/roof_fade.gd, and the reason there are two: RoofFade tweens a named
## mesh's `transparency` when the player trips an Area3D, which is exactly right for the
## hand-modelled zones, where "Roof" is a node you can point at. A GladeKit building has no such
## node — a GladeWall batches every brick in its footprint into one MultiMeshInstance per brick
## VARIANT, so the only node-level fade available is "the entire building at once", and the far wall
## would go with the near one.
##
## So this half of the problem is solved a fragment at a time instead, in painted_env.gdshader:
## anything inside the cone between the camera and the player, and nearer than the player, is
## stippled away. This node's whole job is to tell the shader where those two points are.
##
## INERT UNLESS IT IS RUNNING. `radius` 0 is the shader's off switch and the value left behind on
## exit, so a scene that never adds this node — or one that stops processing — renders exactly as it
## did before any of this existed.

## Radius of the hole, in metres, at the player. 0 disables.
@export var radius := 1.6
## Group the subject belongs to. The rig follows the same node.
@export var target_group := "player"
## Metres above the target's origin to aim at — feet are a poor centre for a hole meant to reveal
## a body.
@export var target_height := 1.0


func _ready() -> void:
	# so a paused or freed owner cannot leave the world permanently full of holes
	tree_exiting.connect(_disable)


func _exit_tree() -> void:
	_disable()


func _process(_delta: float) -> void:
	var target := get_tree().get_first_node_in_group(target_group) as Node3D
	var cam := get_viewport().get_camera_3d()
	if target == null or cam == null or not target.is_visible_in_tree() or radius <= 0.0:
		_disable()
		return
	RenderingServer.global_shader_parameter_set("see_through_target",
			target.global_position + Vector3.UP * target_height)
	RenderingServer.global_shader_parameter_set("see_through_radius", radius)


func _disable() -> void:
	RenderingServer.global_shader_parameter_set("see_through_radius", 0.0)

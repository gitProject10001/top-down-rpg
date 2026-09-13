extends Node
## Reveal player and nearby ground along the camera ray. Physics stays intact.
var group: Node3D
var player: CharacterBody3D
var camera: Camera3D
var meshes: Array[MeshInstance3D]=[]
var sections: Node3D
func _ready() -> void:
	sections=preload("res://scripts/village/architecture_sections.gd").new()
	sections.name="RevealSections"
	add_child(sections)

var _scan := 0.0
var _radius := 0.0
var _last_focus := Vector3.INF
var _last_camera := Vector3.INF
var _last_radius := -1.0
func collect(node: Node) -> void:
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(true): collect(child)
func _process(delta: float) -> void:
	if not is_instance_valid(group) or not is_instance_valid(player): return
	_scan-=delta
	var rescan := _scan<=0
	if rescan:
		meshes.clear(); collect(group); _scan=0.3
	_radius=move_toward(_radius,group.visibility_radius if group.courtyard_visibility else 0.0,delta*14)
	var shape: CollisionShape3D=player.get_node("Collision")
	var focus: Vector3= player.global_position+Vector3.UP*(shape.position.y-shape.shape.height*0.5)
	if not rescan and focus.distance_squared_to(_last_focus)<0.0001 and camera.global_position.distance_squared_to(_last_camera)<0.0001 and is_equal_approx(_radius,_last_radius): return
	_last_focus=focus; _last_camera=camera.global_position; _last_radius=_radius
	for mesh in meshes:
		if not is_instance_valid(mesh): continue
		mesh.set_instance_shader_parameter("reveal_focus",focus)
		mesh.set_instance_shader_parameter("reveal_camera",camera.global_position)
		mesh.set_instance_shader_parameter("reveal_radius",_radius)

	sections.update_sections(meshes,focus,camera.global_position,_radius)

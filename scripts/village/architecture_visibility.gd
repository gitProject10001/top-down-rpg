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

var _occlusion_meshes: Dictionary = {}
var _clear_time := 0.0
var occluded := false

func _player_occluded(focus: Vector3, height: float) -> bool:
	# Test the original visible geometry, ignoring the shader cut itself. This
	# prevents the reveal from switching itself off as soon as it exposes the player.
	for mesh in meshes:
		if not is_instance_valid(mesh) or mesh.mesh==null or not mesh.is_visible_in_tree(): continue
		var resource: Mesh=mesh.mesh
		var key := resource.get_instance_id()
		if not _occlusion_meshes.has(key):
			var supported := false
			for surface in resource.get_surface_count():
				var material := mesh.get_active_material(surface)
				if material is ShaderMaterial and material.shader and material.shader.resource_path in [
					"res://shaders/pixelart/painted_architecture.gdshader",
					"res://shaders/pixelart/roof_clay.gdshader",
					"res://addons/house_builder/plaster.gdshader"]: supported=true
			_occlusion_meshes[key]=resource.generate_triangle_mesh() if supported else null
		var tree: TriangleMesh=_occlusion_meshes[key]
		if tree==null: continue
		var inverse := mesh.global_transform.affine_inverse()
		for fraction in [0.45,0.85]:
			var target: Vector3= focus+Vector3.UP*height*fraction
			# Orthographic screen rays are parallel, not aimed at the camera position.
			var direction: Vector3= camera.global_basis.z if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else (camera.global_position-target).normalized()
			var end: Vector3= target+direction*minf(camera.far,target.distance_to(camera.global_position))
			var start: Vector3= target+direction*0.08
			if tree.intersect_segment(inverse*start,inverse*end).size()>0: return true
	return false

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
		var live := {}
		for mesh in meshes:
			if mesh.mesh: live[mesh.mesh.get_instance_id()]=true
		for key in _occlusion_meshes.keys():
			if not live.has(key): _occlusion_meshes.erase(key)
	var shape: CollisionShape3D=player.get_node("Collision")
	var focus: Vector3= player.global_position+Vector3.UP*(shape.position.y-shape.shape.height*0.5)
	var blocked: bool= group.courtyard_visibility and _player_occluded(focus,shape.shape.height)
	_clear_time=0.0 if blocked else _clear_time+delta
	if blocked: occluded=true
	elif _clear_time>=0.12 or not group.courtyard_visibility: occluded=false
	_radius=move_toward(_radius,group.visibility_radius if occluded else 0.0,delta*14)
	if not rescan and focus.distance_squared_to(_last_focus)<0.0001 and camera.global_position.distance_squared_to(_last_camera)<0.0001 and is_equal_approx(_radius,_last_radius): return
	_last_focus=focus; _last_camera=camera.global_position; _last_radius=_radius
	for mesh in meshes:
		if not is_instance_valid(mesh): continue
		mesh.set_instance_shader_parameter("reveal_focus",focus)
		mesh.set_instance_shader_parameter("reveal_camera",camera.global_position)
		mesh.set_instance_shader_parameter("reveal_radius",_radius)

	sections.update_sections(meshes,focus,camera.global_position,_radius)

@tool
extends AnimatableBody3D
signal changed(opened: bool)
var opened := false
var open_angle := PI*0.55
var door_width := 1.2
var closed_frame := Transform3D.IDENTITY
var motion: Tween
var highlighted := false
var _highlight_material: ShaderMaterial
var leaf_height := 2.0
func configure(frame: Transform3D,w: float,h: float,material: Material,initial_open: bool=false) -> void:
	closed_frame=frame; transform=frame; door_width=w
	leaf_height=h-0.025
	sync_to_physics=false
	var leaf := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=Vector3(w-0.035,h-0.025,0.045)
	leaf.mesh=mesh; leaf.material_override=material
	leaf.position=Vector3(w*0.5,h*0.5,0)
	add_child(leaf)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=mesh.size; collision.shape=box; collision.position=leaf.position
	add_child(collision)
	opened=initial_open
	_apply_angle(PI*0.55 if opened else 0.0)
func toggle(actor_position: Vector3) -> bool:
	var local := closed_frame.affine_inverse()*(get_parent() as Node3D).to_local(actor_position)
	if opened and absf(local.z)<0.55 and local.x>-0.3 and local.x<door_width+0.3: return false
	if motion and motion.is_running(): return false
	if not opened: open_angle=PI*0.55*(1.0 if local.z>=0.0 else -1.0)
	opened=not opened
	var angle := atan2((closed_frame.basis.inverse()*basis).z.x,(closed_frame.basis.inverse()*basis).z.z)
	motion=create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	motion.tween_method(_apply_angle,angle,open_angle if opened else 0.0,0.32).set_trans(Tween.TRANS_SINE)
	changed.emit(opened)
	return true
func _apply_angle(angle: float) -> void:
	transform=closed_frame*Transform3D(Basis(Vector3.UP,angle),Vector3.ZERO)
func set_cutaway(cut: bool) -> void:
	# Doors remain complete, including while the surrounding architecture is cut.
	visible=true
	var leaf: MeshInstance3D=get_child(0)
	var shown := leaf_height
	leaf.scale.y=shown/leaf_height
	leaf.position.y=shown*0.5

func set_highlight(active: bool) -> void:
	if highlighted==active: return
	highlighted=active
	if active and _highlight_material==null:
		_highlight_material=ShaderMaterial.new()
		_highlight_material.shader=preload("res://shaders/pixelart/door_highlight.gdshader")
	var leaf: MeshInstance3D=get_child(0)
	leaf.material_overlay=_highlight_material if active else null

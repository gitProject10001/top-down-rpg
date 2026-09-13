@tool
extends Node3D
## Authored stair attached to a semantic edge of its parent terrace.
@export_storage var component_id := ""
@export_enum("Frontale", "Destra", "Sinistra") var side := 0:
	set(value): side=clampi(value,0,2); changed()
@export_range(0.9,2.4,0.1) var width := 1.2:
	set(value): width=value; changed()
@export_range(-1,1,0.05) var offset := 0.0:
	set(value): offset=value; changed()
@export_range(-5,5,0.1) var ground_level := 0.0:
	set(value): ground_level=value; changed()
@export var enabled := true:
	set(value): enabled=value; changed()
var visual: Node3D
func terrace() -> Node3D:
	var n := get_parent()
	while n:
		if n.has_method("stair_frame"): return n
		n=n.get_parent()
	return null
func changed() -> void:
	var host := get_parent()
	if host and host.has_method("stair_frame"): host.changed()
func _enter_tree() -> void:
	if component_id.is_empty(): component_id="stair_"+str(Time.get_ticks_usec())+"_"+str(get_instance_id())
	changed()
func _exit_tree() -> void: changed()
func rebuild(material: Material) -> void:
	var host := terrace()
	if host==null: return
	if is_instance_valid(visual): visual.free()
	visual=Node3D.new(); add_child(visual,false,Node.INTERNAL_MODE_BACK)
	transform=host.stair_frame()
	var projection := 0.0
	var stair_width := width
	var rise: float=host.effective_elevation()-ground_level; var run: float=host.stair_run(); var center := 0.0
	var count := maxi(2,ceili(rise/0.18))
	box(Vector3(center,-0.06,projection+0.225),Vector3(stair_width,0.12,0.45),material,false)
	for i in count:
		box(Vector3(center,-rise*(i+0.5)/count-0.06,projection+0.45+(i+0.5)*(run-0.45)/count),Vector3(stair_width,0.12,(run-0.45)/count+0.015),material,false)
	var body := StaticBody3D.new(); body.name="StairRamp"; var collision := CollisionShape3D.new(); var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for x in [center-stair_width*0.5,center+stair_width*0.5]:
		points.append(Vector3(x,-rise-0.12,projection)); points.append(Vector3(x,0.02,projection-0.08)); points.append(Vector3(x,0.02,projection+0.45))
		points.append(Vector3(x,-rise+0.01,projection+run)); points.append(Vector3(x,-rise-0.12,projection+run))
	shape.points=points; collision.shape=shape; body.add_child(collision); visual.add_child(body)
	for x in [center-stair_width*0.5-0.04,center+stair_width*0.5+0.04]:
		beam(Vector3(x,0.96,projection),Vector3(x,0.96,projection+0.45),0.10,material)
		beam(Vector3(x,0.96,projection+0.45),Vector3(x,-rise+0.96,projection+run),0.10,material)
		beam(Vector3(x,-0.15,projection),Vector3(x,-rise-0.15,projection+run),0.15,material)
		for i in count+1:
			box(Vector3(x,-rise*i/count+0.46,projection+0.45+(run-0.45)*i/count),Vector3(0.065,0.96,0.065),material)
func box(center: Vector3,size: Vector3,material: Material,solid: bool=true) -> void:
	var mesh := MeshInstance3D.new(); var shape := BoxMesh.new(); shape.size=size
	mesh.mesh=shape; mesh.material_override=material; mesh.position=center; visual.add_child(mesh)
	if not solid: return
	var body := StaticBody3D.new(); var collision := CollisionShape3D.new(); var collider := BoxShape3D.new(); collider.size=size
	collision.shape=collider; body.add_child(collision); body.position=center; visual.add_child(body)

func beam(a: Vector3,b: Vector3,thickness: float,material: Material) -> void:
	var pose := Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5)
	var mesh := MeshInstance3D.new(); var shape := BoxMesh.new(); shape.size=Vector3(thickness,a.distance_to(b),thickness)
	mesh.mesh=shape; mesh.material_override=material; mesh.transform=pose; visual.add_child(mesh)
	var body := StaticBody3D.new(); var collision := CollisionShape3D.new(); var solid := BoxShape3D.new(); solid.size=shape.size
	collision.shape=solid; body.add_child(collision); body.transform=pose; visual.add_child(body)

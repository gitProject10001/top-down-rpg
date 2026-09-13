@tool
extends Node3D
## Authored attachment. Host IDs refer to semantic facades, never mesh triangles.
@export_storage var component_id := ""
@export_enum("main/front", "main/back", "main/right", "main/left") var host_id := "main/front":
	set(value): host_id=value; changed()
@export_range(-1,1,0.01) var along := 0.0:
	set(value): along=value; changed()
@export_range(0,8,0.1) var elevation := 2.8:
	set(value): elevation=value; changed()
@export_range(1.6,8,0.1) var balcony_width := 3.0:
	set(value): balcony_width=value; changed()
@export_range(0.8,4,0.1) var projection := 1.5:
	set(value): projection=value; changed()
@export var create_door := true:
	set(value): create_door=value; changed()
@export var door_open := false
var visual: Node3D
func house() -> Node:
	return get_parent().get_parent() if get_parent() else null
func wall() -> int:
	return ["main/front","main/back","main/right","main/left"].find(host_id)
func changed() -> void:
	var h := house()
	if h and h.has_method("request_rebuild"): h.request_rebuild()
func _enter_tree() -> void:
	for sibling in get_parent().get_children():
		if sibling!=self and sibling.get_script()==get_script() and sibling.component_id==component_id: component_id=""
	if component_id.is_empty(): component_id="balcony_"+str(Time.get_unix_time_from_system()).replace(".","_")+"_"+str(get_instance_id())
	changed()
func _exit_tree() -> void: changed()
func opening_record() -> Dictionary:
	return {"kind":"door","wall":wall(),"u":along,"floor_y":elevation,"width":1.0,"height":2.0,"component_id":component_id,"open":door_open}
func validation_error() -> String:
	var h := house()
	if h==null or not h.has_method("wall_point"): return "Il balcone deve stare in Casa / Components."
	if wall()<0: return "Facciata non disponibile."
	var center: float=along*h.wall_length(wall())*0.5
	if absf(center)+balcony_width*0.5>h.wall_length(wall())*0.5-0.18: return "Balcone oltre il bordo: riduci larghezza o spostalo verso il centro."
	if elevation+2.12>h.wall_height: return "Muro troppo basso per la porta: alza le pareti o abbassa il balcone."
	if not h.wall_exposed(wall(),center,balcony_width*0.5): return "Facciata coperta dall'ala: scegli un altro aggancio."
	if create_door:
		for record in h.openings:
			var o: Dictionary=h.resolved_opening(record)
			if o.wall==wall() and absf(o.along-center)<(o.width+1.0)*0.5+0.16 and absf(o.y-elevation-1)<(o.height+2)*0.5+0.16:
				return "La porta incontra un'apertura manuale. Sposta il balcone o disattiva Crea porta per usare un accesso esistente."
	for other in h.attached_components():
		if other==self: continue
		if other.host_id==host_id and absf(other.along-along)*h.wall_length(wall())*0.5<(other.balcony_width+balcony_width)*0.5+0.1 and absf(other.elevation-elevation)<2.2:
			return "Due balconi si sovrappongono sulla stessa facciata."
	return ""
func _get_configuration_warnings() -> PackedStringArray:
	var error := validation_error()
	return PackedStringArray() if error.is_empty() else PackedStringArray([error])
func refresh() -> void:
	if is_instance_valid(visual): visual.free()
	visual=Node3D.new(); visual.name="_Visual"; add_child(visual,false,Node.INTERNAL_MODE_BACK)
	var h := house()
	if h==null: return
	var tangent: Vector3=(h.wall_point(wall(),1,0)-h.wall_point(wall(),0,0)).normalized()
	transform=Transform3D(Basis(tangent,Vector3.UP,h.wall_normal(wall())),h.wall_point(wall(),along*h.wall_length(wall())*0.5,elevation))
	if Engine.is_editor_hint(): update_configuration_warnings()
	if not validation_error().is_empty(): return
	var material: Material=h._material(Vector2(0.5,0),Color(0.60,0.53,0.46))
	var count := ceili(balcony_width/0.18)
	for i in count:
		box(Vector3(-balcony_width*0.5+(i+0.5)*balcony_width/count,-0.08,projection*0.5),Vector3(balcony_width/count-0.008,0.16,projection+0.12),material)
	for x in [-balcony_width*0.5,balcony_width*0.5]:
		for z in [0.06,projection-0.06]: box(Vector3(x,0.5,z),Vector3(0.12,1.15,0.12),material)
		box(Vector3(x,0.95,projection*0.5),Vector3(0.10,0.1,projection),material)
		box(Vector3(x,-0.22,projection*0.5),Vector3(0.18,0.22,projection+0.2),material)
		for i in range(1,ceili(projection/0.25)):
			box(Vector3(x,0.48,i*projection/ceili(projection/0.25)),Vector3(0.055,0.85,0.055),material)
	box(Vector3(0,0.95,projection-0.06),Vector3(balcony_width,0.1,0.1),material)
	for i in range(1,ceili(balcony_width/0.25)):
		box(Vector3(-balcony_width*0.5+i*balcony_width/ceili(balcony_width/0.25),0.48,projection-0.06),Vector3(0.055,0.85,0.055),material)
	update_gizmos()
func box(center: Vector3,size: Vector3,material: Material) -> void:
	var mesh := MeshInstance3D.new(); var shape := BoxMesh.new(); shape.size=size
	mesh.mesh=shape; mesh.material_override=material; mesh.position=center; visual.add_child(mesh)
	var body := StaticBody3D.new(); var collision := CollisionShape3D.new(); var solid := BoxShape3D.new(); solid.size=size
	collision.shape=solid; body.add_child(collision); body.position=center; visual.add_child(body)

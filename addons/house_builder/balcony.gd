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
@export_storage var floor_id := "":
	set(value): floor_id=value; changed()
@export_storage var door_id := "":
	set(value): door_id=value; changed()
@export_group("Terrazza e scala esterna")
@export var support_posts := false:
	set(value): support_posts=value; changed()
@export var exterior_stairs := false:
	set(value): exterior_stairs=value; changed()
@export_range(0.9,2.4,0.1) var stair_width := 1.2:
	set(value): stair_width=value; changed()
@export_range(-1,1,0.05) var stair_offset := 0.0:
	set(value): stair_offset=value; changed()
@export_range(-5,5,0.1) var ground_level := 0.0:
	set(value): ground_level=value; changed()
@export var door_open := false
var visual: Node3D
func house() -> Node:
	return get_parent().get_parent() if get_parent() else null
func wall() -> int:
	var record := linked_door()
	return int(record.get("wall",0)) if not record.is_empty() else ["main/front","main/back","main/right","main/left"].find(host_id)
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
	return {"kind":"door","wall":wall(),"u":effective_along(),"floor_y":effective_elevation(),"width":1.0,"height":2.0,"component_id":component_id,"open":door_open}
func validation_error() -> String:
	var h := house()
	if h==null or not h.has_method("wall_point"): return "Il balcone deve stare in Casa / Components."
	if not floor_id.is_empty() and h.authored_floor(floor_id)==null: return "Il piano collegato è stato rimosso. Scegli un piano o Quota manuale."
	if not door_id.is_empty():
		var record := linked_door()
		if record.is_empty(): return "La porta collegata è stata rimossa. Scegli un altro accesso o una porta generata."
		if record.get("kind","window")!="door": return "L’apertura collegata non è più una porta."
		if absf(h.opening_floor_y(record)-effective_elevation())>0.06: return "Porta e balcone sono a quote diverse. Collega entrambi allo stesso piano."
		if float(record.get("width",1.0))+0.3>balcony_width: return "La porta è più larga del balcone. Aumenta la larghezza."
	if wall()<0 or wall()>3: return "Facciata non disponibile."
	if (support_posts or has_stairs()) and effective_elevation()-ground_level<0.3: return "La quota della terrazza deve superare il terreno di almeno 30 cm."
	if has_stairs() and stair_actual_width()>stair_edge_length()-0.4: return "Scala troppo larga per la terrazza: aumenta la larghezza del piano."
	var stair_count := 0
	for child in get_children():
		if child.has_method("terrace"): stair_count+=1
	if stair_count>1: return "Questa versione supporta una scala per terrazza. Rimuovi o sposta la scala duplicata."
	if has_stairs() and effective_elevation()-stair_ground()<0.3: return "La scala deve scendere almeno 30 cm rispetto al piano."
	var center: float=effective_along()*h.wall_length(wall())*0.5
	if absf(center)+balcony_width*0.5>h.wall_length(wall())*0.5-0.18: return "Balcone oltre il bordo: riduci larghezza o spostalo verso il centro."
	if effective_elevation()+2.12>h.wall_height: return "Muro troppo basso per la porta: alza le pareti o abbassa il balcone."
	if not h.wall_exposed(wall(),center,balcony_width*0.5): return "Facciata coperta dall'ala: scegli un altro aggancio."
	if create_door and door_id.is_empty():
		for record in h.openings:
			var o: Dictionary=h.resolved_opening(record)
			if o.wall==wall() and absf(o.along-center)<(o.width+1.0)*0.5+0.16 and absf(o.y-effective_elevation()-1)<(o.height+2)*0.5+0.16:
				return "La porta incontra un'apertura manuale. Sposta il balcone o disattiva Crea porta per usare un accesso esistente."
	for other in h.attached_components():
		if other==self: continue
		if other.wall()==wall() and absf(other.effective_along()-effective_along())*h.wall_length(wall())*0.5<(other.balcony_width+balcony_width)*0.5+0.1 and absf(other.effective_elevation()-effective_elevation())<2.2:
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
	transform=Transform3D(Basis(tangent,Vector3.UP,h.wall_normal(wall())),h.wall_point(wall(),effective_along()*h.wall_length(wall())*0.5,effective_elevation()))
	if Engine.is_editor_hint(): update_configuration_warnings()
	var authored_stair := stair_component()
	if authored_stair:
		authored_stair.visible=false
		if is_instance_valid(authored_stair.visual): authored_stair.visual.free()
	if not validation_error().is_empty(): return
	if authored_stair: authored_stair.visible=has_stairs()
	var material: Material=h._material(Vector2(0.5,0),Color(0.60,0.53,0.46))
	var count := ceili(balcony_width/0.18)
	for i in count:
		box(Vector3(-balcony_width*0.5+(i+0.5)*balcony_width/count,-0.08,projection*0.5),Vector3(balcony_width/count-0.008,0.16,projection+0.12),material)
	for edge in 3: build_railing(edge,material)
	for x in [-balcony_width*0.5,balcony_width*0.5]:
		box(Vector3(x,-0.22,projection*0.5),Vector3(0.18,0.22,projection+0.2),material)
	if support_posts:
		var rise := effective_elevation()-ground_level
		for x in [-balcony_width*0.5+0.10,balcony_width*0.5-0.10]:
			for z in [0.12,projection-0.12]: box(Vector3(x,-rise*0.5-0.08,z),Vector3(0.20,rise-0.16,0.20),material)
	if has_stairs(): build_stairs(material)
	update_gizmos()
func box(center: Vector3,size: Vector3,material: Material,solid: bool=true) -> void:
	var mesh := MeshInstance3D.new(); var shape := BoxMesh.new(); shape.size=size
	mesh.mesh=shape; mesh.material_override=material; mesh.position=center; visual.add_child(mesh)
	if not solid: return
	var body := StaticBody3D.new(); var collision := CollisionShape3D.new(); var collider := BoxShape3D.new(); collider.size=size
	collision.shape=collider; body.add_child(collision); body.position=center; visual.add_child(body)

func linked_door() -> Dictionary:
	var h := house()
	return h.opening_by_id(door_id) if h and h.has_method("opening_by_id") else {}
func effective_along() -> float:
	var record := linked_door()
	if record.is_empty(): return along
	var resolved: Dictionary=house().resolved_opening(record)
	return resolved.along/(house().wall_length(resolved.wall)*0.5)
func effective_elevation() -> float:
	var h := house()
	if h==null: return elevation
	if not floor_id.is_empty(): return h.floor_elevation(floor_id,elevation)
	var record := linked_door()
	return h.opening_floor_y(record) if not record.is_empty() else elevation

func stair_run() -> float: return (effective_elevation()-stair_ground())/tan(deg_to_rad(32.0))+0.45
func stair_center() -> float: return stair_actual_offset()*maxf(0,(stair_edge_length()-stair_actual_width())*0.5-0.20)
func build_stairs(material: Material) -> void:
	var stair := stair_component()
	if stair==null:
		stair=preload("res://addons/house_builder/exterior_stair.gd").new()
		stair.width=stair_width; stair.offset=stair_offset; stair.ground_level=ground_level
		visual.add_child(stair)
	stair.rebuild(material)

func stair_component() -> Node3D:
	for child in get_children():
		if child.has_method("terrace"): return child
	return null
func has_stairs() -> bool:
	var stair := stair_component()
	return stair.enabled if stair else exterior_stairs
func stair_side() -> int:
	var stair := stair_component()
	return stair.side if stair else 0
func stair_actual_width() -> float:
	var stair := stair_component()
	return stair.width if stair else stair_width
func stair_actual_offset() -> float:
	var stair := stair_component()
	return stair.offset if stair else stair_offset
func stair_ground() -> float:
	var stair := stair_component()
	return stair.ground_level if stair else ground_level
func stair_edge_length() -> float: return balcony_width if stair_side()==0 else projection
func edge_frame(edge: int) -> Transform3D:
	if edge==0: return Transform3D(Basis.IDENTITY,Vector3(0,0,projection))
	return Transform3D(Basis(Vector3.UP,PI*0.5 if edge==1 else -PI*0.5),Vector3(balcony_width*0.5*(1 if edge==1 else -1),0,projection*0.5))
func stair_frame() -> Transform3D:
	return edge_frame(stair_side())*Transform3D(Basis.IDENTITY,Vector3(stair_center(),0,0))
func build_railing(edge: int,material: Material) -> void:
	var length := balcony_width if edge==0 else projection
	var previous := visual; visual=Node3D.new(); visual.transform=edge_frame(edge); previous.add_child(visual)
	var spans: Array[Vector2]=[Vector2(-length*0.5,length*0.5)]
	if has_stairs() and stair_side()==edge:
		spans=[Vector2(-length*0.5,stair_center()-stair_actual_width()*0.5),Vector2(stair_center()+stair_actual_width()*0.5,length*0.5)]
	for span in spans:
		if span.y-span.x<0.01: continue
		box(Vector3((span.x+span.y)*0.5,0.95,-0.06),Vector3(span.y-span.x,0.1,0.1),material)
		for x in [span.x,span.y]: box(Vector3(x,0.5,-0.06),Vector3(0.08,1.1,0.08),material)
		var count := ceili((span.y-span.x)/0.25)
		for i in range(1,count): box(Vector3(lerpf(span.x,span.y,float(i)/count),0.48,-0.06),Vector3(0.055,0.85,0.055),material)
	visual=previous

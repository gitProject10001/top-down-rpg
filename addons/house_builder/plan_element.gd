@tool
extends Node3D
## Authored data lives on this node. Only _Visual is disposable.
const Door=preload("res://addons/house_builder/door.gd")
@export_enum("Stanza","Muro","Scala","Oggetto") var kind := 0:
	set(v): kind=v; dirty()
@export var roof_exit := false:
	set(v): roof_exit=v; dirty()
@export var dimensions := Vector3(3,2.6,3):
	set(v): dimensions=Vector3(maxf(v.x,0.12),maxf(v.y,0.12),maxf(v.z,0.12)); dirty()
@export_enum("ingresso","soggiorno","cucina","camera","ripostiglio") var room_type := "camera":
	set(v): room_type=v; dirty()
@export var display_name := "":
	set(v): display_name=v; dirty()
@export_storage var automatic_name := ""
@export var has_door := true:
	set(v): has_door=v; dirty()
@export_range(-0.85,0.85,0.01) var door_offset := 0.0:
	set(v): door_offset=v; dirty()
@export_range(0.7,2.0,0.05) var door_width := 1.2:
	set(v): door_width=v; dirty()
@export var asset: PackedScene:
	set(v): asset=v; dirty()
@export_enum("Tavolo","Sedia","Letto","Cassapanca","Scaffale") var prop_type := 0:
	set(v): prop_type=v; dirty()
@export_group("Generazione")
@export var stable_id := ""
@export var generated := false
@export var locked := false
@export_storage var baseline: Dictionary={}
@export_storage var room_ids: PackedStringArray=[]
var _pending := true
var _visual: Node3D
var _pose := Transform3D.IDENTITY
var _cut := false
var _warning_signature := ""
func _ready() -> void:
	_pose=transform; dirty()
func dirty() -> void:
	_pending=true
	if is_inside_tree(): update_gizmos()
func _process(_dt: float) -> void:
	if Engine.is_editor_hint() and kind==0: refresh_room_name()
	if transform!=_pose:
		_pose=transform
		if is_inside_tree(): update_gizmos()
	if _pending: rebuild()
	if Engine.is_editor_hint() and kind==2:
		var p=plan()
		var signature := str(transform,dimensions,p.floor_height if p else 0,p.house().dimensions() if p else Vector4.ZERO)
		if signature!=_warning_signature:
			_warning_signature=signature; update_configuration_warnings()
func refresh_room_name() -> void:
	if not is_inside_tree(): return
	var legacy := str(name).begins_with("Stanza_") or str(name)=="Stanza" or str(name).begins_with("@")
	if automatic_name=="" and not legacy: return
	if automatic_name!="" and str(name)!=automatic_name: return
	var title := display_name.strip_edges()
	if title=="": title={"ingresso":"Ingresso","soggiorno":"Soggiorno","cucina":"Cucina","camera":"Camera","ripostiglio":"Ripostiglio"}.get(room_type,room_type.capitalize())
	var candidate := title.validate_node_name(); var suffix := 2
	if candidate=="": candidate="Stanza"
	while get_parent().has_node(NodePath(candidate)) and get_parent().get_node(NodePath(candidate))!=self:
		candidate=title.validate_node_name()+"_%d"%suffix; suffix+=1
	name=candidate; automatic_name=str(name)
func record() -> Dictionary:
	var pose := transform
	var room=get_parent()
	var ids := room_ids
	if kind==3 and room!=null and room.get_script()==get_script() and room.kind==0:
		pose=room.transform*transform; ids=PackedStringArray([room.stable_id])
	var result := {"kind":kind,"dimensions":dimensions,"room_type":room_type,"position":pose.origin,"rotation":pose.basis.get_euler(),"has_door":has_door,"door_offset":door_offset,"door_width":door_width,"prop_type":prop_type,"asset":asset.resource_path if asset else "","room_ids":ids}
	if roof_exit: result["roof_exit"]=true
	return result
func protected_edit() -> bool:
	if locked or not generated: return true
	if baseline.is_empty(): return false
	if bool(baseline.get("roof_exit",false))!=roof_exit: return true
	var current := record()
	for key in current:
		if not baseline.has(key): return true
		var a=current[key]; var b=baseline[key]
		# Transform serialization can wrap Euler angles or round floating point values.
		if key=="rotation":
			if not Basis.from_euler(a).is_equal_approx(Basis.from_euler(b)): return true
		elif a is Vector3:
			if not a.is_equal_approx(b): return true
		elif a is float:
			if not is_equal_approx(a,float(b)): return true
		elif a!=b: return true
	return false
func accept_baseline() -> void: baseline=record().duplicate(true)
func plan() -> Node:
	var ancestor := get_parent()
	while ancestor!=null:
		if ancestor.has_method("level_records"): return ancestor
		ancestor=ancestor.get_parent()
	return null
func material(wood: bool) -> Material:
	var p=plan()
	if p and p.has_method("wood_material"): return p.wood_material() if wood else p.wall_material()
	var m := StandardMaterial3D.new(); m.albedo_color=Color(0.35,0.23,0.13) if wood else Color(0.62,0.44,0.25); return m
func box(p: Vector3,size: Vector3,mat: Material,solid: bool=true) -> MeshInstance3D:
	if size.x<0.001 or size.y<0.001 or size.z<0.001: return null
	var mesh := MeshInstance3D.new(); var cube := BoxMesh.new(); cube.size=size
	mesh.mesh=cube; mesh.material_override=mat; mesh.position=p; _visual.add_child(mesh)
	mesh.set_meta("height",size.y); mesh.set_meta("bottom",p.y-size.y*0.5)
	if solid:
		var body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var primitive := BoxShape3D.new()
		primitive.size=size; shape.shape=primitive; body.position=p; body.add_child(shape); _visual.add_child(body)
	return mesh
func rebuild() -> void:
	if not is_inside_tree(): return
	_pending=false
	if is_instance_valid(_visual): _visual.free()
	_visual=Node3D.new(); _visual.name="_Visual"; add_child(_visual,false,Node.INTERNAL_MODE_BACK)
	var wood := material(true)
	match kind:
		0: pass
		1:
			var length := dimensions.x; var h := dimensions.y; var t := dimensions.z
			var w := minf(door_width,length-0.3)
			if not has_door or w<0.7:
				box(Vector3(0,h*0.5,0),dimensions,material(false))
			else:
				var center := clampf(door_offset*length*0.5,-length*0.5+w*0.5+0.12,length*0.5-w*0.5-0.12)
				var left := center-w*0.5+length*0.5; var right := length*0.5-center-w*0.5
				var dh := minf(2.3,h-0.18)
				box(Vector3(-length*0.5+left*0.5,h*0.5,0),Vector3(left,h,t),material(false))
				box(Vector3(length*0.5-right*0.5,h*0.5,0),Vector3(right,h,t),material(false))
				box(Vector3(center,dh+(h-dh)*0.5,0),Vector3(w,h-dh,t),material(false))
				for sign_value in [-1,1]: box(Vector3(center+sign_value*(w*0.5+0.04),dh*0.5,0),Vector3(0.08,dh,t+0.06),wood,false)
				box(Vector3(center,0.04,0),Vector3(w,0.04,t+0.25),wood,false)
				var door := Door.new(); _visual.add_child(door)
				door.configure(Transform3D(Basis.IDENTITY,Vector3(center-w*0.5,0,0)),w,dh,wood)
		2:
			for i in 18:
				var rise := (i+1)*stair_height()/18.0
				box(Vector3(0,rise*0.5,dimensions.z*0.5-(i+0.5)*dimensions.z/18.0),Vector3(dimensions.x,rise,dimensions.z/18.0),wood,false)
			var hull := ConvexPolygonShape3D.new(); var points := PackedVector3Array()
			for x in [-dimensions.x*0.5,dimensions.x*0.5]:
				points.append(Vector3(x,0,dimensions.z*0.5)); points.append(Vector3(x,0,-dimensions.z*0.5)); points.append(Vector3(x,stair_height()+0.05,-dimensions.z*0.5))
			hull.points=points
			var body := StaticBody3D.new(); var shape := CollisionShape3D.new(); shape.shape=hull; body.add_child(shape); _visual.add_child(body)
		3:
			if asset: _visual.add_child(asset.instantiate())
			else: build_prop(wood)
	update_gizmos()
func build_prop(wood: Material) -> void:
	var cloth := StandardMaterial3D.new(); cloth.albedo_color=Color(0.31,0.37,0.28); cloth.roughness=0.95
	var linen := StandardMaterial3D.new(); linen.albedo_color=Color(0.67,0.61,0.46); linen.roughness=0.95
	var iron := StandardMaterial3D.new(); iron.albedo_color=Color(0.13,0.12,0.10); iron.metallic=0.55; iron.roughness=0.7
	var w := dimensions.x; var h := dimensions.y; var d := dimensions.z
	match prop_type:
		0,1:
			var top := h*0.5 if prop_type==1 else h
			box(Vector3(0,top-0.06,0),Vector3(w,0.12,d),wood,false)
			for x in [-1,1]:
				for z in [-1,1]: box(Vector3(x*w*0.38,top*0.45,z*d*0.38),Vector3(0.085,top*0.9,0.085),wood,false)
			if prop_type==1:
				for x in [-1,1]: box(Vector3(x*w*0.38,h*0.72,-d*0.38),Vector3(0.085,h*0.56,0.085),wood,false)
				box(Vector3(0,h*0.88,-d*0.38),Vector3(w,0.18,0.08),wood,false)
		2:
			box(Vector3(0,h*0.28,0),Vector3(w,h*0.34,d),wood,false)
			box(Vector3(0,h*0.54,0),Vector3(w*0.92,h*0.2,d*0.95),linen,false)
			box(Vector3(0,h*0.67,d*0.12),Vector3(w*0.94,h*0.1,d*0.67),cloth,false)
			box(Vector3(0,h*0.7,-d*0.33),Vector3(w*0.7,h*0.14,d*0.2),linen,false)
			box(Vector3(0,h*0.5,-d*0.48),Vector3(w,h,0.10),wood,false)
		3:
			box(Vector3(0,h*0.46,0),Vector3(w,h*0.9,d),wood,false)
			box(Vector3(0,h*0.96,0),Vector3(w*1.02,h*0.08,d*1.02),wood,false)
			for x in [-0.32,0.32]: box(Vector3(x*w,h*0.5,d*0.505),Vector3(0.05,h,0.025),iron,false)
			box(Vector3(0,h*0.72,d*0.52),Vector3(0.10,0.13,0.025),iron,false)
		4:
			for x in [-1,1]: box(Vector3(x*(w*0.5-0.045),h*0.5,0),Vector3(0.09,h,d),wood,false)
			for y in [0.05,0.36,0.68,0.97]: box(Vector3(0,h*y,0),Vector3(w,0.07,d),wood,false)
			box(Vector3(0,h*0.5,-d*0.47),Vector3(w,h,0.045),wood,false)
	# One conservative collider matches the footprint used by layout validation.
	var body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var hull := BoxShape3D.new()
	hull.size=dimensions; shape.shape=hull; body.position.y=h*0.5; body.add_child(shape); _visual.add_child(body)
func runtime_view(inside: bool,actor: Vector3,camera: Vector3) -> void:
	if kind!=1 or not is_instance_valid(_visual): return
	var a := to_local(actor); var c := to_local(camera)
	var cut := inside and (a.z*c.z<0 or (absf(a.z)<1.6 and absf(a.x-door_offset*dimensions.x*0.5)<1.5)) and a.y>-0.1 and a.y<dimensions.y+0.1
	if cut==_cut: return
	_cut=cut
	for child in _visual.get_children():
		if child is MeshInstance3D:
			var h: float=child.get_meta("height"); var bottom: float=child.get_meta("bottom")
			var shown := minf(h,maxf(0.8-bottom,0)) if cut else h
			child.visible=shown>0.001; child.scale.y=maxf(0.001,shown/h); child.position.y=bottom+shown*0.5
		elif child is Door: child.set_cutaway(cut)

func _get_configuration_warnings() -> PackedStringArray:
	var p=plan()
	if kind!=2 or p==null or not p.house().has_method("contains_footprint"): return PackedStringArray()
	if roof_exit and get_parent()!=p.levels().back():
		return PackedStringArray(["La scala al tetto deve appartenere all’ultimo piano dell’InteriorPlan."])
	if not roof_exit and not is_equal_approx(dimensions.y,p.floor_height):
		return PackedStringArray(["La scala non raggiunge il piano: imposta Dimensions Y uguale a Floor Height dell’InteriorPlan."])
	for x in [-dimensions.x*0.5-0.2,dimensions.x*0.5+0.2]:
		for z in [-dimensions.z*0.5-0.5,dimensions.z*0.5+0.5]:
			if not p.house().contains_footprint(transform*Vector3(x,0,z),0.25):
				return PackedStringArray(["Scala o spazio di sbarco fuori dalla torre: sposta/riduci la scala oppure allarga la pianta."])
	return PackedStringArray()

func stair_height() -> float:
	var p=plan()
	if roof_exit and p and p.house().has_method("effective_elevation"):
		return p.house().effective_elevation()-get_parent().position.y-0.05
	return dimensions.y

func opening_planes() -> Array:
	var planes: Array=[]
	for pair in [[Vector3.RIGHT,dimensions.x*0.5+0.08],[Vector3.LEFT,dimensions.x*0.5+0.08],[Vector3.BACK,dimensions.z*0.5-0.10],[Vector3.FORWARD,dimensions.z*0.5+0.08]]:
		var n: Vector3=basis*pair[0]; planes.append(Plane(n,float(pair[1])+n.dot(position)))
	return planes

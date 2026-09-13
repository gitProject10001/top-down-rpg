@tool
extends Node3D
## Authored platform and ground access; generated children are disposable.
@export var size := Vector2(24,16):
	set(v): size=Vector2(maxf(2,v.x),maxf(2,v.y)); _pending=true
@export_range(0.2,3,0.1) var elevation := 1.2:
	set(v): elevation=v; _pending=true
@export_range(1,10,0.1) var access_width := 6.0:
	set(v): access_width=v; _pending=true
@export_range(1,12,0.1) var access_run := 4.0:
	set(v): access_run=v; _pending=true
var _pending := true
@export var linked_buildings: Array[NodePath]=[]
var _visual: Node3D
func _process(_delta: float) -> void:
	if _pending: rebuild()
func _get_configuration_warnings() -> PackedStringArray:
	if get_parent()==null or not get_parent().has_method("primary_tower"): return ["La corte deve essere figlia di una fortificazione."]
	for path in linked_buildings:
		if get_node_or_null(path)==null: return ["Edificio collegato mancante: "+str(path)+". Correggi Linked Buildings."]
	if elevation/access_run>0.45: return ["Accesso troppo ripido: aumenta Access Run (massimo 45%)."]
	return []
func rebuild() -> void:
	if not is_inside_tree(): return
	_pending=false; update_configuration_warnings()
	if is_instance_valid(_visual): _visual.free()
	_visual=Node3D.new(); _visual.name="_Generated"; add_child(_visual,false,Node.INTERNAL_MODE_BACK)
	if get_parent()==null or not get_parent().has_method("primary_tower"): return
	var host=get_parent().primary_tower()
	if host==null: return
	var material: Material=host._material(Vector2(0,0.5),Color(0.65,0.63,0.59))
	var mesh := ArrayMesh.new(); var slab := BoxMesh.new(); slab.size=Vector3(size.x,elevation,size.y); slab.material=material
	preload("res://addons/house_builder/mesh_join.gd").append(mesh,slab,Transform3D(Basis.IDENTITY,Vector3(0,elevation*0.5,0)),[])
	var w := minf(access_width,size.x)*0.5; var z := size.y*0.5
	var points := [Vector3(-w,-0.08,z),Vector3(w,-0.08,z),Vector3(w,-0.08,z+access_run),Vector3(-w,-0.08,z+access_run),Vector3(-w,elevation,z),Vector3(w,elevation,z),Vector3(w,0,z+access_run),Vector3(-w,0,z+access_run)]
	var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]:
		for triangle in [[face[0],face[1],face[2]],[face[0],face[2],face[3]]]:
			for index in triangle:
				var point: Vector3=points[index]; tool.set_uv(Vector2(point.x,point.z)); tool.add_vertex(point)
	tool.generate_normals(); tool.generate_tangents(); tool.commit(mesh); mesh.surface_set_material(mesh.get_surface_count()-1,material)
	var visual := MeshInstance3D.new(); visual.mesh=mesh; _visual.add_child(visual)
	var body := StaticBody3D.new(); var shape := CollisionShape3D.new(); shape.shape=mesh.create_trimesh_shape(); body.add_child(shape); _visual.add_child(body)

func courtyard_support_height(point: Vector3) -> float:
	var local := transform.affine_inverse()*point
	if absf(local.x)<=size.x*0.5 and absf(local.z)<=size.y*0.5:
		return (transform*Vector3(local.x,elevation,local.z)).y
	if absf(local.x)<=minf(access_width,size.x)*0.5 and local.z>=size.y*0.5 and local.z<=size.y*0.5+access_run:
		var y := elevation*(1.0-(local.z-size.y*0.5)/access_run)
		return (transform*Vector3(local.x,y,local.z)).y
	return NAN

func height_state(paths: Array) -> Dictionary:
	var positions := {}
	for path in paths:
		var building := get_node_or_null(path)
		if building: positions[path]=building.position
	return {"elevation":elevation,"bindings":linked_buildings.duplicate(),"positions":positions}

func height_proposal(value: float) -> Dictionary:
	if value<0.2 or value>3 or value/access_run>0.45:
		return {"error":"Quota non valida: usa 0.2–3 m e un accesso con pendenza massima 45%. Aumenta Access Run se necessario."}
	var paths: Array=linked_buildings.duplicate()
	if paths.is_empty():
		for building in get_parent().buildings():
			var point: Vector3=transform.affine_inverse()*building.position
			if absf(point.x)<=size.x*0.5 and absf(point.z)<=size.y*0.5: paths.append(get_path_to(building))
	var positions := {}
	for path in paths:
		var building := get_node_or_null(path)
		if building==null or building not in get_parent().buildings(): return {"error":"Collegamento edificio mancante: "+str(path)+". Correggi Linked Buildings."}
		positions[path]=building.position+Vector3.UP*(value-elevation)
	return {"elevation":value,"bindings":paths,"positions":positions}

func apply_height_state(state: Dictionary) -> void:
	elevation=state.elevation
	linked_buildings.assign(state.bindings)
	for path in state.positions:
		var building := get_node_or_null(path)
		if building: building.position=state.positions[path]
	get_parent().rebuild()

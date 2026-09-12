@tool
extends Node3D
const Element=preload("res://addons/house_builder/plan_element.gd")
const Door=preload("res://addons/house_builder/door.gd")
const MeshJoin=preload("res://addons/house_builder/mesh_join.gd")
@export_range(2.4,3.5,0.1) var floor_height := 2.6:
	set(v): floor_height=v; _pending=true
@export var seed_value := 416522
@export_range(2,10) var requested_rooms := 4
@export var preview_inside := true:
	set(v): preview_inside=v; _pending=true
@export_range(0,3) var active_floor := 0:
	set(v): active_floor=v; _pending=true
var _pending := true
var _signature := ""
var _wood: Material
var _wall: Material
var _floors: Node3D
func house() -> Node3D: return get_parent() as Node3D
func wood_material() -> Material:
	if _wood==null: _wood=house()._material(Vector2(0.5,0),Color(0.60,0.53,0.46))
	return _wood
func wall_material() -> Material:
	if _wall==null: _wall=house()._plaster_material()
	return _wall
func levels() -> Array[Node3D]:
	var list: Array[Node3D]=[]
	for child in get_children():
		if child is Node3D: list.append(child)
	return list
func elements() -> Array[Node3D]:
	var result: Array[Node3D]=[]
	for level in levels():
		for child in level.get_children():
			if child is Element: result.append(child)
	return result
func _ready() -> void: _pending=true
func _process(_dt: float) -> void:
	var signature := str(house().dimensions(),house().wing_settings(),floor_height,levels().size())
	for e in elements():
		if e.kind==2: signature+=str(e.transform,e.dimensions)
	if signature!=_signature: _signature=signature; _pending=true
	if _pending: rebuild()
func rebuild() -> void:
	if not is_inside_tree(): return
	_pending=false
	var list := levels()
	if list.is_empty(): return
	var total := list.size()*floor_height
	if not is_equal_approx(house().wall_height,total): house().wall_height=total
	if is_instance_valid(_floors): _floors.free()
	_floors=Node3D.new(); _floors.name="_Floors"; add_child(_floors,false,Node.INTERNAL_MODE_BACK)
	for i in list.size():
		list[i].position.y=i*floor_height
		var mesh := ArrayMesh.new(); var cuts: Array=[]
		if i>0:
			for e in list[i-1].get_children():
				if e is Element and e.kind==2:
					var planes: Array=[]
					for pair in [[Vector3.RIGHT,e.dimensions.x*0.5+0.08],[Vector3.LEFT,e.dimensions.x*0.5+0.08],[Vector3.BACK,e.dimensions.z*0.5-0.10],[Vector3.FORWARD,e.dimensions.z*0.5+0.08]]:
						var n: Vector3=e.basis*pair[0]; planes.append(Plane(n,float(pair[1])+n.dot(e.position)))
					cuts.append(planes)
		var slab := BoxMesh.new(); slab.size=Vector3(house().width-0.4,0.10,house().depth-0.4); slab.material=wood_material()
		MeshJoin.append(mesh,slab,Transform3D.IDENTITY,cuts)
		if house().wing_enabled:
			var wing := BoxMesh.new(); wing.size=Vector3(house().wing_span()-0.4,0.10,house().width*0.5+house().wing_length-0.4); wing.material=wood_material()
			MeshJoin.append(mesh,wing,house().wing_transform(),cuts)
		var floor_node := Node3D.new(); floor_node.position.y=i*floor_height; _floors.add_child(floor_node)
		var visual := MeshInstance3D.new(); visual.mesh=mesh; floor_node.add_child(visual)
		var body := StaticBody3D.new(); var shape := CollisionShape3D.new(); shape.shape=mesh.create_trimesh_shape(); body.add_child(shape); floor_node.add_child(body)
	if Engine.is_editor_hint(): editor_view()
func editor_view() -> void:
	house().set_cutaway(preview_inside,active_floor*floor_height,floor_height)
	for i in levels().size(): levels()[i].visible=not preview_inside or i==active_floor
	if is_instance_valid(_floors):
		for i in _floors.get_child_count(): _floors.get_child(i).visible=not preview_inside or i<=active_floor
func runtime_view(inside: bool,index: int,actor: Vector3,camera: Vector3) -> void:
	for i in levels().size(): levels()[i].visible=inside and i<=index
	if is_instance_valid(_floors):
		for i in _floors.get_child_count(): _floors.get_child(i).visible=inside and i<=index
	for e in elements(): e.runtime_view(inside,actor,camera)
func doors() -> Array[Node3D]:
	var result: Array[Node3D]=[]
	for e in elements():
		if is_instance_valid(e._visual):
			for child in e._visual.get_children():
				if child is Door: result.append(child)
	return result

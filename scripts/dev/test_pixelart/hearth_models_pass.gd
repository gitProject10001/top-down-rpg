extends RefCounted
func apply(world: Node) -> void:
	var camp: Node3D = world.get_node("Camp")
	for n in camp.get_children():
		if n.name in ["HearthHall","ContinuousPaintedHallRoof","WeatheredRoofCloth"] or n.name.begins_with("painted_gatehouse") or n.name.begins_with("painted_cottage"):
			n.hide()
			for shape in n.find_children("*","CollisionShape3D",true,false): shape.disabled = true
	var lodge := add_model(camp,"hearth_lodge_authored",Vector3(0,0,-2.2),0)
	add_model(camp,"hearth_cottage_authored",Vector3(-6.7,0,13),-8)
	add_model(camp,"hearth_cottage_authored",Vector3(9.5,0,14.8),15)
	collider(lodge,Vector3(0,1.5,0),Vector3(8.3,3,4.5))
	collider(lodge,Vector3(1.02,1.5,3.0),Vector3(2.9,3,2.0))
	for old in camp.get_children():
		if old.name=="PaintedWallIvy": old.position.z += .15

func add_model(camp: Node3D,asset: String,pos: Vector3,yaw: float) -> Node3D:
	var model: Node3D = load("res://assets/models/camp/"+asset+".glb").instantiate()
	camp.add_child(model)
	model.position = pos
	model.rotation_degrees.y = yaw
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		for i in mesh.mesh.get_surface_count():
			var src: Material = mesh.mesh.surface_get_material(i)
			var label: String = src.resource_name
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/pixelart/hearth_authored_surface.gdshader")
			m.set_shader_parameter("solid",Color(0,0,0,0))
			m.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/building_brushwork.png"))
			var q := Vector2(.5,0)
			var tint := Color(.78,.74,.67)
			if "Roof" in label:
				q=Vector2(0,0)
			elif "Timber" in label:
				q=Vector2(.5,0)
			elif "Plaster" in label:
				q=Vector2(.5,.5)
				tint=Color(.85,.79,.69)
			elif "Stone" in label:
				q=Vector2(.5,.5)
				m.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/surfaces.png"))
				tint=Color(.68,.67,.60)
				m.set_shader_parameter("detail_lod",1.5)
			elif "Dark" in label: m.set_shader_parameter("solid",Color(.075,.053,.035))
			elif "Iron" in label: m.set_shader_parameter("solid",Color(.21,.22,.21))
			elif "Glass" in label: m.set_shader_parameter("solid",Color(.54,.28,.08))
			m.set_shader_parameter("quadrant",q)
			m.set_shader_parameter("tint",tint)
			mesh.set_surface_override_material(i,m)
	if "cottage" in asset: collider(model,Vector3(0,1.3,0),Vector3(4.2,2.6,4.8))
	return model

func collider(parent: Node3D,pos: Vector3,size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
	parent.add_child(body)

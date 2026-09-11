extends RefCounted
## Painted masses over depth-bearing 3D surfaces; fixed-camera illustration approach.
func apply(world: Node) -> void:
	world.get_parent().stretch_shrink = 2
	var environment: Environment = world.get_node("WorldEnvironment").environment
	environment.ambient_light_energy = .48
	environment.sdfgi_energy = .8
	world.get_node("SoftSkyFill").light_energy = .32
	world.get_node("Sun").rotation_degrees = Vector3(-48,-35,0)
	world.get_node("Sun").shadow_normal_bias = .35
	dress_workshops(world.get_node("Camp"))
	var ground := ShaderMaterial.new()
	ground.shader = load("res://shaders/pixelart/painted_ground_layout.gdshader")
	ground.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/ground_painting.png"))
	world.get_node("Ground").set_surface_override_material(0,ground)
	world.get_node("Camp/BankGrassClusters").hide()
	var forest := world.get_node("Camp/PaintedForest")
	var camera: Camera3D = world.get_node("IsoCam")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixelart/painted_canopy.gdshader")
	mat.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/canopy_painting.png"))
	mat.set_shader_parameter("tint",Color(.73,.75,.74))
	var birch_mat: ShaderMaterial = mat.duplicate()
	birch_mat.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/birch_painting.png"))
	birch_mat.set_shader_parameter("tint",Color(.77,.78,.71))
	var crown_mesh := crown()
	var index := 0
	for tree in forest.get_children():
		for old in tree.find_children("*Crown*","MeshInstance3D",true,false): old.hide()
		var s: float = tree.scale.x
		var bush: bool = tree.scale.y < .5
		var canopy := MeshInstance3D.new()
		canopy.name = "IllustratedCrown"
		canopy.mesh = crown_mesh
		canopy.material_override = birch_mat if index%3==1 else mat
		index += 1
		forest.add_child(canopy)
		canopy.global_transform = Transform3D(camera.global_basis.scaled(Vector3.ONE*s),tree.global_position+Vector3.UP*(1.25 if bush else 4.25*s))
		canopy.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	soften_materials(world.get_node("Camp"))
	rebuild_roofs(world.get_node("Camp"))
	var cloth := ShaderMaterial.new()
	cloth.shader = load("res://shaders/pixelart/painted_cloth_uv.gdshader")
	cloth.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/building_brushwork.png"))
	world.get_node("Camp/WeatheredRoofCloth").material_override = cloth
	world.get_node("Camp/WeatheredRoofCloth").position.y = .3
	add_fire(world)

func add_fire(world: Node) -> void:
	var fire: Node3D = world.get_node("Camp/Campfire")
	fire.position = Vector3(-5.9,0,4.7)
	var flame := MeshInstance3D.new()
	flame.name = "PaintedFlame"
	var quad := QuadMesh.new()
	quad.size = Vector2(.72,1.05)
	flame.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pixelart/hearth_flame.gdshader")
	flame.material_override = m
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.add_child(flame)
	flame.global_transform = Transform3D(world.get_node("IsoCam").global_basis,fire.global_position+Vector3.UP*.55)
	var glow := OmniLight3D.new()
	glow.name = "HearthGlow"
	glow.position.y = .6
	glow.light_color = Color(1,.48,.12)
	glow.light_energy = 1.8
	glow.omni_range = 3.2
	glow.shadow_enabled = true
	fire.add_child(glow)

func dress_workshops(camp: Node3D) -> void:
	var dressing := Node3D.new()
	dressing.name = "WorkshopDressing"
	camp.add_child(dressing)
	var props := [
		["dungeon/barrel",Vector3(-2.8,0,.4),.56,15],
		["dungeon/barrel",Vector3(3.0,0,.15),.60,-12],
		["dungeon/barrel",Vector3(3.7,0,-.1),.49,22],
		["dungeon/crate",Vector3(-6.4,0,1.2),.55,8],
		["dungeon/crate",Vector3(-6.3,.74,1.15),.43,-7],
		["dungeon/table",Vector3(-4.9,0,1.65),.48,0],
		["camp/barrel_open",Vector3(8.8,0,5.5),.75,0],
		["dungeon/barrel",Vector3(10.6,0,5.8),.5,30],
		["camp/bucket",Vector3(7.1,0,6.3),.9,0],
		["camp/log_pile",Vector3(-4.2,0,-.1),.62,0]
	]
	for entry in props:
		var prop: Node3D = load("res://assets/models/"+entry[0]+".glb").instantiate()
		dressing.add_child(prop)
		prop.position = entry[1]
		prop.scale = Vector3.ONE*float(entry[2])
		prop.rotation_degrees.y = float(entry[3])
	var painter = load("res://scripts/dev/test_pixelart/painted_pass.gd").new()
	painter.atlas = load("res://assets/textures/hearth_painted/building_brushwork.png")
	painter.paint_building(dressing)
	painter.static_gi(dressing)

func rebuild_roofs(camp: Node3D) -> void:
	var hall: Node3D = camp.get_node("HearthHall")
	strip_tiles(hall)
	var roof := MeshInstance3D.new()
	roof.name = "ContinuousPaintedHallRoof"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1,1]:
		for row in 12:
			for col in 40:
				if side==1 and col<12: continue
				for c in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
					var uv: Vector2 = (Vector2(col,row)+c)/Vector2(40,12)
					var x := -5.5+uv.x*11.0
					var y := 6.91-uv.y*3.4-.10*sin(uv.x*PI)-.055*sin(uv.y*PI)
					var z: float = -2.2+side*uv.y*(2.75+.025*sin(col*7.3))
					st.set_uv(uv)
					st.add_vertex(Vector3(x,y,z))
	st.generate_normals()
	roof.mesh = st.commit()
	roof.material_override = roof_material(Vector2(3.1,1.5))
	camp.add_child(roof)
	roof.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	for prop in camp.get_children():
		if prop.name.begins_with("painted_gatehouse") or prop.name.begins_with("painted_cottage"):
			strip_tiles(prop)
			var is_gate: bool = prop.name.begins_with("painted_gatehouse")
			gable_roof(prop,1.66 if is_gate else 2.58,1.52 if is_gate else 3.1,2.55 if is_gate else 2.62,1.86 if is_gate else 2.52)

func strip_tiles(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var old: Mesh = node.mesh
		var mesh := ArrayMesh.new()
		var overrides: Array[Material] = []
		var removed := false
		for i in old.get_surface_count():
			var src: Material = old.surface_get_material(i)
			if src and "Tile" in src.resource_name:
				removed = true
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,old.surface_get_arrays(i))
			mesh.surface_set_material(mesh.get_surface_count()-1,src)
			overrides.append(node.get_active_material(i))
		if removed:
			node.mesh = mesh
			for i in overrides.size(): node.set_surface_override_material(i,overrides[i])
	for c in node.get_children(): strip_tiles(c)

func roof_material(repeats: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixelart/painted_roof_uv.gdshader")
	mat.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/building_brushwork.png"))
	mat.set_shader_parameter("repeats",repeats)
	return mat

func gable_roof(parent: Node3D,half_width: float,half_depth: float,eave: float,rise: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1,1]:
		for uv in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
			st.set_uv(uv)
			st.add_vertex(Vector3(side*half_width*uv.y,eave+rise*(1.0-uv.y),-half_depth+uv.x*half_depth*2.0))
	st.generate_normals()
	var roof := MeshInstance3D.new()
	roof.name = "ContinuousPaintedRoof"
	roof.mesh = st.commit()
	roof.material_override = roof_material(Vector2(half_depth*.8,1.0))
	parent.add_child(roof)
	roof.gi_mode = GeometryInstance3D.GI_MODE_STATIC

func soften_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			var m: Material = node.get_active_material(i)
			if m is ShaderMaterial and m.shader.resource_path.ends_with("pixel_char.gdshader"):
				m.shader = load("res://shaders/pixelart/painted_npc.gdshader")
				m.set_shader_parameter("cloth_a",Color(.42,.20,.16))
				m.set_shader_parameter("cloth_b",Color(.29,.31,.35))
				m.set_shader_parameter("helmet",Color(.48,.45,.40))
				m.set_shader_parameter("mail",Color(.26,.27,.27))
				m.set_shader_parameter("shade_saturation",.55)
				m.set_shader_parameter("shade_strength",.4)
			if m is ShaderMaterial and m.shader.resource_path.ends_with("painted_architecture.gdshader"):
				var q: Vector2 = m.get_shader_parameter("quadrant")
				m.set_shader_parameter("detail_lod",2.0)
				if q==Vector2(0,0): m.set_shader_parameter("tint",Color(.77,.74,.70))
				if q==Vector2(.5,0): m.set_shader_parameter("tint",Color(.90,.87,.81))
				if q==Vector2(0,.5):
					m.set_shader_parameter("detail_lod",3.5)
					m.set_shader_parameter("tint",Color(.92,.84,.78))
	for c in node.get_children(): soften_materials(c)

func crown_height(uv: Vector2) -> float:
	# Shape the actual surface to the five painted masses, not one generic dome.
	var lobes := [Vector4(.49,.25,.31,.27),Vector4(.22,.47,.24,.28),Vector4(.78,.49,.24,.26),Vector4(.39,.74,.27,.27),Vector4(.69,.72,.24,.25)]
	var height := 0.0
	for l in lobes:
		var d := (uv-Vector2(l.x,l.y))/Vector2(l.z,l.w)
		var cap := maxf(0.0,1.0-d.length_squared())
		height = maxf(height,sqrt(cap)*1.28)
	return height

func crown() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in 64:
		for x in 64:
			for c in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var uv: Vector2 = (Vector2(x,y)+c)/64.0
				var depth := crown_height(uv)
				st.set_uv(uv)
				var dx := (crown_height(uv+Vector2(.004,0))-crown_height(uv-Vector2(.004,0)))/.0448
				var dy := (crown_height(uv+Vector2(0,.004))-crown_height(uv-Vector2(0,.004)))/.0448
				st.set_normal(Vector3(-dx,dy,1).normalized())
				st.add_vertex(Vector3((uv.x-.5)*5.6,(.5-uv.y)*5.6,depth))
	return st.commit()

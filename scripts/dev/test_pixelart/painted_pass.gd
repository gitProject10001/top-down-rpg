extends RefCounted
const ATLAS = "res://assets/textures/hearth_painted/building_brushwork.png"
const LEAVES = "res://assets/textures/hearth_painted/oak_leaves.png"
var atlas: Texture2D
var foliage: ShaderMaterial
var bark: ShaderMaterial

func apply(world: Node) -> void:
	atlas = load(ATLAS)
	foliage = ShaderMaterial.new()
	foliage.shader = load("res://shaders/pixelart/painted_foliage.gdshader")
	foliage.set_shader_parameter("leaves",load(LEAVES))
	bark = architecture(Vector2(.5,0),Color(.85,.87,.81),2.0)
	var ground := ShaderMaterial.new()
	ground.shader = load("res://shaders/pixelart/painted_terrain.gdshader")
	ground.set_shader_parameter("atlas",load("res://assets/textures/hearth_painted/terrain_brushwork.png"))
	world.get_node("Ground").set_surface_override_material(0,ground)
	world.get_node("Trees").hide()
	world.get_node("Scatter").hide()
	world.get_node("Camp/Foliage").hide()
	var camp: Node3D = world.get_node("Camp")
	add_building(camp,"painted_gatehouse",Vector3(0,0,.35),0,Vector3(2.7,2.5,2.2))
	add_building(camp,"painted_cottage",Vector3(-6.7,0,13.0),-8,Vector3(4.4,3,5.2))
	add_building(camp,"painted_cottage",Vector3(9.5,0,14.8),15,Vector3(4.4,3,5.2))
	camp.get_node("Well").rotation_degrees.y = 80
	camp.get_node("LogPile").position = Vector3(-7.0,0,3.8)
	camp.get_node("PlankStack").position = Vector3(-8.0,0,5.7)
	camp.get_node("Bench").position = Vector3(7.2,0,4.5)
	var spots := [Vector3(-2.1,0,1.8),Vector3(2.1,0,1.8),Vector3(-4.4,0,2.9),Vector3(9.4,0,4.1),Vector3(4.8,0,7.0)]
	var figures := camp.get_node("Figures").get_children()
	for i in mini(figures.size(),spots.size()): figures[i].position = spots[i]
	for child in camp.get_children():
		if "ivy" in child.name.to_lower(): child.hide()
	add_drapery(camp)
	add_wall_ivy(camp)
	var forest := Node3D.new()
	forest.name = "PaintedForest"
	world.get_node("Camp").add_child(forest)
	var tree_scene: PackedScene = load("res://assets/models/camp/painted_oak.glb")
	var places := [Vector3(-12,0,-6),Vector3(-9,0,-9),Vector3(-5,0,-11),Vector3(2,0,-11),Vector3(8,0,-9),Vector3(12,0,-6),Vector3(-13,0,2),Vector3(13,0,2),Vector3(-11,0,10),Vector3(12,0,10)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9321
	for p in places:
		var tree: Node3D = tree_scene.instantiate()
		forest.add_child(tree)
		tree.position = p
		tree.rotation.y = rng.randf()*TAU
		var s := rng.randf_range(.8,1.15)
		tree.scale = Vector3(s,s,s)
		paint_tree(tree)
	# Low leaf clusters join the grass carpet to walls, instead of isolated grass stalks.
	var bush_places := [Vector3(-6,0,-3),Vector3(5.8,0,-2),Vector3(4.8,0,-4),Vector3(-5.7,0,.2),Vector3(-9,0,7),Vector3(10,0,6),Vector3(-11,0,-2),Vector3(8,0,8),Vector3(-7,0,-5)]
	for p in bush_places:
		var bush: Node3D = tree_scene.instantiate()
		forest.add_child(bush)
		bush.position = p-Vector3(0,.6,0)
		bush.scale = Vector3(.36,.27,.36)
		bush.rotation.y = rng.randf()*TAU
		paint_tree(bush)
		var bush_mat: ShaderMaterial = foliage.duplicate()
		bush_mat.set_shader_parameter("tint",Color(.68,.73,.59))
		for leaf in bush.find_children("*Crown*","MeshInstance3D",true,false): leaf.material_override = bush_mat
	paint_building(world.get_node("Camp"))
	var env: Environment = world.get_node("WorldEnvironment").environment
	env.ambient_light_energy = 1.1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = .45
	env.ssao_radius = .7
	env.ssao_intensity = 1.3
	world.get_node("Sun").light_energy = 1.15
	world.get_node("Sun").light_color = Color(1,.94,.84)
	var post: ShaderMaterial = world.get_node("IsoCam/PostPixel").get_surface_override_material(0)
	post.set_shader_parameter("palette_mix",0.0)
	post.set_shader_parameter("exposure",1.2)
	post.set_shader_parameter("saturation",.9)
	post.set_shader_parameter("outline_strength",.10)
	static_gi(world)
	world.get_parent().stretch_shrink = 1
	world.get_node("IsoCam/PostPixel").hide()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ambient_light_color = Color(.65,.72,.80)
	var fill := DirectionalLight3D.new()
	fill.name = "SoftSkyFill"
	fill.rotation_degrees = Vector3(-25,45,0)
	fill.light_color = Color(.72,.81,.90)
	fill.light_energy = .75
	fill.shadow_enabled = false
	world.add_child(fill)
	add_grass(camp,rng)
	var character_style := Node.new()
	character_style.name = "VillageCharacterPalette"
	character_style.set_script(load("res://scripts/dev/test_pixelart/village_character_palette.gd"))
	world.add_child(character_style)
	character_style.call("apply")

func add_building(camp: Node3D, asset: String, pos: Vector3, angle: float, bounds: Vector3) -> void:
	var prop: Node3D = load("res://assets/models/camp/"+asset+".glb").instantiate()
	camp.add_child(prop)
	prop.position = pos
	prop.rotation_degrees.y = angle
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds
	shape.shape = box
	shape.position.y = bounds.y*.5
	body.add_child(shape)
	prop.add_child(body)

func cloth_vertex(u: float,v: float) -> Vector3:
	return Vector3(-5.45+u*3.2,6.94-v*3.30-.25*sin(u*PI)*sin(v*PI)+.065*sin(u*29.0)*v,-2.25+v*2.90)

func add_drapery(camp: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in 20:
		for x in 24:
			var center := Vector2((x+.5)/24.0,(y+.5)/20.0)
			if ((center-Vector2(.29,.65))/Vector2(.09,.06)).length() < 1.0: continue
			if ((center-Vector2(.73,.88))/Vector2(.055,.09)).length() < 1.0: continue
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var uv := Vector2((x+corner.x)/24.0,(y+corner.y)/20.0)
				st.set_uv(uv)
				st.add_vertex(cloth_vertex(uv.x,uv.y))
	st.generate_normals()
	var cloth := MeshInstance3D.new()
	cloth.name = "WeatheredRoofCloth"
	cloth.mesh = st.commit()
	var m := architecture(Vector2(0,.5),Color(1.0,.88,.79),4.2)
	m.resource_name = "Canvas"
	cloth.mesh.surface_set_material(0,m)
	camp.add_child(cloth)

func add_wall_ivy(camp: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3811
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for stem in [-4.9,-2.9,3.15,5.0]:
		for i in 11:
			var y := i*.29+.20
			var x: float = stem+sin(y*1.8+stem)*.22+rng.randf_range(-.10,.10)
			var s := rng.randf_range(.56,.88)
			for uv in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				st.set_uv(uv)
				st.add_vertex(Vector3(x+(uv.x-.5)*s,y+(uv.y-.5)*s,.22+rng.randf_range(.015,.07)))
	st.generate_normals()
	var ivy := MeshInstance3D.new()
	ivy.name = "PaintedWallIvy"
	ivy.mesh = st.commit()
	var mat: ShaderMaterial = foliage.duplicate()
	mat.shader = load("res://shaders/pixelart/painted_ivy.gdshader")
	mat.set_shader_parameter("tint",Color(.64,.68,.47))
	ivy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ivy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ivy.material_override = mat
	camp.add_child(ivy)

func add_grass(camp: Node3D, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 7:
		var x := rng.randf_range(-.13,.13)
		var z := rng.randf_range(-.13,.13)
		var height := rng.randf_range(.11,.23)
		var lean := rng.randf_range(-.10,.10)
		st.set_color(Color(.24,.28,.12))
		st.add_vertex(Vector3(x-.026,0,z))
		st.add_vertex(Vector3(x+.026,0,z))
		st.set_color(Color(.32,.35,.19))
		st.add_vertex(Vector3(x+lean,height,z+.03))
	st.generate_normals()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = st.commit()
	mm.instance_count = 1000
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1
	mm.mesh.surface_set_material(0,mat)
	for i in 1000:
		var p := Vector3(rng.randf_range(-17,17),.015,rng.randf_range(-11,17))
		# Ground-cover islands are sparse in the traveled center and denser on its banks.
		if absf(p.x) < 6.8 and p.z > -6 and p.z < 10: p.x += 7.5 if p.x>0 else -7.5
		var s := rng.randf_range(.65,1.25)
		mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*s),p))
	var grass := MultiMeshInstance3D.new()
	grass.name = "BankGrassClusters"
	grass.multimesh = mm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camp.add_child(grass)

func architecture(quadrant: Vector2, tint: Color, metres: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pixelart/painted_architecture.gdshader")
	m.set_shader_parameter("atlas",atlas)
	m.set_shader_parameter("quadrant",quadrant)
	m.set_shader_parameter("tint",tint)
	m.set_shader_parameter("metres",metres)
	return m

func paint_tree(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = foliage if "Crown" in node.name else bark
	for child in node.get_children(): paint_tree(child)

func paint_building(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var src: Material = node.mesh.surface_get_material(i)
			if not src: continue
			var label := src.resource_name
			if "Tile" in label or "Roof" in label:
				node.set_surface_override_material(i,architecture(Vector2(0,0),Color(.85,.76,.67),2.5))
			elif "Wood" in label:
				node.set_surface_override_material(i,architecture(Vector2(.5,0),Color(.70,.65,.58),1.4))
			elif "Plaster" in label:
				node.set_surface_override_material(i,architecture(Vector2(.5,.5),Color(.77,.70,.60),3.5))
			elif "Canvas" in label:
				node.set_surface_override_material(i,architecture(Vector2(0,.5),Color(.72,.63,.55),3.2))
			elif "Stone" in label:
				var stone := architecture(Vector2(.5,.5),Color(.73,.70,.61),3.2)
				stone.set_shader_parameter("atlas",load("res://assets/textures/hearth_painted/surfaces.png"))
				node.set_surface_override_material(i,stone)
	for child in node.get_children(): paint_building(child)

func static_gi(node: Node) -> void:
	if node.name == "Player": return
	if node is GeometryInstance3D: node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	for child in node.get_children(): static_gi(child)

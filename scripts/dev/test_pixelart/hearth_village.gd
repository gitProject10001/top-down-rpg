extends Node3D
## Independent art direction for Hearth Village. All material copies are scene-local.
var shot := ""
var frames := 0
var taking := false
var bake := false
var mats := {}
var baked_resources := {}
@onready var view: SubViewport = $Pixel/View

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.trim_prefix("--shot=")
		if a == "--bake": bake = true
	$Pixel.stretch_shrink = 2
	var cam: Camera3D = $Pixel/View/IsoCam
	cam.add_to_group("camera_rig")
	cam.ortho_size = 17.5
	cam.pitch_deg = 48.0
	cam.focus_height = 4.0
	view.size_changed.connect(func(): cam.pixel_rows = view.size.y)
	var env: Environment = $Pixel/View/WorldEnvironment.environment.duplicate()
	$Pixel/View/WorldEnvironment.environment = env
	env.ambient_light_energy = 0.75
	env.ssao_intensity = 1.8
	$Pixel/View/Sun.light_energy = 2.8
	$Pixel/View/Fire.light_energy = 2.0
	var ground := ShaderMaterial.new()
	ground.shader = load("res://shaders/pixelart/hearth_ground.gdshader")
	$Pixel/View/Ground.set_surface_override_material(0, ground)
	_skin($Pixel/View/Camp)
	_skin($Pixel/View/Trees)
	var hall: Node3D = load("res://assets/models/camp/hearth_hall.glb").instantiate()
	hall.name = "HearthHall"
	hall.position = Vector3(0,0,-2.2)
	hall.rotation_degrees.y = 0
	hall.scale = Vector3(1.35,1.1,1.0)
	$Pixel/View/Camp.add_child(hall)
	_skin(hall)
	var ivy: Node3D = load("res://assets/models/camp/hearth_ivy.glb").instantiate()
	ivy.position = hall.position
	ivy.scale = hall.scale
	$Pixel/View/Camp.add_child(ivy)
	_skin(ivy)
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.3,4.0,4.3)
	collision.shape = box
	collision.position.y = 2.0
	obstacle.position = hall.position
	obstacle.add_child(collision)
	$Pixel/View/Camp.add_child(obstacle)
	$Pixel/View/Camp/Ruin.hide()
	$Pixel/View/Camp/Chapel.hide()
	$Pixel/View/Camp/Mantle.hide()
	var post: ShaderMaterial = $Pixel/View/IsoCam/PostPixel.get_surface_override_material(0).duplicate()
	$Pixel/View/IsoCam/PostPixel.set_surface_override_material(0,post)
	post.set_shader_parameter("exposure",1.4)
	post.set_shader_parameter("contrast",1.02)
	post.set_shader_parameter("palette_mix",0.18)
	post.set_shader_parameter("dither",0.006)
	post.set_shader_parameter("outline_strength",0.08)
	post.set_shader_parameter("vignette",0.1)
	# Small, grouped grass replaces isolated glowing stalks.
	for n in $Pixel/View/Scatter.get_children():
		if n is MultiMeshInstance3D:
			var m: StandardMaterial3D = StandardMaterial3D.new()
			m.albedo_color = Color(0.35,0.30,0.14) if n.name == "Grass" else Color(0.30,0.23,0.16)
			m.roughness = 1.0
			n.material_override = m
			if n.name == "Grass":
				for i in n.multimesh.instance_count:
					var t: Transform3D = n.multimesh.get_instance_transform(i)
					t.basis = t.basis.scaled(Vector3(1.5,0.5,1.5))
					n.multimesh.set_instance_transform(i,t)
	# Decorative figures sit on the same ground as the player.
	for fig in $Pixel/View/Camp/Figures.get_children(): fig.position.y = 0.0
	load("res://scripts/dev/test_pixelart/painted_pass.gd").new().apply($Pixel/View)
	load("res://scripts/dev/test_pixelart/painted_stage_two.gd").new().apply($Pixel/View)
	load("res://scripts/dev/test_pixelart/hearth_models_pass.gd").new().apply($Pixel/View)
	load("res://scripts/dev/test_pixelart/hearth_clarity_pass.gd").new().apply($Pixel/View)
	$Pixel.stretch_shrink = 1
	$Pixel/View/IsoCam/PostPixel.hide()
	if shot != "":
		for n in get_tree().root.get_children():
			if n is CanvasLayer: n.visible = false

func _skin(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			var original: Material = node.get_active_material(i)
			if original is StandardMaterial3D and original.resource_name.begins_with("Hearth"):
				var hand := ShaderMaterial.new()
				hand.shader = load("res://shaders/pixelart/hearth_surface.gdshader")
				var c: Color = original.albedo_color
				if "Stone" in original.resource_name: c = Color(0.46,0.34,0.25)
				elif "Plaster" in original.resource_name: c = Color(0.49,0.35,0.25)
				elif "Wood" in original.resource_name: c = Color(0.24,0.12,0.07)
				elif "Canvas" in original.resource_name: c = Color(0.50,0.33,0.25)
				elif "Dark" in original.resource_name: c = Color(0.09,0.045,0.03)
				elif "Ivy" in original.resource_name:
					var v := float(original.resource_name.right(1).to_int()) * 0.018
					c = Color(0.28+v,0.27+v,0.12+v*0.5)
				else:
					var v := float(original.resource_name.right(1).to_int()) * 0.009
					c = Color(0.25+v,0.125+v,0.08+v)
				hand.set_shader_parameter("paint", c)
				node.set_surface_override_material(i,hand)
			if original is ShaderMaterial:
				var key: String = original.resource_path
				if not mats.has(key):
					var m: ShaderMaterial = original.duplicate()
					m.next_pass = null
					m.set_shader_parameter("use_normal_map",false)
					m.set_shader_parameter("use_ao_map",false)
					m.set_shader_parameter("grain",0.08)
					m.set_shader_parameter("mortar",0.012)
					m.set_shader_parameter("mortar_strength",0.48)
					m.set_shader_parameter("bevel_light",0.10)
					m.set_shader_parameter("bevel_dark",0.12)
					m.set_shader_parameter("tone_jitter",0.12)
					if "stone" in key: m.set_shader_parameter("albedo_color",Color(0.64,0.49,0.35))
					if "roof" in key:
						m.set_shader_parameter("albedo_color",Color(0.30,0.16,0.10))
						m.set_shader_parameter("block_size",Vector2(0.65,0.65))
					if "canvas" in key:
						m.shader = load("res://shaders/pixelart/hearth_surface.gdshader")
						m.set_shader_parameter("paint",Color(0.57,0.39,0.30))
					mats[key]=m
				node.set_surface_override_material(i,mats[key])
	for child in node.get_children(): _skin(child)

func _process(_delta: float) -> void:
	frames += 1
	if shot != "" and frames > 100 and not taking:
		taking = true
		for layer in get_tree().root.find_children("*","CanvasLayer",true,false): layer.hide()
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(shot))
		print("HEARTH_RENDER ",err," ",shot)
		if bake:
			_bake_scene()
		get_tree().quit()

func _bake_scene() -> void:
	# Save the actual art and scene-local materials for editing directly in Godot.
	# Do not duplicate through PackedScene instantiation: that retains imported child state
	# alongside our explicitly owned material overrides, producing editor name collisions.
	# Let the duplicate copy viewport dimensions before restoring container-driven sizing.
	var stretched: bool = $Pixel.stretch
	$Pixel.stretch = false
	var copy := duplicate(DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS)
	$Pixel.stretch = stretched
	copy.get_node("Pixel").stretch = stretched
	copy.set_script(null)
	var old_player: Node3D = copy.get_node("Pixel/View/Player")
	var player_transform := old_player.transform
	var player_parent := old_player.get_parent()
	player_parent.remove_child(old_player)
	old_player.free()
	var fresh_player: Node3D = load("res://scenes/player/player3.tscn").instantiate()
	fresh_player.name = "Player"
	fresh_player.transform = player_transform
	player_parent.add_child(fresh_player)
	copy.get_node("Pixel/View/Camp").scene_file_path = ""
	for path in ["Pixel/View/Camp","Pixel/View/Camp/Foliage","Pixel/View/Trees","Pixel/View/Scatter"]:
		copy.get_node(path).set_script(null)
	for path in ["Pixel/View/Camp/Ruin","Pixel/View/Camp/Chapel","Pixel/View/Camp/Mantle","Pixel/View/Camp/Foliage","Pixel/View/Trees","Pixel/View/Scatter"]:
		var old: Node = copy.get_node(path)
		old.get_parent().remove_child(old)
		old.free()
	for prop in copy.get_node("Pixel/View/Camp").get_children():
		if prop is Node3D and not prop.visible:
			prop.get_parent().remove_child(prop)
			prop.free()
	_own(copy,copy)
	DirAccess.make_dir_recursive_absolute("res://assets/models/camp/hearth_baked")
	_externalize(copy)
	var packed := PackedScene.new()
	var err := packed.pack(copy)
	if err == OK: err = ResourceSaver.save(packed,"res://scenes/dev/hearth_village_playable.tscn")
	print("HEARTH_BAKE ",err)
	copy.free()

func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.name != "Player":
			# The art is stored as ordinary editable nodes, with meshes still referencing
			# the imported resources. Only player3 remains a PackedScene instance.
			child.scene_file_path = ""
			_own(child,root)

func _externalize(node: Node) -> void:
	# Keep large geometry in binary resources rather than embedding tens of MB of
	# vertex arrays in the scene text. Shared meshes are saved once.
	if node.name == "Player": return
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		node.mesh = _binary_resource(node.mesh)
	elif node is MultiMeshInstance3D and node.multimesh:
		node.multimesh = _binary_resource(node.multimesh)
	for child in node.get_children(): _externalize(child)

func _binary_resource(resource: Resource) -> Resource:
	var id := resource.get_instance_id()
	if baked_resources.has(id): return baked_resources[id]
	var path := "res://assets/models/camp/hearth_baked/geometry_%03d.res" % baked_resources.size()
	var err := ResourceSaver.save(resource,path,ResourceSaver.FLAG_COMPRESS)
	assert(err == OK,"Could not save village geometry")
	var saved := load(path)
	baked_resources[id] = saved
	return saved

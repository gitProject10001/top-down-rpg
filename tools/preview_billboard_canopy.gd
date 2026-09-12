extends "res://tools/preview_tuft_flow.gd"
## Standalone study. Orbit with left/right; Esc closes. --capture saves 8 views.
var camera: Camera3D
var crown: MeshInstance3D
var angle := 0.0
var capturing := false
var inclined := Basis(Vector3(1.0042056,0,0),Vector3(0,0.67194456,0.7462701),Vector3(0,-0.7462702,0.6719446))

func update_view() -> void:
	camera.position = Vector3(sin(angle)*9,12.85,cos(angle)*9)
	camera.look_at(Vector3(0,2.7,0))
	# Orthographic billboarding uses camera orientation, not tree-to-camera position.
	var back := camera.global_basis.z
	var yaw := atan2(back.x,back.z)
	# The authored front points toward -Z, not +Z.
	crown.basis = Basis(Vector3.UP,yaw+PI)*inclined

func _process(delta: float) -> bool:
	if camera == null or capturing: return false
	if Input.is_key_pressed(KEY_ESCAPE): quit()
	var direction := float(Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_LEFT))
	angle += direction*delta
	update_view()
	return false

func run() -> void:
	capturing = "--capture" in OS.get_cmdline_user_args()
	world = Node3D.new()
	root.add_child(world)
	branch(Vector3.ZERO,Vector3(-0.15,2.4,0),0.28)
	branch(Vector3(-0.15,2.4,0),Vector3(0.15,4.0,0),0.16)
	crown = MeshInstance3D.new()
	crown.mesh = load("res://assets/models/camp/hearth_baked/geometry_026.res")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixelart/painted_canopy.gdshader")
	mat.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/canopy_painting.png"))
	mat.set_shader_parameter("tint",Color(0.73,0.75,0.74))
	crown.material_override = mat
	world.add_child(crown)
	crown.position = Vector3(0,4.2678733,0)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-45,-30,0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.20,0.23,0.20)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.5
	update_view()
	if not capturing: return
	for i in range(8):
		angle = i*TAU/8
		update_view()
		assert(crown.basis.determinant()>0.0)
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/tuft_flow/billboard_view_%d.png"%i)
	print("BILLBOARD_PASS: eight camera angles, single original crown, fixed trunk")
	quit()

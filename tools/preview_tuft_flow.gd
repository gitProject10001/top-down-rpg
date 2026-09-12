extends SceneTree
## Isolated art study. Never added to the playable scene.
var world: Node3D
var materials: Array[ShaderMaterial] = []

func _initialize() -> void:
	call_deferred("run")

func branch(a: Vector3, b: Vector3, radius: float) -> void:
	var n := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.55
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 7
	n.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.15, 0.085)
	mat.roughness = 1.0
	n.material_override = mat
	world.add_child(n)
	n.position = (a+b)*0.5
	var up := (b-a).normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	n.basis = Basis(side, up, side.cross(up))

func tuft(origin: Vector3, direction: Vector3, width: float, variant: int) -> void:
	# One gently bent support carries a whole painted spray, never individual leaves.
	var along := direction.normalized()
	var across := along.cross(Vector3.UP).normalized()
	var normal := across.cross(along).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(4):
		for x in range(4):
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var uv: Vector2 = (Vector2(x,y)+corner)/4.0
				# Image attachment is upper right; leaf flow runs down-left.
				var axial := ((1.0-uv.x)+uv.y)*0.5
				var lateral := (uv.x+uv.y-1.0)*0.72
				st.set_uv(uv)
				st.add_vertex(origin+along*axial*width+across*lateral*width+normal*sin(axial*PI)*width*0.10)
	st.generate_normals()
	var n := MeshInstance3D.new()
	n.mesh = st.commit()
	n.material_override = materials[variant%4]
	world.add_child(n)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var shader := Shader.new()
	# Temporary preview-only chroma rejection of baked grey checkerboard.
	# Originals remain untouched; this is NOT a production alpha mask.
	shader.code = "shader_type spatial; render_mode cull_disabled; uniform sampler2D ink: source_color, filter_linear_mipmap; void fragment(){vec3 c=texture(ink,UV).rgb; float sat=max(c.r,max(c.g,c.b))-min(c.r,min(c.g,c.b)); if(sat<0.075) discard; ALBEDO=c; ROUGHNESS=1.0; SPECULAR=0.0;}"
	for i in range(4):
		var img := Image.load_from_file("res://art_source/tuft_flow/tuft_%d.png"%(i+1))
		assert(img != null)
		img.generate_mipmaps()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("ink", ImageTexture.create_from_image(img))
		materials.append(mat)
	branch(Vector3.ZERO,Vector3(-0.15,2.3,0),0.28)
	branch(Vector3(-0.15,2.3,0),Vector3(0.12,4.5,0.1),0.17)
	# Authored branch lines with asymmetrical tiers and intentional openings.
	for i in range(7):
		var angle := i*2.39996
		var axis := Vector3(cos(angle),0,sin(angle))
		var start := Vector3(0,2.1+i*0.29,0)
		var elbow := start+axis*(0.7+0.12*(i%3))+Vector3.UP*0.8
		var tip := elbow+axis*0.6+Vector3.UP*0.15
		branch(start,elbow,0.10)
		branch(elbow,tip,0.065)
		for j in range(3):
			var flow := axis.rotated(Vector3.UP,(j-1)*0.43)+Vector3.DOWN*(0.25+j*0.12)
			tuft(tip-axis*0.3*j,flow,1.6+0.4*((i+j)%3),i+j)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-45,-30,0)
	light.light_energy = 1.0
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.20,0.23,0.20)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 8.5
	for i in range(4):
		var angle := i*PI/2+0.4
		cam.position = Vector3(cos(angle)*9,10,sin(angle)*9)
		cam.look_at(Vector3(0,2.7,0))
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/tuft_flow/tree_view_%d.png"%i)
	print("TUFT_FLOW_PASS: four views, 21 painted supports, no game scene changes")
	quit()

extends "res://tools/preview_tuft_flow.gd"
## Three static crowns, with the source surface turned to hang downward.

func panel(center: Vector3, yaw: float, width: float, mat: ShaderMaterial, tilt: float) -> void:
	var right := Vector3(cos(yaw),0,sin(yaw))
	var up := Vector3.UP*cos(tilt)+Vector3(-sin(yaw),0,cos(yaw))*sin(tilt)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(8):
		for x in range(8):
			for c in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var uv: Vector2 = (Vector2(x,y)+c)/8.0
				var p := center+right*(uv.x-0.5)*width+up*(0.5-uv.y)*width*0.85
				st.set_uv(uv)
				st.add_vertex(p)
	st.generate_normals()
	var n := MeshInstance3D.new()
	n.mesh = st.commit()
	n.material_override = mat
	world.add_child(n)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D ink: source_color, filter_nearest;
varying vec3 shared_normal;
void vertex(){
 vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 // Separate, equally curved height layers: no intersecting rotated bowls.
 p.y=MODEL_MATRIX[3].y+0.8-0.24*dot(p.xz,p.xz);
 VERTEX=(inverse(MODEL_MATRIX)*vec4(p,1.0)).xyz;
 shared_normal=normalize((p-vec3(0.0,3.8,0.0))*vec3(0.5,0.8,0.5)+vec3(0.0,1.6,0.0));
}
void fragment(){
 vec4 c=texture(ink,(floor(UV*256.0)+0.5)/256.0);
 if(c.a<0.5)discard;
 float value=dot(c.rgb,vec3(0.299,0.587,0.114));
 ALBEDO=mix(vec3(value),c.rgb,0.72);
 NORMAL=normalize((VIEW_MATRIX*vec4(shared_normal,0.0)).xyz);
 ROUGHNESS=1.0;SPECULAR=0.0;
}
void light(){float d=clamp(dot(NORMAL,LIGHT)*0.55+0.45,0.0,1.0);DIFFUSE_LIGHT+=LIGHT_COLOR*mix(d,floor(d*5.0)/5.0,0.3)*ATTENUATION/3.14159;}
"""
	var base := ShaderMaterial.new()
	base.shader = shader
	base.set_shader_parameter("ink",load("res://assets/textures/hearth_painted/canopy_painting.png"))
	branch(Vector3.ZERO,Vector3(-0.15,2.4,0),0.28)
	branch(Vector3(-0.15,2.4,0),Vector3(0.15,4.4,0),0.16)
	# Taken from IllustratedCrown in the playable scene, not a reconstructed card.
	var camp_basis := Basis(Vector3(0.70710677,0,0.70710677),Vector3.UP,Vector3(-0.70710677,0,0.70710677))
	var original_basis := camp_basis * Basis(Vector3(1.0042056,0,0),Vector3(0,0.67194456,0.7462701),Vector3(0,-0.7462702,0.6719446))
	var crown_mesh: Mesh = load("res://assets/models/camp/hearth_baked/geometry_026.res")
	assert(crown_mesh != null)
	var tier := 0
	for degrees in [0.0,120.0,240.0]:
		var crown := MeshInstance3D.new()
		crown.name = "StaticCrown%d"%int(degrees)
		crown.mesh = crown_mesh
		crown.material_override = base
		# Turn the bowl over at its center BEFORE distributing copies around Y.
		var downward_basis := Basis(Vector3.RIGHT,PI)*original_basis
		var tier_scale := 1.0-0.19*tier
		crown.transform = Transform3D((Basis(Vector3.UP,deg_to_rad(degrees))*downward_basis).scaled(Vector3.ONE*tier_scale),Vector3(0,3.65+0.62*tier,0))
		world.add_child(crown)
		tier += 1
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
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 8.5
	for i in range(8):
		var angle := i*TAU/8+0.4
		cam.position = Vector3(cos(angle)*9,10,sin(angle)*9)
		cam.look_at(Vector3(0,2.7,0))
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/tuft_flow/refined_view_%d.png"%i)
	print("CORRECTED_CANOPY_PASS: eight views; downward-facing source mesh, static yaw 0/120/240")
	quit()

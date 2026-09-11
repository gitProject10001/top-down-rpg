extends RefCounted
const ATLAS = "res://assets/textures/hearth_painted/architecture_clear_v2.png"
func apply(world: Node) -> void:
	var camp := world.get_node("Camp")
	for mesh in camp.find_children("*","MeshInstance3D",true,false):
		var cursor: Node=mesh
		var hidden:=false
		while cursor!=camp:
			if cursor is Node3D and not cursor.visible: hidden=true
			cursor=cursor.get_parent()
		if hidden: continue
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.get_active_material(i)
			if not mat is ShaderMaterial: continue
			if mat.shader.resource_path == "res://shaders/pixelart/painted_architecture.gdshader":
				var current_atlas: Texture2D=mat.get_shader_parameter("atlas")
				if current_atlas and current_atlas.resource_path==ATLAS: continue
				var old_q: Vector2=mat.get_shader_parameter("quadrant")
				if old_q==Vector2(0,.5): continue
				var prop_mat:=ShaderMaterial.new()
				prop_mat.shader=mat.shader
				prop_mat.set_shader_parameter("detail_lod",2.0)
				prop_mat.set_shader_parameter("quadrant",old_q)
				prop_mat.set_shader_parameter("tint",mat.get_shader_parameter("tint"))
				prop_mat.set_shader_parameter("metres",mat.get_shader_parameter("metres"))
				prop_mat.set_shader_parameter("atlas",load(ATLAS))
				if old_q==Vector2(.5,.5):
					prop_mat.set_shader_parameter("quadrant",Vector2(0,.5))
					prop_mat.set_shader_parameter("metres",1.6)
				if not mesh.has_meta("clarity_mesh"):
					var copy:=ArrayMesh.new()
					for surface in mesh.mesh.get_surface_count():
						copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.mesh.surface_get_arrays(surface))
						copy.surface_set_material(surface,mesh.get_active_material(surface))
					mesh.mesh=copy
					mesh.set_meta("clarity_mesh",true)
				mesh.mesh.surface_set_material(i,prop_mat)
				mesh.set_surface_override_material(i,prop_mat)
				continue
			if mat.shader.resource_path != "res://shaders/pixelart/hearth_authored_surface.gdshader": continue
			var m: ShaderMaterial = mat.duplicate()
			var old: Texture2D = m.get_shader_parameter("painting")
			var q: Vector2 = m.get_shader_parameter("quadrant")
			m.shader = load("res://shaders/pixelart/architecture_clear.gdshader")
			m.set_shader_parameter("painting",load(ATLAS))
			if old and old.resource_path.ends_with("surfaces.png"):
				q=Vector2(0,.5)
				m.set_shader_parameter("tint",Color(.83,.79,.73))
				m.set_shader_parameter("uv_scale",Vector2(.62,.62))
			elif q==Vector2(0,0):
				m.set_shader_parameter("tint",Color(.70,.77,.85))
				m.set_shader_parameter("uv_scale",Vector2(.83,1.2))
			elif q==Vector2(.5,.5):
				m.set_shader_parameter("tint",Color(.90,.87,.83))
			else: m.set_shader_parameter("tint",Color(.82,.78,.73))
			m.set_shader_parameter("quadrant",q)
			mesh.set_surface_override_material(i,m)
	var ivy: MeshInstance3D = camp.get_node("PaintedWallIvy")
	ivy.mesh=ivy_mesh()
	ivy.position=Vector3.ZERO
	ivy.material_override=ShaderMaterial.new()
	ivy.material_override.shader=load("res://shaders/pixelart/ivy_leaf_geometry.gdshader")
	ivy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ivy.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	var ground_mat: ShaderMaterial=world.get_node("Ground").get_active_material(0).duplicate()
	ground_mat.shader=load("res://shaders/pixelart/ground_clear.gdshader")
	world.get_node("Ground").set_surface_override_material(0,ground_mat)
	# Sky fill keeps painted midtones readable on the facade under the eave.
	world.get_node("SoftSkyFill").light_energy=.48

func ivy_mesh() -> ArrayMesh:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng:=RandomNumberGenerator.new()
	rng.seed=39276
	var palette=[Color("707044"),Color("85804a"),Color("60643c"),Color("979057"),Color("777b49")]
	for stem in [-3.85,-2.95,3.42,4.05]:
		for j in 10:
			var y:=.42+j*.29
			var x: float=stem+sin(y*2.1+stem)*.22
			for side in [-1,1]:
				var end:=Vector3(x+side*rng.randf_range(.25,.50),y+rng.randf_range(.03,.22),.17+j*.001)
				var start:=Vector3(x,y-.10,.17+j*.001)
				var offset:=Vector3(.013,.008,0)
				tri(st,start-offset,start+offset,end,Color("4c4930"))
				for k in 2:
					var p:=start.lerp(end,.45+k*.50)
					p.y+=(.09 if k%2==0 else -.08)
					leaf(st,p,rng.randf_range(.12,.18),rng.randf_range(-1.1,1.1),palette[rng.randi_range(0,4)])
	return st.commit()

func leaf(st: SurfaceTool,p: Vector3,s: float,a: float,c: Color) -> void:
	var outline=[Vector2(0,-.68),Vector2(-.55,-.20),Vector2(-.80,.18),Vector2(-.28,.32),Vector2(0,1),Vector2(.29,.32),Vector2(.79,.17),Vector2(.55,-.20)]
	for i in outline.size():
		var u: Vector2=outline[i].rotated(a)*s
		var v: Vector2=outline[(i+1)%outline.size()].rotated(a)*s
		tri(st,p+Vector3(0,0,.018),p+Vector3(u.x,u.y,0),p+Vector3(v.x,v.y,0),c.lightened(.10) if i<4 else c.darkened(.08))

func tri(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	st.set_color(color)
	st.set_normal(Vector3(0,.18,1).normalized())
	for p in [a,b,c]: st.add_vertex(p)

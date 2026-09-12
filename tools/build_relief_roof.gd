extends SceneTree
## Deterministic offline mesh build. Run with Godot --headless --script this file.
## Replaces only surface 3 of the authored cottage; walls/collision stay authored.
var st: SurfaceTool
var rng := RandomNumberGenerator.new()
var tile_count := 0
var tile_uv_origin := Vector2.ZERO
var tile_uv_size := Vector2.ONE
var tile_side := 1.0
var tile_transform := Transform3D.IDENTITY
var broken_count := 0
var shifted_count := 0

func _initialize() -> void:
	call_deferred("build")

func face(a: Vector3,b: Vector3,c: Vector3,color: Color, cavity: float=1.0) -> void:
	var normal := (b-a).cross(c-a).normalized()
	color.a=cavity
	for p in [a,c,b]:
		st.set_normal(tile_transform.basis*normal)
		st.set_color(color)
		st.set_uv(Vector2(p.z,p.x))
		st.set_uv2(Vector2((p.z-tile_uv_origin.x)/tile_uv_size.x+0.5,(tile_uv_origin.y-p.x*tile_side)/tile_uv_size.y))
		st.add_vertex(tile_transform*p)

func point(uv: Vector2, side: float, distance: float, z: float, lift: float) -> Vector3:
	var x := side*(2.50-distance-uv.y)
	return Vector3(x,4.72-absf(x)*0.96+lift,z+uv.x)

func tile(side: float, distance: float, z: float, width: float, length: float, damage: int=0, shifted: bool=false, front_edge: bool=false) -> void:
	tile_count+=1
	tile_uv_origin=Vector2(z,2.50-distance)
	tile_uv_size=Vector2(width,length)
	tile_side=side
	var w := width*0.5
	var chip := rng.randf_range(0.025,0.075)
	var edge := PackedVector2Array([Vector2(-w+chip,rng.randf_range(-0.025,0.015)),Vector2(w-0.018,rng.randf_range(-0.03,0.03)),Vector2(w,0.045),Vector2(w-0.008,length-0.025),Vector2(w-0.028,length),Vector2(-w+0.016,length),Vector2(-w,length-0.035),Vector2(-w,chip)])
	# Large fractures in the exposed lower end; the upper overlap stays supported.
	# Convex cuts keep the closed fan triangulation valid, including the underside.
	if damage>0 and width>0.20:
		broken_count+=1
		edge[0]=Vector2(w*0.35,0.045)
		edge[7]=Vector2(-w,length*0.48)
		if damage==2:
			edge[0]=Vector2(-w+0.055,length*0.40)
			edge[1]=Vector2(w-0.025,length*0.27)
			edge[2]=Vector2(w,length*0.34)
	tile_transform=Transform3D.IDENTITY
	if shifted and width>0.20:
		shifted_count+=1
		var pivot := point(Vector2(0,length*0.5),side,distance,z,0.10)
		var roof_normal := Vector3(side*0.96,1,0).normalized()
		var rotation := Basis(roof_normal,deg_to_rad(11.0 if z>0 else -9.0))
		var slide := Vector3(side*0.065,-0.062,0.16 if front_edge else -0.035)+roof_normal*0.055
		tile_transform=Transform3D(rotation,pivot+slide-rotation*pivot)
	var shades := [Color("77665a"),Color("827165"),Color("72665f"),Color("8b7867"),Color("806758"),Color("74706a"),Color("877365")]
	var pigment: Color = shades[rng.randi_range(0,shades.size()-1)].srgb_to_linear()
	pigment *= rng.randf_range(0.91,1.06)
	pigment.a=1.0
	var lift := rng.randf_range(0.0,0.016)
	var tilt := rng.randf_range(-0.065,0.065)
	if damage>0 and width>0.20:
		# Black recessed backing covers the exposed fracture, above the lower course.
		# Same surface/material: zero pigment and zero specular remain black at every hour.
		var p0 := point(Vector2(-w,-0.025),side,distance,z,0.105)
		var p1 := point(Vector2(w,-0.025),side,distance,z,0.105)
		var p2 := point(Vector2(w,length*0.58),side,distance,z,0.067)
		var p3 := point(Vector2(-w,length*0.58),side,distance,z,0.067)
		if side>0:
			face(p0,p2,p1,Color.BLACK,0.0)
			face(p0,p3,p2,Color.BLACK,0.0)
		else:
			face(p0,p1,p2,Color.BLACK,0.0)
			face(p0,p2,p3,Color.BLACK,0.0)
	var bottom: Array[Vector3]=[]
	var rim: Array[Vector3]=[]
	var top: Array[Vector3]=[]
	for uv in edge:
		var h := 0.17-0.13*uv.y/length+lift+uv.x*tilt
		bottom.append(point(uv,side,distance,z,h-0.065))
		rim.append(point(uv,side,distance,z,h-0.014))
		var inset := uv.lerp(Vector2(0,length*0.5),0.065)
		top.append(point(inset,side,distance,z,h))
	var center := point(Vector2(0,length*0.52),side,distance,z,0.105+lift)
	var underside := center-Vector3(0,0.065,0)
	for i in edge.size():
		var j := (i+1)%edge.size()
		# Ring is counterclockwise on positive slope; swap for the other slope.
		if side>0:
			face(underside,bottom[i],bottom[j],pigment,0.35)
			face(center,top[j],top[i],pigment)
			face(top[i],top[j],rim[j],pigment)
			face(top[i],rim[j],rim[i],pigment)
			face(rim[i],rim[j],bottom[j],pigment,0.45)
			face(rim[i],bottom[j],bottom[i],pigment,0.45)
		else:
			face(underside,bottom[j],bottom[i],pigment,0.35)
			face(center,top[i],top[j],pigment)
			face(top[i],rim[j],top[j],pigment)
			face(top[i],rim[i],rim[j],pigment)
			face(rim[i],bottom[j],rim[j],pigment,0.45)
			face(rim[i],bottom[i],bottom[j],pigment,0.45)

func build() -> void:
	rng.seed=416522
	var scene = load("res://scenes/dev/hearth_village_playable.tscn").instantiate()
	var original: Mesh = scene.get_node("Pixel/View/Camp/hearth_cottage_authored2/hearth_cottage_authored").mesh
	# Keep an immutable first-run source for reproducible rebuilds after scene integration.
	var source_path := "res://assets/models/roof_relief/cottage_source.res"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/roof_relief"))
	if ResourceLoader.exists(source_path): original=load(source_path)
	else: ResourceSaver.save(original,source_path)
	st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		for row in range(10):
			var distance := row*0.25
			var length := minf(0.40,2.50-distance)
			var z := -2.70
			var column := 0
			while z<2.69:
				var width := minf(0.35+rng.randf_range(-0.04,0.04),2.70-z)
				if column==0 and row%2==1: width*=0.5
				var address := Vector2i(row,column)
				var breaks := [Vector2i(1,5),Vector2i(3,12),Vector2i(6,8),Vector2i(8,13)] if side<0 else [Vector2i(2,11),Vector2i(4,5),Vector2i(7,12)]
				var shifts := [Vector2i(0,10),Vector2i(4,14),Vector2i(7,5)] if side<0 else [Vector2i(1,8),Vector2i(5,13),Vector2i(8,4)]
				var front_edge := z+width>2.69 and row in [2,6]
				var damage := (2 if row%2==0 else 1) if address in breaks else 0
				tile(side,distance,z+width*0.5,maxf(width-0.024,0.006),length,damage,address in shifts or front_edge,front_edge)
				z+=width
				column+=1
	st.generate_tangents()
	st.index()
	var relief := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader=load("res://shaders/pixelart/roof_clay.gdshader")
	mat.set_shader_parameter("cavity_strength",0.78)
	ResourceSaver.save(mat,"res://assets/models/roof_relief/clay.tres")
	var result := ArrayMesh.new()
	for s in original.get_surface_count():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,relief.surface_get_arrays(0) if s==3 else original.surface_get_arrays(s))
		result.surface_set_material(s,mat if s==3 else original.surface_get_material(s))
	ResourceSaver.save(result,"res://assets/models/roof_relief/cottage_relief.res")
	print("ROOF_BUILD_OK tiles=",tile_count," broken=",broken_count," shifted=",shifted_count," roof_triangles=",relief.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3)
	scene.free()
	quit()

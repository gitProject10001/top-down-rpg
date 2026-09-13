@tool
extends RefCounted
## Parameterized version of the authored relief tiles, used by the house editor.
## Returns one mesh surface; no scene access, file I/O or per-tile nodes.
var roof_frame := Transform3D.IDENTITY
var half_span := 2.5
var ridge_height := 4.72
var slope := 0.96
var st: SurfaceTool
var rng := RandomNumberGenerator.new()
var tile_count := 0
var tile_uv_origin := Vector2.ZERO
var tile_uv_size := Vector2.ONE
var tile_side := 1.0
var tile_transform := Transform3D.IDENTITY
var broken_count := 0
var shifted_count := 0

func generate(width: float, depth: float, height: float, rise: float, seed_value: int, weathered: bool=true, single_slope: bool=false) -> ArrayMesh:
	half_span=width*0.5+0.3
	ridge_height=height+rise
	slope=rise/(width*0.5)
	roof_frame=Transform3D.IDENTITY
	var run_width := depth
	var sides := [-1.0,1.0]
	if single_slope:
		half_span=depth+0.6
		slope=rise/depth
		ridge_height=height+rise+slope*0.3
		run_width=width
		sides=[1.0]
		roof_frame=Transform3D(Basis(Vector3(0,0,1),Vector3.UP,Vector3(-1,0,0)),Vector3(0,0,-depth*0.5-0.3))
	rng.seed=seed_value
	tile_count=0
	broken_count=0
	shifted_count=0
	var damage_rng := RandomNumberGenerator.new()
	damage_rng.seed=seed_value+7919
	st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := ceili(half_span/0.25)
	var step := half_span/rows
	for side in sides:
		for row in rows:
			var distance := row*step
			var length := minf(step*1.6,half_span-distance)
			var z := -run_width*0.5-0.3
			var column := 0
			while z<run_width*0.5+0.29:
				var width_tile := minf(0.35+rng.randf_range(-0.04,0.04),run_width*0.5+0.3-z)
				if column==0 and row%2==1: width_tile*=0.5
				# Independent seeded samples avoid the former repeating diagonal damage.
				var damaged := weathered and damage_rng.randf()<0.022
				var moved := weathered and damage_rng.randf()<0.016
				var damage := damage_rng.randi_range(1,2) if damaged else 0
				tile(side,distance,z+width_tile*0.5,maxf(width_tile-0.024,0.006),length,damage,moved)
				z+=width_tile
				column+=1
	st.generate_tangents()
	st.index()
	var mesh := st.commit()
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/pixelart/roof_clay.gdshader")
	material.set_shader_parameter("cavity_strength",0.78)
	mesh.surface_set_material(0,material)
	return mesh

func face(a: Vector3,b: Vector3,c: Vector3,color: Color, cavity: float=1.0) -> void:
	var normal := (b-a).cross(c-a).normalized()
	color.a=cavity
	for p in [a,c,b]:
		st.set_normal(roof_frame.basis*tile_transform.basis*normal)
		st.set_color(color)
		st.set_uv(Vector2(p.z,p.x))
		st.set_uv2(Vector2((p.z-tile_uv_origin.x)/tile_uv_size.x+0.5,(tile_uv_origin.y-p.x*tile_side)/tile_uv_size.y))
		st.add_vertex(roof_frame*tile_transform*p)

func point(uv: Vector2, side: float, distance: float, z: float, lift: float) -> Vector3:
	var x := side*(half_span-distance-uv.y)
	return Vector3(x,ridge_height-absf(x)*slope+lift,z+uv.x)

func tile(side: float, distance: float, z: float, width: float, length: float, damage: int=0, shifted: bool=false, front_edge: bool=false) -> void:
	tile_count+=1
	tile_uv_origin=Vector2(z,half_span-distance)
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
		var roof_normal := Vector3(side*slope,1,0).normalized()
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

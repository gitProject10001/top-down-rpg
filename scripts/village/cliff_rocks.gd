@tool
extends RefCounted
## Deterministic faceted outcrops; one mesh, not hundreds of scene nodes.
static func build(terrain: Node3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7129
	var limit: float = terrain.extent*0.5-64
	var center: Vector2 = terrain.plateau_center.clamp(Vector2.ONE*(-limit),Vector2.ONE*limit)
	var radius: float = terrain.plateau_radius
	var height: float = terrain.plateau_height
	for side in range(4):
		var along := -radius
		while along < radius:
			var width := rng.randf_range(1.6,3.5)
			var outward := Vector2.RIGHT.rotated(side*PI/2)
			var tangent := outward.orthogonal()
			var horizontal := center+outward*(radius-0.8)+tangent*along
			# Leave the entire south access and its shoulders unobstructed.
			if not (side == 1 and absf(along)<9):
				var y := 0.0
				while y < height-0.3:
					var h := minf(rng.randf_range(0.85,2.6),height-y+0.1)
					var stagger := rng.randf_range(-0.42,0.42)*width
					var p := horizontal+outward*rng.randf_range(-0.45,0.45)+tangent*stagger
					var low := radius-4.0
					var high := radius+3.0
					for k in range(12):
						var mid := (low+high)*0.5
						var test := center+outward*mid+tangent*(along+stagger)
						if terrain.height_at(test.x,test.y)>y+h*0.43: low = mid
						else: high = mid
					p += outward*((low+high)*0.5-radius+0.65)
					_rock(st,rng,Vector3(p.x,y+h*0.43,p.y),Vector3(width*rng.randf_range(0.9,1.3),h,3.0),side*PI/2+PI/2)
					y += h*0.85
				for j in range(rng.randi_range(1,3)):
					var p := horizontal+outward*rng.randf_range(1.2,4.0)+tangent*rng.randf_range(-1,1)
					var size := rng.randf_range(0.25,0.85)
					_rock(st,rng,Vector3(p.x,terrain.height_at(p.x,p.y)+size*0.28,p.y),Vector3(size*1.3,size,size),rng.randf()*TAU)
			along += width*0.88
	# Rock banks taper down with the ramp, keeping its central ten metres clear.
	for sign_value in [-1,1]:
		for z in range(int(radius)-5,int(radius)+24,2):
			var p := center+Vector2(sign_value*6.8,z)
			var h: float = terrain.height_at(center.x+sign_value*5.4,p.y)
			var y := 0.0
			while y<h:
				var size_y := minf(1.8,h-y+0.2)
				_rock(st,rng,Vector3(p.x,y+size_y*0.4,p.y),Vector3(2.1,size_y,2.0),0)
				y += 1.5
	st.generate_normals()
	st.index()
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.85,0.82,0.72)
	material.roughness = 1
	material.metallic_specular = 0
	mesh.surface_set_material(0,material)
	return mesh

static func _rock(st: SurfaceTool, rng: RandomNumberGenerator, pos: Vector3, size: Vector3, angle: float) -> void:
	var points: Array[Vector3] = []
	var bevel := PackedVector2Array([Vector2(-0.32,-0.5),Vector2(0.30,-0.5),Vector2(0.5,-0.29),Vector2(0.5,0.28),Vector2(0.29,0.5),Vector2(-0.30,0.5),Vector2(-0.5,0.30),Vector2(-0.5,-0.28)])
	var rotation := Basis(Vector3.UP,angle+rng.randf_range(-0.32,0.32))*Basis(Vector3.FORWARD,rng.randf_range(-0.18,0.18))
	var lean := Vector2(rng.randf_range(-0.18,0.18),rng.randf_range(-0.16,0.16))
	var top_scale := rng.randf_range(0.52,0.88)
	var shoulder := rng.randf_range(0.05,0.32)
	for ring in range(3):
		var scale := top_scale if ring == 2 else (0.85 if ring == 0 else 1.0)
		for p in bevel:
			var v := Vector3(p.x*scale+rng.randf_range(-0.07,0.07)+lean.x*ring*0.5,[-0.5,shoulder,0.5][ring]+rng.randf_range(-0.08,0.08),p.y*scale+rng.randf_range(-0.07,0.07)+lean.y*ring*0.5)
			points.append(pos+rotation*(v*size))
	var color := Color(0.34,0.35,0.30).lerp(Color(0.47,0.42,0.30),rng.randf())*rng.randf_range(0.72,1.12)
	for ring in range(2):
		for i in range(8):
			var a := ring*8+i
			var b := ring*8+(i+1)%8
			var tint := color*rng.randf_range(0.82,1.10)
			_face(st,points[a],points[b+8],points[a+8],tint)
			_face(st,points[a],points[b],points[b+8],tint)
	for i in range(1,7): _face(st,points[16],points[16+i],points[17+i],color*1.12)

static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for p in [a,b,c]:
		st.set_color(color)
		st.add_vertex(p)

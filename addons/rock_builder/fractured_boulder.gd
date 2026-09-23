@tool
extends RefCounted
## Intersect fracture planes to obtain broad, coherent rock faces (not noisy triangle strips).
static func build(seed_value: int,color: Color) -> ArrayMesh:
 var rng := RandomNumberGenerator.new(); rng.seed=seed_value
 var flip := -1.0 if rng.randf()<0.5 else 1.0
 var split := rng.randf_range(0.60,0.77)
 var shoulder := rng.randf_range(0.48,0.76)
 # Major slab plus a subordinate attached ledge: unequal masses with a shared bedding axis.
 var pieces := [[Vector3(split,1,1),Vector3((split-1)*0.5*flip,0,0)],
  [Vector3(1-split+0.06,shoulder,rng.randf_range(0.83,1.0)),Vector3(split*0.5*flip,0,0)]]
 if seed_value%4==0: pieces=[[Vector3.ONE,Vector3.ZERO]]
 var positions := PackedVector3Array(); var normals := PackedVector3Array(); var colors := PackedColorArray()
 var parts: Array[PackedVector3Array]=[]
 var material: Material
 for i in pieces.size():
  var mesh := _solid(seed_value+i*7919,color)
  var arrays := mesh.surface_get_arrays(0)
  var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var source_normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var scale: Vector3=pieces[i][0]; var offset: Vector3=pieces[i][1]
  for j in points.size():
   points[j]=points[j]*scale+offset
   source_normals[j]=(source_normals[j]/scale).normalized()
  parts.append(points); positions.append_array(points); normals.append_array(source_normals)
  colors.append_array(arrays[Mesh.ARRAY_COLOR]); material=mesh.surface_get_material(0)
 # One dominant fracture inclination spans the entire mass, including its shoulder.
 var lean := Vector2(rng.randf_range(0.15,0.28)*flip,rng.randf_range(-0.10,0.10))
 var horizontal_scale := Vector2(1.0+absf(lean.x),1.0+absf(lean.y))
 for i in positions.size():
  var v := positions[i]
  positions[i]=Vector3((v.x+(v.y-0.5)*lean.x)/horizontal_scale.x,v.y,(v.z+(v.y-0.5)*lean.y)/horizontal_scale.y)
  var n := normals[i]
  normals[i]=Vector3(n.x*horizontal_scale.x,n.y-lean.x*n.x-lean.y*n.z,n.z*horizontal_scale.y).normalized()
 for part in parts:
  for i in part.size():
   var v := part[i]
   part[i]=Vector3((v.x+(v.y-0.5)*lean.x)/horizontal_scale.x,v.y,(v.z+(v.y-0.5)*lean.y)/horizontal_scale.y)
 var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=positions; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=colors
 var result := ArrayMesh.new(); result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 result.surface_set_material(0,material); result.set_meta("collision_parts",parts)
 return result

static func _solid(seed_value: int,color: Color,faceted: bool=false,geological: bool=false) -> ArrayMesh:
 var rng := RandomNumberGenerator.new(); rng.seed=seed_value
 var planes: Array[Plane]=[]
 var tilt := 0.13 if faceted else 0.07
 for axis in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK]:
  var normal: Vector3=(axis+Vector3(rng.randf_range(-tilt,tilt),rng.randf_range(-0.18,0.18) if axis.y==0.0 else 0.0,rng.randf_range(-tilt,tilt))).normalized()
  planes.append(Plane(normal,rng.randf_range(0.46,0.53)))
 for x in [-1,1]:
  for z in [-1,1]:
   if geological:
    # A few unequal breaks, rather than the same bevel on all eight corners.
    var chipped := rng.randf()<0.35
    planes.append(Plane(Vector3(x,rng.randf_range(-0.08,0.08),z).normalized(),rng.randf_range(0.53,0.61) if chipped else rng.randf_range(0.67,0.74)))
    planes.append(Plane(Vector3(x*0.8,1,z*0.8).normalized(),rng.randf_range(0.59,0.68) if chipped else rng.randf_range(0.78,0.87)))
   else:
    planes.append(Plane(Vector3(x,rng.randf_range(-0.08,0.08),z).normalized(),rng.randf_range(0.55,0.64) if faceted else rng.randf_range(0.60,0.68)))
    planes.append(Plane(Vector3(x*rng.randf_range(0.6,1.0),1.0,z*rng.randf_range(0.6,1.0)).normalized(),rng.randf_range(0.65,0.76) if faceted else rng.randf_range(0.73,0.81)))
 var vertices := PackedVector3Array()
 for a in planes.size():
  for b in range(a+1,planes.size()):
   for c in range(b+1,planes.size()):
    var point=planes[a].intersect_3(planes[b],planes[c])
    if point==null: continue
    var inside := true
    for plane in planes:
     if plane.distance_to(point)>0.0001: inside=false; break
    if not inside: continue
    var duplicate := false
    for v in vertices:
     if v.distance_squared_to(point)<0.00000001: duplicate=true; break
    if not duplicate: vertices.append(point)
 var minimum := Vector3(INF,INF,INF); var maximum := -minimum
 for v in vertices: minimum=minimum.min(v); maximum=maximum.max(v)
 var size := maximum-minimum
 var positions := PackedVector3Array(); var normals := PackedVector3Array(); var colors := PackedColorArray()
 for plane in planes:
  var face: Array[Vector3]=[]; var center := Vector3.ZERO
  for v in vertices:
   if absf(plane.distance_to(v))<0.0002: face.append(v); center+=v
  if face.size()<3: continue
  center/=face.size()
  var u := plane.normal.cross(Vector3.UP if absf(plane.normal.y)<0.9 else Vector3.RIGHT).normalized()
  var w := plane.normal.cross(u)
  face.sort_custom(func(a,b): return atan2((a-center).dot(w),(a-center).dot(u))>atan2((b-center).dot(w),(b-center).dot(u)))
  var tint := color*rng.randf_range(0.92,1.06); tint.a=1
  for i in range(1,face.size()-1):
   var triangle := PackedVector3Array()
   for v in [face[0],face[i],face[i+1]]: triangle.append((v-minimum)/size-Vector3(0.5,0,0.5))
   var normal := (triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
   positions.append_array(triangle)
   for j in 3: normals.append(normal); colors.append(tint)
 var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=positions; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=colors
 var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var material := StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.roughness=0.95
 mesh.surface_set_material(0,material)
 return mesh

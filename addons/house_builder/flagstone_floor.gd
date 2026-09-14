@tool
extends RefCounted
const Sample=preload("res://addons/house_builder/stone_wall_sample.gd")
const Join=preload("res://addons/house_builder/mesh_join.gd")
static func apply(house: Node3D,source: ArrayMesh) -> ArrayMesh:
 # Sloped/stepped walks retain their dedicated profile for now.
 if house.has_method("is_curtain_wall") and absf(house._slope_rise)>0.001: return source
 var floor_y: float=house.wall_height+0.18
 var faces := source.get_faces()
 var domains: Array=[]
 for i in range(0,faces.size(),3):
  var a: Vector3=faces[i]; var b: Vector3=faces[i+1]; var c: Vector3=faces[i+2]
  if absf(a.y-floor_y)>0.002 or absf(b.y-floor_y)>0.002 or absf(c.y-floor_y)>0.002: continue
  if (b-a).cross(c-a).length_squared()<0.000001: continue
  var center := (a+b+c)/3.0
  var cutters: Array=[]
  for edge in [[a,b],[b,c],[c,a]]:
   var normal: Vector3=(edge[1]-edge[0]).cross(Vector3.UP).normalized()
   if normal.dot(center-edge[0])>0: normal=-normal
   # Remove the outside of each triangle, keeping staircase openings untouched.
   cutters.append([Plane(-normal,-normal.dot(edge[0]))])
  domains.append({"cuts":cutters,"min":Vector2(minf(a.x,minf(b.x,c.x)),minf(a.z,minf(b.z,c.z))),"max":Vector2(maxf(a.x,maxf(b.x,c.x)),maxf(a.z,maxf(b.z,c.z)))})
 if domains.is_empty(): return source
 var result := ArrayMesh.new(); Join.append(result,source,Transform3D.IDENTITY,[])
 for i in result.get_surface_count():
  var material=result.surface_get_material(i)
  if material is ShaderMaterial and material.shader.resource_path=="res://shaders/pixelart/painted_architecture.gdshader":
   material=material.duplicate(); material.set_shader_parameter("plain_horizontal_stone",true); result.surface_set_material(i,material)
 var combined := SurfaceTool.new(); combined.begin(Mesh.PRIMITIVE_TRIANGLES)
 var piece_count := 0
 var sample=Sample.new(); sample._rng.seed=house.house_seed+593
 var random := RandomNumberGenerator.new(); random.seed=house.house_seed+319
 var rows := maxi(1,roundi((house.depth+0.24)/0.85))
 var row_height: float=(house.depth+0.24)/rows
 for row in rows:
  var x: float=-house.width*0.5-0.12
  while x<house.width*0.5+0.11:
   var remaining: float=house.width*0.5+0.12-x
   var width := minf(random.randf_range(0.7,1.4),remaining)
   if remaining-width<0.3: width=remaining
   var z: float=-house.depth*0.5-0.12+(row+0.5)*row_height
   sample._surface=SurfaceTool.new(); sample._surface.begin(Mesh.PRIMITIVE_TRIANGLES)
   sample.stone(Vector3.ZERO,maxf(0.01,width-0.022),row_height-0.024)
   var arrays: Array=sample._surface.commit_to_arrays()
   var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
   var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
   var transform := Transform3D(Basis(Vector3.RIGHT,Vector3.FORWARD,Vector3.UP*0.15),Vector3(x+width*0.5,floor_y-0.023,z))
   for i in range(0,positions.size(),3):
    var a: Vector3=transform*positions[i]; var b: Vector3=transform*positions[i+1]; var c: Vector3=transform*positions[i+2]
    tool.set_normal((c-a).cross(b-a).normalized())
    for j in 3: tool.set_color(colors[i+j]); tool.add_vertex(transform*positions[i+j])
   var tile := tool.commit()
   for domain in domains:
    if x+width<domain.min.x or x>domain.max.x or z+row_height*0.5<domain.min.y or z-row_height*0.5>domain.max.y: continue
    var clipped := ArrayMesh.new()
    Join.append(clipped,tile,Transform3D.IDENTITY,domain.cuts)
    for surface in clipped.get_surface_count():
     combined.append_from(clipped,surface,Transform3D.IDENTITY); piece_count+=1
   x+=width
 sample.free()
 # Consolidate the clipped pieces into one surface/material for the whole walkway.
 if piece_count>0:
  combined.commit(result)
  var material := ShaderMaterial.new(); material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
  result.surface_set_material(result.get_surface_count()-1,material)
 return result

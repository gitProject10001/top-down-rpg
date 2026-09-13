extends Node3D
## Visual sections of the final mesh: native TriangleMesh BVH preserves authored holes.
## No collision geometry is added. Hollow shells are never filled across their rooms.
const SLICES := 192
const SECTION = preload("res://shaders/pixelart/architecture_section.gdshader")
var cache: Dictionary = {}
var solid_sections := 0
var hollow_sections := 0
var last_build_usec := 0

func intervals(tree: TriangleMesh, faces: PackedVector3Array, origin: Vector3, direction: Vector3) -> Array[Vector2]:
 var result: Array[Vector2]=[]
 var cursor := origin
 var winding := 0
 var begin := 0.0
 for hit_number in 96:
  var hit := tree.intersect_ray(cursor,direction)
  if hit.is_empty(): break
  var point: Vector3=hit.position
  var distance := (point-origin).dot(direction)
  var f: int=hit.face_index*3
  var normal := (faces[f+1]-faces[f]).cross(faces[f+2]-faces[f])
  var sign_value := 1 if normal.dot(direction)>0.0 else -1
  var previous := winding
  winding+=sign_value
  if previous==0: begin=distance
  elif winding==0 and distance-begin>0.002: result.append(Vector2(begin,distance))
  cursor=point+direction*0.001
 return result

func update_sections(sources: Array[MeshInstance3D], focus: Vector3, camera_position: Vector3, radius: float) -> void:
 var started := Time.get_ticks_usec()
 solid_sections=0; hollow_sections=0
 for entry in cache.values(): entry.node.visible=false
 if radius<=0.01: return
 var direction := (camera_position-focus).normalized()
 var right := direction.cross(Vector3.UP).normalized()
 var up := right.cross(direction)
 var alive := {}
 for source in sources:
  if not is_instance_valid(source) or source.mesh==null: continue
  # Tile roofs and moving joinery have no masonry section.
  if source.name not in [&"Walls",&"Roof"]: continue
  var id := source.get_instance_id(); alive[id]=true
  if not source.is_visible_in_tree(): continue
  var box := source.get_aabb()
  var center := source.to_global(box.get_center())
  var reach := (source.global_basis*box.size).length()*0.5+0.2
  var offset := center-focus
  var along := offset.dot(direction)
  if along+reach<0.2 or center.y+reach<focus.y+0.35: continue
  if absf((offset-direction*along).length()-(radius+maxf(along,0.0)*0.16))>reach*1.2: continue
  var parent := source.get_parent().get_parent()
  var hollow := not parent.has_method("is_curtain_wall")
  if source.name==&"Roof" and hollow: continue
  if not cache.has(id) or cache[id].mesh!=source.mesh:
   if cache.has(id): cache[id].node.queue_free()
   var node := MeshInstance3D.new(); node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   node.name="HollowSection" if hollow else "StoneSection"
   var material := ShaderMaterial.new(); material.shader=SECTION
   material.set_shader_parameter("hollow",hollow)
   node.material_override=material; add_child(node)
   var tree := source.mesh.generate_triangle_mesh()
   cache[id]={"node":node,"mesh":source.mesh,"tree":tree,"faces":tree.get_faces(),"material":material}
  var entry: Dictionary=cache[id]
  var inverse := source.global_transform.affine_inverse()
  var vertices := PackedVector3Array()
  # Each angular strip is bounded by actual entry/exit intersections with the mesh.
  for i in SLICES:
   var angle := TAU*(float(i)+0.5)/SLICES
   var radial := radius+0.065*sin(angle*13.0)+0.035*sin(angle*29.0+1.2)
   var radial_direction := right*cos(angle)+up*sin(angle)
   var base := focus+radial_direction*radial
   var ray := direction+radial_direction*0.16
   var local_direction := (inverse.basis*ray).normalized()
   var unit := (source.global_basis*local_direction).dot(direction)
   var origin := inverse*(base-ray*100.0)
   for span in intervals(entry.tree,entry.faces,origin,local_direction):
    var low := maxf(0.2,span.x*unit-100.0)
    var high := span.y*unit-100.0
    if high<=low: continue
    var corners: Array[Vector3]=[]
    for edge in [i,i+1]:
     var a := TAU*float(edge)/SLICES
     var r := radius+0.065*sin(a*13.0)+0.035*sin(a*29.0+1.2)
     var p := focus+(right*cos(a)+up*sin(a))*r
     var edge_ray := direction+(right*cos(a)+up*sin(a))*0.16
     corners.append(p+edge_ray*low); corners.append(p+edge_ray*high)
    if maxf(maxf(corners[0].y,corners[1].y),maxf(corners[2].y,corners[3].y))<focus.y+0.35: continue
    for index in [0,1,2,2,1,3]: vertices.append(corners[index])
  if vertices.is_empty(): continue
  var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices
  var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  entry.node.mesh=mesh; entry.node.visible=true
  entry.material.set_shader_parameter("floor_height",focus.y+0.35)
  if hollow: hollow_sections+=1
  else: solid_sections+=1
 for id in cache.keys():
  if not alive.has(id): cache[id].node.queue_free(); cache.erase(id)
 last_build_usec=Time.get_ticks_usec()-started

extends Node3D
## Visual sections of the final mesh: native TriangleMesh BVH preserves authored holes.
## No collision geometry is added. Hollow shells are never filled across their rooms.
const SLICES := 96
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

static func cut_frame(source: MeshInstance3D, focus: Vector3, camera_position: Vector3) -> Transform3D:
 var volume: Node3D=source
 var ancestor := source.get_parent()
 while ancestor:
  if ancestor is Node3D and ancestor.has_method("wall_count"):
   volume=ancestor; break
  ancestor=ancestor.get_parent()
 var height := source.to_global(source.get_aabb().get_center()).y
 if volume!=source:
  height=volume.global_position.y+float(volume.wall_height)*0.5
 var direction := (camera_position-focus).normalized()
 var center := focus+direction*maxf(0.0,(height-focus.y)/maxf(direction.y,0.1))
 var right := volume.global_basis.x; right.y=0; right=right.normalized()
 var forward := right.cross(Vector3.UP).normalized()
 return Transform3D(Basis(right,Vector3.UP,forward),center)

func _quad(vertices: PackedVector3Array, a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
 for p in [a,b,c,c,b,d]: vertices.append(p)

func update_sections(sources: Array[MeshInstance3D], focus: Vector3, camera_position: Vector3, maximum_radius: float, radii: Dictionary={}) -> void:
 var started := Time.get_ticks_usec()
 solid_sections=0; hollow_sections=0
 for entry in cache.values(): entry.node.visible=false
 if maximum_radius<=0.01: return
 var direction := (camera_position-focus).normalized()
 var alive := {}
 for source in sources:
  if not is_instance_valid(source) or source.mesh==null: continue
  if source.name not in [&"Walls",&"Roof"]: continue
  var id := source.get_instance_id(); alive[id]=true
  var radius: float=radii.get(id,maximum_radius) if not radii.is_empty() else maximum_radius
  if radius<=0.01: continue
  if not source.is_visible_in_tree(): continue
  var box := source.get_aabb()
  var center := source.to_global(box.get_center())
  var reach := (source.global_basis*box.size).length()*0.5+0.2
  var frame := cut_frame(source,focus,camera_position)
  var offset := frame.basis.inverse()*(center-frame.origin)
  if absf(offset.x)>radius+reach or absf(offset.z)>radius+reach or center.y+reach<focus.y+0.35: continue
  if (center-focus).dot(direction)+reach<0.2: continue
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
  var floor_y := focus.y+0.35
  var local_up := (inverse.basis*Vector3.UP).normalized()
  var vertical_unit := (source.global_basis*local_up).y
  # Four upright faces of the rectangular cut; mesh intervals retain real voids.
  for side in 4:
   var normal: Vector3=[frame.basis.x,frame.basis.z,-frame.basis.x,-frame.basis.z][side]
   var tangent := normal.cross(Vector3.UP)
   for i in SLICES:
    var step := 2.0*radius/SLICES
    var base := frame.origin+normal*radius+tangent*(-radius+(i+0.5)*step)
    base.y=floor_y-100.0
    for span in intervals(entry.tree,entry.faces,inverse*base,local_up):
     var low := maxf(floor_y,base.y+span.x*vertical_unit)
     var high := base.y+span.y*vertical_unit
     if high<=low: continue
     var a := base-tangent*step*0.5; a.y=low
     var b := a; b.y=high
     _quad(vertices,a,b,a+tangent*step,b+tangent*step)
  # Horizontal base closes the newly exposed wall thickness as well.
  var ray := frame.basis.z
  var local_ray := (inverse.basis*ray).normalized()
  var unit := (source.global_basis*local_ray).dot(ray)
  for i in SLICES:
   var step := 2.0*radius/SLICES
   var base := frame.origin+frame.basis.x*(-radius+(i+0.5)*step)-ray*100.0
   base.y=floor_y
   for span in intervals(entry.tree,entry.faces,inverse*base,local_ray):
    var low := maxf(-radius,span.x*unit-100.0)
    var high := minf(radius,span.y*unit-100.0)
    if high<=low: continue
    var a := base+ray*(100.0+low)-frame.basis.x*step*0.5
    var b := a+ray*(high-low)
    _quad(vertices,a,b,a+frame.basis.x*step,b+frame.basis.x*step)
  if vertices.is_empty(): continue
  var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices
  var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  entry.node.mesh=mesh; entry.node.visible=true
  entry.material.set_shader_parameter("floor_height",floor_y-0.001)
  entry.material.set_shader_parameter("focus",focus)
  entry.material.set_shader_parameter("view_direction",direction)
  if hollow: hollow_sections+=1
  else: solid_sections+=1
 for id in cache.keys():
  if not alive.has(id): cache[id].node.queue_free(); cache.erase(id)
 last_build_usec=Time.get_ticks_usec()-started

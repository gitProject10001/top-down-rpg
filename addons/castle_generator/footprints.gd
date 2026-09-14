@tool
extends RefCounted
## Planar authoring footprints. No generated meshes and no mutation during preview.
static func collect(node: Node3D, frame: Transform3D=Transform3D.IDENTITY) -> Dictionary:
 if not frame.basis.y.is_equal_approx(Vector3.UP) or not frame.basis.is_equal_approx(frame.basis.orthonormalized()) or frame.basis.determinant()<0:
  return {"error":"Inclinazione o scala non supportata: "+str(node.name)}
 if node.wing_enabled: return {"error":"Ala integrata non ancora supportata: "+str(node.name)}
 var polygon := PackedVector2Array()
 for point in [Vector3(-node.width/2,0,-node.depth/2),Vector3(node.width/2,0,-node.depth/2),Vector3(node.width/2,0,node.depth/2),Vector3(-node.width/2,0,node.depth/2)]:
  var p: Vector3=frame*point; polygon.append(Vector2(p.x,p.z))
 var shapes: Array=[polygon]
 for volume in node.authored_volumes():
  var local: Transform3D=volume.transform
  if volume.attached:
   var tangent: Vector3=(node.wall_point(volume.host_wall,1,0)-node.wall_point(volume.host_wall,0,0)).normalized()
   local=Transform3D(Basis(tangent,Vector3.UP,node.wall_normal(volume.host_wall)),node.wall_point(volume.host_wall,volume.host_offset*node.wall_length(volume.host_wall)*0.5,0,volume.depth*0.5-node.WALL_THICKNESS-0.08))
  var child=collect(volume,frame*volume.get_parent().transform*local)
  if child.has("error"): return child
  shapes.append_array(child.shapes)
 return {"shapes":shapes}

static func overlap(a: PackedVector2Array,b: PackedVector2Array) -> bool:
 for polygon in [a,b]:
  for i in polygon.size():
   var edge: Vector2=polygon[(i+1)%polygon.size()]-polygon[i]
   var axis := Vector2(-edge.y,edge.x).normalized()
   var amin := INF; var amax := -INF; var bmin := INF; var bmax := -INF
   for p in a: amin=minf(amin,p.dot(axis)); amax=maxf(amax,p.dot(axis))
   for p in b: bmin=minf(bmin,p.dot(axis)); bmax=maxf(bmax,p.dot(axis))
   if amax<bmin or bmax<amin: return false
 return true

static func distance(a: PackedVector2Array,b: PackedVector2Array) -> float:
 if overlap(a,b): return 0
 var result := INF
 for pair in [[a,b],[b,a]]:
  for p in pair[0]:
   for i in pair[1].size():
    result=minf(result,p.distance_to(Geometry2D.get_closest_point_to_segment(p,pair[1][i],pair[1][(i+1)%pair[1].size()])))
 return result

static func validate(groups: Dictionary,span: Vector2,minimum_open: float) -> PackedStringArray:
 var errors := PackedStringArray(); var occupied := 0.0
 var inner := Rect2(Vector2(5,-span.y+5),span-Vector2(10,10))
 var ids := groups.keys()
 for index in ids.size():
  var id: String=ids[index]
  for shape in groups[id]:
   var area := 0.0
   for i in shape.size():
    var p: Vector2=shape[i]; var q: Vector2=shape[(i+1)%shape.size()]
    area+=p.cross(q)
    if p.x<inner.position.x-0.001 or p.x>inner.end.x+0.001 or p.y<inner.position.y-0.001 or p.y>inner.end.y+0.001:
     if not errors.has(id+": ingombro oltre il margine delle mura."): errors.append(id+": ingombro oltre il margine delle mura.")
   occupied+=absf(area)*0.5
   for previous in range(index):
    for other in groups[ids[previous]]:
     if distance(shape,other)<0.999:
      var message := id+" / "+str(ids[previous])+": passaggio inferiore a 1 m."
      if not errors.has(message): errors.append(message)
 # Conservative sum: overlapping pieces of the SAME building may count twice.
 if 1.0-occupied/inner.get_area()<minimum_open: errors.append("Spazio scoperto insufficiente (stima conservativa degli accessori).")
 return errors

@tool
extends RefCounted
const Geometry=preload("res://addons/rock_builder/outcrop_geometry.gd")
## Partition a footprint with oblique geological faults, never rows of instances.
static func cells(outline: PackedVector2Array,metric: Vector3,height: float,spacing: float,seed_value: int) -> Array[Dictionary]:
 metric/=maxf(metric.y,0.001)
 var world := PackedVector2Array()
 var horizontal := Vector2(maxf(metric.x,0.001),maxf(metric.z,0.001))
 for p in outline: world.append(p*horizontal)
 var bounds := Rect2(world[0],Vector2.ZERO)
 for p in world: bounds=bounds.expand(p)
 var span := maxf(spacing*2.6,height*0.85)*metric.y
 span=maxf(span,sqrt(bounds.size.x*bounds.size.y/96.0))
 var queue: Array[Dictionary]=[{"id":"fault","poly":PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])}]
 var result: Array[Dictionary]=[]
 while not queue.is_empty():
  var record: Dictionary=queue.pop_back()
  var polygon: PackedVector2Array=record.poly
  var box := Rect2(polygon[0],Vector2.ZERO)
  for p in polygon: box=box.expand(p)
  var area := 0.0
  for i in polygon.size(): area+=polygon[i].cross(polygon[(i+1)%polygon.size()])
  var rng := RandomNumberGenerator.new(); rng.seed=hash(str(seed_value)+record.id)
  if absf(area)*0.5>span*span*0.8 and record.id.length()<24:
   var angle := (0.0 if box.size.x>box.size.y else PI*0.5)+rng.randf_range(-0.55,0.55)
   var normal := Vector2(cos(angle),sin(angle))
   var center := box.get_center()+normal*maxf(box.size.x,box.size.y)*rng.randf_range(-0.12,0.12)
   var a := half(polygon,normal,center.dot(normal))
   var b := half(polygon,-normal,-center.dot(normal))
   if a.size()>=3 and b.size()>=3:
    queue.append({"id":record.id+"0","poly":a}); queue.append({"id":record.id+"1","poly":b}); continue
  var fragments := Geometry2D.intersect_polygons(polygon,world)
  for f in fragments.size():
   var fragment: PackedVector2Array=fragments[f]
   var center := Vector2.ZERO
   for p in fragment: center+=p
   center/=fragment.size()
   var uv := (center-bounds.position)/bounds.size.max(Vector2.ONE*0.001)
   # A coherent broad crest descends to one side; only a small local displacement per fault.
   var crest := 0.62+0.34*sin(uv.x*2.2+0.5)+0.12*(1.0-uv.y)
   var top := clampf(crest+rng.randf_range(-0.16,0.12),0.42,1.12)
   var local := PackedVector2Array()
   for p in fragment: local.append(p/horizontal)
   result.append({"id":record.id+"_"+str(f),"polygon":local,"center":center/horizontal,"top":top,"tint":rng.randf_range(0.94,1.04)})
 return result
static func half(polygon: PackedVector2Array,normal: Vector2,offset: float) -> PackedVector2Array:
 var result := PackedVector2Array()
 for i in polygon.size():
  var a := polygon[i]; var b := polygon[(i+1)%polygon.size()]
  var da := normal.dot(a)-offset; var db := normal.dot(b)-offset
  if da<=0: result.append(a)
  if (da<0 and db>0) or (da>0 and db<0): result.append(a.lerp(b,da/(da-db)))
 return result
static func geometry(record: Dictionary,holes: Array,height: float,color: Color) -> ArrayMesh:
 var polygon: PackedVector2Array=record.polygon
 var center: Vector2=record.center
 var rings: Array=[polygon]
 # Hole contours are intersected by the same partition; subtraction keeps through-openings.
 var solids: Array[PackedVector2Array]=[polygon]
 for hole in holes:
  var next: Array[PackedVector2Array]=[]
  for solid in solids: next.append_array(Geometry2D.clip_polygons(solid,hole))
  solids=next
 var faces := PackedVector3Array()
 var handled := {}
 for i in solids.size():
  if Geometry2D.is_polygon_clockwise(solids[i]): continue
  rings=[solids[i]]
  for j in solids.size():
   if Geometry2D.is_polygon_clockwise(solids[j]) and Geometry2D.is_point_in_polygon(solids[j][0],solids[i]): rings.append(solids[j]); handled[j]=true
  var top := Geometry.top_faces(rings,record.top)
  var sides := Geometry.walls(rings,record.top,-0.06)
  var bottom := Geometry.top_faces(rings,-0.06)
  faces.append_array(top); faces.append_array(sides)
  for k in range(0,bottom.size(),3): faces.append_array(PackedVector3Array([bottom[k],bottom[k+2],bottom[k+1]]))
 for i in faces.size():
  var p := faces[i]
  # Fine fissure width and a shared inclined bedding plane, instead of detached boxes.
  var xz := (Vector2(p.x,p.z)-center)*0.995
  p.x=xz.x; p.z=xz.y
  if p.y>0: p.y+=0.035*(xz.x-xz.y)/maxf(height,0.3)
  faces[i]=p
 var material := StandardMaterial3D.new(); material.albedo_color=color*record.tint; material.albedo_color.a=1; material.roughness=1
 var mesh := Geometry.mesh(faces,material)
 mesh.set_meta("exact_faces",faces)
 return mesh

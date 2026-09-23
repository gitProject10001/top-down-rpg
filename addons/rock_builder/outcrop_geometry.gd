@tool
extends RefCounted
## Horizontal trapezoid decomposition: exact concave contours and holes, no voxel grid.
static func contains(p: Vector2, rings: Array) -> bool:
 if rings.is_empty() or not Geometry2D.is_point_in_polygon(p,rings[0]): return false
 for i in range(1,rings.size()):
  if Geometry2D.is_point_in_polygon(p,rings[i]): return false
 return true

static func validate(rings: Array) -> String:
 if rings.is_empty(): return "Disegna un contorno."
 var edges: Array=[]
 for r in rings.size():
  var ring: PackedVector2Array=rings[r]
  if ring.size()<3 or ring.size()>256: return "Ogni contorno richiede 3–256 punti."
  var area := 0.0
  for i in ring.size():
   var a := ring[i]; var b := ring[(i+1)%ring.size()]
   if not a.is_finite() or a.distance_to(b)<0.001: return "Punti coincidenti o non validi."
   area+=a.cross(b)
   edges.append([a,b,r,i,ring.size()])
  if absf(area)<0.001: return "Area troppo piccola."
  if r>0 and not Geometry2D.is_point_in_polygon(ring[0],rings[0]): return "Un buco deve essere interno all'area."
  for other in range(1,r):
   if Geometry2D.is_point_in_polygon(ring[0],rings[other]) or Geometry2D.is_point_in_polygon(rings[other][0],ring): return "I buchi non possono sovrapporsi."
 for i in edges.size():
  for j in range(i+1,edges.size()):
   var a: Array=edges[i]; var b: Array=edges[j]
   if a[2]==b[2] and (absi(a[3]-b[3])==1 or absi(a[3]-b[3])==a[4]-1): continue
   if Geometry2D.segment_intersects_segment(a[0],a[1],b[0],b[1])!=null or a[0].distance_to(Geometry2D.get_closest_point_to_segment(a[0],b[0],b[1]))<0.0001 or b[0].distance_to(Geometry2D.get_closest_point_to_segment(b[0],a[0],a[1]))<0.0001: return "I contorni non possono incrociarsi o toccarsi."
 return ""

static func top_faces(rings: Array, height: float) -> PackedVector3Array:
 var levels: Array[float]=[]
 var edges: Array=[]
 for ring in rings:
  for i in ring.size():
   var a: Vector2=ring[i]; var b: Vector2=ring[(i+1)%ring.size()]
   if not levels.has(a.y): levels.append(a.y)
   if absf(a.y-b.y)>0.000001: edges.append([a,b])
 levels.sort()
 var faces := PackedVector3Array()
 for row in range(levels.size()-1):
  var low := levels[row]; var high := levels[row+1]; var mid := (low+high)*0.5
  var crossing: Array=[]
  for e in edges:
   if mid>minf(e[0].y,e[1].y) and mid<maxf(e[0].y,e[1].y): crossing.append(e)
  crossing.sort_custom(func(a,b): return x_at(a,mid)<x_at(b,mid))
  for i in range(0,crossing.size()-1,2):
   var left: Array=crossing[i]; var right: Array=crossing[i+1]
   var a := Vector3(x_at(left,low),height,low); var b := Vector3(x_at(right,low),height,low)
   var c := Vector3(x_at(right,high),height,high); var d := Vector3(x_at(left,high),height,high)
   triangle(faces,a,b,c); triangle(faces,a,c,d)
 return faces

static func x_at(edge: Array,y: float) -> float:
 return lerpf(edge[0].x,edge[1].x,(y-edge[0].y)/(edge[1].y-edge[0].y))
static func triangle(faces: PackedVector3Array,a: Vector3,b: Vector3,c: Vector3) -> void:
 if (b-a).cross(c-a).length_squared()>0.00000001: faces.append_array(PackedVector3Array([a,b,c]))
static func walls(rings: Array,height: float,base: float) -> PackedVector3Array:
 var faces := PackedVector3Array()
 for ri in rings.size():
  var ring: PackedVector2Array=rings[ri].duplicate()
  # Clockwise in XZ gives outward Godot front faces for outer boundary.
  if Geometry2D.is_polygon_clockwise(ring)==(ri==0): ring.reverse()
  for i in ring.size():
   var p := ring[i]; var q := ring[(i+1)%ring.size()]
   var a := Vector3(p.x,base,p.y); var b := Vector3(q.x,base,q.y)
   var c := Vector3(q.x,height,q.y); var d := Vector3(p.x,height,p.y)
   triangle(faces,a,b,c); triangle(faces,a,c,d)
 return faces
## Faceted recesses stay inside the footprint; the top rim and holes remain exact.
static func geological_walls(rings: Array,height: float,seed_value: int) -> PackedVector3Array:
 var faces := PackedVector3Array()
 for ri in rings.size():
  var ring: PackedVector2Array=rings[ri].duplicate()
  if Geometry2D.is_polygon_clockwise(ring)==(ri==0): ring.reverse()
  for i in ring.size():
   var p := ring[i]; var q := ring[(i+1)%ring.size()]
   var tangent := (q-p).normalized(); var inward := Vector2(-tangent.y,tangent.x)
   var count := maxi(1,ceili(p.distance_to(q)/1.25))
   var columns: Array=[]
   for j in range(count+1):
    var t := float(j)/count; var point := p.lerp(q,t)
    var limit := minf(0.75,minf(point.distance_to(p),point.distance_to(q))*0.3)
    for other in rings:
     for e in other.size():
      var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,other[e],other[(e+1)%other.size()]))
      if distance>0.0001: limit=minf(limit,distance*0.25)
    var rng := RandomNumberGenerator.new(); rng.seed=hash(str(seed_value)+":"+str(point))
    var column := PackedVector3Array()
    for level in [-0.5,0.0,0.32,0.37,0.72,1.0]:
     var y: float=-0.5 if level<0 else height*level
     var recess: float=0.0 if level==1.0 or level<0.0 else limit*rng.randf_range(0.25,1.0)
     if level==0.37: recess=limit
     var v := point+inward*recess
     column.append(Vector3(v.x,y,v.y))
    columns.append(column)
   for j in count:
    for level in range(5):
     var a: Vector3=columns[j][level]; var b: Vector3=columns[j+1][level]
     var c: Vector3=columns[j+1][level+1]; var d: Vector3=columns[j][level+1]
     triangle(faces,a,b,c); triangle(faces,a,c,d)
 return faces
static func mesh(faces: PackedVector3Array,material: Material) -> ArrayMesh:
 var result := ArrayMesh.new()
 if faces.is_empty(): return result
 var normals := PackedVector3Array()
 for i in range(0,faces.size(),3):
  var normal := (faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized()
  for j in 3: normals.append(normal)
 var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=faces; arrays[Mesh.ARRAY_NORMAL]=normals
 result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 result.surface_set_material(0,material)
 return result

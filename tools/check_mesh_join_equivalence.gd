extends SceneTree
const Join=preload("res://addons/house_builder/mesh_join.gd")
var failures:=0
func _initialize(): call_deferred("run")
static func triangles(mesh: Mesh) -> Dictionary:
 var result: Dictionary={}
 for surface in mesh.get_surface_count():
  var a=mesh.surface_get_arrays(surface)
  var material=mesh.surface_get_material(surface)
  var normal_mapped: bool=material is ShaderMaterial and "NORMAL_MAP" in material.shader.code
  var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
  var idx: PackedInt32Array=a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
  for j in range(0,idx.size() if not idx.is_empty() else v.size(),3):
   var corners: Array=[]
   for k in 3:
    var i: int=idx[j+k] if not idx.is_empty() else j+k
    corners.append([v[i],a[Mesh.ARRAY_NORMAL][i],a[Mesh.ARRAY_TEX_UV][i] if a[Mesh.ARRAY_TEX_UV]!=null else Vector2.ZERO,a[Mesh.ARRAY_TEX_UV2][i] if a[Mesh.ARRAY_TEX_UV2]!=null else Vector2.ZERO,a[Mesh.ARRAY_COLOR][i] if a[Mesh.ARRAY_COLOR]!=null else Color.WHITE,Vector4(a[Mesh.ARRAY_TANGENT][i*4],a[Mesh.ARRAY_TANGENT][i*4+1],a[Mesh.ARRAY_TANGENT][i*4+2],a[Mesh.ARRAY_TANGENT][i*4+3]) if normal_mapped and a[Mesh.ARRAY_TANGENT]!=null else Vector4.ZERO])
   if (corners[1][0]-corners[0][0]).cross(corners[2][0]-corners[0][0]).length_squared()<1e-10: continue
   var center: Vector3=(corners[0][0]+corners[1][0]+corners[2][0])/3
   var key:=Vector3i((center*1000).round())
   if not result.has(key): result[key]=[]
   result[key].append(corners)
 return result
static func equivalent(a: Mesh,b: Mesh) -> bool:
 var old:=triangles(a); var fresh:=triangles(b)
 var missing:=0; var attributes:=0; var total:=0; var tangent_max:=0.0; var tangent_errors:=0
 for key in old:
  for tri in old[key]:
   total+=1
   var found:=false
   for delta in [Vector3i.ZERO,Vector3i(1,0,0),Vector3i(-1,0,0),Vector3i(0,1,0),Vector3i(0,-1,0),Vector3i(0,0,1),Vector3i(0,0,-1)]:
    var bucket: Array=fresh.get(key+delta,[])
    for other in bucket:
     for rotation in 3:
      var same:=true
      for k in 3:
       if tri[k][0].distance_to(other[(k+rotation)%3][0])>0.00003: same=false; break
      if same:
       for k in 3:
        var x: Array=tri[k]; var y: Array=other[(k+rotation)%3]
        if x[5]!=Vector4.ZERO and y[5]!=Vector4.ZERO:
         var difference: float=(x[5]-y[5]).length()
         tangent_max=maxf(tangent_max,difference)
         if difference>.01: tangent_errors+=1
        if x[1].distance_to(y[1])>0.001 or x[2].distance_to(y[2])>0.0001 or x[3].distance_to(y[3])>0.0001 or (Vector4(x[4].r,x[4].g,x[4].b,x[4].a)-Vector4(y[4].r,y[4].g,y[4].b,y[4].a)).length()>0.001: attributes+=1
       bucket.erase(other); found=true; break
     if found: break
    if found: break
   if not found: missing+=1
 var extra:=0
 for bucket in fresh.values(): extra+=bucket.size()
 print("GEOMETRY triangles=",total," missing=",missing," extra=",extra," attributes=",attributes," tangent_max=",tangent_max," tangent_errors=",tangent_errors)
 return missing==0 and extra==0 and attributes==0 and tangent_errors==0
func run():
 var reference=preload("res://tools/fixtures/mesh_join_reference.gd")
 var roof=load("res://addons/house_builder/roof_mesh.gd").new().generate(3.21,2.57,3.,1.8,515)
 var cases: Array=[[],[[Plane(Vector3.RIGHT,.21),Plane(Vector3.LEFT,.19),Plane(Vector3.UP,5.)]],[[Plane(Vector3.FORWARD,-.7)],[Plane(Vector3(1,1,0).normalized(),3.)]],[[Plane(Vector3.UP,100.)]]]
 for transform in [Transform3D.IDENTITY,Transform3D(Basis(Vector3.UP,.71).scaled(Vector3(1.1,.9,1.3)),Vector3(.27,.12,-.37))]:
  for cuts in cases:
   var a:=ArrayMesh.new(); var b:=ArrayMesh.new()
   reference.append(a,roof,transform,cuts)
   Join.append(b,roof,transform,cuts)
   if not equivalent(a,b): failures+=1
 print("MESH_JOIN_EQUIVALENCE failures=",failures)
 quit(failures)

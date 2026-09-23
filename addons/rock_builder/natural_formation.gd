@tool
extends RefCounted
const Geometry=preload("res://addons/rock_builder/outcrop_geometry.gd")
const Boulder=preload("res://addons/rock_builder/fractured_boulder.gd")

static func envelope(node: Node3D,contours: Array) -> PackedVector3Array:
 var top := Geometry.top_faces(contours,1.0)
 var faces := PackedVector3Array()
 for i in range(0,top.size(),3):
  subdivide(faces,top[i],top[i+1],top[i+2],2)
 var walls := Geometry.walls(contours,1.0,-0.15)
 for i in range(0,walls.size(),3): subdivide(faces,walls[i],walls[i+1],walls[i+2],2)
 var bottom := Geometry.top_faces(contours,-0.15)
 for i in range(0,bottom.size(),3): faces.append_array(PackedVector3Array([bottom[i],bottom[i+2],bottom[i+1]]))
 var bounds := Rect2(contours[0][0],Vector2.ZERO)
 for p in contours[0]: bounds=bounds.expand(p)
 for i in faces.size():
  var p := faces[i]
  if p.y>0:
   p.y=node.height*profile_at(node,Vector2(p.x,p.z),bounds)*p.y
  faces[i]=p
 return faces
static func subdivide(output: PackedVector3Array,a: Vector3,b: Vector3,c: Vector3,depth: int) -> void:
 if depth==0: Geometry.triangle(output,a,b,c); return
 var ab := (a+b)*0.5; var bc := (b+c)*0.5; var ca := (c+a)*0.5
 subdivide(output,a,ab,ca,depth-1); subdivide(output,ab,b,bc,depth-1)
 subdivide(output,ca,bc,c,depth-1); subdivide(output,ab,bc,ca,depth-1)

# Large rooted masses establish the silhouette. Smaller shelves are subordinate,
# never a uniform layer of similarly sized stones over every surface.
static func masses(node: Node3D,contours: Array) -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 var rng := RandomNumberGenerator.new(); rng.seed=node.rock_seed
 var metric := Vector3(node.global_basis.x.length(),node.global_basis.y.length(),node.global_basis.z.length())
 # Work in world metres: enlarging the envelope adds space, not larger rocks.
 var bounds := Rect2(contours[0][0],Vector2.ZERO)
 for p in contours[0]: bounds=bounds.expand(p)
 var span: float=node.natural_rock_size
 var spacing: float=node.natural_min_spacing if node.natural_min_spacing>0 else span*0.56
 if node.walkable:
  var ring: PackedVector2Array=contours[0]
  for edge in ring.size():
   var a := Vector3(ring[edge].x,0,ring[edge].y)
   var b := Vector3(ring[(edge+1)%ring.size()].x,0,ring[(edge+1)%ring.size()].y)
   var tangent := ((b-a)*metric).normalized()
   var length := ((b-a)*metric).length()
   var walked := 0.0
   while walked<length:
    var width := minf(span*rng.randf_range(0.7,1.45),length-walked+span*0.15)
    var point := a.lerp(b,minf(1,(walked+width*0.5)/length))
    var frame := Basis(tangent,Vector3.UP,tangent.cross(Vector3.UP))
    var height: float=node.height*metric.y*rng.randf_range(1.02,1.12)
    append_mass(result,point,frame,Vector3(width*1.14,height,span*rng.randf_range(0.46,0.7)),metric,rng)
    walked+=width*0.9 if node.natural_min_spacing==0 else spacing
 else:
  var centers: Array[Vector3]=[]
  var radii: Array[float]=[]
  var area := bounds.size.x*metric.x*bounds.size.y*metric.z
  for attempt in mini(4000,ceili(area/(span*span)*90) if node.natural_min_spacing==0 else ceili(area/(spacing*spacing)*28)):
   var point := Vector3(rng.randf_range(bounds.position.x,bounds.end.x),0,rng.randf_range(bounds.position.y,bounds.end.y))
   if not Geometry.contains(Vector2(point.x,point.z),contours): continue
   var radius := spacing
   var accepted := true
   for j in centers.size():
    if ((point-centers[j])*metric).length()<(radius+radii[j])*0.5: accepted=false; break
   if not accepted: continue
   centers.append(point); radii.append(radius)
   var profile := profile_at(node,Vector2(point.x,point.z),bounds)
   var height: float=node.height*metric.y*maxf(0.28,profile)*rng.randf_range(0.90,1.15)
   var frame := Basis(Vector3.UP,rng.randf_range(-0.16,0.16))
   # Shared bedding inclination: a crag has a direction, rather than independent rotations.
   frame.y=Vector3(0.16,1,-0.24)
   append_mass(result,point,frame,Vector3(span*rng.randf_range(0.85,1.35),height,span*rng.randf_range(0.7,1.15)),metric,rng)
 # Thin a deterministic candidate set: density never rescales or moves retained masses.
 var retained: Array[Dictionary]=[]
 for record in result:
  var selection := RandomNumberGenerator.new(); selection.seed=hash(str(node.rock_seed)+record.id+":density")
  if selection.randf()>=node.natural_density: continue
  retained.append(record)
  if node.natural_max_rocks>0 and retained.size()>=node.natural_max_rocks: break
 result=retained
 add_secondary_scales(result,metric,bounds,node)
 return result

# Independent random streams preserve the large composition when detailing changes.
# Shelves attach to a parent; chips form sparse clusters at its exposed foot.
static func add_secondary_scales(result: Array[Dictionary],metric: Vector3,bounds: Rect2,node: Node3D) -> void:
 var parents := result.duplicate(true)
 for parent in parents:
  var rng := RandomNumberGenerator.new(); rng.seed=hash(str(node.rock_seed)+parent.id+":details")
  var transform: Transform3D=parent.transform
  var world := Basis.from_scale(metric)*transform.basis
  var width := minf(world.x.length(),world.z.length())
  var tall := world.y.length()
  var point := transform.origin
  var outward := Vector3(point.x-bounds.get_center().x,0,point.z-bounds.get_center().y)*metric
  if outward.length_squared()<0.01: outward=Vector3.FORWARD
  outward=outward.normalized()
  var frame := Basis(Vector3.UP,atan2(outward.x,outward.z)+rng.randf_range(-0.15,0.15))
  var foot := Vector3(point.x,0,point.z)+outward*width*0.43/metric
  if rng.randf()<node.medium_rock_density:
   var size := Vector3(node.medium_rock_size,node.medium_rock_size*0.75,node.medium_rock_size*0.9)
   append_mass(result,foot,frame,size,metric,rng)
   result[-1].id=parent.id+"_shelf"; result[-1].layer="medium"
  rng.seed=hash(str(node.rock_seed)+parent.id+":small")
  if rng.randf()>node.small_rock_density: continue
  var chip_size: float=node.small_rock_size
  for chip in rng.randi_range(2,3):
   var side := Vector3(outward.z,0,-outward.x)
   var position := foot+(outward*width*rng.randf_range(0.18,0.38)+side*width*rng.randf_range(-0.3,0.3))/metric
   var size := chip_size*rng.randf_range(0.65,1.15)
   append_mass(result,position,frame,Vector3(size*1.3,size*0.75,size),metric,rng)
   result[-1].id=parent.id+"_chip_%d"%chip; result[-1].layer="small"
   result[-1].transform.origin.y=-size*0.12/metric.y
   if not node.walkable and rng.randf()<node.small_surface_ratio:
    place_on_parent(result[-1],parent,node,metric,size,rng)

static func source_mesh(node: Node3D,variant: int) -> ArrayMesh:
 var key := "natural:%d:%d"%[node.rock_seed,variant]
 if not node._rock_cache.has(key):
  node._rock_cache[key]=Boulder._solid(node.rock_seed+variant*3571,node.stone_color,false,true)
  node.last_new_rocks+=1
 return node._rock_cache[key]

static func place_on_parent(record: Dictionary,parent: Dictionary,node: Node3D,metric: Vector3,size: float,rng: RandomNumberGenerator) -> void:
 var vertices: PackedVector3Array=source_mesh(node,parent.variant).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 var surfaces: Array=[]; var total := 0.0
 var frame: Transform3D=Transform3D(Basis.from_scale(metric),Vector3.ZERO)*parent.transform
 for i in range(0,vertices.size(),3):
  var a: Vector3=frame*vertices[i]; var b: Vector3=frame*vertices[i+1]; var c: Vector3=frame*vertices[i+2]
  var cross := (c-a).cross(b-a)
  if cross.normalized().y<0.65: continue
  total+=cross.length()*0.5; surfaces.append([a,b,c,cross.normalized(),total])
 if surfaces.is_empty(): return
 var target := rng.randf()*total
 for face in surfaces:
  if target>face[4]: continue
  # Place near a supporting face centre and embed slightly into the parent surface.
  var point: Vector3=(face[0]+face[1]+face[2])/3.0
  var normal: Vector3=face[3]
  var tangent := Vector3.RIGHT.slide(normal).normalized()
  var orientation := Basis(tangent,normal,tangent.cross(normal)).rotated(normal,rng.randf_range(-PI,PI))
  record.transform=Transform3D(Basis.from_scale(Vector3.ONE/metric)*orientation*Basis.from_scale(Vector3(size*1.3,size*0.75,size)),(point-normal*size*0.18)/metric)
  return

static func append_mass(result: Array[Dictionary],point: Vector3,frame: Basis,size: Vector3,metric: Vector3,rng: RandomNumberGenerator) -> void:
 var index := result.size()
 var variation := Basis(Vector3.UP,rng.randf_range(-0.065,0.065))
 var transform := Transform3D(Basis.from_scale(Vector3.ONE/metric)*frame*variation*Basis.from_scale(size),point-Vector3.UP*0.12)
 result.append({"id":"mass_%d"%index,"variant":index%12,"layer":"large","transform":transform})

static func profile_at(node: Node3D,point: Vector2,bounds: Rect2) -> float:
 if node.walkable: return 1.0
 var q := (point-bounds.position)/bounds.size.max(Vector2.ONE*0.001)
 if node.shape_kind==1:
  var distance := INF; var along := 0.0; var length := 0.0; var walked := 0.0
  for j in range(node.outline.size()-1): length+=node.outline[j].distance_to(node.outline[j+1])
  for j in range(node.outline.size()-1):
   var a: Vector2=node.outline[j]; var b: Vector2=node.outline[j+1]
   var closest := Geometry2D.get_closest_point_to_segment(point,a,b)
   var d := closest.distance_to(point)
   if d<distance: distance=d; along=(walked+a.distance_to(closest))/maxf(length,0.001)
   walked+=a.distance_to(b)
  var crown := pow(maxf(0.0,1.0-distance/(node.path_width*0.56)),0.65)
  return (0.12+0.88*crown)*(0.6+0.4*sin(along*PI))
 var cross_profile := clampf(minf(q.y/0.20,(1.0-q.y)/0.65),0,1)
 var run := clampf(minf(q.x/0.14,(1.0-q.x)/0.28),0,1)
 return 0.12+0.88*cross_profile*lerpf(0.4,1.0,run)

static func rebuild(node: Node3D,contours: Array) -> void:
 var faces := envelope(node,contours)
 if not node.walkable and node.natural_detail and not node._editing:
  for i in faces.size():
   if faces[i].y>0: faces[i].y*=0.45
 if is_instance_valid(node._generated): node._generated.free()
 node._generated=Node3D.new(); node._generated.name="_NaturalEnvelope"; node.add_child(node._generated,false,Node.INTERNAL_MODE_BACK)
 var material := StandardMaterial3D.new(); material.albedo_color=node.stone_color; material.roughness=1
 var visual := MeshInstance3D.new(); visual.mesh=Geometry.mesh(faces,material); node._generated.add_child(visual)
 if node.walkable:
  var inset := Geometry2D.offset_polygon(contours[0],-0.35,Geometry2D.JOIN_MITER)
  var soil_rings: Array=[]
  if inset.size()==1:
   soil_rings.append(inset[0])
   for i in range(1,contours.size()):
    var expanded := Geometry2D.offset_polygon(contours[i],0.25,Geometry2D.JOIN_MITER)
    if expanded.size()==1: soil_rings.append(expanded[0])
  if not soil_rings.is_empty() and Geometry.validate(soil_rings).is_empty():
   var soil_material := StandardMaterial3D.new(); soil_material.albedo_color=node.ground_color; soil_material.roughness=1
   var soil := MeshInstance3D.new(); soil.name="Terra"
   soil.mesh=Geometry.mesh(Geometry.top_faces(soil_rings,node.height+0.008),soil_material); node._generated.add_child(soil)
 if node.collisions_enabled:
  var body := StaticBody3D.new(); var collision := CollisionShape3D.new(); var shape := ConcavePolygonShape3D.new()
  shape.set_faces(faces); collision.shape=shape; body.add_child(collision); body.set_meta("art_ground_surface",node.walkable); node._generated.add_child(body)
 if node._editing: return
 if not is_instance_valid(node._rocks):
  node._rocks=Node3D.new(); node._rocks.name="_SurfaceRocks"; node.add_child(node._rocks,false,Node.INTERNAL_MODE_BACK)
 var wanted := {}; node.rock_keys.clear(); node.rock_positions.clear(); node.last_new_rocks=0
 if node.natural_detail:
  for record in masses(node,contours):
   var position: Vector3=record.transform.origin
   var hole_safe := true
   for i in range(1,contours.size()):
    var hole: PackedVector2Array=contours[i]
    if Geometry2D.is_point_in_polygon(Vector2(position.x,position.z),hole): hole_safe=false
    for j in hole.size():
     if Vector2(position.x,position.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(position.x,position.z),hole[j],hole[(j+1)%hole.size()]))<node.rock_spacing: hole_safe=false
   if not hole_safe: continue
   wanted[record.id]=true
   var instance := node._rocks.get_node_or_null(NodePath(record.id)) as MeshInstance3D
   if instance==null:
    instance=MeshInstance3D.new(); instance.name=record.id; node._rocks.add_child(instance)
   instance.mesh=source_mesh(node,record.variant); instance.transform=record.transform
   if node.rock_offsets.has(record.id): instance.position+=node.rock_offsets[record.id]
   # Keep the complete source solid below the walkable crest, including bevels.
   if node.walkable:
    var highest := -INF
    for vertex in instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
     highest=maxf(highest,(instance.transform*vertex).y)
    instance.position.y-=maxf(0.0,highest-node.height)
   # Check the actual projected solid, including shear and user offsets, against holes.
   var projected := PackedVector2Array()
   for vertex in instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
    var p: Vector3=instance.transform*vertex
    projected.append(Vector2(p.x,p.z))
   var footprint := Geometry2D.convex_hull(projected)
   for i in range(1,contours.size()):
    if not Geometry2D.intersect_polygons(footprint,contours[i]).is_empty(): hole_safe=false; break
   if not hole_safe:
    wanted.erase(record.id); instance.free(); continue
   node.rock_keys.append(record.id); node.rock_positions.append(instance.position)
   if node.collisions_enabled: node._rock_collision(instance)
 for child in node._rocks.get_children():
  if not wanted.has(str(child.name)): child.free()

extends SceneTree
const Outcrop=preload("res://addons/rock_builder/outcrop.gd")
const Geometry=preload("res://addons/rock_builder/outcrop_geometry.gd")
var failures := 0
func check(value: bool,label: String) -> void:
 if not value: failures+=1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for seed_value in 12:
  var boulder := preload("res://addons/rock_builder/fractured_boulder.gd").build(seed_value,Color.GRAY)
  var arrays := boulder.surface_get_arrays(0)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  check(vertices==preload("res://addons/rock_builder/fractured_boulder.gd").build(seed_value,Color.GRAY).surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"deterministic fracture planes")
  var offset := 0
  for part in boulder.get_meta("collision_parts"):
   var edges := {}; var center := Vector3.ZERO
   for point in part: center+=point
   center/=part.size()
   for i in range(0,part.size(),3):
    var face_center: Vector3=(part[i]+part[i+1]+part[i+2])/3
    check(normals[offset+i].dot(face_center-center)>0,"outward fracture faces")
    for j in 3:
     var a := str(part[i+j].snapped(Vector3.ONE*0.0001))
     var b := str(part[i+(j+1)%3].snapped(Vector3.ONE*0.0001))
     var key := a+":"+b if a<b else b+":"+a
     edges[key]=edges.get(key,0)+1
   for count in edges.values(): check(count==2,"closed collision part")
   offset+=part.size()
 var node := Outcrop.new(); root.add_child(node)
 node.holes=[PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)])]; node.rebuild()
 check(node.last_error.is_empty(),"valid holed contour")
 var faces := Geometry.top_faces(node.rings(),3); var area := 0.0
 for i in range(0,faces.size(),3):
  var normal := (faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]); area+=normal.length()/2
  check(normal.y>0,"top winding")
  var c := (faces[i]+faces[i+1]+faces[i+2])/3
  check(not (absf(c.x)<1 and absf(c.z)<1),"no top triangles in hole")
 check(absf(area-76)<0.001,"exact area minus hole")
 var old := node.snapshot(); var ids := {}
 for rock in node._rocks.get_children(): ids[rock.name]=[rock.mesh.get_instance_id(),rock.mesh.get_meta("courses",1)]
 node.height=3.137; node.rebuild()
 for rock in node._rocks.get_children():
  if ids[rock.name][1]==rock.mesh.get_meta("courses",1): check(ids[rock.name][0]==rock.mesh.get_instance_id(),"unchanged courses reuse detail mesh")
 node.begin_edit(); node.height=4.219; node.rebuild(); node.apply_state(old); node.end_edit(); node.rebuild()
 check(node.height==3,"cancel")
 var undo := UndoRedo.new(); undo.create_action("height")
 undo.add_do_property(node,"height",5.0); undo.add_undo_property(node,"height",3.0); undo.commit_action(); node.rebuild()
 undo.undo(); node.rebuild(); check(node.height==3,"undo")
 undo.redo(); node.rebuild(); check(node.height==5,"redo")
 await physics_frame; await physics_frame
 var space := root.world_3d.direct_space_state
 check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,10,0),Vector3(0,-2,0))).is_empty(),"hole collision open")
 var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3,10,0),Vector3(3,-2,0)))
 check(not hit.is_empty() and absf(hit.position.y-5)<0.001,"top collision")
 check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,2,-10),Vector3(0,2,-2))).is_empty(),"outer wall")
 check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,2,0),Vector3(2,2,0))).is_empty(),"hole wall")
 var packed := PackedScene.new(); check(packed.pack(node)==OK,"pack")
 check(ResourceSaver.save(packed,"user://rock_outcrop_check.tscn")==OK,"save")
 var restored=load("user://rock_outcrop_check.tscn").instantiate(); root.add_child(restored)
 check(restored.holes==node.holes and restored.height==node.height,"reopen")
 check(restored.get_child_count()==0,"internal generated content"); restored.free()
 node.apply_state(old); node.outline=PackedVector2Array([Vector2(-5,-4),Vector2(5,-4),Vector2(5,0),Vector2(2,0),Vector2(2,4),Vector2(-5,4)]); node.rebuild()
 check(node.last_error.is_empty(),"concave area")
 var before: Node=node._generated; node.holes.append(node.holes[0]); node.rebuild()
 check(not node.last_error.is_empty() and node._generated==before,"invalid holes preserve previous result")
 node.holes=[]; node.shape_kind=1; node.outline=PackedVector2Array([Vector2(-5,0),Vector2(0,2),Vector2(5,0)]); node.rebuild(); check(node.last_error.is_empty(),"path")
 node.shape_kind=2; node.volume_size=Vector2(7,9); node.rebuild(); check(node.last_error.is_empty(),"volume")
 node.walkable=false; node.rebuild(); await physics_frame; await physics_frame
 check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-10,6,0),Vector3(0,6,0))).is_empty(),"forbidden region barrier")
 var timings: Array[float]=[]
 for i in 20:
  node.height=3.0137+i*0.0037; node.rebuild(); timings.append(node.last_build_ms)
 timings.sort(); print("OUTCROP_EDIT median_ms=",timings[10]," p95_ms=",timings[18])
 var baseline := {}
 for rock in node._rocks.get_children():
  if str(rock.name).begins_with("chip_"): continue
  baseline[rock.name]=[rock.mesh.get_instance_id(),rock.mesh.get_meta("courses",1)]
 node.scale=Vector3(1,4,1)
 await process_frame; await process_frame
 check(node.rock_keys.size()<baseline.size(),"native vertical scale composes fewer broader continuous masses")
 node.scale=Vector3.ONE
 await process_frame; await process_frame
 for rock in node._rocks.get_children():
  if baseline.has(rock.name): check(rock.mesh.get_instance_id()==baseline[rock.name][0],"scale restoration reuses original mesh")
 node.scale=Vector3.ONE*2
 await process_frame; await process_frame
 for rock in node._rocks.get_children():
  if baseline.has(rock.name): check(rock.mesh.get_instance_id()==baseline[rock.name][0],"uniform scale preserves proportions")
 node.scale=Vector3.ONE
 var parent := Node3D.new(); root.add_child(parent); node.reparent(parent,false)
 parent.scale=Vector3(1,4,1)
 await process_frame; await process_frame
 check(node.rock_keys.size()<baseline.size(),"parent scale composes fewer broader continuous masses")
 node.reparent(root,false); parent.free()
 undo.clear_history(); node.free(); print("ROCK_OUTCROP failures=",failures); quit(1 if failures else 0)

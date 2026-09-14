extends SceneTree
const Terrace=preload("res://addons/rock_builder/terrace.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var terrace=Terrace.new(); root.add_child(terrace)
 var first=terrace.proposal(); assert(not first.has("error")); assert(first==terrace.proposal())
 terrace.apply(first)
 await physics_frame
 await physics_frame
 var query=PhysicsRayQueryParameters3D.create(Vector3(0,10,0),Vector3(0,-1,0))
 var hit=terrace.get_world_3d().direct_space_state.intersect_ray(query)
 assert(not hit.is_empty() and is_equal_approx(hit.position.y,3),"Platform top must collide at discrete height")
 query=PhysicsRayQueryParameters3D.create(Vector3(0,1,20),Vector3(0,1,0))
 assert(not terrace.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"Platform side must block passage")
 var ramp_state=terrace.snapshot()
 terrace.ramp_enabled=false; terrace.apply(terrace.proposal())
 var full_count=terrace.border().get_child_count()
 terrace.ramp_enabled=true; terrace.apply(terrace.proposal())
 assert(terrace.border().get_child_count()<full_count,"Ramp must open the border")
 terrace.ramp_enabled=false; terrace.apply(terrace.proposal())
 assert(terrace.border().get_child_count()==full_count,"Disabling ramp restores automatic border")
 terrace.ramp_enabled=true; terrace.apply(ramp_state)
 var obstruction=terrace.border().node_for("0_0")
 var original_position: Vector3=obstruction.position
 obstruction.position=Vector3(0,0,7)
 assert(terrace.proposal().has("error"),"Authored rock blocking ramp must produce an error")
 assert(obstruction.position==Vector3(0,0,7))
 obstruction.position=original_position
 terrace.ramp_length=2; assert(terrace.proposal().has("error"),"Reject steep ramp")
 terrace.ramp_length=6
 var rock=terrace.border().node_for("0_0"); rock.position.x+=0.5
 var authored_position: Vector3=rock.position
 var detail=Node3D.new(); detail.name="Manuale"; rock.add_child(detail); detail.owner=terrace
 terrace.border().node_for("0_1").free()
 var before=terrace.snapshot()
 terrace.terrace_seed=98; terrace.elevation=4; terrace.ramp_length=8
 var next=terrace.proposal(); assert(not next.has("error"))
 var undo=UndoRedo.new(); undo.create_action("Terrace")
 undo.add_do_method(terrace.apply.bind(next)); undo.add_undo_method(terrace.apply.bind(before)); undo.commit_action()
 assert(rock.position==authored_position and rock.get_node("Manuale")==detail)
 assert(terrace.border().node_for("0_1")==null)
 assert(terrace.applied_state.elevation==4)
 undo.undo(); assert(terrace.applied_state.elevation==3)
 undo.redo(); assert(terrace.applied_state.elevation==4)
 var packed=PackedScene.new(); assert(packed.pack(terrace)==OK)
 var copy=packed.instantiate(); root.add_child(copy)
 assert(copy.applied_state.elevation==4 and copy.border().node_for("0_1")==null)
 assert(copy.border().node_for("0_0").position==authored_position)
 assert(copy.border().node_for("0_0").has_node("Manuale"))
 assert(copy.core!=null)
 terrace.footprint=Vector2(1,12); assert(terrace.proposal().has("error"))
 assert(terrace.applied_state.elevation==4)
 undo.clear_history(); undo.free(); copy.free(); terrace.free()
 print("ROCK_TERRACE_COLLISION_MANUAL_UNDO_SAVE_OK")
 quit()

extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var group=preload("res://addons/rock_builder/formation.gd").new(); root.add_child(group)
 var first=group.proposal(); assert(not first.has("error"))
 assert(first==group.proposal())
 group.apply(first)
 assert(group.proposal().protected==0,"Fresh generated rocks remain automatic")
 var moved=group.node_for("0_0"); moved.position.x+=1
 var custom := Node3D.new(); custom.name="DettaglioManuale"; moved.add_child(custom); custom.owner=group
 var position: Vector3=moved.position
 group.node_for("1_2").free()
 group.formation_seed+=1
 var proposal=group.proposal(); assert(proposal.protected>=1)
 var undo := UndoRedo.new(); undo.create_action("Regenerate")
 undo.add_do_method(group.apply.bind(proposal)); undo.add_undo_method(group.apply.bind(group.snapshot())); undo.commit_action()
 assert(moved.position==position and moved.get_node("DettaglioManuale")==custom)
 assert(group.node_for("1_2")==null)
 undo.undo(); assert(moved.position==position and group.node_for("1_2")==null)
 undo.redo(); assert(moved.position==position)
 var packed := PackedScene.new(); assert(packed.pack(group)==OK)
 var copy=packed.instantiate(); assert(copy.node_for("0_0").position==position and copy.node_for("1_2")==null)
 assert(copy.proposal().protected>=1); copy.free()
 var before_invalid=group.snapshot()
 moved.position=Vector3(0,0,1)
 assert(group.proposal().has("error"),"Manual obstruction must be reported")
 assert(moved.position==Vector3(0,0,1),"Validation must not move authored nodes")
 group.apply(before_invalid)
 var clean=preload("res://addons/rock_builder/formation.gd").new(); root.add_child(clean)
 for seed_value in range(12):
  clean.formation_seed=seed_value
  assert(not clean.proposal().has("error"),"Gentle guide must keep free side clear")
 clean.curve.clear_points()
 for point in [Vector3(-8,0,-8),Vector3(8,0,8),Vector3(-8,0,8),Vector3(8,0,-8)]: clean.curve.add_point(point)
 assert(clean.proposal().has("error"),"Crossing guide must detect rock intrusion")
 clean.free()
 group.curve.set_point_position(1,Vector3(0,1,0)); assert(group.proposal().has("error"))
 undo.clear_history(); undo.free(); group.free()
 print("ROCK_FORMATION_DETERMINISM_MANUAL_DELETE_UNDO_SAVE_OK")
 quit()

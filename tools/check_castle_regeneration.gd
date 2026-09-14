extends SceneTree
const Request=preload("res://addons/castle_generator/request.gd")
const Planner=preload("res://addons/castle_generator/planner.gd")
const Service=preload("res://addons/castle_generator/regeneration.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var request=Request.new(); request.seed_value=17
 var original=Planner.generate(request).plan
 var group=preload("res://addons/castle_generator/materializer.gd").create(original)
 var keep=group.get_node("Mastio"); var hall=group.get_node("CorpoServizi")
 keep.position.z+=0.1
 keep.openings[0]["width"]=1.1
 var edited_doors=keep.openings.duplicate(true)
 var manual=Node3D.new(); manual.name="ManualDetail"; keep.add_child(manual)
 var keep_position: Vector3=keep.position
 var proposal: Dictionary={}
 for seed_value in 100:
  request.seed_value=seed_value
  proposal=Service.propose(group,Planner.generate(request).plan)
  if not proposal.has("error"): break
 assert(not proposal.has("error"),str(proposal))
 assert("keep" in proposal.preserved)
 var previous_baseline: Dictionary=group.get_meta("composition_baseline",{}).duplicate(true)
 var before := {}
 for id in proposal.updates: before[id]=proposal.snapshot[id].transform.origin
 var undo := UndoRedo.new()
 undo.create_action("Regenerate")
 undo.add_do_method(Service.apply.bind(group,proposal.updates,proposal.plan,proposal.baseline))
 undo.add_undo_method(Service.apply.bind(group,before,original,previous_baseline))
 undo.commit_action()
 assert(keep.position==keep_position and keep.openings==edited_doors and keep.get_node("ManualDetail")==manual)
 var again=Service.propose(group,proposal.plan)
 assert(not again.has("error") and "keep" in again.preserved,"Manual override survives repeated regeneration")
 undo.undo(); assert(group.get_meta("composition_plan")==original)
 undo.redo(); assert(group.get_meta("composition_plan")==proposal.plan)
 hall.set_meta("composition_locked",true)
 var locked=Service.propose(group,proposal.plan)
 assert(not locked.has("error") and "hall" in locked.preserved)
 for child in group.find_children("*","Node",true,false): child.owner=group
 var packed := PackedScene.new(); assert(packed.pack(group)==OK)
 var restored=packed.instantiate()
 var persisted=Service.propose(restored,proposal.plan)
 assert(not persisted.has("error") and "hall" in persisted.preserved and "keep" in persisted.preserved)
 assert(restored.get_node("Mastio").openings==edited_doors)
 restored.free()
 hall.position=keep.position
 assert(Service.propose(group,proposal.plan).has("error"),"Overlap with manual edits must block mutation")
 undo.clear_history(); undo.free()
 group.free()
 print("CASTLE_REGEN_MANUAL_DETAILS_LOCKS_CONFLICTS_UNDO_REDO_OK")
 quit()

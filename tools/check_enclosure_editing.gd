extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func run() -> void:
	var group=preload("res://addons/house_builder/fortification_factory.gd").create_enclosure(); root.add_child(group); await settle()
	assert(group.diagnostics().is_empty())
	var gate=group.get_node("TorreOvest/Cortina"); gate.gate_offset=0.25
	var stairs=group.get_node("TorreOvest/InteriorPlan/PrimoPiano/ScalaTetto"); stairs.position.x=1.4
	var before: Dictionary=group.layout_state(); var proposal: Dictionary=group.resize_proposal(Vector2(20,18))
	assert(not proposal.has("error")); group.apply_layout(proposal); await settle()
	assert(group.layout_size()==Vector2(20,18) and group.diagnostics().is_empty())
	assert(gate.gate_offset==0.25 and is_equal_approx(stairs.position.x,1.4),"Authored details survive resizing")
	assert(is_equal_approx(group.entry_position.x,10) and is_equal_approx(group.entry_position.z,4))
	group.apply_layout(before); await settle(); assert(group.layout_size()==Vector2(16,16))
	var unchanged: Dictionary=group.layout_state()
	assert(group.resize_proposal(Vector2(40,40)).has("error") and group.layout_state()==unchanged)
	gate.target_tower=NodePath("../../Missing"); await settle()
	var issues: Array=group.diagnostics()
	assert(not issues.is_empty() and issues.any(func(i): return i.node==NodePath("TorreOvest/Cortina")))
	gate.target_tower=NodePath("../../TorreEst"); await settle()
	group.get_node("TorreEst").position.z=1
	assert(group.resize_proposal(Vector2(20,18)).has("error"),"Freeform layouts are not overwritten")
	group.free(); print("ENCLOSURE_RESIZE_PRESERVATION_DIAGNOSTICS_OK"); quit()

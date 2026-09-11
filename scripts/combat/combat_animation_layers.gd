extends RefCounted
## Per-fighter action clock and lower-body mask. Only the action can be held;
## gait keeps running. During a committed strike the authored full-body clip wins.
static func install(tree: AnimationTree) -> void:
	var sm := tree.tree_root as AnimationNodeStateMachine
	var action := sm.get_node("Slash") as AnimationNodeAnimation
	if action == null: return
	var layers := AnimationNodeBlendTree.new()
	layers.add_node("Action", action)
	layers.add_node("ActionClock", AnimationNodeTimeScale.new())
	var gait := AnimationNodeBlendSpace1D.new()
	for entry in [["block", 0.0], ["walk", 1.0]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = entry[0]
		gait.add_blend_point(clip, entry[1])
	layers.add_node("Gait", gait)
	var mask := AnimationNodeBlend2.new()
	mask.filter_enabled = true
	var walk := tree.get_animation("walk")
	for i in walk.get_track_count():
		var path := walk.track_get_path(i)
		var bone := str(path).get_slice(":", 1)
		if bone in ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]:
			mask.set_filter_path(path, true)
	layers.add_node("Legs", mask)
	layers.connect_node("ActionClock", 0, "Action")
	layers.connect_node("Legs", 0, "ActionClock")
	layers.connect_node("Legs", 1, "Gait")
	layers.connect_node("output", 0, "Legs")
	sm.replace_node("Slash", layers)

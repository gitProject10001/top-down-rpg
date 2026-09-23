extends RefCounted
## UAL free locomotion + humanoid-retargeted Mixamo lower-body strafing.
const CLIPS := {"walk_back":"aim_back", "walk_left":"aim_left", "walk_right":"aim_right", "run_back":"run_back", "run_left":"strafe_left", "run_right":"strafe_right"}
const LEGS := ["Hips","LeftUpperLeg","LeftLowerLeg","LeftFoot","LeftToes","RightUpperLeg","RightLowerLeg","RightFoot","RightToes"]
static func install(player: Player) -> bool:
	var tree := player._tree
	if tree == null or not player.face_movement: return false
	var library := tree.get_animation_library("")
	for key in CLIPS:
		var clip := load("res://assets/models/animations/locomotion/"+CLIPS[key]+".res").duplicate(true) as Animation
		player._strip_root_drift(clip)
		clip.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(key,clip)
		var recovery := clip.duplicate(true) as Animation
		for i in range(recovery.get_track_count()-1,-1,-1):
			if not String(recovery.track_get_path(i)).get_slice(":",1) in LEGS: recovery.remove_track(i)
		var stance_clip := tree.get_animation("idle_sword")
		for i in stance_clip.get_track_count():
			if not String(stance_clip.track_get_path(i)).get_slice(":",1) in LEGS:
				stance_clip.copy_track(i,recovery)
		library.add_animation("recover_"+key,recovery)
	var sm := tree.tree_root as AnimationNodeStateMachine
	var original := sm.get_node("Move")
	if original is AnimationNodeBlendSpace1D:
		original.set_blend_point_position(1,player.walk_speed/player.move_speed)
	var layers := AnimationNodeBlendTree.new()
	layers.add_node("Free",original)
	layers.add_node("FreeClock",AnimationNodeTimeScale.new())
	layers.connect_node("FreeClock",0,"Free")
	layers.add_node("Walk",directional(["walk","walk_back","walk_left","walk_right"]))
	layers.add_node("Run",directional(["jog","run_back","run_left","run_right"]))
	layers.add_node("WalkClock",AnimationNodeTimeScale.new())
	layers.add_node("RunClock",AnimationNodeTimeScale.new())
	layers.connect_node("WalkClock",0,"Walk")
	layers.connect_node("RunClock",0,"Run")
	layers.add_node("Speed",AnimationNodeBlend2.new())
	layers.connect_node("Speed",0,"WalkClock")
	layers.connect_node("Speed",1,"RunClock")
	var stance := AnimationNodeAnimation.new()
	stance.animation = "idle_sword"
	layers.add_node("Stance",stance)
	var legs := AnimationNodeBlend2.new()
	legs.filter_enabled=true
	var walk := tree.get_animation("walk")
	for i in walk.get_track_count():
		var path := walk.track_get_path(i)
		if String(path).get_slice(":",1) in LEGS: legs.set_filter_path(path,true)
	layers.add_node("Legs",legs)
	layers.connect_node("Legs",0,"Stance")
	layers.connect_node("Legs",1,"Speed")
	layers.add_node("Locked",AnimationNodeBlend2.new())
	layers.connect_node("Locked",0,"FreeClock")
	layers.connect_node("Locked",1,"Legs")
	layers.connect_node("output",0,"Locked")
	sm.replace_node("Move",layers)
	tree["parameters/Move/Legs/blend_amount"]=1.0
	return true

static func directional(clips: Array) -> AnimationNodeBlendSpace2D:
	var blend := AnimationNodeBlendSpace2D.new()
	var points := [Vector2(0,1),Vector2(0,-1),Vector2(-1,0),Vector2(1,0)]
	for i in 4:
		var clip := AnimationNodeAnimation.new()
		clip.animation=clips[i]
		blend.add_blend_point(clip,points[i])
	var idle := AnimationNodeAnimation.new()
	idle.animation="idle_sword"
	blend.add_blend_point(idle,Vector2.ZERO)
	return blend

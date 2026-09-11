class_name OgreLimitLayer
extends SkeletonModifier3D
## THE ANATOMY'S LAST WORD. Runs after every other layer (child order is execution order) and
## clamps the upper body's bones to the LIVE joint budgets in scripts/components/joint_limits.gd
## — the same table the ragdoll's physical joints are authored from, so a fighter's anatomy and
## its corpse's can never drift apart.
##
## This is a HYPER-EXTENSION GUARD, not a posture police: the live budgets are generous (a
## shoulder may carry 150 degrees from rest — the Blender refinement pass's own clamp), and the
## clamp returns the input BIT-IDENTICAL whenever a bone is inside its budget. A stack that
## never exceeds anatomy produces exactly the motion it produced before this layer existed,
## which is what keeps the curve-diff gate meaningful: any deviation the diff shows IS a frame
## that was beyond anatomy.
##
## Deliberately not clamped, each for a reason the refactor paid for:
##   - legs and hips: the foot IK's world-contact guarantee must stay the last word below the
##     pelvis (clamping a leg after the plant re-introduces skate);
##   - hands: the grip solve and _wrap_fist own them, and a carried haft legitimately holds the
##     wrist near ~105 degrees — the Blender pass exempts exactly these, so does this.

var solver: OgreSolver

var _bones: Array = []          # [bone_idx, swing_deg, twist_deg], resolved once
var _resolved := false


func _resolve(skel: Skeleton3D) -> void:
	_resolved = true
	for e in JointLimits.CHAIN:
		var budget := Vector2(float(e[4]), float(e[5]))
		if budget.x <= 0.0:
			continue
		var idx := skel.find_bone(String(e[0]))
		if idx >= 0:
			_bones.append([idx, budget.x, budget.y])


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if not _resolved:
		_resolve(skel)
	for e in _bones:
		var idx: int = e[0]
		var rest_q: Quaternion = skel.get_bone_rest(idx).basis.get_rotation_quaternion()
		var pose_q: Quaternion = skel.get_bone_pose_rotation(idx)
		var rel := rest_q.inverse() * pose_q
		var clamped := JointLimits.clamp_swing_twist(rel, e[1], e[2])
		if clamped != rel:
			skel.set_bone_pose_rotation(idx, (rest_q * clamped).normalized())

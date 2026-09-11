class_name ArmGuard
extends SkeletonModifier3D
## Procedural "shield up". Runs in the skeleton's modifier stack — AFTER the AnimationTree has
## written the locomotion pose — and eases the LEFT ARM toward a guard pose by `amount` (0 = pure
## locomotion, 1 = full guard). The shield rides the left hand (a BoneAttachment socket), so
## lifting the arm raises the shield to cover the front, on top of whatever the body is doing
## (idle / walk / run / strafe). No dedicated block clip needed.
##
## The target rotations were SAMPLED from the old block_idle mocap, so the raise matches how the
## animator held the guard — procedural, but not hand-guessed angles.

const GUARD := {
	"LeftShoulder": Quaternion(-0.356893, -0.624305, -0.462787, 0.518361),
	"LeftUpperArm": Quaternion(0.163146, 0.975072, -0.063386, 0.136383),
	"LeftLowerArm": Quaternion(0.667421, -0.733193, 0.129470, 0.014621),
	"LeftHand": Quaternion(0.006776, 0.713555, -0.016328, 0.700376),
}

var amount := 0.0                      ## 0..1 guard blend, driven by the Block state

var _idx: Dictionary = {}              ## bone name -> index (resolved once)


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or amount <= 0.001:
		return
	if _idx.is_empty():
		for b in GUARD:
			_idx[b] = skel.find_bone(b)
	for b in GUARD:
		var i: int = _idx[b]
		if i < 0:
			continue
		var cur := skel.get_bone_pose_rotation(i)
		skel.set_bone_pose_rotation(i, cur.slerp(GUARD[b], amount))

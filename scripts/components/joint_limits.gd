class_name JointLimits
extends RefCounted
## THE ANATOMY TABLE — one source of truth for what every humanoid joint here may do, consumed
## by BOTH halves of the constraint story:
##   - tools/author_ragdoll.gd reads the RAGDOLL columns to author PhysicalBone3D joints
##     (inspector-tunable afterwards; the tool's values are only defaults), and
##   - the ogre's OgreLimitLayer reads the LIVE columns to clamp the procedural stack's output.
##
## The two column sets are DIFFERENT NUMBERS ON PURPOSE, and the difference is the design:
## a corpse should be nearly rigid through the trunk (a dead spine does not curl — the tight
## ragdoll cones are what stopped the folded-in-half corpse), while a fighter mid-swing
## legitimately carries its shoulder ~150 degrees from rest — live limits are HYPER-extension
## guards matching the Blender refinement pass's clamps (shoulders <=150, elbows <=135), not a
## posture police. A live budget of 0 means "not live-clamped": hips and legs belong to the
## foot IK's contact guarantee, hands to the grip solve — clamping either re-breaks things the
## refactor fixed.
##
## Bone names are SkeletonProfileHumanoid — every rig here retargets onto GeneralSkeleton, so
## the same table serves the swordsman (VRoid), the ogre (Mixamo) and whoever comes next.

## bone: [tip, ragdoll joint type, ragdoll params, live_swing_deg, live_twist_deg,
##        angular_damp, spring]
## ragdoll params: CONE = [swing_span, twist_span] · HINGE = [lower, upper] (both DEGREES —
## joint_constraints/* take degrees in this build, unlike joint_rotation's radians).
## angular_damp: the MUSCLE TONE dial — per-bone rotational damping (DAMP_MODE_REPLACE), the
## cheap half of "a body is not wet rope". Trunk stiff, limbs looser, extremities loosest.
## spring: [] = none; [equilibrium_deg, stiffness, damping] switches that HINGE to a 6DOF
## joint with an angular SPRING on the flexion axis — the engine's own spring-mass-damper,
## pulling the joint toward a slightly-bent natural angle so an elbow settles at muscle rest,
## never flopped flat. Signs follow the hinge signs (verified visually per rig).
const CHAIN := [
	["Hips", "Spine", PhysicalBone3D.JOINT_TYPE_NONE, [], 0.0, 0.0, 1.5, []],
	["Spine", "Chest", PhysicalBone3D.JOINT_TYPE_CONE, [10.0, 8.0], 30.0, 20.0, 1.5, []],
	["Chest", "UpperChest", PhysicalBone3D.JOINT_TYPE_CONE, [10.0, 8.0], 30.0, 20.0, 1.5, []],
	["UpperChest", "Neck", PhysicalBone3D.JOINT_TYPE_CONE, [10.0, 8.0], 30.0, 20.0, 1.5, []],
	["Neck", "Head", PhysicalBone3D.JOINT_TYPE_CONE, [15.0, 12.0], 40.0, 30.0, 1.2, []],
	["Head", "", PhysicalBone3D.JOINT_TYPE_CONE, [20.0, 15.0], 45.0, 35.0, 1.2, []],
	["LeftUpperArm", "LeftLowerArm", PhysicalBone3D.JOINT_TYPE_CONE, [70.0, 30.0], 150.0, 60.0, 0.8, []],
	["LeftLowerArm", "LeftHand", PhysicalBone3D.JOINT_TYPE_HINGE, [-5.0, 135.0], 135.0, 45.0, 0.8, [20.0, 45.0, 4.0]],
	["LeftHand", "", PhysicalBone3D.JOINT_TYPE_CONE, [25.0, 10.0], 0.0, 0.0, 0.6, []],
	["RightUpperArm", "RightLowerArm", PhysicalBone3D.JOINT_TYPE_CONE, [70.0, 30.0], 150.0, 60.0, 0.8, []],
	["RightLowerArm", "RightHand", PhysicalBone3D.JOINT_TYPE_HINGE, [-5.0, 135.0], 135.0, 45.0, 0.8, [20.0, 45.0, 4.0]],
	["RightHand", "", PhysicalBone3D.JOINT_TYPE_CONE, [25.0, 10.0], 0.0, 0.0, 0.6, []],
	["LeftUpperLeg", "LeftLowerLeg", PhysicalBone3D.JOINT_TYPE_CONE, [50.0, 20.0], 0.0, 0.0, 0.8, []],
	["LeftLowerLeg", "LeftFoot", PhysicalBone3D.JOINT_TYPE_HINGE, [-135.0, 5.0], 0.0, 0.0, 0.8, [-25.0, 45.0, 4.0]],
	["LeftFoot", "", PhysicalBone3D.JOINT_TYPE_CONE, [20.0, 10.0], 0.0, 0.0, 0.6, []],
	["RightUpperLeg", "RightLowerLeg", PhysicalBone3D.JOINT_TYPE_CONE, [50.0, 20.0], 0.0, 0.0, 0.8, []],
	["RightLowerLeg", "RightFoot", PhysicalBone3D.JOINT_TYPE_HINGE, [-135.0, 5.0], 0.0, 0.0, 0.8, [-25.0, 45.0, 4.0]],
	["RightFoot", "", PhysicalBone3D.JOINT_TYPE_CONE, [20.0, 10.0], 0.0, 0.0, 0.6, []],
]


## Clamp a bone's rotation RELATIVE TO REST to a swing/twist budget. Twist is the component
## about the bone's own long axis (local Y — the retarget's overwrite_axis points every bone's
## +Y at its child), swing is everything else; rel == swing * twist. Angles in degrees.
## Returns `rel` untouched when it is inside the budget, so a stack that never exceeds anatomy
## is bit-identical with the clamp in place — which is what keeps the curve-diff gate honest.
static func clamp_swing_twist(rel: Quaternion, swing_deg: float, twist_deg: float) -> Quaternion:
	rel = rel.normalized()
	var t := Quaternion(0.0, rel.y, 0.0, rel.w)
	t = t.normalized() if t.length_squared() > 0.000001 else Quaternion.IDENTITY
	var s := rel * t.inverse()
	var sa := 2.0 * acos(clampf(absf(s.w), 0.0, 1.0))
	var ta := 2.0 * acos(clampf(absf(t.w), 0.0, 1.0))
	var smax := deg_to_rad(swing_deg)
	var tmax := deg_to_rad(twist_deg)
	if sa <= smax and ta <= tmax:
		return rel
	# COMPLIANT, not a wall: tissue resists, it does not clang. Overshoot past the budget is
	# compressed asymptotically into a ~10 degree compliance zone — the first degree of
	# violation mostly passes, the tenth barely moves — so approaching a limit reads as muscle
	# taking the strain. C1-continuous at the boundary (slope 1 at zero overshoot), and
	# BIT-IDENTICAL at or below the budget, which is what lets the curve-diff gate keep
	# meaning: any deviation it shows is a frame that was genuinely beyond anatomy.
	var margin := deg_to_rad(10.0)
	if sa > smax and sa > 0.001:
		var give_s := smax + margin * (1.0 - exp(-(sa - smax) / margin))
		s = Quaternion.IDENTITY.slerp(s, give_s / sa)
	if ta > tmax and ta > 0.001:
		var give_t := tmax + margin * (1.0 - exp(-(ta - tmax) / margin))
		t = Quaternion.IDENTITY.slerp(t, give_t / ta)
	return (s * t).normalized()


## The live budgets, keyed by bone name — (swing, twist) in degrees, ZERO = leave the bone alone.
static func live_budget(bone: String) -> Vector2:
	for e in CHAIN:
		if String(e[0]) == bone:
			return Vector2(float(e[4]), float(e[5]))
	return Vector2.ZERO

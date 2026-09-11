class_name OgreFootIk
extends SkeletonModifier3D
## Puts the feet where the solver said they go, and keeps them there.
##
## THIS RUNS LAST, and the ordering is not arbitrary. Every layer before it moves the pelvis — the
## bob, the footfall settle, the lean, the idle sway. A leg solved BEFORE the pelvis moves breaks
## contact by exactly the pelvis's displacement, so the foot would slide by a few centimetres on
## every bob. The general rule, which makes the whole stack's order derivable instead of
## memorised:
##
##   Order layers by the strength of their guarantee.
##   Local-space embellishments first. World-space guarantees last, strongest last.
##
## A foot planted on the ground is the strongest guarantee in the system, so it gets the last word.
##
## WHAT IT DOES NOT DO. It does not decide where to step, when to step, or whether the ground is
## there — OgreSolver did all of that during the physics tick, with the raycasts, where a raycast is
## legal. This layer converts a world point into three bone rotations and stops.

var solver: OgreSolver

## Knee splay: how far outward the knees point, as a fraction of forward. Heavy bipeds are
## bow-legged because a wide pelvis makes the femurs clear it — and a knee that tracks straight
## ahead on a creature this wide reads as a person in a suit.
@export_range(0.0, 1.2, 0.01) var knee_splay := 0.35
## How strongly the ankle lies flat on the slope it landed on. Blended out during swing, because a
## foot in the air has no ground to conform to.
@export_range(0.0, 1.0, 0.01) var ankle_to_ground := 0.7

var _idx: Dictionary = {}
var _knee := [PI, PI]          ## last solved interior knee angle, read by the lab
var _solved := [Vector3.ZERO, Vector3.ZERO]   ## where the ankle ACTUALLY ended up, in world space
var _hip := [Vector3.ZERO, Vector3.ZERO]      ## the hip joint the solve started from, in world space
var _lift := [0.0, 0.0]                       ## how high the hip joint actually sits above the foot
var _foot_rest: Array[Basis] = []             ## the feet's rest orientation = this rig's "flat"


## The interior knee angles, in radians. The lab watches these because a leg at 0 degrees of bend is
## locked straight, which is the pop TwoBoneIk's soft clamp exists to prevent.
func knee_angles() -> Array:
	return _knee


## Where the ankle bone actually finished, in world space, sampled immediately after the solve.
##
## Recorded here rather than read from outside because a modifier's writes are only reliably visible
## DURING the modifier pass — a caller in _physics_process gets whatever the skeleton held before the
## pass and sees a foot that never moves. That is not a subtle discrepancy: it made the first skate
## measurement report exactly the body's speed at every gait, which looked like a catastrophic solver
## bug and was a catastrophic instrument bug.
##
## Note this is the RESULT, not the request. If the IK fails to reach its target this diverges from
## solver.feet[i].target, which is exactly what a skate test needs to be able to see.
func solved_world(i: int) -> Vector3:
	return _solved[i]


## The hip joint the solve started from, sampled in the same pass and for the same reason: read from
## outside, it reports the rest pose and makes the pelvis look like it never moves.
func hip_world(i: int) -> Vector3:
	return _hip[i]




## The hip joint's ACTUAL height above the foot it is solving to.
##
## This is the number the stride budget needs and the one no formula gets right: it is the crouch,
## plus the bob, plus the settle spring, plus the pelvis roll, plus the difference between the
## body's origin and the hip joint, all at once. Measuring it needs no model, cannot drift, and
## unlike an error integrator it cannot run away -- an earlier version fed accumulated over-reach
## back into the stride and ratcheted it to zero, with the cadence going to 14 Hz on the way.
func hip_lift(i: int) -> float:
	return _lift[i]


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or solver == null or not solver.is_ready():
		return
	if _idx.is_empty():
		for b in OgreSolver.BONES:
			_idx[b] = skel.find_bone(b)
		# The rest pose is this rig's definition of a flat foot. Captured once; see
		# TwoBoneIk.flatten for why naming an axis instead does not work.
		for n in ["LeftFoot", "RightFoot"]:
			var bi: int = _idx.get(n, -1)
			_foot_rest.append(Basis() if bi < 0 else skel.get_bone_global_rest(bi).basis)

	var to_skel := skel.global_transform.affine_inverse()
	var world_fwd := solver.forward()

	var sides := [
		{"up": "LeftUpperLeg", "low": "LeftLowerLeg", "foot": "LeftFoot"},
		{"up": "RightUpperLeg", "low": "RightLowerLeg", "foot": "RightFoot"},
	]
	for i in 2:
		var s: Dictionary = sides[i]
		var iu: int = _idx.get(s["up"], -1)
		var il: int = _idx.get(s["low"], -1)
		var ifo: int = _idx.get(s["foot"], -1)
		if iu < 0 or il < 0 or ifo < 0:
			continue
		var f = solver.feet[i]

		# The pole sits forward of the hip and out to the side, so the knee bends the way a knee
		# bends. Placed well clear of the limb — a pole too close to the leg's own axis is exactly
		# the degenerate case TwoBoneIk has to fall back out of.
		var hip_world: Vector3 = skel.global_transform * skel.get_bone_global_pose(iu).origin
		_hip[i] = hip_world
		# Splay OUTWARD, which is what solver.side_dir() is for -- see its comment for why
		# "outward" is not "+right" on this rig, and what it looks like when you get it backwards.
		var pole_world: Vector3 = hip_world \
				+ world_fwd * solver.max_reach \
				+ solver.side_dir(i) * (solver.max_reach * knee_splay)

		_lift[i] = hip_world.y - f.target.y
		_knee[i] = TwoBoneIk.solve(skel, iu, il, ifo,
				to_skel * f.target, to_skel * pole_world)
		_solved[i] = skel.global_transform * skel.get_bone_global_pose(ifo).origin

		# The ankle conforms to whatever it landed on, faded in with contact so a foot arriving on a
		# slope rolls onto it rather than snapping flat the instant it touches.
		var amount: float = ankle_to_ground * f.contact
		if amount > 0.001:
			var inv := skel.global_transform.basis.orthonormalized().inverse()
			var level: Vector3 = (inv * Vector3.UP).normalized()
			var n: Vector3 = (inv * (f.normal if f.grounded else Vector3.UP)).normalized()
			TwoBoneIk.flatten(skel, ifo, _foot_rest[i], level, n, amount)

class_name TwoBoneIk
extends RefCounted
## Analytic two-bone IK — hip, knee, ankle — solved in closed form by the law of cosines.
##
## PURE STATIC MATH, NO NODES beyond the skeleton it is handed. That is deliberate: it means
## probe_proc_anim.gd can hammer it with ten thousand random targets and no scene at all, which is
## the only practical way to catch the failure below.
##
## ENGINE STATUS (correct as of 4.6.3, was different when this file was written): Godot 4.6 ships
## `TwoBoneIK3D` — analytic and documented as always deterministic, so two of the three original
## reasons for this file are gone. The two that remain: (1) the scene-free testability above (an
## engine node cannot be hammered without a Skeleton3D in a tree), and (2) `rotate()`/`flatten()`
## below are used by every layer far beyond the leg solve, so this file cannot be deleted even if
## the solve itself is ever swapped. Any swap must first prove the engine node handles the ~98%
## extension singularity the way SOFT_REACH does — see the failure note below. `SkeletonIK3D`
## remains deprecated (it was iterative FABRIK; iteration can answer differently between frames
## for the same input, and a leg that solves slightly differently each frame shimmers).
##
## THE FAILURE THIS EXISTS TO AVOID. At exactly full extension the bend plane is undefined: the
## hip, knee and ankle are collinear, so the cross product that defines "which way the knee points"
## collapses to a zero vector and the normalisation produces garbage. The knee snaps 180 degrees
## for a single frame, which reads as a violent pop. Clamping the target JUST SHORT of full
## extension (`SOFT_REACH`) keeps the solution continuous through the whole range — there is no
## discontinuity to hit, rather than one that is merely unlikely.
##
## This matters more for the ogre than it would for a person: its rest pose already stands at ~98%
## leg extension, so it lives right up against the singularity rather than safely away from it.

## Fraction of full reach the solver will extend to. Below 1.0 by enough that the knee always keeps
## a definite bend direction; close enough to 1.0 that the leg still looks straight when striding.
const SOFT_REACH := 0.98
const EPS := 0.0001


## Solve the chain so `tip` lands on `target`, with the middle joint bending toward `pole`.
## Everything is in SKELETON space (what get_bone_global_pose returns), not world space — the
## caller converts, once, rather than this converting per bone.
##
## Returns the knee's interior angle in radians, which the lab reads to prove the joint never locks.
static func solve(skel: Skeleton3D, i_up: int, i_low: int, i_tip: int,
		target: Vector3, pole: Vector3) -> float:
	if skel == null or i_up < 0 or i_low < 0 or i_tip < 0:
		return PI

	var a: Vector3 = skel.get_bone_global_pose(i_up).origin
	var b: Vector3 = skel.get_bone_global_pose(i_low).origin
	var c: Vector3 = skel.get_bone_global_pose(i_tip).origin

	# Segment lengths are read from the CURRENT pose rather than cached from rest. Self-calibrating:
	# no constant to keep in step with the rig, and it survives a reimport at another scale.
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < EPS or l2 < EPS:
		return PI

	var to_target := target - a
	var dist := to_target.length()
	if dist < EPS:
		return PI
	var dir := to_target / dist
	# Clamped at BOTH ends: too far collapses the bend plane (see the header), too near folds the
	# limb through itself, which flips the knee inside out.
	var d := clampf(dist, absf(l1 - l2) + EPS, (l1 + l2) * SOFT_REACH)

	# The bend plane's normal. Prefer the pole; if the pole happens to lie along the limb, fall back
	# to the plane the limb is already in, and only then to an arbitrary perpendicular. Each fallback
	# is a real case: a knee pointing exactly at the target is what happens on a dead-straight leg.
	var n := dir.cross(pole - a)
	if n.length_squared() < EPS:
		n = dir.cross(b - a)
	if n.length_squared() < EPS:
		n = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP)
	n = n.normalized()

	# Law of cosines. `alpha` is the angle between the thigh and the hip->target line; `knee` is the
	# interior angle at the joint, which is what gets reported back.
	var alpha := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var knee := acos(clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0))

	var b_new := a + (Quaternion(n, alpha) * dir) * l1
	var c_new := a + dir * d

	# Write the UPPER bone by the rotation that carries its current direction onto the solved one.
	# Rotating what is there, rather than composing an absolute basis, keeps the bone's twist about
	# its own axis — which is where the ogre's authored hunch lives, and would otherwise be erased.
	_aim(skel, i_up, b - a, b_new - a)
	# The parent moved, so the child's global pose has to be re-read before aiming it. Reusing the
	# stale `c` here is the classic bug: the shin ends up solved against the pre-rotation thigh.
	var b2: Vector3 = skel.get_bone_global_pose(i_low).origin
	var c2: Vector3 = skel.get_bone_global_pose(i_tip).origin
	_aim(skel, i_low, c2 - b2, c_new - b_new)
	return knee


## Apply a rotation expressed in SKELETON space to one bone, and let its children follow.
##
## THE TRAP THIS EXISTS TO AVOID, which cost a whole pass of "the poses look weak": the obvious
## version reads the bone's global pose, multiplies the basis, and writes it back with the origin
## unchanged. That looks harmless and is not. `set_bone_global_pose` writes a LOCAL transform
## computed against the parent, so pinning each bone's global origin in turn re-pins every child to
## where it was BEFORE its parent rotated. Rotate a shoulder by 158 degrees that way and the elbow
## stays exactly where it started -- the arm visibly moves about half as far as it was told to, and
## no amount of increasing the angle fixes it because the cancellation scales too.
##
## Writing the LOCAL rotation instead leaves the positions to the hierarchy, which is whose job it
## is. Nothing is pinned and children go where their parents take them.
static func rotate(skel: Skeleton3D, idx: int, q: Quaternion) -> void:
	if idx < 0:
		return
	var cur := skel.get_bone_global_pose(idx).basis.get_rotation_quaternion()
	var want := (q * cur).normalized()
	var parent := skel.get_bone_parent(idx)
	if parent >= 0:
		var pg := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion()
		want = (pg.inverse() * want).normalized()
	skel.set_bone_pose_rotation(idx, want)


## Rotate one bone so `from` points along `to`, leaving its position and its roll alone.
static func _aim(skel: Skeleton3D, idx: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < EPS or to.length_squared() < EPS:
		return
	rotate(skel, idx, Quaternion(from.normalized(), to.normalized()))


## Lay a foot flat on the ground it landed on.
##
## DO NOT DO THIS BY NAMING AN AXIS. The obvious version rotates the bone's local +Y onto the ground
## normal, which assumes the foot bone's own up axis is up. On this rig it is not — Mixamo bones
## point along their child, and the retarget's `overwrite_axis` rewrites them again — so that
## version stood the ogre on its toes and floated the whole body half a metre off the floor.
##
## The rest pose already contains the answer: the character was authored standing flat on level
## ground, so the foot's REST basis IS "flat, facing forward" for this rig, whatever its axes happen
## to be. All that is needed is to take that basis and tilt it by the rotation from level to the
## actual ground normal. No axis is named and nothing has to be true about the rig's conventions.
##
## `rest_basis` and both directions are in SKELETON space; `amount` blends it in with contact.
static func flatten(skel: Skeleton3D, idx: int, rest_basis: Basis,
		level: Vector3, normal: Vector3, amount: float) -> void:
	if amount <= 0.001:
		return
	var g := skel.get_bone_global_pose(idx)
	var tilt := Quaternion(level.normalized(), normal.normalized()) if normal.length_squared() > EPS 			else Quaternion.IDENTITY
	var want := (tilt * rest_basis.get_rotation_quaternion()).normalized()
	var cur := g.basis.get_rotation_quaternion().normalized()
	g.basis = Basis(cur.slerp(want, clampf(amount, 0.0, 1.0)))
	skel.set_bone_global_pose(idx, g)

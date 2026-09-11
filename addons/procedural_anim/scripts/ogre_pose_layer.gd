class_name OgrePoseLayer
extends SkeletonModifier3D
## Blends the active key poses onto the rest pose. Runs FIRST in the stack, so everything after it —
## gait, foot IK, the arms holding the mace — reads a body that is already doing what the action
## asked for.
##
## THE ARM GUARD, GENERALISED. `scripts/arm_guard.gd` slerps four bones toward one hard-coded shield
## pose by an `amount` set from outside. This is that with N named poses, weights per pose, and the
## angles living in a Resource instead of the file. The contract is identical: read state, cache the
## indices once, write bone poses, integrate nothing.
##
## ANGLES ARE BODY-RELATIVE, NOT LOCAL. Each pose entry is (pitch, yaw, roll) degrees about the
## ogre's own right / up / forward axes, composed onto the bone's current global pose. That is the
## same construction the gait layer uses, and for the same reason: a local Euler triple is a guess
## about which of a bone's axes is which, and this project has already paid for that guess once (see
## TwoBoneIk.flatten). A body-relative angle is readable and cannot be wrong about the rig.

var solver: OgreSolver

var _idx: Dictionary = {}


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or solver == null or not solver.is_ready():
		return
	var active: Dictionary = solver.pose_weights
	if active.is_empty():
		return
	if _idx.is_empty():
		for b in OgreSolver.BONES:
			_idx[b] = skel.find_bone(b)

	var inv := skel.global_transform.basis.orthonormalized().inverse()
	var up := (inv * Vector3.UP).normalized()
	var fwd := (inv * solver.forward()).normalized()
	var right := (inv * solver.right()).normalized()

	# Sum the poses per bone before touching the skeleton. Applying them one pose at a time would
	# make the result depend on dictionary order, and two half-weighted poses would compose into
	# something neither of them describes.
	var blend: Dictionary = {}
	for name_ in active:
		var w: float = active[name_]
		if w <= 0.001:
			continue
		var bones: Dictionary = solver.poses.bones_of(name_)
		for b in bones:
			var a: Vector3 = bones[b]
			blend[b] = blend.get(b, Vector3.ZERO) + a * w

	# Parents before children: a child's local rotation is computed against its parent's CURRENT
	# global pose, so the parent has to have moved first or the child compensates for a rotation
	# that has not happened yet.
	var order := OgreSolver.BONES.filter(func(b): return blend.has(b))
	for b in order:
		var i: int = _idx.get(b, -1)
		if i < 0:
			continue
		# WHERE THE CLIP OWNS A BONE, THE POSE LETS GO. Both are intent, and on a bone the clip
		# drives it is the better intent -- it carries the arc. Applying both instead ADDS them: the
		# clip's forward fold plus the pose's forward fold doubled the spine over until the ogre was
		# bent to the floor. The gait layer already backs off the same way, for the same reason.
		var free := 1.0 - (solver.clip_layer.influence(b) if solver.clip_layer else 0.0)
		if free <= 0.001:
			continue
		var a: Vector3 = blend[b] * free
		var q := Quaternion(right, deg_to_rad(a.x)) \
				* Quaternion(up, deg_to_rad(a.y)) \
				* Quaternion(fwd, deg_to_rad(a.z))
		# Local rotation, not a global pose write -- see TwoBoneIk.rotate for why the obvious
		# version silently halves every angle by re-pinning the children.
		TwoBoneIk.rotate(skel, i, q)

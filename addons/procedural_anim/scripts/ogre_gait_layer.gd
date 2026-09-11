class_name OgreGaitLayer
extends SkeletonModifier3D
## The body above the knees: pelvis bob, list and yaw, the spine's lagged counter-rotation, the
## lean, the level head, and the arm swing.
##
## A DUMB WRITER. It integrates nothing and queries nothing — every number it uses was computed by
## OgreSolver during the physics tick. See that file's header for why the split is hard rather than
## stylistic. This is `scripts/arm_guard.gd` with more bones and the same contract: read a value
## from outside, cache the bone indices once, write poses.
##
## WHY GLOBAL-POSE ROTATIONS AND NOT LOCAL EULERS. Every rotation here is a physical statement about
## the world — "lean forward", "twist about the vertical", "swing the arm along the direction of
## travel". Expressed as local Euler angles those become per-bone guesses about which axis happens
## to be which on this particular rig, and the answer changes with the import's `overwrite_axis`
## setting. Building the delta in skeleton space and composing it onto the bone's current global
## pose is the same code for every bone and cannot be wrong about an axis.
##
## COMPOSE, NEVER ACCUMULATE. Each write is `Basis(delta) * current`, where `current` is re-read
## from the skeleton. Skeleton3D restores bone poses around the modifier pass, so `current` starts
## at the rest pose (or at whatever an earlier layer left), and layering happens by reading what the
## previous layer wrote. A `+=` here would drift within a single frame and give a different result
## at a different framerate.

## How the forward lean is shared down the spine. It sums to 1.0: the total is the physically
## correct atan(a/g), and this only decides where the bend happens. Weighting the middle heavily is
## what makes it read as a torso leaning rather than a plank tipping at the hips.
const LEAN_SHARE := {
	"Hips": 0.20, "Spine": 0.30, "Chest": 0.30, "UpperChest": 0.20,
}

var solver: OgreSolver

var _idx: Dictionary = {}


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or solver == null or not solver.is_ready():
		return
	if _idx.is_empty():
		for b in OgreSolver.BONES:
			_idx[b] = skel.find_bone(b)

	# The body's frame, expressed in skeleton space. Everything below is built out of these three
	# axes, so the layer never has to know how the model node is oriented.
	# ORTHONORMALISED, because this basis is used to carry DIRECTIONS and the hips OFFSET, and
	# Basis.inverse() is not transposed(): any scale on the chain comes back as 1/s and shears what
	# it touches. Nothing scales the ogre in normal play, but the death tween squashes Visuals to
	# 0.08 in Y, which would push the pelvis write below through a 12.5x stretch. On a pure rotation
	# this is a no-op. The world->skeleton POSITION conversions keep their scale and stay affine.
	var inv := skel.global_transform.basis.orthonormalized().inverse()
	var up := (inv * Vector3.UP).normalized()
	var fwd := (inv * solver.forward()).normalized()
	var right := (inv * solver.right()).normalized()

	_pelvis(skel, inv, up, fwd, right)
	_spine(skel, up, right, fwd)
	_arms(skel, right)


## The pelvis carries the whole body, so it is the only bone that gets a POSITION as well as a
## rotation: the bob, the footfall settle and the idle sway are all displacements of the hips, and
## everything above inherits them for free.
func _pelvis(skel: Skeleton3D, inv: Basis, up: Vector3, fwd: Vector3, right: Vector3) -> void:
	var i: int = _idx.get("Hips", -1)
	if i < 0:
		return
	var q := Quaternion(up, solver.hips_yaw) * Quaternion(fwd, solver.hips_roll)
	TwoBoneIk.rotate(skel, i, q)
	# The pelvis is the one bone that genuinely moves, so it is the one bone whose POSITION is
	# written -- and being the root of the chain, nothing above it can be re-pinned by doing so.
	# hips_offset is in the body's own frame (x sideways, y up), so it goes through the same
	# body-to-skeleton rotation as the axes above rather than being added raw.
	var world_off := Basis(Vector3.UP, solver.facing) * solver.hips_offset
	skel.set_bone_pose_position(i, skel.get_bone_rest(i).origin + inv * world_off)
	_lean_bone(skel, "Hips", right, fwd)


## Lean, shared down the chain, then cancelled again at the neck.
func _spine(skel: Skeleton3D, up: Vector3, right: Vector3, fwd: Vector3) -> void:
	for b in ["Spine", "Chest", "UpperChest"]:
		_lean_bone(skel, b, right, fwd)
	# The chest's counter-rotation to the pelvis, arriving a beat late. Split across two joints so
	# the twist is distributed instead of kinking at one vertebra.
	for b in ["Spine", "Chest"]:
		var i: int = _idx.get(b, -1)
		if i < 0:
			continue
		TwoBoneIk.rotate(skel, i, Quaternion(up, solver.spine_yaw * 0.5))

	# VESTIBULAR STABILISATION. Animals hold their heads level; the neck spends the whole day
	# undoing what the body does. A body that leans under a head that does not is alive, and a model
	# that rotates as one rigid block is a prop. This one line is most of that difference.
	var cancel := -solver.tuning.head_stabilise
	for b in ["Neck", "Head"]:
		var i: int = _idx.get(b, -1)
		if i < 0:
			continue
		var g := skel.get_bone_global_pose(i)
		var q := Quaternion(right, solver.lean_pitch * cancel * 0.5) \
				* Quaternion(fwd, solver.lean_roll * cancel * 0.5)
		g.basis = Basis(q) * g.basis
		skel.set_bone_global_pose(i, g)


func _lean_bone(skel: Skeleton3D, name_: String, right: Vector3, fwd: Vector3) -> void:
	var share: float = LEAN_SHARE.get(name_, 0.0) * (1.0 - solver.pose_influence(name_))
	if share <= 0.001:
		return
	var i: int = _idx.get(name_, -1)
	if i < 0:
		return
	TwoBoneIk.rotate(skel, i, Quaternion(right, solver.lean_pitch * share)
			* Quaternion(fwd, solver.lean_roll * share))


## Arms swing about the body's lateral axis, contralateral to the legs. The elbow droops a little
## more the faster it goes: long heavy arms trail and fold rather than staying straight.
func _arms(skel: Skeleton3D, right: Vector3) -> void:
	var pairs := [["LeftUpperArm", "LeftLowerArm", 0], ["RightUpperArm", "RightLowerArm", 1]]
	for p in pairs:
		# Wherever a pose owns the arm, the walk cycle lets go of it. Without this the ogre swings a
		# mace overhead and walks its arms at the same time, and the two just cancel into mush.
		var free: float = 1.0 - solver.pose_influence(p[0])
		# And wherever the arm is holding the WEAPON, the walk cycle lets go of it too. Same rule,
		# different owner: an arm carrying four metres of iron does not swing like an empty one, and
		# swinging it moves the shoulder out from under the grip the IK is trying to keep.
		free *= 1.0 - solver.hold_influence(p[0]) * solver.tuning.arm_hold_calm
		if free <= 0.001:
			continue
		var iu: int = _idx.get(p[0], -1)
		if iu >= 0:
			TwoBoneIk.rotate(skel, iu, Quaternion(right, solver.arm_swing[p[2]] * free))
		var il: int = _idx.get(p[1], -1)
		if il >= 0:
			TwoBoneIk.rotate(skel, il, Quaternion(right, -absf(solver.arm_swing[p[2]]) * 0.5 * free))

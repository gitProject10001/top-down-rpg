class_name OgreClipLayer
extends SkeletonModifier3D
## Plays an authored animation clip over the procedural body — masked, weighted, and only where a
## clip is better than a solver.
##
## WHY BOTH. The two are good at opposite things, and pretending either can do the whole job is how
## you get a stiff creature or a floating one:
##
##   A CLIP is good at INTENT. The arc of a two-handed overhead swing — where the weight shifts,
##   when the shoulders rotate ahead of the arms, how the follow-through hangs — is a performance.
##   Deriving that from physics gets you something that moves correctly and means nothing.
##
##   THE SOLVER is good at CONTACT AND CONTEXT. A clip cannot know where the ground is, how fast the
##   creature is travelling, which way it turned last frame, or that it is standing on a slope. Play
##   one on a moving character and the feet skate, because the clip was authored for a treadmill.
##
## So the clip takes the upper body and the solver keeps everything that touches the world. The mask
## is the whole design: `UPPER_BODY` is the list of bones a performance owns, and everything absent
## from it — legs, feet, the pelvis's height — stays with the gait, the foot IK and the reach budget
## that were built to hold them.
##
## THE LEGS ARE NOT IN THE MASK EVEN THOUGH THE CLIP ANIMATES THEM. Mixamo's clip has perfectly good
## leg keys, and using them would undo every guarantee the foot IK makes: no plant locking, no
## ground adaptation, no crouch solved from reach. The feet would skate, on a creature whose whole
## read is weight. The clip's legs are simply ignored.
##
## AND THE DYNAMICS LAYER STILL RUNS ON TOP. The clip sets a target like any other layer, and the
## springs above it make the chest arrive late and overshoot — so the same authored swing carries
## inertia it was never keyed with, and reads heavier than it does in Mixamo's preview.

## Bones this layer WRITES. Hips is included: the pelvis twist is half of what makes a two-handed
## swing read, and leaving it out was the mistake that produced a torso swinging over a lower body
## that had no idea an attack was happening.
##
## The LEGS are still absent, and that is not the same mistake repeated. They are not ignored either
## -- see foot_offset(), which reads the clip's leg keys through forward kinematics and hands the
## result to the foot IK as a TARGET. The clip says where the feet should go; the solver still
## decides where they can actually be, which is the only way plant locking and ground adaptation
## survive contact with an animation authored on a flat treadmill.
const UPPER_BODY: Array[String] = [
	"Hips",
	"Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
]

## The leg chains, from the pelvis down. Read by forward kinematics, never written.
const LEGS: Array = [
	["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"],
	["RightUpperLeg", "RightLowerLeg", "RightFoot"],
]

## Which mix group each bone answers to. The groups are the parts of a body worth arguing about
## separately -- see OgreTuning's "Animation mix" for what each dial means and why this mask is
## hand-built rather than taken from the engine.
const GROUP := {
	"Hips": "pelvis",
	"Spine": "spine", "Chest": "spine", "UpperChest": "spine",
	"Neck": "head", "Head": "head",
	"LeftShoulder": "arms", "LeftUpperArm": "arms", "LeftLowerArm": "arms", "LeftHand": "arms",
	"RightShoulder": "arms", "RightUpperArm": "arms", "RightLowerArm": "arms", "RightHand": "arms",
}

var solver: OgreSolver

## The clip being played, the point in it, and how much of it to apply. All three are driven by the
## solver's action runner; nothing here decides anything.
var clip: Animation
var time := 0.0
var weight := 0.0
## DIAGNOSTIC ONLY. Drive the entire skeleton from the clip at full strength -- every bone it has a
## track for, legs and pelvis included, masks and mix dials bypassed. With the other layers switched
## off this shows the imported animation ON ITS OWN, which is the only way to tell a bad retarget
## apart from a bad blend. See the lab's --demo=pureclip.
var raw := false

## Resolved once per clip: [animation track index, skeleton bone index] for the masked rotation
## tracks only. A clip carries tracks for bones this rig does not have and for bones the mask does
## not want, and looking those up every frame forever is a cost with no result.
var _tracks: Array = []
var _for: Animation

## Rotation track index by bone name, for EVERY bone the clip animates -- including the ones this
## layer does not write. The leg FK needs to read keys it must not apply.
var _rot: Dictionary = {}
## Bone rest transforms for the pelvis and both leg chains, cached at resolve. Rests are
## parent-relative, which is exactly what composing a chain wants.
var _rest: Dictionary = {}
## The clip's Hips position track, and the rig's neutral pelvis, so the track can be reported as a
## DEVIATION rather than an absolute position.
var _hips_pos_track := -1
## The clip's OWN neutral pelvis: the value of its position track on frame one.
var _hips_zero := Vector3.ZERO
## Skeleton bone index by name, for the pelvis and both leg chains.
var _bone: Dictionary = {}
## Ankle position relative to the pelvis, in skeleton space, as the clip wants it. Captured each
## pass by _capture_feet().
var _foot := [Vector3.ZERO, Vector3.ZERO]


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or clip == null or weight <= 0.001:
		return
	if _for != clip:
		_resolve(skel)

	if raw:
		_drive_all(skel)
		return

	for t in _tracks:
		var ti: int = t[0]
		var bi: int = t[1]
		var share: float = clip_share(t[2])
		if share <= 0.001:
			continue
		var want: Quaternion = clip.rotation_track_interpolate(ti, time)
		# clip_yaw is an IMPORT correction (Mixamo's clip faces the wrong way on this model). A
		# baked clip was sampled off this very skeleton and already faces where the rig faces --
		# yawing it flipped the pelvis a half turn and the whole performance with it.
		if t[2] == "Hips" and not (solver != null and solver.clip_authored()):
			want = _yaw() * want
		# Blended against whatever the layers below left, not written over it. At share 1 the clip
		# wins outright; between 0 and 1 it is genuinely mixed with the procedural pose, which is
		# what makes a clip fade in over a wind-up instead of snapping on -- and now also what lets
		# the arms come from the animation while the head keeps looking where the solver wants.
		skel.set_bone_pose_rotation(bi, skel.get_bone_pose_rotation(bi).slerp(want, share))

	_capture_feet(skel)


## Pose the legs from the clip and read back where the ankles land, as an offset from the pelvis.
##
## The write is deliberate and temporary: the foot IK solves all three leg bones later in the same
## pass, so what is left here never reaches the screen. What survives is the MEASUREMENT -- the
## stance the animator authored, in this rig's own terms, for the solver to reconcile against the
## ground it can actually see.
## Every track the clip has, applied outright. The pelvis gets its POSITION too, because without it
## the animation is judged with its weight shift removed -- which is exactly the thing being looked
## for. Diagnostic path; nothing in the game reaches it.
func _drive_all(skel: Skeleton3D) -> void:
	for bone_name in _rot:
		var bi := skel.find_bone(String(bone_name))
		if bi >= 0:
			var q: Quaternion = clip.rotation_track_interpolate(int(_rot[bone_name]), time)
			skel.set_bone_pose_rotation(bi, (_yaw() * q) if bone_name == "Hips" else q)
	var ih: int = _bone.get("Hips", -1)
	if ih >= 0 and _hips_pos_track >= 0:
		skel.set_bone_pose_position(ih, skel.get_bone_rest(ih).origin + _yaw()
				* (clip.position_track_interpolate(_hips_pos_track, time) - _hips_zero))


func _capture_feet(skel: Skeleton3D) -> void:
	var ih: int = _bone.get("Hips", -1)
	if ih < 0:
		return
	for side in LEGS.size():
		for b in LEGS[side]:
			var bi: int = _bone.get(b, -1)
			if bi >= 0 and _rot.has(b):
				skel.set_bone_pose_rotation(bi, clip.rotation_track_interpolate(int(_rot[b]), time))
	var hips: Vector3 = skel.get_bone_global_pose(ih).origin
	for side in LEGS.size():
		var bi: int = _bone.get(LEGS[side][2], -1)
		_foot[side] = Vector3.ZERO if bi < 0 else skel.get_bone_global_pose(bi).origin - hips


func _resolve(skel: Skeleton3D) -> void:
	_for = clip
	_tracks.clear()
	_rot.clear()
	_rest.clear()
	_hips_pos_track = -1
	var mask := {}
	for b in UPPER_BODY:
		mask[b] = true
	for i in clip.get_track_count():
		var path := str(clip.track_get_path(i))
		var bone := path.get_slice(":", 1) if ":" in path else ""
		if clip.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if bone == "Hips":
				_hips_pos_track = i
			continue
		if clip.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		_rot[bone] = i
		if not mask.has(bone):
			continue
		var bi := skel.find_bone(bone)
		if bi >= 0:
			_tracks.append([i, bi, bone])

	# Rests for everything the FK walks.
	var need := ["Hips"]
	for chain in LEGS:
		for b in chain:
			need.append(b)
	for b in need:
		var bi := skel.find_bone(b)
		if bi >= 0:
			_rest[b] = skel.get_bone_rest(bi)
			_bone[b] = bi
	_hips_zero = Vector3.ZERO if _hips_pos_track < 0 			else clip.position_track_interpolate(_hips_pos_track, 0.0)


## The clip's facing correction, about the rig's own up axis. Applied to the Hips alone -- it is the
## root of the chain, so turning it turns the whole performance, and every bone below inherits it
## without needing to know. See OgreTuning.clip_yaw for why this is 180 on this model.
func _yaw() -> Quaternion:
	if solver == null or solver.tuning == null:
		return Quaternion.IDENTITY
	return Quaternion(Vector3.UP, deg_to_rad(solver.tuning.clip_yaw))


## The clip's rotation for one bone at the current time, or its rest rotation if the clip has no
## opinion about it.
func _rot_of(bone: String) -> Quaternion:
	if _rot.has(bone):
		return clip.rotation_track_interpolate(int(_rot[bone]), time)
	var r: Transform3D = _rest.get(bone, Transform3D.IDENTITY)
	return r.basis.get_rotation_quaternion()


## How far the clip wants the PELVIS displaced from ITS OWN neutral, in skeleton space.
##
## This is the weight shift -- loading back into the wind-up, driving down through contact. The body
## layer ADDS it rather than being replaced by it, so the gait's own bob and the reach budget's
## crouch still apply and the pelvis cannot be pushed somewhere the legs cannot follow.
##
## MEASURED AGAINST THE CLIP'S FIRST FRAME, not against the rig's rest pose. Those are not the same
## zero: this model's skeleton sits about 2 m off its own origin in Z, so differencing against the
## rest turned 14 cm of genuine weight shift into a 2.12 m constant with the shift buried inside it.
## A clip's neutral is wherever the clip starts, and that is the only reference that means anything.
func hips_offset() -> Vector3:
	if clip == null or _hips_pos_track < 0 or weight <= 0.001:
		return Vector3.ZERO
	return _yaw() * (clip.position_track_interpolate(_hips_pos_track, time) - _hips_zero) * weight


## Where the clip wants one ankle, RELATIVE TO THE PELVIS, in skeleton space.
##
## CAPTURED FROM THE SKELETON, NOT COMPUTED. The first version walked the chain by hand --
## rest offset times keyed rotation, pelvis down to ankle -- and it was wrong: it put the feet a
## metre apart fore-and-aft and only 1.2 m below a pelvis they sit 2 m under. The clip is retargeted
## through a bone map onto a rig whose rest pose is a hunch rather than a T, and reproducing what
## that does to a chain by hand means reimplementing the engine's own skinning conventions and
## getting every one of them right. So the legs are posed onto the skeleton and the answer is read
## back from it. The foot IK re-solves those bones a moment later, so the write is scratch space.
##
## RELATIVE TO THE PELVIS ON PURPOSE. An absolute position would be measured against a pelvis the
## clip believes in and the solver has since moved -- the dynamics layer displaces it every frame,
## and the reach budget lowers it further. As an offset it re-anchors to wherever the pelvis
## actually ended up, so the stance the animator authored survives a body doing its own thing
## underneath.
func foot_offset(side: int) -> Vector3:
	if side < 0 or side >= _foot.size():
		return Vector3.ZERO
	return _foot[side]


## How much of one bone the clip is entitled to right now: the action's own fade-in envelope, times
## whatever its group's mix dial leaves the animation.
##
## THIS IS THE ONE FUNCTION THE WHOLE MIX HANGS OFF. OgrePoseLayer already backs off by it and
## OgreGaitLayer already backs off by solver.pose_influence(), which folds it in -- so making this
## per-group made both of them per-group without either file changing. Two systems writing the same
## shoulder do not average into something better; they cancel into mush, and this is what stops it.
func clip_share(bone: String) -> float:
	if clip == null or weight <= 0.001 or not GROUP.has(bone):
		return 0.0
	# AN AUTHORED CLIP OWNS ITS BONES OUTRIGHT — the dials sit out. The dials exist to blend a
	# BORROWED clip against the procedural body; an action's own clip (baked from the solver, or
	# refined from that bake) already CONTAINS the procedural body's contribution, recorded, so
	# blending it against the live layers again would count the pose twice — the playback would
	# land at share-squared of what was recorded, and the diff would read it as the ogre going
	# soft in exactly the groups the dials left partial.
	if solver != null and solver.clip_authored():
		return weight
	return weight * (1.0 - _mix(String(GROUP[bone])))


## The dial-complement for one group: how much of that part the clip KEEPS after its mix dial.
## THIS IS THE ONLY DOOR TO THE mix_* DIALS. The solver used to read mix_legs, mix_weapon and a
## second copy of mix_pelvis straight off the tuning resource — three authorities for "who owns
## this part of the body", on two different clocks, and any change to the mask had to be chased
## through two files. Every consumer now resolves through _mix() below, in this one file.
func share_of(group: String) -> float:
	# (For AUTHORED clips only the PELVIS echo is skipped in _step_clip_stance — the feet half
	# still reconciles, and it bypasses this dial entirely: an authored stance is the clip's
	# outright, ground-disposed. This dial therefore only ever scales a BORROWED clip's legs/
	# pelvis against the live layers. The weapon read stays live for both: the weapon rides the
	# fist, and the fist is the clip's. An earlier version of this comment claimed an early
	# return that never existed — the 30% stance squeeze it hid is fixed at the caller.)
	return 1.0 - _mix(group)


## The dial for one group. A match rather than a dictionary because each one has to be its own
## @export_range for the lab's panel to build a slider for it. `legs` and `weapon` are not bone
## groups (the legs are FK scratch, the weapon is not a bone) but their dials live here with the
## rest so the mask has one home.
func _mix(group: String) -> float:
	if solver == null or solver.tuning == null:
		return 0.0
	match group:
		"head": return solver.tuning.mix_head
		"spine": return solver.tuning.mix_spine
		"arms": return solver.tuning.mix_arms
		"pelvis": return solver.tuning.mix_pelvis
		"legs": return solver.tuning.mix_legs
		"weapon": return solver.tuning.mix_weapon
		_: return 0.0


## Which bones this clip is currently driving, and how hard. Kept as the name the other layers ask
## by; it is the same number as clip_share().
func influence(bone: String) -> float:
	return clip_share(bone)

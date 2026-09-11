class_name OgreDynamicsLayer
extends SkeletonModifier3D
## INERTIA FOR EVERYTHING ABOVE THE PELVIS. This is the layer that was missing, and its absence was
## the honest criticism of the whole system: the legs were genuinely procedural — gait law, plant
## and swing, IK, a crouch solved from reach — while the shoulders, elbows, torso and head were
## static angles with a plain ease between them. That is a keyframe with extra steps, and it reads
## like one.
##
## WHAT IT DOES. Every bone it owns gets a rotational spring. The pose and gait layers below write a
## TARGET; this layer never reaches that target directly. It accelerates toward it, arrives late,
## and goes past. So:
##
##   - The chest lags the hips through a turn and catches up afterwards.
##   - A slam's wind-up drags the shoulders a beat behind the spine, and the strike whips them
##     through and overshoots before settling.
##   - The head is thrown around by everything the body does, and steadies itself last.
##   - Blending between two poses stops being a straight interpolation and becomes a body being
##     moved by forces, which is the entire difference between the two.
##
## None of that needs the poses to change. It is applied to whatever the layers below produced, so
## it improves every action at once and any action added later for free.
##
## WHY A GENERIC FILTER RATHER THAN HAND-ANIMATED SECONDARY MOTION. Because the input is already
## unpredictable — the pose blend, the gait, the lean and the footfall settle all move these bones,
## and they interact. Anything hand-authored would have to anticipate the combination. A spring does
## not care what moved the target; it responds to the fact that it moved.
##
## HEAVIER MEANS SLOWER, and the per-bone frequencies below are that statement: the chest is the
## heaviest thing here and the slowest to respond; the head is light and quick but hangs off the end
## of a chain of slow things, so it ends up whipping. Carrying the mace slows the arms further —
## a four-metre lump of iron has its own opinion about how fast a shoulder can change direction.

## Per bone: how fast it responds (rad/s) and how much it overshoots (damping ratio, below 1).
## These ARE the mass model. A bone with a low frequency and light damping is heavy and floppy; a
## high frequency with heavy damping is light and stiff.
const TUNE := {
	"Spine":         {"w": 15.0, "z": 0.55},
	"Chest":         {"w": 13.0, "z": 0.50},
	"UpperChest":    {"w": 12.0, "z": 0.50},
	"Neck":          {"w": 19.0, "z": 0.55},
	"Head":          {"w": 21.0, "z": 0.60},
	"LeftShoulder":  {"w": 14.0, "z": 0.52},
	"RightShoulder": {"w": 14.0, "z": 0.52},
	"LeftUpperArm":  {"w": 11.0, "z": 0.45},
	"RightUpperArm": {"w": 11.0, "z": 0.45},
	"LeftLowerArm":  {"w": 13.0, "z": 0.50},
	"RightLowerArm": {"w": 13.0, "z": 0.50},
}

const SAFE_STEP := 0.20
const MAX_SUB := 6

var solver: OgreSolver

var _idx: Dictionary = {}
var _state: Dictionary = {}      ## bone index -> Quaternion, where the spring actually is
var _vel: Dictionary = {}        ## bone index -> Vector3, angular velocity as a rotation vector
var _lag := 0.0                  ## worst degrees between where a bone was asked to be and where it is


## How far the upper body is currently BEHIND what the pose and gait layers asked for, in degrees.
##
## This is the layer's output made legible. Inertia is invisible in a still frame -- a photograph of
## a lagging shoulder looks exactly like a photograph of a shoulder in the wrong place -- so the
## number is what tells you it is working. Zero while standing; it spikes hard on the frame a strike
## fires and bleeds off over the follow-through. If it stays at zero during a slam, this layer is
## doing nothing and the upper body is back to being posed rather than moved.
func lag_degrees() -> float:
	return _lag


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or solver == null or not solver.is_ready():
		return
	if _idx.is_empty():
		for b in TUNE:
			_idx[b] = skel.find_bone(b)

	# The engine's own delta -- 4.6 deprecated the deltaless callback, and taking it from
	# the parameter retires this layer's reason to read solver state for time at all.
	var dt: float = delta
	if dt <= 0.0:
		return
	var gain: float = solver.tuning.upper_response
	# The mace makes the arms sluggish. Not a stylistic choice: a shoulder carrying a long lever
	# genuinely cannot change direction as fast, and making the arms the SAME speed whether the ogre
	# is holding four metres of iron or nothing is the tell that the weapon has no weight.
	var loaded: float = 1.0 if solver.carrying == &"" else solver.tuning.weapon_drag

	_lag = 0.0
	for b in TUNE:
		var i: int = _idx.get(b, -1)
		if i < 0:
			continue
		var target := skel.get_bone_pose_rotation(i)
		if b == "Neck" or b == "Head":
			target = _look(skel, target, b)
		if not _state.has(i):
			# First frame: start ON the target, or the whole body snaps out of the rest pose.
			_state[i] = target
			_vel[i] = Vector3.ZERO
			continue
		var t: Dictionary = TUNE[b]
		var arm: bool = b.ends_with("Arm") or b.ends_with("Shoulder")
		var w: float = float(t["w"]) * gain * (loaded if arm else 1.0)
		var got := _step(i, target, w, float(t["z"]), dt)
		_lag = maxf(_lag, rad_to_deg(got.angle_to(target)))

		# STAND DOWN WHERE THE CLIP OWNS THE BONE -- the last layer that was still arguing with it.
		#
		# The spring has to keep RUNNING (its state must track the clip, or it lunges for a target
		# hundreds of degrees stale the moment the clip lets go), but its output is faded out. Two
		# reasons, and the second is the one that showed:
		#
		#   AN AUTHORED SWING ALREADY HAS ITS FOLLOW-THROUGH. Springing it again double-counts the
		#   inertia that the animator keyed in by hand.
		#
		#   FOUR METRES OF LEVER TURNS A SMALL LAG INTO A WILD ONE. At the fastest part of the slam
		#   the mace covers about 180 degrees in 0.13 s, so a spring trailing by even a tenth of a
		#   second puts the head most of a half-turn from where the fist is pointing -- and because
		#   the weapon is rigid to the fist, that is exactly where the mace goes. Side by side with
		#   the same frame of the clip alone, the mace was on the opposite side of the ogre.
		var free := 1.0 - (solver.clip_layer.influence(b) if solver.clip_layer else 0.0)
		skel.set_bone_pose_rotation(i, target if free <= 0.001 else target.slerp(got, free))


## One damped rotational spring, integrated toward `target`.
##
## The error is expressed as a ROTATION VECTOR (axis times angle) rather than as a quaternion
## difference, because that is the form that adds and scales like a velocity — which is what a
## spring needs. Substepped for the same reason spring.gd is: a stiff spring on a hitching frame
## diverges, and it would do so on the one frame the player is looking at.
func _step(i: int, target: Quaternion, w: float, z: float, dt: float) -> Quaternion:
	var st: Quaternion = _state[i]
	var vel: Vector3 = _vel[i]
	var subs := clampi(int(ceil(w * dt / SAFE_STEP)), 1, MAX_SUB)
	var h := dt / float(subs)
	for _s in subs:
		var d := (target * st.inverse()).normalized()
		if d.w < 0.0:
			d = -d                                  # shortest arc, not the long way round
		var sin_half := sqrt(maxf(1.0 - d.w * d.w, 0.0))
		var err := Vector3.ZERO
		if sin_half > 0.00001:
			err = Vector3(d.x, d.y, d.z) / sin_half * (2.0 * acos(clampf(d.w, -1.0, 1.0)))
		vel += (err * (w * w) - vel * (2.0 * z * w)) * h
		var speed := vel.length()
		if speed > 0.00001:
			st = (Quaternion(vel / speed, speed * h) * st).normalized()
	_state[i] = st
	_vel[i] = vel
	return st


## The head turning to watch you, folded into the target BEFORE the spring so the turn inherits the
## lag rather than snapping. A heavy creature notices you late and looks round slowly, and that
## reluctance is most of what makes it read as big rather than alert.
func _look(skel: Skeleton3D, target: Quaternion, bone: String) -> Quaternion:
	var at := solver.look_target
	if at == null or not is_instance_valid(at):
		return target
	var head_world: Vector3 = skel.global_transform * skel.get_bone_global_pose(_idx[bone]).origin
	var to := at.global_position - head_world
	if to.length_squared() < 0.01:
		return target
	to = to.normalized()
	var fwd := solver.forward()
	var right := solver.right()
	# Clamped hard: a neck that can point anywhere reads as a turret. Split across neck and head so
	# neither joint carries the whole turn.
	var yaw := clampf(atan2(to.dot(right), to.dot(fwd)),
			-deg_to_rad(solver.tuning.look_yaw_deg), deg_to_rad(solver.tuning.look_yaw_deg))
	var pitch := clampf(-asin(clampf(to.y, -1.0, 1.0)),
			-deg_to_rad(solver.tuning.look_pitch_deg), deg_to_rad(solver.tuning.look_pitch_deg))
	var share := 0.45 if bone == "Neck" else 0.55
	var inv := skel.global_transform.basis.orthonormalized().inverse()
	var up := (inv * Vector3.UP).normalized()
	var rt := (inv * right).normalized()
	var parent := skel.get_bone_parent(_idx[bone])
	var pg := Quaternion.IDENTITY
	if parent >= 0:
		pg = skel.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	# The look is a world-space intent, so it is composed in world terms and brought back into the
	# bone's local frame — the same construction the pose layer uses, and for the same reason.
	var q := Quaternion(up, yaw * share) * Quaternion(rt, pitch * share)
	return (pg.inverse() * q * pg * target).normalized()


## Drop the accumulated motion. Used on teleports, where letting the springs unwind from the old
## pose would drag the ogre's upper body across the level for half a second after it arrives.
func reset() -> void:
	_state.clear()
	_vel.clear()

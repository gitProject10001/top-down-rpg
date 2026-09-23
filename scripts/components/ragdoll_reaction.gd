extends PhysicalBoneSimulator3D
## Short death transition, not a locomotion or active-balance solver.
## Samples live bone motion, adds one local impact, then releases all resistance.
@export_range(0.0, .8, .01) var collapse_duration := .68
@export_range(0.0, 5.0, .1) var impact_speed := 2.2
@export_range(1.0, 2.5, .1) var finisher_multiplier := 1.5
@export_range(0.0, 1.0, .05) var animation_inertia := .35
@export_range(0.0, 60.0, 1.0) var posture_strength := 32.0
@export_range(0.0, 1.0, .05) var body_response := .65
var impact_bone := ""
var impact_position := Vector3.ZERO
var seeded_velocity := Vector3.ZERO
var _samples: Dictionary = {}
var _motion: Dictionary = {}
var _captured := false
var _direction := Vector3.FORWARD
var _point := Vector3.ZERO
var _finisher := false
var _incoming := Vector3.ZERO

func _physics_process(delta: float) -> void:
	if _captured or is_simulating_physics(): return
	var skeleton := get_parent() as Skeleton3D
	if skeleton == null or delta <= 0: return
	for bone in get_children():
		if not bone is PhysicalBone3D: continue
		var index: int = bone.get_bone_id()
		if index < 0: continue
		var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(index) * bone.body_offset
		if _samples.has(bone.name):
			var previous: Transform3D = _samples[bone.name]
			var distance := pose.origin.distance_to(previous.origin)
			# Debug teleports are not physical momentum.
			if distance < .5:
				var rotation := (pose.basis.orthonormalized().get_rotation_quaternion() * previous.basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
				if rotation.w < 0: rotation = -rotation
				var angular := Vector3.ZERO
				if rotation.get_angle() > .001: angular = rotation.get_axis() * rotation.get_angle() / delta
				_motion[bone.name] = [(pose.origin-previous.origin)/delta, angular.limit_length(8.0)]
			else: _motion.erase(bone.name)
		_samples[bone.name] = pose

func capture_impact(point: Vector3, direction: Vector3, incoming: Vector3, finisher: bool) -> void:
	_captured = true
	_point = point
	_direction = direction.normalized() if direction.length_squared() > .001 else Vector3.FORWARD
	_incoming = incoming.limit_length(6.0)
	_finisher = finisher

func start_reaction() -> void:
	var closest: PhysicalBone3D
	var distance := INF
	# Use the live skeleton's last pose, before animation is stopped.
	for bone in get_children():
		if not bone is PhysicalBone3D: continue
		var pose: Transform3D = _samples.get(bone.name, bone.global_transform)
		var d := pose.origin.distance_squared_to(_point)
		if d < distance:
			distance = d
			closest = bone
	physical_bones_start_simulation()
	seeded_velocity = _incoming
	for bone in get_children():
		if not bone is PhysicalBone3D: continue
		var motion: Array = _motion.get(bone.name, [_incoming, Vector3.ZERO])
		# Bone motion already includes locomotion: blend, do not add it twice.
		bone.linear_velocity = _incoming.lerp(Vector3(motion[0]).limit_length(7.0), animation_inertia).limit_length(7.0)
		bone.angular_velocity = Vector3(motion[1]) * animation_inertia
		bone.bounce = 0.0
		bone.friction = .85
		bone.linear_damp = .18
		var duration := collapse_duration
		var label := String(bone.bone_name)
		# React away from the contact with an asymmetric loss of support.
		# These are small angular targets, never world-position constraints.
		var skeleton := get_parent() as Skeleton3D
		var side := signf(skeleton.global_basis.x.dot(_point - skeleton.global_position))
		if is_zero_approx(side): side = 1.0
		var struck_side := ("Right" in label and side > 0) or ("Left" in label and side < 0)
		var axis := Vector3.UP.cross(_direction).normalized()
		if axis.length_squared() < .1: axis = skeleton.global_basis.x.normalized()
		var angle := 0.0
		var delay := 0.0
		var strength := posture_strength
		if "Leg" in label or "Foot" in label:
			duration *= .42 if struck_side else .80
			angle = -.14 if "LowerLeg" in label else .07
			strength *= .65
		elif "Arm" in label or "Hand" in label:
			duration *= 1.05
			delay = .10 if struck_side else .17
			angle = -.30 if "UpperArm" in label else -.18
			strength *= .70
		elif label in ["Spine", "Chest", "UpperChest"]:
			angle = .20
			delay = .03 if label == "Spine" else .07
		elif label in ["Head", "Neck"]:
			angle = -.12
			delay = .14
			duration *= .85
		if bone == closest: duration *= .65
		if _finisher: duration *= .65
		var bend := Quaternion(axis, angle * body_response)
		if label in ["Chest", "UpperChest"]:
			bend = Quaternion(Vector3.UP, side * .12 * body_response) * bend
		bone.begin_resistance(bone.global_basis.orthonormalized().get_rotation_quaternion(), duration, strength, bend, minf(delay, duration*.3))
		# Relax the authored elbow/knee springs as well, without changing anatomical limits.
		if bone.joint_type == PhysicalBone3D.JOINT_TYPE_6DOF:
			var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			tween.tween_method(func(value: float):
				if is_instance_valid(bone): bone.set("joint_constraints/z/angular_spring_stiffness", value),
				float(bone.get("joint_constraints/z/angular_spring_stiffness")), 0.0, maxf(duration, .01))
	if closest:
		impact_bone = String(closest.bone_name)
		# Limit lever length: approximate contacts must not launch a limb into orbit.
		var lever := (_point - closest.global_position).limit_length(.10)
		impact_position = closest.global_position + lever
		var speed := impact_speed * (finisher_multiplier if _finisher else 1.0)
		closest.apply_impulse(_direction * speed * closest.mass, lever)
	set_physics_process(false)

func resume_pose_sampling() -> void:
	_captured = false

func finish_pose_sampling(displacement: Vector3, incoming: Vector3) -> void:
	_physics_process(1.0 / Engine.physics_ticks_per_second)
	_captured = true
	_point += displacement
	_incoming = incoming.limit_length(6.0)

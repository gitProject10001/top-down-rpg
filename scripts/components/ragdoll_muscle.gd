extends PhysicalBone3D
## Brief, bounded posture resistance in the physics callback. Gravity and joints
## remain authoritative; there is no position pinning or equilibrium controller.
var target_rotation := Quaternion.IDENTITY
var release_seconds := 0.0
var elapsed := 0.0
var resistance := 0.0
var active_reaction := false

func begin_resistance(rotation: Quaternion, duration: float, strength: float) -> void:
	target_rotation = rotation
	release_seconds = maxf(duration, .01)
	resistance = strength
	elapsed = 0.0
	active_reaction = true

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not active_reaction: return
	elapsed += state.step
	if elapsed >= release_seconds:
		active_reaction = false
		return
	var fade := pow(1.0 - elapsed / release_seconds, 2.0)
	var current := state.transform.basis.orthonormalized().get_rotation_quaternion()
	var error := (target_rotation * current.inverse()).normalized()
	if error.w < 0: error = -error
	var angle := error.get_angle()
	if angle > .001:
		var acceleration := error.get_axis() * minf(angle, .6) * resistance - state.angular_velocity * 5.0
		state.angular_velocity += acceleration.limit_length(35.0) * fade * state.step

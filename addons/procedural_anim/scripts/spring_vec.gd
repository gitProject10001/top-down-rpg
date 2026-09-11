class_name SpringVec
extends RefCounted
## Spring, three axes at once. See spring.gd for why springs and not the project's usual
## exponential ease — the short version is that an ease cannot overshoot, and overshoot is mass.
##
## Kept as its own class rather than three Springs at every call site because the things that need
## it (the chest lagging behind the hips, the head resisting a lean) are naturally vectors, and
## writing `.x .y .z` three times per bone per frame is how a sign error gets in.

const SAFE_STEP := 0.20
const MAX_SUB := 8

var value: Vector3
var vel: Vector3
var omega: float
var zeta: float


func _init(start := Vector3.ZERO, frequency := 10.0, damping := 0.5) -> void:
	value = start
	omega = frequency
	zeta = damping


func step(delta: float, target: Vector3) -> Vector3:
	if delta <= 0.0:
		return value
	var subs := clampi(int(ceil(omega * delta / SAFE_STEP)), 1, MAX_SUB)
	var dt := delta / float(subs)
	for _i in subs:
		var accel := (target - value) * (omega * omega) - vel * (2.0 * zeta * omega)
		vel += accel * dt
		value += vel * dt
	return value



func reset(to := Vector3.ZERO) -> void:
	value = to
	vel = Vector3.ZERO

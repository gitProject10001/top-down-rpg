class_name Spring
extends RefCounted
## A damped harmonic oscillator, and the reason the ogre reads as heavy rather than slow.
##
## WHY NOT THE PROJECT'S USUAL SMOOTHING. Everything else here eases with
## `x = lerpf(x, target, 1.0 - exp(-speed * delta))` (camera_rig.gd, player.gd, enemy.gd), which is
## frame-rate independent, cheap, and CANNOT OVERSHOOT. That last property is exactly wrong for
## mass. A heavy body arrives late and goes PAST — the pelvis drops below its resting height on a
## footfall and comes back up, the chest keeps travelling after the hips stop. An exponential ease
## is a body with no momentum; it lands like a hydraulic. This lands like meat.
##
## Two dials, both physical, so they can be reasoned about instead of dialled blind:
##   omega -- angular frequency in rad/s. How fast it responds. Period = TAU / omega.
##   zeta  -- damping ratio. 1.0 = critically damped, the fastest approach with NO overshoot.
##            Below 1.0 overshoots and rings; ABOVE 1.0 is sluggish and never oscillates.
##            The ogre lives at 0.35-0.55. That visible second bounce is the whole point.
##
## STABILITY. Semi-implicit Euler goes unstable when `omega * delta` gets large, and a stiff spring
## (omega 20+) on a hitching frame is exactly when that happens — the ogre would detonate on the one
## frame the player notices. So the step is subdivided to keep `omega * dt` under SAFE_STEP. Costs a
## handful of multiplies and removes a whole class of "it exploded once and I could not reproduce it".

const SAFE_STEP := 0.20        ## max omega*dt per substep; beyond ~0.5 semi-implicit Euler diverges
const MAX_SUB := 8             ## cap the subdivision so a 2-second hitch cannot freeze the frame

var value: float                ## current position
var vel: float                  ## current velocity, in units/s
var omega: float                ## rad/s
var zeta: float                 ## damping ratio


func _init(start := 0.0, frequency := 10.0, damping := 0.5) -> void:
	value = start
	omega = frequency
	zeta = damping


## Integrate toward `target`. Call once per physics tick.
func step(delta: float, target: float) -> float:
	if delta <= 0.0:
		return value
	var subs := clampi(int(ceil(omega * delta / SAFE_STEP)), 1, MAX_SUB)
	var dt := delta / float(subs)
	for _i in subs:
		# a = omega^2 * (target - x) - 2*zeta*omega*v      the standard damped-spring acceleration
		var accel := omega * omega * (target - value) - 2.0 * zeta * omega * vel
		vel += accel * dt
		value += vel * dt
	return value


## A kick, not a displacement. This is how a footfall enters the system: the impact does not MOVE
## the pelvis, it gives it downward VELOCITY, and the spring decides how far it sinks and how it
## comes back. Driving the position directly instead would make every landing identical depth
## regardless of how hard it was — which is the difference between an impact and a pose change.
func impulse(v: float) -> void:
	vel += v


## Snap to a value with no motion — for teleports and resets, where ringing would be a bug.
func reset(to := 0.0) -> void:
	value = to
	vel = 0.0


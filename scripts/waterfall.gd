extends MeshInstance3D
## A procedural spill, and its PLUNGE POOL: the falling sheet is the mesh, and this script
## keeps poking the ripple field at the foot so the water below is permanently disturbed —
## rings spreading out from under the fall, for free, because that field already exists.
##
## This is where the two water systems earn each other. Nothing here simulates anything; it
## drops an impulse into WA2's wave equation at a cadence and lets the solver do the rest.
##
## A map can carry hundreds of these (every downhill-facing rim cell of every lake), so the
## per-frame cost is one distance check: the ripple window is only 64 m across and Ripples
## culls anything outside it anyway, but culling here keeps far falls from crowding the
## 16-impulse queue and starving the player's own footsteps.

## A WATERFALL IS A LINE, NOT A DRIP. One jittered point every 0.22 s reads as bubbles
## surfacing — the pool looked like it was boiling rather than being fallen into. Three things
## fix it: the impulse SWEEPS across the fall's width instead of landing at random, it is WIDE
## enough that successive ones overlap into a continuous trough, and it lands often enough to
## be a curtain rather than a series of events.
##
## The sweep step is deliberately irrational-ish so it never settles into a short cycle and
## redraws the same few spots — that is what made the scatter read as discrete in the first
## place.
const EVERY := 0.07                           ## seconds between impulses
const SWEEP := 0.383                          ## fraction of the width advanced each time
const RADIUS := 0.9                           ## metres; overlaps its neighbours

## The plunge point in the SHEET'S OWN frame, resolved to world at emission time. Not a baked
## world position: the terrain is repositioned after the falls are built, so anything captured
## at build time is wrong by half a map.
var foot_local := Vector3.ZERO
var width := 2.0                              ## the sheet's own width, for the sweep
var strength := 0.02

var _t := 0.0
var _sweep := 0.0


func _ready() -> void:
	# Stagger, so a mapful of falls does not all fire on the same frame and blow through the
	# solver's 16-impulse budget in one go while the player's own footsteps queue behind.
	_t = randf() * EVERY
	_sweep = randf()


func _process(delta: float) -> void:
	_t += delta
	if _t < EVERY:
		return
	_t = 0.0
	# THE RIPPLE WINDOW decides what is close enough to matter — not a distance to the player.
	# It is the same authority Ripples itself uses to cull, it follows the camera in the
	# benches where no player exists, and it keeps a mapful of distant falls from crowding
	# the 16-impulse queue and starving the player's own footsteps.
	# Walk across the fall rather than scattering inside it.
	_sweep = fposmod(_sweep + SWEEP, 1.0)
	var foot := to_global(foot_local + Vector3((_sweep - 0.5) * width, 0.0, 0.0))
	var origin := Ripples.window_origin()
	var f := Vector2(foot.x, foot.z) - origin
	if f.x < 0.0 or f.y < 0.0 or f.x > Ripples.SIZE_M or f.y > Ripples.SIZE_M:
		return
	Ripples.splash(foot, RADIUS, strength)

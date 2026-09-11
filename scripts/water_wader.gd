extends Node
## WADING, as one self-configuring child of the player (the BlobShadow doctrine: drop it in,
## it reads its parent, no state file changes). Each physics tick it probes the Water oracle
## once — a dictionary lookup, not a raycast — and turns depth into:
##
##   - `water_slow` on the parent (via set(), so any body without the property ignores it):
##     apply_movement multiplies it in, which slows every state that moves through the helper.
##     Dash is DELIBERATELY untouched — it writes velocity directly, and a full-speed dash
##     through knee water behind a big splash is the fantasy, not a bug.
##   - THE BODY ITSELF, as a solid registered with the solver, which is what makes the waves;
##   - splashes on entry, on dashing in, and on landing from a jump — the landing read the
##     same airborne->floor fact jump.gd:62 uses, without editing jump.gd.
##
## THE DISTANCE-CADENCED FOOT RINGS ARE GONE, and the numbers are why. Measured on a flat 1.04 m
## pan (probe_swe_wake.gd), peak-to-peak wake in a band beside a 16 m track:
##
##   foot rings, as originally shipped      6.8 mm    against a 5.9 mm noise floor
##   foot rings, widened and strengthened  48.3 mm
##   THE BODY AS A SOLID                  246.6 mm    and 127 mm at walking pace
##
## Five times the best the rings could manage, and thirty-six times what was actually shipped. It
## also comes out RIGHT rather than tuned: a solid has a bow wave because water piles against its
## front and a wake because the displaced water closes behind it, it scales with speed on its own,
## and it goes silent when the body stands still. Keeping the rings on top would have poked a hole
## through the middle of the body that was displacing the water.
##
## Feet sit 1.07 m below the player root (dash.gd:11's measured constant).

const FOOT_DROP := 1.07
const DASH_SPEED := 12.0                      ## planar speed that reads as a dash entry

## THE BODY IS A SOLID IN THE WATER, not a series of pokes at it.
##
## An impulse is a hole punched in the surface that then radiates and dies. A SOLID shoulders water
## aside continuously: it has a bow wave because water piles against its front, a wake because the
## displaced water closes behind it, and it makes NOTHING at all when it stands still - all of that
## for free, out of the same conservation law that governs everything else in the field, with no
## amplitude to tune. That is why the dragged cylinder obstacle reads as convincingly as it does
## and the footfall rings never did.
##
## bed_at() = max(terrain, obstacle_top), so a top face above the surface blocks the whole column,
## which is what a person standing in water does. The face depth hf = max(0, max(w,wn) - max(b,bn))
## closes the boundary faces by itself; nothing else in the solver has to learn about bodies.
##
## LEGS, NOT SHOULDERS - and 0.45 was neither. It was picked to be comfortably wide on the coarser
## grid it was chosen on, and the result was a wading player who out-waved the BOAT: 261 mm of wake
## against the raft's 204. A person is not a barge.
##
## Measured on a flat 1.04 m pan, wake against footprint (probe_swe_wake.gd):
##
##   r 0.45    261 mm   128 % of the raft    31.5 cells, area swinging 10 % as it walks
##   r 0.3125  203 mm   100 %                15.0 cells, 13 %      <- the collision capsule
##   r 0.28    160 mm    79 %                12.0 cells, 17 %
##   r 0.25    109 mm    53 %                 9.9 cells, 30 %      <- here
##   r 0.20     73 mm    36 %                 6.2 cells, 48 %
##
## The player's own body capsule is 0.3125 (player4.tscn:26) and still makes exactly the boat's
## wake, so matching it is not enough. 0.25 is the legs rather than the whole body, and it puts a
## person at about half a boat, which is the right order.
##
## THE COST IS REAL AND IS THE SECOND COLUMN. obstacle_top() tests the texel CENTRE, so a body
## covers a whole number of cells and that count changes as it walks - the disc breathes, and the
## smaller it is the harder it breathes in relative terms. 30 % at this radius. If that reads as
## noise in the wake the fix is a soft-rimmed cylinder rather than a bigger one: obs_a[i].w is
## unused for cylinders and could carry an inner radius, letting the top ramp instead of step, which
## stays a pure function of the integer texel index and so keeps the conservation argument intact.
const BODY_R := 0.25
## HOW FAR THE BODY'S TOP SITS BELOW THE WATERLINE, and it must be BELOW it.
##
## A top face above the surface makes the solid EMERGENT: the solver closes every face around it and
## keeps those cells dry, and the renderer then cuts the water at the body's outline. That is right
## for a pier and wrong for a person - the player waded in a dry crater with the lake standing off
## at arm's length, which is what it looked like.
##
## Sunk instead, water stands over the body, the faces stay open, and the surface is drawn straight
## through - the character's own mesh is what you see standing in it. It still raises the bed, so it
## still displaces, and the cost is almost nothing: measured on a flat 1.04 m pan, a full block
## makes a 285.2 mm wake and 8 cm of submergence makes 261.2 mm. Eight per cent, for the difference
## between water that reaches the player and water that recoils from them.
##
## Deeper buys nothing and costs more - 0.12 gives 255.4 mm, 0.25 gives 223.6.
const BODY_SUBMERGE := 0.08
## Below this there is not enough water for a body to displace anything, and holding a solid in a
## puddle only quantises the shoreline.
const BODY_MIN_DEPTH := 0.08

var _body: CharacterBody3D = null
var _prev_depth := 0.0
var _prev_on_floor := true
var _prev_vy := 0.0
var _obs := -1                                ## the solver's id for this body, -1 when ashore


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	set_physics_process(_body != null)


func _physics_process(dt: float) -> void:
	var pos := _body.global_position
	var surface: float = Water.surface_y(pos)
	var depth := 0.0
	if not is_nan(surface):
		depth = clampf(surface - (pos.y - FOOT_DROP), 0.0, 0.7)
	_body.set("water_slow", lerpf(1.0, 0.5, smoothstep(0.05, 0.45, depth)))

	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	var feet := Vector3(pos.x, surface if not is_nan(surface) else pos.y, pos.z)

	if _prev_depth <= 0.01 and depth > 0.04 and speed > 2.0:
		var dashing := speed >= DASH_SPEED
		Fx.splash(feet, 1.3 if dashing else 0.7)
		Water.wake(feet, 1.9 if dashing else 1.3, 0.55 if dashing else 0.30)

	if _body.is_on_floor() and not _prev_on_floor and _prev_vy < -3.0 and depth > 0.04:
		Fx.splash(feet, 1.0)
		Water.wake(feet, 1.5, 0.40)

	# ---- THE BODY ITSELF, standing in the water and pushing it about.
	_solid(pos, surface, depth)

	_prev_depth = depth
	_prev_on_floor = _body.is_on_floor()
	_prev_vy = _body.velocity.y


## Keep a solid registered with the solver wherever the body is actually standing in water, and
## keep its top face level with the surface as it wades from shallow to deep.
##
## THE TOP HAS TO TRACK, which is why obstacle_move grew a top_y. Registered once at the entry
## depth and left there, the body would stop blocking as soon as it walked in deeper - water would
## simply flow over its head - and the bow wave would fade out exactly where it should be growing.
##
## `depth` is the body's own IMMERSION, not the water column - and the difference is a bug that
## would only ever have shown up on the raft. A rider stands on a deck above a metre of lake, so the
## column is deep and the immersion is zero; gating on the column would have kept a body-sized solid
## registered under the boat, displacing water nobody is standing in and fighting the hull's own
## solid for the same cells. Same for a bridge, a jetty, or a jump over a pond.
func _solid(pos: Vector3, surface: float, depth: float) -> void:
	var wading := not is_nan(surface) and depth > BODY_MIN_DEPTH
	var deep_enough := wading and surface - Water.bed_y(pos) > BODY_MIN_DEPTH
	if not deep_enough:
		_drop_solid()
		return
	var at := Vector2(pos.x, pos.z)
	var top := surface - BODY_SUBMERGE
	if _obs < 0:
		_obs = Ripples.obstacle_add(Ripples.Obstacle.CYLINDER, at, Vector2(BODY_R, BODY_R), top)
	else:
		Ripples.obstacle_move(_obs, at, NAN, top)


func _drop_solid() -> void:
	if _obs >= 0:
		Ripples.obstacle_remove(_obs)
		_obs = -1


## A body that leaves the scene must take its solid with it. An abandoned obstacle is a permanent
## invisible pillar in the lake, and the only symptom is water going round something that is not
## there any more.
func _exit_tree() -> void:
	_drop_solid()

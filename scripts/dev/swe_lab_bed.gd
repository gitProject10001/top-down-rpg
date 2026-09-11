@tool
extends Node3D
## A SYNTHETIC BED for the SWE lab: a water oracle over an analytic profile instead of over a
## generated world.
##
## It exists so the solver can be watched in isolation. The wilds answer these same four
## questions from painted cells and derived tiers, which is the right thing in the game and
## the wrong thing on a bench — you cannot ask a generated map for "a flat pan", "a V-channel
## at 2% grade" or "three terraces and nothing else", and those are exactly the cases that
## tell you whether a solver works.
##
## THE CONTRACT IS DUCK-TYPED (Water.oracle resolves whoever holds group "water_oracle" and
## calls water_surface_y / water_depth_at / water_flow_at / water_is_spring), so this drives
## the REAL Ripples solver through the REAL code path. A lab with its own driver measures its
## own driver.
##
## THE MODEL'S ONE LIMIT, stated here because the lab exists to surface it — and now MEASURED,
## because it did. The wilds model has a FLAT rest surface Y per region and a rest depth
## H0 = Y - bed. There is no separate bed-elevation channel, so "an empty basin with a shaped
## floor" is representable only as eta = -H0: water at rest is the model's zero, and emptiness
## is a full-amplitude displacement away from it.
##
## A displacement is exactly what the solver is built to relax. At the SHORELINE, H0 falls to
## zero across one metre of the bilinear terrain field, so eta acquires a real, steep gradient
## there and the solver reads a dry beach as a metre-high wall of water leaning inward — then
## correctly collapses it into the basin, at about a millimetre of head per step. Measured by
## scripts/dev/probe_swe_lab.gd: 60 cubic metres into a dry 48 m basin in five seconds, with no
## spring, no drain and no impulse. Its section 2 carries the evidence that it is the shoreline
## and nothing else — the INTERIOR of a flat empty pan is an exact fixed point, gravity = 0 stops
## it dead, and the growth is linear rather than compounding.
##
## So THE SOLVER CANNOT HOLD A DRY BASIN AT REST, and no tuning changes that: in its state
## variables a dry basin IS a metre of piled-up water. The fix is a design decision rather than a
## patch — make depth h the primary variable over a separate bed elevation, so "dry" is h = 0 and
## costs no displacement. The game is unaffected meanwhile: ponds there start and stay near rest,
## which is the one regime this encoding is exact in.

## BANKS ARE RAMPS, NOT WALLS. They used to be `+0.9 if past the rim`, a vertical cliff one vertex
## wide - and a vertical cliff in the BED is a vertical cliff in the WATERLINE, quantised by
## whatever resolution the terrain field happens to have. The bench then spends its time showing
## you the staircase of its own test shape rather than anything the solver did.
enum Profile {
	FLAT_PAN,       ## one level, uniform depth — the control case
	VALLEY,         ## a V-channel falling along +X: grade, banks, one outlet
	TERRACES,       ## three flat steps — exercises the weirs and nothing else
	BOWL,           ## a round basin with no outlet — fills, then only the sink empties it
	## A PURE TILTED PAN: the grade and nothing else - no V, no banks, no vertical step anywhere.
	## The control that separates "a lake cannot sit over a SLOPE" from "a lake cannot sit against
	## a STEP", which look identical in a volume total and want opposite fixes.
	RAMP,
	## A MEANDERING CHANNEL, cut into a plain and falling along +X, fed by a fast inflow at the -X
	## rim. The centreline snakes with a sine; the banks rise as a smooth trough round it so there
	## is no vertical wall to be a step. Twelve metres of wavelength and six of amplitude fits three
	## bends in the 48 m extent, and the channel is 6 m wide - THIRTY texels at dx 0.2, which is the
	## point: a channel narrower than about ten texels is a staircase with water in it, and every
	## bend then sheds off the lattice rather than off the bank.
	RIVER,
	## A SHELVING BEACH, shallowing along +X out of deep water at -X. Waves arrive from the ocean
	## end and run up it. Unlike VALLEY there are no side banks at all - the shore is the only
	## feature, so nothing else can be blamed for what the waterline does.
	BEACH,
	## TERRACES WITH A REAL DROP: three pools, each spilling into the next over a lip. The drop is
	## the whole point - it is what makes a plunge rather than a ramp - but it is bounded by the
	## grid, not by taste. The staggered scheme is stable to about 6 m of depth, and a plunge pool
	## fills to roughly the drop height, so 1.8 m a step keeps the deepest pool inside it with room
	## to spare.
	WATERFALL,
}

## BOWL by default: a basin with a rim is the shape that demonstrates the headline behaviour -
## it fills, and then it overflows. A valley drains off the end before you can see either.
@export var profile := Profile.BOWL:
	set(v):
		profile = v
		_dirty = true
@export var extent := 48.0                    ## metres across, square, centred on this node
@export var bed_depth := 0.55                 ## deepest the floor sits below the rest surface
@export var grade := 0.03                     ## VALLEY / RIVER: metres of fall per metre along +X
@export var rest_y := 0.0                     ## the rest water surface height
## RIVER. Six metres of channel is thirty texels at dx 0.2 - a channel narrower than about ten is
## a staircase with water in it, and every bend sheds off the lattice instead of off the bank.
@export var river_width := 6.0
@export var river_amp := 6.0                  ## metres the centreline swings either side of z = 0
@export var river_wave := 24.0                ## metres of X per full meander
## BEACH. Metres of rise per metre along +X, so the waterline sits at x = -bed_depth/beach_slope.
@export var beach_slope := 0.03
## WATERFALL. Metres of drop per step. Three steps, so the total fall is twice this. Bounded by the
## grid rather than by taste: the staggered scheme is stable to about 6 m and a plunge pool fills to
## roughly the drop, so 1.8 keeps the deepest pool well inside it.
@export var fall_step := 1.8

## Sources and sinks, in LOCAL XZ. Sources inject; sinks are drains the solver reads as
## ordinary springs with a negative rate (see swe_lab.gd, which flips the sign per cell).
var springs: Array[Vector2] = []
var spring_radius := 2.0

var _dirty := true


func _ready() -> void:
	add_to_group("water_oracle")


## Bed elevation at a local XZ, in world Y. Below rest_y is a basin; above it is bank.
func bed_at(local: Vector2) -> float:
	var h := extent * 0.5
	var x := clampf(local.x / h, -1.0, 1.0)
	var z := clampf(local.y / h, -1.0, 1.0)
	match profile:
		Profile.FLAT_PAN:
			return rest_y - bed_depth
		Profile.VALLEY:
			# A V across Z, falling along X. The banks rise above rest so the channel has
			# somewhere to be contained.
			var across := absf(z)
			var floor_y := rest_y - bed_depth * (1.0 - across * across)
			return floor_y - local.x * grade + 0.9 * smoothstep(0.66, 0.86, across)
		Profile.RAMP:
			return rest_y - bed_depth - local.x * grade
		Profile.TERRACES:
			var step := floorf((x + 1.0) * 1.5)          # 0, 1, 2 across the map
			return rest_y - bed_depth + (2.0 - step) * 1.2
		Profile.RIVER:
			# The centreline snakes across Z as a sine of X; the bed is a smooth trough round it,
			# falling along +X so the water has somewhere to go. `across` is the distance from the
			# centreline in channel half-widths, so the trough profile is written once and the
			# meander is entirely in where its centre is.
			var mid := river_amp * sin(TAU * local.x / maxf(river_wave, 0.1))
			var across := absf(local.y - mid) / maxf(river_width * 0.5, 0.1)
			# smoothstep, NOT a clamp to a V: a channel with a corner at the bank is a corner in
			# the WATERLINE, and the bench would spend its time showing the corner.
			var cut := bed_depth * (1.0 - smoothstep(0.0, 1.35, across))
			return rest_y - cut - local.x * grade + 0.35 * smoothstep(1.0, 1.6, across)
		Profile.BEACH:
			# Deep at -X, shelving up through the waterline and on to dry sand. No banks: the
			# shore is the only feature on this bed, so nothing else can be blamed for the
			# waterline. `beach_slope` is the rise per metre, so the waterline sits at
			# x = -bed_depth/beach_slope and everything up-beach of it is dry.
			return rest_y - bed_depth + local.x * beach_slope
		Profile.WATERFALL:
			# Three pools falling along +X, each with a flat floor and a lip. The pools are cut
			# INTO the steps rather than the steps being the floor, so each one holds water instead
			# of shedding it - a staircase of flat treads is a ramp with corners, not a waterfall.
			var stp := clampf(floorf((x + 1.0) * 1.5), 0.0, 2.0)
			var top: float = rest_y + (2.0 - stp) * fall_step
			# Where in this step are we? The pool occupies most of it and the lip is the last fifth.
			# fract() is GLSL; GDScript spells it this way.
			var into: float = (x + 1.0) * 1.5 - floorf((x + 1.0) * 1.5)
			var pool := 1.0 - smoothstep(0.72, 0.95, into)
			return top - fall_step * 0.45 * pool
		_:
			var r := sqrt(x * x + z * z)
			return rest_y - bed_depth * maxf(0.0, 1.0 - r * r) + 0.9 * smoothstep(0.80, 0.98, r)


# ---------------------------------------------------------------- the water contract --------
# The same four questions the wilds answers, over an analytic bed. `local` is this node's own
# XZ plane, exactly as WildsTerrain defines it.

## THE REST SURFACE IS NOT ALWAYS ONE FLAT LEVEL, and three of the profiles need it not to be.
##
## The wilds model has a single flat Y per water region, and for a bowl or a pan that is exactly
## right. For a WATERFALL it is not: three pools at three heights are three rest levels, and giving
## them one would either flood the upper steps to the bottom pool's level or leave them dry. For a
## RIVER falling along its length the same argument applies more weakly - the surface follows the
## bed downhill rather than sitting level.
##
## So the rest surface is per-profile. It stays flat where flat is right, and steps with the terrain
## where it is not. Everything downstream already copes: the solver reconstructs its rest depth as
## max(Y - b, 0) at every texel, and rest_y_at takes the stencil max, so a stepped Y is no more
## trouble than a stepped bed.
func rest_surface_at(local: Vector2) -> float:
	var h := extent * 0.5
	match profile:
		Profile.WATERFALL:
			# Each pool's own level: the lip of its step. A pool fills to its lip and then spills,
			# which is the behaviour the profile exists to show.
			var x := clampf(local.x / h, -1.0, 1.0)
			var stp := clampf(floorf((x + 1.0) * 1.5), 0.0, 2.0)
			return rest_y + (2.0 - stp) * fall_step
		Profile.RIVER:
			# The surface follows the valley floor downhill. Without this the river is a level lake
			# in a sloping trench, which is a reservoir, not a river.
			return rest_y - local.x * grade
		_:
			return rest_y


func water_surface_y(local: Vector2) -> float:
	if absf(local.x) > extent * 0.5 or absf(local.y) > extent * 0.5:
		return NAN
	# Anywhere the bed sits BELOW the rest surface is part of the basin — it is water as far
	# as the solver is concerned, even when it currently holds none. That distinction (a place
	# water can be, versus water) is the one the wilds model does not draw.
	var y := rest_surface_at(local)
	return y if bed_at(local) < y else NAN


func water_depth_at(local: Vector2) -> float:
	if is_nan(water_surface_y(local)):
		return 0.0
	return maxf(rest_surface_at(local) - bed_at(local), 0.0)


## The bed, straight out of the profile - this bench has an analytic floor, which is the whole
## reason it exists. Outside the bench extent it answers the wall, so the box closes itself.
func water_bed_y(local: Vector2) -> float:
	if absf(local.x) > extent * 0.5 or absf(local.y) > extent * 0.5:
		return Water.BED_WALL
	return bed_at(local)


## No baked current here on purpose. In the wilds u0 is terrain-derived and carries transport;
## on the bench it would be a second unexplained input sitting under everything, so the lab
## shows what gravity alone does with a bed.
func water_flow_at(_local: Vector2) -> Vector2:
	return Vector2.ZERO


func water_is_spring(local: Vector2) -> bool:
	for s in springs:
		if local.distance_to(s) <= spring_radius:
			return true
	return false

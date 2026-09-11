extends Node
## World-space water queries (autoload "Water"): surface height, water-column depth, and the
## is-there-water-here test, answered by whatever node currently holds group "water_oracle"
## (wilds_terrain joins it in _begin; terrain_field could join later). Duck-typed on
## water_surface_y/water_depth_at exactly as the foliage addon duck-types the ground trio —
## no class_name coupling, so zones swap freely and this file never changes.
##
## NAN is the honest "no water": a caller can tell a dry cell from water at height 0.0.
## depth_at answers 0 on dry ground so movement code can feed it to a curve without guards.

## THE BED OFF THE MAP, and past any terrain a tier system can produce (max_tier 4 x 1.2 m).
## A solver reading the bed channel sees this as a floor it can never climb, which is exactly a
## reflecting wall - so the world edge bounds the simulation without anybody writing a boundary
## condition. Positive, and the mirror of Ripples.DRY_Y at the other end of the same scale.
const BED_WALL := 1000.0

var _oracle: Node3D = null


func oracle() -> Node3D:
	if _oracle == null or not is_instance_valid(_oracle) or not _oracle.is_inside_tree():
		_oracle = get_tree().get_first_node_in_group("water_oracle") as Node3D
	return _oracle


func surface_y(world_pos: Vector3) -> float:
	var o := oracle()
	if o == null:
		return NAN
	var l := o.to_local(world_pos)
	var ys: float = o.water_surface_y(Vector2(l.x, l.z))
	if is_nan(ys):
		return NAN
	# Back through the terrain's transform: the oracle answers in its own frame, and the zone
	# parks terrains at arbitrary world offsets.
	return o.to_global(Vector3(l.x, ys, l.z)).y


func depth_at(world_pos: Vector3) -> float:
	var o := oracle()
	if o == null:
		return 0.0
	var l := o.to_local(world_pos)
	return o.water_depth_at(Vector2(l.x, l.z))


## THE BED under a point, in world Y: the floor, whether or not there is water on it.
##
## Optional in the contract, and the FALLBACK CHAIN is the point. An oracle that answers
## water_bed_y is believed. One that does not still has a bed wherever it has water, because
## surface minus depth IS the bed there - so the terraced wilds and a bare decorative pond both
## work, and an oracle written before this query existed does not have to be edited to keep up.
func bed_y(world_pos: Vector3) -> float:
	var o := oracle()
	if o == null:
		return BED_WALL
	var l := o.to_local(world_pos)
	var xz := Vector2(l.x, l.z)
	if o.has_method("water_bed_y"):
		return o.to_global(Vector3(l.x, o.water_bed_y(xz), l.z)).y
	var ys: float = o.water_surface_y(xz)
	if is_nan(ys):
		return BED_WALL
	return o.to_global(Vector3(l.x, ys - o.water_depth_at(xz), l.z)).y


func is_water(world_pos: Vector3) -> bool:
	return not is_nan(surface_y(world_pos))


## Is this a SOURCE — a painted spring, where water enters the world?
func is_spring(world_pos: Vector3) -> bool:
	var o := oracle()
	if o == null or not o.has_method("water_is_spring"):
		return false
	var l := o.to_local(world_pos)
	return o.water_is_spring(Vector2(l.x, l.z))


## THE CURRENT here, in metres/second on the world XZ plane, ZERO on dry ground — so a caller
## can add it to a velocity unconditionally. Flows are DERIVED from terrain, not simulated
## (see WildsGen.flow_at), which is why this is a cheap pure call and not a texture readback.
func flow_at(world_pos: Vector3) -> Vector2:
	var o := oracle()
	if o == null or not o.has_method("water_flow_at"):
		return Vector2.ZERO
	var l := o.to_local(world_pos)
	var f: Vector2 = o.water_flow_at(Vector2(l.x, l.z))
	# The oracle answers in ITS basis; zones park terrains at arbitrary yaws in principle.
	var g := o.to_global(Vector3(l.x + f.x, l.y, l.z + f.y)) - o.to_global(l)
	return Vector2(g.x, g.z)


## A WAKE FROM SOMETHING MOVING THROUGH THE WATER - a hull, a boot - sized so it cannot poke a hole
## through the lake it is sailing on.
##
## THIS IS POLICY AND IT LIVES HERE ON PURPOSE. Ripples.splash is the solver's primitive: it
## displaces a column by however many metres it is told to, which is the right and general
## behaviour and is what a dam break and a drain both need. Whether THIS game's boat is allowed to
## displace half its lake is an artistic question about this game, and the solver must not learn
## the answer - the seam exists so gameplay caps sit on top of the simulation rather than inside it.
##
## TWO THINGS ARE BEING BOUGHT, and measuring them separated the dials (probe_swe_wake.gd, on a
## flat 1.04 m pan at the game's own policy settings):
##
##   RADIUS IS THE CHEAP LEVER AND IT WAS NEVER USED. Widening the raft's bow ring from 0.6 m to
##   1.4 m took the radiated wake from 26 mm to 109 mm - four times - while tripling its STRENGTH
##   bought only 2.5x for slightly MORE drawdown. A poke narrower than about three texels is at the
##   grid scale, which is exactly the wavelength the upwind flux and the curvature-gated smoother
##   dissipate fastest; the energy is gone in a handful of steps however much of it there is. The
##   player's footfall ring was 0.35 m - 1.7 texels - and measured 6.8 mm against a 5.9 mm null,
##   which is to say the wader has never made a wave at all, only noise.
##
##   DEPTH IS THE CEILING, and it is why strength cannot simply be multiplied. Displacement is in
##   metres of water column, so a 0.5 m poke is a modest dent in the 1.04 m lake and a hole clean
##   through the 0.2 m shallows at its edge - and a dry cell is not a bigger wave, it is a shock
##   front and a stripe of foam. Clamping to a fraction of the LOCAL column makes the same call
##   site safe in both places without anybody tuning per-water constants.
## THE CAP IS ON THE DISPLACEMENT, BUT THE CONSTRAINT IS ON THE TROUGH, and those differ by about
## a factor of two: the poke digs a dip and the dip then overshoots as the water rushes back. At
## 0.35 a raft over a 0.30 m fringe drew the column down to 0.106 m - a 65 % drawdown from a cap
## that says 35 %. It got WORSE when the grid was refined, which is the tell: dx 0.1429 dissipates
## less than dx 0.2, so more of the trough survives. A cap tuned against a coarse grid is a cap
## tuned against its numerical damping.
##
## 0.25 leaves the same fringe at about half its column, which is a boat sitting deep in shallow
## water rather than one about to punch through it.
const WAKE_BITE := 0.25                       ## most of the column one wake may displace


func wake(world_pos: Vector3, radius: float, want_m: float) -> void:
	var rip := _ripples()
	if rip == null:
		return
	var column := depth_at(world_pos)
	if column <= 0.01:
		return
	# The sign is the caller's: splash displaces DOWNWARD for a positive strength, so a hull pushing
	# water aside and a spring welling up both come through here and only the magnitude is capped.
	var cap := column * WAKE_BITE
	rip.call("splash", world_pos, radius, clampf(want_m, -cap, cap))


## THE SOLVER, BY PATH, AND IT CANNOT BE BY NAME. `Ripples` is declared AFTER `Water` in
## project.godot, and GDScript resolves autoload identifiers against the ones registered so far -
## so writing `Ripples.splash(...)` in this file fails to COMPILE, and an autoload whose script
## fails to compile is silently replaced by a bare Node. Every `Water.surface_y` in the game then
## becomes "nonexistent function in base Node". Nothing warns; the first symptom is the whole water
## layer gone.
##
## Swapping the two declarations only moves the break, because the dependency already runs the
## other way: ripple_field.gd calls Water.flow_at. One direction has to go through the tree, and it
## is this one - the solver may not know about the game, so the game is the side that reaches.
var _rip: Node = null


func _ripples() -> Node:
	if _rip == null or not is_instance_valid(_rip):
		_rip = get_node_or_null(^"/root/Ripples")
	return _rip

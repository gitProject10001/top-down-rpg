class_name SweTerrainOracle
extends SweTerrain
## THE GAME'S WORLD, presented to the solver through the three questions it actually asks.
##
## This is the ONLY file that knows both sides. It reads the `Water` autoload - which resolves
## whatever node currently holds group "water_oracle" and duck-types the wilds' contract onto it -
## and answers `SweTerrain`. Everything game-shaped stops here: the solver upstream of it has never
## heard of a tier, a painted flag or a region, and the wilds downstream of it have never heard of
## a face velocity.
##
## When a zone wants different water it writes a different SweTerrain, not a different solver.

## Where the world ends. The game's own constant, because on this side of the seam that is fine.
var wall := Water.BED_WALL


func bed_y(world: Vector3) -> float:
	if Water.oracle() == null:
		return wall
	return Water.bed_y(world)


## THE LEVEL, NOT THE DEPTH. The wilds contract answers `water_surface_y` in the oracle's own frame
## and NAN where a place has no water region, which is exactly this question - so it passes straight
## through. The solver derives depth as level minus bed and the two cannot disagree, which is a
## whole class of shoreline bug that does not exist when only one of them is stored.
func level_y(world: Vector3) -> float:
	if Water.oracle() == null:
		return NAN
	return Water.surface_y(world)


func is_spring(world: Vector3) -> bool:
	if Water.oracle() == null:
		return false
	return Water.is_spring(world)


## Is there a world to ask at all? The solver sleeps when there is not - a bench with no bed and a
## zone with no water should both cost nothing rather than simulating a kilometre of wall.
func present() -> bool:
	return Water.oracle() != null

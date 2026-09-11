class_name SweTerrain
extends RefCounted
## EVERYTHING THE SHALLOW-WATER SOLVER NEEDS TO KNOW ABOUT A WORLD, and it is three questions.
##
## The solver is general-purpose. It integrates depth over a bed and knows nothing about tiers,
## painted flags, regions, forests, zones or the wilds - and it must not learn, because the moment
## it does it stops being a solver and becomes this game's water. Caps, artistic limits and
## gameplay behaviour belong on top of it as policy, never inside it.
##
## So the seam is this class, and it is deliberately tiny:
##
##   bed_y(p)      the floor, in world Y, EVERYWHERE - including where there is no water and
##                 where there is no map. Off the world it should answer a value so high nothing
##                 can climb it, which is a reflecting wall the solver gets for free without
##                 anybody writing a boundary condition.
##   level_y(p)    the water level this place belongs to, in world Y, or NAN for "nowhere near
##                 water". This is what the solver seeds a full basin to and what it relaxes a
##                 window rim toward. It is a LEVEL, not a depth: depth is level minus bed, and
##                 deriving it here rather than storing it is what keeps the two from disagreeing.
##   is_spring(p)  does water enter here.
##
## That is the whole interface. A bench bed answers it analytically; the wilds answer it from a
## painted map; a future zone can answer it however it likes.
##
## THE DEFAULT IMPLEMENTATION IS A DRY WORLD, so a solver with no terrain attached does nothing
## rather than crashing or - worse - inventing water.


## The floor at a world position. Must never return NAN: the solver differences this channel, and
## a NAN propagates through max() into every neighbour.
func bed_y(_world: Vector3) -> float:
	return WALL


## The water level this position belongs to, or NAN where there is none.
func level_y(_world: Vector3) -> float:
	return NAN


func is_spring(_world: Vector3) -> bool:
	return false


## IS THERE A WORLD TO ASK AT ALL. A solver with nothing attached should cost nothing rather than
## simulate a kilometre of wall, so this gates the whole step. A terrain object that exists is
## present by virtue of existing; the game's adapter overrides it, because there the world can be
## absent while the adapter is not - a crypt has no water oracle in it.
func present() -> bool:
	return true


## THE OFF-WORLD FLOOR. Higher than any terrain a game is likely to build, so a solver reading it
## sees a floor it can never climb. Kept here rather than imported from the game's Water autoload,
## because a general solver cannot depend on a particular game's constants - that is the coupling
## this class exists to remove.
const WALL := 1000.0

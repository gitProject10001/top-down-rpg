@tool
class_name SimWaterSource
extends Node3D
## WATER IN OR OUT, AT A PLACE, authored by putting one of these in the scene.
##
## A spring, a drain, a pipe, a leak in a puzzle room's ceiling. Positive `rate` adds water and
## negative takes it away; the two are one node because they are one number and a sink is a source
## with a sign.
##
## WHY A NODE AND NOT MAP PAINT. The solver is general purpose and the wilds map is not - painting
## sources into WildsMap's pages would tie this addon to one game's map format, which is the
## coupling the whole SimTerrain seam exists to avoid. A node works in any scene, is visible and
## movable in the editor, and is how the raft and the waterfall already inject.
##
## ONE INJECTION PER SIM STEP, NEVER PER FRAME, and this is the important part.
##
## The obvious `_process(delta)` implementation is wrong in a way that is invisible until somebody
## profiles it: the solver advances on a FIXED 1/60 step and skips frames above that rate, so a
## source that fires every frame with a `delta`-scaled amount injects a different quantity on a fast
## machine than on a slow one. waterfall.gd does exactly that today and it was measured - the same
## drain probe returned +198 m3/min on one run and +62 on the next, purely because the physics tick
## and the sim step had drifted apart. Water that flows faster on a slower computer is not water.
##
## So this watches the solver's own step counter and injects exactly once per step it actually took,
## at exactly its fixed step size.

## Metres of water added per second over the disc. Negative drains.
@export_range(-2.0, 2.0, 0.01) var rate := 0.0
## Radius of the disc it acts over, in metres.
@export_range(0.1, 12.0, 0.1) var radius := 1.0
## Off without deleting it - a puzzle wants its flood to start on a lever, not on load.
@export var active := true

var _last_step := -1


func _ready() -> void:
	set_process(not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if not active or is_equal_approx(rate, 0.0):
		return
	var rip := _sim()
	if rip == null:
		return
	# THE SOLVER'S OWN CLOCK. debug_steps counts steps the sim actually took, so this fires once per
	# step and not once per frame - and skips entirely on a frame where the sim did not advance.
	var step := int(rip.get("debug_steps"))
	if step == _last_step:
		return
	_last_step = step
	# splash() displaces DOWNWARD for a positive strength - it is the drain's primitive - so a
	# source is a negative poke. The sign is inverted here rather than in the caller so `rate` reads
	# the way a person expects: positive adds water.
	rip.call("splash", global_position, radius, -rate * float(rip.get("STEP")))


## The driver, by path. Not by name: this addon must not assume the game registered the autoload
## under any particular identifier, and a source in a scene with no solver should do nothing rather
## than crash.
func _sim() -> Node:
	return get_tree().root.get_node_or_null(^"/root/Ripples") if is_inside_tree() else null

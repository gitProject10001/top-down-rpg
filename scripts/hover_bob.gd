extends Node3D
## The hover. The robot has no legs and no clips — its whole idle is this: a slow sine bob with a
## touch of roll, applied to the MODEL node so the parent Visuals stays clean for enemy.gd's
## facing writes (_face owns Visuals.rotation.y; two writers on one node is the fold-in-half trap
## the ogre refactor spent a week un-learning).

@export var bob_height := 0.12   ## metres of vertical travel either side of rest
@export var bob_hz := 0.55       ## full bob cycles per second
@export var sway_deg := 2.0      ## roll amplitude — half the bob's frequency, like a slow float

var _t := 0.0
var _base_y := 0.0

func _ready() -> void:
	_base_y = position.y

func _process(delta: float) -> void:
	_t += delta
	position.y = _base_y + sin(_t * TAU * bob_hz) * bob_height
	rotation.z = deg_to_rad(sway_deg) * sin(_t * TAU * bob_hz * 0.5)

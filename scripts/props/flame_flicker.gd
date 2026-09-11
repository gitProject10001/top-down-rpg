extends MeshInstance3D
## A FLAME THAT GUTTERS. The fire's light is a baked Static omni (its real-time energy would only
## reach the player, who would breathe while the walls did not), so the life is in the flame mesh
## alone: a little noise on its scale and a centimetre of wander, the hero torch's recipe
## (scripts/hero_torch.gd) without the light.

@export var amount := 0.08      ## scale swing, as a fraction
@export var rate := 7.0         ## Hz
@export var wander := 0.01      ## metres of positional jitter

var _noise := FastNoiseLite.new()
var _t := 0.0
var _base_scale := Vector3.ONE
var _base_pos := Vector3.ZERO


func _ready() -> void:
	_noise.seed = hash(global_position)
	_noise.frequency = 1.0
	_base_scale = scale
	_base_pos = position


func _process(delta: float) -> void:
	_t += delta * rate
	var n := _noise.get_noise_1d(_t)
	var m := _noise.get_noise_1d(_t + 100.0)
	scale = _base_scale * (1.0 + n * amount)
	position = _base_pos + Vector3(m, n, m * 0.5) * wander

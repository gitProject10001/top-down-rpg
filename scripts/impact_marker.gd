class_name ImpactMarker
extends Node3D
## The predicted point-of-impact ring shown on the ground while aiming a ballistic shot
## (blue for the player) and under incoming enemy arrows (red = get out of there).
##
## Ownership contract: whoever spawns it either frees it manually (player cancels the aim)
## or calls start_lifetime(flight_time) to let it outlive them and fade exactly when the
## arrow lands.

@export var color := Color(0.6, 0.85, 1.0)

@onready var _mesh: MeshInstance3D = $Ring

var _mat: StandardMaterial3D
var _t := 0.0

func _ready() -> void:
	# Per-instance material so player/enemy markers can differ in color.
	_mat = (_mesh.get_active_material(0) as StandardMaterial3D).duplicate()
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	_mat.emission = color
	_mesh.material_override = _mat

func _process(delta: float) -> void:
	_t += delta
	var pulse := 1.0 + 0.08 * sin(_t * 9.0)        # gentle breathing so it reads as "live"
	_mesh.scale = Vector3(pulse, 1.0, pulse)

## Fade out and free after `seconds` — call when the arrow is loosed, with its flight time.
func start_lifetime(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_interval(maxf(seconds - 0.1, 0.0))
	tw.tween_property(_mat, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(queue_free)

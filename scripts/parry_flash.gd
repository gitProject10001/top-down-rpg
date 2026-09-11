extends Node3D
## A short bright flash for a successful parry: a burst of light + particles that fades and frees.

func _ready() -> void:
	$Particles.emitting = true
	var t := create_tween()
	t.tween_property($Light, "light_energy", 0.0, 0.3).from(9.0)
	t.tween_callback(queue_free)

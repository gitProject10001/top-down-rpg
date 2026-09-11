class_name Bow
extends Node3D

@export var arrow_scene: PackedScene
@export var damage := 1
@export var arrow_color := Color(0.6, 0.85, 1.0)

func shoot(direction: Vector3, origin: Vector3) -> void:
	if arrow_scene == null:
		return
	var arrow := arrow_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = origin
	arrow.setup(direction, 4, damage, arrow_color)

func shoot_at(target: Vector3, origin: Vector3, h_speed := -1.0) -> float:
	if arrow_scene == null:
		return 0.0
	var arrow := arrow_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = origin
	return arrow.setup_ballistic(target, 4, damage, arrow_color, h_speed)

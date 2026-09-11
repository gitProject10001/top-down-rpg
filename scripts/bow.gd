class_name Bow
extends Node3D
## The player's ranged weapon component — the archery counterpart to Sword.
##
## Like Sword, it owns the "how" (spawn an arrow, give it the player's team mask) while the
## Shoot STATE owns the "when". Keeping it a component means swapping to a crossbow or a
## different projectile later is just a different scene here.

@export var arrow_scene: PackedScene       ## the Projectile to spawn (res://scenes/fx/arrow.tscn)
@export var damage := 1
@export var arrow_color := Color(0.6, 0.85, 1.0)   ## player shots read cool/blue

## Fire one arrow toward `direction`, starting at `origin` (world space). Straight shot.
func shoot(direction: Vector3, origin: Vector3) -> void:
	if arrow_scene == null:
		return
	var arrow := arrow_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = origin
	arrow.setup(direction, 4, damage, arrow_color)   # mask 4 = hit the ENEMY hurtbox layer

## Lob one arrow on a gravity arc that lands on `target`. `h_speed` = charge power (flatter
## and faster the higher it is; -1 = the arrow's default). Returns the flight time so the
## caller can keep the impact marker alive until the arrow actually lands.
func shoot_at(target: Vector3, origin: Vector3, h_speed := -1.0) -> float:
	if arrow_scene == null:
		return 0.0
	var arrow := arrow_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = origin
	return arrow.setup_ballistic(target, 4, damage, arrow_color, h_speed)

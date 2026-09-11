class_name Portal
extends Area3D
## Walk into this to travel to another zone. The destination is a scene PATH (loaded at runtime, so
## two zones can point at each other without a circular ExtResource dependency), and a spawn-marker
## name to arrive at in the destination.

@export_file("*.tscn") var target_zone_path: String
@export var target_spawn := "Spawn"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# group check + node lookup (not `is Player` / `World.`) so this script also compiles in the
	# autoload-less headless test environment (the dungeon suite instantiates portals)
	if body.is_in_group("player") and target_zone_path != "":
		var world := get_node_or_null("/root/World")
		if world:
			world.go_to(load(target_zone_path), target_spawn)

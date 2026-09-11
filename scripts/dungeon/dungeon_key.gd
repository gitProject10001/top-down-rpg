class_name DungeonKey
extends Area3D
## A key lying in a room. Walk over it and every gate barred by the same id opens.
##
## Deliberately dumb: it does not know which gates exist, it just tells the dungeon root (group
## "dungeon") that the key was taken. Lookups are by GROUP and get_node_or_null, never by autoload
## or by class, so the headless suite — which runs with no autoloads registered — can build and
## exercise this exactly like the real game does.

var key_id := "key_0"

var _taken := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1                            # the player's CharacterBody3D lives on layer 1
	monitorable = false
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# a small idle spin so a key on the floor reads as a pickup rather than clutter
	rotate_y(delta * 1.6)


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon and dungeon.has_method("grant_key"):
		dungeon.grant_key(key_id)
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.combat_impact.emit(0.2)               # the same sting a room-clear uses
	queue_free()

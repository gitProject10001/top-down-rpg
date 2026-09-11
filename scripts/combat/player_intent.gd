class_name PlayerIntent
extends FighterIntent

func _physics_process(_delta: float) -> void:
	move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	look = Vector2.ZERO
	guard = Input.is_action_pressed("block")
	attack_held = Input.is_action_pressed("attack") or Input.is_action_just_pressed("attack")

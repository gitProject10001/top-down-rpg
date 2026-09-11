extends CharacterBody2D
## Simple top-down 2D movement for the 2D-look test. WASD moves; the sprite flips to face left/right.
## Reuses the same Input Map actions as the 3D game (move_left/right/up/down).

@export var speed := 260.0

@onready var _sprite: Sprite2D = $Sprite

func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * speed
	move_and_slide()
	if absf(input.x) > 0.01:
		_sprite.flip_h = input.x < 0.0

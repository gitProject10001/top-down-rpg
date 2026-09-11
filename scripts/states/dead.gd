extends State
## Player is dead: freeze control. Respawn/checkpoints come in M5; for now we just stop and
## announce it on the EventBus so other systems (HUD, music) can react.

func enter() -> void:
	player.velocity = Vector3.ZERO
	EventBus.player_died.emit()

func physics_update(_delta: float) -> void:
	player.velocity = Vector3.ZERO
	player.move_and_slide()

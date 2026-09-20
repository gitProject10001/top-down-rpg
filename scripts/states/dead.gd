extends State
## Player is dead: freeze control. Respawn/checkpoints come in M5; for now we just stop and
## announce it on the EventBus so other systems (HUD, music) can react.

func enter() -> void:
	player.velocity = Vector3.ZERO
	if player.intent: player.intent.clear()
	if player.sword: player.sword.cancel_swing()
	player.set_tree_active(true)
	if player.has_clip("death"): player.play_clip("death")
	if player.is_input_driven():
		EventBus.player_died.emit()
	else:
		EventBus.enemy_died.emit(player)

func physics_update(_delta: float) -> void:
	player.velocity = Vector3.ZERO
	player.move_and_slide()

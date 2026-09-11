extends State
## Running. Drives the body toward the input direction while still facing the cursor
## (so you can strafe — move one way, aim another, like Death's Door combat).
## Returns to Idle when there's no movement input.

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.face_aim_direction(delta)

	var input := player.get_move_input()
	if input == Vector2.ZERO:
		fsm.transition_to("Idle")
		return

	player.apply_movement(input, delta)
	player.move_and_slide()

	# THE DIRECTIONAL PAIR, polled rather than event-driven. A body a brain is driving receives no
	# InputEvents at all (state_machine.gd stops them), so the two states the duelist shares with
	# the player have to be reachable from the intent both of them write. PlayerIntent latches the
	# press, so a person loses no responsiveness by coming through here.
	if player.intent:
		if fsm.has_state("DirAttack") and player.intent.can_start_attack() and player.stamina>=12.0:
			fsm.transition_to("DirAttack")
			return
		if fsm.has_state("Guard") and player.intent.guard and player.can_block():
			fsm.transition_to("Guard")
			return

func handle_input(event: InputEvent) -> void:
	# Gated: a body carrying DirAttack/Guard reaches them by polling the intent above, and would
	# otherwise ALSO take the click-combo path on the very same press.
	if event.is_action_pressed("attack") and not fsm.has_state("DirAttack"):
		fsm.transition_to("Attack")
	elif event.is_action_pressed("shoot") and player.can_shoot():
		fsm.transition_to("Shoot")
	elif event.is_action_pressed("dash") and player.can_dash():
		# Dash with attack HELD = the lunge, on a body that has one. See dash_attack.gd.
		if Input.is_action_pressed("attack") and fsm.has_state("DashAttack"):
			fsm.transition_to("DashAttack")
		else:
			fsm.transition_to("Dash")
	elif event.is_action_pressed("block") and player.can_block() and not fsm.has_state("Guard"):
		fsm.transition_to("Block")
	elif event.is_action_pressed("jump") and player.is_on_floor() and fsm.has_state("Jump"):
		fsm.transition_to("Jump")

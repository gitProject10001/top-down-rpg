extends State
## A quick burst with invulnerability frames (the Death's Door dodge).
##
## i-frames are a Health flag, NOT magic local to the dash: we flip player.health.invulnerable on
## for the burst and off at the end. Every future i-frame source (parry, get-up) reuses that switch,
## so damage handling stays in one place.

@export var dash_speed := 16.0
@export var dash_time := 0.18
@export var trail_width := 1.0     ## metres across the dodge smear
@export var trail_height := -0.85  ## smear height on the player (root is capsule-centred, feet
                                   ## at -1.07) — just clear of the floor, so it reads as a skid

var _elapsed := 0.0
var _dir := Vector3.ZERO

func enter() -> void:
	_elapsed = 0.0
	# Dash toward movement input if any, else straight ahead (where we're facing).
	var input := player.get_move_input()
	if input != Vector2.ZERO:
		_dir = Vector3(input.x, 0.0, input.y).normalized()
	else:
		_dir = -player.visuals.global_transform.basis.z
		_dir.y = 0.0
		_dir = _dir.normalized()
	player.health.set_invulnerable(true)
	player.start_dash_cooldown()
	# Lay the smear FLAT in the ground plane, across the dash direction.
	#
	# A ribbon's surface is spanned by its own axis and the path it sweeps, so there are exactly
	# two choices: UPRIGHT (axis vertical) or FLAT (axis horizontal, across travel). Under a fixed
	# ~53 deg camera the flat one is not a preference, it is the only correct answer: the ground
	# plane's normal sits at a constant angle to the view, so a flat ribbon shows the same
	# sin(53) = 0.80 of its area whichever way you dash. An upright ribbon's normal is horizontal,
	# so it falls from 0.60 to EXACTLY ZERO as the dash turns toward or away from the camera —
	# dashing "up" or "down" the screen drew the smear as a bare line. World-space area is not
	# screen-space area; only the second one is visible.
	#
	# _dir is constant for the whole dash, so orienting once here costs nothing per frame.
	var across := _dir.cross(Vector3.UP).normalized() * (trail_width * 0.5)
	var mid := Vector3(0.0, trail_height, 0.0)
	player.dash_trail.span(mid - across, mid + across)
	# The smear is the i-frame TELL. It is on for exactly as long as invulnerability is, so what
	# the player sees and what the damage code does are the same fact — the reason it is switched
	# here beside set_invulnerable() rather than anywhere else.
	player.dash_trail.hold()

func physics_update(delta: float) -> void:
	_elapsed += delta
	var speed := dash_speed * (1.0 - 0.4 * (_elapsed / dash_time))   # slight decel
	player.velocity.x = _dir.x * speed
	player.velocity.z = _dir.z * speed
	player.apply_gravity(delta)
	player.move_and_slide()
	if _elapsed >= dash_time:
		# a press buffered mid-dash flows straight into the swing (dash -> attack, no dead frame)
		if player.consume_attack_buffer():
			fsm.transition_to("DirAttack" if fsm.has_state("DirAttack") else "Attack")
		else:
			fsm.transition_to("Move" if player.get_move_input() != Vector2.ZERO else "Idle")

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		# Pressed EARLY, on a body that has a lunge, the dodge converts into one — that is the
		# "dash attack" as most players will try to perform it. Pressed late (or on player/player2,
		# which have no DashAttack) it just buffers into the normal combo on exit, as before.
		if _elapsed < dash_time * 0.5 and fsm.has_state("DashAttack"):
			fsm.transition_to("DashAttack")
		else:
			player.buffer_attack()           # can't swing mid-dash — remember it for the exit

func exit() -> void:
	player.health.set_invulnerable(false)   # always drop i-frames when leaving the dash
	# INSTINCT BUYS TIME, NOT DISTANCE. The window is extended past the dash rather than by making
	# `dash_time` bigger, because dash_time is doing two other jobs — it shapes the deceleration
	# curve (line 51) and it sets how early a press converts the dodge into a lunge (line 68). Scale
	# it and a high-Instinct player silently gets a floatier dash and a different lunge window.
	#
	# It goes through the DEADLINE rather than a timer here, because `invulnerable` is a plain bool
	# with four writers: a dash that converts into a lunge would have dash_attack.gd clear a flag
	# this state was still meant to be holding. A deadline nobody else can clear survives that.
	var traits := player.get_node_or_null("/root/Traits")
	if traits:
		var extra: float = dash_time * maxf(float(traits.iframe_scale()) - 1.0, 0.0)
		player.health.extend_invulnerable(extra)
		player.dash_trail.stop(0.14 + extra)   # the tell still ends exactly when the i-frames do
		return
	player.dash_trail.stop(0.14)            # ...and the tell fades with them

extends State
## The lunge: a dash that carries the blade with it (Quaternius' Sword_Dash).
##
## WHY A STATE OF ITS OWN, and not "Dash then Attack". The plain Dash is a DEFENSIVE move — it
## grants i-frames, it goes wherever you steer, and dash.gd already flows into a normal swing on
## exit. This is the opposite: an OFFENSIVE commitment. It locks its direction at the press, it
## covers ground on the animation's own schedule rather than a fixed burst, and the damage window
## opens mid-travel so the hit lands on someone you closed the distance to. Two different intents
## sharing one state would mean a flag threaded through every branch of both.
##
## THE MOTION COMES FROM THE CLIP'S SHAPE, NOT FROM THE CLIP. The animation was exported without
## root motion (see the extractor's header), so the body would travel nowhere if we just played it.
## Instead the state drives the capsule along a lunge curve — fast at the plant, decaying through
## the follow-through — and the clip supplies the pose. That also keeps the distance covered a
## GAMEPLAY number you can tune here, rather than something baked into an .res file.
##
## I-frames run through the wind-up and the strike but END with the recovery, so the lunge is a
## trade you can lose: commit late and you eat the counter-hit during the tail.

@export var clip := "atk_dash"     ## the lunge animation (player3: UAL Sword_Dash)
@export var lunge_speed := 15.0    ## peak travel speed at the plant (m/s)
## How sharply the lunge decays. Measured: 2.6 covered 4.0 m and spent its last twenty frames
## crawling under 2 m/s — a visible skate with no weight behind it. 4.5 lands ~2.7 m, close to the
## plain dash's reach, and is near a standstill by the time the recovery plays.
@export var lunge_curve := 4.5
@export var strike := 0.34         ## fallback contact point, if the clip has no attack_timing entry
@export var iframe_end := 0.55     ## fraction of the clip where invulnerability drops
@export var hit_dur := 0.14        ## seconds the hitbox stays live
@export var steer := 0.12          ## how much late steering is allowed (0 = fully committed)
## How far ahead the lunge will commit to a target, beyond normal contact range. Measured at 2.6 m
## of travel (see the header), so anything inside that is genuinely reachable — this is not aim
## assist reaching for things the state cannot get to.
@export var lunge_reach := 2.6

var _t := 0.0
var _len := 0.5
var _dir := Vector3.ZERO
var _hit := false
var _strike := 0.34               ## post-warp contact fraction (see _resolve_strike)


func enter() -> void:
	_t = 0.0
	_hit = false
	# Lunge toward the TARGET if there is one, the cursor otherwise — never the movement keys. This
	# is an aimed attack: you throw yourself at something. (The plain Dash does the reverse; it goes
	# where you steer, because escaping is about direction of travel, not of intent.)
	#
	# The acquisition radius is the lunge's own reach, not a swing's: it covers the whole distance
	# this state can cross under its own power, so committing to something across the room is a
	# decision the lunge can actually honour.
	var target := player.acquire_target(
			player.contact_range(null) + lunge_reach, player.target_arc)
	var to_aim: Vector3
	if target:
		player.face_point(target.global_position, 0.2)
		to_aim = target.global_position - player.global_position
	else:
		player.face_aim_direction(0.2, true)
		to_aim = player.aim_point() - player.global_position
	to_aim.y = 0.0
	if to_aim.length_squared() > 0.0001:
		_dir = to_aim.normalized()
	else:
		_dir = -player.visuals.global_transform.basis.z
		_dir.y = 0.0
		_dir = _dir.normalized()

	player.health.set_invulnerable(true)
	player.start_dash_cooldown()
	_len = player.play_attack(clip)
	# If the clip has an attack_timing entry it was retimed at load (sped up, wind-up compressed),
	# so the authored `strike` fraction no longer points at contact. attack_meta holds the POST-warp
	# fraction — the same number the combo reads, so lunge and combo can never drift apart.
	_strike = player.attack_meta.get(clip, {}).get("strike", strike)
	if player.sword:
		player.sword.begin_swing(0, _len)
	# The same flat ground-plane smear the dodge uses — see dash.gd for why it is never upright.
	if player.dash_trail:
		var across := _dir.cross(Vector3.UP).normalized() * 0.5
		player.dash_trail.span(Vector3(0.0, -0.85, 0.0) - across, Vector3(0.0, -0.85, 0.0) + across)
		player.dash_trail.hold()


func physics_update(delta: float) -> void:
	_t += delta
	var f := _t / maxf(_len, 0.01)

	# Late steering, heavily damped: enough that the lunge doesn't feel like it's on rails, not
	# enough to turn it into a homing move.
	if steer > 0.0:
		var input := player.get_move_input()
		if input != Vector2.ZERO:
			_dir = _dir.lerp(Vector3(input.x, 0.0, input.y).normalized(), steer * delta * 10.0).normalized()

	# exp decay: most of the ground is covered before the blade lands, so the hit reads as the
	# END of the travel rather than something that happens while still sliding.
	var speed := lunge_speed * exp(-lunge_curve * f)
	player.velocity.x = _dir.x * speed
	player.velocity.z = _dir.z * speed
	player.apply_gravity(delta)
	player.move_and_slide()

	if not _hit and f >= _strike:
		if player.sword:
			player.sword.hit(hit_dur, false, player.swing_damage())
		_hit = true

	if f >= iframe_end:
		player.health.set_invulnerable(false)

	if f >= 1.0:
		# A press buffered during the lunge flows into the normal combo — the lunge is an OPENER.
		if player.consume_attack_buffer():
			fsm.transition_to("Attack")
		else:
			fsm.transition_to("Move" if player.get_move_input() != Vector2.ZERO else "Idle")


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		player.buffer_attack()             # chain out of the lunge into the sword combo


func exit() -> void:
	player.health.set_invulnerable(false)  # belt and braces: never leave i-frames on
	if player.dash_trail:
		player.dash_trail.stop(0.14)

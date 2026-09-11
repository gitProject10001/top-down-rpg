extends State
## THE DIRECTIONAL GUARD — the defensive half of the Bannerlord mechanic.
##
## Holding the guard button raises the sword; the right stick (or a flick of the mouse) chooses
## WHICH WAY it is held. A strike is stopped only if the guard is pointing the way the strike came
## from. Get it wrong and the blow lands in full: there is no partial credit, because a guard that
## half-works is a guard you do not have to aim.
##
## WHY THIS REPLACED THE OMNI-GUARD. The older guard answered any frontal hit inside a 75-degree
## cone with no direction to it. This one is a strict superset: a directionless hit still falls
## through to that same behaviour, so nothing that already worked had to change to make room.
##
## HEAVY, ON PURPOSE. Guarding costs you the ground: move_scale drops you to a walk, and the body
## locks its facing onto whatever it has acquired instead of tracking the cursor. Between the two,
## a guarded fighter cannot casually reposition — which is the point. Position is the resource the
## mechanic spends, and it only reads as a resource if raising the guard makes it expensive.

const GUARD_CLIP := "block"

@export var parry_window := 0.24   ## Includes the 0.12 s needed to physically raise the guard.
@export var move_scale := 0.4      ## fraction of run speed you can shuffle while guarding
@export var raise_speed := 16.0    ## how fast the arm eases into a new direction

## THE MIRROR. A swing thrown from the attacker's left arrives on the defender's right, so the two
## frames disagree by a flip on exactly one axis. See SwingDir's header for why it lives there and
## why it must be applied here and nowhere else. Off = block the direction the attacker named.
@export var mirror_incoming := true

## How far out the guard will look for something to face. Beyond this it holds the cursor's
## direction instead — locking onto a distant enemy while you fight a near one is worse than not
## locking at all.
@export var face_lock_range := 6.0

var _t := 0.0
var _dir := SwingDir.UP
var _blend := 0.0
var _switch_time:=0.0


func enter() -> void:
	_t = 0.0
	_blend = 0.0
	_switch_time=.12
	_dir = player.intent.guard_dir
	if player.shield:
		player.shield.raise()
	elif player.has_clip(GUARD_CLIP):
		player.play_clip(GUARD_CLIP)


func exit() -> void:
	if player.shield:
		player.shield.lower()
	if player.guard_pose:
		player.guard_pose.amount = 0.0
		player.guard_pose.dir = SwingDir.NONE


func physics_update(delta: float) -> void:
	_t += delta
	if _dir != player.intent.guard_dir:
		_dir=player.intent.guard_dir
		_switch_time=.12
	_switch_time=maxf(0.0,_switch_time-delta)
	if player.guard_pose:
		player.guard_pose.dir = _dir
		# Frame-rate independent easing, the same form used everywhere else in this project. A
		# snap would make every direction change read as a teleport, and the whole reason the
		# opponent can beat your guard is that MOVING it takes time.
		_blend = lerpf(_blend, 1.0, 1.0 - exp(-raise_speed * delta))
		player.guard_pose.amount = _blend

	player.apply_gravity(delta)
	player.apply_movement(player.get_move_input(), delta, move_scale)

	# THE FACING LOCK. A guard tracking the cursor lets you hold a direction while pointing
	# somewhere else, and then "which way did that come from" stops being a question about the
	# fight and becomes a question about your mouse. Locked onto the opponent, the only thing the
	# guard direction can mean is the guard direction.
	var target := player.acquire_target(face_lock_range, 180.0)
	if target:
		player.face_point(target.global_position, delta)
	else:
		player.face_aim_direction(delta)
	player.move_and_slide()

	# ATTACK OUT OF THE GUARD, without dropping it first. Bannerlord's exchanges are guard-swing-
	# guard with no neutral in between, and routing back through Idle would put a dead frame in
	# the middle of every riposte.
	if player.intent.can_start_attack() and fsm.has_state("DirAttack") and player.stamina>=12.0:
		fsm.transition_to("DirAttack")
		return

	# release, or GUARD BREAK when the stamina runs dry
	if not player.intent.guard or player.stamina <= 0.0:
		fsm.transition_to("Move" if player.get_move_input() != Vector2.ZERO else "Idle")


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("dash") and player.can_dash():
		fsm.transition_to("Dash")
	# Jump-cancel, mirroring the dash-cancel: the ground wave deliberately ignores the guard
	# ("ground wave = JUMP" is taught on screen), so the escape it teaches must be reachable
	# WHILE guarding.
	elif event.is_action_pressed("jump") and player.is_on_floor() and fsm.has_state("Jump"):
		fsm.transition_to("Jump")


## WHICH WAY THE GUARD IS POINTING, in the DEFENDER's own frame. player.on_incoming_hit compares
## this against the direction stamped on the incoming hitbox.
func guard_dir() -> int:
	return _dir


## Does this guard answer a swing thrown in `attack_dir` (the ATTACKER's frame)?
func blocks(attack_dir: int) -> bool:
	if _switch_time>0.0 or _blend<.65: return false
	if attack_dir == SwingDir.NONE or _dir == SwingDir.NONE:
		return false
	return _dir == (SwingDir.mirror(attack_dir) if mirror_incoming else attack_dir)


## The player checks this when hit to decide block vs parry. Only reached on a MATCHED guard —
## a parry is a perfectly-timed correct block, never a reward for guessing wrong quickly.
func is_parry_active() -> bool:
	return _t < parry_window

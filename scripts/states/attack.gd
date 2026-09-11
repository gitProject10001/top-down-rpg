extends State
## A click-chained looping melee combo (horizontal → backhand → downward → repeat).
##
## Built on the Death's Door pattern (docs/deaths-door-study.md): per-clip strike/cancel timing,
## input buffering, and — the key — THE RECOVERY TAIL ONLY PLAYS IF YOU DON'T CHAIN. A buffered
## press consumed just after the strike jumps to the next swing (skipping the recovery); no press
## = the recovery plays as the natural combo ender. One click = one full swing; mashing loops the
## chain endlessly; dash cancels out at any time.

## The combo ORDER. Strike/cancel timing lives with the clip processing in player.gd
## (attack_timing authored on the original clips, then wind-up-compressed at load) — the state
## reads the POST-warp fractions from player.attack_meta, so gameplay and animation always agree.
##
## Exported because the clips differ per body: the Mixamo set below for player/player2, Quaternius'
## atk_a/atk_b/atk_c for player3. Whatever is listed here must also have an entry in that player's
## attack_timing, or the swing falls back to untimed defaults.
@export var chain: PackedStringArray = ["atk_h", "atk_b", "atk_d"]

@export var move_scale := 0.35     ## fraction of run speed you can drift while swinging
@export var hit_dur := 0.12        ## seconds the hitbox stays live

## THE ATTACK STEP — the "little dash" into a swing.
##
## Measured before it existed (tools/measure_attack.gd): contact ends at 2.08 m, and at 2.10 m the
## swing misses by 16 mm. Nothing tells the player that, so they swing from the same spot again and
## miss again — which is exactly the complaint this answers. Worse, the box's corner reaches
## further than its face, so dead-ahead is the WORST angle: 2.10 m whiffs at 0 degrees and connects
## at 20.
##
## So a swing that has acquired a target turns exactly at it and closes whatever gap is left,
## arriving at contact ON the strike frame rather than sliding in afterwards. The step is capped
## (player.attack_step_max) so it stays a step and never a teleport, and it aims `step_lead` INSIDE
## the envelope rather than at its lip — landing on a 16 mm margin is the bug, not the fix.
##
## With no target acquired nothing happens here at all: the swing goes where the cursor pointed and
## misses if it deserves to. Assistance that turns deliberate whiffs into hits is worse than none.
@export var step_lead := 0.85      ## aim this fraction into the envelope, not at its edge

## What fraction of your incoming speed a swing carries through its wind-up when there is NOTHING
## to step toward. Without this, clicking mid-run drops you from 6 m/s to 2.1 m/s in a tenth of a
## second — the body plants, the camera keeps up, and it reads as the game taking the controls
## away. It also strands you short of anything you were closing on. 0 restores the old dead stop.
@export var momentum_carry := 0.55

## THE OPENER. When the first swing of a chain has real ground to cover, play a clip that actually
## DEPICTS covering it.
##
## The step above solved the geometry but not the animation: atk_a is a stationary swing, so closing
## a metre inside it slides the body across the floor with the feet planted. Quaternius ships
## Sword_Dash — a lunge — and using it exactly where a lunge is what happens makes the movement
## honest. It is the same step underneath; only the pose changes.
##
## ONLY WHEN FAR, and only on the FIRST swing. Once you are inside the envelope the chain is the
## ordinary atk_a/atk_b/atk_c: a lunge from point-blank range would look ridiculous and would rob
## the combo of its fast opener. Empty disables this entirely, which is how player/player2 keep
## their behaviour — they have no lunge clip to reach for.
@export var opener_clip := ""
@export var opener_min_gap := 0.3  ## metres short of contact before the lunge is worth playing

var _step := 0
var _t := 0.0
var _len := 0.4
var _strike := 0.4
var _cancel := 0.55
var _hit := false
var _queued := false
var _target: Node3D
var _clip := ""                    ## the clip this swing is actually playing (may be the opener)
var _step_vel := Vector3.ZERO
var _step_until := 0.0             ## seconds into the clip that the step keeps driving


func enter() -> void:
	_step = 0
	_start_step()


func _start_step() -> void:
	_t = 0.0
	_hit = false
	_queued = false

	# TARGET FIRST, then the clip. Which animation this swing should be depends on how much ground
	# it has to cover, so the acquisition cannot wait until after play_attack the way it used to.
	#
	# Re-acquired EVERY swing, not held for the whole combo: mid-chain the first target may be dead,
	# knocked away, or no longer the one you mean. A lock that outlives its reason is how a combo
	# ends up swinging at a corpse while something else hits you.
	_target = player.acquire_target(
			player.contact_range(null) + player.attack_step_max, player.target_arc)
	if _target:
		player.face_point(_target.global_position, 0.25)
	else:
		player.face_aim_direction(0.25, true)    # no target: the cursor is the whole truth

	_clip = chain[_step]
	if _step == 0 and opener_clip != "" and _gap_to_target() > opener_min_gap:
		_clip = opener_clip
	_len = player.play_attack(_clip)
	var meta: Dictionary = player.attack_meta.get(_clip, {"strike": 0.4, "cancel": 0.55})
	_strike = meta.strike
	_cancel = meta.cancel
	_aim_step()
	player.sword.begin_swing(_step, _len)        # blade glow + streak (the crescent fires with the hit)


## How far short of contact this swing is, in metres. Negative means already inside the envelope;
## -INF means there is nothing to be short of.
func _gap_to_target() -> float:
	if _target == null:
		return -INF
	var to: Vector3 = _target.global_position - player.global_position
	to.y = 0.0
	return to.length() - player.contact_range(_target) * step_lead


## Work out the step for THIS swing: how far short of contact we are, and how fast to close it so
## we arrive as the blade lands rather than after.
func _aim_step() -> void:
	_step_vel = Vector3.ZERO
	_step_until = 0.0
	var incoming := Vector3(player.velocity.x, 0.0, player.velocity.z)

	if _target == null:
		# Nothing to close on: carry the run through the wind-up instead of planting. This is the
		# "velocity" half of the problem — the distance half is the step below.
		if momentum_carry > 0.0 and incoming.length() > 0.5:
			_step_vel = incoming * momentum_carry
			_step_until = _len * _strike
		return

	var to: Vector3 = _target.global_position - player.global_position
	to.y = 0.0
	var gap: float = _gap_to_target()
	if gap <= 0.0:
		return                                   # already inside the envelope; a swing plants
	gap = minf(gap, player.attack_step_max)
	# Seconds from now until the blade connects. Everything the step has to do, it does in here —
	# past the strike a step only pushes you through the target.
	var windup: float = maxf(_len * _strike, 0.05)
	_step_vel = to.normalized() * minf(gap / windup, player.attack_step_speed)
	_step_until = _len * _strike


func physics_update(delta: float) -> void:
	_t += delta
	player.apply_gravity(delta)
	if _t < _step_until:
		# The step OWNS the body until contact. Running apply_movement here instead is what made a
		# running attack lurch to a near-stop: it decelerates 6 m/s to 2.1 m/s in a tenth of a
		# second, which both kills the momentum and leaves you short of the target you were
		# closing on. Driving velocity directly keeps the swing travelling.
		player.velocity.x = _step_vel.x
		player.velocity.z = _step_vel.z
	else:
		player.apply_movement(player.get_move_input(), delta, move_scale)  # slow drift, mobile combat
	player.move_and_slide()

	var f := _t / maxf(_len, 0.01)
	if not _hit and f >= _strike:
		# damage window + slash crescent together, at this clip's strike moment
		player.sword.hit(hit_dur, _step % 2 == 0, player.swing_damage())
		_hit = true

	# A buffered press past this clip's cancel point chains into the next swing, skipping the
	# recovery tail; the chain WRAPS (…-> atk_d -> atk_h -> …) so mashing keeps the flurry going.
	# Only an un-queued swing plays its recovery — the natural combo ender.
	if _queued and _hit and f >= _cancel:
		_step = (_step + 1) % chain.size()
		_start_step()
	elif _hit and f >= _cancel and player.get_move_input() != Vector2.ZERO:
		# MOVE-CANCEL. Past the cancel point the hit has already landed, so the rest is pure
		# recovery — let walking break out of it. This is the single biggest responsiveness win:
		# the player is never stuck watching an animation they have finished paying for. It does
		# NOT enable spam, because it grants no extra attacks, only the freedom to reposition.
		fsm.transition_to("Move")
	elif f >= 1.0:
		fsm.transition_to("Move" if player.get_move_input() != Vector2.ZERO else "Idle")


func handle_input(event: InputEvent) -> void:
	# DASH-CANCEL, BUT NOT BEFORE THE SWING HAS COMMITTED. Cancelling out of a swing you have not
	# yet thrown makes an attack free: you can open on anything, see what it does, and leave before
	# paying for the look. This game has no stamina -- a deliberate choice, and the right one -- but
	# removing stamina obliges you to replace what it did, and one of the two things it did was make
	# attacking a commitment. Death's Door's replacement is exactly this: the swing's early frames
	# cannot be cancelled, so how much of the combo to spend is a decision rather than a reflex.
	#
	# After `_hit` it is free again, which is what keeps the combo fluid instead of trapping.
	if event.is_action_pressed("dash") and player.can_dash() and _hit:
		fsm.transition_to("Dash")                # dash-cancel out of the combo
	elif event.is_action_pressed("attack"):
		_queued = true                           # buffer the next swing

extends State
## Tap: a buffered three-hit phrase. Hold: the same directional charge and feint.
## Every follow-up needs a new press; the finisher ends the phrase. Directions
## still travel with the visible blade, so guard/interception keep their rules.
signal combo_step_started(index: int, direction: int, clip: String)
signal damage_window_opened(index: int, duration: float)

## THE CLIP PER DIRECTION, indexed by SwingDir (up, down, left, right). All four already exist in
## player3_anims.tres: an overhead chop, a thrust, and two side swings.
## Whatever is listed here must also have an entry in that body's attack_timing, or
## the swing falls back to untimed defaults and its strike frame is a guess.
@export var dir_clips: PackedStringArray = ["atk_c", "atk_cross", "atk_b", "atk_swing"]

@export var move_scale := 0.48     ## fraction of run speed you can drift while winding up
@export var hit_dur := 0.12        ## seconds the hitbox stays live
@export var hold_max := 1.2        ## seconds the swing may hang at the apex before it falls anyway

## THE ROOT. Velocity kept during the strike itself: a swing plants you. Without this the
## directional game collapses into a running blender, because the safest place to be is always
## inside someone who cannot turn as fast as you can circle. 0 would freeze the body outright,
## which reads as the game taking the controls away — 0.15 is "committed", not "paralysed".
@export var root_speed := 0.15

@export var recoil_time := 0.45    ## how long a blocked swing leaves you open
@export var contact_assist_distance := 0.10
@export var contact_assist_angle := 5.0
@export var contact_assist_range := 1.50
@export var contact_assist_time := .16
@export_group("Tap combo")
@export var combo_contact_times := PackedFloat32Array([0.15, 0.21, 0.30])
@export var combo_hit_windows := PackedFloat32Array([0.10, 0.11, 0.14])
@export var combo_step_distances := PackedFloat32Array([0.28, 0.22, 0.36])
@export var combo_stamina_costs := PackedFloat32Array([12.0, 9.0, 14.0])
@export var combo_buffer_time := 0.35
@export var dodge_buffer_time := 0.20

enum Phase { WINDUP, HOLD, SWING, RECOIL }

var _phase := Phase.WINDUP
var _dir := SwingDir.UP
var _t := 0.0
var _hold := 0.0
var _recoil := 0.0
var _len := 0.4
var _strike := 0.4
var _cancel := 0.55
var _hit := false
var _wants_release := false   ## let go before the apex; the swing falls the moment it gets there
var _clip := ""
var _target: Node3D
var _assist_elapsed := 0.0
var _assist_travel := 0.0
var _assist_turn := 0.0
var _step := 0
var _human_combo := false
var _input_dir := SwingDir.RIGHT
var _queued_dir := SwingDir.NONE
var _queued_left := 0.0
var _dodge_left := 0.0
var _window_time := 0.12
var _dodge_at := 0.0
var _lunge_dir := Vector3.ZERO
var _lunge_left := 0.0
var _drift_velocity := Vector2.ZERO


func enter() -> void:
	_step = 0
	_human_combo = player.intent is PlayerIntent
	_queued_left = 0.0
	_dodge_left = 0.0
	_recoil = 0.0
	_assist_elapsed = 0.0
	_assist_travel = 0.0
	_assist_turn = 0.0
	player.intent.consume_attack()
	player.stamina=maxf(0.0,player.stamina-_step_value(combo_stamina_costs, 12.0))
	_input_dir = player.intent.attack_dir
	_begin(player.intent.attack_dir)


func exit() -> void:
	player.sword.cancel_swing()
	_queued_left = 0.0
	_dodge_left = 0.0
	_lunge_left = 0.0
	if player.intent is PlayerIntent:
		(player.intent as PlayerIntent).consume_combo_press()
	if player.guard_pose:
		player.guard_pose.amount = 0.0
		player.guard_pose.dir = SwingDir.NONE
	# Every interruption restores the animation clock, including hurt and death.
	player.set_attack_playback_speed(1.0)


func _begin(dir: int) -> void:
	_phase = Phase.WINDUP
	_t = 0.0
	_hold = 0.0
	_hit = false
	_wants_release = not player.intent.attack_held
	_dir = dir if dir != SwingDir.NONE else SwingDir.UP
	player.set_tree_active(true)

	# This target only supplies the existing bounded early windup assistance.
	# The swing direction and the released step never track a target.
	_target = player.acquire_target(contact_assist_range, contact_assist_angle)

	_clip = dir_clips[_dir] if _dir < dir_clips.size() else dir_clips[0]
	_len = player.play_attack(_clip)
	var meta: Dictionary = player.attack_meta.get(_clip, {"strike": 0.4, "cancel": 0.55})
	_strike = meta.strike
	_cancel = meta.cancel
	_window_time = maxf(0.04, _len * (.78 - _strike))
	if _human_combo:
		var clip_length := _len
		_len = maxf(0.36, _step_value(combo_contact_times, 0.20) / maxf(_strike, 0.10))
		_window_time = _step_value(combo_hit_windows, hit_dur)
		var contact := _len * _strike
		var recovery := 0.12 if _step == 2 else 0.045
		_cancel = minf(0.96, (contact + _window_time + recovery) / _len)
		player.set_attack_playback_speed(clip_length / _len)
	_dodge_at = _len * _strike + _window_time + (0.025 if _human_combo else 0.08)
	_lunge_left = 0.0
	combo_step_started.emit(_step, _dir, _clip)

func _step_value(values: PackedFloat32Array, fallback: float, index := -1) -> float:
	var selected := _step if index < 0 else index
	return values[mini(selected, values.size() - 1)] if not values.is_empty() else fallback

func combo_index() -> int:
	return _step

func _capture_buffer(delta: float) -> void:
	_queued_left = maxf(0.0, _queued_left - delta)
	_dodge_left = maxf(0.0, _dodge_left - delta)
	if not _human_combo:
		return
	var intent := player.intent as PlayerIntent
	if intent.consume_combo_press() and _phase != Phase.RECOIL and _step < 2:
		_queued_left = combo_buffer_time
		_queued_dir = intent.attack_dir

func _next_step() -> void:
	_step += 1
	_queued_left = 0.0
	player.intent.consume_attack()
	player.stamina = maxf(0.0, player.stamina - _step_value(combo_stamina_costs, 12.0))
	# Unchanged input follows a backhand then overhead phrase. A deliberate new
	# direction overrides it; moving the mouse while holding can still feint.
	var direction := _queued_dir
	if direction == _input_dir or direction == SwingDir.NONE:
		direction = (SwingDir.LEFT if _dir != SwingDir.LEFT else SwingDir.RIGHT) if _step == 1 else SwingDir.UP
	_input_dir = player.intent.attack_dir
	_begin(direction)


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	_assist_elapsed += delta
	_capture_buffer(delta)

	match _phase:
		Phase.WINDUP:
			_tick_windup(delta)
		Phase.HOLD:
			_tick_hold(delta)
		Phase.SWING:
			_tick_swing(delta)
		Phase.RECOIL:
			_tick_recoil(delta)

	player.move_and_slide()


func _tick_windup(delta: float) -> void:
	_t += delta
	player.apply_movement(player.get_move_input(), delta, move_scale)
	_face(delta)

	if _rewound():
		return
	# A RELEASE DURING THE WIND-UP IS REMEMBERED, NOT OBEYED. Throwing on the frame the button came
	# up would let a quick click skip straight to the strike with no telegraph at all — a swing
	# nobody can read, which is the one thing this whole mechanic cannot allow. The wind-up is the
	# price of the blow, and letting go early only means it falls the instant it is paid.
	if not _wants_release and (player.intent.consume_release() or not player.intent.attack_held):
		_wants_release = true
	if _t >= _len * _strike * .60:
		if _wants_release:
			_throw()
			return
		# Still holding at the top of the swing: hang there.
		_phase = Phase.HOLD
		_hold = 0.0
		player.set_tree_active(false)


## Hold the animation clock, but keep evaluating its pose for the skeleton modifiers.
func _tick_hold(delta: float) -> void:
	# Evaluate the frozen pose every tick so SkeletonModifier3D gets an animated
	# base, not a restored rest pose after its previous modification is rolled back.
	player.evaluate_held_pose()
	_hold += delta
	player.stamina=maxf(0.0,player.stamina-8.0*delta)
	player.apply_movement(player.get_move_input(), delta, move_scale)
	_face(delta)

	if _rewound():
		return
	if _released():
		return
	# Held too long. The swing falls anyway rather than hanging forever: an indefinite hold is a
	# stance, and a stance you can hold for free is not a commitment.
	if _hold >= hold_max or player.stamina<=0.0:
		_throw()


## Keep pointed at whatever this swing committed to, so the direction the defender reads is the
## direction the geometry actually delivers.
func _face(delta: float) -> void:
	# A bounded early preparation adjustment, never pursuit. Budgets belong to
	# the entire attack, so changing direction cannot buy another assisted step.
	if _phase != Phase.WINDUP or _assist_elapsed > contact_assist_time: return
	if not player.intent.attack_held or _wants_release: return
	if not is_instance_valid(_target): return
	var to := _target.global_position-player.global_position
	if absf(to.y) > .6: return
	to.y = 0.0
	var distance := to.length()
	if distance < .01 or distance > contact_assist_range: return
	var desired_yaw := atan2(-to.x,-to.z)
	var yaw_error := wrapf(desired_yaw-player.visuals.global_rotation.y,-PI,PI)
	var max_angle := deg_to_rad(contact_assist_angle)
	if absf(yaw_error) > max_angle: return
	var movement := player.get_move_input()
	if movement.length() > .1 and movement.normalized().dot(Vector2(to.x,to.z).normalized()) < .7: return
	var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP,_target.global_position+Vector3.UP,1)
	var exclusions: Array[RID] = [player.get_rid()]
	if _target is CollisionObject3D: exclusions.append(_target.get_rid())
	ray.exclude = exclusions
	if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return
	var turn := clampf(yaw_error,-minf(max_angle-_assist_turn,delta*.6),minf(max_angle-_assist_turn,delta*.6))
	player.visuals.global_rotation.y += turn
	_assist_turn += absf(turn)
	var step := minf(maxf(0.0,distance-1.40),minf(maxf(0.0,contact_assist_distance-_assist_travel),delta*.7))
	if step <= .00001: return
	var motion := to.normalized()*step
	if player.test_move(player.global_transform,motion): return
	var before := player.global_position
	player.move_and_collide(motion)
	_assist_travel += player.global_position.distance_to(before)


## Did the fighter change their mind about the direction? Re-wind from the new side.
func _rewound() -> bool:
	var want: int = player.intent.attack_dir
	if want != SwingDir.NONE and want != _input_dir and player.stamina >= 4.0 and not _wants_release:
		player.stamina=maxf(0.0,player.stamina-4.0)
		_input_dir = want
		_begin(want)
		return true
	return false


## Did they let go? Throw it.
func _released() -> bool:
	if player.intent.consume_release() or not player.intent.attack_held:
		_throw()
		return true
	return false


## Resume at the apex. The damage window opens later as the blade enters its strike arc.
func _throw() -> void:
	_phase = Phase.SWING
	player.set_tree_active(true)
	_t = _len * _strike * .60
	player.sword.begin_swing(_step,_len-_t,true)
	# The small step follows the fighter's already-visible facing, never a
	# target. A backwards/sideways movement request opts out of this step.
	_lunge_dir = -player.visuals.global_basis.z
	_lunge_dir.y = 0.0
	_lunge_dir = _lunge_dir.normalized()
	var movement := player.get_move_input()
	if _human_combo and (movement.length() < .1 or movement.normalized().dot(Vector2(_lunge_dir.x, _lunge_dir.z)) > .35):
		_lunge_left = _step_value(combo_step_distances, .25)
	player.velocity.x*=.35
	player.velocity.z*=.35
	_drift_velocity = Vector2(player.velocity.x, player.velocity.z)


func _tick_swing(delta: float) -> void:
	_t += delta
	if not _hit and _t>=_len*_strike:
		_hit=true
		player.sword.hit(_window_time,_dir%2==0,player.swing_damage(),_dir)
		damage_window_opened.emit(_step, _window_time)
		if _phase==Phase.RECOIL: return
	# Commit through the contact; return some footwork during recovery. Collision
	# resolution remains CharacterBody3D's, including steps stopped by a wall.
	var recovering := _t >= _len * _strike + _window_time
	var mobility := move_scale if recovering and _human_combo else root_speed
	# Keep user drift separate from last frame's added step. Feeding the sum
	# back into acceleration silently extends a nominal 28 cm step each frame.
	player.velocity.x = _drift_velocity.x
	player.velocity.z = _drift_velocity.y
	player.apply_movement(player.get_move_input(),delta,mobility)
	var planar:=Vector2(player.velocity.x,player.velocity.z).limit_length(player.move_speed*mobility)
	_drift_velocity = planar
	if _lunge_left > 0.0 and not recovering:
		var travel := minf(_lunge_left, delta * 2.8)
		_lunge_left -= travel
		planar += Vector2(_lunge_dir.x, _lunge_dir.z) * travel / maxf(delta, .001)
	player.velocity.x=planar.x
	player.velocity.z=planar.y

	var f := _t / maxf(_len, 0.01)
	if _dodge_left > 0.0 and _hit and _t >= _dodge_at and player.can_dash():
		fsm.transition_to("Dash")
	elif _queued_left > 0.0 and _hit and f >= _cancel and _step < 2 and player.stamina >= _step_value(combo_stamina_costs, 12.0, _step + 1):
		_next_step()
	elif f >= _cancel and player.get_move_input() != Vector2.ZERO:
		# MOVE-CANCEL, the same responsiveness rule attack.gd follows: past the cancel point the
		# hit has landed and the rest is recovery you have already paid for.
		fsm.transition_to("Move")
	elif f >= 1.0:
		# Straight back into a guard if it is already being asked for — that is the exchange.
		if player.intent.guard and fsm.has_state("Guard") and player.can_block():
			fsm.transition_to("Guard")
		else:
			fsm.transition_to("Move" if player.get_move_input() != Vector2.ZERO else "Idle")


func _tick_recoil(delta: float) -> void:
	_recoil -= delta
	if player.guard_pose:
		player.guard_pose.amount = .85*clampf(_recoil/.12,0,1)
	player.apply_friction(delta)
	if _recoil <= 0.0:
		fsm.transition_to("Move" if player.get_move_input() != Vector2.ZERO else "Idle")


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("block") and charging() and player.can_block():
		player.stamina=maxf(0.0,player.stamina-6.0)
		fsm.transition_to("Guard")
		return
	# Dash-cancel, but only once the swing has actually been thrown — the same commitment rule
	# attack.gd argues for. Cancelling a swing you have not paid for makes attacking free.
	if event.is_action_pressed("dash") and player.can_dash() and _phase != Phase.RECOIL:
		_dodge_left = dodge_buffer_time
		if _phase == Phase.SWING and _hit and _t >= _dodge_at:
			fsm.transition_to("Dash")


## CALLED BY THE DEFENDER when their guard answered this swing (player.gd's _do_block walks up from
## the hitbox to find it). Being blocked is the punishment for being read: the sword stops dead and
## you are open for recoil_time, which is roughly a whole exchange.
func blocked(duration := -1.0) -> void:
	if _phase == Phase.RECOIL:
		return
	_phase = Phase.RECOIL
	_queued_left = 0.0
	_dodge_left = 0.0
	_lunge_left = 0.0
	player.sword.cancel_swing()
	_recoil = recoil_time if duration < 0.0 else duration
	player.set_tree_active(true)
	# A stopped sword recoils into guard, not the full-body damage flinch.
	if player.has_clip("block"):
		player.play_clip("block")
	if player.guard_pose:
		player.guard_pose.dir = _dir
		player.guard_pose.amount = .85
		if player.guard_pose.has_method("contact_recoil"):
			player.guard_pose.contact_recoil(duration > recoil_time)


## The direction this swing is currently aimed. Read by the duelist AI so it has something to
## guess at, and by the HUD so the player can see the enemy's wind-up.
func pending_dir() -> int:
	return _dir

func pose_fraction() -> float:
	return -1.0 if _phase==Phase.RECOIL else clampf(_t/maxf(_len,.01),0,1)


## Is the swing still being charged? A wound-up sword is the tell the whole mechanic reads.
func charging() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.HOLD

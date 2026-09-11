extends State
## THE DIRECTIONAL SWING — the offensive half of the Bannerlord mechanic.
##
## Hold the attack button and the sword winds up and STOPS at the top of the swing. Release it and
## the blow falls. Which of the four directions it falls from is whatever the stick or the mouse
## last said, and that direction travels with the hit (sword.gd stamps it on the hitbox) so the
## defender's guard has something to be right or wrong about.
##
## WHY A HOLD RATHER THAN A CLICK. The click chain in attack.gd is a rhythm game against yourself:
## the timing you are playing is the animation's. A held wind-up moves the timing into the fight —
## you are waiting for THEM, they are reading YOU, and the moment either of you commits is a
## decision instead of a beat. It is also the only way a feint can exist, because a feint is
## nothing more than changing your mind while the sword is still up.
##
## CHANGING DIRECTION RE-WINDS. Push a new direction before you release and the swing starts over
## from that side. That is deliberately not free: the opponent always sees the swing that is
## actually coming, and the cost of lying to them is the wind-up you spend doing it. A direction
## that could be swapped silently at the apex would make every guard a coin toss.
##
## Both states coexist. A scene carrying `Attack` keeps the click combo; a scene carrying
## `DirAttack` gets this. player3 and the duelist built from it carry this one.

## THE CLIP PER DIRECTION, indexed by SwingDir (up, down, left, right). All four already exist in
## player3_anims.tres and none of them was being used: an overhead chop, a thrust, and the two
## side swings. Whatever is listed here must also have an entry in that body's attack_timing, or
## the swing falls back to untimed defaults and its strike frame is a guess.
@export var dir_clips: PackedStringArray = ["atk_c", "atk_cross", "atk_b", "atk_swing"]

@export var move_scale := 0.35     ## fraction of run speed you can drift while winding up
@export var hit_dur := 0.12        ## seconds the hitbox stays live
@export var hold_max := 1.2        ## seconds the swing may hang at the apex before it falls anyway

## THE ROOT. Velocity kept during the strike itself: a swing plants you. Without this the
## directional game collapses into a running blender, because the safest place to be is always
## inside someone who cannot turn as fast as you can circle. 0 would freeze the body outright,
## which reads as the game taking the controls away — 0.15 is "committed", not "paralysed".
@export var root_speed := 0.15

@export var step_lead := 0.85      ## aim this fraction into the envelope, not at its edge
@export var recoil_time := 0.45    ## how long a blocked swing leaves you open
@export var contact_assist_distance := 0.10
@export var contact_assist_angle := 5.0
@export var contact_assist_range := 1.50
@export var contact_assist_time := .16

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
var _step_vel := Vector3.ZERO
var _assist_elapsed := 0.0
var _assist_travel := 0.0
var _assist_turn := 0.0


func enter() -> void:
	_recoil = 0.0
	_assist_elapsed = 0.0
	_assist_travel = 0.0
	_assist_turn = 0.0
	player.intent.consume_attack()
	player.stamina=maxf(0.0,player.stamina-12.0)
	_begin(player.intent.attack_dir)


func exit() -> void:
	player.sword.cancel_swing()
	if player.guard_pose:
		player.guard_pose.amount = 0.0
		player.guard_pose.dir = SwingDir.NONE
	# Every interruption restores the animation clock, including hurt and death.
	player.set_tree_active(true)


func _begin(dir: int) -> void:
	_phase = Phase.WINDUP
	_t = 0.0
	_hold = 0.0
	_hit = false
	_wants_release = false
	_dir = dir if dir != SwingDir.NONE else SwingDir.UP
	player.set_tree_active(true)

	# Target first, then the clip — the same order and the same reasons as attack.gd: which
	# direction the swing should commit to and how much ground it has to cover both come from the
	# acquisition, so it cannot wait until after the clip is playing.
	_target = player.acquire_target(contact_assist_range, contact_assist_angle)

	_clip = dir_clips[_dir] if _dir < dir_clips.size() else dir_clips[0]
	_len = player.play_attack(_clip)
	var meta: Dictionary = player.attack_meta.get(_clip, {"strike": 0.4, "cancel": 0.55})
	_strike = meta.strike
	_cancel = meta.cancel
	_step_vel=Vector3.ZERO
	# Step 0 deliberately: begin_swing's argument is the COMBO index, and sword.gd reads it back as
	# "is this a finisher" for the knockback weight. A directional swing has no combo position, and
	# passing the direction here would have made every left and right swing a finisher.


## How far short of contact this swing is, in metres. Negative means already inside the envelope.
func _gap_to_target() -> float:
	if _target == null:
		return -INF
	var to: Vector3 = _target.global_position - player.global_position
	to.y = 0.0
	return to.length() - player.contact_range(_target) * step_lead


## The step into the swing. Identical in intent to attack.gd's — the measured envelope ends at
## 2.08 m and misses by 16 mm at 2.10, so a swing that has committed to a target closes the last
## few centimetres itself. Capped by the player's own attack_step_max, so it stays a step.
func _aim_step() -> void:
	_step_vel = Vector3.ZERO
	if _target == null:
		return
	var to: Vector3 = _target.global_position - player.global_position
	to.y = 0.0
	var gap: float = _gap_to_target()
	if gap <= 0.0:
		return
	gap = minf(gap, player.attack_step_max)
	var windup: float = maxf(_len * _strike, 0.05)
	_step_vel = to.normalized() * minf(gap / windup, player.attack_step_speed)


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	_assist_elapsed += delta

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
	# The step OWNS the body until the apex, for the reason attack.gd documents: running
	# apply_movement here decelerates 6 m/s to 2.1 in a tenth of a second and strands the swing
	# short of what it was closing on.
	if _step_vel != Vector3.ZERO:
		player.velocity.x = _step_vel.x
		player.velocity.z = _step_vel.z
	else:
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
	if want != SwingDir.NONE and want != _dir and player.stamina >= 4.0 and not _wants_release:
		player.stamina=maxf(0.0,player.stamina-4.0)
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
	player.sword.begin_swing(0,_len-_t,true)
	player.velocity.x*=.35
	player.velocity.z*=.35


func _tick_swing(delta: float) -> void:
	_t += delta
	if not _hit and _t>=_len*_strike:
		_hit=true
		player.sword.hit(_len*(.78-_strike),_dir%2==0,player.swing_damage(),_dir)
		if _phase==Phase.RECOIL: return
	# Rooted: the swing has left, and where you were standing when it did is where it lands from.
	player.apply_movement(player.get_move_input(),delta,root_speed)
	var planar:=Vector2(player.velocity.x,player.velocity.z).limit_length(player.move_speed*root_speed)
	player.velocity.x=planar.x
	player.velocity.z=planar.y

	var f := _t / maxf(_len, 0.01)
	if f >= _cancel and player.get_move_input() != Vector2.ZERO:
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
	if event.is_action_pressed("dash") and player.can_dash() and _hit and _t/_len>=_cancel:
		fsm.transition_to("Dash")


## CALLED BY THE DEFENDER when their guard answered this swing (player.gd's _do_block walks up from
## the hitbox to find it). Being blocked is the punishment for being read: the sword stops dead and
## you are open for recoil_time, which is roughly a whole exchange.
func blocked(duration := -1.0) -> void:
	if _phase == Phase.RECOIL:
		return
	_phase = Phase.RECOIL
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

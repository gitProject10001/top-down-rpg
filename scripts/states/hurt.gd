extends State
## Brief stagger after taking a hit: input is ignored, knockback (set by the player when damaged)
## plays out, then control returns. Stops the player from acting through damage.

@export var stun_time := 0.28
@export_group("Enemy reactions")
@export var finisher_knockdown := true
@export_range(.25, 1.5, .05) var fall_duration := .55
@export_range(.3, 1.5, .05) var rise_duration := .65
var reaction_clip := "hurt_chest"
var knocked_down := false
var recovering := false
@export_range(.1,.6,.01) var recovery_distance := .35
@export_range(.15,.6,.01) var recovery_duration := .30
var recovery_step := false
var _pending_step := false
var _stepping := false
var _step_direction := Vector3.ZERO
var _step_left := 0.0
var _pending_finisher := false

## Only applied hits reach this entry point. Repeated hits do not restart a
## fall/get-up indefinitely; lethal damage still transitions immediately to Dead.
func receive_hit(source: Node) -> void:
	if fsm.current_state == self and knocked_down: return
	reaction_clip = "hurt_chest"
	_pending_finisher = false
	_pending_step = false
	if not player.is_input_driven() and player.health.hp > 0:
		_pending_finisher = finisher_knockdown and source != null and bool(source.get_meta("finisher", false)) and player.has_clip("hurt_knockback") and player.has_clip("getup")
		_pending_step = not _pending_finisher and source != null and bool(source.get_meta("recovery_step",false)) and player.has_clip("recover_walk_back")
		if source != null and source.has_meta("contact_point"):
			var skeleton := player.find_child("GeneralSkeleton", true, false) as Skeleton3D
			if skeleton:
				var head := skeleton.find_bone("Head")
				if head >= 0:
					var head_position := skeleton.to_global(skeleton.get_bone_global_pose(head).origin)
					var point: Vector3 = source.get_meta("contact_point")
					if point.is_finite() and point.y >= head_position.y - .16 and player.has_clip("hurt_head"):
						reaction_clip = "hurt_head"
	if fsm.current_state == self: enter()
	else: fsm.transition_to("Hurt")

## How long a heavy knockback slides before friction takes it. Only applies above 6 m/s, so a
## normal hit still behaves exactly as it did.
@export var slide_time := 0.38

var _elapsed := 0.0
var _knocked := false
var _duration := 0.28

func enter() -> void:
	_elapsed = 0.0
	recovery_step = _pending_step
	_pending_step = false
	_stepping = false
	_step_left = recovery_distance
	_step_direction = Vector3(player.velocity.x,0,player.velocity.z).normalized()
	_duration = .12 if recovery_step else stun_time
	knocked_down = _pending_finisher
	_pending_finisher = false
	recovering = false
	_knocked = player.velocity.length() >= 6.0
	player.set_tree_active(true)
	if player.sword:
		player.sword.cancel_swing()
	if player.intent:
		player.intent.consume_attack()
	if knocked_down:
		reaction_clip = "hurt_knockback"
		_duration = _play_timed(reaction_clip, fall_duration)
	elif player.has_clip(reaction_clip):
		player.play_clip(reaction_clip)

func _play_timed(clip: String, wanted: float) -> float:
	var length := player.play_clip(clip)
	# This action clock belongs to the enemy's existing animation layers.
	if fsm.has_state("DirAttack"):
		player.set_attack_playback_speed(length / wanted)
		return wanted
	return length

func exit() -> void:
	player.set_attack_playback_speed(1.0)
	knocked_down = false
	recovering = false
	reaction_clip = "hurt_chest"
	recovery_step = false
	_stepping = false


func extend_stun(seconds: float) -> void:
	_duration = maxf(_duration, seconds)

func physics_update(delta: float) -> void:
	_elapsed += delta
	player.apply_gravity(delta)
	# LET A REAL SHOVE PLAY OUT. Friction from the first frame bled a 12 m/s kick down to nothing
	# inside the 0.28 s stun, so the attack whose entire purpose is to put the player back out at
	# mace range moved them about a third of a metre. Anything above a walking knock gets a moment
	# to travel before the friction starts; ordinary hits are unaffected.
	if _stepping:
		var travel := minf(_step_left, recovery_distance/recovery_duration*delta)
		var motion := _step_direction*travel
		var safe := not player.test_move(player.global_transform,motion*2.0)
		var brain := player.intent
		if brain is PackBrain and is_instance_valid(brain.director):
			safe = safe and brain.director.safe_step(player,Vector2(_step_direction.x,_step_direction.z),maxf(travel*2,.12))
		if safe:
			player.velocity.x=motion.x/delta
			player.velocity.z=motion.z/delta
			_step_left-=travel
		else:
			player.velocity.x=0
			player.velocity.z=0
			_step_left=0
			_elapsed=_duration
	elif _elapsed > slide_time or player.velocity.length() < 6.0:
		player.apply_friction(delta)
	player.move_and_slide()
	# A big shove keeps the player out of control until it has actually carried them, or the stun
	# ends while they are still travelling and they can simply walk back in mid-flight.
	if _elapsed >= maxf(_duration, slide_time if _knocked else 0.0):
		if recovery_step and not _stepping:
			_stepping=true
			_elapsed=0
			var local_dir := player.visuals.global_basis.inverse()*_step_direction
			var clip := "recover_walk_back"
			if absf(local_dir.x)>absf(local_dir.z): clip="recover_walk_right" if local_dir.x>0 else "recover_walk_left"
			elif local_dir.z<0: clip="walk"
			reaction_clip=clip
			player.play_clip(clip)
			_duration=recovery_duration
		elif knocked_down and not recovering:
			recovering = true
			reaction_clip = "getup"
			_elapsed = 0.0
			_duration = _play_timed(reaction_clip, rise_duration)
		else:
			fsm.transition_to("Idle")

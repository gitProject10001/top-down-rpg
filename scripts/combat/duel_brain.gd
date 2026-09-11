class_name DuelBrain
extends FighterIntent
## THE DUELIST'S MIND. Fills in exactly the same FighterIntent fields a person's hands fill in, so
## the body it drives is a Player in every other respect — same states, same rig, same rules, same
## measured attack envelope. Nothing here can do anything the player cannot.
##
## WHAT IT IS TRYING TO BE. Not hard, not fair — READABLE. A directional fight is only interesting
## if you can tell what is about to happen and be wrong about it anyway, so every decision this
## makes has a tell attached: it winds up for `telegraph` seconds before it swings, its guard is a
## visible pose, and it commits to a direction rather than tracking yours. The difficulty dial that
## matters is `guard_read`, which is how often it guesses your direction right — not its speed and
## not its damage.
##
## IT PLAYS THE SPACING GAME. It wants to stand at `ring`, which is just outside its own contact
## range, and it steps in to swing and out again afterwards. That is what makes footwork the
## subject: you can deny its opening by holding the distance, and it can deny yours the same way.

## Metres it wants between the two of you when neither is committed. Just outside contact (2.08 m
## measured), so closing the last step is a decision somebody has to make.
@export var ring := 1.85
@export var strike_distance := 1.40
@export var crowded_distance := 1.20
@export var attack_step_limit := 0.35
@export var reset_time := 0.65

## Seconds it holds the wind-up before releasing. This IS the difficulty of reading it: shorter
## gives you less time to answer, and below about 0.25 no human can.
@export var telegraph := 0.4

## Chance it guards the direction you are actually swinging. 1.0 is unbeatable by attacking, 0.25
## is a sparring partner. The rest of the time it picks one of the other three.
@export_range(0.0, 1.0) var guard_read := 0.6

## Chance it opens rather than waits, rolled every `think_period`.
@export_range(0.0, 1.0) var aggression := 0.55

## Seconds before it responds to something new. Without this it answers a wind-up on the same
## frame it starts, which reads as cheating even when the read itself was fair.
@export var reaction := 0.22

@export var think_period := 0.35   ## how often it re-decides
@export var recover := 0.5         ## seconds it stays passive after its own swing lands or misses

## How hard it circles rather than closing head-on. 0 walks straight in.
@export_range(0.0, 1.0) var strafe := 0.45

## HOW CLOSE YOU HAVE TO COME before it is a fight. Beyond this it stands where it was placed and
## does nothing at all — which is what makes it a sparring partner you walk up to rather than an
## ambush at the spawn point. It does NOT drop back out once engaged inside 1.5x this, so backing
## off two steps mid-exchange does not switch it off.
@export var engage_range := 6.0

enum Mode { WAIT, PRESS, SWING, GUARD, RESET }

var _mode := Mode.WAIT
var _think := 0.0
var _swing_t := 0.0
var _cooldown := 0.0
var _react := 0.0
var _strafe_sign := 1.0
var _engaged := false
var _opponent: Node3D
var _step_start := Vector3.ZERO
var _reset_left := 0.0
var _was_committed := false
var _side_left := 0.0


func _physics_process(delta: float) -> void:
	var me := fighter()
	if me == null:
		return
	if not me.health.is_alive():
		clear()
		return

	_opponent = _find_opponent(me)
	if _opponent == null:
		clear()
		return

	var to: Vector3 = _opponent.global_position - me.global_position
	to.y = 0.0
	var dist := to.length()
	var toward := Vector2(to.x, to.z).normalized() if dist > 0.01 else Vector2.ZERO
	# ALWAYS AT THE OPPONENT. Facing is not a tactic here — a fighter looking anywhere else swings
	# at nothing, and its guard would be covering a direction the blow is not coming from.
	look = toward

	# STAND DOWN, and stand still. Everything below assumes a fight is happening.
	var limit: float = engage_range * (1.5 if _engaged else 1.0)
	if dist > limit:
		_engaged = false
		clear()
		return
	_engaged = true
	# Recovery starts when the body's committed action actually finishes, not
	# when the AI releases its button. Recoil/hurt must pay their own time first.
	var committed := me.state_name() in ["DirAttack", "Hurt"]
	if _was_committed and not committed:
		_mode = Mode.RESET
		_reset_left = reset_time
		_cooldown = recover
	_was_committed = committed
	if not committed:
		_reset_left = maxf(0.0, _reset_left - delta)
	_side_left = maxf(0.0, _side_left - delta)

	_cooldown = maxf(_cooldown - delta, 0.0)
	_think -= delta
	if _think <= 0.0:
		_think = think_period
		_decide(me, dist)

	_drive(delta, dist, toward)


## One decision, taken on a timer rather than every frame. A mind that re-decides sixty times a
## second flickers between answers and reads as noise.
func _decide(me: Player, dist: float) -> void:
	if me.state_name() in ["DirAttack", "Hurt"]: return
	if dist < crowded_distance or _reset_left > 0.0:
		_mode = Mode.RESET
		return
	var threat := _incoming_dir()

	# THEY ARE WINDING UP. Answer it — after `reaction`, and only as well as `guard_read` allows.
	if threat != SwingDir.NONE and dist < ring * 1.6:
		if _mode != Mode.GUARD:
			_react = reaction
			_mode = Mode.GUARD
			guard_dir = _guess(threat)
		return

	# Mid-swing: nothing to decide, the state machine owns the body until it lands.
	if _mode == Mode.SWING:
		return

	if _cooldown > 0.0:
		_mode = Mode.WAIT
		return

	# In range and feeling like it: open.
	if dist <= strike_distance + attack_step_limit and me.stamina>=24.0 and randf() < aggression:
		_mode = Mode.SWING
		_swing_t = 0.0
		_step_start = me.global_position
		attack_dir = _pick_attack()
		# Change the circling hand each exchange, so it does not become a treadmill you can learn.
		_strafe_sign = 1.0 if randf() < 0.5 else -1.0
		return

	# NOTHING COMING, AND NOT OPENING: hold a guard rather than standing in the open. A duelist
	# that only guards in reaction can be beaten by attacking first, every time, which makes the
	# whole reading contest a formality.
	if dist <= ring * 1.3 and randf() < 0.5:
		_mode = Mode.GUARD
		_react = reaction
		guard_dir = SwingDir.ALL[randi() % SwingDir.COUNT]
		return
	_mode = Mode.PRESS if dist > strike_distance + .15 and me.stamina >= 24.0 else Mode.WAIT
	if _mode == Mode.WAIT and randf() < .3:
		_side_left = .35


## Turn the decision into the same fields a person's hands would set.
func _drive(delta: float, dist: float, toward: Vector2) -> void:
	_react = maxf(_react - delta, 0.0)

	match _mode:
		Mode.SWING:
			guard = false
			attack_held = true
			_swing_t += delta
			# Step in while winding up; the swing's own step closes whatever is left.
			var travelled := Vector2(fighter().global_position.x-_step_start.x, fighter().global_position.z-_step_start.z).length()
			var remaining := minf(dist-strike_distance, attack_step_limit-travelled)
			move = toward * clampf(remaining*2.0, 0.0, .5)
			if _swing_t >= telegraph:
				request_release()
				attack_held = false
				_mode = Mode.RESET
				move = Vector2.ZERO
		Mode.RESET:
			attack_held = false
			guard = true
			# Never retreat through a strike or recoil: gameplay owns that phase.
			if fighter().state_name() in ["DirAttack", "Hurt"]:
				move = Vector2.ZERO
			else:
				move = -toward * clampf((ring-dist)*1.5, 0.0, .7)
		Mode.GUARD:
			attack_held = false
			guard = _react <= 0.0
			# Give ground behind the guard rather than standing in the blow. This is the same
			# spacing answer the player has, and it is why a swing can be made to miss.
			move = -toward * clampf((strike_distance+.15-dist)*2.0, 0.0, .65)
			# Held until the next _decide, not dropped the moment the tell goes away: a guard that
			# vanishes on the same frame the swing lands is not a guard.
		Mode.PRESS:
			guard = true
			attack_held = false
			move = toward * clampf((dist-strike_distance)*1.5, 0.0, .6)
		_:
			guard = false
			attack_held = false
			# Hold the ring: in if too far, out if too close, and always drifting around it.
			var radial := clampf((dist - ring) / 1.5, -.4, .4) if absf(dist-ring) > .15 else 0.0
			var side := Vector2(-toward.y, toward.x) * strafe * _strafe_sign if _side_left > 0.0 else Vector2.ZERO
			move = (toward * radial + side).limit_length(1.0)
	# If a wall denies the retreat, try a lateral escape. Never teleport or
	# push the opponent to manufacture space; a corner remains disadvantageous.
	if move.length() > .01:
		var body := fighter()
		if body.test_move(body.global_transform, Vector3(move.x,0,move.y).normalized()*.45):
			var side := Vector2(-toward.y,toward.x)*_strafe_sign
			if body.test_move(body.global_transform, Vector3(side.x,0,side.y)*.45):
				side = -side
			move = Vector2.ZERO if body.test_move(body.global_transform, Vector3(side.x,0,side.y)*.45) else side*.4


## Which way the opponent's wind-up is aimed, or NONE if they are not winding one up. This is the
## tell — the same one drawn on the HUD for the player.
func _incoming_dir() -> int:
	if _opponent == null or not is_instance_valid(_opponent):
		return SwingDir.NONE
	if not _opponent.has_method("charging_dir"):
		return SwingDir.NONE
	return _opponent.charging_dir()


## Guess their direction, right `guard_read` of the time. A wrong guess is a real wrong guess: it
## picks one of the other three, so the mistake is visible rather than a guard that simply fails.
func _guess(actual: int) -> int:
	if randf() < guard_read:
		return SwingDir.mirror(actual)
	var wrong: Array[int] = []
	for d in SwingDir.ALL:
		if d != SwingDir.mirror(actual):
			wrong.append(d)
	return wrong[randi() % wrong.size()]


## Swing at whatever their guard is NOT covering. Against a guard held up it comes low; against a
## guard held left it comes from the other side. Against no guard at all it picks freely, so it
## does not become predictable while you are standing open.
func _pick_attack() -> int:
	var theirs := SwingDir.NONE
	if _opponent != null and _opponent.has_method("current_guard_dir"):
		theirs = _opponent.current_guard_dir()
	if theirs == SwingDir.NONE:
		return SwingDir.ALL[randi() % SwingDir.COUNT]
	# The guard direction the defender must hold to stop a given swing is the mirror of it, so the
	# swing that beats a guard is anything whose mirror is not the guard they are holding.
	var open: Array[int] = []
	for d in SwingDir.ALL:
		if SwingDir.mirror(d) != theirs:
			open.append(d)
	return open[randi() % open.size()]


## Whoever this fighter is fighting: the nearest live body in the group its Player is aimed at.
func _find_opponent(me: Player) -> Node3D:
	if _opponent != null and is_instance_valid(_opponent):
		var hp := _opponent.get_node_or_null("Health") as Health
		if hp == null or hp.is_alive():
			return _opponent
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(me.target_group):
		var e := n as Node3D
		if e == null or e == me or not is_instance_valid(e):
			continue
		var hp2 := e.get_node_or_null("Health") as Health
		if hp2 and not hp2.is_alive():
			continue
		var d: float = e.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

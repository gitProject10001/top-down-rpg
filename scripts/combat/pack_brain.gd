class_name PackBrain
extends FighterIntent
## A less defensive group opponent. Only writes FighterIntent; no damage or movement integration.
const DirectorScript = preload("res://scripts/combat/pack_director.gd")
@export var engage_range := 9.0
@export var strike_distance := 1.40
@export var telegraph_min := .35
@export var telegraph_max := .50
@export_range(0, 1) var guard_read := .20
@export_range(0, 1) var guard_chance := .22
@export var recovery := .48
@export var brain_seed := 1

var director: Node
var opponent: Node3D
var _rng := RandomNumberGenerator.new()
var _engaged := false
var _committed := false
var _winding := false
var _wind_time := 0.0
var _telegraph := .40
var _cooldown := .1
var _guard_left := 0.0
var _guard_delay := 0.0
var _guard_check := 0.0
var _side := 1.0

func _ready() -> void:
	_rng.seed = brain_seed
	_side = 1.0 if brain_seed % 2 == 0 else -1.0

func configure(coordinator: Node, player: Node3D) -> void:
	if is_instance_valid(director) and fighter(): director.release_turn(fighter())
	director = coordinator
	opponent = player
	_engaged = false
	_rng.seed = brain_seed + absi(String(get_parent().name).hash())
	clear()
	if fighter(): director.register(fighter())

func _exit_tree() -> void:
	if is_instance_valid(director) and fighter(): director.release_turn(fighter())

func _physics_process(delta: float) -> void:
	var me := fighter()
	if me == null or me.health == null: return
	_resolve_encounter()
	if not is_instance_valid(director) or not is_instance_valid(opponent):
		clear()
		return
	var hp := opponent.get_node_or_null("Health") as Health
	var state := me.state_name()
	var dialogue := get_node_or_null("/root/Dialogue")
	var paused: bool = dialogue != null and dialogue.active
	var interrupted: bool = paused or not me.health.is_alive() or state in ["Hurt", "Dead"] or (hp != null and not hp.is_alive())
	var attacking := state in ["DirAttack", "Attack", "DashAttack"]
	var offset := opponent.global_position - me.global_position
	var toward := Vector2(offset.x, offset.z).normalized()
	var distance := Vector2(offset.x, offset.z).length()
	var arena_ok: bool = not director.arena_origin.is_finite() or opponent.global_position.distance_to(director.arena_origin) <= director.encounter_radius
	_engaged = distance <= engage_range * (1.4 if _engaged else 1.0) and arena_ok
	if _committed and not attacking:
		_cooldown = recovery + _rng.randf_range(0, .15)
		_winding = false
	_committed = attacking
	_cooldown = maxf(0, _cooldown - delta)
	director.report(me, _engaged and not interrupted and _cooldown <= 0 and me.stamina >= 24,
		attacking, interrupted or not _engaged)
	if interrupted or not _engaged:
		if attacking and (paused or not _engaged or (hp != null and not hp.is_alive())):
			me.get_node("StateMachine").transition_to("Idle")
		clear()
		_winding = false
		_cooldown = maxf(_cooldown, recovery)
		return
	look = toward
	move = Vector2.ZERO
	guard = false
	if attacking:
		# A wall/elevation change during the tell cancels through the body's normal state exit.
		if not director.can_attack(me):
			me.get_node("StateMachine").transition_to("Idle")
			director.release_turn(me)
			clear()
			_winding = false
			return
		if _winding:
			_wind_time += delta
			attack_held = true
			if _wind_time >= _telegraph:
				request_release()
				attack_held = false
				_winding = false
		else:
			attack_held = false
		return
	attack_held = false
	if _cooldown <= 0 and me.stamina >= 24: director.request_turn(me)
	if director.holds_turn(me):
		_guard_left = 0
		if distance <= strike_distance + .10 and director.can_attack(me) and director.begin_attack(me):
			attack_dir = SwingDir.ALL[_rng.randi_range(0, SwingDir.COUNT - 1)]
			_telegraph = _rng.randf_range(telegraph_min, telegraph_max)
			_wind_time = 0
			_winding = true
			attack_held = true
			return
		move = toward * clampf((distance - strike_distance + .05) * 1.1, -.25, .60)
	else:
		var station: Vector3 = director.station_for(me)
		var displacement := Vector2(station.x - me.global_position.x, station.z - me.global_position.z)
		move = displacement.normalized() * minf(displacement.length() * .75, .42)
		_tick_guard(delta, distance)
	move = (move + director.separation_for(me) * .72).limit_length(.75)
	_avoid_edges(me, toward)

func _tick_guard(delta: float, distance: float) -> void:
	_guard_left = maxf(0, _guard_left - delta)
	_guard_delay = maxf(0, _guard_delay - delta)
	_guard_check -= delta
	if _guard_check <= 0:
		_guard_check = .65 + _rng.randf_range(0, .30)
		var incoming := int(opponent.charging_dir()) if opponent.has_method("charging_dir") else SwingDir.NONE
		if distance < 2.5 and incoming != SwingDir.NONE and _rng.randf() < guard_chance:
			_guard_delay = .20
			_guard_left = .55
			var correct := SwingDir.mirror(incoming)
			if _rng.randf() < guard_read:
				guard_dir = correct
			else:
				var wrong: Array[int] = []
				for direction in SwingDir.ALL:
					if direction != correct: wrong.append(direction)
				guard_dir = wrong[_rng.randi_range(0, wrong.size() - 1)]
	guard = _guard_left > 0 and _guard_delay <= 0

func _avoid_edges(me: CharacterBody3D, toward: Vector2) -> void:
	if move.length_squared() < .001: return
	if director.safe_step(me, move): return
	var lateral := Vector2(-toward.y, toward.x) * _side
	if director.safe_step(me, lateral):
		move = lateral * .32
	elif director.safe_step(me, -lateral):
		move = -lateral * .32
		_side = -_side
	else:
		move = Vector2.ZERO

func _resolve_encounter() -> void:
	if is_instance_valid(director) and is_instance_valid(opponent): return
	for candidate in get_tree().get_nodes_in_group("pack_director"):
		if candidate.get_viewport() == get_viewport() and is_instance_valid(candidate.target):
			configure(candidate, candidate.target)
			return

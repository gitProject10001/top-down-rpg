class_name PackDirector
extends Node
## Encounter-level turns and ring positions. Inspired by rpg-3d's CombatDirector,
## but consumes explicit intent facts instead of that project's Enemy state enum.
## Bodies, sword contacts, damage, hurt and parry remain the shared Player pipeline.

@export_range(1, 2, 1) var attack_slots := 2
@export var start_spacing := 0.30
@export var approach_lease := 2.8
@export var attack_lease := 4.0
@export var ring_radius := 2.65
@export var separation_radius := 1.20
@export var max_elevation_difference := 0.60
@export var encounter_radius := 18.0

var target: Node3D
var arena_origin := Vector3.INF
var water_bodies: Array[Node3D] = []
var _members: Dictionary = {}
var _clock := 0.0
var _serial := 0
var _next_start := 0.0
var _ring_anchor := 0.0
var _grants := 0
var _starts := 0

func _ready() -> void:
	add_to_group("pack_director")

func configure(player: Node3D, origin := Vector3.INF) -> void:
	target = player
	arena_origin = origin
	_members.clear()
	_next_start = _clock
	water_bodies.clear()
	if is_inside_tree():
		for node in get_viewport().find_children("*", "Node3D", true, false):
			if node.has_method("contains_point") and node.has_method("set_simulation"):
				water_bodies.append(node)

func register(actor: Node3D) -> void:
	var id := actor.get_instance_id()
	if _members.has(id): return
	if _members.is_empty() and is_instance_valid(target):
		var offset := actor.global_position - target.global_position
		_ring_anchor = atan2(offset.z, offset.x)
	_members[id] = {"actor": actor, "eligible": false, "committed": false,
		"reported": _clock, "turn": false, "started": false, "granted": 0.0,
		"request": -1, "turns": 0}
	actor.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)

func report(actor: Node3D, eligible: bool, committed: bool, interrupted := false) -> void:
	register(actor)
	var entry: Dictionary = _members[actor.get_instance_id()]
	entry.reported = _clock
	entry.eligible = eligible
	if interrupted or not _alive(actor) or not _alive(target):
		release_turn(actor)
	elif entry.turn and entry.committed and not committed:
		release_turn(actor)
	entry.committed = committed
	if not eligible: entry.request = -1

func request_turn(actor: Node3D) -> bool:
	register(actor)
	var entry: Dictionary = _members[actor.get_instance_id()]
	if entry.turn: return true
	if not entry.eligible: return false
	if entry.request < 0:
		entry.request = _serial
		_serial += 1
	_grant_waiter()
	return entry.turn

## Spacing is enforced when a windup actually starts, not when its approach lease was granted.
func begin_attack(actor: Node3D) -> bool:
	if not holds_turn(actor) or _clock < _next_start or not can_attack(actor): return false
	var entry: Dictionary = _members[actor.get_instance_id()]
	if entry.started: return true
	entry.started = true
	entry.granted = _clock
	_next_start = _clock + start_spacing
	_starts += 1
	return true

func holds_turn(actor: Node3D) -> bool:
	return is_instance_valid(actor) and _members.has(actor.get_instance_id()) and _members[actor.get_instance_id()].turn

func release_turn(actor: Node3D) -> void:
	if not is_instance_valid(actor) or not _members.has(actor.get_instance_id()): return
	var entry: Dictionary = _members[actor.get_instance_id()]
	entry.turn = false
	entry.started = false
	entry.request = -1

func _forget(id: int) -> void:
	_members.erase(id)

func _physics_process(delta: float) -> void:
	_clock += delta
	for id in _members.keys():
		var entry: Dictionary = _members[id]
		if not is_instance_valid(entry.actor) or not entry.actor.is_inside_tree():
			_members.erase(id)
			continue
		if not _alive(entry.actor) or not _alive(target) or _clock - entry.reported > .25:
			release_turn(entry.actor)
			entry.eligible = false
		elif entry.turn and _clock - entry.granted > (attack_lease if entry.started else approach_lease):
			release_turn(entry.actor)
	_grant_waiter()

func _grant_waiter() -> void:
	if not _alive(target): return
	var occupied := 0
	var waiting: Array[Dictionary] = []
	for entry: Dictionary in _members.values():
		if entry.turn: occupied += 1
		elif entry.eligible and entry.request >= 0: waiting.append(entry)
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.request < b.request)
	for entry in waiting:
		if occupied >= attack_slots: break
		if not can_attack(entry.actor): continue
		entry.turn = true
		entry.started = false
		entry.granted = _clock
		entry.request = -1
		entry.turns += 1
		_grants += 1
		occupied += 1

func station_for(actor: Node3D) -> Vector3:
	if not is_instance_valid(target): return actor.global_position
	var ids: Array[int] = []
	for id in _members:
		if _alive(_members[id].actor) and _clock - _members[id].reported < .3: ids.append(id)
	var index := ids.find(actor.get_instance_id())
	if index < 0: return actor.global_position
	var desired := _ring_anchor + TAU * float(index) / maxi(ids.size(), 1)
	var offset := actor.global_position - target.global_position
	var current := atan2(offset.z, offset.x)
	# Advance around the circumference, never cut through the target to a far-side station.
	var angle := current + clampf(wrapf(desired - current, -PI, PI), -.65, .65)
	return Vector3(target.global_position.x + cos(angle) * ring_radius,
		actor.global_position.y, target.global_position.z + sin(angle) * ring_radius)

func separation_for(actor: Node3D) -> Vector2:
	var separation := Vector2.ZERO
	for entry: Dictionary in _members.values():
		var other: Node3D = entry.actor
		if other == actor or not _alive(other): continue
		var delta := actor.global_position - other.global_position
		if absf(delta.y) > .7: continue
		var away := Vector2(delta.x, delta.z)
		var distance := away.length()
		if distance < .001:
			away = Vector2.RIGHT if actor.get_instance_id() < other.get_instance_id() else Vector2.LEFT
			distance = .001
		if distance < separation_radius:
			separation += away.normalized() * (1.0 - distance / separation_radius)
	return separation.limit_length(1.0)

func can_attack(actor: Node3D) -> bool:
	if not _alive(actor) or not _alive(target) or not actor.is_inside_tree(): return false
	if absf(actor.global_position.y - target.global_position.y) > max_elevation_difference: return false
	if arena_origin.is_finite() and target.global_position.distance_to(arena_origin) > encounter_radius: return false
	var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * .15,
		target.global_position + Vector3.UP * .15, 1, _body_exclusions())
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## Physical lookahead protects the actual raised terrain and water margins without a NavRegion.
## It does not attempt to solve a maze: blocked agents wait or try a nearby lateral direction.
func safe_step(actor: CharacterBody3D, direction: Vector2, distance := .72) -> bool:
	if direction.length_squared() < .0001: return true
	var delta := Vector3(direction.x, 0, direction.y).normalized() * distance
	if actor.test_move(actor.global_transform, delta): return false
	var here := _floor_at(actor, actor.global_position)
	var next := _floor_at(actor, actor.global_position + delta)
	if here.is_empty() or next.is_empty(): return false
	if next.normal.y < .70 or absf(next.position.y - here.position.y) > .48: return false
	var water := get_node_or_null("/root/Water")
	if water and water.has_method("surface_y"):
		var surface: float = water.surface_y(next.position)
		if not is_nan(surface) and surface > next.position.y + .10: return false
	for body in water_bodies:
		if not is_instance_valid(body): continue
		var local := body.to_local(next.position)
		if local.y < .10 and body.contains_point(Vector2(local.x, local.z)): return false
	return true

func _floor_at(actor: Node3D, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .50,
		point - Vector3.UP * 1.55, 1, _body_exclusions())
	return actor.get_world_3d().direct_space_state.intersect_ray(query)

func _body_exclusions() -> Array[RID]:
	var excluded: Array[RID] = []
	if is_instance_valid(target) and target is CollisionObject3D: excluded.append(target.get_rid())
	for entry: Dictionary in _members.values():
		if is_instance_valid(entry.actor) and entry.actor is CollisionObject3D: excluded.append(entry.actor.get_rid())
	return excluded

func _alive(actor: Node3D) -> bool:
	if not is_instance_valid(actor): return false
	var health := actor.get_node_or_null("Health")
	return health == null or health.is_alive()

func snapshot() -> Dictionary:
	var holders := 0
	var turns := {}
	for entry: Dictionary in _members.values():
		if entry.turn: holders += 1
		if is_instance_valid(entry.actor): turns[String(entry.actor.name)] = entry.turns
	return {"holders": holders, "members": _members.size(), "grants": _grants,
		"starts": _starts, "turns": turns, "clock": _clock}

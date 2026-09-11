class_name SwarmSpawner
extends Node3D
## The generator: a nest that pumps out Swarmlings while its conditions hold.
##
## "Under certain circumstances" is the whole design — a spawner that runs unconditionally is just a
## lag machine. Every one of these must be true for a spawn tick to fire:
##   1. `active`                       — can be flipped by a room, a cutscene, a boss phase
##   2. the player is within `activate_range`   — no spawning into an empty room
##   3. live count < `max_alive`       — hard ceiling, also what keeps the boids O(n²) cheap
##   4. budget remaining               — `total_budget` -1 = endless, else a finite wave
##
## Give it a Health child and it becomes DESTRUCTIBLE: kill the nest to stop the tide. That turns a
## swarm encounter from attrition into a target-priority decision, which is the more interesting
## version of the fight.

@export var swarm_scene: PackedScene = preload("res://scenes/enemy_swarmling.tscn")
@export var active := true

@export_group("Rate")
@export var spawn_interval := 1.2
@export var per_burst := 2
@export var max_alive := 14           ## ceiling on THIS spawner's living children
@export var total_budget := -1        ## -1 = endless; otherwise the wave stops after N
@export var spawn_radius := 1.4
@export var start_delay := 0.5

@export_group("Trigger")
@export var activate_range := 20.0    ## player must be this close
@export var require_player := true

var _timer := 0.0
var _spawned := 0
var _alive: Array[Node] = []
var _player: Node3D
var _dead := false

@onready var _visuals: Node3D = $Visuals


func _ready() -> void:
	_timer = start_delay
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var health := get_node_or_null("Health") as Health
	if health:
		health.died.connect(_on_destroyed)
		health.damaged.connect(_on_damaged)


func _process(delta: float) -> void:
	if _dead or not active:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if require_player and _player == null:
			return
	_alive = _alive.filter(func(n): return is_instance_valid(n))

	# Idle pulse — a visible "this thing is live" tell so the player can find it.
	_visuals.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.004) * 0.05)

	if not _can_spawn():
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_burst()


func _can_spawn() -> bool:
	if _alive.size() >= max_alive:
		return false
	if total_budget >= 0 and _spawned >= total_budget:
		return false
	if require_player:
		if not is_instance_valid(_player):
			return false
		if global_position.distance_to(_player.global_position) > activate_range:
			return false
	return true


func _burst() -> void:
	var parent := get_parent()                 # siblings of the nest, so they die with the zone
	for i in per_burst:
		if _alive.size() >= max_alive:
			return
		if total_budget >= 0 and _spawned >= total_budget:
			return
		var s := swarm_scene.instantiate()
		parent.add_child(s)
		var a := randf() * TAU
		var r := sqrt(randf()) * spawn_radius   # sqrt = even area distribution, not centre-heavy
		(s as Node3D).global_position = global_position + Vector3(cos(a) * r, 0.4, sin(a) * r)
		_alive.append(s)
		_spawned += 1

	var fx := preload("res://scenes/fx/swarm_pop.tscn").instantiate()
	get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = global_position + Vector3(0, 0.5, 0)


## Flash on damage so it reads as hurtable rather than scenery.
func _on_damaged(_amount: int, _source: Node) -> void:
	var mesh := _visuals.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		var m := (mat as StandardMaterial3D).duplicate()
		mesh.set_surface_override_material(0, m)
		m.emission = Color(1, 1, 1)
		var t := create_tween()
		t.tween_property(m, "emission_energy_multiplier", 1.0, 0.25).from(6.0)


## Nest destroyed: stop spawning and collapse. Existing swarmlings are left alive on purpose — you
## still have to clean them up, the nest just stops replacing them.
func _on_destroyed() -> void:
	_dead = true
	active = false
	var hb := get_node_or_null("HurtBox") as Area3D
	if hb:
		hb.set_deferred("monitorable", false)
	EventBus.enemy_died.emit(self)
	EventBus.combat_impact.emit(0.4)

	for i in 3:                                # a bigger burst than a single swarmling pop
		var fx := preload("res://scenes/fx/swarm_pop.tscn").instantiate()
		get_tree().current_scene.add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3(
			randf_range(-0.4, 0.4), 0.3 + randf() * 0.5, randf_range(-0.4, 0.4))
	var t := create_tween()
	t.tween_property(_visuals, "scale", Vector3(1.5, 0.2, 1.5), 0.08)
	t.tween_property(_visuals, "scale", Vector3.ZERO, 0.15)
	t.tween_callback(queue_free)

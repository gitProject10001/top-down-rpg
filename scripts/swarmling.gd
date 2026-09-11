class_name Swarmling
extends CharacterBody3D
## A single member of the swarm: a little capsule that dies to ONE hit with a pop.
##
## DELIBERATELY NOT enemy.gd. That script carries poise, three attack kinds, animation trees and a
## telegraph — all correct for a duel with one foe, all wasted on something you kill in a single
## swing. A swarmling is cheap on purpose so there can be twenty of them.
##
## THE PATTERN IS EMERGENT, NOT SCRIPTED. Movement is classic boids — separation, cohesion,
## alignment — layered on top of "seek the player". Nobody authors the formation: it forms because
## every unit obeys the same four urges, so the swarm swirls, clumps and splits around obstacles on
## its own, and never looks choreographed twice.

@export var move_speed := 5.5
@export var accel := 14.0             ## how fast they change heading (low = lazy, high = twitchy)

@export_group("Attack")
@export var attack_range := 1.4
@export var attack_cooldown := 1.3
@export var strike_windup := 0.22     ## brief lunge tell — even a trash mob needs a readable beat
@export var hit_duration := 0.15

@export_group("Flocking")
@export var neighbor_radius := 3.5    ## who counts as "nearby" for cohesion/alignment
@export var separation_radius := 1.1  ## personal space; below this they push apart hard
@export var w_seek := 1.0
@export var w_separation := 2.0       ## highest weight — without it the swarm collapses to a dot
@export var w_cohesion := 0.3
@export var w_alignment := 0.4
@export var wobble := 0.4             ## vertical bob, so they skitter instead of gliding

var _player: Node3D
var _cool := 0.0
var _dead := false
var _phase := 0.0                     ## per-unit bob offset so they don't pulse in unison
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var _visuals: Node3D = $Visuals
@onready var _hitbox: HitBox = $Visuals/AttackHitBox
@onready var _health: Health = $Health


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_phase = randf() * TAU
	_cool = randf() * attack_cooldown          # stagger first strikes so they don't all lunge at once
	_health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_cool = maxf(_cool - delta, 0.0)
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	var steer := to_player.normalized() * w_seek + _flock()
	steer.y = 0.0
	if steer.length() > 0.001:
		steer = steer.normalized()

	# Close in, then hold at arm's length while the strike is on cooldown — this is what makes the
	# swarm ORBIT you instead of piling into your chest.
	var want := steer * move_speed
	if dist < attack_range * 0.85:
		want = -to_player.normalized() * move_speed * 0.5 + _flock() * move_speed * 0.5
	velocity.x = move_toward(velocity.x, want.x, accel * delta)
	velocity.z = move_toward(velocity.z, want.z, accel * delta)
	move_and_slide()

	# Face travel; bob on a per-unit phase so the mass shimmers rather than pulsing as one.
	var planar := Vector2(velocity.x, velocity.z)
	if planar.length() > 0.2:
		_visuals.rotation.y = lerp_angle(_visuals.rotation.y,
				atan2(-velocity.x, -velocity.z), 1.0 - exp(-12.0 * delta))
	_phase += delta * 9.0
	_visuals.position.y = sin(_phase) * 0.06 * wobble

	if dist <= attack_range and _cool <= 0.0:
		_strike()


## Boids in three lines of intent: keep apart, stay with the group, go the same way.
## O(n²) over the swarm group — fine because SwarmSpawner.max_alive caps the flock. If that cap ever
## rises a lot, this is the thing to replace with a spatial hash.
func _flock() -> Vector3:
	var sep := Vector3.ZERO
	var centre := Vector3.ZERO
	var heading := Vector3.ZERO
	var n := 0
	for other in get_tree().get_nodes_in_group("swarm"):
		if other == self or not is_instance_valid(other):
			continue
		var o := other as Node3D
		var d := o.global_position - global_position
		d.y = 0.0
		var len_sq := d.length_squared()
		if len_sq > neighbor_radius * neighbor_radius or len_sq < 0.0001:
			continue
		centre += o.global_position
		if "velocity" in other:
			heading += (other.velocity as Vector3)
		n += 1
		if len_sq < separation_radius * separation_radius:
			sep -= d.normalized() * (1.0 - sqrt(len_sq) / separation_radius)
	if n == 0:
		return sep * w_separation
	centre = centre / float(n) - global_position
	centre.y = 0.0
	heading.y = 0.0
	return sep * w_separation \
		+ centre.normalized() * w_cohesion \
		+ (heading.normalized() * w_alignment if heading.length() > 0.01 else Vector3.ZERO)


## A quick lunge, then a short damage window. The wind-up is tiny but non-zero on purpose: it gives
## the player something to react to even in a mob.
func _strike() -> void:
	_cool = attack_cooldown
	var t := create_tween()
	t.tween_property(_visuals, "scale", Vector3(0.8, 1.3, 0.8), strike_windup * 0.6)
	t.tween_property(_visuals, "scale", Vector3(1.25, 0.8, 1.25), 0.06)
	t.tween_callback(func():
		if not _dead:
			_hitbox.activate())
	t.tween_property(_visuals, "scale", Vector3.ONE, 0.12)
	t.tween_callback(_hitbox.deactivate).set_delay(hit_duration)


## One hit and they're gone — the whole point. Squash, burst, vanish.
func _on_died() -> void:
	_dead = true
	set_physics_process(false)
	_hitbox.deactivate()
	$Collision.set_deferred("disabled", true)
	$HurtBox.set_deferred("monitorable", false)
	EventBus.enemy_died.emit(self)

	var pop := preload("res://scenes/fx/swarm_pop.tscn").instantiate()
	get_tree().current_scene.add_child(pop)
	(pop as Node3D).global_position = global_position + Vector3(0, 0.35, 0)

	# No hitstop or camera shake here on purpose: the sword already provides both on a landed hit,
	# and firing them per-swarmling would turn a satisfying cleave into a stuttering mess.
	var t := create_tween()
	t.tween_property(_visuals, "scale", Vector3(1.7, 0.3, 1.7), 0.05)
	t.tween_property(_visuals, "scale", Vector3.ZERO, 0.09)
	t.tween_callback(queue_free)

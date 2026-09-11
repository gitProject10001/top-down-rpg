class_name TrainingDummy
extends CharacterBody3D
## A capsule that exists to be hit, and to say so clearly.
##
## WHY NOT enemy.gd: that script chases, telegraphs, strikes and staggers, and every one of those
## moves the target while you are trying to measure whether a swing reaches it. A dummy that HOLDS
## ITS POST is the only way to answer "does this attack connect from here" — the whole point of the
## distance study. It is also the honest way to feel the problem: when you miss a dummy standing
## still, the miss is yours and the geometry's, not the AI's.
##
## It still keeps a `drift` option, off by default, precisely because the user described attacks
## that only land because the enemy wandered into them. That is a real failure mode worth being
## able to reproduce on purpose rather than encounter by accident.
##
## Layers match the real enemies: HurtBox on layer 4, which is what the sword's HitBox masks.

signal was_hit(damage: int, from: Node)
signal was_healed

@export var max_hp := 999                ## a post, not an opponent — it should outlast the session
@export var flash_time := 0.16           ## how long the white hit-flash lasts
@export var recoil_distance := 0.22      ## how far a hit shoves it off its post (m)
@export var recoil_return := 6.0         ## how fast it springs back
@export var drift_speed := 0.0           ## >0 makes it wander; reproduces the "it walked into my swing" case
@export var drift_radius := 1.5

var hits := 0
var _post: Vector3                       ## where it stands; recoil is measured against this
var _offset := Vector3.ZERO              ## current displacement from the post
var _flash := 0.0
var _drift_angle := 0.0
var _mat: StandardMaterial3D
var _base_color := Color(0.72, 0.74, 0.78)

@onready var _mesh: MeshInstance3D = $Visuals/Mesh
@onready var _health: Health = $Health


func _ready() -> void:
	_post = global_position
	_drift_angle = randf() * TAU
	# Own copy of the material, so flashing THIS dummy doesn't flash the whole row of them.
	var m := _mesh.get_active_material(0)
	if m is StandardMaterial3D:
		_mat = (m as StandardMaterial3D).duplicate()
		_mesh.set_surface_override_material(0, _mat)
		_base_color = _mat.albedo_color
	_health.damaged.connect(_on_damaged)


## The radius a swing has to reach to touch this thing — read off the HurtBox rather than declared,
## so the distance study measures the shape that actually receives damage. Contact range for an
## attacker is its own reach() PLUS this.
func hurt_radius() -> float:
	var shape_node := $HurtBox/Shape as CollisionShape3D
	if shape_node and shape_node.shape is CapsuleShape3D:
		return (shape_node.shape as CapsuleShape3D).radius
	return 0.5


func _on_damaged(amount: int, source: Node) -> void:
	hits += 1
	_flash = flash_time
	# Shove directly away from whatever hit us. The sword's HitBox is player-anchored, so its
	# global_position is the swinger's centre — good enough for a recoil direction, and it means
	# the dummy leans away from the blow rather than in some arbitrary fixed direction.
	if source is Node3D:
		var away := global_position - (source as Node3D).global_position
		away.y = 0.0
		if away.length() > 0.01:
			_offset += away.normalized() * recoil_distance
	was_hit.emit(amount, source)
	# A post you can whittle down stops being a measuring instrument, so it heals straight back.
	if _health.hp < max_hp:
		_health.hp = max_hp
		was_healed.emit()


func _physics_process(delta: float) -> void:
	if drift_speed > 0.0:
		_drift_angle += delta * 0.7
		_post = _post.lerp(
			_post + Vector3(cos(_drift_angle), 0.0, sin(_drift_angle)) * drift_radius,
			1.0 - exp(-drift_speed * delta))
	_offset = _offset.lerp(Vector3.ZERO, 1.0 - exp(-recoil_return * delta))
	global_position = _post + _offset

	if _flash > 0.0:
		_flash -= delta
		if _mat:
			# Ease OUT of white rather than snapping back: a linear fade reads as a flash, a step
			# reads as a rendering glitch.
			var t := clampf(_flash / flash_time, 0.0, 1.0)
			_mat.albedo_color = _base_color.lerp(Color(1, 1, 1), t)
			_mat.emission_enabled = true
			_mat.emission = Color(1, 1, 1)
			_mat.emission_energy_multiplier = 2.5 * t
	elif _mat and _mat.emission_enabled:
		_mat.albedo_color = _base_color
		_mat.emission_enabled = false

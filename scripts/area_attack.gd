class_name AreaAttack
extends Node3D
## A telegraphed ground-slam: a red disc GROWS on the floor to warn the player, then after the
## wind-up a single damage PULSE fires inside that radius. Leave the circle — or dash through it
## with i-frames — to avoid it.
##
## Reuses the HitBox component for the actual damage, so the pulse routes through HurtBox → Health
## like every other hit (blockable, dodgeable via dash i-frames). The enemy just spawns one of
## these at its feet; all timing/visuals live here so the enemy code stays simple.

@export var windup := 0.7      ## seconds the telegraph grows before it detonates (self-run mode)
@export var radius := 4.0      ## blast radius (m)
@export var damage := 1

## When true, the SPAWNER owns the clock: it feeds set_progress() from the attacker's own action
## clock and calls detonate_now() on the strike beat. The self-running tween below only serves
## spawners with no clock of their own (the brute). An attacker whose wind-up can HOLD — the
## ogre's aim hold freezes its action clock for up to 0.7 s — must drive the disc, or the warning
## detonates before the blow it warns about; for the pound, where the ring IS the damage, that was
## a hit arriving early out of a circle that promised otherwise.
var driven := false

@onready var _tele: MeshInstance3D = $Telegraph
@onready var _hitbox: HitBox = $HitBox
@onready var _shape: CollisionShape3D = $HitBox/Shape

var _mat: StandardMaterial3D
var _detonated := false

## CONTACT. The pulse caught someone whose hp changed.
func _on_ring_landed(_target: Node, _pos: Vector3, applied: int) -> void:
	if applied > 0:
		CombatFeedback.contact_landed(0.08, 0.08, 0.3)

func _ready() -> void:
	# Size the damage cylinder to the blast radius (duplicate so we don't edit a shared resource).
	var cyl := (_shape.shape as CylinderShape3D).duplicate() as CylinderShape3D
	cyl.radius = radius
	_shape.shape = cyl
	_hitbox.damage = damage
	_hitbox.deactivate()
	# CONTACT weight for a caught pulse: the ring used to speak only on the BEAT (the fixed 0.5
	# detonation shake, hit or miss) — a player actually caught inside it deserved more than a
	# spectator's kick. Applied-gated like every contact.
	_hitbox.dealt_hit.connect(_on_ring_landed)

	# Our own copy of the telegraph material so we can pulse/fade this instance alone.
	_mat = ($Telegraph as MeshInstance3D).get_active_material(0).duplicate() as StandardMaterial3D
	_tele.material_override = _mat

	_tele.scale = Vector3(0.15, 1.0, 0.15)
	if driven:
		return
	# Grow the disc from a dot to full radius during the wind-up, pulsing brighter as it fills.
	var t := create_tween()
	t.tween_property(_tele, "scale", Vector3(radius, 1.0, radius), windup).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_method(_pulse, 0.0, 1.0, windup)
	t.tween_callback(_detonate)


## Driven mode: growth and pulse as a function of wind-up progress 0..1. Frozen input, frozen disc
## — which makes the ogre's aim hold VISIBLE: the circle stops growing while it waits for you.
func set_progress(f: float) -> void:
	if _detonated:
		return
	f = clampf(f, 0.0, 1.0)
	var s: float = maxf(0.15, radius * smoothstep(0.0, 1.0, f))
	_tele.scale = Vector3(s, 1.0, s)
	_pulse(f)


## Driven mode: the blow arrived — fire the pulse now, exactly on the attacker's strike beat.
func detonate_now() -> void:
	if _detonated:
		return
	_detonate()


## The attack behind this warning stopped existing (stagger, fear). Fade out without damage —
## a circle left promising a blow that is not coming devalues every future one.
func dismiss() -> void:
	if _detonated:
		return
	_detonated = true
	var t := create_tween()
	t.tween_property(_mat, "albedo_color:a", 0.0, 0.2)
	t.tween_callback(queue_free)


func _pulse(f: float) -> void:
	# Speed up the warning flash as detonation nears.
	var flash := 0.5 + 0.5 * sin(f * f * 40.0)
	_mat.emission_energy_multiplier = 1.0 + flash * 3.0

func _detonate() -> void:
	_detonated = true
	_hitbox.activate()                       # sweeps anyone standing inside the ring right now
	EventBus.combat_impact.emit(0.5)         # camera kick
	# White flash, then fade the disc out and clean up.
	_mat.albedo_color = Color(1, 1, 1, 0.7)
	_mat.emission = Color(1, 1, 1)
	_mat.emission_energy_multiplier = 5.0
	var t := create_tween()
	t.tween_interval(0.12)
	t.tween_callback(_hitbox.deactivate)
	t.tween_property(_mat, "albedo_color:a", 0.0, 0.35)
	t.tween_callback(queue_free)

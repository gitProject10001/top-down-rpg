class_name GroundWave
extends Node3D
## THE SURFACE ATTACK: a shockwave ring that PROPAGATES along the floor from where a lobbed
## shot lands. The damage lives on the WAVEFRONT — the travelling edge, not the disc: each
## target is tested exactly once, on the frame the ring's centre-line reaches them, and only
## if they are standing on ground near the wave's own plane. JUMP over it (Space — reachable
## from inside a guard, block.gd allows it), or dash through it (i-frames) — BLOCK does not
## help, and that asymmetry is deliberate: the purple bolt punishes guarding, the wave punishes
## standing, and between them the player learns that this enemy is answered with feet. The wave
## wears the same VIOLET family as the pierce bolt for exactly that reason: violet = the guard
## does not answer this.
##
## Damage goes straight to Health.take_damage, deliberately NOT through HurtBox.apply_hit —
## the interception path IS the blocking path, and this attack exists to be unblockable.
## (architecture.md's one-damage-path rule has this as its single sanctioned exception.)
## I-frames still work (Health checks them itself) and airborne bodies are skipped entirely.
##
## The visual is the impact-marker recipe (unshaded emissive torus), but the mesh's inner/outer
## radii are rewritten per frame instead of scaling the node — a scaled torus fattens its tube
## as it grows, and a 10 m ring would arrive as a wall of light rather than an edge.

@export var speed := 8.0            ## metres/sec the front travels
@export var max_radius := 10.0
@export var band := 0.55            ## VISUAL thickness of the edge; the hit test is centre-line
@export var damage := 1
## Shove on hit, read off this node's meta by the victim's damage handler. NOTE that handler
## takes maxf(its own default 8.0, this) — the meta is a RAISE-ONLY override, so a value at or
## below 8 is a dead dial. Authored above it so the wave's toss actually reads as the wave's.
@export var knockback := 9.5
@export var target_group := "player"
@export var color := Color(0.8, 0.3, 1.0)

var _r := 0.0
var _dying := false
var _announced := false
var _passed: Array[Node] = []       ## a wavefront passes each body once, hit or not

@onready var _ring: MeshInstance3D = $Ring
var _mesh: TorusMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	set_meta("knockback", knockback)
	# Per-instance mesh AND material: the mesh because we animate its radii, the material
	# because two overlapping waves fading independently must not share an alpha.
	_mesh = (_ring.mesh as TorusMesh).duplicate() as TorusMesh
	_ring.mesh = _mesh
	_mat = (_ring.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
	_mat.emission = color
	_ring.material_override = _mat


func _physics_process(delta: float) -> void:
	if _dying:
		return
	if not _announced:
		# The crater thump — HERE and not in _ready, because _ready runs during add_child,
		# BEFORE the spawner has set global_position (projectile.gd's trail documents the same
		# trap): announced from _ready, the dust bursts at the world origin instead.
		_announced = true
		CombatFeedback.beat_dust(global_position, 1.6)
		CombatFeedback.beat_shake(0.25)
	var prev := _r
	_r += speed * delta
	_mesh.inner_radius = maxf(_r - band * 0.5, 0.02)
	_mesh.outer_radius = _r + band * 0.5
	# The front loses presence as it spends itself — alpha and glow fade with distance run.
	var life := clampf(1.0 - _r / max_radius, 0.0, 1.0)
	_mat.albedo_color.a = 0.15 + 0.45 * life
	_mat.emission_energy_multiplier = 0.6 + 2.4 * life

	# Hit when the ring's CENTRE-LINE crosses a body ("jump when it touches me" must work —
	# testing at the leading edge fired ~2 frames before the visible ring arrived). Frame steps
	# are ~0.13 m at this speed, so consecutive (prev, _r] intervals tile the floor gaplessly.
	for t in get_tree().get_nodes_in_group(target_group):
		if t in _passed or not (t is CharacterBody3D):
			continue
		var body := t as CharacterBody3D
		var d := Vector2(body.global_position.x - global_position.x,
				body.global_position.z - global_position.z).length()
		if d > _r + 0.001:
			continue                          # the front has not reached them yet
		_passed.append(t)                     # reached this frame — one test, now or never
		if d <= prev - 0.001:
			continue                          # entered the interior mid-life (teleport, respawn)
		if not body.is_on_floor():
			continue                          # airborne: the whole point of the jump
		if absf(body.global_position.y - global_position.y) > 1.5:
			continue                          # grounded on OTHER ground — a ledge above the wave
		var h := body.get_node_or_null("Health") as Health
		if h != null and h.take_damage(damage, self) > 0:
			CombatFeedback.contact_landed(0.04, 0.2, 0.2)

	if _r >= max_radius:
		_dying = true
		var tw := create_tween()
		tw.tween_property(_mat, "albedo_color:a", 0.0, 0.2)
		tw.tween_callback(queue_free)

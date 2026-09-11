class_name TetherAnchor
extends StaticBody3D
## A ring on a post, across a gap or behind bars. The Aegis Tether pulls it; you cannot reach it.
##
## That unreachability is the point: an anchor you could walk up to and press E on would be a
## button, and the room would teach nothing about the rope. Placement puts it where the player can
## SEE it and not stand next to it.

signal pulled

const TINT := Color(0.55, 0.85, 0.95)      ## the tether's own colour, so the answer is legible

## What this opens. Anything with an open() — a SliceGate, or a DungeonDoor if you are feeling
## brave. Left empty it just emits `pulled` and something else can listen.
@export var opens_path: NodePath

var _spent := false
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group("tether_anchor")
	collision_layer = 1
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.8, 0.5)
	shape.shape = box
	shape.position.y = 0.9
	add_child(shape)

	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.34, 1.7, 0.34)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.26, 0.25, 0.29)
	pm.material = post_mat
	post.mesh = pm
	post.position.y = 0.85
	post.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(post)

	# The ring glows, because it has to be readable as a TARGET from across a gap the player cannot
	# cross. It is emissive rather than lit: this carries no Light3D at all, which keeps it out of
	# the room-lighting rule about mounts and door clearance entirely.
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.36
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = TINT
	ring_mat.emission_enabled = true
	ring_mat.emission = TINT
	ring_mat.emission_energy_multiplier = 2.4
	tm.material = ring_mat
	_ring.mesh = tm
	_ring.position.y = 1.75
	_ring.rotation.x = PI * 0.5
	_ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _process(delta: float) -> void:
	if not _spent:
		_ring.rotate_y(delta * 1.1)          # the same idle spin DungeonKey uses to say "interactive"


## The rope caught. Throw the lever and open whatever it was wired to.
func pull() -> void:
	if _spent:
		return
	_spent = true
	remove_from_group("tether_anchor")
	set_process(false)

	var t := create_tween()
	t.tween_property(_ring, "position:y", 1.35, 0.18)
	t.tween_property(_ring, "position:y", 1.75, 0.22)

	var target := get_node_or_null(opens_path)
	if target and target.has_method("open"):
		target.open()
	pulled.emit()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.combat_impact.emit(0.3)

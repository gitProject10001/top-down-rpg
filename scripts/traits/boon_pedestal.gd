class_name BoonPedestal
extends Area3D
## Rises out of the floor when a room clears. Walk into it and choose one of three.
##
## BUILT AT CLEAR TIME, not at generation. That is worth stating because it is what keeps this
## invisible to the dungeon's test suites entirely — no suite ever enters or clears a room, so
## anything that exists only after a fight is structurally outside what they measure. The pedestal
## is the one piece of slice furniture that lands in EVERY room, and it costs nothing.
##
## It grows by SCALE rather than rising from below the floor. RoomGI sizes a room's lighting probe
## to contain the lowest AABB of everything under it, visible or not, so a pedestal parked at
## -1.2 m while it waits would quietly make that room's GI coarser for the whole run.

const TINT := Color(1.0, 0.86, 0.55)
const RISE := 0.55

var _used := false
var _column: Node3D
var _ring: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	shape.position.y = 0.8
	add_child(shape)

	_column = Node3D.new()
	_column.scale.y = 0.02
	add_child(_column)

	var plinth := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.42
	pm.bottom_radius = 0.58
	pm.height = 1.1
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.28, 0.27, 0.31)
	stone.roughness = 0.95
	pm.material = stone
	plinth.mesh = pm
	plinth.position.y = 0.55
	plinth.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_column.add_child(plinth)

	# The offer itself: a slowly turning ring above the stone. Emissive rather than lit — this
	# carries no Light3D, which keeps it clear of the room-lighting rule about how far a mount has
	# to stand from a doorway, and a pedestal can therefore rise wherever the fight left room.
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.34
	var glow := StandardMaterial3D.new()
	glow.albedo_color = TINT
	glow.emission_enabled = true
	glow.emission = TINT
	glow.emission_energy_multiplier = 2.6
	tm.material = glow
	_ring.mesh = tm
	_ring.position.y = 1.45
	_ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.add_child(_ring)

	var t := create_tween()
	t.set_ease(Tween.EASE_OUT)
	t.set_trans(Tween.TRANS_BACK)
	t.tween_property(_column, "scale:y", 1.0, RISE)


func _process(delta: float) -> void:
	if not _used:
		_ring.rotate_y(delta * 0.9)


func _on_body_entered(body: Node3D) -> void:
	if _used or not body.is_in_group("player"):
		return
	var sheet := get_node_or_null("/root/Sheet")
	if sheet == null or sheet.active:
		return
	_used = true
	sheet.offer_boons()
	var t := create_tween()
	t.tween_interval(0.1)
	t.tween_property(_column, "scale:y", 0.02, 0.35)
	t.tween_callback(queue_free)

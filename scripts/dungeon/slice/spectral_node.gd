class_name SpectralNode
extends StaticBody3D
## Geometry that is not there until it is looked at with the right light. The Sunfire Lantern's
## reveal is what makes it real — before that it is invisible AND intangible.
##
## BOTH, and this is the only interesting decision in the file. An invisible bridge you can already
## walk across is not a puzzle, it is a rendering bug: the player crosses the gap by accident, never
## learns the lantern does this, and the room's whole idea is spent. So the collision shape starts
## disabled and the reveal is what switches it on.
##
## Disabled via set_deferred, never by assignment — this may be revealed from inside a physics
## callback (the lantern fires from an input frame, but the tools are used mid-collision as often as
## not), and mutating a shape mid-flush is how Jolt ends up with a body it is still iterating.
##
## The layer stays 1 throughout. Zeroing the collision LAYER would have been the obvious way to make
## it non-solid, and it would trip the suite's rule that every StaticBody3D in a dungeon is on
## layer 1 — the shape is the switch, not the layer.

const TINT := Color(0.72, 0.52, 0.95)      ## Perception's violet: the tool that finds it is a lens

@export var deck := Vector3(4.0, 0.35, 4.0)

var revealed := false

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("spectral")
	collision_layer = 1
	collision_mask = 0

	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = deck
	_shape.shape = box
	add_child(_shape)
	_shape.set_deferred("disabled", true)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(TINT.r, TINT.g, TINT.b, 0.0)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = TINT
	_mat.emission_energy_multiplier = 0.0

	var box_mesh := BoxMesh.new()
	box_mesh.size = deck
	box_mesh.material = _mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box_mesh
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.visible = false
	add_child(_mesh)


## Lit at last. Fades in and becomes solid.
func reveal() -> void:
	if revealed:
		return
	revealed = true
	remove_from_group("spectral")             # revealed once; the lantern stops paying it attention
	_mesh.visible = true
	# SOLID IMMEDIATELY, visible over 0.4 s. The other order would let a player who reacted fast
	# fall through a bridge they can already see.
	_shape.set_deferred("disabled", false)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_mat, "albedo_color:a", 0.85, 0.4)
	t.tween_property(_mat, "emission_energy_multiplier", 0.9, 0.4)
	# Whatever was standing on it was hidden too — a platform that appears under a prize you could
	# already see and take is not much of a secret. Cascading rather than exporting a path keeps the
	# relationship where it is obvious: it is on the platform, so it comes with the platform.
	for c in get_children():
		if c.has_method("reveal"):
			c.reveal()
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.combat_impact.emit(0.2)

class_name InsightPickup
extends Area3D
## What is behind the wall, or in the vault, or at the bottom of the puzzle: Insight, sometimes an
## idea, sometimes a tool you did not descend with.
##
## Deliberately one node for all three, because they are all the same beat — a reward for having
## noticed something — and three near-identical pickup scripts would drift.
##
## NOT a DungeonKey and never scripted as one: the lock suite takes the first DungeonKey it finds
## and requires every locked door in the dungeon to match its id, so a second key-shaped thing with
## a different id fails an assertion about a system it has nothing to do with.

const TINT := Color(1.0, 0.86, 0.55)

@export var insight := 3
@export var grants_conviction := ""            ## a Conviction id, or "" for none
@export var grants_tool := ""                  ## a ToolWeapon name, or "" for none
@export_multiline var flavour := ""            ## shown as a murmur when taken

## Start unseen and untakeable, waiting for reveal(). A reward you can pick up before you have
## solved the thing hiding it is not a reward, it is a bug that looks like generosity — so the
## Area3D stops monitoring too, not just rendering.
@export var hidden := false

var _taken := false
var _spin: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1                         # the player's CharacterBody3D lives on layer 1
	monitorable = false
	body_entered.connect(_on_body_entered)
	if hidden:
		visible = false
		set_deferred("monitoring", false)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	shape.shape = sphere
	shape.position.y = 0.7
	add_child(shape)

	_spin = Node3D.new()
	_spin.position.y = 0.8
	add_child(_spin)

	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.45, 0.7, 0.45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TINT
	mat.emission_enabled = true
	mat.emission = TINT
	mat.emission_energy_multiplier = 2.2
	mesh.material = mat
	mi.mesh = mesh
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(mi)


## Uncovered — by a wall coming down, or by a light finding the platform it was sitting on.
func reveal() -> void:
	if not hidden:
		return
	hidden = false
	visible = true
	set_deferred("monitoring", true)


func _process(delta: float) -> void:
	if not _taken:
		_spin.rotate_y(delta * 1.5)
		_spin.position.y = 0.8 + sin(Time.get_ticks_msec() / 600.0) * 0.06


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true

	var traits := get_node_or_null("/root/Traits")
	if traits:
		if insight > 0:
			traits.add_insight(insight)
		if grants_conviction != "":
			traits.gain_conviction(grants_conviction)

	if grants_tool != "":
		var belt := body.find_child("ToolBelt", true, false)
		if belt and belt.has_method("unlock"):
			belt.unlock(grants_tool)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.combat_impact.emit(0.25)

	if flavour != "":
		var notice := get_node_or_null("/root/Notice")
		if notice and traits:
			notice.murmur(traits.Attr.PERCEPTION, flavour)

	queue_free()

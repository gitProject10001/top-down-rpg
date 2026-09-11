class_name Shield
extends Node3D
## The player's shield component. Rests at the arm; raise() swings it to a front guard pose, lower()
## returns it. flash_parry() pulses its emission on a successful parry. Pure visuals + poses — the
## block/parry damage rules live in the Block state / player (single place damage flows through).

@onready var _mesh: MeshInstance3D = $Mesh
var _mat: StandardMaterial3D
var hand_driven := false   ## shield rides the left-hand socket; the arm is raised procedurally
var _recoil := 0.0         ## 0..1 brace-back kick when the shield eats a hit

func _ready() -> void:
	var m := _mesh.get_active_material(0)
	if m is StandardMaterial3D:
		_mat = (m as StandardMaterial3D).duplicate()
		_mesh.set_surface_override_material(0, _mat)

## Damped hand-follow (see Sword.follow_grip) — same weight trick, stiffer constant. The recoil
## kick is layered ON TOP each frame (a plain tween would be overwritten by this follow).
func follow_grip(target: Transform3D, k: float) -> void:
	global_transform = global_transform.interpolate_with(target, k)
	if _recoil > 0.001:
		translate_object_local(Vector3(0.0, 0.0, _recoil * 0.09))   # brief brace toward the body

## Quick procedural jolt when the shield blocks/parries a hit (replaces the old flinch clip).
func recoil() -> void:
	_recoil = 1.0
	create_tween().tween_property(self, "_recoil", 0.0, 0.18).set_trans(Tween.TRANS_QUAD)

func raise() -> void:
	if hand_driven:
		return   # the block clip raises the ARM — the shield just rides the hand
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position", Vector3(0.35, 0.25, -0.55), 0.12)
	t.parallel().tween_property(self, "rotation:y", deg_to_rad(-35), 0.12)

func lower() -> void:
	if hand_driven:
		return
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "position", Vector3.ZERO, 0.15)
	t.parallel().tween_property(self, "rotation:y", 0.0, 0.15)

func flash_parry() -> void:
	if _mat == null:
		return
	_mat.emission_enabled = true
	_mat.emission = Color(0.6, 0.9, 1.0)
	var t := create_tween()
	t.tween_method(func(e: float): _mat.emission_energy_multiplier = e, 5.0, 0.0, 0.35)

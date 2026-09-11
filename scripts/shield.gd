class_name Shield
extends Node3D

var hand_driven := false
var _recoil := 0.0

func follow_grip(target: Transform3D, weight: float) -> void:
	global_transform = global_transform.interpolate_with(target, weight)

func raise() -> void: pass
func lower() -> void: pass
func recoil() -> void: _recoil = 1.0
func flash_parry() -> void: pass

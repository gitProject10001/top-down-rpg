class_name PlayerIntent
extends FighterIntent

@export var stick_deadzone := 0.45
@export var mouse_pixels := 26.0
@export var screen_relative_directions := true
var _mirror_screen := false
var _mouse_travel := Vector2.ZERO
var _screen_guard := SwingDir.UP
var _screen_attack := SwingDir.UP

func _input(event: InputEvent) -> void:
	if guard or attack_held:
		if event is InputEventMouseMotion:
			_mouse_travel += (event as InputEventMouseMotion).relative

func _physics_process(_delta: float) -> void:
	var p := fighter()
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move = raw
	if p:
		var rig := get_tree().get_first_node_in_group("camera_rig") as Node3D
		if rig:
			var v := Vector3(raw.x, 0.0, raw.y).rotated(Vector3.UP, rig.global_rotation.y)
			move = Vector2(v.x, v.z)
	look = Vector2.ZERO
	var was_held := attack_held
	guard = Input.is_action_pressed("block")
	attack_held = Input.is_action_pressed("attack") or Input.is_action_just_pressed("attack")
	var d := _direction()
	if d != SwingDir.NONE:
		if guard: _screen_guard = d
		if attack_held: _screen_attack = d
	_update_direction_frame()
	guard_dir = local_direction(_screen_guard)
	attack_dir = local_direction(_screen_attack)
	if was_held and not attack_held:
		request_release()
	if not (guard or attack_held):
		_mouse_travel = Vector2.ZERO

func _update_direction_frame() -> void:
	var p := fighter()
	var camera := get_viewport().get_camera_3d()
	if p == null or camera == null: return
	# Sideways poses are ambiguous: hysteresis avoids rapid left/right toggling.
	var alignment: float = p.visuals.global_basis.x.normalized().dot(camera.global_basis.x)
	if alignment > 0.15: _mirror_screen = false
	elif alignment < -0.15: _mirror_screen = true

func local_direction(direction: int) -> int:
	return SwingDir.mirror(direction) if screen_relative_directions and _mirror_screen else direction

## Inverse mapping for HUD. AI and hitboxes continue to speak actor-local directions.
func screen_direction(direction: int) -> int:
	return local_direction(direction)

func _direction() -> int:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var d := SwingDir.from_vector(stick, stick_deadzone)
	if d != SwingDir.NONE:
		_mouse_travel = Vector2.ZERO
		return d
	if _mouse_travel.length() >= mouse_pixels:
		d = SwingDir.from_vector(_mouse_travel.normalized(), 0.0)
		_mouse_travel = Vector2.ZERO
		return d
	return SwingDir.NONE

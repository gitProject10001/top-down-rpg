class_name PlayerIntent
extends FighterIntent

@export var stick_deadzone := 0.45
@export var mouse_pixels := 26.0
@export var screen_relative_directions := true
@export var attack_press_memory := 0.35
var _mirror_screen := false
var _mouse_travel := Vector2.ZERO
var _screen_guard := SwingDir.UP
var _screen_attack := SwingDir.RIGHT
var _attack_down := false
var _attack_press_left := 0.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_sample_attack_button(true)
	elif event.is_action_released("attack"):
		_sample_attack_button(false)
	if guard or attack_held:
		if event is InputEventMouseMotion:
			_mouse_travel += (event as InputEventMouseMotion).relative

func _physics_process(delta: float) -> void:
	_attack_press_left = maxf(0.0, _attack_press_left - delta)
	var p := fighter()
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move = raw
	if p:
		var rig := get_tree().get_first_node_in_group("camera_rig") as Node3D
		if rig:
			var v := Vector3(raw.x, 0.0, raw.y).rotated(Vector3.UP, rig.global_rotation.y)
			move = Vector2(v.x, v.z)
	look = Vector2.ZERO
	guard = Input.is_action_pressed("block")
	# Input events latch even a complete click between two physics frames. Polling
	# also supports Input.action_press and a held button when focus is restored.
	_sample_attack_button(Input.is_action_pressed("attack"))
	var d := _direction()
	if d != SwingDir.NONE:
		if guard: _screen_guard = d
		if attack_held: _screen_attack = d
	_update_direction_frame()
	guard_dir = local_direction(_screen_guard)
	attack_dir = local_direction(_screen_attack)
	if not (guard or attack_held):
		_mouse_travel = Vector2.ZERO

func _sample_attack_button(down: bool) -> void:
	if down != _attack_down:
		_attack_down = down
		if down:
			_attack_press_left = attack_press_memory
		else:
			request_release()
	attack_held = down

func can_start_attack() -> bool:
	return _attack_press_left > 0.0

func consume_attack() -> void:
	super()
	_attack_press_left = 0.0

## One edge pays for one swing. Holding, key repeat and discarded combo presses
## cannot start another attack when the state returns to Idle.
func consume_combo_press() -> bool:
	if _attack_press_left <= 0.0:
		return false
	_attack_press_left = 0.0
	return true

func clear() -> void:
	super()
	_attack_press_left = 0.0
	# Keep the physical level: an interruption must require a fresh press.

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

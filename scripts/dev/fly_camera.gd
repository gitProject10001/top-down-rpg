class_name FlyCamera
extends Camera3D
## Free-fly camera for the dev scenes. Deliberately reads RAW KEYS rather than input actions:
## it must keep working if the project's input map changes, and it must not fight the gameplay
## bindings when a dev scene is opened next to the real game.
##
## PHYSICAL keys, not keycodes, and this is not a detail. `is_key_pressed` reports the key's LABEL,
## which depends on the OS keyboard layout: on AZERTY the key in the QWERTY-W position reports Z, so
## forward was simply unbound, and the key under the left hand's natural "strafe left" finger
## reported Q and flew the camera DOWNWARD. `is_physical_key_pressed` addresses the position on the
## board instead, so this is WASD on QWERTY and ZQSD on AZERTY with no branch and no setting — which
## is what every game does and what a hand expects.
##
## Look is HELD on right-mouse rather than always-on, because these scenes have a tuning panel —
## an always-captured cursor would make the sliders unusable.
##
##   RMB drag  look        W/A/S/D  move (physical positions)    Q/E  down/up
##   Shift     x3 speed    wheel    change speed (while looking)

@export var speed := 9.0
@export var boost := 3.0
@export var sensitivity := 0.0022

var _looking := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if _looking
					else Input.MOUSE_MODE_VISIBLE)
		elif _looking and mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				speed = minf(speed * 1.15, 200.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				speed = maxf(speed / 1.15, 0.5)
	elif event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		rotation.y -= mm.relative.x * sensitivity
		# Clamp pitch just short of straight up/down so the camera can never gimbal over.
		rotation.x = clampf(rotation.x - mm.relative.y * sensitivity, -1.54, 1.54)
		rotation.z = 0.0


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir -= basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += basis.x
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): dir -= Vector3.UP
	if dir == Vector3.ZERO:
		return
	var mult := boost if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	global_position += dir.normalized() * speed * mult * delta

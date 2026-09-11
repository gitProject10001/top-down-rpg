class_name PlayerIntent
extends FighterIntent
## A PERSON'S intent: the half of FighterIntent that knows about Input, cameras and mice.
##
## THE DIRECTION COMES FROM THE RIGHT STICK, which was already declared in project.godot as the
## four `aim_*` actions and read by nothing — camera_rig.gd orbits off the raw axes, and
## player.gd:556 deliberately refuses to let axis 2/3 flip its aim mode. So the actions existed
## with nobody listening, and this is the listener. No new bindings.
##
## AND FROM THE MOUSE, which is how Mount & Blade has always read it: hold the button, move the
## mouse, and the way you moved it is the way you swing. The cursor already steers `aim_point`, so
## what is read here is TRAVEL — accumulated relative motion since the button went down — rather
## than position. It has to clear a threshold before it commits, or the hand's own tremor would
## pick a direction for you.
##
## The movement mapping below is player.gd's old get_move_input, moved here whole. It belongs on
## this side of the line: camera-relative WASD is a fact about a person at a screen.

## How far the stick must be pushed before it names a direction. Higher than the actions' own 0.25
## deadzone: at 0.25 a stick resting off-centre would silently change your guard.
@export var stick_deadzone := 0.45

## Pixels of mouse travel that commit a direction. About a centimetre at ordinary sensitivity —
## a deliberate flick, not a drift.
@export var mouse_pixels := 26.0

var _mouse_travel := Vector2.ZERO
var _camera_rig: Node3D
var _screen_flipped := false
var _screen_guard := SwingDir.UP
var _screen_attack := SwingDir.UP

## Horizontal screen/local conversion is its own inverse. Near a side-on
## silhouette keep the last mapping to avoid flickering between two guards.
func screen_direction(local_direction: int) -> int:
	var p := fighter()
	if _camera_rig == null:
		_camera_rig = get_tree().get_first_node_in_group("camera_rig") as Node3D
	if p and _camera_rig:
		var alignment := p.visuals.global_basis.x.normalized().dot(_camera_rig.global_basis.x.normalized())
		if alignment > .15: _screen_flipped = false
		elif alignment < -.15: _screen_flipped = true
	return SwingDir.mirror(local_direction) if _screen_flipped else local_direction


## Mouse travel is accumulated in _input rather than sampled per tick, because a fast flick can
## cross the whole threshold inside one physics frame and polling would only ever see where it
## ended up. Non-consuming: the states still get every event they had before.
func _input(event: InputEvent) -> void:
	if not (guard or attack_held):
		return
	if event is InputEventMouseMotion:
		_mouse_travel += (event as InputEventMouseMotion).relative


func _physics_process(_delta: float) -> void:
	var p := fighter()
	if p == null:
		return

	move = _move_world(p)
	var locked_target := p.combat_lock_target()
	if locked_target:
		var bearing := locked_target.global_position-p.global_position
		look = Vector2(bearing.x,bearing.z).normalized()
	else:
		look = Vector2.ZERO

	var was_held := attack_held
	guard = Input.is_action_pressed("block")
	# THE TAP THAT FALLS BETWEEN TWO FRAMES. is_action_pressed is a level, and a click shorter than
	# one physics tick (16.7 ms is easy to beat) is never seen down at all — so the click did
	# nothing and the swing was simply eaten. is_action_just_pressed reports the edge that happened
	# since the last tick, which holds the press for exactly the one frame the state needs to see
	# it; dir_attack.gd then makes the swing finish its wind-up whatever happens next.
	attack_held = Input.is_action_pressed("attack") or Input.is_action_just_pressed("attack")
	if not (guard or attack_held):
		_mouse_travel = Vector2.ZERO

	var d := _direction()
	if d != SwingDir.NONE:
		# ONE READING FEEDS BOTH, and the guard only listens while it is up. Otherwise a stick
		# pushed left during a swing would also be re-aiming a guard nobody is holding, and the
		# guard you raise afterwards would point somewhere you chose for a different reason.
		if guard:
			_screen_guard = d
		if attack_held:
			_screen_attack = d
	if guard:
		guard_dir = screen_direction(_screen_guard)
	if attack_held:
		attack_dir = screen_direction(_screen_attack)

	# The button came up: throw it. Ordering matters — attack_held has already been updated, so a
	# state polling `attack_held` this same tick sees the wind-up finished and the release waiting.
	if was_held and not attack_held:
		request_release()


## Stick first, mouse second. A pad plugged in wins while it is being pushed; let go and the mouse
## can still speak, which is what a person switching devices mid-fight expects.
func _direction() -> int:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var from_stick := SwingDir.from_vector(stick, stick_deadzone)
	if from_stick != SwingDir.NONE:
		_mouse_travel = Vector2.ZERO
		return from_stick
	if _mouse_travel.length() >= mouse_pixels:
		var d := SwingDir.from_vector(_mouse_travel.normalized(), 0.0)
		_mouse_travel = Vector2.ZERO
		return d
	return SwingDir.NONE


## MOVEMENT INTENT MAPPED TO WORLD AXES THROUGH THE CAMERA'S YAW: when a CameraZone swings the rig
## (e.g. the warehouse), screen-up keeps meaning "away from the camera" — WASD stays
## screen-relative. With the default yaw of 0 this is exactly the old world-axis mapping.
##
## Lock controls facing only. Movement always follows the camera's horizontal
## axes, so selecting or circling an enemy never rotates the controls.
func _move_world(p: Player) -> Vector2:
	if Dialogue.active:
		return Vector2.ZERO                  # frozen while talking to an NPC
	# Drawing the bow on a controller: plant and AIM with the left stick — don't walk. (Mouse+kb
	# keeps the kite-and-shoot shuffle, since it aims with the cursor and moves with WASD.)
	if p.gamepad_aim() and p.state_name() == "Shoot":
		return Vector2.ZERO
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _camera_rig == null:
		_camera_rig = get_tree().get_first_node_in_group("camera_rig") as Node3D
		if _camera_rig == null:
			return raw
	var yaw: float = _camera_rig.global_rotation.y
	var v := Vector3(raw.x, 0.0, raw.y).rotated(Vector3.UP, yaw)
	return Vector2(v.x, v.z)

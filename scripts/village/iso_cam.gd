extends Camera3D
## Top-down orbit camera with narrow perspective and an orthographic fallback.
## FOV controls perspective strength; framing matching derives viewing distance
## from the existing ortho_size span. Pixel snapping is orthographic-only.

## What to follow. Empty leaves the camera wherever it was placed, which is what the fixed hero
## framing and the --shot renders use.
@export var target_path: NodePath

@export_group("Framing")
## Narrow perspective preserves the top-down composition while showing depth.
@export var perspective_enabled := false
@export_range(10.0, 40.0, 0.5) var perspective_fov := 20.0
## Match ortho_size at the focus plane; distance then follows FOV and combat zoom.
@export var match_perspective_framing := true
## Down-angle. The reference sits near 55 degrees -- high enough to read the ground plan, shallow
## enough that roofs and tent sides still show a face.
@export_range(20.0, 89.0, 0.5) var pitch_deg := 55.0
## Rotation about the vertical. 45 is the true isometric quarter-view.
@export_range(-180.0, 180.0, 0.5) var yaw_deg := 45.0
## How far back along the view axis. Orthographic, so this only decides what is in front of the
## near plane -- not how big anything looks. That is ortho_size.
@export_range(5.0, 200.0, 0.5) var distance := 40.0
## Metres of world visible top to bottom. THIS is the zoom.
@export_range(2.0, 60.0, 0.25) var ortho_size := 13.0
## Metres above the target's origin to actually look at, so a 1.8 m character sits in frame rather
## than at the bottom edge.
@export var focus_height := 1.1

@export_group("Follow")
## Metres per second of catch-up, as an exponential rate. 0 pins the camera to the target exactly.
@export_range(0.0, 30.0, 0.5) var follow_rate := 9.0
## Lead the camera toward where the target is heading. Small, or the frame swims.
@export_range(0.0, 4.0, 0.05) var look_ahead := 0.0

@export_group("Free look")
## TURN THE WORLD WHEN NOBODY HAS YOUR ATTENTION. yaw_deg is the angle the camera STARTS at, not
## one it is pinned to: with nothing locked, camera_left/camera_right walk the yaw around and it
## stays wherever it is left. There is no limit and no recentre, so the turn is a real 360 — the
## angle wraps rather than running into a stop.
##
## WHY IT IS SAFE TO SPIN A FIXED-ANGLE LOOK. The three things that could have broken do not:
## movement is already re-based every frame off this camera's own yaw (player_intent.gd:20-23), the
## pixel snap rounds along the camera's axes rather than the world's, and the camp is real geometry
## rather than cards facing one direction. Only the pitch is fixed, and that is the part the
## axonometric read actually depends on.
@export var free_rotate := false
## Independent of free orbit: lock may frame the pair without rotating the view.
@export var lock_rotate := false
## Degrees per second at full deflection.
@export_range(15.0, 360.0, 5.0) var rotate_speed_deg := 110.0

@export_group("Pixels")
@export var pixel_snap := true
## Set from the scene driver when it knows the real render height; falls back to the viewport's.
@export var pixel_rows := 0

var _focus := Vector3.ZERO
var _target: Node3D = null
var _have_focus := false
var _lock_target: Node3D
var _lock_marker: Label3D
@export var lock_range := 9.0
@export var lock_yaw_slack_deg := 15.0
@export var lock_turn_speed_deg := 85.0
@export_range(.7,1.0,.01) var lock_zoom_ratio := .86
var _view_yaw := 0.0
var _lock_mix := 0.0
## Where free look has left the camera. Seeded from yaw_deg, then owned by the player — and kept in
## step with _view_yaw while a lock is on, so dropping the lock does not whip the world back to the
## angle it started the session at.
var _free_yaw := 0.0

func locked() -> Node3D:
	return _lock_target if is_instance_valid(_lock_target) else null


## THE ONE CASE WHERE TURNING THE CAMERA IS WRONG. Both the right stick and the mouse pick a swing
## direction in SCREEN space, so rotating the view mid-guard or mid-wind-up moves the target the
## player is already aiming at. The lock path refuses to rotate under a released strike for exactly
## this reason; free look refuses for the whole of both directional states.
func _rotation_allowed() -> bool:
	if not free_rotate or locked() != null or Dialogue.active:
		return false
	if _target != null and _target.has_method("state_name"):
		var state: String = _target.state_name()
		if state == "DirAttack" or state == "Guard":
			return false
	return true

func _physics_process(_delta: float) -> void:
	# Poll the action here: this camera lives inside the pixel SubViewport,
	# where unhandled input can be consumed before reaching the camera.
	if Dialogue.active:
		_lock_target = null
	elif Input.is_action_just_pressed("lock_on"):
		if locked(): _lock_target = null
		else: _select_lock()
	elif Input.is_action_just_pressed("lock_cycle"):
		_select_lock(true)
	if locked():
		var hp := _lock_target.get_node_or_null("Health") as Health
		if (hp and not hp.is_alive()) or not is_instance_valid(_target) or _target.global_position.distance_to(_lock_target.global_position) > lock_range*1.4:
			_lock_target = null
	if _lock_marker:
		_lock_marker.visible = locked() != null
		if locked(): _lock_marker.global_position = _lock_target.global_position+Vector3.UP*2.0

func _select_lock(cycle := false) -> void:
	if not is_instance_valid(_target): return
	var candidates: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		if not node is Node3D or node.get_world_3d() != get_world_3d(): continue
		var hp := node.get_node_or_null("Health") as Health
		if hp and not hp.is_alive(): continue
		if _target.global_position.distance_to(node.global_position) <= lock_range:
			candidates.append(node)
	candidates.sort_custom(func(a: Node3D,b: Node3D): return _target.global_position.distance_squared_to(a.global_position) < _target.global_position.distance_squared_to(b.global_position))
	if candidates.is_empty(): return
	var index := candidates.find(locked())
	_lock_target = candidates[(index+1)%candidates.size()] if cycle else candidates[0]
	if not _lock_marker:
		_lock_marker = Label3D.new()
		_lock_marker.text = "◇"
		_lock_marker.font_size = 48
		_lock_marker.pixel_size = .006
		_lock_marker.modulate = Color(1,.8,.25)
		_lock_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		get_parent().add_child(_lock_marker)


func _ready() -> void:
	projection = PROJECTION_PERSPECTIVE if perspective_enabled else PROJECTION_ORTHOGONAL
	keep_aspect = KEEP_HEIGHT
	fov = perspective_fov
	_view_yaw = deg_to_rad(yaw_deg)
	_free_yaw = _view_yaw
	size = ortho_size
	# Orthographic near/far are a slab, not a cone: everything between them is drawn at full size,
	# so the slab has to be deep enough to hold the whole camp from this distance.
	near = 0.05
	far = distance * 2.0 + 200.0
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	_apply(true)


func _process(delta: float) -> void:
	_apply(false, delta)


func _apply(instant: bool, delta := 0.0) -> void:
	var opponent := locked()
	var in_combat := opponent != null and is_instance_valid(_target)
	_lock_mix = move_toward(_lock_mix,1.0 if in_combat else 0.0,delta*2.0)

	# Free look, polled rather than handled: this camera lives inside the pixel SubViewport, where
	# an unhandled event can be eaten before it arrives. Wrapped, so the turn never hits a stop.
	if _rotation_allowed() and delta > 0.0:
		var turn := Input.get_axis("camera_left","camera_right")
		if absf(turn) > 0.0:
			_free_yaw = wrapf(_free_yaw+turn*deg_to_rad(rotate_speed_deg)*delta,-PI,PI)

	var yaw_goal := _free_yaw
	if in_combat and lock_rotate:
		var bearing := opponent.global_position-_target.global_position
		if Vector2(bearing.x,bearing.z).length() > .4:
			var behind := atan2(-bearing.x,-bearing.z)
			var error := wrapf(behind-_view_yaw,-PI,PI)
			var slack := deg_to_rad(lock_yaw_slack_deg)
			yaw_goal = _view_yaw+signf(error)*maxf(0.0,absf(error)-slack)
		# Do not rotate the screen controls underneath a released sword strike.
		if _target.has_method("state_name") and _target.state_name() == "DirAttack" and _target.charging_dir() == -1:
			yaw_goal = _view_yaw
	if instant:
		_view_yaw = yaw_goal
	elif in_combat:
		var error := wrapf(yaw_goal-_view_yaw,-PI,PI)
		_view_yaw = wrapf(_view_yaw+clampf(error*(1.0-exp(-5.0*delta)),-deg_to_rad(lock_turn_speed_deg)*delta,deg_to_rad(lock_turn_speed_deg)*delta),-PI,PI)
	else:
		# Free look needs no smoothing of its own — the axis is already the rate — and running it
		# through the lock's easing would put a lag between the stick and the world, then cap the
		# turn at lock_turn_speed_deg, which is the speed for swinging a camera around a duel and
		# not for looking about.
		_view_yaw = yaw_goal
	# Hand the lock's angle back to free look, so letting go of a target leaves the camera where the
	# fight left it instead of snapping to wherever the session started.
	if in_combat:
		_free_yaw = _view_yaw

	var basis_want := Basis.from_euler(
			Vector3(deg_to_rad(-pitch_deg), _view_yaw, 0.0))
	var size_goal := ortho_size*lerpf(1.0,lock_zoom_ratio,_lock_mix)
	if in_combat:
		var spread := opponent.global_position-_target.global_position
		var viewport_size := get_viewport().get_visible_rect().size
		var aspect := maxf(.3,viewport_size.x/maxf(1,viewport_size.y))
		size_goal = maxf(size_goal,maxf(absf(spread.dot(basis_want.y))+4.0,(absf(spread.dot(basis_want.x))+4.0)/aspect))
	size = size_goal if instant else lerpf(size,size_goal,1.0-exp(-4.0*delta))

	if _target != null:
		var want := _target.global_position + Vector3.UP * focus_height
		if in_combat:
			var pair_focus := _target.global_position.lerp(opponent.global_position,.45)+Vector3.UP*1.1
			want = want.lerp(pair_focus,_lock_mix)
		if look_ahead > 0.0 and _target is CharacterBody3D:
			var v: Vector3 = (_target as CharacterBody3D).velocity
			want += Vector3(v.x, 0.0, v.z) * look_ahead * 0.1
		if instant or follow_rate <= 0.0 or not _have_focus:
			_focus = want
		else:
			# Frame-rate independent exponential smoothing. A plain lerp(delta * k) is not:
			# it converges faster at high frame rates, so the camera feels different on
			# different machines.
			_focus = _focus.lerp(want, 1.0 - exp(-follow_rate * delta))
		_have_focus = true
	elif not _have_focus:
		# No target: keep whatever the scene placed, and derive the focus from it so the snap
		# below still has something coherent to round.
		_focus = global_position + basis_want.z * -distance
		_have_focus = true

	projection = PROJECTION_PERSPECTIVE if perspective_enabled else PROJECTION_ORTHOGONAL
	fov = perspective_fov
	var view_distance := distance
	if perspective_enabled:
		if match_perspective_framing:
			view_distance = size / (2.0*tan(deg_to_rad(perspective_fov)*0.5))
		else:
			view_distance = distance * size / maxf(ortho_size,0.01)
	far = maxf(distance,view_distance)*2.0+200.0
	var pos := _focus + basis_want.z * view_distance
	# Orthographic snapping has no globally consistent pixel size in perspective.
	if pixel_snap and not perspective_enabled:
		pos = _snap(pos, basis_want)
	global_transform = Transform3D(basis_want, pos)


## Round the position to whole pixels along the camera's own screen axes. Depth is untouched --
## under an orthographic projection, sliding along the view axis moves nothing on screen.
func _snap(pos: Vector3, b: Basis) -> Vector3:
	var rows := pixel_rows
	if rows <= 0:
		rows = int(get_viewport().get_visible_rect().size.y)
	if rows <= 0:
		return pos
	var world_per_pixel := size / float(rows)
	if world_per_pixel <= 0.0:
		return pos
	var right := b.x
	var up := b.y
	var fwd := -b.z
	var r := snappedf(pos.dot(right), world_per_pixel)
	var u := snappedf(pos.dot(up), world_per_pixel)
	var f := pos.dot(fwd)
	return right * r + up * u + fwd * f

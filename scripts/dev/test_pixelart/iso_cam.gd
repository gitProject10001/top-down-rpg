extends Camera3D
## ORTHOGRAPHIC ISO CAMERA that keeps the world locked to the pixel grid.
##
## WHY NOT scenes/camera_rig.tscn. That rig is perspective (fov 42), orbits, and runs a depth-of-
## field CameraAttributesPractical. All three are wrong here and none of them is a setting: a
## perspective camera makes two identical barrels different sizes, which pixel art never does;
## orbiting breaks the fixed axonometric read the whole look depends on; and DoF is a continuous
## blur, which is exactly the thing a 64-colour palette cannot represent. camera_rig.gd is left
## alone -- this is a separate camera for a separate contract.
##
## THE PIXEL SNAP, which is the only non-obvious thing here.
##
## Render the world at 640x360 and move the camera by an arbitrary fraction of a pixel, and every
## static edge in the frame re-samples on a different texel boundary each frame. A wall that is not
## moving crawls. It is the single loudest tell that a "pixel art" scene is really a filtered 3D
## render, and no amount of shader work hides it.
##
## The fix is to move the camera in whole pixels. Because the projection is orthographic, one screen
## pixel is a constant number of world metres -- size / viewport_height -- so the camera's offset
## along its own right and up axes can simply be rounded to a multiple of that. Depth is left alone:
## moving along the view axis changes nothing about where a texel lands under an orthographic
## projection.
##
## The residue is that the camera advances in ~3 cm steps instead of continuously. At walking speed
## that is invisible; the alternative (feeding the sub-pixel remainder back through a shifted,
## oversized SubViewportContainer) buys smoother camera motion at the cost of a one-pixel border and
## a lot more moving parts. If the stepping ever shows, that is the upgrade -- not turning the snap
## off.

## What to follow. Empty leaves the camera wherever it was placed, which is what the fixed hero
## framing and the --shot renders use.
@export var target_path: NodePath

@export_group("Framing")
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

func locked() -> Node3D:
	return _lock_target if is_instance_valid(_lock_target) else null

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
	projection = PROJECTION_ORTHOGONAL
	_view_yaw = deg_to_rad(yaw_deg)
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
	var yaw_goal := deg_to_rad(yaw_deg)
	if in_combat:
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
	else:
		var error := wrapf(yaw_goal-_view_yaw,-PI,PI)
		_view_yaw = wrapf(_view_yaw+clampf(error*(1.0-exp(-5.0*delta)),-deg_to_rad(lock_turn_speed_deg)*delta,deg_to_rad(lock_turn_speed_deg)*delta),-PI,PI)

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

	var pos := _focus + basis_want.z * distance
	if pixel_snap:
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

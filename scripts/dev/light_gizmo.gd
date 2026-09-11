extends Node3D
## A move gizmo that works IN PLAY MODE — three axis arrows you drag to reposition a light while
## the game is running, with the lighting updating as you drag.
##
## WHY THIS EXISTS. The crypt's lights are all at candle height: a candelabra flame at 1.55 m, a
## brazier bowl at 0.95 m, the room fill at 5.5 m. Measured on the hero frame, that geometry — not
## the energies, not the shader — is most of why the floor reads dark and the walls read hot: a
## flame one metre off a wall hits it at N.L 0.88 from anywhere in the room, and rakes the floor at
## 0.36 four metres out and 0.17 at nine. "Where should this light actually be" is therefore one of
## the highest-value questions in the whole art pass, and until now the only way to ask it was to
## edit a .tscn, restart, and look.
##
## HOW IT PICKS. Screen-space distance, not physics raycasts. Lights have no colliders, and giving
## them invisible ones to click would put fake bodies into a scene whose collision layout is a
## gameplay contract. Projecting each candidate to the screen and taking the nearest within a pixel
## radius is simpler, needs nothing added to the scene, and behaves correctly when a light is inside
## a wall — which is exactly when you most need to grab it.
##
## HOW IT DRAGS. For an axis `a` at origin `o`, the screen vector for one world unit along that axis
## is `sa = project(o + a) - project(o)`. Then a mouse delta `md` converts to world units as
## `dot(md, sa) / dot(sa, sa)` — the least-squares projection of the mouse motion onto the axis.
## Exact, one line, and it stays correct at any camera angle including nearly edge-on, where the
## naive "divide by screen length" version explodes.
##
## LMB is free for this because scripts/dev/fly_camera.gd deliberately holds its look on RMB.

## `from` is the light's LOCAL position before the drag began. It has to travel with the signal:
## the tuner records old -> new for its save diff, and by the time the drag ends the old value is
## already gone from the node — reading it at that point reports "moved from where it now is".
signal moved(light: Light3D, from: Vector3, to: Vector3)

## Pixels. Generous, because a light marker is small and the thing you are trying to do is grab it.
const GRAB_PX := 14.0
## Screen-constant sizing: the gizmo is scaled by distance so it stays about this fraction of the
## viewport height however far away the light is. An arrow that shrinks to nothing across the room
## is an arrow you cannot use in the room you are not standing in.
const SCREEN_SIZE := 0.11
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_COLORS := [Color(0.95, 0.30, 0.32), Color(0.45, 0.90, 0.35), Color(0.35, 0.55, 0.98)]

var target: Light3D

var _arrows: Array[Node3D] = []
var _drag := -1
var _drag_from := Vector3.ZERO          ## world, the anchor the drag maths projects against
var _drag_from_local := Vector3.ZERO    ## local, what the save diff reports as the old value
var _drag_mouse := Vector2.ZERO


func _ready() -> void:
	for i in AXES.size():
		_arrows.append(_build_arrow(AXES[i], AXIS_COLORS[i]))
	visible = false
	set_process_unhandled_input(true)


## Shaft plus head, pointing down `dir`. Unshaded and depth-test-off: a gizmo that a wall can hide
## is a gizmo that vanishes the moment the light you want is behind something, which in a dungeon
## made of walls is most of the time.
func _build_arrow(dir: Vector3, col: Color) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.disable_receive_shadows = true

	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.022
	sm.bottom_radius = 0.022
	sm.height = 0.78
	shaft.mesh = sm
	shaft.material_override = mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = Vector3(0, 0.39, 0)
	root.add_child(shaft)

	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.075
	hm.height = 0.22
	head.mesh = hm
	head.material_override = mat
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.position = Vector3(0, 0.89, 0)
	root.add_child(head)

	# The meshes are built along +Y, so build a basis whose Y column IS the axis and let the other
	# two fall out of a cross product.
	#
	# NOT `Basis.looking_at(dir, UP).get_euler() + Vector3(PI/2, 0, 0)`, which was the first attempt:
	# adding euler angles is not composing rotations, and it silently produced arrows pointing down
	# -X and -Z while the drag maths used +X and +Z. The gizmo looked plausible and dragged
	# backwards. Caught by printing the arrow tips in world space rather than by looking at it.
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	root.basis = Basis(x, y, x.cross(y))
	return root


func is_dragging() -> bool:
	return _drag >= 0


func attach(l: Light3D) -> void:
	target = l
	visible = l != null
	_drag = -1


func detach() -> void:
	target = null
	visible = false
	_drag = -1


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		detach()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	global_position = target.global_position
	# Constant on-screen size. fov is vertical, so this is the world height of the viewport at the
	# light's depth, times the fraction we want to occupy.
	var d := cam.global_position.distance_to(global_position)
	var world_h := 2.0 * d * tan(deg_to_rad(cam.fov) * 0.5)
	scale = Vector3.ONE * maxf(world_h * SCREEN_SIZE, 0.01)


# ---------------------------------------------------------------- input ---------------------


func _unhandled_input(event: InputEvent) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if target != null and visible:
				var hit := _axis_under(cam, mb.position)
				if hit >= 0:
					_drag = hit
					_drag_from = target.global_position
					_drag_from_local = target.position
					_drag_mouse = mb.position
					get_viewport().set_input_as_handled()
		elif _drag >= 0:
			_drag = -1
			if target != null:
				moved.emit(target, _drag_from_local, target.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag >= 0 and target != null:
		var mm := event as InputEventMouseMotion
		var axis: Vector3 = AXES[_drag]
		var o := _drag_from
		var sa := cam.unproject_position(o + axis) - cam.unproject_position(o)
		var denom := sa.dot(sa)
		if denom > 0.0001:
			var t := (mm.position - _drag_mouse).dot(sa) / denom
			target.global_position = o + axis * t
		get_viewport().set_input_as_handled()


## Which axis arrow is under the cursor, or -1. Measured against the SEGMENT from the gizmo origin
## to the arrow tip rather than against the tip alone, so grabbing the middle of a shaft works.
func _axis_under(cam: Camera3D, at: Vector2) -> int:
	var best := -1
	var best_d := GRAB_PX
	var o := global_position
	if cam.is_position_behind(o):
		return -1
	var so := cam.unproject_position(o)
	for i in AXES.size():
		var tip: Vector3 = o + (AXES[i] as Vector3) * scale.x
		if cam.is_position_behind(tip):
			continue
		var d := _point_to_segment(at, so, cam.unproject_position(tip))
		if d < best_d:
			best_d = d
			best = i
	return best


static func _point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.dot(ab)
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

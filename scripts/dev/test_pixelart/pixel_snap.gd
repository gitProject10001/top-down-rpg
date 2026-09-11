extends Node
## SNAPS MOVING OBJECTS TO THE CAMERA'S PIXEL LATTICE, which is what stops their outlines flickering.
##
## THE PROBLEM. scripts/dev/test_pixelart/iso_cam.gd already snaps the CAMERA, so the whole static
## world sits on a fixed pixel grid and nothing in it crawls. A moving object gets no such promise:
## the player slides continuously through world space, its silhouette lands a third of a pixel over
## here and two thirds over there, and the outline pass -- which asks a yes/no question per pixel
## about the depth step at that pixel -- answers differently every frame. The result is a contour
## that fizzes along the edge of anything that moves. Softening the outline threshold hides some of
## it and costs the crispness the whole look is built on.
##
## THE FIX IS THE ONE PIXEL ART HAS ALWAYS USED. A sprite does not move by a third of a pixel; it
## moves by one. Quantising a moving object's position onto the same lattice the camera uses puts its
## silhouette back on stable pixel boundaries, and the outline becomes as steady as the buildings.
##
## HORIZONTAL ONLY, AND THAT IS DELIBERATE. The obvious implementation snaps along the camera's own
## right and up axes. The right axis is horizontal (the camera has yaw and pitch but no roll), so
## that half is free -- but the up axis has a vertical component, and nudging a CharacterBody3D up
## and down by a centimetre every frame fights its floor detection and can make it believe it is
## airborne. So the lattice is laid on the GROUND instead: one axis along camera-right, the other
## along camera-forward-projected-to-the-ground. Moving along that second axis is what moves an
## object vertically on screen, and the conversion is a factor of sin(pitch) -- a metre of ground
## travel toward the camera is only sin(pitch) metres of screen rise. Y is never touched, so physics
## never notices.
##
## The lattice is anchored at the world origin rather than at the camera, so it does not shift when
## the camera does, and two objects snapped by it stay in register with each other.

## The camera whose pixels define the lattice. Must be the orthographic iso_cam.
@export var camera_path: NodePath

## Everything that moves and wants a stable outline. The player is the obvious one; add anything
## else that is animated through world space.
@export var targets: Array[NodePath] = []

@export var enabled := true

var _cam: Camera3D = null
var _targets: Array[Node3D] = []


func _ready() -> void:
	_cam = get_node_or_null(camera_path) as Camera3D
	if _cam == null:
		push_warning("[PIXELSNAP] no camera at %s; moving outlines will flicker" % camera_path)
		set_process(false)
		return
	for path in targets:
		var n := get_node_or_null(path) as Node3D
		if n != null:
			_targets.append(n)
	# Late in the frame, so anything that moved this tick is snapped before it is drawn.
	process_priority = 100


func _process(_delta: float) -> void:
	if not enabled or _cam == null or _targets.is_empty():
		return
	var rows := _rows()
	if rows <= 0:
		return
	# One screen pixel, in metres, under an orthographic projection.
	var world_per_pixel := _cam.size / float(rows)
	if world_per_pixel <= 0.0:
		return

	var basis := _cam.global_transform.basis
	# Camera right, already horizontal.
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	# Camera forward, flattened onto the ground.
	var fwd := -basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z)
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()

	# How far along the ground an object must travel to rise one pixel on screen. Straight down
	# (pitch 90) that is infinite -- nothing moves vertically on screen -- so it is clamped.
	var sin_pitch: float = clampf(absf(-basis.z.y), 0.15, 1.0)
	var step_fwd := world_per_pixel / sin_pitch

	for node in _targets:
		if not is_instance_valid(node):
			continue
		var p := node.global_position
		var flat := Vector3(p.x, 0.0, p.z)
		var a := snappedf(flat.dot(right), world_per_pixel)
		var b := snappedf(flat.dot(fwd), step_fwd)
		var snapped := right * a + fwd * b
		node.global_position = Vector3(snapped.x, p.y, snapped.z)


## The camera's viewport height in pixels -- the SubViewport's, not the window's.
func _rows() -> int:
	if "pixel_rows" in _cam and int(_cam.pixel_rows) > 0:
		return int(_cam.pixel_rows)
	var vp := _cam.get_viewport()
	return int(vp.get_visible_rect().size.y) if vp != null else 0

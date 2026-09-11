extends SceneTree
## SHOOT A SCENE THAT ALREADY EXISTS, AND NEVER WRITE TO IT.
##
## `shot_houses.gd` builds its cast in code, which is right for a fixture and wrong the moment
## somebody opens the saved scene and MOVES something to show what is broken. This loads whatever is
## there, waits for the stone to grow back, and photographs it — the arrangement under the camera is
## the one in the file, not the one in a script.
##
## Aimed at a node by name, so the ring and the close views frame the thing being argued about:
##   Godot_console.exe --path . --resolution 1200x760 --script res://scripts/gladekit_tests/shot_scene.gd -- \
##       --scene=res://scenes/dev/gladekit/glade_houses.tscn --at=Farmhouse --out=C:/some/folder
##
## `--stand=x,y,z` puts the player there first and `--nogui` drops the tuning panel, which is what a
## scene whose look depends on where the player IS needs before it can be photographed at all.

const WARMUP := 90

var _out := "user://"
var _scene := "res://scenes/dev/gladekit/glade_houses.tscn"
var _at := ""
var _eye := Vector3.INF
var _to := Vector3.INF
var _fov := 60.0
var _stand := Vector3.INF
var _nogui := false
var _cam: Camera3D
var _root: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
		elif a.begins_with("--scene="):
			_scene = a.substr(8)
		elif a.begins_with("--at="):
			_at = a.substr(5)
		elif a.begins_with("--eye="):
			_eye = _vec(a.substr(6))
		elif a.begins_with("--to="):
			_to = _vec(a.substr(5))
		elif a.begins_with("--fov="):
			_fov = a.substr(6).to_float()
		elif a.begins_with("--stand="):
			_stand = _vec(a.substr(8))
		elif a == "--nogui":
			_nogui = true
	_run()


## `x,y,z` from the command line — for standing somewhere specific, which is the whole point when the
## thing being argued about is what you see from ONE spot.
func _vec(s: String) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return Vector3.INF
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())


func _run() -> void:
	var packed: PackedScene = load(_scene)
	if packed == null:
		push_error("no scene at " + _scene)
		quit(1)
		return
	_root = packed.instantiate() as Node3D
	root.add_child(_root)
	for i in 4:
		await process_frame

	# WHERE THE PLAYER IS STANDING IS PART OF THE SCENE. `GladeCutaway` opens a house only while
	# somebody is inside it, so a photograph of a cut-open house is a photograph of a scene with a
	# player in a particular room — there is no camera angle that shows it otherwise.
	if _stand != Vector3.INF:
		var who := _root.get_tree().get_first_node_in_group("player") as Node3D
		if who != null:
			who.global_position = _stand
			print("[SHOT] player stands at %v" % _stand)
		else:
			push_warning("--stand given but no node in group \"player\"")
	if _nogui:
		for c in _root.get_children():
			if c is CanvasLayer:
				(c as CanvasLayer).visible = false
	for i in 8:
		await process_frame

	# WHERE TO POINT, measured off the thing itself rather than typed in: a node that has been moved
	# has moved, and a hard-coded camera then photographs the grass beside it.
	var target: Node3D = _root.find_child(_at, true, false) as Node3D if _at != "" else _root
	if target == null:
		target = _root
	var box := _bounds(target)
	var mid := box.get_center()
	# TALL THINGS NEED THE SAME ROOM AS WIDE ONES. Framing off the footprint alone put the ring
	# camera inside its own subject's height and cut the top off a tower in every one of the eight.
	var reach: float = maxf(maxf(box.size.x, box.size.z) * 0.5, box.size.y * 0.62) + 2.0
	print("[SHOT] %s centre %v  size %v" % [_at, mid, box.size])

	_cam = Camera3D.new()
	_root.add_child(_cam)
	_cam.current = true

	# ONE NAMED SPOT, WHEN THERE IS ONE. A defect somebody can see from where they are standing is
	# best argued about from where they are standing.
	if _eye != Vector3.INF and _to != Vector3.INF:
		_look(_eye, _to, _fov)
		await _shoot("scene_eye")
		quit(0)
		return

	_look(Vector3(mid.x, box.position.y + box.size.y * 5.0, mid.z + 0.1),
			Vector3(mid.x, box.position.y, mid.z), 46.0)
	await _shoot("scene_plan")

	for k in 8:
		var a := TAU * float(k) / 8.0
		_look(mid + Vector3(sin(a), 0.0, cos(a)) * (reach * 2.2) + Vector3.UP * (reach * 1.2),
				Vector3(mid.x, box.position.y + 1.0, mid.z), 42.0)
		await _shoot("scene_%03d" % int(round(rad_to_deg(a))))

	# ...AND FROM THE GROUND, ON EACH SIDE, LOOKING UP AND ACROSS. A hole in a wall shows the sky
	# through it from below and nothing at all from above, which is why every earlier round of this
	# missed one: the eye-height and bird's-eye cameras agree with each other and both are wrong.
	for k in 4:
		var a := TAU * float(k) / 4.0
		var out: Vector3 = Vector3(sin(a), 0.0, cos(a))
		_look(mid - out * (reach + 1.5) + Vector3(0.0, box.position.y + 0.5, 0.0),
				mid + out * reach + Vector3(0.0, box.position.y + box.size.y * 1.1, 0.0), 70.0)
		await _shoot("scene_up_%03d" % int(round(rad_to_deg(a))))

	quit(0)


## The world box of a node and everything generated under it — `get_children(true)` because the stone
## is INTERNAL_BACK and the ordinary walk cannot see any of it.
func _bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children(true):
			stack.append(c)
		var mi := cur as VisualInstance3D
		if mi == null:
			continue
		var w: AABB = mi.global_transform * mi.get_aabb()
		if first:
			box = w
			first = false
		else:
			box = box.merge(w)
	return box


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.position = from
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.fov = fov


func _shoot(name: String) -> void:
	for i in WARMUP:
		await process_frame
	var img := _cam.get_viewport().get_texture().get_image()
	var path := _out + name + ".png"
	if img.save_png(path) == OK:
		print("[SHOT] ok   %s (%d x %d)" % [path, img.get_width(), img.get_height()])
	else:
		print("[SHOT] FAILED %s" % path)

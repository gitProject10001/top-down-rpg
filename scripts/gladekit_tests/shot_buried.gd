extends SceneTree
## LOOK AT `buried_style` ON THE WHINBEK TOWER. The suite proves the region is built and built out
## of the right thing; it cannot say whether a building with an interior face reads better than one
## with a hole in it. This renders the same scene three ways — the region deleted (today), refilled
## with the wall's own style, and refilled with an interior rule — from cameras that can actually
## see it, which mostly means with the winner hidden.
##
## Needs a real rendering context, so run it WITHOUT --headless (a window opens and closes):
##   Godot_console.exe --path . --resolution 1280x800 --script res://scripts/gladekit_tests/shot_buried.gd
##
## Output directory is the first command-line argument, or user:// if none is given.

const SCENE := "res://scenes/dev/gladekit/whinbek.tscn"
const WARMUP := 24                             ## frames for the deferred rebuilds to settle

## Each view is a camera and the buildings it has to hide to see anything. A buried face is by
## definition inside another solid, so "hide the winner" is not cheating — it is the only way to
## photograph the thing under discussion.
const VIEWS := [
	{"name": "context", "from": Vector3(13.0, 8.5, 14.0), "at": Vector3(0.0, 3.2, 0.0),
		"fov": 46.0, "hide": []},
	{"name": "tower_cut", "from": Vector3(2.4, 3.4, -12.5), "at": Vector3(2.4, 3.0, -3.0),
		"fov": 42.0, "hide": ["Tower"]},
	{"name": "boundary", "from": Vector3(7.6, 2.4, -8.4), "at": Vector3(1.8, 2.2, -3.4),
		"fov": 38.0, "hide": ["Tower"]},
	{"name": "house_inside", "from": Vector3(-0.4, 2.0, 1.7), "at": Vector3(2.4, 1.9, -3.0),
		"fov": 70.0, "hide": [], "lamp": Vector3(0.2, 2.6, 1.2)},
	## The same camera with the tower taken away: how much of the refill the room can see is the
	## difference between these two.
	{"name": "house_inside_cut", "from": Vector3(-0.4, 2.0, 1.7), "at": Vector3(2.4, 1.9, -3.0),
		"fov": 70.0, "hide": ["Tower"], "lamp": Vector3(0.2, 2.6, 1.2)},
	{"name": "wing_cut", "from": Vector3(-2.0, 2.6, 0.6), "at": Vector3(4.0, 1.6, 0.6),
		"fov": 46.0, "hide": ["MainBlock"]},
	## The porch's side walls, from the street. Nothing here is inside anything — which is the point.
	{"name": "porch_street", "from": Vector3(-6.6, 2.6, 8.6), "at": Vector3(-2.0, 1.4, 3.2),
		"fov": 38.0, "hide": []},
	{"name": "porch_nomain", "from": Vector3(-6.6, 2.6, 8.6), "at": Vector3(-2.0, 1.4, 3.2),
		"fov": 38.0, "hide": ["MainBlock"]},
	{"name": "porch_noporch", "from": Vector3(-6.6, 2.6, 8.6), "at": Vector3(-2.0, 1.4, 3.2),
		"fov": 38.0, "hide": ["Porch"]},
]

var _out := "user://"
var _walls: Array[GladeWall] = []
var _by_name := {}


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for a in args:
		if a.begins_with("--out="):
			_out = a.substr(6)
	if not _out.ends_with("/"):
		_out += "/"

	var scene: Node = load(SCENE).instantiate()
	root.add_child(scene)
	_collect(scene)
	for i in WARMUP:
		await process_frame

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 2.2
	lamp.visible = false
	root.add_child(lamp)

	for mode in ["off", "same", "interior"]:
		for w in _walls:
			_dress(w, mode)
			w.rebuild()
		for i in 6:
			await process_frame
		var total := 0
		for w in _walls:
			total += w.snap_transforms.size()
		print("[SHOT] buried=%-8s %d bricks in the scene" % [mode, total])

		for v in VIEWS:
			for n in v["hide"]:
				(_by_name[n] as Node3D).visible = false
			lamp.visible = v.has("lamp")
			if v.has("lamp"):
				lamp.position = v["lamp"]
			cam.fov = v["fov"]
			cam.look_at_from_position(v["from"], v["at"], Vector3.UP)
			for i in 4:
				await process_frame
			var path: String = "%s%s_%s.png" % [_out, v["name"], mode]
			var img := root.get_texture().get_image()
			var err := img.save_png(path)
			print("[SHOT] %s %s" % ["ok  " if err == OK else "FAIL", path])
			for n in v["hide"]:
				(_by_name[n] as Node3D).visible = true

	quit(0)


# ---------------------------------------------------------------- the styles ----------------


## Point every style this wall uses at a buried style, or put its own styles back.
##
##   off       what the scene ships with: the swallowed region is simply not built
##   same      the buried region built out of the wall's own rule — "the wall continues"
##   interior  a different rule for a different place: small rough coursed stone, no cap, no moss
func _dress(w: GladeWall, mode: String) -> void:
	w.style = _buried_of(w.get_meta("orig_style"), mode)
	for s in w.storeys:
		if s and s.has_meta("orig_style"):
			s.style = _buried_of(s.get_meta("orig_style"), mode)


func _buried_of(st: GladeStyle, mode: String) -> GladeStyle:
	if st == null or mode == "off":
		return st
	var outer: GladeStyle = st.duplicate()
	var inner: GladeStyle = st.duplicate()
	if mode == "interior":
		inner.wall_mode = GladeStyle.WallMode.MASONRY
		inner.course_height = 0.22
		inner.brick_min_width = 0.24
		inner.brick_max_width = 0.42
		inner.palette = [Color(0.74, 0.71, 0.64), Color(0.66, 0.63, 0.57),
				Color(0.58, 0.56, 0.52)] as Array[Color]
		inner.palette_weights = PackedFloat32Array([3, 2, 1])
		inner.cap_course = false
		inner.crenellated = false
		inner.band_every = 0.0
		inner.jamb_stones = false
		inner.moss_wind = 0.0
		inner.weather_moss_from = 1.1              # nothing grows on an inside face
	outer.buried_style = inner
	return outer


func _collect(n: Node) -> void:
	if n is GladeWall:
		var w: GladeWall = n
		w.set_meta("orig_style", w.style)
		for s in w.storeys:
			if s:
				s.set_meta("orig_style", s.style)
		_walls.append(w)
		_by_name[w.name] = w
	for c in n.get_children():
		_collect(c)

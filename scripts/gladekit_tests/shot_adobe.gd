extends SceneTree
## THE ADOBE PROOF OF CONCEPT, in the four stages the disagreement can actually be at:
##
##   blockout   the massing alone, flat-shaded. Is the SILHOUETTE right before any piece exists?
##   fill       every rule, bare lighting. Is the clay one block, are the openings cut, does the
##              parapet read, is the thatch thatch?
##   rendering  through adobe_lookdev.tscn — painted shader, Kuwahara, grade. Does it read?
##   reference  the plate, for the confrontation.
##
## Sibling of shot_concept.gd, which does the same for whinbek. Run WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1000x1240 --script res://scripts/gladekit_tests/shot_adobe.gd -- --out=C:/some/folder

const BARE := "res://scenes/dev/gladekit/adobe.tscn"
const LOOKDEV := "res://scenes/dev/gladekit/adobe_lookdev.tscn"
const WARMUP := 30

## The reference is a tall plate seen from a high three-quarter view, close to isometric.
const CAM_FROM := Vector3(-16.5, 13.0, 17.5)
const CAM_AT := Vector3(0.2, 2.6, 0.4)
const CAM_FOV := 34.0

## Two metres from the things that keep going wrong.
const DETAIL := [
	{"name": "thatch", "from": Vector3(1.2, 3.0, 9.6), "at": Vector3(-1.6, 1.7, 5.9)},
	{"name": "door", "from": Vector3(8.6, 2.2, 6.4), "at": Vector3(5.4, 1.2, 2.6)},
	{"name": "dome", "from": Vector3(-8.6, 5.6, 5.2), "at": Vector3(-4.0, 3.4, 1.0)},
	{"name": "corner", "from": Vector3(9.2, 1.8, 4.6), "at": Vector3(6.2, 1.6, 2.2)},
]

var _out := "user://"


func _initialize() -> void:
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if not _out.ends_with("/"):
		_out += "/"

	var bare: Node = load(BARE).instantiate()
	root.add_child(bare)
	for i in WARMUP:
		await process_frame
	var cam := Camera3D.new()
	bare.add_child(cam)
	cam.fov = CAM_FOV
	cam.far = 400.0
	cam.current = true
	cam.look_at_from_position(CAM_FROM, CAM_AT, Vector3.UP)

	GladeDebug.blockout = true
	GladeDebug.refresh(bare)
	for i in 12:
		await process_frame
	await _shot("blockout")

	GladeDebug.blockout = false
	GladeDebug.refresh(bare)
	for i in 12:
		await process_frame
	_report(bare)
	await _shot("fill")

	# CLOSE UP, because the wide shot flatters everything. Every defect found in this style so far —
	# the brick pattern in the clay, the sugar-cube thatch, the inside-out faces — was invisible at
	# the framing the plate is drawn at and obvious from two metres.
	for d in DETAIL:
		cam.fov = 42.0
		cam.look_at_from_position(d["from"], d["at"], Vector3.UP)
		await _shot("detail_%s" % d["name"])
	bare.free()

	var look: Node = load(LOOKDEV).instantiate()
	root.add_child(look)
	for i in WARMUP:
		await process_frame
	var pl := look.get_node_or_null("Player") as Node3D
	if pl:
		pl.visible = false
	var lcam := Camera3D.new()
	look.add_child(lcam)
	lcam.fov = CAM_FOV
	lcam.far = 400.0
	lcam.current = true
	lcam.look_at_from_position(CAM_FROM, CAM_AT, Vector3.UP)
	for i in 12:
		await process_frame
	_hide_ui(root, [look.get_node_or_null("PostFX"), look.get_node_or_null("PainterlyGrade")])
	await _shot("rendering")

	quit(0)


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	var path := "%sadobe_%s.png" % [_out, name]
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("[ADOBE] %s %s (%d x %d)" % ["ok  " if err == OK else "FAIL", path,
			img.get_width(), img.get_height()])


## What the rules actually produced. `adobe_quads` is the honest number for a mud wall: it places no
## instances, so a brick count would read zero and say nothing.
func _report(n: Node) -> void:
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is GladeWall:
			var st: Dictionary = (c as GladeWall).stats
			print("  %-9s %5d quads   %4d pieces   openings %d"
					% [c.name, int(st.get("adobe_quads", 0)), int(st.get("bricks", 0)),
							int(st.get("openings", 0))])
		elif c is GladeRoof:
			print("  %-9s %5d shingles" % [c.name, int((c as GladeRoof).stats.get("shingles", 0))])
		for k in c.get_children():
			stack.append(k)


func _hide_ui(root_node: Node, keep: Array) -> void:
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if keep.has(n):
			continue
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
			continue
		if n is Control:
			(n as Control).visible = false
			continue
		for c in n.get_children():
			stack.append(c)

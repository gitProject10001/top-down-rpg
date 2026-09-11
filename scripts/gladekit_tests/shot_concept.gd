extends SceneTree
## WHINBEK AGAINST ITS CONCEPT ART. One camera, three stages, so the comparison can be made at the
## level the disagreement is actually at:
##
##   massing   the four prisms and the cone, flat-shaded, no detail at all — is the SILHOUETTE right
##   geometry  every piece, bare lighting — are the junctions right
##   painted   through whinbek_lookdev.tscn's shader, Kuwahara and sun — does it read as the painting
##
## The camera matches the reference's viewpoint: a long lens from the south-west, a little above the
## first floor, which is where docs/images/references/whinbek-conceptart.jpg is drawn from.
##
## Run WITHOUT --headless, at the reference's aspect (1920 x 1550):
##   Godot_console.exe --path . --resolution 1240x1000 --script res://scripts/gladekit_tests/shot_concept.gd -- --out=C:/some/folder

const WHINBEK := "res://scenes/dev/gladekit/whinbek.tscn"
const LOOKDEV := "res://scenes/dev/gladekit/whinbek_lookdev.tscn"
const WARMUP := 30

## Far back on a longish lens, which is how the reference is drawn — the plate has almost no
## perspective divergence, and the building fills about three quarters of the frame height.
const CAM_FROM := Vector3(-35.1, 11.73, 27.0)
const CAM_AT := Vector3(0.8, 5.4, -0.2)
const CAM_FOV := 30.0

var _out := "user://"


func _initialize() -> void:
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if not _out.ends_with("/"):
		_out += "/"

	var bare: Node = load(WHINBEK).instantiate()
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
	await _shot("massing")

	GladeDebug.blockout = false
	GladeDebug.refresh(bare)
	for i in 12:
		await process_frame
	_report(bare)
	await _shot("geometry")
	bare.free()

	var look: Node = load(LOOKDEV).instantiate()
	root.add_child(look)
	for i in WARMUP:
		await process_frame
	var pl := look.get_node_or_null("Player") as Node3D
	if pl:
		pl.visible = false
	# The reference is painted from the front-LEFT: the gable end catches the light and the long
	# elevation falls away. The look-dev's own default sun comes from the other side.
	look.set("_sun_yaw", -72.0)
	look.set("_sun_pitch", 33.0)
	look.call("_apply_sun")
	# ...and the plate is on white. Flat background, so the comparison is about the building.
	var env := look.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env and env.environment:
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.93, 0.94, 0.95)
	# ...and the ground in the plate is dry straw, not a lawn. The look-dev skins it with a duplicate
	# of the painted material precisely so it can carry its own colour.
	var gm := look.find_child("Mesh", true, false) as MeshInstance3D
	if gm and gm.material_override is ShaderMaterial:
		(gm.material_override as ShaderMaterial).set_shader_parameter("albedo_color",
				Color(0.74, 0.68, 0.5))

	var lcam := Camera3D.new()
	look.add_child(lcam)
	lcam.fov = CAM_FOV
	lcam.far = 400.0
	lcam.current = true
	lcam.look_at_from_position(CAM_FROM, CAM_AT, Vector3.UP)
	for i in 12:
		await process_frame
	# LAST, not first. The player's HUD is an autoload's CanvasLayer hanging off the tree ROOT, not
	# off the look-dev node, and it is built after everything here has run — so the sweep has to
	# start at the root and happen at the last possible moment.
	# BOTH post layers survive the sweep. The look-dev runs Kuwahara and then the painterly grade,
	# and sparing only the first would switch the grade off in exactly the render being judged —
	# which is the same shape of mistake as the player HUD that got photographed earlier.
	_hide_ui(root, [look.get_node_or_null("PostFX"), look.get_node_or_null("PainterlyGrade")])
	await _shot("painted")

	quit(0)


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	var path := "%swhinbek_%s.png" % [_out, name]
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("[SHOT] %s %s (%d x %d)" % ["ok  " if err == OK else "FAIL", path,
			img.get_width(), img.get_height()])


## Everything drawn over the 3D would be photographed along with the building: the tuning panel on
## the look-dev node, and the player's HUD, which is a CanvasLayer INSIDE the player and so survives
## hiding the player itself. Walk the whole tree; the Kuwahara pass is the one to keep.
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


func _report(n: Node) -> void:
	var walls: Array[Node] = []
	_collect(n, walls)
	for w in walls:
		var st: Dictionary = w.get("stats")
		if w is GladeWall:
			print("  %-10s %5d pieces  quoins %3d  tees %3d"
					% [w.name, int(st.get("bricks", 0)), int(st.get("quoins", 0)),
							int(st.get("tees", 0))])
		else:
			print("  %-10s %5d shingles  valleys %3d  cut %3d"
					% [w.name, int(st.get("shingles", 0)), int(st.get("valleys", 0)),
							int(st.get("cut", 0))])


func _collect(n: Node, out: Array[Node]) -> void:
	if n is GladeWall or n is GladeRoof:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

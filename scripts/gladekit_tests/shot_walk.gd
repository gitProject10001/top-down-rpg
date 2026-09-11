extends SceneTree
## THE SEE-THROUGH AND THE ORTHO TOGGLE, from the camera that actually plays the game.
##
## The player is put BEHIND the house, which is the case the feature exists for: at the rig's fixed
## ~53 degrees anything north of a building is behind its roof. Three frames, so the difference is
## the only variable:
##
##   occluded    see-through off — the player is simply gone
##   through     see-through on — a stippled hole in whatever stands in the way
##   ortho       the same, on an orthographic projection
##
## Run WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1152x648 --script res://scripts/gladekit_tests/shot_walk.gd -- --out=C:/some/folder

const LOOKDEV := "res://scenes/dev/gladekit/whinbek_lookdev.tscn"
const WARMUP := 40
## North of the main block (which reaches z = -3.2), so the house sits between the rig and them.
const STAND := Vector3(0.0, 0.6, -6.0)
## Inside the main block, which spans x -4.8..4.8 and z -3.2..3.2.
const INSIDE := Vector3(-1.0, 1.6, 0.0)

var _out := "user://"


func _initialize() -> void:
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if not _out.ends_with("/"):
		_out += "/"

	var look: Node = load(LOOKDEV).instantiate()
	root.add_child(look)
	for i in WARMUP:
		await process_frame

	look.call("_set_mode", true)
	var player := look.get_node_or_null("Player") as Node3D
	var rig := look.get_node_or_null("CameraRig") as Node3D
	if player == null or rig == null:
		print("[WALK] no player/rig in the look-dev")
		quit(1)
		return
	player.global_position = STAND
	rig.global_position = STAND               # skip the follow lerp rather than wait it out
	for i in 30:
		await process_frame
		await physics_frame

	var st := look.get_node_or_null("SeeThrough")
	var cam := rig.get_node_or_null("Camera3D") as Camera3D

	st.set("radius", 0.0)
	await _shot(look, "occluded")

	st.set("radius", 1.8)
	await _shot(look, "through")

	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 14.0
	await _shot(look, "ortho")
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE

	# ...and INDOORS, which is a different shot: the lid comes off the storey the player is standing
	# on, the world outside dims, and the rig pulls in.
	var interior := look.get_node_or_null("InteriorView")
	player.global_position = INSIDE
	rig.global_position = INSIDE
	for i in 40:
		await process_frame
		await physics_frame
	print("[WALK] indoors: %s" % ("yes" if bool(interior.get("_inside") != null) else "NO"))
	await _shot(look, "inside")

	quit(0)


func _shot(look: Node, name: String) -> void:
	for i in 10:
		await process_frame
	_hide_ui(root, [look.get_node_or_null("PostFX"), look.get_node_or_null("PainterlyGrade")])
	for i in 2:
		await process_frame
	var path := "%swalk_%s.png" % [_out, name]
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("[WALK] %s %s" % ["ok  " if err == OK else "FAIL", path])


## Same sweep the concept shot uses: the tuning panel and the player's HUD would otherwise be
## photographed along with the scene, and both post layers have to survive it.
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

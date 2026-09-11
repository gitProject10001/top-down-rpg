extends SceneTree
## THE DEFECTS, FROM TWO METRES — the four things a close-up of whinbek showed and this cycle fixed.
##
##   the stack   a chimney through a roof left a RAW NOTCH: the claim deleted the tiles and nothing
##               lapped the joint, so you could see into the roof cavity. Now it is aproned.
##   the eave    the roof WAS the tile field and nothing else, so the 0.45 m overhang hung over open
##               air and every column joint was a slot to the sky. Now there is a deck behind it.
##   the frame   braces ran the whole storey THROUGH the mid-rail and all leaned the same way.
##   the glass   windows were snapped to a grid 0.20 m from the one the studs were built on.
##
## Run WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1400x900 --script res://scripts/gladekit_tests/shot_apron.gd -- --out=C:/some/folder
const WHINBEK := "res://scenes/dev/gladekit/whinbek.tscn"
const WARMUP := 26
var _out := "user://"
var _cam: Camera3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()

func _run() -> void:
	var scn: Node = (load(WHINBEK) as PackedScene).instantiate()
	root.add_child(scn)
	for i in WARMUP:
		await process_frame
	_cam = Camera3D.new()
	scn.add_child(_cam)
	_cam.current = true
	# the stack coming through the main roof
	await _look(Vector3(9.6, 8.4, 6.2), Vector3(6.9, 5.4, 2.2), 42.0, "apron_stack")
	# the eave and verge from below, where the overhang used to be open
	await _look(Vector3(-6.4, 1.6, 9.4), Vector3(-2.2, 4.6, 4.0), 46.0, "apron_eave")
	# the timber frame: braces and glass
	await _look(Vector3(2.6, 3.4, 11.5), Vector3(1.4, 3.0, 5.4), 34.0, "apron_frame")
	quit(0)

func _look(from: Vector3, at: Vector3, fov: float, name: String) -> void:
	_cam.position = from
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.fov = fov
	for i in 6:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + name + ".png"
	var err := img.save_png(path)
	print("[SHOT] %s   %s" % ["ok" if err == OK else "FAILED", ProjectSettings.globalize_path(path)])

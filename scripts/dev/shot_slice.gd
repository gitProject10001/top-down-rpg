extends SceneTree
## PHOTOGRAPH THE VERTICAL SLICE — the hub cast, the check card, the boon pick.
##
##   Godot_console.exe --path . --resolution 1600x900 --script res://scripts/dev/shot_slice.gd -- \
##       --out=C:/some/folder
##
## MUST RUN WITHOUT --headless, the same rule every other shot script here carries: the dummy
## renderer has no pixels and saves black frames.
##
## The two UI shots are the reason this exists rather than being a stop in shot_arena.gd. A check
## card and a boon pick cannot be photographed by standing somewhere — they have to be TRIGGERED,
## and the card in particular drops Engine.time_scale, so the capture has to happen on a clock the
## card has not slowed. Every wait here is real-time for that reason.

const WARMUP := 90           ## frames for SDFGI/TAA to settle before the first capture
const SETTLE := 50           ## frames for the camera rig's lerps to converge after a move

## Standing among the three, on the arena floor. World space, since that is what the player node
## wants: room-local (0, -13.2, 80) through the hub instance's transform.
const LOOK_AT_CAST := Vector3(6.88, -9.71, 58.55)

var _out := "user://"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.ends_with("/"):
		_out += "/"
	_run()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main                    # World.go_to reads it; a --script tree does not set it
	for i in WARMUP:
		await process_frame

	var player := root.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		print("[SHOT] no player")
		quit(1)
		return

	# 1. THE HUB CAST.
	player.global_position = LOOK_AT_CAST
	var rig := root.get_tree().get_first_node_in_group("camera_rig") as Node3D
	if rig:
		rig.global_position = player.global_position
	for i in SETTLE:
		await process_frame
	await _shot("hub_cast")

	# 2. THE CHECK CARD. Failure rather than success, because the failed card is the one that has to
	# still look deliberate — it is the same card drained, and it is easy to make it look broken.
	var traits := root.get_node_or_null("/root/Traits")
	var notice := root.get_node_or_null("/root/Notice")
	if traits and notice:
		notice.interject(traits.Attr.LOGIC, "medium", "",
				"That is not settling. Settling cracks run with the load — this one runs ACROSS "
						+ "it, and it is venting cold air. There is a space behind that wall.",
				"Cracked masonry. Everything down here is cracked masonry. You are, you suspect, "
						+ "being asked to have an opinion about a wall.")
		await _real(0.9)
		await _shot("check_card")
		await _real(3.0)                    # let it dismiss itself and hand the clock back

	# 3. THE BOON PICK.
	var sheet := root.get_node_or_null("/root/Sheet")
	if sheet and traits:
		traits.begin_run(11)
		sheet.offer_boons()
		await _real(0.5)
		await _shot("boon_pick")

	print("[SHOT] wrote 3 frames to %s" % _out)
	quit(0)


## Real seconds. A Notice card runs the world at a quarter speed, so a scaled wait would be four
## times longer than intended and the boon shot would land after the card had gone.
func _real(seconds: float) -> void:
	await root.get_tree().create_timer(seconds, true, false, true).timeout


func _shot(name_of: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := _out + name_of + ".png"
	img.save_png(path)
	print("[SHOT] %s" % path)

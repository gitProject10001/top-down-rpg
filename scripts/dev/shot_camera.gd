extends SceneTree
## PHOTOGRAPH THE HUB'S THREE FRAMINGS, AND PROVE THE RIG'S CLAIM LIST POPS CORRECTLY.
##
##   Godot_console.exe --path . --resolution 1600x900 --script res://scripts/dev/shot_camera.gd -- \
##       --out=C:/some/folder
##
## MUST RUN WITHOUT --headless. The dummy renderer has no pixels, so a headless run saves black
## frames — the same rule every other shot script here carries.
##
## WHY THIS EXISTS AND NOT JUST shot_arena.gd. That script photographs the ARENA; this one
## photographs the CAMERA. It prints, at every stop, the zoom the rig actually settled on and the
## full list of claims with their priorities, so a framing bug shows up as a number rather than as a
## picture somebody has to squint at.
##
## THE REGRESSION TEST IS THE LAST TWO LINES, talk_in_arena followed by talk_released:
##
##   [CAM] talk_in_arena  zoom=0.70  claims=[ArenaCameraZone(p0), Dialogue(p10)]
##   [CAM] talk_released  zoom=1.40  claims=[ArenaCameraZone(p0)]
##
## 1.40 is ArenaCameraZone's framing. Before CameraRig kept a list, releasing the conversation reset
## to the hardcoded default and this line read 1.00 — the camera silently forgot which zone the
## player was standing in for the rest of the visit. scenes/world/room.tscn:576 records that bug
## being worked around by MOVING three NPCs rather than fixed. If this line ever says 1.00 again,
## the list has regressed to a slot.
##
## The stairs stops are the other half: StairsVistaZone sits geometrically INSIDE ArenaCameraZone
## and is entered first, so seeing BOTH claims held with the p10 one winning is what proves priority
## beats recency.

const SETTLE := 110          ## framing lerps at zoom_speed 4.0; ~1.5 s to converge
const WARMUP := 60

## WORLD space, and that distinction has already cost one debugging session. The Room node is
## instanced at (6.88, 3.35, -21.46), so the coordinates written in room.tscn are NOT world
## coordinates. Parking at the raw scene numbers puts the player outside every zone, and the probe
## then cheerfully reports default framing everywhere — a wrong answer that looks like a real one.
const STOPS := {
	"arena": Vector3(6.88, -9.85, 45.0),
	"stairs_top": Vector3(-22.0, 0.8, 69.4),
	"stairs_mid": Vector3(-12.0, -3.8, 69.4),
	"stairs_low": Vector3(-6.0, -6.6, 69.4),
}
## On the arena floor near the three NPCs, for the conversation pair.
const TALK_SPOT := Vector3(6.88, -9.85, 54.0)

var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in WARMUP:
		await process_frame

	var player := root.get_tree().get_first_node_in_group("player") as Node3D
	var rig := root.get_tree().get_first_node_in_group("camera_rig")
	if player == null or rig == null:
		push_error("no player or no camera_rig in the scene")
		quit(1)
		return

	for key: String in STOPS.keys():
		await _park(player, STOPS[key])
		_report(key, rig)
		await _shoot(key)

	await _park(player, TALK_SPOT)
	var dlg := root.get_node_or_null("/root/Dialogue")
	if dlg != null:
		dlg.start({"start": {"speaker": "Maren", "text": "Framing check.", "responses": []}})
		for i in SETTLE:
			await physics_frame
		_report("talk_in_arena", rig)
		await _shoot("talk_in_arena")
		if dlg.has_method("close"):
			dlg.close()
		else:
			dlg.finished.emit()
		for i in SETTLE:
			await physics_frame
		_report("talk_released", rig)
		await _shoot("talk_released")
	quit(0)


## SETTLES ON THE PHYSICS TICK, not the process tick, and that is the difference between this
## working and silently reporting nothing. Area3D resolves overlap in the physics step, so a player
## teleported into a zone is not INSIDE it — as far as body_entered is concerned — until one has
## run. Waiting on process_frame instead gives an empty claim list at every stop.
func _park(player: Node3D, pos: Vector3) -> void:
	player.global_position = pos
	player.set("velocity", Vector3.ZERO)
	for i in SETTLE:
		await physics_frame


func _report(key: String, rig) -> void:
	# _zoom and _claims are private. Read them anyway: the whole point is to see what the rig
	# DECIDED, which is not the same as what the scene asked for, and that difference is the bug.
	var z: float = rig.get("_zoom")
	var claims: Array = rig.get("_claims")
	var names: Array[String] = []
	for c in claims:
		var o = c["owner"]
		names.append("%s(p%d)" % [o.name if is_instance_valid(o) else "<freed>", c["priority"]])
	print("[CAM] %-14s zoom=%.2f  claims=[%s]" % [key, z, ", ".join(names)])


func _shoot(key: String) -> void:
	for i in 20:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + "cam_" + key + ".png"
	print("[SHOT] %-14s %s  %s" % [key, "ok" if img.save_png(path) == OK else "FAILED", path])

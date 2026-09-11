extends SceneTree
## PHOTOGRAPH THE HUB ARENA THROUGH THE GAME'S OWN CAMERA RIG.
##
##   Godot_console.exe --path . --resolution 1600x900 --script res://scripts/dev/shot_arena.gd -- \
##       --out=C:/some/folder [--strip] [--only=vista]
##
## MUST RUN WITHOUT --headless. The dummy renderer has no pixels, so a headless run saves black
## frames — the same rule every other shot script here carries.
##
## WHY NOT shot_scene.gd. That harness builds its own Camera3D, which is right for photographing a
## building and wrong for anything that lives in the RIG: the vista framing, the per-zone depth of
## field, the frame shift. All of those are CameraRig state, so the picture has to be taken through
## the rig's camera or it is a photograph of a camera that does not exist in the game.
##
## AND IT WAITS. CameraZone framing is lerped at zoom_speed 4.0, so a claim takes about 1.5 s to
## converge — roughly 90 physics frames. A shot at 30 frames photographs the transition and reads as
## a botched framing. SETTLE is deliberately generous.
##
## --strip takes four frames a quarter-second apart at each stop. Wind phase, TAA smear and any
## transparent-surface ghosting are all motion artefacts: a still frame cannot show them, so the
## things most likely to be wrong are exactly the things one screenshot cannot see.

const SETTLE := 110          ## physics frames for the framing lerps to converge
const WARMUP := 60           ## process frames for SDFGI/TAA to settle before the first capture
const STRIP := 4
const STRIP_GAP := 0.25

## Standing spots, in world space.
const STOPS := {
	# inside TerraceVistaZone — the establishing shot, and the only place the diorama DOF applies
	"vista": Vector3(-37.0, 5.2, 69.5),
	# on the arena floor south of the gate — the gameplay control, framing must stay untouched here
	"gameplay": Vector3(6.88, -8.8, 52.0),
	# Close on a house FRONT, for windows and wall texture. The rig looks down -Z, so this has to
	# be a house whose front turns toward +Z: the houses face the central gate, which leaves
	# house_hall at world (25.85, 28.33) the only one presenting its windows to the default yaw.
	"windows": Vector3(25.0, -8.8, 46.0),
}

var _out := "user://"
var _strip := false
var _only := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
		elif a == "--strip":
			_strip = true
		elif a.begins_with("--only="):
			_only = a.substr(7)
	_run()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in WARMUP:
		await process_frame

	var player := root.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		push_error("no player")
		quit(1)
		return

	for key: String in STOPS.keys():
		if _only != "" and key != _only:
			continue
		player.global_position = STOPS[key]
		player.set("velocity", Vector3.ZERO)
		for f in SETTLE:
			await physics_frame
		await _shoot(key)
		if _strip:
			for s in range(1, STRIP):
				var t := 0.0
				while t < STRIP_GAP:
					t += 1.0 / 60.0
					await physics_frame
				await _shoot("%s_f%d" % [key, s])
	quit(0)


func _shoot(name: String) -> void:
	for i in 20:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + "arena_" + name + ".png"
	var err := img.save_png(path)
	print("[SHOT] %-16s %s  %s" % [name, "ok" if err == OK else "FAILED", path])
	# Same idiom as make_street.gd's _stats(): the foliage claim is "one draw call per patch", and
	# that is a number, not a belief.
	print("[PERF] %-16s draws=%d prims=%d objects=%d" % [
			name,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])

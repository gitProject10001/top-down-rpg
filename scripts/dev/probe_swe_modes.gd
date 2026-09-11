extends SceneTree
## DO THE BED PROFILES ACTUALLY DO WHAT THEY SAY?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_modes.gd
##
## Every profile is a claim about a piece of terrain, and until now nothing checked any of them. The
## claim that went unchecked longest was TERRACES: its middle step stands 0.65 m above rest, the
## bench opens with its source at the centre of the bed, which lands there, and a spring on dry
## ground was silently dropped - so the report came back "terraces does not spawn water" and it was
## not the terraces. This is the probe that would have said so in one line.
##
## For each profile: how much of the extent is below its own rest surface (so can hold water), what
## the reset actually seeds, and - for the three that carry a boundary and a source - whether water
## is still arriving after a few hundred steps.

var _rip: Node = null
var _lab: Node = null
var _fail := 0

## name, profile index, steps to run, and whether the volume should be RISING at the end
const CASES := [
	["flat pan ", 0, 300, false],
	["valley   ", 1, 300, false],
	["terraces ", 2, 300, true],
	["bowl     ", 3, 300, true],
	["ramp     ", 4, 300, false],
	["RIVER    ", 5, 600, false],
	["BEACH    ", 6, 600, false],
	["WATERFALL", 7, 900, true],
]


func _initialize() -> void:
	_lab = (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(_lab)
	current_scene = _lab
	for _i in 30:
		await process_frame
	_rip = root.get_node("/root/Ripples")
	_lab.set("_live", false)
	if not _lab.has_method("_read_back"):
		print("[MODES] FAIL: swe_lab.gd did not load")
		quit(1)
		return
	_rip.set("depth_mode", true)
	_rip.set("staggered", true)
	_rip.call("sim_set", &"seep", 0.0)

	print("[MODES] profile      wet at seed    volume seeded -> after N steps      max h   max|u|")
	for c: Array in CASES:
		await _one(c[0], int(c[1]), int(c[2]), bool(c[3]))

	print("[MODES] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


func _one(name_: String, prof: int, steps: int, want_rising: bool) -> void:
	_lab.get_node("Bed").set("profile", prof)
	_lab.call("_apply_profile_defaults", prof)
	_lab.call("_rebuild")
	# EMPTY for the ones with a source, so "water arrived" means something. FULL for the rest,
	# because their claim is about where water CAN sit rather than about filling.
	await _lab.call("_reset", want_rising)
	_lab.call("_read_back")
	var seeded := float(_lab.get("_volume"))
	var wet0 := float(_lab.get("_wet_area"))
	for _i in steps:
		_lab.call("_feed_sink", 1)
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")
	var after := float(_lab.get("_volume"))
	var res := int(_rip.get("RES"))
	print("[MODES] %s   %7.0f m2    %9.2f -> %9.2f m3 (%4d st)   %6.3f  %6.3f"
			% [name_, wet0, seeded, after, steps, _max_h(res), _max_u(res)])

	# THE CLAIM EVERY PROFILE MAKES: some of it is below its own rest surface. A profile that holds
	# no water anywhere is a bug in the arithmetic, and it is the one nobody notices until they
	# select it and see a dry map.
	if want_rising:
		if after <= seeded + 1.0:
			print("[MODES]    FAIL: %s was given a source and gained %.2f m3 - nothing is arriving"
					% [name_.strip_edges(), after - seeded])
			_fail += 1
	else:
		if wet0 <= 0.0:
			print("[MODES]    FAIL: %s seeds no wet area at all - no part of this bed is below its "
					% name_.strip_edges() + "own rest surface")
			_fail += 1
	if _diverged(res):
		print("[MODES]    FAIL: %s diverged" % name_.strip_edges())
		_fail += 1


func _max_h(res: int) -> float:
	var img: Image = _lab.get("_state_img")
	if img == null:
		return 0.0
	var top := 0.0
	for z in range(0, res, 2):
		for x in range(0, res, 2):
			top = maxf(top, img.get_pixel(x, z).r)
	return top


func _max_u(res: int) -> float:
	var top := 0.0
	for z in range(0, res, 2):
		for x in range(0, res, 2):
			top = maxf(top, (_lab.call("_vel_at", Vector2i(x, z), res) as Vector2).length())
	return top


func _diverged(res: int) -> bool:
	var img: Image = _lab.get("_state_img")
	if img == null:
		return true
	for z in range(0, res, 4):
		for x in range(0, res, 4):
			var px := img.get_pixel(x, z)
			if is_nan(px.r) or absf(px.r) > 100.0 or absf(px.g) > 100.0:
				return true
	return false

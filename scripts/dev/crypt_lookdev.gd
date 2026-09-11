extends SceneTree
## The crypt art pass's eyes AND its ruler. Shoots the same fixed frames every run, and measures
## the four things the pass is actually claiming, so "it looks better" can be checked rather than
## asserted.
##
## MUST RUN WITHOUT --headless. The dummy renderer has no pixels to read back, and NoiseTexture2D
## generates on a worker thread — a headless run photographs flat grey.
##
##   Godot_console.exe --path . --resolution 1600x900 \
##       --script res://scripts/dev/crypt_lookdev.gd -- --out=C:/some/folder
##
## WHY IT LOADS main.tscn. The crypt has no WorldEnvironment of its own: it renders inside the hub's
## persistent one, and the whole black-void pass IS an override of that environment. A rig with its
## own hand-written Environment would photograph a look the game never shows — which is exactly the
## drift docs/anime-look-todo.md §A3 is about. So the real Environment is lifted out of main.tscn,
## and the sun and env are put in the groups DungeonGenerator._dim_world looks them up by. Get that
## wrong and _dim_world silently no-ops.
##
## The seed is PINNED. Comparing phase to phase only means anything on the same dungeon.

const ZONE := "res://scenes/world/zone_crypt.tscn"
const MAIN := "res://scenes/main.tscn"
const SEED := 42                    ## also used by verify_dungeon's lock suite, so it has real gates
const WARMUP := 100                 ## seamless noise generates on a thread; shot_houses.gd uses 90
const SETTLE := 20                  ## between shots: SDFGI needs a few frames to re-fit after a move
const DISCARD := 40                 ## frames _perf drops before sampling — see the note in _perf
## The measurement floor, in ms. Not a guess: the occlusion-culling A/B below is a KNOWN ZERO (the
## dungeon contains no occluders, so the two halves render identically) and across three runs it
## came back 0.00, 0.43 and 0.68, with the sign flipping. That is a 3070 stepping between boost
## states, not anything in the scene. Any A/B smaller than this is not a result — which is why the
## verdict on occlusion culling is "free" rather than "cheap". SDFGI's 1.6 ms clears it twofold.
const PERF_NOISE := 0.70

## The authored viewing angle, from CameraRig: ~53 degrees above horizontal.
const PITCH := 0.93
const FOV := 50.0

var _out := "user://"
var _world: Node3D
var _cam: Camera3D
var _zone: Node3D
var _env: Environment
var _report: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	# KILL VSYNC BEFORE ANYTHING RENDERS, or every single number in the perf table is 16.67 ms and
	# the whole cost ruler is worthless. `await process_frame` in a SceneTree script resumes on the
	# idle frame, so what it measures is the PRESENTED frame — vsync included.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_run()


func _run() -> void:
	# LET THE TREE START FIRST. _initialize() runs BEFORE the first frame, and a node added to root
	# at that point does not get _ready until the tree enters — so zone_crypt would not have
	# generated, would not have moved itself to (500, 0, 500), and would not have dimmed the world
	# by the time the camera is aimed at it. The symptom is a camera pointing at the origin, 700 m
	# from the dungeon, photographing the inside of the fog. One frame makes add_child synchronous.
	await process_frame

	_world = Node3D.new()
	_world.name = "CryptLookdev"
	root.add_child(_world)
	_stage()

	_zone = (load(ZONE) as PackedScene).instantiate() as Node3D
	_zone.set("dungeon_seed", SEED)
	# _ready() generates the whole dungeon synchronously and calls _dim_world, so by the time
	# add_child returns the environment override has already happened.
	_world.add_child(_zone)

	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.current = true
	_cam.far = 400.0

	var origin: Vector3 = _zone.position                       # the start room, cell (0,0,0)
	var neighbour := _neighbour_centre()
	_say("[STAGE] start room %s, unlit neighbour %s" % [origin, neighbour])
	_say("[AMBIENT] source=%s energy=%.4f color=%s sky_contrib=%.2f" % [
			_env.ambient_light_source, _env.ambient_light_energy, _env.ambient_light_color,
			_env.ambient_light_sky_contribution])
	_report_lights()
	_report_pieces()

	# 1. THE HERO FRAME: the start room at the game's own angle. Every number below comes off this.
	_orbit(origin + Vector3(0, 1.0, 0), 19.0, 0.0)
	var hero := await _shoot("01_room_iso")
	await _perf("01_room_iso")

	# 2. THE SAME DIRECTION, PULLED BACK. What the depth-fog curtain actually hides — and the frame
	# where the old grey void filled everything above the walls.
	_orbit(origin + Vector3(0, 1.0, 0), 48.0, 0.0)
	var far := await _shoot("02_far")
	await _perf("02_far")

	# 3. A FLOOR/WALL JUNCTION, CLOSE AND LOW. Cavity, grime pooling low, and moss in the mortar are
	# all sub-metre effects; an 19 m iso shot cannot resolve any of them.
	_look(origin + Vector3(-4.0, 1.6, 1.5), origin + Vector3(-9.0, 0.2, -4.0), 55.0)
	await _shoot("03_junction")

	# 4. A LONG WALL RUN, STRAIGHT ON. Three or four 4 m modules in one frame is the ONLY view that
	# answers the question this whole pass exists for: do two copies of wall_brick_a read the same?
	_look(origin + Vector3(0.0, 1.8, 0.0), origin + Vector3(0.0, 1.8, -20.0), 62.0)
	var repeat := await _shoot("04_repeat")
	await _perf("04_repeat")

	# 4b. THE WALL AS AN ELEVATION, straight on and level with the middle of the stack. The ONLY
	# frame that answers whether the banding reads as architecture or as a tall fence — which is
	# the entire thesis of building the wall in courses rather than just making it taller.
	# INSIDE the room (its half-depth is 6), or the near wall's own coping fills the foreground and
	# you are photographing the top of a wall instead of the elevation of the far one.
	_look(origin + Vector3(0.0, 3.2, 5.0), origin + Vector3(0.0, 3.0, -6.0), 62.0)
	await _shoot("09_wall_stack")

	# 4c. THE GAME'S REAL CAMERA AT THE NEAR FOLLOW CLAMP — the exact worst case the diorama cutaway
	# exists for. DungeonRoom clamps the follow target to footprint.z * 0.5 - 1.0, so this is as
	# close to the camera-side wall as the player can physically get. If the cut ever regresses,
	# this is the frame where the player disappears.
	var clamp_z: float = maxf(DungeonLayout.ROOM_SIZE.z * 0.5 - 1.0, 1.0)
	var stand := origin + Vector3(0.0, 0.0, clamp_z)
	_look(stand + Vector3(0.0, 12.5, 9.375) * 1.15, stand + Vector3(0.0, 1.0, 0.0), 42.0)
	await _shoot("10_near_clamp")

	# 5+6. THE LIT ROOM AND AN UNLIT ONE, from identical cameras. DungeonRoom.set_lit() darkens every
	# room but the player's, and with shadow_enabled = false on every torch the only thing stopping
	# light crossing a wall is SDFGI occlusion. Two matched frames make that a ratio, not an opinion.
	_look(origin + Vector3(0, 30, 0.01), origin, 46.0)
	var lit := await _shoot("05_lit_room")
	if neighbour != Vector3.INF:
		_look(neighbour + Vector3(0, 30, 0.01), neighbour, 46.0)
		var dark := await _shoot("06_unlit_room")
		_leak_check(lit, dark)

	# 7. A COMBAT ROOM WITH ITS FURNITURE. The start room is planned with no cover, so it shows
	# neither statue nor brazier no matter what the theme lists — every shot above is of an empty
	# room, which is exactly how "the new props do not spawn" would look if it were true.
	var statue := _first_statue()
	if statue != Vector3.INF:
		# LIGHT THE ROOM FIRST. Every room but the player's is held at 6% by set_lit, so a frame of
		# the furniture in any other room is a photograph of the dark state — the first version of
		# this shot came back all but black and looked exactly like the props had failed to spawn.
		var host := _room_at(statue)
		if host != null:
			host.set_lit(true, false)
			await process_frame
		_look(statue + Vector3(4.0, 2.6, 4.6), statue + Vector3(0, 1.4, 0), 55.0)
		await _shoot("07_statue")
		if host != null:
			_orbit(host.global_position + Vector3(0, 1.0, 0), 19.0, 0.0)
			await _shoot("08_combat_room")
	else:
		_say("[SHOT] no statue in this dungeon — no cover_large slot was planned")

	# 11+13. THE MOVING LIGHT. Everything above photographs a crypt lit by things bolted to walls;
	# these two are the acceptance test for the actual ask, and they are the only shots that build
	# their own subject rather than photographing the generated dungeon.
	await _torch_suite(origin)

	await _shaft_check(origin)
	await _ambient_probe(origin)

	# COST, measured last so the quality numbers above are taken on a frame nobody has poked.
	# Back to the hero frame first: the stress and the A/B only mean anything on the same view every
	# run, and shot 08 left the camera in a different room.
	_orbit(origin + Vector3(0, 1.0, 0), 19.0, 0.0)
	for i in SETTLE:
		await process_frame
	await _perf_sdfgi_ab()
	await _perf_occlusion_ab()
	await _perf_stress()

	_measure(hero, far, repeat)
	_perf_table()
	_write_report()
	quit(0)


# ---------------------------------------------------------------- the measurements ----------


## EVERY CHECK HERE IS TWO-SIDED, AND THAT IS NOT PEDANTRY. The first version tested only upper
## bounds — "void below 0.005", "saturation below 0.15" — and then reported five green PASSes on a
## frame that was pure black from edge to edge, because an unlit room satisfies every one of them.
## A dark dungeon and a broken one look identical to a one-sided test.
func _measure(hero: Image, far: Image, repeat: Image) -> void:
	_say("")
	_say("=== measurements (hero frame unless noted) ===")

	# THE VOID. Top strip of the hero frame is above the walls: nothing but background and fog.
	# This is the number the whole of phase 1 is for, and the number the original screenshot failed
	# at daylight levels.
	# THE VOID IS MEASURED ON THE FAR FRAME NOW, and that is a consequence of the walls getting
	# taller rather than a relaxed bound. The hero frame's top 8% used to be empty sky above a 3 m
	# wall; at 6.8 m it is the far wall's upper courses, so the old rect measured stone and read
	# 0.211. Pulled back to 48 m the crypt is small in frame and genuinely surrounded by nothing,
	# which is the thing the check was always about. The positive half of the same observation is
	# `vertical stone fraction` below.
	var void_l: float = _stats(far, Rect2(0.0, 0.0, 1.0, 0.08)).mean
	_verdict("void luminance (far frame)", void_l, void_l < 0.005, "< 0.005")

	# THE ROOM GOT TALLER, stated as a number. That band was void before the courses existed, so a
	# regression to a 3 m box shows up here as a collapse toward zero.
	var top: float = _stats(hero, Rect2(0.1, 0.0, 0.8, 0.30)).readable
	_verdict("vertical stone fraction", top, top > 0.20, "> 0.20")

	# The gate for whether a second, higher sconce tier is needed: if the upper course is not lit,
	# 3.5 m of new wall is just a dark band and the height is wasted.
	var upper: float = _stats(hero, Rect2(0.1, 0.0, 0.8, 0.22)).med
	_verdict("upper course luminance", upper, upper > 0.02 and upper < 0.45, "0.02..0.45")

	# THE ROOM IS VISIBLE AT ALL — two numbers, because one mean cannot say it.
	#
	# The first version averaged luminance over the middle of the frame and demanded it clear 0.045.
	# That is the wrong quantity: most of that rect is floor which is SUPPOSED to be dark in a
	# torch-lit crypt, so the mean is pinned low by exactly the thing the art is trying to do, and
	# chasing it just floods the room with ambient. It also did not move at all when ambient went up
	# 40% — SDFGI occludes ambient inside a sealed room — while the unlit NEIGHBOUR brightened 2.6x
	# and wrecked the leak ratio. Ambient is not the lever in here; torchlight is.
	#
	# So ask the two questions separately: is the lit stone bright enough to read as stone, and is
	# enough of the room above the floor of visibility to fight in.
	# BRIGHTNESS: a high percentile over the whole frame, not a mean or a median over a hand-drawn
	# rect. Every rect in an isometric shot of a room is part lit stone and part black void, so a
	# median lands wherever the boundary happens to fall — the wall band read 0.011 while the bricks
	# in it were plainly bright, because 45% of the rect was void. p90 asks the question that
	# actually matters: does the stone the torches DO reach read as stone?
	var p90: float = _stats(hero, Rect2(0.0, 0.1, 1.0, 0.8)).p90
	_verdict("lit stone p90", p90, p90 > 0.10 and p90 < 0.60, "0.10..0.60")

	# COVERAGE: and separately, how much of the room is above the floor of visibility. These two
	# together are the readability of the frame; neither alone is.
	var hero_body := _stats(hero, Rect2(0.15, 0.3, 0.7, 0.5))
	_verdict("room readable fraction", hero_body.readable, hero_body.readable > 0.15, "> 0.15")

	# THE DARK END. If ambient or shade_occlusion is leaking, the crypt has no true darks and the
	# whole thing reads as flat grey stone in a black box rather than as torch pools.
	var body := _stats(far, Rect2(0.0, 0.45, 1.0, 0.5))
	_verdict("stone p5 luminance", body.p5, body.p5 < 0.10, "< 0.10")

	# RESIDUAL SKY BLUE — measured as saturation IN THE COOL HUES ONLY, which is the whole point.
	# The first version tested overall saturation against 0.15 and started failing the moment the
	# torches worked, because a room lit by fire is legitimately saturated: it read 0.27 at hue 8
	# degrees, which is amber and is exactly right. Overall saturation cannot tell "the sky is still
	# leaking in" from "this is firelight". Only the hue band can.
	_verdict("residual sky blue", hero_body.blue, hero_body.blue < 0.06, "< 0.06")
	# THE HUE IS NOW A GATE, not just a printed aside. It was already being measured and reported
	# and nothing was checking it, which meant the one failure mode the rest of the checks are all
	# blind to — the crypt going colour-neutral — could only be caught by somebody looking at a PNG.
	# A grey bounce, a white GI bake, a fog albedo left at an outdoor value: every one of those
	# leaves luminance, contrast and leak ratio exactly where they were and drains the fire out of
	# the room. Bounded on both sides because too far the other way is sodium orange, which this
	# project has already had once and wrote a shader uniform to fix (see light_tint_amount).
	var hue: float = hero_body.hue * 360.0     # _stats returns 0..1, like Color.h
	_verdict("torchlit hue (degrees)", hue, hue > 12.0 and hue < 45.0, "12 .. 45")
	_say("    (mean hue %.0f deg, overall saturation %.2f — near 30 is torchlit stone, near 220 is sky)"
			% [hero_body.hue * 360.0, hero_body.sat])

	# THE FOG CURTAIN. At 48 m out, everything past fog_end must be gone.
	var fog: float = _stats(far, Rect2(0.0, 0.0, 1.0, 0.12)).mean
	_verdict("fog curtain (far frame top)", fog, fog < 0.01, "< 0.01")

	# THE REPEAT. Two 4 m modules side by side in frame 04: correlate their pixel blocks. High
	# correlation means the world-space sampling is not doing its job — most likely a noise scale
	# that is an exact divisor of the 4 m module pitch, so every module samples the same phase.
	# Only meaningful on pixels that have something in them — two black blocks correlate at 0.
	var r := _correlate(repeat, Rect2(0.18, 0.35, 0.22, 0.3), Rect2(0.60, 0.35, 0.22, 0.3))
	var lit_enough: bool = _stats(repeat, Rect2(0.18, 0.35, 0.64, 0.3)).mean > 0.01
	_verdict("module correlation", r, lit_enough and r < 0.85,
			"< 0.85" if lit_enough else "N/A dark")

	# THERE IS DELIBERATELY NO "SHADOW PRESENCE" CHECK ON THIS FRAME, and the reason is worth the
	# paragraph because it is a good idea that does not survive measurement.
	#
	# The plan called for one: standard deviation of luminance over the lit wall, on the reasoning
	# that cast shadows put light next to dark and so raise spread, where a flat GI wash of the same
	# mean lowers it. Sound in principle. Measured over the upper-wall rect across four builds of
	# this exact frame:
	#
	#     pre-shadow (8b8f403)          sd 0.1405
	#     nine casters on (0c89630)     sd 0.1412
	#     SDFGI dialled back (72ff0a6)  sd 0.1544
	#     with fog (7108033)            sd 0.1494
	#
	# Switching nine lights from shadowless to casting moves it by 0.0007. The kit's own albedo and
	# normal variation — chunky ashlar, four noise layers, per-brick COLOR_0 — swamps the shadow
	# term completely, so any threshold that passes today would also have passed before the shadows
	# existed. A check that cannot separate the two states is not a weak check, it is a decoration
	# that reports green forever, and this file's own header is about exactly that failure.
	#
	# The regression it was meant to catch is already covered, and covered CAUSALLY rather than
	# correlationally: 11_torch_shadow toggles one caster and reads the same rect twice, so it
	# measures the shadow itself instead of a statistic that correlates with it on a good day.


func _leak_check(lit: Image, dark: Image) -> void:
	var a: float = _stats(lit, Rect2(0.2, 0.2, 0.6, 0.6)).mean
	var b: float = _stats(dark, Rect2(0.2, 0.2, 0.6, 0.6)).mean
	var ratio: float = a / maxf(b, 1e-5)
	_say("")
	# > 12, not > 20. The theme's ambient is deliberately NOT zero — unlit stone has to read as a
	# shape rather than a hole — and a uniform ambient floor under both rooms caps the achievable
	# ratio no matter how well the walls occlude. What this is actually guarding against is a real
	# leak, and that shows up as a ratio of 1 to 3, nowhere near this bar.
	_verdict("lit/unlit room ratio", ratio, ratio > 12.0, "> 12")
	_say("    (lit %.4f, unlit %.4f — this is the SDFGI occlusion test: torches cast no shadows,"
			% [a, b])
	_say("     so nothing else stops an OmniLight lighting the next room through a wall)")


## 12. IS THE VOLUMETRIC FOG DOING ANYTHING, AND IS IT DOING TOO MUCH. A low camera raking along a
## wall past the candelabras is the view a shaft is visible from at all — from the game's own
## overhead angle you are looking down THROUGH the fog rather than across it, and even a good one
## barely registers.
##
## Bounded on both sides, and the upper bound is the one that will actually fire. Fog is the easiest
## thing in the whole plan to overdo: it costs nothing to type a bigger number, it makes a still
## frame look atmospheric, and it quietly greys out the brick relief that the last four commits were
## spent carving. Below 0.008 it is not worth its froxel grid; above 0.070 it is washing the room
## out. The check does not care which side it fails on.
func _shaft_check(origin: Vector3) -> void:
	if _env == null:
		return
	# Along the -X wall, low and looking down the run of it, so several sconces stack in depth.
	_look(origin + Vector3(-7.0, 1.2, 5.0), origin + Vector3(-7.0, 1.6, -6.0), 62.0)
	var on := await _shoot("12_shaft")
	_env.volumetric_fog_enabled = false
	var off := await _shoot("12b_shaft_off")
	_env.volumetric_fog_enabled = true

	# The middle band only: the floor is unaffected by fog and the void above the wall has nothing
	# to scatter in, so including either just dilutes the signal with pixels that cannot move.
	var r := Rect2(0.15, 0.25, 0.70, 0.45)
	var d: float = _stats(on, r).mean - _stats(off, r).mean
	_verdict("volumetric fog contribution", d, d > 0.008 and d < 0.070, "0.008 .. 0.070")
	_say("    (fog on %.4f, off %.4f)" % [_stats(on, r).mean, _stats(off, r).mean])
	for i in SETTLE:
		await process_frame


## The VoxelGI A/B that used to live here is gone: it asked whether a bake was worth its cost, the
## answer was yes, and RoomGI now ships one. Baking a second one over the same room would have
## measured two overlapping GI volumes and reported nonsense. The numbers it produced are recorded
## in scripts/dungeon/style/room_gi.gd's header, which is where they are now load-bearing.


## WHAT AMBIENT ACTUALLY DOES IN THIS SCENE, which turns out to be nothing, and why.
##
## dungeon_theme.gd:113-122 records two separate occasions when raising ambient "moved the hero
## frame not at all" and puts it down to ambient not being room-gated. That explanation never fitted
## the observation — an ungated light still lights the room you are in. Cutting the crypt's ambient
## energy by 65% (0.5 to 0.175 via ambient_factor) and getting FOUR IDENTICAL DECIMAL PLACES on
## every check is not a small effect, it is no effect, and it wants a real answer.
##
## Four measurements of the same frame settle it: ambient high/low crossed with SDFGI on/off.
func _ambient_probe(origin: Vector3) -> void:
	if _env == null:
		return
	_orbit(origin + Vector3(0, 1.0, 0), 19.0, 0.0)
	var base := _env.ambient_light_energy
	_say("")
	_say("=== is ambient doing anything? (hero frame, lit stone p90) ===")
	for gi in [true, false]:
		_env.sdfgi_enabled = gi
		for mul in [1.0, 4.0]:
			_env.ambient_light_energy = base * mul
			for i in 30:
				await process_frame
			var img := root.get_texture().get_image()
			_say("  sdfgi %-3s  ambient %.3f   p90 %.4f  mean %.4f" % [
					"on" if gi else "off", base * mul,
					_stats(img, Rect2(0.1, 0.15, 0.8, 0.7)).p90,
					_stats(img, Rect2(0.1, 0.15, 0.8, 0.7)).mean])
	_env.ambient_light_energy = base
	_env.sdfgi_enabled = true
	for i in SETTLE:
		await process_frame


## THE TWO SHOTS THAT TEST THE ACTUAL ASK: a light that moves and casts. Both build their own
## subject — a stand-in body and a torch — in an empty corner of the start room, because the
## generated dungeon contains no player and the checks have to be about the torch rather than about
## whatever the dresser happened to place.
##
## Torn down at the end, so the cost table that follows measures the crypt and not this rig.
func _torch_suite(origin: Vector3) -> void:
	var stage := Node3D.new()
	_world.add_child(stage)
	# OFF THE ROOM CENTRE, because the start room's centre is taken. DungeonGenerator parks the
	# ReturnPortal at (0, 0, 4) and it is a two-metre glowing slab — the first attempt at this shot
	# put the camera 0.5 m in front of it and photographed nothing but cyan.
	stage.global_position = origin + Vector3(0.0, 0.0, -2.5)

	# AND THE ROOM GOES DARK. Seven shadow-casting candelabras around the perimeter would put their
	# own shadows through the same floor this measures, and the number would be about them as much
	# as about the torch. Killing the room's lighting makes the torch the only thing in the frame
	# throwing anything, which is the only way the ratio means what its name says. The torch is
	# parented to `stage`, not to the room, so set_lit does not touch it.
	# ZEROED, NOT DIMMED. set_lit(false) holds the room's lights at 6%, which was enough to make this
	# check depend on the theme's energies rather than on the torch: raising fill_energy 8 -> 11 and
	# light_energy 7.5 -> 9.5 moved the torch's measured share 33% -> 27% without anything about the
	# torch changing. A check that reports a regression when an unrelated knob moves is worse than
	# no check. Zero them and the only directional light in the frame is the one being tested.
	var room := _room_at(origin)
	var doused: Array[Light3D] = []
	if room != null:
		room.set_lit(false, false)
		for n in _flatten(room):
			if n is Light3D:
				doused.append(n as Light3D)
				(n as Light3D).light_energy = 0.0

	# A NEUTRAL TEST CARD, because the crypt's own floor cannot carry this measurement. Measured on
	# the first working version: dark stone 2-4 m from the torch reads 0.01 in shadow and 0.03 lit,
	# and a ratio between two numbers that small is quantisation noise wearing a verdict's clothes.
	# A matte mid-grey plane is the standard way to shoot a lighting test and it makes the shadow
	# unambiguous. It is 0.6 albedo and perfectly flat, so nothing but the shadow varies across it.
	var card := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.0, 7.0)
	card.mesh = plane
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.6, 0.6, 0.6)
	grey.roughness = 1.0
	card.material_override = grey
	stage.add_child(card)
	card.position = Vector3(0.0, 0.02, 0.0)     # just proud of the floor tiles, no z-fighting

	# The body. A capsule on CHARACTER_LAYER, which is what ToonSkin puts the player's meshes on —
	# the whole question here is whether a light's cull mask also excludes a mesh from its SHADOW
	# map, and that is only meaningful on the layer the real player actually uses.
	var body := MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.radius = 0.32
	caps.height = 1.7
	body.mesh = caps
	body.material_override = grey
	body.layers = ToonSkin.CHARACTER_LAYER
	stage.add_child(body)
	body.position = Vector3(0.0, 0.85, 0.0)

	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.93, 0.82)
	torch.light_energy = 4.5
	torch.omni_range = 9.0
	torch.omni_attenuation = 1.5
	torch.shadow_enabled = true
	torch.shadow_bias = 0.025
	torch.shadow_normal_bias = 1.0
	torch.light_size = 0.15
	stage.add_child(torch)
	torch.position = Vector3(0.38, 1.25, 0.22)

	# THE CAMERA HAS TO BE INSIDE THE ROOM. The first version stood it 6.5 m back on +Z, which is
	# past the room's half-depth of 6 — outside the near wall, photographing its unlit outer face.
	# cutaway_out only removes the courses ABOVE the base, so there is still 3 m of solid masonry
	# there and the frame came back black with a lit strip over the top of it. 4.5 m is inside.
	var at := stage.global_position
	_look(at + Vector3(-1.1, 1.6, 4.5), at + Vector3(0.0, 0.7, 0.0), 50.0)
	# A coarse luminance grid of the frame, printed once. The rects below have to sit on the shadow
	# and on lit floor beside it, and eyeballing screen fractions off a screenshot is how you end up
	# measuring a wall. This is the receipt for where they were put.
	# 11. THE SAME RECT, WITH THE CASTER ON AND OFF. The obvious test — shadow side against lit side
	# — was tried first and is not well posed: the two rects are at different distances from a point
	# light, so the ratio mixes occlusion with inverse-square falloff and lands wherever the
	# geometry happens to put it (0.60 measured, against a 0.55 bar, meaning nothing either way).
	# Toggling the caster changes exactly one thing, so the difference is the shadow and nothing else.
	var probe := Rect2(0.12, 0.52, 0.16, 0.12)     # solidly inside the umbra; see the grid below

	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var clean := await _shoot("11a_torch_nocaster")
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var cast := await _shoot("11_torch_shadow")
	# A coarse luminance grid, printed once. `probe` has to sit on the shadow, and eyeballing screen
	# fractions off a screenshot is how a check ends up measuring a wall by accident. The receipt.
	_grid(cast)

	# AND THE PLAN'S BIGGEST UNKNOWN, answered rather than argued. HeroLight used to carry
	# light_cull_mask = 1048573, excluding render layer 2 — the layer ToonSkin puts every character
	# mesh on. Whether that mask also removes the mesh from the light's SHADOW MAP is engine
	# internal and version sensitive, and the whole feature is a no-op if it does. Put the old mask
	# back on an otherwise identical torch and read the same rect.
	torch.light_cull_mask = 1048573
	var masked := await _shoot("11b_torch_oldmask")
	torch.light_cull_mask = 1048575

	var base: float = _stats(clean, probe).mean
	var with_shadow: float = _stats(cast, probe).mean
	var with_mask: float = _stats(masked, probe).mean
	var ratio: float = with_shadow / maxf(base, 1e-5)
	# BOUND AT 0.80, NOT THE 0.55 THE PLAN ASKED FOR, and the difference is a finding rather than a
	# climbdown. Measured three times with the probe in different parts of the umbra, this ratio
	# does not move off ~0.67 — because a shadow can only remove the light that is actually
	# DIRECTIONAL, and on this surface the torch supplies barely a third of it. The rest is the
	# theme's ambient plus SDFGI, neither of which a shadow map touches. 0.55 is not reachable by
	# any amount of shadow work while the ambient floor is where it is.
	#
	# So the check tests what it can honestly test: no shadow at all reads 1.00, and anything at or
	# under 0.80 is a real, substantial cast shadow. Two-sided as ever — a black frame has a
	# beautiful shadow ratio, so the unoccluded reading has to be genuinely lit.
	_verdict("torch casts the player's shadow", ratio, ratio < 0.80 and base > 0.05,
			"< 0.80 with unoccluded > 0.05")
	_say("    (unoccluded %.4f, shadowed %.4f — the torch supplies %.0f%% of the light here and"
			% [base, with_shadow, 100.0 * (base - with_shadow) / maxf(base, 1e-5)])
	_say("     ambient plus GI supplies the rest, which is the ceiling on every shadow in the crypt)")
	# THE PLAN'S BIGGEST UNKNOWN, ANSWERED. If these two agree, light_cull_mask does NOT remove a
	# mesh from the light's shadow map — masking only stops the light SHADING it.
	_say("    (same rect with the old light_cull_mask %.4f — %s)" % [with_mask,
			"the mask does not affect shadow maps" if absf(with_mask - with_shadow) < 0.01
			else "THE MASK KILLS THE SHADOW — dropping it was load-bearing"])

	# 13. THE ACCEPTANCE TEST. Move the light, and require the picture to change — that is what
	# "dynamic shadows for moving lights" means, reduced to one number. Bounded ABOVE as well:
	# a huge difference is an exposure shift or a light that simply left the frame, not a shadow
	# sweeping across a floor.
	var before := await _shoot("13_moving_a")
	torch.position += Vector3(2.5, 0.0, 0.0)
	var after := await _shoot("13_moving_b")
	var moved := _mean_abs_diff(before, after, Rect2(0.2, 0.45, 0.6, 0.45))
	_verdict("moving-light shadow delta", moved, moved > 0.010 and moved < 0.35, "0.010 .. 0.35")

	stage.queue_free()
	# No manual restore needed, and that is worth knowing rather than guessing at: set_lit writes
	# each light's energy from the table it recorded at COLLECT time, not from whatever the property
	# currently holds, so lighting the room back up overwrites the zeroes outright.
	if room != null:
		room.set_lit(true, false)
	await process_frame


## A 10x8 luminance grid over the whole frame, printed as text. Placing a measurement rect by
## squinting at a PNG is how a check ends up quietly measuring a wall instead of a floor; this makes
## the placement checkable from the log alone, and diffable between runs.
func _grid(img: Image) -> void:
	_say("    luminance grid (x across, y down, each cell 10%% of the frame):")
	for gy in 8:
		var row := "     "
		for gx in 10:
			row += "%5.2f" % _stats(img, Rect2(gx * 0.1, gy * 0.125, 0.1, 0.125)).mean
		_say(row)


## Mean absolute per-pixel luminance difference between two frames over a rect. The whole point is
## that it is signless: a shadow sweeping right darkens as much as it brightens, and a signed mean
## would cancel that to nothing and report a working feature as broken.
func _mean_abs_diff(a: Image, b: Image, r: Rect2) -> float:
	var x0 := int(r.position.x * a.get_width())
	var y0 := int(r.position.y * a.get_height())
	var x1 := mini(int((r.position.x + r.size.x) * a.get_width()), a.get_width())
	var y1 := mini(int((r.position.y + r.size.y) * a.get_height()), a.get_height())
	var sum := 0.0
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			sum += absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance())
			n += 1
	return sum / maxf(n, 1)


## Mean/p5 luminance, mean saturation and mean hue over a rect given in 0..1 screen fractions.
func _stats(img: Image, r: Rect2) -> Dictionary:
	var x0 := int(r.position.x * img.get_width())
	var y0 := int(r.position.y * img.get_height())
	var x1 := mini(int((r.position.x + r.size.x) * img.get_width()), img.get_width())
	var y1 := mini(int((r.position.y + r.size.y) * img.get_height()), img.get_height())
	var lums := PackedFloat32Array()
	var sum := 0.0
	var sat := 0.0
	# Hue is a circular quantity: averaging 350 and 10 the naive way gives 180, which would read as
	# cyan on a scene that is entirely warm red. Sum unit vectors instead, weighted by saturation so
	# near-grey pixels (whose hue is numerically meaningless) do not vote.
	var hx := 0.0
	var hy := 0.0
	# Saturation carried by COOL pixels only (hue 180-270 deg). This is the sky-leak signal, kept
	# separate from overall saturation because torchlight swamps that one.
	var blue := 0.0
	var readable := 0.0
	var n := 0
	# Stride 2: a quarter of the pixels is plenty for a mean over tens of thousands, and the full
	# scan on a 1600x900 frame is slow enough in GDScript to notice.
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var c := img.get_pixel(x, y)
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			lums.append(l)
			sum += l
			sat += c.s
			hx += cos(c.h * TAU) * c.s
			hy += sin(c.h * TAU) * c.s
			if c.h > 0.5 and c.h < 0.75:
				blue += c.s
			# "Not a black hole": the luminance at which a surface stops being absence and starts
			# being dim stone you can navigate by. Eyeballed against the reference dioramas.
			if l > 0.012:
				readable += 1.0
			n += 1
	if n == 0:
		return {"mean": 0.0, "p5": 0.0, "p90": 0.0, "med": 0.0, "sat": 0.0, "hue": 0.0,
				"blue": 0.0, "readable": 0.0}
	lums.sort()
	return {
		"mean": sum / n,
		"p5": lums[clampi(int(lums.size() * 0.05), 0, lums.size() - 1)],
		"p90": lums[clampi(int(lums.size() * 0.90), 0, lums.size() - 1)],
		"med": lums[n / 2],
		"sat": sat / n,
		"hue": fposmod(atan2(hy, hx) / TAU, 1.0),
		"blue": blue / n,
		"readable": readable / n,
	}


## Pearson correlation of the luminance of two equal-sized screen rects. The repetition test.
func _correlate(img: Image, a: Rect2, b: Rect2) -> float:
	var va := _luma_block(img, a)
	var vb := _luma_block(img, b)
	var n := mini(va.size(), vb.size())
	if n < 16:
		return 0.0
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += va[i]
		mb += vb[i]
	ma /= n
	mb /= n
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in n:
		var xa := va[i] - ma
		var xb := vb[i] - mb
		num += xa * xb
		da += xa * xa
		db += xb * xb
	return num / maxf(sqrt(da * db), 1e-6)


func _luma_block(img: Image, r: Rect2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x0 := int(r.position.x * img.get_width())
	var y0 := int(r.position.y * img.get_height())
	var w := int(r.size.x * img.get_width())
	var h := int(r.size.y * img.get_height())
	for j in range(0, h, 3):
		for i in range(0, w, 3):
			var c := img.get_pixel(mini(x0 + i, img.get_width() - 1),
					mini(y0 + j, img.get_height() - 1))
			out.append(c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722)
	return out


# ---------------------------------------------------------------- staging -------------------


## The GAME's environment, not one written here. Lifted straight out of main.tscn so the rig cannot
## drift from what the player sees, then parked in the groups _dim_world looks up by name.
func _stage() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	var src_env: Environment = null
	var sun_energy := 1.0
	var sun_rot := Vector3(-45, -130, 0)
	for n in _flatten(main):
		if n is WorldEnvironment and src_env == null:
			src_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			sun_energy = (n as DirectionalLight3D).light_energy
			sun_rot = (n as DirectionalLight3D).rotation_degrees

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	# duplicate(true): main.tscn's sub-resource is cached and shared, and DungeonEnv MUTATES it.
	# Without the copy this rig would leave a blacked-out Environment in the resource cache.
	_env = src_env.duplicate(true) if src_env != null else Environment.new()
	we.environment = _env
	we.add_to_group("world_env")
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = sun_energy
	sun.rotation_degrees = sun_rot
	sun.shadow_enabled = true
	sun.add_to_group("sun")
	_world.add_child(sun)

	main.free()                                   # never entered the tree; nothing ran
	_say("[STAGE] environment lifted from %s (sun energy %.3f)" % [MAIN, sun_energy])


# ---------------------------------------------------------------- the cost ruler ------------
#
# THE PROJECT HAS NEVER MEASURED WHAT ANYTHING COSTS. There is a quality ruler — the ten two-sided
# checks in _measure() — and no cost axis at all, which is how you ship four heavy features and
# discover you are at 12 fps with no idea which one did it.
# docs/environment-pipeline-todo.md has carried "what has never been measured is what it COSTS" as
# an open item since SDFGI was turned on. This closes it.

var _perf_rows: Array[String] = []


## Measure the frame we are currently parked on. Call straight after _shoot(), so the camera has
## already had its settle frames and the numbers describe the frame that was photographed.
func _perf(label: String, samples := 30) -> void:
	var rid := root.get_viewport_rid()
	# WALL CLOCK AND GPU TIMER, BOTH. viewport_get_measured_render_time_* is the right instrument
	# but nobody in this project has ever used it, and it can return zeros on some backends. If the
	# two disagree badly the wall clock is the number of record — so print both rather than trusting
	# one. The GPU timer also lags a couple of frames, hence sampling over `samples` rather than
	# reading it the instant we arrive.
	# THROW THE FIRST FORTY FRAMES AWAY, and take the MEDIAN of the rest. Both are here because of
	# one concrete failure: with MSAA on, `01_room_iso` read 5.61 ms while `hero SDFGI on` — the
	# exact same camera on the exact same geometry — read 3.32. The culprit is the get_image()
	# readback inside _shoot() just before it. MSAA turns that readback into a resolve plus a full
	# copy, and the pipeline takes tens of frames to come back, not one; the median alone only got
	# 5.61 down to 4.02. At DISCARD 40 the two agree to the digit (3.42 and 3.42), which is how we
	# know the recovery is the whole story and not a real difference between the frames.
	#
	# The cost of being careful here is 70 frames per row — under two seconds for the whole table.
	for i in DISCARD:
		await process_frame
	var t0 := Time.get_ticks_usec()
	var gpu: Array[float] = []
	var cpu := 0.0
	for i in samples:
		await process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var wall := (Time.get_ticks_usec() - t0) / (1000.0 * samples)
	gpu.sort()
	cpu /= samples
	_perf_rows.append("  %-16s %7.2f %7.2f %7.2f %8d %11d %8.1f" % [
		label, gpu[samples / 2], cpu, wall,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
	])


## The hero frame held for a long run. A single 30-frame sample hides shadow-atlas thrash, which
## shows up as a worst-case spike rather than as a mean.
func _perf_stress(frames := 180) -> void:
	var rid := root.get_viewport_rid()
	var all := PackedFloat32Array()
	for i in frames:
		await process_frame
		all.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	all.sort()
	var n := all.size()
	var sum := 0.0
	for v in all:
		sum += v
	_say("")
	_say("  hero stress over %d frames: mean %.2f ms   p95 %.2f ms   worst %.2f ms"
			% [n, sum / n, all[int(n * 0.95)], all[n - 1]])


## SDFGI ON vs OFF on the same frame — the measurement docs/environment-pipeline-todo.md has wanted
## since SDFGI was switched on, and it costs ten lines.
func _perf_sdfgi_ab() -> void:
	if _env == null:
		return
	await _perf("hero SDFGI on")
	_env.sdfgi_enabled = false
	for i in 30:                          # SDFGI needs frames to UN-fit, not just to fit
		await process_frame
	await _perf("hero SDFGI off")
	_env.sdfgi_enabled = true
	for i in 30:
		await process_frame


## OCCLUSION CULLING ON vs OFF, which is a question about a setting the crypt cannot use. The
## project has `use_occlusion_culling = true` and the dungeon contains no OccluderInstance3D at all,
## so what this measures is the cost of running the software occlusion job over an empty occluder
## set. If that is free, the setting stays on for zone_courtyard.tscn, which does author occluders.
func _perf_occlusion_ab() -> void:
	var rid := root.get_viewport_rid()
	await _perf("hero occlusion on")
	RenderingServer.viewport_set_use_occlusion_culling(rid, false)
	for i in SETTLE:
		await process_frame
	await _perf("hero occlusion off")
	RenderingServer.viewport_set_use_occlusion_culling(rid, true)
	for i in SETTLE:
		await process_frame


func _perf_table() -> void:
	_say("")
	_say("=== cost (vsync off; gpu is the MEDIAN of 30 frames after %d discarded, cpu the mean, "
			% DISCARD + "wall the cross-check. Differences under %.2f ms are noise) ===" % PERF_NOISE)
	_say("  %-16s %7s %7s %7s %8s %11s %8s"
			% ["frame", "gpu ms", "cpu ms", "wall ms", "draws", "prims", "vram MB"])
	for r in _perf_rows:
		_say(r)


## WHICH KIT PIECES A DUNGEON ACTUALLY GREW. Adding a variant to a theme's `pieces` is not the same
## as it appearing: the tag has to be planned in the first place (the start room has no cover slots,
## so it shows neither pillar nor brazier however many variants exist), and a `weights` array of the
## wrong length silently drops back to uniform. Counting is the only way to know which of those
## happened, and a screenshot of one room cannot tell you.
func _report_pieces() -> void:
	var census := {}
	for n in _flatten(_zone):
		var nm := str(n.name)
		# Skip Godot's auto-names (@StaticBody3D@417): those are the code greybox and the corridor
		# strips, which are not kit pieces and would bury the census in three hundred entries.
		if nm.begins_with("@"):
			continue
		nm = nm.trim_suffix("2").trim_suffix("3")
		# Course pieces are collider-free and have no wrapper, so their node name comes straight
		# from the Blender object and they are neither StaticBody3D nor named like a mount. The meta
		# is the only thing that identifies them, and counting them is the cheapest possible answer
		# to "did the arcade actually spawn".
		if n is StaticBody3D or nm.begins_with("Candelabra") \
				or n.has_meta(RoomDresser.COURSE_META):
			census[nm] = int(census.get(nm, 0)) + 1
	var keys := census.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s:%d" % [k, census[k]])
	_say("[PIECES] " + ", ".join(parts))


## The DungeonRoom a world point belongs to, by walking up from the nearest piece.
func _room_at(at: Vector3) -> DungeonRoom:
	var best: DungeonRoom = null
	var best_d := INF
	for n in _flatten(_zone):
		if n is DungeonRoom:
			var d: float = (n as Node3D).global_position.distance_to(at)
			if d < best_d:
				best_d = d
				best = n
	return best


## Where the first statue in the dungeon stands, so a frame can be aimed at one. Vector3.INF if the
## layout planned no cover_large slot at all.
func _first_statue() -> Vector3:
	for n in _flatten(_zone):
		if str(n.name).begins_with("Statue") and n is Node3D:
			return (n as Node3D).global_position
	return Vector3.INF


## WHAT THE LIGHTS ACTUALLY ARE, not what the theme asked for. Two separate things can silently
## swallow a theme's Lighting group between authoring and render: a kit scene that hardcodes its own
## OmniLight values (candelabra.tscn did exactly that until `theme_light` was added), and
## DungeonRoom.set_lit() scaling every light in a room by 0.06. Both are invisible in a screenshot
## and both look like "the shader is too dark".
func _report_lights() -> void:
	var by_room := {}
	for n in _flatten(_zone):
		if n is Light3D and not (n is DirectionalLight3D):
			var room := n.get_parent()
			while room != null and not (room is DungeonRoom):
				room = room.get_parent()
			var key: String = room.name if room != null else "(loose)"
			var l := n as Light3D
			# The shadow flag is in the signature because "which lights actually cast" is the single
			# most useful thing this report can answer, and until now it could not answer it at all.
			# The crypt ran ~90 lights with exactly one caster and nothing here said so.
			var sig := "%s%s e%.2f r%.1f a%.2f" % [
				"Spot" if l is SpotLight3D else "Omni",
				"+shadow" if l.shadow_enabled else "",
				l.light_energy, _range_of(l), _atten_of(l)]
			var slot: Dictionary = by_room.get(key, {})
			slot[sig] = int(slot.get(sig, 0)) + 1
			by_room[key] = slot
	var shown := 0
	for k in by_room:
		if shown >= 3:
			break
		_say("[LIGHTS] %-16s %s" % [k, by_room[k]])
		shown += 1


## Range and attenuation under their two different names. Both properties exist on both types and
## mean the same thing; only the prefix differs, which is a Godot wart rather than a distinction.
static func _range_of(l: Light3D) -> float:
	return (l as SpotLight3D).spot_range if l is SpotLight3D else (l as OmniLight3D).omni_range


static func _atten_of(l: Light3D) -> float:
	return (l as SpotLight3D).spot_attenuation if l is SpotLight3D \
			else (l as OmniLight3D).omni_attenuation


## Centre of a room ONE DOOR from the start room, in world space — the unlit half of the leak test.
##
## It has to be a genuine neighbour on two counts. The weak one is that the check means more there:
## a room across the map is trivially dark and proves nothing about whether a torch crosses a wall,
## which is what the number is for. The strong one is that DungeonRoom.show_around() now HIDES
## everything further than one door out, so pointing this camera at an arbitrary room would
## photograph a hidden one, and the leak ratio would come back as a division by black.
func _neighbour_centre() -> Vector3:
	var layout = _zone.get("layout")
	if layout == null or not layout.rooms.has(Vector3i.ZERO):
		return Vector3.INF
	# The edge list is shared by both ends and from_cell is whichever side authored it, so the
	# neighbour is simply the end that is not us.
	for e in layout.rooms[Vector3i.ZERO].edges:
		var far_cell: Vector3i = e.from_cell + e.dir
		var cell: Vector3i = e.from_cell if far_cell == Vector3i.ZERO else far_cell
		if cell == Vector3i.ZERO or cell.y != 0:
			continue                              # keep the two frames on the same floor
		var rd = layout.room_at(cell)
		if rd != null:
			return _zone.position + DungeonLayout.room_origin(rd)
	return Vector3.INF


func _flatten(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_flatten(c))
	return out


## The game's viewing angle: a camera on an arc at PITCH above the target, `yaw` around it.
func _orbit(at: Vector3, dist: float, yaw: float) -> void:
	var off := Vector3(0.0, sin(PITCH), cos(PITCH)).rotated(Vector3.UP, yaw) * dist
	_look(at + off, at, FOV)


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.position = from
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.fov = fov


var _first := true

func _shoot(shot_name: String) -> Image:
	# Full warm-up once (noise textures, SDFGI cascades), a short settle after every camera move.
	for i in (WARMUP if _first else SETTLE):
		await process_frame
	_first = false
	var img := root.get_texture().get_image()
	var path := _out + shot_name + ".png"
	var err := img.save_png(path)
	_say("[SHOT] %-16s %s  %s" % [shot_name, "ok" if err == OK else "FAILED",
			ProjectSettings.globalize_path(path)])
	return img


func _verdict(label: String, value: float, ok: bool, target: String) -> void:
	_say("  %-28s %8.4f   %-10s %s" % [label, value, target, "PASS" if ok else "**FAIL**"])


func _say(s: String) -> void:
	print(s)
	_report.append(s)


func _write_report() -> void:
	var fa := FileAccess.open(_out + "lookdev.txt", FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_report))
		fa.close()

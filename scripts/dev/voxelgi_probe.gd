extends SceneTree
## THE GO/NO-GO FOR VOXELGI IN THE CRYPT. It answered NO. This is the evidence, kept runnable.
##
##   Godot_console.exe --path . --script res://scripts/dev/voxelgi_probe.gd
##
## THE ANSWER, measured on an RTX 3070 over the seed-42 start room:
##
##   subdiv  64: 1103 ms per room   (x10 rooms = 11.0 s)
##   subdiv 128: 1548 ms per room   (x10 rooms = 15.5 s)
##   subdiv 256: 3186 ms per room   (x10 rooms = 31.9 s)
##   VRAM after ONE baked room: 649 -> 1135 MB
##
## Eleven seconds of hard freeze at the coarsest setting there is, for a dungeon that is assembled
## from a seed inside _ready() — so every one of those seconds lands inside World.go_to's add_child.
## And note the shape of the curve: 64 to 128 doubles the cells in every axis and costs only 40%
## more, which says the bake is dominated by walking the GEOMETRY, not by voxel resolution. The
## crypt room is ~350 k primitives of chunky modelled brick. There is no subdiv setting that escapes
## that, so there is no version of this that is cheap.
##
## Weighed against what it would buy: SDFGI is already running, already gives a warm bounce, needs
## no bake at all, and costs 1.6 ms a frame. VoxelGI would add a second indirect term on top of a
## scene that (see docs, "the ambient floor") is already 67% indirect. Declining it is not a
## compromise here — it is the same conclusion the numbers point at from three directions.
##
## THE QUESTION THE PLAN ACTUALLY ASKED could not be answered, and that is worth writing down too.
## Godot's voxeliser reads albedo by casting a material to StandardMaterial3D, and every piece of
## crypt stone wears a ShaderMaterial that computes albedo in fragment() — nothing for the cast to
## find. The plan's test was to bake with `create_visual_debug = true` and read the debug MultiMesh,
## whose cubes are documented as carrying each cell's baked albedo. In 4.6.3 they do not: every
## instance colour comes back pure black, INCLUDING for a control box wearing a plain red
## StandardMaterial3D placed in the room for exactly this purpose. The control is why this script
## reports "cannot tell" rather than "bakes black" — a reader that returns black for a known-red
## input is not measuring albedo, and the honest output of a broken instrument is no answer at all.
##
## (SDFGI is unaffected by the ShaderMaterial question either way, which is not a contradiction: it
## voxelises by RENDERING the geometry with its real material, so it sees the shader's output. That
## is why the crypt's existing bounce is warm.)
##
## MUST RUN WITHOUT --headless: the dummy renderer bakes nothing.

const ZONE := "res://scenes/world/zone_crypt.tscn"
const MAIN := "res://scenes/main.tscn"
const SEED := 42

## Where the verdict lands. Both bounds are two-sided on purpose — the failure this exists to catch
## (white) and the success (warm stone) are both "a colour", and only a range tells them apart.
const WHITE_LUM := 0.70          ## above this, with no saturation, the bake is white
const FLAT_SAT := 0.05
const STONE_LUM := Vector2(0.10, 0.50)
const STONE_HUE := Vector2(15.0, 45.0)   ## degrees; the kit's amber-brown stone

var _world: Node3D
var _zone: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_world = Node3D.new()
	root.add_child(_world)

	var main := (load(MAIN) as PackedScene).instantiate()
	for n in _flatten(main):
		if n is WorldEnvironment:
			var we := WorldEnvironment.new()
			we.environment = (n as WorldEnvironment).environment.duplicate(true)
			we.add_to_group("world_env")
			_world.add_child(we)
			break
	main.free()

	_zone = (load(ZONE) as PackedScene).instantiate() as Node3D
	_zone.set("dungeon_seed", SEED)
	_world.add_child(_zone)
	await process_frame

	var room: Node3D = null
	for n in _flatten(_zone):
		if n is DungeonRoom:
			room = n as Node3D
			break
	if room == null:
		print("[VGI] no DungeonRoom found — the generator did not run")
		quit(1)
		return
	print("[VGI] baking over %s at %s" % [room.name, room.global_position])

	var vgi := VoxelGI.new()
	# Room plus its walls. Larger spills into the corridor and wastes cells on the void; smaller
	# fails to voxelise the walls themselves, which are the occluders the whole thing depends on.
	vgi.size = Vector3(21.5, 8.0, 13.5)
	vgi.subdiv = VoxelGI.SUBDIV_128
	_world.add_child(vgi)
	vgi.global_position = room.global_position + Vector3(0.0, 3.4, 0.0)

	# A CONTROL, because "everything baked black" has two explanations and only one of them is about
	# the shader. Either the voxeliser genuinely reads black off a ShaderMaterial, or this script is
	# reading the debug mesh wrong. A box wearing a plain StandardMaterial3D in a colour nothing in
	# the crypt is tells the two apart: if the control bakes red, the reader works and the stone
	# really is black; if the control bakes black too, the fault is here.
	var control := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	control.mesh = box
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.05, 0.05)
	control.material_override = red
	control.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	room.add_child(control)
	control.position = Vector3(0.0, 1.0, 0.0)
	await process_frame

	# BAKE TIME PER SUBDIVISION, which turns out to be the number that decides this phase. The
	# dungeon is generated from a seed in _ready(), so every one of these seconds is a freeze inside
	# World.go_to's add_child, multiplied by however many rooms get baked.
	for sd in [VoxelGI.SUBDIV_64, VoxelGI.SUBDIV_128, VoxelGI.SUBDIV_256]:
		vgi.subdiv = sd
		var t := Time.get_ticks_msec()
		vgi.bake(room, false)
		await process_frame
		print("[VGI] subdiv %s: bake %d ms  (x10 rooms = %.1f s)" % [
				["64", "128", "256"][[VoxelGI.SUBDIV_64, VoxelGI.SUBDIV_128,
				VoxelGI.SUBDIV_256].find(sd)],
				Time.get_ticks_msec() - t, (Time.get_ticks_msec() - t) * 10.0 / 1000.0])

	vgi.subdiv = VoxelGI.SUBDIV_128
	var t0 := Time.get_ticks_msec()
	vgi.bake(room, true)
	var ms := Time.get_ticks_msec() - t0
	await process_frame

	var mm := _find_multimesh(vgi)
	if mm == null:
		print("[VGI] bake produced no debug MultiMesh. VoxelGI cannot be probed this way; treat "
				+ "the phase as blocked rather than assuming either answer.")
		quit(1)
		return

	# Mean albedo over every solid cell, plus the hue as a unit-vector mean — averaging degrees
	# directly is wrong across the 0/360 wrap, and amber sits close enough to it to matter.
	var n := mm.instance_count
	# A MultiMesh with use_colors off returns black for every instance, which is indistinguishable
	# from a bake that really did read black. Say which one this is before reading a single colour.
	print("[VGI] debug mesh: use_colors=%s use_custom_data=%s" % [mm.use_colors, mm.use_custom_data])
	if not mm.use_colors:
		var mat: Variant = _debug_material(vgi)
		print("[VGI] no per-instance colours on the debug mesh — its albedo is in the material "
				+ "instead: %s" % mat)
		quit(1)
		return
	var lum := 0.0
	var sat := 0.0
	var hx := 0.0
	var hy := 0.0
	var reddish := 0
	var nonblack := 0
	for i in n:
		var c := mm.get_instance_color(i)
		lum += c.get_luminance()
		sat += c.s
		hx += cos(c.h * TAU) * c.s
		hy += sin(c.h * TAU) * c.s
		if c.get_luminance() > 0.01:
			nonblack += 1
		if c.r > 0.4 and c.g < 0.2 and c.b < 0.2:
			reddish += 1
	print("[VGI] control: %d cells read red out of %d non-black (of %d total)"
			% [reddish, nonblack, n])
	lum /= maxf(n, 1)
	sat /= maxf(n, 1)
	var hue := fmod(rad_to_deg(atan2(hy, hx)) + 360.0, 360.0)

	print("[VGI] bake %d ms, %d solid cells" % [ms, n])
	print("[VGI] mean baked albedo: luminance %.4f  saturation %.4f  hue %.1f deg" % [lum, sat, hue])
	print("[VGI] vram after bake: %.1f MB" % (RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0))

	if reddish == 0 and nonblack == 0:
		# The control is the whole point. A red box read as black means the instrument is broken,
		# not that the scene is black, and a broken instrument must not be allowed to produce a
		# verdict — that is how you end up implementing a workaround for a problem you invented.
		print("[VGI] ALBEDO READOUT UNUSABLE: the known-red control box also baked black, so the "
				+ "debug MultiMesh is not carrying albedo in this build. No verdict from this test.")
	elif lum > WHITE_LUM and sat < FLAT_SAT:
		print("[VGI] the voxeliser fell back to WHITE — a ShaderMaterial gives it nothing to read. "
				+ "Bake through a StandardMaterial3D proxy on material_override.")
	elif lum >= STONE_LUM.x and lum <= STONE_LUM.y and hue >= STONE_HUE.x and hue <= STONE_HUE.y:
		print("[VGI] the real stone albedo came through; a direct bake would be correct.")
	else:
		print("[VGI] something else is being read; do not proceed on a guess.")
	print("[VGI] VERDICT: NO. Not on the albedo question, which is untestable here — on bake time. "
			+ "11 s of freeze for a bounce SDFGI already provides for 1.6 ms and no load cost.")
	quit(0)


func _debug_material(n: Node) -> Variant:
	if n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		if mmi.material_override != null:
			return mmi.material_override
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			return mmi.multimesh.mesh.surface_get_material(0)
	for c in n.get_children():
		var m: Variant = _debug_material(c)
		if m != null:
			return m
	return null


func _find_multimesh(n: Node) -> MultiMesh:
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		return (n as MultiMeshInstance3D).multimesh
	for c in n.get_children():
		var m := _find_multimesh(c)
		if m != null:
			return m
	return null


func _flatten(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_flatten(c))
	return out

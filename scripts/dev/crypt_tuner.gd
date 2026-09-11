extends Node3D
## The crypt's tuning bench: a real dungeon, playable, with every knob that decides how it looks
## exposed as a live control.
##
##   Godot_v4.6.3-stable_win64_console.exe --path . res://scenes/dev/crypt_tuner.tscn
##
## WHY THIS EXISTS ALONGSIDE scripts/dev/crypt_lookdev.gd. That one is the HEADLESS rig: fourteen
## two-sided checks, a cost table, exit code. It answers "is this allowed to ship". It cannot answer
## "what should I change", because every question costs a three-minute round trip and comes back as
## a number rather than a picture. The four defects found in the last session — a black disc under
## every flame, a lid of daylit cloud below the floor, pebbles that cast no contact shadow, a fog
## density that needed two corrections downward — were every one of them spotted by eye in a
## screenshot, and not one of them was caught by a check. This is the other half of that pair.
##
## FLY with RMB + WASD. TAB drops into WALK, which uses the GAME's Player and CameraRig — a free
## camera flatters everything, and the pinned ~53 degrees is the only angle a player ever sees.
##
## WHAT IS LIVE AND WHAT NEEDS A REBUILD, because getting this wrong means dragging a slider that
## does nothing and concluding the value does not matter:
##
##   live      shader uniforms, Environment, any property of an existing light, the post stack
##   rebuild   DungeonTheme values — RoomDresser._light and Kit.dress read them ONCE at build time
##
## Nothing here is imported by the game. It reads the same resources the game reads, which is the
## point: `crypt.tres` and `crypt_stone.tres` are `load()`ed and therefore CACHED AND SHARED, so
## moving a slider mutates the very object every brick in the dungeon is already using. That is what
## makes the tuning instant, and it is also why an unsaved session is lost on quit.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")

const MAIN := "res://scenes/main.tscn"
const ZONE := "res://scenes/world/zone_crypt.tscn"
const THEME_PATH := "res://scenes/dungeon/themes/crypt.tres"
const STONE_PATH := "res://assets/materials/crypt_stone.tres"

## Small on purpose. The full crypt is nine rooms and show_around() only ever draws three of them,
## so a bigger number costs build time and buys nothing you can see — but it must stay above two or
## there are no transitions to exercise, and transitions are where the bugs have been.
const ROOMS := 4

@onready var _sun: DirectionalLight3D = $Sun
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _subject: Node3D = $Subject

var _zone: Node3D
var _theme: DungeonTheme
var _stone: ShaderMaterial
var _env: Environment
var _seed := 42
var _walking := false
var _mode_button: Button
var _status: Label

## Everything moved this session, as "target|key" -> {"old": Variant, "new": Variant}. The save pass
## turns this into a diff; `old` is captured on the FIRST touch of a key so dragging a slider back
## and forth still reports the true starting value.
var _changes := {}


func _ready() -> void:
	_stage_env()
	_theme = load(THEME_PATH) as DungeonTheme
	_stone = load(STONE_PATH) as ShaderMaterial
	_build_zone()
	_build_ui()
	_set_mode(false)
	# The viewport's own GPU timer, same instrument the headless rig uses. NOTE this bench runs
	# windowed with vsync on, so the WALL clock is pinned at 16.67 ms and only the gpu figure means
	# anything here — the headless rig is still the place cost decisions get made.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_scan()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--selftest"):
			_selftest(a.substr(11) if a.length() > 11 else "")
			break


## A SMOKE TEST FOR THE BENCH ITSELF, because an interactive scene is otherwise unverifiable from a
## terminal: it never exits, so `timeout` kills it and takes every buffered print with it — which is
## exactly how the first run of this file came back with an empty log and no way to tell whether it
## had worked or crashed in _ready.
##
##   … res://scenes/dev/crypt_tuner.tscn -- --selftest=/some/dir
##
## Builds everything, waits for the noise textures to generate on their worker thread, writes a
## screenshot and a census, and quits non-zero if anything came up empty.
func _selftest(out_dir: String) -> void:
	for i in 100:
		await get_tree().process_frame
	var fails: Array[String] = []
	var lights := 0
	var rooms := 0
	var stone := 0
	for n in _flatten(_zone):
		if n is DungeonRoom:
			rooms += 1
		elif n is Light3D:
			lights += 1
		elif n is MeshInstance3D and (n as MeshInstance3D).material_override == _stone:
			stone += 1
	var panel_rows := _count_controls(self)
	print("[SELFTEST] rooms=%d lights=%d stone_meshes=%d panel_rows=%d changes=%d"
			% [rooms, lights, stone, panel_rows, _changes.size()])
	print("[SELFTEST] env=%s theme=%s stone_mat=%s" % [_env != null, _theme != null, _stone != null])
	if rooms < 2:
		fails.append("fewer than 2 rooms built — no transitions to exercise")
	if lights < 5:
		fails.append("only %d lights" % lights)
	if stone < 10:
		fails.append("only %d meshes wear the stone material" % stone)
	if panel_rows < 100:
		fails.append("panel built only %d controls — introspection is not finding properties"
				% panel_rows)
	fails.append_array(_selftest_patch())
	fails.append_array(await _selftest_gizmo())
	fails.append_array(await _selftest_fly_lighting())
	fails.append_array(await _selftest_walk())
	if out_dir != "":
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(out_dir.rstrip("/\\") + "/tuner.png")
		print("[SELFTEST] screenshot %s" % ("ok" if err == OK else error_string(err)))
	for f in fails:
		print("[SELFTEST] FAIL: %s" % f)
	print("[SELFTEST] %s" % ("PASS" if fails.is_empty() else "FAIL"))
	get_tree().quit(0 if fails.is_empty() else 1)


## THE COMMENT-PRESERVATION TEST, run against a COPY of crypt.tres so a smoke test can never damage
## the file it is protecting. Patches one existing key and one key that does not exist yet, then
## checks the value landed, the appended key landed, and a distinctive comment line survived.
func _selftest_patch() -> Array[String]:
	var fails: Array[String] = []
	var src := FileAccess.get_file_as_string(THEME_PATH)
	var tmp := "user://_tuner_patch_test.tres"
	var w := FileAccess.open(tmp, FileAccess.WRITE)
	if w == null:
		return ["could not open %s for the patch test" % tmp]
	w.store_string(src)
	w.close()

	var res := _patch_tres(tmp, {"light_energy": 4.25, "shader_parameter/not_in_file": 0.5})
	var after := FileAccess.get_file_as_string(tmp)
	print("[SELFTEST] patch written=%s appended=%s" % [res["written"], res["appended"]])
	if not after.contains("light_energy = 4.25"):
		fails.append("patch did not replace light_energy")
	if not after.contains("shader_parameter/not_in_file = 0.5"):
		fails.append("patch did not append a missing key")
	# The whole reason this is a text patch and not ResourceSaver.
	for marker in ["KEEP THIS THE SAME LENGTH", "LEFT AT 1.0 BECAUSE IT IS INERT",
			"PUSHED OUT FROM 22"]:
		if not after.contains(marker):
			fails.append("patch destroyed the comment '%s'" % marker)
	if src.split("\n").size() + 1 != after.split("\n").size():
		fails.append("patch changed the line count by more than the one appended line")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	return fails


## The gizmo and picking, exercised without simulating input: put the camera where a known light is
## visible, ask the picker for that light's own screen position, and check it comes back.
func _selftest_gizmo() -> Array[String]:
	var fails: Array[String] = []
	if _gizmo == null:
		return ["no gizmo was created"]
	if _gizmo.get_child_count() != 3:
		fails.append("gizmo has %d arrows, expected 3" % _gizmo.get_child_count())
	var marked := 0
	for l in _lights:
		if l.get_node_or_null("TunerMarker") != null:
			marked += 1
	if marked != _lights.size():
		fails.append("%d of %d lights have a marker" % [marked, _lights.size()])
	if not _gizmo.get("visible"):
		fails.append("gizmo did not attach to the initially selected light")

	# Aim the fly camera at a light, then pick at exactly its projected position.
	var cam := get_viewport().get_camera_3d()
	var target: Light3D = null
	for l in _lights:
		if l.name == "RoomFill":
			target = l
			break
	if cam == null or target == null:
		return fails
	cam.global_position = target.global_position + Vector3(0.0, 2.0, 7.0)
	cam.look_at(target.global_position, Vector3.UP)
	await get_tree().process_frame
	var at := cam.unproject_position(target.global_position)
	var got := _pick_light(at)
	var sel := _light_list.get_selected_id()
	if not got or sel < 0 or _lights[sel] != target:
		fails.append("picking at a light's own screen position did not select it")
	else:
		# And the readout the gizmo exists to move: RoomFill sits at 5.5 m, which should give a
		# floor N.L near 0.81 at 4 m — if this prints something wildly different the height maths
		# or the room-floor lookup is wrong.
		_update_geometry(target)
		print("[SELFTEST] geometry: %s" % _geometry.text)
	# EACH ARROW MUST POINT DOWN THE AXIS IT DRAGS. The first version built the rotations by adding
	# euler angles, which is not composing rotations: X and Z came out pointing at -X and -Z while
	# the drag maths used +X and +Z, so the gizmo looked plausible and dragged backwards. Comparing
	# the rendered tip against the axis is the check that would have caught it in one run.
	await get_tree().process_frame
	var g := _gizmo as Node3D
	var axes: Array = GizmoScript.AXES
	for i in g.get_child_count():
		var a3 := g.get_child(i) as Node3D
		var tip: Vector3 = a3.to_global(Vector3(0.0, 1.0, 0.0)) - g.global_position
		var want: Vector3 = axes[i]
		if tip.normalized().dot(want) < 0.99:
			fails.append("gizmo arrow %d points %s, expected %s"
					% [i, tip.normalized(), want])
	print("[SELFTEST] gizmo at %s scale %.2f arrows=%d target=%s" % [g.global_position,
			g.scale.x, g.get_child_count(), (g.get("target") as Node).name])
	return fails


## Fly into a second room and check it actually lights, and the first one stops being lit. This is
## the whole of bug 1b: without it you fly through whatever state the generator froze at build time.
func _selftest_fly_lighting() -> Array[String]:
	var fails: Array[String] = []
	var rooms: Array[Node] = []
	for n in _zone.get_children():
		if n is DungeonRoom:
			rooms.append(n)
	if rooms.size() < 2:
		return ["only %d rooms — cannot test a transition" % rooms.size()]
	var a := rooms[0] as DungeonRoom
	var b := rooms[1] as DungeonRoom
	var cam := get_viewport().get_camera_3d()
	for target in [a, b]:
		cam.global_position = (target as Node3D).global_position + Vector3(0.0, 6.0, 0.0)
		for i in 8:
			await get_tree().process_frame
	# set_lit fades over 0.5 s, so give the tween time before reading energies.
	await _wait_frames(45)
	var ea := _fill_energy(a)
	var eb := _fill_energy(b)
	print("[SELFTEST] fly lighting: %s fill %.2f, %s fill %.2f (camera is in %s)"
			% [a.name, ea, b.name, eb, b.name])
	if eb <= ea:
		fails.append("flew into %s but its fill (%.2f) is not above %s's (%.2f)"
				% [b.name, eb, a.name, ea])
	if not b.visible:
		fails.append("%s is not even visible after flying into it" % b.name)
	return fails


func _fill_energy(room: Node) -> float:
	for n in _flatten(room):
		if n is Light3D and (n as Node3D).name == "RoomFill":
			return (n as Light3D).light_energy
	return -1.0


## TAB into WALK must not show a black screen — the failure that started this. Checks the rig
## actually reached the player AND that the resulting frame has something in it, because a rig in
## the right place pointed at nothing would pass the first test alone.
func _selftest_walk() -> Array[String]:
	var fails: Array[String] = []
	var player := get_node_or_null("Player") as Node3D
	var rig := get_node_or_null("CameraRig") as Node3D
	if player == null or rig == null:
		return ["Player or CameraRig missing"]
	_set_mode(true)
	await _wait_frames(40)
	var gap := rig.global_position.distance_to(player.global_position)
	# The right 55% of the frame, clear of the tuning panel.
	var img := get_viewport().get_texture().get_image()
	var lum := _mean_luma(img, Rect2(0.45, 0.1, 0.5, 0.8))
	print("[SELFTEST] walk: rig %.2f m from player, frame mean luminance %.4f" % [gap, lum])
	if gap > 4.0:
		fails.append("rig is %.1f m from the player — target_path is not resolving" % gap)
	if lum < 0.01:
		fails.append("walk-mode frame is black (mean %.4f)" % lum)
	_set_mode(false)
	await _wait_frames(5)
	return fails


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _mean_luma(img: Image, r: Rect2) -> float:
	var x0 := int(r.position.x * img.get_width())
	var y0 := int(r.position.y * img.get_height())
	var x1 := mini(int((r.position.x + r.size.x) * img.get_width()), img.get_width())
	var y1 := mini(int((r.position.y + r.size.y) * img.get_height()), img.get_height())
	var s := 0.0
	var n := 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			s += img.get_pixel(x, y).get_luminance()
			n += 1
	return s / maxf(n, 1)


func _count_controls(n: Node) -> int:
	var c := 1 if (n is HSlider or n is ColorPickerButton or n is CheckBox or n is SpinBox
			or n is OptionButton) else 0
	for k in n.get_children():
		c += _count_controls(k)
	return c


# ---------------------------------------------------------------- staging -------------------


## Lift the game's own environment rather than authoring one here. A bench with its own hand-written
## Environment photographs a look the game never shows, which is the drift docs/anime-look-todo.md
## A3 is a post-mortem about.
func _stage_env() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	var src: Environment = null
	for n in _flatten(main):
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			src = (n as WorldEnvironment).environment
			break
	# duplicate(true) is not optional: DungeonEnv MUTATES whatever environment it is given, and
	# main.tscn's is a shared cached sub-resource. Without the copy this bench leaves a blacked-out
	# environment in the resource cache for every other scene in the editor.
	_env = src.duplicate(true) if src != null else Environment.new()
	_world_env.environment = _env
	main.free()


## Build (or rebuild) the dungeon. Free-then-await-then-add, and the ordering is load-bearing:
## DungeonGenerator._dim_world's re-entrancy guard protects ONE generator from applying twice, not
## TWO generators from overlapping. If a second zone's _ready runs before the first zone's
## _exit_tree, the newcomer snapshots the already-blacked-out environment and will later "restore"
## the crypt's void onto the daylit hub.
func _rebuild() -> void:
	if _zone != null and is_instance_valid(_zone):
		# The rooms hold the CameraRig's frame; freeing them without releasing leaves the rig
		# pointing at a dead node, because release_frame only ever fires from body_exited.
		var rig := get_node_or_null("CameraRig")
		if rig != null and rig.has_method("release_frame"):
			for n in _flatten(_zone):
				if n is DungeonRoom:
					rig.call("release_frame", n)
		_subject.remove_child(_zone)
		_zone.queue_free()
		_zone = null
		_last_room = null           # the room it pointed at is about to stop existing
		await get_tree().process_frame
	_build_zone()


func _build_zone() -> void:
	_zone = (load(ZONE) as PackedScene).instantiate() as Node3D
	_zone.set("dungeon_seed", _seed)
	_zone.set("room_count", ROOMS)
	_subject.add_child(_zone)
	# The zone parks itself at (500, 0, 500) in its own _ready, so the player and the camera have to
	# follow it there — otherwise you start 700 m away looking at the inside of the fog, which is
	# exactly how the first version of the headless rig failed.
	var player := get_node_or_null("Player") as Node3D
	if player != null:
		var marker := _find_spawn(_zone)
		player.global_position = marker + Vector3(0.0, 0.2, 0.0)
	var fly := get_node_or_null("FlyCam") as Camera3D
	if fly != null:
		# The game's own angle and distance (CameraRig's 15.6 m offset x room_zoom 1.15), nudged
		# right so the panel does not cover the room. Opening on the framing the player actually
		# gets is the whole reason this is not a free-orbit bench.
		var at: Vector3 = _zone.position + Vector3(3.0, 1.0, 0.0)
		fly.global_position = at + Vector3(0.0, 12.5, 9.375) * 1.15
		fly.look_at(at, Vector3.UP)
	_refresh_lights()               # no-op on the first build; the rebuild button needs it
	_note("built seed %d, %d rooms" % [_seed, ROOMS])


func _find_spawn(zone: Node) -> Vector3:
	for n in _flatten(zone):
		if n is Marker3D and n.name == "SpawnA":
			return (n as Node3D).global_position
	return (zone as Node3D).position


# ---------------------------------------------------------------- the panel -----------------


func _build_ui() -> void:
	# Sized to the window rather than to a constant: the project authors no [display] section, so
	# the game runs at Godot's default 1152x648 and a hardcoded 760-tall panel hangs off the bottom
	# with its last rows unreachable.
	var vh := get_viewport().get_visible_rect().size.y
	var box := Tuning.build_panel(self, 320, int(maxf(vh - 40.0, 300.0)))

	_status = Tuning.line(box, "", Color(0.55, 0.95, 0.6))
	_perf_line = Tuning.line(box, "", Color(0.7, 0.8, 1.0))
	_mode_button = Tuning.button(box, "Switch to WALK  (Tab)", func() -> void:
		_set_mode(not _walking)
		_refresh_mode_button())

	Tuning.header(box, "DUNGEON")
	Tuning.number(box, "seed", float(_seed), 1.0, func(v: float) -> void: _seed = int(v))
	Tuning.button(box, "Rebuild", func() -> void: _rebuild())
	Tuning.check(box, "light the room I fly into", _fly_lights, func(on: bool) -> void:
		_fly_lights = on
		_last_room = null)

	Tuning.header(box, "POST  (both ship OFF today)")
	_post_toggle(box, "Kuwahara  (layer 9)", "KuwaharaFilter")
	_post_toggle(box, "PainterlyGrade  (layer 10)", "PainterlyGrade")
	_post_uniforms(box, "KuwaharaFilter")
	_post_uniforms(box, "PainterlyGrade")

	Tuning.header(box, "STONE SHADER")
	var rows := Tuning.from_shader(box, _stone, func(nm: String, v: Variant) -> void:
		_record(STONE_PATH, "shader_parameter/" + nm, v, func() -> Variant:
			return RenderingServer.shader_get_parameter_default(_stone.shader.get_rid(), nm)))
	_note("%d shader rows" % rows)

	Tuning.header(box, "ENVIRONMENT")
	# The property list comes from DungeonEnv's own tables, so this panel cannot drift from the set
	# of things the crypt override actually touches.
	var env_keys: Array = DungeonEnv.FIXED_ENV.keys() + DungeonEnv.THEMED_ENV.keys()
	Tuning.from_object(box, _env, env_keys, func(nm: String, v: Variant) -> void:
		_record("dungeon_env.gd", nm, v, func() -> Variant: return _env.get(nm)))

	Tuning.header(box, "THEME  (needs Rebuild)")
	Tuning.from_object(box, _theme, [], func(nm: String, v: Variant) -> void:
		_record(THEME_PATH, nm, v, func() -> Variant: return _theme.get(nm)))

	_build_lights_panel(box)

	Tuning.header(box, "GI")
	Tuning.check(box, "SDFGI", _env.sdfgi_enabled,
			func(on: bool) -> void: _env.sdfgi_enabled = on)
	Tuning.button(box, "Bake VoxelGI over this room", _bake_voxel_gi)
	Tuning.check(box, "VoxelGI visible", false, func(on: bool) -> void:
		if _vgi != null:
			_vgi.visible = on)

	Tuning.header(box, "DIAGNOSTICS")
	Tuning.button(box, "Re-scan for errors", func() -> void: _scan())
	_diag = Tuning.log_pane(box, 190)

	Tuning.header(box, "SAVE")
	Tuning.button(box, "Write changes + diff", _save)
	_save_log = Tuning.log_pane(box, 130)


# ---------------------------------------------------------------- GI ------------------------


var _vgi: VoxelGI


## VoxelGI was rejected for shipping on bake time — scripts/dev/voxelgi_probe.gd measured 1.1 s per
## room at the COARSEST subdiv, so eleven seconds of hard freeze for a ten-room crypt generated
## inside _ready. None of that matters on a bench where you bake once and look at it, and the
## comparison against SDFGI is worth having by eye rather than by argument.
func _bake_voxel_gi() -> void:
	var host := _room_at(_player_or_cam())
	if host == null:
		_note("no room to bake")
		return
	if _vgi != null and is_instance_valid(_vgi):
		_vgi.queue_free()
	_vgi = VoxelGI.new()
	# Room plus its walls. Larger spills into the corridor and wastes cells on the void; smaller
	# fails to voxelise the walls, which are the occluders the whole thing depends on.
	_vgi.size = Vector3(21.5, 8.0, 13.5)
	_vgi.subdiv = VoxelGI.SUBDIV_128
	add_child(_vgi)
	_vgi.global_position = host.global_position + Vector3(0.0, 3.4, 0.0)
	var before := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var t0 := Time.get_ticks_msec()
	_vgi.bake(host, false)
	var ms := Time.get_ticks_msec() - t0
	var after := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	_note("VoxelGI %s baked in %d ms, +%.0f MB" % [host.name, ms, (after - before) / 1048576.0])


func _player_or_cam() -> Vector3:
	var n := get_node_or_null("Player" if _walking else "FlyCam") as Node3D
	return n.global_position if n != null else Vector3.ZERO


# ---------------------------------------------------------------- diagnostics ---------------
#
# THE "FIND ERRORS" HALF, and every check below is a defect this project has actually shipped.
# None of them would fail a lookdev check — they are all things that look plausible in a number and
# wrong in a picture, which is exactly the gap this bench exists to close.


var _diag: RichTextLabel
var _perf_line: Label


func _scan() -> void:
	var warn: Array[String] = []
	var casters := 0
	var flames := 0
	if _zone == null or not is_instance_valid(_zone):
		return

	# ONLY THE ROOM YOU ARE LOOKING AT. Every other room is held dark by set_lit, which turns its
	# casting OFF — so scanning them all reports "no shadow-casting light" for eight rooms out of
	# nine, which is correct behaviour and a useless warning. The verify suite hit exactly this and
	# solved it by lighting every room first; a bench cannot, because that would change what you
	# are looking at.
	var here := _room_at(_player_or_cam())
	if here != null:
		var room_casters := 0
		for n in _flatten(here):
			if n is Light3D and (n as Light3D).shadow_enabled:
				room_casters += 1
		if room_casters == 0:
			warn.append("%s (the room you are in) has no shadow-casting light" % here.name)

	for n in _flatten(_zone):
		if n is Light3D and not (n is DirectionalLight3D):
			var l := n as Light3D
			if l.shadow_enabled:
				casters += 1
				# THE BLACK-DISC BUG. A caster inside its own fixture projects that fixture onto the
				# floor, magnified by the ratio of the distances — a 5.5 cm flame box 6 cm under a
				# light 1.55 m up threw a 1.4 m black disc through the brightest pool in the room.
				var host := l.get_parent()
				if host != null:
					for sib in host.get_children():
						if sib is GeometryInstance3D and sib != l \
								and (sib as GeometryInstance3D).cast_shadow \
										!= GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
							var mi := sib as VisualInstance3D
							var box := mi.global_transform * mi.get_aabb()
							if box.has_point(l.global_position):
								warn.append("%s/%s is INSIDE caster %s — expect a black disc"
										% [host.name, l.name, sib.name])
				if _room_of(l) == null:
					warn.append("%s casts but is outside any DungeonRoom — set_lit cannot reach it"
							% l.name)
		elif n is GeometryInstance3D:
			var g := n as GeometryInstance3D
			if n.has_meta("torch_flame"):
				flames += 1
				if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					warn.append("flame %s still casts shadows" % n.name)
			if n is MeshInstance3D:
				var mi2 := n as MeshInstance3D
				if mi2.material_override == _stone and mi2.mesh != null \
						and mi2.mesh.get_surface_count() > 0:
					var arr: Array = mi2.mesh.surface_get_arrays(0)
					if arr.size() > Mesh.ARRAY_COLOR and arr[Mesh.ARRAY_COLOR] == null:
						# Named by parent and mesh class, because these are auto-named nodes and
						# "@MeshInstance3D@187" tells you nothing you can act on.
						var par := n.get_parent()
						warn.append("%s/%s (%s) wears the stone shader with no COLOR_0 — the "
								% [par.name if par != null else "?", n.name,
								mi2.mesh.get_class()]
								+ "palette remap reads white and renders it flat stone_light")

	for id: String in _changes:
		var v: Variant = (_changes[id] as Dictionary)["new"]
		if v is float and (is_nan(v as float) or is_inf(v as float)):
			warn.append("%s is NaN/inf" % id)

	var head := "[color=#8f8]%d casters, %d flames, %d lights[/color]" % [
			casters, flames, _lights.size()]
	if warn.is_empty():
		_diag.text = head + "\n[color=#8f8]no warnings[/color]"
	else:
		_diag.text = head + "\n[color=#f88]" + "\n".join(warn) + "[/color]"
	print("[TUNER] scan: %d casters, %d warnings" % [casters, warn.size()])
	for w in warn:
		print("   ! %s" % w)


func _room_of(n: Node) -> Node:
	var p := n.get_parent()
	while p != null:
		if p is DungeonRoom:
			return p
		p = p.get_parent()
	return null


# ---------------------------------------------------------------- saving --------------------
#
# NOT ResourceSaver, and this is the one place the bench deliberately departs from the pattern it
# otherwise copies. whinbek_lookdev.gd:203 saves its material with ResourceSaver.save() and that is
# right for a file whose only content is values. It is wrong here: ResourceSaver reserialises a
# .tres from the in-memory resource, and every COMMENT in the file is lost. crypt.tres currently
# carries about sixty lines of measured findings — the fog_begin distance table, the note that
# ambient_factor is inert because SDFGI supersedes constant ambient, the fill_energy diagnosis, the
# warning that `weights` must stay the same length as `pieces` — and crypt_stone.tres carries
# twenty more. Those comments cost more to rediscover than the numbers they annotate.
#
# So: read the file as text, rewrite only the lines whose key changed, leave everything else byte
# for byte. Values are serialised with var_to_str(), whose output IS .tres literal syntax —
# Color(1, 0.85, 0.68, 1), 9.5, true — so there is no formatter to get subtly wrong.
#
# Two categories cannot be written at all and are reported instead:
#   * Environment values live in DungeonEnv.FIXED_ENV / THEMED_ENV, `const` dictionaries in code.
#   * Light values live in kit .tscn files and in RoomDresser._fill.

var _save_log: RichTextLabel


func _save() -> void:
	if _changes.is_empty():
		_write_log("[color=#aaa]nothing changed[/color]")
		return
	var by_target := {}
	for id: String in _changes:
		var c: Dictionary = _changes[id]
		var t: String = c["target"]
		if not by_target.has(t):
			by_target[t] = []
		(by_target[t] as Array).append(c)

	var report: Array[String] = []
	var shown: Array[String] = []
	report.append("crypt tuning session %s" % Time.get_datetime_string_from_system())
	for target: String in by_target:
		var rows: Array = by_target[target]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"])
		report.append("")
		if target == THEME_PATH or target == STONE_PATH:
			var values := {}
			for c: Dictionary in rows:
				values[c["key"]] = c["new"]
			var res := _patch_tres(target, values)
			report.append("--- %s  (WRITTEN)" % target)
			for c: Dictionary in rows:
				var k: String = c["key"]
				var how := "replaced" if (res["written"] as Array).has(k) else (
						"appended" if (res["appended"] as Array).has(k) else "NOT FOUND")
				report.append("    %-34s %s -> %s   [%s]"
						% [k, var_to_str(c["old"]), var_to_str(c["new"]), how])
			shown.append("[color=#8f8]%s: %d written[/color]" % [target.get_file(), rows.size()])
		else:
			report.append("--- %s  (PASTE BY HAND — not machine-writable)" % target)
			for c: Dictionary in rows:
				report.append("    %-34s %s -> %s"
						% [c["key"], var_to_str(c["old"]), var_to_str(c["new"])])
			shown.append("[color=#fd8]%s: %d to paste[/color]" % [target.get_file(), rows.size()])

	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "user://crypt_tuning_%s.txt" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(report))
		f.close()
	print("\n".join(report))
	shown.append("[color=#aaa]%s[/color]" % ProjectSettings.globalize_path(path))
	_write_log("\n".join(shown))


func _write_log(s: String) -> void:
	if _save_log != null:
		_save_log.text = s


## A .tres literal, with floats rounded before they are written.
##
## var_to_str is otherwise exactly right — its output IS .tres syntax — but shader uniforms are
## float32 and reading one back into a GDScript float promotes it to float64, so a slider left at
## 0.34 serialises as `0.33999999240032`. Correct, unreadable, and it makes every future diff of the
## file noisy. Six significant digits is well past float32's ~7, so nothing is lost that the GPU
## could have told apart.
static func _literal(v: Variant) -> String:
	if v is float:
		return var_to_str(snappedf(v as float, 0.000001))
	if v is Color:
		var c := v as Color
		return "Color(%s, %s, %s, %s)" % [
			var_to_str(snappedf(c.r, 0.000001)), var_to_str(snappedf(c.g, 0.000001)),
			var_to_str(snappedf(c.b, 0.000001)), var_to_str(snappedf(c.a, 0.000001))]
	if v is Vector3:
		var p := v as Vector3
		return "Vector3(%s, %s, %s)" % [var_to_str(snappedf(p.x, 0.000001)),
			var_to_str(snappedf(p.y, 0.000001)), var_to_str(snappedf(p.z, 0.000001))]
	return var_to_str(v)


## Line-targeted rewrite. Returns which keys were replaced, appended, or not found — a key that
## silently vanishes is how a tuning session appears to save and does not.
func _patch_tres(path: String, values: Dictionary) -> Dictionary:
	var out := {"written": [], "appended": [], "missing": []}
	if not FileAccess.file_exists(path):
		out["missing"] = values.keys()
		return out
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var done := {}
	for i in lines.size():
		var raw: String = lines[i]
		var eq := raw.find(" = ")
		if eq <= 0 or raw.begins_with(";") or raw.begins_with("["):
			continue
		var key := raw.substr(0, eq).strip_edges()
		if not values.has(key) or done.has(key):
			continue
		lines[i] = "%s = %s" % [key, _literal(values[key])]
		done[key] = true
		(out["written"] as Array).append(key)
	# Anything not already in the file is a shader parameter still sitting at its shader default;
	# it needs a new line rather than a replaced one. Appended at the end of the [resource] block,
	# which for these two files is the end of the file.
	var extra: Array[String] = []
	for key: String in values:
		if not done.has(key):
			extra.append("%s = %s" % [key, _literal(values[key])])
			(out["appended"] as Array).append(key)
	var text := "\n".join(lines)
	if not extra.is_empty():
		if not text.ends_with("\n"):
			text += "\n"
		text += "\n".join(extra) + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		out["missing"] = values.keys()
		return out
	f.store_string(text)
	f.close()
	return out


# ---------------------------------------------------------------- lights --------------------
#
# The properties worth a row, per type. Curated rather than the whole Light3D property list,
# because that runs to ~60 entries once transform, visibility, culling and editor-only flags are
# counted and the ones that matter get lost in it. `position` is in the list on purpose: where a
# light IS turns out to matter more than any of its settings — the black-disc bug was a flame mesh
# six centimetres under a point light, and no amount of bias would have fixed it.

const LIGHT_PROPS := [
	"position",
	"light_color", "light_energy", "light_indirect_energy", "light_volumetric_fog_energy",
	"light_size", "light_specular",
	"shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_opacity", "shadow_blur",
	"distance_fade_enabled", "distance_fade_begin", "distance_fade_shadow", "distance_fade_length",
]
const OMNI_PROPS := ["omni_range", "omni_attenuation"]
const SPOT_PROPS := ["spot_range", "spot_attenuation", "spot_angle", "spot_angle_attenuation"]

const GizmoScript := preload("res://scripts/dev/light_gizmo.gd")
## Pixels within which a click grabs a light marker.
const PICK_PX := 18.0

var _light_list: OptionButton
var _light_rows: VBoxContainer
var _lights: Array[Light3D] = []
var _gizmo: Node3D
var _geometry: Label
var _xray := true
var _fly_lights := true
var _last_room: Node3D


func _build_lights_panel(box: VBoxContainer) -> void:
	Tuning.header(box, "LIGHTS")
	_light_list = Tuning.option(box, "", PackedStringArray(), -1,
			func(i: int) -> void: _show_light(i))
	var row := HBoxContainer.new()
	box.add_child(row)
	var sub := VBoxContainer.new()
	row.add_child(sub)
	Tuning.button(sub, "+ Omni", func() -> void: _add_light(true))
	var sub2 := VBoxContainer.new()
	row.add_child(sub2)
	Tuning.button(sub2, "+ Spot", func() -> void: _add_light(false))
	var sub3 := VBoxContainer.new()
	row.add_child(sub3)
	Tuning.button(sub3, "Delete", _delete_light)
	Tuning.line(box, "click a marker to select · drag an arrow to move", Color(0.6, 0.6, 0.7))
	Tuning.check(box, "markers through walls", _xray, func(on: bool) -> void:
		_xray = on
		_refresh_lights())
	# THE READOUT THAT ANSWERS THE QUESTION THE GIZMO EXISTS FOR. Height above the room floor, and
	# the N.L a horizontal floor actually receives at three distances — because a light's height is
	# not an aesthetic choice, it is the single number that decides whether the floor gets lit.
	_geometry = Tuning.line(box, "", Color(1.0, 0.85, 0.55))
	_light_rows = VBoxContainer.new()
	box.add_child(_light_rows)

	_gizmo = GizmoScript.new()
	_gizmo.name = "LightGizmo"
	add_child(_gizmo)
	_gizmo.connect("moved", _on_light_moved)
	_refresh_lights()


## Rescan the zone. Labels carry the room, the type and — most usefully — whether the light casts,
## because "which lights actually cast" was invisible in this project for months while the crypt ran
## ninety lights and one caster.
func _refresh_lights() -> void:
	if _light_list == null:
		return                      # called from _build_zone during _ready, before the UI exists
	_lights.clear()
	if _zone != null and is_instance_valid(_zone):
		for n in _flatten(_zone):
			if n is Light3D and not (n is DirectionalLight3D):
				_lights.append(n as Light3D)
	var names := PackedStringArray()
	for l in _lights:
		var room := "loose"
		var p := l.get_parent()
		while p != null:
			if p is DungeonRoom:
				room = p.name
				break
			p = p.get_parent()
		names.append("%s / %s%s  e%.1f" % [room, l.name,
				"  [shadow]" if l.shadow_enabled else "", l.light_energy])
	_light_list.clear()
	for i in names.size():
		_light_list.add_item(names[i], i)
	for l in _lights:
		_ensure_marker(l)
	if not _lights.is_empty():
		_light_list.select(0)
		_show_light(0)


## A visible dot at every light, parented to the light so it follows without any bookkeeping.
## Coloured by the light's own colour and made bigger when it casts, because "which lights cast"
## is the thing you most want to see at a glance in a room lit by ten of them.
func _ensure_marker(l: Light3D) -> void:
	var m := l.get_node_or_null("TunerMarker") as MeshInstance3D
	if m == null:
		m = MeshInstance3D.new()
		m.name = "TunerMarker"
		var s := SphereMesh.new()
		s.radial_segments = 8
		s.rings = 4
		m.mesh = s
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		l.add_child(m)
	var r := 0.13 if l.shadow_enabled else 0.08
	(m.mesh as SphereMesh).radius = r
	(m.mesh as SphereMesh).height = r * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = l.light_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Through walls by default: a light you cannot see is a light you cannot reposition, and half
	# the point here is spotting one that is buried inside a fixture or sunk into the floor.
	mat.no_depth_test = _xray
	mat.render_priority = 8
	m.material_override = mat


func _show_light(i: int) -> void:
	for c in _light_rows.get_children():
		c.queue_free()
	if i < 0 or i >= _lights.size():
		if _gizmo != null:
			_gizmo.call("detach")
		return
	var l := _lights[i]
	if _gizmo != null:
		_gizmo.call("attach", l)
	_update_geometry(l)
	var props: Array = LIGHT_PROPS.duplicate()
	props.append_array(SPOT_PROPS if l is SpotLight3D else OMNI_PROPS)
	# Deferred so the queue_free'd rows are gone before the new ones arrive — otherwise the panel
	# briefly holds two light's worth of controls and the scroll jumps.
	await get_tree().process_frame
	if not is_instance_valid(l) or not is_instance_valid(_light_rows):
		return
	Tuning.from_object(_light_rows, l, props, func(nm: String, v: Variant) -> void:
		_record(_light_target(l), "%s.%s" % [l.name, nm], v, func() -> Variant: return l.get(nm)))


## HEIGHT IS THE LIGHTING MODEL, stated as the number it actually is. A point source at height h
## delivers N.L = h / sqrt(h^2 + d^2) to a horizontal floor d metres away, and hits the vertical
## wall a metre behind it at ~0.88 no matter where you stand. That asymmetry — not the energies —
## is why the crypt's floor reads dark while its walls read hot, and it is entirely a consequence
## of every light in the kit sitting at candle height.
func _update_geometry(l: Light3D) -> void:
	if _geometry == null:
		return
	var room := _room_at(l.global_position)
	var h: float = l.global_position.y - (room.global_position.y if room != null else 0.0)
	if h <= 0.01:
		_geometry.text = "height %.2f m — at or below the floor" % h
		return
	var parts := PackedStringArray()
	for d in [1.0, 4.0, 9.0]:
		parts.append("%.2f@%dm" % [h / sqrt(h * h + d * d), int(d)])
	_geometry.text = "height %.2f m   floor N·L %s   (a wall gets ~0.88 at any distance)" % [
			h, " ".join(parts)]


## Which FILE a light's value would have to be edited in, since none of them can be saved
## automatically: the kit pieces are .tscn scenes and the room fill is built in code.
func _light_target(l: Light3D) -> String:
	var p := l.get_parent()
	var owner_name: String = String(p.name) if p != null else "?"
	if l.name == "RoomFill":
		return "room_dresser.gd::_fill"
	if owner_name.begins_with("Candelabra"):
		return "scenes/dungeon/kit/candelabra.tscn"
	if owner_name.begins_with("Brazier"):
		return "scenes/dungeon/kit/brazier_a.tscn"
	if owner_name.begins_with("Altar"):
		return "scenes/dungeon/kit/altar.tscn"
	return "scene: %s" % owner_name


## Spawn a light where the fly camera is, parented to the nearest room so it sits in the same
## transform space as everything else.
##
## NOTE it will NOT be dimmed by set_lit: DungeonRoom caches its light list on the first call and
## never rescans. For a bench that is the behaviour you want — a probe light you added stays on
## while you walk out of the room — but it means a light added here is not a faithful preview of
## one added to the kit.
func _add_light(omni: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _zone == null:
		return
	var l: Light3D = OmniLight3D.new() if omni else SpotLight3D.new()
	l.name = "Tuner%s%d" % ["Omni" if omni else "Spot", _lights.size()]
	l.light_energy = 5.0
	l.shadow_enabled = true
	# DROPPED WHERE YOU ARE POINTING, not at the camera. The kit walls and floors are StaticBody3D
	# with real colliders, so a ray through the cursor lands on the surface under it and the light
	# arrives 1.5 m above that — roughly where a fixture would be, and immediately draggable.
	# Falling back to a point in front of the camera keeps it usable when aimed at the void.
	var at := _cursor_world(cam, 1.5)
	var host := _room_at(at)
	var parent: Node = host if host != null else _zone
	parent.add_child(l)
	l.global_position = at
	if not omni:
		l.look_at(at + Vector3.DOWN, Vector3.BACK)
	_note("added %s in %s at %.1f,%.1f,%.1f" % [l.name, parent.name, at.x, at.y, at.z])
	_refresh_lights()
	for i in _lights.size():
		if _lights[i] == l:
			_light_list.select(i)
			_show_light(i)
			break


## Where the cursor ray meets the world, lifted by `up`. Falls back to a point 8 m ahead.
func _cursor_world(cam: Camera3D, up: float) -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return from + cam.project_ray_normal(mouse) * 8.0
	return (hit["position"] as Vector3) + Vector3(0.0, up, 0.0)


func _delete_light() -> void:
	var i := _light_list.get_selected_id() if _light_list != null else -1
	if i < 0 or i >= _lights.size():
		return
	var l := _lights[i]
	_note("deleted %s" % l.name)
	l.get_parent().remove_child(l)
	l.queue_free()
	_refresh_lights()


## LIGHT THE ROOM YOU ARE FLYING THROUGH. Rooms light from DungeonRoom's Area3D trigger, which
## filters on the "player" group — so in fly mode nothing ever enters one and you fly through the
## state frozen at build time. Worse than dark, too: show_around() sets `visible = false` on every
## room further than one door out, so the third room along is not dimmed, it is not drawn.
##
## This mirrors what the trigger does (dungeon_room.gd:93-96) and nothing else. It deliberately does
## NOT call claim_frame, set_follow_bounds or _activate — that last one slams the doors and SPAWNS
## THE ENEMIES, and a lighting bench that drops a brute on you every time you cross a room is not a
## lighting bench.
##
## Gated on the room CHANGING. set_lit early-outs on `_lit == on`, so a per-frame call is nearly free
## and cannot restart the 0.5 s fade — but show_around re-scans every sibling's children, so it is
## still worth not doing sixty times a second.
func _light_room_under_camera() -> void:
	var here := _room_at(_player_or_cam())
	if here == null or here == _last_room:
		return
	_last_room = here
	for sib in here.get_parent().get_children():
		if sib is DungeonRoom:
			(sib as DungeonRoom).set_lit(sib == here)
	(here as DungeonRoom).show_around()
	_note("lit %s" % here.name)


## Which room contains a world point. Footprint containment first, nearest-XZ as the fallback.
##
## THE OBVIOUS VERSION IS WRONG TWICE, and both bite here. Measuring 3D distance to room centres puts
## the fly camera — which sits 12.5 m up at the game's own angle — closer to a NEIGHBOUR's centre
## than to the room it is inside, and a stairwell's rooms are FLOOR_HEIGHT = 8 m apart in Y so the
## floor above can win outright. And walking the whole zone recursively per call is wasteful when
## rooms are DIRECT children of the zone root (dungeon_generator.gd:90) — which matters now that
## this runs every frame for the fly-mode lighting.
##
## `footprint` is per-room, not the global ROOM_SIZE, so this handles multi-cell halls correctly.
func _room_at(at: Vector3) -> Node3D:
	if _zone == null or not is_instance_valid(_zone):
		return null
	var best: Node3D = null
	var bd := INF
	for n in _zone.get_children():
		if not (n is DungeonRoom):
			continue
		var r := n as DungeonRoom
		var d: Vector3 = at - r.global_position
		if absf(d.y) < DungeonLayout.FLOOR_HEIGHT * 0.5 \
				and absf(d.x) <= r.footprint.x * 0.5 and absf(d.z) <= r.footprint.z * 0.5:
			return r
		var flat := absf(d.x) + absf(d.z)
		if flat < bd:
			bd = flat
			best = r
	return best


func _post_toggle(box: VBoxContainer, label: String, node_name: String) -> void:
	var n := get_node_or_null(NodePath(node_name)) as CanvasLayer
	if n == null:
		Tuning.line(box, "%s — MISSING" % label, Color(1.0, 0.5, 0.4))
		return
	Tuning.check(box, label, n.visible, func(on: bool) -> void: n.visible = on)


## The post shaders' own uniforms, same introspection as the stone panel. Their ColorRect child owns
## the ShaderMaterial, not the CanvasLayer.
func _post_uniforms(box: VBoxContainer, node_name: String) -> void:
	var n := get_node_or_null(NodePath(node_name))
	if n == null:
		return
	for c in n.get_children():
		if c is CanvasItem and (c as CanvasItem).material is ShaderMaterial:
			var mat := (c as CanvasItem).material as ShaderMaterial
			Tuning.from_shader(box, mat, func(nm: String, v: Variant) -> void:
				_record(node_name, nm, v, func() -> Variant:
					return RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), nm)))
			return


## Record a change, capturing the pre-change value the first time a key is touched.
func _record(target: String, key: String, new_value: Variant, old_getter: Callable) -> void:
	var id := "%s|%s" % [target, key]
	if not _changes.has(id):
		_changes[id] = {"target": target, "key": key, "old": old_getter.call()}
	_changes[id]["new"] = new_value
	_note("%d changed" % _changes.size())


func _note(s: String) -> void:
	if _status != null:
		_status.text = s
	print("[TUNER] %s" % s)


# ---------------------------------------------------------------- fly / walk ----------------
#
# Copied from scripts/dev/whinbek_lookdev.gd:136. It toggles processing and swaps which Camera3D is
# current — deliberately NOT CameraRig.claim_frame, which is about which room owns the framing, not
# about which camera the viewport looks through.


func _set_mode(walk: bool) -> void:
	_walking = walk
	var player := get_node_or_null("Player") as Node3D
	var rig := get_node_or_null("CameraRig") as Node3D
	var fly := get_node_or_null("FlyCam") as Camera3D
	if player != null:
		player.visible = walk
		player.set_process(walk)
		player.set_physics_process(walk)
		player.set_process_input(walk)
		player.set_process_unhandled_input(walk)
	if rig != null:
		# set_process is a no-op — CameraRig follows in _physics_process (camera_rig.gd:101) and has
		# no _process at all. Kept only because the line is copied verbatim from whinbek_lookdev,
		# and removing it silently would invite someone to add it back.
		rig.set_physics_process(walk)
		# SNAP, DO NOT LERP. The rig eases toward its target at follow_speed 6.0 and has not been
		# tracking at all while flying, so without this, entering WALK is a one-to-two second swoop
		# through blacked-out fog from wherever the rig last was before anything appears.
		if walk and player != null:
			(rig as Node3D).global_position = player.global_position
		var rig_cam := rig.get_node_or_null("Camera3D") as Camera3D
		if rig_cam != null and walk:
			rig_cam.current = true
	# Re-apply the lit room on the next frame whichever way we just switched: walk hands lighting
	# back to the Area3D trigger, fly takes it back.
	_last_room = null
	if fly != null:
		fly.set_process(not walk)
		fly.set_process_unhandled_input(not walk)
		if not walk:
			fly.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_mode_button() -> void:
	if _mode_button != null:
		_mode_button.text = ("Switch to FLY  (Tab)" if _walking else "Switch to WALK  (Tab)")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_TAB:
		_set_mode(not _walking)
		_refresh_mode_button()
		get_viewport().set_input_as_handled()
		return
	# LMB anywhere that is not a gizmo arrow selects the nearest light marker. The gizmo runs its
	# own handler and marks the event handled when it grabs an axis, but node input order is not
	# something to rely on for correctness, so ask it directly.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
				and not (_gizmo != null and _gizmo.call("is_dragging")):
			if _pick_light(mb.position):
				get_viewport().set_input_as_handled()


## Nearest light to the cursor in SCREEN space. Lights have no colliders, and giving them fake ones
## to click would put bodies into a scene whose collision layout is a gameplay contract — so this
## projects each candidate instead. It also keeps working when a light is buried inside a wall or a
## fixture, which is exactly the case you most need to grab.
func _pick_light(at: Vector2) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var best := -1
	var best_d := PICK_PX
	for i in _lights.size():
		var l := _lights[i]
		if not is_instance_valid(l) or cam.is_position_behind(l.global_position):
			continue
		var d := at.distance_to(cam.unproject_position(l.global_position))
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	_light_list.select(best)
	_show_light(best)
	_note("selected %s" % _lights[best].name)
	return true


## A drag finished. Record it against the file the value would have to be edited in, and refresh the
## height readout — the number the whole gizmo exists to let you push around.
func _on_light_moved(l: Light3D, from: Vector3, to: Vector3) -> void:
	_record(_light_target(l), "%s.position" % l.name, to, func() -> Variant: return from)
	_update_geometry(l)
	_note("%s -> %.2f, %.2f, %.2f" % [l.name, to.x, to.y, to.z])


## Every tenth frame, not every frame: get_rendering_info and the render-time timers are cheap but
## rewriting a Label's text forces a relayout of the whole panel, and a bench that stutters while
## you drag a slider is a bench that lies about what the slider costs.
func _process(_delta: float) -> void:
	if _fly_lights and not _walking:
		_light_room_under_camera()
	if _perf_line == null or Engine.get_frames_drawn() % 10 != 0:
		return
	var rid := get_viewport().get_viewport_rid()
	_perf_line.text = "%d fps   gpu %.2f ms   %d draws   %.1fM prims   %.0f MB" % [
		Engine.get_frames_per_second(),
		RenderingServer.viewport_get_measured_render_time_gpu(rid),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
				/ 1048576.0]


func _flatten(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_flatten(c))
	return out

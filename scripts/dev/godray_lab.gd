extends Node3D
## THE GOD-RAY BENCH: one room, one breach, and every number that decides what the shaft looks like.
##
##   Godot_v4.6.3-stable_win64_console.exe --path . res://scenes/dev/godray_lab.tscn
##
## WHY A THIRD BENCH. layout_lab answers "what did the rules decide" and crypt_tuner answers "how
## does the whole crypt look". Neither is any use here, because a shaft of light is a THREE-SYSTEM
## effect — a spot light, a fog volume, and the geometry of the hole between them — and the failure
## modes all look identical from a screenshot:
##
##   * the beam misses the hole and lights a metre of solid masonry (this shipped, twice)
##   * the beam is correct and there is no fog for it to be visible in
##   * the fog is correct and reaches out through the wall into the void, where a lookdev check
##     pins luminance under 0.005
##   * everything is correct and the numbers are simply too low
##
## Four different fixes, one symptom: "the god rays look flat". So this bench puts the geometry, the
## light and the fog on the same panel, and MEASURES the frame while you drag them.
##
## THE TWO GEOMETRY CONTROLS ARE THE POINT. A lamp at (x, hole + d*s, -d) aimed along (0, -s, 1)
## crosses the wall plane at exactly y = hole for ANY slope s and ANY standoff d — the beam cannot
## miss the opening, whatever you drag. What s and d actually choose:
##
##   slope     how steep the shaft is. Deliberately NOT the camera's own 53 degrees: a beam parallel
##             to the view foreshortens into a blob rather than reading as a shaft.
##   standoff  how far behind the wall the lamp sits — and therefore whether it is inside the room's
##             VoxelGI. RoomGI's volume reaches MARGIN/2 (2.0 m) past each wall; a lamp beyond that
##             lights the fog and bounces into the room not at all, which is the single most
##             convincing way to make a shaft look painted on.
##
## Nothing here is imported by the game. It builds the real zone and edits the real nodes, and SAVE
## writes them back to every file they live in — the two wall_breach_*.tscn, room_gi.gd for the GI
## constants and dungeon_env.gd for the Environment fog. Those last two are why the first version of
## this, which printed values to paste, lost a whole tuning session: they are not in the scene.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")

const MAIN := "res://scenes/main.tscn"
const ZONE := "res://scenes/world/zone_crypt.tscn"
const BREACH := "res://scenes/dungeon/kit/wall_breach_a.tscn"
## Where the hole sits in the breach mesh, in the piece's local space. Must match the `hole=` tuple
## in tools/make_dungeon_variants.py — move it there and this follows, or the beam misses.
const HOLE := Vector2(0.55, 1.95)
const PANEL_W := 330

var _zone: Node3D
var _room: DungeonRoom
var _breach: Node3D
var _spot: SpotLight3D
var _fog: FogVolume
var _fog_mat: FogMaterial
var _env: Environment
var _cam: FlyCamera

var _slope := 1.0
var _standoff := 1.5
var _fog_len := 7.0
var _fog_wide := 2.8
var _readout: Label
var _pane: RichTextLabel


func _ready() -> void:
	_stage()
	# AWAITED. _build() waits a frame for the zone's _ready to run, and the panel is built out of
	# the nodes it produces — without the await the SHAFT LIGHT and SHAFT FOG sections would simply
	# be absent, and a bench missing half its controls looks like a bench with nothing to control.
	await _build()
	_ui()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--selftest="):
			_selftest(a.trim_prefix("--selftest="))
			return


# ---------------------------------------------------------------- staging ------------------

## Lift the game's own Environment rather than authoring one. A bench with a hand-written
## Environment tunes a shaft against a look the game never ships — the drift docs/anime-look-todo.md
## A3 is a post-mortem about. duplicate(true) because DungeonEnv MUTATES what it is given and
## main.tscn's is a shared cached sub-resource.
func _stage() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	var src: Environment = null
	for n in _all(main):
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			src = (n as WorldEnvironment).environment
			break
	_env = src.duplicate(true) if src != null else Environment.new()
	main.free()
	var we := WorldEnvironment.new()
	we.environment = _env
	we.add_to_group("world_env")
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.add_to_group("sun")
	add_child(sun)

	_cam = FlyCamera.new()
	_cam.speed = 10.0
	_cam.current = true
	add_child(_cam)


## A SMALL REAL DUNGEON, then one wall forced to be breached.
##
## Three rooms rather than one: the crypt has no standalone "build me a room" entry point, and
## reaching for one would mean this bench lighting something the game never assembles. Three builds
## in well under a second and everything — RoomFog, RoomGI, the theme, the cutaway — is the real
## thing.
func _build() -> void:
	if _zone != null and is_instance_valid(_zone):
		remove_child(_zone)
		_zone.queue_free()
		_zone = null
	_zone = (load(ZONE) as PackedScene).instantiate() as Node3D
	_zone.set("dungeon_seed", 42)
	_zone.set("room_count", 3)
	add_child(_zone)
	await get_tree().process_frame

	# NOT THE START ROOM. It is at cell zero, runs the `threshold` program (no cover, few mounts) and
	# holds the return portal — a bright cyan box parked in the middle of the subject. Any other room
	# is a lit fight room, which is what a shaft is meant to be seen against.
	for n in _zone.get_children():
		if n is DungeonRoom and (n as DungeonRoom).cell != Vector3i.ZERO:
			_room = n as DungeonRoom
			break
	if _room == null:
		for n in _zone.get_children():
			if n is DungeonRoom:
				_room = n as DungeonRoom
				break
	for n in _all(_zone):
		if n is DungeonRoom:
			(n as DungeonRoom).visible = true
			(n as DungeonRoom).set_lit(true)
	_force_breach()
	_frame()
	_apply_geometry()
	# BAKE THE ROOM ON SCREEN. RoomGI primes the start room and its neighbours and then waits for a
	# player to follow; this bench has none and frames a different room anyway, so without forcing it
	# the subject is lit by direct light only — which is exactly the "no bounce" the GI section below
	# exists to fix, and it would look like the sliders did nothing.
	var gi = _zone.get_node_or_null("RoomGI")
	if gi != null:
		gi.probe = _room
		gi._ensure(_room)
		gi._only(_room)


## Swap one upper course on the FAR wall for a breach.
##
## The far wall specifically: RoomDresser stamps every course with COURSE_META and its yaw encodes
## which side of the room it is on, so `out_of_yaw(rotation.y) == (0, -1)` is the -Z run — the one
## the fixed camera actually looks at. Putting the subject on a side wall would make this a bench
## for something you cannot see.
func _force_breach() -> void:
	if _room == null:
		return
	var target: Node3D = null
	for c in _room.get_children():
		if not (c is Node3D) or not c.has_meta(RoomDresser.COURSE_META):
			continue
		if str(c.get_meta(RoomDresser.COURSE_META)) != RoomPlan.T_WALL_UPPER:
			continue
		if RoomShape.out_of_yaw((c as Node3D).rotation.y) != Vector2i(0, -1):
			continue
		if target == null or absf((c as Node3D).position.x) < absf(target.position.x):
			target = c as Node3D          # the most central bay of that run
	if target == null:
		return
	var at := target.position
	var yaw := target.rotation.y
	_room.remove_child(target)
	target.queue_free()

	_breach = (load(BREACH) as PackedScene).instantiate() as Node3D
	_room.add_child(_breach)
	_breach.position = at
	_breach.rotation.y = yaw
	Kit.dress(_breach, _zone.get("theme"), -1.0, at.y, "wall_upper")
	_spot = _breach.get_node_or_null("Shaft") as SpotLight3D
	_fog = _breach.get_node_or_null("ShaftFog") as FogVolume
	if _fog != null:
		# duplicate() so dragging density here cannot write through to the shipped .tscn's resource
		_fog_mat = (_fog.material as FogMaterial).duplicate() as FogMaterial
		_fog.material = _fog_mat


## THE ARITHMETIC THE BENCH EXISTS FOR. Lamp at (hx, hole.y + d*s, -d), aimed along (0, -s, 1).
## Crossing z = 0 costs d of forward travel and therefore d*s of drop, which lands exactly on
## hole.y for every s and every d. The fog runs from the wall plane inward, never behind it.
func _apply_geometry() -> void:
	if _spot == null:
		return
	var s := _slope
	var d := _standoff
	var inv := 1.0 / sqrt(1.0 + s * s)
	var zc := Vector3(0.0, s * inv, -inv)             # -direction
	var xc := Vector3(-1.0, 0.0, 0.0)
	var yc := zc.cross(xc)
	var basis := Basis(xc, yc, zc)
	_spot.transform = Transform3D(basis, Vector3(HOLE.x, HOLE.y + d * s, -d))
	if _fog == null:
		return
	# start at the wall plane (t = d / dir.z) and run `_fog_len` further in
	var t0 := d / inv
	var mid := t0 + _fog_len * 0.5
	var dir := -zc
	_fog.transform = Transform3D(basis, Vector3(HOLE.x, HOLE.y + d * s, -d) + dir * mid)
	_fog.size = Vector3(_fog_wide, _fog_wide, _fog_len)


## The baked GI data for the room on screen. Looked up live rather than cached, because RoomGI evicts
## and re-bakes: a cached VoxelGIData would go stale the moment the bench rebuilt a room, and the
## sliders would silently be writing to a texture nothing renders.
func _gi_data() -> VoxelGIData:
	if _zone == null or not is_instance_valid(_zone) or _room == null:
		return null
	var gi = _zone.get_node_or_null("RoomGI")
	if gi == null:
		return null
	var vgi = gi._data.get(_room)
	if vgi == null or not is_instance_valid(vgi):
		return null
	return (vgi as VoxelGI).data


func _frame() -> void:
	if _room == null:
		return
	# Far enough back to see the beam LAND. The interesting half of a shaft is the pool at the
	# bottom, not the hole at the top — that is where you can tell a shaft from a glow — and the
	# game's own 18 m framing cropped it off.
	var at := _room.global_position
	_cam.global_position = at + Vector3(0.0, 11.5, 18.0)
	_cam.look_at(at + Vector3(0.0, 2.0, -2.0), Vector3.UP)


# ---------------------------------------------------------------- the panel ----------------

func _ui() -> void:
	var box := Tuning.build_panel(self, PANEL_W, 760)

	Tuning.header(box, "BEAM GEOMETRY")
	Tuning.line(box, "the beam hits the hole at ANY of these", Color(0.55, 0.75, 0.55))
	Tuning.slider(box, "slope (rise/run)", 0.4, 3.0, 0.05, _slope, func(v: float) -> void:
		_slope = v
		_apply_geometry())
	Tuning.slider(box, "standoff (m behind wall)", 0.4, 4.0, 0.1, _standoff, func(v: float) -> void:
		_standoff = v
		_apply_geometry())
	Tuning.line(box, "standoff > 2.0 leaves the room's VoxelGI", Color(0.95, 0.72, 0.4))

	Tuning.header(box, "SHAFT LIGHT")
	if _spot != null:
		Tuning.slider(box, "energy", 0.0, 30.0, 0.5, _spot.light_energy,
				func(v: float) -> void: _spot.light_energy = v)
		Tuning.slider(box, "volumetric fog energy", 0.0, 20.0, 0.25,
				_spot.light_volumetric_fog_energy,
				func(v: float) -> void: _spot.light_volumetric_fog_energy = v)
		Tuning.slider(box, "spot angle", 5.0, 45.0, 0.5, _spot.spot_angle,
				func(v: float) -> void: _spot.spot_angle = v)
		Tuning.slider(box, "spot range", 8.0, 40.0, 1.0, _spot.spot_range,
				func(v: float) -> void: _spot.spot_range = v)
		Tuning.slider(box, "attenuation", 0.2, 3.0, 0.05, _spot.spot_attenuation,
				func(v: float) -> void: _spot.spot_attenuation = v)
		# SOFTNESS lives in these two, not in the fog. light_size is the source's physical radius —
		# at 0.3 the masonry throws a cut-paper shadow edge and the beam looks stencilled; the
		# references all have a penumbra a metre wide. angle attenuation does the same across the
		# cone rather than along the shadow.
		Tuning.slider(box, "light size (penumbra)", 0.0, 4.0, 0.05, _spot.light_size,
				func(v: float) -> void: _spot.light_size = v)
		Tuning.slider(box, "angle attenuation (soft edge)", 0.0, 4.0, 0.05,
				_spot.spot_angle_attenuation,
				func(v: float) -> void: _spot.spot_angle_attenuation = v)
		Tuning.color(box, "colour", _spot.light_color,
				func(c: Color) -> void: _spot.light_color = c)
		Tuning.check(box, "shadows (the shaft IS the shadow)", _spot.shadow_enabled,
				func(on: bool) -> void: _spot.shadow_enabled = on)

	Tuning.header(box, "SHAFT FOG")
	if _fog_mat != null:
		Tuning.slider(box, "density", 0.0, 0.4, 0.005, _fog_mat.density,
				func(v: float) -> void: _fog_mat.density = v)
		Tuning.slider(box, "edge fade", 0.0, 1.0, 0.05, _fog_mat.edge_fade,
				func(v: float) -> void: _fog_mat.edge_fade = v)
		Tuning.slider(box, "height falloff", 0.0, 2.0, 0.05, _fog_mat.height_falloff,
				func(v: float) -> void: _fog_mat.height_falloff = v)
		Tuning.color(box, "fog albedo", _fog_mat.albedo,
				func(c: Color) -> void: _fog_mat.albedo = c)
		Tuning.slider(box, "length", 2.0, 16.0, 0.5, _fog_len, func(v: float) -> void:
			_fog_len = v
			_apply_geometry())
		Tuning.slider(box, "width", 1.0, 6.0, 0.1, _fog_wide, func(v: float) -> void:
			_fog_wide = v
			_apply_geometry())

	# THE HALF THE SHAFT DOES NOT DO ITSELF. In every reference the room is lit by the beam's BOUNCE
	# — the floor it lands on throws light back onto the walls and up into the vault — and that is
	# VoxelGI, not fog. bake() leaves this data at energy 1.0 with one bounce, which is thin for a
	# crypt whose other emitters are candle-sized, so the strongest light in the building was giving
	# up most of its effect on the way back.
	Tuning.header(box, "GLOBAL ILLUMINATION")
	var gi := _gi_data()
	if gi == null:
		Tuning.line(box, "room not baked yet — fly into it", Color(0.95, 0.72, 0.4))
	else:
		Tuning.slider(box, "GI energy", 0.0, 6.0, 0.1, gi.energy, func(v: float) -> void:
			var d := _gi_data()
			if d != null:
				d.energy = v)
		Tuning.slider(box, "GI propagation", 0.0, 1.0, 0.02, gi.propagation,
				func(v: float) -> void:
					var d := _gi_data()
					if d != null:
						d.propagation = v)
		Tuning.check(box, "two bounces", gi.use_two_bounces, func(on: bool) -> void:
			var d := _gi_data()
			if d != null:
				d.use_two_bounces = on)

	Tuning.header(box, "ENVIRONMENT")
	Tuning.slider(box, "fog GI inject", 0.0, 1.0, 0.05, _env.volumetric_fog_gi_inject,
			func(v: float) -> void: _env.volumetric_fog_gi_inject = v)
	Tuning.slider(box, "fog anisotropy", -0.9, 0.9, 0.05, _env.volumetric_fog_anisotropy,
			func(v: float) -> void: _env.volumetric_fog_anisotropy = v)
	Tuning.slider(box, "global fog density", 0.0, 0.05, 0.001, _env.volumetric_fog_density,
			func(v: float) -> void: _env.volumetric_fog_density = v)

	Tuning.header(box, "MEASURED")
	_readout = Tuning.line(box, "", Color(0.85, 0.85, 0.9))
	Tuning.line(box, "lookdev bounds: void < 0.005,", Color(0.6, 0.6, 0.66))
	Tuning.line(box, "volumetric fog contribution 0.008..0.070", Color(0.6, 0.6, 0.66))

	Tuning.button(box, "SAVE to the .tscn and the scripts", func() -> void: _save())
	_pane = Tuning.log_pane(box, 170)
	Tuning.line(box, "RMB+WASD fly, Q/E down/up", Color(0.6, 0.6, 0.66))


## WRITE THE TUNED VALUES TO DISK. Not "print them for pasting", and the difference is the whole
## reason this function was rewritten: the first version printed EIGHT of the twenty-three things
## the panel tunes. It silently dropped spot_angle_attenuation, shadow_enabled, all three GI
## controls and all three Environment ones — so a session spent making the shaft soft and the room
## bright copied out as a shaft that was neither, and reopening the scene looked like the bench had
## lied. A partial copy button is worse than no copy button, because it fails quietly.
##
## Patches lines in place rather than re-serialising: these files carry more comment than data, and
## every one of those comments is a decision somebody has to be able to read later.
func _save() -> void:
	if _spot == null or _fog_mat == null:
		return
	var done: Array[String] = []
	# Breach A is what the bench edits; B gets the same LOOK but keeps its own geometry, because its
	# hole is somewhere else and a transform copied across would aim the beam at solid masonry.
	for spec in [["a", HOLE], ["b", Vector2(-0.85, 2.15)]]:
		var path := "res://scenes/dungeon/kit/wall_breach_%s.tscn" % spec[0]
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var hole: Vector2 = spec[1]
		var lamp := _lamp_xform(hole)
		var fogx := _fog_xform(hole)
		txt = _patch(txt, "FogMaterial", "density", "%.4f" % _fog_mat.density)
		txt = _patch(txt, "FogMaterial", "albedo", "Color(%.3f, %.3f, %.3f, 1)"
				% [_fog_mat.albedo.r, _fog_mat.albedo.g, _fog_mat.albedo.b])
		txt = _patch(txt, "FogMaterial", "edge_fade", "%.3f" % _fog_mat.edge_fade)
		txt = _patch(txt, "FogMaterial", "height_falloff", "%.3f" % _fog_mat.height_falloff)
		txt = _patch(txt, "Shaft", "transform", _fmt(lamp))
		txt = _patch(txt, "Shaft", "light_color", "Color(%.3f, %.3f, %.3f, 1)"
				% [_spot.light_color.r, _spot.light_color.g, _spot.light_color.b])
		txt = _patch(txt, "Shaft", "light_energy", "%.3f" % _spot.light_energy)
		txt = _patch(txt, "Shaft", "light_size", "%.3f" % _spot.light_size)
		txt = _patch(txt, "Shaft", "light_volumetric_fog_energy",
				"%.3f" % _spot.light_volumetric_fog_energy)
		txt = _patch(txt, "Shaft", "shadow_enabled", "true" if _spot.shadow_enabled else "false")
		txt = _patch(txt, "Shaft", "spot_range", "%.3f" % _spot.spot_range)
		txt = _patch(txt, "Shaft", "spot_angle", "%.3f" % _spot.spot_angle)
		txt = _patch(txt, "Shaft", "spot_angle_attenuation", "%.3f" % _spot.spot_angle_attenuation)
		txt = _patch(txt, "Shaft", "spot_attenuation", "%.3f" % _spot.spot_attenuation)
		txt = _patch(txt, "ShaftFog", "transform", _fmt(fogx))
		txt = _patch(txt, "ShaftFog", "size", "Vector3(%.2f, %.2f, %.2f)"
				% [_fog_wide, _fog_wide, _fog_len])
		var w := FileAccess.open(path, FileAccess.WRITE)
		if w != null:
			w.store_string(txt)
			w.close()
			done.append(path.get_file())

	# THE GI AND ENVIRONMENT VALUES DO NOT LIVE IN THE SCENE, and that is precisely what the old
	# copy button hid. They are consts in two scripts, so they are patched there.
	var gi := _gi_data()
	if gi != null:
		if _rewrite("res://scripts/dungeon/style/room_gi.gd",
				"const GI_ENERGY :=", "const GI_ENERGY := %.2f" % gi.energy):
			done.append("room_gi.gd GI_ENERGY")
		if _rewrite("res://scripts/dungeon/style/room_gi.gd",
				"const GI_PROPAGATION :=", "const GI_PROPAGATION := %.2f" % gi.propagation):
			done.append("room_gi.gd GI_PROPAGATION")
	for pair in [["volumetric_fog_gi_inject", _env.volumetric_fog_gi_inject],
			["volumetric_fog_anisotropy", _env.volumetric_fog_anisotropy],
			["volumetric_fog_density", _env.volumetric_fog_density]]:
		if _rewrite("res://scripts/dungeon/style/dungeon_env.gd",
				'	"%s":' % pair[0], '	"%s": %.4f,' % [pair[0], pair[1]]):
			done.append("dungeon_env.gd " + String(pair[0]))

	var msg := "[b]wrote %d[/b]
%s" % [done.size(), "
".join(done)]
	if gi == null:
		msg += "
[color=#fa7368]GI not baked — its values were NOT saved[/color]"
	if _standoff > 2.0:
		msg += "
[color=#fa7368]standoff %.1f is outside the room's VoxelGI[/color]" % _standoff
	_pane.text = msg
	print("[godray] saved: " + ", ".join(done))


## Replace `key = ...` inside a .tscn section, or append it if the section has no such line yet.
## A section runs from its header to the next line starting with "[".
static func _patch(text: String, section: String, key: String, value: String) -> String:
	var lines := text.split("
")
	var out: Array[String] = []
	var inside := false
	var wrote := false
	for i in lines.size():
		var line: String = lines[i]
		if line.begins_with("["):
			if inside and not wrote:
				out.append("%s = %s" % [key, value])
				wrote = true
			inside = line.contains(section)
		if inside and line.begins_with(key + " "):
			out.append("%s = %s" % [key, value])
			wrote = true
			continue
		out.append(line)
	if inside and not wrote:
		out.append("%s = %s" % [key, value])
	return "
".join(out)


## Replace the one line starting with `prefix`. Returns whether anything changed — a silent no-op
## here is how a value gets "saved" and then reappears at its old number.
static func _rewrite(path: String, prefix: String, replacement: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var lines := f.get_as_text().split("
")
	f.close()
	var hit := false
	for i in lines.size():
		if lines[i].begins_with(prefix):
			lines[i] = replacement
			hit = true
			break
	if not hit:
		return false
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		return false
	w.store_string("
".join(lines))
	w.close()
	return true


## The lamp transform for a given hole, from the current slope and standoff.
func _lamp_xform(hole: Vector2) -> Transform3D:
	var inv := 1.0 / sqrt(1.0 + _slope * _slope)
	var zc := Vector3(0.0, _slope * inv, -inv)
	var xc := Vector3(-1.0, 0.0, 0.0)
	return Transform3D(Basis(xc, zc.cross(xc), zc),
			Vector3(hole.x, hole.y + _standoff * _slope, -_standoff))


func _fog_xform(hole: Vector2) -> Transform3D:
	var inv := 1.0 / sqrt(1.0 + _slope * _slope)
	var lamp := _lamp_xform(hole)
	var dir := -lamp.basis.z
	return Transform3D(lamp.basis, lamp.origin + dir * (_standoff / inv + _fog_len * 0.5))


func _fmt(t: Transform3D) -> String:
	var b := t.basis
	return "Transform3D(%.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f)" % [
		b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
		t.origin.x, t.origin.y, t.origin.z]


# ---------------------------------------------------------------- measuring ----------------
#
# TUNE AGAINST NUMBERS, NOT AN IMPRESSION. Every one of this project's art regressions was found by
# probing pixels and missed by looking; the shaft is worse than most, because a bright beam and a
# beam that has flooded the room look the same until you measure the void.

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5 or _readout == null:
		return
	_t = 0.0
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	# The void is the top strip: above the cornice there is nothing, and any light there is light
	# that has escaped the room.
	var void_l := _mean(img, Rect2i(int(w * 0.35), 0, int(w * 0.3), int(h * 0.12)))
	var room_l := _mean(img, Rect2i(int(w * 0.3), int(h * 0.25), int(w * 0.55), int(h * 0.45)))
	_readout.text = "void %.4f   room %.4f%s" % [void_l, room_l,
			"    LEAKING" if void_l >= 0.005 else ""]


func _mean(img: Image, r: Rect2i) -> float:
	var total := 0.0
	var n := 0
	var y := r.position.y
	while y < mini(r.end.y, img.get_height()):
		var x := r.position.x
		while x < mini(r.end.x, img.get_width()):
			var c := img.get_pixel(x, y)
			total += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			n += 1
			x += 4
		y += 4
	return total / maxf(n, 1)


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _count(n: Node, cls: String) -> int:
	var total := 1 if n.is_class(cls) else 0
	for c in n.get_children():
		total += _count(c, cls)
	return total


# ---------------------------------------------------------------- selftest -----------------
#
# An interactive scene cannot otherwise be checked from a terminal: it never exits, so `timeout`
# kills it and takes every buffered print with it.

func _selftest(out_dir: String) -> void:
	var fails: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for _i in 40:
		await get_tree().process_frame
	if _breach == null:
		fails.append("no breach was forced onto the far wall")
	if _spot == null or _fog == null:
		fails.append("breach carries no Shaft / ShaftFog")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/godray_lab.png")

	# THE BEAM MUST REACH THE HOLE, asserted rather than eyeballed, at several slopes and standoffs.
	# This is the check that would have caught the two versions that shipped pointing at masonry.
	for s in [0.6, 1.0, 2.0]:
		for d in [0.8, 1.5, 3.0]:
			_slope = s
			_standoff = d
			_apply_geometry()
			var o := _spot.transform.origin
			var dir := -_spot.transform.basis.z
			var t := -o.z / dir.z
			var y := o.y + dir.y * t
			if absf(y - HOLE.y) > 0.001:
				fails.append("slope %.1f standoff %.1f: beam crosses the wall at y %.3f, hole is %.3f"
						% [s, d, y, HOLE.y])
	_slope = 1.0
	_standoff = 1.5
	_apply_geometry()

	var void_l := _mean(img, Rect2i(int(img.get_width() * 0.35), 0,
			int(img.get_width() * 0.3), int(img.get_height() * 0.12)))
	if void_l >= 0.005:
		fails.append("void luminance %.4f — the shaft fog is leaking outside the room" % void_l)
	# BACK THE FILES UP FIRST. This test exercises the REAL save path onto the REAL files — anything
	# less would not have caught the bug it exists for — so it has to put them back afterwards. A
	# selftest that leaves 12.25 in a shipped light is worse than the bug.
	const TOUCHED := [
		"res://scenes/dungeon/kit/wall_breach_a.tscn",
		"res://scenes/dungeon/kit/wall_breach_b.tscn",
		"res://scripts/dungeon/style/room_gi.gd",
		"res://scripts/dungeon/style/dungeon_env.gd",
	]
	var backup := {}
	for path in TOUCHED:
		var bf := FileAccess.open(path, FileAccess.READ)
		if bf == null:
			fails.append("could not back up " + path)
			continue
		backup[path] = bf.get_as_text()
		bf.close()

	# THE ROUND TRIP. Set distinctive values, save, read the FILES BACK, and assert every one of them
	# survived. The old copy button emitted 8 of 23 controls and dropped every GI and Environment
	# value silently — a whole tuning session came back wrong and looked like the bench had lied.
	# Asserting against the text on disk is the only version of this check that could have caught it.
	_spot.light_energy = 12.25
	_spot.light_size = 1.75
	_spot.spot_angle = 27.5
	_spot.spot_angle_attenuation = 2.25
	_spot.spot_attenuation = 0.45
	_fog_mat.density = 0.0325
	_fog_mat.edge_fade = 0.65
	var gi_before := _gi_data()
	if gi_before != null:
		gi_before.energy = 2.35
		gi_before.propagation = 0.77
	_env.volumetric_fog_gi_inject = 0.42
	_save()
	if not _pane.text.contains("wrote"):
		fails.append("save produced no report")
	var want := {
		"res://scenes/dungeon/kit/wall_breach_a.tscn": [
			"light_energy = 12.250", "light_size = 1.750", "spot_angle = 27.500",
			"spot_angle_attenuation = 2.250", "spot_attenuation = 0.450",
			"density = 0.0325", "edge_fade = 0.650"],
		"res://scenes/dungeon/kit/wall_breach_b.tscn": [
			"light_energy = 12.250", "spot_angle_attenuation = 2.250"],
		"res://scripts/dungeon/style/room_gi.gd": [
			"const GI_ENERGY := 2.35", "const GI_PROPAGATION := 0.77"],
		"res://scripts/dungeon/style/dungeon_env.gd": ['"volumetric_fog_gi_inject": 0.4200,'],
	}
	for path in want:
		var rf := FileAccess.open(path, FileAccess.READ)
		if rf == null:
			fails.append("could not re-read " + path)
			continue
		var body := rf.get_as_text()
		rf.close()
		for needle in want[path]:
			if not body.contains(needle):
				fails.append("%s: `%s` did not survive the save" % [path.get_file(), needle])

	for path in backup:
		var rw := FileAccess.open(path, FileAccess.WRITE)
		if rw == null:
			fails.append("COULD NOT RESTORE " + path)
			continue
		rw.store_string(backup[path])
		rw.close()

	# THE PANEL ACTUALLY HAS THE CONTROLS. _build() awaits a frame, so a panel built before it
	# finished would silently skip every light and fog slider — the sections would just not be
	# there, and a bench with no controls is indistinguishable from a bench whose controls do
	# nothing. Counting is how that stays caught.
	# 16 today: 2 geometry, 6 light, 5 fog, 3 environment. The bound is 14 rather than 16 so adding
	# a knob does not fail the suite — but it is well above the 5 a panel built too early produces
	# (geometry and environment only, since those do not depend on the zone), which is the failure
	# this is here to catch.
	var sliders := _count(self, "HSlider")
	if sliders < 14:
		fails.append("panel has only %d sliders — the light/fog sections did not build" % sliders)

	for m in fails:
		printerr("[godray] FAIL: " + m)
	print("[godray] selftest: %d failures, void %.4f, output in %s" % [fails.size(), void_l, out_dir])
	get_tree().quit(1 if not fails.is_empty() else 0)

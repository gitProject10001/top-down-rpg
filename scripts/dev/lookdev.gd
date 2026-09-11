extends Node3D
## Look-development sandbox: an asset, a ground plane, a sun, and live sliders for everything that
## decides how it reads. Fly with RMB + WASD.
##
## WHY THIS EXISTS. Every "is it plastic / is it flat / is it too dark" question so far was settled
## by MEASURING, not by staring at a screenshot — and the slow part was always the edit-reimport-
## relaunch loop. Here the knob and the result are on screen together, so a tuning pass is seconds
## rather than minutes.
##
## It edits assets/materials/painted_env.tres IN MEMORY. "Save material" writes it back to disk, which
## only works when running from the project folder (res:// is not writable in an exported build).
## Characters use assets/materials/toon_character.tres — same shader, separate resource.

const ENV_MAT := "res://assets/materials/painted_env.tres"
## preload by PATH, not by class_name: registering a global class needs an editor rescan, and a
## rescan is what corrupted a style resource last cycle. See tuning_panel.gd.
const Tuning := preload("res://scripts/dev/tuning_panel.gd")

@onready var _sun: DirectionalLight3D = $Sun
@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _subject: Node3D = $Subject
@onready var _omni: OmniLight3D = $Lights/Omni
@onready var _spot: SpotLight3D = $Lights/Spot
@onready var _hearth: OmniLight3D = $Lights/Hearth

## The two foliage materials. Separate from the subject material because wind_height has to match
## the plant's real height — see the note in painted_foliage_small.tres.
const FOLIAGE := ["res://assets/materials/painted_foliage_small.tres",
		"res://assets/materials/painted_foliage_large.tres"]

var _mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _fps: Label
var _sun_yaw := 35.0
var _sun_pitch := 52.0
var _t := 0.0
var _animate := true
var _light_speed := 0.5
var _hearth_base := 3.0
var _bulbs: Dictionary = {}
var _walking := false
var _mode_button: Button
var _foliage: Array[ShaderMaterial] = []


## A visible emissive blob at a light's own origin. Lights are invisible nodes, so without this you
## are guessing where the illumination is coming from — and a moving light is impossible to reason
## about at all.
##
## cast_shadow OFF is not optional: a mesh sitting exactly on a point light's origin would
## otherwise shadow that light with its own body and black out everything around it.
func _make_bulb(light: Light3D, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _bulb_material(light.light_color)
	light.add_child(mi)
	return mi


func _bulb_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 6.0     # over 1.0 so the environment's glow pass picks it up
	return m


func _tint_bulb(light: Light3D, c: Color) -> void:
	light.light_color = c
	var mi: MeshInstance3D = _bulbs.get(light)
	if mi != null:
		mi.material_override = _bulb_material(c)


func _ready() -> void:
	_mat = load(ENV_MAT) as ShaderMaterial
	# ONE material for the whole building. Legitimate here only because the mesh carries its own
	# colour in COLOR_0 — with textures this would need a material per surface.
	for mi in _find_meshes(_subject):
		mi.material_override = _mat
	# The ground is a bare PlaneMesh with no colour attribute, so COLOR is 1.0 and albedo_color is
	# what tints it. It gets a DUPLICATE so it can be a different colour while still receiving every
	# slider change — you cannot judge a shadow terminator without a surface for the shadow to fall on.
	_ground_mat = _mat.duplicate() as ShaderMaterial
	_ground_mat.set_shader_parameter("albedo_color", Color(0.76, 0.63, 0.36))
	# get_node_or_null, NOT $Ground. A hard path here meant that deleting one cosmetic node aborted
	# _ready() before the UI was built, so _fps stayed null and _process threw on every single
	# frame — a missing ground plane took the whole scene down. Nothing optional gets a hard path.
	var ground := get_node_or_null("Ground") as MeshInstance3D
	if ground != null:
		ground.material_override = _ground_mat
	# Frame the subject from code rather than hand-authoring a camera basis in the .tscn — swap the
	# Subject for a different asset and the opening shot still points at it.
	var cam := get_node_or_null("FlyCam") as Camera3D
	if cam != null:
		cam.look_at(Vector3(0.0, 2.2, 0.0), Vector3.UP)
	_bulbs = {
		_omni: _make_bulb(_omni, 0.22),
		_spot: _make_bulb(_spot, 0.16),
		_hearth: _make_bulb(_hearth, 0.13),
	}
	for path in FOLIAGE:
		var m := load(path) as ShaderMaterial
		if m != null:
			_foliage.append(m)
	_build_ui()
	_apply_sun()
	_set_mode(false)                       # start flying; walking is opt-in


## FLY vs WALK. Two things must move together or the scene fights itself: which camera is
## `current`, and whether FlyCamera is allowed to read the keyboard. Leave the fly camera
## processing while walking and WASD drives both at once.
##
## The point of walk mode is that it uses the GAME's player and the GAME's CameraRig. A free
## camera flatters everything, and several problems this session -- the dodge smear reading as a
## line, roof arcs going edge-on -- existed only at the fixed ~53 deg the player actually sees.
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
		rig.set_process(walk)
		rig.set_physics_process(walk)
		var rig_cam := rig.get_node_or_null("Camera3D") as Camera3D
		if rig_cam != null and walk:
			rig_cam.current = true
	if fly != null:
		fly.set_process(not walk)
		fly.set_process_unhandled_input(not walk)
		if not walk:
			fly.current = true
	# Mouse stays free in both modes: walking aims with the cursor, and the panel needs clicks.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_mode_button() -> void:
	if _mode_button != null:
		_mode_button.text = ("Switch to FLY  (Tab)" if _walking else "Switch to WALK  (Tab)")


## Wind belongs to the plants only; the house and ground keep wind_strength at 0.
func _set_wind(name_: String, value: Variant) -> void:
	for m in _foliage:
		m.set_shader_parameter(name_, value)


## Every toon slider goes through here so the subject and the ground never drift apart.
func _set_param(name_: String, value: Variant) -> void:
	_mat.set_shader_parameter(name_, value)
	_ground_mat.set_shader_parameter(name_, value)


func _find_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_find_meshes(c))
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed 			and (event as InputEventKey).keycode == KEY_TAB:
		_set_mode(not _walking)
		_refresh_mode_button()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _fps == null:
		return               # _ready() did not finish; do not throw once per frame on top of it
	_fps.text = "%d fps   %d verts drawn" % [
		Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]
	if not _animate:
		return
	_t += delta * _light_speed

	# Omni orbits the house and bobs, so every wall gets raked at a grazing angle at some point —
	# grazing is where a wrapped-lambert term misbehaves if it is going to.
	_omni.position = Vector3(cos(_t) * 6.8, 2.4 + sin(_t * 2.3) * 0.9, sin(_t) * 6.8)

	# Spot sweeps across the front and keeps aiming at the house, so the cone edge crosses corners
	# and the roof pitch rather than sitting on flat ground.
	var sweep := sin(_t * 0.8)
	_spot.position = Vector3(sweep * 8.0, 9.0, 7.0)
	_spot.look_at(Vector3(sweep * 2.5, 1.2, 0.0), Vector3.UP)

	# Cheap two-frequency flicker: one slow wobble plus one fast one never lines up into an obvious
	# loop, which a single sine always does.
	_hearth.light_energy = _hearth_base * (0.86 + 0.10 * sin(_t * 9.0) + 0.06 * sin(_t * 21.7))


# ---------------------------------------------------------------------------------------------
# UI — built in code, like every other panel in this project (Hud, Pause, Dialogue).
# ---------------------------------------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12; panel.offset_top = 12
	panel.custom_minimum_size = Vector2(310, 0)
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(286, 0)
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)

	_fps = Label.new()
	box.add_child(_fps)
	var help := Label.new()
	help.text = "TAB fly/walk\nfly: RMB look · WASD · Q/E up-down · Shift fast"
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)

	# The single most important knob: how far light carries past the terminator. 0 reads as cel,
	# ~0.5 as painted. Everything else is colour.
	_header(box, "PAINTED — LIGHT")
	_slider(box, "wrap", 0.0, 1.0, 0.01, _mat.get_shader_parameter("wrap"),
			func(v: float) -> void: _set_param("wrap", v))
	_slider(box, "bands (0 = smooth)", 0.0, 8.0, 1.0, _mat.get_shader_parameter("bands"),
			func(v: float) -> void: _set_param("bands", v))
	_slider(box, "band_softness", 0.01, 1.0, 0.01, _mat.get_shader_parameter("band_softness"),
			func(v: float) -> void: _set_param("band_softness", v))

	_header(box, "PAINTED — SHADOW")
	_color(box, "shade_tint", _mat.get_shader_parameter("shade_tint"),
			func(c: Color) -> void: _set_param("shade_tint", c))
	_slider(box, "shade_strength", 0.0, 1.0, 0.01, _mat.get_shader_parameter("shade_strength"),
			func(v: float) -> void: _set_param("shade_strength", v))
	_slider(box, "shade_saturation", 0.0, 2.0, 0.05, _mat.get_shader_parameter("shade_saturation"),
			func(v: float) -> void: _set_param("shade_saturation", v))

	_header(box, "PAINTED — SUNLIT")
	_color(box, "light_tint", _mat.get_shader_parameter("light_tint"),
			func(c: Color) -> void: _set_param("light_tint", c))
	_slider(box, "light_tint_amount", 0.0, 1.0, 0.05,
			_mat.get_shader_parameter("light_tint_amount"),
			func(v: float) -> void: _set_param("light_tint_amount", v))
	_check(box, "use_vertex_color", true,
			func(on: bool) -> void: _mat.set_shader_parameter("use_vertex_color", on))

	_header(box, "SUN")
	_slider(box, "energy", 0.0, 8.0, 0.05, _sun.light_energy,
			func(v: float) -> void: _sun.light_energy = v)
	# light_angular_distance is ALREADY in degrees — converting it showed "458 deg".
	_slider(box, "softness (deg)", 0.0, 30.0, 0.5, _sun.light_angular_distance,
			func(v: float) -> void: _sun.light_angular_distance = v)
	_slider(box, "pitch (deg)", 5.0, 88.0, 1.0, _sun_pitch,
			func(v: float) -> void: _sun_pitch = v; _apply_sun())
	_slider(box, "yaw (deg)", -180.0, 180.0, 1.0, _sun_yaw,
			func(v: float) -> void: _sun_yaw = v; _apply_sun())
	_color(box, "sun colour", _sun.light_color,
			func(c: Color) -> void: _sun.light_color = c)
	# shadow_normal_bias is the one that matters on thin walls: Godot's default 2.0 offsets the
	# shadow further than a 0.22 m wall is thick, so light appears along interior seams.
	_slider(box, "shadow_normal_bias", 0.0, 2.0, 0.05, _sun.shadow_normal_bias,
			func(v: float) -> void: _sun.shadow_normal_bias = v)
	_slider(box, "shadow_bias", 0.0, 0.3, 0.005, _sun.shadow_bias,
			func(v: float) -> void: _sun.shadow_bias = v)
	_slider(box, "shadow max dist", 10.0, 120.0, 5.0, _sun.directional_shadow_max_distance,
			func(v: float) -> void: _sun.directional_shadow_max_distance = v)

	_header(box, "MOVING LIGHTS")
	_check(box, "animate", _animate, func(on: bool) -> void: _animate = on)
	_slider(box, "speed", 0.0, 2.0, 0.05, _light_speed,
			func(v: float) -> void: _light_speed = v)
	_check(box, "omni (orbits)", true, func(on: bool) -> void: _omni.visible = on)
	_slider(box, "omni energy", 0.0, 20.0, 0.5, _omni.light_energy,
			func(v: float) -> void: _omni.light_energy = v)
	_slider(box, "omni range", 1.0, 30.0, 0.5, _omni.omni_range,
			func(v: float) -> void: _omni.omni_range = v)
	_color(box, "omni colour", _omni.light_color,
			func(c: Color) -> void: _tint_bulb(_omni, c))
	_check(box, "spot (sweeps)", true, func(on: bool) -> void: _spot.visible = on)
	_slider(box, "spot energy", 0.0, 40.0, 0.5, _spot.light_energy,
			func(v: float) -> void: _spot.light_energy = v)
	_slider(box, "spot angle", 2.0, 80.0, 1.0, _spot.spot_angle,
			func(v: float) -> void: _spot.spot_angle = v)
	_slider(box, "spot edge falloff", 0.0, 3.0, 0.05, _spot.spot_angle_attenuation,
			func(v: float) -> void: _spot.spot_angle_attenuation = v)
	_color(box, "spot colour", _spot.light_color,
			func(c: Color) -> void: _tint_bulb(_spot, c))
	_check(box, "hearth (indoors)", true, func(on: bool) -> void: _hearth.visible = on)
	_slider(box, "hearth energy", 0.0, 12.0, 0.25, _hearth_base,
			func(v: float) -> void: _hearth_base = v)
	_check(box, "light shadows", true, func(on: bool) -> void:
		_omni.shadow_enabled = on
		_spot.shadow_enabled = on
		_hearth.shadow_enabled = on)

	_header(box, "MODE")
	var mode := Button.new()
	mode.pressed.connect(func() -> void:
		_set_mode(not _walking)
		_refresh_mode_button())
	box.add_child(mode)
	_mode_button = mode
	_refresh_mode_button()

	_header(box, "KUWAHARA (post)")
	var kuwa := get_node_or_null("PostFX/Kuwahara") as ColorRect
	if kuwa != null:
		var km := kuwa.material as ShaderMaterial
		_check(box, "enabled", kuwa.visible, func(on: bool) -> void: kuwa.visible = on)
		_slider(box, "radius (px)", 1.0, 10.0, 1.0, km.get_shader_parameter("radius"),
				func(v: float) -> void: km.set_shader_parameter("radius", int(v)))
		_slider(box, "strength", 0.0, 1.0, 0.05, km.get_shader_parameter("strength"),
				func(v: float) -> void: km.set_shader_parameter("strength", v))

	_header(box, "CAMERA")
	var cam := get_node_or_null("FlyCam") as Camera3D
	if cam != null:
		_slider(box, "fov", 20.0, 100.0, 1.0, cam.fov, func(v: float) -> void: cam.fov = v)
		_slider(box, "near", 0.01, 2.0, 0.01, cam.near, func(v: float) -> void: cam.near = v)
		_slider(box, "far", 50.0, 1000.0, 10.0, cam.far, func(v: float) -> void: cam.far = v)
		_slider(box, "fly speed", 1.0, 60.0, 0.5, cam.get("speed"),
				func(v: float) -> void: cam.set("speed", v))
		_slider(box, "mouse sensitivity", 0.0005, 0.008, 0.0002, cam.get("sensitivity"),
				func(v: float) -> void: cam.set("sensitivity", v))
		# Orthographic is worth a click: this game's real camera is a fixed overhead rig, and a long
		# lens or a true ortho projection is much closer to how the asset will actually be seen than
		# the wide perspective you naturally fly around in.
		_check(box, "orthographic", false, func(on: bool) -> void:
			cam.projection = (Camera3D.PROJECTION_ORTHOGONAL if on
					else Camera3D.PROJECTION_PERSPECTIVE))
		_slider(box, "ortho size", 2.0, 60.0, 0.5, cam.size,
				func(v: float) -> void: cam.size = v)
		# Snap to the game's actual framing: camera_rig.gd's authored pitch is ~53 degrees.
		var frame := Button.new()
		frame.text = "Frame like the game (53°)"
		frame.pressed.connect(func() -> void:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 45.0
			var d := 16.0
			cam.global_position = Vector3(0.0, d * sin(0.93), d * cos(0.93))
			cam.look_at(Vector3(0.0, 1.6, 0.0), Vector3.UP))
		box.add_child(frame)

	_header(box, "WIND (plants only)")
	var fw: ShaderMaterial = _foliage[0] if not _foliage.is_empty() else null
	if fw != null:
		_slider(box, "speed", 0.0, 6.0, 0.05, fw.get_shader_parameter("wind_speed"),
				func(v: float) -> void: _set_wind("wind_speed", v))
		_slider(box, "gust wavelength", 0.01, 1.0, 0.01,
				fw.get_shader_parameter("wind_wavelength"),
				func(v: float) -> void: _set_wind("wind_wavelength", v))
		_slider(box, "grass sway (m)", 0.0, 0.5, 0.01,
				fw.get_shader_parameter("wind_strength"),
				func(v: float) -> void: _foliage[0].set_shader_parameter("wind_strength", v))
		if _foliage.size() > 1:
			_slider(box, "tree sway (m)", 0.0, 1.0, 0.01,
					_foliage[1].get_shader_parameter("wind_strength"),
					func(v: float) -> void: _foliage[1].set_shader_parameter("wind_strength", v))

	_header(box, "WORLD")
	var e := _env.environment
	_slider(box, "ambient energy", 0.0, 3.0, 0.05, e.ambient_light_energy,
			func(v: float) -> void: e.ambient_light_energy = v)
	# The knob that hides: with ambient_light_source = SKY, `ambient energy` above scales only the
	# COLOR term — the sky term is this one. Setting energy to 0 and expecting darkness is the
	# mistake; measured, this slider moved a sealed interior from 0.297 to 0.0003.
	_slider(box, "ambient sky contribution", 0.0, 1.0, 0.05, e.ambient_light_sky_contribution,
			func(v: float) -> void: e.ambient_light_sky_contribution = v)
	_color(box, "ambient colour", e.ambient_light_color,
			func(c: Color) -> void: e.ambient_light_color = c)
	_slider(box, "exposure", 0.2, 3.0, 0.05, e.tonemap_exposure,
			func(v: float) -> void: e.tonemap_exposure = v)
	# SDFGI is the only GI that works on geometry generated at load, so it is the one to judge.
	_check(box, "SDFGI", e.sdfgi_enabled, func(on: bool) -> void: e.sdfgi_enabled = on)
	_check(box, "SSAO", e.ssao_enabled, func(on: bool) -> void: e.ssao_enabled = on)

	var save := Button.new()
	save.text = "Save material to painted_env.tres"
	save.pressed.connect(_save_material)
	box.add_child(save)


func _apply_sun() -> void:
	_sun.rotation_degrees = Vector3(-_sun_pitch, _sun_yaw, 0.0)


func _save_material() -> void:
	var err := ResourceSaver.save(_mat, ENV_MAT)
	print("save %s -> %s" % [ENV_MAT, "OK" if err == OK else error_string(err)])


# The widgets themselves live in tuning_panel.gd so this panel and whinbek_lookdev.gd cannot drift
# apart. These stay as thin forwarders rather than being inlined at ~40 call sites: the diff is one
# line each, so "did the refactor change the existing lookdev?" is answerable by reading them.
func _header(box: VBoxContainer, text: String) -> void:
	Tuning.header(box, text)


func _slider(box: VBoxContainer, name_: String, lo: float, hi: float, step: float,
		value: Variant, on_change: Callable) -> void:
	Tuning.slider(box, name_, lo, hi, step, value, on_change)


func _color(box: VBoxContainer, name_: String, value: Variant, on_change: Callable) -> void:
	Tuning.color(box, name_, value, on_change)


func _check(box: VBoxContainer, name_: String, pressed: bool, on_change: Callable) -> void:
	Tuning.check(box, name_, pressed, on_change)

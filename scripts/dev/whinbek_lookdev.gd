extends Node3D
## Look-development and play sandbox for the GLADEKIT building, tuned against
## docs/images/references/whinbek-conceptart.jpg. Sibling of scripts/dev/lookdev.gd, which does the
## same job for the hand-modelled house.glb.
##
## WHY A SECOND ONE. lookdev.gd skins its subject by walking for MeshInstance3D and setting
## material_override. That cannot work here: a GladeWall frees and regrows every child on every
## rebuild, so an override applied from outside is gone the next time anything nudges the wall.
## GladeKit gets its material two different ways instead, and both matter:
##
##   bricks, timbers, plaster, shingles, floors   GladeStyle.material, read on every rebuild
##   props (.glb frames, shutters, flower boxes)  re-skinned on the `rebuilt` signal, below
##
## Fly with RMB + WASD. TAB switches to WALK, which uses the GAME's player and CameraRig — a free
## camera flatters everything, and the fixed ~53 degrees is the only angle the player ever sees.

const GLADE_MAT := "res://assets/materials/painted_glade.tres"
const Tuning := preload("res://scripts/dev/tuning_panel.gd")
## Preloaded rather than referenced by class_name: a brand-new global class is not in the editor's
## script cache until it rescans, and this project has learned to keep editor runs to a minimum.
const SeeThroughScript := preload("res://scripts/see_through.gd")
const InteriorViewScript := preload("res://scripts/interior_view.gd")

@onready var _sun: DirectionalLight3D = $Sun
@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _subject: Node3D = $Subject

var _mat: ShaderMaterial
var _fps: Label
var _sun_yaw := 35.0
var _sun_pitch := 38.0
var _walking := false
var _mode_button: Button
var _walls: Array[GladeWall] = []
var _see_through: Node
var _interior: Node


func _ready() -> void:
	_mat = load(GLADE_MAT) as ShaderMaterial
	# whinbek.tscn carries its own Sun and WorldEnvironment so it is worth opening on its own for
	# judging geometry. Inside this wrapper they would be a second sun and a second environment —
	# two directional lights double every highlight and the later WorldEnvironment silently wins.
	_silence_inner_lighting()
	_skin_ground()
	_collect_walls(_subject)
	# Props are respawned by every rebuild, so re-skin on the signal rather than once here. Doing it
	# once looks right until the first time anything touches a wall, and then silently un-does itself.
	for w in _walls:
		if not w.rebuilt.is_connected(_skin_props):
			w.rebuilt.connect(_skin_props.bind(w))
		_skin_props(w)
	var cam := get_node_or_null("FlyCam") as Camera3D
	if cam != null:
		cam.look_at(Vector3(0.0, 4.0, 0.0), Vector3.UP)
	_see_through = SeeThroughScript.new()
	_see_through.name = "SeeThrough"
	add_child(_see_through)
	_interior = InteriorViewScript.new()
	_interior.name = "InteriorView"
	add_child(_interior)
	_interior.call("setup", _see_through, get_node_or_null("CameraRig"))
	_build_ui()
	_apply_sun()
	_set_mode(false)


## Switch off whatever lighting the instanced subject brought with it, so this scene's Sun and
## Environment are the only ones in play.
func _silence_inner_lighting() -> void:
	_silence(_subject)


func _silence(n: Node) -> void:
	if n is DirectionalLight3D:
		(n as DirectionalLight3D).visible = false
	elif n is WorldEnvironment:
		(n as WorldEnvironment).environment = null
	for c in n.get_children():
		_silence(c)


## The ground gets the painted shader too, on a DUPLICATE so it can keep its own colour. You cannot
## judge a shadow terminator without a surface for the shadow to fall on, and a ground on a
## different lighting model than the building it sits under makes every judgement about the building
## wrong.
func _skin_ground() -> void:
	var ground := _subject.find_child("Mesh", true, false) as MeshInstance3D
	if ground == null:
		return
	var gm := (load(GLADE_MAT) as ShaderMaterial).duplicate() as ShaderMaterial
	gm.set_shader_parameter("use_vertex_color", false)   # a BoxMesh has no COLOR_0: it would be white
	# THE SUBJECT'S OWN GROUND COLOUR, if it set one. This used to be hardcoded to whinbek's green,
	# which put an Alsatian lawn under an adobe compound the first time a second scene reused this
	# script. A look-dev skins the ground so shadows have somewhere to fall; it does not get to
	# decide what the ground IS.
	var was := ground.material_override if ground.material_override else ground.mesh.surface_get_material(0)
	var tint := Color(0.44, 0.47, 0.35)
	if was is StandardMaterial3D:
		tint = (was as StandardMaterial3D).albedo_color
	gm.set_shader_parameter("albedo_color", tint)
	ground.material_override = gm


func _collect_walls(n: Node) -> void:
	if n is GladeWall:
		_walls.append(n as GladeWall)
	for c in n.get_children():
		_collect_walls(c)


## Put the painted shader on this wall's socketed props. The bricks already have it from the style;
## these are imported .glb scenes carrying whatever material Blender exported, and left alone they
## sit on a painted building looking like plastic stickers.
##
## `get_children(true)` — the `true` is load-bearing. Generated children are added with
## INTERNAL_MODE_BACK, and the default get_children() does not return internal nodes at all.
func _skin_props(w: GladeWall) -> void:
	for c in w.get_children(true):
		_skin_meshes(c)
	for c in w.get_children():
		if c is GladeRoof:
			for rc in (c as GladeRoof).get_children(true):
				_skin_meshes(rc)


func _skin_meshes(n: Node) -> void:
	# MultiMeshInstance3D is deliberately skipped: those are the bricks, and they already carry the
	# style's material. Overriding them here would work today and break the moment a style differs.
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = _mat
	for c in n.get_children(true):
		_skin_meshes(c)


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
	# The see-through belongs to WALK: there is no player to keep in view while flying, and leaving
	# it running would punch a hole around wherever the player happens to be standing off-screen.
	if _see_through != null:
		_see_through.set_process(walk)
		if not walk:
			_see_through._disable()
	if _interior != null:
		_interior.set_process(walk)
		if not walk:
			_interior.call("_leave")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The rig's camera, which is the one WALK mode looks through.
func _rig_cam() -> Camera3D:
	var rig := get_node_or_null("CameraRig")
	return rig.get_node_or_null("Camera3D") as Camera3D if rig != null else null


func _refresh_mode_button() -> void:
	if _mode_button != null:
		_mode_button.text = ("Switch to FLY  (Tab)" if _walking else "Switch to WALK  (Tab)")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_TAB:
		_set_mode(not _walking)
		_refresh_mode_button()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _fps == null:
		return
	_fps.text = "%d fps   %d verts drawn" % [
		Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]


func _apply_sun() -> void:
	_sun.rotation_degrees = Vector3(-_sun_pitch, _sun_yaw, 0.0)


func _save_material() -> void:
	var err := ResourceSaver.save(_mat, GLADE_MAT)
	print("save %s -> %s" % [GLADE_MAT, "OK" if err == OK else error_string(err)])


func _rebuild_all() -> void:
	for w in _walls:
		w.rebuild()


func _build_ui() -> void:
	var box := Tuning.build_panel(self)

	_fps = Label.new()
	box.add_child(_fps)
	var help := Label.new()
	help.text = "TAB fly/walk\nfly: RMB look · WASD · Q/E up-down · Shift fast"
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)

	# The one knob that decides whether a downward-facing shingle is a colour or a black hole.
	Tuning.header(box, "PAINTED — LIGHT")
	Tuning.slider(box, "wrap", 0.0, 1.0, 0.01, _mat.get_shader_parameter("wrap"),
			func(v: float) -> void: _mat.set_shader_parameter("wrap", v))
	Tuning.slider(box, "bands (0 = smooth)", 0.0, 8.0, 1.0, _mat.get_shader_parameter("bands"),
			func(v: float) -> void: _mat.set_shader_parameter("bands", v))
	Tuning.slider(box, "band_softness", 0.01, 1.0, 0.01,
			_mat.get_shader_parameter("band_softness"),
			func(v: float) -> void: _mat.set_shader_parameter("band_softness", v))

	Tuning.header(box, "PAINTED — SHADOW")
	Tuning.color(box, "shade_tint", _mat.get_shader_parameter("shade_tint"),
			func(c: Color) -> void: _mat.set_shader_parameter("shade_tint", c))
	Tuning.slider(box, "shade_strength", 0.0, 1.0, 0.01,
			_mat.get_shader_parameter("shade_strength"),
			func(v: float) -> void: _mat.set_shader_parameter("shade_strength", v))
	Tuning.slider(box, "shade_saturation", 0.0, 2.0, 0.05,
			_mat.get_shader_parameter("shade_saturation"),
			func(v: float) -> void: _mat.set_shader_parameter("shade_saturation", v))

	Tuning.header(box, "PAINTED — SUNLIT")
	Tuning.color(box, "light_tint", _mat.get_shader_parameter("light_tint"),
			func(c: Color) -> void: _mat.set_shader_parameter("light_tint", c))
	Tuning.slider(box, "light_tint_amount", 0.0, 1.0, 0.05,
			_mat.get_shader_parameter("light_tint_amount"),
			func(v: float) -> void: _mat.set_shader_parameter("light_tint_amount", v))

	Tuning.header(box, "SUN")
	Tuning.slider(box, "energy", 0.0, 6.0, 0.05, _sun.light_energy,
			func(v: float) -> void: _sun.light_energy = v)
	Tuning.slider(box, "softness (deg)", 0.0, 15.0, 0.25, _sun.light_angular_distance,
			func(v: float) -> void: _sun.light_angular_distance = v)
	Tuning.slider(box, "pitch (deg)", 5.0, 88.0, 1.0, _sun_pitch,
			func(v: float) -> void:
				_sun_pitch = v
				_apply_sun())
	Tuning.slider(box, "yaw (deg)", -180.0, 180.0, 1.0, _sun_yaw,
			func(v: float) -> void:
				_sun_yaw = v
				_apply_sun())
	Tuning.color(box, "sun colour", _sun.light_color,
			func(c: Color) -> void: _sun.light_color = c)
	# Godot's default 2.0 offsets the shadow further than a 0.4 m timber wall is thick, so light
	# creeps along interior seams. Same trap as the other lookdev.
	Tuning.slider(box, "shadow_normal_bias", 0.0, 2.0, 0.05, _sun.shadow_normal_bias,
			func(v: float) -> void: _sun.shadow_normal_bias = v)

	Tuning.header(box, "WORLD")
	var e := _env.environment
	Tuning.slider(box, "ambient energy", 0.0, 3.0, 0.05, e.ambient_light_energy,
			func(v: float) -> void: e.ambient_light_energy = v)
	Tuning.slider(box, "ambient sky contribution", 0.0, 1.0, 0.05,
			e.ambient_light_sky_contribution,
			func(v: float) -> void: e.ambient_light_sky_contribution = v)
	Tuning.color(box, "ambient colour", e.ambient_light_color,
			func(c: Color) -> void: e.ambient_light_color = c)
	Tuning.slider(box, "exposure", 0.2, 3.0, 0.05, e.tonemap_exposure,
			func(v: float) -> void: e.tonemap_exposure = v)
	Tuning.check(box, "SSAO", e.ssao_enabled, func(on: bool) -> void: e.ssao_enabled = on)
	Tuning.slider(box, "ssao intensity", 0.0, 4.0, 0.1, e.ssao_intensity,
			func(v: float) -> void: e.ssao_intensity = v)
	Tuning.slider(box, "ssao radius", 0.1, 2.0, 0.05, e.ssao_radius,
			func(v: float) -> void: e.ssao_radius = v)
	# THE COLOUR ADJUSTMENT WAS TUNED BLIND. scenes/main.tscn has run contrast and saturation since
	# the game's environment was built; this panel never showed them, so the look-dev and the game
	# drifted apart without anybody being able to see it happen. Measured against the reference,
	# saturation was most of the missing chroma on the lit side.
	Tuning.check(box, "adjustment", e.adjustment_enabled,
			func(on: bool) -> void: e.adjustment_enabled = on)
	Tuning.slider(box, "contrast", 0.5, 2.0, 0.01, e.adjustment_contrast,
			func(v: float) -> void: e.adjustment_contrast = v)
	Tuning.slider(box, "saturation", 0.0, 2.0, 0.01, e.adjustment_saturation,
			func(v: float) -> void: e.adjustment_saturation = v)

	Tuning.header(box, "PAINTED — SHADOW (cast)")
	# How much of the shade tint survives inside a cast shadow. Not a taste knob: at 0 the tint
	# lights the inside of a sealed building. See painted_env.gdshader.
	Tuning.slider(box, "shade_occlusion", 0.0, 1.0, 0.05,
			_mat.get_shader_parameter("shade_occlusion"),
			func(v: float) -> void: _mat.set_shader_parameter("shade_occlusion", v))

	Tuning.header(box, "GRADE (post)")
	var grade := get_node_or_null("PainterlyGrade/Rect") as ColorRect
	if grade != null:
		var gm := grade.material as ShaderMaterial
		Tuning.check(box, "enabled", grade.visible, func(on: bool) -> void: grade.visible = on)
		Tuning.slider(box, "split_strength", 0.0, 1.0, 0.01,
				gm.get_shader_parameter("split_strength"),
				func(v: float) -> void: gm.set_shader_parameter("split_strength", v))
		Tuning.slider(box, "vignette", 0.0, 1.0, 0.01,
				gm.get_shader_parameter("vignette_strength"),
				func(v: float) -> void: gm.set_shader_parameter("vignette_strength", v))
		# These two have to AGREE with the surface shader's shade_tint and light_tint above, or the
		# grade spends its strength undoing what the shading just did — which is exactly what was
		# happening while the grade's shadow was teal and the shader's was blue-violet.
		Tuning.color(box, "grade shadow_tint", gm.get_shader_parameter("shadow_tint"),
				func(c: Color) -> void: gm.set_shader_parameter("shadow_tint", c))
		Tuning.color(box, "grade highlight_tint", gm.get_shader_parameter("highlight_tint"),
				func(c: Color) -> void: gm.set_shader_parameter("highlight_tint", c))

	Tuning.header(box, "KUWAHARA (post)")
	var kuwa := get_node_or_null("PostFX/Kuwahara") as ColorRect
	if kuwa != null:
		var km := kuwa.material as ShaderMaterial
		Tuning.check(box, "enabled", kuwa.visible, func(on: bool) -> void: kuwa.visible = on)
		Tuning.slider(box, "radius (px)", 1.0, 10.0, 1.0, km.get_shader_parameter("radius"),
				func(v: float) -> void: km.set_shader_parameter("radius", int(v)))
		Tuning.slider(box, "strength", 0.0, 1.0, 0.05, km.get_shader_parameter("strength"),
				func(v: float) -> void: km.set_shader_parameter("strength", v))

	Tuning.header(box, "CAMERA")
	var cam := get_node_or_null("FlyCam") as Camera3D
	if cam != null:
		Tuning.slider(box, "fov", 20.0, 100.0, 1.0, cam.fov,
				func(v: float) -> void: cam.fov = v)
		Tuning.slider(box, "fly speed", 1.0, 60.0, 0.5, cam.get("speed"),
				func(v: float) -> void: cam.set("speed", v))
		Tuning.button(box, "Frame like the game (53°)", func() -> void:
			cam.current = true
			cam.fov = 45.0
			var d := 22.0
			cam.global_position = Vector3(0.0, d * sin(0.93), d * cos(0.93))
			cam.look_at(Vector3(0.0, 3.0, 0.0), Vector3.UP))

	Tuning.header(box, "MODE")
	_mode_button = Tuning.button(box, "", func() -> void:
		_set_mode(not _walking)
		_refresh_mode_button())
	_refresh_mode_button()

	# ORTHOGRAPHIC, on the WALK camera. The game is played down a fixed ~53 degree rig, and at that
	# angle a perspective frustum quietly lies about a building: walls lean, and how much of the far
	# side you can see depends on where in the frame it sits. Ortho is how the reference paintings
	# are drawn and how the massing should be judged. `size` is the height of the view in METRES,
	# which is why it has nothing to do with fov.
	var rc := _rig_cam()
	if rc != null:
		Tuning.check(box, "orthographic (walk)", rc.projection == Camera3D.PROJECTION_ORTHOGONAL,
				func(on: bool) -> void:
					rc.projection = (Camera3D.PROJECTION_ORTHOGONAL if on
							else Camera3D.PROJECTION_PERSPECTIVE))
		Tuning.slider(box, "ortho size (m)", 4.0, 40.0, 0.5, rc.size,
				func(v: float) -> void: rc.size = v)

	# SEE-THROUGH. scripts/see_through.gd, and the companion note in scripts/roof_fade.gd explains
	# why a GladeKit building needs a fragment test where a modelled one needs a faded node.
	Tuning.header(box, "SEE-THROUGH (walk)")
	Tuning.slider(box, "hole radius (m)", 0.0, 6.0, 0.1, _see_through.radius,
			func(v: float) -> void: _see_through.radius = v)
	Tuning.slider(box, "aim height (m)", 0.0, 3.0, 0.1, _see_through.target_height,
			func(v: float) -> void: _see_through.target_height = v)

	Tuning.header(box, "GLADEKIT")
	Tuning.button(box, "Rebuild all walls", _rebuild_all)
	Tuning.button(box, "Save material to painted_glade.tres", _save_material)

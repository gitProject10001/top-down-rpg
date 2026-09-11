extends Node3D
## test_pixelart -- a 3D medieval camp rendered to read as hand-drawn pixel art.
##
## THE SHAPE OF IT. Everything 3D lives inside a SubViewport that renders at a fraction of the
## window (960x540 at 1080p), and a SubViewportContainer blows that up with NEAREST filtering. The
## pixel grid is therefore the render resolution -- not a shader effect stamped over a full-res
## image, which is what pixelate-in-post gives you and why that always looks like a filter. Inside
## the viewport the scene is ordinary lit 3D with full PBR maps; the last thing drawn is a
## full-screen quad (shaders/pixelart/pixel_post.gdshader) that inks the outlines from depth and
## normals and snaps every pixel to a 64-colour palette.
##
## TWO PROJECT SETTINGS HAD TO BE OVERRIDDEN HERE, and they are the traps to know about.
## project.godot turns on TAA (rendering/anti_aliasing/quality/use_taa=true) and 2x MSAA globally.
## Both are correct for the main game and both are fatal here: TAA blends the previous frame in, so
## every hard pixel edge smears into a two-frame ghost, and MSAA softens exactly the stair-steps
## that pixel art is made of. The SubViewport turns both off for itself. Nothing global is changed.
##
## RUNNING IT
##   Godot_console.exe --path . --resolution 1920x1080 res://scenes/dev/test_pixelart.tscn
##       -- [--shot=res://...png] [--free] [--nopost] [--raw] [--shrink=N]
##
##   --shot=<png>  render one settled frame, save it, quit. WINDOWED ONLY -- a --headless run never
##                 completes a frame, so it would save a black image (or hang waiting for one).
##   --free        fly camera instead of the iso follow cam, for inspecting geometry.
##   --nopost      hide the post quad: raw lit 3D, unpalettised. The A/B that tells a geometry
##                 problem from a shader one.
##   --raw         keep the post pass but drop the palette (palette_mix = 0), which separates
##                 "the colours are wrong" from "the lighting is wrong".
##   --shrink=N    render at 1/N of the window instead of the scene's default.
##
## LIVE CONTROLS. Run the scene and every dial that decides the look is a slider, top-left:
## exposure, contrast, saturation, split toning, the whole outline group, palette mix and dither,
## the light energies, and the ground shader. TAB hides the panel, F10 saves a numbered frame, and
## PRINT VALUES dumps the current settings to the console in .tres syntax so a good state can be
## pasted straight back into assets/materials/pixelart/post.tres.

const SHOT_SETTLE_FRAMES := 12

@onready var _container: SubViewportContainer = $Pixel
@onready var _view: SubViewport = $Pixel/View
@onready var _cam: Camera3D = $Pixel/View/IsoCam
@onready var _post: MeshInstance3D = $Pixel/View/IsoCam/PostPixel
@onready var _fire: OmniLight3D = $Pixel/View/Fire

var _fire_base_energy := 0.0
var _shot_path := ""
var _shot_frames := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--shrink="):
			_container.stretch_shrink = maxi(1, int(a.trim_prefix("--shrink=")))
		elif a == "--nopost":
			_post.visible = false
		elif a == "--raw":
			_set_post_param(&"palette_mix", 0.0)
		elif a == "--free":
			_free_camera()

	# The camera needs the REAL row count to size a pixel, and the SubViewport has not been laid out
	# yet in _ready() -- the container sets its size from its own rect, which arrives with the first
	# resize notification. Ask again once that has happened.
	_view.size_changed.connect(_push_pixel_rows)
	_push_pixel_rows()

	if _fire != null:
		_fire_base_energy = _fire.light_energy

	if _shot_path != "":
		# Give the renderer time to settle: shaders compile on first use, the SubViewport sizes
		# itself on the first resize, and SSAO needs a frame or two of history.
		_shot_frames = SHOT_SETTLE_FRAMES
	else:
		# Only when a human is driving. A --shot run wants nothing drawn over the frame it saves.
		_build_tuner()


func _process(delta: float) -> void:
	_flicker(delta)
	if _shot_path == "":
		return
	_shot_frames -= 1
	if _shot_frames <= 0:
		_save_shot()


## HEARTH FLICKER. Two incommensurate frequencies so the loop never becomes audible to the eye --
## the same trick shaders/painted_env.gdshader uses for wind. A single sine reads as a pulse.
func _flicker(delta: float) -> void:
	if _fire == null or _fire_base_energy <= 0.0:
		return
	var t := Time.get_ticks_msec() * 0.001
	var f := 1.0 + 0.10 * sin(t * 7.3) + 0.06 * sin(t * 11.7) + 0.04 * sin(t * 2.9)
	_fire.light_energy = _fire_base_energy * f


func _push_pixel_rows() -> void:
	if _cam != null and _cam.has_method("set") and "pixel_rows" in _cam:
		_cam.pixel_rows = _view.size.y


func _set_post_param(name: StringName, value: Variant) -> void:
	var mat := _post.get_surface_override_material(0)
	if mat == null:
		mat = _post.material_override
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter(name, value)


## Swap the iso cam for scripts/dev/fly_camera.gd, keeping the post quad -- the point of --free is
## to look at the pixel-art scene from elsewhere, not to look at a different scene.
func _free_camera() -> void:
	var script := load("res://scripts/dev/fly_camera.gd")
	if script == null:
		push_warning("[PIXELART] --free: scripts/dev/fly_camera.gd not found, keeping the iso cam")
		return
	_cam.set_script(script)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 50.0


func _save_shot() -> void:
	# The SubViewport's own texture, not the window's: that is the 640x360 art, before the nearest
	# upscale. Saving the window instead would bake the display scale into the file and make two
	# renders taken on different monitors incomparable.
	await RenderingServer.frame_post_draw
	var img := _view.get_texture().get_image()
	var path := _shot_path
	var dir := path.get_base_dir()
	if dir.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var err := img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	if err != OK:
		push_error("[PIXELART] could not write %s (%d)" % [path, err])
	else:
		print("[PIXELART] wrote %s  %dx%d" % [path, img.get_width(), img.get_height()])
	_shot_path = ""
	get_tree().quit(0 if err == OK else 1)


# ---------------------------------------------------------------------------- live controls ----
## The slider panel. Built in code rather than added to the .tscn: it is a debugging aid, and a
## debugging aid that lives in the scene file is one more thing to remember to take out before
## committing. See scripts/dev/test_pixelart/look_panel.gd.
func _build_tuner() -> void:
	var script: Script = load("res://scripts/dev/test_pixelart/look_panel.gd")
	if script == null:
		push_warning("[PIXELART] look_panel.gd not found; running without live controls")
		return
	var panel: CanvasLayer = CanvasLayer.new()
	panel.set_script(script)
	panel.post_material = _post_mat()
	panel.post_quad = _post
	panel.container = _container
	panel.sun = get_node_or_null("Pixel/View/Sun")
	panel.fire = _fire
	var ground := get_node_or_null("Pixel/View/Ground") as MeshInstance3D
	if ground != null:
		panel.ground_material = ground.get_surface_override_material(0) as ShaderMaterial
	add_child(panel)


func _post_mat() -> ShaderMaterial:
	var mat := _post.get_surface_override_material(0)
	if mat == null:
		mat = _post.material_override
	return mat as ShaderMaterial


## F10 still saves a numbered frame -- the one shortcut worth keeping, because it is the thing you
## want the instant a slider lands somewhere good.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_F10:
			_snap_now()


func _snap_now() -> void:
	await RenderingServer.frame_post_draw
	var dir := "res://scenes/dev/test_pixelart/renders"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := 0
	var path := ""
	while true:
		path = "%s/live_%02d.png" % [dir, n]
		if not FileAccess.file_exists(path):
			break
		n += 1
	var err := _view.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("[PIXELART] %s %s" % ["wrote" if err == OK else "FAILED to write", path])

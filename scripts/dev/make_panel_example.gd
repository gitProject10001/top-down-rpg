extends SceneTree
## Builds the PANEL example pair, once, so there is something that works to look at and edit:
##
##   assets/materials/glade_panel_stone.tres   a StandardMaterial3D — swap its two texture slots
##   addons/gladekit/styles/panel_stone.tres   a GladeStyle in PANEL mode pointing at it
##
##   Godot_console.exe --headless --path . --script res://scripts/dev/make_panel_example.gd
func _initialize() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.022
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	n.cellular_jitter = 1.0

	var albedo := NoiseTexture2D.new()
	albedo.noise = n
	albedo.seamless = true          # or every tile boundary is a visible line
	albedo.width = 512
	albedo.height = 512

	var normal := NoiseTexture2D.new()
	normal.noise = n
	normal.seamless = true
	normal.width = 512
	normal.height = 512
	normal.as_normal_map = true
	normal.bump_strength = 12.0

	var mat := StandardMaterial3D.new()
	mat.resource_name = "GladePanelStone"
	mat.albedo_texture = albedo
	mat.albedo_color = Color(0.78, 0.73, 0.63)
	mat.normal_enabled = true
	mat.normal_texture = normal
	mat.normal_scale = 1.4
	mat.roughness = 0.92
	var mp := "res://assets/materials/glade_panel_stone.tres"
	print("[MAKE] material: %s" % error_string(ResourceSaver.save(mat, mp)))

	var st: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres").duplicate()
	st.resource_name = "PanelStone"
	st.wall_mode = GladeStyle.WallMode.PANEL
	st.panel_uv_scale = 2.0
	st.material = load(mp)
	var sp := "res://addons/gladekit/styles/panel_stone.tres"
	print("[MAKE] style:    %s" % error_string(ResourceSaver.save(st, sp)))
	quit(0)

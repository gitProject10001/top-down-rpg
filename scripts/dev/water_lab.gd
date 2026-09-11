extends "res://scripts/dev/wilds_walk.gd"
## THE WATER BENCH: wilds_walk with a small EAGER map, a painted lake, and the player standing
## on its west shore — the water milestones' measuring ground. Same controls as the walk bench
## (TAB fly/walk, right-stick orbit). The seed is pinned: a bench that rerolls its subject
## measures nothing. Eager (stream off) because the bench teleports the player straight to the
## shore, a spot no spawn ring would have warmed.

const LAKE := Rect2i(30, 30, 10, 7)           ## cells — a 20 x 14 m pond near the map centre
## The river: a 3-cell channel running west out of the lake. Its cells keep whatever tier the
## noise gave them, so it descends as a STAIRCASE — each same-tier run is its own flat region
## with a spill edge between, which is exactly the shape flow, waterfalls and downstream drift
## all need to be visible at once. A closed pond can only ever show eddies.
## Five cells wide, not three: the bed's shallow/deep split is decided per grid CORNER, so in
## a 3-wide channel every corner touches dry and the whole stream bakes as foamy shore.
const RIVER_ROWS := Vector2i(31, 36)          ## z range, exclusive end
const RIVER_X := Vector2i(12, 30)             ## x range, exclusive end — west of the lake

## The depth-aware surface, by path rather than class_name - water_window.gd declares neither, and
## the swe bench preloads it the same way.
const WaterWindow := preload("res://addons/sim_water/scripts/water_window.gd")

var _field_view: TextureRect = null
var _flow_view := false                       ## show the flow solver instead of the wave field


func _ready() -> void:
	var authored := WildsMap.new()
	authored.seed = 7
	authored.cells_w = 64
	authored.cells_h = 64
	for cz in range(LAKE.position.y, LAKE.end.y):
		for cx in range(LAKE.position.x, LAKE.end.x):
			authored.set_flag(authored.idx(Vector2i(cx, cz)), WildsMap.F_WATER)
	for cz in range(RIVER_ROWS.x, RIVER_ROWS.y):
		for cx in range(RIVER_X.x, RIVER_X.y):
			authored.set_flag(authored.idx(Vector2i(cx, cz)), WildsMap.F_WATER)
	# THE SOURCE. Without one the solver has an exact fixed point at rest, which is the right
	# answer to the wrong question: a river with a waterfall in it must be carrying water from
	# somewhere to somewhere. The spring sits at the far END of the channel so the water has
	# the whole reach to cross before it spills — but INSIDE the 64 m solver window,
	# because a source the window cannot see is a source that does not exist.
	for cz in range(RIVER_ROWS.x, RIVER_ROWS.y):
		var si := authored.idx(Vector2i(RIVER_X.x + 4, cz))
		authored.set_flag(si, authored.flag_at(si) | WildsMap.F_SPRING)
	# A LAKE WORTH SIMULATING. The generator's default puts the mid-water bed 0.9 m below the tier
	# top and the surface 0.35 m below it, so every painted lake in the world was 0.55 m deep - a
	# puddle, and by coincidence the exact bed_depth the swe bench had been using, for the same
	# reason nobody had noticed. 2.6 m gives a 2.25 m column: deep enough that the surface reads as
	# water rather than as wet ground, and that a wave has somewhere to go.
	#
	# THIS IS AFFORDABLE BECAUSE OF THE STAGGERED REWRITE and not before it. The scheme is explicit,
	# so it is stable while kappa = g*h*dt^2/dx^2 stays under its limit, and that limit went from
	# 0.25 to 0.5 when the velocity moved to the faces - 3.67 m of water to 7.34 m, measured 6/8.
	# 1.39 m of bed against a 0.35 m surface drop is a 1.04 m column - nearly double the 0.55 m
	# every lake in this world used to be, and still WADEABLE, which is not a preference.
	#
	# 2.6 was tried and it drowned the player on the first run. There is no swim state in this game
	# at all, and three separate files say so in passing: terrain_field ("no swimming logic, no
	# per-frame water-level query, and no depth test"), raft.gd stepping a rider off into the water
	# because "every water in this world is wadeable", and the wilds suite asserting the sea is
	# wadeable so nobody can walk off the map. A lake deeper than a person is a gameplay change.
	authored.lake_depth = 1.39
	map = authored
	stream = false
	super._ready()
	# ---- THE SOLVER THIS BENCH EXISTS TO WATCH.
	#
	# depth over a bed, on a staggered grid, over terrain the WILDS ADDON GENERATED - not a bench
	# bed pretending. That is the whole point of running the lab through wilds_walk: the solver is
	# fed the same painted map, the same tiers and the same shoreline the game builds, through the
	# same SweTerrain seam, so what passes here is a statement about the game and not about a
	# synthetic pan.
	#
	# The guard stays ON. This is the bench a person leaves running, and an explicit scheme walking
	# off its CFL limit does not wobble, it saturates float16 and never comes back.
	Ripples.depth_mode = true
	Ripples.staggered = true
	Ripples.advect = true
	Ripples.sim_set(&"cfl_guard", true)
	# ---- POLICY, and it is policy rather than physics: every probe that measures the scheme runs
	# with both of these at their neutral values.
	#
	# SLOWER WAVES. c = sqrt(g*h) is 4.7 m/s on 2.25 m of water, which crosses this 20 m pond in
	# four seconds - correct, and on a screen it reads as a puddle twitching rather than as a lake.
	# 0.35 puts it at 2.8 m/s. It also buys CFL headroom rather than spending it, because kappa is
	# linear in g.
	Ripples.sim_set(&"wave_scale", 0.35)
	# AND THE GRID-SCALE SHIMMER GOES. A Laplacian of the SURFACE, so it is exactly zero on a flat
	# lake however the bed varies underneath, damping as k^2: at the two-texel mode the neighbours'
	# mean differs from the centre by the whole amplitude, at twenty texels by about one per cent.
	# The shimmer dies in a third of a second and a wave you can see does not.
	# 0.30 rather than the 0.02 a bare k^2 filter could afford, because the AMPLITUDE GATE below
	# keeps it off anything with a shape. A two-texel shimmer is inside the gate and dies in a step
	# or two; a wave is fifty times outside it and never sees the filter at all.
	Ripples.sim_set(&"smooth_grid", 0.30)
	Ripples.sim_set(&"ripple_kill", 0.008)
	# THE LAKE MUST BE THE SAME LAKE TOMORROW. Measured, the shipped configuration lost 7.95 % of
	# this lake in one minute of play - visibly receding, gone in twelve - because seepage and the
	# window's own horizon rim are two ~120 m3/min terms pulling opposite ways and the lake settled
	# wherever they happened to balance. 1/30 per second draws it back to the level the map
	# authored, slowly enough that no wave notices and firmly enough that nothing accumulates.
	Ripples.sim_set(&"level_keep", 0.033)
	# ---- AND THE SURFACE THAT CAN DRAW IT.
	#
	# The wilds draw water as a FLAT PLANE PER REGION at a fixed height, deciding where water is
	# from a baked depth texture and treating the solver as a small displacement on top. Every one
	# of those is right for the encoding it was built for and wrong for this one: hand that shader a
	# 2.25 m absolute depth where it expects a centimetre-scale deviation and it saturates into a
	# flat pale sheet - which is exactly what the first photograph of this bench showed, with a
	# correct simulation running underneath it.
	#
	# WaterWindow is the surface that reads the depth encoding: one camera-following grid whose
	# every vertex sits at bed + h, discarding where there is no water, with Beer-Lambert absorption
	# so depth is visible. It goes on TOP of the region planes here rather than replacing them,
	# because replacing them is a change to the game and this is a bench - the far planes keep
	# theirs and the window covers the 64 m the solver actually simulates.
	var win := WaterWindow.new()
	win.name = "WaterWindow"
	add_child(win)
	# AND THE FLAT PLANES GO. They are not merely redundant under the window - they are WRONG under
	# it, because water_stylized reads R as a deviation from a fixed height and the depth encoding
	# stores an absolute column there. Left on, the lake photographs as a solid white sheet with a
	# correct simulation running invisibly beneath.
	#
	# Hidden rather than deleted: they are what the rest of the world still draws with, and this
	# bench covers only the 64 m the solver actually simulates.
	call_deferred("_hide_region_planes")


## Turn off the wilds' per-region water planes wherever the solver window covers them. Deferred and
## repeated, because the zone streams: a region built after this runs would arrive with its plane
## visible and put a white patch in the middle of a simulated lake.
func _hide_region_planes() -> void:
	for n in get_tree().get_nodes_in_group("wilds_water_plane"):
		var mi := n as MeshInstance3D
		if mi != null:
			mi.visible = false
	_stand_on_shore()
	_spawn_raft()


## The bench's subject is the lake, not wherever the generator's spawn landed — put the player
## a cell and a half west of the waterline, facing in.
func _stand_on_shore() -> void:
	var zone := get_tree().get_first_node_in_group("zone") as Node3D
	if zone == null:
		return
	var terrain := zone.get_node_or_null("Terrain") as Node3D
	var m: WildsMap = zone.get("built_map")
	if terrain == null or m == null:
		return
	var shore := Vector2(float(LAKE.position.x) - 1.5,
			float(LAKE.position.y) + LAKE.size.y * 0.5) * m.cell_size
	var player := $Player as Node3D
	# +1.2, the zone's own SpawnA offset (wilds_zone.gd:133) — NOT a token hand's clearance.
	# The body's origin rides ~1.07 m ABOVE its feet, so dropping the ROOT to ground + 0.3
	# buries the feet three quarters of a metre inside the terrain, and a chunk collider is a
	# hollow ConcavePolygonShape3D: the body does not stand on it, it falls straight through.
	player.global_position = zone.to_global(terrain.position
			+ Vector3(shore.x, terrain.height_at(shore) + 1.2, shore.y))


## WA4: the raft floats mid-lake, a few strides from the shore spot — board with E, sail with
## the move stick, E again near a shore to step off.
func _spawn_raft() -> void:
	var zone := get_tree().get_first_node_in_group("zone") as Node3D
	if zone == null:
		return
	var terrain := zone.get_node_or_null("Terrain") as Node3D
	var m: WildsMap = zone.get("built_map")
	if terrain == null or m == null:
		return
	var raft := (load("res://scenes/props/raft.tscn") as PackedScene).instantiate() as Node3D
	add_child(raft)
	var mid := Vector2(float(LAKE.position.x) + LAKE.size.x * 0.5,
			float(LAKE.position.y) + LAKE.size.y * 0.5) * m.cell_size
	raft.global_position = zone.to_global(terrain.position + Vector3(mid.x, 0.0, mid.y))


# ---------------------------------------------------------------- ripple-field debug --------
# The measuring instruments the WA2 verification asks for: a poke on demand (time a ring
# against the 2 m cell grid — it should cross one cell in 0.8 s at c = 2.5), the raw field as
# a grey card (still water = mid grey; any tint at rest is an encoding bug), and a frame-time
# readout to price the sim (expect < 0.1 ms of delta with the field on).

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_R:
				# By GROUP, not by $Player: boarding the raft reparents the body under the
				# deck, and the fixed path stops resolving the moment the bench gets
				# interesting.
				var p := get_tree().get_first_node_in_group("player") as Node3D
				if p != null:
					Ripples.splash(p.global_position, 0.6, 0.3)
				get_viewport().set_input_as_handled()
				return
			KEY_F:
				_toggle_field_view()
				get_viewport().set_input_as_handled()
				return
			KEY_G:
				# Swap the overlay between the SOLVER's state (R eta, GB velocity, A foam)
				# and its TERRAIN INPUT (RG baked current, B rest depth, A the region rest
				# level — the staircase the weirs read).
				_flow_view = not _flow_view
				if _field_view == null:
					_toggle_field_view()
				else:
					_field_view.visible = true
				get_viewport().set_input_as_handled()
				return
			KEY_P:
				print("[WaterLab] process %.2f ms · fps %d" % [
						Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
						int(Performance.get_monitor(Performance.TIME_FPS))])
				get_viewport().set_input_as_handled()
				return
	super._unhandled_input(event)


func _process(delta: float) -> void:
	super._process(delta)
	# The ping-pong swaps textures every tick — track the live front, not a stale half.
	if _field_view != null and _field_view.visible:
		_field_view.texture = Ripples.field_texture() if _flow_view else Ripples.debug_texture()


func _toggle_field_view() -> void:
	if _field_view == null:
		var layer := CanvasLayer.new()
		layer.name = "FieldView"
		layer.layer = 41
		add_child(layer)
		_field_view = TextureRect.new()
		_field_view.position = Vector2(10.0, 48.0)
		_field_view.custom_minimum_size = Vector2(256.0, 256.0)
		_field_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_field_view.stretch_mode = TextureRect.STRETCH_SCALE
		layer.add_child(_field_view)
	else:
		_field_view.visible = not _field_view.visible


func _hint() -> void:
	super._hint()
	var layer := get_node_or_null("Hint")
	if layer == null:
		return
	var label := Label.new()
	label.text = "water: R ring at player · F wave field · G flow solver (RG velocity, B foam) · P frame time"
	label.position = Vector2(10.0, 26.0)
	label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 0.55))
	label.add_theme_font_size_override("font_size", 13)
	layer.add_child(label)

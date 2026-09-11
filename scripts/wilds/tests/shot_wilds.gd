extends SceneTree
## Photograph the wilds zone, from the game's own camera pitch.
##
##   Godot_console.exe --path . --resolution 1280x720 --script res://scripts/wilds/tests/shot_wilds.gd -- \
##       --out=C:/some/folder
##
## Four subjects, each answering a question the suites cannot:
##
##   wide     — the whole map. Do the terraces read as Direland ground (stepped masses under
##              forest) rather than as a contour plot?
##   terrace  — close on a cliff run with a ramp in it. Is the ramp obviously the way up?
##   water    — a lake region. Does the surface sit in its basin, foam at the shore?
##   floor    — two metres from trees and grass. Does the forest floor read as UNDER the trees?
##
## The zone scene carries no light or sky of its own (the World provides them in game), so this
## harness brings a sun and a plain procedural sky — photography equipment, not shipping look.

const PITCH := 53.0

var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var zone := (load("res://scenes/world/zone_wilds.tscn") as PackedScene).instantiate()
	# An AUTHORED map, not a bare seed: water is painted, never derived, so a fresh map has no
	# lake to photograph. One blob near the north-west quarter is enough.
	var authored := WildsMap.new()
	authored.seed = 42
	for wz in range(14, 20):
		for wx in range(38, 47):
			authored.set_flag(authored.idx(Vector2i(wx, wz)), authored.flag_at(authored.idx(Vector2i(wx, wz))) | WildsMap.F_WATER)
	zone.set("map", authored)
	zone.set("stream", false)      # photographs frame the WHOLE map; streaming would leave
	root.add_child(zone)           # everything beyond the spawn ring unbuilt
	current_scene = zone

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	root.add_child(sun)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	cam.far = 600.0
	for _i in 30:
		await process_frame

	var m: WildsMap = zone.built_map
	var d: Dictionary = zone.derived
	var terrain := zone.get_node("Terrain") as Node3D
	# World position of a cell centre, through the zone park offset and the terrain centring.
	var at := func(c: Vector2i) -> Vector3:
		var y := (d.tiers as PackedInt32Array)[m.idx(c)] * m.tier_height
		return (zone as Node3D).position + terrain.position \
				+ Vector3((c.x + 0.5) * m.cell_size, y, (c.y + 0.5) * m.cell_size)

	# --- wide: the whole map --------------------------------------------------------------------
	var centre := Vector2i(m.cells_w / 2, m.cells_h / 2)
	_aim(cam, at.call(centre), 150.0)
	await _settle(20)
	_save("wilds_wide")

	# --- terrace + water: the GROUND is the subject — a canopy over it hides exactly what these
	# two shots exist to show, so the forest steps aside for them.
	var flora := zone.get_node("Flora") as Node3D
	flora.visible = false
	var ramp_cell := centre
	for i: int in (d.ramps as Dictionary):
		ramp_cell = Vector2i(i % m.cells_w, i / m.cells_w)
		break
	_aim(cam, at.call(ramp_cell), 26.0)
	await _settle(15)
	_save("wilds_terrace")

	if not (d.regions as Array).is_empty():
		var best: Dictionary = d.regions[0]
		for region: Dictionary in d.regions:
			if (region.cells as Array).size() > (best.cells as Array).size():
				best = region
		var b: Rect2i = best.bounds
		_aim(cam, at.call(b.position + b.size / 2), 30.0)
		await _settle(15)
		_save("wilds_water")
	flora.visible = true

	# --- floor: standing among the trees, facing AWAY from the return portal beside the spawn ---
	var sp: Vector2i = d.spawn
	var ground: Vector3 = at.call(sp)
	cam.global_position = ground + Vector3(-6.0, 1.6, 1.5)
	cam.look_at(ground + Vector3(3.0, 1.0, -2.0))
	cam.fov = 50.0
	await _settle(20)
	_save("wilds_floor")

	quit(0)


func _aim(cam: Camera3D, at: Vector3, dist: float) -> void:
	cam.global_position = at + Vector3(0.0, sin(deg_to_rad(PITCH)) * dist,
			cos(deg_to_rad(PITCH)) * dist)
	cam.look_at(at)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _save(stem: String) -> void:
	var path := _out + stem + ".png"
	print("[WILDS SHOT] %s (%s)" % [path,
			"ok" if root.get_texture().get_image().save_png(path) == OK else "FAILED"])

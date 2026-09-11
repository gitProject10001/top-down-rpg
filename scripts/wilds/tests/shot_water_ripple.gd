extends SceneTree
## Photograph the RIPPLE FIELD (WA2): the painted lake before any impulse (must look exactly
## like the pre-field water — the flat field contributes zero), then a poke at the lake centre
## photographed twice, 0.35 s and 1.1 s later. Between the two shots the ring front should
## travel ~1.9 m at c = 2.5 m/s — measure it against the 2 m cell grid on the shore.
##
##   Godot_console.exe --path . --resolution 1280x720 \
##       --script res://scripts/wilds/tests/shot_water_ripple.gd -- --out=C:/some/folder

const PITCH := 53.0

var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var zone := (load("res://scenes/world/zone_wilds.tscn") as PackedScene).instantiate()
	var authored := WildsMap.new()
	authored.seed = 7
	authored.cells_w = 64
	authored.cells_h = 64
	for wz in range(30, 37):
		for wx in range(30, 40):
			authored.set_flag(authored.idx(Vector2i(wx, wz)), WildsMap.F_WATER)
	# A channel west out of the lake. It keeps the noise's tiers, so it steps down as a
	# staircase of flat reaches — the shape a current and a waterfall need to be visible.
	# FIVE cells wide, not three: the bed's shallow/deep split is decided per grid CORNER, and
	# in a 3-wide channel every corner touches dry ground, so the whole thing bakes as shore —
	# foam edge to edge before flow has said anything. Five leaves a deep middle to look at.
	for wz in range(31, 36):
		for wx in range(12, 30):
			authored.set_flag(authored.idx(Vector2i(wx, wz)), WildsMap.F_WATER)
	# THE SOURCE. Without one the solver has an exact fixed point at rest, which is the right
	# answer to the wrong question: a river with a waterfall in it must be carrying water from
	# somewhere to somewhere. The spring sits at the far END of the channel so the water has
	# the whole reach to cross before it spills — but INSIDE the 64 m solver window,
	# because a source the window cannot see is a source that does not exist.
	for cz in range(31, 36):
		var si := authored.idx(Vector2i(16, cz))
		authored.set_flag(si, authored.flag_at(si) | WildsMap.F_SPRING)
	zone.set("map", authored)
	zone.set("stream", false)
	root.add_child(zone)
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
	root.add_child(sun)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	cam.far = 600.0
	# The zone's _ready (and its synchronous build) runs once the tree starts turning — read
	# nothing of it before these frames pass, shot_wilds' own hard-learned order.
	for _i in 30:
		await process_frame

	var m: WildsMap = zone.built_map
	var d: Dictionary = zone.derived
	var terrain := zone.get_node("Terrain") as Node3D
	var lake_c := Vector2i(35, 33)
	var tier: int = (d.tiers as PackedInt32Array)[m.idx(lake_c)]
	var surface := tier * m.tier_height - WildsGen.SURFACE_DROP
	var centre: Vector3 = (zone as Node3D).position + terrain.position \
			+ Vector3((lake_c.x + 0.5) * m.cell_size, surface, (lake_c.y + 0.5) * m.cell_size)

	_aim(cam, centre, 24.0)
	await _settle(40)
	_save("ripple_0_still")

	# By identifier the autoload is invisible here — a --script file compiles before the
	# project registers its globals — but the singleton itself stands in the tree as usual.
	var ripples := root.get_node("/root/Ripples")
	ripples.set("debug_log", true)
	print("[WILDS SHOT] frames: physics %d process %d" % [Engine.get_physics_frames(),
			Engine.get_process_frames()])
	ripples.splash(centre, 0.6, 0.3)
	var trace := ""
	for f in 14:
		await process_frame
		var im: Image = (ripples.debug_texture() as Texture2D).get_image()
		trace += "%.3f " % im.get_pixel(256, 141).r
	print("[WILDS SHOT] dent texel per frame: %s(steps %d)" % [trace,
			int(ripples.get("debug_steps"))])
	print("[WILDS SHOT] field R after poke: %s" % str(_field_minmax(ripples)))
	await _settle(18)                       # ~0.35 s: the rebound ring is young and tight
	_save("ripple_1_young")
	await _settle(45)                       # ~1.1 s total: the front ~1.9 m further out
	print("[WILDS SHOT] field R at spread: %s" % str(_field_minmax(ripples)))
	_save("ripple_2_spread")

	# The full splash package (WA3): droplet burst + foam ring accent + field ring, framed
	# close while the droplets are still in the air.
	_aim(cam, centre, 14.0)
	root.get_node("/root/Fx").splash(centre, 1.2)
	ripples.splash(centre, 0.8, 0.2)
	await _settle(9)
	_save("ripple_3_splash")

	# WA4: the raft. Spawn mid-lake (it must snap itself to the surface), then shove it west
	# shore-ward, re-topping the velocity each frame so drag cannot win: it should trail wake
	# rings and RUN AGROUND in the shallows — FLOATING mode treats the rising bed as a wall.
	var raft := (load("res://scenes/props/raft.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(raft)
	raft.global_position = centre + Vector3(2.0, 0.0, 0.0)
	await _settle(5)
	_aim(cam, centre + Vector3(-4.0, 0.0, 0.0), 18.0)
	for _i in 90:
		raft.set("velocity", Vector3(-4.5, 0.0, 0.0))
		await process_frame
	_save("ripple_4_raft")
	print("[WILDS SHOT] raft rests at %.2f m from lake centre, y %.2f (surface %.2f)"
			% [(raft.global_position - centre).length(), raft.global_position.y, centre.y])

	# THE RIVER (WB1/WB2): the channel from above, framed wide enough to show the staircase of
	# reaches, the current running down it, and where foam gathers.
	var river: Vector3 = (zone as Node3D).position + terrain.position \
			+ Vector3(21.0 * m.cell_size, surface, 33.5 * m.cell_size)
	_aim(cam, river, 34.0)
	await _settle(20)
	_save("flow_1_river")
	print("[WILDS SHOT] flow samples: %s" % _flow_line(zone, terrain, m))

	# RIPPLES RIDE THE CURRENT (WB4). Poke still-ish water, then watch the disturbance's
	# CENTROID move: if advection is working it drifts downstream at the local flow speed,
	# and if it is not it stays exactly where it was put.
	var probe := centre
	var drift_flow: Vector2 = (root.get_node("/root/Water") as Node).flow_at(probe)
	# THE ADVECTION A/B (WB4). Advection is OFF by default; this is the measurement that
	# decided that, and the one any future BFECC pass has to beat. Amplitude is the number
	# that matters, not the drift: a ring that has been diffused below the noise floor has
	# not travelled anywhere, it has died.
	var here := Vector2(probe.x, probe.z)
	var drifted := []
	for on: bool in [false, true]:
		ripples.set("advect", on)
		await _settle(70)                   # let the previous ring die away first
		ripples.splash(probe, 0.7, 0.3)
		await _settle(4)
		var c0 := _field_centroid(ripples, here, 5.0)
		await _settle(36)                   # ~0.6 s, i.e. 36 sim steps
		var c1 := _field_centroid(ripples, here, 5.0)
		drifted.append(INF if not c0.is_finite() or not c1.is_finite()
				else (c1 - c0).length())
		print("[WILDS SHOT]   advect=%s amplitude after 0.6 s: %s"
				% [str(on), str(_field_minmax(ripples))])
	print("[WILDS SHOT] ring drift over 0.6 s: advect OFF %.2f m, ON %.2f m; local flow "
			% [drifted[0], drifted[1]]
			+ "(%.2f, %.2f) = %.2f m/s" % [drift_flow.x, drift_flow.y, drift_flow.length()])

	# What the SOLVER is actually producing, before judging it by eye.
	var fl_img: Image = (ripples.debug_texture() as Texture2D).get_image()
	# Measured over WET texels only — dry ground is zeroed by the solver and would drown the
	# averages, which is what "foam mean 0.026" was really saying the first time.
	var vmax := 0.0
	var fmax := 0.0
	var favg := 0.0
	var white := 0
	var n := 0
	for y in range(0, fl_img.get_height(), 3):
		for x in range(0, fl_img.get_width(), 3):
			var px := fl_img.get_pixel(x, y)
			var sp := Vector2(px.g, px.b).length()
			vmax = maxf(vmax, sp)
			if sp <= 0.0001 and px.a <= 0.0001:
				continue                      # dry
			n += 1
			fmax = maxf(fmax, px.a)
			favg += px.a
			if px.a > 0.3:
				white += 1
	if n > 0:
		print("[WILDS SHOT] solver over %d wet texels: |v| max %.2f, foam max %.2f, "
				% [n, vmax, fmax] + "mean %.3f, %d%% visibly white"
				% [favg / float(n), white * 100 / n])

	# THE SPILL (WB3): frame the river's own tier step close, where the sheet hangs and the
	# plunge pool below it is being rung continuously by waterfall.gd.
	var falls := terrain.find_child("Waterfalls", true, false) as Node3D
	if falls != null and falls.get_child_count() > 0:
		var best: Node3D = falls.get_child(0)
		for f: Node3D in falls.get_children():
			# The one furthest down the channel reads best: more water below it to ring.
			if f.position.x < best.position.x:
				best = f
		_aim(cam, (falls as Node3D).to_global(best.position), 11.0)
		await _settle(25)
		_save("flow_2_waterfall")
		print("[WILDS SHOT] %d falls; framed one at local %s" % [falls.get_child_count(),
				str(best.position.round())])
	else:
		print("[WILDS SHOT] NO WATERFALLS BUILT")

	# The field's own card, straight from the sim. Heights are stored zero-centred in metres,
	# so a PNG of it clips every trough to black — the numbers above are the measurement, this
	# is only the shape of the wave.
	var img: Image = (ripples.debug_texture() as Texture2D).get_image()
	print("[WILDS SHOT] field card %s" % ("ok" if img != null
			and img.save_png(_out + "ripple_field_raw.png") == OK else "FAILED"))
	quit(0)


## What the current actually reads along the channel, so the picture is not the only evidence:
## tier, then the flow vector the world would push a body with, sampled every four cells.
func _flow_line(zone: Node3D, terrain: Node3D, m: WildsMap) -> String:
	var water := root.get_node("/root/Water")
	var out := ""
	for cx in [14, 18, 22, 26, 30, 34]:
		var local := Vector2(cx + 0.5, 33.5) * m.cell_size
		var w: Vector3 = zone.to_global(terrain.position + Vector3(local.x, 0.0, local.y))
		var f: Vector2 = water.flow_at(w)
		out += "x%d(%.2f,%.2f) " % [cx, f.x, f.y]
	return out


## Where the disturbance IS, in world metres: the |height|-weighted centroid of the field.
## Advection has to be measured, not admired — a ring drifting two metres is invisible in a
## still frame and unmistakable in this number.
func _field_centroid(ripples: Node, near: Vector2, radius: float) -> Vector2:
	var img: Image = (ripples.debug_texture() as Texture2D).get_image()
	var origin: Vector2 = ripples.window_origin()
	var size: float = ripples.SIZE_M
	var sum := Vector2.ZERO
	var wsum := 0.0
	for y in range(0, 512, 2):
		for x in range(0, 512, 2):
			var w := absf(img.get_pixel(x, y).r)
			if w < 0.004:
				continue                      # ignore the quiet field, weight the ring
			# LOCAL ONLY. The map's waterfalls are ringing their own plunge pools inside this
			# same window, and a whole-field centroid measures those too — it read a 1.39 m
			# "drift" for a 0.16 m one before this radius was here.
			var p := origin + Vector2(x, y) / 512.0 * size
			if p.distance_to(near) > radius:
				continue
			sum += p * w
			wsum += w
	if wsum <= 0.0:
		# NOT Vector2.ZERO: that is a real world position ~700 m from the lake, and returning
		# it turned a quiet field into a 704 m "drift" in this very harness.
		return Vector2(INF, INF)
	return sum / wsum


## Coarse min/max of the field's R channel, in METRES — still water reads (0.0, 0.0) and any
## live wave spreads the pair (a fresh poke ~-0.28, its rebound crest ~+0.08). The probe the
## "measure, don't eyeball" rule asks for.
func _field_minmax(ripples: Node) -> Vector2:
	var img: Image = (ripples.debug_texture() as Texture2D).get_image()
	var lo := 1.0
	var hi := 0.0
	for y in range(0, 512, 4):
		for x in range(0, 512, 4):
			var r := img.get_pixel(x, y).r
			lo = minf(lo, r)
			hi = maxf(hi, r)
	return Vector2(lo, hi)


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

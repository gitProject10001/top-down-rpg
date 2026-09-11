extends SceneTree
## Do the falls actually ring the pool they land in? Checks each fall's resolved plunge point
## is over WATER and inside the solver window, then watches eta near one of them.


func _initialize() -> void:
	var lab := (load("res://scenes/dev/water_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in 60:
		await process_frame
	var rip := root.get_node("/root/Ripples")
	var wat := root.get_node("/root/Water")
	var zone := get_first_node_in_group("zone") as Node3D
	var falls := (zone.get_node("Terrain") as Node3D).find_child("Waterfalls", true, false)
	if falls == null:
		print("[PLUNGE] no falls")
		quit(1)
	# A/B: the script's discrete pokes vs the weir's continuous line source alone.
	var poke_off := OS.get_cmdline_user_args().has("--noscript")
	if poke_off:
		for f: Node3D in falls.get_children():
			f.set("strength", 0.0)
	print("[PLUNGE] script pokes: %s" % ("OFF" if poke_off else "ON"))
	var org: Vector2 = rip.window_origin()
	var wet := 0
	var inw := 0
	var n := 0
	var probe := Vector3.INF
	for f: Node3D in falls.get_children():
		var p: Vector3 = f.to_global(f.get("foot_local"))
		n += 1
		if wat.depth_at(p) > 0.01:
			wet += 1
		var rel := Vector2(p.x, p.z) - org
		if rel.x >= 0.0 and rel.y >= 0.0 and rel.x <= 64.0 and rel.y <= 64.0:
			inw += 1
			if not probe.is_finite():
				probe = p
	print("[PLUNGE] %d falls: %d land in water, %d inside the solver window" % [n, wet, inw])
	if not probe.is_finite():
		print("[PLUNGE] none in window — nothing can ring")
		quit(1)
	# Watch eta within 3 m of one plunge point: it must be continuously disturbed, not still.
	for k in 4:
		for _i in 45:
			await process_frame
		var img: Image = (rip.debug_texture() as Texture2D).get_image()
		var o: Vector2 = rip.window_origin()
		var lo := 1e9
		var hi := -1e9
		for y in range(0, 512, 2):
			for x in range(0, 512, 2):
				var w := o + Vector2(x, y) / 512.0 * 64.0
				if w.distance_to(Vector2(probe.x, probe.z)) > 3.0:
					continue
				var e := img.get_pixel(x, y).r
				lo = minf(lo, e)
				hi = maxf(hi, e)
		print("[PLUNGE] t=%.1fs  eta near the foot: %.4f .. %.4f" % [(k + 1) * 0.75, lo, hi])
	quit(0)

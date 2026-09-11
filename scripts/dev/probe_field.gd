extends SceneTree
## WD1 GATE: is the terrain field texture right, and is the tier staircase in its A channel a
## clean STEP rather than a ramp? If A is smeared, the solver cannot tell a weir from a slope
## and the gravity term detonates across it.


func _initialize() -> void:
	var lab := (load("res://scenes/dev/water_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in 45:
		await process_frame

	var rip := root.get_node("/root/Ripples")
	var t0 := Time.get_ticks_usec()
	rip.call("_refresh_field", rip.window_origin() + Vector2(9.0, 9.0))
	print("[WD1] bake of %d texels took %.1f ms"
			% [64 * 64, (Time.get_ticks_usec() - t0) / 1000.0])

	var o: Vector2 = rip.window_origin()
	for m in [1, 2, 4]:
		var t1 := Time.get_ticks_usec()
		rip.call("_refresh_field", o + Vector2(float(m), 0.0))
		rip.call("_refresh_field", o + Vector2(float(m) * 2.0, 0.0))
		print("[WD1] %d m step re-bake: %.2f ms" % [m, (Time.get_ticks_usec() - t1) / 1000.0])
	var tex: Texture2D = rip.call("field_texture")
	if tex == null:
		print("[WD1] NO FIELD TEXTURE")
		quit(1)
	var img := tex.get_image()
	print("[WD1] format %d size %s" % [img.get_format(), str(img.get_size())])

	# Inventory the A channel: distinct rest-surface levels, and how many texels are dry.
	var levels := {}
	var dry := 0
	var wet := 0
	var h_max := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a < -900.0:
				dry += 1
			else:
				wet += 1
				levels["%.3f" % px.a] = int(levels.get("%.3f" % px.a, 0)) + 1
				h_max = maxf(h_max, px.b)
	var keys: Array = levels.keys()
	keys.sort()
	print("[WD1] %d wet texels, %d dry; rest depth max %.3f m" % [wet, dry, h_max])
	print("[WD1] distinct rest surfaces: %s" % str(keys))
	for k in keys:
		print("[WD1]   Y=%s -> %d texels" % [k, levels[k]])

	# THE STEP TEST: scan a row and report the largest jump between neighbouring WET texels.
	# A tier is 1.2 m. A crisp staircase jumps by ~1.2 in ONE texel; a ramp would show a
	# sequence of ~0.15 m nudges, which is what filter_linear would have produced.
	var worst := 0.0
	var steps := 0
	for y in img.get_height():
		for x in range(img.get_width() - 1):
			var a := img.get_pixel(x, y).a
			var b := img.get_pixel(x + 1, y).a
			if a < -900.0 or b < -900.0:
				continue
			var d := absf(b - a)
			if d > 0.001:
				steps += 1
				worst = maxf(worst, d)
	print("[WD1] %d wet/wet neighbour pairs differ in level; largest single-texel jump %.3f m"
			% [steps, worst])
	quit(0)

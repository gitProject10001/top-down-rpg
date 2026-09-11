extends SceneTree
## Does the water brush's DIG-THEN-FILL actually produce a basin? Applies the canvas's own
## formula (new_paint = current_paint + target - final) over a disc that spans several tiers,
## then re-derives and asks the generator what it made.


func _initialize() -> void:
	var m := WildsMap.new()
	m.seed = 42
	m.cells_w = 64
	m.cells_h = 64
	var d0 := WildsGen.derive_light(m)
	var t0: PackedInt32Array = d0.tiers

	# A disc deliberately placed where the terrain is NOT flat.
	var centre := Vector2i(32, 32)
	var radius := 6
	var cells: Array[Vector2i] = []
	var before := {}
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if Vector2(dx, dz).length() > float(radius) + 0.01:
				continue
			var c := centre + Vector2i(dx, dz)
			cells.append(c)
			before["%d" % t0[m.idx(c)]] = true
	print("[BRUSH] before: the disc spans tiers %s" % str(before.keys()))

	# The brush, exactly as wilds_canvas applies it: level to the FIRST cell's tier, then flag.
	var target: int = t0[m.idx(cells[0])]
	for c in cells:
		var i := m.idx(c)
		var final_t: int = t0[i]
		if final_t != target:
			m.set_tier_paint(i, m.tier_paint_at(i) + target - final_t)
		m.set_flag(i, m.flag_at(i) | WildsMap.F_WATER)

	var d := WildsGen.derive_light(m)
	var t: PackedInt32Array = d.tiers
	var after := {}
	var off := 0
	for c in cells:
		var tv: int = t[m.idx(c)]
		after["%d" % tv] = true
		if tv != target:
			off += 1
	print("[BRUSH] after:  the disc spans tiers %s (%d cells off target %d)"
			% [str(after.keys()), off, target])

	# The real question is not "are the numbers equal" but "is it ONE POOL".
	var regions := 0
	var mine := {}
	for c in cells:
		var r: int = int((d.region_of as Dictionary).get(m.idx(c), -1))
		if r >= 0:
			mine["%d" % r] = true
	regions = mine.size()
	print("[BRUSH] the painted water forms %d region(s): %s" % [regions, str(mine.keys())])

	# And no cliff may stand inside it: a segment whose cell AND low neighbour are both ours.
	var inner_cliffs := 0
	var owned := {}
	for c in cells:
		owned[m.idx(c)] = true
	for s: Dictionary in (d.segments as Array):
		var sc: Vector2i = s.cell
		var nb: Vector2i = sc + (s.side as Vector2i)
		if owned.has(m.idx(sc)) and m.in_bounds(nb) and owned.has(m.idx(nb)):
			inner_cliffs += 1
	print("[BRUSH] cliff faces standing INSIDE the basin: %d" % inner_cliffs)
	quit(0 if off == 0 and regions == 1 and inner_cliffs == 0 else 1)

extends SceneTree
## Headless verification for the wilds landscape generator. Run:
##   Godot_console.exe --headless --path . --script res://scripts/wilds/tests/verify_wilds.gd
## Results also written to user://verify_wilds.txt. Non-zero exit code on any failure.
## Same crash-detection idiom as every other suite in this project: a runtime error inside a
## suite unwinds silently, so the count is asserted at the end.

const EXPECTED_SUITES := 19
const SEEDS := [5, 7, 42, 137, 20260825]

var _fails: Array[String] = []
var _log := ""
var _suites_done := 0


func _initialize() -> void:
	_determinism_suite()
	_winding_suite()
	_quantisation_suite()
	_collider_suite()
	_reachability_suite()
	_roundtrip_suite()
	_locality_suite()
	_water_suite()
	_water_query_suite()
	_flow_suite()
	_flora_suite()
	_sockets_suite()
	_service_suite()
	_equivalence_suite()
	_border_suite()
	await _streaming_suite()
	await _giant_suite()
	await _walk_bench_suite()
	await _zone_suite()

	if _suites_done != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported done — one crashed silently"
				% [_suites_done, EXPECTED_SUITES])
	var f := FileAccess.open("user://verify_wilds.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log)
	if _fails.is_empty():
		_say("[VERIFY] WILDS PASS")
		quit(0)
	else:
		for line in _fails:
			_say("[VERIFY] FAIL: " + line)
		quit(1)


func _map_for(s: int) -> WildsMap:
	var m := WildsMap.new()
	m.seed = s
	m.cells_w = 48
	m.cells_h = 48
	return m


## Every derived number and triangle, folded to one value.
func _fold(d: Dictionary) -> int:
	var parts: Array = [d.tiers, d.spawn, d.min_tier, d.max_tier, d.auto_ramps, d.shelves]
	var ramp_keys: Array = (d.ramps as Dictionary).keys()
	ramp_keys.sort()
	for k in ramp_keys:
		parts.append([k, d.ramps[k]])
	for chunk: Dictionary in d.chunks:
		parts.append(chunk.faces)
	return hash(parts)


func _determinism_suite() -> void:
	for s in SEEDS:
		var a := WildsGen.derive(_map_for(s))
		var b := WildsGen.derive(_map_for(s))
		if _fold(a) != _fold(b):
			_fails.append("seed %d: two derivations disagree" % s)
	# The LIGHT path (what the canvas and the stroke check consume) must be the full path
	# minus `chunks`, key for key — the paint surface and the mesh must see one landscape.
	var full := WildsGen.derive(_map_for(42))
	var light := WildsGen.derive_light(_map_for(42))
	var same: bool = full.has("chunks") and not light.has("chunks") \
			and light.size() == full.size() - 1
	for k in light:
		if not full.has(k) or hash(light[k]) != hash(full[k]):
			same = false
	_check(same, "derive_light diverges from derive minus the mesh")
	_done("determinism suite: %d seeds derive identically twice, light path agrees"
			% SEEDS.size())


## THE WINDING LAW, asserted not trusted: for every triangle the cross (b-a)x(c-a) must OPPOSE
## the stored outward normal (Godot front faces are clockwise about it).
func _winding_suite() -> void:
	var d := WildsGen.derive(_map_for(42))
	var tris := 0
	var bad := 0
	for chunk: Dictionary in d.chunks:
		for surface in [chunk.top, chunk.cliff]:
			var v: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = surface[Mesh.ARRAY_NORMAL]
			for i in range(0, v.size(), 3):
				tris += 1
				var cross := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
				if cross.dot(n[i]) >= 0.0:
					bad += 1
	_check(tris > 100, "suspiciously few triangles: %d" % tris)
	_check(bad == 0, "%d of %d triangles wind with their outward normal — backface-culled "
			% [bad, tris] + "ground")
	_done("winding suite: %d triangles all clockwise about their outward normal" % tris)


## Discrete altitude is the whole point: every vertex Y is a whole number of tiers (ramp
## vertices sit on tier tops too — only the SURFACE between them slopes), and every ramp
## bridges exactly one tier.
func _quantisation_suite() -> void:
	var m := _map_for(42)
	var d := WildsGen.derive(m)
	var off := 0
	for chunk: Dictionary in d.chunks:
		for surface in [chunk.top, chunk.cliff]:
			var v: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
			for p in v:
				var q := p.y / m.tier_height
				if absf(q - roundf(q)) > 0.001:
					off += 1
	_check(off == 0, "%d vertices off the tier lattice" % off)
	var bad_ramps := 0
	for i in (d.ramps as Dictionary):
		var c := Vector2i(i % m.cells_w, i / m.cells_w)
		var nb: Vector2i = c + (d.ramps[i] as Vector2i)
		if not m.in_bounds(nb) \
				or (d.tiers as PackedInt32Array)[m.idx(nb)] \
				!= (d.tiers as PackedInt32Array)[i] + 1:
			bad_ramps += 1
	_check(bad_ramps == 0, "%d ramps do not bridge exactly one tier" % bad_ramps)
	_done("quantisation suite: every vertex on the 1.2 m lattice, every ramp bridges one tier")


## Collision IS the render triangles — byte equality, not a tolerance.
func _collider_suite() -> void:
	var m := _map_for(7)
	for cz in range(20, 26):
		for cx in range(20, 26):
			m.set_flag(m.idx(Vector2i(cx, cz)), WildsMap.F_WATER)
	var d := WildsGen.derive(m)
	for chunk: Dictionary in d.chunks:
		var expect := PackedVector3Array()
		expect.append_array((chunk.top as Array)[Mesh.ARRAY_VERTEX])
		expect.append_array((chunk.cliff as Array)[Mesh.ARRAY_VERTEX])
		expect.append_array(chunk.wall)
		if chunk.faces != expect:
			_fails.append("chunk %s: collision faces differ from render triangles + sea wall"
					% str(chunk.origin))
		# This map is a CLIFFS border: nothing may pay for a wall it does not need.
		if (chunk.wall as PackedVector3Array).size() > 0:
			_fails.append("chunk %s: a cliff-bordered map grew a sea wall" % str(chunk.origin))
	_done("collider suite: every chunk's shape is its render triangles plus the sea wall, "
			+ "byte for byte — no lid, the bed is the water's own collider")


## WATER: painted cells form regions, each with one surface level below every adjacent dry
## top and a bed carved under the surface that IS the collider — no lid, wading is the
## contract; a river chain stepping a tier becomes separate regions.
func _water_suite() -> void:
	var m := _map_for(42)
	# A lake on whatever tier the noise put there, and a two-reach river across a tier edge:
	# find a boundary between different tiers and paint water on both sides.
	for cz in range(10, 14):
		for cx in range(10, 14):
			m.set_flag(m.idx(Vector2i(cx, cz)), WildsMap.F_WATER)
	var d0 := WildsGen.derive(_map_for(42))
	var edge := Vector2i(-1, -1)
	for cz in range(2, 46):
		for cx in range(2, 45):
			var a := (d0.tiers as PackedInt32Array)[cz * 48 + cx]
			var b := (d0.tiers as PackedInt32Array)[cz * 48 + cx + 1]
			if a != b and Vector2i(cx, cz).distance_to(Vector2i(12, 12)) > 8:
				edge = Vector2i(cx, cz)
				break
		if edge.x >= 0:
			break
	_check(edge.x >= 0, "no tier edge found to lay a river across")
	if edge.x >= 0:
		m.set_flag(m.idx(edge), WildsMap.F_WATER)
		m.set_flag(m.idx(edge + Vector2i(1, 0)), WildsMap.F_WATER)
	var d := WildsGen.derive(m)
	var regions: Array = d.regions
	_check(regions.size() >= 3, "expected a lake + two river reaches, got %d regions"
			% regions.size())
	var tiers: PackedInt32Array = d.tiers
	for region: Dictionary in regions:
		var surface: float = float(region.tier) * m.tier_height - WildsGen.SURFACE_DROP
		for i in (region.cells as Array):
			var c := Vector2i(i % m.cells_w, i / m.cells_w)
			for dir in WildsGen.DIRS:
				var nb: Vector2i = c + dir
				if not m.in_bounds(nb) or (m.flag_at(m.idx(nb)) & WildsMap.F_WATER) != 0:
					continue
				# A shore at the water's own tier (or above) must stand proud of the surface.
				# LOWER ground across the holding cliff is allowed — that is a terrace pond
				# seen from below, contained by its own rim face.
				if tiers[m.idx(nb)] >= tiers[m.idx(c)]:
					_check(surface < tiers[m.idx(nb)] * m.tier_height + 0.001,
							"water at %s floods its level shore %s" % [c, nb])
	# The fence is GONE (the wading milestone): no collision vertex may stand at the old lid
	# plane — surface + 1.6, an off-lattice height nothing else produces — and the beds ARE
	# the collider: every region shows its shore bed (tier*th - BED_SHALLOW), and somewhere a
	# region wide enough for interior corners carves its deep bed (tier*th - BED_DEEP). Both
	# bed offsets are off the 1.2 m lattice too, so a hit can only be water geometry.
	var heights := {}
	for chunk: Dictionary in d.chunks:
		for p in (chunk.faces as PackedVector3Array):
			heights["%.3f" % p.y] = true
	var deep_somewhere := false
	for region: Dictionary in regions:
		var old_lid := "%.3f" % (float(region.tier) * m.tier_height \
				- WildsGen.SURFACE_DROP + 1.6)
		_check(not heights.has(old_lid), "a lid survives at %s for a region on tier %d"
				% [old_lid, region.tier])
		var shore := "%.3f" % (float(region.tier) * m.tier_height - WildsGen.BED_SHALLOW)
		_check(heights.has(shore), "no shore bed at %s for a region on tier %d"
				% [shore, region.tier])
		if heights.has("%.3f" % (float(region.tier) * m.tier_height - WildsGen.bed_deep(m))):
			deep_somewhere = true
	_check(deep_somewhere, "no region carved a deep bed — interior corners missing everywhere")
	_done("water suite: %d regions level below their shores, beds carved and walkable, no lid"
			% regions.size())


## FLOW, derived and never solved: WildsGen.flow_at must be a pure function of
## (map, tiers, cell) — deterministic, ZERO on dry ground, pointing downhill at a spill edge,
## refusing to drive into a bank, and above all IDENTICAL between the full derivation and a
## windowed region derive. That last one is the seam law applied to currents: a river must not
## change direction because the player walked into a different chunk.
func _flow_suite() -> void:
	var m := _map_for(42)
	# A pond, and a two-tier channel running off it so there is a real spill edge.
	for cz in range(10, 16):
		for cx in range(10, 16):
			m.set_flag(m.idx(Vector2i(cx, cz)), WildsMap.F_WATER)
	var d := WildsGen.derive(m)
	var tiers: PackedInt32Array = d.tiers

	# Deterministic, and dry ground is exactly zero (not merely small).
	var again := WildsGen.derive(_map_for(42))
	var dry_nonzero := 0
	var unstable := 0
	for cz in range(4, 44):
		for cx in range(4, 44):
			var c := Vector2i(cx, cz)
			var f := WildsGen.flow_at(m, tiers, c)
			if f != WildsGen.flow_at(m, again.tiers, c):
				unstable += 1
			if not WildsGen.is_water(m, m.idx(c)) and f != Vector2.ZERO:
				dry_nonzero += 1
	_check(unstable == 0, "%d cells flow differently on a second derivation" % unstable)
	_check(dry_nonzero == 0, "%d dry cells carry a current" % dry_nonzero)

	# THE SEAM: every water cell must answer identically through a region derive, whose tiers
	# are a Dictionary over a 34-cell window rather than a whole-map array.
	var seam := 0
	var checked := 0
	for origin: Vector2i in [Vector2i(0, 0), Vector2i(0, 32), Vector2i(32, 0)]:
		var region := WildsGen.derive_region(m,
				Rect2i(origin, Vector2i(WildsGen.CHUNK, WildsGen.CHUNK)))
		for cz in range(origin.y, origin.y + WildsGen.CHUNK):
			for cx in range(origin.x, origin.x + WildsGen.CHUNK):
				var c := Vector2i(cx, cz)
				if not WildsGen.is_water(m, m.idx(c)):
					continue
				checked += 1
				if WildsGen.flow_at(m, tiers, c) != WildsGen.flow_at(m, region.tiers, c):
					seam += 1
	_check(checked > 20, "the flow seam test found only %d water cells to check" % checked)
	_check(seam == 0, "%d water cells flow differently in a region derive than in the full "
			% seam + "one — the seam law is broken for currents")

	# A SPILL EDGE PULLS DOWNHILL. Find a water cell with a lower neighbour and assert the
	# current has a positive component toward it.
	var spills := 0
	var wrong_way := 0
	for i: int in (d.region_of as Dictionary):
		var c := Vector2i(i % m.cells_w, i / m.cells_w)
		for dir: Vector2i in WildsGen.DIRS:
			var nb: Vector2i = c + dir
			if not m.in_bounds(nb) or tiers[m.idx(nb)] >= tiers[m.idx(c)]:
				continue
			spills += 1
			# The drop term is FLOW_DROP per tier plus the land slope, against at most one
			# bank push; the component toward the drop must survive.
			if WildsGen.flow_at(m, tiers, c).dot(Vector2(dir.x, dir.y)) <= 0.0:
				wrong_way += 1
	if spills > 0:
		_check(wrong_way == 0, "%d of %d spill edges have water flowing AWAY from the drop"
				% [wrong_way, spills])

	# THE EDDY TERM IS DIVERGENCE-FREE. Curl noise can swirl but must never act as a source or
	# a sink. Measured on the eddy term ALONE: the slope term legitimately has divergence
	# (water really does pile up where the land flattens out), so mixing them proves nothing.
	# An earlier version measured the whole field on a "flat" map and read 3.0 — which was a
	# three-tier border rim, not a broken curl.
	var worst := 0.0
	var moved := 0.0
	for cz in range(12, 36):
		for cx in range(12, 36):
			var c := Vector2i(cx, cz)
			var ex1 := WildsGen._flow_eddy(m, c + Vector2i(1, 0))
			var ex0 := WildsGen._flow_eddy(m, c - Vector2i(1, 0))
			var ez1 := WildsGen._flow_eddy(m, c + Vector2i(0, 1))
			var ez0 := WildsGen._flow_eddy(m, c - Vector2i(0, 1))
			worst = maxf(worst, absf(0.5 * ((ex1.x - ex0.x) + (ez1.y - ez0.y))))
			moved = maxf(moved, WildsGen._flow_eddy(m, c).length())
	_check(moved > 0.01, "there are no eddies at all (max swirl %.4f)" % moved)
	_check(worst < 0.001, "the eddy field has divergence %.4f — curl noise must only swirl"
			% worst)

	# AND THE CURRENT REACHES THE WHOLE POOL. Every cell of a reach shares one tier, so the
	# local tier test alone leaves its middle dead still (measured: 0.05 everywhere, all
	# eddy). This holds the continuous-slope term to actually doing that work.
	var interior := 0
	var still := 0
	for i: int in (d.region_of as Dictionary):
		var c := Vector2i(i % m.cells_w, i / m.cells_w)
		var edge := false
		for dir: Vector2i in WildsGen.DIRS:
			var nb: Vector2i = c + dir
			if not m.in_bounds(nb) or not WildsGen.is_water(m, m.idx(nb)) \
					or tiers[m.idx(nb)] != tiers[m.idx(c)]:
				edge = true
		if edge:
			continue                             # banks and spills have their own terms
		interior += 1
		if WildsGen.flow_at(m, tiers, c).length() < 0.05:
			still += 1
	if interior > 0:
		_check(still == 0, "%d of %d cells mid-pool have no current at all — the slope term "
				% [still, interior] + "is not reaching past the spill edge")
	# THE SOURCE is painted, and only counts where there is water to enter: a spring flag on
	# dry ground is not a spring, it is a mistake. Same shape as every other predicate here.
	var sp_cell := Vector2i(11, 11)
	var dry_cell := Vector2i(30, 30)
	m.set_flag(m.idx(sp_cell), m.flag_at(m.idx(sp_cell)) | WildsMap.F_SPRING)
	m.set_flag(m.idx(dry_cell), m.flag_at(m.idx(dry_cell)) | WildsMap.F_SPRING)
	_check(WildsGen.is_spring(m, m.idx(sp_cell)), "a spring painted on water is not a spring")
	_check(not WildsGen.is_spring(m, m.idx(dry_cell)),
			"a spring painted on DRY ground counts as a source")
	_check(not WildsGen.is_spring(m, m.idx(Vector2i(12, 12))),
			"an unpainted water cell counts as a source")

	_done("flow suite: %d water cells agree across the seam, spills pull downhill, %d "
			% [checked, interior] + "mid-pool cells still run, eddies swirl without sources")


## THE WATER QUERY CONTRACT (the wading milestone): water_surface_y answers
## tier * th - SURFACE_DROP over any water cell and NAN over dry ground — so a caller can
## tell "no water" from "water at height zero" — and water_depth_at answers the bilinear
## column: 0.55 m over a deep interior, 0 on the wet beach, 0 on dry ground. The LAZY path
## (per-chunk derive_region, the 14 km opening) must answer exactly as the eager one.
func _water_query_suite() -> void:
	var m := _map_for(42)
	for cz in range(10, 14):
		for cx in range(10, 14):
			m.set_flag(m.idx(Vector2i(cx, cz)), WildsMap.F_WATER)
	var d := WildsGen.derive(m)
	var terrain: StaticBody3D = load("res://scripts/wilds/wilds_terrain.gd").new()
	terrain.build(m, d)
	# The lake's central grid corner (12,12): all four cells around it are painted, so the
	# bilinear bed there is BED_DEEP exactly and the column is DEEP - DROP = 0.55 m.
	var centre := Vector2(12.0, 12.0) * m.cell_size
	var tier: int = (d.tiers as PackedInt32Array)[m.idx(Vector2i(12, 12))]
	var surface := tier * m.tier_height - WildsGen.SURFACE_DROP
	_check(absf(terrain.water_surface_y(centre) - surface) < 0.001,
			"surface over the lake answers %.3f, want %.3f"
			% [terrain.water_surface_y(centre), surface])
	# Against the MAP's depth, not the engine default: lake_depth is authorable now, so a suite
	# pinned to the constant would pass on a map that overrides it and prove nothing.
	var want_deep := WildsGen.bed_deep(m) - WildsGen.SURFACE_DROP
	_check(absf(terrain.water_depth_at(centre) - want_deep) < 0.01,
			"depth at the lake centre answers %.3f, want %.3f"
			% [terrain.water_depth_at(centre), want_deep])
	# Just inside the lake's outer corner cell: every near corner touches dry, the bed stands
	# ABOVE the surface (the wet beach), and the column clamps to zero.
	var beach := Vector2(10.1, 10.1) * m.cell_size
	_check(terrain.water_depth_at(beach) < 0.005,
			"the wet beach reports %.3f m of water" % terrain.water_depth_at(beach))
	_check(not is_nan(terrain.water_surface_y(beach)),
			"the beach cell is water — its surface must still answer")
	# Dry ground: NAN surface (not zero), zero depth.
	var dry := Vector2(30.5, 30.5) * m.cell_size
	_check(is_nan(terrain.water_surface_y(dry)), "dry ground answers a surface height")
	_check(terrain.water_depth_at(dry) == 0.0, "dry ground answers %.3f m of water"
			% terrain.water_depth_at(dry))
	# OFF the map there is no water, whatever the border is doing. height_at clamps off-map
	# lookups to the edge cell by design; water must not inherit that, or a sea border would
	# report a floatable surface out over the void.
	var sea := _map_for(42)
	sea.border_mode = WildsMap.BORDER_SEA
	var st: StaticBody3D = load("res://scripts/wilds/wilds_terrain.gd").new()
	st.build(sea, WildsGen.derive(sea))
	var inside := Vector2(0.5, 24.5) * sea.cell_size
	_check(not is_nan(st.water_surface_y(inside)), "the sea's own edge cell is not water")
	for off: Vector2 in [Vector2(-3.0, 24.5), Vector2(float(sea.cells_w) + 3.0, 24.5)]:
		var p := off * sea.cell_size
		_check(is_nan(st.water_surface_y(p)), "off-map point %s answers a water surface" % p)
		_check(st.water_depth_at(p) == 0.0, "off-map point %s answers water depth" % p)
	st.free()
	# THE BED, and the invariant is depth == max(surface - bed, 0) rather than bed + depth ==
	# surface: on the WET BEACH the bed stands above the surface and the column clamps to zero, so
	# the naive form is false exactly where the shore is. All three quantities come out of
	# _bed_y_at now, and this is what keeps them there - the moment somebody recomputes the bed a
	# second way, what a body feels starts drifting from what the surface shows, which is the one
	# thing this contract exists to prevent.
	for p: Vector2 in [centre, beach]:
		var bed: float = terrain.water_bed_y(p)
		var want: float = maxf(terrain.water_surface_y(p) - bed, 0.0)
		_check(absf(terrain.water_depth_at(p) - want) < 0.001,
				"depth at %s is %.4f, but surface %.4f - bed %.4f says %.4f"
				% [p, terrain.water_depth_at(p), terrain.water_surface_y(p), bed, want])
	# ...and the beach is the case that distinguishes them: a bed PROUD of its own water surface.
	_check(terrain.water_bed_y(beach) > terrain.water_surface_y(beach),
			"the wet beach bed %.4f is not above its surface %.4f"
			% [terrain.water_bed_y(beach), terrain.water_surface_y(beach)])
	_check(terrain.water_bed_y(centre) < terrain.water_surface_y(centre),
			"the lake centre bed %.4f is not below its surface %.4f"
			% [terrain.water_bed_y(centre), terrain.water_surface_y(centre)])
	# On DRY ground the bed is the terrain itself. This is what lets a solver flood ground that
	# was never painted as water, and it is why the query cannot simply be surface minus depth.
	_check(absf(terrain.water_bed_y(dry) - terrain.height_at(dry)) < 0.001,
			"the bed on dry ground answers %.3f, but the terrain is at %.3f"
			% [terrain.water_bed_y(dry), terrain.height_at(dry)])
	# OFF the map it is a WALL, not the clamped edge cell height_at would hand back. A solver
	# reading a shelf out there would spread across it forever instead of stopping at the world.
	for off: Vector2 in [Vector2(-3.0, 24.5), Vector2(float(m.cells_w) + 3.0, 24.5)]:
		var q := off * m.cell_size
		_check(terrain.water_bed_y(q) >= Water.BED_WALL,
				"off-map bed at %s answers %.3f, not the wall" % [q, terrain.water_bed_y(q)])
	# The lazy path answers identically — same cells, no global derivation.
	var lazy: StaticBody3D = load("res://scripts/wilds/wilds_terrain.gd").new()
	lazy.build_lazy(m)
	for p: Vector2 in [centre, beach, dry]:
		var a: float = terrain.water_surface_y(p)
		var b: float = lazy.water_surface_y(p)
		if is_nan(a) != is_nan(b) or (not is_nan(a) and absf(a - b) > 0.001):
			_fails.append("lazy surface_y at %s: %.3f vs eager %.3f" % [p, b, a])
		if absf(terrain.water_depth_at(p) - lazy.water_depth_at(p)) > 0.001:
			_fails.append("lazy depth_at at %s: %.3f vs eager %.3f"
					% [p, lazy.water_depth_at(p), terrain.water_depth_at(p)])
		if absf(terrain.water_bed_y(p) - lazy.water_bed_y(p)) > 0.001:
			_fails.append("lazy bed_y at %s: %.3f vs eager %.3f"
					% [p, lazy.water_bed_y(p), terrain.water_bed_y(p)])
	terrain.free()
	lazy.free()
	_done("water query suite: surface and column answer the formula, depth = max(surface - bed, 0), "
			+ "the bed is the terrain on dry ground and a wall off-map, lazy agrees with eager")


## THE GUARANTEE: every walkable cell reaches the spawn, on every seed — and on a hostile map
## (a painted mesa three tiers up) the shelf carver still gets there.
func _reachability_suite() -> void:
	for s in SEEDS:
		var d := WildsGen.derive(_map_for(s))
		_check((d.reached as Dictionary).size() == (d.walkable as Dictionary).size(),
				"seed %d: %d of %d walkable cells unreachable" % [s, d.reached.size(),
				d.walkable.size()])
	var mesa := _map_for(42)
	for cz in range(4, 10):
		for cx in range(4, 10):
			mesa.set_tier_paint(cz * mesa.cells_w + cx, 3)
	var dm := WildsGen.derive(mesa)
	_check((dm.reached as Dictionary).size() == (dm.walkable as Dictionary).size(),
			"the painted mesa stranded %d cells" % (dm.walkable.size() - dm.reached.size()))
	_check(int(dm.auto_ramps) + int(dm.shelves) > 0, "the mesa needed no carves at all?")
	_done("reachability suite: %d seeds + one mesa, every walkable cell reaches the spawn"
			% SEEDS.size())


func _roundtrip_suite() -> void:
	var m := _map_for(137)
	m.set_tier_paint(100, 2)
	m.set_flag(200, WildsMap.F_RAMP_FORBIDDEN)
	m.set_forest(300, 180)
	m.spawn_cell = Vector2i(10, 10)
	var path := "user://verify_wilds_map.tres"
	_check(ResourceSaver.save(m, path) == OK, "map failed to save")
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as WildsMap
	_check(back != null, "map failed to load back")
	if back != null:
		_check(_fold(WildsGen.derive(m)) == _fold(WildsGen.derive(back)),
				"a loaded map derives a different landscape")
	_done("roundtrip suite: a saved map loads back and derives identically")


## EDIT LOCALITY — the seam law's payoff: painting one cell rebuilds its own chunk and leaves
## distant chunks BYTE-identical, because every corner jitters from its own world coordinates.
## Forest paint (no geometry yet) must change nothing; a tier bump that leaves reachability's
## carves untouched must change only its own chunk neighbourhood. The suite hunts for such a
## bump empirically rather than assuming one — reachability cascades are a documented
## non-locality, not a silent one.
func _locality_suite() -> void:
	var m := _map_for(42)
	var base := WildsGen.derive(m)
	m.set_forest(m.idx(Vector2i(5, 5)), 200)
	var forested := WildsGen.derive(m)
	for k in base.chunks.size():
		if (base.chunks[k] as Dictionary).faces != (forested.chunks[k] as Dictionary).faces:
			_fails.append("forest paint moved geometry in chunk %d" % k)
	m.set_forest(m.idx(Vector2i(5, 5)), 0)

	var found := false
	for cz in range(2, 30):
		for cx in range(2, 30):
			var c := Vector2i(cx, cz)
			m.set_tier_paint(m.idx(c), 1)
			var bumped := WildsGen.derive(m)
			var same_ramps: bool = str(bumped.ramps) == str(base.ramps)
			var full: bool = (bumped.reached as Dictionary).size() \
					== (bumped.walkable as Dictionary).size()
			if same_ramps and full:
				found = true
				var home := Vector2i(cx / WildsGen.CHUNK, cz / WildsGen.CHUNK)
				for k in base.chunks.size():
					var origin: Vector2i = (base.chunks[k] as Dictionary).origin
					var chunk_pos := origin / WildsGen.CHUNK
					var near: bool = absi(chunk_pos.x - home.x) <= 1 \
							and absi(chunk_pos.y - home.y) <= 1
					if not near and (base.chunks[k] as Dictionary).faces \
							!= (bumped.chunks[k] as Dictionary).faces:
						_fails.append("a bump at %s moved geometry in far chunk %s"
								% [c, origin])
				var home_k := -1
				for k in bumped.chunks.size():
					if (bumped.chunks[k] as Dictionary).origin / WildsGen.CHUNK == home:
						home_k = k
				_check(home_k >= 0 and (bumped.chunks[home_k] as Dictionary).faces \
						!= (base.chunks[home_k] as Dictionary).faces,
						"the bump changed nothing at all — the paint is not reaching the mesh")
				break
			m.set_tier_paint(m.idx(c), 0)
		if found:
			break
	_check(found, "no carve-neutral bump found in a 28x28 search — locality untestable")
	_done("locality suite: forest paint moves nothing; a tier bump stays in its neighbourhood")


## SUITE 9 — LIFE. Trees stand ON their cell's tier top and never on water, ramps or the spawn
## lane; grass dabs are baked at exact tier heights (the off-tree replay guarantee); a clearing
## silences everything; two builds are the same forest; and the ground contract answers a ramp
## honestly (mid-ramp height, tilted normal) — what GrassPatch reprojection stands on.
func _flora_suite() -> void:
	var flora_script := load("res://scripts/wilds/wilds_flora.gd")
	var terrain_script := load("res://scripts/wilds/wilds_terrain.gd")
	var m := _map_for(42)
	m.fill_forest(255)                      # a guaranteed forest
	var d := WildsGen.derive(m)

	var holder := Node3D.new()
	root.add_child(holder)                        # in-tree: the ground contract resolves
	var terrain: StaticBody3D = terrain_script.new()
	terrain.name = "Terrain"
	holder.add_child(terrain)
	terrain.build(m, d, null)
	var flora := Node3D.new()
	holder.add_child(flora)
	flora_script.build(flora, m, d, terrain, null)

	var stands := flora.get_node_or_null("PaintedTrees")
	_check(stands != null, "no PaintedTrees under the flora root")
	var trees := stands.get_children() if stands != null else []
	_check(trees.size() > 50, "a fully painted 48x48 forest grew only %d trees" % trees.size())
	var tiers: PackedInt32Array = d.tiers
	var sp: Vector2i = d.spawn
	var clear: int = flora_script.SPAWN_CLEAR_CELLS
	var misplaced := 0
	for t: Node3D in trees:
		var c := Vector2i(floori(t.position.x / m.cell_size), floori(t.position.z / m.cell_size))
		var i := m.idx(c)
		if (m.flag_at(i) & WildsMap.F_WATER) != 0 or (d.ramps as Dictionary).has(i) \
				or absf(t.position.y - tiers[i] * m.tier_height) > 0.001 \
				or (absi(c.x - sp.x) <= clear and absi(c.y - sp.y) <= clear):
			misplaced += 1
	_check(misplaced == 0, "%d trees float, drown, block a ramp or crowd the spawn" % misplaced)

	var grass := flora.get_node_or_null("WildsGrass") as GrassPatch
	_check(grass != null and grass.paint_only, "no paint_only WildsGrass under the flora root")
	if grass != null:
		_check(grass.get_node_or_null(grass.terrain) == terrain,
				"the grass patch's terrain path does not resolve to the terrain")
		_check(grass.brush_points.size() > 100,
				"a full forest laid only %d grass dabs" % grass.brush_points.size())
		var off := 0
		for k in grass.brush_points.size():
			var c := Vector2i(floori(grass.brush_points[k].x / m.cell_size),
					floori(grass.brush_points[k].y / m.cell_size))
			var i := m.idx(c)
			if (m.flag_at(i) & WildsMap.F_WATER) != 0 \
					or absf(grass.brush_heights[k] - tiers[i] * m.tier_height) > 0.001:
				off += 1
		_check(off == 0, "%d grass dabs are baked off their tier top or underwater" % off)
	var bushes := flora.get_node_or_null("WildsBushes") as BushPatch
	_check(bushes != null and bushes.paint_only, "no paint_only WildsBushes under the flora root")
	if bushes != null:
		var crowding := 0
		for k in bushes.brush_points.size():
			var c := Vector2i(floori(bushes.brush_points[k].x / m.cell_size),
					floori(bushes.brush_points[k].y / m.cell_size))
			if absi(c.x - sp.x) <= clear and absi(c.y - sp.y) <= clear:
				crowding += 1
		_check(crowding == 0, "%d bushes crowd the spawn clearing" % crowding)

	# The same seed grows the same forest.
	var flora2 := Node3D.new()
	holder.add_child(flora2)
	flora_script.build(flora2, m, d, terrain, null)
	var stands2 := flora2.get_node_or_null("PaintedTrees")
	var same: bool = stands2 != null and stands2.get_child_count() == trees.size()
	if same and not trees.is_empty():
		same = ((stands2.get_child(0) as Node3D).transform as Transform3D) \
				.is_equal_approx((trees[0] as Node3D).transform)
	_check(same, "two builds of the same map are different forests")

	# A clearing is a clearing.
	var mc := _map_for(42)
	mc.fill_forest(255)
	mc.fill_flags_or(WildsMap.F_CLEARING)
	var dc := WildsGen.derive(mc)
	var florac := Node3D.new()
	holder.add_child(florac)
	flora_script.build(florac, mc, dc, terrain, null)
	var standsc := florac.get_node_or_null("PaintedTrees")
	var grassc := florac.get_node_or_null("WildsGrass") as GrassPatch
	_check(standsc != null and standsc.get_child_count() == 0
			and grassc != null and grassc.brush_points.is_empty(),
			"an all-clearing map still grew life")

	# The ground contract on a ramp — what reprojection would stand on.
	var ramp_checked := false
	for i: int in (d.ramps as Dictionary):
		var c := Vector2i(i % m.cells_w, i / m.cells_w)
		var mid := Vector2((c.x + 0.5) * m.cell_size, (c.y + 0.5) * m.cell_size)
		var want := tiers[i] * m.tier_height + 0.5 * m.tier_height
		_check(absf(terrain.height_at(mid) - want) < 0.001,
				"mid-ramp height_at answers %.3f, the slope says %.3f"
				% [terrain.height_at(mid), want])
		_check(not terrain.normal_at(mid).is_equal_approx(Vector3.UP),
				"normal_at on a ramp answers flat")
		ramp_checked = true
		break
	_check(ramp_checked, "seed 42 derived no ramps — ground contract untested")

	# Counts are captured BEFORE the free: a freed object compares equal to null in GDScript,
	# so reading it afterwards silently reports zero instead of erroring.
	var tree_count := trees.size()
	var dab_count := grass.brush_points.size() if grass != null else 0
	holder.free()
	_done("flora suite: %d trees on their tiers, %d grass dabs baked true, clearings hold"
			% [tree_count, dab_count])


## SUITE 10 — KIT SOCKETS. With authored pieces in the style, every cliff segment grows one at
## its segment's exact edge, foot and facing; "straight_<drop>" outranks "straight"; every
## water-rim segment grows a waterfall at the spill line; and a null style grows nothing —
## the procedural face is the fallback by construction.
func _sockets_suite() -> void:
	var terrain_script := load("res://scripts/wilds/wilds_terrain.gd")
	var m := _map_for(42)
	for wz in range(14, 20):
		for wx in range(28, 37):
			m.set_flag(m.idx(Vector2i(wx, wz)), m.flag_at(m.idx(Vector2i(wx, wz))) | WildsMap.F_WATER)
	var d := WildsGen.derive(m)

	var stub_a := PackedScene.new()
	var na := Node3D.new()
	na.set_meta("kind", "A")
	stub_a.pack(na)
	na.free()
	var stub_b := PackedScene.new()
	var nb := Node3D.new()
	nb.set_meta("kind", "B")
	stub_b.pack(nb)
	nb.free()
	var style := WildsStyle.new()
	style.cliff_pieces = {"straight": stub_a, "straight_2": stub_b}
	style.waterfall_scene = stub_a

	var terrain: StaticBody3D = terrain_script.new()
	terrain.build(m, d, style)
	var pieces := terrain.get_node_or_null("CliffPieces")
	var falls := terrain.get_node_or_null("Waterfalls")
	var segs: Array = d.segments
	var water_segs := 0
	for s: Dictionary in segs:
		if (m.flag_at(m.idx(s.cell as Vector2i)) & WildsMap.F_WATER) != 0:
			water_segs += 1
	_check(pieces != null and pieces.get_child_count() == segs.size(),
			"%d cliff pieces for %d segments" % [pieces.get_child_count() if pieces else 0,
			segs.size()])
	_check(falls != null and water_segs > 0 and falls.get_child_count() == water_segs,
			"%d waterfalls for %d water-rim segments"
			% [falls.get_child_count() if falls else 0, water_segs])
	if pieces != null and pieces.get_child_count() == segs.size():
		var tiers: PackedInt32Array = d.tiers
		var bad := 0
		for k in segs.size():
			var s: Dictionary = segs[k]
			var c: Vector2i = s.cell
			var dir: Vector2i = s.side
			var p := pieces.get_child(k) as Node3D
			var want := Vector3((c.x + 0.5 + dir.x * 0.5) * m.cell_size,
					(tiers[m.idx(c)] - (s.drop as int)) * m.tier_height,
					(c.y + 0.5 + dir.y * 0.5) * m.cell_size)
			var out := -p.basis.z
			var kind_ok: bool = str(p.get_meta("kind")) \
					== ("B" if (s.drop as int) == 2 else "A")
			if not p.position.is_equal_approx(want) \
					or not out.is_equal_approx(Vector3(dir.x, 0.0, dir.y)) or not kind_ok:
				bad += 1
		_check(bad == 0, "%d cliff pieces stand off their segment's edge, foot, facing "
				% bad + "or resolution rung")
	if falls != null and falls.get_child_count() > 0:
		var tiers: PackedInt32Array = d.tiers
		var wrong := 0
		var k := 0
		for s: Dictionary in segs:
			if (m.flag_at(m.idx(s.cell as Vector2i)) & WildsMap.F_WATER) == 0:
				continue
			var f := falls.get_child(k) as Node3D
			k += 1
			var want_y: float = tiers[m.idx(s.cell as Vector2i)] * m.tier_height \
					- WildsGen.SURFACE_DROP
			if absf(f.position.y - want_y) > 0.001:
				wrong += 1
		_check(wrong == 0, "%d waterfalls hang off the spill line" % wrong)
	terrain.free()

	# A BARE STYLE STILL SPILLS. Cliff pieces need art and stay absent without it, but the
	# waterfall is generated now (the tree_scenes fallback doctrine) — the socket had been
	# wired since W1 and never filled, so a terraced river read as disconnected ponds with a
	# bare cliff between them. The sheets hang from the lip and end at the foot.
	var bare: StaticBody3D = terrain_script.new()
	bare.build(m, d, null)
	var bare_falls := bare.get_node_or_null("Waterfalls")
	_check(bare.get_node_or_null("CliffPieces") == null,
			"a null style still grew cliff pieces, which need art")
	_check(bare_falls != null and bare_falls.get_child_count() == water_segs,
			"a bare style grew %d procedural falls for %d water-rim segments"
			% [bare_falls.get_child_count() if bare_falls else 0, water_segs])
	if bare_falls != null:
		var tiers2: PackedInt32Array = d.tiers
		var off := 0
		var k2 := 0
		for s: Dictionary in segs:
			if (m.flag_at(m.idx(s.cell as Vector2i)) & WildsMap.F_WATER) == 0:
				continue
			var f := bare_falls.get_child(k2) as MeshInstance3D
			k2 += 1
			var top: float = tiers2[m.idx(s.cell as Vector2i)] * m.tier_height
			var lip := top - WildsGen.SURFACE_DROP
			var foot: float = top - int(s.drop) * m.tier_height
			# A QuadMesh is centred, so the sheet spans lip..foot when its origin sits at the
			# midpoint and its height is the difference.
			var h: float = (f.mesh as QuadMesh).size.y
			if absf(f.position.y - (lip - h * 0.5)) > 0.001 or absf(h - (lip - foot)) > 0.001:
				off += 1
		_check(off == 0, "%d procedural falls do not span their lip to their foot" % off)

	# AND THE WORLD'S EDGE DOES NOT POUR INTO THE VOID. A rim segment has no in-bounds low
	# neighbour, so on a SEA-bordered map — where the border band is itself water — every
	# perimeter cell would grow a fall spilling off the map. The cliff face must stay (it is
	# what walls the world); only the spill is suppressed.
	var sea := _map_for(42)
	sea.border_mode = WildsMap.BORDER_SEA
	var sd := WildsGen.derive(sea)
	var sea_t: StaticBody3D = terrain_script.new()
	sea_t.build(sea, sd, null)
	# How many falls the guard is actually suppressing — asserted non-zero, or this whole
	# check passes vacuously on a map that never had a rim spill to begin with.
	var suppressed := 0
	for s: Dictionary in (sd.segments as Array):
		var sc: Vector2i = s.cell
		if WildsGen.is_water(sea, sea.idx(sc)) and not sea.in_bounds(sc + (s.side as Vector2i)):
			suppressed += 1
	_check(suppressed > 0, "the sea-rim guard was never exercised: no rim spill to suppress")
	var sea_falls := sea_t.get_node_or_null("Waterfalls")
	var over_edge := 0
	if sea_falls != null:
		for f: Node3D in sea_falls.get_children():
			var cell := Vector2i(floori(f.position.x / sea.cell_size),
					floori(f.position.z / sea.cell_size))
			if not sea.in_bounds(cell) or WildsGen._in_border(sea, cell):
				over_edge += 1
	_check(over_edge == 0, "%d waterfalls pour off the world's rim on a sea-bordered map"
			% over_edge)
	sea_t.free()
	bare.free()
	_done("sockets suite: %d pieces seated true, %d waterfalls on the lip, bare style bare"
			% [segs.size(), water_segs])


## SUITE 11 — THE PAINT SERVICE: pure paint + undo spine, no refusal left to test (a stroke
## can never vanish — the decision W6 wrote down). Every stroke sticks, including a severing
## river; the undo side of a committed gesture restores every touched cell byte for byte; a
## dab off the map is ignored without opening a page.
func _service_suite() -> void:
	var svc = load("res://addons/wilds/editor/wilds_map_service.gd").new()
	var m := _map_for(42)
	svc.map = m

	# A river three cells thick, bank to bank: it severs the map — and it must STICK.
	svc.begin_gesture()
	for wz in range(20, 23):
		for wx in m.cells_w:
			var i := m.idx(Vector2i(wx, wz))
			svc.paint("flags", i, m.flag_at(i) | WildsMap.F_WATER)
	_check(svc.end_gesture("river wall"), "a severing river did not stick")
	var wet := 0
	for wx in m.cells_w:
		if (m.flag_at(m.idx(Vector2i(wx, 21))) & WildsMap.F_WATER) != 0:
			wet += 1
	_check(wet == m.cells_w, "only %d of %d river cells stayed painted" % [wet, m.cells_w])

	# Undo restores every touched value exactly — replay the recorded undo side by hand (the
	# editor's ctrl+Z calls the same _apply with the same dictionary).
	var probe := m.idx(Vector2i(5, 40))
	var before_tier := m.tier_paint_at(probe)
	svc.begin_gesture()
	svc.paint("tier", probe, before_tier + 3)
	svc.paint("forest", probe, 200)
	var undo_side: Dictionary = svc._undo_side()
	_check(svc.end_gesture("bump"), "a plain tier dab did not stick")
	_check(m.tier_paint_at(probe) == before_tier + 3 and m.forest_at(probe) == 200,
			"the dab did not land")
	svc._apply(undo_side)
	_check(m.tier_paint_at(probe) == before_tier and m.forest_at(probe) == 0,
			"undo did not restore the touched cells byte for byte")

	# Out-of-range dabs are ignored and allocate nothing.
	var pages := m.page_count()
	svc.begin_gesture()
	svc.paint("tier", -5, 9)
	svc.paint("tier", m.cell_count() + 7, 9)
	_check(not svc.end_gesture("off map") and m.page_count() == pages,
			"an off-map dab opened a page")
	_done("service suite: strokes always stick, undo restores exactly, off-map dabs ignored")


## REGION EQUIVALENCE — the halo-correctness proof. A chunk derived through its own REGION
## (windowed chamfer tiers, local water, painted ramps) must be byte-identical to the same
## chunk from a whole-map derivation with the guarantee off — across seeds, painted mesas and
## pits, water crossing a chunk border, painted ramps. This is what makes the 14 km world
## honest: any section, derived alone, IS the world.
func _equivalence_suite() -> void:
	for s: int in [42, 137]:
		var m := _map_for(s)
		for cz in range(30, 34):
			for cx in range(30, 34):
				m.set_tier_paint(m.idx(Vector2i(cx, cz)), 3)
		m.set_tier_paint(m.idx(Vector2i(8, 40)), -2)
		for cz in range(14, 18):
			for cx in range(28, 37):
				m.set_flag(m.idx(Vector2i(cx, cz)), WildsMap.F_WATER)
		m.set_flag(m.idx(Vector2i(20, 20)), WildsMap.F_RAMP_PAINTED)
		var full := WildsGen.derive(m, false)
		var bad := 0
		for chunk: Dictionary in full.chunks:
			var region := WildsGen.derive_region(m,
					Rect2i(chunk.origin, Vector2i(WildsGen.CHUNK, WildsGen.CHUNK)))
			var rc := WildsGen.mesh_chunk(m, region, chunk.origin)
			if rc.faces != chunk.faces or rc.wall != chunk.wall \
					or hash(rc.top) != hash(chunk.top) or hash(rc.cliff) != hash(chunk.cliff):
				bad += 1
		_check(bad == 0, "seed %d: %d chunks differ between region and full derivation"
				% [s, bad])
	_done("equivalence suite: every region-derived chunk is the full derivation's chunk, "
			+ "byte for byte")


## THE BORDER: whatever the size, the world's edge is never a walkable square. Cliff rim (the
## default): no border cell is walkable, edge columns stand tall over the interior, and the
## rim line WANDERS (the warped limit differs along one edge). Sea: the band is water,
## unwalkable, and carves a bed like any lake.
func _border_suite() -> void:
	var m := _map_for(42)
	var d := WildsGen.derive_light(m)
	var bad_walk := 0
	for i in (d.walkable as Dictionary):
		if WildsGen._in_border(m, Vector2i(i % m.cells_w, i / m.cells_w)):
			bad_walk += 1
	_check(bad_walk == 0, "%d border cells are walkable" % bad_walk)
	var tiers: PackedInt32Array = d.tiers
	var low_edge := 0
	for cx in range(4, 44, 4):
		if tiers[m.idx(Vector2i(cx, 0))] < tiers[m.idx(Vector2i(cx, 24))] + 4:
			low_edge += 1
	_check(low_edge == 0,
			"%d edge columns fail to stand at least 4 tiers over the interior" % low_edge)
	# Organic: the warped limit varies along the edge — the rim line is a coastline, not
	# a ruler.
	var lo_l := 1e9
	var hi_l := -1e9
	for cx in range(0, 48, 3):
		var l: float = WildsGen._border_limit(m, Vector2i(cx, 0))
		lo_l = minf(lo_l, l)
		hi_l = maxf(hi_l, l)
	_check(hi_l - lo_l > 1.0,
			"the border limit is flat along the edge (%.2f..%.2f)" % [lo_l, hi_l])

	var ms := _map_for(42)
	ms.border_mode = WildsMap.BORDER_SEA
	_check(WildsGen.is_water(ms, ms.idx(Vector2i(0, 24))), "the sea edge is not water")
	var ds := WildsGen.derive_light(ms)
	_check(not (ds.walkable as Dictionary).has(ms.idx(Vector2i(0, 24))),
			"sea cells are walkable")
	var chunk := WildsGen.mesh_chunk(ms,
			WildsGen.derive_region(ms, Rect2i(0, 0, 32, 32)), Vector2i.ZERO)
	# The sea flattens to tier 0, so any collision vertex below the lattice is its carved bed
	# (-0.2 shore / -0.9 deep) — dry ground in this chunk never dips under y = 0.
	var sea_bed := false
	for p in (chunk.faces as PackedVector3Array):
		if p.y < -0.15:
			sea_bed = true
			break
	_check(sea_bed, "the sea meshed without a carved bed")

	# AND THE WORLD STILL ENDS. The sea is wadeable now (0.55 m, bed to the last cell), so
	# the map's rim carries an invisible wall — without it a player wades off the edge.
	var surface := -WildsGen.SURFACE_DROP
	var wall: PackedVector3Array = chunk.wall
	_check(wall.size() > 0, "a sea-bordered chunk on the map rim grew no wall")
	var high := -1e9
	var on_rim := true
	for p in wall:
		high = maxf(high, p.y)
		# Every wall vertex stands on the map's boundary planes (x = 0 or z = 0 here),
		# jitter included — never inland.
		if minf(absf(p.x), absf(p.z)) > WildsGen.JITTER * ms.cell_size + 0.001:
			on_rim = false
	_check(on_rim, "a sea wall vertex stands inland instead of on the map rim")
	_check(high > surface + 1.2, "the sea wall tops out at %.2f — a 1.2 m jump clears it "
			% high + "over a surface at %.2f" % surface)
	# The wall is COLLISION-ONLY: nothing on the rim plane may be DRAWN standing over the sea.
	# (Scoped to the rim on purpose — this chunk is 32 cells wide and its inland half rises
	# tens of tiers, all of it legitimately above the waterline.)
	var render := PackedVector3Array()
	render.append_array((chunk.top as Array)[Mesh.ARRAY_VERTEX])
	render.append_array((chunk.cliff as Array)[Mesh.ARRAY_VERTEX])
	var leaked := false
	for p in render:
		if minf(absf(p.x), absf(p.z)) <= WildsGen.JITTER * ms.cell_size + 0.001 \
				and p.y > surface + 1.2:
			leaked = true
			break
	_check(not leaked, "the sea wall leaked into the rendered mesh")
	_done("border suite: rims rise unwalkably and wander, the sea takes the edge")


## THE 14 KM SMOKE: a 7000x7000 map (49M cells) must cost nothing until touched — pages stay
## sparse under paint, one region derives and meshes in bounded time, and the LAZY zone
## enters by standing only the spawn ring.
func _giant_suite() -> void:
	var m := WildsMap.new()
	m.seed = 99
	m.cells_w = 7000
	m.cells_h = 7000
	m.spawn_cell = Vector2i(3500, 3500)
	var svc = load("res://addons/wilds/editor/wilds_map_service.gd").new()
	svc.map = m
	svc.begin_gesture()
	svc.paint("tier", m.idx(Vector2i(3502, 3500)), 2)
	svc.paint("flags", m.idx(Vector2i(100, 100)), WildsMap.F_WATER)
	_check(svc.end_gesture("two dabs across 10 km"), "painting a giant map failed")
	_check(m.page_count() <= 4, "two dabs opened %d pages — storage is not sparse"
			% m.page_count())

	var t0 := Time.get_ticks_msec()
	var region := WildsGen.derive_region(m, Rect2i(3488, 3488, 32, 32))
	var region_ms := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var chunk := WildsGen.mesh_chunk(m, region, Vector2i(3488, 3488))
	var mesh_ms := Time.get_ticks_msec() - t0
	_check(region_ms < 1500, "one region derive took %d ms on the giant map" % region_ms)
	_check(mesh_ms < 1500, "one chunk mesh took %d ms on the giant map" % mesh_ms)
	_check((chunk.faces as PackedVector3Array).size() > 100,
			"the giant map's centre chunk meshed empty")

	# The far LOD: the whole 14 km as one backdrop, in bounded time, with canopy masses —
	# and an exclusion rect must actually cut quads out (the editor ring's hole).
	t0 = Time.get_ticks_msec()
	var far: Node3D = load("res://scripts/wilds/wilds_far.gd").build(m, null)
	var far_ms := Time.get_ticks_msec() - t0
	var far_holed: Node3D = load("res://scripts/wilds/wilds_far.gd").build(m, null,
			Rect2i(3488, 3488, 96, 96))
	_check(far_ms < 3000, "the far LOD took %d ms to build" % far_ms)
	_check(int(far.get_meta("far_quads", 0)) > 5000, "the far LOD ground is empty")
	_check(int(far.get_meta("far_blobs", 0)) > 100, "the far LOD grew no canopy masses")
	_check(int(far_holed.get_meta("far_quads", 0)) < int(far.get_meta("far_quads", 0)),
			"the exclusion rect cut no hole in the far LOD")
	far.free()
	far_holed.free()

	var zone := (load("res://scenes/world/zone_wilds.tscn") as PackedScene).instantiate()
	zone.set("map", m)
	t0 = Time.get_ticks_msec()
	root.add_child(zone)
	await process_frame
	var entry_ms := Time.get_ticks_msec() - t0
	var terrain: StaticBody3D = zone.get_node("Terrain")
	_check(zone.find_child("SpawnA", true, false) != null, "no SpawnA on the giant map")
	_check(terrain.has_chunk(Vector2i(3488, 3488)),
			"the giant zone's spawn ring did not stand")
	_check(not terrain.has_chunk(Vector2i(0, 0)), "the giant zone built the far corner")
	_check(entry_ms < 20000, "giant zone entry took %d ms" % entry_ms)
	# The backdrop stands, and its canopy masses CLEAR around a focus (the anti-doubling
	# contract between the streamed ring and its own scenery).
	var farn := zone.get_node_or_null("FarLOD")
	_check(farn != null and int(farn.call("blob_count")) > 100,
			"the lazy zone hung no far backdrop")
	if farn != null and int(farn.call("blob_count")) > 0:
		farn.call("clear_around", farn.call("blob_origin", 0), 60.0)
		_check(int(farn.call("hidden_count")) >= 1,
				"clear_around hid nothing at a known blob")
	zone.free()
	_done("giant suite: sparse under paint, region %d ms, chunk %d ms, entry %d ms at 14 km"
			% [region_ms, mesh_ms, entry_ms])


## SUITE 12 — STREAMING. Only the sections around the player exist: the spawn ring stands the
## frame the zone is ready (there must be ground to land on), the far corner does not; a
## streamed chunk is byte-identical to the one the full derive builds; and walking to the far
## corner spawns it while the spawn ring despawns behind you. A 128x128 map (256 m) keeps the
## two corners farther apart than free_radius, so despawn is actually observable.
func _streaming_suite() -> void:
	var m := WildsMap.new()
	m.seed = 42
	m.cells_w = 128
	m.cells_h = 128
	var zone := (load("res://scenes/world/zone_wilds.tscn") as PackedScene).instantiate()
	zone.set("map", m)
	root.add_child(zone)
	await process_frame
	var terrain: StaticBody3D = zone.get_node("Terrain")
	var d: Dictionary = zone.derived
	var sp: Vector2i = d.spawn
	var spawn_origin := Vector2i(sp.x / WildsGen.CHUNK, sp.y / WildsGen.CHUNK) * WildsGen.CHUNK
	_check(terrain.has_chunk(spawn_origin), "the spawn ring did not stand synchronously")
	# The corner farthest from the spawn must NOT exist yet.
	var far := Vector2i(0 if sp.x >= m.cells_w / 2 else m.cells_w - WildsGen.CHUNK,
			0 if sp.y >= m.cells_h / 2 else m.cells_h - WildsGen.CHUNK)
	_check(not terrain.has_chunk(far), "the far corner was built eagerly — nothing streamed")
	_check(not (d as Dictionary).has("chunks"), "the streaming zone derived the full mesh")

	# Determinism across the seam: the streamed spawn chunk's collider must be byte-equal to
	# the same chunk from a one-shot full derivation.
	var full_chunk := WildsGen.mesh_chunk(zone.built_map, d, spawn_origin)
	var shape := terrain.get_node_or_null("Collision_%d_%d"
			% [spawn_origin.x, spawn_origin.y]) as CollisionShape3D
	_check(shape != null and (shape.shape as ConcavePolygonShape3D).get_faces()
			== full_chunk.faces, "a streamed chunk differs from the full derive's chunk")

	# Walk (well, teleport) to the far corner: a fake player pulls the stream. Injected into
	# the streamer directly, NOT via the "player" group — the Hud autoload polls that group
	# and chokes on a bare Node3D with no health.
	var walker := Node3D.new()
	root.add_child(walker)
	zone.get_node("Stream").set("_player", walker)
	var t_local := Vector3((far.x + WildsGen.CHUNK * 0.5) * m.cell_size, 0.0,
			(far.y + WildsGen.CHUNK * 0.5) * m.cell_size)
	walker.global_position = (terrain as Node3D).global_transform * t_local
	var tick0 := Engine.get_physics_frames()
	while Engine.get_physics_frames() - tick0 < 40 and not terrain.has_chunk(far):
		await process_frame
	_check(terrain.has_chunk(far), "walking to the far corner never spawned its section")
	_check(not terrain.has_chunk(spawn_origin),
			"the spawn ring never despawned %d chunks behind the player" % 0)
	var flora_far := zone.get_node_or_null("Flora/Flora_%d_%d" % [far.x, far.y])
	_check(flora_far != null, "the far section has terrain but no forest")
	walker.free()
	zone.free()
	_done("streaming suite: spawn ring synchronous, far corner streams in, seam byte-equal")


## SUITE 13 — THE WALK BENCH. scenes/dev/wilds_walk.tscn is how a person plays the wilds:
## F6 must land the game's Player on SpawnA looking through the rig, TAB must hand the
## viewport to the fly camera (with the player parked) and back, and the game look must be
## LIFTED from main.tscn, never re-authored. No compile-time refs to Player/FlyCamera here —
## groups and duck-typing only, the test-script compilation law.
func _walk_bench_suite() -> void:
	var bench := (load("res://scenes/dev/wilds_walk.tscn") as PackedScene).instantiate()
	bench.set("map_seed", 42)
	root.add_child(bench)
	# add_child during _initialize is DEFERRED (the root is still busy setting up), so the
	# bench only enters the tree — and only runs _ready — after a frame (the zone suite always
	# awaited this; asserting synchronously here tested an instantiated-but-unrooted scene).
	await process_frame
	var player := bench.get_node_or_null("Player") as Node3D
	var zone := bench.find_child("ZoneWilds", true, false)
	_check(player != null and player.is_in_group("player"), "no grouped Player in the bench")
	_check(zone != null, "the bench built no wilds zone")
	if player != null and zone != null:
		var spawn := zone.find_child("SpawnA", true, false) as Node3D
		# Loose-ish tolerance: physics has ticked once by now and gravity has begun taking
		# the 0.2 m hover back.
		_check(spawn != null and player.global_position.distance_to(
				spawn.global_position + Vector3(0.0, 0.2, 0.0)) < 0.1,
				"the player did not start on SpawnA")
	var rig_cam := bench.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var fly := bench.get_node_or_null("FlyCam") as Camera3D
	_check(rig_cam != null and root.get_camera_3d() == rig_cam,
			"walk mode does not look through the rig camera")
	bench.call("_set_mode", false)
	_check(fly != null and root.get_camera_3d() == fly and player != null
			and not player.visible and not player.is_physics_processing(),
			"fly mode left the player running or the rig camera current")
	bench.call("_set_mode", true)
	_check(root.get_camera_3d() == rig_cam, "TAB back to walk did not restore the rig")
	var env := bench.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_check(env != null and env.environment != null,
			"the game environment was not lifted from main.tscn")
	var sun := bench.get_node_or_null("Sun")
	_check(sun != null and sun.is_in_group("sun"), "no grouped sun in the bench")
	# THE STANDING TEST — the one no data-level suite can give: let physics run and require
	# the player to LAND on the terrain, not pass through it. This is the assertion that
	# caught W1's decorative colliders (CollisionShape3D under a chunk holder instead of the
	# body — registered nowhere, byte-verified anyway).
	if player != null and zone != null:
		var spawn := zone.find_child("SpawnA", true, false) as Node3D
		for _i in 40:
			await process_frame
		_check(spawn != null and player.global_position.y > spawn.global_position.y - 3.0,
				"the player fell through the terrain (y drifted to %.2f, spawn at %.2f)"
				% [player.global_position.y, spawn.global_position.y if spawn else 0.0])
	# THE ORBIT — end to end through a simulated right stick: press aim_right and the rig must
	# actually swing; hold aim_up far past the band and the pitch target must stop at the
	# 70-degree ceiling — the always-top-down promise, asserted rather than trusted.
	var rig := bench.get_node_or_null("CameraRig") as Node3D
	if rig != null:
		var yaw_before: float = rig.rotation.y
		Input.action_press("aim_right")
		for _i in 30:
			await process_frame
		Input.action_release("aim_right")
		_check(absf(rig.rotation.y - yaw_before) > 0.05,
				"the right stick did not orbit the rig")
		Input.action_press("aim_up")
		for _i in 120:
			await process_frame
		Input.action_release("aim_up")
		var pt: float = rig.get("_pitch_target")
		_check(pt > deg_to_rad(66.0) and pt <= deg_to_rad(70.0) + 0.01,
				"orbit pitch did not ride to (and stop at) the top-down ceiling (%.3f rad)" % pt)
	# THE JUMP — A must launch an arc that clears one 1.2 m tier and come back down onto the
	# ground. parse_input_event, not action_press: the trigger lives in handle_input, which
	# only ever sees real InputEvents. The wait counts PHYSICS ticks, not render frames —
	# headless render outpaces 60 Hz physics ~2.4:1 (measured), so a render-frame window is
	# less than half the wall-clock it claims and the arc (1.12 s + landing) outlives it.
	if player != null:
		var ground_y: float = player.global_position.y
		var peak: float = ground_y
		var ev := InputEventAction.new()
		ev.action = "jump"
		ev.pressed = true
		Input.parse_input_event(ev)
		var tick0 := Engine.get_physics_frames()
		while Engine.get_physics_frames() - tick0 < 110:
			await process_frame
			peak = maxf(peak, player.global_position.y)
		_check(peak - ground_y > 1.2,
				"the jump peaked %.2f m above ground — a 1.2 m tier stays out of reach"
				% (peak - ground_y))
		_check(player.global_position.y < ground_y + 0.3,
				"the player never came back down (y=%.2f after the jump)"
				% (player.global_position.y - ground_y))
		var fsm: Node = player.get_node_or_null("StateMachine")
		var state: String = String(fsm.get("current_state").name) if fsm != null else "?"
		_check(state in ["Idle", "Move"],
				"the jump did not hand control back (stuck in %s)" % state)
	bench.free()
	_done("walk bench suite: standing on SpawnA, TAB swaps cameras, stick orbits in its band")


func _zone_suite() -> void:
	var zone := (load("res://scenes/world/zone_wilds.tscn") as PackedScene).instantiate()
	zone.set("map_seed", 42)
	root.add_child(zone)
	await process_frame
	_check(zone.is_in_group("zone"), "zone root is not in group \"zone\"")
	var spawn := zone.find_child("SpawnA", true, false)
	_check(spawn != null, "no SpawnA in the zone")
	var terrain := zone.find_child("Terrain", true, false)
	_check(terrain != null, "no Terrain in the zone")
	if spawn != null and terrain != null:
		var m: WildsMap = zone.built_map
		var d: Dictionary = zone.derived
		var sp: Vector2i = d.spawn
		_check((d.reached as Dictionary).has(m.idx(sp)), "the spawn cell is not reached")
		# SpawnA stands 1.2 above its own tier top.
		var local := Vector2((sp.x + 0.5) * m.cell_size, (sp.y + 0.5) * m.cell_size)
		var want: float = terrain.height_at(local) + 1.2
		var got: float = (spawn as Node3D).position.y - (terrain as Node3D).position.y
		_check(absf(got - want) < 0.01, "SpawnA floats %.2f above its tier, drew 1.2"
				% (got - (want - 1.2)))
		_check(terrain.side() > 0, "terrain does not answer the foliage ground contract")
	zone.free()
	_done("zone suite: contract, spawn on reached ground, terrain answers as ground")


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _done(msg: String) -> void:
	_suites_done += 1
	_say("[VERIFY] " + msg)


func _say(msg: String) -> void:
	print(msg)
	_log += msg + "\n"

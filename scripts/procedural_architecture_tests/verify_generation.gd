extends SceneTree
## Headless verification of the generation ensemble (addons/procedural_architecture/gen). Run:
##   Godot_console.exe --headless --path . --script res://scripts/procedural_architecture_tests/verify_generation.gd --log-file <fresh path>
## Non-zero exit on any failure. Same crash-detection idiom as the other suites.

const Poisson := preload("res://addons/procedural_architecture/gen/algo/poisson.gd")
const Voronoi := preload("res://addons/procedural_architecture/gen/algo/voronoi.gd")
const Graph := preload("res://addons/procedural_architecture/gen/algo/graph.gd")
const Grid := preload("res://addons/procedural_architecture/gen/algo/grid.gd")
const CA := preload("res://addons/procedural_architecture/gen/algo/ca.gd")
const BSP := preload("res://addons/procedural_architecture/gen/algo/bsp.gd")
const Growth := preload("res://addons/procedural_architecture/gen/algo/growth.gd")
const Generator := preload("res://addons/procedural_architecture/gen/generator.gd")
const ZoneBrief := preload("res://addons/procedural_architecture/gen/zone_brief.gd")
const Api := preload("res://addons/floorplan/api/floorplan_api.gd")
const Layout := preload("res://addons/floorplan/api/plan_layout.gd")
const Host := preload("res://addons/procedural_architecture/core/module_host.gd")
const Drafter := preload("res://addons/procedural_architecture/core/drafter.gd")
const WorldBake := preload("res://scripts/world/world_bake.gd")
const WorldCrypt := preload("res://scripts/world/world_crypt.gd")

const EXPECTED_SUITES := 13

var _fails: Array[String] = []
var _log := ""
var _suites_done := 0


func _initialize() -> void:
	_poisson_suite()
	_voronoi_suite()
	_graph_suite()
	_grid_ca_suite()
	_bsp_suite()
	_growth_suite()
	_determinism_suite()
	_trace_suite()
	_crypt_suite()
	_city_suite()
	_roads_suite()
	_anchor_suite()
	_coast_suite()
	if _suites_done != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported done — one crashed silently" % [_suites_done, EXPECTED_SUITES])
	var f := FileAccess.open("user://verify_generation.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log)
	if _fails.is_empty():
		_say("[VERIFY] GENERATION PASS")
		quit(0)
	else:
		for line in _fails:
			_say("[VERIFY] FAIL: " + line)
		quit(1)


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _rect(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])


# ---------------------------------------------------------------- 1. Poisson -----------------


## Minimum distance kept, coverage without gaps, every sample inside, a wanted first sample.
func _poisson_suite() -> void:
	var boundary := _rect(120, 80)
	var pts := Poisson.sample(boundary, 8.0, _rng(7), 30, Vector2(0.5, 40.0))
	_check(pts.size() > 80, "poisson: only %d samples on 120×80 at r=8" % pts.size())
	var min_d := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_d = minf(min_d, pts[i].distance_to(pts[j]))
	_check(min_d >= 8.0 - 1e-4, "poisson: min distance %.3f < r" % min_d)
	var inside := true
	for p in pts:
		if not Geometry2D.is_point_in_polygon(p, boundary):
			inside = false
	_check(inside, "poisson: a sample left the polygon")
	_check(pts[0].is_equal_approx(Vector2(0.5, 40.0)), "poisson: the wanted first sample was not used")
	# no empty disc of radius 2r anywhere (maximal sampling): probe a lattice
	var worst := 0.0
	for gy in range(4, 80, 8):
		for gx in range(4, 120, 8):
			var probe := Vector2(gx, gy)
			var d := INF
			for p in pts:
				d = minf(d, p.distance_to(probe))
			worst = maxf(worst, d)
	_check(worst < 16.0, "poisson: an empty disc of radius %.1f (want < 2r = 16)" % worst)
	# a non-convex polygon
	var l_shape := PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(60, 30), Vector2(30, 30), Vector2(30, 60), Vector2(0, 60)])
	var pl := Poisson.sample(l_shape, 5.0, _rng(3))
	var all_in := true
	for p in pl:
		if not Geometry2D.is_point_in_polygon(p, l_shape):
			all_in = false
	_check(pl.size() > 60 and all_in, "poisson: L-shape %d samples, inside %s" % [pl.size(), all_in])
	_done("poisson suite done (%d samples, min d %.2f, worst gap %.1f)" % [pts.size(), min_d, worst])


# ---------------------------------------------------------------- 2. Voronoi -----------------


## Cells cover the boundary exactly, do not overlap, hold their seeds; Lloyd evens the areas;
## tidy leaves no short edge and keeps the shared edges shared.
func _voronoi_suite() -> void:
	var boundary := _rect(150, 100)
	var seeds := Poisson.sample(boundary, 22.0, _rng(11))
	var cs: Array = Voronoi.cells(seeds, boundary)
	var total := 0.0
	var holds := true
	var empty := 0
	for i in cs.size():
		var c: PackedVector2Array = cs[i]
		if c.size() < 3:
			empty += 1
			continue
		total += absf(Voronoi.area(c))
		if not Geometry2D.is_point_in_polygon(seeds[i], c):
			holds = false
	_check(empty == 0, "voronoi: %d empty cells of %d" % [empty, cs.size()])
	_check(absf(total - 15000.0) < 1.0, "voronoi: cells cover %.2f of 15000" % total)
	_check(holds, "voronoi: a seed lies outside its cell")
	var overlap := 0.0
	for i in cs.size():
		for j in range(i + 1, cs.size()):
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(cs[i], cs[j]):
				overlap += absf(Voronoi.area(piece))
	_check(overlap < 1e-3, "voronoi: cells overlap by %.4f" % overlap)
	# Lloyd: the area variance drops
	var var0 := _area_variance(cs)
	var relaxed := Voronoi.lloyd(seeds, boundary, 3)
	var cs2: Array = Voronoi.cells(relaxed, boundary)
	var var1 := _area_variance(cs2)
	_check(var1 < var0, "voronoi: Lloyd did not even the areas (%.1f → %.1f)" % [var0, var1])
	# tidy: no edge under 1 m, vertices on the 0.25 grid, shared edges still shared
	var tidy: Array = Voronoi.tidy_all(cs2, 1.0, 0.25)
	var shortest := INF
	var off_grid := 0
	for c: PackedVector2Array in tidy:
		for k in c.size():
			var p := c[k]
			var q := c[(k + 1) % c.size()]
			shortest = minf(shortest, p.distance_to(q))
			if absf(p.x / 0.25 - round(p.x / 0.25)) > 1e-4 or absf(p.y / 0.25 - round(p.y / 0.25)) > 1e-4:
				off_grid += 1
	_check(shortest >= 1.0 - 1e-4 and off_grid == 0, "voronoi: tidy left an edge of %.2f m, %d vertices off grid" % [shortest, off_grid])
	var shared: Array = Voronoi.shared_edges(tidy)
	_check(shared.size() >= cs2.size(), "voronoi: only %d shared edges for %d cells" % [shared.size(), cs2.size()])
	var tris := Voronoi.delaunay(relaxed)
	var edges: Array = Graph.edges_from_triangles(tris)
	_check(edges.size() >= shared.size() * 0.8, "voronoi: Delaunay edges %d vs shared edges %d" % [edges.size(), shared.size()])
	_done("voronoi suite done (%d cells, variance %.0f → %.0f, %d shared edges)" % [cs.size(), var0, var1, shared.size()])


func _area_variance(cs: Array) -> float:
	var areas: Array = []
	for c: PackedVector2Array in cs:
		if c.size() >= 3:
			areas.append(absf(Voronoi.area(c)))
	var mean := 0.0
	for a in areas:
		mean += a
	mean /= maxf(1.0, float(areas.size()))
	var v := 0.0
	for a in areas:
		v += (a - mean) * (a - mean)
	return v / maxf(1.0, float(areas.size()))


# ---------------------------------------------------------------- 3. graph -------------------


func _graph_suite() -> void:
	var pts := Poisson.sample(_rect(100, 60), 12.0, _rng(5))
	var tris := Voronoi.delaunay(pts)
	var edges: Array = Graph.edges_from_triangles(tris)
	var weights := PackedFloat32Array()
	for e: Array in edges:
		weights.append(pts[e[0]].distance_to(pts[e[1]]))
	var mst: Array = Graph.kruskal(pts.size(), edges, weights)
	_check(mst.size() == pts.size() - 1, "graph: MST has %d edges for %d vertices" % [mst.size(), pts.size()])
	_check(Graph.all_reachable(pts.size(), mst, 0), "graph: MST does not connect every vertex")
	var extra: Array = Graph.loops(edges, weights, mst, 3)
	_check(extra.size() == 3, "graph: %d loops, want 3" % extra.size())
	for e: Array in extra:
		_check(not mst.has(e), "graph: a loop edge is in the tree")
	var depth := Graph.bfs_depth(pts.size(), mst, 0)
	var maxd := 0
	for d in depth:
		maxd = maxi(maxd, d)
	_check(depth[0] == 0 and maxd >= 3, "graph: depths (max %d)" % maxd)
	var depth2 := Graph.bfs_depth(pts.size(), mst + extra, 0)
	var shallower := true
	for i in depth.size():
		if depth2[i] > depth[i]:
			shallower = false
	_check(shallower, "graph: loops made a vertex deeper")
	_done("graph suite done (%d vertices, max depth %d)" % [pts.size(), maxd])


# ---------------------------------------------------------------- 4. grid + CA ---------------


func _grid_ca_suite() -> void:
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 30), Vector2(20, 30), Vector2(20, 15), Vector2(0, 15)])
	var g: RefCounted = Grid.from_polygon(poly, 0.5)
	var free: int = g.count(g.FREE)
	_check(absf(float(free) * 0.25 - 900.0) < 30.0, "grid: %d free cells → %.1f m², want ≈ 900" % [free, float(free) * 0.25])
	var back: Array = g.to_polygons(g.FREE, 0.01)
	_check(back.size() == 1 and absf(absf(Voronoi.area(back[0])) - 900.0) < 30.0, "grid: polygon back %d pieces, area %.1f" % [back.size(), absf(Voronoi.area(back[0])) if not back.is_empty() else -1.0])
	# CA: one floor component, a fair share of the area, valid polygons
	var cave: RefCounted = Grid.from_polygon(_rect(60, 40), 0.5)
	CA.carve(cave, 0.45, 7, _rng(40))
	var floor: int = cave.count(CA.FLOOR)
	var rock: int = cave.count(CA.ROCK)
	_check(floor > 0 and rock > 0 and float(floor) / float(floor + rock) > 0.3, "ca: floor %d rock %d" % [floor, rock])
	var dropped: int = cave.largest_component(CA.FLOOR, CA.ROCK)
	_check(dropped == 0, "ca: %d floor cells were still disconnected" % dropped)
	var polys: Array = cave.to_polygons(CA.FLOOR, 0.3, true)
	_check(polys.size() == 1, "ca: %d outer polygons, want 1" % polys.size())
	if polys.size() == 1:
		var a := absf(Voronoi.area(polys[0]))
		# the outer polygon spans the floor plus the rock islands inside it (holes are dropped
		# here; the texture operator will subtract them)
		var cells_area := float(floor) * 0.25
		_check(a >= cells_area * 0.95 and a <= cells_area * 1.6, "ca: polygon area %.1f vs cells %.1f" % [a, cells_area])
	_done("grid+ca suite done (%d floor cells, %d rock)" % [floor, rock])


# ---------------------------------------------------------------- 5. BSP ---------------------


func _bsp_suite() -> void:
	var res: Dictionary = BSP.partition(Rect2(0, 0, 56, 39), 5, 5.0, _rng(9))
	var leaves: Array = res.leaves
	var rooms: Array = res.rooms
	var links: Array = res.links
	_check(leaves.size() >= 12 and leaves.size() == rooms.size(), "bsp: %d leaves, %d rooms" % [leaves.size(), rooms.size()])
	var cover := 0.0
	var disjoint := true
	for i in leaves.size():
		cover += (leaves[i] as Rect2).get_area()
		for j in range(i + 1, leaves.size()):
			var x := (leaves[i] as Rect2).intersection(leaves[j])
			if x.get_area() > 1e-3:      # touching leaves meet within float noise
				disjoint = false
	_check(absf(cover - 56.0 * 39.0) < 1e-3 and disjoint, "bsp: leaves cover %.1f, disjoint %s" % [cover, disjoint])
	var inside := true
	var fill_ok := true
	for i in rooms.size():
		var leaf: Rect2 = leaves[i]
		var room: Rect2 = rooms[i]
		if not leaf.grow(1e-4).encloses(room):
			inside = false
		var f := room.get_area() / leaf.grow(-0.5).get_area()
		if f < 0.78 * 0.78 - 1e-3 or f > 0.95 * 0.95 + 1e-3:
			fill_ok = false
	_check(inside and fill_ok, "bsp: rooms inside leaves %s, fill %s" % [inside, fill_ok])
	_check(links.size() == leaves.size() - 1 and Graph.all_reachable(leaves.size(), links, 0), "bsp: %d links for %d leaves, connected %s" % [links.size(), leaves.size(), Graph.all_reachable(leaves.size(), links, 0)])
	_done("bsp suite done (%d rooms)" % rooms.size())


# ---------------------------------------------------------------- 6. growth ------------------


func _growth_suite() -> void:
	var poly := _rect(24, 14)
	var g: RefCounted = Grid.from_polygon(poly, 0.5)
	var program: Array = [
		{"role": "hall", "area_m2": 12.0, "aspect": 3.0, "priority": 9},
		{"role": "living", "area_m2": 24.0, "aspect": 1.5, "priority": 8},
		{"role": "kitchen", "area_m2": 12.0, "aspect": 1.2, "priority": 7},
		{"role": "bedroom", "area_m2": 14.0, "aspect": 1.0, "priority": 6},
		{"role": "bedroom", "area_m2": 14.0, "aspect": 1.0, "priority": 6},
		{"role": "bath", "area_m2": 6.0, "aspect": 1.0, "priority": 4},
		{"role": "study", "area_m2": 8.0, "aspect": 0.7, "priority": 3},
		{"role": "closet", "area_m2": 5.0, "aspect": 1.0, "priority": 2},
	]
	var res: Dictionary = Growth.grow(g, program, _rng(21))
	var rooms: Array = res.rooms
	_check(rooms.size() == 8, "growth: %d rooms placed of 8" % rooms.size())
	var within := 0
	var total := 0.0
	for r: Dictionary in rooms:
		var target := 0.0
		for item: Dictionary in program:
			if String(item.role) == String(r.role):
				target = float(item.area_m2)
				break
		total += float(r.area_m2)
		if absf(float(r.area_m2) - target) <= target * 0.25 + 0.5:
			within += 1
		_check((r.polygons as Array).size() >= 1, "growth: room %s has no polygon" % r.role)
	_check(within >= 6, "growth: only %d of 8 rooms within 25 %% of their target" % within)
	# disjoint by construction (labels); every room touches the hall or another room
	var adj: Dictionary = res.adjacency
	var touched := {}
	for key in adj:
		var ab := String(key).split("-")
		touched[int(ab[0])] = true
		touched[int(ab[1])] = true
	var lonely := 0
	for r: Dictionary in rooms:
		if not touched.has(int(r.label)):
			lonely += 1
	_check(lonely == 0, "growth: %d rooms share no edge with anything" % lonely)
	# the runs of a shared edge are straight and at least one cell long
	var straight := true
	for key in adj:
		for run: Array in adj[key]:
			var p: Vector2 = run[0]
			var q: Vector2 = run[1]
			if not (is_equal_approx(p.x, q.x) or is_equal_approx(p.y, q.y)) or p.distance_to(q) < 0.5 - 1e-4:
				straight = false
	_check(straight, "growth: a shared run is not an axis-aligned segment")
	var hall: Array = res.hall
	_check(total <= 24.0 * 14.0 and hall.size() >= 1, "growth: rooms %.1f m² of 336, hall pieces %d" % [total, hall.size()])
	# THE RULES OF SCALE. Fill: a guardhouse's rooms cover it, the hall seeded at the door
	var g2: RefCounted = Grid.from_polygon(_rect(12, 10), 0.5)
	var door := Vector2(6.0, 10.0)
	var prog2: Array = [
		{"role": "hall", "area_m2": 12.0, "aspect": 2.0, "priority": 9, "max_area_m2": 40.0},
		{"role": "guard", "area_m2": 16.0, "aspect": 1.2, "priority": 8, "max_area_m2": 60.0},
		{"role": "office", "area_m2": 12.0, "aspect": 1.2, "priority": 6, "max_area_m2": 40.0},
		{"role": "cell", "area_m2": 7.0, "aspect": 1.0, "priority": 5, "max_area_m2": 30.0},
		{"role": "cell", "area_m2": 7.0, "aspect": 1.0, "priority": 5, "max_area_m2": 30.0},
	]
	var res2: Dictionary = Growth.grow(g2, prog2, _rng(5), {"fill": true, "pocket_cells": 8, "seed_at": {0: g2.cell_of(door + Vector2(0, -0.5))}})
	var covered := 0.0
	var hall_d := INF
	for r: Dictionary in res2.rooms:
		covered += float(r.area_m2)
		if int(r.k) == 0:
			for hp2: PackedVector2Array in r.polygons:
				for i in hp2.size():
					hall_d = minf(hall_d, Geometry2D.get_closest_point_to_segment(door, hp2[i], hp2[(i + 1) % hp2.size()]).distance_to(door))
	_check((res2.rooms as Array).size() == 5 and covered >= 120.0 * 0.98, "growth fill: %d rooms cover %.1f of 120 m²" % [(res2.rooms as Array).size(), covered])
	_check((res2.grid as RefCounted).count(Growth.HALL) <= 4, "growth fill: %d free cells left" % (res2.grid as RefCounted).count(Growth.HALL))
	_check(hall_d <= 0.6, "growth fill: the hall is %.1f m from the door" % hall_d)
	# Gap: a ward's buildings apart by a passage, the passage one connected network; an open
	# square at the gate stays passage
	var g3: RefCounted = Grid.from_polygon(_rect(40, 30), 0.5)
	var gate := Vector2(20.0, 30.0)
	for y in g3.h:
		for x in g3.w:
			if g3.at(x, y) == g3.FREE and Rect2(gate - Vector2(2, 2), Vector2(4, 4)).has_point(g3.centre(x, y)):
				g3.put(x, y, g3.OPEN)
	var prog3: Array = []
	for i in 6:
		prog3.append({"role": "house", "area_m2": 100.0, "aspect": 1.3, "priority": 5 - i * 0.01, "max_area_m2": 140.0})
	var res3: Dictionary = Growth.grow(g3, prog3, _rng(9), {"gap": 4, "min_cells": 160, "pocket_cells": 32})
	var grid3: RefCounted = res3.grid
	var too_close := 0
	for y in grid3.h:
		for x in grid3.w:
			var v: int = grid3.at(x, y)
			if v <= 0:
				continue
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					var u: int = grid3.at(x + dx, y + dy)
					if u > 0 and u != v:
						too_close += 1
	_check((res3.rooms as Array).size() >= 4 and too_close == 0, "growth gap: %d buildings, %d cell pairs within the gap" % [(res3.rooms as Array).size(), too_close])
	var hall_copy: RefCounted = grid3.duplicate_grid()
	var cut: int = hall_copy.largest_component(Growth.HALL, -9)
	_check(cut == 0, "growth gap: the passage network is cut (%d cells off the main piece)" % cut)
	var gate_open := true
	for y in grid3.h:
		for x in grid3.w:
			if Rect2(gate - Vector2(2, 2), Vector2(4, 4)).has_point(grid3.centre(x, y)) and grid3.at(x, y) > 0:
				gate_open = false
	_check(gate_open, "growth gap: a building took the open square at the gate")
	_done("growth suite done (%d rooms, %.0f m² rooms, %d hall pieces; fill %.0f m², %d buildings apart)" % [rooms.size(), total, hall.size(), covered, (res3.rooms as Array).size()])


# ---------------------------------------------------------------- 7. determinism -------------


func _determinism_suite() -> void:
	var b := _rect(90, 60)
	var a1 := Poisson.sample(b, 9.0, _rng(77))
	var a2 := Poisson.sample(b, 9.0, _rng(77))
	_check(a1 == a2, "determinism: poisson differs for the same seed")
	var c1: Array = Voronoi.cells(Voronoi.lloyd(a1, b, 2), b)
	var c2: Array = Voronoi.cells(Voronoi.lloyd(a2, b, 2), b)
	_check(str(c1) == str(c2), "determinism: voronoi differs")
	var g1: RefCounted = Grid.from_polygon(_rect(30, 20), 0.5)
	var g2: RefCounted = Grid.from_polygon(_rect(30, 20), 0.5)
	var prog: Array = [{"role": "a", "area_m2": 30.0, "aspect": 1.0, "priority": 2}, {"role": "b", "area_m2": 20.0, "aspect": 2.0, "priority": 1}]
	var r1: Dictionary = Growth.grow(g1, prog, _rng(5))
	var r2: Dictionary = Growth.grow(g2, prog, _rng(5))
	_check((r1.grid as RefCounted).data == (r2.grid as RefCounted).data, "determinism: growth differs")
	var k1: RefCounted = Grid.from_polygon(_rect(30, 20), 0.5)
	var k2: RefCounted = Grid.from_polygon(_rect(30, 20), 0.5)
	CA.carve(k1, 0.45, 5, _rng(8))
	CA.carve(k2, 0.45, 5, _rng(8))
	_check(k1.data == k2.data, "determinism: ca differs")
	var b1: Dictionary = BSP.partition(Rect2(0, 0, 40, 30), 4, 5.0, _rng(2))
	var b2: Dictionary = BSP.partition(Rect2(0, 0, 40, 30), 4, 5.0, _rng(2))
	_check(str(b1.rooms) == str(b2.rooms), "determinism: bsp differs")
	_done("determinism suite done")


# ---------------------------------------------------------------- 8. a whole zone ------------


## A 150 m dungeon: the paper's districts by depth, every container connected through its
## gates, deterministic, written into a plan (groups, one owner per cell) that bakes; a
## district re-rolled alone changes only its own subtree's nodes.
# ---------------------------------------------------------------- 8. the trace ---------------
## The trace stamps everything an op produced, changes nothing, and `to_parts(upto)` writes
## the plan as it was after a step.
func _trace_suite() -> void:
	var legend: Resource = Api.default_legend()
	var plan: Node = Api.new_plan("Traced", null, legend)
	root.add_child(plan)
	var ctx: Dictionary = Host.context(plan)
	# ON A CITY, because a crypt's partition is authored rather than computed: the trace is
	# about the machinery that stamps every step, and a kind with one operator would prove
	# nothing about it.
	var brief: Resource = ZoneBrief.new()
	brief.id = "zone"
	brief.kind = "city"
	brief.seed = 7
	brief.size_m = 460.0
	var plain: Dictionary = Generator.generate(brief, ctx)
	var traced_ctx := ctx.duplicate()
	var trace: Array = []
	traced_ctx["trace"] = trace
	var traced: Dictionary = Generator.generate(brief, traced_ctx)
	var tree: RefCounted = traced.tree
	_check(trace.size() > 50, "trace: only %d entries" % trace.size())
	var ascending := true
	var unresolved := 0
	for i in trace.size():
		var e: Dictionary = trace[i]
		if int(e.step) != i:
			ascending = false
		var c: RefCounted = tree.find(String(e.cell_id))
		if c == null or int(c.depth) != int(e.depth):
			unresolved += 1
	_check(ascending and unresolved == 0, "trace: steps not ascending or %d entries unresolved" % unresolved)
	# every child and every element carries a stamp
	var unstamped := 0
	for c: RefCounted in tree.walk():
		if c.parent != null and not c.params.has("step"):
			unstamped += 1
		for name in ["adjacency", "gates", "fixtures", "walls", "stairs"]:
			for e in c.get(name):
				if not (e as Dictionary).has("step"):
					unstamped += 1
		for name in ["holes", "reserved", "open"]:
			if (c.params.get("step_" + name, PackedInt32Array()) as PackedInt32Array).size() != (c.get(name) as Array).size():
				unstamped += 1
	_check(unstamped == 0, "trace: %d things without a step stamp" % unstamped)
	# a stamp never precedes the cell's own creation, and the cell's ops come in its order
	var out_of_order := 0
	for c: RefCounted in tree.walk():
		var born := int(c.params.get("step", -1))
		for g: Dictionary in c.gates:
			if int(g.step) < born:
				out_of_order += 1
		for ch: RefCounted in c.children:
			if int(ch.params.get("step", -1)) < born:
				out_of_order += 1
	_check(out_of_order == 0, "trace: %d stamps before their cell was born" % out_of_order)
	# the trace changes nothing
	var a: Dictionary = plain.stats
	var b: Dictionary = traced.stats
	var same := true
	for key in ["cells", "wards", "buildings", "rooms", "gates", "fixtures", "walls"]:
		if int(a[key]) != int(b[key]):
			same = false
	_check(same and str(a.roles) == str(b.roles), "trace: a traced run differs from a plain one")
	_check((Generator.to_parts(tree, brief) as Array).size() == (plain.parts as Array).size(), "trace: parts differ")
	# the plan as it was after the zone's first partition: only the root and its wards
	var first_ward_step := -1
	for e: Dictionary in trace:
		if String(e.op) == "seed" and int(e.depth) == 0:
			first_ward_step = int(e.step)   # the wards are born at the NEXT step (voronoi)
			break
	var early: Array = Generator.to_parts(tree, brief, first_ward_step)
	var late: Array = Generator.to_parts(tree, brief, trace.size() - 1)
	_check(first_ward_step >= 0 and early.size() >= 1 and early.size() < late.size()
			and late.size() == (plain.parts as Array).size(),
			"trace: parts before the zone's partition %d, up to the end %d (want %d)" % [early.size(), late.size(), (plain.parts as Array).size()])
	# rules from the brief win over the recipe's, and the recipe fills the rest
	var b2: Resource = ZoneBrief.new()
	b2.id = "zone"
	b2.kind = "city"
	b2.seed = 7
	b2.size_m = 460.0
	b2.rules = {"passage_m": 3.0}
	var r2: Dictionary = Generator.generate(b2, ctx)
	_check(is_equal_approx(float((r2.tree as RefCounted).rule("passage_m", 0.0)), 3.0) and String((r2.tree as RefCounted).rule("style", "")) == "city",
			"trace: the brief's rules did not win (passage %.1f, style %s)" % [float((r2.tree as RefCounted).rule("passage_m", 0.0)), String((r2.tree as RefCounted).rule("style", ""))])
	plan.free()
	_done("trace suite done (%d steps, %d parts)" % [trace.size(), late.size()])


func _crypt_suite() -> void:
	var legend: Resource = Api.default_legend()
	var plan_node: Node = Api.new_plan("Crypt", null, legend)
	root.add_child(plan_node)
	var ctx: Dictionary = Host.context(plan_node)
	var map: WorldMap = WorldBake.new_map("dungeon", 0.0, 11, 1.0, "cryptsuite")
	var brief: Resource = (map.zones[0] as Dictionary).brief
	var res: Dictionary = Generator.generate(brief, ctx)
	var tree: RefCounted = res.tree
	_check((res.warnings as PackedStringArray).is_empty(), "crypt: %s" % str(res.warnings))

	var rooms: Array = tree.children
	_check(rooms.size() >= 10 and rooms.size() <= 15, "crypt: %d rooms" % rooms.size())

	# THE ASSERTION THAT MAKES THE ZIGZAG IMPOSSIBLE TO REINTRODUCE. Every room outline comes
	# from the boundary of a set of square tiles, so every edge is axis-aligned; a 45 degree run
	# is allowed because a chamfered corner is one. Anything else means a raster crept back in.
	var band: Array = tree.rule("room_m2", [0.0, 1.0e9])
	var tile: float = float(tree.rule("tile_m", 5.0))
	var skew := 0
	var off_lattice := 0
	var too_small := 0
	var too_big := 0
	for c: RefCounted in rooms:
		var poly: PackedVector2Array = c.polygon
		var a: float = c.area()
		if a < float(band[0]):
			too_small += 1
		if a > float(band[1]):
			too_big += 1
		for i in poly.size():
			var p: Vector2 = poly[i]
			var q: Vector2 = poly[(i + 1) % poly.size()]
			var d := q - p
			if absf(d.x) > 0.001 and absf(d.y) > 0.001 and absf(absf(d.x) - absf(d.y)) > 0.01:
				skew += 1
			# EVERY VERTEX ON THE TILE LATTICE, at a QUARTER of a tile. A door stub is half a
			# tile, which used to set the grain; every room is then grown by a quarter of one so
			# the rock between two of them reads as a wall and not as a rampart
			# (`world_crypt.GAP_M`), and a quarter tile is the coarsest grid both land on.
			var grain := tile * 0.25
			if absf(p.x / grain - roundf(p.x / grain)) > 0.01 or absf(p.y / grain - roundf(p.y / grain)) > 0.01:
				off_lattice += 1
	_check(skew == 0, "crypt: %d wall edges are neither axis-aligned nor 45 degrees" % skew)
	_check(off_lattice == 0, "crypt: %d vertices are off the %.2f m lattice" % [off_lattice, tile * 0.25])
	_check(too_small == 0 and too_big == 0,
			"crypt: %d rooms under %.0f m2, %d over %.0f m2" % [too_small, float(band[0]), too_big, float(band[1])])

	# THE PARTITION DRAWS NOTHING. No adjacency means `to_parts` writes no wall line, which is
	# why (skew == 0) can never regress: the only walls are the bands around each floor island.
	_check(String(tree.boundary) == "none" and (tree.adjacency as Array).is_empty(),
			"crypt: the zone still draws %d partition lines" % (tree.adjacency as Array).size())
	var parts: Array = Generator.to_parts(tree, brief)
	var walls := 0
	var plate := 0
	for part: Dictionary in parts:
		walls += ((part.draft as Resource).get("walls") as Array).size()
		for r: Dictionary in ((part.draft as Resource).get("regions") as Array):
			if String(r.get("role", "")) == "plate":
				plate += 1
	_check(walls == 0, "crypt: %d wall lines written — a carved level has none" % walls)
	_check(plate == 0, "crypt: the root is floored, so the whole level is one island")

	# rooms do not overlap, and non-neighbours keep the rock between them
	var overlap := 0
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var a2: RefCounted = rooms[i]
			var b2: RefCounted = rooms[j]
			if int(a2.floor) != int(b2.floor):
				continue
			if not Geometry2D.intersect_polygons(a2.polygon, b2.polygon).is_empty():
				overlap += 1
	_check(overlap == 0, "crypt: %d pairs of rooms overlap" % overlap)

	# EVERY DOORWAY ON A WALL OF BOTH ROOMS IT JOINS. This is what makes a door a door: the bake
	# cuts an opening at the point by snapping it to the nearest edge of the floor island, so a
	# point that is not ON an island's edge cuts a hole somewhere else and leaves the passage
	# sealed. It cost a round: the doorway used to sit on the room's own wall face, which the
	# door stub makes INTERIOR, and the cut landed on the side of the corridor while its end
	# stayed solid — a doorway you could see through and not walk through.
	var off_wall := 0
	for g: Dictionary in tree.gates:
		var at: Vector2 = g.point
		for side in [int(g.a), int(g.b)]:
			var poly: PackedVector2Array = (rooms[side] as RefCounted).polygon
			var near := INF
			for i in poly.size():
				near = minf(near, Geometry2D.get_closest_point_to_segment(
						at, poly[i], poly[(i + 1) % poly.size()]).distance_to(at))
			if near > 0.01:
				off_wall += 1
	_check(off_wall == 0, "crypt: %d doorways are not on a wall of the room they open" % off_wall)

	# EVERY ROOM REACHABLE from the start, through the doors and nothing else
	var link := {}
	for g: Dictionary in tree.gates:
		link[int(g.a)] = (link.get(int(g.a), []) as Array) + [int(g.b)]
		link[int(g.b)] = (link.get(int(g.b), []) as Array) + [int(g.a)]
	var seen := {0: true}
	var queue: Array = [0]
	while not queue.is_empty():
		var at: int = queue.pop_back()
		for to: int in (link.get(at, []) as Array):
			if not seen.has(to):
				seen[to] = true
				queue.append(to)
	_check(seen.size() == rooms.size(), "crypt: %d of %d rooms reachable" % [seen.size(), rooms.size()])

	# ONE LOCK, AND IT IS A BRIDGE: cut it and something becomes unreachable
	var locked: Array = []
	for g: Dictionary in (brief.plan as Dictionary).gates:
		if String(g.get("key_id", "")) != "":
			locked.append(g)
	_check(locked.size() == 1, "crypt: %d locked doors" % locked.size())
	if locked.size() == 1:
		var cut: Dictionary = locked[0]
		var reach := {0: true}
		var q2: Array = [0]
		while not q2.is_empty():
			var at2: int = q2.pop_back()
			for to2: int in (link.get(at2, []) as Array):
				var crossing := (at2 == int(cut.a) and to2 == int(cut.b)) or (at2 == int(cut.b) and to2 == int(cut.a))
				if crossing or reach.has(to2):
					continue
				reach[to2] = true
				q2.append(to2)
		_check(reach.size() < rooms.size(), "crypt: the locked door is not a bridge — it locks nothing")

	# the same seed twice is the same level
	var again: Dictionary = WorldCrypt.build(11, 10, 1, 2)
	_check(str(again.rooms) == str((brief.plan as Dictionary).rooms), "crypt: two runs of one seed differ")
	var other: Dictionary = WorldCrypt.build(12, 10, 1, 2)
	_check(str(other.rooms) != str((brief.plan as Dictionary).rooms), "crypt: two seeds give the same level")

	var floors := int((brief.plan as Dictionary).floors)
	plan_node.free()
	_done("crypt suite done (%d rooms over %d floors, %d doors, %d wall lines)" % [
			rooms.size(), floors, (tree.gates as Array).size(), walls])





## THE CITY: the same recursion at the scale of a town. What is checked is what a map has to
## show — a wall with its gates, quarters, blocks of houses with the right footprints, and a
## street between every pair of blocks.
func _city_suite() -> void:
	var plan: Node = Api.new_plan("CitySuite", null, Api.default_legend(), false)
	root.add_child(plan)
	var brief: Resource = ZoneBrief.new()
	brief.id = "city"
	brief.kind = "city"
	brief.size_m = 420.0
	brief.seed = 7
	brief.cell_m = 1.0
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = Generator.generate(brief, Host.context(plan))
	var gen_ms := Time.get_ticks_msec() - t0
	var tree: RefCounted = res.tree
	var st: Dictionary = res.stats
	_check((res.warnings as PackedStringArray).is_empty(), "city: %s" % str(res.warnings))
	var quarters: Array = []
	var blocks: Array = []
	var houses: Array = []
	var walls: Array = []
	for c: RefCounted in tree.walk():
		if String(c.kind) == "wall":
			walls.append(c)
		elif String(c.kind) == "block":
			blocks.append(c)
		elif String(c.role) == "house":
			houses.append(c)
		elif int(c.depth) == 1 and String(c.role) != "wall":
			quarters.append(c)
	_check(quarters.size() >= 6, "city: %d quarters on a 420 m site" % quarters.size())
	_check(blocks.size() >= quarters.size(), "city: %d blocks for %d quarters" % [blocks.size(), quarters.size()])
	_check(houses.size() >= 150, "city: %d houses" % houses.size())
	# the curtain: runs of wall with a gap at every gate, each a floored box of its own
	var curtain: Array = []
	for c: RefCounted in walls:
		if c.parent == tree:
			curtain.append(c)
	_check(curtain.size() >= 6, "city: %d runs of curtain" % curtain.size())
	var gates := (tree.entrances as PackedVector2Array).size()
	_check(gates == int(tree.rule("gates", 0)), "city: %d gates of %d" % [gates, int(tree.rule("gates", 0))])
	for c: RefCounted in curtain:
		_check((c.polygon as PackedVector2Array).size() == 4, "city: a wall run is not a box")
		_check(bool(c.floored) and bool(c.leaf), "city: the wall run %s is not a built leaf" % c.id)
	# the runs are broken by the gates: more runs than the outline has edges
	_check(curtain.size() >= gates, "city: %d runs cannot hold %d gates" % [curtain.size(), gates])
	# every house is a BOX of the right footprint
	var lo: float = float((tree.rule("house_m2", [0.0, 0.0]) as Array)[0])
	var hi: float = float((tree.rule("house_m2", [0.0, 0.0]) as Array)[1])
	var boxes := 0
	var sized := 0
	for c: RefCounted in houses:
		if (c.polygon as PackedVector2Array).size() == 4:
			boxes += 1
		var a: float = c.area()
		if a >= lo * 0.5 and a <= hi * 1.6:
			sized += 1
	_check(boxes == houses.size(), "city: %d of %d houses are not boxes" % [houses.size() - boxes, houses.size()])
	_check(sized >= int(float(houses.size()) * 0.95), "city: %d of %d houses outside %.0f-%.0f m2" % [
			houses.size() - sized, houses.size(), lo, hi])
	# nothing is floored but the buildings: the ground belongs to the terrain
	_check(not bool(tree.floored), "city: the site is a slab")
	for c: RefCounted in quarters:
		_check(not bool(c.floored), "city: quarter %s is a slab" % c.id)
	for c: RefCounted in blocks:
		_check(not bool(c.floored), "city: block %s is a slab" % c.id)
	for c: RefCounted in houses:
		_check(bool(c.floored), "city: house %s has no floor" % c.id)
	plan.free()
	_done("city suite done (%d quarters, %d blocks, %d houses, %d walls; gen %d ms)" % [
			quarters.size(), blocks.size(), houses.size(), walls.size(), gen_ms])


## THE ROADS: a street of real width between the blocks, made by the growth's gap, and half an
## avenue kept clear along each quarter's own border by `open_border_m`.
func _roads_suite() -> void:
	var plan: Node = Api.new_plan("RoadsSuite", null, Api.default_legend(), false)
	root.add_child(plan)
	var brief: Resource = ZoneBrief.new()
	brief.id = "city"
	brief.kind = "city"
	brief.size_m = 380.0
	brief.seed = 4
	brief.cell_m = 1.0
	var res: Dictionary = Generator.generate(brief, Host.context(plan))
	var tree: RefCounted = res.tree
	var street: float = float(tree.rule("street_m", 4.0))
	var half: float = float(tree.rule("avenue_half_m", 4.0))
	var checked := 0
	var too_close := 0
	var over_border := 0
	for q: RefCounted in tree.children:
		if String(q.kind) == "wall":
			continue
		var blocks: Array = []
		for c: RefCounted in q.children:
			if String(c.kind) == "block":
				blocks.append(c)
		# every pair of blocks keeps the street between them (the grid rounds it, so a cell of
		# slack is fair)
		for i in blocks.size():
			for j in range(i + 1, blocks.size()):
				checked += 1
				if _gap_between(blocks[i].polygon, blocks[j].polygon) < street - 1.6:
					too_close += 1
		# and every block stands back from the quarter's own outline by half an avenue
		for b: RefCounted in blocks:
			var d := INF
			for p: Vector2 in (b.polygon as PackedVector2Array):
				d = minf(d, _dist_to_outline(q.polygon, p))
			if d < half - 1.6:
				over_border += 1
	_check(checked > 0, "roads: no pair of blocks to measure")
	_check(too_close == 0, "roads: %d of %d block pairs closer than the %.1f m street" % [too_close, checked, street])
	_check(over_border == 0, "roads: %d blocks inside the %.1f m border band" % [over_border, half])
	# the leftovers are regions, not slabs: the street is the terrain's, not the bake's
	var streets := 0
	for c: RefCounted in tree.walk():
		if String(c.role) == "corridor":
			streets += 1
			_check(not bool(c.floored), "roads: street %s is a slab" % c.id)
	_check(streets > 0, "roads: the growth left no street at all")
	plan.free()
	_done("roads suite done (%d block pairs, %d streets)" % [checked, streets])


## THE CASTLE IS NOT PINNED TO THE MIDDLE: the anchor vocabulary puts it where the rule says,
## and "auto" does not put it in the same place twice.
func _anchor_suite() -> void:
	var plan: Node = Api.new_plan("AnchorSuite", null, Api.default_legend(), false)
	root.add_child(plan)
	var ctx := Host.context(plan)
	var places: Array = []
	for spec: Array in [["centre", 7], ["wall", 7], ["corner", 7]]:
		var brief: Resource = ZoneBrief.new()
		brief.id = "city"
		brief.kind = "city"
		brief.size_m = 360.0
		brief.seed = int(spec[1])
		brief.cell_m = 1.5
		brief.rules = {"castle_at": String(spec[0])}
		var res: Dictionary = Generator.generate(brief, ctx)
		var tree: RefCounted = res.tree
		var castle: RefCounted = null
		for c: RefCounted in tree.children:
			if String(c.role) == "castle":
				castle = c
		_check(castle != null, "anchor: no castle with castle_at %s" % spec[0])
		if castle == null:
			continue
		var here: Vector2 = castle.centroid()
		var centre: Vector2 = tree.centroid()
		var reach := 0.0
		for p: Vector2 in (tree.polygon as PackedVector2Array):
			reach = maxf(reach, p.distance_to(centre))
		var off := here.distance_to(centre) / maxf(reach, 1.0)
		places.append([String(spec[0]), off])
		if String(spec[0]) == "centre":
			_check(off < 0.42, "anchor: centre put the castle %.2f of the way out" % off)
		else:
			_check(off > 0.20, "anchor: %s put the castle %.2f of the way out (that is the middle)" % [spec[0], off])
		# whatever the anchor, the compound is walled and stands in its own ring road
		var runs: Array = []
		for c: RefCounted in castle.children:
			if String(c.kind) == "wall":
				runs.append(c)
		_check(runs.size() >= 4, "anchor: the castle has %d runs of curtain" % runs.size())
		if not runs.is_empty():
			# the compound stands inside its quarter, a ring road all round it (a run records
			# what it inset from; the quarter's own polygon is now the ground inside the walls)
			_check(float((runs[0].params as Dictionary).get("inset_m", 0.0)) >= float(castle.rule("castle_moat_m", 0.0)) - 0.01,
					"anchor: the castle wall left no ring road")
			# and the runs go the whole way round what they enclose
			_check(float((castle.params as Dictionary).get("curtain_m", 0.0)) >= _perimeter(castle.polygon) * 0.7,
					"anchor: %.0f m of curtain around %.0f m of ground" % [
							float((castle.params as Dictionary).get("curtain_m", 0.0)), _perimeter(castle.polygon)])
	# "auto" reads the site, so two seeds are two different towns
	var spots: Array = []
	for seed in [3, 7]:
		var brief: Resource = ZoneBrief.new()
		brief.id = "city"
		brief.kind = "city"
		brief.size_m = 360.0
		brief.seed = seed
		brief.cell_m = 1.5
		var res: Dictionary = Generator.generate(brief, ctx)
		for c: RefCounted in (res.tree as RefCounted).children:
			if String(c.role) == "castle":
				var t: RefCounted = res.tree
				spots.append((c.centroid() - t.centroid()) / maxf(t.bbox().size.x, 1.0))
	_check(spots.size() == 2 and (spots[0] as Vector2).distance_to(spots[1]) > 0.08,
			"anchor: auto put the castle in the same place for two seeds (%s)" % str(spots))
	plan.free()
	_done("anchor suite done (%s)" % str(places))


## The shortest distance between two polygons' outlines (they never overlap here).
func _gap_between(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := INF
	for i in a.size():
		for j in b.size():
			var p := Geometry2D.get_closest_point_to_segment(a[i], b[j], b[(j + 1) % b.size()])
			best = minf(best, p.distance_to(a[i]))
			var q := Geometry2D.get_closest_point_to_segment(b[j], a[i], a[(i + 1) % a.size()])
			best = minf(best, q.distance_to(b[j]))
	return best


func _dist_to_outline(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(p))
	return best


func _perimeter(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += (poly[(i + 1) % poly.size()] - poly[i]).length()
	return s


func _poly_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5


## THE COAST: a town that faces the water across one straight edge. Everything about it that
## could quietly come out wrong is a relationship between two things decided in different files
## — the outline and the shore half-plane, the palisade and the water, the gates and the wall —
## so what is checked here is the agreements, not the numbers.
func _coast_suite() -> void:
	var map: WorldMap = WorldBake.new_map("coast", 380.0, 5, 0.6, "coastsuite")
	var brief: Resource = (map.zones[0] as Dictionary).brief
	var site: Dictionary = map.site
	var shore_n: Vector2 = site.shore_n
	var shore_d := float(site.shore_d)
	var quay := float(site.quay_m)
	# THE OUTLINE IS DRY. Every point of the town's boundary is landward of the waterline: a
	# town whose own outline crosses the shore is a town with houses in the sea.
	var poly: PackedVector2Array = brief.outline()
	_check(poly.size() >= 6, "coast: the outline has %d points" % poly.size())
	var wet := 0
	var on_shore := 0
	for pt in poly:
		var sd := pt.dot(shore_n) - shore_d
		if sd > 0.01:
			wet += 1
		if absf(sd) <= 0.01:
			on_shore += 1
	_check(wet == 0, "coast: %d points of the outline are in the water" % wet)
	_check(on_shore >= 2, "coast: only %d points sit on the waterline — the chord is not straight" % on_shore)
	# the brief's own half-plane stands BACK from the terrain's by the quay: one line would
	# either fence off the quays or flood them
	_check(absf(float(brief.rules.shore_d) - (shore_d - quay)) < 0.01,
			"coast: the wall line and the water line are the same line")
	var plan: Node = Api.new_plan("Coast", null, Api.default_legend(), false)
	root.add_child(plan)
	var res: Dictionary = Generator.generate(brief, Host.context(plan))
	var tree: RefCounted = res.tree
	var st: Dictionary = res.stats
	var roles: Dictionary = st.roles
	for want in ["harbour", "residential", "craft", "market"]:
		_check(int(roles.get(want, 0)) >= 1, "coast: no %s quarter" % want)
	_check(int(roles.get("pier", 0)) >= 3, "coast: %d piers" % int(roles.get("pier", 0)))
	# THE GATES ARE LANDWARD, every one of them: a gate on the water is a gap in a wall that
	# was never built there
	var sea_gates := 0
	for e: Vector2 in tree.entrances:
		if e.dot(shore_n) > float(brief.rules.shore_d) + 0.01:
			sea_gates += 1
	_check(tree.entrances.size() >= 2, "coast: %d gates" % tree.entrances.size())
	_check(sea_gates == 0, "coast: %d gates open onto the sea" % sea_gates)
	# THE PALISADE STOPS AT THE WATER: runs on the landward arc, none across the chord
	var runs := 0
	var sea_runs := 0
	for c: RefCounted in tree.children:
		if String(c.kind) != "wall":
			continue
		runs += 1
		if c.centroid().dot(shore_n) > float(brief.rules.shore_d) + 0.01:
			sea_runs += 1
	_check(runs >= 3, "coast: %d runs of palisade" % runs)
	_check(sea_runs == 0, "coast: %d runs of palisade stand in the water" % sea_runs)
	# the harbour is ON the water: nearer the shore than the town's own centre is
	var centre: Vector2 = tree.centroid()
	for c: RefCounted in tree.children:
		if String(c.role) != "harbour":
			continue
		_check(c.centroid().dot(shore_n) > centre.dot(shore_n),
				"coast: the harbour is further from the water than the middle of the town")
	# FEWER HOUSES THAN A CITY, and bigger: the whole point of the kind
	var houses := 0
	var small := 0
	for c: RefCounted in tree.walk():
		if String(c.role) != "house":
			continue
		houses += 1
		if c.area() < 45.0:
			small += 1
	_check(houses >= 15 and houses <= 160, "coast: %d houses on a 380 m site" % houses)
	_check(small == 0, "coast: %d houses under 45 m²" % small)
	plan.free()
	_done("coast suite done (%d houses, %d piers, %d gates, %d runs of palisade)" % [
			houses, int(roles.get("pier", 0)), tree.entrances.size(), runs])


func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _done(msg: String) -> void:
	_suites_done += 1
	_say("[VERIFY] " + msg)


func _say(msg: String) -> void:
	print(msg)
	_log += msg + "\n"

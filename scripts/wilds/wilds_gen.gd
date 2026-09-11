@tool
class_name WildsGen
extends Object
## Pure derivation: WildsMap in, everything else out — tiers, ramps, reachability, cliff
## segments, per-chunk mesh arrays and collision faces. No nodes, no scene, no physics; the
## editor preview, the runtime zone and the headless suites all call this one entry point, so
## they cannot disagree (the DungeonLayout argument, applied to countryside).
##
## Staged like GladeKit's wall pipeline: TIERS -> RAMPS -> SEGMENTS -> MESH(+COLLISION), each
## stage reading what came before and writing only its own keys into the derived dictionary.
## Randomness is keyed to WHERE, never WHEN: every draw is a hash of (seed, cell) — painting
## one corner of the map cannot reshuffle the far corner (GladeKit's Law 1).
##
## THE SEAM LAW: every cell corner's XZ jitter is computed from the corner's own integer grid
## coordinates + the seed, so the two cells sharing a corner — including across chunk borders —
## place it identically. Chunks need no stitch bookkeeping because there is nothing to stitch.
## Y is NEVER jittered: tops sit exactly on tier * tier_height, which is what keeps the stepped
## terrace read crisp and height_at() honest.
##
## THE WINDING LAW (terrain_field.gd's, restated): Godot's front face is CLOCKWISE about the
## outward normal, so for every triangle (a, b, c) the cross (b-a)x(c-a) must OPPOSE the
## outward normal. _tri() enforces it by construction; the suite asserts it anyway.

const CHUNK := 32                             ## cells per chunk side — rebuild-locality unit
const JITTER := 0.35                          ## of a cell, per axis; corners can never cross

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## The whole derivation. Returns:
##   tiers: PackedInt32Array           final per-cell tier (shelf demotions included)
##   ramps: Dictionary                 cell idx -> Vector2i climb direction (on the LOW cell)
##   spawn: Vector2i                   the cell SpawnA stands on
##   walkable: Dictionary              idx -> true
##   reached: Dictionary               idx -> true (the guarantee: == walkable)
##   auto_ramps / shelves: int         what reachability had to carve (counted, not swallowed)
##   segments: Array[Dictionary]       {cell, side, drop} — cliff runs, the future kit seam
##   chunks: Array[Dictionary]         {origin, top: mesh arrays, cliff: mesh arrays,
##                                      faces: PackedVector3Array (collision, same triangles)}
##   min_tier / max_tier: int
## THE DEFAULT lake depth, in metres below the tier top at mid-water. The MAP may override it -
## see WildsMap.lake_depth - because how deep a lake is belongs to the place, not to the engine.
## Read through bed_deep(map) everywhere; this constant is only the fallback when there is no map.
const BED_DEEP := 0.9
const BED_SHALLOW := 0.2                      ## at the shore — ABOVE the surface: a wet beach
const SURFACE_DROP := 0.35                    ## water surface below the tier top


## The mid-water bed drop this map asks for, falling back to the constant.
static func bed_deep(m) -> float:
	return BED_DEEP if m == null else float(m.lake_depth)
const SEA_WALL := 2.5                         ## invisible rim over the SEA border's outer face


## `guarantee` runs the reachability repair (auto-carved ramps + shelf demotions) — the
## small-map contract. FALSE leaves the terrain exactly as noise + paint say, painted ramps
## only: the region path's semantics, where traversal is the JUMP plus what the author drew.
static func derive(map: WildsMap, guarantee := true) -> Dictionary:
	var d := derive_light(map, guarantee)
	_stage_mesh(map, d)
	return d


## Everything EXCEPT the mesh: tiers, ramps, water regions, segments, reachability — all the
## canvas ever reads. The mesh stage costs real time and only a 3D build consumes `chunks`.
static func derive_light(map: WildsMap, guarantee := true) -> Dictionary:
	var d := {}
	_stage_tiers(map, d)
	_stage_ramps(map, d, guarantee)
	_stage_water(map, d)
	_stage_segments(map, d)
	return d


## EVERYTHING ONE REGION NEEDS, computed without touching the rest of the world — the 14 km
## answer: derivation cost is the cost of the window, not of the map. `rect` is the CELL
## rectangle the result must serve (for a streamed chunk: the chunk itself); halos are taken
## internally — tiers over rect+2 (painted-ramp resolution on the rect+1 ring reads one
## further), ramps over rect+1 (segment suppression), segments/water for rect(+1). The keys
## mirror the full derive's, with Dictionaries where the full path uses whole-map arrays; the
## mesh reads both through untyped access, and the equivalence suite holds the two paths to
## byte-for-byte agreement. NO reachability: on a region-derived world, traversal is the jump
## plus painted ramps — the guarantee is a small-map (full-derive) feature.
static func derive_region(map: WildsMap, rect: Rect2i) -> Dictionary:
	var full := Rect2i(0, 0, map.cells_w, map.cells_h)
	var r := rect.intersection(full)
	var tr := r.grow(2).intersection(full)
	var base := _tiers_window(map, tr)
	var tiers := {}
	for wz in range(tr.position.y, tr.end.y):
		for wx in range(tr.position.x, tr.end.x):
			var i := wz * map.cells_w + wx
			tiers[i] = _finish_tier(map, Vector2i(wx, wz),
					base[(wz - tr.position.y) * tr.size.x + (wx - tr.position.x)])
	var d := {"rect": r, "tiers": tiers, "min_tier": 0, "max_tier": map.max_tier}
	var ramps := {}
	var rr := r.grow(1).intersection(full)
	for wz in range(rr.position.y, rr.end.y):
		for wx in range(rr.position.x, rr.end.x):
			var i := wz * map.cells_w + wx
			if (map.flag_at(i) & WildsMap.F_RAMP_PAINTED) != 0 \
					and not is_water(map, i) and not _in_border(map, Vector2i(wx, wz)):
				var dir := _painted_ramp_dir(map, tiers, i)
				if dir != Vector2i.ZERO:
					ramps[i] = dir
	d.ramps = ramps
	_water_components(map, d, r.grow(1).intersection(full))
	_segments_for(map, d, r)
	return d


# ---------------------------------------------------------------- BORDER --------------------
# THE WORLD'S EDGE IS NEVER A STRAIGHT LINE AND NEVER WALKABLE, whatever the map size: a
# rising cliff rim of >=2-tier steps (the jump clears exactly one — the rim is a wall to it)
# or open sea, along a seeded noise line that wanders through the border band. Every function
# here is PURE in (map, cell) — no scan, no state — which is what keeps the border identical
# in the full derive, in every region, on the canvas and in the far LOD.

## Water as the WORLD sees it: painted, or the border sea. Every water decision in the
## pipeline goes through here — never through the raw flag.
static func is_water(map: WildsMap, i: int) -> bool:
	if (map.flag_at(i) & WildsMap.F_WATER) != 0:
		return true
	return map.border_mode == WildsMap.BORDER_SEA \
			and _in_border(map, Vector2i(i % map.cells_w, i / map.cells_w))


## WHERE WATER ENTERS. A spring only counts where there is water to enter, so this is the
## painted flag AND is_water — same shape as every other predicate here, pure in (map, i).
##
## Why painted rather than derived: a source is the catchment this map does not model. The
## terrain can say which way water would run, and does (flow_at), but it cannot say how much
## arrives or from where, because the answer is off the edge of what the generator knows.
static func is_spring(map: WildsMap, i: int) -> bool:
	return (map.flag_at(i) & WildsMap.F_SPRING) != 0 and is_water(map, i)


static func _edge_d(map: WildsMap, c: Vector2i) -> int:
	return mini(mini(c.x, c.y), mini(map.cells_w - 1 - c.x, map.cells_h - 1 - c.y))


static func _in_border(map: WildsMap, c: Vector2i) -> bool:
	if map.border_mode == WildsMap.BORDER_NONE:
		return false
	var d := _edge_d(map, c)
	if d >= map.border_cells:
		return false
	return float(d) < _border_limit(map, c)


## How deep the border reaches at this cell: the band width warped by a coarse value noise,
## so the coastline / rim line meanders instead of tracing the square.
static func _border_limit(map: WildsMap, c: Vector2i) -> float:
	return map.border_cells * (0.55 + 0.45 * _border_noise(map, c))


## Coarse-lattice value noise in [0,1), ~12-cell period, arithmetic (the hot-loop hash law).
static func _border_noise(map: WildsMap, c: Vector2i) -> float:
	var lx := c.x / 12
	var lz := c.y / 12
	var fx := float(c.x % 12) / 12.0
	var fz := float(c.y % 12) / 12.0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var sd := map.seed + 0x51DE
	var h00 := float(_hmix(sd, lx, lz)) / 2147483647.0
	var h10 := float(_hmix(sd, lx + 1, lz)) / 2147483647.0
	var h01 := float(_hmix(sd, lx, lz + 1)) / 2147483647.0
	var h11 := float(_hmix(sd, lx + 1, lz + 1)) / 2147483647.0
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


## The cliff rim's tier ADD: ceil(depth * 2) + 1, so consecutive rim cells climb by two or
## more — stairs the jump cannot take. Zero everywhere but a CLIFFS border band.
static func _border_shift(map: WildsMap, c: Vector2i) -> int:
	if map.border_mode != WildsMap.BORDER_CLIFFS:
		return 0
	var d := _edge_d(map, c)
	if d >= map.border_cells:
		return 0
	var k := _border_limit(map, c) - float(d)
	if k <= 0.0:
		return 0
	return int(ceil(k * 2.0)) + 1


## Tiers + paint + border, the one post-pass both derive paths share: the sea floor is flat
## zero, the rim adds its shift, everything floors at 0. Applied AFTER the chamfer — border
## is authored world shape, not noise to be smoothed.
static func _finish_tier(map: WildsMap, c: Vector2i, base: int) -> int:
	if map.border_mode == WildsMap.BORDER_SEA and _in_border(map, c):
		return 0
	return maxi(base + map.tier_paint_at(map.idx(c)) + _border_shift(map, c), 0)


# ---------------------------------------------------------------- FLOW ----------------------
# WHICH WAY THE WATER GOES, derived rather than solved.
#
# The reference implementations of this (River Editor's GPU Lattice-Boltzmann, and the SPH
# family) run a solver to obtain a velocity field. We cannot: a solver is stateful and global,
# and this generator is keyed to WHERE and never WHEN — the lazy path derives a 34-cell window
# and never sees the world, so there is no river graph to solve over and region ids are not
# even stable between chunks. Note the LBM author's own stated endgame is to bake his velocity
# field offline into a virtual texture; a procedural world can simply START there.
#
# So flow is a PURE FUNCTION of (map, tiers, cell), like is_water and _finish_tier before it,
# and it is the sum of three local terms:
#
#   SLOPE      down the CONTINUOUS land height. The terraces are quantised from a smooth FBM
#              field, and that field still slopes across a reach whose tiers are all equal —
#              so the stylization is what is stepped, the land underneath is not. This is the
#              term that makes a whole pool know which way its river runs. A purely local
#              tier test cannot: it fires only on the one cell touching the drop, which is
#              exactly what the first cut of this did (measured: 0.05 everywhere, all eddy).
#   DROP       an extra kick toward any lower neighbour, so the water visibly gathers pace in
#              the last cell before it spills.
#   BANK       away from dry neighbours, so a current follows its channel instead of crossing
#              it. In a channel both banks push and cancel, leaving the slope alone.
#   EDDY       the CURL of a value-noise field. Curl is divergence-free by construction, so it
#              can only ever swirl — it cannot invent a source or a sink the way a noise vector
#              would. This is the cheap, honest stand-in for the vorticity LBM is prized for.
#
# The result is unit-less; a metres-per-second scale is applied by the reader (shader uniform
# and water_flow_at alike), so retuning speed never costs a rebake.

const FLOW_SLOPE := 6.0                       ## gain on the continuous land gradient
const FLOW_SLOPE_MAX := 1.2                   ## ...clamped, so a cliff face is not a firehose
## Per tier of drop toward a lower neighbour, and deliberately larger than FLOW_SLOPE_MAX: a
## real spill edge must spill. The tiers are the ground truth for where water LEAVES, and the
## smooth land noise they were quantised from can disagree with them locally (the chamfer
## clamp, paint and the border all bend tiers away from the raw field) — where the two
## disagree, the drop wins.
const FLOW_DROP := 2.0
const FLOW_BANK := 0.35                       ## per dry neighbour, pushing off the bank
const FLOW_EDDY := 0.5                        ## curl-noise swirl
const FLOW_EDDY_CELLS := 8                    ## eddy lattice period, in cells (~16 m)


## The flow vector on a cell, in the map's XZ. Vector2.ZERO on dry ground — a caller can add
## this to anything unconditionally. `tiers` is indexable by global cell index and may be a
## whole-map PackedInt32Array or a window Dictionary; reads outside it fall back rather than
## erroring, which is what lets a bake sample the halo around its own rect.
static func flow_at(map: WildsMap, tiers, c: Vector2i) -> Vector2:
	if not map.in_bounds(c) or not is_water(map, map.idx(c)):
		return Vector2.ZERO
	var t := _tier_read(map, tiers, c, 0)
	var v := _slope_at(map, c)
	for dir: Vector2i in DIRS:
		var nb := c + dir
		var d2 := Vector2(dir.x, dir.y)
		if not map.in_bounds(nb):
			continue                          # the world's edge pulls nothing off it
		# Falling back to our OWN tier means an unknown neighbour contributes no pull —
		# a halo miss must never invent a waterfall.
		var nt := _tier_read(map, tiers, nb, t)
		if nt < t:
			v += d2 * (float(t - nt) * FLOW_DROP)
		elif not is_water(map, map.idx(nb)):
			# A bank only pushes back when it is a WALL — at our level or above. Dry ground
			# BELOW us is not a bank, it is a waterfall, and the drop above already sent the
			# water over it; pushing away from it too would make a lake rim refuse to spill.
			v -= d2 * FLOW_BANK
	return v + _flow_eddy(map, c)


## Downhill on the CONTINUOUS land, i.e. minus the gradient of the same FBM field the tiers
## were quantised from. Pure in (map, cell) and needs no halo at all — the noise is a function
## of position, so a region derive and the full derive sample the identical field.
static func _slope_at(map: WildsMap, c: Vector2i) -> Vector2:
	var n := _land_noise(map)
	var cs := map.cell_size
	var wx := (c.x + 0.5) * cs
	var wz := (c.y + 0.5) * cs
	var g := Vector2(n.get_noise_2d(wx + cs, wz) - n.get_noise_2d(wx - cs, wz),
			n.get_noise_2d(wx, wz + cs) - n.get_noise_2d(wx, wz - cs))
	var len := g.length()
	if len < 0.00001:
		return Vector2.ZERO
	return (-g / len) * minf(len * FLOW_SLOPE, FLOW_SLOPE_MAX)


## The swirl alone, kept separate so the suite can hold IT to divergence-free without the
## slope term (which legitimately has divergence) drowning the measurement.
## curl(psi) = (d psi/d z, -d psi/d x), central differences on the cell lattice.
static func _flow_eddy(map: WildsMap, c: Vector2i) -> Vector2:
	var dx := _flow_noise(map, c + Vector2i(1, 0)) - _flow_noise(map, c - Vector2i(1, 0))
	var dz := _flow_noise(map, c + Vector2i(0, 1)) - _flow_noise(map, c - Vector2i(0, 1))
	return Vector2(dz, -dx) * FLOW_EDDY


## The land's own noise, rebuilt from the map's dials and cached by them — the same object
## _tiers_window builds, so flow runs downhill on exactly the field the terraces came from.
static var _land_key := ""
static var _land_obj: FastNoiseLite = null

static func _land_noise(map: WildsMap) -> FastNoiseLite:
	var key := "%d|%s|%d" % [map.seed, map.noise_freq, map.noise_octaves]
	if key != _land_key or _land_obj == null:
		var n := FastNoiseLite.new()
		n.seed = map.seed
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = map.noise_octaves
		n.frequency = map.noise_freq
		_land_obj = n
		_land_key = key
	return _land_obj


## Tier lookup that tolerates both derive shapes AND a miss. wilds_terrain.height_at's bare
## subscript hard-errors on a cell outside a cached region; nothing here may do that, because
## a flow bake deliberately reads one cell past its own window.
static func _tier_read(map: WildsMap, tiers, c: Vector2i, fallback: int) -> int:
	if not map.in_bounds(c):
		return fallback
	var i := map.idx(c)
	if tiers is Dictionary:
		return int((tiers as Dictionary).get(i, fallback))
	return (tiers as PackedInt32Array)[i]


## Value noise on a coarse lattice, in [0,1) — _border_noise's arithmetic hash idiom with its
## own salt, so eddies and coastlines never rhyme.
static func _flow_noise(map: WildsMap, c: Vector2i) -> float:
	@warning_ignore("integer_division")
	var lx := c.x / FLOW_EDDY_CELLS
	@warning_ignore("integer_division")
	var lz := c.y / FLOW_EDDY_CELLS
	var fx := float(posmod(c.x, FLOW_EDDY_CELLS)) / float(FLOW_EDDY_CELLS)
	var fz := float(posmod(c.y, FLOW_EDDY_CELLS)) / float(FLOW_EDDY_CELLS)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var sd := map.seed + 0x0F10
	var h00 := float(_hmix(sd, lx, lz)) / 2147483647.0
	var h10 := float(_hmix(sd, lx + 1, lz)) / 2147483647.0
	var h01 := float(_hmix(sd, lx, lz + 1)) / 2147483647.0
	var h11 := float(_hmix(sd, lx + 1, lz + 1)) / 2147483647.0
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


# ---------------------------------------------------------------- WATER ---------------------

## Painted water cells become REGIONS (4-connected same-tier components). Every reach of a
## painted river that steps a tier becomes its own region with its own flat surface, the
## cliff between them carrying the (future) waterfall. Emits: region_of {cell idx -> region
## idx, absent = dry} and regions [{cells, tier, bounds}]. Because a component is SAME-TIER by
## construction, clipping the scan to a window cannot change any region's level — which is
## what lets derive_region reuse this verbatim.
static func _stage_water(map: WildsMap, d: Dictionary) -> void:
	_water_components(map, d, Rect2i(0, 0, map.cells_w, map.cells_h))


static func _water_components(map: WildsMap, d: Dictionary, rect: Rect2i) -> void:
	var tiers = d.tiers
	var region_of := {}
	var regions: Array = []
	for sz in range(rect.position.y, rect.end.y):
		for sx in range(rect.position.x, rect.end.x):
			var start_i := sz * map.cells_w + sx
			if not is_water(map, start_i) or region_of.has(start_i):
				continue
			var cells: Array[int] = []
			var lo_tier := 1 << 30
			var bounds := Rect2i(Vector2i(sx, sz), Vector2i.ONE)
			var queue: Array = [start_i]
			region_of[start_i] = regions.size()
			while not queue.is_empty():
				var i: int = queue.pop_back()
				cells.append(i)
				lo_tier = mini(lo_tier, tiers[i])
				var c := Vector2i(i % map.cells_w, i / map.cells_w)
				bounds = bounds.expand(c).expand(c + Vector2i.ONE)
				for dir in DIRS:
					var nb := c + dir
					if not map.in_bounds(nb) or not rect.has_point(nb):
						continue
					var inb := map.idx(nb)
					if is_water(map, inb) \
							and not region_of.has(inb) and tiers[inb] == tiers[i]:
						region_of[inb] = regions.size()
						queue.append(inb)
			regions.append({"cells": cells, "tier": lo_tier, "bounds": bounds})
	d.region_of = region_of
	d.regions = regions


# ---------------------------------------------------------------- TIERS ---------------------

## The noise BASE (post-sweeps, pre-paint) depends only on the generation dials, never on
## paint — cached so a paint stroke pays the paint pass alone instead of resampling and
## re-sweeping the whole field (74 ms of every stroke on a 112x90 map, measured). Keyed by
## every input that shapes it; determinism is untouched because the cache holds exactly what
## recomputation would produce.
static var _base_key := ""
static var _base := PackedInt32Array()


static func _stage_tiers(map: WildsMap, d: Dictionary) -> void:
	var key := "%d|%d|%d|%s|%d|%d|%s" % [map.seed, map.cells_w, map.cells_h,
			map.noise_freq, map.noise_octaves, map.max_tier, map.cell_size]
	var tiers: PackedInt32Array
	if key == _base_key:
		tiers = _base.duplicate()
	else:
		tiers = _tiers_window(map, Rect2i(0, 0, map.cells_w, map.cells_h))
		_base = tiers.duplicate()
		_base_key = key
	for i in map.cell_count():
		tiers[i] = _finish_tier(map, Vector2i(i % map.cells_w, i / map.cells_w), tiers[i])
	d.tiers = tiers
	var lo := 1 << 30
	var hi := -(1 << 30)
	for i in map.cell_count():
		lo = mini(lo, tiers[i])
		hi = maxi(hi, tiers[i])
	d.min_tier = lo
	d.max_tier = hi


## How far one cell's noise base can influence another through the roll clamp: a base of 0
## pulls a neighbour down at 2 per step, so beyond max_tier/2 steps it cannot bite. A window
## grown by this many cells computes tiers EXACTLY — the fact region derivation stands on.
static func clamp_halo(map: WildsMap) -> int:
	return int(map.max_tier / 2.0) + 1


## The tier BASE (quantised noise, roll-clamped, PRE-paint) for `rect`, exact and order-free:
## tier[i] = min over j of (base[j] + 2 * manhattan(i, j)), computed as a two-pass chamfer
## distance transform over rect grown by clamp_halo — O(n), no raster-cascade (the old
## in-place sweeps could carry an update across the whole row in one pass, which is why they
## could never be region-local). Returns rect-local row-major values.
static func _tiers_window(map: WildsMap, rect: Rect2i) -> PackedInt32Array:
	var full := Rect2i(0, 0, map.cells_w, map.cells_h)
	var w := rect.grow(clamp_halo(map)).intersection(full)
	var n := FastNoiseLite.new()
	n.seed = map.seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = map.noise_octaves
	n.frequency = map.noise_freq
	var ww := w.size.x
	var wh := w.size.y
	var t := PackedInt32Array()
	t.resize(ww * wh)
	for wz in wh:
		for wx in ww:
			var v := n.get_noise_2d((w.position.x + wx + 0.5) * map.cell_size,
					(w.position.y + wz + 0.5) * map.cell_size)
			t[wz * ww + wx] = clampi(
					int(floor((v * 0.5 + 0.5) * float(map.max_tier + 1))), 0, map.max_tier)
	for wz in wh:                                 # forward chamfer: left + top
		for wx in ww:
			var i := wz * ww + wx
			if wx > 0:
				t[i] = mini(t[i], t[i - 1] + 2)
			if wz > 0:
				t[i] = mini(t[i], t[i - ww] + 2)
	for wz in range(wh - 1, -1, -1):              # backward chamfer: right + bottom
		for wx in range(ww - 1, -1, -1):
			var i := wz * ww + wx
			if wx < ww - 1:
				t[i] = mini(t[i], t[i + 1] + 2)
			if wz < wh - 1:
				t[i] = mini(t[i], t[i + ww] + 2)
	var out := PackedInt32Array()
	out.resize(rect.size.x * rect.size.y)
	for rz in rect.size.y:
		for rx in rect.size.x:
			out[rz * rect.size.x + rx] = t[(rect.position.y - w.position.y + rz) * ww
					+ (rect.position.x - w.position.x + rx)]
	return out


# ---------------------------------------------------------------- RAMPS ---------------------

## Reachability is a GUARANTEE, not a hope: after this stage every walkable cell reaches the
## spawn, on every seed, by construction — the wilds equivalent of the dungeon's "the walk
## keeps the graph a tree". Carves are deterministic (lowest hash wins) and edit-local.
static func _stage_ramps(map: WildsMap, d: Dictionary, guarantee := true) -> void:
	var tiers: PackedInt32Array = d.tiers
	var walkable := {}
	for i in map.cell_count():
		if not is_water(map, i) \
				and not _in_border(map, Vector2i(i % map.cells_w, i / map.cells_w)):
			walkable[i] = true
	var ramps := {}
	# Painted ramps first: the author's ramps climb toward whichever neighbour stands one tier
	# up (lowest hash when several do).
	for i in walkable:
		if (map.flag_at(i) & WildsMap.F_RAMP_PAINTED) != 0:
			var dir := _painted_ramp_dir(map, tiers, i)
			if dir != Vector2i.ZERO:
				ramps[i] = dir

	var spawn := map.spawn_cell
	if not map.in_bounds(spawn) or not walkable.has(map.idx(spawn)):
		spawn = _auto_spawn(map, tiers, walkable)

	var auto_ramps := 0
	var shelves := 0
	if not guarantee:
		# Painted ramps only — no carves, no shelves, no repair. The flood still runs so
		# `reached` is honest information (the dock reports stranding as advisory).
		d.tiers = tiers
		d.ramps = ramps
		d.spawn = spawn
		d.walkable = walkable
		d.reached = _flood(map, tiers, walkable, ramps, spawn)
		d.auto_ramps = 0
		d.shelves = 0
		return
	var reached := _flood(map, tiers, walkable, ramps, spawn)
	# CANDIDATES ARE MAINTAINED, NOT RESCANNED. The old loop re-walked every unreached cell
	# per carve — O(carves x unreached), ~300 ms of every paint stroke on a 112x90 map
	# (measured), all of it re-discovering pairs it had already seen. One seed scan fills the
	# pools; each flood expansion offers only the pairs around newly reached cells; entries
	# whose unreached side got absorbed (or whose low cell got a ramp) go stale and are
	# discarded at pick time. A shelf changes tiers, so it re-floods AND re-seeds — the rare
	# repair keeps paying its honest full price.
	var cands := {"ramp": {}, "shelf": {}, "rheap": [], "sheap": []}
	_seed_candidates(map, tiers, walkable, ramps, reached, cands)
	var guard := map.cell_count() * 4
	while reached.size() < walkable.size() and guard > 0:
		guard -= 1
		var carve := _pick_carve(ramps, reached, cands)
		if carve.is_empty():
			break                             # nothing carvable at all; counted below
		if carve.kind == "ramp":
			ramps[carve.low] = carve.dir
			auto_ramps += 1
			# INCREMENTAL: a new ramp only ever ADDS crossings, so the flood continues from
			# the two cells it joins instead of restarting — the difference between a derive
			# in milliseconds and one in seconds on a fragmented map. Both ends are offered;
			# _flood_more expands from whichever already stands in the reached set.
			var low_c := Vector2i(carve.low % map.cells_w, carve.low / map.cells_w)
			var fresh := _flood_more(map, tiers, walkable, ramps, reached,
					[low_c, low_c + (carve.dir as Vector2i)])
			for r: Vector2i in fresh:
				var ir := map.idx(r)
				for dir in DIRS:
					var nbc := r + dir
					if map.in_bounds(nbc):
						var inb := map.idx(nbc)
						if walkable.has(inb) and not reached.has(inb):
							_offer(map, tiers, cands, inb, ir, -dir)
		else:
			tiers[carve.cell] += carve.step   # a demoted shelf, one tier toward the reached side
			shelves += 1
			# A tier change can REMOVE crossings as well as add them; only a full re-flood is
			# honest here. Shelves are the rare repair, so the cost stays where it belongs.
			reached = _flood(map, tiers, walkable, ramps, spawn)
			cands = {"ramp": {}, "shelf": {}, "rheap": [], "sheap": []}
			_seed_candidates(map, tiers, walkable, ramps, reached, cands)

	d.tiers = tiers
	d.ramps = ramps
	d.spawn = spawn
	d.walkable = walkable
	d.reached = reached
	d.auto_ramps = auto_ramps
	d.shelves = shelves


static func _auto_spawn(map: WildsMap, tiers: PackedInt32Array, walkable: Dictionary) -> Vector2i:
	# The modal tier is where most of the map lives; the spawn goes to the walkable cell on it
	# nearest the centre — deterministic scan, no rng to desync.
	var counts := {}
	for i in walkable:
		counts[tiers[i]] = int(counts.get(tiers[i], 0)) + 1
	var modal := 0
	var best_n := -1
	for t in counts:
		if counts[t] > best_n or (counts[t] == best_n and t < modal):
			best_n = counts[t]
			modal = t
	var centre := Vector2(map.cells_w, map.cells_h) * 0.5
	var pick := Vector2i.ZERO
	var best_d := 1e12
	for i in walkable:
		if tiers[i] != modal:
			continue
		var c := Vector2i(i % map.cells_w, i / map.cells_w)
		var dist := centre.distance_squared_to(Vector2(c) + Vector2(0.5, 0.5))
		if dist < best_d:
			best_d = dist
			pick = c
	return pick


static func _can_cross(tiers: PackedInt32Array, ramps: Dictionary, ia: int, ib: int,
		dir: Vector2i) -> bool:
	var ta := tiers[ia]
	var tb := tiers[ib]
	if ta == tb:
		return true
	if tb == ta + 1 and ramps.get(ia, Vector2i.ZERO) == dir:
		return true                           # up my own ramp
	if ta == tb + 1 and ramps.get(ib, Vector2i.ZERO) == -dir:
		return true                           # down the neighbour's ramp
	return false


static func _flood(map: WildsMap, tiers: PackedInt32Array, walkable: Dictionary,
		ramps: Dictionary, spawn: Vector2i) -> Dictionary:
	var reached := {}
	if not walkable.has(map.idx(spawn)):
		return reached
	reached[map.idx(spawn)] = true
	_flood_more(map, tiers, walkable, ramps, reached, [spawn])
	return reached


## Continue an existing flood from the given seed cells — the incremental half of the carver.
## Returns the cells newly reached by THIS call, so the carve loop can offer only the frontier
## pairs around them.
static func _flood_more(map: WildsMap, tiers: PackedInt32Array, walkable: Dictionary,
		ramps: Dictionary, reached: Dictionary, seeds: Array) -> Array:
	var fresh: Array = []
	var queue: Array = []
	for s: Vector2i in seeds:
		if reached.has(map.idx(s)):
			queue.append(s)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		var ic := map.idx(c)
		for dir in DIRS:
			var nb := c + dir
			if not map.in_bounds(nb):
				continue
			var inb := map.idx(nb)
			if not walkable.has(inb) or reached.has(inb):
				continue
			if _can_cross(tiers, ramps, ic, inb, dir):
				reached[inb] = true
				queue.append(nb)
				fresh.append(nb)
	return fresh


## Fill the candidate pools from scratch: every (unreached, reached) frontier pair, offered.
static func _seed_candidates(map: WildsMap, tiers: PackedInt32Array, walkable: Dictionary,
		_ramps: Dictionary, reached: Dictionary, cands: Dictionary) -> void:
	for ib in walkable:
		if reached.has(ib):
			continue
		var b := Vector2i(ib % map.cells_w, ib / map.cells_w)
		for dir in DIRS:
			var a := b + dir
			if map.in_bounds(a) and reached.has(map.idx(a)):
				_offer(map, tiers, cands, ib, map.idx(a), dir)


## Record one frontier pair (b unreached, a reached, `dir` running b -> a) as repair
## candidates. Hashes are arithmetic bit-mixes keyed to WHERE (the format-string hash law):
## picks are content-determined, never insertion-order-determined.
static func _offer(map: WildsMap, tiers: PackedInt32Array, cands: Dictionary,
		ib: int, ia: int, dir: Vector2i) -> void:
	var dt: int = tiers[ib] - tiers[ia]
	if dt == 0:
		return
	if absi(dt) == 1:
		var low_i := ia if dt > 0 else ib
		if (map.flag_at(low_i) & WildsMap.F_RAMP_FORBIDDEN) != 0:
			return
		# `dir` runs UNREACHED -> reached, so the climb (low -> high) is its negation when
		# the reached side is the low one.
		var up: Vector2i = -dir if dt > 0 else dir
		var key := low_i * 4 + DIRS.find(up)
		if not (cands.ramp as Dictionary).has(key):
			var h := _hmix(map.seed, low_i, DIRS.find(up))
			cands.ramp[key] = {"h": h, "low": low_i, "up": up, "b": ib}
			_heap_push(cands.rheap, [h, key])
	else:
		# Shelf candidate: pull the UNREACHED cell one tier toward us (dt = unreached -
		# reached); prefer the smallest gap, then the seeded order.
		var key := ib * 4 + DIRS.find(dir)
		if not (cands.shelf as Dictionary).has(key):
			var k := (absi(dt) << 20) | (_hmix(map.seed, ib, DIRS.find(dir)) & 0xFFFFF)
			cands.shelf[key] = {"k": k, "cell": ib, "step": -1 if dt > 0 else 1}
			_heap_push(cands.sheap, [k, key])


## The best single repair joining the reached set to anything unreached: a Delta-1 ramp when
## one exists (lowest hash), else a one-tier shelf demotion on the unreached side of the
## tightest boundary. Pops the maintained MIN-HEAPS, lazily discarding entries the flood or
## an earlier carve made stale — at 256x256 max-tier-8 the repair runs 7,661 carves, and the
## old pool SCAN per pick was O(carves x pool), seconds of every derive. Heap order [value,
## key] is exactly the scan's (value, then key) tie-break, so the picks — and therefore the
## whole derived landscape — are byte-identical to the scanning version's.
static func _pick_carve(ramps: Dictionary, reached: Dictionary, cands: Dictionary) -> Dictionary:
	var rheap: Array = cands.rheap
	while not rheap.is_empty():
		var key: int = rheap[0][1]
		var c: Dictionary = (cands.ramp as Dictionary).get(key, {})
		if c.is_empty() or reached.has(c.b) or ramps.has(c.low):
			_heap_pop(rheap)
			(cands.ramp as Dictionary).erase(key)
			continue
		return {"kind": "ramp", "low": c.low, "dir": c.up}
	var sheap: Array = cands.sheap
	while not sheap.is_empty():
		var key: int = sheap[0][1]
		var c: Dictionary = (cands.shelf as Dictionary).get(key, {})
		if c.is_empty() or reached.has(c.cell):
			_heap_pop(sheap)
			(cands.shelf as Dictionary).erase(key)
			continue
		return {"kind": "shelf", "cell": c.cell, "step": c.step}
	return {}


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[i] < heap[p]:
			var t = heap[i]
			heap[i] = heap[p]
			heap[p] = t
			i = p
		else:
			break


static func _heap_pop(heap: Array) -> void:
	var last = heap.pop_back()
	if heap.is_empty():
		return
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var s := i
		if l < n and heap[l] < heap[s]:
			s = l
		if r < n and heap[r] < heap[s]:
			s = r
		if s == i:
			break
		var t = heap[i]
		heap[i] = heap[s]
		heap[s] = t
		i = s


static func _hmix(sd: int, a: int, b: int) -> int:
	var h := sd * 0x9E3779B1 + a * 0x85EBCA77 + b * 0xC2B2AE3D
	h = (h ^ (h >> 15)) * 0x2545F491
	return (h ^ (h >> 13)) & 0x7FFFFFFF


## Where a PAINTED ramp on cell i climbs: toward whichever non-water neighbour stands exactly
## one tier up (lowest hash when several do), ZERO when none does. `tiers` is indexable by
## global cell index — the full derive hands a PackedInt32Array, a region hands a Dictionary;
## the caller guarantees the four neighbours are inside it.
static func _painted_ramp_dir(map: WildsMap, tiers, i: int) -> Vector2i:
	var c := Vector2i(i % map.cells_w, i / map.cells_w)
	var best := Vector2i.ZERO
	var best_h := 0
	for dir in DIRS:
		var nb := c + dir
		if not map.in_bounds(nb):
			continue
		var inb := map.idx(nb)
		if is_water(map, inb):
			continue
		if tiers[inb] == tiers[i] + 1:
			var h := hash("%d|rampdir|%s|%s" % [map.seed, c, dir])
			if best == Vector2i.ZERO or h < best_h:
				best = dir
				best_h = h
	return best


# ---------------------------------------------------------------- SEGMENTS ------------------

## Every cliff run, as data: {cell, side, drop} — my tier stands `drop` courses above what lies
## across `side` (map edge counts, dropping to one course under the lowest tier so the world
## reads finished). A ramp climbing toward a face suppresses that face: the flight IS the wall.
static func _stage_segments(map: WildsMap, d: Dictionary) -> void:
	_segments_for(map, d, Rect2i(0, 0, map.cells_w, map.cells_h))


static func _segments_for(map: WildsMap, d: Dictionary, rect: Rect2i) -> void:
	var tiers = d.tiers
	var ramps: Dictionary = d.ramps
	var segments: Array = []
	# Map-edge faces drop to one course under ZERO — a CONSTANT, not min_tier-1, because a
	# region derive cannot know the global minimum and two chunks disagreeing about the world's
	# floor would tear the map edge at their seam. Tiers never go below 0, so -1 is always
	# under everything.
	var floor_tier := -1
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			var c := Vector2i(cx, cz)
			var t = tiers[map.idx(c)]
			for dir in DIRS:
				var nb := c + dir
				var nb_tier := floor_tier
				if map.in_bounds(nb):
					nb_tier = tiers[map.idx(nb)]
					if nb_tier >= t:
						continue
					# The neighbour's ramp climbing INTO this face replaces the wall.
					if ramps.get(map.idx(nb), Vector2i.ZERO) == -dir:
						continue
				segments.append({"cell": c, "side": dir, "drop": t - nb_tier})
	d.segments = segments


# ---------------------------------------------------------------- MESH ----------------------

## One chunk's mesh, derived on demand — the STREAMING half of _stage_mesh. Byte-identical to
## the chunk the full stage builds (the streaming suite asserts it): a chunk's content depends
## only on the light stages, never on other chunks or on build order, which is what makes
## spawn-and-despawn sections possible at all.
static func mesh_chunk(map: WildsMap, d: Dictionary, origin: Vector2i) -> Dictionary:
	var key := origin / CHUNK
	var segs: Array = []
	for s: Dictionary in d.segments:
		if Vector2i((s.cell as Vector2i).x / CHUNK, (s.cell as Vector2i).y / CHUNK) == key:
			segs.append(s)
	return _build_chunk(map, d, origin, segs)


static func _stage_mesh(map: WildsMap, d: Dictionary) -> void:
	var chunks: Array = []
	var seg_by_chunk := {}
	for s: Dictionary in d.segments:
		var key := Vector2i((s.cell as Vector2i).x / CHUNK, (s.cell as Vector2i).y / CHUNK)
		if not seg_by_chunk.has(key):
			seg_by_chunk[key] = []
		(seg_by_chunk[key] as Array).append(s)
	for oz in range(0, map.cells_h, CHUNK):
		for ox in range(0, map.cells_w, CHUNK):
			chunks.append(_build_chunk(map, d, Vector2i(ox, oz),
					seg_by_chunk.get(Vector2i(ox / CHUNK, oz / CHUNK), [])))
	d.chunks = chunks


static func _build_chunk(map: WildsMap, d: Dictionary, origin: Vector2i,
		segs: Array) -> Dictionary:
	# UNTYPED tier/region reads throughout the mesh: the full derive hands whole-map packed
	# arrays, a region derive hands Dictionaries covering only its window — both index the
	# same way, and this code must not care which world it is meshing.
	var tiers = d.tiers
	var ramps: Dictionary = d.ramps
	var th := map.tier_height
	var top := _acc()
	var cliff := _acc()

	var wall := PackedVector3Array()
	for cz in range(origin.y, mini(origin.y + CHUNK, map.cells_h)):
		for cx in range(origin.x, mini(origin.x + CHUNK, map.cells_w)):
			var c := Vector2i(cx, cz)
			var i := map.idx(c)
			var t: int = tiers[i]
			var y := t * th
			var p00 := _corner(map, cx, cz)
			var p10 := _corner(map, cx + 1, cz)
			var p11 := _corner(map, cx + 1, cz + 1)
			var p01 := _corner(map, cx, cz + 1)
			var col := Color(_tfrac(map, t), 0, 0)
			_sea_wall(map, wall, c, t)
			if is_water(map, i):
				_water_cell(map, d, top, c, [p00, p10, p11, p01])
				_shore_skirts(map, d, cliff, c)
				continue
			_shore_skirts(map, d, cliff, c)
			var dir: Vector2i = ramps.get(i, Vector2i.ZERO)
			if dir == Vector2i.ZERO:
				var up := Vector3.UP
				_tri(top, _at(p00, y), _at(p10, y), _at(p11, y), up, col)
				_tri(top, _at(p00, y), _at(p11, y), _at(p01, y), up, col)
			else:
				# The ramp: corners on the climb side rise one tier; the surface normal leans
				# back against the climb.
				var hy := y + th
				var a := _at(p00, hy if (dir == Vector2i(-1, 0) or dir == Vector2i(0, -1)) else y)
				var b := _at(p10, hy if (dir == Vector2i(1, 0) or dir == Vector2i(0, -1)) else y)
				var e := _at(p11, hy if (dir == Vector2i(1, 0) or dir == Vector2i(0, 1)) else y)
				var f := _at(p01, hy if (dir == Vector2i(-1, 0) or dir == Vector2i(0, 1)) else y)
				var n := Vector3(-dir.x * th, map.cell_size, -dir.y * th).normalized()
				_tri(top, a, b, e, n, col)
				_tri(top, a, e, f, n, col)
				_ramp_skirts(map, d, top, c, dir, col)

	for s: Dictionary in segs:
		_cliff_face(map, d, cliff, s)

	# Collision IS the render triangles, PLUS the sea wall — one ConcavePolygonShape3D per
	# chunk, agreement by construction and asserted byte-for-byte. The bed IS the water's
	# collider now: wading is the feature, and the old LID (a collision-only quad 1.6 m over
	# EVERY water surface, terrain_field's LAKE_WALL contract) was the placeholder that kept
	# water decorative. What the lid also silently did, and the wall now does deliberately, is
	# END THE WORLD in SEA mode — see _sea_wall.
	var faces := PackedVector3Array()
	faces.append_array(top.v)
	faces.append_array(cliff.v)
	faces.append_array(wall)
	return {"origin": origin, "top": _arrays(top), "cliff": _arrays(cliff), "wall": wall,
			"faces": faces}


## A water cell: its BED, carved into the same top surface — and the bed is exactly what a
## wading body stands on, shallow at any corner touching dry ground and deep elsewhere. The
## wet-ground flag rides the colour's green channel for the shader.
static func _water_cell(map: WildsMap, d: Dictionary, top: Dictionary,
		c: Vector2i, corners: Array) -> void:
	var th := map.tier_height
	var t: int = d.tiers[map.idx(c)]
	var col := Color(_tfrac(map, t), 1.0, 0)
	var ys: Array[float] = []
	for k in 4:
		var corner_cell: Vector2i = c + [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1),
				Vector2i(0, 1)][k]
		ys.append(t * th - (BED_SHALLOW if _corner_touches_dry(map, corner_cell)
				else bed_deep(map)))
	_tri(top, _at(corners[0], ys[0]), _at(corners[1], ys[1]), _at(corners[2], ys[2]),
			Vector3.UP, col)
	_tri(top, _at(corners[0], ys[0]), _at(corners[2], ys[2]), _at(corners[3], ys[3]),
			Vector3.UP, col)


## THE WORLD ENDS HERE, in SEA mode: an invisible collision wall on the outward face of every
## cell that sits on the map's true perimeter.
##
## The CLIFFS border ends the world with geometry a body cannot climb (>=2-tier steps the
## 1-tier jump refuses), and needs nothing from here. The SEA border used to end it by
## accident: the water lid fenced every water cell, the sea included. With water now wadeable
## by design, the sea band — 0.55 m deep, flat, and reaching the last cell — became a ramp
## off the edge of the world (probed: bed at -0.9 under a surface at -0.35, all the way to
## row 0). This is that fence, made deliberate and made SMALL: the map's rim only, not every
## lake in the world, so a pond keeps its wadeable shore and the ocean keeps its horizon.
##
## Collision-only, like the lid was — no normals, no colour, never rendered. Pure in
## (map, cell), so region and full derivation emit it identically.
static func _sea_wall(map: WildsMap, wall: PackedVector3Array, c: Vector2i, t: int) -> void:
	if map.border_mode != WildsMap.BORDER_SEA:
		return
	var top_y := t * map.tier_height - SURFACE_DROP + SEA_WALL
	var bottom := t * map.tier_height - bed_deep(map) - 0.5  # under the bed: no gap to slip through
	for side: Vector2i in DIRS:
		var nb := c + side
		if map.in_bounds(nb):
			continue                          # not the map's rim — the neighbour continues
		var e := _edge_corners(map, c, side)
		wall.append(_at(e[0], bottom))
		wall.append(_at(e[1], bottom))
		wall.append(_at(e[1], top_y))
		wall.append(_at(e[0], bottom))
		wall.append(_at(e[1], top_y))
		wall.append(_at(e[0], top_y))


## Does grid corner (cx, cz) touch any dry (or out-of-map) cell? Shared by bed depths so the
## shore band is continuous across cells by construction.
static func _corner_touches_dry(map: WildsMap, corner: Vector2i) -> bool:
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
		var cell := corner + off
		if not map.in_bounds(cell) or not is_water(map, map.idx(cell)):
			return true
	return false


## The underwater face of a cell's edge wherever it meets WATER whose bed sits below the wall
## the segments already built: from the water's tier top down to its bed at that edge. Dry
## shores get the shallow 0.2, a waterfall's foot gets the deep 0.9.
static func _shore_skirts(map: WildsMap, d: Dictionary, cliff: Dictionary, c: Vector2i) -> void:
	var th := map.tier_height
	var tiers = d.tiers
	var i := map.idx(c)
	var my_water := is_water(map, i)
	for dir in DIRS:
		var nb := c + dir
		if not map.in_bounds(nb):
			continue
		var inb := map.idx(nb)
		if not is_water(map, inb):
			continue                          # the neighbour is dry; nothing underwater here
		if my_water and tiers[inb] == tiers[i]:
			continue                          # same pool, same bed — no face between
		if tiers[i] < tiers[inb]:
			continue                          # standing below the water's rim: its own tier
			                                  # segment already walls past the bed line
		var drop := BED_SHALLOW if not my_water else bed_deep(map)
		var y1: float = tiers[inb] * th
		var y0 := y1 - drop
		var e := _edge_corners(map, c, dir)
		var outward := Vector3(dir.x, 0, dir.y)
		var col := Color(_tfrac(map, tiers[i]), 1.0, 0)
		_tri(cliff, _at(e[0], y0), _at(e[1], y0), _at(e[1], y1), outward, col)
		_tri(cliff, _at(e[0], y0), _at(e[1], y1), _at(e[0], y1), outward, col)


## One cliff face: a quad per 1.2 m course from the low top to the high top, along the shared
## jittered edge, front toward the LOW side. Course parity rides the colour's blue channel so
## the shader can band strata without a second attribute.
static func _cliff_face(map: WildsMap, d: Dictionary, acc: Dictionary, s: Dictionary) -> void:
	var c: Vector2i = s.cell
	var side: Vector2i = s.side
	var th := map.tier_height
	var t: int = d.tiers[map.idx(c)]
	var e := _edge_corners(map, c, side)
	var outward := Vector3(side.x, 0, side.y)
	var t_frac := _tfrac(map, t)
	for k in int(s.drop):
		var y0 := (t - int(s.drop) + k) * th
		var y1 := y0 + th
		var col := Color(t_frac, 0, float(k % 2))
		_tri(acc, _at(e[0], y0), _at(e[1], y0), _at(e[1], y1), outward, col)
		_tri(acc, _at(e[0], y0), _at(e[1], y1), _at(e[0], y1), outward, col)


## The little vertical triangles beside a ramp, where its sloped top rises above the flat
## neighbour it runs alongside — without them you see through the ramp's flank.
static func _ramp_skirts(map: WildsMap, d: Dictionary, acc: Dictionary, c: Vector2i,
		dir: Vector2i, col: Color) -> void:
	var th := map.tier_height
	var t: int = d.tiers[map.idx(c)]
	var perp := Vector2i(-dir.y, dir.x)
	for side in [perp, -perp]:
		var nb: Vector2i = c + side
		if map.in_bounds(nb) and d.tiers[map.idx(nb)] > t:
			continue                          # a higher neighbour's own cliff covers this flank
		var e := _edge_corners(map, c, side)
		# Which end of this flank edge is the ramp's HIGH end? The corner also touched by the
		# climb side. Both edge corner orderings are along +x/+z; resolve by projection.
		var high_first := (dir == Vector2i(-1, 0) or dir == Vector2i(0, -1))
		var lo: Vector2 = e[1] if high_first else e[0]
		var hi: Vector2 = e[0] if high_first else e[1]
		var outward := Vector3(side.x, 0, side.y)
		_tri(acc, _at(lo, t * th), _at(hi, t * th), _at(hi, t * th + th), outward, col)


# ---------------------------------------------------------------- helpers -------------------

## THE SEAM LAW made executable: jitter from the corner's own integer coordinates and nothing
## else. ±JITTER of a cell per axis; at 0.35 two corners can never swap sides.
##
## An ARITHMETIC mix, not hash("%d|%d|..."): _corner is the hottest call in the mesh stage
## (every cell asks for four corners, every cliff and skirt asks again) and building a format
## string per call put whole seconds into a derive. The low-frequency draws (carve picks) keep
## their readable string keys; this one earns its bit-twiddling.
static func _corner(map: WildsMap, cx: int, cz: int) -> Vector2:
	var h := map.seed * 0x9E3779B1 + cx * 0x85EBCA77 + cz * 0xC2B2AE3D
	h = (h ^ (h >> 15)) * 0x2545F491
	h = h ^ (h >> 13)
	var jx := float(h & 0x3FF) / 1023.0 - 0.5
	var jz := float((h >> 10) & 0x3FF) / 1023.0 - 0.5
	return Vector2((cx + jx * JITTER) * map.cell_size, (cz + jz * JITTER) * map.cell_size)


## The two shared-edge corners of cell `c` on `side`, ordered along +x/+z.
static func _edge_corners(map: WildsMap, c: Vector2i, side: Vector2i) -> Array:
	match side:
		Vector2i(1, 0):
			return [_corner(map, c.x + 1, c.y), _corner(map, c.x + 1, c.y + 1)]
		Vector2i(-1, 0):
			return [_corner(map, c.x, c.y), _corner(map, c.x, c.y + 1)]
		Vector2i(0, 1):
			return [_corner(map, c.x, c.y + 1), _corner(map, c.x + 1, c.y + 1)]
		_:
			return [_corner(map, c.x, c.y), _corner(map, c.x + 1, c.y)]


## Tier fraction for vertex COLOR.r, normalised against the MAP's dial rather than the
## derived min/max: a region derive cannot know the global extremes, and two chunks
## disagreeing about the palette would tint a seam. Painted mesas above max_tier clamp.
static func _tfrac(map: WildsMap, t: int) -> float:
	return clampf(float(t) / maxf(float(map.max_tier), 1.0), 0.0, 1.0)


static func _at(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


static func _acc() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray()}


## THE WINDING LAW enforced at the only place triangles are born: emitted so the cross
## (b-a)x(c-a) OPPOSES the outward normal (Godot front faces are clockwise about it).
static func _tri(acc: Dictionary, a: Vector3, b: Vector3, c: Vector3, outward: Vector3,
		col: Color) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	# NO `as` CASTS on these appends: casting a packed array COPIES it (measured — the cast
	# form appended to a temporary and every mesh came out empty), while plain chained access
	# mutates the dictionary's own buffer in Godot 4.
	acc["v"].append(a)
	acc["v"].append(b)
	acc["v"].append(c)
	for _k in 3:
		acc["n"].append(outward)
		acc["c"].append(col)


static func _arrays(acc: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = acc.v
	arrays[Mesh.ARRAY_NORMAL] = acc.n
	arrays[Mesh.ARRAY_COLOR] = acc.c
	return arrays

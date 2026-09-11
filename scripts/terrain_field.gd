extends StaticBody3D
## A SCULPTABLE HEIGHT FIELD — the ground the foliage bench paints on.
##
## The first real terrain in this project. Everything walkable up to now has been hand-placed
## primitives: scenes/world/room.tscn's Collision body is eight box and cylinder shapes at three
## fixed heights, joined by two tilted slabs, and the visual is discrete objects modelled in
## room_kit.blend. addons/gladekit/MANUAL.md:1435 records the gap in as many words — "there is no
## heightmap system in this project yet".
##
## WHY A HEIGHT GRID AND NOT A SCULPTED MESH FROM BLENDER. A .blend terrain is a round trip per
## iteration and cannot be judged under the game's own environment, but the deciding reason is that
## it yields no queryable height: every grass tuft would need a physics raycast to find its Y.
## An array we own makes height_at() a bilinear read, which is what lets GrassPatch place 19,000
## tufts on a hillside for the same cost it places them on a plane.
##
## WHY 1 METRE CELLS, AND WHY THE NODE IS NEVER SCALED. The collider is a HeightMapShape3D, whose
## samples sit exactly one unit apart in the shape's local space. Anything other than 1 m cells
## would need a non-uniform scale on the CollisionShape3D, which Godot handles badly. So cell_size
## is 1.0, extent is 64, and the 65 x 65 vertex grid maps one-to-one onto a 65 x 65 map_data array
## with no scaling anywhere. HeightMapShape3D appears nowhere else in this project's own code, but
## addons/proton_scatter/src/scatter.gd:661 already consumes one, so it is not unproven ground.
##
## NO class_name, deliberately, for the reason scripts/dev/tuning_panel.gd states: a new global class
## forces an editor rescan, and a rescan corrupted crypt_stone.tres last cycle. Construct it with
## preload("res://scripts/terrain_field.gd").new().
##
## THE SLOPE CLAMP IS THE LOAD-BEARING FEATURE, not the brushes. This project has no navmesh and no
## step logic (docs/architecture.md:168, scripts/dungeon/kit.gd:499); nothing overrides
## floor_max_angle so it is Godot's 45 degrees, and scripts/enemy.gd:227 chases with a flattened
## vector. A face steeper than 45 degrees is not a challenge to an enemy, it is a trap it never
## escapes and never reports. So sculpting clamps gradients by default and you turn the clamp off
## on purpose, per stroke, when a wall is what you want.

## What the brush is doing to the ground. Passed to sculpt().
enum Mode { RAISE, LOWER, SMOOTH, FLATTEN, CLIFF, LAKE }

## THE TWO BRUSHES THAT DO NOT GET THEIR SLOPES CLAMPED.
##
## CLIFF is the obvious one: a deliberate wall is the whole point of it, and the slope overlay in
## shaders/terrain_slope.gdshader is there to keep that a decision rather than an accident.
##
## LAKE is the one that had to be learned. It was clamped at first, and that is a contradiction: the
## brush digs a basin and the clamp immediately spreads it back out, so every dab paid for a full
## relaxation — measured at 17 to 44 ms, up to 44 with the window grown to the whole grid — to
## partly undo the work the same dab had just done. Deep water simply could not be carved.
##
## The clamp exists to keep WALKABLE ground walkable, and the inside of a lake is not walkable ground
## by design: _collision_heights() fills it to LAKE_WALL above the surface precisely so nobody can
## stand there. A steep bank reads correctly and blocks correctly. The shore OUTSIDE the water stays
## gentle on its own, because the brush's falloff never lifts ground it did not lower.
const UNCLAMPED := [Mode.CLIFF, Mode.LAKE]

## How far above the water an unenterable lake is walled off, in metres. Over one 1 m cell this is a
## 58-degree face, comfortably past floor_max_angle's 45, so a CharacterBody3D slides off the rim
## rather than climbing onto the invisible lid. At 1.0 it would be exactly 45 and marginal.
const LAKE_WALL := 1.6

## Relaxation cap for the slope clamp. It breaks early the moment a pass changes nothing, which is
## the usual case; this only bounds the pathological one.
const MAX_RELAX := 32

## Slack on the slope test, in metres per cell.
##
## WITHOUT IT THE RELAXATION NEVER TERMINATES. Correcting a pair moves both ends toward the limit,
## and in floating point they land a hair over it, so an exact `> limit` test finds the same pair
## violating on every pass forever: the loop always ran its full 32 passes, over a window that grows
## to the whole grid, and a LAKE dab cost 60 ms of doing nothing. A tenth of a millimetre is far
## below anything the 1 m grid can express and is the same tolerance probe_terrain.gd asserts with.
const SLOPE_EPS := 0.0001

@export var extent := 64.0                ## metres, square. The node sits at the centre.
@export var cell_size := 1.0              ## see the header — this must stay 1.0
## Gradients are clamped to this after every sculpt dab unless the stroke opts out. 30 is under
## scripts/dungeon/gameplay/room_shape.gd:219's own MAX_SLOPE of 35 and well under the engine's 45.
@export var max_slope_deg := 30.0

## Height per grid vertex, row-major with Z outer: heights[iz * side + ix]. This IS the collider's
## map_data layout, which is why nothing has to be transposed on the way out.
var heights := PackedFloat32Array()
## Which vertices a LAKE stroke has painted. A vertex is actually under water only if it is painted
## AND below water_level, so raising ground inside an old lake drains it without bookkeeping.
var lake := PackedByteArray()
var water_level := 0.0

var _side := 0                            ## vertices per edge = cells + 1
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _mesh := ArrayMesh.new()
var _mi: MeshInstance3D
var _shape: HeightMapShape3D
var _mat: ShaderMaterial
var _min_h := 0.0
var _max_h := 0.0

## PER-PHASE TIMING OF THE LAST sculpt(), in microseconds, for scripts/dev/probe_terrain.gd's budget
## check to read AFTERWARDS.
##
## Recorded, never printed. The first version of this printed a line from inside sculpt() and the
## print cost 13 ms on a Windows console — inside the very region the probe was timing, so a dab
## that really took 3 ms measured as 15 ms and the instrument was reporting mostly itself. Writing
## three ints and letting the caller read them once the clock has stopped costs nothing.
var last_clamp_us := 0
var last_refresh_us := 0
var last_water_us := 0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	if heights.is_empty():
		reset_flat()
	else:
		_rebuild_all()


# ---------------------------------------------------------------------------------------------
# GRID
# ---------------------------------------------------------------------------------------------

func side() -> int:
	return _side


func _allocate() -> void:
	_side = int(round(extent / cell_size)) + 1
	var n := _side * _side
	heights.resize(n)
	lake.resize(n)
	_verts.resize(n)
	_normals.resize(n)
	_uvs.resize(n)
	_rebuild_indices()


## Two triangles per cell, built once. THE WINDING IS THE TRAP, and it is worth spelling out because
## getting it wrong does not look like a winding bug — the whole ground is backface-culled and every
## plant on it appears to float in the sky. scripts/gladekit_tests/probe_cliff.gd:174 hit this first:
##
##   Godot's front face is CLOCKWISE about the outward normal, so the right-hand normal of the
##   emitted vertex order must OPPOSE the direction the surface actually faces.
##
## The ground faces up, so each triangle's (b-a) x (c-a) must point DOWN. Both orders below do;
## scripts/dev/probe_terrain.gd asserts it on every triangle rather than trusting this comment.
func _rebuild_indices() -> void:
	var cells := _side - 1
	_indices = PackedInt32Array()
	_indices.resize(cells * cells * 6)
	var w := 0
	for iz in cells:
		for ix in cells:
			var a := iz * _side + ix
			var b := a + 1
			var c := a + _side + 1
			var d := a + _side
			_indices[w] = a
			_indices[w + 1] = b
			_indices[w + 2] = c
			_indices[w + 3] = a
			_indices[w + 4] = c
			_indices[w + 5] = d
			w += 6


func _idx(ix: int, iz: int) -> int:
	return iz * _side + ix


## Grid coordinates of a local XZ point, unclamped and fractional.
func _grid_of(local: Vector2) -> Vector2:
	return Vector2((local.x + extent * 0.5) / cell_size, (local.y + extent * 0.5) / cell_size)


## Local XZ of a grid vertex.
func _local_of(ix: int, iz: int) -> Vector2:
	return Vector2(-extent * 0.5 + ix * cell_size, -extent * 0.5 + iz * cell_size)


func _h(ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, _side - 1) * _side + clampi(ix, 0, _side - 1)]


# ---------------------------------------------------------------------------------------------
# SAMPLING — the public reason this class exists
# ---------------------------------------------------------------------------------------------

## Ground height at a point in the field's LOCAL XZ. Bilinear, and clamped at the rim rather than
## returning garbage, so a scatter that overruns the edge lands on the edge instead of at zero.
func height_at(local: Vector2) -> float:
	var g := _grid_of(local)
	var gx := clampf(g.x, 0.0, float(_side - 1))
	var gz := clampf(g.y, 0.0, float(_side - 1))
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var h00 := _h(ix, iz)
	var h10 := _h(ix + 1, iz)
	var h01 := _h(ix, iz + 1)
	var h11 := _h(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


## Surface normal at a local XZ point, by central difference. Matches the per-vertex normals the
## mesh carries, so foliage tilted by this agrees with the ground it is standing on.
func normal_at(local: Vector2) -> Vector3:
	var e := cell_size
	var hl := height_at(local - Vector2(e, 0.0))
	var hr := height_at(local + Vector2(e, 0.0))
	var hd := height_at(local - Vector2(0.0, e))
	var hu := height_at(local + Vector2(0.0, e))
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## Where a ray meets the ground, in GLOBAL space, or Vector3.INF for a miss.
##
## THIS MARCHES THE ARRAY, it does not ask the physics server. Three reasons, in order of weight:
## the collider is uploaded after a sculpt dab and a physics query on the same frame would answer
## about the previous shape; the bench needs no collision layer set up to work; and a ray that
## starts inside the terrain (which the fly camera can) has a defined answer here rather than a
## silent miss. Costs a few hundred bilinear samples, which is nothing next to one mouse event.
func raycast(from: Vector3, dir: Vector3) -> Vector3:
	var lf := to_local(from)
	var ld := (to_local(from + dir) - lf).normalized()
	var half := extent * 0.5

	# Trim the ray to the slab of space the field could possibly occupy, so a shallow ray across a
	# 64 m field does not march from the camera all the way to the horizon.
	var t0 := 0.0
	var t1 := 4096.0
	for axis: Vector2 in [Vector2(lf.x, ld.x), Vector2(lf.z, ld.z)]:
		if absf(axis.y) < 0.00001:
			if absf(axis.x) > half:
				return Vector3.INF
			continue
		var ta := (-half - axis.x) / axis.y
		var tb := (half - axis.x) / axis.y
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 <= t0:
		return Vector3.INF
	# And by the height band, both ends padded so a ray grazing the highest ridge is not trimmed off.
	if absf(ld.y) > 0.00001:
		var ty0 := (_min_h - 1.0 - lf.y) / ld.y
		var ty1 := (_max_h + 1.0 - lf.y) / ld.y
		t0 = maxf(t0, minf(ty0, ty1))
		t1 = minf(t1, maxf(ty0, ty1))
		if t1 <= t0:
			return Vector3.INF

	var step := cell_size * 0.5
	var t := t0
	var p := lf + ld * t
	if p.y - height_at(Vector2(p.x, p.z)) <= 0.0:
		return to_global(p)          # started at or under the surface
	while t < t1:
		t = minf(t + step, t1)
		p = lf + ld * t
		if p.y - height_at(Vector2(p.x, p.z)) <= 0.0:
			# Bisect the crossing. Eight halvings of a 0.5 m step lands inside 2 mm, which is far
			# finer than the 1 m grid the answer is interpolated from.
			var lo := t - step
			var hi := t
			for _i in 8:
				var mid := (lo + hi) * 0.5
				var q := lf + ld * mid
				if q.y - height_at(Vector2(q.x, q.z)) > 0.0:
					lo = mid
				else:
					hi = mid
			return to_global(lf + ld * hi)
	return Vector3.INF


# ---------------------------------------------------------------------------------------------
# SCULPTING
# ---------------------------------------------------------------------------------------------

var _flatten_target := 0.0
var _lake_depth := 1.6


## Call once when a stroke begins. FLATTEN and LAKE both need a reference height taken before the
## stroke starts changing the ground under them, or every dab chases the last one and the pad drifts.
func begin_stroke(local: Vector2, mode: int, lake_depth: float) -> void:
	_flatten_target = height_at(local)
	_lake_depth = lake_depth
	if mode == Mode.LAKE:
		water_level = _flatten_target


## One dab. `hard` disables the slope clamp for this dab — that is what CLIFF means.
func sculpt(local: Vector2, radius: float, mode: int, strength: float) -> void:
	if _side == 0:
		return
	var g := _grid_of(local)
	var cells := radius / cell_size
	var x0 := clampi(int(floor(g.x - cells)) - 1, 0, _side - 1)
	var x1 := clampi(int(ceil(g.x + cells)) + 1, 0, _side - 1)
	var z0 := clampi(int(floor(g.y - cells)) - 1, 0, _side - 1)
	var z1 := clampi(int(ceil(g.y + cells)) + 1, 0, _side - 1)
	if x1 < x0 or z1 < z0:
		return

	# SMOOTH must read a snapshot. Averaging in place walks the blur across the rect in the
	# iteration's own direction and shears the ground toward +X+Z, which reads as a bug and is one.
	var snap := PackedFloat32Array()
	if mode == Mode.SMOOTH:
		snap = heights.duplicate()

	var lake_bed := water_level - _lake_depth
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var p := _local_of(ix, iz)
			var d := p.distance_to(local)
			if d > radius:
				continue
			var t := d / maxf(radius, 0.001)
			# Smooth falloff for the shaping brushes; CLIFF holds full strength to 0.75 of the
			# radius and then drops, because a cliff with a gaussian edge is a hill.
			var w := (1.0 - t * t) * (1.0 - t * t)
			if mode == Mode.CLIFF:
				w = 1.0 if t < 0.75 else smoothstep(1.0, 0.75, t)
			var i := _idx(ix, iz)
			match mode:
				Mode.RAISE, Mode.CLIFF:
					heights[i] += strength * w
				Mode.LOWER:
					heights[i] -= strength * w
				Mode.SMOOTH:
					var mean := (snap[_idx(clampi(ix - 1, 0, _side - 1), iz)]
							+ snap[_idx(clampi(ix + 1, 0, _side - 1), iz)]
							+ snap[_idx(ix, clampi(iz - 1, 0, _side - 1))]
							+ snap[_idx(ix, clampi(iz + 1, 0, _side - 1))]) * 0.25
					heights[i] = lerpf(heights[i], mean, clampf(strength * w, 0.0, 1.0))
				Mode.FLATTEN:
					heights[i] = lerpf(heights[i], _flatten_target, clampf(strength * w, 0.0, 1.0))
				Mode.LAKE:
					heights[i] = lerpf(heights[i], lake_bed, clampf(strength * w, 0.0, 1.0))
					if lake[i] == 0:
						lake[i] = 1
						_lake_marks += 1

	var rect := Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)
	var _t0 := Time.get_ticks_usec()
	if not mode in UNCLAMPED:
		rect = _clamp_slopes(rect)
	var _t1 := Time.get_ticks_usec()
	_refresh(rect)
	last_clamp_us = _t1 - _t0
	last_refresh_us = Time.get_ticks_usec() - _t1


## Pull neighbouring vertices together until no edge is steeper than max_slope_deg.
##
## Cheap in the case that matters: a single dab with a smooth falloff introduces a gradient of
## roughly 2 * strength / radius, which for the panel's defaults is well inside the limit, so the
## scan below finds nothing and returns immediately. It is REPEATED dabs in one place, building a
## cone whose sides steepen a little each time, that eventually trip it — and by then the violation
## can have to travel outside the dab's own footprint to resolve, which is why the fallback relaxes
## the whole grid rather than the rect. Returns the region it actually touched.
func _clamp_slopes(rect: Rect2i) -> Rect2i:
	var limit := cell_size * tan(deg_to_rad(clampf(max_slope_deg, 1.0, 89.0)))
	var violated := false
	for iz in range(rect.position.y, rect.end.y):
		for ix in range(rect.position.x, rect.end.x):
			var h := heights[_idx(ix, iz)]
			if (ix + 1 < _side and absf(h - heights[_idx(ix + 1, iz)]) > limit + SLOPE_EPS) \
					or (iz + 1 < _side and absf(h - heights[_idx(ix, iz + 1)]) > limit + SLOPE_EPS):
				violated = true
				break
		if violated:
			break
	if not violated:
		return rect

	# THE RELAXATION GROWS OUT OF THE DAB; it does not sweep the field.
	#
	# It used to run every pass over all 65 x 65 vertices, and a LAKE dab — which carves a 2 m basin
	# and so always trips the limit at its rim — cost 113 ms, seven frames, on the one brush that
	# rebakes water as well. A correction can only travel one cell per pass, so a pass that looks
	# further out than it has had time to reach is looking at ground it cannot have disturbed.
	# Widening the window by one cell per pass covers exactly what can move and nothing else.
	var touched := rect
	for p in MAX_RELAX:
		var r := _grow(rect, p + 1)
		var moved := false
		for iz in range(r.position.y, r.end.y):
			for ix in range(r.position.x, r.end.x):
				var i := _idx(ix, iz)
				for n: Vector2i in [Vector2i(ix + 1, iz), Vector2i(ix, iz + 1)]:
					if n.x >= _side or n.y >= _side:
						continue
					var j := _idx(n.x, n.y)
					var diff := heights[i] - heights[j]
					if absf(diff) <= limit + SLOPE_EPS:
						continue
					# Move BOTH ends by half the excess. Moving only the high one erodes a hill down
					# to nothing over repeated strokes; splitting it preserves the mean elevation.
					var fix := (absf(diff) - limit) * 0.5 * signf(diff)
					heights[i] -= fix
					heights[j] += fix
					moved = true
		touched = touched.merge(r)
		if not moved:
			break
	return touched


func _grow(r: Rect2i, by: int) -> Rect2i:
	var x0 := maxi(r.position.x - by, 0)
	var z0 := maxi(r.position.y - by, 0)
	var x1 := mini(r.end.x + by, _side)
	var z1 := mini(r.end.y + by, _side)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


## Fill the whole field with fractal noise. The parameter set is lifted from
## scripts/gladekit_tests/probe_cliff.gd:154 — seed 5, frequency 0.018, two octaves, amplitude 3.2 —
## because that is the one configuration in this repo already known to read as rolling ground rather
## than as a crumpled sheet. The dials exist to move away from it, not to find it again.
func noise_fill(nseed: int, frequency: float, octaves: int, amplitude: float) -> void:
	var n := FastNoiseLite.new()
	n.seed = nseed
	n.frequency = frequency
	n.fractal_octaves = maxi(octaves, 1)
	for iz in _side:
		for ix in _side:
			var p := _local_of(ix, iz)
			heights[_idx(ix, iz)] = n.get_noise_2d(p.x, p.y) * amplitude
	_clamp_slopes(Rect2i(0, 0, _side, _side))
	_refresh(Rect2i(0, 0, _side, _side))


func reset_flat() -> void:
	_allocate()
	for i in heights.size():
		heights[i] = 0.0
		lake[i] = 0
	_lake_marks = 0
	water_level = 0.0
	_refresh(Rect2i(0, 0, _side, _side))


# ---------------------------------------------------------------------------------------------
# BUILD
# ---------------------------------------------------------------------------------------------

func _rebuild_all() -> void:
	if _side == 0 or _verts.size() != heights.size():
		var keep := heights.duplicate()
		var keep_lake := lake.duplicate()
		_allocate()
		if keep.size() == heights.size():
			heights = keep
			lake = keep_lake
	_refresh(Rect2i(0, 0, _side, _side))


## Recompute vertices and normals inside `rect` (expanded by one, because a normal reads its
## neighbours), then hand the whole surface back to the GPU.
##
## The recompute is scoped; the upload is not. That is on purpose. Re-deriving 4,225 positions and
## normals per mouse-motion event is real GDScript time, so it is worth scoping — but re-uploading
## an already-built PackedVector3Array is a memcpy the driver does asynchronously, and splitting it
## into partial region updates would buy microseconds at the cost of a second code path that has to
## stay in agreement with this one.
##
## NOT SurfaceTool. SurfaceTool inside a per-element loop is exactly what made GrassPatch.settle()
## take 34 seconds before it was rewritten, and this loop runs on every mouse move.
func _refresh(rect: Rect2i) -> void:
	if _side == 0:
		return
	var x0 := maxi(rect.position.x - 1, 0)
	var z0 := maxi(rect.position.y - 1, 0)
	var x1 := mini(rect.end.x + 1, _side)
	var z1 := mini(rect.end.y + 1, _side)
	var inv := 1.0 / float(_side - 1)
	for iz in range(z0, z1):
		for ix in range(x0, x1):
			var i := _idx(ix, iz)
			var p := _local_of(ix, iz)
			var h := heights[i]
			_verts[i] = Vector3(p.x, h, p.y)
			_uvs[i] = Vector2(ix * inv, iz * inv)
			# Central difference, matching normal_at(). At the rim _h() clamps, which halves the
			# effective step there — harmless, and it keeps the edge from flaring.
			_normals[i] = Vector3(_h(ix - 1, iz) - _h(ix + 1, iz), 2.0 * cell_size,
					_h(ix, iz - 1) - _h(ix, iz + 1)).normalized()

	_min_h = INF
	_max_h = -INF
	for h in heights:
		_min_h = minf(_min_h, h)
		_max_h = maxf(_max_h, h)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_ensure_nodes()
	_shape.map_data = _collision_heights()
	var _w0 := Time.get_ticks_usec()
	_refresh_water()
	last_water_us = Time.get_ticks_usec() - _w0
	surface_changed.emit()


## The collider is NOT the render surface. Lake beds are filled back up to LAKE_WALL above the water
## so the player physically cannot walk into a lake, while the visible mesh keeps the real basin —
## the barrier is invisible and the water still has a bottom you can see through it. Decorative
## water, blocked off, with no swimming logic, no per-frame water-level query, and no depth test.
func _collision_heights() -> PackedFloat32Array:
	var out := heights.duplicate()
	var wall := water_level + LAKE_WALL
	for i in out.size():
		if lake[i] == 1 and heights[i] < water_level:
			out[i] = maxf(out[i], wall)
	return out


func _ensure_nodes() -> void:
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.name = "Surface"
		_mi.mesh = _mesh
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/terrain_slope.gdshader")
		_mi.material_override = _mat
		add_child(_mi)
	if _shape == null:
		_shape = HeightMapShape3D.new()
		_shape.map_width = _side
		_shape.map_depth = _side
		var cs := CollisionShape3D.new()
		cs.name = "Body"
		cs.shape = _shape
		add_child(cs)
	elif _shape.map_width != _side:
		_shape.map_width = _side
		_shape.map_depth = _side


## Emitted after the ground changes, so anything standing on it can re-seat itself.
signal surface_changed


func material() -> ShaderMaterial:
	_ensure_nodes()
	return _mat


# ---------------------------------------------------------------------------------------------
# WATER
# ---------------------------------------------------------------------------------------------

## How many metres of water one unit of the depth map stands for. Shared with the shader's own
## `depth_scale`, and they have to agree or the shallows and the foam land at the wrong contour.
const DEPTH_SCALE := 2.0

var _water: MeshInstance3D
var _water_mat: ShaderMaterial
var _water_tex: ImageTexture
## How many vertices a LAKE stroke has ever marked. Kept as a counter purely so the common case —
## a field with no lake in it, which is most fields most of the time — can skip the depth bake and
## the has_water() scan entirely. _refresh() runs on every mouse-motion event, and re-baking a
## 4,225-pixel image and allocating a texture per dab is exactly the kind of per-frame cost this
## bench has twice had to hunt down and remove.
var _lake_marks := 0


## ONE FLAT QUAD OVER THE WHOLE FIELD, shaped entirely by the depth map — see the header of
## shaders/water_stylized.gdshader. Building an actual lake mesh would mean extracting a contour from
## the height field, keeping it in step with every sculpt dab, and getting the waterline to agree
## with the collider's shore wall; a texture the field can bake in one pass does all three for free.
func _refresh_water() -> void:
	if _lake_marks == 0 and _water == null:
		return
	var wet := has_water()
	if _water == null:
		if not wet:
			return
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://shaders/water_stylized.gdshader")
		var pm := PlaneMesh.new()
		pm.size = Vector2(extent, extent)
		_water = MeshInstance3D.new()
		_water.name = "Water"
		_water.mesh = pm
		_water.material_override = _water_mat
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_water)
	_water.visible = wet
	if not wet:
		return
	_water.position = Vector3(0.0, water_level, 0.0)
	_water_mat.set_shader_parameter("extent", extent)
	_water_mat.set_shader_parameter("depth_scale", DEPTH_SCALE)
	# update() rather than create_from_image(), so a stroke that keeps widening a lake reuses one
	# texture instead of orphaning one per dab.
	var img := depth_image(DEPTH_SCALE)
	if _water_tex == null:
		_water_tex = ImageTexture.create_from_image(img)
		_water_mat.set_shader_parameter("depth_map", _water_tex)
	else:
		_water_tex.update(img)


func water_material() -> ShaderMaterial:
	return _water_mat


## Depth under the waterline, as a texture the water shader can read without a DEPTH_TEXTURE fetch.
## We own the height array, so the honest way to get a shoreline is to bake it rather than to sample
## the depth buffer — which would also drag the water into the sorted pass the project has spent
## some effort staying out of (painted_env.gdshader:107 on why a MultiMesh cannot sort).
## R = metres under water, normalised by `scale`. Zero outside the painted lake, so the mask edge and
## the waterline coincide and foam has something to sit on.
## BUILT AS A BUFFER, NOT WITH set_pixel. The obvious version called Image.set_pixel once per grid
## vertex and cost 110 MILLISECONDS per dab — seven frames, on the one brush that has to rebake this
## every time it moves, and scripts/dev/probe_terrain.gd's budget check is what caught it. Filling a
## PackedFloat32Array and handing the whole thing to create_from_data does the same work with one
## conversion instead of 4,225 per-pixel calls into the engine.
func depth_image(scale: float = 2.0) -> Image:
	var inv := 1.0 / maxf(scale, 0.001)
	var buf := PackedFloat32Array()
	buf.resize(_side * _side)
	for i in buf.size():
		buf[i] = clampf((water_level - heights[i]) * inv, 0.0, 1.0) \
				if (lake[i] == 1 and heights[i] < water_level) else 0.0
	return Image.create_from_data(_side, _side, false, Image.FORMAT_RF, buf.to_byte_array())


func has_water() -> bool:
	if _lake_marks == 0:
		return false
	for i in lake.size():
		if lake[i] == 1 and heights[i] < water_level:
			return true
	return false


# ---------------------------------------------------------------------------------------------
# PERSISTENCE
# ---------------------------------------------------------------------------------------------
#
# A 4,225-float array has no business in a .cfg or in .tscn text, so heights live in their own
# binary file rather than riding the bench's ConfigFile. Magic and version up front because a
# height file that silently loads at the wrong resolution produces a plausible-looking wrong
# terrain, which is the worst kind of wrong.

const MAGIC := "RPGTERR"
const VERSION := 1


func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_pascal_string(MAGIC)
	f.store_32(VERSION)
	f.store_float(extent)
	f.store_float(cell_size)
	f.store_float(water_level)
	f.store_var(heights)
	f.store_var(lake)
	f.close()
	return true


func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	if f.get_pascal_string() != MAGIC or f.get_32() != VERSION:
		push_warning("TerrainField: %s is not a v%d height file" % [path, VERSION])
		return false
	extent = f.get_float()
	cell_size = f.get_float()
	water_level = f.get_float()
	var h: PackedFloat32Array = f.get_var()
	var lk: PackedByteArray = f.get_var()
	f.close()
	_allocate()
	if h.size() != heights.size():
		push_warning("TerrainField: %s holds %d samples, this field wants %d" %
				[path, h.size(), heights.size()])
		return false
	heights = h
	lake = lk if lk.size() == heights.size() else lake
	_lake_marks = 0
	for b in lake:
		if b == 1:
			_lake_marks += 1
	_refresh(Rect2i(0, 0, _side, _side))
	return true

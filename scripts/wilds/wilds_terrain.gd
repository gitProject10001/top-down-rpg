@tool
extends StaticBody3D
## The BUILT terraces: chunk meshes and their colliders under one body, plus the ground
## contract the foliage addon duck-types (side / height_at / normal_at — the exact trio
## GrassPatch._ground_node resolves). @tool where terrain_field deliberately is not, and the
## difference is argued rather than drifted into: the editor is the wilds' primary authoring
## surface, GrassPatch's placeholder gate REJECTS non-tool ground scripts in the editor, and
## the rescan hazard terrain_field's header guards against lives in class_name registration —
## which this script does not have (preload it by path).
##
## NOT in group glade_body or glade_wall: those name what GladeKit's conform rays EXCLUDE, and
## ground exists to be HIT by them. Collision is layer 1, mask 0, one ConcavePolygonShape3D
## per chunk built from the render triangles themselves — agreement by construction.

const GROUND_SHADER := preload("res://shaders/wilds_ground.gdshader")
const WATER_SHADER := preload("res://shaders/water_stylized.gdshader")
const FALL_SHADER := preload("res://shaders/waterfall.gdshader")
const DEPTH_SCALE := 2.0                      ## terrain_field's encoding: red = metres / 2
const DEPTH_PX_PER_M := 2.0
## The flow map is a QUARTER the depth map's resolution per axis, a sixteenth the samples: a
## shoreline contour needs 2 px/m to stay crisp, a current is low-frequency by nature and
## linear filtering between 2 m samples is exactly the smoothing we would otherwise add.
const FLOW_PX_PER_M := 0.5
## Metres between water-surface vertices, and the cap on how many a single plane may have.
## 0.5 m gives a 1-2 m ripple three to four vertices across; 192 subdivisions is 37k verts.
const WATER_VERTS_M := 0.5
const WATER_SUBDIV_MAX := 192

var map: WildsMap = null
var derived: Dictionary = {}
var _style: WildsStyle = null
var _flow_speed := 1.0                        ## metres/second per unit of baked flow
var _top_mat: ShaderMaterial
var _cliff_mat: ShaderMaterial
## One material for every fall on the map: the sheet animates from TIME and its strands from
## their own UVs, so nothing here is per-instance and hundreds of falls share one.
var _fall_mat_cache: ShaderMaterial = null
var _lazy := false
var _region_cache: Dictionary = {}            ## chunk origin -> derive_region dict


## Build (or rebuild) every chunk from a FULL derivation. Children are transient — cleared and
## regrown, never owned; the bake owns them later, the same split the Forge preview makes.
func build(p_map: WildsMap, p_derived: Dictionary, style: WildsStyle = null) -> void:
	_begin(p_map, p_derived, style)
	for chunk: Dictionary in derived.chunks:
		_grow_chunk(chunk)
	_build_water(style)
	_place_pieces(style)


## The STREAMING opening: water, materials and the ground contract stand immediately; chunks
## arrive later, one at a time, through ensure_chunk — the derivation here is the LIGHT one,
## and each chunk's mesh is derived the moment somebody walks toward it.
func build_streaming(p_map: WildsMap, p_derived: Dictionary, style: WildsStyle = null) -> void:
	_begin(p_map, p_derived, style)
	_build_water(style)


## The 14-KM OPENING: no derivation at all. Every chunk derives its own REGION on first
## touch (WildsGen.derive_region — cost of the window, never of the map), cached until the
## chunk drops; water surfaces are built per chunk, clipped to it. The ground contract
## answers from the same cache, deriving on demand — the world is numbers until walked on.
func build_lazy(p_map: WildsMap, style: WildsStyle = null) -> void:
	_begin(p_map, {}, style)
	_lazy = true


func _begin(p_map: WildsMap, p_derived: Dictionary, style: WildsStyle) -> void:
	map = p_map
	derived = p_derived
	_lazy = false
	_region_cache = {}
	# The water contract's rendezvous: the Water autoload resolves whoever holds this group,
	# duck-typed on water_surface_y/water_depth_at exactly as the foliage resolves the ground
	# trio. terrain_field could join later; today the wilds are the only oracle.
	add_to_group("water_oracle")
	for c in get_children():
		c.free()
	collision_layer = 1
	collision_mask = 0
	_style = style
	_flow_speed = style.flow_speed if style != null else 1.0
	_fall_mat_cache = null
	_top_mat = _material(style, false)
	_cliff_mat = _material(style, true)


func has_chunk(origin: Vector2i) -> bool:
	return has_node("Chunk_%d_%d" % [origin.x, origin.y])


## The derivation a chunk's cells live in: the global dict when one exists, else the chunk's
## own cached region. Public — the streamer hands it to the flora builder.
func region_for(origin: Vector2i) -> Dictionary:
	if not _lazy:
		return derived
	if not _region_cache.has(origin):
		_region_cache[origin] = WildsGen.derive_region(map,
				Rect2i(origin, Vector2i(WildsGen.CHUNK, WildsGen.CHUNK)))
	return _region_cache[origin]


## Stand one chunk, deriving its mesh on demand. Kit pieces for the chunk's own segments hang
## under its holder, so dropping the chunk drops its dressing with it.
func ensure_chunk(origin: Vector2i) -> void:
	if has_chunk(origin) or (derived.is_empty() and not _lazy):
		return
	var src := region_for(origin)
	var chunk := WildsGen.mesh_chunk(map, src, origin)
	var holder := _grow_chunk(chunk)
	if _lazy:
		_water_surfaces(src, origin, holder)
	# Dressing runs with or WITHOUT a style: authored cliff pieces need one, the procedural
	# spill does not, and the benches carry no style at all.
	@warning_ignore("integer_division")
	var key := origin / WildsGen.CHUNK
	var segs: Array = []
	for s: Dictionary in src.segments:
		@warning_ignore("integer_division")
		var sk := Vector2i((s.cell as Vector2i).x / WildsGen.CHUNK,
				(s.cell as Vector2i).y / WildsGen.CHUNK)
		if sk == key:
			segs.append(s)
	_place_segments(src, segs, holder, _style)


func drop_chunk(origin: Vector2i) -> void:
	var holder := get_node_or_null("Chunk_%d_%d" % [origin.x, origin.y])
	if holder != null:
		holder.free()
	var shape := get_node_or_null("Collision_%d_%d" % [origin.x, origin.y])
	if shape != null:
		shape.free()
	_region_cache.erase(origin)


func _grow_chunk(chunk: Dictionary) -> Node3D:
	var origin: Vector2i = chunk.origin
	var holder := Node3D.new()
	holder.name = "Chunk_%d_%d" % [origin.x, origin.y]
	add_child(holder)
	_mesh_child(holder, chunk.top, _top_mat, "Tops")
	_mesh_child(holder, chunk.cliff, _cliff_mat, "Cliffs")
	if (chunk.faces as PackedVector3Array).size() >= 3:
		var shape := CollisionShape3D.new()
		shape.name = "Collision_%d_%d" % [origin.x, origin.y]
		var poly := ConcavePolygonShape3D.new()
		poly.set_faces(chunk.faces)
		shape.shape = poly
		# DIRECT child of the body, not of the chunk holder: a CollisionShape3D only
		# registers on its immediate CollisionObject3D parent, and one nested under a
		# plain Node3D is silently ignored — the walk bench fell straight through W1's
		# beautifully verified, entirely decorative colliders. Chunk-local coords equal
		# body-local coords (holders sit at the origin), so nothing else moves.
		add_child(shape)
	return holder


func _mesh_child(holder: Node3D, arrays: Array, mat: Material, mesh_name: String) -> void:
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	mi.material_override = mat
	holder.add_child(mi)


func _material(style: WildsStyle, cliff: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("is_cliff", cliff)
	if style != null:
		mat.set_shader_parameter("grass_color", Vector3(style.grass_color.r,
				style.grass_color.g, style.grass_color.b))
		mat.set_shader_parameter("grass_dark", Vector3(style.grass_dark.r,
				style.grass_dark.g, style.grass_dark.b))
		mat.set_shader_parameter("dirt_color", Vector3(style.dirt_color.r,
				style.dirt_color.g, style.dirt_color.b))
		mat.set_shader_parameter("cliff_color", Vector3(style.cliff_color.r,
				style.cliff_color.g, style.cliff_color.b))
		mat.set_shader_parameter("cliff_dark", Vector3(style.cliff_dark.r,
				style.cliff_dark.g, style.cliff_dark.b))
		mat.set_shader_parameter("strata_height", style.strata_height)
	return mat


# ---------------------------------------------------------------- water ---------------------

## One flat surface per water REGION on the existing water_stylized shader: the lake's whole
## SHAPE lives in a baked depth texture (red = metres underwater / DEPTH_SCALE), so foam is the
## shallow band by construction and the quad discards over dry ground. The plane is a padded
## SQUARE because the shader maps UV as xz / extent — a square keeps the texture unstretched.
## The depth image is written into one buffer and created from data in one call — never
## set_pixel, the recorded 110 ms trap.
func _build_water(style: WildsStyle) -> void:
	if not derived.has("regions"):
		return
	for r_id in (derived.regions as Array).size():
		var region: Dictionary = derived.regions[r_id]
		var bounds: Rect2i = region.bounds
		var tier: int = region.tier
		var surface_y := tier * map.tier_height - WildsGen.SURFACE_DROP
		var side_m := (maxi(bounds.size.x, bounds.size.y) + 2) * map.cell_size
		var centre := (Vector2(bounds.position) + Vector2(bounds.size) * 0.5) * map.cell_size
		_water_plane(derived, r_id, Rect2i(bounds.position, bounds.size).grow(0),
				Vector2(side_m, side_m), centre, surface_y, "Water_%d" % r_id, self, style)


## Water surfaces for ONE lazily-derived chunk, parented under its holder (freed with it).
## Each region piece covers the region's cells inside the chunk, padded one cell on any side
## where the water does NOT continue into the neighbouring chunk (the jittered shoreline
## wanders up to 0.7 m past the cell rect and the fade needs room) — and NOT padded where it
## does, so adjacent chunks' pieces abut exactly instead of z-fighting on a shared strip.
func _water_surfaces(src: Dictionary, origin: Vector2i, into: Node3D) -> void:
	if not src.has("regions"):
		return
	var chunk_rect := Rect2i(origin, Vector2i(WildsGen.CHUNK, WildsGen.CHUNK)) \
			.intersection(Rect2i(0, 0, map.cells_w, map.cells_h))
	for r_id in (src.regions as Array).size():
		var region: Dictionary = src.regions[r_id]
		var inter := Rect2i()
		var any := false
		var cont := {"l": false, "r": false, "t": false, "b": false}
		for i in (region.cells as Array):
			var c := Vector2i(int(i) % map.cells_w, int(i) / map.cells_w)
			if chunk_rect.has_point(c):
				inter = Rect2i(c, Vector2i.ONE) if not any \
						else inter.merge(Rect2i(c, Vector2i.ONE))
				any = true
			else:
				cont.l = cont.l or c.x < chunk_rect.position.x
				cont.r = cont.r or c.x >= chunk_rect.end.x
				cont.t = cont.t or c.y < chunk_rect.position.y
				cont.b = cont.b or c.y >= chunk_rect.end.y
		if not any:
			continue
		var pad_l := 0 if cont.l else 1
		var pad_r := 0 if cont.r else 1
		var pad_t := 0 if cont.t else 1
		var pad_b := 0 if cont.b else 1
		var rect := Rect2i(inter.position - Vector2i(pad_l, pad_t),
				inter.size + Vector2i(pad_l + pad_r, pad_t + pad_b))
		var tier: int = region.tier
		var surface_y := tier * map.tier_height - WildsGen.SURFACE_DROP
		var size_m := Vector2(rect.size) * map.cell_size
		var centre := (Vector2(rect.position) + Vector2(rect.size) * 0.5) * map.cell_size
		var extent := maxf(size_m.x, size_m.y)
		_water_plane(src, r_id, rect, size_m, centre, surface_y,
				"Water_%d_%d_%d" % [origin.x, origin.y, r_id], into, _style, extent)


## One surface plane + its baked depth texture. The depth image always covers the SQUARE of
## side `extent` around `centre` — the shader maps object xz / extent, so a NON-square plane
## simply samples its own subrect of that square.
func _water_plane(src: Dictionary, r_id: int, _rect: Rect2i, size_m: Vector2,
		centre: Vector2, surface_y: float, node_name: String, into: Node3D,
		style: WildsStyle, extent := 0.0) -> void:
	if extent <= 0.0:
		extent = maxf(size_m.x, size_m.y)
	var px := int(ceil(extent * DEPTH_PX_PER_M))
	var buf := PackedFloat32Array()
	buf.resize(px * px)
	for pz in px:
		for pxx in px:
			var world := centre + (Vector2(pxx + 0.5, pz + 0.5) / px - Vector2(0.5, 0.5)) \
					* extent
			buf[pz * px + pxx] = _depth_at(src, world, r_id, surface_y) / DEPTH_SCALE
	var img := Image.create_from_data(px, px, false, Image.FORMAT_RF,
			buf.to_byte_array())
	var mesh := PlaneMesh.new()
	mesh.size = size_m
	# SUBDIVIDED, because the surface now MOVES. A 2-triangle quad cannot show a wave however
	# good the solver is; the shader displaces vertices by eta, so the mesh needs enough of
	# them that a ring crest gets three or four. Capped, because the eager path builds one
	# plane per whole lake and a 200 m region at 0.5 m would be 160k vertices for water nobody
	# is standing next to.
	mesh.subdivide_width = clampi(int(size_m.x / WATER_VERTS_M) - 1, 0, WATER_SUBDIV_MAX)
	mesh.subdivide_depth = clampi(int(size_m.y / WATER_VERTS_M) - 1, 0, WATER_SUBDIV_MAX)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("extent", extent)
	mat.set_shader_parameter("depth_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("depth_scale", DEPTH_SCALE)
	mat.set_shader_parameter("flow_map", _flow_image(src, centre, extent))
	mat.set_shader_parameter("flow_speed", _flow_speed)
	if style != null:
		mat.set_shader_parameter("flow_drag", style.flow_drag)
		mat.set_shader_parameter("foam_speed", style.foam_speed)
		mat.set_shader_parameter("foam_gather", style.foam_gather)
	if style != null:
		mat.set_shader_parameter("shallow_color", style.water_shallow)
		mat.set_shader_parameter("deep_color", style.water_deep)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(centre.x, surface_y, centre.y)
	# TAGGED, so a scene running the DEPTH solver can turn them off. These planes are flat, sit at
	# one fixed height per region, decide where water is from a baked texture, and read the state
	# texture's R as a small deviation from that height. Every one of those is correct for the eta
	# encoding they were built for and wrong for depth, where R is an absolute column - hand this
	# shader 2.25 m where it expects centimetres and the lake renders as a flat white sheet with a
	# perfectly good simulation running underneath it.
	#
	# A group rather than a flag on this node: the terrain should not have to know which solver a
	# scene chose, and a scene that swaps the surface should not have to know how many regions the
	# generator happened to make.
	mi.add_to_group("wilds_water_plane")
	into.add_child(mi)


## The flow field over the same square the depth map covers, one texel per two metres. Its own
## small loop rather than a channel of the depth image: at a sixteenth the samples this costs
## about 6% of what fusing it into the depth bake would, and the depth map stays FORMAT_RF.
## Written into ONE buffer and created from data in ONE call — never set_pixel, the recorded
## 110 ms trap.
func _flow_image(src: Dictionary, centre: Vector2, extent: float) -> ImageTexture:
	var px := maxi(2, int(ceil(extent * FLOW_PX_PER_M)))
	var buf := PackedFloat32Array()
	buf.resize(px * px * 3)
	var tiers = src.tiers
	for pz in px:
		for pxx in px:
			var world := centre + (Vector2(pxx + 0.5, pz + 0.5) / px - Vector2(0.5, 0.5)) \
					* extent
			var c := Vector2i(floori(world.x / map.cell_size), floori(world.y / map.cell_size))
			var f := WildsGen.flow_at(map, tiers, c)
			# CONVERGENCE, -divergence by central differences on the cell lattice. Positive
			# where the current crowds into itself; that is where foam gathers and stays,
			# and it is free here because the neighbours are four more pure calls.
			var fx1 := WildsGen.flow_at(map, tiers, c + Vector2i(1, 0))
			var fx0 := WildsGen.flow_at(map, tiers, c - Vector2i(1, 0))
			var fz1 := WildsGen.flow_at(map, tiers, c + Vector2i(0, 1))
			var fz0 := WildsGen.flow_at(map, tiers, c - Vector2i(0, 1))
			var conv := -0.5 * ((fx1.x - fx0.x) + (fz1.y - fz0.y))
			var o := (pz * px + pxx) * 3
			buf[o] = f.x
			buf[o + 1] = f.y
			buf[o + 2] = maxf(conv, 0.0)
	return ImageTexture.create_from_image(Image.create_from_data(px, px, false,
			Image.FORMAT_RGBF, buf.to_byte_array()))


## THE BED ELEVATION under a world point of THIS region, in world Y - NAN anywhere else.
## Bilinear over the cell's four corner bed depths, so the shore band eases instead of stepping
## per cell.
##
## THIS IS THE ONE OWNER of that arithmetic. Three things read it - the baked depth texture, the
## gameplay depth query, and the solver bed channel - and the whole reason what a body feels
## cannot drift from what the surface shows is that none of them computes it a second time.
func _bed_y_at(src: Dictionary, world: Vector2, r_id: int) -> float:
	var c := Vector2i(floori(world.x / map.cell_size), floori(world.y / map.cell_size))
	if not map.in_bounds(c) or int(src.region_of.get(map.idx(c), -1)) != r_id:
		return NAN
	var tier: int = src.tiers.get(map.idx(c), 0) if src.tiers is Dictionary \
			else src.tiers[map.idx(c)]
	var f := world / map.cell_size - Vector2(c)
	var d00 := _corner_depth(c, Vector2i(0, 0), tier)
	var d10 := _corner_depth(c, Vector2i(1, 0), tier)
	var d01 := _corner_depth(c, Vector2i(0, 1), tier)
	var d11 := _corner_depth(c, Vector2i(1, 1), tier)
	var bed_drop: float = lerpf(lerpf(d00, d10, f.x), lerpf(d01, d11, f.x), f.y)
	return tier * map.tier_height - bed_drop


## Metres of water under a world point of THIS region, 0 anywhere else.
func _depth_at(src: Dictionary, world: Vector2, r_id: int, surface_y: float) -> float:
	var b := _bed_y_at(src, world, r_id)
	return 0.0 if is_nan(b) else maxf(surface_y - b, 0.0)


func _corner_depth(c: Vector2i, off: Vector2i, _tier: int) -> float:
	return WildsGen.BED_SHALLOW if WildsGen._corner_touches_dry(map, c + off) \
			else WildsGen.bed_deep(map)


# ---------------------------------------------------------------- kit sockets ---------------

## THE KIT SEAM, opened but not yet asked to carry weight: every cliff segment offers itself to
## the style's authored pieces (Kit._resolve's ladder — "straight_<drop>" then "straight"), and
## every water-rim segment to the waterfall socket. Pieces are DRESSING over the procedural
## face, not a replacement for it: the generated quads stay as the collider and the backing, so
## an authored piece thinner than the silhouette can never open a hole. Placement contract for
## the Blender kit: origin at the FOOT of the face on the unjittered cell-edge lattice, face
## authored on local -Z looking outward, one cell (2.0 m) wide, one course (1.2 m) per drop —
## art thicker than the corner jitter's ±0.7 m covers the wobble.
## Runs with or WITHOUT a style: authored cliff pieces need one, but the procedural spill does
## not, and the benches carry no style resource at all — gating the whole pass on `style`
## meant the falls could never appear anywhere they could be looked at.
func _place_pieces(style: WildsStyle) -> void:
	if not derived.has("segments"):
		return
	_place_segments(derived, derived.segments, self, style)


func _place_segments(src: Dictionary, segs: Array, into: Node3D, style: WildsStyle) -> void:
	var tiers = src.tiers
	var pieces := Node3D.new()
	pieces.name = "CliffPieces"
	var falls := Node3D.new()
	falls.name = "Waterfalls"
	for s: Dictionary in segs:
		var c: Vector2i = s.cell
		var dir: Vector2i = s.side
		var drop: int = s.drop
		var top: float = tiers[map.idx(c)] * map.tier_height
		var edge := Vector3((c.x + 0.5 + dir.x * 0.5) * map.cell_size, 0.0,
				(c.y + 0.5 + dir.y * 0.5) * map.cell_size)
		# -Z after a yaw of r points (-sin r, -cos r); solving for `dir` outward.
		var yaw := atan2(-float(dir.x), -float(dir.y))
		var scene := _cliff_piece(style, drop) if style != null else null
		if scene != null:
			var p := scene.instantiate() as Node3D
			if p != null:
				p.position = edge + Vector3(0.0, top - drop * map.tier_height, 0.0)
				p.rotation.y = yaw
				pieces.add_child(p)
		# THE WORLD'S EDGE DOES NOT POUR INTO THE VOID. A rim segment has no in-bounds low
		# neighbour (_segments_for reads its tier as -1), so in BORDER_SEA mode — where the
		# border band IS water — every perimeter cell would otherwise grow a waterfall
		# spilling off the map. The segment itself must stay: it is the cliff face that walls
		# the world. Only the spill is suppressed.
		if WildsGen.is_water(map, map.idx(c)) and map.in_bounds(c + dir):
			_spill(falls, style, edge, top, drop, yaw)
	for holder: Node3D in [pieces, falls]:
		if holder.get_child_count() > 0:
			into.add_child(holder)
		else:
			holder.free()


## ONE SPILL at a water rim. An authored `waterfall_scene` wins if the style carries one;
## otherwise the fall is generated, the way tree_scenes falls back to a stand-in rather than
## leaving the world bare. Either way the sheet hangs from the LIP — the upper pool's surface
## at top - SURFACE_DROP — down to the foot, so a three-course drop gets a three-course fall
## instead of the one-size prefab the socket's old ladder would have handed it.
func _spill(falls: Node3D, style: WildsStyle, edge: Vector3, top: float, drop: int,
		yaw: float) -> void:
	var lip := top - WildsGen.SURFACE_DROP
	var foot := top - drop * map.tier_height
	if style != null and style.waterfall_scene != null:
		var f := style.waterfall_scene.instantiate() as Node3D
		if f != null:
			f.position = edge + Vector3(0.0, lip, 0.0)
			f.rotation.y = yaw
			falls.add_child(f)
		return
	var height := maxf(lip - foot, 0.1)
	var quad := QuadMesh.new()
	quad.size = Vector2(map.cell_size, height)
	# SUBDIVIDED so the sheet can bulge. Two triangles cannot have thickness, and the fall read
	# as frosted glass for exactly that reason before the shader had vertices to move.
	quad.subdivide_width = 12
	quad.subdivide_depth = maxi(6, int(height / 0.18))
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _fall_mat(style)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# QuadMesh is centred on its own origin in the local XY plane, so the sheet hangs from the
	# lip when its centre sits half a height below it. The yaw is the segment's own, which the
	# kit contract already defines as -Z pointing outward (downstream).
	mi.position = edge + Vector3(0.0, lip - height * 0.5, 0.0)
	mi.rotation.y = yaw
	mi.set_script(load("res://scripts/waterfall.gd"))
	# The plunge point sits a little downstream of the face so its rings spread into the pool
	# rather than into the cliff behind them.
	# THE PLUNGE POINT IS STORED LOCAL, never as a baked world position. wilds_zone sets
	# terrain.position AFTER build() returns, so a to_global() taken here resolves through a
	# terrain still sitting at the origin and comes out half a map away — every fall was
	# ringing the water 90 m from itself, outside the solver window, which culls it. Hence a
	# plunge pool with no rings in it. Same frame the mist already uses.
	mi.set("foot_local", Vector3(0.0, -height * 0.5 + 0.1, -map.cell_size * 0.45))
	mi.set("width", map.cell_size)
	mi.set("strength", 0.015 + 0.008 * float(drop))
	falls.add_child(mi)
	# The mist hangs under its OWN fall, not under the Waterfalls holder: it belongs to that
	# sheet, it dies with it, and the holder keeps meaning exactly one child per water-rim
	# segment (which the sockets suite counts).
	_plunge(mi, height, drop)


## THE PLUNGE: continuous mist at the foot of a fall. NOT fx_oneshot — that frees itself on
## `finished`, which an emitter that never stops never emits. A permanent emitter needs no
## script at all, which is why this has none.
##
## The rings in the pool are waterfall.gd's job; this is the part that leaves the water.
func _plunge(into: Node3D, height: float, drop: int) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = map.cell_size * 0.35
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 42.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.9 + 0.4 * float(drop)
	pm.gravity = Vector3(0.0, -6.5, 0.0)      # lighter than real: mist hangs
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.color = Color(0.94, 0.98, 0.99, 0.55)
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.99, 1.0, 0.6)
	var p := GPUParticles3D.new()
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.material_override = mat
	p.amount = 10 + 6 * drop
	p.lifetime = 1.1
	p.explosiveness = 0.0
	p.one_shot = false
	p.emitting = true
	# Particles live in WORLD space but GPUParticles3D culls on a NODE-LOCAL box, and the 4 m
	# default would pop the mist out whenever the emitter left frame (blade_trail.gd's trap).
	p.visibility_aabb = AABB(Vector3(-4.0, -3.0, -4.0), Vector3(8.0, 8.0, 8.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	into.add_child(p)
	# In the sheet's own frame: the quad is centred, -Z is downstream, so the plunge sits half
	# a height below the centre and a little out from the face.
	p.position = Vector3(0.0, -height * 0.5 + 0.1, -map.cell_size * 0.45)


func _fall_mat(style: WildsStyle) -> ShaderMaterial:
	if _fall_mat_cache == null:
		var m := ShaderMaterial.new()
		m.shader = FALL_SHADER
		if style != null:
			m.set_shader_parameter("water_color", style.water_shallow)
		_fall_mat_cache = m
	return _fall_mat_cache


func _cliff_piece(style: WildsStyle, drop: int) -> PackedScene:
	for key in ["straight_%d" % drop, "straight"]:
		var v: Variant = style.cliff_pieces.get(key)
		if v is PackedScene:
			return v
	return null


# ---------------------------------------------------------------- ground contract -----------
# The trio GrassPatch/BushPatch duck-type (grass_patch.gd:723-763). `local` is this node's own
# XZ plane, exactly as TerrainField answers it.

func side() -> int:
	return map.cells_w if map != null else 0


## Honest for the STEPPED model: a terrace answers its tier height, a ramp answers its slope.
## The XZ corner jitter only moves where a border falls, never what height a surface has — so
## a cell lookup is exact everywhere except within a jitter's width of a border, where grass
## erring one cell lands on an equally real surface.
func height_at(local: Vector2) -> float:
	if map == null or (derived.is_empty() and not _lazy):
		return 0.0
	var c := _cell_of(local)
	var src := _src_for(c)
	var t: int = src.tiers[map.idx(c)]
	var y := t * map.tier_height
	var dir: Vector2i = (src.ramps as Dictionary).get(map.idx(c), Vector2i.ZERO)
	if dir == Vector2i.ZERO:
		return y
	var frac := local / map.cell_size - Vector2(c)
	var along := frac.x if dir.x != 0 else frac.y
	if dir.x < 0 or dir.y < 0:
		along = 1.0 - along
	return y + clampf(along, 0.0, 1.0) * map.tier_height


func normal_at(local: Vector2) -> Vector3:
	if map == null or (derived.is_empty() and not _lazy):
		return Vector3.UP
	var c := _cell_of(local)
	var src := _src_for(c)
	var dir: Vector2i = (src.ramps as Dictionary).get(map.idx(c), Vector2i.ZERO)
	if dir == Vector2i.ZERO:
		return Vector3.UP
	return Vector3(-dir.x * map.tier_height, map.cell_size, -dir.y * map.tier_height).normalized()


## THE WATER HALF OF THE CONTRACT (the water milestones' addition): the surface height over a
## point, NAN where no water region claims the cell — so a caller can tell "no water" from
## "water at height zero". Same terrain-local XZ frame as height_at. Lazy mode resolves
## through the same region cache the streamer keeps warm, so a probe inside the ring is a
## dictionary hit, never a derive.
func water_surface_y(local: Vector2) -> float:
	if map == null or (derived.is_empty() and not _lazy) or not _on_map(local):
		return NAN
	var c := _cell_of(local)
	var src := _src_for(c)
	var r_id := int((src.region_of as Dictionary).get(map.idx(c), -1))
	if r_id < 0:
		return NAN
	return float((src.regions[r_id] as Dictionary).tier) * map.tier_height \
			- WildsGen.SURFACE_DROP


## Metres of water COLUMN under a point — 0 on dry ground and on the wet beach (where the bed
## stands above the surface). The same bilinear corner math the baked depth texture uses
## (_depth_at), so what the shader shows and what gameplay feels agree by construction.
func water_depth_at(local: Vector2) -> float:
	if map == null or (derived.is_empty() and not _lazy) or not _on_map(local):
		return 0.0
	var c := _cell_of(local)
	var src := _src_for(c)
	var r_id := int((src.region_of as Dictionary).get(map.idx(c), -1))
	if r_id < 0:
		return 0.0
	var surface := float((src.regions[r_id] as Dictionary).tier) * map.tier_height \
			- WildsGen.SURFACE_DROP
	return _depth_at(src, local, r_id, surface)


## THE BED under a point, in world Y - the floor the water sits on, whether or not there is any
## water on it. Inside a water region it is the same bilinear corner math water_depth_at uses, so
## `bed + depth == surface` holds exactly rather than approximately. On dry ground it is the
## terrain itself, which is what lets a solver flood ground that was never painted as water.
##
## OFF THE MAP IT IS A WALL, not a hole. height_at deliberately clamps off-map lookups to the edge
## cell, and inheriting that here would hand a solver a flat shelf at the world edge to spread
## across forever. A sentinel far above any terrain reads to the solver as a bed it can never
## climb - the reflecting boundary comes free, out of the same rule that already keeps a raft
## from floating over the void (_on_map).
func water_bed_y(local: Vector2) -> float:
	if map == null or (derived.is_empty() and not _lazy) or not _on_map(local):
		return Water.BED_WALL
	var c := _cell_of(local)
	var src := _src_for(c)
	var r_id := int((src.region_of as Dictionary).get(map.idx(c), -1))
	if r_id >= 0:
		var b := _bed_y_at(src, local, r_id)
		if not is_nan(b):
			return b
	return height_at(local)


## THE CURRENT at a point, in metres/second, Vector2.ZERO on dry ground. Recomputed from the
## same pure function the texture was baked from rather than read back off the GPU, so what
## the surface shows and what a body feels cannot drift apart — and a query into an unbuilt
## chunk answers without needing its water plane to exist.
func water_flow_at(local: Vector2) -> Vector2:
	if map == null or (derived.is_empty() and not _lazy) or not _on_map(local):
		return Vector2.ZERO
	var c := _cell_of(local)
	return WildsGen.flow_at(map, _src_for(c).tiers, c) * _flow_speed


## Is this cell a painted spring? Terrain-local XZ, like the rest of the water contract.
func water_is_spring(local: Vector2) -> bool:
	if map == null or not _on_map(local):
		return false
	return WildsGen.is_spring(map, map.idx(_cell_of(local)))


## The dict a cell's numbers live in — the global derivation, or the cell's chunk region.
func _src_for(c: Vector2i) -> Dictionary:
	if not _lazy:
		return derived
	@warning_ignore("integer_division")
	return region_for(Vector2i(c.x / WildsGen.CHUNK * WildsGen.CHUNK,
			c.y / WildsGen.CHUNK * WildsGen.CHUNK))


## Is this point actually ON the map? height_at deliberately CLAMPS off-map lookups to the
## edge cell — grass a jitter's width past the last cell wants the last cell's ground. Water
## must not: past a sea border the clamp would answer "water here" over the void, and a body
## or a raft asking would be told it can float where there is no world.
func _on_map(local: Vector2) -> bool:
	return local.x >= 0.0 and local.y >= 0.0 \
			and local.x < map.cells_w * map.cell_size \
			and local.y < map.cells_h * map.cell_size


func _cell_of(local: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(local.x / map.cell_size), 0, map.cells_w - 1),
			clampi(floori(local.y / map.cell_size), 0, map.cells_h - 1))

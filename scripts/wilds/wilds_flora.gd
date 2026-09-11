@tool
extends Object
## LIFE ON THE TERRACES, by reuse: real GrassPatch/BushPatch instances (the foliage addon's own
## nodes, so the foliage dock keeps painting on top of what the generator laid down), and trees
## STAMPED as real child nodes under a painted_skin parent — never scattered into a MultiMesh,
## because a tree is big enough to be placed, selected, and deleted by hand.
##
## Density = the map's forest_paint over a seeded noise base, silenced by clearings, water,
## ramps and the spawn lane. Randomness keyed to WHERE (cell hash), so repainting one glade
## cannot reshuffle a single distant trunk.
##
## Two API facts this file is shaped around (measured in grass_patch.gd):
##  - append_stroke() re-uploads the whole MultiMesh buffer per dab — fine for a brush, O(n²)
##    for a generator. We fill the stroke ARRAYS directly and rebuild() once: rebuild's replay
##    is _emit_dab in the same order at the same seed, byte-for-byte what the brush would make.
##  - the default dab rate is count/region_area ≈ 24 tufts/m²; a dab per cell at that rate is
##    hundreds of thousands of tufts. density is set EXPLICITLY and dabs are hash-thinned.

const TREE_FALLBACKS := ["res://assets/models/veg_leaf_tree.glb",
		"res://assets/models/veg_leaf_tree_b.glb"]
const BUSH_SOURCE := "res://assets/models/veg_leaf_bush.glb"
const PAINTED_SKIN := "res://scripts/painted_skin.gd"
const TREE_MATERIAL := "res://assets/materials/painted_foliage_leaf_tree.tres"

const TREE_THRESHOLD := 0.55
const GRASS_THRESHOLD := 0.25
## 3, not 2: canopies lean a cell past their trunk, and at the game's 53° pitch a tree two
## cells south of the spawn hangs over the player's head — measured in the walk bench.
const SPAWN_CLEAR_CELLS := 3


## `region` scopes the growth to a cell rectangle — the streaming path builds one chunk's
## flora at a time; empty means the whole map (the editor preview and the suites). Cell hashes
## key everything to WHERE, so a region build grows exactly the region's slice of the full
## forest, whichever order the chunks arrive in.
static func build(parent: Node3D, map: WildsMap, derived: Dictionary,
		terrain: Node3D, style: WildsStyle, region := Rect2i()) -> void:
	var r := region if region.has_area() else Rect2i(0, 0, map.cells_w, map.cells_h)
	r = r.intersection(Rect2i(0, 0, map.cells_w, map.cells_h))
	var tiers = derived.tiers                 # whole-map array OR a region's dict — both index
	var ramps: Dictionary = derived.ramps
	var spawn: Vector2i = derived.get("spawn", Vector2i(-1, -1))

	# THE TREES: one candidate per cell, kept when the density says forest and the cell hash
	# agrees — a dense stand at full paint, stragglers at the noise's edge. All children are
	# added BEFORE the stands node enters the tree: painted_skin skins in _ready, and a child
	# arriving after that walk stays raw.
	var scenes: Array = []
	if style != null and not style.tree_scenes.is_empty():
		scenes = style.tree_scenes
	else:
		for path in TREE_FALLBACKS:
			if ResourceLoader.exists(path):
				scenes.append(load(path))
	var stands := Node3D.new()
	stands.name = "PaintedTrees"
	var skin := load(PAINTED_SKIN)
	if skin != null:
		stands.set_script(skin)
		if ResourceLoader.exists(TREE_MATERIAL):
			stands.set("env_template", load(TREE_MATERIAL))
		stands.set("use_vertex_color", true)
		stands.set("verbose", false)
	if not scenes.is_empty():
		for cz in range(r.position.y, r.end.y):
			for cx in range(r.position.x, r.end.x):
				var c := Vector2i(cx, cz)
				var i := map.idx(c)
				if WildsGen.is_water(map, i) or ramps.has(i):
					continue
				if absi(cx - spawn.x) <= SPAWN_CLEAR_CELLS \
						and absi(cz - spawn.y) <= SPAWN_CLEAR_CELLS:
					continue
				var density := _density(map, c)
				if density < TREE_THRESHOLD:
					continue
				var h := _mix(map.seed, cx, cz, 7)
				if float(h & 0xFFFF) / 65535.0 > (density - TREE_THRESHOLD) * 2.2:
					continue
				var inst := (scenes[h % scenes.size()] as PackedScene).instantiate() as Node3D
				if inst == null:
					continue
				inst.name = "Tree"
				var jx := (float((h >> 4) & 0xFF) / 255.0 - 0.5) * map.cell_size * 0.6
				var jz := (float((h >> 12) & 0xFF) / 255.0 - 0.5) * map.cell_size * 0.6
				inst.position = Vector3((cx + 0.5) * map.cell_size + jx,
						tiers[i] * map.tier_height,
						(cz + 0.5) * map.cell_size + jz)
				inst.rotation.y = float(h % 628) / 100.0
				var s := 0.85 + float((h >> 8) & 0xFF) / 255.0 * 0.5
				inst.scale = Vector3(s, s, s)
				stands.add_child(inst)
	parent.add_child(stands)

	# THE UNDERGROWTH: one GrassPatch and one BushPatch over the whole map in paint_only mode,
	# dabbed where the ground is grassy. Patches sit at the terrain's origin so patch-local XZ
	# equals terrain-local XZ — the ground contract needs no translation.
	var grass := GrassPatch.new()
	grass.name = "WildsGrass"
	grass.paint_only = true
	grass.rng_seed = map.seed * 31 + 5
	grass.density = 3.5
	grass.brush_radius = 1.2
	var bushes := BushPatch.new()
	bushes.name = "WildsBushes"
	bushes.paint_only = true
	bushes.rng_seed = map.seed * 31 + 9
	bushes.density = 0.12
	bushes.brush_radius = 1.8
	if ResourceLoader.exists(BUSH_SOURCE):
		bushes.mesh_source = load(BUSH_SOURCE)
	for cz in range(r.position.y, r.end.y):
		for cx in range(r.position.x, r.end.x):
			var c := Vector2i(cx, cz)
			var i := map.idx(c)
			if WildsGen.is_water(map, i):
				continue
			var density := _density(map, c)
			if density < GRASS_THRESHOLD:
				continue
			var h := _mix(map.seed, cx, cz, 11)
			var at := Vector2((cx + 0.5) * map.cell_size, (cz + 0.5) * map.cell_size)
			var y: float = tiers[i] * map.tier_height
			if float(h & 0xFF) / 255.0 < 0.4:
				grass.brush_points.append(at)
				grass.brush_radii.append(grass.brush_radius)
				grass.brush_heights.append(y)
				grass.brush_normals.append(Vector3.UP)
			# Bushes honour the spawn clearing like trees do — a bush is tall enough to hide
			# the character standing in it (measured in the walk bench). Grass is not.
			if density > 0.45 and float((h >> 8) & 0xFF) / 255.0 < 0.22 \
					and not (absi(cx - spawn.x) <= SPAWN_CLEAR_CELLS
					and absi(cz - spawn.y) <= SPAWN_CLEAR_CELLS):
				bushes.brush_points.append(at)
				bushes.brush_radii.append(bushes.brush_radius)
				bushes.brush_heights.append(y)
				bushes.brush_normals.append(Vector3.UP)
	parent.add_child(grass)
	grass.terrain = grass.get_path_to(terrain)
	grass.rebuild()
	grass.settle()
	parent.add_child(bushes)
	bushes.terrain = bushes.get_path_to(terrain)
	bushes.rebuild()          # BushPatch has no settle(); its shading is per-instance already


## Forest density in [0, 1]: a broad seeded noise base lifted by the author's forest paint and
## silenced by clearings.
static func _density(map: WildsMap, c: Vector2i) -> float:
	var i := map.idx(c)
	if (map.flag_at(i) & WildsMap.F_CLEARING) != 0:
		return 0.0
	var h := _mix(map.seed, c.x >> 2, c.y >> 2, 3)      # 4-cell blocks: woods, not confetti
	var base := float(h & 0xFFFF) / 65535.0 * 0.55 + 0.2
	return clampf(base + float(map.forest_at(i)) / 255.0, 0.0, 1.0)


static func _mix(sd: int, x: int, z: int, salt: int) -> int:
	var h := sd * 0x9E3779B1 + x * 0x85EBCA77 + z * 0xC2B2AE3D + salt * 0x27D4EB2F
	h = (h ^ (h >> 15)) * 0x2545F491
	return (h ^ (h >> 13)) & 0x7FFFFFFF

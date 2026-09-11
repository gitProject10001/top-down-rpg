@tool
extends Object
## THE FAR LOD: the whole map as one cheap backdrop — a stepped heightfield sampled at a
## stride (quantised noise + paint, no chamfer: approximate on purpose, this is scenery seen
## from hundreds of metres) and the forest as canopy MASSES in a single MultiMesh of low-poly
## blobs. The stride scales with the map (~160 samples per side), so a 16 km map costs the
## same as a 2 km one: one mesh around 50k triangles and a few thousand blob instances.
##
## Sits `y_offset` BELOW the true surface so real streamed/derived chunks always win the
## depth test where they overlap it — near ground covers the backdrop instead of z-fighting.
## `exclude` skips a cell rect entirely (the editor's ring preview cuts the hole where the
## exact chunks stand). Distant stands as MultiMesh is the recorded rule — near trees stay
## individually placed and selectable; THESE are the far ones.

const GROUND_SHADER := preload("res://shaders/wilds_ground.gdshader")
const Flora := preload("res://scripts/wilds/wilds_flora.gd")


static func build(map: WildsMap, style: WildsStyle = null, exclude := Rect2i(),
		y_offset := -0.25) -> Node3D:
	var root := Node3D.new()
	root.name = "FarLOD"
	root.set_script(load("res://scripts/wilds/wilds_far_node.gd"))
	var s := maxi(1, int(ceil(maxi(map.cells_w, map.cells_h) / 160.0)))
	var nx := int(ceil(float(map.cells_w) / s))
	var nz := int(ceil(float(map.cells_h) / s))
	var n := FastNoiseLite.new()
	n.seed = map.seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = map.noise_octaves
	n.frequency = map.noise_freq
	var th := map.tier_height
	var cs := map.cell_size

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var blob_at: Array = []                    # [Vector3 pos, float density, int hash]
	for gz in nz:
		for gx in nx:
			var cell_rect := Rect2i(gx * s, gz * s, s, s)
			if exclude.has_area() and exclude.intersects(cell_rect):
				continue
			var c := Vector2i(mini(gx * s + s / 2, map.cells_w - 1),
					mini(gz * s + s / 2, map.cells_h - 1))
			var i := map.idx(c)
			var v := n.get_noise_2d((c.x + 0.5) * cs, (c.y + 0.5) * cs)
			var t := WildsGen._finish_tier(map, c,
					clampi(int(floor((v * 0.5 + 0.5) * float(map.max_tier + 1))), 0, map.max_tier))
			var water := WildsGen.is_water(map, i)
			var y := t * th + y_offset
			var x0 := gx * s * cs
			var z0 := gz * s * cs
			var x1 := minf((gx + 1) * s * cs, map.cells_w * cs)
			var z1 := minf((gz + 1) * s * cs, map.cells_h * cs)
			var col := Color(clampf(float(t) / maxf(float(map.max_tier), 1.0), 0.0, 1.0),
					1.0 if water else 0.0, 0.0)
			_quad(verts, norms, cols, Vector3(x0, y, z0), Vector3(x1, y, z0),
					Vector3(x1, y, z1), Vector3(x0, y, z1), col)
			if not water:
				var density: float = Flora._density(map, c)
				if density > 0.5:
					blob_at.append([Vector3((x0 + x1) * 0.5, t * th, (z0 + z1) * 0.5),
							density, Flora._mix(map.seed, gx, gz, 17)])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	if verts.size() >= 3:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "FarGround"
	mi.mesh = mesh
	mi.material_override = _ground_material(style)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	if not blob_at.is_empty():
		var blob := SphereMesh.new()
		blob.radial_segments = 6
		blob.rings = 3
		blob.radius = 1.0
		blob.height = 1.4
		var mat := StandardMaterial3D.new()
		# ALBEDO on the material, not per-instance colours — instance colours through a
		# StandardMaterial proved unreliable (blobs rendered cream), and one canopy tone is
		# what distance shows anyway. DARK on purpose: a lit blob drinks the whole sky's
		# ambient, and this tone is what meets the real painted canopies at the handover.
		mat.albedo_color = Color(0.12, 0.24, 0.10)
		mat.roughness = 1.0
		blob.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = blob
		mm.instance_count = blob_at.size()
		var base_transforms: Array = []
		for k in blob_at.size():
			var e: Array = blob_at[k]
			var density: float = e[1]
			var h: int = e[2]
			var w := s * cs * (0.32 + 0.3 * density)
			var basis := Basis.from_scale(Vector3(w, w * (0.4 + 0.3
					* (float((h >> 8) & 0xFF) / 255.0)), w))
			# Hash jitter breaks the sampling grid — forest masses, not a plantation.
			var jx := (float(h & 0x7F) / 127.0 - 0.5) * s * cs * 0.6
			var jz := (float((h >> 16) & 0x7F) / 127.0 - 0.5) * s * cs * 0.6
			var t := Transform3D(basis, (e[0] as Vector3) + Vector3(jx, w * 0.3, jz))
			mm.set_instance_transform(k, t)
			base_transforms.append(t)
		root.call("register_blobs", base_transforms)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "FarCanopy"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	# Counts as metadata: the suites assert on these — mesh buffer readback is not a thing a
	# headless dummy renderer promises (the recorded MultiMesh lesson).
	root.set_meta("far_quads", verts.size() / 6)
	root.set_meta("far_blobs", blob_at.size())
	return root


## Front face clockwise about UP — the winding law, locally enforced.
static func _quad(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color) -> void:
	for tri: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		if (p1 - p0).cross(p2 - p0).dot(Vector3.UP) > 0.0:
			var t := p1
			p1 = p2
			p2 = t
		verts.append(p0)
		verts.append(p1)
		verts.append(p2)
		for _k in 3:
			norms.append(Vector3.UP)
			cols.append(col)


static func _ground_material(style: WildsStyle) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("is_cliff", false)
	if style != null:
		mat.set_shader_parameter("grass_color", Vector3(style.grass_color.r,
				style.grass_color.g, style.grass_color.b))
		mat.set_shader_parameter("grass_dark", Vector3(style.grass_dark.r,
				style.grass_dark.g, style.grass_dark.b))
		mat.set_shader_parameter("dirt_color", Vector3(style.dirt_color.r,
				style.dirt_color.g, style.dirt_color.b))
	return mat

extends Object
## THE WIREFRAME — every triangle GladeKit actually committed, drawn as lines.
##
## The question this exists to answer is "are these real polygons, or is something else going on?"
## The honest way to answer it is to read the INDEX BUFFERS OF THE COMMITTED MESHES and draw what is
## in them. Nothing here knows anything about walls, faces or styles; it walks a subtree, finds
## meshes, and draws their edges. If a triangle appears in this overlay it is in the mesh, and if it
## is in the mesh it appears here. There is no third possibility for it to be wrong in.
##
## WHY NOT `Viewport.DEBUG_DRAW_WIREFRAME`. Three lines and it would work — but it is all-or-nothing
## for the whole viewport, it needs `RenderingServer.set_debug_generate_wireframes(true)` before any
## mesh exists, and above all it cannot tell you WHICH KIND of triangle you are looking at. The whole
## point of looking at a mass in wireframe is seeing that it is two populations at once: a handful of
## big `ArrayMesh` panels and a few hundred instanced boxes. One colour for both hides exactly the
## thing worth seeing.
##
## `get_children(true)` IS NOT OPTIONAL. A `GladeMass` adopts every mesh it makes with
## `INTERNAL_MODE_BACK`, so an ordinary walk of the tree finds a node with no children and this file
## would cheerfully report zero triangles for a finished building. `shot_scene.gd` learned the same
## thing.
##
## DELIBERATELY NO `class_name`, like the rest of `scripts/dev` — see `tuning_panel.gd` for the
## reason. `preload()` it by path.

## Above this many line segments the overlay stops adding and says so in `counts()`. A masonry face
## is ~54 edges per stone, so a large building runs to six figures: past that the picture is solid
## ink anyway and the frame time is real. Truncation is REPORTED rather than silent — a wireframe
## that quietly stopped drawing would be a lie about the geometry, which is the one thing this file
## must not be.
const MAX_LINES := 140000

## Positions closer than this are the same corner. The meshes come out of `SurfaceTool.commit()`
## unindexed (nothing calls `index()`), so the same corner arrives many times over and the only way
## to draw a shared edge once is to weld on position.
const WELD := 0.0001


## One overlay node carrying the edges of everything under `root`.
##
## Built in GLOBAL space and marked `top_level`, so the caller may parent it anywhere without the
## lines drifting off the geometry they describe.
static func edges(root: Node3D, panel_col := Color(0.45, 0.9, 1.0),
		brick_col := Color(1.0, 0.75, 0.35)) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Wireframe"
	var budget := MAX_LINES

	var meshes: Array[MeshInstance3D] = []
	var multis: Array[MultiMeshInstance3D] = []
	_collect(root, meshes, multis)

	# --- the ArrayMesh panels: linings, copings, reveals, bevels, floors, textured faces ---------
	var lines := PackedVector3Array()
	for mi in meshes:
		if mi.mesh == null:
			continue
		var local := _mesh_edges(mi.mesh)
		var xf := mi.global_transform
		for i in local.size():
			if budget <= 0:
				break
			lines.append(xf * local[i])
			if i % 2 == 1:
				budget -= 1
	if not lines.is_empty():
		holder.add_child(_line_mesh(lines, panel_col))

	# --- the instanced pieces: every stone, timber, quoin and floorboard -------------------------
	var mirror := _mirror(root, multis)
	var taken := 0
	lines = PackedVector3Array()
	for mmi in multis:
		var mm := mmi.multimesh
		if mm == null or mm.mesh == null or mm.instance_count == 0:
			continue
		# THE TEMPLATE IS EXTRACTED ONCE. Every instance is the same unit box under a different
		# transform, which is the entire reason a wall of six hundred stones costs one mesh.
		var template := _mesh_edges(mm.mesh)
		var xf := mmi.global_transform
		for j in mm.instance_count:
			if budget <= 0:
				break
			var t := xf * (mirror[taken + j] if not mirror.is_empty() \
					else mm.get_instance_transform(j))
			for i in template.size():
				lines.append(t * template[i])
			budget -= template.size() / 2
		taken += mm.instance_count
	if not lines.is_empty():
		holder.add_child(_line_mesh(lines, brick_col))

	holder.set_meta("truncated", budget <= 0)
	return holder


## What the overlay just drew, as numbers. `tris` and `verts` are what is IN THE MESHES, not what
## survived the line budget — the counts describe the building, the overlay describes as much of it
## as it could draw.
static func counts(root: Node3D) -> Dictionary:
	var meshes: Array[MeshInstance3D] = []
	var multis: Array[MultiMeshInstance3D] = []
	_collect(root, meshes, multis)

	var out := {"tris": 0, "verts": 0, "surfaces": 0, "meshes": 0, "instances": 0,
			"instanced_tris": 0, "preview": 0}
	for mi in meshes:
		if mi.mesh == null:
			continue
		# The blockout preview counted apart from the real thing — see `_mesh_edges`.
		if not (mi.mesh is ArrayMesh):
			out.preview += 1
			continue
		out.meshes += 1
		for s in mi.mesh.get_surface_count():
			out.surfaces += 1
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null \
					else PackedInt32Array()
			out.verts += v.size()
			out.tris += (idx.size() if not idx.is_empty() else v.size()) / 3
	for mmi in multis:
		var mm := mmi.multimesh
		if mm == null or mm.mesh == null:
			continue
		out.instances += mm.instance_count
		var per := 0
		for s in mm.mesh.get_surface_count():
			var arr := mm.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null \
					else PackedInt32Array()
			per += (idx.size() if not idx.is_empty() else v.size()) / 3
		out.instanced_tris += per * mm.instance_count
	return out


## The counts line the panel shows. Kept here so the doc, the panel and the overlay cannot disagree
## about what a number means.
static func summary(root: Node3D) -> String:
	var c := counts(root)
	if c.tris == 0 and c.instances == 0:
		return "nothing committed yet.\n%d ImmediateMesh blockout preview(s)" % c.preview
	return "%d tris in %d ArrayMesh surface(s)\n+ %d instances x %d tris = %d\ntotal %d triangles" % [
			c.tris, c.surfaces, c.instances,
			(c.instanced_tris / maxi(c.instances, 1)), c.instanced_tris,
			c.tris + c.instanced_tris]


# ---------------------------------------------------------------- the walk ---------------------


## THE HEADLESS FALLBACK, and empty in every normal case.
##
## `MultiMesh.get_instance_transform` reads back identity under the dummy renderer, so a headless
## shot of this overlay would pile every stone in a building on the origin. `GladeMass` already keeps
## a CPU-side mirror of exactly those placements for its own tests (`snap_transforms`), and
## `GladeBuildBuffer.flatten()` concatenates the slots in the same order `_commit` adopts the
## `MultiMeshInstance3D`s in — so the mirror can be consumed run by run against the instance counts.
##
## Used only when the buffers are demonstrably dead: with a live renderer the MultiMesh is the
## authority, because it is the thing actually being drawn and therefore the thing worth checking.
static func _mirror(root: Node3D, multis: Array[MultiMeshInstance3D]) -> Array[Transform3D]:
	var total := 0
	for mmi in multis:
		if mmi.multimesh == null:
			continue
		total += mmi.multimesh.instance_count
		for j in mmi.multimesh.instance_count:
			if not mmi.multimesh.get_instance_transform(j).is_equal_approx(Transform3D.IDENTITY):
				return []                          # the buffers are live; nothing to fall back to
	if total == 0 or not (root is GladeMass):
		return []
	var snap: Array[Transform3D] = (root as GladeMass).snap_transforms
	return snap if snap.size() == total else []


## Every mesh under `root`, INCLUDING the internal children GladeKit hides its output in.
## LAST REBUILD'S MESHES ARE STILL IN THE TREE, and skipping them is not optional. `GladeMass` drops
## its old output with `queue_free()`, which does not take effect until the end of the frame — so
## anything that measures a mass in the same frame it rebuilt it sees every generation at once. A
## chapter that rebuilds three times to prove determinism read three blockouts and tripled its own
## instance count, which is the exact kind of quietly-wrong number this file exists not to produce.
static func _collect(n: Node, meshes: Array[MeshInstance3D],
		multis: Array[MultiMeshInstance3D]) -> void:
	if n.is_queued_for_deletion():
		return
	if n is MeshInstance3D:
		meshes.append(n as MeshInstance3D)
	elif n is MultiMeshInstance3D:
		multis.append(n as MultiMeshInstance3D)
	for c in n.get_children(true):
		_collect(c, meshes, multis)


# ---------------------------------------------------------------- the edges --------------------


## Every distinct triangle edge of a mesh, as consecutive point pairs in the mesh's own space.
##
## THE FAN DIAGONALS ARE DRAWN, and that is correct rather than sloppy. A GladeKit face is a triangle
## fan over a polygon, so the diagonals ARE edges of the triangles that exist; hiding them would draw
## a picture of the polygon somebody meant instead of the mesh that is there, and telling those two
## apart is the entire job. `GladeDebug.massing_mesh` takes the other choice deliberately — it draws
## the MASSING, where a facet join is noise.
static func _mesh_edges(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	var seen := {}                                 ## edge key -> true
	var ids := {}                                  ## welded position -> small int
	var pts: Array[Vector3] = []

	# COMMITTED GEOMETRY ONLY. An unstyled mass draws an `ImmediateMesh` blockout, which is a preview
	# of the intent and not a mesh anybody will ship — and it carries LINE surfaces, which read as
	# nonsense triangles if walked as though they were not. `counts()` reports it separately so the
	# distinction stays visible rather than becoming a silent zero.
	if not (mesh is ArrayMesh):
		return out

	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		# `SurfaceTool.commit()` without `index()` hands back an UNINDEXED surface, which every mesh
		# in this kit is. Both shapes are handled: with an index buffer, walk it; without one, the
		# triangles are consecutive triples.
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null \
				else PackedInt32Array()
		var n: int = idx.size() if not idx.is_empty() else v.size()
		var t := 0
		while t + 2 < n:
			var a := _weld(v[idx[t]] if not idx.is_empty() else v[t], ids, pts)
			var b := _weld(v[idx[t + 1]] if not idx.is_empty() else v[t + 1], ids, pts)
			var c := _weld(v[idx[t + 2]] if not idx.is_empty() else v[t + 2], ids, pts)
			_edge(a, b, seen, pts, out)
			_edge(b, c, seen, pts, out)
			_edge(c, a, seen, pts, out)
			t += 3
	return out


## A position's small integer id, welding anything within `WELD` onto the first one seen.
static func _weld(p: Vector3, ids: Dictionary, pts: Array[Vector3]) -> int:
	var key := Vector3i(roundi(p.x / WELD), roundi(p.y / WELD), roundi(p.z / WELD))
	if ids.has(key):
		return ids[key]
	var id := pts.size()
	ids[key] = id
	pts.append(p)
	return id


## Emit an edge once. Keyed on the ORDERED pair of ids, so the two triangles sharing an edge draw
## one line between them rather than two coincident ones.
static func _edge(a: int, b: int, seen: Dictionary, pts: Array[Vector3],
		out: PackedVector3Array) -> void:
	if a == b:
		return
	var key := (a * 1048576 + b) if a < b else (b * 1048576 + a)
	if seen.has(key):
		return
	seen[key] = true
	out.append(pts[a])
	out.append(pts[b])


## Lines into an `ImmediateMesh`, wearing the overlay material the rest of the kit's annotations use
## — unshaded, no depth test, high render priority, so the wireframe sits ON the stone rather than
## fighting it for the same pixels.
static func _line_mesh(lines: PackedVector3Array, col: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in lines:
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = GladeDebug.overlay_material(col)
	# Built in world space above; `top_level` keeps it that way wherever the caller parents it.
	mi.top_level = true
	return mi

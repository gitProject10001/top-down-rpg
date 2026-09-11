extends SceneTree
## MEASURE WHAT THE ENGINE ACTUALLY IMPORTED, not what Blender said it exported.
##
##   Godot_console.exe --path . --resolution 640x360 --script res://scripts/dev/probe_foliage.gd
##
## Two things are checked here, and both are invisible in a diff:
##
## 1. CANOPY ROUNDNESS survived the import. tools/fix_vegetation.py replaces the shading normals so
##    a bush reads as one soft mass, and tools/export_vegetation.py scores the result — but that
##    score is measured in Blender. Godot's scene importer is free to weld, re-smooth or LOD the
##    mesh on the way in, and `meshes/generate_lods` does exactly that. So the number has to be
##    taken again on this side of the import or it is only a claim about a file nobody loads.
##
## 2. THE BLOCKOUT'S OPENINGS were split. `bo_dark` used to mean both windows and doors; glass can
##    only be assigned to one of them, so the split has to have happened before the skin can route
##    it. The baked `bushes` object must also be gone, or the arena has two bush fields.
##
## Pass mark is 0.85. The shipped assets measured 0.41-0.73 before the fix.

const PASS := 0.85
const K := 0.5            ## must match tools/fix_vegetation.py
const STEM_ASPECT := 1.6  ## must match tools/fix_vegetation.py

const PIECES := [
	"res://assets/models/veg_bush.glb",
	"res://assets/models/veg_bush_b.glb",
	"res://assets/models/veg_bush_c.glb",
	"res://assets/models/veg_tree.glb",
	"res://assets/models/veg_tree_b.glb",
]


func _initialize() -> void:
	_run()


func _run() -> void:
	var bad := 0
	for path: String in PIECES:
		var mesh := _first_mesh(path)
		if mesh == null:
			print("[FOLIAGE] %-22s NO MESH" % path.get_file())
			bad += 1
			continue
		var score := _roundness(mesh)
		var ok := score >= PASS
		if not ok:
			bad += 1
		print("[FOLIAGE] %-22s roundness=%.3f  %s" % [path.get_file(), score, "ok" if ok else "FAIL"])

	# --- the blockout's openings
	var packed := load("res://assets/models/arena_blockout.glb") as PackedScene
	var root_node := packed.instantiate()
	var names := {}
	var has_bushes := false
	_collect(root_node, names)
	for c in root_node.get_children():
		if c.name == "bushes":
			has_bushes = true
	var keys: Array = names.keys()
	keys.sort()
	print("[BLOCKOUT] surface materials: %s" % [keys])
	print("[BLOCKOUT] bo_glass present: %s | bo_door present: %s | baked bushes gone: %s"
			% [names.has("bo_glass"), names.has("bo_door"), not has_bushes])
	if not names.has("bo_glass") or not names.has("bo_door") or has_bushes:
		bad += 1

	print("[FOLIAGE] %s" % ("all gates passed" if bad == 0 else "%d GATE(S) FAILED" % bad))
	quit(0 if bad == 0 else 1)


## Pull the first mesh out of an imported .glb scene. Same shape as GladeScatter._first_mesh.
func _first_mesh(path: String) -> Mesh:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var found := _find_mesh(inst)
	inst.free()
	return found


func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null


func _collect(n: Node, out: Dictionary) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat != null:
				out[mat.resource_name] = true
	for c in n.get_children():
		_collect(c, out)


## Mean dot(direction from the lowered canopy pivot, shading normal), stems excluded. Stems are
## found the same way the Blender side finds them: taller than they are wide.
func _roundness(mesh: Mesh) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.is_empty() or norms.is_empty():
		return 0.0

	# Godot is Y-up; the Blender side measured in Z-up. Height is VERTEX.y here.
	var aabb := mesh.get_aabb()
	var footprint := maxf(aabb.size.x, aabb.size.z)
	if aabb.size.y / maxf(footprint, 0.00001) > STEM_ASPECT:
		return 0.0

	var centroid := Vector3.ZERO
	for v in verts:
		centroid += v
	centroid /= float(verts.size())
	var pivot := centroid - Vector3(0.0, K * maxf(aabb.size.y, 0.00001), 0.0)

	var total := 0.0
	for i in verts.size():
		var d := verts[i] - pivot
		if d.length() < 0.000001:
			continue
		total += maxf(0.0, d.normalized().dot(norms[i]))
	return total / float(verts.size())

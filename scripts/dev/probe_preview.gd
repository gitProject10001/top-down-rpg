extends SceneTree
## Reproduce the EDITOR PREVIEW path exactly (wilds_preview_builder.build with a style) and
## report whether water planes exist, how many verts they carry, and what their material is.


func _initialize() -> void:
	var m := WildsMap.new()
	m.seed = 7
	m.cells_w = 64
	m.cells_h = 64
	for cz in range(30, 37):
		for cx in range(30, 40):
			m.set_flag(m.idx(Vector2i(cx, cz)), WildsMap.F_WATER)
	var d := WildsGen.derive(m)
	var style := WildsStyle.new()
	var builder := load("res://addons/wilds/preview/wilds_preview_builder.gd")
	var root_node: Node3D = builder.build(m, d, style)
	root.add_child(root_node)
	for _i in 5:
		await process_frame

	var terrain := root_node.get_node_or_null("Terrain") as Node3D
	print("[PREVIEW] terrain: %s" % (terrain.name if terrain else "MISSING"))
	var waters := 0
	var verts := 0
	var shaders := {}
	for c in terrain.get_children():
		if not (c is MeshInstance3D):
			continue
		if not String(c.name).begins_with("Water"):
			continue
		waters += 1
		var mi := c as MeshInstance3D
		var pm := mi.mesh as PlaneMesh
		verts += (pm.subdivide_width + 2) * (pm.subdivide_depth + 2)
		var mat := mi.material_override as ShaderMaterial
		var key := "null-material"
		if mat != null:
			key = "no-shader" if mat.shader == null else mat.shader.resource_path
			var dm: Variant = mat.get_shader_parameter("depth_map")
			var fm: Variant = mat.get_shader_parameter("flow_map")
			key += "  depth=%s flow=%s size=%s" % [str(dm != null), str(fm != null),
					str(pm.size)]
		shaders[key] = int(shaders.get(key, 0)) + 1
	print("[PREVIEW] %d water planes, %d verts total" % [waters, verts])
	for k in shaders:
		print("[PREVIEW]   %s  x%d" % [k, shaders[k]])
	quit(0)

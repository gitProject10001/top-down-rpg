extends SceneTree
## TEMPORARY smoke test for GladeRockMesh / GladeRockField. Delete once the suites exist.


func _initialize() -> void:
	for cfg in [
		{"n": "bare", "f": null, "sub": 0, "facets": 13},
		{"n": "displaced", "f": _field(0.18, 0.0), "sub": 1, "facets": 13},
		{"n": "strata", "f": _field(0.22, 0.85), "sub": 2, "facets": 11},
		{"n": "pebble", "f": _field(0.10, 0.0), "sub": 1, "facets": 22},
		{"n": "facet1.0", "f": _field(0.18, 0.0, 1.0), "sub": 2, "facets": 13},
		{"n": "facet0.0", "f": _field(0.18, 0.0, 0.0), "sub": 2, "facets": 13},
		{"n": "blocky", "f": _field(0.30, 0.55, 0.9), "sub": 2, "facets": 9},
	]:
		_look(cfg.n, cfg.f, cfg.facets, cfg.sub)

	print("--- identity: displace 0 must reproduce the bare solid exactly ---")
	GladeRockMesh.clear_cache()
	var a := GladeRockMesh.build(4, null, 13, Vector3(0.5, 0.38, 0.46), 0.26, 0.72, 1)
	GladeRockMesh.clear_cache()
	var b := GladeRockMesh.build(4, _field(0.0, 0.0), 13, Vector3(0.5, 0.38, 0.46), 0.26, 0.72, 1)
	print("  identical: %s" % [_verts(a) == _verts(b)])

	print("--- pure function: same args twice, cache cleared between ---")
	GladeRockMesh.clear_cache()
	var c := _verts(GladeRockMesh.build(7, _field(0.18, 0.0), 13))
	GladeRockMesh.clear_cache()
	var d := _verts(GladeRockMesh.build(7, _field(0.18, 0.0), 13))
	GladeRockMesh.clear_cache()
	var e := _verts(GladeRockMesh.build(8, _field(0.18, 0.0), 13))
	print("  seed 7 == seed 7: %s   seed 7 == seed 8: %s" % [c == d, c == e])
	quit(0)


func _field(disp: float, strata: float, facet := 0.5) -> GladeRockField:
	var f := GladeRockField.new(3)
	f.displace = disp
	f.strata = strata
	f.strata_step = 0.35
	f.facet = facet
	f._apply()
	return f


func _verts(m: ArrayMesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _look(name: String, f: GladeRockField, facets: int, sub: int) -> void:
	GladeRockMesh.clear_cache()
	var m := GladeRockMesh.build(3, f, facets, Vector3(0.5, 0.38, 0.46), 0.26, 0.72, sub)
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)

	# winding: the right-hand normal of each triangle must OPPOSE its stated normal
	var bad := 0
	var flat := 0
	var i := 0
	while i + 2 < v.size():
		var gn := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		if gn.dot(n[i]) > 1e-9:
			bad += 1
		if n[i].distance_to(n[i + 1]) > 1e-5 or n[i].distance_to(n[i + 2]) > 1e-5:
			flat += 1
		i += 3

	# manifold: every undirected edge used exactly twice
	var edges := {}
	i = 0
	while i + 2 < v.size():
		for e in [[i, i + 1], [i + 1, i + 2], [i + 2, i]]:
			var p := v[e[0]]
			var q := v[e[1]]
			var kp := "%d,%d,%d" % [roundi(p.x * 200000), roundi(p.y * 200000), roundi(p.z * 200000)]
			var kq := "%d,%d,%d" % [roundi(q.x * 200000), roundi(q.y * 200000), roundi(q.z * 200000)]
			var k: String = kp + "|" + kq if kp < kq else kq + "|" + kp
			edges[k] = int(edges.get(k, 0)) + 1
		i += 3
	var open := 0
	var hist := {}
	var examples: Array = []
	for k in edges:
		var cnt := int(edges[k])
		hist[cnt] = int(hist.get(cnt, 0)) + 1
		if cnt != 2:
			open += 1
			if examples.size() < 3:
				examples.append("%s x%d" % [k, cnt])

	# how close do two DISTINCT vertices get? if it is under the dedupe quantum, the dedupe is
	# splitting one corner into two and that alone would open every edge that meets there
	var uniqv := {}
	for p in v:
		uniqv["%d,%d,%d" % [roundi(p.x * 200000), roundi(p.y * 200000), roundi(p.z * 200000)]] = p
	var keys: Array = uniqv.keys()
	var closest := 999.0
	for i2 in keys.size():
		for j2 in range(i2 + 1, keys.size()):
			closest = minf(closest, (uniqv[keys[i2]] as Vector3).distance_to(uniqv[keys[j2]]))
	if open > 0:
		print("    edge histogram %s  closest-distinct-verts %.5f  e.g. %s"
				% [hist, closest, ", ".join(examples)])

	# distinct plane normals: how many big flat faces did we actually get?
	var faces := {}
	i = 0
	while i < n.size():
		faces["%d,%d,%d" % [roundi(n[i].x * 24), roundi(n[i].y * 24), roundi(n[i].z * 24)]] = true
		i += 3

	print("%-10s tris %4d  distinct-normals %3d  aabb %s  base_y %+.4f  bad-winding %d  non-flat %d  open-edges %d"
			% [name, v.size() / 3, faces.size(),
					"%.3f x %.3f x %.3f" % [box.size.x, box.size.y, box.size.z],
					box.position.y, bad, flat, open])

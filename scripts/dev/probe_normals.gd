extends SceneTree
## WHICH MESHES ARE WOUND AGAINST THEIR OWN NORMALS.
##
##   Godot_console.exe --path . --resolution 640x360 --script res://scripts/dev/probe_normals.gd \
##       [-- --scene=res://scenes/main.tscn]
##
## A face has two independent statements about which way it points: the ORDER its vertices are
## listed in, and the NORMAL vector stored on them. When they disagree the face is lit from behind
## and culled from in front, which on a closed object reads as a hole and on an open one as a patch
## of shadow that does not move with the sun.
##
## THE SIGN IS CALIBRATED, NOT ASSUMED. Godot's front face is clockwise about the outward normal, so
## the right-hand normal of the emitted vertex order OPPOSES the direction the surface faces — the
## rule scripts/gladekit_tests/probe_cliff.gd:174 states and scripts/terrain_field.gd repeats. Get
## that backwards and this probe reports every correct mesh as broken and every broken one as fine,
## which is worse than not running it. So it measures a Godot-built BoxMesh first and takes the
## convention from that, and refuses to report anything if the calibration itself is ambiguous.

var _scene := "res://scenes/main.tscn"
## Below this fraction of disagreeing triangles a mesh is treated as clean: a handful of degenerate
## slivers in an imported mesh is normal and says nothing about the object's winding.
const NOISE := 0.02


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_scene = a.substr(8)
	_run()


func _run() -> void:
	var sign_ := _calibrate()
	if sign_ == 0:
		print("[NORMALS] CALIBRATION FAILED — refusing to guess the winding convention")
		quit(1)
		return
	print("[NORMALS] convention: a correct face's winding normal has dot %s 0 with its shading normal"
			% ["<" if sign_ < 0 else ">"])

	var root := (load(_scene) as PackedScene).instantiate()
	get_root().add_child(root)
	for _i in 30:
		await process_frame

	var vol_sign := _calibrate_volume()
	print("[NORMALS] convention: a correct CLOSED mesh has signed volume %s 0"
			% ["<" if vol_sign < 0 else ">"])

	var rows: Array = []
	_walk(root, root, sign_, rows)
	rows.sort_custom(func(a, b): return a["bad_frac"] > b["bad_frac"])

	# THE OTHER WAY A MESH FACES THE WRONG WAY, and the one the winding-versus-normals test cannot
	# see: flip BOTH and they still agree with each other while the surface faces inward. That is
	# what a negative scale bakes into an export. Signed volume asks the independent question — does
	# this surface enclose its own inside — and only means anything on a mesh that is closed, so it
	# is reported against how much of the AABB the volume accounts for.
	var inside_out: Array = []
	for r: Dictionary in rows:
		# A volume of essentially zero has no sign worth trusting — a symmetric little prop can land
		# either side of nothing — so it is not evidence of anything.
		if r["closed"] > 0.25 and absf(r["volume"]) > 0.01 				and signf(r["volume"]) != float(vol_sign):
			inside_out.append(r)
	if inside_out.is_empty():
		print("[NORMALS] no closed mesh encloses its volume the wrong way round")
	else:
		print("")
		print("%-44s %10s  %s" % ["object / surface", "closedness", "INSIDE OUT"])
		for r: Dictionary in inside_out:
			print("%-44s %9.2f   volume %.2f" % [r["path"], r["closed"], r["volume"]])

	var flipped := 0
	var tris_flipped := 0
	print("")
	print("%-44s %8s %7s  %s" % ["object / surface", "tris", "flipped", "verdict"])
	for r: Dictionary in rows:
		if r["bad_frac"] <= NOISE:
			continue
		flipped += 1
		tris_flipped += r["bad"]
		print("%-44s %8d %6.1f%%  %s" % [r["path"], r["tris"], r["bad_frac"] * 100.0,
				"INVERTED" if r["bad_frac"] > 0.9 else "MIXED"])
	var total_tris := 0
	for r: Dictionary in rows:
		total_tris += r["tris"]
	print("")
	print("[NORMALS] %d of %d surfaces wound against their normals (%d of %d triangles)"
			% [flipped, rows.size(), tris_flipped, total_tris])
	quit(0)


## Take the convention from a mesh Godot built itself, whose winding is correct by construction.
## Returns -1 or +1 for the sign a CORRECT face's dot product should have, or 0 if the primitive
## did not give a clear answer.
func _calibrate() -> int:
	var box := BoxMesh.new()
	var r := _measure(box.get_mesh_arrays() if box.has_method("get_mesh_arrays")
			else box.surface_get_arrays(0))
	if r["n"] == 0:
		return 0
	var frac_neg: float = float(r["neg"]) / float(r["n"])
	if frac_neg > 0.95:
		return -1
	if frac_neg < 0.05:
		return 1
	return 0


## The sign a correctly wound CLOSED mesh's signed volume carries, taken from a Godot primitive
## rather than from a memory of which way the right-hand rule falls out here.
func _calibrate_volume() -> int:
	var box := BoxMesh.new()
	var r := _measure(box.surface_get_arrays(0))
	return int(signf(r["volume"])) if absf(r["volume"]) > 0.0001 else 1


## Count, over one surface's triangles, how many have a NEGATIVE dot between the winding normal and
## the averaged shading normal. Degenerate triangles are skipped rather than counted either way.
## Also accumulates the signed volume, and how much of the bounding box that volume accounts for —
## a flat plane or an open shell scores near zero and is not a candidate for the volume test.
func _measure(arrays: Array) -> Dictionary:
	var out := {"n": 0, "neg": 0, "volume": 0.0, "closed": 0.0}
	if arrays.size() <= Mesh.ARRAY_NORMAL:
		return out
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms = arrays[Mesh.ARRAY_NORMAL]
	if norms == null or verts.is_empty():
		return out
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
			else PackedInt32Array()
	var count := idx.size() if idx.size() > 0 else verts.size()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var vol := 0.0
	var t := 0
	while t + 2 < count:
		var i0 := idx[t] if idx.size() > 0 else t
		var i1 := idx[t + 1] if idx.size() > 0 else t + 1
		var i2 := idx[t + 2] if idx.size() > 0 else t + 2
		var gn := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		vol += verts[i0].dot(verts[i1].cross(verts[i2])) / 6.0
		if gn.length_squared() > 0.0000001:
			var sn: Vector3 = (norms[i0] + norms[i1] + norms[i2])
			if sn.length_squared() > 0.0000001:
				out["n"] += 1
				if gn.dot(sn) < 0.0:
					out["neg"] += 1
		t += 3
	out["volume"] = vol
	# CLOSEDNESS, and the trap in measuring it. Dividing the volume by the bounding box works only
	# while the box HAS a volume: a flower or a leaf card is flat, its thinnest axis is ~0, and the
	# ratio explodes to 1.0 — which read as "perfectly closed" and put every flat object in the
	# scene on the inside-out list. A sheet cannot be inside out; it has no inside.
	var box := hi - lo
	var thin: float = minf(box.x, minf(box.y, box.z))
	var thick: float = maxf(box.x, maxf(box.y, box.z))
	if thick <= 0.000001 or thin / thick < 0.02:
		out["closed"] = 0.0
	else:
		out["closed"] = clampf(absf(vol) / (box.x * box.y * box.z), 0.0, 1.0)
	return out


func _walk(n: Node, root: Node, sign_: int, rows: Array) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			# PrimitiveMesh has no surface_get_primitive_type — only ArrayMesh does — and its
			# surfaces are triangles by construction, so the question is only worth asking of one.
			if mi.mesh is ArrayMesh 					and mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var r := _measure(mi.mesh.surface_get_arrays(s))
			if r["n"] == 0:
				continue
			# A face is CORRECT when its dot matches the calibrated sign; count the rest.
			var bad: int = (r["n"] - r["neg"]) if sign_ < 0 else r["neg"]
			rows.append({
				"path": (str(root.get_path_to(mi)) + (":%d" % s)).substr(0, 44),
				"tris": r["n"], "bad": bad, "bad_frac": float(bad) / float(r["n"]),
				"volume": r["volume"], "closed": r["closed"],
			})
	for c in n.get_children(true):
		_walk(c, root, sign_, rows)

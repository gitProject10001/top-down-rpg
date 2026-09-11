extends SceneTree
## Pull the ArrayMesh out of an imported .glb and save it as a .res.
##
## WHY THIS EXISTS. `GladeStyle.brick_meshes` is `Array[Mesh]` — it wants a MESH, and a .glb imports
## as a PackedScene. The five `glade_brick_*.res` files in assets/models were evidently extracted by
## hand in the editor, and there was no script for it, so the next person modelling a brick or a
## thatch strand had to rediscover the dance. This is that dance, once.
##
## The prop sockets (`window_frame`, `door_leaf`, `chimney_pot` ...) are `PackedScene` and take the
## .glb directly — only the tile/brick sockets need this.
##
## TWO CONVENTIONS, AND THEY ARE NOT THE SAME ONE. This is what `--spin` is for, and skipping it
## cost a whole render:
##
##   a WALL brick  X = width along the course, Y = height,        Z = through the wall
##   a ROOF tile   X = width along the course, Y = **the slope's normal**, Z = **up the slope**
##
## because `_tile_slope` builds each tile's basis as `_rh(row_dir, n, up_dir)`. A thatch strand
## modelled the wall way — reeds running up Y, which is how every prop in this kit is authored —
## therefore comes out of the roof standing straight up off the slope. It renders as a scrubbing
## brush, and no amount of tuning the tiler fixes it, because the tiler is right.
##
##   --spin=x90   rotate +90 deg about X on the way in: the model's Y becomes the tile's Z
##
##   Godot_console.exe --headless --path . --script res://scripts/dev/extract_mesh.gd -- \
##       --from=res://assets/models/glade_thatch.glb --to=res://assets/models/glade_thatch.res \
##       --spin=x90


func _initialize() -> void:
	var from := ""
	var to := ""
	var spin := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="):
			from = a.substr(7)
		elif a.begins_with("--to="):
			to = a.substr(5)
		elif a.begins_with("--spin="):
			spin = a.substr(7)
	if from.is_empty() or to.is_empty():
		print("[MESH] --from=res://...glb --to=res://...res")
		quit(1)
		return

	var packed := load(from) as PackedScene
	if packed == null:
		print("[MESH] cannot load %s — has it been imported? try --headless --import first" % from)
		quit(1)
		return
	var root_node := packed.instantiate()
	var mesh := _first_mesh(root_node)
	if mesh == null:
		print("[MESH] no MeshInstance3D under %s" % from)
		quit(1)
		return
	if not spin.is_empty():
		mesh = _spun(mesh, spin)
		if mesh == null:
			print("[MESH] --spin= takes x90 / x-90 / y90 / y-90 / z90 / z-90")
			quit(1)
			return
	# Saved as a plain resource: no scene, no material, no transform — a Mesh and nothing else, which
	# is what the socket takes and what keeps the style in charge of the material.
	var err := ResourceSaver.save(mesh, to)
	print("[MESH] %s %s -> %s (%d surfaces, %d verts)"
			% ["ok" if err == OK else "FAILED", from, to, mesh.get_surface_count(),
					mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()])
	quit(0 if err == OK else 1)


## The same mesh in a different axis convention. Baked into the .res rather than applied at
## placement time, because the socket is an `Array[Mesh]` and a Mesh cannot carry a transform — and
## because a knob on the style to correct a mis-authored asset would be a knob everybody has to
## think about forever.
func _spun(m: ArrayMesh, spin: String) -> ArrayMesh:
	var axes := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}
	if spin.length() < 2 or not axes.has(spin[0]):
		return null
	var deg := spin.substr(1).to_float()
	if is_zero_approx(deg):
		return null
	var b := Basis(axes[spin[0]], deg_to_rad(deg))
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = b * verts[i]
		arr[Mesh.ARRAY_VERTEX] = verts
		if arr[Mesh.ARRAY_NORMAL] != null:
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in nrm.size():
				nrm[i] = b * nrm[i]
			arr[Mesh.ARRAY_NORMAL] = nrm
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


func _first_mesh(n: Node) -> ArrayMesh:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh:
		return (n as MeshInstance3D).mesh as ArrayMesh
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null

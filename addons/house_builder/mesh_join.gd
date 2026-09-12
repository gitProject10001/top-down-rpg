@tool
extends RefCounted
## Subtract convex regions from triangles, interpolating all material attributes.
## Planes describe the removed region with signed distance <= 0.
static func append(target: ArrayMesh, source: Mesh, transform: Transform3D, cutters: Array) -> void:
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else positions.size()
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted := 0
		for triangle in range(0,count,3):
			var polygon: Array=[]
			for corner in 3:
				var i := indices[triangle+corner] if not indices.is_empty() else triangle+corner
				polygon.append([transform*positions[i],transform.basis*arrays[Mesh.ARRAY_NORMAL][i],arrays[Mesh.ARRAY_TEX_UV][i] if arrays[Mesh.ARRAY_TEX_UV]!=null else Vector2.ZERO,arrays[Mesh.ARRAY_TEX_UV2][i] if arrays[Mesh.ARRAY_TEX_UV2]!=null else Vector2.ZERO,arrays[Mesh.ARRAY_COLOR][i] if arrays[Mesh.ARRAY_COLOR]!=null else Color.WHITE])
			var pieces: Array=[polygon]
			for planes in cutters:
				var next: Array=[]
				for piece in pieces: next.append_array(subtract(piece,planes))
				pieces=next
			for piece in pieces:
				for j in range(1,piece.size()-1):
					if (piece[j][0]-piece[0][0]).cross(piece[j+1][0]-piece[0][0]).length_squared()<0.0000000001: continue
					for vertex in [piece[0],piece[j],piece[j+1]]:
						tool.set_normal(vertex[1].normalized())
						tool.set_uv(vertex[2]); tool.set_uv2(vertex[3]); tool.set_color(vertex[4])
						tool.add_vertex(vertex[0]); emitted+=1
		if emitted==0: continue
		tool.generate_tangents()
		tool.index()
		tool.commit(target)
		target.surface_set_material(target.get_surface_count()-1,source.surface_get_material(surface))

static func subtract(polygon: Array, planes: Array) -> Array:
	# Most triangles lie completely outside the other volume.
	for plane in planes:
		var outside := true
		for vertex in polygon:
			if plane.distance_to(vertex[0])<=0.0: outside=false; break
		if outside: return [polygon]
	var kept: Array=[]
	var inside := polygon
	for plane in planes:
		var front: Array=[]
		var back: Array=[]
		for i in inside.size():
			var a: Array=inside[i]
			var b: Array=inside[(i+1)%inside.size()]
			var da: float=plane.distance_to(a[0])
			var db: float=plane.distance_to(b[0])
			if da>0.0: front.append(a)
			else: back.append(a)
			if (da>0.0)!=(db>0.0):
				var t := da/(da-db)
				var v: Array=[]
				for k in 5: v.append(a[k].lerp(b[k],t))
				front.append(v); back.append(v)
		if front.size()>=3: kept.append(front)
		inside=back
		if inside.size()<3: break
	return kept

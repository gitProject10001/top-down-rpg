@tool
extends RefCounted
## Convex subtraction, preserving indexed buffers outside the affected regions.
static var counters := {"groups":0,"triangles_tested":0,"triangles_clipped":0,"triangles_kept":0,"tangent_context_triangles":0}
static var _groups: Dictionary={}
const GROUP_TRIANGLES := 64

static func _needs_tangents(material: Material) -> bool:
	# These project shaders use position/normal/colour only. Unknown materials
	# retain the conservative path, including shader includes and custom code.
	if material is ShaderMaterial and material.shader and material.shader.resource_path in ["res://shaders/pixelart/solid_masonry.gdshader","res://shaders/pixelart/painted_architecture.gdshader","res://addons/house_builder/plaster.gdshader"]:
		var code: String=material.shader.code
		return "NORMAL_MAP" in code or "TANGENT" in code or "BINORMAL" in code or "#include" in code
	return true

static func _relation(center: Vector3, extent: Vector3, planes: Array) -> int:
	var inside := true
	for plane: Plane in planes:
		var distance := plane.distance_to(center)
		var radius := plane.normal.abs().dot(extent)
		if distance-radius>0.000001: return 0 # safely outside
		if distance+radius>0.0: inside=false
	return 2 if inside else 1

static func _surface_groups(source: Mesh, surface: int, vertices: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var authored_groups: Dictionary=source.get_meta("clip_groups",{})
	if authored_groups.has(surface): return authored_groups[surface]
	var id := source.get_instance_id()
	if _groups.has(id) and _groups[id].ref.get_ref()==source and _groups[id].surfaces.has(surface):
		return _groups[id].surfaces[surface]
	var result: Array=[]
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for start in range(0,count,GROUP_TRIANGLES*3):
		var end := mini(start+GROUP_TRIANGLES*3,count)
		var low := Vector3(INF,INF,INF)
		var high := -low
		for i in range(start,end):
			var p := vertices[indices[i] if not indices.is_empty() else i]
			low=low.min(p); high=high.max(p)
		result.append([start,end,(low+high)*.5,(high-low)*.5])
	if not _groups.has(id) or _groups[id].ref.get_ref()!=source:
		if _groups.size()>256: _groups.clear()
		_groups[id]={"ref":weakref(source),"surfaces":{}}
	_groups[id].surfaces[surface]=result
	return result

static func append(target: ArrayMesh, source: Mesh, transform: Transform3D, cutters: Array, scheduler: Node=null) -> void:
	for surface in source.get_surface_count():
		var requires_tangents := _needs_tangents(source.surface_get_material(surface))
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else positions.size()
		# Work in the source frame. This avoids transforming every triangle for
		# every cutter; the unchanged buffer is transformed once at publication.
		var local_cuts: Array=[]
		var inverse := transform.affine_inverse()
		for cutter in cutters:
			var planes: Array=[]
			for plane: Plane in cutter: planes.append(inverse*plane)
			local_cuts.append(planes)
		var independent_groups: bool=source.get_meta("clip_groups",{}).has(surface)
		var kept_groups: Array=[]
		var clipped_groups: Array=[]
		var kept := PackedInt32Array()
		var tool: SurfaceTool
		var emitted := 0
		if local_cuts.is_empty():
			if indices.is_empty():
				indices.resize(positions.size())
				for i in indices.size(): indices[i]=i
			kept=indices
			if independent_groups: kept_groups=source.get_meta("clip_groups")[surface].duplicate(true)
		else:
			for group in _surface_groups(source,surface,positions,indices):
				counters.groups+=1
				if scheduler!=null and not await scheduler.yield_build(): return
				var candidates: Array=[]
				var removed := false
				for planes in local_cuts:
					var relation := _relation(group[2],group[3],planes)
					if relation==2: removed=true; break
					if relation==1: candidates.append(planes)
				if removed: continue
				var kept_start := kept.size()
				var clipped_start := emitted
				if candidates.is_empty():
					if not indices.is_empty(): kept.append_array(indices.slice(group[0],group[1]))
					else:
						for i in range(group[0],group[1]): kept.append(i)
					if independent_groups: kept_groups.append([kept_start,kept.size(),group[2],group[3]])
					counters.triangles_kept+=(group[1]-group[0])/3
					continue
				for triangle in range(group[0],group[1],3):
					counters.triangles_tested+=1
					var ia := indices[triangle] if not indices.is_empty() else triangle
					var ib := indices[triangle+1] if not indices.is_empty() else triangle+1
					var ic := indices[triangle+2] if not indices.is_empty() else triangle+2
					var a := positions[ia]; var b := positions[ib]; var c := positions[ic]
					var low := a.min(b).min(c); var high := a.max(b).max(c)
					var relevant: Array=[]
					removed=false
					for planes in candidates:
						var relation := _relation((low+high)*.5,(high-low)*.5,planes)
						if relation==2: removed=true; break
						if relation==1: relevant.append(planes)
					if removed: continue
					if relevant.is_empty() and not independent_groups:
						kept.append(ia); kept.append(ib); kept.append(ic)
						counters.triangles_kept+=1
						continue
					if relevant.is_empty(): counters.tangent_context_triangles+=1
					else: counters.triangles_clipped+=1
					var polygon: Array=[]
					for i in [ia,ib,ic]:
						polygon.append([transform*positions[i],transform.basis*arrays[Mesh.ARRAY_NORMAL][i],arrays[Mesh.ARRAY_TEX_UV][i] if arrays[Mesh.ARRAY_TEX_UV]!=null else Vector2.ZERO,arrays[Mesh.ARRAY_TEX_UV2][i] if arrays[Mesh.ARRAY_TEX_UV2]!=null else Vector2.ZERO,arrays[Mesh.ARRAY_COLOR][i] if arrays[Mesh.ARRAY_COLOR]!=null else Color.WHITE])
					var pieces: Array=[polygon]
					# Keep the legacy arithmetic/order for the small boundary set.
					for local_planes in relevant:
						var index := local_cuts.find(local_planes)
						var next: Array=[]
						for piece in pieces: next.append_array(subtract(piece,cutters[index]))
						pieces=next
					for piece in pieces:
						for j in range(1,piece.size()-1):
							if (piece[j][0]-piece[0][0]).cross(piece[j+1][0]-piece[0][0]).length_squared()<0.0000000001: continue
							if tool==null:
								tool=SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
							for vertex in [piece[0],piece[j],piece[j+1]]:
								tool.set_normal(vertex[1].normalized())
								tool.set_uv(vertex[2]); tool.set_uv2(vertex[3]); tool.set_color(vertex[4])
								tool.add_vertex(vertex[0]); emitted+=1
				if independent_groups and emitted>clipped_start: clipped_groups.append([clipped_start,emitted,group[2],group[3]])
		if kept.is_empty() and emitted==0: continue
		if requires_tangents and transform!=Transform3D.IDENTITY and arrays[Mesh.ARRAY_TEX_UV]!=null:
			# Preserve the pre-encoding normals for MikkTSpace. Repacking them
			# before tangent generation changes handedness on zero-area UV faces.
			if tool==null:
				tool=SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in kept:
				tool.set_normal((transform.basis*arrays[Mesh.ARRAY_NORMAL][i]).normalized())
				tool.set_uv(arrays[Mesh.ARRAY_TEX_UV][i])
				tool.set_uv2(arrays[Mesh.ARRAY_TEX_UV2][i] if arrays[Mesh.ARRAY_TEX_UV2]!=null else Vector2.ZERO)
				tool.set_color(arrays[Mesh.ARRAY_COLOR][i] if arrays[Mesh.ARRAY_COLOR]!=null else Color.WHITE)
				tool.add_vertex(transform*positions[i])
			tool.generate_tangents(); tool.index(); tool.commit(target)
			target.surface_set_material(target.get_surface_count()-1,source.surface_get_material(surface))
			continue
		if scheduler!=null and not await scheduler.yield_build(): return
		var kept_count := kept.size()
		var base: Array=arrays.duplicate()
		base[Mesh.ARRAY_INDEX]=kept
		if transform!=Transform3D.IDENTITY:
			base[Mesh.ARRAY_VERTEX]=transform*positions
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL].duplicate()
			for i in normals.size(): normals[i]=(transform.basis*normals[i]).normalized()
			base[Mesh.ARRAY_NORMAL]=normals

		if emitted>0:
			if requires_tangents and (independent_groups or arrays[Mesh.ARRAY_TEX_UV]==null): tool.generate_tangents()
			tool.index()
			var clipped := tool.commit_to_arrays()
			if kept.is_empty(): base=clipped
			else: _merge_arrays(base,clipped)
		if requires_tangents and not independent_groups and arrays[Mesh.ARRAY_TEX_UV]!=null and (transform!=Transform3D.IDENTITY or not cutters.is_empty()):
			var normalized: PackedVector3Array=base[Mesh.ARRAY_NORMAL].duplicate()
			for i in normalized.size(): normalized[i]=normalized[i].normalized()
			base[Mesh.ARRAY_NORMAL]=normalized
			# MikkTSpace defines special tangents for degenerate UV triangles.
			# Transforming stored tangents is not equivalent in that case (roof
			# bevels contain these). Meshes without independent tangent groups use
			# the conservative full-surface fallback.
			var transformed := ArrayMesh.new()
			transformed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,base)
			var tangent_tool := SurfaceTool.new()
			tangent_tool.create_from(transformed,0)
			tangent_tool.generate_tangents()
			base=tangent_tool.commit_to_arrays()
		if independent_groups and transform==Transform3D.IDENTITY:
			var result_groups: Array=kept_groups
			for group in clipped_groups: result_groups.append([group[0]+kept_count,group[1]+kept_count,group[2],group[3]])
			var metadata: Dictionary=target.get_meta("clip_groups",{})
			metadata[target.get_surface_count()]=result_groups
			target.set_meta("clip_groups",metadata)
		target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,base)
		target.surface_set_material(target.get_surface_count()-1,source.surface_get_material(surface))

static func _merge_arrays(base: Array, extra: Array) -> void:
	var offset: int=base[Mesh.ARRAY_VERTEX].size()
	var added: int=extra[Mesh.ARRAY_VERTEX].size()
	for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR,Mesh.ARRAY_TANGENT]:
		if base[slot]==null and extra[slot]==null: continue
		if base[slot]==null:
			base[slot]=extra[slot].slice(0,0)
			base[slot].resize(offset*4 if slot==Mesh.ARRAY_TANGENT else offset)
			if slot==Mesh.ARRAY_COLOR: base[slot].fill(Color.WHITE)
		if extra[slot]==null:
			var blank=base[slot].slice(0,0)
			blank.resize(added*4 if slot==Mesh.ARRAY_TANGENT else added)
			if slot==Mesh.ARRAY_COLOR: blank.fill(Color.WHITE)
			base[slot].append_array(blank)
		else: base[slot].append_array(extra[slot])
	var indices: PackedInt32Array=extra[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(added)
		for i in added: indices[i]=i
	for i in indices.size(): indices[i]+=offset
	base[Mesh.ARRAY_INDEX].append_array(indices)

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

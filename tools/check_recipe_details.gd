extends SceneTree
const Detail = preload("res://addons/house_builder/recipe_detail.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("RECIPE_DETAIL_CHECK: " + message)

func fingerprint(mesh: ArrayMesh) -> int:
	var arrays: Array = []
	for surface in mesh.get_surface_count(): arrays.append(mesh.surface_get_arrays(surface))
	return hash(var_to_bytes(arrays))

func check_mesh(detail: Node3D) -> void:
	var visual: MeshInstance3D = detail.get_node("_GeneratedRecipeDetail/DetailMesh")
	var mesh: ArrayMesh = visual.mesh
	check(mesh.get_surface_count() > 0 and mesh.get_surface_count() <= 7, detail.kind+": batched material budget")
	var triangle_budget := 5500 if detail.kind == "gothic_bell_tower" else 4500
	check(detail.triangle_count > 50 and detail.triangle_count < triangle_budget, detail.kind+": usable low-cost volumetric mesh")
	var bounds := mesh.get_aabb()
	var extent: Vector3 = detail.dimensions
	check(bounds.size.x > extent.x*.50 and bounds.size.y > extent.y*.45 and bounds.size.z > extent.z*.25,
		detail.kind+": mesh must have actual volume in all axes")
	check(bounds.position.x >= -extent.x*.55 and bounds.end.x <= extent.x*.55 and bounds.position.z >= -extent.z*.55 and bounds.end.z <= extent.z*.55,
		detail.kind+": horizontal envelope")
	check(bounds.position.y >= -extent.y*.015 and bounds.end.y <= extent.y*1.035, detail.kind+": base and top envelope")
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		check(positions.size() == normals.size(), detail.kind+": authored face normals")
		for normal in normals:
			if not normal.is_finite() or absf(normal.length()-1.0) > .001:
				check(false,detail.kind+": finite unit normals"); break
		var mat: ShaderMaterial = mesh.surface_get_material(surface)
		check(mat.shader.resource_path.ends_with("recipe_detail.gdshader"), detail.kind+": matte painted material")
	print("DETAIL_GEOMETRY ",detail.kind," triangles=",detail.triangle_count," surfaces=",mesh.get_surface_count()," bounds=",bounds)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var details: Array[Node3D] = []
	for i in Detail.KINDS.size():
		var kind: String = Detail.KINDS[i]
		var detail: Node3D = Detail.new()
		detail.name = kind
		detail.kind = kind
		detail.dimensions = Detail.default_dimensions(kind)
		detail.detail_seed = 153+i
		detail.detail_id = "test_"+kind
		detail.position.x = i*20.0
		world.add_child(detail)
		details.append(detail)
		check_mesh(detail)
		var body := detail.get_node_or_null("_GeneratedRecipeDetail/DetailCollision")
		if kind in Detail.ROOF_KINDS or kind == "hanging_sign":
			check(body == null,kind+": no invisible blocker on roof/wall ornament")
		else:
			check(body is StaticBody3D and body.get_child_count() in range(1,7),kind+": fitted ground blocker")
		var visual: MeshInstance3D = detail.get_node("_GeneratedRecipeDetail/DetailMesh")
		var signature := fingerprint(visual.mesh)
		var edited_transform := detail.transform
		var manual := Node3D.new()
		manual.name = "ManualAdjustment"
		detail.add_child(manual)
		detail.locked = true
		detail.rebuild()
		check(signature == fingerprint(detail.get_node("_GeneratedRecipeDetail/DetailMesh").mesh),kind+": deterministic mesh")
		check(detail.transform == edited_transform and is_instance_valid(manual) and manual.get_parent() == detail,kind+": rebuild preserves authored transform/manual child")
		detail.set_cutaway(true)
		check(detail.get_node("_GeneratedRecipeDetail/DetailMesh").visible == (kind not in Detail.ROOF_KINDS),kind+": cutaway keeps visible ground footprints")
		if kind in Detail.MASONRY_CUTAWAY_KINDS:
			var cut_visual: MeshInstance3D = detail.get_node("_GeneratedRecipeDetail/DetailMesh")
			check(cut_visual.mesh.surface_get_material(0).get_shader_parameter("cutaway_enabled") == true,kind+": tall geometry clipped in material")
			var caps: Node3D = detail.get_node("_GeneratedRecipeDetail/CutawayCaps")
			check(caps.visible and caps.get_child_count() > 0,kind+": blocked ground footprint remains visibly capped")
			for cap in caps.get_children(): check(absf(cap.position.y+.0175-Detail.CUTAWAY_HEIGHT)<.001,kind+": cap exactly at cut plane")
		detail.set_cutaway(false)
		detail.detail_seed += 1
		detail.rebuild()
		check(signature != fingerprint(detail.get_node("_GeneratedRecipeDetail/DetailMesh").mesh),kind+": independent seeded variation")
		# Packed authoring contains parameters, never the disposable generated mesh.
		var packed := PackedScene.new()
		check(packed.pack(detail) == OK,kind+": packed authoring")
		var restored: Node3D = packed.instantiate()
		check(restored.get_node_or_null("_GeneratedRecipeDetail") == null,kind+": cache not serialized")
		check(restored.kind == kind and restored.detail_id == detail.detail_id and restored.locked and restored.detail_seed == detail.detail_seed,kind+": authoring survives reopen")
		world.add_child(restored)
		check(fingerprint(restored.get_node("_GeneratedRecipeDetail/DetailMesh").mesh) == fingerprint(detail.get_node("_GeneratedRecipeDetail/DetailMesh").mesh),kind+": editor/runtime same generation")
		restored.queue_free()
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	for detail in details:
		if detail.kind in Detail.ROOF_KINDS or detail.kind == "hanging_sign": continue
		var sample := Vector3(-detail.dimensions.x*.25,0,0)
		if detail.kind == "gothic_facade": sample.z = -detail.dimensions.z*.25
		if detail.kind == "market_awning": sample = Vector3(-detail.dimensions.x*.455,0,detail.dimensions.z*.43)
		var ray := PhysicsRayQueryParameters3D.create(detail.global_position+sample+Vector3.UP*(detail.dimensions.y+1),detail.global_position+sample+Vector3.DOWN*.2,1)
		var result := space.intersect_ray(ray)
		check(not result.is_empty(),detail.kind+": real physical blocker under geometry")
		if not result.is_empty(): check(result.collider.get_parent().get_parent() == detail,detail.kind+": collision belongs to editable component")
		if detail.kind in ["gothic_facade", "market_awning"]:
			var capsule := CapsuleShape3D.new()
			capsule.radius = .28
			capsule.height = 1.8
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis.IDENTITY,detail.global_position+Vector3(0,1.05,2.5))
			query.motion = Vector3(0,0,-5)
			query.collision_mask = 1
			var motion := space.cast_motion(query)
			check(motion[0] > .999,detail.kind+": real capsule clears centre doorway")
		if detail.kind == "gothic_facade":
			check(not mesh_hits(detail,Vector3(0,1.1,2),Vector3.FORWARD),"gothic_facade: entrance is genuinely absent from mesh")
		if detail.kind == "gothic_bell_tower":
			check(not mesh_hits(detail,Vector3(detail.dimensions.x*.18,detail.dimensions.y*.675,3),Vector3.FORWARD),"gothic_bell_tower: belfry openings are genuinely absent from mesh")
	print("RECIPE_DETAILS_RESULT failures=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func mesh_hits(detail: Node3D, origin: Vector3, direction: Vector3) -> bool:
	var mesh: ArrayMesh = detail.get_node("_GeneratedRecipeDetail/DetailMesh").mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			if Geometry3D.ray_intersects_triangle(origin,direction,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]) != null: return true
	return false

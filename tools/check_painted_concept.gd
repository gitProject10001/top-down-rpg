extends SceneTree
## Real integrated-scene renders. Run after importing assets, without --headless:
## godot --path . --script res://tools/check_painted_concept.gd
## Writes only captures/ and user://. The source scene and art profile are untouched.
const Edit = preload("res://scripts/art/art_surface_edit.gd")
var scene: Node3D
var view: SubViewport
var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("PAINTED_CONCEPT: " + message)

func settle(frames: int = 30) -> void:
	for i in frames:
		await physics_frame

func capture(filename: String) -> void:
	await settle(35)
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image().save_png("res://captures/" + filename + ".png")
	check(result == OK, "Failed to save " + filename)
	print("PAINTED_CAPTURE ", filename)

func move_focus(position: Vector3, camera_size: float = 17.5) -> void:
	scene.player.position = position
	scene.player.velocity = Vector3.ZERO
	scene.camera.ortho_size = camera_size
	await settle(65)

func mesh_state(art: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for change in art.changes:
		if change.get("property", "") == "mesh":
			result.append({"node": change.object, "original": change.before,
				"painted": change.after, "transform": change.object.transform})
	return result

func check_grass(grass: Node) -> void:
	check(grass.blades.size() == 12, "Expected four grass families with three mesh variants each")
	var variants: Array[int] = []
	variants.resize(grass.blades.size())
	var count := 0
	for chunk in grass.chunks.values():
		for child in chunk.get_children():
			if not child is MultiMeshInstance3D or child.multimesh == null:
				continue
			if not child.multimesh.mesh is ArrayMesh:
				continue # Pebble batches use SphereMesh, outside the typed grass array.
			var variant: int = grass.blades.find(child.multimesh.mesh)
			if variant >= 0:
				variants[variant] += child.multimesh.instance_count
				count += child.multimesh.instance_count
	for family in 4:
		var family_count := 0
		for variation in 3:
			var index := family * 3 + variation
			if index < variants.size():
				family_count += variants[index]
		check(family_count > 0, "Grass family %d is missing from the river test" % family)
	check(count > 1000, "Dense river grass is missing")
	print("PAINTED_GRASS instances=", count, " variants=", variants)

func sample_percentile(samples: Array[float], fraction: float) -> float:
	var ordered := samples.duplicate()
	ordered.sort()
	return ordered[clampi(ceili((ordered.size() - 1) * fraction), 0, ordered.size() - 1)]

func measure_gameplay_view() -> void:
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	await settle(40)
	var cpu_render: Array[float] = []
	var gpu_render: Array[float] = []
	var frame_elapsed: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in 120:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_elapsed.append(float(now - previous) / 1000.0)
		previous = now
		cpu_render.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		gpu_render.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
	var metrics := {
		"sample_frames": 120,
		"warmup_physics_frames": 40,
		"viewport_width": view.size.x,
		"viewport_height": view.size.y,
		"cpu_render_median_ms": sample_percentile(cpu_render, .5),
		"cpu_render_p95_ms": sample_percentile(cpu_render, .95),
		"gpu_render_median_ms": sample_percentile(gpu_render, .5),
		"gpu_render_p95_ms": sample_percentile(gpu_render, .95),
		"frame_elapsed_median_ms": sample_percentile(frame_elapsed, .5),
		"frame_elapsed_p95_ms": sample_percentile(frame_elapsed, .95),
		"notes": "Integrated river, actual gameplay SubViewport; render CPU excludes other gameplay work; elapsed frames include waiting/vsync. One local run, no cross-machine guarantee."
	}
	var file := FileAccess.open("res://captures/painted_concept_metrics.json", FileAccess.WRITE)
	check(file != null, "Cannot write performance report")
	if file != null:
		file.store_string(JSON.stringify(metrics, "\t"))
	print("PAINTED_PERFORMANCE ", JSON.stringify(metrics))

func check_local_regeneration() -> void:
	var controller: Node
	for node in scene.find_children("*", "Node", true, false):
		var script: Script = node.get_script()
		if script != null and script.resource_path.ends_with("art_study_layers.gd"):
			controller = node
			break
	check(controller != null, "Editable art controller is missing from the integrated scene")
	if controller == null:
		return
	var profile: Resource = controller.profile
	check(profile == scene.art_direction.profile, "Editor controller and runtime use different art data")
	var kept := Edit.new()
	kept.surface_path = NodePath("TerrenoComposto/Superficie")
	# Far outside the sample so validation edits do not alter the delivered shot.
	kept.local_position = Vector3(200, 0, 200)
	kept.layer = Edit.Layer.GRASS_DENSITY
	kept.intensity = -.25
	check(profile.add_edit(kept), "Cannot append authored art edit")
	kept.locked = true
	var removed := Edit.new()
	removed.surface_path = kept.surface_path
	removed.local_position = kept.local_position
	removed.layer = Edit.Layer.MOSS
	check(profile.add_edit(removed), "Cannot append canceled art edit")
	check(profile.set_edit_deleted(removed.stable_id, true), "Cannot retain deletion tombstone")
	var kept_id := kept.stable_id
	var removed_id := removed.stable_id
	var seed := kept.seed
	controller.regenerate()
	await settle(60)
	controller.regenerate()
	await settle(60)
	var after: Resource = scene.art_direction.profile
	check(after.find_edit(kept_id) != null, "Regeneration lost edited record")
	check(after.find_edit(removed_id) != null, "Regeneration lost deletion tombstone")
	if after.find_edit(kept_id) != null:
		var edit: Resource = after.find_edit(kept_id)
		check(edit.locked and edit.local_position == Vector3(200, 0, 200) and edit.seed == seed, "Regeneration changed locked local detail")
	if after.find_edit(removed_id) != null:
		check(after.find_edit(removed_id).deleted, "Regeneration resurrected erased detail")
	print("PAINTED_REGEN_PRESERVATION ", kept_id, " ", removed_id)

func copy_visual(source: Node) -> Node:
	var copy: Node
	if source is MeshInstance3D:
		var mesh := MeshInstance3D.new()
		mesh.mesh = source.mesh
		mesh.material_override = source.material_override
		mesh.cast_shadow = source.cast_shadow
		mesh.extra_cull_margin = source.extra_cull_margin
		for i in source.get_surface_override_material_count():
			mesh.set_surface_override_material(i, source.get_surface_override_material(i))
		copy = mesh
	elif source is MultiMeshInstance3D:
		var mesh := MultiMeshInstance3D.new()
		mesh.multimesh = source.multimesh
		mesh.cast_shadow = source.cast_shadow
		mesh.extra_cull_margin = source.extra_cull_margin
		copy = mesh
	elif source is Camera3D:
		var camera := Camera3D.new()
		camera.projection = source.projection
		camera.size = source.size
		camera.near = source.near
		camera.far = source.far
		camera.current = true
		copy = camera
	elif source is Light3D or source is WorldEnvironment:
		copy = source.duplicate(0)
		copy.set_script(null)
	elif source is Node3D and not source is CollisionShape3D:
		copy = Node3D.new()
	else:
		return null
	copy.name = source.name
	if copy is Node3D:
		copy.transform = source.transform
		copy.visible = source.visible
	for child in source.get_children(true):
		var visual := copy_visual(child)
		if visual != null:
			copy.add_child(visual)
	return copy

func assign_owner(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		assign_owner(child, owner_root)

func assert_script_free(node: Node) -> void:
	check(node.get_script() == null, "Static editor preview retained runtime script: " + str(node.name))
	for child in node.get_children():
		assert_script_free(child)

func snapshot_roundtrip() -> void:
	var snapshot := Node3D.new()
	snapshot.name = "PaintedConceptEditorSnapshot"
	for child in view.get_children():
		if child.name == "Player":
			continue
		var copy := copy_visual(child)
		if copy != null:
			snapshot.add_child(copy)
	assign_owner(snapshot, snapshot)
	var packed := PackedScene.new()
	check(packed.pack(snapshot) == OK, "Editor snapshot pack failed")
	var path := "user://painted_concept_editor_snapshot.scn"
	check(ResourceSaver.save(packed, path) == OK, "Editor snapshot save failed")
	snapshot.free()
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(reloaded != null, "Editor snapshot could not reopen")
	if reloaded == null:
		return
	var reopened := reloaded.instantiate()
	assert_script_free(reopened)
	check(reopened.get_node_or_null("PaintedGrass") != null, "Saved editor snapshot lost 3D grass")
	var saved_ground: MeshInstance3D = reopened.get_node("TerrenoComposto/Superficie")
	check(saved_ground.material_override.get_shader_parameter("anime_painted") == true, "Saved snapshot reverted to original ground texture")
	var source_count := view.find_children("*", "MultiMeshInstance3D", true, false).size()
	var saved_count := reopened.find_children("*", "MultiMeshInstance3D", true, false).size()
	check(source_count == saved_count, "Saved snapshot lost generated scatter batches")
	reopened.free()
	print("PAINTED_EDITOR_ROUNDTRIP ", path)

func check_editor_preview_path() -> void:
	# Exercise the @tool setup directly without opening an editor or running the
	# gameplay root's _ready. Child authoring scripts still construct their meshes.
	var preview: Node3D = load("res://scenes/dev/integrated_landscape.tscn").instantiate()
	var driver: Script = preview.get_script()
	preview.set_script(null)
	for child in preview.get_children():
		if child.name not in ["TerrenoComposto", "Boschi", "Affioramento_0", "ArtStudyLayers"]:
			preview.remove_child(child)
			child.free()
	root.add_child(preview)
	await settle(5)
	preview.set_script(driver)
	preview.setup_editor_preview()
	await settle(50)
	var layers := preview.get_node_or_null("ArtStudyLayers")
	check(layers != null, "Editor setup lost its art controller")
	check(preview.get_node_or_null("GameplayPreviewRig") == null, "Editor setup unexpectedly built the runtime gameplay rig")
	check(preview.art_direction.profile == layers.profile, "Editor preview used different profile data")
	var ground: MeshInstance3D = preview.get_node("TerrenoComposto/Superficie")
	check(ground.material_override.get_shader_parameter("anime_painted") == true, "Editor setup kept the old ground material")
	check(preview.art_direction.grass.blades.size() == 12, "Editor setup did not build all twelve grass meshes")
	check(not preview.art_direction.grass.chunks.is_empty(), "Editor preview did not scatter any 3D grass")
	var first_count := preview.get_child_count(true)
	preview.setup_editor_preview(layers.profile)
	await settle(40)
	check(preview.get_child_count(true) == first_count, "Repeated editor preview leaked generated helper nodes")
	check(preview.art_direction.profile == layers.profile, "Repeated editor setup changed authoring resource")
	preview.art_direction.clear()
	preview.free()
	await process_frame
	print("PAINTED_EDITOR_SETUP checked same profile, materials, grass and repeated setup without runtime driver")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	if "--editor-only" in OS.get_cmdline_user_args():
		await check_editor_preview_path()
		quit(0 if failures.is_empty() else 1)
		return
	scene = load("res://scenes/dev/integrated_landscape.tscn").instantiate()
	root.add_child(scene)
	await settle(90)
	view = scene.get_node("GameplayPreviewRig/Pixel/View")
	var art: RefCounted = scene.art_direction
	check(art.profile != null, "Integrated art profile is missing")
	check(art.profile.grass_family_weights is Vector4, "Profile family weights unavailable")
	check(scene.has_method("setup_editor_preview"), "Integrated scene has no editor preview entry point")
	await check_local_regeneration()
	art = scene.art_direction
	var ground: MeshInstance3D = view.get_node("TerrenoComposto/Superficie")
	var ground_painted: Material = ground.material_override
	var sources := mesh_state(art)
	check(not sources.is_empty(), "No tree mesh replacements recorded for reversible F7 comparison")
	await move_focus(Vector3(-9, 1, 24))
	check_grass(art.grass)
	await measure_gameplay_view()
	await capture("painted_concept_river")
	var frozen_edits: Array = []
	for edit in art.profile.edits:
		if edit != null:
			frozen_edits.append([edit.stable_id, edit.local_position, edit.seed, edit.locked, edit.deleted])
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F7
	scene._unhandled_key_input(event)
	check(not art.enabled and not art.grass.visible, "F7 did not restore original mode")
	check(ground.material_override != ground_painted, "F7 did not restore original ground")
	for record in sources:
		check(record.node.mesh == record.original, "F7 failed to restore original tree geometry")
		check(record.node.transform == record.transform, "Tree transform changed during F7")
	scene._unhandled_key_input(event)
	check(art.enabled and art.grass.visible, "F7 did not restore painted mode")
	check(ground.material_override == ground_painted, "F7 lost painted material identity")
	for record in sources:
		check(record.node.mesh == record.painted, "F7 lost generated tree geometry")
	var edit_index := 0
	for edit in art.profile.edits:
		if edit == null:
			continue
		check([edit.stable_id, edit.local_position, edit.seed, edit.locked, edit.deleted] == frozen_edits[edit_index], "F7 mutated authored local edits")
		edit_index += 1
	var start: Vector3 = scene.player.position
	Input.action_press("move_down")
	await settle(40)
	Input.action_release("move_down")
	check(scene.player.position.distance_to(start) > .5, "Decorative detail blocked player movement on river approach")
	for water in scene.waters:
		check(water.simulation_enabled, "Water simulation stopped")
		var clock_before: float = water._surface.material_override.get_shader_parameter("clock")
		await settle(4)
		check(water._surface.material_override.get_shader_parameter("clock") > clock_before, "Water clock stopped")
	await move_focus(Vector3(-42, 1, 10))
	await capture("painted_concept_castle")
	await move_focus(Vector3(-59, 1, -49), 22.0)
	check(view.get_node_or_null("Affioramento_0") != null, "Original cliff guide was removed")
	check(art.cliffs != null, "Continuous cliff representation missing")
	await capture("painted_concept_sample")
	await snapshot_roundtrip()
	scene.queue_free()
	await process_frame
	await process_frame
	await check_editor_preview_path()
	print("PAINTED_CONCEPT_", "PASS" if failures.is_empty() else "FAIL", ": F7 geometry, 12 variants, persisted visual preview, editor setup, movement, live water; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

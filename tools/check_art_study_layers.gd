extends SceneTree
const Profile = preload("res://scripts/art/art_study_profile.gd")
const Edit = preload("res://scripts/art/art_surface_edit.gd")
const Layers = preload("res://scripts/art/art_study_layers.gd")
var regeneration_count := 0

func check_stamped_material_roundtrip(scene_root: Node3D) -> void:
	# Actual local-stamp isolation produces A -> B in paint_architecture; the
	# painted ground pass then requests B -> C. F7 must restore exact resource A.
	var art = preload("res://scripts/village/anime_art_direction.gd").new()
	art.root = scene_root
	art.profile = Profile.new()
	var terrain := MeshInstance3D.new()
	terrain.name = "StampedTerrain"
	terrain.mesh = PlaneMesh.new()
	var original := ShaderMaterial.new()
	original.shader = preload("res://shaders/pixelart/ground_clear.gdshader")
	terrain.material_override = original
	scene_root.add_child(terrain)
	var stamp := Edit.new()
	stamp.surface_path = scene_root.get_path_to(terrain)
	stamp.layer = Edit.Layer.GRASS_DENSITY
	art.profile.add_edit(stamp)
	art.paint_architecture(scene_root, {})
	var isolated: ShaderMaterial = terrain.material_override
	assert(isolated != original, "A local surface edit must isolate its shared material")
	var painted: ShaderMaterial = isolated.duplicate()
	painted.set_shader_parameter("anime_painted", true)
	art.remember(terrain, "material_override", painted)
	var material_records := 0
	for change in art.changes:
		if change.get("object") == terrain and change.get("property") == "material_override":
			material_records += 1
			assert(change.before == original and change.after == painted)
	assert(material_records == 1, "Repeated overrides must keep one original baseline")
	# A different property on the same object must not be folded into that record.
	art.remember(terrain, "visible", false)
	for cycle in 3:
		art.apply(true)
		assert(terrain.material_override == painted and not terrain.visible)
		art.apply(false)
		assert(terrain.material_override == original and terrain.visible,
			"F7 must restore the exact authored material, not an intermediate duplicate")
	art.clear()
	assert(art.changes.is_empty() and terrain.material_override == original)
	terrain.free()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var profile := Profile.new()
	assert(is_equal_approx(profile.density_multiplier, 1.3))
	assert(profile.grass_enabled and profile.weathering_enabled and profile.cliffs_enabled)
	var moss := Edit.new()
	moss.surface_path = NodePath("Castle/Wall")
	moss.local_position = Vector3(2, 1, 0)
	moss.local_rotation_degrees = Vector3(90, 0, 0)
	moss.layer = Edit.Layer.MOSS
	moss.radius = 2.0
	moss.intensity = 0.65
	assert(profile.add_edit(moss))
	var stable_id := moss.stable_id
	var stable_seed := moss.seed
	assert(not stable_id.is_empty() and stable_seed == profile.seed_for(stable_id))
	moss.locked = true
	assert(not profile.set_edit_deleted(stable_id, true))
	var removed := Edit.new()
	removed.layer = Edit.Layer.MOSS
	removed.surface_path = moss.surface_path
	removed.intensity = 1.0
	assert(profile.add_edit(removed))
	assert(profile.set_edit_deleted(removed.stable_id, true))
	var erase := Edit.new()
	erase.layer = Edit.Layer.GRASS_DENSITY
	erase.surface_path = NodePath("Terrain")
	erase.intensity = -0.7
	assert(profile.add_edit(erase))
	assert(is_equal_approx(profile.sample_layer(Edit.Layer.GRASS_DENSITY, erase.surface_path, Vector3.ZERO, 1.0), 0.3))
	assert(is_equal_approx(profile.sample_layer(Edit.Layer.MOSS, moss.surface_path, moss.local_position), 0.65))
	assert(is_zero_approx(profile.sample_layer(Edit.Layer.MOSS, NodePath("OtherWall"), moss.local_position)))
	assert(is_zero_approx(profile.sample_layer(Edit.Layer.MOSS, moss.surface_path, moss.local_position + Vector3(0, 0, 3))))
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var layers := Layers.new()
	layers.profile = profile
	scene_root.add_child(layers)
	layers.regeneration_requested.connect(func(requested: Resource):
		assert(requested == profile)
		regeneration_count += 1)
	layers.regenerate()
	layers.regenerate()
	assert(regeneration_count == 2 and profile.edits.size() == 3)
	assert(moss.locked and not moss.deleted and removed.deleted)
	assert(moss.stable_id == stable_id and moss.seed == stable_seed)
	assert(ResourceSaver.save(profile, "user://art_study_profile_roundtrip.tres") == OK)
	var copy := ResourceLoader.load("user://art_study_profile_roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	assert(copy.edits.size() == 3 and copy.find_edit(stable_id).locked)
	assert(copy.find_edit(removed.stable_id).deleted)
	assert(copy.find_edit(stable_id).seed == stable_seed)
	assert(copy.next_edit_serial == profile.next_edit_serial)
	var late_edit := Edit.new()
	assert(copy.add_edit(late_edit) and late_edit.stable_id != removed.stable_id)
	# Shader packing must agree with CPU masks after a rotated, translated,
	# nonuniformly scaled wall: using a world radius would fail this case.
	var surface_to_world := Transform3D(Basis.from_euler(Vector3(.2, .7, -.15)).scaled_local(Vector3(2, .8, 1.5)), Vector3(10, 3, -6))
	var packed := profile.pack_shader_edits(moss.surface_path, surface_to_world)
	assert(packed.art_edit_count == 1 and packed.art_edit_overflow == 0)
	var local_point := moss.local_position + Vector3(.9, .4, .1)
	var world_point := surface_to_world * local_point
	var p := Vector4(world_point.x, world_point.y, world_point.z, 1.0)
	var q := Vector3(packed.art_edit_rows_x[0].dot(p), packed.art_edit_rows_y[0].dot(p), packed.art_edit_rows_z[0].dot(p))
	var shader_weight := (1.0 - smoothstep(.55, 1.0, Vector2(q.x, q.z).length())) * (1.0 - smoothstep(.55, 1.0, absf(q.y)))
	assert(is_equal_approx(shader_weight, moss.influence(local_point)))
	assert(is_equal_approx(packed.art_edit_values[0].x, moss.intensity))
	assert(packed.art_edit_values[0].y == Edit.Layer.MOSS)
	var again := profile.pack_shader_edits(moss.surface_path, surface_to_world)
	assert(again.art_edit_rows_x == packed.art_edit_rows_x and again.art_edit_values == packed.art_edit_values)
	profile.grass_family_weights = Vector4.ZERO
	assert(profile.normalized_family_weights() == Vector4(.25, .25, .25, .25))
	# Fixed GPU buffer cannot silently lose authored data.
	for i in 34:
		var extra := Edit.new()
		extra.surface_path = NodePath("Overflow")
		assert(profile.add_edit(extra))
	var overflow := profile.pack_shader_edits(NodePath("Overflow"))
	assert(overflow.art_edit_count == 32 and overflow.art_edit_overflow == 2)
	assert(profile.edits.size() == 37)
	check_stamped_material_roundtrip(scene_root)
	scene_root.free()
	print("ART_STUDY_PASS: typed roundtrip, locked/tombstone preservation, deterministic seeds, local/world masks, overflow diagnostics, regeneration signal, exact stamped-material F7 roundtrip")
	quit()

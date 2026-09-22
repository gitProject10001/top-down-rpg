extends SceneTree
## Explicit, repeatable migration of the twelve protected study buildings.
## No settlement/landscape regeneration. The source scene remains the authoring data.
const SOURCE := "res://scenes/dev/integrated_landscape.tscn"
const Service = preload("res://addons/house_builder/recipe_apply.gd")
const LOTS := ["StradaBorgo_0_0_-1", "StradaBorgo_0_0_1", "StradaBorgo_0_1_-1", "StradaBorgo_0_1_1", "StradaBorgo_1_0_-1", "StradaBorgo_1_1_1"]
const ROLES := ["dwelling", "shop", "inn", "forge", "stable", "chapel"]
const VARIANTS := ["compact", "high_roof", "side_porch", "rear_annex", "broad_porch", "stone_base"]
const EXPANDED_ROLES := ["inn", "chapel"]
var errors: PackedStringArray = []

func _initialize() -> void: call_deferred("run")

func authored(node: Node) -> Dictionary:
	var values := {}
	for p in node.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_STORAGE and str(p.name) != "script":
			var value = node.get(p.name)
			if not value is Object: values[p.name] = value
	var children := {}
	for child in node.get_children(): children[str(child.name)] = authored(child)
	return {"properties": values, "children": children}

func resized_access(lot: Node3D, house: Node3D) -> PackedVector3Array:
	# Keep the existing connection to the street. The saved approach wraps around
	# the front and then follows the entrance side of these two specific lots.
	var opening: Dictionary=house.resolved_opening(house.openings[0])
	var portal: Vector3=house.wall_point(opening.wall,opening.along,0)
	# The church buttresses project beyond the nave. Keep a full player-width
	# corridor outside their bases before turning into the existing portal.
	var clearance := 1.35 if house.archetype_id == "chapel" else .85
	var outside: Vector3=portal+house.wall_normal(opening.wall)*clearance
	var front: float=house.depth*.5+.85
	return PackedVector3Array([lot.access_path[0],house.transform*Vector3(0,0,front),house.transform*Vector3(outside.x,0,front),house.transform*outside,house.transform*portal])

func run() -> void:
	var scene = load(SOURCE).instantiate()
	var controller = scene.get_script()
	var settings := {"art_preview_center": scene.art_preview_center, "combat_encounter_enabled": scene.combat_encounter_enabled}
	scene.set_script(null) # Do not bake GameplayPreviewRig, grass caches or runtime enemies.
	root.add_child(scene)
	for frame in 12: await physics_frame
	var unchanged := {}
	for child in scene.get_children():
		if child.name != "Borgo" and not str(child.name).begins_with("CasaCitta_"):
			unchanged[str(child.name)] = authored(child)
	var buildings: Array = []
	for i in LOTS.size():
		var lot = scene.get_node("Borgo/Lotto_" + LOTS[i])
		buildings.append({"house": lot.get_node("Edificio"), "lot": lot, "role": ROLES[i], "variant": "compact" if i == 0 else ""})
	for i in 6:
		buildings.append({"house": scene.get_node("CasaCitta_%02d" % i), "role": "dwelling", "variant": VARIANTS[i]})
	for entry in buildings:
		var house = entry.house
		var plan = house.get_node("InteriorPlan")
		var before := authored(plan)
		var pose: Transform3D = house.transform
		var openings: Array = house.openings.duplicate(true)
		var footprint := Vector2(house.width, house.depth)
		var recipe = load("res://addons/house_builder/recipes/" + entry.role + ".tres")
		var resize: bool=entry.has("lot") and entry.role in EXPANDED_ROLES
		var proposal: Dictionary = Service.propose(house, recipe, house.house_seed, hash(str(house.house_seed)+":details"), entry.variant, not resize)
		if not proposal.ok:
			errors.append(str(house.get_path()) + ": " + "; ".join(proposal.errors)); continue
		Service.apply(house, proposal.after)
		if entry.role=="chapel" and entry.has("lot"):
			if entry.lot.path_surface==null: entry.lot.path_surface=preload("res://assets/art/chapel_path_surface.tres")
			# This lot's street attachment is at z=6.4. Keep the former front
			# edge z=5.3 while lengthening the nave away from that connection.
			# Record the last automatic pose so later hand placement is protected.
			var original_pose: Transform3D=entry.lot.baseline_house.transform
			var previous_pose: Transform3D=house.get_meta("study_expansion_pose",original_pose)
			if house.transform.is_equal_approx(previous_pose):
				pose=original_pose.translated_local(Vector3(0,0,5.3-house.depth*.5))
				house.transform=pose
				house.set_meta("study_expansion_pose",pose)
		house.rebuild()
		for frame in 3: await physics_frame
		if not Service._equal(before, authored(plan)): errors.append(str(house.get_path()) + ": InteriorPlan changed")
		if not house.transform.is_equal_approx(pose) or (not resize and Vector2(house.width,house.depth) != footprint) or house.openings != openings:
			errors.append(str(house.get_path()) + ": protected footprint/pose/openings changed")
		if resize:
			entry.lot.access_path=resized_access(entry.lot,house)
			entry.lot.rebuild_access()
		for volume in house.authored_volumes():
			if not volume.volume_error().is_empty(): errors.append(str(volume.get_path()) + ": " + volume.volume_error())
		if entry.has("lot"):
			var request = entry.lot.request.duplicate(true)
			request.recipe = recipe
			request.recipe_variant_id = entry.variant
			request.recipe_structural_seed = house.house_seed
			request.recipe_detail_seed = house.recipe_provenance.detail_seed
			request.footprint=Vector2(house.width,house.depth)
			entry.lot.request = request
		print("BORGO_RECIPE ", house.get_path(), " role=", entry.role, " variant=", entry.variant, " parts=", proposal.after.parts.size())
	for path in unchanged:
		if not Service._equal(unchanged[path], authored(scene.get_node(path))): errors.append(path + ": unrelated authoring changed")
	if errors.is_empty() and "--save" in OS.get_cmdline_user_args():
		scene.set_script(controller)
		for key in settings: scene.set(key, settings[key])
		var packed := PackedScene.new()
		var error := packed.pack(scene)
		if error == OK: error = ResourceSaver.save(packed, SOURCE)
		if error != OK: errors.append("Save failed: " + str(error))
		print("BORGO_SAVE ", error)
	print("BORGO_APPLY_RESULT buildings=", buildings.size(), " errors=", errors)
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if errors.is_empty() else 1)

extends SceneTree
const House = preload("res://addons/house_builder/house.gd")
const Request = preload("res://addons/house_builder/building_request.gd")
const Apply = preload("res://addons/house_builder/recipe_apply.gd")
const Plan = preload("res://addons/house_builder/plan.gd")
const Element = preload("res://addons/house_builder/plan_element.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error("BUILDING_RECIPES: " + label)

func base_house() -> Node3D:
	var house := House.new()
	house.width = 5.8; house.depth = 7.2; house.wall_height = 2.6
	house.openings = [{"kind": "door", "wall": 0, "u": 0.0, "width": 1.4, "height": 2.3}]
	return house

func semantic(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	for part in result.parts: part.erase("node")
	return result

func part_with_id(house: Node, id: String) -> Node3D:
	for container_name in Apply.CONTAINERS:
		var container := house.get_node_or_null(NodePath(container_name))
		if container:
			for node in container.get_children():
				if node.get_meta("recipe_part_id", "") == id: return node
	return null

func check_switch_and_unlock(catalog: Array) -> void:
	var house := base_house()
	var first := Apply.propose(house, catalog[2], 28, 71)
	check(first.ok, "cross-recipe fixture starts valid")
	if not first.ok: house.free(); return
	Apply.apply(house, first.after)
	var chimney := part_with_id(house, "inn:Camino")
	chimney.dimensions *= 1.1
	var edited_volume := part_with_id(house, "inn:SalaLaterale")
	edited_volume.battlement_spacing = 1.45
	# The church now requires its larger nave; this explicit switch allows resize.
	var chapel := Apply.propose(house, catalog[5], 28, 71, "", false)
	check(chapel.ok, "switch recipe retains edited prior detail")
	if chapel.ok:
		Apply.apply(house, chapel.after)
		check(part_with_id(house, "inn:Camino") == chimney, "previous recipe's edited detail retains identity")
		check(part_with_id(house, "inn:SalaLaterale") == edited_volume and is_equal_approx(edited_volume.battlement_spacing, 1.45), "secondary authored Volume property preserves component across recipes")
		chimney.free()
		var back := Apply.propose(house, catalog[2], 28, 71)
		check(back.ok, "switch back accepts manually deleted retained detail")
		if back.ok:
			Apply.apply(house, back.after)
			check(part_with_id(house, "inn:Camino") == null and "inn:Camino" in house.recipe_provenance.deleted_ids, "cross-recipe deletion remains a tombstone")
	house.free()
	house = base_house()
	first = Apply.propose(house, catalog[0], 28, 71, "high_roof")
	check(first.ok, "unlock fixture starts valid")
	if not first.ok: house.free(); return
	Apply.apply(house, first.after)
	chimney = part_with_id(house, "dwelling:Camino")
	var original_seed: int = chimney.detail_seed
	chimney.locked = true
	var locked := Apply.propose(house, catalog[0], 28, 72, "high_roof")
	check(locked.ok, "locked detail recipe proposal valid")
	if locked.ok:
		Apply.apply(house, locked.after)
		check(chimney.detail_seed == original_seed, "Inspector lock preserves detail seed")
		chimney.locked = false
		var unlocked := Apply.propose(house, catalog[0], 28, 73, "high_roof")
		check(unlocked.ok, "unlocked detail recipe proposal valid")
		if unlocked.ok:
			Apply.apply(house, unlocked.after)
			check(chimney.detail_seed != original_seed and not chimney.locked, "Inspector unlock permits regeneration again")
	house.free()

func check_live_plan(recipe: Resource) -> void:
	var expected_height: float = recipe.main_properties.wall_height
	var house := base_house(); house.name = "LivePlanHouse"
	house.wall_height = 4.0
	var plan := Plan.new(); plan.name = "InteriorPlan"
	house.add_child(plan); plan.owner = house
	var floor := Node3D.new(); floor.name = "Piano_0"; plan.add_child(floor); floor.owner = house
	var room := Element.new(); room.name = "StanzaManuale"; room.stable_id = "manual_room"; room.dimensions = Vector3(2.2, 2.6, 2.8)
	floor.add_child(room); room.owner = house
	root.add_child(house)
	plan.rebuild()
	check(is_equal_approx(house.wall_height, 2.6), "legacy InteriorPlan still controls exterior height exactly")
	var records: Array = plan.level_records(0).duplicate(true)
	var signals: Array = []
	house.recipe_applied.connect(func(): signals.append(house.build_count))
	var proposal := Apply.propose(house, recipe, 12, 23)
	check(proposal.ok, "real InteriorPlan shop proposal validates")
	if proposal.ok:
		Apply.apply(house, proposal.after)
		check(signals.is_empty(), "recipe notification waits for completed geometry")
		house.rebuild()
		check(signals.size() == 1, "recipe notification fires once after geometry rebuild")
		plan.rebuild(); house.rebuild()
		check(signals.size() == 1, "ordinary rebuild does not duplicate recipe notification")
		check(is_equal_approx(house.wall_height, expected_height) and is_equal_approx(plan.floor_height, 2.6), "recipe exterior eaves survive real InteriorPlan rebuild without raising floor")
		check(Apply._equal(records, plan.level_records(0)), "real InteriorPlan authored records unchanged")
		for volume in house.authored_volumes():
			check(volume.volume_error().is_empty(), "attached roof stays valid after real plan rebuild: " + volume.volume_error())
		var packed := PackedScene.new(); check(packed.pack(house) == OK, "live InteriorPlan packs")
		check(ResourceSaver.save(packed, "user://building_recipe_live_plan.tscn") == OK, "live InteriorPlan saves")
		var reopened = load("user://building_recipe_live_plan.tscn").instantiate()
		root.add_child(reopened)
		reopened.get_node("InteriorPlan").rebuild(); reopened.rebuild()
		check(is_equal_approx(reopened.wall_height, expected_height) and is_equal_approx(reopened.get_node("InteriorPlan").floor_height, 2.6), "reopening keeps exterior and interior heights independent")
		for volume in reopened.authored_volumes(): check(volume.volume_error().is_empty(), "reopened accessory roof still valid")
		reopened.free()
		plan.floor_height = 4.2
		house.wall_height = 4.2
		house.recipe_provenance.main_baseline.wall_height = 3.6
		var tall_floor := Apply.propose(house, recipe, 13, 24)
		check(tall_floor.ok, "existing taller floor remains valid")
		if tall_floor.ok:
			check(is_equal_approx(tall_floor.after.properties.wall_height, maxf(expected_height,4.2)) and is_equal_approx(tall_floor.after.provenance.main_baseline.wall_height, maxf(expected_height,4.2)), "existing floor constraint participates in recipe baseline")
			Apply.apply(house, tall_floor.after)
			var taller_recipe: Resource = recipe.duplicate(true)
			taller_recipe.main_properties.wall_height = maxf(expected_height,4.2)+0.4
			var taller := Apply.propose(house, taller_recipe, 13, 24)
			check(taller.ok and is_equal_approx(taller.after.properties.wall_height, maxf(expected_height,4.2)+0.4), "floor-imposed height is not mistaken for a manual edit")
	house.free()

func check_legacy_volume_baseline(recipe: Resource) -> void:
	var house := base_house()
	var proposal := Apply.propose(house, recipe, 12, 23)
	check(proposal.ok, "legacy volume baseline fixture validates")
	if not proposal.ok: house.free(); return
	Apply.apply(house, proposal.after)
	var volume := part_with_id(house, "inn:SalaLaterale")
	var old_seed: int = volume.house_seed
	var baseline: Dictionary = volume.get_meta("recipe_baseline").duplicate(true)
	for field in ["battlement_spacing", "roof_door_enabled", "roof_door_floor_id", "roof_door_offset", "roof_door_open"]:
		baseline.values.erase(field)
	volume.set_meta("recipe_baseline", baseline)
	var migrated := Apply.propose(house, recipe, 99, 23)
	check(migrated.ok, "older baseline migrates without rejection")
	if migrated.ok:
		Apply.apply(house, migrated.after)
		check(volume.house_seed != old_seed, "missing default fields do not falsely protect an untouched volume")
		baseline = volume.get_meta("recipe_baseline").duplicate(true)
		baseline.values.erase("battlement_spacing")
		volume.set_meta("recipe_baseline", baseline)
		volume.battlement_spacing = 1.55
		old_seed = volume.house_seed
		var manual := Apply.propose(house, recipe, 100, 23)
		check(manual.ok, "older baseline can retain non-default secondary edit")
		if manual.ok:
			Apply.apply(house, manual.after)
			check(is_equal_approx(volume.battlement_spacing, 1.55) and volume.house_seed == old_seed, "missing tracked field with non-default value is protected")
	house.free()

func run() -> void:
	var legacy := Request.new()
	check(legacy.data() == {"type": 0, "footprint": Vector2(5, 7), "storeys": 1, "seed": 1, "entrance": 0}, "unconfigured request retains exact legacy contract")
	var legacy_house := legacy.create_house()
	check(legacy_house.building_recipe == null and legacy_house.get_node_or_null("Volumes") == null, "legacy request still creates the original single house")
	legacy_house.free()
	var catalog: Array = []
	for role in ["dwelling", "shop", "inn", "forge", "stable", "chapel"]:
		var recipe = load("res://addons/house_builder/recipes/" + role + ".tres")
		catalog.append(recipe)
		var variants: Array = recipe.variants if not recipe.variants.is_empty() else [{"id": ""}]
		for variant in variants:
			var house := base_house()
			if role=="chapel":
				var small_before := Apply.snapshot(house)
				var too_small := Apply.propose(house,recipe,21,97,variant.id)
				check(not too_small.ok and Apply._equal(semantic(small_before),semantic(Apply.snapshot(house))),"large church rejects a protected small lot without changing it")
				house.width=recipe.main_properties.width; house.depth=recipe.main_properties.depth
			var source_footprint := Vector2(house.width,house.depth)
			var proposal := Apply.propose(house, recipe, 21, 97, variant.id)
			check(proposal.ok, role + "/" + variant.id + " validates: " + str(proposal.errors))
			if not proposal.ok: house.free(); continue
			var repeated := Apply.propose(house, recipe, 21, 97, variant.id)
			check(Apply._equal(semantic(proposal.after), semantic(repeated.after)), role + " proposal is deterministic")
			Apply.apply(house, proposal.after)
			check(Vector2(house.width,house.depth).is_equal_approx(source_footprint), "recipe preserves source footprint")
			var applied := Apply.snapshot(house)
			var again := Apply.propose(house, recipe, 21, 97, variant.id)
			check(again.ok, role + " repeated application remains valid")
			if again.ok:
				Apply.apply(house, again.after)
				check(Apply._equal(semantic(applied), semantic(Apply.snapshot(house))), role + " repeated application is idempotent")
			var detail_change := Apply.propose(house, recipe, 21, 98, variant.id)
			check(detail_change.ok, "independent detail seed remains valid")
			if detail_change.ok:
				check(Apply._equal(applied.properties, detail_change.after.properties), "detail seed leaves main structure unchanged")
				for part in detail_change.after.parts:
					if part.container == "Volumes":
						var old: Dictionary = applied.parts.filter(func(p): return p.id == part.id)[0]
						check(Apply._equal(old.values, part.values), "detail seed leaves authored volume geometry unchanged")
			house.free()
	# Named component preservation, independent detail seed, persistence and actual UndoRedo.
	var house := base_house(); house.name = "RecipeHouse"
	var interior := Node3D.new(); interior.name = "InteriorPlan"; interior.set_meta("manual_floor_height", 2.6); house.add_child(interior); interior.owner = house
	var manual := Node3D.new(); manual.name = "ManualLamp"; house.add_child(manual); manual.owner = house
	var recipe: Resource = catalog[2]
	var proposal := Apply.propose(house, recipe, 28, 71)
	check(proposal.ok, "inn fixture valid")
	if proposal.ok:
		var undo := UndoRedo.new()
		undo.create_action("Apply recipe")
		undo.add_do_method(Apply.apply.bind(house, proposal.after))
		undo.add_undo_method(Apply.apply.bind(house, proposal.before))
		undo.commit_action()
		check(house.get_node("InteriorPlan") == interior and house.get_node("ManualLamp") == manual, "authoring children retain exact identity")
		undo.undo()
		check(house.building_recipe == null and house.get_node_or_null("Volumes") == null and house.get_node("InteriorPlan") == interior, "Undo restores unmodified source and children")
		undo.redo()
		var volume: Node3D = house.get_node("Volumes/SalaLaterale")
		var detail: Node3D = house.get_node("RecipeDetails/Camino")
		volume.host_offset = .06
		detail.dimensions *= 1.12
		detail.locked = true
		var custom := Node3D.new(); custom.name = "HandPlaced"; volume.add_child(custom); custom.owner = house
		var removed := house.get_node("RecipeDetails/Abbaino"); removed.free()
		house.roof_height = 3.7
		var changed := Apply.propose(house, recipe, 999, 222)
		check(changed.ok, "regeneration accepts protected components")
		if changed.ok:
			Apply.apply(house, changed.after)
			check(house.get_node("Volumes/SalaLaterale") == volume and is_equal_approx(volume.host_offset, .06) and custom.get_parent() == volume, "manual component/child survives seed changes")
			check(house.get_node("RecipeDetails/Camino") == detail and detail.locked and is_equal_approx(detail.dimensions.x, .85 * 1.12), "locked edited detail survives seed changes")
			check(not house.has_node("RecipeDetails/Abbaino") and "inn:Abbaino" in house.recipe_provenance.deleted_ids, "intentional deletion persists")
			check(is_equal_approx(house.roof_height, 3.7), "manual root property survives recipe reapplication")
			var packed := PackedScene.new(); check(packed.pack(house) == OK, "recipe authoring packs")
			check(ResourceSaver.save(packed, "user://building_recipe_roundtrip.tscn") == OK, "recipe scene saves")
			var reopened = load("user://building_recipe_roundtrip.tscn").instantiate()
			check(reopened.building_recipe.recipe_id == "inn" and reopened.recipe_provenance.detail_seed == 222, "recipe resources and provenance survive reopen")
			check(reopened.has_node("InteriorPlan") and reopened.has_node("Volumes/SalaLaterale/HandPlaced") and not reopened.has_node("RecipeDetails/Abbaino"), "manual children and deletion survive reopen")
			var repeat := Apply.propose(reopened, recipe, 999, 223)
			check(repeat.ok, "reopened recipe remains editable")
			reopened.free()
		undo.clear_history()
		undo.free()
	house.free()
	var request := Request.new(); request.recipe = catalog[1]; request.recipe_detail_seed = 32
	check(request.data().schema == 3 and request.data().recipe.id == "shop", "recipe request includes versioned recipe inputs")
	var requested := request.create_house()
	check(requested != null and requested.building_recipe.recipe_id == "shop" and requested.has_node("RecipeDetails/BancoMerci"), "BuildingRequest delegates to same recipe service")
	if requested: requested.free()
	for storeys in [2, 3]:
		request.storeys = storeys
		requested = request.create_house()
		check(requested != null and requested.wall_height >= storeys * 2.6, "recipe request preserves declared storeys before InteriorPlan exists")
		if requested:
			var again := Apply.propose(requested, catalog[1], 1, 33)
			check(again.ok and again.after.properties.wall_height >= storeys * 2.6, "later recipe application preserves request height constraint")
			var chimney := part_with_id(requested, "shop:Camino")
			check(chimney != null and chimney.position.y > storeys * 2.6, "roof detail anchors use preserved multi-storey height")
			requested.free()
	var impossible: Resource = catalog[2].duplicate(true)
	impossible.components[0].properties.wall_height = 20.0
	var unchanged := base_house()
	var invalid := Apply.propose(unchanged, impossible, 1, 2)
	check(not invalid.ok and unchanged.building_recipe == null and unchanged.get_child_count() == 0, "invalid component fails proposal without mutating the source")
	unchanged.free()
	for invalid_kind in [true, false]:
		var malformed: Resource = catalog[0].duplicate(true)
		malformed.variants.clear()
		if invalid_kind: malformed.details[0].kind = "unregistered_test_detail"
		else: malformed.details[0].dimensions = Vector3(1,0,1)
		var source := base_house()
		var rejected := Apply.propose(source, malformed, 1, 2)
		check(not rejected.ok and source.building_recipe == null and source.get_child_count() == 0, "unknown detail kind or invalid dimensions fail before source mutation")
		source.free()
	check_switch_and_unlock(catalog)
	check_live_plan(catalog[2])
	check_legacy_volume_baseline(catalog[2])
	print("BUILDING_RECIPE_CHECK failures=", failures)
	quit(0 if failures == 0 else 1)

@tool
extends RefCounted
## Exercises the real plugin chooser and its real EditorUndoRedoManager history.
func run(plugin: EditorPlugin) -> void:
	for _i in 65: await plugin.get_tree().process_frame
	var scene := EditorInterface.get_edited_scene_root()
	assert(scene != null)
	var house = load("res://addons/house_builder/house.gd").new()
	house.name = "EditableRecipeHouse"; house.width = 5.8; house.depth = 7.2
	var openings: Array[Dictionary] = [{"kind": "door", "wall": 0, "u": 0.0, "width": 1.4, "height": 2.3}]
	house.openings = openings
	scene.add_child(house); house.owner = scene
	var manual := Node3D.new(); manual.name = "ManualObject"; house.add_child(manual); manual.owner = scene
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(house)
	plugin.recipe_choice.select(1); plugin._recipe_variants()
	plugin.recipe_structural_seed.value = 57; plugin.recipe_detail_seed.value = 84
	plugin._apply_building_recipe()
	for _i in 4: await plugin.get_tree().process_frame
	assert(house.building_recipe != null and house.building_recipe.recipe_id == "shop")
	assert(house.has_node("RecipeDetails/TendaBottega") and house.has_node("RecipeDetails/BancoMerci"))
	var porch: Node = house.get_node("RecipeDetails/TendaBottega")
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(house))
	history.undo()
	assert(house.building_recipe == null and not house.has_node("RecipeDetails"))
	assert(house.get_node("ManualObject") == manual)
	history.redo()
	assert(house.get_node("RecipeDetails/TendaBottega") == porch)
	assert(porch.owner == scene and house.get_node("RecipeDetails/BancoMerci").owner == scene)
	plugin._apply_building_recipe()
	assert(house.get_node("RecipeDetails/TendaBottega") == porch and house.get_node("RecipeDetails").get_child_count() == 4)
	assert(not plugin.recipe_keep_footprint.button_pressed)
	plugin.recipe_choice.select(2); plugin._recipe_variants()
	plugin._apply_building_recipe()
	assert(is_equal_approx(house.width, 9.0) and is_equal_approx(house.depth, 8.6))
	history.undo()
	assert(is_equal_approx(house.width, 5.8) and is_equal_approx(house.depth, 7.2))
	assert(house.get_node("RecipeDetails/TendaBottega") == porch and house.get_node("ManualObject") == manual)
	history.redo()
	assert(is_equal_approx(house.width, 9.0) and is_equal_approx(house.depth, 8.6))
	plugin.recipe_keep_footprint.button_pressed = true
	plugin.recipe_choice.select(5); plugin._recipe_variants()
	plugin._apply_building_recipe()
	assert(house.building_recipe.recipe_id == "chapel")
	assert(is_equal_approx(house.width, 9.0) and is_equal_approx(house.depth, 8.6))
	assert(house.get_node("ManualObject") == manual)
	print("BUILDING_RECIPE_REAL_EDITOR_APPLY_UNDO_REDO_IDEMPOTENT_OK")
	print("BUILDING_RECIPE_REAL_EDITOR_ROLE_DIMENSIONS_KEEP_FOOTPRINT_OK")
	plugin.get_tree().quit()

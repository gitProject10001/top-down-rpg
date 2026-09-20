extends SceneTree
## Reproduce the late Volume audit which replaces already painted materials.
const House = preload("res://addons/house_builder/house.gd")
const Recipes = preload("res://addons/house_builder/recipe_apply.gd")
const Art = preload("res://scripts/village/anime_art_direction.gd")
const Edit = preload("res://scripts/art/art_surface_edit.gd")
class GrassProbe extends Node3D:
	var enabled_calls := 0
	func set_enabled(_active: bool) -> void: enabled_calls += 1

var failures := 0
var art = Art.new()
var pending: Dictionary = {}
var notifications := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error("BUILDING_MATERIAL_REFRESH: " + label)

func queue_refresh(building: Node) -> void:
	notifications += 1
	if pending.has(building.get_instance_id()): return
	pending[building.get_instance_id()] = building
	call_deferred("flush_refresh")

func flush_refresh() -> void:
	for building in pending.values():
		if is_instance_valid(building): art.refresh_architecture(building)
	pending.clear()

func materials(node: Node, found: Dictionary = {}) -> Array:
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			var material = node.get_active_material(i)
			if material is ShaderMaterial and material.shader and material.shader.resource_path.get_file() in ["solid_masonry.gdshader", "painted_architecture.gdshader"]:
				found[material.get_instance_id()] = material
	for child in node.get_children(true): materials(child, found)
	return found.values()

func assert_painted(building: Node, active: bool, label: String) -> void:
	var list := materials(building)
	check(not list.is_empty(), "fixture contains actual architecture ShaderMaterials")
	for material in list: check((material.get_shader_parameter("anime_painted") == true) == active, label)

func create_house(world: Node, title: String, role: String) -> Node3D:
	var house := House.new(); house.name = title; house.width = 6.0; house.depth = 7.0
	house.openings = [{"kind": "door", "wall": 0, "u": 0.0, "width": 1.4, "height": 2.3}]
	var recipe = load("res://addons/house_builder/recipes/" + role + ".tres")
	var proposal := Recipes.propose(house, recipe, 14, 23,"",role!="chapel")
	check(proposal.ok, "test building recipe valid: " + str(proposal.errors))
	if proposal.ok: Recipes.apply(house, proposal.after)
	world.add_child(house)
	house.set_process(false)
	for volume in house.authored_volumes(): volume.set_process(false)
	return house

func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var house := create_house(world, "Locanda", "inn")
	var neighbor := create_house(world, "Cappella", "chapel"); neighbor.position.x = 20.0
	var grass := GrassProbe.new(); grass.name = "UntouchedGrass"; world.add_child(grass)
	var marker := Node3D.new(); world.add_child(marker)
	art.root = world
	art.profile = art.profile.duplicate(true)
	var stamp := Edit.new(); stamp.stable_id = "painted_wall_moss"; stamp.layer = Edit.Layer.MOSS
	stamp.surface_path = NodePath("Locanda/_Generated/Walls"); stamp.local_position = Vector3(1.0, .3, 3.5)
	art.profile.edits.append(stamp)
	art.paint_architecture(world, {})
	art.remember(marker, "position", Vector3(3, 4, 5))
	art.grass = grass
	art.apply(true)
	house.rebuilt.connect(queue_refresh.bind(house))
	assert_painted(house, true, "initial materials are painted")
	var count_before: int = art.changes.size()
	var grass_calls := grass.enabled_calls
	var neighbor_materials := materials(neighbor)
	var prior_material_ids := materials(house).map(func(m): return m.get_instance_id())
	var volume: Node3D = house.authored_volumes()[0]
	volume._observed = ""
	volume._process(.2)
	check(house._pending, "first Volume observation really requests another host rebuild")
	house._process(.2)
	check(notifications == 1, "late host rebuild emits generic notification")
	check(materials(house).any(func(m): return m.get_instance_id() not in prior_material_ids), "late rebuild replaced actual material objects")
	assert_painted(house, false, "new materials expose the previous unpainted-default regression")
	await process_frame
	assert_painted(house, true, "deferred local refresh repaints all replacement materials")
	check(art.changes.size() == count_before, "disposable material records are removed instead of accumulating")
	check(art.grass == grass and grass.enabled_calls == grass_calls, "local material refresh does not reconfigure or toggle grass")
	check(materials(neighbor) == neighbor_materials, "neighbor material identities are untouched")
	check(marker.position == Vector3(3, 4, 5), "unrelated presentation records remain active")
	var facade: Node3D=neighbor.get_node("RecipeDetails/FacciataGotica")
	facade.rebuilt.connect(queue_refresh.bind(neighbor))
	facade.rebuild()
	await process_frame
	var facade_material: ShaderMaterial=facade.get_node("_GeneratedRecipeDetail/DetailMesh").mesh.surface_get_material(0)
	check(facade_material.get_shader_parameter("anime_painted")==true and facade_material.get_shader_parameter("masonry_finish_enabled")==true,"detail rebuild preserves painted weathering and shared masonry finish")
	var walls: MeshInstance3D = house.get_node("_Generated/Walls")
	check(materials(walls).any(func(m): return m.get_shader_parameter("art_edit_count") == 1), "surface stamp reapplied to replacement wall")
	art.apply(false)
	house.roof_height += .15; house.rebuild()
	await process_frame
	assert_painted(house, false, "rebuild while F7 is off stays in original mode")
	assert_painted(neighbor, false, "F7 still restores untouched neighbor")
	check(facade_material.get_shader_parameter("anime_painted")!=true,"F7 restores rebuilt detail shader")
	art.apply(true)
	assert_painted(house, true, "F7 restores regenerated painted materials")
	assert_painted(neighbor, true, "neighbor retains its reversible presentation")
	for iteration in 4:
		house.house_seed += 1; house.rebuild()
		await process_frame
		assert_painted(house, true, "repeated rebuild stays painted")
		check(art.changes.size() == count_before, "repeated rebuild keeps tracking bounded")
	art.clear()
	assert_painted(house, false, "clear restores latest generated material baseline")
	check(marker.position == Vector3.ZERO, "clear restores unrelated original property")
	world.free()
	print("BUILDING_MATERIAL_REFRESH_CHECK failures=", failures, " rebuild_notifications=", notifications)
	quit(0 if failures == 0 else 1)

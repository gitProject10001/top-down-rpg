extends SceneTree
const House = preload("res://addons/house_builder/house.gd")
const Plan = preload("res://addons/house_builder/plan.gd")
const Element = preload("res://addons/house_builder/plan_element.gd")
const Apply = preload("res://addons/house_builder/recipe_apply.gd")
const Recipe = preload("res://addons/house_builder/recipes/inn.tres")
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error("INN_COMPOSITION: " + label)

func roof_intersections(visual: MeshInstance3D, frame: Transform3D, origin: Vector3) -> Array[Vector3]:
	var hits: Array[Vector3]=[]
	for surface in visual.mesh.get_surface_count():
		var arrays := visual.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size() if not indices.is_empty() else positions.size(),3):
			var triangle: Array[Vector3]=[]
			for j in 3: triangle.append(frame*positions[indices[i+j] if not indices.is_empty() else i+j])
			var hit = Geometry3D.segment_intersects_triangle(origin,origin-Vector3.UP*12,triangle[0],triangle[1],triangle[2])
			if hit is Vector3: hits.append(hit)
	return hits

func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var house := House.new(); house.name = "Locanda"; house.width = 9; house.depth = 8.6
	house.openings = [{"kind":"door","wall":3,"u":0.0,"width":1.4,"height":2.3},{"kind":"window","wall":0,"u":.55,"y":1.5}]
	var original_openings := house.openings.duplicate(true)
	var plan := Plan.new(); plan.name = "InteriorPlan"; house.add_child(plan); plan.owner = house
	var level := Node3D.new(); level.name = "PianoTerra"; level.set_meta("floor_id","ground"); plan.add_child(level); level.owner = house
	var room := Element.new(); room.name = "SalaManuale"; room.stable_id = "inn_original_room"; room.dimensions = Vector3(4,2.6,4)
	level.add_child(room); room.owner = house
	var records := plan.level_records(0).duplicate(true)
	var proposal := Apply.propose(house, Recipe, 27, 93)
	check(proposal.ok, "inn composition fits original lower entrance: " + str(proposal.errors))
	if not proposal.ok: house.free(); world.free(); quit(1); return
	var undo := UndoRedo.new(); undo.create_action("Inn composition")
	undo.add_do_method(Apply.apply.bind(house,proposal.after)); undo.add_undo_method(Apply.apply.bind(house,proposal.before)); undo.commit_action()
	world.add_child(house)
	for frame in 4: await physics_frame
	check(house.wall_height == 5.9 and house.facade_storey_height == 3.2, "exterior reads two storeys")
	check(plan.levels().size() == 1 and is_equal_approx(plan.floor_height,2.6) and Apply._equal(records,plan.level_records(0)), "no invented interior storey or changed room data")
	check(Apply._equal(original_openings,house.openings), "manual lower openings remain exact")
	check(house.facade_openings().size() == 14, "upper facade keeps fourteen windows outside the roof junction")
	var facade_before := house.facade_openings()
	check(Apply._equal(facade_before,house.facade_openings()), "generated upper-window IDs and placement deterministic")
	var replacement: Dictionary = facade_before[0].duplicate(true); replacement.erase("facade_id")
	house.openings.append(replacement)
	check(house.facade_openings().size() == 13 and replacement in house.openings, "manual opening overrides a generated upper window")
	house.openings = original_openings
	var gallery: Node3D = house.get_node("Components/GalleriaSuperiore")
	var porch: Node3D = house.get_node("Volumes/PorticoIngresso")
	check(gallery.validation_error().is_empty() and gallery.balcony_width > 7.8, "long gallery uses the ordinary validated Balcony builder")
	check(not gallery.create_door and not gallery.exterior_stairs and not gallery.support_posts, "gallery creates no fake interior access or ground blockers")
	check(porch.roof_top() < gallery.elevation-.17, "porch roof clears the gallery deck")
	check(house.get_node("Volumes/SalaLaterale").host_wall == 1, "annex stays behind the inn, away from the left access")
	var dormer: Node3D = house.get_node("RecipeDetails/Abbaino")
	var rear_dormer: Node3D = house.get_node("RecipeDetails/AbbainoRetro")
	check(absf(dormer.position.z-rear_dormer.position.z)>3.0 and dormer.position.x<0 and rear_dormer.position.x>0, "dormers occupy opposite slopes clear of the transverse body")
	var query := PhysicsRayQueryParameters3D.create(Vector3(.1,5,5.0),Vector3(.1,2.0,5.0),1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and gallery.is_ancestor_of(hit.collider) and is_equal_approx(hit.position.y,gallery.elevation), "gallery deck has real collision at the authored elevation")
	var capsule := CapsuleShape3D.new(); capsule.radius=.3125; capsule.height=1.9481
	var clearance := PhysicsShapeQueryParameters3D.new(); clearance.shape=capsule; clearance.collision_mask=1
	clearance.transform=Transform3D(Basis.IDENTITY,Vector3(0,1.10,5.0))
	check(world.get_world_3d().direct_space_state.intersect_shape(clearance).is_empty(), "character capsule fits below the portico and gallery")
	var upper: Node3D=house.get_node("Volumes/CorpoCamere")
	clearance.transform.origin=Vector3(5.1,1.1,1.505)
	check(world.get_world_3d().direct_space_state.intersect_shape(clearance).is_empty(),"walkable ground below the upper body")
	check(not house.contains_footprint(clearance.transform.origin),"passing beneath the upper body does not trigger entry/cutaway")
	var roof_hits := roof_intersections(house.get_node("_Generated/Roof"),Transform3D.IDENTITY,Vector3(3.7,12,1.75))
	roof_hits.append_array(roof_intersections(upper.get_node("_Generated/Roof"),upper.transform,Vector3(3.7,12,1.75)))
	check(not roof_hits.is_empty(),"joined roof covers the transverse body")
	for roof_hit in roof_hits: check(roof_hit.y>7.4,"main roof buried inside upper body is removed, including relief tiles")
	var previous_inset: float=upper.attachment_inset
	upper.attachment_inset=.5
	check(not upper.volume_error().is_empty(),"exposed rear gable is rejected before regeneration")
	upper.attachment_inset=previous_inset
	house.set_cutaway(true,0,2.6)
	check(not gallery.visual.visible and not dormer.get_node("_GeneratedRecipeDetail/DetailMesh").visible and not rear_dormer.get_node("_GeneratedRecipeDetail/DetailMesh").visible, "upper gallery and roof ornaments disappear in ground-floor cutaway")
	house.set_cutaway(false)
	check(gallery.visual.visible and dormer.get_node("_GeneratedRecipeDetail/DetailMesh").visible and rear_dormer.get_node("_GeneratedRecipeDetail/DetailMesh").visible, "outside presentation restores all upper elements")
	undo.undo(); house.rebuild()
	check(not house.has_node("Components") and house.get_node("InteriorPlan") == plan and not house.facade_upper_windows, "Undo restores original exterior and original interior identity")
	undo.redo(); house.rebuild()
	check(house.get_node("Components/GalleriaSuperiore") == gallery, "Redo reuses the exact authored gallery node")
	var revised = Recipe.duplicate(true)
	for component in revised.components:
		if component.id == "GalleriaSuperiore": component.properties.projection=1.8
	gallery.locked=true
	var locked := Apply.propose(house,revised,27,94)
	check(locked.ok, "locked gallery can coexist with a new recipe revision")
	if locked.ok: Apply.apply(house,locked.after)
	check(is_equal_approx(gallery.projection,1.45), "Inspector lock protects gallery projection")
	gallery.locked=false
	var unlocked := Apply.propose(house,revised,27,95)
	check(unlocked.ok, "unlocked gallery can update")
	if unlocked.ok: Apply.apply(house,unlocked.after)
	check(is_equal_approx(gallery.projection,1.8), "Inspector unlock allows recipe gallery update")
	var custom := Node3D.new(); custom.name="ManualFlowerBox"; gallery.add_child(custom); custom.owner=house
	gallery.projection=1.9
	var manual := Apply.propose(house,Recipe,28,96)
	check(manual.ok, "edited gallery accepted without replacing its manual child")
	if manual.ok: Apply.apply(house,manual.after)
	check(is_equal_approx(gallery.projection,1.9) and gallery.get_node("ManualFlowerBox")==custom, "manual gallery edit and child retained")
	house.rebuild()
	var packed := PackedScene.new(); check(packed.pack(house)==OK,"composed inn packs")
	check(ResourceSaver.save(packed,"user://inn_composition.tscn")==OK,"composed inn saves")
	var reopened = load("user://inn_composition.tscn").instantiate()
	check(reopened.get_node("Volumes/CorpoCamere").roof_junction and is_equal_approx(reopened.get_node("Volumes/CorpoCamere").attachment_elevation,3.2),"roof junction and upper elevation survive reopening")
	check(reopened.has_node("Components/GalleriaSuperiore/ManualFlowerBox") and reopened.facade_openings().size()==14,"gallery authoring and upper facade survive reopening")
	reopened.free()
	gallery.free()
	var deleted := Apply.propose(house,Recipe,29,97)
	check(deleted.ok,"manually deleted gallery does not invalidate remaining inn")
	if deleted.ok: Apply.apply(house,deleted.after)
	check(not house.has_node("Components/GalleriaSuperiore") and "inn:GalleriaSuperiore" in house.recipe_provenance.deleted_ids,"gallery deletion is a persistent tombstone")
	undo.clear_history(); undo.free()
	world.free()
	print("INN_COMPOSITION_CHECK failures=",failures)
	quit(0 if failures==0 else 1)

extends SceneTree
const House = preload("res://addons/house_builder/house.gd")
const Apply = preload("res://addons/house_builder/recipe_apply.gd")
const Recipe = preload("res://addons/house_builder/recipes/chapel.tres")
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1; push_error("CHAPEL_COMPOSITION: "+label)

func mesh_hits(visual: MeshInstance3D,frame: Transform3D,origin: Vector3) -> Array[Vector3]:
	var hits: Array[Vector3]=[]
	for surface in visual.mesh.get_surface_count():
		var arrays := visual.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size() if not indices.is_empty() else positions.size(),3):
			var points: Array[Vector3]=[]
			for j in 3: points.append(frame*positions[indices[i+j] if not indices.is_empty() else i+j])
			var hit = Geometry3D.segment_intersects_triangle(origin,origin-Vector3.UP*12,points[0],points[1],points[2])
			if hit is Vector3: hits.append(hit)
	return hits

func run() -> void:
	var house := House.new(); house.width=8.8; house.depth=14.2
	house.openings=[{"kind":"door","wall":3,"u":0.0,"width":1.4,"height":2.3},{"kind":"window","wall":3,"u":.65,"y":1.5}]
	var openings := house.openings.duplicate(true)
	var proposal := Apply.propose(house,Recipe,27,93)
	check(proposal.ok,"roof junction clears the retained entrance and side window: "+str(proposal.errors))
	if not proposal.ok: house.free(); quit(1); return
	var undo := UndoRedo.new(); undo.create_action("Church composition")
	undo.add_do_method(Apply.apply.bind(house,proposal.after)); undo.add_undo_method(Apply.apply.bind(house,proposal.before)); undo.commit_action()
	root.add_child(house)
	for i in 4: await physics_frame
	var upper: Node3D=house.get_node("Volumes/CoperturaPortale")
	var facade: Node3D=house.get_node("RecipeDetails/FacciataGotica")
	check(house.masonry_trim and upper.masonry_trim,"stone treatment belongs to ordinary builder nodes")
	check(Apply._equal(openings,house.openings),"original openings retained")
	var origin := Vector3(-4.0,12,.30)
	var hits := mesh_hits(house.get_node("_Generated/Roof"),Transform3D.IDENTITY,origin)
	hits.append_array(mesh_hits(upper.get_node("_Generated/Roof"),upper.transform,origin))
	check(not hits.is_empty(),"transverse roof covers the entrance axis")
	for hit in hits: check(hit.y>8.0,"buried main roof tiles removed from intersection")
	var query := PhysicsShapeQueryParameters3D.new(); var capsule := CapsuleShape3D.new()
	capsule.radius=.3125; capsule.height=1.9481; query.shape=capsule; query.collision_mask=1
	for x in [-5.65,-5.3,-5.1]:
		query.transform=Transform3D(Basis.IDENTITY,Vector3(x,1.1,0))
		check(house.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"approach under the portal is clear at "+str(x))
	house.set_cutaway(true,0,2.6)
	check(not upper.get_node("_Generated/Roof").visible,"cross roof disappears on entry")
	house.set_cutaway(false)
	undo.undo(); house.rebuild()
	check(not house.masonry_trim and not house.has_node("Volumes"),"Undo restores original structure")
	undo.redo(); house.rebuild()
	check(house.get_node("Volumes/CoperturaPortale")==upper,"Redo preserves authored component identity")
	facade.position.z+=.04
	var edited := Apply.propose(house,Recipe,27,94)
	check(edited.ok,"detail seed can change with edited facade")
	if edited.ok: Apply.apply(house,edited.after)
	check(is_equal_approx(facade.position.z,.04),"manual facade position survives detail regeneration")
	var packed := PackedScene.new(); check(packed.pack(house)==OK,"church packs")
	check(ResourceSaver.save(packed,"user://chapel_composition.tscn")==OK,"church saves")
	var reopened = load("user://chapel_composition.tscn").instantiate()
	check(reopened.masonry_trim and reopened.get_node("Volumes/CoperturaPortale").masonry_trim,"stone treatment survives reopening")
	check(Apply._equal(reopened.openings,openings),"saved entrance unchanged")
	reopened.free(); undo.clear_history(); undo.free(); house.free()
	print("CHAPEL_COMPOSITION_CHECK failures=",failures)
	quit(0 if failures==0 else 1)

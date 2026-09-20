extends SceneTree
const House = preload("res://addons/house_builder/house.gd")
const Apply = preload("res://addons/house_builder/recipe_apply.gd")
const Recipe = preload("res://addons/house_builder/recipes/chapel.tres")
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1; push_error("CHAPEL_COMPOSITION: "+label)

func mesh_hits(visual: MeshInstance3D,frame: Transform3D,origin: Vector3, direction := Vector3.DOWN*12.0) -> Array[Vector3]:
	var hits: Array[Vector3]=[]
	for surface in visual.mesh.get_surface_count():
		var arrays := visual.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size() if not indices.is_empty() else positions.size(),3):
			var points: Array[Vector3]=[]
			for j in 3: points.append(frame*positions[indices[i+j] if not indices.is_empty() else i+j])
			var hit = Geometry3D.segment_intersects_triangle(origin,origin+direction,points[0],points[1],points[2])
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
	check(is_equal_approx(facade.portal_recess_depth,.76),"recipe enables the recessed portal")
	var portal_mesh: MeshInstance3D=facade.get_node("_GeneratedRecipeDetail/DetailMesh")
	var portal_faces: PackedVector3Array=portal_mesh.mesh.get_faces()
	check(is_equal_approx(facade.rose_recess_depth,.10),"rose recess is authored in the recipe")
	# A ray through an off-rib glass sector must meet glass behind the facade,
	# never a wall triangle left over the circular aperture.
	var mesh: ArrayMesh=portal_mesh.mesh
	var ray_start := Vector3(.37,facade.dimensions.y*.735+.23,1.0)
	var nearest_z := -INF
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for t in range(0,indices.size(),3):
			var hit = Geometry3D.segment_intersects_triangle(ray_start,ray_start-Vector3.BACK*2.0,vertices[indices[t]],vertices[indices[t+1]],vertices[indices[t+2]])
			if hit is Vector3: nearest_z=maxf(nearest_z,hit.z)
	check(nearest_z>-.14 and nearest_z<-.045,"glass is recessed and facade aperture is genuinely open")
	# Include the real upper body's projecting masonry, not just the facade.
	var lower_glass := Vector3(.12,facade.dimensions.y*.735-.65,1.0)
	var glass_hits := mesh_hits(portal_mesh,Transform3D.IDENTITY,lower_glass,Vector3.FORWARD*2.0)
	var wall_hits := mesh_hits(upper.get_node("_Generated/Walls"),facade.global_transform.affine_inverse()*upper.global_transform,lower_glass,Vector3.FORWARD*2.0)
	var glass_front := -INF; var wall_front := -INF
	for hit in glass_hits: glass_front=maxf(glass_front,hit.z)
	for hit in wall_hits: wall_front=maxf(wall_front,hit.z)
	check(not glass_hits.is_empty() and glass_front>wall_front+.015,"lower glass clears the actual upper-body masonry")
	var reveal_vertices := 0
	for vertex in portal_faces:
		if absf(vertex.x)<1.15 and vertex.y>.3 and vertex.y<2.3 and vertex.z<-.4: reveal_vertices+=1
	check(reveal_vertices>24,"deep jambs have actual geometry behind the facade")
	facade.rebuild()
	check(portal_faces==facade.get_node("_GeneratedRecipeDetail/DetailMesh").mesh.get_faces(),"portal regeneration is deterministic")
	check(house.masonry_trim and upper.masonry_trim,"stone treatment belongs to ordinary builder nodes")
	check(house.masonry_finish!=null and house.masonry_finish==upper.masonry_finish and house.masonry_finish==facade.masonry_finish,"one shared finish reaches nave, upper body and facade")
	var original_color: Color=house.masonry_finish.stone_color
	var old_builds: int=facade.build_count
	house.masonry_finish.stone_color=Color(.29,.28,.25)
	for i in 20: await physics_frame
	check(facade.build_count>old_builds,"editing the shared resource rebuilds its authored consumers")
	var finish_mat: ShaderMaterial=facade.get_node("_GeneratedRecipeDetail/DetailMesh").mesh.surface_get_material(0)
	check(finish_mat.get_shader_parameter("masonry_tint").is_equal_approx(Vector3(.29,.28,.25)),"Inspector color edit reaches the generated material")
	house.masonry_finish.stone_color=original_color
	for i in 20: await physics_frame
	check(Apply._equal(openings,house.openings),"original openings retained")
	var origin := Vector3(-4.0,12,.30)
	var hits := mesh_hits(house.get_node("_Generated/Roof"),Transform3D.IDENTITY,origin)
	hits.append_array(mesh_hits(upper.get_node("_Generated/Roof"),upper.transform,origin))
	check(not hits.is_empty(),"transverse roof covers the entrance axis")
	for hit in hits: check(hit.y>8.0,"buried main roof tiles removed from intersection")
	# Sample the actual stone cornice volume, not merely roof height at the valley.
	var trim_frame := facade.global_transform.affine_inverse()*upper.global_transform
	var original_roof := MeshInstance3D.new()
	original_roof.mesh=upper._build_roof()
	var removed_hits := 0
	for segment in preload("res://addons/house_builder/recipe_gothic.gd").gable_trim_segments(facade.dimensions):
		var a: Vector3=segment[0]; var b: Vector3=segment[1]
		var side := (b-a).normalized().cross(Vector3.FORWARD)
		for t in [.25,.5,.75,.9]:
			for offset in [-.06,0.0,.06]:
				var probe: Vector3 = a.lerp(b,t)+side*offset+Vector3.BACK
				for hit in mesh_hits(original_roof,trim_frame,probe,Vector3.FORWARD*2.0):
					if absf(hit.z)<.14: removed_hits+=1
				for hit in mesh_hits(upper.get_node("_Generated/Roof"),trim_frame,probe,Vector3.FORWARD*2.0):
					check(absf(hit.z)>=.14,"tiles do not penetrate the stone gable cornice")
	check(removed_hits>0,"regression probes detect the former tile/cornice overlap")
	# The upper body also has its own stone bargeboards behind the facade.
	for side in [-1.0,1.0]:
		var a := Vector3(side*upper.width*.5,upper.wall_height,upper.depth*.5)
		var b := Vector3(0,upper.wall_height+upper.roof_height,upper.depth*.5)
		for t in [.25,.5,.75,.9]:
			var probe: Vector3=a.lerp(b,t)+Vector3.BACK
			for hit in mesh_hits(upper.get_node("_Generated/Roof"),Transform3D.IDENTITY,probe,Vector3.FORWARD*2.0):
				check(absf(hit.z-upper.depth*.5)>.12,"tiles clear the upper body's own stone bargeboard")
	for point in upper.get_node("_Generated/Roof").mesh.get_faces():
		check(absf(point.z)<=upper.depth*.5-.124,"end tiles stop behind the stone verge instead of projecting through it")
	original_roof.free()
	var query := PhysicsShapeQueryParameters3D.new(); var capsule := CapsuleShape3D.new()
	capsule.radius=.3125; capsule.height=1.9481; query.shape=capsule; query.collision_mask=1
	for x in [-5.65,-5.3,-5.1]:
		query.transform=Transform3D(Basis.IDENTITY,Vector3(x,1.1,0))
		check(house.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"approach under the portal is clear at "+str(x))
	# Check the full reveal separately from the intentionally closed moving door.
	for z in [.08,-.20,-.46,-.70]:
		query.transform=Transform3D(Basis.IDENTITY,facade.to_global(Vector3(0,1.1,z)))
		for hit in house.get_world_3d().direct_space_state.intersect_shape(query):
			check(not facade.is_ancestor_of(hit.collider),"reveal keeps the full capsule corridor clear")
	house.set_cutaway(true,0,2.6)
	check(not upper.get_node("_Generated/Roof").visible,"cross roof disappears on entry")
	house.set_cutaway(false)
	undo.undo(); house.rebuild()
	check(not house.masonry_trim and not house.has_node("Volumes"),"Undo restores original structure")
	undo.redo(); house.rebuild()
	check(house.get_node("Volumes/CoperturaPortale")==upper,"Redo preserves authored component identity")
	var roof_builds: int=upper.build_count
	facade.position.z+=.04
	for i in 16: await physics_frame
	check(upper.build_count>roof_builds,"moving the facade updates the attached roof trim")
	facade.portal_recess_depth=.72
	facade.rose_recess_depth=.08
	var edited := Apply.propose(house,Recipe,27,94)
	check(edited.ok,"detail seed can change with edited facade")
	if edited.ok: Apply.apply(house,edited.after)
	check(is_equal_approx(facade.position.z,.04),"manual facade position survives detail regeneration")
	check(is_equal_approx(facade.portal_recess_depth,.72),"manual recess depth survives detail regeneration")
	check(is_equal_approx(facade.rose_recess_depth,.08),"manual rose recess survives regeneration")
	var packed := PackedScene.new(); check(packed.pack(house)==OK,"church packs")
	check(ResourceSaver.save(packed,"user://chapel_composition.tscn")==OK,"church saves")
	var reopened = load("user://chapel_composition.tscn").instantiate()
	check(reopened.masonry_trim and reopened.get_node("Volumes/CoperturaPortale").masonry_trim,"stone treatment survives reopening")
	check(reopened.masonry_finish==reopened.get_node("RecipeDetails/FacciataGotica").masonry_finish and reopened.masonry_finish==reopened.get_node("Volumes/CoperturaPortale").masonry_finish,"shared finish identity survives save and reopen")
	check(is_equal_approx(reopened.get_node("RecipeDetails/FacciataGotica").portal_recess_depth,.72),"edited recess depth survives reopening")
	check(Apply._equal(reopened.openings,openings),"saved entrance unchanged")
	check(is_equal_approx(reopened.get_node("RecipeDetails/FacciataGotica").rose_recess_depth,.08),"rose depth survives save and reopen")
	reopened.free(); undo.clear_history(); undo.free(); house.free()
	print("CHAPEL_COMPOSITION_CHECK failures=",failures)
	quit(0 if failures==0 else 1)

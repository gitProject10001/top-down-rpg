extends SceneTree
const Profile=preload("res://addons/house_builder/roof_profile.gd")
const Roof=preload("res://addons/house_builder/roof_mesh.gd")
const Apply=preload("res://addons/house_builder/recipe_apply.gd")
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1; push_error("CURVED_ROOF "+label)
func run() -> void:
	for curve in [0.0,.65,1.0]:
		check(is_equal_approx(Profile.height_at(3,3.4,curve,0),3.4),"ridge invariant")
		check(is_zero_approx(Profile.height_at(3,3.4,curve,3)),"eave invariant")
		check(is_equal_approx(Profile.height_at(3,3.4,curve,3.3),Profile.slope_at(3,3.4,curve,3)*.3),"overhang tangent")
	var generator:=Roof.new()
	var legacy:=generator.generate(6,7,3,3.4,27).get_faces()
	check(legacy==generator.generate(6,7,3,3.4,27,true,false,0).get_faces(),"zero identical")
	var curved:=generator.generate(6,7,3,3.4,27,true,false,.65).get_faces()
	check(curved==generator.generate(6,7,3,3.4,27,true,false,.65).get_faces(),"seed deterministic")
	for point in curved: check(point.is_finite(),"finite vertices")
	var start:=Time.get_ticks_usec()
	var scene: Node3D=load("res://scenes/dev/curved_roof_study.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	print("CURVED_ROOF_GENERATION two_houses_ms=",(Time.get_ticks_usec()-start)*.001)
	var house: Node3D=scene.get_node("Curved")
	start=Time.get_ticks_usec(); house.rebuild()
	print("CURVED_ROOF_GENERATION rebuild_ms=",(Time.get_ticks_usec()-start)*.001)
	var faces: PackedVector3Array=house._collision_shell.get_faces()
	for x in [-2.7,-1.5,-.2,.2,1.5,2.7]:
		var y: float=3.0+Profile.height_at(3,3.4,.65,x)-.08
		var found:=false
		for index in range(0,faces.size(),3):
			if Geometry3D.segment_intersects_triangle(Vector3(x,y,4),Vector3(x,y,3),faces[index],faces[index+1],faces[index+2]) is Vector3: found=true; break
		check(found,"gable collision follows curve without gaps")
	var openings: Array=house.openings.duplicate(true)
	var original: Node=house._generated
	house.wing_enabled=true; house.rebuild()
	check(house._generated==original and not house.roof_curvature_error().is_empty(),"unsupported combination retains last valid mesh")
	house.wing_enabled=false; house.rebuild()
	house.set_cutaway(true)
	check(not house._generated.get_node("Roof").visible,"cutaway")
	house.set_cutaway(false)
	var proposal: Dictionary=Apply.propose(scene.get_node("Straight"),load("res://addons/house_builder/recipes/curved_cottage.tres"),27,93)
	check(proposal.ok,"recipe validates")
	if proposal.ok:
		var undo:=UndoRedo.new(); undo.create_action("Curved roof")
		undo.add_do_method(Apply.apply.bind(scene.get_node("Straight"),proposal.after))
		undo.add_undo_method(Apply.apply.bind(scene.get_node("Straight"),proposal.before)); undo.commit_action()
		check(is_equal_approx(scene.get_node("Straight").roof_curvature,.65),"apply")
		undo.undo(); check(is_zero_approx(scene.get_node("Straight").roof_curvature),"undo")
		undo.redo(); check(is_equal_approx(scene.get_node("Straight").roof_curvature,.65),"redo")
		undo.undo(); undo.clear_history(); undo.free()
	var packed:=PackedScene.new(); packed.pack(scene)
	ResourceSaver.save(packed,"user://curved_roof_roundtrip.tscn")
	var restored: Node=load("user://curved_roof_roundtrip.tscn").instantiate()
	check(is_equal_approx(restored.get_node("Curved").roof_curvature,.65),"saved profile")
	check(restored.get_node("Curved").openings==openings,"retained openings")
	restored.free()
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1152,648)
		var camera: Camera3D=scene.get_node("Camera3D")
		camera.look_at(Vector3(0,2.7,0))
		for i in 100: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/curved_roof_comparison.png")
		camera.position=Vector3(4.6,5,20); camera.look_at(Vector3(4.6,3.2,0)); camera.size=11
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/curved_roof_gable.png")
	house.masonry_trim=true; house.wall_finish=1; house.rebuild()
	check(house._generated.get_node("Roof").mesh.get_faces().size()>0,"curved stone trim retains roof")
	if DisplayServer.get_name()!="headless":
		var camera: Camera3D=scene.get_node("Camera3D")
		camera.position=Vector3(13,11,15); camera.look_at(Vector3(4.6,3.2,0)); camera.size=12
		for i in 60: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/curved_roof_stone.png")
	print("CURVED_ROOF_RESULT failures=",failures)
	scene.free()
	await process_frame
	quit(0 if failures==0 else 1)

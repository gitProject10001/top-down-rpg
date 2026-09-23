extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
const Volume=preload("res://addons/house_builder/volume.gd")
const Roof=preload("res://addons/house_builder/roof_mesh.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures+=1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func finish(house: Node) -> void:
	var frames := 0
	while house._editor_running and frames<3000:
		await process_frame
		frames+=1
	check(not house._editor_running,"Editor generation did not finish")
func run() -> void:
	var roof := Roof.new()
	roof.begin(4.37,5.19,2.6,2.1,416522)
	var slices := 0
	while not roof.advance(500): slices+=1
	var original := roof.result.surface_get_arrays(0)
	var groups: Array=roof.result.get_meta("clip_groups")[0]
	check(groups.size()==roof.tile_count and groups[-1][1]==original[Mesh.ARRAY_INDEX].size(),"Tile groups do not cover the indexed roof")
	# Verify an actual disk hit after the deferred idle writer has completed.
	while not preload("res://scripts/generation_cache.gd")._pending_saves.is_empty():
		await create_timer(.1).timeout
	Roof.memory.clear()
	var cached := Roof.new().generate(4.37,5.19,2.6,2.1,416522)
	check(original==cached.surface_get_arrays(0),"Disk cache changed roof geometry")
	if FileAccess.file_exists("res://.godot/reference_roof.gd"):
		for parameters in [[4.37,5.19,2.6,2.1,416522,true,false,0.0],[4.2,5.0,2.6,2.1,45,true,true,0.0],[4.2,5.0,2.6,2.1,45,true,false,.3]]:
			var baseline=load("res://.godot/reference_roof.gd").new().callv("generate",parameters)
			var current=Roof.new().callv("generate",parameters)
			check(baseline.surface_get_arrays(0)==current.surface_get_arrays(0),"Resumable generator changed original roof geometry")
	var world := Node3D.new()
	root.add_child(world)
	var house := House.new()
	world.add_child(house)
	house.set_process(false)
	var initial := house.dimensions()
	var count: int=house.build_count
	house.begin_interactive_edit()
	var maximum := 0
	for i in 100:
		var start := Time.get_ticks_usec()
		house.width=4.2+i*.05
		house._process(.016)
		maximum=maxi(maximum,Time.get_ticks_usec()-start)
	check(house.build_count==count,"Dragging performed a full rebuild")
	check(maximum<100000,"Dragging exceeded 100 ms")
	house.set_dimensions(initial)
	house.end_interactive_edit()
	house._run_editor_rebuild()
	await finish(house)
	check(house.dimensions()==initial,"Cancel did not restore dimensions")
	check(house._preview==null and house._generated.visible,"Final mesh did not replace preview")
	# Interrupt a real slicing job with a newer edit; stale output must not publish.
	house.wing_enabled=true
	house.width=9.3
	house._run_editor_rebuild()
	await process_frame
	house.begin_interactive_edit()
	house.width=6.7
	await finish(house)
	house.end_interactive_edit()
	house._run_editor_rebuild()
	await finish(house)
	check(is_equal_approx(house.width,6.7),"Stale build overwrote latest edit")
	check(house._generated.name=="_Generated","Generated root lost stable name")
	check(house._generated.get_node("Roof").mesh.get_surface_count()>0,"Missing final roof")
	# Undo/redo are the same batched setters used by the gizmo's undo action.
	var undo := UndoRedo.new()
	undo.create_action("dimensions")
	undo.add_do_method(house.set_dimensions.bind(Vector4(7.2,5,2.6,2.1)))
	undo.add_undo_method(house.set_dimensions.bind(house.dimensions()))
	undo.commit_action()
	undo.undo()
	check(is_equal_approx(house.width,6.7),"Undo dimensions failed")
	undo.redo()
	check(is_equal_approx(house.width,7.2),"Redo dimensions failed")
	house.wing_enabled=false
	var volumes := Node3D.new(); volumes.name="Volumes"; house.add_child(volumes)
	var volume := Volume.new(); volume.attached=false; volumes.add_child(volume)
	volume.set_process(false)
	volume.begin_interactive_edit()
	check(house._editing,"Volume drag did not suspend its host")
	volume.width=2.7
	volume.end_interactive_edit()
	house._run_editor_rebuild()
	await finish(house)
	check(not house._editing and not volume._editing,"Drag state leaked")
	check(volume._preview==null and volume._generated.visible,"Volume preview did not finish")
	# Preview and generated nodes must never enter the authoring scene.
	house.owner=world
	house.begin_interactive_edit()
	var packed := PackedScene.new()
	check(packed.pack(world)==OK,"Packing scene during drag failed")
	for i in packed.get_state().get_node_count():
		check(not str(packed.get_state().get_node_name(i)).begins_with("_"),"Temporary geometry was serialized")
	house.end_interactive_edit()
	print("INCREMENTAL_GENERATION failures=",failures," drag_max_ms=",maximum/1000.0," roof_slices=",slices)
	undo.free()
	world.free()
	quit(failures)

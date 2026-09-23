@tool
extends SceneTree
## Run with --editor --script; changes are deliberately never saved.
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures+=1; push_error(message)
func _initialize() -> void: call_deferred("run")
func settle(house: Node) -> void:
	for i in 3000:
		await process_frame
		if not house._pending and not house._editor_running: return
	check(false,"Editor rebuild did not settle")
func run() -> void:
	await create_timer(2).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	var start := Time.get_ticks_usec()
	EditorInterface.open_scene_from_path("res://scenes/dev/integrated_landscape.tscn")
	for i in 120: await process_frame
	var scene := EditorInterface.get_edited_scene_root()
	check(scene!=null,"Scene did not open")
	print("EDITOR_OPEN_WITH_SETTLE ms=",(Time.get_ticks_usec()-start)/1000.0)
	var house: Node3D=null
	for node in scene.find_children("*","Node3D",true,false):
		if node.has_method("begin_interactive_edit") and not node.has_method("volume_host") and not node.has_method("footprint_vertices") and node.get("archetype_id")=="chapel":
			house=node
			break
	check(house!=null,"No editable house")
	await settle(house)
	var before: Vector4=house.dimensions()
	var count: int=house.build_count
	house.begin_interactive_edit()
	var frame_times: Array[float]=[]
	for i in 60:
		start=Time.get_ticks_usec()
		house.width=before.x+.1*sin(i*.1)
		await process_frame
		frame_times.append((Time.get_ticks_usec()-start)/1000.0)
	check(house.build_count==count,"Editor rebuilt detailed house while dragging")
	house.set_dimensions(before)
	house.end_interactive_edit()
	await settle(house)
	check(house._preview==null and house._generated.visible,"Editor did not publish final house")
	# Time the real chapel with presentation, interior plan and other scene
	# processing enabled; the isolated benchmark intentionally measures builders.
	var finalizations: Array[float]=[]
	for offset in [.011,.023,.041]:
		house.begin_interactive_edit()
		house.width=before.x+offset
		start=Time.get_ticks_usec()
		house.end_interactive_edit()
		await settle(house)
		for frame in 2: await process_frame
		var elapsed := (Time.get_ticks_usec()-start)/1000.0
		finalizations.append(elapsed)
		print("EDITOR_CHAPEL_FINALIZATION scene_settled_ms=",elapsed," phases=",house.build_timings)
		house.set_dimensions(before)
		await settle(house)
	finalizations.sort()
	print("EDITOR_CHAPEL_FINALIZATION_RESULT median_ms=",finalizations[1]," max_ms=",finalizations[-1])
	var layers := scene.get_node("ArtStudyLayers")
	var grass: Node=scene.art_direction.grass
	check(grass.work_mode,"Default editor mode is not Lavoro")
	layers.preview_quality=1
	check(not grass.work_mode and scene.art_direction.grass==grass,"Quality switch rebuilt the presentation")
	layers.preview_quality=0
	frame_times.sort()
	print("EDITOR_PERFORMANCE failures=",failures," drag_p95_ms=",frame_times[int(frame_times.size()*.95)]," drag_max_ms=",frame_times[-1])
	quit(failures)

extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(true): freeze(child)
func run() -> void:
	var source=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
	var chapel: Node3D
	for node in source.find_children("*","Node3D",true,false):
		if node is House and node.archetype_id=="chapel": chapel=node; break
	assert(chapel!=null)
	chapel.get_parent().remove_child(chapel)
	source.free()
	var simple := House.new()
	var wing := House.new(); wing.wing_enabled=true
	var with_volume := House.new(); with_volume.width=6.; with_volume.depth=8.; with_volume.wall_height=6.
	var container := Node3D.new(); container.name="Volumes"; with_volume.add_child(container)
	var accessory=preload("res://addons/house_builder/volume.gd").new()
	accessory.width=2.7; accessory.depth=3.; accessory.roof_height=1.2
	container.add_child(accessory)
	var fixtures := {"simple":simple,"wing":wing,"volume":with_volume,"chapel":chapel}
	var reps := 20
	var edit_kind := "width"
	var dimension_step := .0037
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reps="): reps=maxi(1,int(arg.get_slice("=",1)))
		if arg.begins_with("--edit="): edit_kind=arg.get_slice("=",1)
		if arg.begins_with("--step="): dimension_step=float(arg.get_slice("=",1))
	if "--golden" in OS.get_cmdline_user_args() or "--verify" in OS.get_cmdline_user_args(): dimension_step=.037
	for label in fixtures:
		var house: Node3D=fixtures[label]
		root.add_child(house)
		for i in 3: await process_frame
		freeze(house)
		var width: float=house.width
		var initial_errors: Dictionary={}
		for volume in house.authored_volumes(): initial_errors[volume]=volume.volume_error()
		var times: Array[float]=[]
		var cpu_times: Array[float]=[]
		var waits: Array[float]=[]
		if "--chapel" in OS.get_cmdline_user_args() and label!="chapel":
			house.free(); continue
		for i in reps:
			house.begin_interactive_edit()
			match edit_kind:
				"opening":
					var changed_openings: Array[Dictionary]=house.openings.duplicate(true)
					if changed_openings.is_empty(): changed_openings.append({"kind":"window","wall":1,"u":0.,"y":1.5,"width":.8,"height":1.1})
					changed_openings[0]["width"]=.8+.007*i
					house.openings=changed_openings
				"roof": house.roof_height=2.1+.017*(i+1)
				_: house.width=width+dimension_step*(i+1)
			house.end_interactive_edit()
			for volume in house.authored_volumes():
				if initial_errors[volume].is_empty() and not volume.volume_error().is_empty():
					failures+=1; push_error("Benchmark edit invalidated volume: "+volume.volume_error())
			var builds: int=house.build_count
			var dependent_counts: Dictionary={}
			for volume in house.authored_volumes(): dependent_counts[volume]=volume.build_count
			var start := Time.get_ticks_usec()
			house._run_editor_rebuild()
			var frames := 0
			while house._editor_running and frames<10000:
				await process_frame
				frames+=1
			var elapsed := (Time.get_ticks_usec()-start)/1000.0
			times.append(elapsed)
			cpu_times.append(house.build_timings.get("cpu_total_ms",0.))
			waits.append(house.build_timings.get("frame_wait_ms",0.))
			if house._editor_running: failures+=1; push_error("Finalization timed out")
			var dependent_builds: Dictionary={}
			for volume in house.authored_volumes(): dependent_builds[str(volume.name)]=volume.build_count-dependent_counts[volume]
			print("EDIT_SAMPLE ",label," width=",house.width," wall_ms=",elapsed," frames=",frames," builds=",house.build_count-builds," dependent_builds=",dependent_builds," phases=",house.build_timings)
			if "--counters" in OS.get_cmdline_user_args(): print("EDIT_COUNTERS ",house.build_counters)
			if i==0 and "--golden" in OS.get_cmdline_user_args(): save_meshes(house,label)
			if i==0 and "--verify" in OS.get_cmdline_user_args() and label!="volume":
				var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://.godot/edit_golden/"+label+"/manifest.json"))
				for path in manifest:
					if "@" in path: continue # unrelated engine-generated furniture names are unstable
					var node=house.get_node_or_null(path)
					print("VERIFY ",label," ",path)
					if node==null or not preload("res://tools/check_mesh_join_equivalence.gd").equivalent(load(manifest[path]),node.mesh): failures+=1
		times.sort(); cpu_times.sort(); waits.sort()
		print("EDIT_RESULT ",label," median_ms=",times[times.size()/2]," p95_ms=",times[mini(times.size()-1,ceili(times.size()*.95)-1)]," cpu_median_ms=",cpu_times[cpu_times.size()/2]," wait_median_ms=",waits[waits.size()/2]," samples=",reps)
		house.free()
	if "--flush-cache" in OS.get_cmdline_user_args():
		while not preload("res://scripts/generation_cache.gd")._pending_saves.is_empty(): await create_timer(.1).timeout
	await process_frame
	quit(failures)
func save_meshes(house: Node, label: String) -> void:
	var directory := "res://.godot/edit_golden/"+label
	DirAccess.make_dir_recursive_absolute(directory)
	var records := {}
	var todo: Array[Node]=[house]
	while not todo.is_empty():
		var node: Node=todo.pop_back()
		for child in node.get_children(true): todo.append(child)
		if node is MeshInstance3D and node.mesh!=null:
			var path := str(house.get_path_to(node))
			var file := directory+"/"+str(records.size())+".res"
			ResourceSaver.save(node.mesh,file)
			records[path]=file
	var output := FileAccess.open(directory+"/manifest.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(records))

extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
const Volume=preload("res://addons/house_builder/volume.gd")
const Finish=preload("res://addons/house_builder/masonry_finish.gd")
const Cache=preload("res://scripts/generation_cache.gd")
var failures:=0
func _initialize(): call_deferred("run")
func check(value: bool, message: String):
 if not value: failures+=1; push_error(message)
func finish(house):
 house._run_editor_rebuild()
 while house._editor_running: await process_frame
func run():
 var world:=Node3D.new(); root.add_child(world)
 var house:=House.new(); house.masonry_finish=Finish.new(); house.wall_finish=1
 world.add_child(house); house.set_process(false)
 var containers:=Node3D.new(); containers.name="Volumes"; house.add_child(containers)
 var volume:=Volume.new(); volume.attached=false; volume.position.x=10
 containers.add_child(volume); volume.set_process(false)
 house.rebuild()
 var count: int=house.build_count
 var roof=house._generated.get_node("Roof").mesh
 var walls=house._generated.get_node("Walls").mesh
 house.masonry_finish.stone_color=Color(.2,.4,.3)
 house.masonry_finish.weathering=.8
 check(house.build_count==count and house._generated.get_node("Walls").mesh==walls,"Material edit rebuilt geometry")
 var volume_count: int=volume.build_count
 var volume_root=volume._generated
 house.openings=[{"kind":"window","wall":0,"u":0.,"y":1.4,"width":.8,"height":.8}]
 await finish(house)
 check(house._generated.get_node("Roof").mesh==roof,"Opening invalidated an unchanged roof")
 check(volume.build_count==volume_count and volume._generated==volume_root,"Unchanged independent volume rebuilt")
 house.masonry_finish.block_size=Vector2(.6,.4)
 check(house._pending,"Distribution edit did not invalidate masonry")
 await finish(house)
 check(house._generated.get_node("Walls").mesh!=walls,"Distribution edit reused stale masonry")
 # Save/reopen only authored state, then compare a new cold reconstruction.
 house.owner=world; containers.owner=world; volume.owner=world
 var packed:=PackedScene.new(); check(packed.pack(world)==OK,"Pack failed")
 var reopened=packed.instantiate(); root.add_child(reopened)
 var restored=reopened.get_child(0)
 check(restored.openings==house.openings and restored.dimensions()==house.dimensions(),"Reopen changed authored state")
 check(restored._generated.get_node("Roof").mesh.surface_get_arrays(0)==house._generated.get_node("Roof").mesh.surface_get_arrays(0),"Reopen changed roof")
 # Idle disk writer must not enter a finalization job.
 var file:=Cache.path_for("edit_test",str(Time.get_ticks_usec()),".res")
 Cache.hold_writes(house); Cache.queue_save(roof,file); Cache._flush_save()
 check(not FileAccess.file_exists(file),"Disk write ran while editor work was active")
 Cache.release_writes(house)
 world.free(); reopened.free()
 print("EDIT_DEPENDENCIES failures=",failures)
 quit(failures)

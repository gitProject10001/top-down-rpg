extends Node
var failures: Array[String]=[]
var scene: Node
var moving_frames: Array[float]=[]
func check(ok: bool, text: String) -> void:
 if not ok: failures.append(text); push_error(text)
func _ready() -> void: call_deferred("run")
func run() -> void:
 var start:=Time.get_ticks_msec()
 scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
 scene.combat_encounter_enabled=false
 get_tree().root.add_child(scene)
 for i in 90: await get_tree().process_frame
 print("WORLD_LOAD_MS ",Time.get_ticks_msec()-start)
 var view: Node=scene.get_node("GameplayPreviewRig/Pixel/View")
 var cycle: Node=scene.day_cycle
 cycle.clock_paused=true
 cycle.hour=23.99; cycle.speed=1; cycle.clock_paused=false; cycle.advance(2)
 check(cycle.hour<1,"midnight wraps")
 cycle.hour=.01; cycle.speed=-1; cycle.advance(2); check(cycle.hour>23,"reverse wraps")
 cycle.speed=1; cycle.hour=10; cycle.advance(1800); check(absf(cycle.hour-10)<.001,"30 minute day")
 cycle.clock_paused=true
 var ground: Node=view.get_node("TerrenoComposto/Superficie")
 check(ground.world_bounds.size==Vector2(304,288),"4x bounds")
 check(view.get_node("WorldStream").ground_node()==ground,"World owns terrain contract")
 var lake: Node=view.get_node("Lago")
 check(lake.depth_at(Vector2(45,0))>2,"deep lake")
 check(lake._depth_collision!=null,"deep water collision")
 for p in [Vector2(-90,45),Vector2(40,80),Vector2(140,45),Vector2(-65,-78)]:
  var hit: Dictionary=scene.player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,60,p.y),Vector3(p.x,-20,p.y)))
  check(not hit.is_empty(),"terrain support "+str(p))
 for name in ["NordOvest","NordEst","CimeNord","Ovest","PromontorioOvest","PromontorioEst"]:
  var cliff: Node3D=view.get_node(name+"/ContinuousCliff")
  var curve: Curve3D=cliff.guide
  var end:=curve.sample_baked(curve.get_baked_length())
  var direction: Vector3=(end-curve.sample_baked(curve.get_baked_length()-.1)).normalized()
  var front:=Vector3(-direction.z,0,direction.x)
  for fraction in [.1,.5,.9]:
   var p: Vector3=end+direction*cliff.effective_ramp_length()*fraction-front*(cliff.wall_depth+cliff.raised_zone_depth*.5)
   var hit: Dictionary=scene.player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*60,p-Vector3.UP*20))
   check(not hit.is_empty() and absf(hit.position.y-ground.height_at(p.x,p.z))<.12,name+" ramp surface agrees with World")
 # Walk the northern ramp with the actual gameplay controller.
 var ramp: Node3D=view.get_node("NordOvest/ContinuousCliff")
 var curve: Curve3D=ramp.guide
 var end:=curve.sample_baked(curve.get_baked_length())
 var direction: Vector3=(end-curve.sample_baked(curve.get_baked_length()-.1)).normalized()
 var side:=Vector3(-direction.z,0,direction.x)
 var lower: Vector3=end+direction*ramp.effective_ramp_length()*.96-side*(ramp.wall_depth+ramp.raised_zone_depth*.5)
 var upper: Vector3=end+direction*ramp.effective_ramp_length()*.08-side*(ramp.wall_depth+ramp.raised_zone_depth*.5)
 lower.y=ground.height_at(lower.x,lower.z); upper.y=ground.height_at(upper.x,upper.z)
 scene.player.position=lower+Vector3.UP*.5; scene.player.velocity=Vector3.ZERO
 for i in 30: await get_tree().physics_frame
 check(await move_to(upper,.5,900),"player climbs northern ramp")
 check(await move_to(lower,.5,900),"player descends northern ramp")
 moving_frames.sort(); print("WORLD_MOVING_FRAME_MS median=",moving_frames[moving_frames.size()/2]," p95=",moving_frames[int(moving_frames.size()*.95)]," max=",moving_frames[-1])
 # Save/reload the authoring resources, and exercise the same Undo API as World.
 var packed:=PackedScene.new()
 var data:=Node3D.new(); var author=preload("res://addons/world_editor/integrated_ground.gd").new()
 data.add_child(author); author.owner=data; author.source_mesh=ground.source_mesh
 author.world_plan=ground.world_plan; author.height_edits.assign([{"kind":"raise","position":Vector2(130,50),"radius":4.0,"value":1.0}])
 check(packed.pack(data)==OK,"pack authored World data")
 check(ResourceSaver.save(packed,"user://expanded_authoring_test.tscn")==OK,"save World data")
 var restored=load("user://expanded_authoring_test.tscn").instantiate()
 check(restored.get_child(0).height_edits==author.height_edits,"reopen preserves manual edits")
 check(restored.get_child(0).world_plan.bounds==ground.world_plan.bounds,"reopen preserves World plan")
 restored.free(); data.free()
 var old: Array[Dictionary]=ground.height_edits.duplicate(true)
 var modified: Array[Dictionary]=old.duplicate(true); modified.append({"kind":"raise","position":Vector2(130,50),"radius":4.0,"value":1.0})
 var undo:=UndoRedo.new(); undo.create_action("World terrain sample")
 undo.add_do_method(ground.apply_edits.bind(modified)); undo.add_undo_method(ground.apply_edits.bind(old)); undo.commit_action()
 check(ground.height_edits==modified,"World edit applied"); undo.undo(); check(ground.height_edits==old,"World Undo restores manual data")
 undo.redo(); check(ground.height_edits==modified,"World Redo restores edit"); undo.undo(); undo.free()
 check(ResourceSaver.save(cycle.profile,"user://expanded_day_profile.tres")==OK,"save cycle profile")
 check(load("user://expanded_day_profile.tres").real_minutes==30,"reopen cycle profile")
 var f6:=InputEventKey.new(); f6.keycode=KEY_F6; f6.pressed=true
 cycle._input(f6); check(cycle.panel.visible,"F6 opens clock UI"); cycle._input(f6)
 # Geometric water limit is a vertical collider, not an invisible floor.
 var water_hit: Dictionary=scene.player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(65,.6,12),Vector3(65,.6,-28)))
 check(not water_hit.is_empty() and water_hit.collider.name=="DeepWaterLimit","deep-water entry blocked")
 # A real paused dialog must stop the solar clock as well.
 var manager: Node=scene.npc_dialogues
 cycle.clock_paused=false
 manager.open_dialogue(manager.actors[0]); var before: float=cycle.hour
 for i in 8: await get_tree().process_frame
 check(cycle.hour==before,"dialogue pauses clock")
 manager.close_dialogue(); cycle.clock_paused=true
 for h in [5.5,12.0,20.5,0.0]:
  cycle.hour=h
  scene.art_direction.apply(not scene.art_direction.enabled); cycle.apply_time()
  check(cycle.hour==h,"F7 retains hour")
  scene.art_direction.apply(true); cycle.apply_time()
  if not scene.overview: scene.toggle_overview()
  for i in 30: await get_tree().process_frame
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png("res://captures/world_hour_%02d.png"%int(h))
 cycle.hour=12; scene.toggle_overview()
 scene.player.position=Vector3(-116,1,91)
 scene.camera._target=null; scene.camera._focus=Vector3(-129,2,103); scene.camera.ortho_size=26; scene.camera._apply(true)
 for i in 90: await get_tree().process_frame
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://captures/world_coast.png")
 var rid: RID=scene.player.get_viewport().get_viewport_rid()
 RenderingServer.viewport_set_measure_render_time(rid,true)
 var gpu: Array[float]=[]; var cpu: Array[float]=[]
 var frames: Array[float]=[]; var last:=Time.get_ticks_usec()
 for i in 180:
  await get_tree().process_frame
  gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid)); cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
  var now:=Time.get_ticks_usec(); frames.append((now-last)/1000.0); last=now
 gpu.sort(); cpu.sort(); print("WORLD_RENDER_MS GPU median=",gpu[90]," p95=",gpu[171]," CPU median=",cpu[90]," p95=",cpu[171])
 frames.sort(); print("WORLD_FRAME_MS median=",frames[90]," p95=",frames[171])
 scene.camera._target=scene.player
 for spot in [["cliff",Vector3(-100,1,-73)],["lake",Vector3(107,1,10)]]:
  scene.player.position=spot[1]
  if spot[0]=="cliff":
   scene.camera.ortho_size=35
   scene.camera.focus_height=7
  else:
   scene.camera.ortho_size=17.5
   scene.camera.focus_height=1.1
  for i in 120: await get_tree().process_frame
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png("res://captures/world_"+spot[0]+".png")
 print("EXPANDED_WORLD_RESULT ",failures)
 scene.queue_free()
 for i in 3: await get_tree().process_frame
 get_tree().quit(0 if failures.is_empty() else 1)

func release() -> void:
 for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
func move_to(target: Vector3, tolerance := .22, limit := 260) -> bool:
 var last:=Time.get_ticks_usec()
 for frame in limit:
  var delta: Vector3 = target - scene.player.global_position
  delta.y = 0
  if delta.length() < tolerance: release(); return true
  var raw := delta.normalized().rotated(Vector3.UP, -scene.camera.global_rotation.y)
  for pair in [["move_left", -raw.x], ["move_right", raw.x], ["move_up", -raw.z], ["move_down", raw.z]]:
   if pair[1] > 0: Input.action_press(pair[0], pair[1])
   else: Input.action_release(pair[0])
  await get_tree().physics_frame
  var now:=Time.get_ticks_usec(); moving_frames.append((now-last)*.001); last=now
 release()
 return false

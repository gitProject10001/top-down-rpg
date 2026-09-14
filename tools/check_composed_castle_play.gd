extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
 for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
 var request=preload("res://addons/castle_generator/request.gd").new()
 request.seed_value=17; request.minimum_span=Vector2(26,26); request.maximum_span=request.minimum_span
 var plan=preload("res://addons/castle_generator/planner.gd").generate(request).plan
 var group=preload("res://addons/castle_generator/materializer.gd").create(plan)
 var keep=group.get_node("Mastio"); keep.rotation.y=0.025; keep.position.z+=0.1
 var container := Node3D.new(); container.name="Volumes"; keep.add_child(container)
 var volume=preload("res://addons/house_builder/volume.gd").new(); volume.name="AccessorioTest"; volume.attached=false; volume.width=2; volume.depth=2; volume.position.z=2; container.add_child(volume)
 var service=preload("res://addons/castle_generator/regeneration.gd")
 var proposal=service.propose(group,plan); assert(not proposal.has("error"),str(proposal))
 service.apply(group,proposal.updates,proposal.plan,proposal.baseline)
 own(group,group)
 var packed := PackedScene.new(); assert(packed.pack(group)==OK); group.free()
 var play=preload("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
 for i in 30: await physics_frame
 await play._walk(Vector3(13,0,2.6),100)
 var gate=play.nearest_door(); assert(gate!=null)
 gate.toggle(play.player.global_position)
 for i in 45: await physics_frame
 await play._walk(Vector3(13,0,-3),250)
 assert(play.player.position.z<-2.5,"Generated courtyard remains reachable after regeneration")
 var actual=play.authored_group.get_node("Mastio")
 assert(actual.rotation.y>0.02 and actual.has_node("Volumes/AccessorioTest"))
 var from: Vector3=actual.to_global(Vector3(actual.width*0.5+1,1,0))
 var to: Vector3=actual.to_global(Vector3(actual.width*0.5-1,1,0))
 assert(not play.player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to)).is_empty(),"Rotated wall has collision")
 if DisplayServer.get_name()!="headless":
  var preview=preload("res://addons/castle_generator/footprint_preview.gd").new(); preview.shapes=proposal.footprints; preview.span=proposal.span
  var ui := CanvasLayer.new(); root.add_child(ui); ui.add_child(preview); preview.position=Vector2(20,20); preview.size=Vector2(400,310)
  await process_frame; await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://captures/balcony_attachment/composed_castle_footprints_play.png")
 print("COMPOSED_CASTLE_REGEN_ROTATION_ACCESSORY_GATE_COLLISION_PLAY_OK")
 quit()

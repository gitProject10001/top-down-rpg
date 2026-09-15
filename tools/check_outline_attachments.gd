extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var tower=preload("res://addons/house_builder/polygon_tower.gd").new(); tower.width=10; tower.depth=10
 var openings: Array[Dictionary]=[{"kind":"door","wall":0,"width":1.2,"height":2.1,"open":true}]
 tower.openings=openings; root.add_child(tower)
 var plan=preload("res://addons/house_builder/tower_interior_factory.gd").create(); tower.add_child(plan)
 var wall=preload("res://addons/house_builder/curtain_wall.gd").new(); wall.connect_to_tower=true; wall.tower_face=2; wall.depth=2; tower.add_child(wall)
 var stairs=preload("res://addons/house_builder/exterior_stair.gd").new(); stairs.side=2; tower.add_child(stairs)
 for i in 12: await process_frame
 var old_floor: int=plan._floors.get_instance_id()
 var old_transform: Transform3D=wall.transform
 var outline=tower.regular_outline()
 for i in outline.size(): outline[i].x+=outline[i].y*0.25
 tower.custom_outline=outline
 for i in 15: await process_frame
 assert(plan._floors.get_instance_id()!=old_floor,"Floor reacts without width/depth change")
 assert(wall.transform!=old_transform and wall.connection_error().is_empty(),"Curtain follows deformed edge")
 assert(stairs.transform.is_equal_approx(tower.stair_frame()),"Exterior stair follows its edge")
 assert(tower.openings==openings,"Authored opening record preserved")
 await physics_frame; await physics_frame
 var ray=PhysicsRayQueryParameters3D.create(tower.wall_point(0,0,1,0.6),tower.wall_point(0,0,1,-0.6))
 assert(root.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"Door collision follows changed face")
 var small=tower.regular_outline()
 for i in small.size(): small[i]*=0.3
 assert(tower.outline_error(small).is_empty())
 assert(not tower.outline_attachment_error(small).is_empty(),"Small valid polygon cannot shrink authored door")
 tower.free(); print("OUTLINE_FLOOR_CURTAIN_STAIRS_DOOR_REFRESH_OK"); quit()

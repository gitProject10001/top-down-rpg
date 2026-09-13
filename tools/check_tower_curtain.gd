extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func run() -> void:
	var tower=preload("res://addons/house_builder/polygon_tower.gd").new()
	tower.width=8; tower.depth=8; tower.wall_height=5.6; tower.roof_height=1; root.add_child(tower)
	var wall=preload("res://addons/house_builder/curtain_wall.gd").new(); wall.name="Cortina"; wall.width=8; wall.connect_to_tower=true
	tower.add_child(wall); wall.owner=tower; await settle()
	assert(wall.connection_error().is_empty() and is_equal_approx(wall.wall_height,5.6))
	var space=root.get_world_3d().direct_space_state
	var gap=PhysicsRayQueryParameters3D.create(Vector3(3.3,5.95,0),Vector3(4.7,5.95,0))
	assert(space.intersect_ray(gap).is_empty(),"Both parapets open at connection")
	var seam=PhysicsRayQueryParameters3D.create(Vector3(4,7,0),Vector3(4,5.4,0))
	assert(not space.intersect_ray(seam).is_empty(),"Walkway continuous at seam")
	tower.width=9; tower.wall_height=6; wall.tower_face=1; await settle()
	assert(is_equal_approx(wall.wall_height,6))
	assert((wall.transform*Vector3(-wall.width*0.5,0,0)).distance_to(tower.wall_point(1,0,0,-0.1))<0.001,"Endpoint follows resized oblique face")
	var packed := PackedScene.new(); assert(packed.pack(tower)==OK)
	var copy=packed.instantiate(); assert(copy.get_node("Cortina").connect_to_tower and copy.get_node("Cortina").tower_face==1); copy.free()
	wall.connect_to_tower=false; await settle()
	assert(tower.connection_spans(1,[Vector2(-1,1)]).size()==1,"Disconnect closes tower parapet")
	wall.connect_to_tower=true; await settle(); tower.remove_child(wall); wall.free(); await settle()
	assert(tower.connection_spans(1,[Vector2(-1,1)]).size()==1)
	tower.free(); print("TOWER_CURTAIN_SEAM_RESIZE_OBLIQUE_DISCONNECT_SAVE_OK"); quit()

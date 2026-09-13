extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var tower=preload("res://addons/house_builder/polygon_tower.gd").new()
	tower.width=6.0; tower.depth=6.0; tower.wall_height=5.6; tower.roof_height=1.0
	var records: Array[Dictionary]=[{"kind":"door","wall":7,"width":1.2,"height":2.1,"open":true}]
	tower.openings=records; root.add_child(tower); tower.rebuild()
	await physics_frame; await physics_frame
	assert(tower.contains_footprint(Vector3.ZERO))
	assert(not tower.contains_footprint(Vector3(2.9,0,2.9)),"Clipped corner is outdoors")
	for wall in 8:
		var origin: Vector3=tower.wall_point(wall,0,1,2)
		var hit: Dictionary=tower.hit_wall(origin,-tower.wall_normal(wall))
		assert(hit.wall==wall,"Placement ray selects every face including 4..7")
	var space=root.get_world_3d().direct_space_state
	var hole=PhysicsRayQueryParameters3D.create(tower.wall_point(7,0,1,0.6),tower.wall_point(7,0,1,-0.6))
	assert(space.intersect_ray(hole).is_empty(),"Open oblique door cuts wall and collision")
	var solid=PhysicsRayQueryParameters3D.create(tower.wall_point(7,0,3,0.6),tower.wall_point(7,0,3,-0.6))
	assert(not space.intersect_ray(solid).is_empty(),"Wall above oblique opening remains solid")
	var corner=PhysicsRayQueryParameters3D.create(Vector3(2.9,8,2.9),Vector3(2.9,-1,2.9))
	assert(space.intersect_ray(corner).is_empty(),"Floor and roof do not fill clipped corners")
	var stairs=preload("res://addons/house_builder/exterior_stair.gd").new(); stairs.side=2; tower.add_child(stairs)
	assert(tower.stair_wall()==6 and tower.stair_frame().basis.z.dot(Vector3.LEFT)>0.99)
	tower.width=7.0; tower.depth=5.8; tower.rebuild()
	var packed := PackedScene.new(); assert(packed.pack(tower)==OK)
	var copy=packed.instantiate(); assert(copy.width==7.0 and copy.depth==5.8 and copy.openings[0].wall==7)
	copy.free(); tower.free(); print("POLYGON_TOWER_FACES_OBLIQUE_HOLE_COLLISION_FOOTPRINT_SAVE_OK"); quit()

extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for sides in [8,12,16]:
  var tower=preload("res://addons/house_builder/polygon_tower.gd").new()
  tower.face_count=sides; tower.width=10; tower.depth=9; tower.wall_height=5
  var records: Array[Dictionary]=[{"kind":"door","wall":sides-1,"width":1.0,"height":2.1,"open":true}]
  tower.openings=records
  root.add_child(tower); tower.rebuild()
  await physics_frame; await physics_frame
  assert(tower.wall_count()==sides and tower.footprint_vertices().size()==sides)
  for wall in sides:
   var hit=tower.hit_wall(tower.wall_point(wall,0,1,2),-tower.wall_normal(wall))
   assert(hit.wall==wall)
  var space=root.get_world_3d().direct_space_state
  var query=PhysicsRayQueryParameters3D.create(tower.wall_point(sides-1,0,1,0.6),tower.wall_point(sides-1,0,1,-0.6))
  assert(space.intersect_ray(query).is_empty(),"Door must cut oblique face")
  query=PhysicsRayQueryParameters3D.create(Vector3(0,8,0),Vector3(0,4,0))
  assert(not space.intersect_ray(query).is_empty(),"Roof slab must remain solid")
  var packed=PackedScene.new(); assert(packed.pack(tower)==OK)
  var copy=packed.instantiate(); assert(copy.face_count==sides and copy.openings[0].wall==sides-1)
  copy.free(); tower.free()
 print("SEGMENTED_TOWER_FACES_DOORS_ROOF_SAVE_OK")
 quit()

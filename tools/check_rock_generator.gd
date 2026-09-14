extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var script=preload("res://addons/rock_builder/rock.gd")
 var rock=script.new(); var signatures := {}
 for seed_value in 12:
  rock.rock_seed=seed_value; rock.strata=1+seed_value%6
  var a=rock.generate(); var b=rock.generate()
  assert(a.mesh.get_faces()==b.mesh.get_faces())
  var faces: PackedVector3Array=a.mesh.get_faces()
  signatures[hash(faces)]=true
  assert(a.triangles<=400 and a.mesh.get_surface_count()==1)
  for i in range(0,faces.size(),3):
   assert(faces[i].is_finite() and (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length_squared()>0.00000001)
  assert(a.hull.size()<=160)
 assert(signatures.size()==12)
 root.add_child(rock)
 for frame in 3: await physics_frame
 var ray := PhysicsRayQueryParameters3D.create(Vector3(0,10,0),Vector3(0,-1,0))
 assert(not rock.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())
 var packed := PackedScene.new(); assert(packed.pack(rock)==OK)
 var copy=packed.instantiate(); assert(copy.rock_seed==rock.rock_seed and copy.strata==rock.strata); copy.free()
 rock.collisions_enabled=false
 for frame in 3: await physics_frame
 assert(rock.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())
 rock.free(); print("ROCK_SEEDS_DETERMINISM_VALID_TRIANGLES_BUDGET_OK"); quit()

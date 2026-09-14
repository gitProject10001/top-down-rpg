extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for sides in [8,12,16]:
  var tower=preload("res://addons/house_builder/polygon_tower.gd").new()
  tower.face_count=sides; tower.width=8; tower.depth=7; tower.wall_height=5; tower.roof_height=3; tower.tower_roof=2
  root.add_child(tower); tower.rebuild()
  var roof: ArrayMesh=tower._generated.get_node("Roof").mesh
  assert(roof.get_surface_count()==1)
  var arrays=roof.surface_get_arrays(0)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  assert(indices.size()/3<30000)
  for i in range(0,indices.size(),3):
   var a=vertices[indices[i]]; var b=vertices[indices[i+1]]; var c=vertices[indices[i+2]]
   assert(a.is_finite() and (b-a).cross(c-a).length()>0.0000001,"Nondegenerate roof triangles")
  assert(vertices==tower._build_roof().surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
  assert(not tower.roof_is_walkable() and not tower.roof_access_error().is_empty())
  await physics_frame; await physics_frame
  var hit=root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1,10,0),Vector3(1,4,0)))
  assert(not hit.is_empty() and hit.position.y>6,"Sloped roof collision")
  var packed=PackedScene.new(); assert(packed.pack(tower)==OK)
  var copy=packed.instantiate(); assert(copy.tower_roof==2 and copy.face_count==sides); copy.free()
  tower.tower_roof=0; tower.rebuild(); assert(tower.roof_is_walkable())
  var stairs=preload("res://addons/house_builder/exterior_stair.gd").new(); tower.add_child(stairs)
  tower.tower_roof=2; assert(tower.tower_roof==0,"Do not replace a roof used by a staircase")
  tower.free()
 print("DOMED_TOWERS_GEOMETRY_COLLISION_SAVE_ACCESS_OK")
 quit()

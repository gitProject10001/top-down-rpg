extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for sides in [8,12,16]:
  var tower=preload("res://addons/house_builder/polygon_tower.gd").new(); tower.face_count=sides; tower.width=8; tower.depth=8
  root.add_child(tower)
  var plan=preload("res://addons/house_builder/tower_interior_factory.gd").create(); tower.add_child(plan)
  var room=preload("res://addons/house_builder/plan_element.gd").new(); room.name="CameraTest"; room.kind=0; room.dimensions=Vector3(0.8,2.6,0.8); room.stable_id="room_test"
  plan.get_node("PianoTerra").add_child(room)
  assert(room.containment_error().is_empty())
  room.position=Vector3(3.4,0,3.4)
  assert(not room.containment_error().is_empty(),"Bounding rectangle corner is outside polygon")
  assert(not room._get_configuration_warnings().is_empty())
  var previous: Array=plan.level_records(0)
  var result: Array=plan.checked_proposal(0,previous)
  assert(plan.generation_failed and result==previous and "CameraTest" in plan.generation_report)
  assert(room.position==Vector3(3.4,0,3.4),"Validation must preserve manual placement")
  room.kind=1; room.dimensions=Vector3(3,2.6,0.2); room.position=Vector3(0,0,3.3); room.rotation.y=PI/4
  assert(not room.containment_error().is_empty(),"Rotated wall end crosses boundary")
  room.position=Vector3.ZERO
  assert(room.containment_error().is_empty())
  tower.position=Vector3(30,2,-10); tower.rotation.y=0.7
  assert(room.containment_error().is_empty(),"World pose must not alter local containment")
  var level=room.get_parent(); level.position.x=6
  assert(not room.containment_error().is_empty(),"Parent transform must be included")
  level.position.x=0; room.scale=Vector3(4,1,4)
  assert(not room.containment_error().is_empty(),"Live scaled wall must be checked")
  room.scale=Vector3.ONE
  assert(room.containment_error().is_empty(),"Warning clears when corrected")
  var furniture=preload("res://addons/house_builder/plan_element.gd").new(); furniture.kind=3; furniture.stable_id="prop_test"; furniture.name="ArredoTest"; furniture.dimensions=Vector3(1,1,1)
  room.kind=0; room.rotation=Vector3.ZERO; room.dimensions=Vector3(2,2.6,2)
  room.add_child(furniture)
  assert(furniture.containment_error().is_empty())
  furniture.position=Vector3(3.4,0,3.4)
  assert("Arredo" in furniture.containment_error(),"Room-child furniture outside polygon must be diagnosed")
  var records=plan.level_records(0)
  assert(plan.checked_proposal(0,records)==records and plan.generation_failed)
  furniture.position=Vector3.ZERO
  assert(furniture.containment_error().is_empty())
  tower.free()
 print("POLYGON_ROOM_WALL_BOUNDS_ROTATION_PARENTS_PRESERVATION_OK")
 quit()

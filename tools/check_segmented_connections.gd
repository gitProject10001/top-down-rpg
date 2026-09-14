extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var tower=preload("res://addons/house_builder/polygon_tower.gd").new(); tower.face_count=16; tower.width=14; tower.depth=14
 root.add_child(tower)
 var wall=preload("res://addons/house_builder/curtain_wall.gd").new(); wall.depth=2.0; wall.tower_face=12; wall.connect_to_tower=true; tower.add_child(wall)
 assert(wall.connection_error().is_empty(),"Face 12 must be usable")
 wall.prepare_attachment()
 assert(wall.position.dot(tower.wall_normal(12))>5)
 wall.tower_face=16; assert(not wall.connection_error().is_empty(),"Do not wrap invalid face IDs")
 wall.tower_face=12; tower.tower_roof=2
 assert(not wall.connection_error().is_empty(),"Do not connect a walkway to a dome")
 tower.tower_roof=0
 var target=preload("res://addons/house_builder/polygon_tower.gd").new(); root.add_child(target)
 wall.target_tower=wall.get_path_to(target); wall.target_face=12
 assert("Target Face" in wall.destination_error())
 tower.free(); target.free()
 print("SEGMENTED_CONNECTION_FACE_AND_ROOF_DIAGNOSTICS_OK")
 quit()

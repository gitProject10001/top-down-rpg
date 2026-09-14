extends RefCounted
## Authored composition using existing builder bodies and stair components.
static func create() -> Node3D:
 var group := Node3D.new(); group.name="EdificioTerrazzato"
 var base=preload("res://addons/house_builder/volume.gd").new()
 base.name="Terrazza"; base.attached=false; base.width=14; base.depth=12; base.wall_height=3; base.roof_height=0.65
 base.canopy_roof=2; base.parapet_enabled=true; base.battlements_enabled=false; base.wall_finish=1
 group.add_child(base)
 var stair=preload("res://addons/house_builder/exterior_stair.gd").new(); stair.name="ScalaTerrazza"; stair.width=2.4; base.add_child(stair)
 var pavilion=preload("res://addons/house_builder/polygon_tower.gd").new()
 pavilion.name="PadiglioneCupola"; pavilion.face_count=12; pavilion.width=5.5; pavilion.depth=5.5; pavilion.wall_height=3; pavilion.roof_height=2.3; pavilion.tower_roof=2; pavilion.wall_finish=0
 pavilion.position=Vector3(0,base.effective_elevation(),-1.5)
 var records: Array[Dictionary]=[{"kind":"door","wall":0,"width":1.3,"height":2.1,"open":true},{"kind":"window","wall":2,"width":0.65,"height":1.1,"y":1.7}]
 pavilion.openings=records; group.add_child(pavilion)
 return group

extends RefCounted
const Volume=preload("res://addons/house_builder/volume.gd")
static func create() -> Node3D:
	var tower := Volume.new(); tower.name="TorreQuadrata"; tower.attached=false
	tower.width=4.8; tower.depth=4.8; tower.wall_height=5.6; tower.roof_height=1.0
	tower.canopy_roof=2; tower.parapet_enabled=true; tower.battlements_enabled=true; tower.archetype_id="tower"
	tower.openings=[{"kind":"door","wall":0,"u":0.0,"width":1.2,"height":2.1},{"kind":"window","wall":2,"u":0.0,"y":3.6,"width":0.45,"height":1.1}]
	return tower

@tool
extends Resource
## Boundary between settlement planning and building generation. Metres, local +Z entrance.
const House=preload("res://addons/house_builder/house.gd")
@export_enum("Casa popolana","Bottega","Casa benestante") var building_type := 0
@export var footprint := Vector2(5,7)
@export_range(1,3) var storeys := 1
@export var seed_value := 1
@export_enum("Fronte +Z","Retro -Z","Destra +X","Sinistra -X") var entrance_side := 0
func data() -> Dictionary: return {"type":building_type,"footprint":footprint,"storeys":storeys,"seed":seed_value,"entrance":entrance_side}
func errors() -> PackedStringArray:
	if footprint.x<1.8 or footprint.x>20 or footprint.y<1.8 or footprint.y>24: return PackedStringArray(["Ingombro edificio fuori dai limiti dell'House Builder."])
	if storeys<1 or storeys>3: return PackedStringArray(["Numero di piani non supportato."])
	return PackedStringArray()
func create_house() -> Node3D:
	if not errors().is_empty(): return null
	var house := House.new(); house.name="Edificio"
	house.width=footprint.x; house.depth=footprint.y; house.wall_height=storeys*2.6
	house.house_seed=seed_value
	house.weathered=building_type!=2; house.roof_height=2.7 if building_type==2 else 2.1
	house.openings=[{"kind":"door","wall":entrance_side,"u":0.0,"width":1.4,"height":2.3},{"kind":"window","wall":entrance_side,"u":0.65,"y":1.5}]
	if building_type==1: house.openings[1].width=1.1; house.openings[1].height=1.2
	for floor_index in range(1,storeys):
		house.openings.append({"kind":"window","wall":0,"u":0.0,"y":floor_index*2.6+1.3})
		house.openings.append({"kind":"window","wall":2,"u":0.0,"y":floor_index*2.6+1.3})
	return house

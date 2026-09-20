@tool
extends Resource
## Boundary between settlement planning and building generation. Metres, local +Z entrance.
const House=preload("res://addons/house_builder/house.gd")
const BuildingRecipe=preload("res://addons/house_builder/building_recipe.gd")
@export var architecture_profile: House.ArchitectureProfile
@export var archetype_id := ""
@export var recipe: BuildingRecipe
@export var recipe_variant_id := ""
@export var recipe_structural_seed := -1
@export var recipe_detail_seed := -1
@export_enum("Casa popolana","Bottega","Casa benestante") var building_type := 0
@export var footprint := Vector2(5,7)
@export_range(1,3) var storeys := 1
@export var seed_value := 1
@export_enum("Fronte +Z","Retro -Z","Destra +X","Sinistra -X") var entrance_side := 0
func data() -> Dictionary:
	var result := {"type":building_type,"footprint":footprint,"storeys":storeys,"seed":seed_value,"entrance":entrance_side}
	if architecture_profile!=null or not archetype_id.is_empty():
		result["schema"]=2; result["archetype"]=archetype_id
		result["architecture"]=architecture_profile.profile_id if architecture_profile else ""
		result["proportions"]=architecture_profile.proportions() if architecture_profile else {}
	if recipe:
		result["schema"] = 3
		result["recipe"] = recipe.data()
		result["recipe_variant"] = recipe_variant_id
		result["structural_seed"] = recipe_structural_seed
		result["detail_seed"] = recipe_detail_seed
	return result
func errors() -> PackedStringArray:
	if footprint.x<1.8 or footprint.x>20 or footprint.y<1.8 or footprint.y>24: return PackedStringArray(["Ingombro edificio fuori dai limiti dell'House Builder."])
	if storeys<1 or storeys>3: return PackedStringArray(["Numero di piani non supportato."])
	return PackedStringArray()
func create_house() -> Node3D:
	if not errors().is_empty(): return null
	var house := House.new(); house.name="Edificio"
	house.archetype_id=archetype_id if not archetype_id.is_empty() else ("shop" if building_type==1 else "dwelling")
	house.width=footprint.x; house.depth=footprint.y; house.wall_height=storeys*2.6
	house.house_seed=seed_value
	house.weathered=building_type!=2; house.roof_height=2.7 if building_type==2 else 2.1
	if architecture_profile:
		house.apply_architecture(house.architecture_proposal(architecture_profile))
		house.roof_height=architecture_profile.default_roof_height; house.profile_baseline={"roof_height":house.roof_height}
	house.openings=[{"kind":"door","wall":entrance_side,"u":0.0,"width":1.4,"height":2.3},{"kind":"window","wall":entrance_side,"u":0.65,"y":1.5}]
	if building_type==1: house.openings[1].width=1.1; house.openings[1].height=1.2
	for floor_index in range(1,storeys):
		house.openings.append({"kind":"window","wall":0,"u":0.0,"y":floor_index*2.6+1.3})
		house.openings.append({"kind":"window","wall":2,"u":0.0,"y":floor_index*2.6+1.3})
	if recipe:
		var service = load("res://addons/house_builder/recipe_apply.gd")
		var proposal: Dictionary = service.propose(house, recipe, seed_value if recipe_structural_seed < 0 else recipe_structural_seed, recipe_detail_seed, recipe_variant_id, true, storeys * 2.6)
		if not proposal.ok:
			push_warning("Ricetta edificio non applicata: " + "; ".join(proposal.errors))
			house.free()
			return null
		service.apply(house, proposal.after)
	return house

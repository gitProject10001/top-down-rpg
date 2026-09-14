extends RefCounted
## Adapter only: consumes an accepted plan through existing authoring builders.
## Returns a NEW group, never regenerates/replaces the user's edited group.
static func create(plan: Dictionary) -> Node3D:
 if plan.get("schema",0)!=1 or plan.get("family","")!="single_court": return null
 if not preload("res://addons/castle_generator/single_court_rules.gd").new().validate(plan,0).is_empty(): return null
 for record in plan.buildings:
  if record.builder not in ["keep","hall"]: return null
 var group=preload("res://addons/house_builder/fortification_factory.gd").create_inhabitable_enclosure()
 group.name="CastelloGenerato"; group.entry_position=plan.entry
 group.set_meta("composition_plan",plan.duplicate(true))
 for tower in group.towers():
  tower.position.x*=plan.span.x/16.0; tower.position.z*=plan.span.y/16.0
  tower.wall_finish=1; tower.house_seed=hash(str(plan.seed)+":"+str(tower.name))
  tower.set_meta("composition_id",str(tower.name))
 for record in plan.buildings:
  var building: Node3D
  if record.builder=="keep": building=preload("res://addons/house_builder/keep_factory.gd").create()
  else:
   var request=preload("res://addons/house_builder/building_request.gd").new()
   request.footprint=record.size; request.archetype_id="hall"; request.seed_value=record.seed
   building=request.create_house(); building.name="CorpoServizi"
  building.width=record.size.x; building.depth=record.size.y
  building.position=record.position; building.house_seed=record.seed
  building.set_meta("composition_id",record.id); group.add_child(building)
 return group

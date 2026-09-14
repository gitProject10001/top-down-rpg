extends SceneTree
const Request=preload("res://addons/castle_generator/request.gd")
const Planner=preload("res://addons/castle_generator/planner.gd")
const Materializer=preload("res://addons/castle_generator/materializer.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var request=Request.new(); var signatures := {}
 for seed_value in 100:
  request.seed_value=seed_value
  var result=Planner.generate(request)
  assert(result.errors.is_empty())
  assert(result==Planner.generate(request),"Identical request must reproduce the plan")
  assert(request.rules.validate(result.plan,request.minimum_open_fraction).is_empty())
  signatures[str(result.plan.span)+str(result.plan.buildings)]=true
 assert(signatures.size()==100,"Seed must change structural composition")
 request.minimum_open_fraction=1
 assert(not Planner.generate(request).errors.is_empty())
 request.minimum_open_fraction=0.65; request.seed_value=17
 var plan=Planner.generate(request).plan
 var group=Materializer.create(plan); root.add_child(group)
 for i in 5: await process_frame
 assert(group.diagnostics().is_empty(),str(group.diagnostics()))
 assert(group.towers().size()==4 and group.curtains().size()==4)
 assert(group.get_meta("composition_plan")==plan)
 print("CASTLE_GENERATOR_100_SEEDS_DETERMINISM_CONSTRAINTS_BUILDER_OK")
 group.free()
 var saved=load("res://scenes/dev/castle_generated_seed17.tscn").instantiate()
 var authored=saved.get_node("CastelloGenerato")
 assert(authored.get_meta("composition_plan")==plan,"Saved example retains its plan")
 assert(authored.get_node("Mastio").get_meta("composition_id")=="keep")
 assert(authored.get_node("CorpoServizi").position==plan.buildings[1].position)
 saved.free()
 print("CASTLE_GENERATOR_SAVED_PLAN_EDITABLE_NODES_OK")
 quit()

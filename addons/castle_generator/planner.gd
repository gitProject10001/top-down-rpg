extends RefCounted
## Pure planning: no scene nodes, meshes or editor dependencies.
static func generate(request: Resource) -> Dictionary:
 if request.rules==null or not request.rules.has_method("propose") or not request.rules.has_method("request_errors") or not request.rules.has_method("validate"):
  return {"errors":["Regole di composizione mancanti."]}
 var request_errors: PackedStringArray=request.rules.request_errors(request)
 if not request_errors.is_empty(): return {"errors":request_errors}
 if not is_finite(request.minimum_open_fraction) or request.minimum_open_fraction<0 or request.minimum_open_fraction>1:
  return {"errors":["La frazione scoperta deve essere fra 0 e 1."]}
 var rng := RandomNumberGenerator.new(); rng.seed=request.seed_value
 for attempt in 64:
  var plan: Dictionary=request.rules.propose(request,rng)
  var errors: PackedStringArray=request.rules.validate(plan,request.minimum_open_fraction)
  if errors.is_empty():
   plan["seed"]=request.seed_value
   for building in plan.buildings:
    # Stable semantic IDs isolate detail randomness from the layout RNG.
    building["seed"]=hash(str(request.seed_value)+":"+building.id)
   return {"plan":plan,"errors":[]}
 return {"errors":["Nessuna disposizione valida in 64 tentativi: riduci lo spazio scoperto richiesto o aumenta l'area."]}

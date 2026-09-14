@tool
extends RefCounted
## First safe increment: change building positions only. Existing nodes/details stay intact.
static func state(group: Node3D) -> Dictionary:
 var result := {}
 for node in group.buildings():
  var id: String=node.get_meta("composition_id","")
  if id.is_empty() or result.has(id): return {}
  result[id]={"transform":node.transform,"size":Vector2(node.width,node.depth),"locked":node.get_meta("composition_locked",false)}
 return result

static func propose(group: Node3D, candidate: Dictionary) -> Dictionary:
 var original: Dictionary=group.get_meta("composition_plan",{})
 if original.is_empty(): return {"error":"Il gruppo non proviene dal compositore."}
 if candidate.get("family","")!=original.get("family",""): return {"error":"Famiglia diversa: crea un nuovo castello."}
 if not candidate.span.is_equal_approx(original.span):
  var request=preload("res://addons/castle_generator/request.gd").new()
  request.seed_value=candidate.seed; request.minimum_span=original.span; request.maximum_span=original.span
  request.minimum_open_fraction=candidate.get("minimum_open_fraction",0.65)
  var result=preload("res://addons/castle_generator/planner.gd").generate(request)
  if not result.errors.is_empty(): return {"error":"; ".join(result.errors)}
  candidate=result.plan
 var snapshot := state(group)
 if snapshot.is_empty(): return {"error":"ID mancanti o duplicati: impossibile rigenerare in sicurezza."}
 var baseline: Dictionary=group.get_meta("composition_baseline",{}).duplicate(true)
 if baseline.is_empty():
  for record in original.buildings: baseline[record.id]=record.position
 var merged: Dictionary=candidate.duplicate(true)
 var updates := {}; var preserved: Array[String]=[]
 var known := {}
 for record in merged.buildings:
  known[record.id]=true
  if not snapshot.has(record.id) or not baseline.has(record.id): return {"error":"Edifici aggiunti o rimossi: rigenerazione strutturale non ancora supportata."}
  var current: Dictionary=snapshot[record.id]
  if not current.transform.basis.is_equal_approx(Basis.IDENTITY): return {"error":"Un edificio è ruotato o scalato: serve la futura validazione degli ingombri orientati."}
  if not is_zero_approx(current.transform.origin.y): return {"error":"La prima rigenerazione supporta edifici a quota zero."}
  record.size=current.size
  if current.locked or not current.transform.origin.is_equal_approx(baseline[record.id]):
   record.position=current.transform.origin; preserved.append(record.id)
  else:
   updates[record.id]=record.position; baseline[record.id]=record.position
 # Towers are outside this increment: reject a modified perimeter, without moving it.
 for tower in group.towers():
  var expected := Vector3.ZERO
  var id: String=tower.get_meta("composition_id","")
  if id in ["TorreEst","TorreNordEst"]: expected.x=original.span.x
  if id in ["TorreNordEst","TorreNordOvest"]: expected.z=-original.span.y
  if not tower.position.is_equal_approx(expected) or not tower.basis.is_equal_approx(Basis.IDENTITY) or not is_equal_approx(tower.width,8) or not is_equal_approx(tower.depth,8):
   return {"error":"Il recinto è stato modificato: viene preservato, ma non è ancora supportato dalla rigenerazione."}
 for node in group.buildings():
  if not node.authored_volumes().is_empty(): return {"error":"Sono presenti volumi accessori: la rigenerazione dei loro ingombri non è ancora supportata."}
  if node not in group.towers() and not known.has(node.get_meta("composition_id","")): return {"error":"Sono presenti corpi aggiunti manualmente: la rigenerazione richiede un controllo degli ingombri aggiuntivi."}
 var errors=preload("res://addons/castle_generator/single_court_rules.gd").new().validate(merged,candidate.get("minimum_open_fraction",0.65))
 if not errors.is_empty(): return {"error":"La proposta entra in conflitto con gli elementi preservati: "+"; ".join(errors)+" Prova un altro seed."}
 return {"snapshot":snapshot,"original":original.duplicate(true),"updates":updates,"baseline":baseline,"plan":merged,"preserved":preserved}

static func apply(group: Node3D, positions: Dictionary, plan: Dictionary, baseline: Dictionary) -> void:
 for node in group.buildings():
  var id: String=node.get_meta("composition_id","")
  if positions.has(id): node.position=positions[id]
 group.set_meta("composition_plan",plan.duplicate(true))
 group.set_meta("composition_baseline",baseline.duplicate(true))
 group.rebuild()

static func baseline_for(group: Node3D) -> Dictionary:
 var baseline: Dictionary=group.get_meta("composition_baseline",{}).duplicate(true)
 if baseline.is_empty():
  for record in group.get_meta("composition_plan",{}).get("buildings",[]): baseline[record.id]=record.position
 return baseline

static func describe(group: Node3D) -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 var baseline := baseline_for(group)
 for node in group.buildings():
  var id: String=node.get_meta("composition_id","")
  var supported := baseline.has(id)
  var locked: bool=node.get_meta("composition_locked",false)
  var manual: bool=supported and not node.position.is_equal_approx(baseline[id])
  var label := "Posizione bloccata" if locked else ("Posizione manuale" if manual else "Posizione automatica")
  if not supported: label="Recinto · rigenerazione non disponibile"
  result.append({"id":id,"name":str(node.name),"status":label,"supported":supported,"locked":locked,"manual":manual})
 return result

static func release_baseline(group: Node3D, id: String) -> Dictionary:
 var baseline := baseline_for(group)
 if not baseline.has(id): return {}
 for node in group.buildings():
  if node.get_meta("composition_id","")==id:
   baseline[id]=node.position
   return baseline
 return {}

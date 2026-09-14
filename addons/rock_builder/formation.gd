@tool
extends Path3D
## Guide follows the BACK of the free area: generated masses lie on its left side.
const Rock=preload("res://addons/rock_builder/rock.gd")
const FIELDS=["transform","rock_seed","dimensions","fracture","strata","strata_dip","lean","stone_color","collisions_enabled"]
@export var formation_seed := 31
@export_range(2,8,0.2) var spacing := 4.0
@export_range(1,8,0.2) var wall_height := 4.5
@export var strata := 3
@export_range(-0.3,0.3,0.02) var strata_dip := 0.15
@export var generation_ids := PackedStringArray()
func _ready() -> void:
 if curve==null:
  curve=Curve3D.new(); curve.add_point(Vector3(-10,0,0)); curve.add_point(Vector3(0,0,-1)); curve.add_point(Vector3(10,0,1))
func snapshot() -> Dictionary:
 var records: Array=[]
 for node in get_children():
  if not node is Rock or not node.has_meta("formation_id"): continue
  var values := {}
  for field in FIELDS: values[field]=node.get(field)
  records.append({"id":node.get_meta("formation_id"),"values":values,"baseline":node.get_meta("formation_baseline",{}).duplicate(true),"locked":node.get_meta("formation_locked",false)})
 return {"records":records,"ids":generation_ids.duplicate()}
func proposal() -> Dictionary:
 if curve==null or curve.get_baked_length()<1: return {"error":"Disegna una guida di almeno un metro."}
 if spacing<2 or wall_height<1: return {"error":"Spaziatura minima 2 m, altezza minima 1 m."}
 for point in curve.get_baked_points():
  if absf(point.y)>0.01: return {"error":"Questa versione usa una guida piana a quota locale zero."}
 var count := ceili(curve.get_baked_length()/spacing)+1
 if count>80: return {"error":"Massimo 80 stazioni per gruppo: dividi la guida."}
 var previous := snapshot(); var existing := {}
 for record in previous.records: existing[record.id]=record
 var output: Array=[]; var seen := PackedStringArray(); var protected := 0
 for index in count:
  var distance_value: float=minf(index*spacing,curve.get_baked_length())
  var p := curve.sample_baked(distance_value)
  var direction := curve.sample_baked(minf(distance_value+0.1,curve.get_baked_length()))-curve.sample_baked(maxf(0,distance_value-0.1))
  if direction.length()<0.001: return {"error":"La guida contiene un tratto senza direzione."}
  direction=direction.normalized()
  var front := Vector3(-direction.z,0,direction.x)
  for tier in 3:
   var id := "%d_%d"%[index,tier]; seen.append(id)
   if not existing.has(id) and generation_ids.has(id): continue # Respect manual deletions.
   if existing.has(id):
    var record: Dictionary=existing[id]
    var node := node_for(id)
    if record.locked or record.values!=record.baseline or node.get_child_count()>0:
     output.append(record); protected+=1; continue
   var rng := RandomNumberGenerator.new(); rng.seed=hash(str(formation_seed)+":"+id)
   var size_value := Vector3(spacing*rng.randf_range(1.1,1.4),wall_height*rng.randf_range(0.8,1.2),spacing*rng.randf_range(0.8,1.0))
   if tier==1: size_value*=Vector3(0.65,0.52,0.65)
   if tier==2: size_value*=Vector3(0.3,0.24,0.3)
   size_value=size_value.max(Vector3.ONE*0.3)
   # Conservative radius keeps new generated geometry behind the guide.
   var back := size_value.length()*0.58+(0.5 if tier==0 else 0.1)
   var pos := p-front*back+direction*rng.randf_range(-0.25,0.25)*spacing
   var frame := Transform3D(Basis(Vector3.UP,-atan2(direction.z,direction.x)),pos)
   var values := {"transform":frame,"rock_seed":int(rng.randi()),"dimensions":size_value,"fracture":0.7,"strata":strata,"strata_dip":strata_dip,"lean":0.12,"stone_color":Color(0.34,0.35,0.32),"collisions_enabled":true}
   output.append({"id":id,"values":values,"baseline":values.duplicate(true),"locked":false})
 for id in existing:
  if seen.has(id): continue
  var record: Dictionary=existing[id]
  if record.locked or record.values!=record.baseline or node_for(id).get_child_count()>0:
   output.append(record); protected+=1
 return {"records":output,"ids":seen,"protected":protected}
func node_for(id: String) -> Node:
 for node in get_children():
  if node.get_meta("formation_id","")==id: return node
 return null
func apply(state: Dictionary) -> void:
 var kept := {}
 for record in state.records:
  kept[record.id]=true
  var node=node_for(record.id)
  if node==null:
   node=Rock.new(); node.name="Roccia_"+record.id; node.set_meta("formation_id",record.id); add_child(node)
   node.owner=owner if owner else self
  for field in FIELDS: node.set(field,record.values[field])
  node.set_meta("formation_baseline",record.baseline.duplicate(true)); node.set_meta("formation_locked",record.locked)
 for node in get_children():
  if node is Rock and node.has_meta("formation_id") and not kept.has(node.get_meta("formation_id")): node.free()
 generation_ids=state.ids.duplicate()

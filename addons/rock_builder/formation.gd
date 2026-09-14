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
 var ribbons := free_ribbons()
 var count := ceili(curve.get_baked_length()/spacing)+1
 if count>80: return {"error":"Massimo 80 stazioni per gruppo: dividi la guida."}
 var stations := compose_stations(count,curve.get_baked_length())
 var previous := snapshot(); var existing := {}
 for record in previous.records: existing[record.id]=record
 var output: Array=[]; var seen := PackedStringArray(); var protected := 0
 for index in count:
  var station: Dictionary=stations[index]
  var distance_value: float=station.distance
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
   var size_value := Vector3(spacing*rng.randf_range(1.4,1.8),wall_height*station.prominence*rng.randf_range(0.85,1.12),spacing*rng.randf_range(0.8,1.0))
   if tier==1: size_value*=Vector3(rng.randf_range(0.8,1.05),rng.randf_range(0.22,0.42),0.85)
   if tier==2: size_value*=Vector3(rng.randf_range(0.2,0.4),rng.randf_range(0.16,0.32),0.3)
   size_value=size_value.max(Vector3.ONE*0.3)
   # Depth-based setback lets broad shelves intersect the feet of taller masses.
   # The whole proposal still passes the global free-ribbon geometry check.
   var back := size_value.z*0.62+(0.85 if tier==0 else 0.25)
   var pos := p-front*back+direction*rng.randf_range(-0.16,0.16)*spacing
   if tier==1: pos+=direction*spacing*0.25
   var frame := Transform3D(Basis(Vector3.UP,-atan2(direction.z,direction.x)),pos)
   var values := {"transform":frame,"rock_seed":int(rng.randi()),"dimensions":size_value,"fracture":0.7,"strata":strata,"strata_dip":strata_dip,"lean":0.12,"stone_color":Color(0.34,0.35,0.32),"collisions_enabled":true}
   output.append({"id":id,"values":values,"baseline":values.duplicate(true),"locked":false})
 for id in existing:
  if seen.has(id): continue
  var record: Dictionary=existing[id]
  if record.locked or record.values!=record.baseline or node_for(id).get_child_count()>0:
   output.append(record); protected+=1
 for record in output:
  var conflict := intersects_free_area(record.values,ribbons)
  if conflict:
   return {"error":"Roccia %s: invade la fascia libera davanti alla guida (2 m). Allarga la curva o sposta la roccia modificata. Nessuna modifica applicata."%record.id}
 return {"records":output,"ids":seen,"protected":protected}

## Seeded runs of 2-4 stations share a crest; compressed spacing forms clusters.
## Stable station/tier IDs keep the existing manual override contract.
func compose_stations(count: int,length_value: float) -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 var start := 0
 var cluster := 0
 while start<count:
  var rng := RandomNumberGenerator.new()
  rng.seed=hash(str(formation_seed)+":cluster:"+str(cluster))
  var members := mini(rng.randi_range(2,4),count-start)
  var compression := rng.randf_range(0.58,0.78)
  var crest := rng.randf_range(0.85,1.25)
  var center := start+(members-1)*0.5
  for j in members:
   var index := start+j
   var t := (center+(j-(members-1)*0.5)*compression)/maxf(count-1,1)
   if index==0: t=0
   if index==count-1: t=1
   var profile := sin(PI*(j+0.5)/members)
   result.append({"distance":t*length_value,"prominence":crest*lerpf(0.5,1.0,profile)})
  start+=members
  cluster+=1
 return result

## Local XZ ribbon: the positive normal is the playable side of the guide.
func free_ribbons() -> Array[PackedVector2Array]:
 var result: Array[PackedVector2Array]=[]
 var points := curve.get_baked_points()
 for i in range(points.size()-1):
  var a := Vector2(points[i].x,points[i].z)
  var b := Vector2(points[i+1].x,points[i+1].z)
  if a.distance_to(b)<0.001: continue
  var tangent := (b-a).normalized()
  var front := Vector2(-tangent.y,tangent.x)*2.0
  result.append(PackedVector2Array([a,b,b+front,a+front]))
 return result

func intersects_free_area(values: Dictionary,ribbons: Array[PackedVector2Array]) -> bool:
 var probe := Rock.new()
 for field in FIELDS:
  if field!="transform": probe.set(field,values[field])
 var hull: PackedVector3Array=probe.generate().hull
 probe.free()
 var points := PackedVector2Array()
 for vertex in hull:
  var p: Vector3=values.transform*vertex
  points.append(Vector2(p.x,p.z))
 var footprint := Geometry2D.convex_hull(points)
 for ribbon in ribbons:
  if not Geometry2D.intersect_polygons(footprint,ribbon).is_empty(): return true
 return false
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

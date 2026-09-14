@tool
extends Node3D
## Parameters describe the next rebuild; applied_state is the saved, active platform.
const Formation=preload("res://addons/rock_builder/formation.gd")
@export var terrace_seed := 31
@export var footprint := Vector2(16,12)
@export_range(1,6,1) var elevation := 3
@export var ramp_enabled := true
@export_range(2,6,0.5) var ramp_width := 3.0
@export_range(2,18,0.5) var ramp_length := 6.0
@export_storage var applied_state: Dictionary={}
var core: Node3D
func _ready() -> void:
 if not applied_state.is_empty(): rebuild_core()
func border() -> Node:
 return get_node_or_null("BordoRoccioso")
func snapshot() -> Dictionary:
 return {"platform":applied_state.duplicate(true),"rocks":border().snapshot() if border() else {"records":[],"ids":PackedStringArray()}}
func proposal() -> Dictionary:
 if footprint.x<6 or footprint.y<6 or footprint.x>60 or footprint.y>60:
  return {"error":"Terrazza: larghezza e profondità devono essere fra 6 e 60 metri."}
 if elevation<1 or elevation>6: return {"error":"Terrazza: quota intera fra 1 e 6 metri."}
 if ramp_enabled and (ramp_width<2 or ramp_width>footprint.x-2 or ramp_length<float(elevation)*2 or ramp_length>18):
  return {"error":"Rampa: larghezza minima 2 m e margine di 1 m sui lati; lunghezza almeno doppia della quota e massimo 18 m (pendenza massima 26.6°)."}
 var corridor: Array[PackedVector2Array]=[]
 if ramp_enabled:
  var half_width := ramp_width/2+0.35
  corridor.append(PackedVector2Array([Vector2(-half_width,footprint.y/2-1),Vector2(half_width,footprint.y/2-1),Vector2(half_width,footprint.y/2+ramp_length+0.5),Vector2(-half_width,footprint.y/2+ramp_length+0.5)]))
 var verifier=Formation.new()
 var prior: Dictionary=snapshot().rocks
 var existing := {}
 for record in prior.records: existing[record.id]=record
 var records: Array=[]
 var ids := PackedStringArray()
 var corners := [Vector3(-footprint.x/2,0,-footprint.y/2),Vector3(footprint.x/2,0,-footprint.y/2),Vector3(footprint.x/2,0,footprint.y/2),Vector3(-footprint.x/2,0,footprint.y/2)]
 for edge in 4:
  var a: Vector3=corners[edge]
  var b: Vector3=corners[(edge+1)%4]
  var tangent := (b-a).normalized()
  var inward := Vector3(-tangent.z,0,tangent.x)
  var count := ceili(a.distance_to(b)/2.5)
  for i in count:
   var id := "%d_%d"%[edge,i]
   if not existing.has(id) and prior.ids.has(id):
    ids.append(id); continue
   if existing.has(id) and is_authored(existing[id]):
    records.append(existing[id]); ids.append(id); continue
   var rng := RandomNumberGenerator.new(); rng.seed=hash(str(terrace_seed)+":"+id)
   var size_value := Vector3(a.distance_to(b)/count*1.8,float(elevation)*rng.randf_range(0.87,0.99),rng.randf_range(1.6,2.2))
   var pos := a.lerp(b,(i+0.5)/count)-inward*0.1
   var values := {"transform":Transform3D(Basis(Vector3.UP,-atan2(tangent.z,tangent.x)),pos),"rock_seed":int(rng.randi()),"dimensions":size_value,"fracture":0.7,"strata":3,"strata_dip":0.08,"lean":0.05,"stone_color":Color(0.34,0.35,0.32),"collisions_enabled":true}
   if ramp_enabled and verifier.intersects_free_area(values,corridor): continue
   ids.append(id)
   records.append({"id":id,"values":values,"baseline":values.duplicate(true),"locked":false})
 for id in existing:
  if not ids.has(id) and is_authored(existing[id]): records.append(existing[id])
 for record in records:
  if ramp_enabled and verifier.intersects_free_area(record.values,corridor):
   verifier.free()
   return {"error":"Roccia manuale %s nel passaggio della rampa: spostala prima di rigenerare. Nessuna modifica applicata."%record.id}
 verifier.free()
 return {"platform":{"footprint":footprint,"elevation":elevation,"ramp_enabled":ramp_enabled,"ramp_width":ramp_width,"ramp_length":ramp_length},"rocks":{"records":records,"ids":ids}}
func is_authored(record: Dictionary) -> bool:
 var node=border().node_for(record.id) if border() else null
 return record.locked or record.values!=record.baseline or (node!=null and node.get_child_count()>0)
func apply(state: Dictionary) -> void:
 applied_state=state.platform.duplicate(true)
 if border()==null:
  var group=Formation.new(); group.name="BordoRoccioso"; group.curve=Curve3D.new()
  add_child(group); group.owner=owner if owner else self
 border().apply(state.rocks)
 rebuild_core()
func rebuild_core() -> void:
 if is_instance_valid(core): core.free()
 if applied_state.is_empty(): return
 core=Node3D.new(); core.name="_Platform"; add_child(core,false,Node.INTERNAL_MODE_BACK)
 var size_value := Vector3(applied_state.footprint.x,float(applied_state.elevation),applied_state.footprint.y)
 var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size=size_value; mesh.mesh=box
 var stone := StandardMaterial3D.new(); stone.albedo_color=Color(0.30,0.31,0.28); stone.roughness=1
 mesh.material_override=stone; mesh.position.y=size_value.y/2; core.add_child(mesh)
 var top := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=applied_state.footprint; top.mesh=plane; top.position.y=size_value.y+0.005
 var earth := StandardMaterial3D.new(); earth.albedo_color=Color(0.32,0.35,0.23); earth.roughness=1
 top.material_override=earth; core.add_child(top)
 var body := StaticBody3D.new(); core.add_child(body)
 var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size=size_value
 collision.shape=shape; collision.position.y=size_value.y/2; body.add_child(collision)

 if applied_state.get("ramp_enabled",false): rebuild_ramp(earth)

func rebuild_ramp(material: Material) -> void:
 var w: float=applied_state.ramp_width/2
 var h: float=applied_state.elevation
 var z: float=applied_state.footprint.y/2
 var end: float=z+applied_state.ramp_length
 # The wedge overlaps the platform slightly; its top meets the platform at h.
 var points := PackedVector3Array([Vector3(-w,0,z-0.05),Vector3(w,0,z-0.05),Vector3(-w,h,z-0.05),Vector3(w,h,z-0.05),Vector3(-w,0,end),Vector3(w,0,end)])
 var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 for face in [[2,3,4],[3,5,4],[0,2,4],[1,5,3],[0,1,2],[1,3,2],[0,4,1],[1,4,5]]:
  for index in face: surface.add_vertex(points[index])
 surface.generate_normals()
 var mesh := MeshInstance3D.new(); mesh.name="Rampa"; mesh.mesh=surface.commit(); mesh.material_override=material; core.add_child(mesh)
 var body := StaticBody3D.new(); core.add_child(body)
 var shape := ConvexPolygonShape3D.new(); shape.points=points
 var collision := CollisionShape3D.new(); collision.shape=shape; body.add_child(collision)

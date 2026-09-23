@tool
extends Node3D
const Geometry = preload("res://addons/rock_builder/outcrop_geometry.gd")
const Field=preload("res://addons/rock_builder/fracture_field.gd")
const Boulder = preload("res://addons/rock_builder/fractured_boulder.gd")
const Natural=preload("res://addons/rock_builder/natural_formation.gd")
signal rebuilt
@export_enum("Costruita", "Naturale") var formation_style := 0:
 set(v): formation_style=v; schedule()
@export var natural_detail := true:
 set(v): natural_detail=v; schedule()
@export_enum("Area", "Percorso", "Volume") var shape_kind := 0:
 set(v): shape_kind=v; schedule()
@export var outline := PackedVector2Array([Vector2(-5,-4),Vector2(5,-4),Vector2(5,4),Vector2(-5,4)]):
 set(v): outline=v; schedule()
@export var holes: Array[PackedVector2Array]=[]:
 set(v): holes=v; schedule()
@export_range(0.3,30.0,0.1) var height := 3.0:
 set(v): height=maxf(0.3,v); schedule()
@export_range(0.5,20.0,0.1) var path_width := 4.0:
 set(v): path_width=maxf(0.5,v); schedule()
@export var volume_size := Vector2(10,8):
 set(v): volume_size=v.max(Vector2.ONE); schedule()
@export var walkable := true:
 set(v): walkable=v; schedule()
@export var rock_seed := 31:
 set(v): rock_seed=v; _rock_cache.clear(); schedule()
@export_range(0.75,4.0,0.25) var rock_spacing := 1.5:
 set(v): rock_spacing=maxf(0.75,v); schedule()
@export_group("Distribuzione naturale")
## Approximate horizontal size in world metres, independent of the envelope dimensions.
@export_range(0.5,20.0,0.1) var natural_rock_size := 5.5:
 set(v): natural_rock_size=clampf(v,0.5,20.0); schedule()
## Minimum centre spacing in world metres. Zero uses spacing proportional to rock size.
@export_range(0.0,20.0,0.1) var natural_min_spacing := 0.0:
 set(v): natural_min_spacing=clampf(v,0.0,20.0); schedule()
## Fraction of primary candidates retained; does not resize any rock.
@export_range(0.0,1.0,0.05) var natural_density := 1.0:
 set(v): natural_density=clampf(v,0.0,1.0); schedule()
## Maximum primary masses, excluding shelves and chips. Zero means automatic.
@export_range(0,512,1) var natural_max_rocks := 0:
 set(v): natural_max_rocks=clampi(v,0,512); schedule()
@export_group("Rocce medie")
@export_range(0.1,10.0,0.1) var medium_rock_size := 1.8:
 set(v): medium_rock_size=clampf(v,0.1,10.0); schedule()
@export_range(0.0,1.0,0.05) var medium_rock_density := 0.38:
 set(v): medium_rock_density=clampf(v,0.0,1.0); schedule()
@export_group("Rocce piccole")
@export_range(0.05,5.0,0.05) var small_rock_size := 0.4:
 set(v): small_rock_size=clampf(v,0.05,5.0); schedule()
@export_range(0.0,1.0,0.05) var small_rock_density := 0.30:
 set(v): small_rock_density=clampf(v,0.0,1.0); schedule()
## Fraction of small clusters placed on parent surfaces instead of at the foot.
## Walkable roofs remain clear.
@export_range(0.0,1.0,0.05) var small_surface_ratio := 0.55:
 set(v): small_surface_ratio=clampf(v,0.0,1.0); schedule()
@export_group("")
@export var stone_color := Color(0.37,0.36,0.31):
 set(v): stone_color=v; _rock_cache.clear(); schedule()
@export var ground_color := Color(0.27,0.32,0.19):
 set(v): ground_color=v; schedule()
@export var collisions_enabled := true:
 set(v): collisions_enabled=v; schedule()
@export var edit_rocks := false:
 set(v): edit_rocks=v; update_gizmos()
@export_storage var rock_offsets: Dictionary={}
var last_error := ""
var last_build_ms := 0.0
var last_new_rocks := 0
var _pending := false
var _editing := false
var _generated: Node3D
var _rocks: Node3D
var _rock_cache := {}
var _revision := 0
var _built_revision := -1
var rock_keys: Array[String]=[]
var rock_positions := PackedVector3Array()
var _scale_metric := Vector3.ZERO

func _ready() -> void:
 set_notify_transform(true)
 _scale_metric=_world_scale_metric()
 rebuild()
func _world_scale_metric() -> Vector3:
 return Vector3(global_basis.x.length(),global_basis.y.length(),global_basis.z.length())
func _notification(what: int) -> void:
 if what==NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
  var metric := _world_scale_metric()
  if not metric.is_equal_approx(_scale_metric):
   _scale_metric=metric
   schedule()
func _mass_span(yaw: float) -> Vector2:
 var frame := global_basis*Basis(Vector3.UP,yaw)
 var world_height := height*frame.y.length()
 # Tall formations use broader continuous slabs, not vertically stacked copies.
 return Vector2(maxf(rock_spacing*2.8,world_height*0.7/maxf(frame.x.length(),0.001)),maxf(rock_spacing*2.8,world_height*0.65/maxf(frame.z.length(),0.001)))

func schedule() -> void:
 _revision+=1
 if not is_inside_tree(): return
 update_gizmos()
 if _pending: return
 _pending=true
 call_deferred("_flush")
func _flush() -> void:
 _pending=false
 if _built_revision!=_revision: rebuild()
func begin_edit() -> void:
 _editing=true
func end_edit() -> void:
 _editing=false
 schedule()
func snapshot() -> Dictionary:
 return {"position":position,"outline":outline.duplicate(),"holes":holes.duplicate(true),"height":height,"path_width":path_width,"volume_size":volume_size,"rock_offsets":rock_offsets.duplicate(true)}
func apply_state(state: Dictionary) -> void:
 for key in state:
  if key=="holes":
   var typed: Array[PackedVector2Array]=[]; typed.assign(state[key]); holes=typed
  else: set(key,state[key])
 schedule()
func rings() -> Array:
 if shape_kind==2:
  var h := volume_size*0.5
  return [PackedVector2Array([Vector2(-h.x,-h.y),Vector2(h.x,-h.y),h,Vector2(-h.x,h.y)])]
 if shape_kind==1:
  if outline.size()<2: return []
  return Geometry2D.offset_polyline(outline,path_width*0.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
 var result: Array=[outline]
 result.append_array(holes)
 return result
func height_at_local(point: Vector2) -> float:
 return height if walkable and Geometry.contains(point,rings()) else NAN
func rebuild() -> void:
 var started := Time.get_ticks_usec()
 var contours := rings()
 last_error=Geometry.validate(contours)
 if not last_error.is_empty():
  update_configuration_warnings()
  return
 var bounds := Rect2(contours[0][0],Vector2.ZERO)
 for p in contours[0]: bounds=bounds.expand(p)
 if bounds.size.x*bounds.size.y/(rock_spacing*rock_spacing)>16384:
  last_error="Area troppo grande: dividi l’affioramento in più nodi."; update_configuration_warnings(); return
 if formation_style==1:
  Natural.rebuild(self,contours)
  _built_revision=_revision; last_build_ms=(Time.get_ticks_usec()-started)/1000.0
  update_gizmos(); update_configuration_warnings(); rebuilt.emit()
  return
 var core_height := height if walkable else height*0.65
 var top := Geometry.top_faces(contours,core_height)
 var sides := Geometry.walls(contours,core_height,-0.5)
 var faces := top.duplicate(); faces.append_array(sides)
 var bottom := Geometry.top_faces(contours,-0.5)
 for i in range(0,bottom.size(),3): faces.append_array(PackedVector3Array([bottom[i],bottom[i+2],bottom[i+1]]))
 if is_instance_valid(_generated): _generated.free()
 _generated=Node3D.new(); _generated.name="_Outcrop"; add_child(_generated,false,Node.INTERNAL_MODE_BACK)
 var stone := StandardMaterial3D.new(); stone.albedo_color=stone_color; stone.roughness=1.0
 var earth := StandardMaterial3D.new(); earth.albedo_color=ground_color if walkable else stone_color; earth.roughness=1.0
 for data in [["Sommità",top,stone],["Parete",sides,stone]]:
  var visual := MeshInstance3D.new(); visual.name=data[0]; visual.mesh=Geometry.mesh(data[1],data[2]); visual.visible=walkable; _generated.add_child(visual)
 if walkable:
  # Expose a stone lip; the ground cover sits inside the crest instead of a paper-thin lid.
  var inset := Geometry2D.offset_polygon(contours[0],-0.35,Geometry2D.JOIN_MITER)
  var soil_rings: Array=[]
  if inset.size()==1:
   soil_rings.append(inset[0])
   for i in range(1,contours.size()):
    var expanded := Geometry2D.offset_polygon(contours[i],0.25,Geometry2D.JOIN_MITER)
    if expanded.size()==1: soil_rings.append(expanded[0])
  if not soil_rings.is_empty() and Geometry.validate(soil_rings).is_empty():
   var soil := MeshInstance3D.new(); soil.name="Terra"
   soil.mesh=Geometry.mesh(Geometry.top_faces(soil_rings,height+0.008),earth); _generated.add_child(soil)
 if collisions_enabled:
  var body := StaticBody3D.new(); body.name="OutcropCollision"
  body.set_meta("art_ground_surface",walkable)
  var collision := CollisionShape3D.new(); var shape := ConcavePolygonShape3D.new()
  if not walkable:
   # Exclusion walls preserve the holes and block access above the visible crest.
   faces.append_array(Geometry.walls(contours,height+8.0,-0.5))
  shape.set_faces(faces); collision.shape=shape; body.add_child(collision); _generated.add_child(body)
 if not _editing: _update_rocks(contours)
 _built_revision=_revision
 last_build_ms=(Time.get_ticks_usec()-started)/1000.0
 update_gizmos(); update_configuration_warnings(); rebuilt.emit()
func _get_configuration_warnings() -> PackedStringArray:
 return PackedStringArray([last_error]) if not last_error.is_empty() else PackedStringArray()
func _mass_stations(contours: Array) -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 if shape_kind==1:
  var curve := Curve3D.new()
  for p in outline: curve.add_point(Vector3(p.x,0,p.y))
  var length := curve.get_baked_length()
  var count := maxi(1,ceili(length/_mass_span(0).x))
  for i in count:
   var d := length*(i+0.5)/count
   var point := curve.sample_baked(d)
   var tangent := curve.sample_baked(minf(d+0.1,length))-curve.sample_baked(maxf(0,d-0.1))
   result.append({"id":"mass_path_%d"%i,"point":Vector2(point.x,point.z),"width":length/count*1.22,"depth":path_width*1.12,"yaw":-atan2(tangent.z,tangent.x),"tier":1.0 if i%3!=0 else 0.7})
  return result
 var bounds := Rect2(contours[0][0],Vector2.ZERO)
 for p in contours[0]: bounds=bounds.expand(p)
 var along_x := bounds.size.x>=bounds.size.y
 var length := bounds.size.x if along_x else bounds.size.y
 var depth := bounds.size.y if along_x else bounds.size.x
 var span := _mass_span(0.0 if along_x else PI*0.5)
 var columns := maxi(1,ceili(length/span.x))
 var rows := maxi(1,ceili(depth/span.y))
 for row in rows:
  for column in columns:
   var uv := Vector2((column+0.5)/columns,(row+0.5)/rows)
   var point := bounds.position+bounds.size*(uv if along_x else Vector2(uv.y,uv.x))
   if not Geometry.contains(point,contours): continue
   var tier := 1.0 if row==0 else lerpf(0.76,0.4,float(row)/rows)
   result.append({"id":"mass_%d_%d"%[row,column],"point":point,"width":length/columns*1.23,"depth":depth/rows*1.25,"yaw":0.0 if along_x else PI*0.5,"tier":tier})
 return result

func _update_rocks(contours: Array) -> void:
 if not is_instance_valid(_rocks):
  _rocks=Node3D.new(); _rocks.name="_RockDetails"; add_child(_rocks,false,Node.INTERNAL_MODE_BACK)
 var wanted := {}; rock_keys.clear(); rock_positions.clear(); last_new_rocks=0
 if walkable: _rim_rocks(contours,wanted)
 else:
  _fracture_field(contours,wanted)

 for node in _rocks.get_children():
  if not wanted.has(str(node.name)): node.free()
 while _rock_cache.size()>maxi(256,wanted.size()+64):
  _rock_cache.erase(_rock_cache.keys()[0])

func _rim_rocks(contours: Array,wanted: Dictionary) -> void:
 for ri in contours.size():
  var ring: PackedVector2Array=contours[ri].duplicate()
  if Geometry2D.is_polygon_clockwise(ring)==(ri==0): ring.reverse()
  for edge in ring.size():
   var a := ring[edge]; var b := ring[(edge+1)%ring.size()]
   var tangent := (b-a).normalized(); var inward := Vector2(-tangent.y,tangent.x)
   var yaw := -atan2(tangent.y,tangent.x)
   var span := _mass_span(yaw)
   var count := maxi(1,roundi(a.distance_to(b)/span.x))
   for station in count:
    var id := "rim_%d_%d_%d"%[ri,edge,station]; wanted[id]=true
    var rng := RandomNumberGenerator.new(); rng.seed=hash(str(rock_seed)+id)
    var depth := maxf(rock_spacing,span.y*0.32)*rng.randf_range(0.85,1.15)
    var width := a.distance_to(b)/count*rng.randf_range(1.15,1.4)
    var p := a.lerp(b,(station+0.5)/count)+inward*depth*(0.65 if ri>0 else 0.05)
    var size_y := height*rng.randf_range(0.9,1.04)+0.15
    var node := _rocks.get_node_or_null(NodePath(id)) as MeshInstance3D
    if node==null:
     node=MeshInstance3D.new(); node.name=id; _rocks.add_child(node)
    var base_key := "%s:%s"%[rock_seed,id]
    var key := base_key
    if not _rock_cache.has(key):
     _rock_cache[key]=Boulder.build(hash(base_key),stone_color); last_new_rocks+=1
    node.mesh=_rock_cache[key]
    node.transform=Transform3D(Basis(Vector3.UP,yaw).scaled_local(Vector3(width,size_y,depth)),Vector3(p.x,-0.2,p.y))
    if rock_offsets.has(id): node.position+=rock_offsets[id]
    rock_keys.append(id); rock_positions.append(node.position+Vector3.UP*size_y)

    if collisions_enabled: _rock_collision(node)

func _rock_collision(rock: MeshInstance3D) -> void:
 var body := StaticBody3D.new(); body.transform=rock.transform
 var parts: Array=rock.mesh.get_meta("collision_parts",[rock.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]])
 for points in parts:
  var collision := CollisionShape3D.new(); var shape := ConvexPolygonShape3D.new()
  shape.points=points; collision.shape=shape; body.add_child(collision)
 _generated.add_child(body)

func _fracture_field(contours: Array,wanted: Dictionary) -> void:
 var holes: Array=[]
 for i in range(1,contours.size()): holes.append(contours[i])
 var records := Field.cells(contours[0],_world_scale_metric(),height,rock_spacing,rock_seed)
 for record in records:
  var id: String=record.id; wanted[id]=true
  var node := _rocks.get_node_or_null(NodePath(id)) as MeshInstance3D
  if node==null:
   node=MeshInstance3D.new(); node.name=id; _rocks.add_child(node)
  var signature: Array=[snappedf(height,0.00001),stone_color,snappedf(record.top,0.00001),record.center.snapped(Vector2.ONE*0.00001),record.tint]
  for p in record.polygon: signature.append(p.snapped(Vector2.ONE*0.00001))
  for hole in holes:
   signature.append("hole")
   for p in hole: signature.append(p.snapped(Vector2.ONE*0.00001))
  var key := "%s:%s:%s"%[rock_seed,id,hash(signature)]
  if not _rock_cache.has(key):
   _rock_cache[key]=Field.geometry(record,holes,height,stone_color); last_new_rocks+=1
  var cached_mesh: Mesh=_rock_cache[key]
  _rock_cache.erase(key); _rock_cache[key]=cached_mesh
  node.mesh=cached_mesh
  node.transform=Transform3D(Basis.IDENTITY.scaled(Vector3(1,height,1)),Vector3(record.center.x,0,record.center.y))
  if rock_offsets.has(id): node.position+=rock_offsets[id]
  rock_keys.append(id); rock_positions.append(node.position+Vector3.UP*height*record.top)
  if collisions_enabled:
   var body := StaticBody3D.new(); body.transform=node.transform
   var collision := CollisionShape3D.new(); var shape := ConcavePolygonShape3D.new()
   shape.set_faces(node.mesh.get_meta("exact_faces")); collision.shape=shape; body.add_child(collision); _generated.add_child(body)

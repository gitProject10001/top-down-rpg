@tool
extends "res://scripts/village/terrain.gd"
## World terrain adapter: preserves the authored central mesh as source data.
## Uses the same world_plan, height_edits, reserved_zones and Undo API as Ground.
@export var source_mesh: ArrayMesh
@export var world_bounds:=Rect2(-152,-144,304,288)
var _source_heights: Dictionary={}
var _water_nodes: Array=[]
var _cliff_nodes: Array=[]
func _ready() -> void:
 _index_source()
 _schedule()
func _schedule() -> void:
 if not is_inside_tree() or _scheduled: return
 _scheduled=true
 call_deferred("_flush_rebuild")
func _flush_rebuild() -> void:
 if _scheduled: _rebuild()
func _index_source() -> void:
 _source_heights.clear()
 if not source_mesh: return
 var arrays:=source_mesh.surface_get_arrays(0)
 for vertex in arrays[Mesh.ARRAY_VERTEX]: _source_heights[Vector2i(roundi(vertex.x),roundi(vertex.z))]=vertex.y
func _source_height(x: float,z: float) -> float:
 var a:=Vector2i(floori(x/2)*2,floori(z/2)*2)
 var u:=fposmod(x,2)/2; var v:=fposmod(z,2)/2
 return lerpf(lerpf(float(_source_heights.get(a,.18)),float(_source_heights.get(a+Vector2i(2,0),.18)),u),lerpf(float(_source_heights.get(a+Vector2i(0,2),.18)),float(_source_heights.get(a+Vector2i(2,2),.18)),u),v)
func base_height(x: float,z: float) -> float:
 var p:=Vector2(x,z)
 var h:=_source_height(x,z) if Rect2(-76,-72,152,144).has_point(p) else .18
 for water in _water_nodes:
  if not is_instance_valid(water): continue
  var q: Vector3=water.to_local(Vector3(x,0,z))
  if water.contains_point(Vector2(q.x,q.z)):
   h=minf(h,water.position.y+water.bed_height(Vector2(q.x,q.z)))
 if world_plan: h+=world_plan.elevation(p)*generation_weight(p)
 for edit in height_edits:
  var weight:=1.0-smoothstep(0,float(edit.radius),p.distance_to(edit.position))
  if edit.kind=="flatten": h=lerpf(h,float(edit.value),weight)
  else: h+=float(edit.value)*weight
 return h
func height_at(x: float,z: float) -> float:
 var h:=base_height(x,z)
 for cliff in _cliff_nodes:
  if not is_instance_valid(cliff): continue
  var local: Vector3=cliff.to_local(Vector3(x,0,z))
  var y: float=cliff.height_at_local(Vector2(local.x,local.z))
  if not is_nan(y): h=maxf(h,cliff.global_position.y+y)
 return h
func _rebuild() -> void:
 _scheduled=false
 if not is_inside_tree() or not source_mesh: return
 if _source_heights.is_empty(): _index_source()
 _water_nodes.clear(); _cliff_nodes.clear()
 var root:=get_parent().get_parent()
 for node in root.get_children():
  if node.has_method("bed_height"):
   _water_nodes.append(node)
   if node.has_signal("water_geometry_changed") and not node.water_geometry_changed.is_connected(_schedule): node.water_geometry_changed.connect(_schedule)
  var cliff:=node.get_node_or_null("ContinuousCliff")
  if cliff: _cliff_nodes.append(cliff)
 var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for z in range(int(world_bounds.position.y),int(world_bounds.end.y),2):
  for x in range(int(world_bounds.position.x),int(world_bounds.end.x),2):
   for offset in [Vector2(0,0),Vector2(2,0),Vector2(0,2),Vector2(2,0),Vector2(2,2),Vector2(0,2)]:
    var p: Vector2=Vector2(x,z)+offset
    var y:=base_height(p.x,p.y)
    st.set_uv(p); st.set_color(Color(.27,.31,.16) if y>.1 else Color(.48,.40,.25)); st.add_vertex(Vector3(p.x,y,p.y))
 st.generate_normals(); st.index(); mesh=_with_lods(st.commit())
 for child in get_children():
  if child is StaticBody3D: child.free()
 create_trimesh_collision()
 surface_changed.emit()
func generation_weight(p: Vector2) -> float:
 if Rect2(-76,-72,152,144).has_point(p): return 0.0
 for cliff in _cliff_nodes:
  if not is_instance_valid(cliff) or not cliff.raised_zone_enabled: continue
  var curve: Curve3D=cliff.guide
  var end:=curve.sample_baked(curve.get_baked_length())
  var dir: Vector3=(end-curve.sample_baked(curve.get_baked_length()-.1)).normalized()
  var local: Vector3=cliff.to_local(Vector3(p.x,0,p.y))-end
  var along:=local.dot(dir)
  var behind: float=-local.dot(Vector3(-dir.z,0,dir.x))
  if along>-2 and along<cliff.effective_ramp_length()+3 and behind>-3 and behind<cliff.wall_depth+cliff.raised_zone_depth+3: return 0.0
 return super.generation_weight(p)

func _notification(what: int) -> void:
 if not Engine.is_editor_hint(): return
 if what==NOTIFICATION_EDITOR_PRE_SAVE: mesh=source_mesh
 elif what==NOTIFICATION_EDITOR_POST_SAVE: _schedule()

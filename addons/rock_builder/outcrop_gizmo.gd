@tool
extends EditorNode3DGizmoPlugin
const Outcrop=preload("res://addons/rock_builder/outcrop.gd")
var undo: EditorUndoRedoManager
func _init() -> void:
 create_handle_material("handles")
 create_material("outline",Color(1,0.65,0.15))
func _has_gizmo(node: Node3D) -> bool: return node is Outcrop
func _get_gizmo_name() -> String: return "Affioramento"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
 gizmo.clear()
 var node=gizmo.get_node_3d()
 var lines := PackedVector3Array()
 for ring in node.rings():
  for i in ring.size():
   for p in [ring[i],ring[(i+1)%ring.size()]]: lines.append(Vector3(p.x,node.height,p.y))
 gizmo.add_lines(lines,get_material("outline",gizmo)); gizmo.add_collision_segments(lines)
 var handles := PackedVector3Array([Vector3(0,node.height,0)])
 var ids := PackedInt32Array([0])
 if node.shape_kind==2:
  handles.append(Vector3(node.volume_size.x/2,node.height/2,0)); ids.append(1)
  handles.append(Vector3(0,node.height/2,node.volume_size.y/2)); ids.append(2)
 else:
  var rings: Array=[node.outline]; rings.append_array(node.holes if node.shape_kind==0 else [])
  for r in rings.size():
   for i in rings[r].size():
    var p: Vector2=rings[r][i]
    handles.append(Vector3(p.x,0,p.y)); ids.append(100+r*256+i)
  if node.shape_kind==1 and node.outline.size()>1:
   var p: Vector2=node.outline[0]
   handles.append(Vector3(p.x+node.path_width/2,0,p.y)); ids.append(3)
 if node.edit_rocks:
  for i in node.rock_positions.size(): handles.append(node.rock_positions[i]); ids.append(100000+i)
 gizmo.add_handles(handles,get_material("handles",gizmo),ids)
func _get_handle_name(_gizmo: EditorNode3DGizmo,id: int,_secondary: bool) -> String:
 if id>=100000: return "Sposta roccia"
 if id>=100: return "Contorno / buco"
 return ["Altezza","Larghezza volume","Profondità volume","Larghezza percorso"][id]
func _get_handle_value(gizmo: EditorNode3DGizmo,_id: int,_secondary: bool) -> Variant:
 return gizmo.get_node_3d().snapshot()
func _set_handle(gizmo: EditorNode3DGizmo,id: int,_secondary: bool,camera: Camera3D,screen_pos: Vector2) -> void:
 var node=gizmo.get_node_3d(); node.begin_edit()
 var inverse: Transform3D=node.global_transform.affine_inverse()
 var origin: Vector3=inverse*camera.project_ray_origin(screen_pos)
 var direction: Vector3=inverse.basis*camera.project_ray_normal(screen_pos)
 if id==0:
  var pair := Geometry3D.get_closest_points_between_segments(Vector3(0,0,0),Vector3(0,100,0),origin,origin+direction*10000)
  node.height=pair[0].y
 else:
  var y: float=node.height/2 if id in [1,2] else 0.0
  if id>=100000: y=node.rock_positions[id-100000].y
  var hit=Plane(Vector3.UP,y).intersects_ray(origin,direction)
  if hit==null: return
  if id==1: node.volume_size=Vector2(maxf(1,hit.x*2),node.volume_size.y)
  elif id==2: node.volume_size=Vector2(node.volume_size.x,maxf(1,hit.z*2))
  elif id==3: node.path_width=absf(hit.x-node.outline[0].x)*2
  elif id>=100000:
   var index := id-100000; var key: String=node.rock_keys[index]
   var old: Vector3=node.rock_offsets.get(key,Vector3.ZERO)
   var shift: Vector3=hit-node.rock_positions[index]; shift.y=0
   node.rock_offsets[key]=old+shift
   node.rock_positions[index]+=shift
   var rock=node._rocks.get_node(NodePath(key)); rock.position+=shift
   node.update_gizmos()
  else:
   var r := (id-100)/256; var i := (id-100)%256
   if r==0:
    var points: PackedVector2Array=node.outline.duplicate(); points[i]=Vector2(hit.x,hit.z); node.outline=points
   else:
    var holes: Array[PackedVector2Array]=node.holes.duplicate(true)
    holes[r-1][i]=Vector2(hit.x,hit.z); node.holes=holes
func _commit_handle(gizmo: EditorNode3DGizmo,_id: int,_secondary: bool,restore: Variant,cancel: bool) -> void:
 var node=gizmo.get_node_3d()
 if cancel or not Outcrop.Geometry.validate(node.rings()).is_empty(): node.apply_state(restore)
 else:
  undo.create_action("Modifica affioramento")
  undo.add_do_method(node,"apply_state",node.snapshot()); undo.add_undo_method(node,"apply_state",restore)
  undo.commit_action(false)
 node.end_edit()

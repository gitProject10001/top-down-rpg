@tool
extends EditorPlugin
const Outcrop=preload("res://addons/rock_builder/outcrop.gd")
var gizmo=preload("res://addons/rock_builder/outcrop_gizmo.gd").new()
var bar: HBoxContainer
var hint: Label
var target: Node3D
var drawing := false
var draw_hole := false
var stroke := PackedVector2Array()
var mouse_down := false
var old_state := {}
var draw_base_y := 0.0
var draw_camera: Camera3D
var excluded_bodies: Array[RID]=[]
func _enter_tree() -> void:
 gizmo.undo=get_undo_redo(); add_node_3d_gizmo_plugin(gizmo)
 add_custom_type("RockOutcrop","Node3D",Outcrop,EditorInterface.get_base_control().get_theme_icon("MeshInstance3D","EditorIcons"))
 add_tool_menu_item("Crea affioramento · area",_create.bind(0))
 add_tool_menu_item("Crea affioramento · percorso",_create.bind(1))
 add_tool_menu_item("Crea affioramento · volume",_create.bind(2))
 add_tool_menu_item("Crea roccia naturale · area",_create.bind(0,1))
 add_tool_menu_item("Crea roccia naturale · percorso",_create.bind(1,1))
 add_tool_menu_item("Crea roccia naturale · volume",_create.bind(2,1))
 bar=HBoxContainer.new()
 for spec in [["Disegna contorno",false],["Disegna buco",true]]:
  var button := Button.new(); button.text=spec[0]; button.pressed.connect(_start.bind(spec[1])); bar.add_child(button)
 var finish := Button.new(); finish.text="Applica disegno"; finish.pressed.connect(_finish); bar.add_child(finish)
 var cancel := Button.new(); cancel.text="Annulla"; cancel.pressed.connect(_cancel); bar.add_child(cancel)
 hint=Label.new(); bar.add_child(hint)
 add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU,bar); bar.hide()
 set_input_event_forwarding_always_enabled()
 if "--outcrop-editor-test" in OS.get_cmdline_user_args(): call_deferred("_run_editor_test")
func _exit_tree() -> void:
 _cancel()
 for label in ["Crea roccia naturale · area","Crea roccia naturale · percorso","Crea roccia naturale · volume"]: remove_tool_menu_item(label)
 remove_node_3d_gizmo_plugin(gizmo); remove_custom_type("RockOutcrop")
 for label in ["Crea affioramento · area","Crea affioramento · percorso","Crea affioramento · volume"]: remove_tool_menu_item(label)
 remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU,bar); bar.queue_free()
func _handles(object: Object) -> bool: return object is Outcrop
func _edit(object: Object) -> void:
 if target!=object: _cancel()
 target=object as Node3D
func _make_visible(value: bool) -> void:
 bar.visible=value
 if not value: _cancel()
func _create(kind: int,style: int=0) -> void:
 var root := EditorInterface.get_edited_scene_root()
 if root==null: return
 var node := Outcrop.new(); node.name="Affioramento"; node.shape_kind=kind; node.formation_style=style
 if style==1: node.walkable=false
 if kind==1: node.outline=PackedVector2Array([Vector2(-5,0),Vector2(5,0)])
 var undo := get_undo_redo(); undo.create_action("Crea affioramento")
 undo.add_do_method(root,"add_child",node,true); undo.add_do_property(node,"owner",root)
 undo.add_do_reference(node); undo.add_undo_method(root,"remove_child",node); undo.commit_action()
 EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(node)
 EditorInterface.edit_node(node)
func _start(hole: bool) -> void:
 if not is_instance_valid(target) or target.shape_kind==2: return
 if hole and target.shape_kind!=0: return
 _cancel(); excluded_bodies.clear(); _collect_bodies(target); old_state=target.snapshot(); drawing=true; draw_hole=hole; draw_base_y=0; stroke.clear()
 hint.text="Trascina o clicca sul terreno; Invio applica, Esc annulla"
func _cancel() -> void:
 drawing=false; mouse_down=false; stroke.clear()
 if is_instance_valid(hint): hint.text=""
 update_overlays()
func _finish() -> void:
 if not drawing or not is_instance_valid(target): return
 if stroke.size()<(2 if target.shape_kind==1 else 3):
  hint.text="Aggiungi altri punti"; return
 var next := old_state.duplicate(true)
 if draw_hole: next.holes.append(stroke.duplicate())
 else:
  next.outline=stroke.duplicate(); next.holes=[]
  next.position=old_state.position+target.basis*Vector3(0,draw_base_y,0)
 target.apply_state(next); target.rebuild()
 if not target.last_error.is_empty():
  hint.text=target.last_error; target.apply_state(old_state); target.rebuild(); return
 var undo := get_undo_redo(); undo.create_action("Disegna affioramento")
 undo.add_do_method(target,"apply_state",next); undo.add_undo_method(target,"apply_state",old_state); undo.commit_action(false)
 _cancel()
func _forward_3d_gui_input(camera: Camera3D,event: InputEvent) -> int:
 if not drawing or not is_instance_valid(target): return AFTER_GUI_INPUT_PASS
 if event is InputEventKey and event.pressed:
  if event.keycode==KEY_ESCAPE: _cancel(); return AFTER_GUI_INPUT_STOP
  if event.keycode==KEY_ENTER: _finish(); return AFTER_GUI_INPUT_STOP
  if event.keycode==KEY_BACKSPACE and not stroke.is_empty(): stroke.resize(stroke.size()-1); update_overlays(); return AFTER_GUI_INPUT_STOP
 if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
  mouse_down=event.pressed
  if event.pressed: _point(camera,event.position,true)
  return AFTER_GUI_INPUT_STOP
 if event is InputEventMouseMotion and mouse_down:
  _point(camera,event.position,false); return AFTER_GUI_INPUT_STOP
 return AFTER_GUI_INPUT_PASS
func _point(camera: Camera3D,screen: Vector2,force: bool) -> void:
 if stroke.size()>=256: return
 draw_camera=camera
 var origin := camera.project_ray_origin(screen); var ray := camera.project_ray_normal(screen)
 var point: Variant=null
 var world := target.get_world_3d()
 if world:
  var query := PhysicsRayQueryParameters3D.create(origin,origin+ray*10000)
  query.exclude=excluded_bodies
  var hit := world.direct_space_state.intersect_ray(query)
  if not hit.is_empty(): point=hit.position
 if point==null:
  var terrains := EditorInterface.get_edited_scene_root().find_children("*","Node3D",true,false)
  var nearest := INF
  for terrain in terrains:
   if terrain.has_method("ray_surface"):
    var sampled: Vector3=terrain.ray_surface(origin,ray)
    if sampled.is_finite() and origin.distance_squared_to(sampled)<nearest:
     point=sampled; nearest=origin.distance_squared_to(sampled)
 if point==null: point=Plane(target.global_basis.y.normalized(),target.global_position).intersects_ray(origin,ray)
 if point==null: return
 var local: Vector3=target.to_local(point); var p := Vector2(local.x,local.z)
 if not stroke.is_empty() and p.distance_to(stroke[-1])<(0.05 if force else 0.75): return
 if stroke.is_empty() and not draw_hole: draw_base_y=local.y
 stroke.append(p); hint.text="%d punti · Invio applica · Backspace elimina · Esc annulla"%stroke.size(); update_overlays()
func _forward_3d_draw_over_viewport(control: Control) -> void:
 if not drawing or stroke.is_empty() or not is_instance_valid(target): return
 var camera := draw_camera
 if not is_instance_valid(camera): return
 var points := PackedVector2Array()
 for p in stroke:
  var world := target.to_global(Vector3(p.x,draw_base_y,p.y))
  if camera.is_position_behind(world): return
  points.append(camera.unproject_position(world))
 if points.size()>1: control.draw_polyline(points,Color.ORANGE,2,true)
 for p in points: control.draw_circle(p,3,Color.ORANGE)

func _run_editor_test() -> void:
 for i in 100:
  if EditorInterface.get_edited_scene_root()!=null: break
  await get_tree().create_timer(0.1).timeout
 await preload("res://tools/check_rock_outcrop_editor.gd").new().run(self)

func _collect_bodies(node: Node) -> void:
 if node is CollisionObject3D: excluded_bodies.append(node.get_rid())
 for child in node.get_children(true): _collect_bodies(child)

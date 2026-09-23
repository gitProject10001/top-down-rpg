extends Node
var root: Window
var cycle: Node
var failed:=false
func _ready() -> void:
 root=get_tree().root
 call_deferred("run")
func check(ok: bool, message: String) -> void:
 if not ok: failed=true; push_error(message)
func click(point: Vector2) -> void:
 var motion:=InputEventMouseMotion.new(); motion.position=point; motion.global_position=point
 root.push_input(motion,true)
 for down in [true,false]:
  var event:=InputEventMouseButton.new(); event.position=point; event.global_position=point
  event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down
  root.push_input(event,true)
  await get_tree().process_frame
func button(text: String) -> BaseButton:
 for node in cycle.panel.find_children("*","BaseButton",true,false):
  if node.text==text: return node
 return null
func run() -> void:
 root.size=Vector2i(1152,648)
 var container: Node
 if has_node("Integrated"):
  container=get_node("Integrated")
  for i in 90: await get_tree().process_frame
  cycle=container.day_cycle
 else:
  container=SubViewportContainer.new(); container.size=Vector2(1152,648)
  container.mouse_filter=Control.MOUSE_FILTER_IGNORE; container.stretch=true; root.add_child(container)
  var view:=SubViewport.new(); view.size=Vector2i(1152,648); view.handle_input_locally=false; container.add_child(view)
  var sun:=DirectionalLight3D.new(); sun.name="Sun"; view.add_child(sun)
  var world:=WorldEnvironment.new(); world.name="WorldEnvironment"; world.environment=Environment.new(); view.add_child(world)
  cycle=preload("res://addons/environment_builder/day_cycle.gd").new(); view.add_child(cycle); cycle.configure(view)
 cycle.clock_paused=true
 var key:=InputEventKey.new(); key.keycode=KEY_F6; key.pressed=true
 root.push_input(key,true)
 for i in 4: await get_tree().process_frame
 check(cycle.panel.visible,"F6 opens panel through input routing")
 check(cycle.panel.get_viewport()==root,"debug UI uses the Window viewport")
 await click(button("Mezzanotte").get_global_rect().get_center())
 check(is_zero_approx(cycle.hour),"midnight button receives mouse click")
 await click(button("×60").get_global_rect().get_center())
 check(cycle.speed==60,"speed button receives mouse click")
 var pause:=button("Ferma orologio")
 await click(pause.get_global_rect().get_center())
 check(pause.button_pressed and cycle.clock_paused,"pause checkbox receives mouse click")
 var rect: Rect2=cycle.slider.get_global_rect()
 await click(rect.position+Vector2(rect.size.x*.72,rect.size.y*.5))
 check(cycle.hour>15 and cycle.hour<20,"hour slider receives mouse click")
 root.push_input(key,true); await get_tree().process_frame
 check(not cycle.panel.visible,"F6 closes panel")
 print("DAY_CYCLE_MOUSE_INPUT ","FAIL" if failed else "PASS")
 container.queue_free(); await get_tree().process_frame
 get_tree().quit(1 if failed else 0)

@tool
extends Control
var plugin: EditorPlugin
func _ready() -> void:
	custom_minimum_size = Vector2(220,220)
var _refresh := 0.0
func _process(delta: float) -> void:
	_refresh+=delta
	if _refresh>.25: _refresh=0; queue_redraw()
func _draw() -> void:
	if not is_instance_valid(plugin.stream): return
	var span := minf(size.x,size.y)
	var ground: Node = plugin.stream.ground_node()
	for x in range(44):
		for z in range(44):
			var p: Vector2 = plugin.stream.bounds.position+Vector2(x,z)/44.0*plugin.stream.bounds.size
			var density: float = smoothstep(25,100,absf(p.y))*smoothstep(-0.35,0.35,plugin.stream._noise.get_noise_2d(p.x,p.y))
			if ground.world_plan: density *= ground.world_plan.forest_density(p)*ground.generation_weight(p)
			var color := Color(0.42,0.40,0.24).lerp(Color(0.09,0.22,0.10),density)
			var h: float=ground.height_at(p.x,p.y)
			color = color.lerp(Color(0.57,0.53,0.43),clampf(h/30.0,0,1))
			if h<0: color=Color(.08,.29,.40)
			draw_rect(Rect2(Vector2(x,z)*span/44,Vector2.ONE*(span/44+1)),color)
	var center: Vector2 = ((plugin.stream.editor_center-plugin.stream.bounds.position)/plugin.stream.bounds.size)*span
	draw_circle(Vector2.ONE*span/2,3,Color.GOLD)
	for zone in ground.reserved_zones:
		draw_arc(((zone.position-plugin.stream.bounds.position)/plugin.stream.bounds.size)*span,zone.radius/plugin.stream.bounds.size.x*span,0,TAU,32,Color.GOLD,1.5)
	draw_rect(Rect2(center-Vector2.ONE*span*0.09,Vector2.ONE*span*0.18),Color.WHITE,false,1)
	for edit in plugin.stream.world_edits:
		if edit.kind == "tree": draw_circle(((Vector2(edit.position.x,edit.position.z)-plugin.stream.bounds.position)/plugin.stream.bounds.size)*span,1,Color.LIGHT_GREEN)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(plugin.stream):
		plugin.stream.follow_editor_camera = false
		plugin.stream.editor_center = plugin.stream.bounds.position+event.position/minf(size.x,size.y)*plugin.stream.bounds.size
		accept_event()

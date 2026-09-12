@tool
extends Control
var plugin: EditorPlugin
func _ready() -> void:
	custom_minimum_size = Vector2(220,220)
func _process(_delta: float) -> void: queue_redraw()
func _draw() -> void:
	if not is_instance_valid(plugin.stream): return
	var span := minf(size.x,size.y)
	var ground: Node = plugin.stream.get_node("../Ground")
	for x in range(44):
		for z in range(44):
			var p := Vector2(x,z)*39.36-Vector2.ONE*866
			var density: float = smoothstep(25,100,absf(p.y))*smoothstep(-0.35,0.35,plugin.stream._noise.get_noise_2d(p.x,p.y))
			if ground.world_plan: density *= ground.world_plan.forest_density(p)*ground.generation_weight(p)
			var color := Color(0.42,0.40,0.24).lerp(Color(0.09,0.22,0.10),density)
			color = color.lerp(Color(0.57,0.53,0.43),clampf(ground.height_at(p.x,p.y)/30.0,0,1))
			draw_rect(Rect2(Vector2(x,z)*span/44,Vector2.ONE*(span/44+1)),color)
	var center: Vector2 = (plugin.stream.editor_center/1732+Vector2.ONE*0.5)*span
	draw_circle(Vector2.ONE*span/2,3,Color.GOLD)
	for zone in ground.reserved_zones:
		draw_arc((zone.position/1732+Vector2.ONE*0.5)*span,zone.radius/1732*span,0,TAU,32,Color.GOLD,1.5)
	draw_rect(Rect2(center-Vector2.ONE*span*0.09,Vector2.ONE*span*0.18),Color.WHITE,false,1)
	for edit in plugin.stream.world_edits:
		if edit.kind == "tree": draw_circle((Vector2(edit.position.x,edit.position.z)/1732+Vector2.ONE*0.5)*span,1,Color.LIGHT_GREEN)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(plugin.stream):
		plugin.stream.follow_editor_camera = false
		plugin.stream.editor_center = (event.position/minf(size.x,size.y)-Vector2.ONE*0.5)*1732
		accept_event()

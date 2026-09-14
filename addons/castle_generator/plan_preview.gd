@tool
extends Control
var plan: Dictionary={}
func _ready() -> void:
 custom_minimum_size=Vector2(0,240)
 resized.connect(queue_redraw)
func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("232b30"))
 if plan.is_empty(): return
 var span: Vector2=plan.span
 var scale_value := minf((size.x-32)/(span.x+8),(size.y-32)/(span.y+8))
 var offset := (size-(span+Vector2(8,8))*scale_value)*0.5
 var a := offset+Vector2(4,4)*scale_value
 var area := Rect2(a,span*scale_value)
 draw_rect(area,Color("59644a"))
 draw_rect(area,Color("c3c3b5"),false,3)
 for point in [area.position,area.position+Vector2(area.size.x,0),area.end,area.position+Vector2(0,area.size.y)]:
  draw_circle(point,4*scale_value,Color("858d95"))
 for building in plan.buildings:
  var point := Vector2(building.position.x,building.position.z+span.y)
  var box := Rect2(a+(point-building.size*0.5)*scale_value,building.size*scale_value)
  draw_rect(box,Color("cead78") if building.id=="keep" else Color("7bbbc3"))
 var entry := a+Vector2(span.x*0.5,span.y)*scale_value
 draw_line(entry-Vector2(5,0),entry+Vector2(5,0),Color("efca54"),5)

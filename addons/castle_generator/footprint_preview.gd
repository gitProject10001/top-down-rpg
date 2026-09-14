@tool
extends Control
var shapes: Dictionary={}
var span := Vector2(26,26)
var conflict := false
func _ready() -> void:
 custom_minimum_size=Vector2(360,280)
 resized.connect(queue_redraw)
func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("242e32"))
 var factor := minf((size.x-24)/span.x,(size.y-24)/span.y)
 var offset := (size-span*factor)*0.5
 draw_rect(Rect2(offset,span*factor),Color("59624a"))
 draw_rect(Rect2(offset+Vector2(5,5)*factor,(span-Vector2(10,10))*factor),Color("c9c5aa"),false,1)
 var palette := [Color("d5ad6d"),Color("72baca")]
 var index := 0
 for id in shapes:
  var color: Color=Color("e07868") if conflict else palette[index%2]
  for polygon in shapes[id]:
   var points := PackedVector2Array()
   for p in polygon: points.append(offset+Vector2(p.x,p.y+span.y)*factor)
   draw_colored_polygon(points,Color(color,0.5))
   points.append(points[0]); draw_polyline(points,color,2,true)
  index+=1

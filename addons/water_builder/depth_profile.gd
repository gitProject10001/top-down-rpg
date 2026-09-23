@tool
extends Resource
## Local bathymetry. Positive depths below the water plane, independent of lighting.
@export_range(.1,30,.1) var maximum_depth := 5.0:
 set(value): maximum_depth=value; emit_changed()
@export_range(1,40,.5) var shelf_width := 14.0:
 set(value): shelf_width=value; emit_changed()
@export var pockets: Array[Dictionary] = []:
 set(value): pockets=value; emit_changed()
@export_range(.2,1.5,.05) var wading_limit := .65:
 set(value): wading_limit=value; emit_changed()
@export var block_deep_water := true:
 set(value): block_deep_water=value; emit_changed()
func sample(point: Vector2, shore: float) -> float:
 var depth:=maximum_depth*smoothstep(0.0,shelf_width,shore)
 for pocket in pockets:
  var weight:=1.0-smoothstep(0,float(pocket.radius),point.distance_to(pocket.center))
  depth+=float(pocket.depth)*weight
 return maxf(.015,depth)

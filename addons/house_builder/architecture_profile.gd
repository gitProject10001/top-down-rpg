@tool
extends Resource
## Geometric starting proportions. Does not change materials or building function.
@export var profile_id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var default_width := 5.0
@export var default_depth := 6.0
@export var default_wall_height := 3.8
@export var default_roof_height := 2.5
func proportions() -> Dictionary:
	return {"width":default_width,"depth":default_depth,"wall_height":default_wall_height,"roof_height":default_roof_height}

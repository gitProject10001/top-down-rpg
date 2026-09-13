@tool
extends Node3D
## Group of independently authored towers; links are stored on curtains.
@export var courtyard_entry := false
@export var entry_position := Vector3(8,0.15,4)

func primary_tower() -> Node3D:
	for child in get_children():
		if child.has_method("footprint_vertices"): return child
	return null
func curtains() -> Array:
	var result: Array=[]
	for tower in get_children():
		for child in tower.get_children():
			if child.has_method("fortification_host"): result.append(child)
	return result
func rebuild() -> void:
	for tower in get_children():
		if tower.has_method("rebuild"): tower.rebuild()
	for wall in curtains(): wall.rebuild()
	for tower in get_children():
		if tower.has_method("rebuild"): tower.rebuild()

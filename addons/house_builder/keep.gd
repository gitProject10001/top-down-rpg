@tool
extends "res://addons/house_builder/volume.gd"
## A keep is an independently editable House Builder volume, not a curtain vertex.
func _init() -> void:
	attached=false; canopy_roof=0; archetype_id="keep"

func contains_footprint(point: Vector3, margin: float=0.0) -> bool:
	return absf(point.x)<width*0.5-margin and absf(point.z)<depth*0.5-margin

func supports_accessory_volumes() -> bool: return true

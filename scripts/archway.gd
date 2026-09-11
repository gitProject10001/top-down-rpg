class_name Archway
extends Node3D
## AN OPEN ARCH standing in a Floorplan opening: a legend `door` row whose door is never shut.
## It exists so two corridor segments or a hall and its corridor can be separate REGIONS (each
## masked on its own) while the room mask (scripts/room_visibility.gd) still walks from one to
## the other — the mask asks a door only for `is_open`, and this one always says yes. Its
## collision, if any, must stay OUT of the opening: the mask's line-of-sight ray to the next
## door passes through here.

## The opening's width; the visual is scaled from `native_width`.
@export var width_m := 2.0
@export var native_width := 2.0

var is_open := true


func _ready() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model != null and native_width > 0.0:
		model.scale.x = width_m / native_width

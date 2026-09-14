@tool
extends Resource
## Composition constraints, independent of meshes/materials. Dimensions in metres.
@export var seed_value := 1
@export var minimum_span := Vector2(26,26)
@export var maximum_span := Vector2(27,27)
@export_range(0,1) var minimum_open_fraction := 0.65
@export var rules: Resource = preload("res://addons/castle_generator/single_court_rules.gd").new()

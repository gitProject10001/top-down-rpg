@tool
extends Resource
## Shared masonry authoring, independent of the scene's lighting preset.
@export var stone_color := Color(.32,.305,.27):
	set(value): stone_color=value; emit_changed()
@export var block_size := Vector2(.72,.37):
	set(value): block_size=value.max(Vector2(.2,.15)); emit_changed()
@export_range(0.0,1.0,.01) var weathering := .5:
	set(value): weathering=clampf(value,0,1); emit_changed()

func apply(material: ShaderMaterial,source_value: float,pattern := false,height_offset := 0.0) -> void:
	material.set_shader_parameter("masonry_finish_enabled",true)
	material.set_shader_parameter("masonry_tint",Vector3(stone_color.r,stone_color.g,stone_color.b))
	material.set_shader_parameter("masonry_block_size",block_size)
	material.set_shader_parameter("masonry_weathering",weathering)
	material.set_shader_parameter("masonry_source_value",source_value)
	material.set_shader_parameter("masonry_courses",pattern)
	material.set_shader_parameter("masonry_height_offset",height_offset)

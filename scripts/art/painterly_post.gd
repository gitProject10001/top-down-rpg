@tool
extends CanvasLayer
## Screen-only experiment. Hidden pass is a true bypass; UI outside this viewport stays sharp.
@export var enabled := true:
	set(value):
		enabled=value
		if is_node_ready(): $Filter.visible=enabled
func _ready() -> void:
	$Filter.visible=enabled
func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_P:
		enabled=not enabled
		print("PAINTERLY_POST ",enabled)
		get_viewport().set_input_as_handled()

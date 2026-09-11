extends Node
## Autoload "Pause" — pause menu (Esc / controller Start): dim overlay, Resume and Exit.
##
## Pausing uses the SceneTree's real pause (get_tree().paused): gameplay, tweens and physics all
## freeze for free because game nodes default to PAUSE_MODE_PAUSABLE — only this menu keeps
## processing (PROCESS_MODE_ALWAYS). Built in code like Dialogue/Hud: zero per-scene setup.

const ACCENT := Color(1.0, 0.82, 0.5)

var _root: Control
var _resume_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working while the tree is paused

	var layer := CanvasLayer.new()
	layer.layer = 30                             # above everything (dialogue is 25)
	add_child(layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	layer.add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(vb)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", ACCENT)
	vb.add_child(title)

	_resume_btn = _button("Resume", vb)
	_resume_btn.pressed.connect(toggle)
	# The one hard-quit path in the codebase, so it is also the last chance to flush the map.
	_button("Exit", vb).pressed.connect(func():
		MapData.save()
		get_tree().quit())


func _button(text: String, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 44)
	b.add_theme_font_size_override("font_size", 22)
	parent.add_child(b)
	return b


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		# Esc/Start with the map up BACKS OUT of the map instead of stacking a second screen on it.
		# Handled HERE, in the owner of the action, rather than by letting MapScreen consume the
		# event first: which autoload's _input runs first is an ordering detail of the engine's
		# propagation, and behaviour must not rest on it.
		if MapScreen.open:
			MapScreen.close()
		else:
			toggle()
		get_viewport().set_input_as_handled()


## Who is currently asking for a frozen tree. See hold().
var _holds := {}


## THE ONE OWNER OF get_tree().paused. Anything that wants the game frozen asks here, by name, and
## the tree runs again only when every hold is released.
##
## Not ceremony: toggle() below DERIVES its state from the flag, so any second writer desynchronises
## it. Open the map (which pauses), press Esc, hit Resume — and the world unfreezes with the map
## still on screen, because the menu read a `paused` it did not set. One owner, no such bug, and the
## next system that needs a freeze gets it for free.
func hold(who: StringName, on: bool) -> void:
	if on:
		_holds[who] = true
	else:
		_holds.erase(who)
	get_tree().paused = not _holds.is_empty()


func toggle() -> void:
	var showing := not _root.visible
	_root.visible = showing
	hold(&"menu", showing)
	if showing:
		_resume_btn.grab_focus()          # controller/keyboard navigation works immediately

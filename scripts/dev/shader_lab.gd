extends Node3D
## Shader lab controls. Deliberately tiny — the scene itself is the tool.
##
## The single most useful thing when judging a toon ramp is watching the TERMINATOR MOVE, so the key
## light orbits: LEFT/RIGHT yaw it, UP/DOWN pitch it, SPACE toggles auto-orbit. TAB swaps every test
## object to the debug visualiser, and 1-6 pick its mode (see shaders/debug_visualize.gdshader).
##
## Nothing here affects the game — this scene exists only to look at the shader with no other
## variables in play.

const DEBUG_SHADER := preload("res://shaders/debug_visualize.gdshader")

@export var auto_orbit := false
@export var orbit_speed := 0.4          ## radians/sec when auto-orbiting
@export var manual_speed := 1.2         ## radians/sec on the arrow keys

@onready var _key: DirectionalLight3D = $KeyLight
@onready var _subjects: Node3D = $Subjects

var _debug_on := false
var _debug_mat: ShaderMaterial
var _saved: Dictionary = {}             ## MeshInstance3D -> its real material, while debugging
var _yaw := 0.0
var _pitch := -0.6


func _ready() -> void:
	_yaw = _key.rotation.y
	_pitch = _key.rotation.x
	_debug_mat = ShaderMaterial.new()
	_debug_mat.shader = DEBUG_SHADER
	_print_help()


func _process(delta: float) -> void:
	if auto_orbit:
		_yaw += orbit_speed * delta
	if Input.is_key_pressed(KEY_LEFT):
		_yaw -= manual_speed * delta
	if Input.is_key_pressed(KEY_RIGHT):
		_yaw += manual_speed * delta
	if Input.is_key_pressed(KEY_UP):
		_pitch = clampf(_pitch - manual_speed * delta, -1.5, -0.05)
	if Input.is_key_pressed(KEY_DOWN):
		_pitch = clampf(_pitch + manual_speed * delta, -1.5, -0.05)
	_key.rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			auto_orbit = not auto_orbit
		KEY_TAB:
			_toggle_debug()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			var m := (event as InputEventKey).keycode - KEY_1
			_debug_mat.set_shader_parameter("mode", m)
			if not _debug_on:
				_toggle_debug()
			print("[lab] debug mode %d" % m)


## Swap every test mesh to the debug visualiser and back. Uses material_override so the real
## material (and the outline next_pass) is untouched underneath.
func _toggle_debug() -> void:
	_debug_on = not _debug_on
	# keep the debug light vector roughly matching the key light so mode 2 reads correctly
	_debug_mat.set_shader_parameter("light_dir", -_key.global_transform.basis.z)
	for mi: MeshInstance3D in _all_meshes(_subjects):
		mi.material_override = _debug_mat if _debug_on else null
	print("[lab] debug view: ", "ON" if _debug_on else "OFF")


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


func _print_help() -> void:
	print("""
[shader lab]
  LEFT/RIGHT   orbit key light      SPACE  auto-orbit
  UP/DOWN      raise/lower light    TAB    debug visualiser
  1..6         debug mode: 1 normals  2 UV  3 N.L  4 vertex colour  5 world pos  6 checker
  Tune the look on assets/materials/toon_character.tres (Inspector) - it drives the game too.
""")

extends SpotLight3D
## Scene-local directional player lamp. Follows the same facing pivot as sword attacks.
func _ready() -> void:
	position = Vector3(.22,1.30,-.36)
	rotation_degrees.x = -9
	spot_range = 12
	spot_angle = 43
	spot_angle_attenuation = .65
	light_color = Color(1,.83,.59)
	light_energy = 3.5
	light_indirect_energy = .6
	shadow_enabled = true
	shadow_bias = .025
	shadow_normal_bias = .25
	light_bake_mode = Light3D.BAKE_DYNAMIC
	visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_light"):
		visible = not visible
		get_viewport().set_input_as_handled()

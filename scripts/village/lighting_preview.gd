extends Node
## F6 cycles repeatable lighting conditions. Does not alter any material or exposure.
const HOURS := [8,12,18,22]
const LABELS := ["Mattino · 08:00","Mezzogiorno · 12:00","Tramonto · 18:00","Notte · 22:00"]
var preset := -1
var label: Label
var _f6_was_down := false

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer=80
	add_child(layer)
	label=Label.new()
	label.position=Vector2(22,68)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(label)
	label.hide()

func _process(_delta: float) -> void:
	# The village runs inside a SubViewport: poll just like its camera controls.
	var down := Input.is_physical_key_pressed(KEY_F6)
	if down and not _f6_was_down:
		apply_preset((preset+1)%4)
	_f6_was_down=down

func apply_preset(index: int) -> void:
	preset=clampi(index,0,3)
	var world := get_parent()
	var sun: DirectionalLight3D=world.get_node("Sun")
	var fill: DirectionalLight3D=world.get_node("SoftSkyFill")
	var env: Environment=world.get_node("WorldEnvironment").environment
	var rotations := [Vector3(-25,-75,0),Vector3(-72,-25,0),Vector3(-12,105,0),Vector3(-38,-55,0)]
	var colors := [Color(1.0,0.85,0.69),Color(1.0,0.97,0.91),Color(1.0,0.57,0.30),Color(0.53,0.65,1.0)]
	var energies := [1.15,1.35,0.85,0.16]
	var ambient := [0.323,0.418,0.2375,0.114]
	sun.rotation_degrees=rotations[preset]
	sun.light_color=colors[preset]
	sun.light_energy=energies[preset]
	# Low bias retains contact under shallow overlapping tiles.
	sun.shadow_bias=0.045
	sun.shadow_normal_bias=0.25
	fill.light_color=Color(0.66,0.75,0.94)
	fill.light_energy=[0.128,0.16,0.08,0.036][preset]
	env.ambient_light_color=Color(0.61,0.70,0.88)
	env.ambient_light_energy=ambient[preset]
	if is_instance_valid(label):
		label.text=LABELS[preset]+"   ·   F6 cambia ora"
		label.show()
	print("ROOF_LIGHTING hour=",HOURS[preset])

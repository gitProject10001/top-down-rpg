@tool
extends Node
const Profile = preload("res://addons/environment_builder/day_cycle_profile.gd")
@export var profile: Resource = Profile.new()
@export_range(0, 24, .01) var hour := 10.0:
 set(value): hour=fposmod(value,24.0); apply_time()
@export_range(-60,60,.1) var speed := 1.0
@export var clock_paused := false
var view: Node
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world: WorldEnvironment
var fill: DirectionalLight3D
var waters: Array=[]
var lights: Array=[]
var emissives: Array=[]
var debug_layer: CanvasLayer
var panel: PanelContainer
var slider: HSlider
var readout: Label
var _updating := false
func configure(target: Node) -> void:
 if view==target and is_instance_valid(moon):
  apply_time(); return
 view=target
 sun=view.get_node("Sun"); world=view.get_node("WorldEnvironment")
 fill=view.get_node_or_null("SoftSkyFill")
 moon=DirectionalLight3D.new(); moon.name="Moon"; moon.light_color=Color(.48,.62,1.0)
 moon.shadow_enabled=true; moon.directional_shadow_max_distance=90
 view.add_child(moon)
 for node in view.find_children("*","Node",true,false):
  if node.has_method("contains_point"): waters.append(node)
  if node is OmniLight3D or node is SpotLight3D:
   lights.append({"node":node,"energy":node.light_energy})
   node.shadow_enabled=false
 refresh_materials()
 hour=profile.initial_hour
 apply_time()
 if not Engine.is_editor_hint(): _make_debug()
func advance(seconds: float) -> void:
 if not clock_paused: hour+=seconds*24.0/(maxf(profile.real_minutes,1)*60.0)*speed
func _process(delta: float) -> void:
 if Engine.is_editor_hint(): return
 advance(delta)

func daylight() -> float:
 return smoothstep(profile.sunrise-.45,profile.sunrise+.65,hour)*(1.0-smoothstep(profile.sunset-.65,profile.sunset+.45,hour))
func apply_time() -> void:
 if not is_instance_valid(world) or not is_instance_valid(sun): return
 var day:=daylight()
 var arc: float=(hour-profile.sunrise)/(profile.sunset-profile.sunrise)*PI
 sun.rotation_degrees=Vector3(-rad_to_deg(asin(clampf(sin(arc),-1,1)))*.78, -65+(hour-5)*8,0)
 sun.light_energy=profile.sun_energy*day
 sun.light_color=profile.dusk_sun.lerp(profile.day_sun,smoothstep(.0,.45,maxf(0,sin(arc))))
 sun.shadow_enabled=day>.05
 var night_hours: float=24.0-(profile.sunset-profile.sunrise)
 var night_elapsed:=fposmod(hour-profile.sunset,24.0)
 var moon_arc: float=night_elapsed/night_hours*PI
 moon.rotation_degrees=Vector3(-rad_to_deg(asin(clampf(sin(moon_arc),-1,1)))*.65,135+night_elapsed*10,0)
 moon.light_energy=profile.moon_energy*(1-day); moon.shadow_enabled=day<.05
 if fill: fill.light_energy=lerpf(.04,.12,day); fill.light_color=profile.night_ambient.lerp(profile.day_ambient,day)
 var env:=world.environment
 env.ambient_light_color=profile.night_ambient.lerp(profile.day_ambient,day)
 env.ambient_light_energy=lerpf(profile.night_energy,profile.day_energy,day)
 env.fog_enabled=true; env.fog_density=lerpf(.00035,.00008,day)
 env.fog_light_color=Color(.10,.15,.26).lerp(Color(.65,.72,.68),day)
 if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
  var sky: ProceduralSkyMaterial=env.sky.sky_material
  sky.sky_top_color=Color(.012,.02,.055).lerp(Color(.28,.49,.64),day)
  sky.sky_horizon_color=Color(.055,.075,.13).lerp(Color(.68,.75,.73),day)
  sky.ground_horizon_color=sky.sky_horizon_color
 for water in waters:
  if is_instance_valid(water) and is_instance_valid(water._surface):
   water._surface.material_override.set_shader_parameter("daylight",day)
 for item in lights:
  if is_instance_valid(item.node): item.node.light_energy=item.energy*lerpf(1.0,.08,day)
 for item in emissives:
  if item.material is ShaderMaterial: item.material.set_shader_parameter("night_strength",1-day)
  else: item.material.emission_energy_multiplier=item.energy*(1-day)
 if is_instance_valid(slider):
  _updating=true; slider.value=hour; readout.text="%02d:%02d  ×%.1f"%[int(hour),int(fmod(hour,1)*60),speed]; _updating=false
func _make_debug() -> void:
 # The world may live in a SubViewportContainer that ignores mouse events.
 # Draw and hit-test the debug UI in the containing Window, outside the post pass.
 var layer:=CanvasLayer.new(); layer.layer=30
 # During normal scene startup the Window is still setting up its children.
 debug_layer=layer; get_window().add_child.call_deferred(layer)
 panel=PanelContainer.new(); panel.position=Vector2(20,130); panel.custom_minimum_size=Vector2(390,160); layer.add_child(panel)
 var box:=VBoxContainer.new(); panel.add_child(box)
 readout=Label.new(); box.add_child(readout)
 slider=HSlider.new(); slider.min_value=0; slider.max_value=24; slider.step=.01; box.add_child(slider)
 slider.value_changed.connect(func(v:float):
  if not _updating: hour=v)
 var buttons:=HBoxContainer.new(); box.add_child(buttons)
 for value in [-60,-10,1,10,60]:
  var button:=Button.new(); button.text="×%d"%value; buttons.add_child(button); button.pressed.connect(func(): speed=value)
 var pause:=CheckButton.new(); pause.text="Ferma orologio"; box.add_child(pause); pause.toggled.connect(func(v:bool): clock_paused=v)
 var presets:=HBoxContainer.new(); box.add_child(presets)
 for item in [["Alba",5.5],["Mezzogiorno",12.0],["Tramonto",20.5],["Mezzanotte",0.0]]:
  var button:=Button.new(); button.text=item[0]; presets.add_child(button); button.pressed.connect(func(): hour=item[1])
 panel.hide(); apply_time()
func _input(event: InputEvent) -> void:
 if is_instance_valid(panel) and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F6:
  panel.visible=not panel.visible; get_viewport().set_input_as_handled()

func refresh_materials() -> void:
 emissives.clear()
 if not is_instance_valid(view): return
 for node in view.find_children("*","MeshInstance3D",true,false):
  if not node.mesh: continue
  for surface in node.mesh.get_surface_count():
   var material: Material=node.get_active_material(surface)
   if material is StandardMaterial3D and (material.emission_enabled or material.get_meta("night_window",false)):
    material=material.duplicate()
    if material.get_meta("night_window",false):
     material.emission_enabled=true; material.emission=Color(1,.48,.13); material.emission_energy_multiplier=.7
    node.set_surface_override_material(surface,material)
    var original: float=material.get_meta("day_cycle_base_energy",material.emission_energy_multiplier)
    material.set_meta("day_cycle_base_energy",original)
    emissives.append({"material":material,"energy":original})
   elif material is ShaderMaterial and material.shader and material.shader.resource_path=="res://addons/house_builder/recipe_detail.gdshader" and material.get_shader_parameter("window_surface")==true:
    emissives.append({"material":material})

func _exit_tree() -> void:
 if is_instance_valid(debug_layer): debug_layer.queue_free()

extends SceneTree
const Outcrop=preload("res://addons/rock_builder/outcrop.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var debug := root.get_node_or_null("Dbg")
 if debug: debug.process_mode=Node.PROCESS_MODE_DISABLED
 for layer in root.find_children("*","CanvasLayer",true,false): layer.visible=false
 var scene := Node3D.new(); scene.name="RockOutcropPlayground"; root.add_child(scene)
 var ground := MeshInstance3D.new(); ground.name="Terreno"; var plane := PlaneMesh.new(); plane.size=Vector2(60,40); ground.mesh=plane
 var mat := StandardMaterial3D.new(); mat.albedo_color=Color(0.19,0.24,0.16); ground.material_override=mat
 scene.add_child(ground); ground.owner=scene; ground.position.y=-0.1
 var area := Outcrop.new(); area.name="AreaConBuco"; area.position.x=-12
 area.outline=PackedVector2Array([Vector2(-5,-4),Vector2(0,-5),Vector2(5,-3),Vector2(6,1),Vector2(3,4),Vector2(-3,4),Vector2(-5,1)])
 area.holes=[PackedVector2Array([Vector2(-1.5,-1.5),Vector2(1.5,-1.5),Vector2(1.5,1.5),Vector2(-1.5,1.5)])]
 scene.add_child(area); area.owner=scene
 var path := Outcrop.new(); path.name="PercorsoRoccioso"; path.shape_kind=1; path.height=3.2; path.walkable=false
 path.outline=PackedVector2Array([Vector2(-3,4),Vector2(0,2),Vector2(-1,-1),Vector2(3,-4)]); path.path_width=3
 scene.add_child(path); path.owner=scene
 var volume := Outcrop.new(); volume.name="VolumeRoccioso"; volume.shape_kind=2; volume.walkable=false; volume.height=5.0; volume.position.x=12; volume.volume_size=Vector2(7,8)
 scene.add_child(volume); volume.owner=scene
 var light := DirectionalLight3D.new(); light.name="Sun"; light.rotation_degrees=Vector3(-55,-25,0); light.shadow_enabled=true; scene.add_child(light); light.owner=scene
 var env := WorldEnvironment.new(); env.name="Environment"; env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR
 env.environment.background_color=Color(0.18,0.21,0.24); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color(0.8,0.85,1); env.environment.ambient_light_energy=0.6
 scene.add_child(env); env.owner=scene
 var camera := Camera3D.new(); camera.name="Camera"; camera.position=Vector3(22,29,36); scene.add_child(camera); camera.look_at(Vector3(0,0,0)); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=34; camera.current=true; camera.owner=scene
 var natural_study := "--natural-study" in OS.get_cmdline_user_args()
 if natural_study:
  area.formation_style=1; area.walkable=true; area.height=5.5; area.rebuild()
  path.formation_style=1; path.height=4; path.rebuild()
  volume.formation_style=1; volume.height=6; volume.rebuild()
 var distribution_study := "--distribution-study" in OS.get_cmdline_user_args()
 var composition_study := "--composition-study" in OS.get_cmdline_user_args() or distribution_study
 if composition_study:
  area.free(); path.free(); volume.free()
  var cases := [[Vector2(7,13),0.65,Vector3.ONE,"Bassa"],[Vector2(7,13),4.0,Vector3.ONE,"Media"],[Vector2(7,13),9.0,Vector3.ONE,"Alta"],[Vector2(7,13),4.0,Vector3(1,0.16,1),"Scala Y"],[Vector2(13,7),3.0,Vector3.ONE,"Larga"],[Vector2(4,17),3.0,Vector3.ONE,"Lunga"]]
  if distribution_study:
   cases=[[Vector2(7,10),6.0,Vector3.ONE,"Base"],[Vector2(7,20),6.0,Vector3.ONE,"Lunghezza x2"],[Vector2(7,10),6.0,Vector3(1,1,2),"Scala Z x2"],[Vector2(7,20),6.0,Vector3.ONE,"Densita 50%"],[Vector2(7,20),6.0,Vector3.ONE,"Distanza 5 m"],[Vector2(7,20),6.0,Vector3.ONE,"Limite 4 masse"]]
  for i in cases.size():
   var sample := Outcrop.new(); sample.name=cases[i][3]; sample.formation_style=1; sample.walkable=false; sample.shape_kind=2
   sample.volume_size=cases[i][0]; sample.height=cases[i][1]; sample.scale=cases[i][2]
   if distribution_study:
    if i==3: sample.natural_density=0.5
    if i==4: sample.natural_min_spacing=5
    if i==5: sample.natural_max_rocks=4
   sample.position=Vector3((i%3-1)*19,0,(i/3)*24-12); scene.add_child(sample)
   var label := Label3D.new(); label.text=cases[i][3]; label.font_size=64; label.pixel_size=0.018; label.position=sample.position+Vector3(0,0.3,11)
   label.rotation_degrees.x=-60; scene.add_child(label)
  plane.size=Vector2(90,85); camera.size=59; camera.position=Vector3(12,55,60); camera.look_at(Vector3.ZERO)
 var scale_study := "--scale-study" in OS.get_cmdline_user_args()
 if scale_study:
  area.free(); path.free(); volume.free()
  for i in 3:
   var sample := Outcrop.new(); sample.name="ScaleStudy%d"%i
   sample.position=Vector3((i-1)*12,0,0); sample.volume_size=Vector2(7,6); sample.shape_kind=2
   sample.walkable=true; sample.height=3.0 if i<2 else 12.0
   if i==1: sample.scale=Vector3(1,4,1)
   scene.add_child(sample); sample.owner=scene
  camera.size=38; camera.position=Vector3(22,32,40); camera.look_at(Vector3(0,4,0))
 elif not natural_study and not composition_study:
  var packed := PackedScene.new(); packed.pack(scene); ResourceSaver.save(packed,"res://scenes/dev/rock_outcrop_playground.tscn")
 for i in 30: await process_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://.godot/rock_distribution_preview.png" if distribution_study else "res://.godot/rock_composition_preview.png" if composition_study else "res://.godot/rock_natural_preview.png" if natural_study else ("res://.godot/rock_scale_preview.png" if scale_study else "res://.godot/rock_outcrop_preview.png"))
 quit()

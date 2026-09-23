extends SceneTree
const Outcrop=preload("res://addons/rock_builder/outcrop.gd")
const Study=preload("res://scripts/dev/rock_parameter_study.gd")
func _initialize() -> void: call_deferred("run")
func owned(parent: Node,child: Node,scene: Node) -> void:
 parent.add_child(child); child.owner=scene
func run() -> void:
 var scene := Node3D.new(); scene.name="RockParameterStudy"; root.add_child(scene)
 var floor_mesh := MeshInstance3D.new(); floor_mesh.name="Ground"
 var plane := PlaneMesh.new(); plane.size=Vector2(180,180); floor_mesh.mesh=plane
 var material := StandardMaterial3D.new(); material.albedo_color=Color(0.20,0.26,0.18); material.roughness=1
 floor_mesh.material_override=material; floor_mesh.position.y=-0.13; owned(scene,floor_mesh,scene)
 var light := DirectionalLight3D.new(); light.name="Sun"; light.rotation_degrees=Vector3(-48,-30,0); light.shadow_enabled=true; owned(scene,light,scene)
 var environment := WorldEnvironment.new(); environment.name="Environment"; environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(0.36,0.45,0.55)
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color(0.8,0.87,1); environment.environment.ambient_light_energy=0.65; owned(scene,environment,scene)
 var cases := [
  {"name":"Montagna", "position":Vector3(-26,0,-25), "size":Vector2(20,24), "height":18.0,"rock":8.0,"medium":3.0,"small":0.65},
  {"name":"Catena_allungata", "position":Vector3(3,0,-25), "size":Vector2(10,30), "height":12.0,"rock":6.0,"medium":2.0,"small":0.45},
  {"name":"Parete_rocciosa", "position":Vector3(28,0,-24), "size":Vector2(4,25), "height":8.0,"rock":4.0,"medium":1.4,"small":0.3},
  {"name":"Campo_piccole_rocce", "position":Vector3(-26,0,7), "size":Vector2(13,16), "height":1.1,"rock":1.1,"medium":0.4,"small":0.15,"spacing":1.0,"density":0.65},
  {"name":"Affioramento_medio", "position":Vector3(0,0,6), "size":Vector2(8,13), "height":6.0,"rock":5.5,"medium":1.8,"small":0.4},
  {"name":"Parete_bassa", "position":Vector3(26,0,6), "size":Vector2(3,18), "height":3.0,"rock":2.5,"medium":0.8,"small":0.2},
  {"name":"Pianoro_con_apertura", "position":Vector3(-24,0,35), "size":Vector2(12,12), "height":4.0,"rock":4.0,"medium":1.3,"small":0.25,"walkable":true},
  {"name":"Dettaglio_sulle_superfici", "position":Vector3(2,0,32), "size":Vector2(8,10), "height":5.0,"rock":4.5,"medium":1.1,"small":0.45,"surface":1.0},
  {"name":"Solo_masse_principali", "position":Vector3(25,0,33), "size":Vector2(8,10), "height":5.0,"rock":4.5,"medium":1.1,"small":0.45,"bare":true}
 ]
 for data in cases:
  var node := Outcrop.new(); node.name=data.name; node.formation_style=1; node.shape_kind=2
  node.position=data.position; node.volume_size=data.size; node.height=data.height; node.walkable=data.get("walkable",false)
  node.natural_rock_size=data.rock; node.medium_rock_size=data.medium; node.small_rock_size=data.small
  node.natural_min_spacing=data.get("spacing",0.0); node.natural_density=data.get("density",1.0)
  node.small_surface_ratio=data.get("surface",0.55)
  if data.get("surface",0.0)>0: node.small_rock_density=0.9
  if data.get("bare",false): node.medium_rock_density=0; node.small_rock_density=0
  if node.walkable:
   node.shape_kind=0; node.outline=PackedVector2Array([Vector2(-6,-6),Vector2(6,-6),Vector2(6,6),Vector2(-6,6)])
   node.holes=[PackedVector2Array([Vector2(-1.6,-1.6),Vector2(1.6,-1.6),Vector2(1.6,1.6),Vector2(-1.6,1.6)])]
  owned(scene,node,scene)
  var label := Label3D.new(); label.name=data.name+"_Label"; label.text=str(data.name).replace("_"," ")+"\nTaglia %.1f m | H %.1f m"%[node.natural_rock_size,node.height]
  label.font_size=48; label.pixel_size=0.016; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.no_depth_test=true
  label.position=data.position+Vector3(0,2,data.size.y*0.5+2); owned(scene,label,scene)
 var hud := CanvasLayer.new(); hud.name="Controls"; owned(scene,hud,scene)
 var text := Label.new(); text.text="ROCK LAB — personaggio e camera del gioco\nWASD: movimento | Controlli di salto e combattimento del gioco\nModifica i nodi in Inspector: Distribuzione naturale / Rocce medie / Rocce piccole"
 text.position=Vector2(20,18); text.add_theme_font_size_override("font_size",20); text.add_theme_color_override("font_shadow_color",Color.BLACK); text.add_theme_constant_override("shadow_offset_x",2); text.add_theme_constant_override("shadow_offset_y",2); owned(hud,text,scene)
 var ground_body := StaticBody3D.new(); ground_body.name="GroundCollision"; owned(scene,ground_body,scene)
 var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size=Vector3(180,1,180); collision.shape=box; collision.position.y=-0.63; owned(ground_body,collision,scene)
 scene.set_script(Study)
 var packed := PackedScene.new(); var status := packed.pack(scene)
 if status==OK: status=ResourceSaver.save(packed,"res://scenes/dev/rock_parameter_study.tscn")
 print("ROCK_PARAMETER_STUDY save=",status," formations=",cases.size())
 scene.free(); quit(0 if status==OK else 1)

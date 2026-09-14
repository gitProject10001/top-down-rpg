extends Node3D
var player: CharacterBody3D
var camera: Camera3D
var pavilion: Node3D
var inside := false
func _ready() -> void:
 var example=load("res://scenes/dev/domed_terrace_example.tscn").instantiate(); add_child(example)
 pavilion=example.get_node("EdificioTerrazzato/PadiglioneCupola")
 camera=example.get_node("Camera"); camera.size=30
 camera.position=Vector3(22,29,34); camera.look_at(Vector3(0,1,3)); camera.current=true; camera.add_to_group("camera_rig")
 var ground := StaticBody3D.new(); add_child(ground)
 var shape := BoxShape3D.new(); shape.size=Vector3(50,1,50)
 var collision := CollisionShape3D.new(); collision.shape=shape; collision.position.y=-0.5; ground.add_child(collision)
 player=load("res://scenes/player/player3.tscn").instantiate(); player.name="Player"; player.position=Vector3(0,0.1,14); add_child(player)
 var ui := CanvasLayer.new(); add_child(ui)
 var label := Label.new(); label.position=Vector2(25,25); label.text="A07.6b · TERRAZZA E CUPOLA\nWASD: movimento · E: porta"; ui.add_child(label)
func walk(target: Vector3,frames: int) -> void:
 for i in frames:
  var delta := target-player.position; delta.y=0
  if delta.length()<0.12: break
  var raw := delta.normalized().rotated(Vector3.UP,-camera.global_rotation.y)
  for pair in [["move_left",-raw.x],["move_right",raw.x],["move_up",-raw.z],["move_down",raw.z]]:
   if pair[1]>0: Input.action_press(pair[0],pair[1])
   else: Input.action_release(pair[0])
  await get_tree().physics_frame
 for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
 for i in 25: await get_tree().physics_frame

func _physics_process(_delta: float) -> void:
 if not is_instance_valid(player): return
 var local := pavilion.to_local(player.global_position)
 var next_inside: bool=pavilion.contains_footprint(local) and local.y>0 and local.y<3
 if next_inside!=inside:
  inside=next_inside; pavilion.set_cutaway(inside,0,3)
func _unhandled_key_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_E:
  pavilion._generated.get_node("Door_0").toggle(player.global_position)

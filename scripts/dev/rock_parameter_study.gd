extends Node3D
## Reuses the integrated scene's complete player, camera and pixel rendering rig.
func _ready() -> void:
 var rig = load("res://scenes/dev/gameplay_preview_rig.tscn").instantiate()
 var view: Node=rig.get_node("Pixel/View")
 for child in get_children():
  if child is CanvasLayer: continue
  if child is WorldEnvironment or child is DirectionalLight3D:
   remove_child(child); child.free(); continue
  remove_child(child); view.add_child(child)
 view.get_node("Player").position=Vector3(0,1,21)
 add_child(rig)

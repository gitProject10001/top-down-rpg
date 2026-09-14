extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var whole_world := "--world" in OS.get_cmdline_user_args()
 var packed=load("res://scenes/dev/hearth_village_playable.tscn" if whole_world else "res://scenes/dev/castle_open_courtyard_example.tscn")
 for isometric in (["--iso" in OS.get_cmdline_user_args()] if whole_world else [false,true]):
  var result=await preload("res://addons/world_editor/map_export.gd").export_png(root,packed,"res://captures/balcony_attachment/design_map_%s.png"%(("world_iso_8k" if isometric else "world") if whole_world else ("iso" if isometric else "top")),isometric,8192 if "--high" in OS.get_cmdline_user_args() else 1024)
  assert(not result.has("error"),str(result))
  print("MAP_EXPORT_OK ",result)
 quit()

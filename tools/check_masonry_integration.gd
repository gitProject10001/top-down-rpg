extends SceneTree
func _initialize() -> void: call_deferred("run")
func triangles(mesh: Mesh) -> int:
 var count := 0
 for i in mesh.get_surface_count():
  var a=mesh.surface_get_arrays(i)
  count+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3
 return count
func run() -> void:
 var wing_house=load("res://addons/house_builder/house.gd").new(); wing_house.wing_enabled=true; root.add_child(wing_house)
 assert(triangles(wing_house._generated.get_node("Walls").mesh)>triangles(wing_house._collision_shell)*3,"Wing collisions also remain simple")
 wing_house.free()
 var world=load("res://scenes/dev/castle_open_courtyard_example.tscn").instantiate(); root.add_child(world)
 for i in 30: await process_frame
 var group=world.get_node("CastelloAperto")
 var house=group.get_node("CorpoServizi")
 var walls: MeshInstance3D=house._generated.get_node("Walls")
 assert(triangles(walls.mesh)>triangles(house._collision_shell)*3,"Decorative mesh must be independent of simple collision shell")
 var plaster: ShaderMaterial=walls.mesh.surface_get_material(0)
 assert(plaster.get_shader_parameter("exposed_masonry"))
 var stone_surfaces := 0
 var has_contact := false
 for i in walls.mesh.get_surface_count():
  var material=walls.mesh.surface_get_material(i)
  if material is ShaderMaterial and material.shader.resource_path=="res://shaders/pixelart/solid_masonry.gdshader": stone_surfaces+=1
  var colors=walls.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
  if colors!=null:
   for color in colors:
    if color.a<0.6: has_contact=true; break
 assert(has_contact,"Stone vertices carry joint occlusion")
 assert(stone_surfaces>=4,"Stone exists beneath each rendered facade")
 for tower in group.towers(): assert(tower.wall_finish==1)
 print("MASONRY_INTEGRATION_OK house_render_triangles=",triangles(walls.mesh)," collision_triangles=",triangles(house._collision_shell))
 if DisplayServer.get_name()!="headless":
  var camera: Camera3D=world.get_node("Camera")
  root.msaa_3d=Viewport.MSAA_4X
  for mode in ["castle","plaster","raking"]:
   if mode!="plaster": camera.size=17.5; camera.position=Vector3(35,18,14); camera.look_at(Vector3(22,3,-1))
   else: camera.size=12; camera.position=Vector3(17,10,-7); camera.look_at(Vector3(8,3,-18))
   if mode=="raking":
    for node in world.get_children():
     if node is DirectionalLight3D: node.rotation_degrees=Vector3(-22,55,0)
   for i in 120: await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://captures/balcony_attachment/integrated_masonry_%s.png"%mode)
 quit()

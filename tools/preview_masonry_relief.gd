extends SceneTree
func _initialize() -> void: call_deferred("run")
func collect(node: Node, materials: Array) -> void:
 if node is MeshInstance3D and node.mesh:
  for i in node.mesh.get_surface_count():
   var m=node.get_active_material(i)
   if m is ShaderMaterial and m.shader.resource_path=="res://shaders/pixelart/painted_architecture.gdshader" and not materials.has(m): materials.append(m)
 for child in node.get_children(true): collect(child,materials)
func run() -> void:
 var world=load("res://scenes/dev/castle_open_courtyard_example.tscn").instantiate(); root.add_child(world)
 for tower in world.get_node("CastelloAperto").towers(): tower.wall_finish=1; tower.rebuild()
 for i in 15: await process_frame
 var camera: Camera3D=world.get_node("Camera")
 camera.size=17.5; camera.position=Vector3(35,18,14); camera.look_at(Vector3(22,3,-1))
 var sun: DirectionalLight3D
 for node in world.get_children():
  if node is DirectionalLight3D: sun=node
 var materials: Array=[]; collect(world,materials)
 var packed=PackedScene.new(); assert(packed.pack(world)==OK)
 assert(ResourceSaver.save(packed,"res://scenes/dev/masonry_relief_example.tscn")==OK)
 root.msaa_3d=Viewport.MSAA_4X
 for mode in ["before","front","raking"]:
  for material in materials: material.set_shader_parameter("masonry_relief",mode!="before")
  sun.rotation_degrees=Vector3(-48,-35,0) if mode!="raking" else Vector3(-22,55,0)
  for i in 180: await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://captures/balcony_attachment/masonry_%s.png"%mode)
 print("MASONRY_RELIEF_TWO_LIGHTS_OK")
 quit()

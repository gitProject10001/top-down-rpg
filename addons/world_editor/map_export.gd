@tool
extends RefCounted
## Isolated snapshot export. The current scene is never moved or saved.
static func export_png(host: Node, packed: PackedScene, path: String, isometric: bool, resolution: int=8192) -> Dictionary:
 var viewport := SubViewport.new(); viewport.size=Vector2i(mini(resolution,2048)+64,mini(resolution,2048)+64)
 viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
 viewport.msaa_3d=Viewport.MSAA_4X
 var instance=packed.instantiate()
 clear_owners(instance)
 var source: Node=instance.get_node_or_null("Pixel/View")
 var world := Node3D.new()
 if source:
  for child in source.get_children(): source.remove_child(child); world.add_child(child)
  instance.free()
 else: world.add_child(instance)
 # Suppress game UI/cameras/player; keep scene lighting and authored geometry.
 var nodes: Array[Node]=[world]; nodes.append_array(world.find_children("*","Node",true,false))
 var streams: Array=[]
 for node in nodes:
  if node.get_script()!=null and node.get_script().resource_path=="res://scripts/village/world_stream.gd":
   streams.append(node)
   for child in node.get_children(): node.remove_child(child); child.free()
  if node is MeshInstance3D and node.mesh:
   node.mesh=node.mesh.duplicate(true)
   if node.material_override: node.material_override=node.material_override.duplicate(true)
   for surface in node.mesh.get_surface_count():
    var material=node.get_surface_override_material(surface)
    if material: node.set_surface_override_material(surface,material.duplicate(true))
  if node is WorldEnvironment and node.environment:
   node.environment=node.environment.duplicate(true)
   if node.environment.sky and node.environment.ambient_light_source==Environment.AMBIENT_SOURCE_BG:
    node.environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
   node.environment.background_mode=Environment.BG_COLOR
   node.environment.background_color=Color(0.15,0.17,0.19)
  if node is AnimationMixer: node.active=false
  if node is Camera3D: node.current=false
  if node is CanvasLayer: node.visible=false
  if node is Node3D and (node.name=="Player" or node.name=="PostPixel"): node.visible=false
 viewport.add_child(world); host.add_child(viewport)
 for frame in 4: await host.get_tree().process_frame
 # Freeze the copy. Stream cells explicitly, including those outside the player radius.
 for node in [world]+world.find_children("*","Node",true,false):
  node.set_process(false); node.set_physics_process(false)
 for stream in streams:
  stream.rebuild()
  var cells := ceili(stream.HALF_WORLD/stream.CELL)
  for x in range(-cells,cells):
   for z in range(-cells,cells): stream._build(Vector2i(x,z))
   await host.get_tree().process_frame
 var bounds := AABB(); var found := false
 for node in world.find_children("*","VisualInstance3D",true,false):
  if not node.is_visible_in_tree() or not (node is MeshInstance3D or node is MultiMeshInstance3D): continue
  var box: AABB=node.global_transform*node.get_aabb()
  if box.size.length_squared()<0.000001: continue
  bounds=box if not found else bounds.merge(box); found=true
 if not found:
  viewport.free(); return {"error":"La scena non contiene geometria 3D visibile."}
 var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.rotation_degrees=Vector3(-55,45,0) if isometric else Vector3(-90,0,0)
 world.add_child(camera)
 var center := bounds.get_center(); var distance := maxf(10,bounds.size.length()*2)
 camera.global_position=center+camera.global_basis.z*distance
 camera.near=0.1; camera.far=distance*3
 var extent := Vector2.ZERO
 for i in 8:
  var point: Vector3=camera.global_basis.inverse()*(bounds.get_endpoint(i)-center)
  extent=extent.max(Vector2(absf(point.x),absf(point.y)))
 camera.size=maxf(1,maxf(extent.x,extent.y)*2.08); camera.current=true
 for node in world.find_children("*","DirectionalLight3D",true,false):
  node.directional_shadow_max_distance=camera.far
  if bounds.size.length()>500: node.shadow_enabled=false
 var full_size := camera.size
 var original_position := camera.global_position
 var tile := mini(2048,resolution)
 var guard := 32
 viewport.size=Vector2i(tile+guard*2,tile+guard*2)
 var picture := Image.create(resolution,resolution,false,Image.FORMAT_RGBA8)
 camera.size=full_size*float(tile+guard*2)/resolution
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 for y in range(0,resolution,tile):
  for x in range(0,resolution,tile):
   var offset := Vector2((x+tile*0.5)/resolution-0.5,0.5-(y+tile*0.5)/resolution)*full_size
   camera.global_position=original_position+camera.global_basis.x*offset.x+camera.global_basis.y*offset.y
   for frame in 4: await host.get_tree().process_frame
   await RenderingServer.frame_post_draw
   var piece := viewport.get_texture().get_image(); piece.convert(Image.FORMAT_RGBA8)
   picture.blit_rect(piece,Rect2i(guard,guard,mini(tile,resolution-x),mini(tile,resolution-y)),Vector2i(x,y))
 camera.size=full_size; camera.global_position=original_position
 var error := picture.save_png(path)
 # Lightweight companion preview; the primary PNG remains at full resolution.
 if error==OK and resolution>2048:
  picture.resize(1024,1024,Image.INTERPOLATE_LANCZOS)
  picture.save_png(path.get_basename()+"_preview.png")
 var metadata := {"projection":"orthographic","view":"isometric" if isometric else "top","resolution":resolution,"bounds_position":str(bounds.position),"bounds_size":str(bounds.size),"camera_transform":str(camera.global_transform),"camera_size":camera.size,"stream_cells":0,"world_seeds":[],"large_overview_shadows_disabled":bounds.size.length()>500}
 for stream in streams:
  metadata.stream_cells+=stream._chunks.size(); metadata.world_seeds.append(stream.world_seed)
 viewport.free()
 if error!=OK: return {"error":"Impossibile salvare PNG: "+error_string(error)}
 var file=FileAccess.open(path.get_basename()+".json",FileAccess.WRITE)
 if file: file.store_string(JSON.stringify(metadata,"  "))
 return {"path":path,"metadata":metadata}

static func clear_owners(node: Node) -> void:
 node.owner=null
 for child in node.get_children(): clear_owners(child)

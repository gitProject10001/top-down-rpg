extends SceneTree
const Grass=preload("res://scripts/village/anime_grass.gd")
const Cache=preload("res://scripts/generation_cache.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures+=1; push_error(message)
func _initialize() -> void: call_deferred("run")
func complete(grass: Node) -> void:
	for i in 20000:
		grass._physics_process(1.0/60)
		if not grass._building and grass._wanted.all(func(key): return grass.chunks.has(key)): return
	check(false,"Streaming failed to complete")
func signature(chunk: Node) -> String:
	var data: Array=[]
	for child in chunk.get_children():
		var mm: MultiMesh=child.multimesh
		for i in mm.instance_count:
			data.append([child.name,mm.get_instance_transform(i),mm.get_instance_custom_data(i) if mm.use_custom_data else mm.get_instance_color(i)])
	return Cache.digest(data)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var parent := Node3D.new(); parent.name="TerrenoComposto"; world.add_child(parent)
	var terrain := MeshInstance3D.new(); terrain.name="Superficie"; parent.add_child(terrain)
	var plane := PlaneMesh.new(); plane.size=Vector2(200,200); terrain.mesh=plane
	var body := StaticBody3D.new(); terrain.add_child(body)
	var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size=Vector3(200,.2,200)
	collision.shape=box; collision.position.y=.08; body.add_child(collision)
	var road := Image.create(8,8,false,Image.FORMAT_RGBA8); road.fill(Color(0,0,0,1))
	var material := ShaderMaterial.new(); material.shader=load("res://shaders/pixelart/ground_clear.gdshader")
	material.set_shader_parameter("road_mask",ImageTexture.create_from_image(road))
	material.set_shader_parameter("road_mask_center",Vector2.ZERO)
	material.set_shader_parameter("road_mask_size",Vector2(200,200))
	terrain.material_override=material
	var player := Node3D.new(); player.name="Player"; world.add_child(player)
	var grass := Grass.new(); world.add_child(grass); grass.configure(world)
	grass.set_physics_process(false)
	await physics_frame
	complete(grass)
	check(grass.chunks.size()==49,"Full mode did not preload its outer ring")
	check(grass.chunks.values().filter(func(chunk): return chunk.visible).size()==25,"Prefetch ring must not increase rendered coverage")
	var origin_signature := signature(grass.chunks[Vector2i.ZERO])
	var original_id: int=grass.chunks[Vector2i.ZERO].get_instance_id()
	player.position.x=8
	complete(grass)
	player.position.x=0
	complete(grass)
	check(grass.chunks[Vector2i.ZERO].get_instance_id()==original_id,"Return path rebuilt a cached chunk")
	for x in [40,80,-64,0]:
		player.position.x=x
		complete(grass)
		check(grass.chunks.size()<=81,"Chunk cache exceeded its bound")
	check(signature(grass.chunks[Vector2i.ZERO])==origin_signature,"Eviction changed seeded placement")
	# Optional comparison against the pre-change sampler, extracted to .godot.
	if FileAccess.file_exists("res://.godot/reference_grass.gd"):
		var reference=load("res://.godot/reference_grass.gd").new()
		world.add_child(reference); reference.set_physics_process(false)
		for key in ["art_profile","study_root","coverage","shared_coverage","material","player","terrain","raised_edit_surfaces","waters","blade","blades","pebble_mesh","density_field","profile_field","edge_field","pigment_field","heading_field","height_field","mask_center","mask_size","ground_ray_top"]:
			reference.set(key,grass.get(key))
		reference.build_chunk(Vector2i.ZERO)
		check(signature(reference.chunks[Vector2i.ZERO])==origin_signature,"Streaming changed original grass distribution")
		reference.free()
	grass.set_work_mode(true)
	complete(grass)
	check(grass.chunks.size()==9,"Work mode must contain 3x3 chunks")
	# Change focus while a chunk is incomplete, then invalidate it again.
	player.position=Vector3(72,0,72); grass._physics_process(.016)
	grass.invalidate_chunks(); player.position=Vector3.ZERO; complete(grass)
	check(grass.chunks.size()==9,"Canceled job published an obsolete chunk")
	var revision: int=grass._revision
	body.position.y=.1
	await physics_frame
	complete(grass)
	for i in 20: grass._physics_process(.016)
	check(grass._revision>revision,"Moving a ground collider did not invalidate scatter")
	complete(grass)
	grass.set_physics_process(true)
	grass._last_stream_frame=-1
	grass._physics_process(.016)
	var clock_before: int=grass._clock
	grass._physics_process(.016)
	check(grass._clock==clock_before,"Physics catch-up spent two budgets in one frame")
	grass.set_physics_process(false)
	print("GRASS_STREAMING failures=",failures," max_slice_ms=",grass.max_work_usec/1000.0," cache=",grass.chunks.size())
	world.free()
	await process_frame
	quit(failures)

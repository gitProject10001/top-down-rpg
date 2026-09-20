extends SceneTree
const Cliff = preload("res://addons/rock_builder/continuous_cliff.gd")
const Formation = preload("res://addons/rock_builder/formation.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
 var formation := Formation.new()
 root.add_child(formation)
 var cliff := Cliff.new()
 cliff.configure_from(formation)
 var first: Dictionary = cliff.generate()
 assert(not first.has("error"), str(first.get("error", "")))
 var repeat: Dictionary = cliff.generate()
 assert(first.vertices == repeat.vertices and first.indices == repeat.indices, "Seeded geometry must be deterministic")
 assert(first.debris == repeat.debris, "Foot debris must be deterministic")
 assert(first.fissure_count >= 3, "Large vertical fractures must exist")
 assert(first.triangles < 6000, "Keep continuous wall geometry bounded")
 check_closed_connected(first)
 check_winding(first)
 assert(not Cliff._invades_corridor(first.vertices, first.indices, first.corridor), "All surfaces must stay outside reserved passage")
 var min_crest := INF
 var max_crest := -INF
 for point in first.crests:
  min_crest = minf(min_crest, point.y)
  max_crest = maxf(max_crest, point.y)
 assert(max_crest - min_crest > 0.5, "Crest needs coherent height variation")
 for seed_value in range(8):
  cliff.cliff_seed = seed_value
  var variant: Dictionary = cliff.generate()
  assert(not variant.has("error"), str(variant.get("error", "")))
  assert(first.vertices != variant.vertices, "Seed changes real surface geometry")
  check_closed_connected(variant)
 for depth in [1.0, 2.0, 6.0]:
  for layer_count in [1, 6]:
   cliff.wall_depth = depth
   cliff.strata = layer_count
   var profile: Dictionary = cliff.generate()
   assert(not profile.has("error"), str(profile.get("error", "")))
   check_closed_connected(profile)
   check_winding(profile)
 cliff.configure_from(formation)
 cliff.cliff_seed = formation.formation_seed
 formation.add_child(cliff)
 cliff.owner = formation
 cliff.rebuild()
 assert(cliff.last_error.is_empty())
 var body: StaticBody3D = cliff.get_node("_GeneratedContinuousCliff/CliffCollision")
 var shape: ConcavePolygonShape3D = body.get_child(0).shape
 assert(shape.get_faces() == first.faces, "Collision follows fissures rather than a convex hull")
 await physics_frame
 var frame: Dictionary = cliff._frame(formation.curve.get_baked_length() * 0.5, formation.curve.get_baked_length())
 var ray_height: Vector3 = frame.center + Vector3.UP * 2.0
 var query := PhysicsRayQueryParameters3D.create(ray_height + frame.front * 3.0, ray_height - frame.front * 3.0)
 var hit := cliff.get_world_3d().direct_space_state.intersect_ray(query)
 assert(not hit.is_empty() and hit.collider == body, "Actual physics ray must hit the visible cliff front")
 query = PhysicsRayQueryParameters3D.create(ray_height + frame.front * 0.25, ray_height + frame.front * 1.95)
 assert(cliff.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Reserved front corridor must remain walkable")
 var user_detail := Node3D.new()
 user_detail.name = "HandPlacedDetail"
 cliff.add_child(user_detail)
 user_detail.owner = formation
 user_detail.position = Vector3(2.0, 1.0, -1.0)
 cliff.rebuild()
 assert(cliff.get_node("HandPlacedDetail") == user_detail, "Regeneration preserves authored children")
 var packed := PackedScene.new()
 assert(packed.pack(formation) == OK)
 var reopened := packed.instantiate()
 var reloaded: Node3D = reopened.get_node(NodePath(cliff.name))
 var reloaded_result: Dictionary = reloaded.generate()
 assert(reloaded_result.vertices == first.vertices, "Scene reopen reproduces geometry")
 assert(reloaded.get_node("HandPlacedDetail").position == user_detail.position)
 reopened.free()
 # Use actual production guides without running the expensive whole landscape.
 var scene := load("res://scenes/dev/integrated_landscape.tscn") as PackedScene
 var content := scene.instantiate()
 var checked := 0
 for child in content.get_children():
  if child.get_script() != Formation: continue
  var candidate := Cliff.new()
  candidate.configure_from(child)
  var result: Dictionary = candidate.generate()
  assert(not result.has("error"), "Production guide %s: %s" % [child.name, result.get("error", "")])
  check_closed_connected(result)
  checked += 1
  candidate.free()
 content.free()
 assert(checked >= 2)
 var bad := Curve3D.new()
 for point in [Vector3(-8, 0, -8), Vector3(8, 0, 8), Vector3(-8, 0, 8), Vector3(8, 0, -8)]: bad.add_point(point)
 cliff.guide = bad
 assert(cliff.generate().has("error"), "Crossing guide must fail safely")
 var retained := cliff.get_node("_GeneratedContinuousCliff")
 cliff.rebuild()
 assert(cliff.get_node("_GeneratedContinuousCliff") == retained, "Invalid guide preserves last valid preview")
 bad = Curve3D.new()
 bad.add_point(Vector3.ZERO)
 bad.add_point(Vector3(3, 1, 0))
 cliff.guide = bad
 assert(cliff.generate().has("error"))
 formation.free()
 print("CONTINUOUS_CLIFF_PASS: deterministic, closed connected surface, outward winding, exact collision, passage, production guides, manual child, save/reopen; triangles=", first.triangles)
 if OS.get_cmdline_user_args().has("--capture"):
  await capture_preview()
 quit()

func capture_preview() -> void:
 var world := Node3D.new()
 root.add_child(world)
 var environment := WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.background_color = Color(0.19, 0.23, 0.25)
 environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color = Color(0.60, 0.73, 0.88)
 environment.environment.ambient_light_energy = 0.43
 environment.environment.ssao_enabled = true
 environment.environment.ssao_radius = 0.7
 world.add_child(environment)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-48, -35, 0)
 sun.shadow_enabled = true
 sun.directional_shadow_max_distance = 60
 sun.light_color = Color(1, 0.93, 0.82)
 sun.light_energy = 1.15
 world.add_child(sun)
 var ground := MeshInstance3D.new()
 var plane := PlaneMesh.new()
 plane.size = Vector2(100, 100)
 ground.mesh = plane
 var material := StandardMaterial3D.new()
 material.albedo_color = Color(0.24, 0.29, 0.19)
 material.roughness = 1.0
 ground.material_override = material
 world.add_child(ground)
 var formation := Formation.new()
 world.add_child(formation)
 var cliff := Cliff.new()
 cliff.configure_from(formation)
 cliff.raised_zone_enabled = OS.get_cmdline_user_args().has("--raised-zone")
 formation.add_child(cliff)
 var camera := Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 25
 camera.position = Vector3(18, 19, 25)
 world.add_child(camera)
 camera.look_at(Vector3(0, 2, -1))
 if cliff.raised_zone_enabled:
  camera.position = Vector3(36, 30, 28)
  camera.size = 44
  camera.look_at(Vector3(9, 2, -9))
 root.msaa_3d = Viewport.MSAA_4X
 for frame in 30: await process_frame
 for layer in root.find_children("*", "CanvasLayer", true, false): layer.hide()
 for frame in 3: await process_frame
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
 root.get_texture().get_image().save_png("res://captures/continuous_cliff_preview.png")
 camera.position = Vector3(8, 9, 23)
 camera.look_at(Vector3(0, 2, -1))
 for frame in 3: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://captures/continuous_cliff_front.png")
 world.free()

func check_closed_connected(result: Dictionary) -> void:
 var edges := {}
 var directions := {}
 var adjacency := {}
 var indices: PackedInt32Array = result.indices
 for i in range(0, indices.size(), 3):
  for j in 3:
   var a := indices[i + j]
   var b := indices[i + (j + 1) % 3]
   var key := Vector2i(mini(a, b), maxi(a, b))
   edges[key] = edges.get(key, 0) + 1
   directions[key] = directions.get(key, 0) + (1 if a < b else -1)
   if not adjacency.has(a): adjacency[a] = []
   adjacency[a].append(b)
 for key in edges:
  assert(edges[key] == 2, "Surface must be watertight with no independent stacked masses")
  assert(directions[key] == 0, "Adjacent faces must have consistent outward winding")
 var visited := {0: true}
 var pending: Array[int] = [0]
 while not pending.is_empty():
  var a: int = pending.pop_back()
  for b in adjacency[a]:
   if not visited.has(b): visited[b] = true; pending.append(b)
 assert(visited.size() == result.vertices.size(), "Every cliff vertex belongs to one connected component")

func check_winding(result: Dictionary) -> void:
 var volume := 0.0
 var vertices: PackedVector3Array = result.vertices
 var indices: PackedInt32Array = result.indices
 for i in range(0, indices.size(), 3):
  var a := vertices[indices[i]]
  var b := vertices[indices[i + 1]]
  var c := vertices[indices[i + 2]]
  volume += a.dot(c.cross(b)) / 6.0
 assert(volume > 0.0, "Clockwise winding must face outward")

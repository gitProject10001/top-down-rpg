extends SceneTree
const Cliff = preload("res://addons/rock_builder/continuous_cliff.gd")
const Formation = preload("res://addons/rock_builder/formation.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
 if not condition:
  failures += 1
  push_error("ELEVATED_ZONE: " + label)

func run() -> void:
 var formation := Formation.new()
 formation.curve = Curve3D.new()
 formation.curve.add_point(Vector3.ZERO)
 formation.curve.add_point(Vector3(20, 0, 0))
 root.add_child(formation)
 var cliff := Cliff.new()
 cliff.configure_from(formation)
 cliff.raised_zone_enabled = true
 formation.add_child(cliff)
 await physics_frame
 var built := cliff.generate()
 check(not built.has("error"), "Valid guide generates raised terrain")
 if built.has("error"):
  formation.free()
  quit(1)
  return
 var terrain: Dictionary = built.elevated
 check(built.mesh.surface_get_material(0).get_shader_parameter("stone_chip_strength") == 0.0, "Geological shader preserves exact rendered crest seam")
 check(terrain.top_vertices == cliff.generate().elevated.top_vertices, "Raised terrain deterministic")
 for i in built.crests.size():
  check(terrain.rows[i][0] == built.crests[i], "Terrain and cliff use exact shared crest positions")
  var p: Vector3 = built.crests[i]
  check(absf(cliff.height_at_local(Vector2(p.x, p.z)) - p.y) < 0.001, "Height query matches crest seam")
 var plateau := Vector2(10, -cliff.wall_depth - cliff.raised_zone_depth * 0.5)
 var ramp := Vector2(20 + cliff.effective_ramp_length() * 0.5, plateau.y)
 check(absf(cliff.height_at_local(plateau) - cliff.wall_height) < 0.001, "Rear region is a level elevated zone")
 check(absf(cliff.height_at_local(ramp) - (cliff.wall_height + cliff.access_ramp_base_height) * 0.5) < 0.001, "End ramp descends to original grade")
 check(is_nan(cliff.height_at_local(Vector2(10, 2))), "Reserved front passage is outside upper terrain")
 check(is_nan(cliff.height_at_local(Vector2(-3, -8))), "Outside height queries return NAN")
 for point in [plateau, ramp]:
  var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 20, point.y), Vector3(point.x, -1, point.y))
  var hit := cliff.get_world_3d().direct_space_state.intersect_ray(query)
  check(not hit.is_empty(), "Upper terrain and ramp have real collision")
  if not hit.is_empty():
   check(hit.collider.name == "ElevatedGroundCollision", "Collision belongs to raised terrain")
   check(hit.collider.get_meta("art_ground_surface", false) and hit.collider.get_meta("art_surface_node") == cliff, "Collider identifies stable editable terrain surface")
   check(absf(hit.position.y - cliff.height_at_local(point)) < 0.001, "Sampled height exactly agrees with physical triangle")
 # A capsule walks from ramp toe onto the plateau without teleportation.
 var body := CharacterBody3D.new()
 body.floor_snap_length = 0.4
 body.floor_max_angle = deg_to_rad(45)
 var shape := CollisionShape3D.new()
 var capsule := CapsuleShape3D.new()
 capsule.radius = 0.25
 capsule.height = 1.5
 shape.shape = capsule
 body.add_child(shape)
 formation.add_child(body)
 var start_x := 20 + cliff.effective_ramp_length() - 1.0
 var start_height := cliff.height_at_local(Vector2(start_x, plateau.y))
 body.position = Vector3(start_x, start_height + 0.80, plateau.y)
 for frame in 420:
  await physics_frame
  body.velocity.x = -3.0
  body.velocity.y -= 12.0 / Engine.physics_ticks_per_second
  body.move_and_slide()
 check(body.position.x < 19.0 and body.position.x > 8.0, "Capsule reaches plateau through access ramp")
 check(absf(body.position.y - (cliff.wall_height + 0.75)) < 0.1, "Capsule stands on upper ground")
 check(body.is_on_floor(), "Upper zone is walkable at actual physics scale")
 body.free()
 var material := StandardMaterial3D.new()
 material.albedo_color = Color(0.2, 0.3, 0.1)
 cliff.set_ground_material(material)
 cliff.rebuild()
 check(cliff.get_node("_GeneratedContinuousCliff/ElevatedGround").material_override == material, "Assigned terrain material survives rebuild")
 cliff.process_mode = Node.PROCESS_MODE_DISABLED
 await physics_frame
 var query := PhysicsRayQueryParameters3D.create(Vector3(plateau.x, 20, plateau.y), Vector3(plateau.x, -1, plateau.y))
 check(cliff.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "F7 inherited disable also removes elevated collision")
 cliff.process_mode = Node.PROCESS_MODE_INHERIT
 var packed := PackedScene.new()
 cliff.owner = formation
 check(packed.pack(formation) == OK, "Raised settings can be saved")
 var copy := packed.instantiate()
 var reopened: Node3D = copy.get_node(NodePath(cliff.name))
 check(reopened.raised_zone_enabled and reopened.raised_zone_depth == cliff.raised_zone_depth, "Raised settings reopen")
 check(reopened.generate().elevated.top_vertices == terrain.top_vertices, "Reopened geometry matches saved settings")
 copy.free()
 var scene := load("res://scenes/dev/integrated_landscape.tscn") as PackedScene
 var content := scene.instantiate()
 for child in content.get_children():
  if child.get_script() != Formation: continue
  var sample := Cliff.new()
  sample.configure_from(child)
  sample.raised_zone_enabled = true
  var output := sample.generate()
  check(not output.has("error"), "Production formation supports raised zone: " + str(child.name))
  sample.free()
 content.free()
 formation.free()
 print("ELEVATED_ZONE_PASS" if failures == 0 else "ELEVATED_ZONE_FAIL", ": exact ridge, physical plateau/ramp, capsule ascent, F7 collision, material, deterministic save/reopen, production guides; failures=", failures)
 quit(1 if failures else 0)

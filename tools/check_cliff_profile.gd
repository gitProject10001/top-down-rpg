extends SceneTree
## Profile switching must survive mesh/body replacement in editable generators.
const Formation = preload("res://addons/rock_builder/formation.gd")
const Rock = preload("res://addons/rock_builder/rock.gd")
const Cliff = preload("res://addons/rock_builder/continuous_cliff.gd")
const Art = preload("res://scripts/village/anime_art_direction.gd")
var failures := 0
var rebuilt_count := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
 if not condition:
  failures += 1
  push_error("CLIFF_PROFILE: " + message)

func settle() -> void:
 for i in 3:
  await process_frame
  await physics_frame

func make_rock(parent: Node3D, id: String, x: float) -> Node3D:
 var rock := Rock.new()
 rock.name = "Rock_" + id
 rock.dimensions = Vector3(1, 2, 1)
 rock.position = Vector3(x, 0, -5)
 rock.set_meta("formation_id", id)
 rock.set_meta("formation_locked", false)
 var values := {}
 for field in Formation.FIELDS: values[field] = rock.get(field)
 rock.set_meta("formation_baseline", values)
 parent.add_child(rock)
 return rock

func collision_at(world: Node3D, x: float, z_from: float, z_to: float) -> Node:
 var query := PhysicsRayQueryParameters3D.create(Vector3(x, 1, z_from), Vector3(x, 1, z_to))
 var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
 return hit.get("collider")

func run() -> void:
 var world := Node3D.new()
 root.add_child(world)
 var formation := Formation.new()
 formation.curve = Curve3D.new()
 formation.curve.add_point(Vector3.ZERO)
 formation.curve.add_point(Vector3(12, 0, 0))
 world.add_child(formation)
 var automatic := make_rock(formation, "automatic", 5.0)
 var manual := make_rock(formation, "with_manual_child", 8.0)
 var detail := Node3D.new()
 detail.name = "HandPlacedMoss"
 manual.add_child(detail)
 var locked := make_rock(formation, "locked", 11.0)
 locked.set_meta("formation_locked", true)
 var edited := make_rock(formation, "edited", 2.0)
 edited.position.y = 0.1
 var cliff := Cliff.new()
 cliff.name = "ContinuousCliff"
 cliff.configure_from(formation)
 cliff.rebuilt.connect(func(): rebuilt_count += 1)
 formation.add_child(cliff)
 await settle()
 var art := Art.new()
 art.profile = art.profile.duplicate(true)
 art.configure_cliffs(world)
 art.apply(false)
 await settle()
 check(not cliff.visible and not cliff.can_process(), "Old mode hides and disables cliff root")
 check(automatic.visible and automatic.can_process(), "Old mode restores automatic rock root")
 check(collision_at(world, 5.0, 3.0, -3.0) == null, "Hidden cliff has no active collider")
 var hit := collision_at(world, 5.0, -3.9, -6.0)
 check(hit != null and automatic.is_ancestor_of(hit), "Original rock collider remains active")
 var previous_rebuilt := rebuilt_count
 cliff.cliff_seed += 1
 cliff.rebuild()
 await settle()
 check(rebuilt_count > previous_rebuilt, "Successful rebuild signals material refresh")
 check(not cliff.can_process(), "Rebuilding hidden cliff preserves inherited disable")
 check(collision_at(world, 5.0, 3.0, -3.0) == null, "Replacement cliff collider remains inactive in old mode")
 art.apply(true)
 await settle()
 check(cliff.visible and cliff.can_process(), "Concept mode activates cliff")
 check(not automatic.visible and not automatic.can_process(), "Concept mode disables automatic original rock root")
 hit = collision_at(world, 5.0, 3.0, -3.0)
 check(hit != null and cliff.is_ancestor_of(hit), "Concept cliff physically blocks its visible surface")
 check(collision_at(world, 5.0, -3.9, -6.0) == null, "Hidden original rock collider is inactive")
 automatic.rock_seed += 1
 automatic.rebuild()
 await settle()
 check(collision_at(world, 5.0, -3.9, -6.0) == null, "Regenerating hidden original rock cannot reactivate its replacement collider")
 for protected in [manual, locked, edited]:
  check(protected.visible and protected.can_process(), "Authored or locked records stay visible and active")
  hit = collision_at(world, protected.position.x, -3.9, -6.0)
  check(hit != null and protected.is_ancestor_of(hit), "Protected original record keeps physical collision")
 check(detail.is_visible_in_tree(), "Manual child is preserved and remains visible")
 art.apply(false)
 await settle()
 hit = collision_at(world, 5.0, -3.9, -6.0)
 check(hit != null and automatic.is_ancestor_of(hit), "F7 restores the replacement original collider")
 art.profile.cliffs_enabled = false
 art.apply(true)
 await settle()
 check(not cliff.visible and automatic.visible, "Disabling cliff layer restores original formation")
 check(collision_at(world, 5.0, 3.0, -3.0) == null, "Disabled cliff layer has no invisible collision")
 art.clear()
 # Stable authoring identity must reach disposable render meshes, including
 # child debris with transforms different from the persistent cliff node.
 formation.position = Vector3(3, 0, -2)
 var stamp = preload("res://scripts/art/art_surface_edit.gd").new()
 stamp.surface_path = world.get_path_to(cliff)
 stamp.layer = stamp.Layer.MOSS
 stamp.local_position = Vector3(4, 1, -0.8)
 stamp.local_rotation_degrees = Vector3(90, 0, 0)
 stamp.radius = 1.8
 stamp.intensity = 0.75
 stamp.locked = true
 art.profile.add_edit(stamp)
 art.root = world
 var visual: MeshInstance3D = cliff.get_node("_GeneratedContinuousCliff/ContinuousGeology")
 var unrelated := MeshInstance3D.new()
 unrelated.name = "UnrelatedSurface"
 unrelated.mesh = visual.mesh
 world.add_child(unrelated)
 art.paint_architecture(world, {})
 art.apply(true)
 var packet: Dictionary = art.profile.pack_shader_edits(stamp.surface_path, cliff.global_transform)
 var painted: ShaderMaterial = visual.get_active_material(0)
 check(painted.get_shader_parameter("art_edit_count") == 1, "Stable cliff-target moss edit reaches generated mesh")
 check(painted.get_shader_parameter("art_edit_rows_x") == packet.art_edit_rows_x, "Stamp coordinates use persistent cliff transform")
 var unrelated_material: ShaderMaterial = unrelated.get_active_material(0)
 check(unrelated_material.get_shader_parameter("art_edit_count") == 0, "Isolating local stamps protects shared unrelated materials")
 for child in cliff.get_node("_GeneratedContinuousCliff").get_children():
  if child.get_script() != Rock: continue
  var fragment: MeshInstance3D = child.get_node("_Generated/Rock")
  var fragment_material: ShaderMaterial = fragment.get_active_material(0)
  check(fragment_material.get_shader_parameter("art_edit_rows_x") == packet.art_edit_rows_x, "Transformed cliff fragment uses the same authored world stamp")
 art.clear()
 cliff.rebuild()
 art.paint_architecture(world, {})
 art.apply(true)
 visual = cliff.get_node("_GeneratedContinuousCliff/ContinuousGeology")
 painted = visual.get_active_material(0)
 check(painted.get_shader_parameter("art_edit_count") == 1 and stamp.locked and not stamp.deleted, "Rebuilt cliff retains the stored locked moss stroke")
 art.clear()
 world.free()
 await process_frame
 print("CLIFF_PROFILE_PASS" if failures == 0 else "CLIFF_PROFILE_FAIL", ": runtime rebuilds, F7 collider inheritance, protected records, manual children, stable moss target/transforms/isolation; failures=", failures)
 quit(1 if failures else 0)

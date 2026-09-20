@tool
extends RefCounted
## Reversible painted presentation, shared by the editor and runtime.
var enabled := false
var changes: Array[Dictionary] = []
var grass: Node3D
var profile: Resource = preload("res://assets/art/default_art_study_profile.tres")
var root: Node
var cliffs: Array[Node3D] = []
var cliff_states: Array[Dictionary] = []
var _geology_active:=false
var _raised_player_return: Dictionary={}
var canopy_shading = preload("res://scripts/village/canopy_shading.gd").new()

func paint_architecture(node: Node, visited: Dictionary) -> void:
    if node is MeshInstance3D and node.mesh != null:
        var first_change := changes.size()
        # Generated cliff meshes are disposable. Stamps belong to the persistent
        # cliff node, in its coordinates, just like elevated-ground brush hits.
        var stamp_surface: Node3D = node
        var ancestor: Node = node.get_parent()
        while ancestor != null and ancestor != root:
            if ancestor is Node3D and ancestor.has_method("height_at_local") and ancestor.has_method("set_ground_material"):
                stamp_surface = ancestor
                break
            ancestor = ancestor.get_parent()
        var surface_path: NodePath = root.get_path_to(stamp_surface)
        if not profile.active_edits(surface_path).is_empty():
            # Isolate locally painted surfaces; sibling renderers may share
            # imported materials but must not inherit this surface's stamps.
            if node.material_override is ShaderMaterial:
                var local_material=node.material_override.duplicate()
                remember(node,"material_override",local_material)
                node.material_override=local_material
            else:
                var local_mesh=node.mesh.duplicate()
                for surface in local_mesh.get_surface_count():
                    var source=node.get_active_material(surface)
                    if source is ShaderMaterial: local_mesh.surface_set_material(surface,source.duplicate())
                remember(node,"mesh",local_mesh)
                node.mesh=local_mesh
        var materials: Array = [node.material_override]
        for surface in node.mesh.get_surface_count():
            materials.append(node.get_active_material(surface))
        for material in materials:
            if not material is ShaderMaterial or material.shader == null:
                continue
            if material.shader.resource_path.get_file() not in ["solid_masonry.gdshader","painted_architecture.gdshader"]:
                continue
            var id: int = material.get_instance_id()
            if visited.has(id):
                continue
            visited[id]=true
            changes.append({"object":material,"uniform":"anime_painted","before":material.get_shader_parameter("anime_painted"),"after":true})
            var amount := 1.0 if profile.weathering_enabled else 0.0
            for key in ["moss_amount","damp_amount","damage_amount"]:
                changes.append({"object":material,"uniform":key,"before":material.get_shader_parameter(key),"after":profile.get(key)*amount})
            for key in ["moss_color","damp_color"]:
                var color: Color=profile.get(key)
                changes.append({"object":material,"uniform":key,"before":material.get_shader_parameter(key),"after":Vector3(color.r,color.g,color.b)})
            var packet: Dictionary = profile.pack_shader_edits(surface_path,stamp_surface.global_transform)
            for key in packet:
                if key=="art_edit_overflow":
                    if packet[key]>0: push_warning("Surface art edits exceed 32: "+str(surface_path))
                    continue
                changes.append({"object":material,"uniform":key,"before":material.get_shader_parameter(key),"after":packet[key]})
        for index in range(first_change, changes.size()):
            # Generated meshes can disappear while their ShaderMaterials remain
            # referenced by this reversible presentation record.
            changes[index]["architecture_source"] = weakref(node)
    for child in node.get_children(true):
        paint_architecture(child,visited)

func refresh_architecture(building: Node) -> void:
    # Rebind only this rebuilt subtree. Lighting, grass, trees, collision mode
    # and player position retain their current state, including F7 comparison.
    if not is_instance_valid(building) or not is_instance_valid(root): return
    var retained: Array[Dictionary] = []
    var visited := {}
    for change in changes:
        var source: Node = null
        if change.has("architecture_source"):
            source = change.architecture_source.get_ref() as Node
            if source == null or source == building or building.is_ancestor_of(source):
                if is_instance_valid(change.object):
                    if change.has("uniform"):
                        change.object.set_shader_parameter(change.uniform, change.before)
                    else:
                        change.object.set(change.property, change.before)
                continue
            if is_instance_valid(change.object) and change.has("uniform"):
                visited[change.object.get_instance_id()] = true
        retained.append(change)
    changes = retained
    var first_change := changes.size()
    paint_architecture(building, visited)
    for index in range(first_change, changes.size()):
        var change: Dictionary = changes[index]
        if not is_instance_valid(change.object): continue
        var value = change.after if enabled else change.before
        if change.has("uniform"):
            change.object.set_shader_parameter(change.uniform, value)
        else:
            change.object.set(change.property, value)

func remember(object: Object, property: String, value: Variant) -> void:
    # A locally stamped surface can be isolated and then receive a painted
    # override during one configure pass. Keep its true authored baseline.
    for change in changes:
        if change.get("object")==object and change.get("property","")==property:
            change.after=value
            return
    changes.append({"object": object, "property": property, "before": object.get(property), "after": value})

func configure(view: Node, settings: Resource = null) -> void:
    root = view
    if settings != null: profile=settings
    profile.ensure_edit_ids()
    configure_cliffs(view)
    project_trees_to_elevation(view)
    paint_architecture(view,{})
    var environment_node: WorldEnvironment = view.get_node("WorldEnvironment")
    var environment: Environment = environment_node.environment.duplicate()
    environment.ambient_light_color = Color(.53, .72, .77)
    environment.ambient_light_energy = profile.ambient_energy
    environment.sdfgi_use_occlusion = profile.gi_occlusion
    environment.ssao_enabled = true
    environment.ssao_intensity = profile.contact_occlusion_intensity
    environment.ssao_radius = profile.contact_occlusion_radius
    environment.ssao_power = profile.contact_occlusion_power
    remember(environment_node, "environment", environment)
    var sun: DirectionalLight3D = view.get_node("Sun")
    remember(sun, "light_color", Color(1.0, .94, .79))
    remember(sun, "light_energy", 1.2)
    remember(sun, "light_angular_distance", profile.sun_angular_distance)
    remember(sun, "shadow_blur", 1.2)
    remember(sun, "shadow_normal_bias", .07)
    var fill: DirectionalLight3D = view.get_node("SoftSkyFill")
    remember(fill, "light_color", Color(.56, .72, .83))
    remember(fill, "light_energy", profile.sky_fill_energy)
    var camera: Camera3D = view.get_node("IsoCam")
    remember(camera, "pixel_snap", false)
    remember(view.get_node("PixelSnap"), "enabled", false)
    var post: MeshInstance3D = camera.get_node("PostPixel")
    var grade: ShaderMaterial = post.get_surface_override_material(0).duplicate()
    var grading := {"saturation": .92, "contrast": 1.0, "outline_strength": .035, "dither": 0.0, "vignette": .025, "split_strength": .06}
    for key in grading:
        grade.set_shader_parameter(key, grading[key])
    grade.set_shader_parameter("shadow_tint", Color(.36,.55,.59))
    remember(post, "surface_material_override/0", grade)
    for mesh in view.find_children("*", "MeshInstance3D", true, false):
        var original = mesh.material_override
        if not original is ShaderMaterial or original.shader == null:
            continue
        var path: String = original.shader.resource_path
        if not path.get_file() in ["ground_clear.gdshader", "foliage_study.gdshader", "prescribed_water.gdshader"]:
            continue
        var material: ShaderMaterial = original.duplicate()
        material.set_shader_parameter("anime_painted", true)
        if path.ends_with("ground_clear.gdshader"):
            material.set_shader_parameter("meadow_painting", preload("res://assets/textures/anime_painted/meadow.png"))
            material.set_shader_parameter("path_painting", preload("res://assets/textures/anime_painted/path.png"))
            material.set_shader_parameter("brush_normal", preload("res://assets/textures/anime_painted/grass_brush_normal.png"))
            material.set_shader_parameter("grass_metres", 1.8)
            material.set_shader_parameter("grass_grade", Vector3(.31,.40,.38))
            material.set_shader_parameter("wear_amount", .24)
            material.set_shader_parameter("gravel_amount", .12)
            material.set_shader_parameter("macro_strength", .22)
            material.set_shader_parameter("dirt_grade", Vector3(.72,.78,.83))
        elif path.ends_with("foliage_study.gdshader"):
            material.shader = preload("res://shaders/pixelart/anime_canopy.gdshader")
            material.set_shader_parameter("leaf_painting", preload("res://assets/textures/anime_painted/foliage_sprays.png"))
            var species := "pine" if mesh.mesh.get_aabb().end.y > 9.0 else "broadleaf"
            remember(mesh,"mesh",canopy_shading.for_mesh(mesh.mesh,species))
        # Water owns its material and updates simulation uniforms each frame.
        # Keep that object and only toggle its opt-in uniform.
        if path.ends_with("prescribed_water.gdshader"):
            changes.append({"object": original, "uniform": "anime_painted", "before": false, "after": true})
        else:
            remember(mesh, "material_override", material)
    grass = preload("res://scripts/village/anime_grass.gd").new()
    grass.name = "PaintedGrass"
    view.add_child(grass)
    grass.configure(view,profile)
    for change in changes:
        if change.get("property","")=="material_override" and change.after is ShaderMaterial and change.after.shader.resource_path.ends_with("ground_clear.gdshader"):
            grass.bind_ground(change.after)
            if change.object==grass.terrain:
                for cliff in cliffs:
                    remember(cliff,"ground_material",change.after)
                    cliff.set_ground_material(change.after)

func project_trees_to_elevation(view: Node) -> void:
    var woods := view.get_node_or_null("Boschi")
    if woods==null: return
    for tree in woods.get_children():
        if not tree is Node3D or tree.get_meta("art_elevation_locked",false): continue
        var original: Vector3=tree.global_position
        var support := NAN
        for cliff in cliffs:
            if not cliff.raised_zone_enabled: continue
            var local: Vector3=cliff.to_local(original)
            var height: float=cliff.height_at_local(Vector2(local.x,local.z))
            if is_nan(height): continue
            var world_height: float=cliff.to_global(Vector3(local.x,height,local.z)).y
            support=world_height if is_nan(support) else maxf(support,world_height)
        if is_nan(support): continue
        # Preserve authored vertical offsets above the original .18 m ground.
        var raised := Vector3(original.x,support+original.y-.18,original.z)
        cliff_states.append({"object":tree,"property":"global_position","before":original,"painted":raised,"last_applied":original,"preserve_manual_offset":true})

func configure_cliffs(view: Node) -> void:
    cliffs.clear()
    cliff_states.clear()
    for formation in view.get_children():
        if not formation is Path3D or not formation.has_method("free_ribbons"):
            continue
        var cliff = formation.get_node_or_null("ContinuousCliff")
        if cliff == null:
            continue
        cliffs.append(cliff)
        cliff_states.append({"object":cliff,"property":"process_mode","before":Node.PROCESS_MODE_DISABLED,"painted":Node.PROCESS_MODE_INHERIT})
        for rock in formation.get_children():
            if rock==cliff or not rock.has_meta("formation_id"):
                continue
            # Respect locked, edited and manually removed legacy records.
            var untouched: bool = not rock.get_meta("formation_locked",false) and rock.get_child_count()==0
            var baseline: Dictionary = rock.get_meta("formation_baseline",{})
            if baseline.is_empty(): untouched=false
            for key in baseline:
                if rock.get(key)!=baseline[key]: untouched=false
            if not untouched: continue
            cliff_states.append({"object":rock,"property":"visible","before":rock.visible,"painted":false})
            # Collision bodies inherit this state, including replacements made
            # by the existing generators after a guide/seed edit.
            cliff_states.append({"object":rock,"property":"process_mode","before":rock.process_mode,"painted":Node.PROCESS_MODE_DISABLED})

func clear() -> void:
    apply(false)
    if is_instance_valid(grass):
        grass.get_parent().remove_child(grass)
        grass.free()
    grass=null
    changes.clear()
    cliffs.clear()
    cliff_states.clear()

func keep_player_on_supported_ground(geology: bool) -> void:
    if Engine.is_editor_hint() or not is_instance_valid(root): return
    var actor:=root.get_node_or_null("Player") as CharacterBody3D
    if actor==null: return
    if geology and not _geology_active and not _raised_player_return.is_empty():
        var safe: Vector3=_raised_player_return.safe
        if Vector2(actor.global_position.x-safe.x,actor.global_position.z-safe.z).length()<.75:
            var destination: Vector3=_raised_player_return.raised
            # A live Inspector height change can rebuild the plateau before the
            # presentation refresh. Keep the player above the new collision.
            var body_shape:=actor.get_node_or_null("Collision") as CollisionShape3D
            var feet:=1.0
            if body_shape and body_shape.shape is CapsuleShape3D:
                feet=body_shape.shape.height*.5-body_shape.position.y
            for cliff in cliffs:
                if not is_instance_valid(cliff) or not cliff.raised_zone_enabled: continue
                var local: Vector3=cliff.to_local(destination)
                var support: float=cliff.height_at_local(Vector2(local.x,local.z))
                if not is_nan(support):
                    destination.y=maxf(destination.y,cliff.to_global(Vector3(local.x,support,local.z)).y+feet)
            actor.global_position=destination
            actor.velocity=Vector3.ZERO
        _raised_player_return.clear()
    elif _geology_active and not geology:
        for cliff in cliffs:
            if not is_instance_valid(cliff) or not cliff.raised_zone_enabled: continue
            var local: Vector3=cliff.to_local(actor.global_position)
            var support: float=cliff.height_at_local(Vector2(local.x,local.z))
            if is_nan(support): continue
            # The original scene has no floor beyond its old boundary. Move to
            # the preserved front corridor before switching off the upper floor.
            var offset: float=cliff.guide.get_closest_offset(Vector3(local.x,0,local.z))
            var guide_point: Vector3=cliff.guide.sample_baked(offset)
            var tangent: Vector3=cliff.guide.sample_baked(minf(offset+.1,cliff.guide.get_baked_length()))-cliff.guide.sample_baked(maxf(0.0,offset-.1))
            tangent.y=0.0
            tangent=tangent.normalized()
            var safe: Vector3=cliff.to_global(guide_point+Vector3(-tangent.z,0,tangent.x)*3.0+Vector3.UP*2.0)
            _raised_player_return={"raised":actor.global_position,"safe":safe}
            actor.global_position=safe
            actor.velocity=Vector3.ZERO
            break

func apply(active: bool) -> void:
    enabled = active
    if is_instance_valid(grass):
        grass.set_enabled(active and profile.grass_enabled and profile.density_multiplier>0)
    var geology: bool = active and profile.cliffs_enabled
    keep_player_on_supported_ground(geology)
    for cliff in cliffs:
        if is_instance_valid(cliff): cliff.visible=geology
    for state in cliff_states:
        if not is_instance_valid(state.object): continue
        if state.get("preserve_manual_offset",false):
            # Moving a tree in the editor remains an authored adjustment through
            # F7, scene saving and regeneration, rather than being overwritten.
            var offset: Vector3=state.object.get(state.property)-state.last_applied
            state.before+=offset
            state.painted+=offset
            state.last_applied=state.painted if geology else state.before
        state.object.set(state.property,state.painted if geology else state.before)
    for change in changes:
        if not is_instance_valid(change.object): continue
        var value = change.after if active else change.before
        if change.has("uniform"):
            change.object.set_shader_parameter(change.uniform, value)
        else:
            change.object.set(change.property, value)
    _geology_active=geology

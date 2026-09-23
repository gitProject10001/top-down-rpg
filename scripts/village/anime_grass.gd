@tool
extends Node3D
## Blender grass geometry with the tutorial's shared world-space painted normals.
## Small chunks provide culling; density and transforms are deterministic across travel.
const CHUNK := 8.0
const STEP := .12
const MESH_COUNT := 12
var art_profile: Resource
var study_root: Node
var editor_center := Vector3(-9,1,24)
var coverage: Image
var shared_coverage: Texture2D
var material: ShaderMaterial
var player: Node3D
var terrain: MeshInstance3D
var raised_edit_surfaces: Array[Node3D] = []
var waters: Array = []
var chunks: Dictionary = {}
var blade: ArrayMesh
var blades: Array[ArrayMesh] = []
var pebble_mesh: SphereMesh
const VARIANTS := ["BassoCompatto", "MedioInclinato", "AltoRado", "BassoPettinato"]
var density_field := FastNoiseLite.new()
var profile_field := FastNoiseLite.new()
var edge_field := FastNoiseLite.new()
var pigment_field := FastNoiseLite.new()
var heading_field := FastNoiseLite.new()
var height_field := FastNoiseLite.new()
var authored_paths: Array[Node3D] = []
var road_mask: Image
var mask_center: Vector2
var mask_size: Vector2
var road_mask_center: Vector2
var road_mask_size: Vector2
var ground_ray_top:=16.0
var enabled := true
signal work_resumed
var work_mode := false
var budget_usec := 2000
var last_work_usec := 0
var max_work_usec := 0
var _deadline := 0
var _building := false
var _revision := 0
var _focus := Vector2i(2147483647,2147483647)
var _wanted: Array[Vector2i] = []
var _used: Dictionary = {}
var _clock := 0
var _last_stream_frame := -1
var _retired: Array[Node] = []
var _world_dirty := false
var _audit_elapsed := 0.0
var _obstacles: Array[StaticBody3D]=[]
var _obstacle_poses: Dictionary={}
var _watch_shapes: Dictionary={}

func _exit_tree() -> void:
    # Release locals held by a suspended sampler/upload before the signal owner
    # disappears (notably a MultiMesh which has not yet been attached).
    _revision+=1
    _wanted.clear()
    if _building: work_resumed.emit()

func _on_static_added(node: Node) -> void:
    if not is_instance_valid(study_root) or not study_root.is_ancestor_of(node): return
    if node is StaticBody3D or (node is CollisionShape3D and node.get_parent() is StaticBody3D):
        invalidate_chunks()

func watch_obstacles() -> void:
    _obstacles.clear()
    _obstacle_poses.clear()
    _watch_shapes.clear()
    if not is_instance_valid(study_root): return
    for node in study_root.find_children("*","StaticBody3D",true,false):
        _obstacles.append(node)
        _obstacle_poses[node.get_instance_id()]=node.global_transform
        for child in node.get_children():
            if child is CollisionShape3D and child.shape!=null:
                if not child.shape.changed.is_connected(invalidate_chunks):
                    child.shape.changed.connect(invalidate_chunks)
                _watch_shapes[child.get_instance_id()]=[weakref(child),child.transform,child.disabled,child.shape.get_rid()]

func audit_obstacles(delta: float) -> void:
    _audit_elapsed+=delta
    if _audit_elapsed<.25: return
    _audit_elapsed=0.0
    for obstacle in _obstacles:
        if not is_instance_valid(obstacle) or _obstacle_poses.get(obstacle.get_instance_id())!=obstacle.global_transform:
            invalidate_chunks()
            return
    for record in _watch_shapes.values():
        var shape: CollisionShape3D=record[0].get_ref()
        if shape==null or shape.transform!=record[1] or shape.disabled!=record[2] or shape.shape==null or shape.shape.get_rid()!=record[3]:
            invalidate_chunks()
            return


func invalidate_chunks() -> void:
    _world_dirty = true

func set_work_mode(value: bool) -> void:
    if work_mode == value: return
    work_mode = value
    invalidate_chunks()

func _retire(chunk: Node) -> void:
    chunk.visible = false
    _retired.append(chunk)

func _discard_one() -> void:
    if _retired.is_empty(): return
    var chunk := _retired[0]
    if chunk.get_child_count() > 0:
        chunk.get_child(0).free()
    else:
        chunk.free()
        _retired.pop_front()

func _update_demand(center: Vector2i) -> void:
    _focus = center
    _wanted.clear()
    var radius := 1 if work_mode else 3
    for z in range(center.y-radius,center.y+radius+1):
        for x in range(center.x-radius,center.x+radius+1):
            _wanted.append(Vector2i(x,z))
    _wanted.sort_custom(func(a: Vector2i,b: Vector2i) -> bool:
        return a.distance_squared_to(center)<b.distance_squared_to(center))
    for key in chunks:
        chunks[key].visible = _chunk_visible(key)
        if key in _wanted: _used[key]=_clock

func _chunk_visible(key: Vector2i) -> bool:
    var radius := 1 if work_mode else 2
    return absi(key.x-_focus.x)<=radius and absi(key.y-_focus.y)<=radius


func configure(view: Node, profile: Resource = null) -> void:
    study_root = view
    art_profile = profile
    player = view.get_node_or_null("Player")
    terrain = view.get_node("TerrenoComposto/Superficie")
    for child in view.get_children():
        if child.has_method("contains_point"):
            waters.append(child)
        var cliff:=child.get_node_or_null("ContinuousCliff")
        if cliff and cliff.raised_zone_enabled and art_profile!=null and not art_profile.active_edits(view.get_path_to(cliff)).is_empty():
            raised_edit_surfaces.append(cliff)
    var mat: ShaderMaterial = terrain.material_override
    var texture: Texture2D = mat.get_shader_parameter("road_mask")
    road_mask = texture.get_image()
    if road_mask.is_compressed():
        road_mask.decompress()
    mask_center = mat.get_shader_parameter("road_mask_center")
    mask_size = mat.get_shader_parameter("road_mask_size")
    road_mask_center=mask_center
    road_mask_size=mask_size
    var coverage_bounds:=Rect2(mask_center-mask_size*.5,mask_size)
    for child in view.get_children():
        var cliff:=child.get_node_or_null("ContinuousCliff")
        if cliff==null or not cliff.raised_zone_enabled: continue
        var ground:=cliff.get_node_or_null("_GeneratedContinuousCliff/ElevatedGround") as MeshInstance3D
        if ground==null: continue
        var bounds:=ground.mesh.get_aabb()
        for corner in 8:
            var world:=ground.to_global(bounds.get_endpoint(corner))
            coverage_bounds=coverage_bounds.expand(Vector2(world.x,world.z))
            ground_ray_top=maxf(ground_ray_top,world.y+2.0)
    mask_center=coverage_bounds.get_center()
    mask_size=coverage_bounds.size
    density_field.seed = 712 if art_profile==null else art_profile.scatter_seed
    density_field.frequency = .16
    profile_field.seed = 1943
    profile_field.frequency = .21
    edge_field.seed = 871
    edge_field.frequency = 1.1
    pigment_field.seed = 3281
    pigment_field.frequency = 1.6
    heading_field.seed = density_field.seed+190
    heading_field.frequency = .31
    height_field.seed = density_field.seed+702
    height_field.frequency = .7
    for candidate in view.find_children("*","Node3D",true,false):
        if "path_surface" in candidate and candidate.path_surface!=null:
            authored_paths.append(candidate)
    bake_coverage()
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/anime_grass/grass_piece.json"))
    material = ShaderMaterial.new()
    material.shader = preload("res://shaders/pixelart/anime_grass.gdshader")
    material.set_shader_parameter("brush_painting", preload("res://assets/textures/anime_painted/meadow.png"))
    material.set_shader_parameter("brush_normal", preload("res://assets/textures/anime_painted/grass_brush_normal.png"))
    if art_profile != null and art_profile.grass_palette.size()>=3:
        for index in 3:
            var color: Color = art_profile.grass_palette[index]
            # These are linear pigment coefficients, not sRGB color uniforms.
            material.set_shader_parameter(["root_color","cool_tip","warm_tip"][index],Vector3(color.r,color.g,color.b))
    bind_meadow(material)
    for variant in MESH_COUNT:
        var mesh := build_variant(data, variant/3, variant%3)
        mesh.surface_set_material(0, material)
        blades.append(mesh)
    blade = blades[0]
    pebble_mesh = SphereMesh.new()
    pebble_mesh.radial_segments = 7
    pebble_mesh.rings = 3
    pebble_mesh.radius = 1.0
    pebble_mesh.height = 2.0
    var stone_material := StandardMaterial3D.new()
    stone_material.vertex_color_use_as_albedo = true
    stone_material.roughness = .95
    pebble_mesh.material = stone_material
    watch_obstacles()
    if not get_tree().node_added.is_connected(_on_static_added):
        get_tree().node_added.connect(_on_static_added)

func weighted_family(rng: RandomNumberGenerator, weights: Vector4) -> int:
    var total := maxf(.0001,weights.x+weights.y+weights.z+weights.w)
    var choice := rng.randf()*total
    for family in 4:
        choice -= weights[family]
        if choice<=0:
            return family
    return 0

func sample_road(uv: Vector2) -> float:
    if uv.x<0 or uv.y<0 or uv.x>=1 or uv.y>=1: return 0.0
    var pixel := uv*Vector2(road_mask.get_size())-Vector2.ONE*.5
    var low := Vector2i(pixel.floor())
    var f := pixel-Vector2(low)
    var a := road_mask.get_pixel(clampi(low.x,0,road_mask.get_width()-1),clampi(low.y,0,road_mask.get_height()-1)).r
    var b := road_mask.get_pixel(clampi(low.x+1,0,road_mask.get_width()-1),clampi(low.y,0,road_mask.get_height()-1)).r
    var c := road_mask.get_pixel(clampi(low.x,0,road_mask.get_width()-1),clampi(low.y+1,0,road_mask.get_height()-1)).r
    var d := road_mask.get_pixel(clampi(low.x+1,0,road_mask.get_width()-1),clampi(low.y+1,0,road_mask.get_height()-1)).r
    return lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)

func bake_coverage() -> void:
    var cache = preload("res://scripts/generation_cache.gd")
    var paths: Array=[]
    for lot in authored_paths:
        paths.append([lot.global_transform,lot.access_path,cache.snapshot(lot.path_surface)])
    var raised: Array=[]
    for cliff in raised_edit_surfaces:
        raised.append([study_root.get_path_to(cliff),cliff.global_transform,cache.snapshot(cliff.guide),cliff.wall_height,cliff.wall_depth,cliff.raised_zone_depth,cliff.access_ramp_length,cliff.access_ramp_base_height,cliff._elevated_sampler._top_vertices if cliff._elevated_sampler!=null else null,cliff._elevated_sampler._top_indices if cliff._elevated_sampler!=null else null])
    var key: String=cache.digest([3,cache.sources(["res://scripts/village/anime_grass.gd","res://scripts/art/art_study_profile.gd","res://scripts/art/art_surface_edit.gd","res://addons/village_builder/path_surface_profile.gd","res://addons/rock_builder/continuous_cliff.gd","res://addons/rock_builder/elevated_zone.gd"]),cache.snapshot(art_profile.edits if art_profile!=null else []),study_root.get_path_to(terrain),terrain.global_transform,mask_center,mask_size,road_mask_center,road_mask_size,road_mask.get_data(),paths,raised])
    var file: String=cache.path_for("coverage",key,".png")
    if FileAccess.file_exists(file):
        coverage=Image.load_from_file(file)
        if coverage!=null and coverage.get_size()==Vector2i(512,512):
            if coverage.get_format()!=Image.FORMAT_RGBA8: coverage.convert(Image.FORMAT_RGBA8)
            shared_coverage=ImageTexture.create_from_image(coverage)
            return
    # This single control image is consumed by both terrain shading and scatter.
    # R=road pigment, G=authored density, B=palette, A=dry bank coverage.
    coverage = Image.create(512,512,false,Image.FORMAT_RGBA8)
    var surface_path := study_root.get_path_to(terrain)
    for y in 512:
        for x in 512:
            var uv := (Vector2(x,y)+Vector2.ONE*.5)/512.0
            var p := (uv-Vector2.ONE*.5)*mask_size+mask_center
            var sample_point := p
            var access_road := 0.0
            for lot in authored_paths:
                var local_path: Vector3=lot.to_local(Vector3(p.x,lot.global_position.y,p.y))
                var q := Vector2(local_path.x,local_path.z)
                var offset: Vector2=lot.path_surface.warp(q,lot.access_path)
                var shifted: Vector3=lot.global_basis*Vector3(offset.x,0,offset.y)
                sample_point+=Vector2(shifted.x,shifted.z)
                access_road=maxf(access_road,lot.path_surface.road_amount(q,lot.access_path))
            var road_uv:=(sample_point-road_mask_center)/road_mask_size+Vector2.ONE*.5
            var road := smoothstep(.12,.82,sample_road(road_uv)+edge_field.get_noise_2d(p.x*3.0,p.y*3.0)*.14)
            road=maxf(road,access_road)
            var density := .5
            var pigment := clampf(.5+pigment_field.get_noise_2d(p.x,p.y)*1.5,0,1)
            var local := terrain.to_local(Vector3(p.x,.18,p.y))
            if art_profile != null and not art_profile.edits.is_empty():
                density = art_profile.sample_layer(0,surface_path,local,density)
                pigment = art_profile.sample_layer(1,surface_path,local,pigment)
                for cliff in raised_edit_surfaces:
                    var raised_local: Vector3=cliff.to_local(Vector3(p.x,.18,p.y))
                    var raised_height: float=cliff.height_at_local(Vector2(raised_local.x,raised_local.z))
                    if is_nan(raised_height): continue
                    raised_local.y=raised_height
                    var raised_path:=study_root.get_path_to(cliff)
                    density=art_profile.sample_layer(0,raised_path,raised_local,density)
                    pigment=art_profile.sample_layer(1,raised_path,raised_local,pigment)
            # Exact polygon tests remain in placement; shoreline blending is
            # height-based in the terrain shader so wet beds stay uncovered.
            coverage.set_pixel(x,y,Color(road,density,pigment,1.0))
    coverage.save_png(file)
    shared_coverage = ImageTexture.create_from_image(coverage)

func bind_meadow(target: ShaderMaterial) -> void:
    if art_profile==null: return
    var anchor:=study_root.get_node_or_null(art_profile.grass_study_surface) if not art_profile.grass_study_surface.is_empty() else null
    target.set_shader_parameter("meadow_region",Vector4.ZERO)
    if anchor:
        target.set_shader_parameter("meadow_region",Vector4(anchor.global_position.x,anchor.global_position.z,art_profile.grass_study_radius,0))
    for pair in [["meadow_patch_scale","grass_patch_scale"],["meadow_ground_influence","grass_ground_influence"],["meadow_normal_mix","grass_normal_mix"],["meadow_wind_strength","grass_wind_strength"]]:
        target.set_shader_parameter(pair[0],art_profile.get(pair[1]))
    if art_profile.grass_palette.size()>=3:
        for i in 2:
            var c: Color=art_profile.grass_palette[i+1]
            target.set_shader_parameter(["meadow_cool","meadow_warm"][i],Vector3(c.r,c.g,c.b))

func bind_ground(ground_material: ShaderMaterial) -> void:
    bind_meadow(ground_material)
    ground_material.set_shader_parameter("art_coverage",shared_coverage)
    ground_material.set_shader_parameter("art_coverage_center",mask_center)
    ground_material.set_shader_parameter("art_coverage_size",mask_size)
    ground_material.set_shader_parameter("use_art_coverage",true)

func build_variant(data: Dictionary, kind: int, variation: int = 0) -> ArrayMesh:
    # A source leaf has four triangles. Each variant has a different leaf count,
    # individual bends and an asymmetric footprint, not just a scaled duplicate.
    var rng := RandomNumberGenerator.new()
    rng.seed = 6100 + kind*31 + variation*107
    var candidates: Array[int] = []
    # The latter half is the reverse shell of the same six blades.
    # The shader is double sided; deforming that shell independently creates
    # intersecting duplicates instead of additional leaves.
    for i in int(data.vertices.size()/24):
        candidates.append(i)
    for i in range(candidates.size()-1,0,-1):
        var j := rng.randi_range(0,i)
        var swap := candidates[i]
        candidates[i] = candidates[j]
        candidates[j] = swap
    var count: int = [5,4,3,6][kind]
    var height: float = [.75,1.0,1.35,.65][kind]*[.82,1.0,1.16][variation]
    var width: float = [1.12,1.0,.85,1.30][kind]*[1.25,1.0,.88][variation]
    var bend: float = [.012,.035,.045,.065][kind]*[1.45,.85,1.20][variation]
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for leaf in count:
        var start := candidates[leaf]*12
        var side_a: Array = data.vertices[start]
        var side_b: Array = data.vertices[start+1]
        var lateral := Vector3(side_a[0]-side_b[0],0,side_a[2]-side_b[2]).normalized()
        var middle := Vector3((side_a[0]+side_b[0])*.5,0,(side_a[2]+side_b[2])*.5)
        var tallest := .001
        for index in range(start,start+12):
            tallest = maxf(tallest,data.vertices[index][1])
        var leaf_height := height*rng.randf_range(.72,1.20)
        var rotation := Basis(Vector3.UP,rng.randf_range(-.40,.40))
        var root_offset := Vector3(rng.randf_range(-.018,.018),0,rng.randf_range(-.018,.018))
        var lean := Vector3(bend,0,rng.randf_range(-bend*.45,bend*.45))
        var ribbon_width := rng.randf_range(.70,1.65)
        var tip_hook := rng.randf_range(-.025,.025)
        var pigment := rng.randf_range(.90,1.08)
        for triangle in range(start,start+12,3):
            for corner in [0,2,1]:
                var index: int = triangle+corner
                var source: Array = data.vertices[index]
                var p := Vector3(source[0],source[1],source[2])
                # Broaden only the ribbon, preserving its length and pointed silhouette.
                p += lateral * (p-middle).dot(lateral) * (2.15*ribbon_width-1.0)
                var t := clampf(p.y/tallest,0,1)
                p += lateral * tip_hook * t*t*t
                p = rotation*(p*Vector3(width,leaf_height,width)) + root_offset + lean*t*t
                var normal: Array = data.normals[index]
                st.set_normal(rotation*Vector3(normal[0],normal[1],normal[2]))
                st.set_uv(Vector2(float(leaf)/count,t))
                st.set_color(Color(pigment,pigment,pigment,1.0))
                st.add_vertex(p)
    return st.commit()

func set_enabled(active: bool) -> void:
    enabled = active
    visible = active

func _physics_process(_delta: float) -> void:
    if not enabled: return
    # Physics may catch up several ticks in one rendered frame. Spend the
    # streaming allowance only once; manual profiler calls disable processing.
    var process_frame := Engine.get_process_frames()
    if is_physics_processing() and process_frame==_last_stream_frame: return
    _last_stream_frame=process_frame
    var started := Time.get_ticks_usec()
    _deadline = started+budget_usec
    _clock += 1
    audit_obstacles(_delta)
    var focus := player.global_position if not Engine.is_editor_hint() and is_instance_valid(player) else editor_center
    var center := Vector2i(floori(focus.x / CHUNK), floori(focus.z / CHUNK))
    if _world_dirty:
        _world_dirty=false
        watch_obstacles()
        _revision+=1
        for chunk in chunks.values(): _retire(chunk)
        chunks.clear()
        _used.clear()
        _focus=Vector2i(2147483647,2147483647)
    if center!=_focus: _update_demand(center)
    _discard_one()
    if _building:
        work_resumed.emit()
    while not _building and Time.get_ticks_usec()<_deadline:
        var found := false
        for key in _wanted:
            if chunks.has(key): continue
            _building=true
            build_chunk(key)
            found=true
            break
        if not found: break
    last_work_usec=Time.get_ticks_usec()-started
    max_work_usec=maxi(max_work_usec,last_work_usec)

func _job_valid(key: Vector2i, revision: int) -> bool:
    return revision==_revision and key in _wanted

func _evict_oldest() -> void:
    if chunks.size()<81: return
    var oldest: Variant=null
    var age := 2147483647
    for key in chunks:
        if key in _wanted: continue
        if int(_used.get(key,0))<age:
            oldest=key
            age=int(_used.get(key,0))
    if oldest!=null:
        _retire(chunks[oldest])
        chunks.erase(oldest)
        _used.erase(oldest)

func build_chunk(key: Vector2i) -> void:
    var revision := _revision
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(key) + (712 if art_profile==null else art_profile.scatter_seed)
    var transforms: Array = []
    var colors: Array = []
    for i in MESH_COUNT:
        transforms.append([])
        colors.append([])
    var stones: Array[Transform3D] = []
    var stone_colors: Array[Color] = []
    var space := get_world_3d().direct_space_state
    var base := Vector2(key) * CHUNK
    var multiplier: float = 1.3 if art_profile==null else art_profile.density_multiplier
    var spacing := STEP/sqrt(maxf(.05,multiplier * (.25 if work_mode else 1.0)))
    var cells := ceili(CHUNK/spacing)
    spacing = CHUNK/cells
    for z in range(cells):
        for x in range(cells):
            if Time.get_ticks_usec()>=_deadline:
                await work_resumed
                if not _job_valid(key,revision):
                    _building=false
                    return
                space=get_world_3d().direct_space_state
            var p := base + Vector2(x + rng.randf(), z + rng.randf()) * spacing
            var patch := clampf(.50+density_field.get_noise_2d(p.x,p.y)*1.4,0,1)
            var ragged := edge_field.get_noise_2d(p.x,p.y)*.18
            if rng.randf() > lerpf(.075,.98,smoothstep(.18,.74,patch+ragged)):
                continue
            var uv := (p-mask_center)/mask_size+Vector2.ONE*.5
            var shared := coverage.get_pixel(clampi(int(uv.x*coverage.get_width()),0,coverage.get_width()-1),clampi(int(uv.y*coverage.get_height()),0,coverage.get_height()-1))
            if uv.x<0 or uv.y<0 or uv.x>=1 or uv.y>=1:
                # Raised zones may extend beyond the old flat terrain mask.
                # The ground shader uses the same dry meadow fallback there.
                shared.r=0.0
                shared.g=.5
            var road := shared.r
            var is_stone := road>.30 and rng.randf()<.025
            var grass_edge := (1.0-road)*shared.g*2.0*shared.a
            if not is_stone and rng.randf()>grass_edge:
                continue
            var query := PhysicsRayQueryParameters3D.create(Vector3(p.x,ground_ray_top,p.y),Vector3(p.x,-1,p.y))
            var hit := space.intersect_ray(query)
            if hit.is_empty():
                continue
            var raised_ground: bool=hit.collider.get_meta("art_ground_surface",false)
            if not terrain.is_ancestor_of(hit.collider) and not raised_ground:
                continue
            if hit.position.y < .12 or hit.normal.y < .65:
                continue
            var in_water := false
            for water in waters:
                var local: Vector3 = water.to_local(hit.position)
                if local.y<.3 and water.contains_point(Vector2(local.x,local.z)):
                    in_water = true
                    break
            if in_water:
                continue
            if is_stone:
                var radius := rng.randf_range(.055,.16)
                var stone_basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(radius,radius*rng.randf_range(.30,.60),radius*rng.randf_range(.65,1.3)))
                stones.append(Transform3D(stone_basis,hit.position+Vector3(0,.008,0)))
                var shade := rng.randf_range(.80,1.12)
                stone_colors.append(Color(.36,.32,.23)*shade)
                continue
            var profile := clampf(.5+profile_field.get_noise_2d(p.x,p.y)*1.6,0,1)
            var kind := 0
            if profile > .76: kind = 2
            elif profile > .52: kind = 1
            elif profile < .28: kind = 3
            # Neighboring profiles mingle at the edge of each patch.
            if rng.randf()<.16:
                kind = rng.randi_range(0,3)
            if art_profile != null:
                var weights: Vector4 = art_profile.normalized_family_weights()
                if rng.randf()>weights[kind]/maxf(.001,maxf(maxf(weights.x,weights.y),maxf(weights.z,weights.w))):
                    kind = weighted_family(rng,weights)
            var variant := kind*3+rng.randi_range(0,2)
            var size := rng.randf_range(.82,1.25)
            var height_scale := lerpf(.80,1.2,clampf(.5+height_field.get_noise_2d(p.x,p.y),0,1))
            var heading := heading_field.get_noise_2d(p.x,p.y)*TAU+rng.randf_range(-.8,.8)
            var basis := Basis(Vector3.UP,heading).scaled(Vector3(size,size*height_scale*rng.randf_range(.8,1.2),size))
            transforms[variant].append(Transform3D(basis,hit.position+Vector3(0,-.008,0)))
            var tint_jitter := rng.randf()
            var pigment := clampf(shared.b+(tint_jitter-.5)*.12,0,1)
            colors[variant].append(Color(pigment,pigment,rng.randf(),patch))
    var chunk := Node3D.new()
    chunk.name = "Grass_%d_%d" % [key.x,key.y]
    chunk.visible=false
    add_child(chunk)
    for kind in MESH_COUNT:
        if Time.get_ticks_usec()>=_deadline:
            await work_resumed
            if not _job_valid(key,revision):
                _retire(chunk)
                _building=false
                return
        var instance := MultiMeshInstance3D.new()
        instance.name = VARIANTS[kind/3]+"_%d"%(kind%3)
        chunk.add_child(instance)
        var multi := MultiMesh.new()
        multi.transform_format = MultiMesh.TRANSFORM_3D
        multi.use_custom_data = true
        multi.mesh = blades[kind]
        multi.instance_count = transforms[kind].size()
        for i in transforms[kind].size():
            if i%32==0 and Time.get_ticks_usec()>=_deadline:
                await work_resumed
                if not _job_valid(key,revision):
                    instance.free()
                    _retire(chunk)
                    _building=false
                    return
            multi.set_instance_transform(i, transforms[kind][i])
            multi.set_instance_custom_data(i, colors[kind][i])
        instance.multimesh = multi
        # Subpixel grass shadow maps produce black stippling at gameplay distance.
        # Keep receiving tree/world shadows; root shading and SSAO anchor blades.
        instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        instance.extra_cull_margin = .15
    var stone_instances := MultiMeshInstance3D.new()
    stone_instances.name = "PathPebbles"
    chunk.add_child(stone_instances)
    var stone_multi := MultiMesh.new()
    stone_multi.transform_format = MultiMesh.TRANSFORM_3D
    stone_multi.use_colors = true
    stone_multi.mesh = pebble_mesh
    stone_multi.instance_count = stones.size()
    for i in stones.size():
        if i%32==0 and Time.get_ticks_usec()>=_deadline:
            await work_resumed
            if not _job_valid(key,revision):
                stone_instances.free()
                _retire(chunk)
                _building=false
                return
        stone_multi.set_instance_transform(i,stones[i])
        stone_multi.set_instance_color(i,stone_colors[i])
    stone_instances.multimesh = stone_multi
    _evict_oldest()
    chunks[key] = chunk
    _used[key] = _clock
    chunk.visible = _chunk_visible(key)
    _building = false

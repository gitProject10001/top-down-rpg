@tool
extends Node3D
## Prescribed water surface; no time-integrated fluid state.
@export var boundary := PackedVector2Array([Vector2(-8,-4),Vector2(-5,-7),Vector2(0,-7),Vector2(4,-4),Vector2(5,-1),Vector2(12,1),Vector2(16,0),Vector2(17,3),Vector2(12,4),Vector2(5,2),Vector2(2,5),Vector2(-4,5),Vector2(-8,2)]):
    set(value):
        boundary = value
        schedule_build()
@export var flow_path := PackedVector2Array([Vector2(0,0),Vector2(5,.5),Vector2(12,2.5),Vector2(16.5,1.5)]):
    set(value):
        flow_path = value
        schedule_build()
@export_range(0, 2, .05) var flow_speed := .55:
    set(value):
        flow_speed = value
        schedule_build()
@export_range(.1, 1, .05) var basin_depth := .4:
    set(value):
        basin_depth = value
        schedule_build()
@export var debug_flow := false:
    set(value):
        debug_flow = value
        schedule_build()
@export var vortex_center := Vector2(-3, -2):
    set(value):
        vortex_center = value
        schedule_build()
@export_range(0, 2, .05) var vortex_strength := 0.0:
    set(value):
        vortex_strength = value
        schedule_build()
var _pending := false
var _surface: MeshInstance3D
var _clock := 0.0
var _rings := PackedVector4Array()
var _next_ring := 0
var _wakes := PackedVector4Array()
var _directions := PackedVector2Array()
var _next_wake := 0
var _spray: MultiMeshInstance3D
var _drops: Array[Dictionary] = []
var _drop_cursor := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    for i in 8: _rings.append(Vector4(0,0,-100,0))
    for i in 16:
        _wakes.append(Vector4(0,0,-100,0))
        _directions.append(Vector2.ZERO)
    if not Engine.is_editor_hint():
        _spray = MultiMeshInstance3D.new()
        _spray.name = "LocalSpray"
        _spray.multimesh = MultiMesh.new()
        _spray.multimesh.transform_format = MultiMesh.TRANSFORM_3D
        var drop := SphereMesh.new()
        drop.radius = .025
        drop.height = .065
        drop.radial_segments = 6
        drop.rings = 2
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(.52,.78,.72)
        material.roughness = .25
        drop.material = material
        _spray.multimesh.mesh = drop
        _spray.multimesh.instance_count = 48
        _spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(_spray,false,Node.INTERNAL_MODE_BACK)
        for i in 48:
            _drops.append({"age":1.0,"position":Vector3.ZERO,"velocity":Vector3.ZERO})
            _spray.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
    rebuild()

func schedule_build() -> void:
    if not is_inside_tree() or _pending: return
    _pending = true
    call_deferred("rebuild")

func _get_configuration_warnings() -> PackedStringArray:
    if boundary.size() < 3 or boundary.size() > 32:
        return ["Il perimetro richiede da 3 a 32 vertici."]
    if flow_path.size() > 16: return ["Massimo 16 punti del flusso nel prototipo."]
    if Geometry2D.triangulate_polygon(boundary).is_empty(): return ["Perimetro non triangolabile: controllare incroci e punti duplicati."]
    return []

func rebuild() -> void:
    _pending = false
    if is_instance_valid(_surface):
        remove_child(_surface)
        _surface.free()
    update_configuration_warnings()
    if not _get_configuration_warnings().is_empty(): return
    var indices := Geometry2D.triangulate_polygon(boundary)
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var uv := PackedVector2Array()
    for p in boundary:
        vertices.append(Vector3(p.x,0,p.y))
        normals.append(Vector3.UP)
        uv.append(p)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uv
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    var material := ShaderMaterial.new()
    material.shader = preload("res://shaders/pixelart/prescribed_water.gdshader")
    var edges := boundary.duplicate()
    edges.resize(32)
    var path := flow_path.duplicate()
    path.resize(16)
    material.set_shader_parameter("boundary",edges)
    material.set_shader_parameter("edge_count",boundary.size())
    material.set_shader_parameter("flow_path",path)
    material.set_shader_parameter("path_count",flow_path.size())
    material.set_shader_parameter("flow_speed",flow_speed)
    material.set_shader_parameter("basin_depth",basin_depth)
    material.set_shader_parameter("debug_flow",debug_flow)
    material.set_shader_parameter("vortex_center",vortex_center)
    material.set_shader_parameter("vortex_strength",vortex_strength)
    _surface = MeshInstance3D.new()
    _surface.name = "WaterSurface"
    _surface.mesh = mesh
    _surface.material_override = material
    _surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_surface, false, Node.INTERNAL_MODE_BACK)

func contains_point(point: Vector2) -> bool:
    return Geometry2D.is_point_in_polygon(point,boundary)

func shore_distance(point: Vector2) -> float:
    var distance := INF
    for i in boundary.size():
        var a := boundary[i]
        var b := boundary[(i+1)%boundary.size()]
        var closest := Geometry2D.get_closest_point_to_segment(point,a,b)
        distance = minf(distance,point.distance_to(closest))
    return distance

func bed_height(point: Vector2) -> float:
    var d := shore_distance(point)
    if contains_point(point): return -.015-basin_depth*smoothstep(0,1.5,d)
    return .18*smoothstep(0,1.1,d)

func ripple(world_point: Vector3, strength := 1.0) -> void:
    var local := to_local(world_point)
    if not contains_point(Vector2(local.x,local.z)): return
    _rings[_next_ring] = Vector4(local.x,local.z,_clock,clampf(strength,0,1))
    _next_ring = (_next_ring+1)%8

func disturb(world_point: Vector3, world_velocity: Vector3) -> void:
    var local := to_local(world_point)
    if not contains_point(Vector2(local.x,local.z)): return
    var velocity := global_basis.inverse()*world_velocity
    var heading := Vector2(velocity.x,velocity.z)
    var speed := heading.length()
    if speed < .2: return
    heading /= speed
    var strength := clampf(speed/5.0,.15,1.0)
    _wakes[_next_wake] = Vector4(local.x,local.z,_clock,strength)
    _directions[_next_wake] = heading
    _next_wake = (_next_wake+1)%16
    ripple(world_point,strength*.6)
    if not is_instance_valid(_spray): return
    for i in 4:
        var side := Vector3(-heading.y,0,heading.x)*(-1 if i%2 else 1)
        _drops[_drop_cursor] = {"age":0.0,
            "position":Vector3(local.x,.025,local.z)+side*.12,
            "velocity":side*_rng.randf_range(.4,1.0)*strength+Vector3(heading.x,0,heading.y)*speed*.12+Vector3.UP*_rng.randf_range(.8,1.6)*strength}
        _drop_cursor = (_drop_cursor+1)%48

func _process(delta: float) -> void:
    _clock += delta
    if is_instance_valid(_surface):
        _surface.material_override.set_shader_parameter("clock",_clock)
        _surface.material_override.set_shader_parameter("rings",_rings)
        _surface.material_override.set_shader_parameter("wakes",_wakes)
        _surface.material_override.set_shader_parameter("wake_directions",_directions)
    if is_instance_valid(_spray):
        for i in _drops.size():
            var drop := _drops[i]
            if drop.age >= .6: continue
            drop.age += delta
            drop.velocity += Vector3.DOWN*5.0*delta
            drop.position += drop.velocity*delta
            var size := maxf(0.0,1.0-drop.age/.6) if drop.position.y>0 else 0.0
            _spray.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),drop.position))

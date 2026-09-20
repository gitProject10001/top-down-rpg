extends RefCounted
## Original leaf cards built from the authored branch paths and crown lobes.
## Only foliage meshes go through this class; trunk and branch nodes stay intact.
var cache: Dictionary = {}
var seed: int = 2109
var crown_normal_blend: float = .70
const SHAPE_NAMES := ["compact", "open", "elongated", "forked"]
const CARD_COORDS := [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1),
    Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]
const CARD_INDICES := [0, 4, 1, 0, 3, 4, 1, 5, 2, 1, 4, 5]

func point(value: Array) -> Vector3:
    return Vector3(value[0], value[2], -value[1])

func branch_direction(center: Vector3, paths: Array) -> Vector3:
    var nearest := INF
    var direction := Vector3.UP
    for path in paths:
        var points: Array = path.points
        for i in range(1, points.size()):
            var a := point(points[i - 1])
            var b := point(points[i])
            var closest := Geometry3D.get_closest_point_to_segment(center, a, b)
            var distance := center.distance_squared_to(closest)
            if distance < nearest:
                nearest = distance
                direction = (b - a).normalized()
    return direction

func for_mesh(source: Mesh, species: String) -> ArrayMesh:
    var key := "%s:%s:%s:%.3f" % [source.get_instance_id(), species, seed, crown_normal_blend]
    if cache.has(key):
        return cache[key]
    var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
        "res://assets/models/foliage_study/" + species + "_plan.json"))
    var rng := RandomNumberGenerator.new()
    rng.seed = seed + (17 if species == "pine" else 0)
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var uvs := PackedVector2Array()
    var local_uvs := PackedVector2Array()
    var colors := PackedColorArray()
    var indices := PackedInt32Array()
    var shape_counts := PackedInt32Array([0, 0, 0, 0])
    var bounds := source.get_aabb()
    var lobe_id := 0
    for lobe in plan.lobes:
        var center := point(lobe.center)
        var radii := Vector3(lobe.radii[0], lobe.radii[2], lobe.radii[1])
        var outward := branch_direction(center, plan.paths)
        var count := 30 if species == "broadleaf" else 23
        var group_tint := rng.randf_range(.16, .84)
        for card in count:
            # A stratified shell plus some interior sprays keeps distinct lobes
            # without a hollow sphere. Offsets and orientation are deterministic.
            var azimuth := card * 2.399963 + rng.randf_range(-.22, .22)
            var y := 1.0 - 2.0 * (float(card) + .5) / float(count)
            var ring := sqrt(maxf(0.0, 1.0 - y * y))
            var direction := Vector3(cos(azimuth) * ring, y, sin(azimuth) * ring)
            var depth := rng.randf_range(.38, .83)
            var offset := direction * radii * depth
            var origin := center + offset
            var crown := (offset / (radii * radii)).normalized()
            var plane := (Vector3.UP * .72 + direction * .46).normalized()
            # Project the real branch direction into this spray's plane.
            var along := outward - plane * outward.dot(plane)
            if along.length_squared() < .01:
                along = Vector3.FORWARD - plane * Vector3.FORWARD.dot(plane)
            along = along.normalized()
            var across := along.cross(plane).normalized()
            var roll := rng.randf_range(-.48, .48)
            plane = plane.rotated(along, roll)
            across = along.cross(plane).normalized()
            var kind := (card + lobe_id) % 4
            shape_counts[kind] += 1
            var length := rng.randf_range(.72, 1.10) if species == "broadleaf" else rng.randf_range(.65, .94)
            var width: float = length * [.93, 1.12, .75, 1.05][kind]
            var fold := rng.randf_range(.07, .14) * width
            var droop := rng.randf_range(.025, .10) * length
            var base := vertices.size()
            var flip := rng.randf() > .5
            var cavity := lerpf(.57, 1.0, depth)
            for coord in CARD_COORDS:
                var position: Vector3 = origin + across * coord.x * width * .5 + along * coord.y * length * .5
                position += plane * (fold * (1.0 - absf(coord.x)) - droop * (coord.y + 1.0) * .5)
                # Keep the previous outer crown envelope; no oversized new crown.
                position = position.clamp(bounds.position, bounds.end)
                vertices.append(position)
                var face_normal := (plane + across * signf(coord.x) * fold / maxf(width * .5, .01)).normalized()
                if face_normal.dot(crown) < 0.0:
                    face_normal = -face_normal
                normals.append((crown * crown_normal_blend + face_normal * (1.0 - crown_normal_blend)).normalized())
                var local_uv := Vector2((coord.x + 1.0) * .5, (1.0 - coord.y) * .5)
                if flip:
                    local_uv.x = 1.0 - local_uv.x
                # Four independent painted sprays with UVs held inside each cell.
                var cell := Vector2(kind % 2, kind / 2)
                uvs.append((cell + Vector2(.006, .006) + local_uv * .988) * .5)
                local_uvs.append(Vector2((coord.x + 1.0) * .5, (coord.y + 1.0) * .5))
                var tip_weight := pow((coord.y + 1.0) * .5, 1.4)
                colors.append(Color(cavity, clampf(group_tint + rng.randf_range(-.06, .06), 0.0, 1.0), tip_weight, 1.0))
            for index in CARD_INDICES:
                indices.append(base + index)
        lobe_id += 1
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_TEX_UV2] = local_uvs
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    var result := ArrayMesh.new()
    result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    result.surface_set_material(0, source.surface_get_material(0))
    result.set_meta("painted_canopy", true)
    result.set_meta("shape_counts", shape_counts)
    result.set_meta("source_bounds", bounds)
    result.set_meta("seed", seed)
    cache[key] = result
    return result

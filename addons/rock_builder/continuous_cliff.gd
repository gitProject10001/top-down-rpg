@tool
extends Node3D
## One closed geological surface behind the existing formation guide.
## Add as a child of the source Path3D, then configure_from(source). The source
## remains the authority for its transform; this node uses identity locally.
const Masonry = preload("res://shaders/pixelart/solid_masonry.gdshader")
const FracturedBoulder = preload("res://addons/rock_builder/fractured_boulder.gd")
const Rock = preload("res://addons/rock_builder/rock.gd")
const ElevatedZone = preload("res://addons/rock_builder/elevated_zone.gd")
signal rebuilt

@export var guide: Curve3D:
 set(value):
  if guide != null and guide.changed.is_connected(schedule): guide.changed.disconnect(schedule)
  guide = value
  if guide != null and not guide.changed.is_connected(schedule): guide.changed.connect(schedule)
  schedule()
@export var cliff_seed := 31:
 set(value): cliff_seed = value; schedule()
@export_range(1.0, 20.0, 0.1) var wall_height := 5.0:
 set(value): wall_height = maxf(value, 1.0); schedule()
@export_range(1.0, 10.0, 0.1) var wall_depth := 3.6:
 set(value): wall_depth = maxf(value, 1.0); schedule()
@export_range(1, 6, 1) var strata := 3:
 set(value): strata = clampi(value, 1, 6); schedule()
@export_range(-0.3, 0.3, 0.01) var strata_dip := 0.15:
 set(value): strata_dip = value; schedule()
@export_range(0.0, 1.0, 0.01) var fracture := 0.8:
 set(value): fracture = clampf(value, 0.0, 1.0); schedule()
@export_range(0.2, 1.0, 0.05) var sample_spacing := 0.5:
 set(value): sample_spacing = clampf(value, 0.2, 1.0); schedule()
@export var stone_color := Color(0.37, 0.36, 0.31):
 set(value): stone_color = value; schedule()
@export var collisions_enabled := true:
 set(value): collisions_enabled = value; schedule()
## Replace the old stratified front with full-height fractured rock masses.
@export var layered_rock_wall := false:
 set(value): layered_rock_wall=value; schedule()
@export_range(1.0,15.0,0.25) var wall_rock_size := 5.5:
 set(value): wall_rock_size=clampf(value,1.0,15.0); schedule()
@export var debris_enabled := true:
 set(value): debris_enabled = value; schedule()
@export var painted := true:
 set(value): painted = value; schedule()
@export_group("Zona sopraelevata")
@export var raised_zone_enabled := false:
 set(value): raised_zone_enabled = value; schedule()
@export_range(6.0, 48.0, 0.5) var raised_zone_depth := 22.0:
 set(value): raised_zone_depth = clampf(value, 6.0, 48.0); schedule()
@export_range(8.0, 60.0, 0.5) var access_ramp_length := 16.0:
 set(value): access_ramp_length = clampf(value, 8.0, 60.0); schedule()
@export_range(-1.0, 2.0, 0.01) var access_ramp_base_height := 0.18:
 set(value): access_ramp_base_height = value; schedule()
@export var ground_material: Material:
 set(value):
  ground_material = value
  _apply_ground_material()
@export_tool_button("Rigenera parete continua") var rebuild_action: Callable = rebuild

var triangle_count := 0
var last_error := ""
var _pending := false
var _generated: Node3D
var _elevated_sampler: RefCounted

func _ready() -> void:
 rebuild()

func configure_from(formation: Path3D) -> void:
 transform = Transform3D.IDENTITY
 guide = formation.curve
 cliff_seed = int(formation.get("formation_seed"))
 wall_height = float(formation.get("wall_height"))
 strata = int(formation.get("strata"))
 strata_dip = float(formation.get("strata_dip"))
 wall_depth = maxf(2.0, float(formation.get("spacing")) * 0.9)
 schedule()

func schedule() -> void:
 if _pending or not is_inside_tree(): return
 _pending = true
 call_deferred("rebuild")

func rebuild() -> void:
 _pending = false
 if not is_inside_tree(): return
 var result := generate()
 last_error = str(result.get("error", ""))
 if not last_error.is_empty():
  # Keep the last valid result when an editor guide temporarily becomes invalid.
  push_warning(last_error)
  return
 if is_instance_valid(_generated): _generated.free()
 _generated = Node3D.new()
 _generated.name = "_GeneratedContinuousCliff"
 add_child(_generated, false, Node.INTERNAL_MODE_BACK)
 var visual := MeshInstance3D.new()
 visual.name = "ContinuousGeology"
 visual.mesh = result.mesh
 _generated.add_child(visual)
 if collisions_enabled:
  var body := StaticBody3D.new()
  body.name = "CliffCollision"
  var collision := CollisionShape3D.new()
  var shape := ConcavePolygonShape3D.new()
  shape.set_faces(result.faces)
  collision.shape = shape
  body.add_child(collision)
  _generated.add_child(body)
 _elevated_sampler = null
 if result.has("elevated"):
  var terrain: Dictionary = result.elevated
  _elevated_sampler = terrain.sampler
  var ground := MeshInstance3D.new()
  ground.name = "ElevatedGround"
  ground.mesh = terrain.mesh
  _generated.add_child(ground)
  _apply_ground_material()
  var skirt := MeshInstance3D.new()
  skirt.name = "ElevatedGroundSkirt"
  skirt.mesh = terrain.skirt_mesh
  var skirt_material: ShaderMaterial = result.mesh.surface_get_material(0).duplicate()
  skirt_material.set_shader_parameter("use_vertex_color", false)
  skirt_material.set_shader_parameter("base_color", Vector3(stone_color.r, stone_color.g, stone_color.b))
  skirt.material_override = skirt_material
  _generated.add_child(skirt)
  if collisions_enabled:
   var body := StaticBody3D.new()
   body.name = "ElevatedGroundCollision"
   body.set_meta("art_ground_surface", true)
   body.set_meta("art_surface_node", self)
   body.set_meta("art_surface_path", NodePath(str(get_parent().name) + "/" + str(name)))
   var collision := CollisionShape3D.new()
   var shape := ConcavePolygonShape3D.new()
   shape.set_faces(terrain.faces)
   collision.shape = shape
   body.add_child(collision)
   _generated.add_child(body)
 if debris_enabled:
  for record in result.debris:
   var piece := Rock.new()
   piece.name = record.id
   piece.rock_seed = record.seed
   piece.dimensions = record.dimensions
   piece.stone_color = stone_color * 0.91
   piece.strata = 1
   piece.fracture = 0.8
   piece.collisions_enabled = collisions_enabled
   piece.transform = record.transform
   _generated.add_child(piece)
   for mesh_node in piece.find_children("*", "MeshInstance3D", true, false):
    var material: ShaderMaterial = mesh_node.mesh.surface_get_material(0)
    material.set_shader_parameter("anime_painted", painted)
 triangle_count = result.triangles
 rebuilt.emit()

func effective_ramp_length() -> float:
 return maxf(access_ramp_length, wall_height * 2.4)

func height_at_local(point: Vector2) -> float:
 if _elevated_sampler == null: return NAN
 return _elevated_sampler.height_at_local(point)

func set_ground_material(material: Material) -> void:
 ground_material = material

func _apply_ground_material() -> void:
 if not is_instance_valid(_generated): return
 var ground := _generated.get_node_or_null("ElevatedGround") as MeshInstance3D
 if ground == null: return
 if ground_material != null:
  ground.material_override = ground_material
 else:
  var fallback := StandardMaterial3D.new()
  fallback.albedo_color = Color(0.24, 0.31, 0.17)
  fallback.roughness = 1.0
  ground.material_override = fallback

## Pure deterministic builder; no tree or rendering dependency.
## Invalid/self-crossing guides return {error} before altering any existing mesh.
func generate() -> Dictionary:
 if guide == null or guide.get_baked_length() < 1.0:
  return {"error": "La parete continua richiede una guida di almeno un metro."}
 var baked := guide.get_baked_points()
 for point in baked:
  if absf(point.y) > 0.01:
   return {"error": "La guida della parete deve essere piana a quota locale zero."}
 var length_value := guide.get_baked_length()
 if length_value > 240.0:
  return {"error": "Dividi le pareti più lunghe di 240 metri in più guide."}
 if _guide_crosses(baked):
  return {"error": "La guida della parete si incrocia: correggila prima di rigenerare."}
 var rng := RandomNumberGenerator.new()
 rng.seed = cliff_seed
 var phase := rng.randf_range(-PI, PI)
 var fissures: Array[Vector3] = []
 var distance_value := rng.randf_range(1.6, 2.8)
 while distance_value < length_value - 0.7:
  # x=guide distance, y=half width, z=depth. Whole-height correlated cuts.
  fissures.append(Vector3(distance_value, rng.randf_range(0.14, 0.44), rng.randf_range(0.45, 1.0)))
  distance_value += rng.randf_range(2.8, 5.7)
 var stations: Array[float] = [0.0, length_value]
 var samples := ceili(length_value / sample_spacing)
 for i in range(1, samples):
  stations.append(float(i) / samples * length_value)
 for fissure in fissures:
  for offset in [-1.65, -1.0, -0.18, 0.18, 1.0, 1.65]:
   stations.append(clampf(fissure.x + fissure.y * offset, 0.0, length_value))
 stations.sort()
 var distinct: Array[float] = []
 for station in stations:
  if distinct.is_empty() or station - distinct[-1] > 0.035: distinct.append(station)
 if distinct[-1] < length_value: distinct[-1] = length_value
 stations = distinct

 var levels: Array[float] = [0.0, 0.055]
 for layer in range(1, strata + 1):
  var t := float(layer) / (strata + 1)
  levels.append(t - 0.027)
  levels.append(t)
  levels.append(t + 0.035)
 levels.append(0.92)
 levels.append(1.0)
 levels.sort()
 var vertices := PackedVector3Array()
 var colors := PackedColorArray()
 var uvs := PackedVector2Array()
 var rings: Array[PackedVector3Array] = []
 var crests := PackedVector3Array()
 var front_vertex_count := levels.size()
 # Front rises, roof traverses backward, rear descends: one closed cross section.
 var ring_size := front_vertex_count + 3
 for s in stations:
  var frame := _frame(s, length_value)
  var center: Vector3 = frame.center
  var front: Vector3 = frame.front
  var crest := wall_height * (0.98 + 0.14 * _angular_wave(s * 0.40 + phase) + 0.065 * _angular_wave(s * 1.72 + phase * 0.7))
  var cut := _cut_at(s, 1.0, fissures, phase)
  crest -= cut * wall_height * 0.11 * fracture
  var back_depth := wall_depth + 0.20 * sin(s * 0.41 + phase)
  var ring := PackedVector3Array()
  for t in levels:
   var incision := _cut_at(s, t, fissures, phase)
   var broad := 0.5 + 0.5 * _angular_wave(s * 0.61 + phase + t * 0.2)
   var sediment := fmod(t * (strata + 1), 1.0)
   var seam := 1.0 - smoothstep(0.0, 0.16, minf(sediment, 1.0 - sediment))
   # All front vertices stay strictly behind the guide. Horizontal shelves are
   # shallow cuts in one face, while vertical fractures reach much farther in.
   var setback := 0.19 + broad * 0.45 + smoothstep(0.02, 0.25, t) * 0.36
   setback += t * lerpf(0.03, 0.65, 0.5 + 0.5 * sin(s * 0.37 + phase * 0.6))
   setback += incision * wall_depth * 0.39 * fracture
   setback += seam * fracture * 0.22 + 0.045 * _angular_wave(s * 1.9 + t * 8.0 + phase)
   setback = minf(setback, back_depth * 0.76)
   var y := t * crest + strata_dip * sin(s * 0.28 + phase) * sin(t * PI)
   var point := center - front * setback + Vector3.UP * y
   ring.append(point)
   var warm_cool := 0.5 + 0.5 * sin(s * 0.22 + phase + t * 2.1)
   var pigment := stone_color * lerpf(0.90, 1.09, warm_cool)
   pigment = pigment.lerp(pigment * Color(0.84, 0.93, 1.10), (1.0 - warm_cool) * 0.23)
   pigment.a = clampf(1.0 - incision * 0.22 - seam * 0.09 - (1.0 - smoothstep(0.0, 0.16, t)) * 0.20, 0.55, 1.0)
   colors.append(pigment)
   uvs.append(Vector2(s, y))
  crests.append(ring[-1])
  # Shallow pitched, uneven roof continues into the back without separate rocks.
  var front_top_depth: float = -(ring[-1] - center).dot(front)
  ring.append(center - front * lerpf(front_top_depth, back_depth, 0.52) + Vector3.UP * (crest + 0.09 * sin(s * 1.02 + phase)))
  ring.append(center - front * back_depth + Vector3.UP * (crest * 0.87))
  ring.append(center - front * back_depth)
  for extra in 3:
   colors.append(stone_color * (1.05 if extra == 0 else 0.96))
   uvs.append(Vector2(s, ring[front_vertex_count + extra].y))
  rings.append(ring)
  vertices.append_array(ring)

 var indices := PackedInt32Array()
 for i in range(stations.size() - 1):
  for j in ring_size:
   # The terrain takes over the exact roof edge; drawing both coplanar surfaces
   # would cause z-fighting and duplicate collision triangles on the ridge.
   if raised_zone_enabled and j in [front_vertex_count - 1, front_vertex_count]: continue
   if layered_rock_wall and j<front_vertex_count-2: continue
   var j_next := (j + 1) % ring_size
   var a := i * ring_size + j
   var b := (i + 1) * ring_size + j
   var c := (i + 1) * ring_size + j_next
   var d := i * ring_size + j_next
   indices.append_array(PackedInt32Array([a, c, b, a, d, c]))
 # Triangulate the possibly concave cross-sections, never fill fissures with a
 # convex collider. The same exact faces are used for visual and static collision.
 for end in [0, stations.size() - 1]:
  var frame := _frame(stations[end], length_value)
  var polygon := PackedVector2Array()
  for point in rings[end]:
   polygon.append(Vector2(-(point - frame.center).dot(frame.front), point.y))
  var cap := Geometry2D.triangulate_polygon(polygon)
  if cap.is_empty(): return {"error": "Sezione degenerata: riduci profondità delle fratture o curvatura."}
  for k in range(0, cap.size(), 3):
   var a: int = end * ring_size + cap[k]
   var b: int = end * ring_size + cap[k + 1]
   var c: int = end * ring_size + cap[k + 2]
   if end == 0: indices.append_array(PackedInt32Array([a, b, c]))
   else: indices.append_array(PackedInt32Array([a, c, b]))

 if layered_rock_wall:
  _append_rock_wall(vertices,indices,colors,uvs,stations,crests,length_value)

 var corridor := _corridor(baked)
 if _invades_corridor(vertices, indices, corridor):
  return {"error": "La parete invade la fascia libera di 2 m su una curva stretta. Allarga la guida; nessuna modifica applicata."}
 var normals := PackedVector3Array()
 normals.resize(vertices.size())
 var faces := PackedVector3Array()
 for k in range(0, indices.size(), 3):
  var a: int = indices[k]
  var b: int = indices[k + 1]
  var c: int = indices[k + 2]
  var normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
  for index in [a, b, c]:
   normals[index] += normal
   faces.append(vertices[index])
 for i in normals.size(): normals[i] = normals[i].normalized()
 var arrays: Array = []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = vertices
 arrays[Mesh.ARRAY_NORMAL] = normals
 arrays[Mesh.ARRAY_COLOR] = colors
 arrays[Mesh.ARRAY_TEX_UV] = uvs
 arrays[Mesh.ARRAY_INDEX] = indices
 var mesh := ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
 var material := ShaderMaterial.new()
 material.shader = Masonry
 material.set_shader_parameter("anime_painted", painted)
 material.set_shader_parameter("stone_normal_flatten", 0.8)
 # Geological cuts are already real geometry. Shader-only chips would pull
 # the exact crest seam away from the adjoining terrain and its collision.
 material.set_shader_parameter("stone_chip_strength", 0.0)
 mesh.surface_set_material(0, material)
 var result := {"mesh": mesh, "vertices": vertices, "indices": indices, "faces": faces,
  "triangles": indices.size() / 3, "crests": crests, "corridor": corridor,
  "debris": _debris(length_value, corridor), "fissure_count": fissures.size()}
 if raised_zone_enabled:
  var sampler := ElevatedZone.new()
  var elevated: Dictionary = sampler.build(rings, stations, front_vertex_count, guide, wall_height, raised_zone_depth, effective_ramp_length(), access_ramp_base_height)
  if _invades_corridor(elevated.top_vertices, elevated.top_indices, corridor):
   return {"error": "Il terreno rialzato invade la fascia libera su una curva stretta. Allarga la guida o riduci la profondità."}
  result.elevated = elevated
 return result

func _append_rock_wall(vertices: PackedVector3Array,indices: PackedInt32Array,colors: PackedColorArray,uvs: PackedVector2Array,stations: Array[float],crests: PackedVector3Array,length_value: float) -> void:
 var rng := RandomNumberGenerator.new(); rng.seed=cliff_seed
 var start := 0.0; var piece := 0
 while start<length_value:
  var width := minf(wall_rock_size*rng.randf_range(0.8,1.25),length_value-start)
  var mesh := FracturedBoulder._solid(cliff_seed+piece*3571,stone_color,false,true)
  var arrays := mesh.surface_get_arrays(0)
  var source: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var tint: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
  var base := vertices.size()
  for i in source.size():
   var v := source[i]
   var distance_value := clampf(start+(v.x+0.5)*width*1.1-width*0.05,0,length_value)
   var frame := _frame(distance_value,length_value)
   var upper := 1
   while upper<stations.size()-1 and stations[upper]<distance_value: upper+=1
   var weight := inverse_lerp(stations[upper-1],stations[upper],distance_value)
   var crest := lerpf(crests[upper-1].y,crests[upper].y,weight)
   var depth := 0.18+(0.5-v.z)*wall_depth
   vertices.append(frame.center-frame.front*depth+Vector3.UP*(v.y*(crest+0.12)-0.12))
   colors.append(tint[i]); uvs.append(Vector2(distance_value,v.y*crest))
   indices.append(base+i)
  start+=width; piece+=1

func _frame(s: float, length_value: float) -> Dictionary:
 var p := guide.sample_baked(s)
 var direction := guide.sample_baked(minf(s + 0.075, length_value)) - guide.sample_baked(maxf(0.0, s - 0.075))
 direction.y = 0.0
 direction = direction.normalized()
 return {"center": p, "direction": direction, "front": Vector3(-direction.z, 0.0, direction.x)}

func _cut_at(s: float, t: float, fissures: Array[Vector3], phase: float) -> float:
 var depth := 0.0
 for cut in fissures:
  # A small drift makes the crack crooked without turning it into a sine ridge.
  var drift := sin(t * 4.0 + phase + cut.x) * cut.y * 0.52 * sin(t * PI)
  var proximity := absf(s - cut.x - drift) / cut.y
  var crack_start := lerpf(-0.18, 0.45, 0.5 + 0.5 * sin(cut.x * 1.71 + phase))
  var taper := smoothstep(crack_start, crack_start + 0.28, t)
  var notch := clampf(1.0 - proximity / 1.65, 0.0, 1.0)
  depth = maxf(depth, pow(notch, 0.75) * cut.z * taper)
 return depth

static func _angular_wave(value: float) -> float:
 return asin(sin(value)) * (2.0 / PI)

func _debris(length_value: float, corridor: Array[PackedVector2Array]) -> Array[Dictionary]:
 var output: Array[Dictionary] = []
 if not debris_enabled: return output
 var rng := RandomNumberGenerator.new()
 rng.seed = hash("cliff-foot:" + str(cliff_seed))
 for i in maxi(1, int(length_value / 3.8)):
  var s := rng.randf_range(0.15, length_value - 0.15)
  var frame := _frame(s, length_value)
  var size_value := rng.randf_range(0.18, 0.48)
  var dimensions := Vector3(size_value * 1.3, size_value * 0.60, size_value)
  var origin: Vector3 = frame.center - frame.front * (0.13 + size_value * 0.53)
  var basis := Basis(Vector3.UP, -atan2(frame.direction.z, frame.direction.x))
  var probe := Rock.new()
  probe.rock_seed = int(rng.randi())
  probe.dimensions = dimensions
  probe.strata = 1
  probe.fracture = 0.8
  var generated := probe.generate()
  var hull := PackedVector2Array()
  for point in generated.hull:
   var v: Vector3 = basis * point + origin
   hull.append(Vector2(v.x, v.z))
  var outline := Geometry2D.convex_hull(hull)
  var clear := true
  for ribbon in corridor:
   if not Geometry2D.intersect_polygons(outline, ribbon).is_empty(): clear = false; break
  if clear:
   output.append({"id": "FootFragment_%02d" % i, "seed": probe.rock_seed,
    "dimensions": dimensions, "transform": Transform3D(basis, origin)})
  probe.free()
 return output

static func _guide_crosses(points: PackedVector3Array) -> bool:
 for i in range(points.size() - 1):
  var a := Vector2(points[i].x, points[i].z)
  var b := Vector2(points[i + 1].x, points[i + 1].z)
  for j in range(i + 2, points.size() - 1):
   var c := Vector2(points[j].x, points[j].z)
   var d := Vector2(points[j + 1].x, points[j + 1].z)
   if Geometry2D.segment_intersects_segment(a, b, c, d) != null: return true
 return false

static func _corridor(points: PackedVector3Array) -> Array[PackedVector2Array]:
 var result: Array[PackedVector2Array] = []
 for i in range(points.size() - 1):
  var a := Vector2(points[i].x, points[i].z)
  var b := Vector2(points[i + 1].x, points[i + 1].z)
  if a.distance_to(b) < 0.001: continue
  var direction := (b - a).normalized()
  var front := Vector2(-direction.y, direction.x) * 2.0
  result.append(PackedVector2Array([a, b, b + front, a + front]))
 return result

static func _invades_corridor(vertices: PackedVector3Array, indices: PackedInt32Array, corridor: Array[PackedVector2Array]) -> bool:
 # Triangle projections also catch spans which cross a ribbon with all corners
 # outside it (a vertex-only clearance check misses concave guide intrusions).
 var bounds: Array[Rect2] = []
 for ribbon in corridor:
  var bound := Rect2(ribbon[0], Vector2.ZERO)
  for point in ribbon: bound = bound.expand(point)
  bounds.append(bound)
 for k in range(0, indices.size(), 3):
  var polygon := PackedVector2Array()
  for j in 3:
   var v := vertices[indices[k + j]]
   polygon.append(Vector2(v.x, v.z))
  if absf((polygon[1] - polygon[0]).cross(polygon[2] - polygon[0])) < 0.000001: continue
  var bound := Rect2(polygon[0], Vector2.ZERO).expand(polygon[1]).expand(polygon[2])
  for j in corridor.size():
   if bound.intersects(bounds[j]) and not Geometry2D.intersect_polygons(polygon, corridor[j]).is_empty(): return true
 return false

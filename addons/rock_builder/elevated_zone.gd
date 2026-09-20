@tool
extends RefCounted
## Upper terrain joined to the cliff crest, with a rear plateau and end ramp.
## A small triangle index makes exact height queries cheap for grass/trees.
const CELL := 2.0
var _height_cells := {}
var _top_vertices := PackedVector3Array()
var _top_indices := PackedInt32Array()

func build(rings: Array[PackedVector3Array], stations: Array[float], front_count: int,
 guide: Curve3D, height: float, depth: float, ramp_length: float, ramp_base: float) -> Dictionary:
 var rows: Array[PackedVector3Array] = []
 var length_value := guide.get_baked_length()
 var rear_steps := maxi(4, ceili(depth / 2.0))
 for row_index in rings.size():
  var source := rings[row_index]
  var row := PackedVector3Array([source[front_count - 1], source[front_count], source[front_count + 1]])
  var s := stations[row_index]
  var direction := guide.sample_baked(minf(s + 0.075, length_value)) - guide.sample_baked(maxf(0.0, s - 0.075))
  direction.y = 0.0
  direction = direction.normalized()
  var front := Vector3(-direction.z, 0.0, direction.x)
  var rim := source[front_count + 1]
  for j in range(1, rear_steps + 1):
   var distance_back := float(j) / rear_steps * depth
   var point := rim - front * distance_back
   point.y = lerpf(rim.y, height, smoothstep(0.0, minf(6.0, depth * 0.4), distance_back))
   row.append(point)
  rows.append(row)
 var terminal := rows[-1]
 var direction := guide.sample_baked(length_value) - guide.sample_baked(maxf(0.0, length_value - 0.1))
 direction.y = 0.0
 direction = direction.normalized()
 var ramp_steps := maxi(8, ceili(ramp_length))
 for i in range(1, ramp_steps + 1):
  var t := float(i) / ramp_steps
  var row := PackedVector3Array()
  for source in terminal:
   var point := source + direction * ramp_length * t
   point.y = lerpf(source.y, ramp_base, smoothstep(0.0, 1.0, t))
   row.append(point)
  rows.append(row)

 _top_vertices = PackedVector3Array()
 _top_indices = PackedInt32Array()
 _height_cells.clear()
 var columns := terminal.size()
 for row in rows: _top_vertices.append_array(row)
 for i in range(rows.size() - 1):
  for j in range(columns - 1):
   var a := i * columns + j
   var b := (i + 1) * columns + j
   var c := b + 1
   var d := a + 1
   _top_indices.append_array(PackedInt32Array([a, c, b, a, d, c]))
 var top_faces := PackedVector3Array()
 for i in _top_indices: top_faces.append(_top_vertices[i])
 _index_heights()
 var skirt_faces := PackedVector3Array()
 # Existing geological mesh already closes the main front and the initial roof
 # side. Avoid a flat skirt filling in its real fissures or coplanar end faces.
 for j in range(2, columns - 1): _wall(skirt_faces, rows[0][j], rows[0][j + 1])
 for i in range(rows.size() - 1): _wall(skirt_faces, rows[i][-1], rows[i + 1][-1])
 for j in range(columns - 1, 0, -1): _wall(skirt_faces, rows[-1][j], rows[-1][j - 1])
 for i in range(rows.size() - 1, rings.size() - 1, -1): _wall(skirt_faces, rows[i][0], rows[i - 1][0])
 var collision_faces := top_faces.duplicate()
 collision_faces.append_array(skirt_faces)
 var top_mesh := _surface(_top_vertices, _top_indices)
 var skirt_mesh := _faces_mesh(skirt_faces)
 return {"mesh": top_mesh, "skirt_mesh": skirt_mesh, "faces": collision_faces,
  "top_faces": top_faces, "top_vertices": _top_vertices, "top_indices": _top_indices,
  "rows": rows, "sampler": self, "ramp_start": length_value, "ramp_length": ramp_length}

func height_at_local(point: Vector2) -> float:
 var key := Vector2i(floori(point.x / CELL), floori(point.y / CELL))
 var result := NAN
 for triangle in _height_cells.get(key, []):
  var a: Vector3 = _top_vertices[_top_indices[triangle]]
  var b: Vector3 = _top_vertices[_top_indices[triangle + 1]]
  var c: Vector3 = _top_vertices[_top_indices[triangle + 2]]
  var av := Vector2(a.x, a.z)
  var v0 := Vector2(b.x - a.x, b.z - a.z)
  var v1 := Vector2(c.x - a.x, c.z - a.z)
  var v2 := point - av
  var determinant := v0.cross(v1)
  if absf(determinant) < 0.0000001: continue
  var u := v2.cross(v1) / determinant
  var v := v0.cross(v2) / determinant
  if u >= -0.00001 and v >= -0.00001 and u + v <= 1.00001:
   var y := a.y + u * (b.y - a.y) + v * (c.y - a.y)
   result = y if is_nan(result) else maxf(result, y)
 return result

func _index_heights() -> void:
 for triangle in range(0, _top_indices.size(), 3):
  var a := _top_vertices[_top_indices[triangle]]
  var bounds := Rect2(Vector2(a.x, a.z), Vector2.ZERO)
  for j in [1, 2]:
   var vertex := _top_vertices[_top_indices[triangle + j]]
   bounds = bounds.expand(Vector2(vertex.x, vertex.z))
  var first := Vector2i(floori(bounds.position.x / CELL), floori(bounds.position.y / CELL))
  var last := Vector2i(floori(bounds.end.x / CELL), floori(bounds.end.y / CELL))
  for x in range(first.x, last.x + 1):
   for z in range(first.y, last.y + 1):
    var key := Vector2i(x, z)
    if not _height_cells.has(key): _height_cells[key] = []
    _height_cells[key].append(triangle)

static func _wall(faces: PackedVector3Array, a: Vector3, b: Vector3) -> void:
 var bottom_a := Vector3(a.x, 0.0, a.z)
 var bottom_b := Vector3(b.x, 0.0, b.z)
 if a.y > 0.00001: faces.append_array(PackedVector3Array([a, bottom_a, bottom_b]))
 if b.y > 0.00001: faces.append_array(PackedVector3Array([a, bottom_b, b]))

static func _surface(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
 var normals := PackedVector3Array()
 normals.resize(vertices.size())
 var uvs := PackedVector2Array()
 var colors := PackedColorArray()
 for point in vertices:
  uvs.append(Vector2(point.x, point.z))
  colors.append(Color.WHITE)
 for i in range(0, indices.size(), 3):
  var a := indices[i]
  var b := indices[i + 1]
  var c := indices[i + 2]
  var normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
  for index in [a, b, c]: normals[index] += normal
 for i in normals.size(): normals[i] = normals[i].normalized()
 var arrays: Array = []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = vertices
 arrays[Mesh.ARRAY_NORMAL] = normals
 arrays[Mesh.ARRAY_TEX_UV] = uvs
 arrays[Mesh.ARRAY_COLOR] = colors
 arrays[Mesh.ARRAY_INDEX] = indices
 var mesh := ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
 return mesh

static func _faces_mesh(faces: PackedVector3Array) -> ArrayMesh:
 var indices := PackedInt32Array()
 for i in faces.size(): indices.append(i)
 return _surface(faces, indices)

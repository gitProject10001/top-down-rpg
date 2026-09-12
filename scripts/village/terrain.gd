@tool
class_name Terrain
extends MeshInstance3D
## Local authored relief, flat world outside. Generated mesh/collision are transient.
signal surface_changed
@export var world_plan: Resource
@export var height_edits: Array[Dictionary] = []
@export var reserved_zones: Array[Dictionary] = [{"position":Vector2.ZERO,"radius":140.0}]

func apply_zones(zones: Array[Dictionary]) -> void:
	reserved_zones = zones.duplicate(true)
	_schedule()

func generation_weight(p: Vector2) -> float:
	var weight := 1.0
	for zone in reserved_zones:
		weight = minf(weight,smoothstep(float(zone.radius),float(zone.radius)+32.0,p.distance_to(zone.position)))
	return weight

func apply_edits(edits: Array[Dictionary]) -> void:
	height_edits = edits.duplicate(true)
	_schedule()

func apply_plan(plan: Resource) -> void:
	world_plan = plan
	_schedule()

@export var extent := 1732.0508:
	set(value):
		extent = maxf(value, 256.0)
		_schedule()
@export var floor_thickness := 1.0 # Retained for scene compatibility.
@export var plateau_center := Vector2(60, -60):
	set(value):
		plateau_center = value
		_schedule()
@export_range(0, 15, 0.25) var plateau_height := 6.0:
	set(value):
		plateau_height = value
		_schedule()
@export_range(12, 35, 1) var plateau_radius := 22.0:
	set(value):
		plateau_radius = value
		_schedule()
var _scheduled := false
var _cliff_triangles := 0
var lod_counts: Array[int] = []

func _with_lods(source: ArrayMesh) -> ArrayMesh:
	var importer := ImporterMesh.new()
	for i in range(source.get_surface_count()):
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(i),[],{},source.surface_get_material(i))
	importer.generate_lods(25.0,60.0,[])
	for i in range(source.get_surface_count()): lod_counts.append(importer.get_surface_lod_count(i))
	return importer.get_mesh()

func _ready() -> void:
	_schedule()

func _schedule() -> void:
	if not is_inside_tree() or _scheduled: return
	_scheduled = true
	call_deferred("_rebuild")

func height_at(x: float, z: float) -> float:
	var limit := extent*0.5-64.0
	var p := Vector2(x,z)-plateau_center.clamp(Vector2.ONE*(-limit),Vector2.ONE*limit)
	var edge := plateau_radius + sin(p.y*0.47)*0.65 + sin(p.x*0.61)*0.45
	var top := 1.0-smoothstep(edge-2.0,edge,maxf(absf(p.x),absf(p.y)))
	# South-facing access ramp: gentle grade, flanked by steep banks.
	var ramp := (1.0-smoothstep(5.0,8.0,absf(p.x))) * (1.0-smoothstep(plateau_radius-7.0,plateau_radius+26.0,p.y))
	if p.y < 0: ramp = 0
	var height := plateau_height*maxf(top,ramp)
	if world_plan: height += world_plan.elevation(Vector2(x,z))*generation_weight(Vector2(x,z))
	for edit in height_edits:
		var weight := 1.0-smoothstep(0.0,float(edit.radius),Vector2(x,z).distance_to(edit.position))
		if edit.kind == "flatten": height = lerpf(height,float(edit.value),weight)
		else: height += float(edit.value)*weight
	return height

func ray_surface(origin: Vector3, direction: Vector3) -> Vector3:
	# Height-field intersection also works when editor physics is not running.
	var previous := 0.0
	for i in range(1,3001):
		var distance := float(i)*2.0
		var p := origin+direction*distance
		if p.y <= height_at(p.x,p.z):
			var low := previous
			var high := distance
			for j in range(14):
				var mid := (low+high)*0.5
				var q := origin+direction*mid
				if q.y > height_at(q.x,q.z): low = mid
				else: high = mid
			return origin+direction*((low+high)*0.5)
		previous = distance
	return Vector3.INF

func _rebuild() -> void:
	_scheduled = false
	lod_counts.clear()
	_cliff_triangles = 0
	var grass := SurfaceTool.new()
	var cliff := SurfaceTool.new()
	grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := extent*0.5
	var c := plateau_center.clamp(Vector2.ONE*(-half+64),Vector2.ONE*(half-64))
	# Four flat rectangles around a 128 m detail patch. No overlapping floor.
	_grid(grass,cliff,Vector2(-half,-half),Vector2(c.x-64,half))
	_grid(grass,cliff,Vector2(c.x+64,-half),Vector2(half,half))
	_grid(grass,cliff,Vector2(c.x-64,-half),Vector2(c.x+64,c.y-64))
	_grid(grass,cliff,Vector2(c.x-64,c.y+64),Vector2(c.x+64,half))
	for x in range(128):
		for z in range(128):
			var p := c-Vector2.ONE*64+Vector2(x,z)
			_quad(grass,cliff,p,p+Vector2.ONE)
	grass.generate_normals()
	grass.index()
	var result := grass.commit()
	if _cliff_triangles > 0:
		cliff.generate_normals()
		cliff.index()
		cliff.commit(result)
		var stone := StandardMaterial3D.new()
		stone.vertex_color_use_as_albedo = true
		stone.albedo_color = Color(0.45,0.42,0.32)
		stone.metallic_specular = 0.0
		stone.roughness = 1.0
		result.surface_set_material(1,stone)
	mesh = _with_lods(result)
	var collider := get_node("Collision/Shape") as CollisionShape3D
	collider.position = Vector3.ZERO
	collider.shape = mesh.create_trimesh_shape()
	var old := get_node_or_null("CliffRocks")
	if old:
		remove_child(old)
		old.queue_free()
	if plateau_height > 0.3:
		var rocks := MeshInstance3D.new()
		rocks.name = "CliffRocks"
		rocks.mesh = _with_lods(preload("res://scripts/village/cliff_rocks.gd").build(self))
		add_child(rocks)
	surface_changed.emit()

func _grid(grass: SurfaceTool, cliff: SurfaceTool, a: Vector2, b: Vector2) -> void:
	# Broad world relief: 8 m sampling. Local village plateau retains 1 m detail.
	var nx := ceili((b.x-a.x)/8.0)
	var nz := ceili((b.y-a.y)/8.0)
	for x in range(nx):
		for z in range(nz):
			var p := a+Vector2(x,z)*8.0
			_quad(grass,cliff,p,(p+Vector2.ONE*8).min(b))

func _quad(grass: SurfaceTool, cliff: SurfaceTool, a: Vector2, b: Vector2) -> void:
	var p := Vector3(a.x,height_at(a.x,a.y),a.y)
	var q := Vector3(b.x,height_at(b.x,a.y),a.y)
	var r := Vector3(b.x,height_at(b.x,b.y),b.y)
	var s := Vector3(a.x,height_at(a.x,b.y),b.y)
	_triangle(grass,cliff,p,q,r)
	_triangle(grass,cliff,p,r,s)

func _triangle(grass: SurfaceTool, cliff: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	var tool := cliff if normal.y < 0.65 else grass
	if tool == cliff: _cliff_triangles += 1
	for p in [a,b,c]:
		tool.set_color(Color(0.48,0.46,0.36) if tool == cliff else Color.WHITE)
		tool.set_uv(Vector2(p.x,p.z))
		tool.add_vertex(p)

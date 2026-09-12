@tool
extends Node3D
## Deterministic decoration streaming. Generated nodes are transient, never scene-owned.
const CELL := 64.0
const HALF_WORLD := 866.0254
@export var world_seed := 2417
@export_range(1, 4) var radius := 2
@export var editor_center := Vector2.ZERO
@export var preview_enabled := true
@export var follow_editor_camera := true
# Authored operations are scene data; temporary MultiMeshes are reconstructed from them.
@export var world_edits: Array[Dictionary] = []
@export_tool_button("Rebuild preview") var rebuild_action: Callable = rebuild
var _chunks: Dictionary = {}
var _queue: Array[Vector2i] = []
var _center := Vector2i(99999, 99999)
var _settings := Vector2i(-1,-1)
var _noise := FastNoiseLite.new()
var _trunk: MeshInstance3D
var _crown: MeshInstance3D
var _rock := SphereMesh.new()
var _rock_material := StandardMaterial3D.new()

func _ready() -> void:
	var ground := get_node("../Ground")
	ground.surface_changed.connect(rebuild)
	_noise.seed = world_seed
	_noise.frequency = 0.015
	var forest := get_node("../Camp/PaintedForest")
	_trunk = forest.get_node("painted_oak/PaintedTrunk_001")
	_crown = forest.get_node("IllustratedCrown")
	_rock.radial_segments = 7
	_rock.rings = 3
	_rock.radius = 0.8
	_rock.height = 1.3
	_rock_material.albedo_color = Color(0.36, 0.34, 0.28)
	_rock_material.roughness = 1.0
	set_process(true)

func rebuild() -> void:
	for chunk in _chunks.values():
		chunk.queue_free()
	_chunks.clear()
	_queue.clear()
	_center = Vector2i(99999, 99999)
	_noise.seed = world_seed

func apply_edits(value: Array[Dictionary]) -> void:
	world_edits = value.duplicate(true)
	rebuild()

func _process(_delta: float) -> void:
	if not is_instance_valid(_trunk): return
	if _settings != Vector2i(world_seed,radius):
		_settings = Vector2i(world_seed,radius)
		rebuild()
	if Engine.is_editor_hint() and not preview_enabled:
		if not _chunks.is_empty(): rebuild()
		return
	var focus := editor_center
	if not Engine.is_editor_hint():
		var player := get_node_or_null("../Player") as Node3D
		if player: focus = Vector2(player.position.x, player.position.z)
	var cell := Vector2i(floori(focus.x / CELL), floori(focus.y / CELL))
	if cell != _center:
		_center = cell
		_queue.clear()
		for key: Vector2i in _chunks.keys():
			if absi(key.x-cell.x) > radius+1 or absi(key.y-cell.y) > radius+1:
				_chunks[key].queue_free()
				_chunks.erase(key)
		for x in range(cell.x-radius, cell.x+radius+1):
			for z in range(cell.y-radius, cell.y+radius+1):
				var key := Vector2i(x,z)
				if not _chunks.has(key) and absf((x+0.5)*CELL) < HALF_WORLD+CELL/2 and absf((z+0.5)*CELL) < HALF_WORLD+CELL/2:
					_queue.append(key)
		_queue.sort_custom(func(a: Vector2i,b: Vector2i): return a.distance_squared_to(cell) < b.distance_squared_to(cell))
	# One bounded cell per frame; no whole-world rebuild on player motion.
	if not _queue.is_empty(): _build(_queue.pop_front())

static func trail_x(z: float) -> float:
	return 18.0*sin(z/95.0) + 9.0*sin(z/37.0)

func _build(key: Vector2i) -> void:
	var chunk := Node3D.new()
	chunk.name = "Cell_%d_%d" % [key.x,key.y]
	chunk.position = Vector3(key.x*CELL,0,key.y*CELL)
	add_child(chunk)
	_chunks[key] = chunk
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x,key.y,world_seed))
	var trees: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var body := StaticBody3D.new()
	chunk.add_child(body)
	# Jittered 8 m cells enforce breathing room, noise creates groves and clearings.
	for ix in range(8):
		for iz in range(8):
			var local := Vector3(ix*8.0+rng.randf_range(2,6),0,iz*8.0+rng.randf_range(2,6))
			var p := local + chunk.position
			local.y = get_node("../Ground").height_at(p.x,p.z)
			var ground := get_node("../Ground")
			if absf(ground.height_at(p.x+1,p.z)-local.y)>0.7 or absf(ground.height_at(p.x,p.z+1)-local.y)>0.7: continue
			if absf(p.x)>HALF_WORLD-3 or absf(p.z)>HALF_WORLD-3 or Vector2(p.x,p.z).length()<32: continue
			if absf(p.x-trail_x(p.z))<5 or absf(p.z-0.35*p.x-90.0)<4: continue
			var route := get_node_or_null("../ExplorationRoute")
			if route and route.excludes(Vector2(p.x,p.z)): continue
			var density := smoothstep(25,100,absf(p.z)) * smoothstep(-0.35,0.35,_noise.get_noise_2d(p.x,p.z))
			if ground.world_plan:
				if ground.generation_weight(Vector2(p.x,p.z))<=0.0: continue
				density *= ground.world_plan.forest_density(Vector2(p.x,p.z))
			if route and route.distance_to_path(Vector2(p.x,p.z))<18:
				density = maxf(density,0.82)
			var scale_value := rng.randf_range(0.75,1.3)
			if rng.randf() < density*0.85:
				trees.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_value),local))
			elif rng.randf()<0.08:
				var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(scale_value,scale_value*0.65,scale_value*1.3))
				rocks.append(Transform3D(basis,local+Vector3.UP*0.25))
	# Ordered operations allow erase then repaint, across cell boundaries.
	for edit in world_edits:
		var point: Vector3 = edit.position
		if edit.kind == "erase":
			var r: float = edit.radius
			for i in range(trees.size()-1,-1,-1):
				var offset := trees[i].origin+chunk.position-point
				if Vector2(offset.x,offset.z).length() <= r: trees.remove_at(i)
		elif Vector2i(floori(point.x/CELL),floori(point.z/CELL)) == key:
			point.y = get_node("../Ground").height_at(point.x,point.z)
			trees.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*float(edit.scale)),point-chunk.position))
	for tree in trees:
		var shape := CylinderShape3D.new()
		shape.radius = 0.4*tree.basis.get_scale().x
		shape.height = 3.5*tree.basis.get_scale().y
		_collider(body,shape,tree.origin+Vector3.UP*shape.height/2)
	for rock in rocks:
		var shape := SphereShape3D.new()
		shape.radius = 0.7*rock.basis.get_scale().x
		_collider(body,shape,rock.origin)
	var trunk_transform: Transform3D = _trunk.get_parent().transform * _trunk.transform
	trunk_transform.origin = Vector3.ZERO
	var crown_transform := _crown.transform
	crown_transform.origin.x = 0
	crown_transform.origin.z = 0
	_batch(chunk,_trunk.mesh,_trunk.material_override,trees,trunk_transform,_trunk)
	_batch(chunk,_crown.mesh,_crown.material_override,trees,crown_transform)
	_batch(chunk,_rock,_rock_material,rocks,Transform3D.IDENTITY)

func _collider(parent: Node, shape: Shape3D, pos: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = pos
	parent.add_child(collider)

func _batch(parent: Node, mesh: Mesh, material: Material, transforms: Array[Transform3D], offset: Transform3D, source: MeshInstance3D = null) -> void:
	if transforms.is_empty(): return
	var instance := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	if source:
		mesh = mesh.duplicate()
		for surface in range(mesh.get_surface_count()):
			var override := source.get_surface_override_material(surface)
			if override: mesh.surface_set_material(surface,override)
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()): mm.set_instance_transform(i,transforms[i]*offset)
	instance.multimesh = mm
	instance.material_override = material
	parent.add_child(instance)

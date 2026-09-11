extends Node3D
## SCATTERS THE SMALL STUFF -- grass tufts, pebbles, fallen twigs -- across the camp floor.
##
## WHY THIS MATTERS MORE THAN IT SOUNDS. Put the reference art next to a render of this scene and the
## single loudest difference, after colour, is DENSITY. The reference floor is never empty: between
## any two props there are tufts, stones, sticks, leaves. Ours had six hand-placed tufts on forty
## square metres of mud, and a large empty surface reads as a 3D groundplane no matter how good the
## material on it is. Detail at this scale is not decoration; it is the thing that stops the eye
## finding the polygon.
##
## ONE MultiMesh PER KIND, so eight hundred objects cost three draw calls. At this size none of them
## needs a collider, a script or a shadow of its own.
##
## THE EXCLUSIONS ARE DERIVED, NOT AUTHORED. The obvious way to keep grass out of the chapel is a
## hand-written list of rectangles, and that list is wrong the first time anyone drags a tent. So
## instead this walks whatever is under `avoid_root` at startup, takes the world AABB of every mesh
## big enough to matter, and refuses to plant inside it. Move a building in the editor and the grass
## moves out of its way with no further work.
##
## DETERMINISTIC: same seed, same camp, same scatter every run. A look-dev scene that reshuffles its
## ground每 launch cannot be compared against yesterday.

@export_group("What to scatter")
@export var grass_mesh: PackedScene
@export var stone_mesh: PackedScene
@export var twig_mesh: PackedScene
## The MultiMesh takes a material_override rather than the flat colour the .glb imported with --
## same reason camp_skin.gd exists, just without needing to match by name for three known meshes.
@export var grass_material: Material
@export var stone_material: Material
@export var twig_material: Material
@export var grass_count := 520
@export var stone_count := 190
@export var twig_count := 110

@export_group("Where")
## Half-extent of the scattered square, in metres, centred on this node.
@export var extent := 17.0
## Everything under here is treated as an obstacle to plant around.
@export var avoid_root: NodePath
## Grown outward from each obstacle AABB, so nothing sprouts flush against a wall.
@export var avoid_margin := 0.35
## Meshes smaller than this in either horizontal axis are ignored as obstacles -- a bucket should
## not clear a metre of grass around itself.
@export var avoid_min_size := 0.6
@export var rng_seed := 20260908

@export_group("Look")
@export var grass_scale := Vector2(0.75, 1.5)
@export var stone_scale := Vector2(0.6, 1.4)
@export var twig_scale := Vector2(0.7, 1.3)
## Sink into the mud, in metres. The ground shader displaces the plane downward, so anything sitting
## exactly on y = 0 floats over the hollows; a little sink hides that everywhere it matters.
@export var sink := 0.06

var _blocked: Array[Rect2] = []


func _ready() -> void:
	_collect_obstacles()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	_scatter("Grass", grass_mesh, grass_count, grass_scale, rng, true, grass_material)
	_scatter("Stones", stone_mesh, stone_count, stone_scale, rng, false, stone_material)
	_scatter("Twigs", twig_mesh, twig_count, twig_scale, rng, false, twig_material)


func _collect_obstacles() -> void:
	var root := get_node_or_null(avoid_root)
	if root == null:
		return
	for node in _meshes(root):
		var aabb := node.get_aabb()
		# Corners through the node transform, because the camp is rotated 45 degrees and an
		# untransformed AABB would be turned the wrong way against the world grid.
		var xf := node.global_transform
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in 8:
			var corner := xf * (aabb.position + Vector3(
				aabb.size.x * float(i & 1),
				aabb.size.y * float((i >> 1) & 1),
				aabb.size.z * float((i >> 2) & 1)))
			lo = Vector2(minf(lo.x, corner.x), minf(lo.y, corner.z))
			hi = Vector2(maxf(hi.x, corner.x), maxf(hi.y, corner.z))
		var size := hi - lo
		if size.x < avoid_min_size and size.y < avoid_min_size:
			continue
		_blocked.append(Rect2(lo, size).grow(avoid_margin))


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _scatter(label: String, scene: PackedScene, count: int, scale_range: Vector2,
		rng: RandomNumberGenerator, upright: bool, material: Material) -> void:
	if scene == null or count <= 0:
		return
	var mesh := _first_mesh(scene)
	if mesh == null:
		push_warning("[SCATTER] %s: no mesh found in %s" % [label, scene.resource_path])
		return

	var transforms: Array[Transform3D] = []
	# Rejection sampling with a hard attempt cap: with a busy camp the obstacle rects can cover
	# enough of the square that a naive while-loop would never finish.
	var attempts := 0
	while transforms.size() < count and attempts < count * 12:
		attempts += 1
		var p := Vector3(rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))
		p += global_position
		if _is_blocked(Vector2(p.x, p.z)):
			continue
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		if not upright:
			# Stones and sticks lie however they fell; grass grows up.
			basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
			basis = basis * Basis(Vector3.FORWARD, rng.randf_range(-0.25, 0.25))
		transforms.append(Transform3D(basis.scaled(Vector3(s, s, s)),
				Vector3(p.x, -sink, p.z)))

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])

	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multi
	# A tuft casting a shadow map entry buys nothing and eight hundred of them cost real time.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material != null:
		node.material_override = material
	add_child(node)


func _is_blocked(xz: Vector2) -> bool:
	for rect in _blocked:
		if rect.has_point(xz):
			return true
	return false


## The first MeshInstance3D mesh inside an imported .glb scene, with its import transform baked in.
func _first_mesh(scene: PackedScene) -> Mesh:
	var inst := scene.instantiate()
	var found: Mesh = null
	for node in _meshes(inst):
		found = node.mesh
		break
	inst.queue_free()
	return found

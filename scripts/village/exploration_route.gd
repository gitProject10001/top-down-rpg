@tool
extends Node3D
## One authored exploration loop. Points are world XZ, saved in the scene.
signal discovered
@export var ground_path: NodePath=NodePath("../Ground")
@export var markers_enabled:=true
@export var points := PackedVector2Array([Vector2(-12,-30),Vector2(-27,-43),Vector2(-38,-62),Vector2(-48,-78),Vector2(-56,-95),Vector2(-73,-89),Vector2(-84,-65),Vector2(-67,-40),Vector2(-43,-27),Vector2(-12,-30)])
@export var clearing := Vector2(-56,-95)
@export var clearing_radius := 12.0
var _found := false
var _signature := 0
var _generated: Node3D

func _ready() -> void:
	get_node(ground_path).surface_changed.connect(_rebuild)

func distance_to_path(p: Vector2) -> float:
	var distance := INF
	for i in range(points.size()-1):
		distance = minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,points[i],points[i+1])))
	return distance

func excludes(p: Vector2) -> bool:
	return distance_to_path(p)<4.5 or p.distance_to(clearing)<clearing_radius

func _process(_delta: float) -> void:
	var signature := hash([points,clearing,clearing_radius])
	if signature != _signature:
		_signature = signature
		_rebuild()
	if Engine.is_editor_hint() or _found or not markers_enabled: return
	var player := get_node_or_null("../Player") as Node3D
	if player and Vector2(player.position.x,player.position.z).distance_to(clearing)<9:
		_found = true
		discovered.emit()
		var layer := CanvasLayer.new()
		add_child(layer)
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = "RADURA DELLE PIETRE ANTICHE"
		label.position = Vector2(24,50)
		label.add_theme_color_override("font_color",Color(0.92,0.85,0.63))
		label.add_theme_color_override("font_shadow_color",Color.BLACK)
		layer.add_child(label)
		var tween := create_tween()
		tween.tween_interval(3)
		tween.tween_property(label,"modulate:a",0.0,1.5)
		tween.tween_callback(layer.queue_free)

func _rebuild() -> void:
	var ground := get_node_or_null(ground_path) as MeshInstance3D
	if not ground: return
	var material := ground.material_override as ShaderMaterial
	if not material: material=ground.get_surface_override_material(0) as ShaderMaterial
	if not material: return
	var packed := PackedVector2Array()
	packed.resize(32)
	for i in range(mini(points.size(),32)): packed[i] = points[i]
	material.set_shader_parameter("exploration_points",packed)
	material.set_shader_parameter("exploration_count",mini(points.size(),32))
	material.set_shader_parameter("exploration_clearing",Vector3(clearing.x,clearing.y,clearing_radius))
	if is_instance_valid(_generated):
		remove_child(_generated)
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "RouteDetails"
	add_child(_generated)
	if not markers_enabled: return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4217
	var stone_builder := preload("res://scripts/village/cliff_rocks.gd")
	# Broken paving at intervals: a visual breadcrumb, not a continuous wall.
	for i in range(mini(4,points.size()-1)):
		var start := points[i]
		var end := points[i+1]
		var direction := (end-start).normalized()
		for step in range(0,int(start.distance_to(end)),6):
			var p := start+direction*step+direction.orthogonal()*rng.randf_range(-1.2,1.2)
			stone_builder._rock(st,rng,Vector3(p.x,ground.height_at(p.x,p.y)-0.06,p.y),Vector3(1.1,0.22,0.85),rng.randf()*TAU)
	# An open ruined enclosure. The walking loop passes through its empty centre.
	for i in range(16):
		var angle := i*TAU/16
		if i in [2,3,8,9,10]: continue
		var p := clearing+Vector2(cos(angle),sin(angle))*7.5
		var height := rng.randf_range(0.6,1.3)
		if i in [0,5,12]: height = 3.2
		stone_builder._rock(st,rng,Vector3(p.x,ground.height_at(p.x,p.y)+height*0.43,p.y),Vector3(1.6,height,1.5),angle)
	st.generate_normals()
	st.index()
	var mesh := st.commit()
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.albedo_color = Color(0.85,0.82,0.72)
	stone.roughness = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = stone
	_generated.add_child(instance)
	# Ruin only is collidable; the shallow paving is decoration.
	for i: int in [0,5,12]:
		var angle := i*TAU/16
		var p := clearing+Vector2(cos(angle),sin(angle))*7.5
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.4,3.2,1.4)
		shape.shape = box
		body.position = Vector3(p.x,ground.height_at(p.x,p.y)+1.6,p.y)
		body.add_child(shape)
		_generated.add_child(body)
	var stream := get_node_or_null("../WorldStream")
	if stream: stream.rebuild()

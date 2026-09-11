class_name GrassPatchBillboard
extends MultiMeshInstance3D
## BILLBOARD variant of GrassPatch (A/B experiment): each instance is a flat card with a
## procedurally drawn grass texture, kept upright and yaw-rotated toward the camera by
## shaders/grass_billboard.gdshader. Same scatter logic and exports as GrassPatch so the two
## can be toggled over the same lawn and compared honestly.

@export var region_size := Vector2(22.5, 13.8)
@export var count := 750
@export var rng_seed := 1
@export var card_size := Vector2(0.7, 0.5)      ## width x height of each grass card
@export var base_color := Color(0.17, 0.30, 0.11)
@export var tip_color := Color(0.38, 0.52, 0.21)
@export var color_variation := 0.12
@export var exclusion_rects: Array[Rect2] = []
@export var sway_strength := 0.06

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var quad := QuadMesh.new()
	quad.size = card_size
	quad.center_offset = Vector3(0, card_size.y * 0.5, 0)   # pivot at the card's bottom

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad

	var spots: Array[Vector2] = []
	for i in count:
		var p := Vector2(rng.randf_range(-region_size.x * 0.5, region_size.x * 0.5),
						 rng.randf_range(-region_size.y * 0.5, region_size.y * 0.5))
		var blocked := false
		for r in exclusion_rects:
			if r.has_point(p):
				blocked = true
				break
		if not blocked:
			spots.append(p)

	mm.instance_count = spots.size()
	for i in spots.size():
		var s := rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, rng.randf_range(0.75, 1.3), s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(spots[i].x, 0.0, spots[i].y)))
		var v := color_variation
		mm.set_instance_color(i, Color(1.0 + rng.randf_range(-v, v),
									   1.0 + rng.randf_range(-v, v) * 0.5,
									   1.0 + rng.randf_range(-v, v)))
	multimesh = mm

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass_billboard.gdshader")
	mat.set_shader_parameter("grass_tex", _make_grass_texture(rng))
	mat.set_shader_parameter("sway_strength", sway_strength)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Draw a little grass-clump texture: tapered blades, root->tip gradient, transparent elsewhere.
## Procedural so no hand-painted asset is needed for the experiment.
func _make_grass_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for b in 8:
		var base_x := rng.randf_range(14.0, S - 14.0)
		var tip_x := base_x + rng.randf_range(-22.0, 22.0)
		var height := rng.randf_range(0.55, 0.95) * (S - 8)
		var steps := int(height)
		for i in steps:
			var t := float(i) / float(steps)                       # 0 root -> 1 tip
			var y := (S - 1) - i
			var x := lerpf(base_x, tip_x, t * t)                   # blades bow outward
			var half := lerpf(4.0, 0.5, t)
			var col := base_color.lerp(tip_color, t)
			for dx in range(int(-half), int(half) + 1):
				var px := clampi(int(x) + dx, 0, S - 1)
				img.set_pixel(px, y, col)
	return ImageTexture.create_from_image(img)

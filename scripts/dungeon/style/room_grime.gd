@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomGrime
extends Object
## THE THING THAT HIDES THE MODULE GRID: patches of dirt and moss that are BIGGER than the modules
## they lie on, projected with Godot's Decal node.
##
## WHY A DECAL AND NOT MORE SHADER. The stone shader already samples in world space, so its grime is
## continuous across a seam — that solved the "two copies of the same wall look identical" half of
## repetition. It cannot solve the other half: a floor tile is a 4 m MESH whose brick layout is baked
## into its vertices, so the layout itself repeats on a 4 m lattice however the surface is shaded.
## Quarter-turning the tiles (RoomDresser.build) turns two tiles into eight, and this puts something
## on top that has no idea the lattice exists.
##
## A Decal projects albedo and normal onto every surface inside its box, across as many pieces as it
## overlaps, and its own edges are soft noise. One 5-7 m patch straddling four tiles leaves no
## straight line anywhere near a tile boundary, which is precisely what the eye was locking onto.
##
## WHY NOT PARALLAX OCCLUSION for this. POM fakes depth from a heightmap, and these bricks are real
## modelled geometry — 18,600 verts per wall, every brick a box with a real silhouette that really
## self-shadows. There is no missing relief for POM to add; it would be paying twice for what the
## mesh already has, and at grazing angles it would fight the actual geometry.
##
## COST. Decals are clustered in Forward+ alongside lights, so a handful per room is cheap, and they
## are skipped entirely past `distance_fade_begin`. They do NOT add geometry — for that (pebbles,
## grass in the joints) see RoomDebris.

## Patches per 100 m^2 of floor. A 20 x 12 room gets about seven.
const DENSITY := 3.0
const SIZE_MIN := 3.4
const SIZE_MAX := 7.2
## Projection depth. Tall enough to catch the floor and the foot of a wall it overlaps, short enough
## not to reach the wall's far face and print the patch on the outside too.
const DEPTH := 1.6

static var _albedo: Texture2D = null
static var _normal: Texture2D = null


## Scatter grime over a room's floor. Stable: keyed to the room's own stream, so a rebuild puts every
## patch back where it was.
static func scatter(room: Node3D, ctx: RoomContext, theme: DungeonTheme) -> void:
	if theme == null or theme.grime_density <= 0.0:
		return
	var area: float = ctx.footprint.x * ctx.footprint.z
	var count := int(round(area / 100.0 * theme.grime_density * DENSITY))
	if count <= 0:
		return
	var rng := ctx.stream("grime")
	var half_x: float = ctx.footprint.x * 0.5
	var half_z: float = ctx.footprint.z * 0.5
	for i in count:
		var d := Decal.new()
		d.texture_albedo = _albedo_texture()
		d.texture_normal = _normal_texture()
		var s := rng.randf_range(SIZE_MIN, SIZE_MAX)
		# Non-square and freely rotated, so the patch's own footprint never echoes the 4 m tile.
		d.size = Vector3(s, DEPTH, s * rng.randf_range(0.6, 1.0))
		d.albedo_mix = theme.grime_opacity
		d.normal_fade = 0.4
		d.modulate = theme.grime_color if rng.randf() > theme.grime_moss_share else theme.grime_moss
		d.upper_fade = 0.2
		d.lower_fade = 0.4
		d.cull_mask = 0xFFFFF
		d.distance_fade_enabled = true
		d.distance_fade_begin = 40.0
		d.distance_fade_length = 12.0
		room.add_child(d)
		d.position = Vector3(rng.randf_range(-half_x, half_x), 0.35,
				rng.randf_range(-half_z, half_z))
		d.rotation.y = rng.randf() * TAU


## One shared 256px patch, built once per run and reused by every decal in the dungeon.
##
## Radial falloff TIMES noise in the alpha: falloff alone gives a soft ellipse, which reads as a
## projected spotlight rather than as dirt. The noise is what makes the edge ragged, and ragged is
## the entire point — a straight edge anywhere near a module boundary is what this exists to avoid.
static func _albedo_texture() -> Texture2D:
	if _albedo != null:
		return _albedo
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.frequency = 0.022
	var size := 256
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var r: float = Vector2(x - c, y - c).length() / c
			var edge: float = clampf(1.0 - r, 0.0, 1.0)
			# smoothstep the falloff, then bite chunks out of it with the noise
			edge = edge * edge * (3.0 - 2.0 * edge)
			var v: float = n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a: float = clampf(edge * 1.5 - 0.45, 0.0, 1.0) * clampf(v * 1.6 - 0.25, 0.0, 1.0)
			# Albedo is WHITE and the colour comes from Decal.modulate, so one texture serves both
			# the dirt patches and the moss ones.
			var tone: float = 0.75 + v * 0.25
			img.set_pixel(x, y, Color(tone, tone, tone, a))
	_albedo = ImageTexture.create_from_image(img)
	return _albedo


## A gentle bump so a patch catches the torchlight instead of reading as a flat sticker.
static func _normal_texture() -> Texture2D:
	if _normal != null:
		return _normal
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	n.frequency = 0.05
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 3.0
	tex.noise = n
	_normal = tex
	return _normal

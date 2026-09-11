@tool
extends RefCounted
## THE GROUND THE WORLD STANDS ON — a Terrain3D grown from the same WorldMap the buildings were
## cut from, so the site and the site's terrain can never disagree.
##
## THE LAW IS THE PLATEAU. A generated city is written at y = 0 and its streets carry no floor
## of their own, so the terrain must be EXACTLY flat under the walls and only start to move
## outside them. Everything here is a function of the distance to the city's own outline: zero
## inside, a skirt that falls away, then mountains that rise with distance, and a lake dropped
## into a gap in the ring. Nothing is authored by hand and nothing is stored: the heightfield is
## a function of the map's seed and its outline, so it comes back the same every run — the
## project's law that randomness is keyed to WHERE, never to WHEN.
##
## Terrain3D is a GDExtension (addons/terrain_3d, MIT): if it is not installed this returns null
## and the zone falls back to its flat collider, which is what the world had before.

## Metres per terrain vertex. 2 m is the compromise this world wants: the city is flat anyway,
## and a mountain silhouette at 2 m reads at the camera's 15 m framing.
const VERTEX_M := 2.0
## Vertices per region side (a region is REGION * VERTEX_M metres across).
const REGION := 256
## THE LOD, which is the extension's own and not ours: a clipmap of MESH_LODS rings, each of
## MESH_SIZE vertices a side, centred on the camera it is given. Eight rings of 32 vertices at
## 2 m spacing reach past 8 km, which is what a site with a mountain backdrop needs, while the
## innermost ring stays dense under a camera framing 15 m. Both are set out loud because a
## packed scene comes back on whatever it was saved with — the same reason `stand_on` exists.
const MESH_LODS := 8
const MESH_SIZE := 32
## Where the extension keeps the region files it is never asked to write.
const RUNTIME_DIR := "user://terrain_runtime"


## Everything the shape of the ground is made of. All of it is derived from the map; the numbers
## are the ones a designer would turn.
class Profile extends RefCounted:
	var centre := Vector2.ZERO       ## the city's own centre, world XZ
	var radius := PackedFloat32Array()  ## the city outline's reach per degree (a star field)
	var skirt_m := 26.0              ## flat ground kept outside the walls (the approach)
	var ramp_m := 150.0              ## how far the mountains take to reach their height
	var mountain_m := 90.0           ## how high they get
	var roll_m := 3.0                ## the gentle roll of the ground near the town
	var lake_centre := Vector2.ZERO
	var lake_r := 0.0
	var lake_depth := 7.0
	var lake_shore_m := 26.0
	var water_y := -1.4
	## THE SEA, as a half-plane: everything with `p.dot(shore_n) > shore_d` is water. A radial
	## profile can put a lake in a ring of mountains and nothing else — an ocean is not a shape
	## about a centre, it is a side. ZERO = this world has no coast.
	var shore_n := Vector2.ZERO
	var shore_d := 0.0
	var shore_fall_m := 60.0         ## how far out the beach takes to reach the sea floor
	var sea_floor_m := 0.0           ## how deep it gets there
	## An island offshore: the lake primitive with its sign turned over.
	var island_centre := Vector2.ZERO
	var island_r := 0.0
	var island_h := 30.0
	var ridge_pow := 2.0             ## how sharply the ridgelines fold — higher is rockier
	var detail_m := 2.5              ## metres of roughness over the range
	var rock_colour := Color(0.44, 0.42, 0.40)
	var woods := false
	var noise: FastNoiseLite = null      ## the big masses
	var ridge: FastNoiseLite = null      ## the ridgelines over them
	var detail: FastNoiseLite = null     ## a couple of metres of roughness


## The terrain under a world, or null when the extension is not installed. With `save_dir` the
## regions are written there and the node keeps that directory, so the ground is GENERATED ONCE
## with the world and afterwards simply loaded — by the editor when the master scene is opened
## and by the game when it runs. Without it the terrain is grown in memory, which is what a
## hand-made zone with no world folder gets.
static func build(map: WorldMap, parent: Node3D, save_dir := "") -> Node3D:
	# A CARVED LEVEL HAS NO OUTSIDE. A crypt is rock and void; there is nothing for a ground to
	# be, nothing to see past the walls, and a terrain under it would only put a second opaque
	# plane at y = 0 for every floor slab's top face to fight with.
	if bool((map.site as Dictionary).get("carved", false)):
		return null
	if not ClassDB.class_exists("Terrain3D"):
		return null
	var prof := profile_of(map)
	var extent: float = maxf(map.bounds.size.x, map.bounds.size.y) * 0.5 + prof.ramp_m + prof.mountain_m * 1.6
	# A HEIGHTMAP MUST LAND ON THE REGION GRID. Terrain3D holds its ground in regions of
	# `region_size` vertices; an import that starts between two of them makes one region and
	# quietly puts the heights somewhere else (that is a nan under your feet). So the origin is
	# snapped down to a region corner and the image is a whole number of regions across.
	var region_m := float(REGION) * VERTEX_M
	var lo := prof.centre - Vector2(extent, extent)
	var hi := prof.centre + Vector2(extent, extent)
	var origin := Vector2(floorf(lo.x / region_m) * region_m, floorf(lo.y / region_m) * region_m)
	var cols := maxi(1, int(ceil((hi.x - origin.x) / region_m)))
	var rows := maxi(1, int(ceil((hi.y - origin.y) / region_m)))
	var w := cols * REGION
	var h_px := rows * REGION
	var img := Image.create(w, h_px, false, Image.FORMAT_RF)
	for y in h_px:
		var wz := origin.y + float(y) * VERTEX_M
		for x in w:
			var h := height_at(prof, Vector2(origin.x + float(x) * VERTEX_M, wz))
			img.set_pixel(x, y, Color(h, 0.0, 0.0, 1.0))
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain"
	# The extension looks for a data directory on the way up and complains about "res://" when it
	# has none; a world being written puts its regions in its own folder, beside its tiles.
	var dir := save_dir if save_dir != "" else RUNTIME_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	# A GROUND IS REGROWN WHOLE. Terrain3D LOADS whatever regions its data directory holds the
	# moment it enters a tree, so the leavings of an older, differently shaped world would be
	# loaded and then written back out beside the new ones.
	_empty(dir)
	terrain.set("data_directory", dir)
	terrain.set("region_size", REGION)
	terrain.set("vertex_spacing", VERTEX_M)
	terrain.set("mesh_lods", MESH_LODS)
	terrain.set("mesh_size", MESH_SIZE)
	terrain.set("cast_shadows", 1)            # On
	# the clipmap's own AABB is the FLAT ring, not the displaced height, so a peak at the edge
	# of the frustum is culled and pops in as you turn: grow the box by how tall the site gets
	terrain.set("cull_margin", maxf(prof.mountain_m, 64.0))
	# A Terrain3D brings its OWN material, assets and data the moment it is made: they are set
	# up here, not replaced, or the extension quietly keeps its own and the ground stays white.
	parent.add_child(terrain)
	var material: Object = terrain.get("material")
	if material != null:
		material.set("auto_shader", true)       # flat ground takes the first texture, slopes the second
		material.set("show_region_grid", false)
		material.set("show_vertex_grid", false)
		material.set("show_instancer_grid", false)
	_dress(terrain.get("assets"), prof.rock_colour)
	var data: Object = terrain.get("data")
	data.call("import_images", [img, null, null], Vector3(origin.x, 0.0, origin.y), 0.0, 1.0)
	data.call("calc_height_range", true)
	if save_dir != "":
		data.call("save_directory", save_dir)
	print("[Terrain] %d x %d regions of %.0f m, %d x %d vertices, heights %s%s" % [
			cols, rows, region_m, w, h_px, str(data.call("get_height_range")),
			(" -> " + save_dir) if save_dir != "" else ""])
	stand_on(terrain)
	if prof.lake_r > 0.0 or prof.shore_n != Vector2.ZERO:
		_water(parent, prof, extent)
	return terrain


## WHAT MAKES IT WALKABLE — and only ever AFTER the terrain is in a tree with its data
## imported: the extension's collision object is not there before that, and building it early
## takes the whole engine down with it. Terrain3D's default is DYNAMIC collision: shapes built around a
## camera it finds for itself, which is nothing at all in a scene with no camera yet — and a
## saved scene comes back on that default however it was packed, so a world loaded from disk had
## no ground under it and the player fell through the streets. FULL is the honest mode for a
## bounded site: every region gets its collision once, here, out loud.
static func stand_on(terrain: Node3D) -> void:
	if terrain == null:
		return
	terrain.set("collision_mode", 3)          # Full / Game
	var collision: Object = terrain.get("collision")
	if collision != null:
		collision.call("build")


## WHAT THE GROUND IS DETAILED AROUND. `set_camera` is a method, not a property, so it survives
## no packing and has to be said again every time a world is stood up — and until it is said the
## extension centres its clipmap on whatever camera it can find for itself, which in a scene
## that has not started yet is none. Returns whether it took: dynamic collision, if this project
## ever wants it, is only honest once this has.
static func follow(terrain: Node3D, cam: Camera3D) -> bool:
	if terrain == null or cam == null:
		return false
	terrain.call("set_camera", cam)
	return true


## The profile of one world: its city's outline as a radius per degree, and a lake dropped into
## the mountain ring on the side the castle does not watch.
static func profile_of(map: WorldMap) -> Profile:
	var prof := Profile.new()
	var outline := city_outline(map)
	prof.centre = _centroid(outline)
	prof.radius = PackedFloat32Array()
	prof.radius.resize(360)
	for i in 360:
		prof.radius[i] = 0.0
	# the reach of the outline per degree: a faceted ring is star-shaped about its centre, so
	# one number per degree describes it exactly enough to shape the ground around it
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var steps := maxi(2, int((b - a).length() / 2.0))
		for s in steps + 1:
			var p: Vector2 = a.lerp(b, float(s) / float(steps))
			var v := p - prof.centre
			var deg := int(fposmod(rad_to_deg(v.angle()), 360.0))
			prof.radius[deg] = maxf(prof.radius[deg], v.length())
	# a degree the sampling missed takes its neighbour's reach
	for pass_i in 2:
		for i in 360:
			if prof.radius[i] <= 0.0:
				prof.radius[i] = maxf(prof.radius[(i + 359) % 360], prof.radius[(i + 1) % 360])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|terrain|%d" % [map.name, map.seed])
	var reach := 0.0
	for r in prof.radius:
		reach = maxf(reach, r)
	# the lake: outside the walls, in the mountains' ring, on a side the seed chooses
	var a_deg := rng.randi_range(0, 359)
	prof.lake_r = clampf(reach * rng.randf_range(0.34, 0.5), 45.0, 190.0)
	var away := reach + prof.skirt_m + prof.lake_r * 0.9
	prof.lake_centre = prof.centre + Vector2.RIGHT.rotated(deg_to_rad(float(a_deg))) * away
	prof.mountain_m = rng.randf_range(70.0, 120.0)
	prof.ramp_m = rng.randf_range(130.0, 190.0)
	# THE SITE IS AUTHORED, the rest is derived. Everything above is what a world with nothing
	# said about it gets; a map that named a shore, an island or a rockier range overrides it
	# here, and nothing below has to know which of the two it is looking at.
	var site: Dictionary = map.site
	if site.has("shore_n"):
		prof.shore_n = site.shore_n
		prof.shore_d = float(site.get("shore_d", 0.0))
		prof.shore_fall_m = float(site.get("shore_fall_m", reach * 0.55))
		prof.sea_floor_m = float(site.get("sea_floor_m", 16.0))
		prof.water_y = float(site.get("water_y", -0.6))
		prof.lake_r = 0.0                  # a world has one body of water, and the sea is it
	if site.has("island_r"):
		prof.island_centre = site.get("island_centre", Vector2.ZERO)
		prof.island_r = float(site.get("island_r", 0.0))
		prof.island_h = float(site.get("island_h", 30.0))
	prof.mountain_m = float(site.get("mountain_m", prof.mountain_m))
	prof.ramp_m = float(site.get("ramp_m", prof.ramp_m))
	prof.ridge_pow = float(site.get("ridge_pow", prof.ridge_pow))
	prof.detail_m = float(site.get("detail_m", prof.detail_m))
	prof.rock_colour = site.get("rock_colour", prof.rock_colour)
	prof.woods = bool(site.get("woods", false))
	# THE SCALE OF A MOUNTAIN IS THE FREQUENCY. A range is a few masses hundreds of metres
	# across with ridgelines over them, not a field of spikes: the shape noise has a period of
	# ~700 m, the ridges ~250 m, and the detail is a couple of metres of roughness.
	var n := FastNoiseLite.new()
	n.seed = int(map.seed)
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.0014
	n.fractal_octaves = 3
	n.fractal_gain = 0.45
	prof.noise = n
	var r2 := FastNoiseLite.new()
	r2.seed = int(map.seed) + 977
	r2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	r2.frequency = 0.004
	r2.fractal_octaves = 3
	r2.fractal_gain = 0.4
	prof.ridge = r2
	var d := FastNoiseLite.new()
	d.seed = int(map.seed) + 1553
	d.noise_type = FastNoiseLite.TYPE_SIMPLEX
	d.frequency = 0.022
	d.fractal_octaves = 2
	prof.detail = d
	return prof


## THE HEIGHT AT A POINT. Flat under the town, a skirt, then mountains — and a lake cut through
## whatever the mountains were doing there.
static func height_at(prof: Profile, p: Vector2) -> float:
	var v := p - prof.centre
	var deg := int(fposmod(rad_to_deg(v.angle()), 360.0))
	var d := v.length() - prof.radius[deg]         # metres outside the city outline
	var h := 0.0
	if d > 0.0:
		# the ground rolls gently as soon as it leaves the walls, and climbs after the skirt
		var roll: float = prof.noise.get_noise_2d(p.x, p.y) * prof.roll_m
		h = roll * clampf(d / prof.skirt_m, 0.0, 1.0)
		var t := clampf((d - prof.skirt_m) / prof.ramp_m, 0.0, 1.0)
		if t > 0.0:
			var reach := smoothstep(0.0, 1.0, t) * prof.mountain_m
			# the mass: where the range stands at all, and how high it gets there
			var mass: float = 0.45 + 0.55 * clampf(prof.noise.get_noise_2d(p.x, p.y) * 1.6 + 0.35, 0.0, 1.0)
			# the ridgeline: the fold of |noise| is what makes a range read as rock
			var ridge: float = 1.0 - absf(prof.ridge.get_noise_2d(p.x, p.y))
			h += reach * mass * (0.55 + 0.45 * pow(ridge, prof.ridge_pow))
			h += prof.detail.get_noise_2d(p.x, p.y) * prof.detail_m * t
	if prof.lake_r > 0.0:
		# the lake wins wherever it lies: a basin with a shore, and no mountain inside it
		var wobble: float = prof.ridge.get_noise_2d(p.x * 0.7, p.y * 0.7) * prof.lake_r * 0.18
		var into := prof.lake_r + wobble - (p - prof.lake_centre).length()
		if into > -prof.lake_shore_m:
			var k := smoothstep(-prof.lake_shore_m, prof.lake_r * 0.35, into)
			h = lerpf(h, -prof.lake_depth, k)
	if prof.shore_n != Vector2.ZERO:
		# THE SEA WINS EVERYTHING SEAWARD OF IT, mountains included. `s` is metres past the
		# shoreline, so the blend starts at exactly 0 and the plateau under the town — which is
		# landward of it by the quay's width — is not touched at all: the flatness the walls
		# stand on is the same law it was before there was any water.
		var s := p.dot(prof.shore_n) - prof.shore_d
		if s > 0.0:
			h = lerpf(h, -prof.sea_floor_m, smoothstep(0.0, prof.shore_fall_m, s))
			var shelf: float = prof.detail.get_noise_2d(p.x * 0.5, p.y * 0.5) * 1.5
			h += shelf * clampf(s / prof.shore_fall_m, 0.0, 1.0)
	if prof.island_r > 0.0:
		# the island: the lake, inverted — a cone of rock standing out of the water rather than a
		# basin cut into the land, and wobbled by the same noise so it is not a dome
		var wob: float = prof.ridge.get_noise_2d(p.x * 0.9, p.y * 0.9) * prof.island_r * 0.22
		var up := prof.island_r + wob - (p - prof.island_centre).length()
		if up > 0.0:
			var k := smoothstep(0.0, prof.island_r * 0.8, up)
			h = maxf(h, lerpf(-prof.sea_floor_m, prof.island_h, k))
	return h


## The city's own outline in world metres: the root cell of the first zone, grown past its
## curtain so the walls stand on flat ground too.
static func city_outline(map: WorldMap) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for c: Dictionary in map.cells:
		if int(c.get("parent", -1)) == -1:
			poly = c.polygon
			break
	if poly.size() < 3:
		var b: Rect2 = map.bounds
		return PackedVector2Array([b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)])
	var grown: Array = Geometry2D.offset_polygon(poly, 18.0)
	if grown.is_empty():
		return poly
	var best: PackedVector2Array = grown[0]
	for g: PackedVector2Array in grown:
		if g.size() > best.size():
			best = g
	return best


## TWO GROUND COLOURS, and no texture files: a Terrain3DTextureAsset carries an albedo colour of
## its own, and the auto shader blends the first (the turf of the valley) into the second (the
## rock of the slopes) by how steep the ground is. Real textures drop into the same two slots.
static func _dress(assets: Object, rock_colour := Color(0.44, 0.42, 0.40)) -> void:
	if assets == null:
		return
	var turf: Object = ClassDB.instantiate("Terrain3DTextureAsset")
	turf.set("name", "turf")
	turf.set("id", 0)
	turf.set("albedo_texture", _ground_texture(Color(0.38, 0.44, 0.27), 0.05, 11))
	turf.set("albedo_color", Color(1, 1, 1))
	turf.set("roughness", 0.92)
	turf.set("uv_scale", 0.08)
	var rock: Object = ClassDB.instantiate("Terrain3DTextureAsset")
	rock.set("name", "rock")
	rock.set("id", 1)
	rock.set("albedo_texture", _ground_texture(rock_colour, 0.07, 29))
	rock.set("albedo_color", Color(1, 1, 1))
	rock.set("roughness", 0.96)
	rock.set("uv_scale", 0.06)
	assets.call("set_texture", 0, turf)
	assets.call("set_texture", 1, rock)


## A GROUND TEXTURE OUT OF NOTHING: a tile of one colour with a little grain in it, so the
## terrain reads as ground rather than as the extension's missing-texture checker. This project
## has no ground textures yet; when it has, they replace these two calls and nothing else.
static func _ground_texture(base: Color, grain: float, seed: int) -> ImageTexture:
	var side := 128
	var img := Image.create(side, side, true, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.05
	n.fractal_octaves = 3
	for y in side:
		for x in side:
			var k: float = n.get_noise_2d(float(x), float(y)) * grain
			img.set_pixel(x, y, Color(clampf(base.r + k, 0.0, 1.0), clampf(base.g + k, 0.0, 1.0),
					clampf(base.b + k * 0.8, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## THE WATER SURFACE: one translucent plane at the water line, over the lake or over the whole
## site when there is a sea. The bed is terrain like any other, so a shore is simply where the
## two meet and nothing has to agree with anything — which is also why one plane can serve a
## round lake and a half-plane of ocean without knowing which it is.
static func _water(parent: Node3D, prof: Profile, extent: float) -> void:
	var mesh := MeshInstance3D.new()
	var sea := prof.shore_n != Vector2.ZERO
	mesh.name = "Sea" if sea else "LakeSurface"
	var plane := PlaneMesh.new()
	var side := extent * 2.4 if sea else (prof.lake_r + prof.lake_shore_m) * 2.4
	plane.size = Vector2(side, side)
	mesh.mesh = plane
	var at := prof.centre if sea else prof.lake_centre
	mesh.position = Vector3(at.x, prof.water_y, at.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.34, 0.44, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.metallic = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	parent.add_child(mesh)


## Every region file in a directory, gone — see the note in `build`.
static func _empty(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".res"):
			d.remove(f)


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(maxi(poly.size(), 1))

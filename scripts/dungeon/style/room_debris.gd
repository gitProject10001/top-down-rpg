@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomDebris
extends Object
## Loose pebbles and grass tufts scattered over the floor — the half of seam-hiding a decal cannot do,
## because it ADDS GEOMETRY rather than projecting onto what is already there.
##
## A decal repaints a seam; a pebble sitting across one physically interrupts it, and casts its own
## little shadow under the room's fill light. Together they are what stops a 4 m lattice of identical
## square meshes reading as a lattice.
##
## BIASED ONTO THE JOINTS, which is the whole trick. Scattering uniformly would decorate the floor
## and leave the grid exactly as legible as before. `JOINT_BIAS` of the scatter is pulled onto the
## nearest 4 m tile boundary instead, so debris collects in the cracks — where it would actually
## gather, and precisely where the eye was finding the repeat.
##
## TWO MULTIMESHES PER ROOM, not two hundred nodes. docs/architecture.md's Godot-First rule, and the
## reason a few hundred pebbles cost nothing: one draw call each.
##
## The pebbles wear the theme's stone material, so they pick up the same palette remap, grime and
## moss as everything else — including per-instance variation, because the shader falls back to
## hashing MODEL_MATRIX when nobody set `piece_params`, and under a MultiMesh that matrix is the
## per-instance one.

const TILE := 4.0                  ## RoomShape's tile pitch — the lattice being hidden
const JOINT_BIAS := 0.7            ## fraction of debris pulled onto a joint rather than left loose
const JOINT_SPREAD := 0.35         ## metres either side of the joint line

const PEBBLES_PER_100M2 := 90.0
## THE OPEN FLOOR IS STILL SPARSE, and deliberately: this is grass finding a crack in a crypt, not a
## lawn, and a flat 34 here is the number that made a room look planted rather than neglected.
##
## That finding is about the MIDDLE of the room, so it survives the raise. With WALL_BIAS taking most
## of the count, 34 leaves about 12 per 100 m² loose on the floor — under the 14 the old sparse
## setting used — and puts everything else against the skirting, where thick is what it should be.
const TUFTS_PER_100M2 := 34.0

## THE SKIRTING IS THE LONGEST CRACK IN THE ROOM, and until now it was the one place debris could not
## reach: `_place` clamps 0.4 m inside the footprint, so every tuft landed on an interior tile joint
## and the wall met the floor on a clean line. It is also the first thing a photograph of a damp
## crypt shows, because it is where water that has run down the wall ends up.
##
## The extra tufts pay for themselves rather than adding cost: they share the existing MultiMesh, so
## the room still draws its grass in one call.
##
## NOT ATTEMPTED IN THE SHADER, though that was the first try. Growth in the brick joints cannot be
## masked from the stone material: the kit's bricks are coplanar boxes whose joints exist only as
## dark lines in the COLOR_0 bake, so there is no lit ledge to put a tuft on, and every gating I
## measured landed under 0.1% of frame — present in the buffer, invisible on screen.
const WALL_BIAS := 0.65            ## fraction of tufts started at the wall base, not a floor joint

## FOOTPRINT/2 IS NOT THE WALL. `ctx.footprint` is `size * CELL_PITCH - GAP` — a 1x1 room is 20 x 12
## — but the masonry stands proud of that line: measured over built rooms, a plain wall's INNER face
## sits 0.60 m inside it (+-9.40 of +-10 on x, +-5.40 of +-6 on z). Place a tuft at footprint/2 and
## it is not at the skirting, it is buried in the wall, which is exactly what the first version did:
## the placement maths was right, the reference plane was wrong, and the grass simply never appeared.
##
## 0.62 clears the deepest intrusion measured. Pieces that recess the other way — arcades, niches —
## go OUTWARD into the void, so they only ever leave a tuft further from the face, never inside it.
const WALL_FACE := 0.62
const WALL_SPREAD := 0.34          ## metres out from that face they straggle

## How far `_place` keeps its floor scatter clear of the footprint edge. Derived from the wall band
## rather than written as a number, so the two populations cannot overlap however the band is tuned —
## and so the suite can tell them apart by distance alone. The 0.06 is the gap between them.
const FLOOR_INSET := WALL_FACE + WALL_SPREAD + 0.06


static func scatter(room: Node3D, ctx: RoomContext, theme: DungeonTheme) -> void:
	if theme == null or theme.debris_density <= 0.0:
		return
	var area: float = ctx.footprint.x * ctx.footprint.z
	var rng := ctx.stream("debris")
	_pebbles(room, ctx, theme, rng, _spots(ctx, rng,
			int(round(area / 100.0 * PEBBLES_PER_100M2 * theme.debris_density)), false))
	if theme.tuft_color.a > 0.0:
		_tufts(room, ctx, theme, rng, _spots(ctx, rng,
				int(round(area / 100.0 * TUFTS_PER_100M2 * theme.debris_density)), true))


## THE POINTS, DRAWN AND FILTERED BEFORE ANY MULTIMESH IS SIZED. `_place` scatters over the room's
## BOUNDING RECT, which is not the same thing as its floor: a carved room has erased tiles inside
## that rect, and a room with a dais has a platform standing on it. Neither is expressible in a
## clamp, so this rejects instead — and the count that survives is the count the MultiMesh is built
## for, which is why the points come first rather than being filtered in the placement loop.
##
## `is_ground`, not `is_unblocked`: debris SHOULD gather at the foot of a pillar. The only things it
## must not do are fall through a hole or bury itself in a plinth.
const SPOT_TRIES := 6
const SPOT_CLEAR := Vector2(0.3, 0.3)

static func _spots(ctx: RoomContext, rng: RandomNumberGenerator, count: int,
		tuft: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in count:
		for attempt in SPOT_TRIES:
			var at: Vector3 = _place_tuft(ctx, rng) if tuft else _place(ctx, rng)
			if ctx.is_ground(at, SPOT_CLEAR):
				out.append(at)
				break
	return out


static func _pebbles(room: Node3D, ctx: RoomContext, theme: DungeonTheme,
		rng: RandomNumberGenerator, at_spots: Array[Vector3]) -> void:
	var count := at_spots.size()
	if count <= 0:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE                      # scaled per instance; one mesh for every pebble
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true                         # the stone shader reads COLOR as its variation signal
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var at: Vector3 = at_spots[i]
		var s := rng.randf_range(0.07, 0.20)
		var b := Basis()
		b = b.rotated(Vector3.UP, rng.randf() * TAU)
		b = b.rotated(Vector3.RIGHT, rng.randf_range(-0.5, 0.5))
		b = b.scaled(Vector3(s, s * rng.randf_range(0.4, 0.8), s * rng.randf_range(0.7, 1.3)))
		mm.set_instance_transform(i, Transform3D(b, at + Vector3(0.0, s * 0.2, 0.0)))
		# Inside the kit's measured COLOR_0 range, so the palette ramp maps pebbles like everything
		# else instead of clipping them to one end of it.
		var v := rng.randf_range(0.22, 0.55)
		mm.set_instance_color(i, Color(v, v * 0.96, v * 0.90))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Pebbles"
	mmi.multimesh = mm
	mmi.material_override = theme.material
	# THEY CAST NOW, and the comment that used to sit here — "300 shadow casters for 2 cm of stone" —
	# was written when the crypt had exactly one shadow-casting light and the answer was obviously
	# no. With nine casters and a moving torch it is obviously yes, for the reason that has nothing
	# to do with the pebble and everything to do with the floor: a small object with no contact
	# shadow does not read as small, it reads as NOT TOUCHING THE GROUND. They were stickers on the
	# floor. A MultiMesh renders its shadow pass as one draw regardless of instance count, so the
	# cost is a depth pass over 300 tiny cubes, not 300 draws.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# ...and no business in the GI trace either, for the same reason. A 2 cm pebble is far below
	# SDFGI's smallest cell, so it cannot occlude or bounce anything — it can only cost a
	# re-voxelisation. Says so explicitly rather than relying on the cell size to make it moot,
	# because VoxelGI arrives later at 0.168 m cells and would happily try.
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	room.add_child(mmi)


## Crossed alpha-cut cards, the cheapest tuft there is. Vertical, so the room's fill light rakes them.
##
## THE CARD MUST BE CUT OUT. The first version used bare opaque quads and the floor grew a crop of
## flat green rectangles — a quad with no alpha is a rectangle, however small you make it. The blades
## come from a generated alpha texture and ALPHA_SCISSOR, not from transparency: scissor keeps them
## in the opaque pass, so a few hundred cards need no depth sorting and take shadows normally.
static func _tufts(room: Node3D, ctx: RoomContext, theme: DungeonTheme,
		rng: RandomNumberGenerator, at_spots: Array[Vector3]) -> void:
	var count := at_spots.size()
	if count <= 0:
		return
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.26, 0.22)
	mesh.center_offset = Vector3(0.0, 0.11, 0.0)     # sit on the floor, not through it
	var mat := StandardMaterial3D.new()
	mat.albedo_color = theme.tuft_color
	mat.albedo_texture = _blade_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	# MSAA DOES NOT ANTIALIAS A SCISSORED EDGE without this. Scissor is a per-fragment discard, so
	# the blade silhouette lands entirely inside one sample and multisampling has nothing to
	# resolve — the tufts would be the one crawling, aliased thing in an otherwise smoothed frame.
	# Alpha-to-coverage turns the alpha into a coverage mask instead, which the same samples do
	# resolve. Free when MSAA is on and a no-op when it is off, so it costs nothing to say here.
	mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED     # a card seen from behind must not vanish
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 1.0
	mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count * 2                    # two quads crossed per tuft
	var i := 0
	for t in count:
		var at: Vector3 = at_spots[t]
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(0.6, 1.15)
		var shade := rng.randf_range(0.65, 1.15)
		for k in 2:
			var b := Basis().rotated(Vector3.UP, yaw + k * PI * 0.5).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(b, at))
			mm.set_instance_color(i, Color(shade, shade, shade))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tufts"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Alpha-scissor cards, so a voxeliser would read them as solid green boxes and bleed grass
	# colour into the bounce off the floor. Wrong twice over: too small to matter, and the wrong
	# answer if it did.
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	room.add_child(mmi)


## A clump of tapering blades, drawn once into a 64px alpha mask and shared by every tuft. Built in
## code rather than shipped as a .png for the same reason the stone noise is: nothing to author, and
## a theme can change the colour without touching an asset.
static var _blades: Texture2D = null

static func _blade_texture() -> Texture2D:
	if _blades != null:
		return _blades
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210                                  # fixed: one texture for the whole game
	for blade in 7:
		var root := rng.randf_range(0.18, 0.82)       # where it leaves the ground, in UV x
		var tip := root + rng.randf_range(-0.30, 0.30)
		var height := rng.randf_range(0.55, 1.0)
		var width := rng.randf_range(0.055, 0.10)
		for row in n:
			# v runs 0 at the TOP of the image; the blade grows from the bottom
			var t := 1.0 - float(row) / float(n - 1)
			if t > height:
				continue
			var f := t / maxf(height, 0.001)
			# curve toward the tip, and taper to nothing at the end
			var cx: float = lerpf(root, tip, f * f)
			var half: float = width * (1.0 - f) * 0.5 * float(n)
			var mid: float = cx * float(n)
			for col in range(int(floorf(mid - half)), int(ceilf(mid + half)) + 1):
				if col < 0 or col >= n:
					continue
				# darker at the root, so a clump has some depth to it
				var shade: float = 0.55 + 0.45 * f
				img.set_pixel(col, row, Color(shade, shade, shade, 1.0))
	_blades = ImageTexture.create_from_image(img)
	return _blades


## Where a tuft starts: WALL_BIAS of the time at the skirting, otherwise a floor joint as before.
##
## The side is drawn in proportion to its own length, not uniformly. Picking one of four walls at
## even odds puts as much grass along a 12 m wall as along a 20 m one, which reads as the short walls
## being overgrown — the same mistake as scattering by room rather than by area.
##
## PEBBLES DELIBERATELY DO NOT GET THIS. They are hiding the 4 m tile lattice, and the skirting is not
## part of it; a line of pebbles against the wall would decorate a seam that was never visible.
static func _place_tuft(ctx: RoomContext, rng: RandomNumberGenerator) -> Vector3:
	if rng.randf() >= WALL_BIAS:
		return _place(ctx, rng)
	var hx: float = ctx.footprint.x * 0.5 - WALL_FACE
	var hz: float = ctx.footprint.z * 0.5 - WALL_FACE
	var out: float = rng.randf_range(0.02, WALL_SPREAD)
	var flip: float = 1.0 if rng.randf() < 0.5 else -1.0
	if rng.randf() < hx / maxf(hx + hz, 0.001):
		# along an X-running wall: free along x, pinned just off the +Z or -Z face
		return Vector3(rng.randf_range(-hx + out, hx - out), 0.0, (hz - out) * flip)
	return Vector3((hx - out) * flip, 0.0, rng.randf_range(-hz + out, hz - out))


## A point on the floor, most of the time snapped onto the nearest tile joint. See JOINT_BIAS.
static func _place(ctx: RoomContext, rng: RandomNumberGenerator) -> Vector3:
	var hx: float = ctx.footprint.x * 0.5 - FLOOR_INSET
	var hz: float = ctx.footprint.z * 0.5 - FLOOR_INSET
	var at := Vector3(rng.randf_range(-hx, hx), 0.0, rng.randf_range(-hz, hz))
	if rng.randf() < JOINT_BIAS:
		# snap whichever axis is already closer to a joint, so debris lines the crack rather than
		# clustering on the intersections
		var dx: float = at.x - roundf(at.x / TILE) * TILE
		var dz: float = at.z - roundf(at.z / TILE) * TILE
		if absf(dx) < absf(dz):
			at.x -= dx - rng.randf_range(-JOINT_SPREAD, JOINT_SPREAD)
		else:
			at.z -= dz - rng.randf_range(-JOINT_SPREAD, JOINT_SPREAD)
		at.x = clampf(at.x, -hx, hx)
		at.z = clampf(at.z, -hz, hz)
	return at

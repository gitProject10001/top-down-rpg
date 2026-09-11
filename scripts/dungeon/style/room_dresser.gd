@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomDresser
extends Object
## The STYLE half of building a room: turn the planned slots into actual nodes.
##
## Reads RoomContext, writes scene nodes. It may NEVER add, move or remove a slot or a spawn — if
## dressing could shift a pillar or drop an enemy, the headless gameplay guarantees would be worth
## nothing. (It does reserve the floor its own clutter occupies, which is bookkeeping for later
## clutter only: it runs last, so nothing gameplay-relevant reads it afterwards.)
##
## Tag -> piece resolution, in order:
##   1. `theme.tag_pieces[tag]`   — this dungeon says a `cover_large` is a "statue", not a pillar
##   2. `DEFAULT_PIECE[tag]`      — the kit's stock answer
## then Kit.piece() resolves that name to theme variants / a wrapper scene / a greybox.

## The kit piece each abstract tag means by default.
const DEFAULT_PIECE := {
	RoomPlan.T_FLOOR: "floor_tile",
	RoomPlan.T_WALL: "wall_straight",
	RoomPlan.T_WALL_DOORWAY: "wall_doorway",
	RoomPlan.T_WALL_ANCHOR: "torch",
	RoomPlan.T_COVER_LARGE: "pillar",
	RoomPlan.T_COVER_SMALL: "crate",
	RoomPlan.T_FOCAL: "altar",
	RoomPlan.T_STAIR: "stair_flight",
	RoomPlan.T_DAIS: "dais",
	# A LEVEL CHANGE, as two roles on the tags that already existed. There is no "terrace" any more:
	# the raised floor is T_FLOOR at a height, the wall holding it up is a T_WALL at a boundary, and
	# only the two pieces that are genuinely a different SIZE need naming.
	RoomPlan.T_FLOOR + "/" + RoomPlan.FLOOR_RAMP: "stair_flight",
	RoomPlan.T_WALL + "/riser": "wall_riser",
	RoomPlan.T_KEY: "key",
	RoomPlan.T_WALL_BAND: "wall_band",
	RoomPlan.T_WALL_UPPER: "wall_upper",
	RoomPlan.T_WALL_CORNICE: "wall_cornice",
	RoomPlan.T_WALL_VAULT: "wall_vault",
	RoomPlan.T_COVER_UPPER: "column_shaft",
	# THE FLOOR INLAY, keyed `tag/role`. Not RoomPlan tags: the plan never emits these, the dresser
	# derives them from the shape (see _inlay), so they must not appear in RoomPlan.ALL_TAGS. A theme
	# may override any one of them through tag_pieces under the same key.
	"floor_inlay/border": "floor_inlay_border",
	"floor_inlay/corner": "floor_inlay_corner",
	"floor_inlay/threshold": "floor_inlay_threshold",
	"floor_inlay/medallion": "floor_inlay_medallion",
	# THE BREACH, placed rather than rolled. See _breach_slot.
	RoomPlan.T_WALL_UPPER + "/breach": "wall_breach",
	# THE BEVELLED CORNER. Roles on the EXISTING wall tags rather than tags of their own: a chamfer
	# is a wall, it just happens to be 2.83 m long and at 45 degrees, and nothing that iterates
	# RoomPlan.ALL_TAGS should have to learn about it. A theme shipping no chamfer art falls back to
	# the plain piece, which is 4 m and would poke through the room — so unlike every other role in
	# this map these entries are not optional decoration, they are the piece.
	RoomPlan.T_WALL + "/chamfer": "wall_chamfer",
	RoomPlan.T_WALL + "/half": "wall_half",
	RoomPlan.T_WALL_BAND + "/chamfer": "wall_band_chamfer",
	RoomPlan.T_WALL_UPPER + "/chamfer": "wall_upper_chamfer",
	RoomPlan.T_WALL_CORNICE + "/chamfer": "wall_cornice_chamfer",
	RoomPlan.T_WALL_BAND + "/half": "wall_band_half",
	RoomPlan.T_WALL_UPPER + "/half": "wall_upper_half",
	RoomPlan.T_WALL_CORNICE + "/half": "wall_cornice_half",
}

## Decoration ABOVE the base course — what the diorama cut removes. Everything here is
## collider-free by construction, which is what makes the cut provably gameplay-neutral.
## T_COVER_UPPER is here for a slightly different reason than the wall courses and it is worth
## stating: it is not decoration the cut removes, it is the top half of a COLUMN. Being a course is
## what makes a tall column legal at all -- collider-free, stamped with COURSE_META, and therefore
## veiled per frame by CourseVeil the moment it comes between the player and the lens. Its yaw is 0
## like every cover slot, so out_of_yaw never matches the cut side and it is never statically
## dropped; the veil is what handles it, which is the correct half of the pair for something
## standing in the middle of the floor rather than on a wall.
const COURSE_TAGS := [
	RoomPlan.T_WALL_BAND, RoomPlan.T_WALL_UPPER, RoomPlan.T_WALL_CORNICE, RoomPlan.T_WALL_VAULT,
	RoomPlan.T_COVER_UPPER,
]
## Stamped on every course piece that survives the cut, carrying its tag. Read by the verify suite.
const COURSE_META := "course_tag"
## ...and which way it faced, stamped beside it. The suite used to recover this from the built
## node's rotation.y, which is the same unguarded quarter-turn rounding side_of() exists to replace —
## so on a chamfer the test would have derived the same wrong answer as the bug and agreed with it.
## A test that reproduces the code's mistake is not a test.
const COURSE_OUT := "course_out"
## ...and HOW BIG IT IS, which is the pair CourseVeil needs and could not ask for. The veil tests a
## piece's ORIGIN against a fixed 2.6 m lane and a fixed COURSE_H, both of which are the numbers for
## a 4 m module — every course in the dungeon today. The moment a run is longer than one module, a
## piece whose centre is 6 m to the side is declared irrelevant while its far end sits directly over
## the player's head, and nothing notices: _cutaway_suite exempts anything carrying COURSE_META
## precisely BECAUSE the veil is supposed to handle it.
##
## Stamped from span_of(role) and Kit.SIZES rather than measured off the built node, because those
## are what the geometry is built from — the span suite already checks span_of against the collider
## that ships, so this inherits a tested number instead of introducing a second opinion.
const COURSE_SPAN := "course_span"
const COURSE_RISE := "course_rise"

## WHICH PLANNED SLOT A NODE CAME FROM, stamped on every piece the dresser builds from one, with the
## slot's role beside it. Pure introspection — nothing in the game reads either, and nothing should.
##
## It exists because the scene tree cannot answer the question afterwards: a built wall, a built
## course and a built chamfer are all a StaticBody3D with a mesh under it, and the tag that decided
## which one it is was consumed here and thrown away. The layout lab's assembly view groups by these
## to replay a room one rule at a time, which is the only way to SEE that the room is assembled by
## rules rather than authored.
const SLOT_META := "slot_tag"
const SLOT_ROLE := "slot_role"


## Mounts sit this far in from the walls (matches where the old hand-placed torches hung).
const MOUNT_INSET := Vector2(2.0, 1.0)
## A fight room reads better half-lit than a treasury does: stretch the spacing in combat rooms.
const COMBAT_SPACING_FACTOR := 1.4
## Keep sconces clear of the doorways so a lit mount never sits inside a passage.
const MOUNT_DOOR_CLEARANCE := 3.0
## However dark the theme, a room the player fights in must be readable.
const MIN_MOUNTS := 2
## Floor a single clutter prop is assumed to occupy, for overlap rejection.
const CLUTTER_SIZE := Vector2(0.6, 0.6)
## Rooms that get a shaft of daylight, as a fraction. Every room is weather; one in three is an
## event — and each one costs a shadow-casting spot, the most expensive light in this frame.
const BREACH_CHANCE := 0.34
## Floor a clutter prop keeps clear of a light mount. Mounts reserve nothing (see _clutter_spots),
## so this is the only thing standing between a pot and the inside of a candelabra.
const ANCHOR_CLEARANCE := 0.9


static func build(room: Node3D, ctx: RoomContext, theme: DungeonTheme) -> void:
	_breach_slot(ctx)                          # stamps a role on one slot; see Slot.role
	for slot in ctx.slots:
		var node := _instantiate(slot, ctx, theme)
		if node == null:
			continue
		room.add_child(node)
		node.set_meta(SLOT_META, slot.tag)
		node.set_meta(SLOT_ROLE, slot.role)
		node.position = slot.transform.origin
		node.rotation.y = slot.transform.basis.get_euler().y
		if slot.tag == RoomPlan.T_FLOOR and slot.role == RoomPlan.FLOOR_RAMP:
			# A FLIGHT IS NOT DROPPED and is not quarter-turned. Kit.stair already puts its bottom
			# at the tile's own floor and its yaw points it up the run.
			pass
		elif slot.tag == RoomPlan.T_FLOOR:
			# Kit pieces are anchored at their BOTTOM centre, so the slab has to drop by its own
			# thickness for its TOP to be the y=0 walk surface the rest of the room assumes.
			node.position.y -= _piece_height(piece_for(slot.tag, theme), theme)
			# QUARTER-TURN THE FLOOR. This is the cheapest fix for modular repetition in the whole
			# kit and it was the most visible one left: floor_tile is SQUARE (4 x 4, and so is its
			# collider), there are only two variants, and every one of them was laid at the same
			# yaw — so the floor read as a 4 m checkerboard of two patterns and the eye found the
			# grid immediately. Four rotations turns two tiles into eight distinct faces at zero
			# cost in geometry, draw calls or memory.
			#
			# Only for FLOOR. Walls are 4 x 3 x 0.5 and rotating one puts it through the room.
			# QUARTER turns only, never a continuous angle: a square tile at 37 degrees puts its
			# corners through its neighbours and leaves gaps at the walls.
			var turn := clampi(int(ctx.variant_roll("floor_yaw", slot.transform.origin) * 4.0), 0, 3)
			node.rotation.y += turn * PI * 0.5
			_inlay(room, ctx, theme, slot)
	# _light REPORTS where it put things, and clutter needs that rather than the slot list. Mounts
	# reach the room by two different routes: planned T_WALL_ANCHOR slots, and — when the plan
	# supplied none, which is every stairwell — the dresser's own perimeter spacing, which creates
	# nodes that were never slots at all. Reading the slots alone left clutter blind to the second
	# route, which is exactly where the last two pots-inside-a-candelabra were.
	var mounts := _light(room, ctx, theme)
	RoomGrime.scatter(room, ctx, theme)
	RoomDebris.scatter(room, ctx, theme)
	RoomFog.add(room, ctx, theme)
	_scatter_clutter(room, ctx, theme, mounts)


## WHICH UPPER COURSE BECOMES A BREACH, chosen instead of rolled.
##
## It used to be a weighted variant like any other: ~1.3% of wall_upper segments, which is about
## 0.8 per room spread over all four runs. In the bench that reads as a dramatic beat, because the
## bench forces one onto the wall you are looking at. In play it almost never landed there — three
## runs in four are either the cut side (dropped whole) or a side wall the fixed camera sees almost
## edge-on — so a feature that cost a shadow-casting spot was mostly invisible.
##
## THE DRESSER IS ALLOWED TO KNOW WHERE THE CAMERA IS. RoomPlan is not, deliberately ("a plan that
## already knew where the camera was would be a plan you could not re-skin"), but this file already
## calls cutaway_out(DungeonRoom.FRAME_YAW) to decide what to drop. Choosing where to PUT the one
## feature worth seeing is the same question answered the other way round.
##
## So: at most one per room, on the run the lens actually faces, at the bay nearest the room's
## centre — and only in some rooms, on a stable per-room roll, because a shaft in every chamber is
## weather rather than an event.
static func _breach_slot(ctx: RoomContext) -> RoomContext.Slot:
	if ctx.rd.type == DungeonLayout.RoomType.STAIR:
		return null                            # everything in a stairwell rides the flight
	if ctx.variant_roll("breach_room", Vector3.ZERO) > BREACH_CHANCE:
		return null
	var facing := -cutaway_out(DungeonRoom.FRAME_YAW)    # the run opposite the cut is the one seen
	var best: RoomContext.Slot = null
	for slot: RoomContext.Slot in ctx.slots_tagged(RoomPlan.T_WALL_UPPER):
		if not faces(side_of(slot), facing):
			continue
		if slot.role != "":
			continue                           # already spoken for; two roles on one slot is a fight
		if best == null or absf(slot.transform.origin.x) < absf(best.transform.origin.x):
			best = slot
	if best != null:
		best.role = "breach"
	return best


## Wall sconces, spaced around the room instead of hand-placed at four fixed corners, plus a warm
## pool over whatever the room is ABOUT (altar, plinth). Skipped entirely if the plan or a
## template authored explicit mounts — hand-authored lighting always wins.
static func _light(room: Node3D, ctx: RoomContext, theme: DungeonTheme) -> Array[Vector3]:
	var placed: Array[Vector3] = []
	_fill(room, ctx, theme)

	for slot in ctx.slots_tagged(RoomPlan.T_FOCAL):
		var pool := OmniLight3D.new()
		pool.light_color = theme.light_color if theme else Color(1.0, 0.75, 0.45)
		pool.light_energy = (theme.light_energy if theme else 1.5) * 0.8
		pool.omni_range = (theme.light_range if theme else 7.0) * 0.7
		# One per dungeon, standing in the middle of the room it marks. If anything in the crypt
		# has earned six cube faces it is the light the room is composed around.
		pool.shadow_enabled = true
		pool.shadow_bias = 0.03
		pool.shadow_normal_bias = 1.2
		pool.light_size = 0.20
		pool.light_volumetric_fog_energy = 1.4
		room.add_child(pool)
		pool.position = slot.transform.origin + Vector3(0, 2.0, 0)

	if not ctx.slots_tagged(RoomPlan.T_WALL_ANCHOR).is_empty():
		for slot: RoomContext.Slot in ctx.slots_tagged(RoomPlan.T_WALL_ANCHOR):
			placed.append(slot.transform.origin)
		return placed

	var spacing := theme.torch_spacing if theme else 10.0
	if ctx.rd.type == DungeonLayout.RoomType.COMBAT:
		spacing *= COMBAT_SPACING_FACTOR
	var climb := RoomPlan.climb_dir(ctx.rd)
	for at: Vector3 in _mount_points(ctx, spacing):
		var torch := Kit.piece(piece_for(RoomPlan.T_WALL_ANCHOR, theme), theme,
				ctx.variant_roll(RoomPlan.T_WALL_ANCHOR, at))
		room.add_child(torch)
		# in a stairwell the mounts ride the flight, or the upper ones are buried in the steps
		torch.position = at + Vector3(0, RoomPlan.climb_height(ctx, climb, at), 0)
		placed.append(torch.position)
	return placed


## The room's one hero light: high over the centre, wide, and the ONLY thing in the crypt that casts
## a shadow. Added before the early-out below, so a room whose mounts were hand-authored by a plan or
## a template still gets it.
##
## Sconces hang on walls and light walls. They left the middle of every room — the twenty by twelve
## metres the player actually fights in — reading as a black hole with a floor somewhere in it, and
## no amount of sconce energy fixes that, because the geometry is at the edges.
static func _fill(room: Node3D, ctx: RoomContext, theme: DungeonTheme) -> void:
	var energy := theme.fill_energy if theme else 2.2
	if energy <= 0.0:
		return
	var fill := OmniLight3D.new()
	fill.name = "RoomFill"
	fill.light_color = theme.fill_color if theme else Color(1.0, 0.86, 0.7)
	fill.light_energy = energy
	fill.omni_range = theme.fill_range if theme else 26.0
	# THE EXPONENT, NOT THE ENERGY, IS THE FLOOR'S PROBLEM. Godot's falloff is
	# pow(1 - d/range, attenuation), so at 1.0 this light loses brightness linearly with distance —
	# on top of the N.L term, which is ALSO falling as you move away from directly underneath it.
	# The two compound, and the corners of a 20x12 room get almost nothing. Raising energy does not
	# fix a curve: going 11 -> 15 moved floor/wall from 0.20 to only 0.21.
	#
	# Below 1.0 the pool stays bright further out and collapses near the lamp instead, which is
	# exactly the right shape for a light whose job is an even wash over a floor rather than a
	# pool around a bracket. The theme's sconces already run 0.9 for the same reason.
	fill.omni_attenuation = 0.7
	fill.shadow_enabled = true
	# Chunky brick relief at a grazing angle is the worst case for shadow acne, and an omni's
	# cubemap has no cascade to fall back on. Normal bias costs a little contact darkness at the
	# foot of a wall, which SSAO at brick radius puts straight back.
	#
	# BOTH BIASES COME DOWN now that the fill is no longer the only caster in the room. 2.0 was
	# tuned when a wall's foot had exactly one shadow to lose and the visible detachment was the
	# cheapest thing to trade away; with seven candelabras also casting into the same corner, that
	# detachment stops being a soft loss and starts reading as objects floating. The range cut below
	# is what pays for it — a shorter range means less depth packed into the same 16 bits, so the
	# same bias in world units buys more precision.
	fill.shadow_normal_bias = 1.2
	fill.shadow_bias = 0.03
	# PCSS-STYLE PENUMBRAE, and the highest-value knob in this phase. The project already sets
	# positional_shadow/soft_shadow_filter_quality = 4 and has never once used the property that
	# quality setting exists to serve: light_size is the emitter's physical radius, so the shadow is
	# contact-hard where an object meets the floor and widens with distance from it. That gradient
	# is most of what reads as expensive lighting, and it costs nothing but the filter taps already
	# being paid for. Widest in the room because the fill is the big soft key from above.
	fill.light_size = 0.30
	# Suppressed hard for Phase 7. A big soft omni at 5.5 m with real fog energy produces uniform
	# haze and nothing else — the sconces at floor level are what make shafts.
	fill.light_volumetric_fog_energy = 0.25
	room.add_child(fill)
	fill.position = Vector3(0.0, theme.fill_height if theme else 5.5, 0.0)


## Room-local mount positions, spread around the inset perimeter and clear of the doorways.
## Works off the footprint, so it keeps working when rooms stop being 20x12.
##
## Mounts that land in a doorway are SLID along the wall, not dropped: a room with three or four
## exits loses most of an evenly-stepped ring to the door clearances, and dropping them left rooms
## lit by a single torch. So sample the perimeter finely, throw away the blocked samples, and then
## spread the wanted number of mounts across whatever wall is left.
static func _mount_points(ctx: RoomContext, spacing: float) -> Array[Vector3]:
	var half := Vector2(ctx.footprint.x * 0.5 - MOUNT_INSET.x, ctx.footprint.z * 0.5 - MOUNT_INSET.y)
	var perimeter := 4.0 * (half.x + half.y)
	var target := maxi(MIN_MOUNTS, int(round(perimeter / maxf(spacing, 1.0))))
	# Offset the ring by a stable per-room amount so neighbouring rooms don't line up identically.
	var phase := ctx.variant_roll("wall_anchor_phase", Vector3.ZERO) * perimeter

	var clear: Array[Vector3] = []
	var on_floor: Array[Vector3] = []
	var samples := maxi(target * 8, int(perimeter / 0.5))
	for i in samples:
		var at := _on_perimeter(half, fmod(phase + perimeter * i / float(samples), perimeter))
		# the inset ring is derived from the BOUNDING box, so on a carved room part of it hangs
		# over a hole where there is no wall to mount to
		if not ctx.shape.contains(at):
			continue
		on_floor.append(at)
		if not _blocks_doorway(ctx, at):
			clear.append(at)
	if clear.size() < MIN_MOUNTS:
		# A small room with three or four exits can have no perimeter left that clears every
		# doorway. Better a sconce closer to a door than a room the player cannot see in: fall
		# back to whichever spots are furthest from any exit.
		var ranked: Array = []
		for at: Vector3 in on_floor:
			ranked.append({"at": at, "d": _door_distance(ctx, at)})
		ranked.sort_custom(func(a, b): return a.d > b.d)
		clear = []
		for i in mini(MIN_MOUNTS, ranked.size()):
			clear.append(ranked[i].at)
	if clear.is_empty():
		return []

	var out: Array[Vector3] = []
	var n := mini(target, clear.size())
	for i in n:
		out.append(clear[i * clear.size() / n])
	return out


## Map a distance along the inset rectangle's perimeter to a point, starting at the -x/-z corner
## and running +x, +z, -x, -z.
static func _on_perimeter(half: Vector2, d: float) -> Vector3:
	var w := half.x * 2.0
	var h := half.y * 2.0
	if d < w:
		return Vector3(-half.x + d, 0.0, -half.y)
	d -= w
	if d < h:
		return Vector3(half.x, 0.0, -half.y + d)
	d -= h
	if d < w:
		return Vector3(half.x - d, 0.0, half.y)
	d -= w
	return Vector3(-half.x, 0.0, half.y - d)


## THE DESIGNED FLOOR. A band along the walls, a return at the corners, a threshold across every
## doorway and a medallion in the middle — laid as a thin collider-free overlay ON the floor tile.
##
## WHY THIS IS DERIVED HERE AND NOT PLANNED. RoomPlan owns the questions only the plan can answer:
## which wall segments exist, where a doorway falls, what the room is for. A tile's role is not one
## of them — every tile exists by definition, and `ctx.shape` plus `ctx.doors()` answer "which of my
## neighbours are missing" completely, at dress time, with no plumbing. The rule the courses follow
## ("only RoomShape.walls() knows which segments can carry one") does not transfer, because there is
## nothing here to discover.
##
## The overlay carries no collision, so it cannot reach MapPainter, the occupancy grid or
## verify_map's area assertions. That is the whole reason it is an overlay rather than four more
## floor_tile variants: a floor tile with a second, taller shape flips its entire 4x4 to WALL.
const INLAY_TAG := "floor_inlay"
## How far the top of the inlay stands above the walk plane. floor_tile_brick_a.tscn's contract is
## that stones recess BELOW the walk surface and never above it, so footing is exactly the greybox's;
## 6 mm is inside the noise of that and reads as set INTO the floor rather than laid on top.
const INLAY_LIFT := 0.006


static func _inlay(room: Node3D, ctx: RoomContext, theme: DungeonTheme,
		slot: RoomContext.Slot) -> void:
	var at: Vector3 = slot.transform.origin
	# NOT ON A BEVELLED TILE. _inlay reads the four axis neighbours to decide its role, so a
	# chamfered corner still looks like a square corner to it and it would lay a 4 x 4 L whose arms
	# run straight through the new masonry.
	if ctx.shape.is_chamfer(ctx.shape.tile_at(slot.transform.origin)):
		return
	# NOT UNDER A PLATFORM. A dais stands on the centre tile, which is exactly the tile the medallion
	# is for — so the room's most elaborate piece of floor art would be built, dressed and drawn
	# entirely inside the plinth on top of it.
	if not ctx.is_ground(at, Vector2(1.0, 1.0)):
		return
	var tile := ctx.shape.tile_at(at)
	var open: Array[Vector2i] = []
	for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not ctx.shape.is_solid(tile + side):
			open.append(side)

	var role := ""
	var yaw := 0.0
	if _near_door_tile(ctx, at):
		role = "threshold"
		yaw = RoomShape._inward_yaw(_door_side(ctx, at))
	elif open.is_empty() and tile == Vector2i((ctx.shape.cols - 1) / 2, (ctx.shape.rows - 1) / 2):
		role = "medallion"                      # rotationally symmetric: it has no front
	elif open.size() == 2 and open[0] + open[1] != Vector2i.ZERO:
		# TWO PERPENDICULAR OPEN SIDES. Opposite pairs fall through deliberately — a one-tile-wide
		# spur is not a corner and gets the plain tile.
		role = "corner"
		yaw = _corner_yaw(open[0], open[1])
	elif open.size() == 1:
		role = "border"
		yaw = RoomShape._inward_yaw(open[0])
	if role == "":
		return

	var piece := piece_for(INLAY_TAG, theme, role)
	if piece == "":
		return                                  # no art for this role; the plain tile stands alone
	var node := Kit.piece(piece, theme, ctx.variant_roll("inlay_" + role, at))
	if node == null:
		return
	room.add_child(node)
	node.position = at + Vector3(0.0, INLAY_LIFT - _piece_height(piece, theme), 0.0)
	# DERIVED, NOT ROLLED, and this is the one thing easy to get wrong. The floor tile under it takes
	# a random quarter-turn to break the modular grid, but a border laid at a random quarter-turn is
	# a border pointing into the room. The pattern is authored on local -Z and _inward_yaw is the
	# function that puts a -Z-facing feature on a given side, which is the same contract wall pieces
	# already use.
	node.rotation.y = yaw


## A CORNER PIECE IS CHIRAL, which is why this is not just `_inward_yaw(one of them)`.
##
## The art carries bands on -Z and -X. Rotating it in quarter turns sweeps that pair through
## (-Z,-X) -> (-X,+Z) -> (+Z,+X) -> (+X,-Z) — all four corners, but each reachable from exactly one
## yaw. Taking `_inward_yaw` of whichever side came first out of a loop would be right a quarter of
## the time and put an L pointing out of the room the rest.
##
## So: walk the cycle the rotations actually produce and take the yaw of the side that leads.
static func _corner_yaw(a: Vector2i, b: Vector2i) -> float:
	const CYCLE: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0),
	]
	for i in 4:
		var lead: Vector2i = CYCLE[i]
		var follow: Vector2i = CYCLE[(i + 1) % 4]
		if (a == lead and b == follow) or (b == lead and a == follow):
			return RoomShape._inward_yaw(lead)
	return 0.0


## Is this tile the one an exit opens onto?
##
## THREE QUARTERS OF A TILE, not a half, and the half was a boundary miss that placed exactly zero
## thresholds. `door_local` puts a doorway ON the wall plane; the centre of the tile it opens into is
## therefore TILE * 0.5 = 2.0 m away, which is not LESS than 2.0. 3.0 catches that tile and stops
## short of the next one along at 6.0.
static func _near_door_tile(ctx: RoomContext, at: Vector3) -> bool:
	for door: Vector3 in ctx.doors():
		if absf(at.x - door.x) < RoomShape.TILE * 0.75 \
				and absf(at.z - door.z) < RoomShape.TILE * 0.75:
			return true
	return false


## Which way the nearest doorway faces out, so a threshold band lies ACROSS the way in rather than
## along it. Derived from which axis the door sits on the room's edge.
static func _door_side(ctx: RoomContext, at: Vector3) -> Vector2i:
	var best := Vector2i(0, -1)
	var near := INF
	for e: DungeonLayout.Edge in ctx.rd.edges:
		if e.dir.x == 0 and e.dir.z == 0:
			continue
		var door := DungeonLayout.door_local(ctx.rd, e)
		var d := Vector2(at.x - door.x, at.z - door.z).length()
		if d < near:
			near = d
			best = Vector2i(e.dir.x, e.dir.z)
	return best


static func _blocks_doorway(ctx: RoomContext, at: Vector3) -> bool:
	return ctx.near_door(at, MOUNT_DOOR_CLEARANCE)


static func _door_distance(ctx: RoomContext, at: Vector3) -> float:
	var best := INF
	for door: Vector3 in ctx.doors():
		best = minf(best, Vector2(at.x - door.x, at.z - door.z).length())
	return best


## Small props on whatever floor the gameplay passes left free. Purely cosmetic: it may only take
## space that is already free, and it never writes a spawn or moves a cover piece — which makes this
## the one pass in the whole dungeon that is gameplay-neutral BY CONSTRUCTION.
##
## IT CLUSTERS, and that is the whole change. The first version sampled uniformly over the room's
## bounding box, so props floated in open floor, evenly apart, looking dropped. Nothing in the
## reference art is placed like that: pots ring the foot of a column, bowls stand in rows along the
## base of a wall, sacks pile in the corner. Objects gather against things — a prop alone in the
## middle of a floor is the one arrangement that reads as procedural.
##
## Positions therefore come from the room's own furniture and walls (see `_clutter_spots`), and the
## RNG chooses only which of those get used and what stands there.
static func _scatter_clutter(room: Node3D, ctx: RoomContext, theme: DungeonTheme,
		mounts: Array[Vector3] = []) -> void:
	if theme == null or theme.clutter.is_empty() or theme.clutter_density <= 0.0:
		return
	var area := ctx.footprint.x * ctx.footprint.z
	var target := int(round(area / 100.0 * theme.clutter_density))
	if target <= 0:
		return

	var rng := ctx.stream("clutter")
	var placed := 0
	for at: Vector3 in _clutter_spots(ctx, mounts):
		if placed >= target:
			break
		var idx := clampi(int(rng.randf() * theme.clutter.size()), 0, theme.clutter.size() - 1)
		var size := _clutter_size(theme, idx)
		# is_unblocked, not is_free: cover, the key, the light mounts and any earlier clutter have all
		# claimed floor by now and a candidate spot knows about none of them — but the DOOR LANES are
		# not a reason to refuse a pot, and in a cross-carved room with three exits they cover every
		# surviving tile. The doorway itself is guarded separately, in _clutter_spots.
		if not ctx.is_unblocked(at, size, 0.15):
			continue
		var node := theme.clutter[idx].instantiate() as Node3D
		if node == null:
			continue
		room.add_child(node)
		node.position = at
		# quarter turns only: furniture in a room reads as placed, not dropped, and a square
		# reservation then covers every orientation it can take
		node.rotation.y = rng.randi_range(0, 3) * PI * 0.5
		# PAINT IT. kit.gd's note says clutter is a deliberate hole in _dress_walk and that the honest
		# fix is a second material — but that reasoning is about not WIDENING the walk from the room
		# root, and these pots are stone. Calling dress() on the prop itself gives them the kit's
		# palette and, because no roll is passed, the `piece_params` sentinel: the shader hashes each
		# one's own world position, so twelve copies of one urn are twelve different urns. The table
		# is untouched because it is marked NO_PAINT and dress() skips that subtree whole.
		Kit.dress(node, theme)
		ctx.reserve(at, size)
		placed += 1


## Per-prop footprint, falling back to the theme's single number. Same silent-fallback idiom as
## DungeonTheme.pick() uses for weights, so a half-filled array is legal rather than fatal.
static func _clutter_size(theme: DungeonTheme, idx: int) -> Vector2:
	if idx >= 0 and idx < theme.clutter_footprints.size():
		return theme.clutter_footprints[idx]
	return theme.clutter_footprint


## WHERE CLUTTER GATHERS, in the order it should be tried.
##
## Two sources, both derived from what the room already contains rather than from its bounding box:
##
##   RINGS  — around every cover piece. A pillar with three pots at its foot reads as a place people
##            put things down; the same three pots two metres away read as litter.
##   ROWS   — along the wall segments RoomShape.walls() emits, stepped in off the wall line by the
##            same inset RoomWeave uses for its sconces, so a row of bowls sits against the masonry
##            instead of inside it.
##
## Ordered by a POSITIONAL roll, never by the order walls() or slots happened to come out in. That
## keeps the choice edit-local — moving one pillar re-rolls the spots around that pillar and leaves
## the far wall's row exactly where it was — which is the law docs/directed-proceduralism.md 4 sets
## for every generated decision in this project.
static func _clutter_spots(ctx: RoomContext, mounts: Array[Vector3] = []) -> Array[Vector3]:
	const RING_RADIUS := 1.15
	const WALL_INSET := 0.85
	const ROW_STEP := 1.1
	## How far the corner nook sits in from the two wall faces meeting there. Enough that a 0.7 m
	## prop clears both: the wall piece is 0.5 thick and stands 0.25 m proud into the room, so a
	## prop centred 0.8 m in reaches 0.45 m from the boundary and never enters the masonry.
	const CORNER_INSET := 0.8
	var out: Array[Vector3] = []

	for slot: RoomContext.Slot in ctx.slots_tagged(RoomPlan.T_COVER_LARGE):
		var base: Vector3 = slot.transform.origin
		# Three around the foot, phase-shifted per pillar so neighbouring columns are not identical.
		var phase: float = ctx.variant_roll("clutter_ring", base) * TAU
		for i in 3:
			var a := phase + i * TAU / 3.0
			out.append(base + Vector3(cos(a), 0.0, sin(a)) * RING_RADIUS)

	for wall: Dictionary in ctx.shape.walls():
		var at: Vector3 = wall.at
		var outward: Vector2i = wall.out
		# NORMALISED, and a REAL perpendicular. Both were fine while every wall was axis-aligned and
		# both are wrong on a chamfer: a diagonal Vector2i has length sqrt(2), so the row sat 1.20 m
		# into the room instead of 0.85; and `(out.y, out.x)` is perpendicular only for a cardinal —
		# on (1, 1) it is (1, 1) again, so the three spots stacked along the wall's own normal and
		# the outermost one stood inside the masonry. On the four axes this is the same set of points
		# it always produced, because the +-1 steps are symmetric.
		var n := Vector3(outward.x, 0.0, outward.y).normalized()
		var inward := -n * WALL_INSET
		# THE ROW IS AS LONG AS ITS WALL. ROW_STEP was a flat 1.1 m whatever the run under it was, so
		# on a 2 m half-run the outer two spots sat 1.1 m from its centre — past its own end, in the
		# corner or inside the perpendicular run's masonry. Derived from the span it is 1.1 exactly at
		# a 4 m module, which is what makes this landable as it stands: every straight wall in the
		# dungeon keeps the row it had, and only the short runs the bevel introduced change.
		var reach: float = minf(ROW_STEP, float(wall.span) * 0.5 * 0.55)
		var along := Vector3(-n.z, 0.0, n.x) * reach
		for step in [-1.0, 0.0, 1.0]:
			out.append(at + inward + along * step)

	# CORNERS GET MORE, because things end up in corners. A wall run is swept and a corner is not:
	# rubble that falls stays there, and anything anyone pushes out of the way goes to the nearest
	# angle. Five spots against a wall bay's three, tucked at the diagonal and along both faces, so a
	# corner reads as a heap rather than as the two rows meeting.
	#
	# Found from the tile grid rather than from walls(): a tile with two PERPENDICULAR open sides is
	# a corner, which is the same test _inlay uses to pick its corner piece — so the debris gathers
	# exactly where the floor pattern already turns.
	for j in ctx.shape.rows:
		for i in ctx.shape.cols:
			var tile := Vector2i(i, j)
			if not ctx.shape.is_solid(tile):
				continue
			var open: Array[Vector2i] = []
			for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not ctx.shape.is_solid(tile + side):
					open.append(side)
			if open.size() != 2 or open[0] + open[1] == Vector2i.ZERO:
				continue
			var centre := ctx.shape.tile_centre(tile)
			var a := Vector3(open[0].x, 0.0, open[0].y)
			var b := Vector3(open[1].x, 0.0, open[1].y)
			# the nook itself, then a short spill along each of the two faces
			var nook := centre + (a + b) * (RoomShape.TILE * 0.5 - CORNER_INSET)
			out.append(nook)
			out.append(nook - a * 0.75)
			out.append(nook - b * 0.75)
			out.append(nook - a * 1.5 - b * 0.15)
			out.append(nook - b * 1.5 - a * 0.15)

	# Reject anything off the floor or standing in a doorway. The clearance is SMALLER than the one
	# sconces keep (MOUNT_DOOR_CLEARANCE, 3.0 m) and deliberately so: a lit mount in a passage reads
	# as a mistake, a pot beside a door reads as a pot beside a door. The doorway's clear opening is
	# 2 m wide, so 2 m of clearance keeps the walk-through line free and nothing more.
	#
	# The retry is the same shape as _mount_points': a 1x1 room with four exits has almost no
	# perimeter that clears every one of them, and seed 42's Room_-1_0_0 came back completely bare
	# because of it. An empty room is worse than a pot near a door.
	# NOTHING INSIDE A CANDELABRA. Wall-mounted anchors are emitted with a ZERO footprint — they hang
	# against the masonry and claim no floor, which is right for the gameplay grid and wrong here,
	# because `is_unblocked` therefore has no idea they exist. Every wall row runs at the same inset
	# the mounts do, so without this a pot lands inside the light stand it is standing next to.
	var lit: Array[Vector3] = mounts.duplicate()
	for slot: RoomContext.Slot in ctx.slots_tagged(RoomPlan.T_WALL_ANCHOR):
		lit.append(slot.transform.origin)
	var clear: Array[Vector3] = []
	for at: Vector3 in out:
		var blocked := false
		for m: Vector3 in lit:
			if Vector2(at.x - m.x, at.z - m.z).length() < ANCHOR_CLEARANCE:
				blocked = true
				break
		if not blocked:
			clear.append(at)
	out = clear

	var keep := _clutter_filter(ctx, out, 2.0)
	if keep.size() < 3:
		keep = _clutter_filter(ctx, out, 1.2)
	keep.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return ctx.variant_roll("clutter_order", a) < ctx.variant_roll("clutter_order", b))
	return keep


static func _clutter_filter(ctx: RoomContext, spots: Array[Vector3],
		clearance: float) -> Array[Vector3]:
	var keep: Array[Vector3] = []
	for at: Vector3 in spots:
		if ctx.shape.contains(at) and not ctx.near_door(at, clearance):
			keep.append(at)
	return keep


## THE DIORAMA CUT. Which way the wall that stands between the player and the lens faces, or ZERO
## if there is no single such wall.
##
## DungeonRoom pins the camera yaw (see DungeonRoom.FRAME_YAW), so exactly ONE side of every room is
## ever the occluder — and a 6.8 m wall on that side hides the player for 0.75 * 6.8 = 5.1 m of a
## 12 m-deep room. That side therefore stops at the base course, which is what every one of the
## reference images is: a cutaway diorama with the near side removed.
##
## FAIL SAFE: a yaw that is not a quarter turn has no single occluding wall, so this returns ZERO
## and the room builds CLOSED. Always correct, merely less pretty. It is safe to fail this way
## precisely because the COLLIDER is never cut — see the kit wrappers, which carry the full wall
## height on all four sides — so nothing about gameplay depends on the answer.
## WHICH SIDE OF THE ROOM A SLOT IS ON. One place, so the cut, the breach and the verify suite can
## never disagree about it — they did the derivation separately before, and three copies of a rule
## that is about to gain an exception is three chances to miss the exception.
##
## Prefers what the plan carried; falls back to the basis for everything that stands in open floor
## and has no side (cover, focal, a light mount), which is exactly what those meant before.
static func side_of(slot: RoomContext.Slot) -> Vector2i:
	if slot.out != Vector2i.ZERO:
		return slot.out
	return RoomShape.out_of_yaw(slot.transform.basis.get_euler().y)


## Does this side face the camera at all? A DOT, not an equality, and the difference only shows on a
## piece that is not square to the room: `cut` is always a cardinal, so a chamfer's diagonal `out`
## can never EQUAL it, and equality would therefore keep both chamfers on the camera-facing corner —
## the two pieces most certain to stand in front of the player. On the four axes the two rules agree
## exactly, which is why this can land before any chamfer exists and be provable by the suite as it
## stands today.
static func faces(side: Vector2i, towards: Vector2i) -> bool:
	return side.x * towards.x + side.y * towards.y > 0


static func cutaway_out(yaw: float) -> Vector2i:
	var quarters := yaw / (PI * 0.5)
	if absf(quarters - roundf(quarters)) > 0.01:
		return Vector2i.ZERO
	# +PI because we want the wall FACING the camera, not the one facing away from it
	return RoomShape.out_of_yaw(yaw + PI)


static func _instantiate(slot: RoomContext.Slot, ctx: RoomContext,
		theme: DungeonTheme) -> Node3D:
	var course := slot.tag in COURSE_TAGS
	if course:
		var cut := Vector2i.ZERO if (theme != null and not theme.cutaway) \
				else cutaway_out(DungeonRoom.FRAME_YAW)
		if cut != Vector2i.ZERO and faces(side_of(slot), cut):
			return null                       # the camera-facing side stops at the base course

	# THE ROLE COMES OFF THE SLOT NOW. It was a fourth argument to this function, computed by the
	# caller as `"breach" if slot == breach else ""` — an identity test against one privileged slot,
	# which does not generalise past exactly one role in exactly one room. Slot.role was declared and
	# documented for this and had never been written or read by anything.
	var piece_name := piece_for(slot.tag, theme, slot.role)
	if piece_name == "":
		push_warning("RoomDresser: no piece for tag '%s'" % slot.tag)
		return null
	# A flight is sized to the room it fills, so it cannot be a fixed kit piece. The slot's yaw
	# already points it up the run; here it only needs the room's own dimensions.
	if slot.tag == RoomPlan.T_STAIR and not (theme != null and theme.has_variants(piece_name)):
		var yaw := slot.transform.basis.get_euler().y
		var along_x := absf(cos(yaw)) > 0.5
		return Kit.stair(
				ctx.footprint.x if along_x else ctx.footprint.z,
				DungeonLayout.FLOOR_HEIGHT,
				ctx.footprint.z if along_x else ctx.footprint.x,
				theme,
				DungeonLayout.STAIR_LANDING)   # flat at the top, so the doorway is not a ledge
	# A PLATFORM IS A RAMP, not a box, and the greybox path cannot know that. Kit._box_body would
	# give this tag a 0.6 m cube with vertical sides — a ledge, and nothing in this project climbs a
	# ledge, so the greybox dungeon the headless suite builds would have an altar nobody can reach.
	# Kit.dais builds the stepped visual and the one frustum collider that makes it walkable.
	if slot.tag == RoomPlan.T_DAIS and not (theme != null and theme.has_variants(piece_name)):
		return Kit.dais(RoomShape.TILE, RoomPlan.DAIS_RISE, RoomPlan.DAIS_TOP, theme)
	# A gallery's flight is sized to the tile it climbs, so like every other flight in the game it
	# cannot be a fixed kit piece — and like every other one its collider is a single ramp, because
	# stepped colliders are stepped ledges and nothing here climbs a ledge.
	if slot.tag == RoomPlan.T_FLOOR and slot.role == RoomPlan.FLOOR_RAMP:
		# SIZED FROM THE SLOT'S OWN BLOCK, not from one tile. The span is in room axes, so which of
		# its two numbers is the run depends on which way the flight points — the same resolution
		# T_STAIR above makes, and for the same reason.
		var ramp_yaw := slot.transform.basis.get_euler().y
		var run_x := absf(cos(ramp_yaw)) > 0.5
		var tiles: Vector2i = slot.span
		var lift: int = ctx.shape.fixture_at(ctx.shape.tile_at(slot.transform.origin)).rise
		return Kit.stair(
				float(tiles.x if run_x else tiles.y) * RoomShape.TILE,
				float(lift) * RoomShape.LEVEL_RISE,
				float(tiles.y if run_x else tiles.x) * RoomShape.TILE,
				theme)
	# A PIECE SPANNING MORE THAN ONE MODULE IS BUILT TO LENGTH. There is no .tscn and no theme
	# variant for a 16 m wall and there should not be one — there would have to be one per length —
	# so it is stretched from the module's own size entry, exactly as a flight is sized to its run.
	# span is ONE for every piece but a fixture run, so this branch is never taken today.
	#
	# IT MUST NOT RETURN EARLY. Written as a `return` first, and that skipped the whole stamping
	# block below — so a 16 m course came out carrying no COURSE_META at all, CourseVeil never
	# collected it, and the one piece most in need of veiling was the only one exempt from it. The
	# stretched node joins the ordinary path instead.
	# Stable per-position roll: the same spot always draws the same variant, so adding a clutter
	# pass later cannot reshuffle the pillars that are already there.
	var roll := ctx.variant_roll(slot.tag, slot.transform.origin)
	# The slot's own Y IS how far above the floor this piece stands, which is exactly what the stone
	# shader needs to keep grime and moss at the floor instead of restarting them on every course.
	var node: Node3D = (Kit.run_piece(piece_name, float(slot.span.x) * RoomShape.TILE, theme)
			if slot.span.x > 1
			else Kit.piece(piece_name, theme, roll, slot.transform.origin.y))
	if course and node != null:
		node.set_meta(COURSE_OUT, side_of(slot))
		# So the cutaway can be ASSERTED rather than inferred. verify_dungeon._cutaway_suite reads
		# this back: an occlusion test alone cannot tell a surviving course from a stair room's
		# climbing base wall, and the greybox pieces have auto-generated names to identify them by.
		node.set_meta(COURSE_META, slot.tag)
		# THE SLOT'S OWN BLOCK WINS OVER THE ROLE TABLE. span_of() answers by role and a run's role
		# says nothing about its length — it would have called a 16 m course 4 m, which is precisely
		# the "a long piece defeats the veil silently" failure the veil was taught extents to avoid.
		# Reintroducing it here would have been invisible: the course would build at full length and
		# be veiled as though it were one module.
		node.set_meta(COURSE_SPAN, float(slot.span.x) * RoomShape.TILE if slot.span.x > 1
				else RoomShape.span_of(slot.role))
		# The piece's OWN height. Kit.SIZES is the greybox table, so a themed variant of a different
		# height would report its greybox — but the fallback it replaces was DungeonLayout.COURSE_H
		# for every piece in the dungeon regardless of what it was, so this is strictly closer and
		# never further. A piece with no entry keeps that fallback rather than reporting zero, which
		# would make the veil hide nothing.
		var greybox: Vector3 = Kit.SIZES.get(piece_name, Vector3.ZERO)
		node.set_meta(COURSE_RISE,
				greybox.y if greybox.y > 0.0 else DungeonLayout.COURSE_H)
	return node


## Which kit piece a tag resolves to, optionally in a ROLE.
##
## Four steps, first hit wins: the theme's override for `tag/role`, the theme's override for `tag`,
## the default for `tag/role`, the default for `tag`. `role` defaults to empty, so every existing
## call site means exactly what it always did.
##
## The point of the fallback chain is that a role is allowed to have no art. A theme that ships no
## border variant renders plain floor everywhere rather than erroring or rendering nothing, which is
## the same degradation rule Kit._resolve follows for variants and wrappers.
static func piece_for(tag: String, theme: DungeonTheme, role := "") -> String:
	if role != "":
		var keyed := tag + "/" + role
		if theme != null and theme.tag_pieces.has(keyed):
			return theme.tag_pieces[keyed]
		if DEFAULT_PIECE.has(keyed):
			return DEFAULT_PIECE[keyed]
	if theme != null and theme.tag_pieces.has(tag):
		return theme.tag_pieces[tag]
	return DEFAULT_PIECE.get(tag, "")


static func _piece_height(piece_name: String, theme: DungeonTheme) -> float:
	var fallback: Vector3 = Kit.SIZES.get(piece_name, Vector3.ONE)
	var size := theme.size_for(piece_name, fallback) if theme else fallback
	return size.y

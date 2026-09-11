@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomPlan
extends Object
## The GAMEPLAY half of building a room: what is where, and why it matters to the fight.
##
## Everything here writes ABSTRACT TAGGED SLOTS into the RoomContext — "a large cover piece
## stands at (-4, 3)" — and enemy spawn intents. NOTHING in this file may name a mesh, a scene,
## a material, a colour or a light. That is not style pedantry: it is what lets the headless
## suite hammer hundreds of seeds with no art loaded, and what lets a dungeon be re-skinned
## without anyone re-checking that the fights still work.
##
## The tags below are the contract with RoomDresser. `cover_*` in particular is a deliberate
## promotion: a pillar is not decoration, it is the thing you break line of sight behind, so it
## is planned here with a real footprint and respected by enemy placement.

## Interior of a single-cell room; used only to scale counts, never as "the" room size.
const BASE_AREA := DungeonLayout.ROOM_SIZE.x * DungeonLayout.ROOM_SIZE.z

# --- slot tags -------------------------------------------------------------------------------
const T_FLOOR := "floor"
const T_WALL := "wall"
const T_WALL_DOORWAY := "wall_doorway"
const T_WALL_ANCHOR := "wall_anchor"          ## sconce/torch/painting mount — claims no floor
const T_COVER_LARGE := "cover_large"          ## breaks line of sight (pillar-scale)
const T_COVER_SMALL := "cover_small"          ## body-blocks, shootable over (crate-scale)
const T_FOCAL := "focal"                      ## the thing the room is about (altar, plinth)
const T_STAIR := "stair"                      ## a flight climbing one floor; replaces the floor
const T_KEY := "key"                          ## the mission item that opens a locked gate

## A RAISED PLATFORM inside an otherwise flat room — floor at a different Y, which is a thing this
## dungeon has never had except as a whole stair room.
##
## It is a PLAN tag and not a decoration, because it changes where a body can stand: the tile it
## covers is reserved, so no cover, no light mount, no clutter and above all no spawn is planned on
## it. What stands on top is placed deliberately by whoever asked for the dais, at y = DAIS_RISE.
##
## Zero-footprint like the courses, for a reason worth stating: the reservation is written by an
## explicit ctx.reserve() instead. If the slot carried the footprint it claims, verify_dungeon's
## pairwise overlap test would see the platform and the altar standing on it as two rects fighting
## over the same 2.4 m of floor — which is exactly right in 2-D and exactly wrong here.
const T_DAIS := "dais"

## Its rise, and the flat square on top. Both are pinned; see Kit.dais and Kit.SIZES["dais"].
const DAIS_RISE := 0.6
const DAIS_TOP := 2.4

## THE FLIGHT THAT CLIMBS ONE LEVEL. Not a tag of its own: a ramp tile IS a floor tile, it just
## happens to be a sloped one, exactly as a stair room's floor is its flight. The role is what tells
## the dresser to build a slope instead of a slab.
const FLOOR_RAMP := "ramp"

## THE SHELL ABOVE THE BASE COURSE. Four decorative tags, all of them zero-footprint and
## collider-free: a course cannot add, move or block anything, so it can never change a fight.
##
## They are planned HERE rather than derived in RoomDresser because WHICH segments can carry a
## course is a property of the room's SHAPE — carved corners, doorways, a stair room's climb — and
## only RoomShape.walls() knows that. Whether the camera-facing one is BUILT is a presentation call
## and belongs to the theme; see RoomDresser.cutaway_out. Placement is plan, presentation is style,
## which is the seam this file and the dresser already sit either side of.
const T_WALL_BAND := "wall_band"              ## projecting string course over the base
const T_WALL_UPPER := "wall_upper"            ## second masonry course, a different bond
const T_WALL_CORNICE := "wall_cornice"        ## overhanging cap
const T_WALL_VAULT := "wall_vault"            ## barrel-vaulted hood over the perimeter aisle

## THE UPPER HALF OF A COLUMN — shaft and capital, standing on a cover_large drum.
##
## A course rather than a taller pillar, and the reason is a hard constraint rather than a taste.
## verify_dungeon's cutaway suite sweeps every mesh whose top clears COURSE_H + 0.35 against three
## player-to-camera segments, and it is right to: at a fixed 53-degree camera a full-height column
## standing in open floor hides the thing you are controlling. Courses are exempt from that sweep
## because they are provably veiled per frame — so splitting the column puts the SILHOUETTE above
## 3 m where it costs nothing and leaves the OBSTRUCTION below it, on the drum, where the fight
## already accounts for it.
##
## Zero-footprint like every other course: it claims no floor, so it cannot move a spawn or a piece
## of cover, and it bypasses every overlap assertion by construction rather than by exemption.
const T_COVER_UPPER := "cover_upper"

const ALL_TAGS := [
	T_FLOOR, T_WALL, T_WALL_DOORWAY, T_WALL_ANCHOR, T_COVER_LARGE, T_COVER_SMALL, T_FOCAL,
	T_STAIR, T_KEY, T_DAIS,
	T_WALL_BAND, T_WALL_UPPER, T_WALL_CORNICE, T_WALL_VAULT, T_COVER_UPPER,
]

const KEY_SIZE := Vector2(1.4, 1.4)

const COVER_LARGE_SIZE := Vector2(1.0, 1.0)
const COVER_SMALL_SIZE := Vector2(1.0, 1.0)
const FOCAL_SIZE := Vector2(2.4, 2.4)


## The doorway restore for an AUTHORED shape — and deliberately NOT pick's whole-row/column
## version. pick restores entire lines because its threat is corner BITES, and a line is the
## cheapest thing that provably survives them; an authored shape's threat is the author, and
## flattening whole lines destroyed the sculpting it was meant to protect — in a 1x1 room the
## door lines ARE the middle cross, so every deck laid across the centre was silently pressed
## flat and its risers never emitted (the floating-slab report). What a doorway actually needs
## is ONE tile: the boundary tile it lands on, solid at level 0, where the door slab and the
## corridor floor meet the room. That tile is restored per edge; every other authored tile —
## decks, pits, ramps — is left exactly as drawn. Doors run at build time because edges are the
## layout's and may attach after the shape was drawn. A fixture standing on the door tile is
## left (the schematic shows the conflict); a door mouth facing a deck the author never ramped
## reads as red unreachable tiles in ROOM view, which is the honest answer.
static func _restore_protect(rd: DungeonLayout.RoomData, shape: RoomShape,
		ctx: RoomContext) -> void:
	for e: DungeonLayout.Edge in rd.edges:
		var door := DungeonLayout.door_local(rd, e)
		var t: Vector2i
		var inward: Vector2i
		if e.dir.x != 0:
			t = Vector2i(shape.cols - 1 if e.dir.x > 0 else 0, shape.row_at(door.z))
			inward = Vector2i(-1 if e.dir.x > 0 else 1, 0)
		elif e.dir.z != 0:
			t = Vector2i(shape.col_at(door.x), shape.rows - 1 if e.dir.z > 0 else 0)
			inward = Vector2i(0, -1 if e.dir.z > 0 else 1)
		else:
			continue
		_protect_tile(shape, t, ctx)
		# AND THE DOOR NEEDS AN APPROACH, not just its tile. When the author carved the field
		# behind a doorway, restoring the boundary tile alone made an ISLAND: a floating slab in
		# the build, and a shape whose own round trip refuses (from_dict checks connectivity),
		# which then blocked every further sculpt of the room. So the restore digs a one-tile
		# strip inward until it meets the floor that is already there — a walkway through the
		# author's void, visible in the schematic, exactly where the door demanded it.
		var p := t + inward
		var guard := shape.cols + shape.rows
		while guard > 0 and p.x >= 0 and p.x < shape.cols and p.y >= 0 and p.y < shape.rows \
				and not shape.is_solid(p):
			if not shape.fill(p, 0):
				break                         # a claimed/frozen tile ends the dig; note follows
			p += inward
			guard -= 1


static func _protect_tile(shape: RoomShape, t: Vector2i, ctx: RoomContext) -> void:
	if shape.fixture_at(t) != null:
		return                                # left standing; visible in the schematic
	if not shape.is_solid(t):
		if not shape.fill(t, 0) and ctx.shape_note == "":
			ctx.shape_note = "a doorway line tile could not be restored at %s" % t
	elif shape.level_of(t) != 0:
		shape.set_level(t, 0)                 # void; a refusal leaves the level — doors climb


## Pick the room's FOOTPRINT, then floor it and wall it. ALWAYS runs, for every room type —
## templates author interiors only, so any template fits any shape and any door combination.
static func plan_shell(rd: DungeonLayout.RoomData, ctx: RoomContext) -> void:
	ctx.footprint = DungeonLayout.size_of(rd)

	# Tile lines a doorway opens on must survive carving. In a hall the exits are spread along the
	# walls, so this is genuinely per-edge rather than "the middle".
	var probe := RoomShape.for_room(rd)
	var protect_cols: Array = []
	var protect_rows: Array = []
	for e: DungeonLayout.Edge in rd.edges:
		var door := DungeonLayout.door_local(rd, e)
		if e.dir.x != 0:
			protect_rows.append(probe.row_at(door.z))
		elif e.dir.z != 0:
			protect_cols.append(probe.col_at(door.x))

	var climb := climb_dir(rd)
	# AN AUTHORED SHAPE, when the graph carries one (the Forge's sculpt mode). Strictly gated on
	# data: with no shape_data this whole block is one is_empty() and the pick call below is
	# byte-identical — which is what keeps every pinned hash still. Skipping pick also skips its
	# stream("shape") draw, and that is safe because streams are per-(seed, cell, pass): no other
	# room's randomness can see this room's undrawn stream (asserted by the graph suite).
	#
	# Refusals FALL BACK to pick and say so on ctx.shape_note: a stair room (its floor IS the
	# flight), a templated room (interiors authored against the full rect), a grid that no
	# longer matches the room's size, a replay the shape's own guards refused.
	var authored: RoomShape = null
	if not rd.shape_data.is_empty():
		if climb != Vector3.ZERO:
			ctx.shape_note = "authored shape ignored: a stair room's floor is its flight"
		elif rd.template_path != "":
			ctx.shape_note = "authored shape ignored: the room uses a template"
		else:
			authored = RoomShape.from_dict(rd.shape_data)
			if authored == null:
				ctx.shape_note = "authored shape refused by its own guards — carved procedurally"
			elif authored.cols != probe.cols or authored.rows != probe.rows:
				ctx.shape_note = ("authored shape is %dx%d but the room is %dx%d — carved "
						% [authored.cols, authored.rows, probe.cols, probe.rows]) + "procedurally"
				authored = null
	if authored != null:
		_restore_protect(rd, authored, ctx)
		ctx.shape = authored
		# THE SHAPE IS THE AUTHOR'S — silhouette, levels, ramps, bevels, all of it — so zoning
		# reduces to bookkeeping: claim what stands off-level so the interior passes keep off it.
		TileProgram.zone_authored(rd, ctx)
	else:
		ctx.shape = RoomShape.pick(rd, ctx.stream("shape"), protect_cols, protect_rows)
		# THE SHAPE IS FINISHED BEFORE ANY OF IT IS LAID — its silhouette, its bevels and its
		# LEVELS. Elevation belongs here, with the footprint, and not to a pass that runs later
		# and works around what the floor already did.
		# STEP 3, ZONING. The room's program says what it is FOR; TileProgram turns that into
		# tiles — which sit at which level, which carry a fixture — and everything below reads
		# what it committed.
		TileProgram.zone(rd, ctx, climb)

	if climb == Vector3.ZERO:
		for tile: Vector2i in ctx.shape.tiles():
			# A FIXTURE LAYS ITS OWN WALK SURFACE, ONCE, AT ITS ANCHOR — in tile order rather than in
			# a block of its own, for the same reason walls() emits them there: slot order is build
			# order, and a one-tile ramp has to come out at exactly the point in this loop its
			# per-tile predecessor did or nothing about this change is inert.
			var fx := ctx.shape.fixture_at(tile)
			if fx != null and fx.anchor == tile:
				_fixture_floor(ctx, fx)
			# ...and one that builds its own surface gets no slab under it. Dead for the bevel, which
			# stands on ordinary floor with a corner cut off — that is `contains`'s business and not
			# this loop's.
			if ctx.shape.consumes_floor(tile):
				continue
			# tile_centre carries the tile's own height, so a raised floor is laid by the same line
			# that lays every other floor.
			ctx.add_slot_at(T_FLOOR, ctx.shape.tile_centre(tile))
	else:
		# The flight IS the floor of a stair room — one piece spanning the whole run, so there is
		# no seam for the player to catch on halfway up.
		ctx.add_slot_at(T_STAIR, Vector3.ZERO, Vector2.ZERO, _yaw_of(climb))

	# One wall per boundary between floor and not-floor. Carved corners get their walls for free;
	# there is no separate "irregular room" path. In a stair room each segment rides the flight,
	# so the walls climb with it instead of being swallowed at the top.
	_plan_walls(rd, ctx, climb)

	# NO light mounts here on purpose. How brightly a room burns and how far apart the sconces
	# hang is STYLE — RoomDresser derives it from the theme. A template may still author explicit
	# T_WALL_ANCHOR slots, and those win.


## EVERY WALL THE SHAPE ASKS FOR, plus the courses above it. Split out of plan_shell so a shape
## carrying a fixture can be walled WITHOUT plan_shell first replacing it — plan_shell picks the
## footprint, so a test or a later zoning pass that installs a fixture and then wants the geometry
## has nowhere to call in. Same code, same order, one caller today.
static func _plan_walls(rd: DungeonLayout.RoomData, ctx: RoomContext, climb: Vector3) -> void:
	for wall: Dictionary in ctx.shape.walls():
		var tag := T_WALL
		for e: DungeonLayout.Edge in rd.edges:
			var hd := Vector2i(e.dir.x, e.dir.z)
			if hd != Vector2i.ZERO and RoomShape.is_doorway(wall, hd, DungeonLayout.door_local(rd, e)):
				tag = T_WALL_DOORWAY
				break
		var at: Vector3 = wall.at
		at.y = climb_height(ctx, climb, at)
		# CARRY THE SIDE, do not make the dresser guess it back out of the yaw. RoomShape.walls()
		# has always returned `out` and this line has always dropped it.
		if wall.role == "riser":
			tag = T_WALL                          # a level boundary is never a doorway
		var slot := ctx.add_slot_at(tag, at, Vector2.ZERO, wall.yaw)
		slot.out = wall.out
		slot.role = wall.role
		# HOW MANY MODULES THIS RUN IS. Exact for a fixture run, whose span is N * TILE by
		# construction; ONE for everything else, including the 2.83 m bevel — a fractional module is
		# not a multiple and the dresser must build the authored piece for it, not a stretched one.
		var mods := 1
		if wall.role == "long":
			mods = int(round(float(wall.span) / RoomShape.TILE))
		slot.span = Vector2i(mods, 1)
		# NO COURSES ON A RISER. The band, upper course, cornice and vault hood are the ROOM's
		# shell, stacked at fixed heights above the floor — 3.0 m and up. A riser is an interior
		# retaining wall 1.2 m tall, so hanging the room's courses off it puts a band, a whole
		# masonry course, a cornice and a barrel vault in mid-air over the gallery, attached to
		# nothing. They were the pieces flying above the deck.
		if wall.role != "riser":
			_plan_courses(ctx, at, wall.yaw, wall.out, wall.role, slot.span)





## INSTALL A WALL RUN, IF NO DOORWAY LIES UNDER IT. The only way a run should ever be created — the
## shape deliberately does not know where the doors are, so the check has to live on this side, and
## putting it behind the constructor means there is no path that skips it.
##
## A DOORWAY IS A PRE-COLLAPSED CELL. The run is refused outright rather than shortened or nudged,
## and that is the cheap answer to the most expensive breakage: Kit._doorway hard-codes its jambs to
## a 4 m module, and _plan_suite asserts exactly one doorway slot per exit, so a run that swallowed a
## door would not produce a wide opening — it would produce a blank wall where the exit was and seal
## the room. There is no tolerance that could be widened to make it work.
static func try_wall_run(rd: DungeonLayout.RoomData, ctx: RoomContext, anchor: Vector2i,
		out_dir: Vector2i, tiles: int) -> bool:
	var along := Vector2i(-out_dir.y, out_dir.x)
	for k in tiles:
		var t: Vector2i = anchor + along * k
		var at := ctx.shape.tile_centre(t) + Vector3(out_dir.x, 0, out_dir.y) * (RoomShape.TILE * 0.5)
		var probe := {"at": at, "out": out_dir, "role": "", "span": RoomShape.TILE}
		for e: DungeonLayout.Edge in rd.edges:
			var hd := Vector2i(e.dir.x, e.dir.z)
			if hd != Vector2i.ZERO and RoomShape.is_doorway(probe, hd,
					DungeonLayout.door_local(rd, e)):
				return false
	return ctx.shape.add_wall_run(anchor, out_dir, tiles)


## Does either wall of this corner carry an exit? Asked through RoomShape.is_doorway, the same test
## plan_shell uses below, rather than through a second rule that could drift from it.
static func corner_has_door(rd: DungeonLayout.RoomData, ctx: RoomContext,
		tile: Vector2i, d: Vector2i) -> bool:
	var centre := ctx.shape.tile_centre(tile)
	for side: Vector2i in [Vector2i(d.x, 0), Vector2i(0, d.y)]:
		var wall := {
			"at": centre + Vector3(side.x, 0.0, side.y) * (RoomShape.TILE * 0.5),
			"out": side,
		}
		for e: DungeonLayout.Edge in rd.edges:
			var hd := Vector2i(e.dir.x, e.dir.z)
			if hd == Vector2i.ZERO:
				continue
			if RoomShape.is_doorway(wall, hd, DungeonLayout.door_local(rd, e)):
				return true
	return false


## The band, the upper course, the cornice and the vault hood that sit on one base wall segment.
##
## Called with the base wall's own `at`, which already carries `climb_height`, so a stair room's
## courses ride the flight for free — exactly like the wall under them.
##
## Every one is zero-footprint, like the base wall: a course claims no floor, so it bypasses every
## overlap and bounds assertion in verify_dungeon._plan_suite by construction rather than by an
## exemption someone has to remember.
##
## All four sides are planned. The camera-facing one is dropped at DRESS time, not here — see
## RoomDresser.cutaway_out. The plan must stay a complete description of the room; a plan that
## already knew where the camera was would be a plan you could not re-skin.
static func _plan_courses(ctx: RoomContext, at: Vector3, yaw: float, out: Vector2i,
		role := "", span := Vector2i.ONE) -> void:
	var band := DungeonLayout.COURSE_H
	var upper := band + DungeonLayout.BAND_H
	var cornice := upper + DungeonLayout.COURSE_H
	for spec in [[T_WALL_BAND, band], [T_WALL_UPPER, upper], [T_WALL_CORNICE, cornice]]:
		var s := ctx.add_slot_at(spec[0], at + Vector3(0.0, spec[1], 0.0), Vector2.ZERO, yaw)
		s.out = out
		s.role = role
		# THE COURSES SPAN WHAT THE WALL UNDER THEM SPANS. A band in 4 m modules over a 16 m run
		# would put three joints where the wall has none, which is the seam a long piece exists to
		# remove.
		s.span = span
	# NO VAULT HOOD ON A BEVELLED RUN. The hood is a 4 m barrel spanning the perimeter aisle and
	# there is no 2.83 m or 2 m version of it; a missing bay over a bevelled corner reads as
	# intentional, a 4 m one cantilevered across a diagonal reads as broken.
	if role == "":
		ctx.add_slot_at(T_WALL_VAULT, at + Vector3(0.0, DungeonLayout.WALL_HEIGHT, 0.0),
				Vector2.ZERO, yaw).out = out


## Horizontal direction a stair room climbs toward (its up-edge), or ZERO for a normal room.
static func climb_dir(rd: DungeonLayout.RoomData) -> Vector3:
	if rd.type != DungeonLayout.RoomType.STAIR:
		return Vector3.ZERO
	for e: DungeonLayout.Edge in rd.edges:
		if e.dir.y > 0:
			return Vector3(e.dir.x, 0, e.dir.z)
	return Vector3.ZERO


## Height of the flight at a local point: 0 at the bottom door, FLOOR_HEIGHT at the top one.
static func climb_height(ctx: RoomContext, climb: Vector3, at: Vector3) -> float:
	if climb == Vector3.ZERO:
		return 0.0
	var run: float = ctx.footprint.x if climb.x != 0 else ctx.footprint.z
	# The rise is spread over the run MINUS a landing, so the flight is level for the last stretch
	# and the doorway is flat. See DungeonLayout.STAIR_LANDING for what this was fixing: the
	# passage's floor overhangs into the room, and a still-climbing flight underneath it left a
	# 0.3 m lip across the only way out.
	var rise := maxf(run - DungeonLayout.STAIR_LANDING, 1.0)
	var t := clampf((at.dot(climb) + run * 0.5) / rise, 0.0, 1.0)
	return DungeonLayout.FLOOR_HEIGHT * t


## Yaw that turns local +X into `dir`. Godot's Y rotation sends +X to (cos, 0, -sin), so pointing
## at +Z needs a NEGATIVE yaw — easy to get backwards.
static func _yaw_of(dir: Vector3) -> float:
	if dir.x > 0:
		return 0.0
	if dir.x < 0:
		return PI
	return -PI * 0.5 if dir.z > 0 else PI * 0.5


## Interior for a room with no handcrafted template: cover first, then the encounter placed
## against what the cover left free.
static func plan_interior(rd: DungeonLayout.RoomData, ctx: RoomContext) -> void:
	# A STAIRWELL IS NOT FURNISHED, and it is the one room the weave must not touch. Everything in a
	# stair room rides the flight — plan_shell already lifts each wall by climb_height, and
	# RoomDresser lifts its sconces the same way — while the weave works on a flat tile grid. Anchors
	# planned here would suppress the dresser's own pass (room_dresser.gd:105) and hang at floor
	# level while the floor climbed away underneath them.
	if rd.type == DungeonLayout.RoomType.STAIR:
		_plan_key(rd, ctx)
		return

	# THE PLATFORM GOES DOWN FIRST, before even the altar. It is the ground the altar stands on, and
	# it reserves its tile, so everything after this — the key, the cover, the mounts, the fight —
	# plans around it without any of them being told it exists.
	var lift := TileProgram.plinth(rd, ctx)

	# The altar is the treasure room's reason to exist, so it goes down before anything else and
	# everything works around it rather than the other way round.
	if rd.type == DungeonLayout.RoomType.TREASURE:
		ctx.add_slot_at(T_FOCAL, Vector3(0.0, lift, 0.0), FOCAL_SIZE)

	# The key goes in before the cover, so pillars and crates plan around it rather than on top.
	_plan_key(rd, ctx)

	# THE COMPOSITION. RoomWeave reads what the room is FOR and lays out cover, focal points and
	# light mounts together on the 4 m tile grid; it hands back the tiles it left free so the fight
	# is placed against what the furniture actually did, not against a blind lattice that never knew
	# the furniture existed.
	var spots := RoomWeave.weave(rd, ctx)

	match rd.type:
		DungeonLayout.RoomType.START, DungeonLayout.RoomType.TREASURE:
			return                                       # lit and dressed, but no fight
		DungeonLayout.RoomType.BOSS:
			_plan_boss(ctx)
			return

	plan_encounter(rd, ctx, spots)


## The boss ESCORT. Deliberately not randomised — the boss beat is authored, and positions are
## proportional to the footprint so a boss hall still reads as an arena.
##
## The corner pillars that used to live here are now the `arena` program's doing (RoomProgram):
## "corners only, middle left open for the area attack" is a statement about arrangement, and it
## belongs with every other such statement rather than hard-coded in one branch. What is left here
## is the part that is genuinely about this fight.
static func _plan_boss(ctx: RoomContext) -> void:
	var hx := ctx.footprint.x * 0.5 - 3.0
	var escort: Array[Array] = [
		["brute", 0.0, -0.17], ["melee", -hx * 0.7, 0.17], ["melee", hx * 0.7, 0.17],
	]
	for spec: Array in escort:
		var at := Vector3(float(spec[1]), 0.0, ctx.footprint.z * float(spec[2]))
		# is_free, because the arena's pillars are placed on the tile grid and this escort is placed
		# proportionally: the two agree at a single cell's size and there is no reason to assume
		# they still will at a 3x2's.
		if not ctx.is_free(at, COVER_SMALL_SIZE):
			at = ctx.find_free(COVER_SMALL_SIZE, 0.0, at)
		ctx.add_spawn(String(spec[0]), at + Vector3(0, 1, 0))


## Put the key somewhere it can actually be picked up: the first lattice spot with clear floor
## around it. Searched rather than pinned, because the room may be a carved L, a stairwell landing
## or a treasury with an altar in the middle.
static func _plan_key(rd: DungeonLayout.RoomData, ctx: RoomContext) -> void:
	if rd.holds_key == "":
		return
	var at := ctx.find_free(KEY_SIZE, 0.3, Vector3.ZERO)
	ctx.add_slot_at(T_KEY, at, KEY_SIZE)


## The walk surface one fixture lays, if it lays one. A bevel does not — it stands on the ordinary
## slab the loop above emits — so this is the ramp and, next, the wall run's threshold.
static func _fixture_floor(ctx: RoomContext, f: RoomShape.Fixture) -> void:
	if f.kind != "ramp":
		return
	# THE BLOCK'S CENTRE, which for the 1x1 case is the tile centre exactly. Taken at the LOW end's
	# level, because Kit.stair builds from its own origin upward and the slot's Y is where the foot
	# of the flight stands.
	var lo := ctx.shape.tile_centre(f.anchor)
	var hi := ctx.shape.tile_centre(f.anchor + f.span - Vector2i.ONE)
	var at := Vector3((lo.x + hi.x) * 0.5, float(f.level) * RoomShape.LEVEL_RISE, (lo.z + hi.z) * 0.5)
	# THE CLIMB GOES IN THE YAW, not in `out`. Kit.stair builds along local +X with its bottom at -X,
	# and Basis(UP, yaw) sends +X to (cos yaw, -sin yaw) — so this is the rotation that points the
	# flight up its own run. `out` stays ZERO on purpose: that field means WHICH SIDE OF THE ROOM a
	# piece faces, and a ramp's direction is not a side. Putting it there made the plan claim a floor
	# tile was a wall facing +X.
	var slot := ctx.add_slot_at(T_FLOOR, at, Vector2.ZERO,
			atan2(-float(f.dir.y), float(f.dir.x)))
	slot.role = FLOOR_RAMP
	slot.span = f.span


## Symmetric lattice of coordinates from -half to +half at `step`, always including 0.
static func _lattice(half: float, step: float) -> Array[float]:
	var out: Array[float] = []
	var n := int(floor(maxf(half, 0.0) / step))
	for i in range(-n, n + 1):
		out.append(i * step)
	return out


## Scale a per-room count by floor area, so a 2x2 hall is not furnished like a closet.
static func _scaled(ctx: RoomContext, base: int, cap: int) -> int:
	var area := ctx.footprint.x * ctx.footprint.z
	return clampi(int(round(base * sqrt(area / BASE_AREA))), 1, cap)


## Enemy count and mix scale with depth. Own RNG stream, so re-tuning prop density can never
## reshuffle the fight.
static func plan_encounter(rd: DungeonLayout.RoomData, ctx: RoomContext,
		spots: Array[Vector3]) -> void:
	var erng := ctx.stream("encounter")
	# Depth sets the pressure, floor area sets how much of it fits: a hall the player has to cross
	# should not hold the same three enemies a closet does.
	var enemy_count := _scaled(ctx, clampi(1 + rd.dist / 2, 1, 4), 8)
	# Deeper rooms may TRADE one slot for a swarm nest — never add one on top, and never more than
	# one per room: two nests out-spawn what the player can clear and the room stops being readable.
	var swarm_slot := -1
	if rd.dist >= 1 and erng.randf() < 0.35:
		swarm_slot = erng.randi_range(0, enemy_count - 1)
	for i in enemy_count:
		var kind := "melee"
		if i == swarm_slot:
			kind = "swarm"
		elif rd.dist >= 2 and erng.randf() < 0.4:
			kind = "archer"
		var pos: Vector3
		if spots.is_empty():
			pos = _fallback_spot(ctx, erng)
		else:
			pos = spots.pop_at(erng.randi_range(0, spots.size() - 1))
		# The nest is a StaticBody3D, so it must sit ON the floor; the others are CharacterBody3Ds
		# dropped from y=1 and left to fall.
		var y_off := 0.0 if kind == "swarm" else 1.0
		ctx.add_spawn(kind, pos + Vector3(0, y_off, 0))


## Somewhere to drop an enemy when every planned spot is taken. Must land on real floor — a room
## with carved corners has holes in its bounding box, and an enemy spawned over one falls out of
## the level. The room centre is always solid (the shape's cross), so it is the safe last resort.
static func _fallback_spot(ctx: RoomContext, rng: RandomNumberGenerator) -> Vector3:
	var hx := ctx.footprint.x * 0.5 - 4.0
	var hz := ctx.footprint.z * 0.5 - 3.0
	for _try in 24:
		var p := Vector3(rng.randf_range(-hx, hx), 0, rng.randf_range(-hz, hz))
		# is_free, not just "on the floor": a random point can land inside cover that was already
		# planted, which spawns an enemy embedded in a pillar.
		if ctx.is_free(p, COVER_SMALL_SIZE):
			return p
	# random darts failed — ask the grid directly rather than dropping the enemy at the origin,
	# which in a carved room is often inside something
	return ctx.find_free(COVER_SMALL_SIZE, 0.0, Vector3.ZERO)

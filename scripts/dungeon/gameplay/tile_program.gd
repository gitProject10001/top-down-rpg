@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name TileProgram
extends Object
## STEP 3, ZONING: turn a room's PROGRAM into tiles.
##
## The room's program says what the place is for — "somewhere people gather, an elevated place to
## look at, and a way to reach it". This is the pass that makes that a floor plan: which tiles sit
## at which level, and which multi-tile fixtures occupy which of them. Everything downstream — the
## floor slabs, the walls, the courses, the cover, the fight — reads what this committed and cannot
## tell how it decided.
##
## THE DECIDER, NOT THE RECORD. RoomShape stays the record: it holds the levels and the fixtures and
## answers questions about them. This file holds no state of its own and is static throughout, so
## there is exactly one place a room's zoning is decided and it can be replaced wholesale.
##
## WHAT THIS REPLACES, and why the replacement was worth making. A gallery was a flag on the
## program, a bespoke function that scanned for a row, and a bespoke pass that raised it. A dais was
## a different flag, a different function and a different pass. Both answered the same three
## questions — where does this go, how high is it, how do you get onto it — and neither could be
## asked a fourth time without a third mechanism. A zone asks them once.
##
## RELATIONS ARE WHERE THE INTENT LIVES. `reach` from the ground to a zone one level up does not say
## "put a ramp here"; it says a body must be able to get there, and the ramps fall out. That is the
## difference between a program that describes a feature and one that describes a purpose, and it is
## the whole reason this layer exists rather than two more flags.
##
## LEAF DECISIONS STAY POSITIONAL. Which corner is bevelled is `ctx.variant_roll(key, tile_centre)`,
## keyed to WHERE and not to WHEN, so a room that gains a door far away does not re-roll the corners
## it already had. The zoning itself may search — it commits once and nothing downstream can tell —
## but a leaf that a later pass could reach must not depend on the order this one ran in.


## Zone the room. Called from RoomPlan.plan_shell, after the footprint is picked and before any of it
## is laid, because every later pass is clipped to what this decides.
static func zone(rd: DungeonLayout.RoomData, ctx: RoomContext, climb: Vector3) -> void:
	_bevel_corners(rd, ctx, climb)
	# A STAIR ROOM IS NOT ZONED. Its whole floor is one flight, so there is nothing to raise and
	# nowhere to put it — the same exclusion the bevels make, for the same reason.
	if climb != Vector3.ZERO:
		return
	# THE LAYOUT PROPOSES AND THE ROOM DISPOSES, and the loop is what makes that honest.
	#
	# The layout decides a purpose from the room's kind, proportion and doors — everything it can see.
	# What it cannot see is the room's SHAPE, which is carved here, so it can hand down a purpose the
	# room turns out to be unable to honour. When the unhonoured part is REQUIRED, the room stops
	# making the claim and falls back, then tries again as the thing it now is.
	#
	# The alternative shipped for two milestones and is what this replaces: 173 rooms called
	# themselves churches and 97 of them had no apse. A label the geometry does not back is worse
	# than a plainer label, because everything downstream — the cover pattern, the lighting, the
	# bench, the player — believes it.
	#
	# THE SETTLED PURPOSE GOES ON THE CONTEXT, NEVER BACK ONTO THE ROOM. Writing rd.purpose here was
	# the first attempt and the pass-independence suite killed it within one run: two contexts built
	# from the same RoomData would disagree, because the first build demoted the room and the second
	# started from the demotion. A room pass that edits layout data makes plan_shell non-idempotent,
	# which is precisely what that suite exists to catch.
	#
	# So `rd.purpose` stays the layout's PROPOSAL and `ctx.program` is what this room settled on. The
	# layout is still the decider; the room is the only thing that knows its own shape, and it
	# records its answer where per-room answers live.
	#
	# Terminates because DEMOTE_TO is a chain with no cycle and every step is strictly plainer.
	# EVERY ZONE MOVES THE SHAPE BEFORE ANY OF THEM BAKES THE GRID, and this list is what makes that
	# true across zones rather than only inside one.
	#
	# `_place_walk` already carried the rule and the reason — "THE SHAPE FIRST, THE GRID AFTER",
	# because move_floor calls RoomContext._ensure_grid, which snapshots the room and FREEZES the
	# shape against any further floor-moving fixture. What nobody had to think about was a second
	# zone, because until the colosseum grew tiers no program asked for two. The moment one did, the
	# arena's own move_floor froze the shape and every flight the deck then tried to install was
	# refused by add_fixture — a raised row with no way onto it, in seven rooms.
	#
	# So the claims are collected and flushed once, after the last zone has had its say. That is the
	# same ordering the file already argued for, applied at the scope the argument was actually about.
	var claims: Array[Vector2i] = []
	var name := RoomProgram.for_room(rd)
	for _step in 4:
		var failed_required := false
		for z: Dictionary in RoomProgram.zones_of(name):
			if int(z.get("level", 0)) == 0:
				continue                      # a ground-level zone claims no tiles here; see plinth()
			var rels := RoomProgram.relations_of(name)
			var placed := false
			match z.get("affinity", ""):
				RoomProgram.A_WALL:
					placed = _place_walk(rd, ctx, z, rels, claims)
				RoomProgram.A_END:
					placed = _place_apse(rd, ctx, z, rels, claims)
				RoomProgram.A_CENTRE:
					placed = _place_pit(rd, ctx, z, rels, claims)
			if placed:
				continue
			# COUNTED, NOT SWALLOWED. An optional zone the room could not fit is still a statement
			# the program made and the dungeon did not honour, so a constraint added three milestones
			# from now cannot quietly stop every prison having an oubliette.
			ctx.zones_refused += 1
			if bool(z.get("required", false)):
				failed_required = true
		if not failed_required:
			break
		var down: String = RoomPurpose.DEMOTE_TO.get(name, "")
		if down == "":
			break
		name = down
	ctx.program = name
	for t: Vector2i in claims:
		ctx.move_floor(ctx.shape.tile_centre(t), Vector2(RoomShape.TILE, RoomShape.TILE))

	# THE WALLS THEMSELVES, LAST. Runs are installed after the zones because a zone can raise or sink
	# tiles and a run must be built along the boundary that survives — and after the bevels, which
	# claim their corner tile and would otherwise be overrun.
	_place_wall_runs(rd, ctx, int(RoomProgram.rules(name).get("wall_run", 0)))


## Zoning for a room whose shape the AUTHOR finished (rd.shape_data via the Forge's sculpt
## mode). The geometry — silhouette, levels, ramps, bevels — arrived in the dict, so what
## remains of zoning is its bookkeeping half: claim every tile that stands off the ground so
## the cover pass, the mounts and the encounter keep off it, exactly what zone()'s claims
## flush does for the placers' tiles. The first move_floor bakes the grid and freezes the
## shape, which is freeze-order safe by construction: authoring finished before this ran.
##
## What an authored room deliberately does NOT get (v1, recorded here rather than discovered):
## no settled ctx.program (RoomWeave.for_room falls back per room_weave.gd), no zone deck
## lights, no sightline claims, and no wall runs (they hang off a settled program's want).
static func zone_authored(_rd: DungeonLayout.RoomData, ctx: RoomContext) -> void:
	for t: Vector2i in ctx.shape.tiles():
		if ctx.shape.level_of(t) != 0 or ctx.shape.is_ramp(t):
			ctx.move_floor(ctx.shape.tile_centre(t), Vector2(RoomShape.TILE, RoomShape.TILE))


## LONG WALLS BUILT AS ONE PIECE instead of a row of 4 m modules.
##
## This is the first caller M6.8's fixture has ever had. The mechanism shipped with no user on
## purpose — a capability with no caller is only as real as the test that drives it — and what it was
## waiting for is art that spans more than a module, because that is the only thing a multi-tile run
## can do that four separate modules cannot: carry a feature ACROSS the joints. A batter, an arcade
## whose bays are not on the tile grid, a face that curves.
##
## LONGEST FIRST, THEN SHORTER. A program asks for a length; if the wall cannot give it the run
## shortens rather than the wall falling back to modules — the same "move before refusing" every
## other placer here answers to. Below three tiles it stops being worth it: at two, the piece spans
## one joint fewer than the modules it replaces.
static func _place_wall_runs(rd: DungeonLayout.RoomData, ctx: RoomContext, want: int) -> void:
	if want < 3:
		return
	var shape := ctx.shape
	const SIDES: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for side: Vector2i in SIDES:
		# TWO DIRECTIONS, AND THEY ARE NOT THE SAME ONE. `step` is the way add_wall_run walks from
		# the anchor it is given; `along` is the way this scan reads the line, which is always
		# ascending so the run-finding is simple. For two of the four sides they point opposite ways,
		# and handing the ascending end to a constructor that walks descending sent it straight off
		# the grid — "tile (-1, 2) is not floor", which is the error saying exactly that and which is
		# only visible because add_wall_run checks its tiles instead of trusting its caller.
		var step := Vector2i(-side.y, side.x)
		var along := Vector2i(absi(side.y), absi(side.x))
		var lines := shape.cols if along.y != 0 else shape.rows
		var across := shape.rows if along.y != 0 else shape.cols
		for a in lines:
			var i := 0
			while i < across:
				# A tile joins a run when it is floor, its `side` neighbour is not, and nothing has
				# claimed it — a bevel owns its whole tile's wall emission and a ramp owns its floor.
				if not _run_tile(shape, a, i, along, side):
					i += 1
					continue
				var j := i
				while j + 1 < across and _run_tile(shape, a, j + 1, along, side):
					j += 1
				var n_tiles := j - i + 1
				while n_tiles >= 3:
					var take := mini(n_tiles, want)
					# The end `step` walks INTO the run from: the low end when it ascends, the high
					# end when it descends.
					var first := i if (step.x + step.y) > 0 else i + take - 1
					var anchor := (Vector2i(a, first) if along.y != 0 else Vector2i(first, a))
					if RoomPlan.try_wall_run(rd, ctx, anchor, side, take):
						break
					n_tiles -= 1
				i = j + 1


static func _run_tile(shape: RoomShape, a: int, i: int, along: Vector2i, side: Vector2i) -> bool:
	var t := (Vector2i(a, i) if along.y != 0 else Vector2i(i, a))
	return shape.is_solid(t) and not shape.is_solid(t + side) and shape.fixture_at(t) == null


## THE PLINTH, which is zoned at a different time and that is deliberate rather than untidy.
##
## It is the ground the room's subject stands on, so it must claim its tile before the subject is
## placed — which happens in plan_interior, after the shell. Zoning it in `zone()` would reserve
## floor before the walls are emitted, and reserving is what BAKES the occupancy grid and freezes the
## shape, so no fixture could be installed afterwards. Two entry points is the price of one ordering
## guarantee that several passes already depend on.
##
## Returns the height of the surface it built, or 0.0, so the caller can stand something on it
## without needing to know whether it exists.
static func plinth(rd: DungeonLayout.RoomData, ctx: RoomContext) -> float:
	for z: Dictionary in RoomProgram.zones_of(RoomProgram.for_room(rd)):
		if z.role != RoomProgram.Z_PLINTH:
			continue
		var shape := ctx.shape
		var t := Vector2i(shape.cols / 2, shape.rows / 2)     # cols and rows are always odd
		var at := shape.tile_centre(t)
		# is_unblocked, NOT is_free — the difference is door lanes, and ignoring them is deliberate.
		# A door on a long wall throws its approach lane straight down the middle of the room, so the
		# centre tile of a 20 x 12 room is ALWAYS in one; testing is_free here would mean the plinth
		# never appeared anywhere. What actually matters is distance to the door itself, next.
		if not ctx.is_unblocked(at, Vector2(RoomShape.TILE, RoomShape.TILE)):
			return 0.0
		# Stricter than the 4.0 m verify_dungeon asserts for a footprint slot, because the platform is
		# wider than what stands on it and a doorway opening onto a step is a doorway you trip over.
		if RoomWeave.door_distance(ctx, at) < 4.5:
			return 0.0
		ctx.add_slot_at(RoomPlan.T_DAIS, at)
		ctx.move_floor(at, Vector2(RoomShape.TILE, RoomShape.TILE))
		return float(z.get("rise", RoomPlan.DAIS_RISE))
	return 0.0


## A RAISED WAY ALONG A WALL, and the ramps its `reach` relation implies.
##
## The placement rule is the one the gallery pass already used, and it is a rule about this affinity
## rather than about galleries: a wall zone takes the longest door-free run on the row FURTHEST from
## the camera. Both halves are load-bearing and neither is arbitrary.
##
## THE LONGEST RUN, NOT THE WHOLE ROW. Requiring every tile of the far row cost the feature almost
## entirely: over 60 seeds, 159 rooms ran a program with a walk and 18 got one — and the refuser was
## not doors (41) but CARVING (100). RoomShape.pick bites rectangles out of the four corners, and a
## corner bite eats into the far row nearly every time, so "the whole row" ruled out most of the
## carved rooms, which is most rooms. A way down part of a wall is still a way.
##
## THE FAR ROW because of what the camera can see, and that is now a measured preference rather than
## a taboo: a deck on the far row has its riser turned toward the lens and occludes nothing at all,
## while the same deck on the near row hides 0.90 m of the floor behind it per level.
## RoomShape.camera_legal is the rule; this is the bias that keeps every room well inside it.
static func _place_walk(rd: DungeonLayout.RoomData, ctx: RoomContext, z: Dictionary,
		relations: Array, claims: Array[Vector2i]) -> bool:
	var shape := ctx.shape
	var want: Vector2i = z.get("want", Vector2i.ONE)
	# A row to give up and at least two to keep.
	if shape.rows < 3 or shape.cols < want.x:
		return false

	var row := 0
	var lo := -1
	var hi := -1
	var i := 0
	while i < shape.cols:
		if not shape.is_solid(Vector2i(i, row)):
			i += 1
			continue
		var j := i
		while j + 1 < shape.cols and shape.is_solid(Vector2i(j + 1, row)):
			j += 1
		if j - i + 1 >= want.x and RoomWeave.run_clear(rd, ctx, row, i, j) and j - i > hi - lo:
			lo = i
			hi = j
		i = j + 1
	if lo < 0:
		return false

	# THE REACH RELATION IS WHAT PUTS THE STAIRS IN. Without one the walk is legal and unreachable,
	# so it is refused outright rather than built as a shelf — a zone nobody can stand on is a hole
	# in the room's program, not a decoration.
	var reach := false
	for r: Dictionary in relations:
		if r.get("to", "") == z.role and r.get("kind", "") == RoomProgram.R_REACH:
			reach = true
	if not reach:
		return false

	# THE RAMPS GO IN THE ROW BELOW, climbing toward the deck — NOT in the deck row climbing along
	# it. That was the first version and it built a staircase nobody could use: a ramp at the END of
	# the run has its low end against whatever the run ends at, which is either the room's end wall
	# or the carved void the run stopped for. You walked up to it only if you were already on it.
	#
	# It costs one tile of ordinary floor at each end, and it makes the riser suppression in
	# RoomShape.walls() fire exactly as written: the ramp climbs -Z into the deck above it, so the
	# boundary between them is the one place the retaining wall is not built.
	# A RAMP NEEDS ITS FOOT AS WELL AS ITSELF. The tile the flight stands on has to be there, and so
	# does the tile in front of it — a ramp whose bottom step opens onto a carved void is a staircase
	# you can only use from the top, which is the whole failure this pass once had.
	# AND IT NEEDS ITS OWN TILE CLEAR OF DOORS. run_clear was applied to the DECK row only, which is
	# the row a door cannot open onto because there would be a 1.2 m wall behind it — but the flights
	# stand in the row BELOW, and nothing ever tested that one. A door opening into a ramp tile puts
	# the side of a staircase across the opening: you come through and meet a flight edge-on, which
	# is what "stairs blocking a door" looks like from inside the room.
	#
	# THE FLIGHTS SLIDE INWARD RATHER THAN THE WALK BEING REFUSED. Any column of the deck can carry a
	# flight, so a blocked end costs a tile of walkway and not the feature — the same choice
	# add_ramp makes when a slope is too steep, where the answer is to lengthen rather than to give
	# up. Only when fewer than two columns are usable is there no gallery to build.
	var below := row + 1
	var usable: Array[int] = []
	for k in range(lo, hi + 1):
		var rt := Vector2i(k, below)
		var foot := Vector2i(k, below + 1)
		if not (shape.is_solid(rt) and shape.is_solid(foot) and shape.level_of(foot) == 0):
			continue
		# THE FLIGHT'S OWN TILE MUST BE AT LEVEL 0 TOO, and until the colosseum grew tiers nothing
		# could make it otherwise — this pass was the only one that moved a level, so the row below
		# a deck was ground by construction. Now the arena sinks the middle row first, and in a
		# three-row room that middle row IS the row the flights stand in. add_ramp takes its rise
		# from the anchor's own level, so a flight starting at -1 and rising one level arrives at 0
		# and the deck above it at +1 is a shelf: the reachability BFS found seven rooms where the
		# whole far row could not be walked to, which is exactly the assertion earning its keep.
		if shape.level_of(rt) != 0 or shape.consumes_floor(rt) or shape.consumes_floor(foot):
			continue
		# AND NOTHING ELSE MAY ALREADY OWN IT. consumes_floor is not the question here — it names
		# ramps only, because a BEVELLED tile still gets its floor slab and so must answer no. But a
		# bevel does CLAIM its tile, and add_fixture refuses a second claim, so set_ramp on a
		# bevelled corner returns false with nobody reading the return: the deck came out raised
		# with zero flights. Two seeds, and both of them decks whose ends are the room's own
		# corners — which is precisely where the flights go, so it was not a rare collision.
		if shape.fixture_at(rt) != null:
			continue
		# The flight's own tile AND the floor it steps down onto: a door into either one is a door
		# you arrive at the side of a staircase through.
		if not RoomWeave.run_clear(rd, ctx, below, k, k):
			continue
		if not RoomWeave.run_clear(rd, ctx, below + 1, k, k):
			continue
		usable.append(k)
	if usable.size() < 2:
		return false                             # one flight is a perch, not a place
	var flights := [usable[0], usable[-1]]

	# THE SHAPE FIRST, THE GRID AFTER, and the two loops are split for that reason alone. move_floor
	# BAKES the occupancy grid — RoomContext snapshots shape.contains() for the whole room and never
	# re-reads it — so any shape change made after it is a change the grid does not know about.
	var lvl: int = z.get("level", 1)
	for k in range(lo, hi + 1):
		shape.set_level(Vector2i(k, row), lvl)
	for k: int in flights:
		# CHECKED, because the failure this hides is a raised deck nobody can reach. add_ramp refuses
		# a claimed tile and a slope past MAX_SLOPE and returns false either way, and set_ramp threw
		# that answer away — so the two guards above are the whole defence and a hole in them was
		# silent until a reachability BFS three passes later named seven rooms at once.
		if not shape.add_ramp(Vector2i(k, below), Vector2i(0, -1), 1, 1):
			push_error("TileProgram: the deck's flight at %s was refused after every guard passed"
					% Vector2i(k, below))
	# Raised and sloping tiles alike are claimed, so the 2-D searchers — cover, mounts, spawns,
	# clutter — keep off them. Anything meant to stand up there is placed by tile, and a tile now
	# knows its own height.
	for k in range(lo, hi + 1):
		claims.append(Vector2i(k, row))
	for k: int in flights:
		claims.append(Vector2i(k, below))

	# LIGHT THE WAY ITSELF. Mounts from RoomWeave sit on the room floor and would hang inside the
	# retaining wall; these ride the deck, which is also what makes a raised way read as somewhere
	# you are meant to go rather than as a ledge.
	for k in range(lo + 1, hi):
		if (k - lo) % 2 == 0:
			continue
		var at := shape.tile_centre(Vector2i(k, row))
		ctx.add_slot_at(RoomPlan.T_WALL_ANCHOR, at + Vector3(0.0, 0.0, RoomWeave.MOUNT_INSET))
	return true


## A RAISED END, WITH A WAY UP EITHER SIDE OF THE APPROACH TO IT.
##
## This is the shape the old flags could not describe, and it is a different thing from a walk: a
## walk runs ALONG a wall and you get onto it at its ends; an apse sits ACROSS the room's far end,
## centred on the axis you come down, and you climb it from either side of the way in. The room is
## aimed at it. That is why it is a zone with an affinity and two relations rather than a seventh
## boolean.
##
## THE MIDDLE COLUMN IS LEFT ALONE ON PURPOSE. Three columns of apse, flights under the outer two,
## and the middle one stays ordinary floor — so you walk straight up the centre, meet the raised end
## face on, and go up round it. Fill that column with a flight and the room becomes a staircase; fill
## it with cover and the sightline relation was for nothing.
static func _place_apse(rd: DungeonLayout.RoomData, ctx: RoomContext, z: Dictionary,
		relations: Array, claims: Array[Vector2i]) -> bool:
	var shape := ctx.shape
	var want: Vector2i = z.get("want", Vector2i(3, 1))
	var wide := maxi(want.x, 3)
	# Needs the far row, a row under it for the flights, and a row in front of that to arrive from.
	if shape.rows < 3 or shape.cols < wide:
		return false
	# REACH IS WHAT PUTS THE STAIRS IN, exactly as it is for a walk. Without it the apse is a shelf.
	var reach := false
	for r: Dictionary in relations:
		if r.get("to", "") == z.role and r.get("kind", "") == RoomProgram.R_REACH:
			reach = true
	if not reach:
		return false

	# EITHER END, FAR ONE FIRST, and this is the camera budget being spent rather than a taboo being
	# obeyed. Measured: of 36 churches, 22 had no apse at all because the FAR wall carried a door —
	# which is not bad luck, it is what a deep room is: you enter it from its short end, so its short
	# end is where the layout puts the way in. Refusing there and stopping meant the program shipped
	# in one room out of four.
	#
	# The near end costs something and the far end costs nothing: a far apse has its riser turned
	# toward the lens and occludes no floor, while a near one hides 0.90 m per level of whatever is
	# behind it. For a 3-tile apse that is 10.8 m2, about 2% of a room this size, against a 12%
	# budget — so it is affordable, and RoomShape.camera_legal is what says so rather than a rule of
	# thumb. Checked BEFORE committing, because a level once set is not cheap to take back.
	for attempt in 2:
		var row := 0 if attempt == 0 else shape.rows - 1
		var below := row + 1 if attempt == 0 else row - 1
		var back := 1 if attempt == 0 else -1
		if _try_apse(rd, ctx, z, relations, row, below, back, wide, claims):
			return true
	return false


## One end of the room. `below` is the row the flights stand in and `back` points from the apse down
## the room, which is what the sightline runs along.
static func _try_apse(rd: DungeonLayout.RoomData, ctx: RoomContext, z: Dictionary, relations: Array,
		row: int, below: int, back: int, wide: int, claims: Array[Vector2i]) -> bool:
	var shape := ctx.shape
	var centre := (shape.cols - 1) / 2

	# THE APSE SLIDES ALONG THE END WALL RATHER THAN INSISTING ON THE MIDDLE. Fixed to the centre
	# columns it landed in 9 of 36 churches, and the refuser was the far wall itself: a deep room is
	# entered from its short end, so that end is exactly where the layout likes to put a door, and
	# carving takes the corners of the same row. Sliding is the same answer the flights already give
	# to a blocked end, and the same one add_ramp gives to a slope that is too steep — move before
	# refusing, and refuse only when nothing fits.
	#
	# CLOSEST TO CENTRE WINS, so a room with the whole end wall free still reads as symmetrical and
	# only a room that cannot be symmetrical is not. The scan is left to right and strictly better
	# wins, so the choice is a property of the room rather than of the order columns were visited.
	var lo := -1
	var best := 1 << 30
	for start in range(0, shape.cols - wide + 1):
		var end := start + wide - 1
		var ok := true
		for k in range(start, end + 1):
			if not shape.is_solid(Vector2i(k, row)):
				ok = false
		if not ok or not RoomWeave.run_clear(rd, ctx, row, start, end):
			continue
		# The two flights, under the window's outer columns, and the floor they step down onto.
		for k in [start, end]:
			if not (shape.is_solid(Vector2i(k, below)) and shape.is_solid(Vector2i(k, below + 1))):
				ok = false
			elif not RoomWeave.run_clear(rd, ctx, below, k, k):
				ok = false
			elif not RoomWeave.run_clear(rd, ctx, below + 1, k, k):
				ok = false
		if not ok:
			continue
		var off: int = absi((start + end) - 2 * centre)
		if off < best:
			best = off
			lo = start
	if lo < 0:
		return false
	var hi := lo + wide - 1
	var mid := (lo + hi) / 2

	var lvl: int = z.get("level", 1)
	# WHAT THIS WOULD COST THE CAMERA, before any of it is committed. Only an apse at the near end
	# occludes anything — the far one's riser faces the lens — so this is zero on the first attempt
	# and a real number on the second.
	if back < 0:
		var hidden := float(wide) * RoomShape.TILE * float(lvl) * RoomShape.LEVEL_RISE 				/ tan(DungeonRoom.FRAME_PITCH)
		var area := float(shape.tile_count()) * RoomShape.TILE * RoomShape.TILE
		if hidden / maxf(area, 1.0) > RoomShape.MAX_HIDDEN:
			return false
	for k in range(lo, hi + 1):
		shape.set_level(Vector2i(k, row), lvl)
	for k in [lo, hi]:
		shape.set_ramp(Vector2i(k, below), Vector2i(0, -back))
	for k in range(lo, hi + 1):
		claims.append(Vector2i(k, row))
	for k in [lo, hi]:
		claims.append(Vector2i(k, below))

	# THE SIGHTLINE, as tiles. The middle column from the apse back down the room: the weave will
	# pre-collapse these to AISLE, which is what keeps cover out of the approach. Recorded rather
	# than enforced here, because WHAT stands on a tile is step 8's business and this is step 3.
	for r: Dictionary in relations:
		if r.get("to", "") != z.role or r.get("kind", "") != RoomProgram.R_SIGHT:
			continue
		var j := below
		while j >= 0 and j < shape.rows:
			if shape.is_solid(Vector2i(mid, j)):
				ctx.sightline.append(Vector2i(mid, j))
			j += back

	# One light on the apse itself, so the thing the room is aimed at is the thing you can see.
	ctx.add_slot_at(RoomPlan.T_WALL_ANCHOR,
			shape.tile_centre(Vector2i(mid, row)) + Vector3(0.0, 0.0, RoomWeave.MOUNT_INSET))
	return true


## A FLOOR SUNK BELOW THE ROOM, with a way out at either end.
##
## The first thing in this dungeon that goes DOWN, and it is the payoff for machinery M7 built and
## nothing had used: signed levels, the refusal to sink a tile on the outline, and the risers that
## retain the drop. Everything here is the same code the gallery and the apse go through — the only
## difference is the sign of the level.
##
## IT MUST BE GENUINELY INTERIOR, and that is a hard rule rather than an aesthetic. The shell wall is
## pinned at y = 0 to enclose the void under a RAISED perimeter tile; a sunken tile on the outline
## would leave nothing at all between its floor and that pin — a slot you see out of the level
## through, at eye height from this camera. RoomShape.set_level refuses it outright, so a pit that
## reached the wall would silently not sink; asking `on_outline` first is what makes the refusal a
## decision rather than a surprise.
##
## THE RAMPS ARE INSIDE THE PIT, which is the mirror of the apse and worth stating. A ramp tile sits
## at the LOW level and climbs toward `ramp_dir` — so a way UP out of a pit is a ramp on the pit's
## own end tile, climbing outward to the ground beside it. The same fixture, read the other way up.
static func _place_pit(rd: DungeonLayout.RoomData, ctx: RoomContext, z: Dictionary,
		relations: Array, claims: Array[Vector2i]) -> bool:
	var shape := ctx.shape
	var want: Vector2i = z.get("want", Vector2i(3, 1))
	var wide := maxi(want.x, 3)              # two ramps and at least one tile of floor between them
	var deep := maxi(want.y, 1)
	# A REACH RELATION OR NOTHING. A pit with no way out is not a room feature, it is a hole the
	# player falls into and the run ends — the same rule the walk and the apse answer to, and the one
	# place it is least survivable to get wrong.
	var reach := false
	for r: Dictionary in relations:
		if r.get("to", "") == z.role and r.get("kind", "") == RoomProgram.R_REACH:
			reach = true
	if not reach:
		return false

	# THE MIDDLE ROW, and only it. A pit may not touch the outline, so in the 5x3 room a prison lives
	# in there is exactly one row it can sit in and no choice to make. Searching outward from the
	# middle was written and then removed: it is correct, it costs nothing, and over 200 seeds it
	# changed not one dungeon — every pit that fits, fits in the middle. A search that never finds
	# anything the simple answer missed is a branch nobody is testing.
	var row := (shape.rows - 1) / 2
	var centre := (shape.cols - 1) / 2
	var lvl: int = z.get("level", -1)
	var lo := -1
	var best := 1 << 30
	for start in range(0, shape.cols - wide + 1):
		var end := start + wide - 1
		var ok := true
		for k in range(start, end + 1):
			for j in range(row, row + deep):
				var t := Vector2i(k, j)
				# Solid, interior, and free of a doorway — a door opening onto a 1.2 m drop is a
				# door you fall through.
				if not shape.is_solid(t) or shape.on_outline(t):
					ok = false
				# AND STILL ORDINARY FLOOR. The pit was the only zone that ever moved a level, so it
				# could assume every tile it looked at was at 0 and unclaimed. The colosseum's tiers
				# end that: a room now carries a raised deck AND a sunken middle, and the deck's
				# flights stand in the row below it — which in a shallow room is the row the pit
				# wants. Sinking a tile a ramp is installed on leaves the flight hanging over the
				# hole it used to climb out of, and add_ramp has no un-install, so this is a
				# rejection and not a repair.
				if shape.level_of(t) != 0 or shape.consumes_floor(t):
					ok = false
			if not RoomWeave.run_clear(rd, ctx, row, k, k):
				ok = false
		# THE GROUND EITHER SIDE is what the ramps climb out onto, so it has to exist and be flat.
		for side in [start - 1, end + 1]:
			var g := Vector2i(side, row)
			if not shape.is_solid(g) or shape.level_of(g) != 0:
				ok = false
		if not ok:
			continue
		var off: int = absi((start + end) - 2 * centre)
		if off < best:
			best = off
			lo = start
	if lo < 0:
		return false
	var hi := lo + wide - 1

	# A PIT CAN CUT THE ROOM IN TWO, and nothing else in this file can. A raised deck sits against a
	# wall and a bevel takes a corner; a pit is a hole ACROSS the middle, and the tiles either side of
	# it keep their level but lose their route — in a 5x3 room whose corner was carved, sinking the
	# middle row stranded the whole of row 0 while every tile in it was still perfectly good floor.
	#
	# So the levels go down provisionally and the room is walked before the ramps are committed. The
	# order matters: set_level is reversible and add_ramp is not — a fixture has no un-install — so
	# everything that can be taken back happens first.
	for k in range(lo, hi + 1):
		for j in range(row, row + deep):
			shape.set_level(Vector2i(k, j), lvl)
	if not _pit_keeps_room_whole(shape, lo, hi, row):
		for k in range(lo, hi + 1):
			for j in range(row, row + deep):
				shape.set_level(Vector2i(k, j), 0)
		return false

	# CLIMBING OUT, one at each end. `add_ramp` takes the rise as levels climbed FROM the tile's own
	# level, so a ramp in the floor of a pit climbing to the ground above is rise 1 like any other.
	shape.add_ramp(Vector2i(lo, row), Vector2i(-1, 0), 1, 1)
	shape.add_ramp(Vector2i(hi, row), Vector2i(1, 0), 1, 1)
	for k in range(lo, hi + 1):
		for j in range(row, row + deep):
			claims.append(Vector2i(k, j))
	return true


## Is every tile still walkable once this block is sunk and its two end ramps exist?
##
## The ramps are not installed yet — that is the point of asking now — so the two crossings they will
## create are added to the walk by hand. Everything else goes through RoomShape.walkable, which is
## the same function the suite's reachability check uses, so this cannot disagree with the assertion
## that would otherwise catch it three passes later.
static func _pit_keeps_room_whole(shape: RoomShape, lo: int, hi: int, row: int) -> bool:
	const SIDES: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var start := Vector2i(-1, -1)
	for t: Vector2i in shape.tiles():
		if shape.level_of(t) == 0:
			start = t
			break
	if start.x < 0:
		return false
	var mouths := {
		Vector2i(lo, row): Vector2i(lo - 1, row),
		Vector2i(hi, row): Vector2i(hi + 1, row),
	}
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var t: Vector2i = queue.pop_back()
		for side: Vector2i in SIDES:
			var n := t + side
			if seen.has(n) or not shape.is_solid(n):
				continue
			if not (shape.walkable(t, side) or mouths.get(t) == n or mouths.get(n) == t):
				continue
			seen[n] = true
			queue.append(n)
	return seen.size() == shape.tile_count()


## BEVEL SOME OF THE CONVEX CORNERS. Runs before anything is laid, so the corners are decided once
## and every later pass — the walls, the courses, the occupancy grid's no-floor bake — sees the same
## room.
##
## Keyed to the TILE, never to a counter: a room that gains a door somewhere far away must not
## re-bevel the corners it already had.
##
## THREE ROOMS ARE EXCLUDED OUTRIGHT, and none of them for looks:
##   * a stair room, whose walls ride the climb — a diagonal across a sloping run is a piece nobody
##     has authored and a seam the player would catch on;
##   * a templated room, whose interior was hand-placed against the square corner;
##   * any corner one of whose two walls carries a DOORWAY. That guard is the load-bearing one. The
##     surviving half-runs are 2 m and a doorway piece is 4 m, so a bevelled door corner would put a
##     2 m wall where an opening should be and seal the room.
static func _bevel_corners(rd: DungeonLayout.RoomData, ctx: RoomContext, climb: Vector3) -> void:
	if climb != Vector3.ZERO or rd.template_path != "":
		return
	var chance: float = RoomProgram.rules(RoomProgram.for_room(rd)).get(
			"chamfer", RoomProgram.CHAMFER_NONE)
	if chance <= 0.0:
		return
	for c: Dictionary in ctx.shape.corner_tiles():
		var tile: Vector2i = c["tile"]
		var d: Vector2i = c["out"]
		if RoomPlan.corner_has_door(rd, ctx, tile, d):
			continue
		if ctx.variant_roll("chamfer", ctx.shape.tile_centre(tile)) < chance:
			ctx.shape.set_chamfer(tile, d)



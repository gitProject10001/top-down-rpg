@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomProgram
extends Object
## WHAT A ROOM IS FOR, as pure data. The missing middle term between "this cell block is 3x2" and
## "there is a pillar at (-4, 3)".
##
## Rooms used to be furnished identically: a 3 m lattice of candidate spots, a random count of
## cover, a random pick of large-or-small, and sconces spread evenly round the perimeter. Every room
## in the crypt therefore said the same thing — "a space with some stuff in it" — and the only
## variation a player could read was the outline. A great hall furnished that way is a big room with
## scattered crates, not a refectory that once fed a garrison.
##
## A PROGRAM is the answer to "what was this place FOR", and it is chosen from what the layout
## already knows: the room's type (BOSS, TREASURE) and its module's kind (hall, gallery, vault).
## Both were decided long before anything is placed, which is what lets the arrangement be
## deliberate rather than sprinkled.
##
## NOTHING HERE MAY NAME A MESH, SCENE, MATERIAL, COLOUR OR LIGHT — the same rule RoomPlan lives
## under, and for the same two reasons: the headless suite plans hundreds of seeds with no art
## loaded, and a dungeon must be re-skinnable without anyone re-checking that the fights still work.
## "Refectory" is a statement about arrangement, not about furniture. The theme decides whether the
## thing standing in the aisle is a candelabra or a brazier.
##
## Deliberately a const Dictionary rather than a Resource: a Resource invites someone to hang this
## off DungeonTheme, and the moment that happens a reskin can change a fight — which is exactly what
## verify_dungeon's reskin suite exists to make impossible.

## How cover is arranged. The pattern IS the meaning; the pieces are the same either way.
const P_NONE := "none"                ## a breath, or an arena that must stay open
const P_FLANK := "flank"              ## two rows either side of a central aisle — a refectory
const P_COLONNADE := "colonnade"      ## evenly spaced pillars along the run — a gallery
const P_CORNERS := "corners"          ## pinned to the corners, middle left clear — an arena
const P_RING := "ring"                ## around a focal point — a treasury, a reliquary
const P_SCATTER := "scatter"          ## the old behaviour, for rooms with no story

## Where the light mounts go.
const L_AISLE := "aisle"              ## down the middle, between the rows
const L_PERIMETER := "perimeter"      ## on the walls, evenly
const L_FOCAL := "focal"              ## clustered around whatever the room is about
const L_DOORS := "doors"              ## flanking the ways in — a threshold

## Minimum mounts any program may emit. verify_dungeon requires every room to carry at least two
## lights, and a room the player fights in must be readable however dark the theme.
const MIN_LIGHTS := 2

## `lights` IS A COUNT FOR A SINGLE CELL, scaled by sqrt(floor area) in RoomWeave._mounts — a great
## hall is eight times a cell's floor and cannot be lit by a cell's worth of candles.
##
## These went up across the board once the crypt was flown rather than photographed. The room fill
## is deliberately dead (crypt.tres: "expect the middle of a large room to fall away into darkness
## between them; that is the intent"), which means the ONLY thing lighting a floor is how many
## flames stand on it. Fewer, brighter sources do not substitute: a candelabra rakes the floor at
## N.L 0.36 four metres out and 0.17 at nine, so range buys glare near the flame and nothing far
## from it. More sources is the only lever the art direction leaves open.
## WHETHER THE ROOM IS BUILT AROUND A RAISED PLATFORM. Vocabulary only — where the tile actually
## lands is TileProgram's problem, the same division as `cover` and `light`.
##
## D_CENTRE goes on the two programs that already have something at the middle to stand on it. It is
## deliberately NOT on "arena": that program's whole statement is corners-only with the middle left
## open for the boss's area attack, and putting a plinth in the way of it is a fight-design decision
## rather than an art one. The platform is climbable from all four sides, so nothing about enemy
## movement forbids it there — it is one word in this dict on the day someone wants it.
const D_NONE := "none"
const D_CENTRE := "centre"

## HOW OFTEN A CONVEX CORNER IS BEVELLED, as a probability per eligible corner. An arrangement
## statement, so it lives here beside the cover pattern rather than in the shape: the shape knows how
## to cut a corner, the program says whether this kind of room is the kind that has them.
##
## Deliberately not on "arena" or "threshold". A bevelled corner takes 2 m2 out of a corner, and the
## boss arena's whole rule is that the fight has room in it; the entrance is the first thing anyone
## sees of the dungeon and should read as square and built rather than as eroded.
const CHAMFER_NONE := 0.0

## WHETHER THE ROOM HAS A RAISED WALKWAY along one of its long walls. On the two programs whose
## rooms are big enough to give up a 4 m strip and still be a room: a refectory (the halls) and a
## colonnade (the galleries). A treasury or a reliquary is built around ONE object in the middle and
## already has its plinth; putting a gallery round the edge as well would leave neither any air.
const G_NONE := "none"
const G_WALL := "wall"

# --- THE ZONE GRAPH ---------------------------------------------------------------------------
#
# `gallery` and `dais` above are FLAGS: one boolean per feature, and a pass somewhere else that
# knows what that feature means. Every kind of level change was therefore its own mechanism, and a
# room could say "I have a gallery" but never "I am a church, so I need somewhere people gather, an
# elevated place to look at, and a way to reach it".
#
# A ZONE is a part of the room set aside for a purpose, possibly at another height. A RELATION is
# something that must be true BETWEEN two zones. Together they are the room's program as a graph,
# and the tile layer DERIVES the floor, the walls and the stairs from it — which is the difference
# between describing a feature and describing an intent.
#
# The two flags stay for now and are the source of truth for the zones the shipped programs get;
# TileProgram reads the zones. They come out when a program ships that the flags cannot express.
#
# NOTHING HERE NAMES A TILE OR A COORDINATE. A zone says how big it wants to be and what it wants to
# be near; WHERE it lands is TileProgram's problem, exactly as `cover` says the pattern and
# RoomWeave says the position.

## What a zone is FOR. Roles, not art: a walk is a raised way along a wall whether the theme builds
## it as a gallery, a rampart or a choir loft.
const Z_GROUND := "ground"            ## the room's own floor. Implicit, always present, always 0
const Z_WALK := "walk"                ## a raised way along a wall — today's gallery
const Z_PLINTH := "plinth"            ## a small platform to stand the room's subject on
const Z_APSE := "apse"                ## a raised END of the room, the thing the room is aimed at
const Z_NAVE := "nave"                ## the floor you cross to reach it
const Z_PIT := "pit"                  ## floor SUNK below the room — an oubliette, an arena floor

## What a zone wants to be NEAR. The affinity is the whole of a zone's placement preference, and it
## is deliberately coarse: a zone that could say "at tile (3, 0)" would be a coordinate in a file
## that must not contain one.
const A_WALL := "wall"                ## against a long wall, as far from the camera as it can get
const A_CENTRE := "centre"            ## the middle of the room
const A_END := "end"                  ## across the far end, centred on the room's own axis

## What must be true between two zones.
const R_REACH := "reach"              ## a body must be able to walk from one to the other. Across a
                                      ## level difference this IMPLIES a ramp — that is the point
const R_SIGHT := "sightline"          ## the tiles between them stay clear


## The zones and relations a program asks for, derived from its flags while the flags are still the
## source of truth. A function rather than more entries in PROGRAMS, so there is ONE statement of
## what a gallery is instead of the same three lines copied onto every program that has one.
static func zones_of(name: String) -> Array:
	var r := rules(name)
	# A PROGRAM MAY DECLARE ITS OWN, and that is the vocabulary paying for itself. The flags below
	# can say "this room has a gallery" and cannot say "this room is aimed at something raised at its
	# far end, which you approach down the middle and climb from either side" — so a program that
	# means the second writes it out, and the flags stay for the ones the flags can express.
	if r.has("zones"):
		return r["zones"]
	var out: Array = []
	if r.get("gallery", G_NONE) == G_WALL:
		# WANTS at least MIN_GALLERY tiles of length and one of depth. `want` is a floor, not a
		# target: the walk takes the longest run it can find that clears the doors, because a
		# gallery down part of a wall is still a gallery and demanding the whole wall cost the
		# feature almost entirely.
		out.append({"role": Z_WALK, "level": 1, "affinity": A_WALL,
				"want": Vector2i(RoomWeave.MIN_GALLERY, 1)})
	if r.get("dais", D_NONE) == D_CENTRE:
		# LEVEL 0 AND A RISE, which is not a contradiction. A plinth is 0.6 m — under
		# MapPainter.FLOOR_MAX_Y so the map still reads it as floor, and under the step ring's 0.8 so
		# a body can walk up it from any side. That is a different thing from a storey and the zone
		# says so rather than pretending it is one.
		out.append({"role": Z_PLINTH, "level": 0, "affinity": A_CENTRE,
				"want": Vector2i.ONE, "rise": RoomPlan.DAIS_RISE})
	return out


## The relations between them. REACH from the ground to anything at another level is the one that
## earns its keep: it is what turns "the walk is a level up" into "there are stairs", without the
## program ever saying the word.
static func relations_of(name: String) -> Array:
	var r := rules(name)
	if r.has("relations"):
		return r["relations"]
	var out: Array = []
	for z: Dictionary in zones_of(name):
		if int(z.get("level", 0)) != 0:
			out.append({"from": Z_GROUND, "to": z.role, "kind": R_REACH})
	return out

const PROGRAMS := {
	"refectory": {
		"cover": P_FLANK, "light": L_AISLE,
		"large": 0.25, "density": 0.55, "lights": 6,
		"dais": D_NONE,
		"chamfer": 0.35,
		"gallery": G_WALL,
	},
	"colonnade": {
		"cover": P_COLONNADE, "light": L_AISLE,
		"large": 0.9, "density": 0.5, "lights": 5,
		"dais": D_NONE,
		"chamfer": 0.5,
		"gallery": G_WALL,
	},
	# A LONG ROOM YOU GO THROUGH rather than one you are in — a deep gallery with a way out at both
	# ends. Columns down its length like a colonnade, lit along the middle because the middle is the
	# route, and NO raised walk: the walls a walk could run along are its sides, and the row the walk
	# pass builds on is its short end.
	"passage": {
		"cover": P_COLONNADE, "light": L_AISLE,
		"large": 0.75, "density": 0.4, "lights": 5,
		"dais": D_NONE,
		"chamfer": 0.2,
		"gallery": G_NONE,
	},
	"treasury": {
		"cover": P_RING, "light": L_FOCAL,
		"large": 0.5, "density": 0.4, "lights": 5,
		"dais": D_CENTRE,
		"chamfer": 0.6,
		"gallery": G_NONE,
	},
	"reliquary": {
		"cover": P_RING, "light": L_FOCAL,
		"large": 0.7, "density": 0.35, "lights": 4,
		"dais": D_CENTRE,
		"chamfer": 0.6,
		"gallery": G_NONE,
	},
	# THE CHURCH, and it is the first program whose shape the flags could not have described. A nave
	# you cross, an apse raised a level at the far end, a way up at either side of it, and a clear
	# line from the door to the thing the room is about. Every one of those is a zone or a relation;
	# none of them is a feature flag, and the tile layer derives the floor, the walls and the stairs
	# from them without the program naming any of the three.
	#
	# THE SIGHTLINE IS NOT DECORATION. It is what stops the cover pass filling the middle of the nave
	# and turning a processional space into a room with an obstacle course in it — the same
	# machinery the aisle already uses, aimed by a relation instead of by the room's long axis.
	"church": {
		"cover": P_FLANK, "light": L_FOCAL,
		"large": 0.35, "density": 0.42, "lights": 6,
		"dais": D_NONE,
		"chamfer": 0.4,
		"gallery": G_NONE,
		"zones": [
			{"role": Z_NAVE, "level": 0, "affinity": A_CENTRE, "want": Vector2i(3, 2)},
			# REQUIRED: a church without an apse is not a church. Every other zone in this file is
			# decoration a room is better for having — a gallery's raised walk, a prison's
			# oubliette — and a room that cannot fit one is still honestly what it says it is. This
			# one IS the statement, so a room that cannot fit it stops making the claim.
			{"role": Z_APSE, "level": 1, "affinity": A_END, "want": Vector2i(3, 1), "required": true},
		],
		"relations": [
			{"from": Z_NAVE, "to": Z_APSE, "kind": R_REACH},
			{"from": Z_NAVE, "to": Z_APSE, "kind": R_SIGHT},
		],
	},
	# THE TWO THE LAYOUT SEATS BY QUOTA rather than derives from a shape. Flags only for now — a
	# prison's cell block and a colosseum's tiers are zones, and they land in their own milestone so
	# that the hash movement from ASSIGNING a purpose stays separable from the hash movement from
	# ZONING one.
	#
	# A PRISON reads as a row of cells off a passage: small cover down both flanks at high density,
	# lit from the walls rather than from the middle, and no bevels — a gaol is built square.
	"prison": {
		"cover": P_FLANK, "light": L_PERIMETER,
		"large": 0.1, "density": 0.75, "lights": 5,
		"dais": D_NONE,
		"chamfer": CHAMFER_NONE,
		"gallery": G_NONE,
		# THE OUBLIETTE. A gaol's statement is a floor you can be put UNDER, and it is the first
		# thing in this dungeon that sinks rather than rises — M7 built signed levels, the rule that
		# a sunken region may never touch the outline, and the stacked risers that retain it, and
		# until now nothing had ever asked for one.
		"zones": [{"role": Z_PIT, "level": -1, "affinity": A_CENTRE, "want": Vector2i(3, 1)}],
		"relations": [{"from": Z_GROUND, "to": Z_PIT, "kind": R_REACH}],
	},
	# A COLOSSEUM is the opposite statement: the middle must stay clear because it is where the fight
	# happens, so the mass goes to the corners and the light goes round the edge. Distinct from
	# `arena` by being brighter and heavier — an arena is one boss, this is a crowd.
	"colosseum": {
		"cover": P_CORNERS, "light": L_PERIMETER,
		"large": 0.95, "density": 0.35, "lights": 8,
		"dais": D_NONE,
		"chamfer": 0.25,
		"gallery": G_NONE,
		# HOW MANY TILES OF WALL COME OUT AS ONE PIECE. A colosseum is the room whose walls ARE the
		# statement — an arcade running round it rather than a row of panels — and a face can only
		# carry a batter or a bay pattern across a tile joint if the piece spans the joint.
		"wall_run": 4,
		# THE ARENA FLOOR, sunk so the room reads as something you look INTO. Same zone kind as the
		# prison's oubliette and deliberately so — one mechanism, two statements, which is the whole
		# argument the fixture layer already makes about bevels and ramps. It is wider because a
		# colosseum has room to be, and because a pit you fight in has to be a place rather than a
		# hole.
		#
		# SINKING IS ALSO THE CHEAP DIRECTION FOR THIS CAMERA. A raised mass hides the floor behind
		# it; a pit's near rim hides part of the PIT, which is a smaller loss and one the player can
		# see the top of. RoomShape.camera_legal is what says so, and it is checked here like
		# anywhere else.
		# THE TIERS, and they are what makes this a colosseum rather than a room with a hole in it.
		# The arena alone gave the room two levels; banked seating over it gives three, and the
		# three are the statement: you stand above, the fight is below, and the ground between is
		# where you cross. Same mechanism as the gallery's raised way — one deck along one wall,
		# reached by a flight at each end — asked for at a different level and for a different
		# reason, which is the argument this whole layer keeps making.
		#
		# THE FAR WALL, WHICH IS FREE. _place_walk builds on row 0, the -Z side, and M7 measured
		# that a far-row deck costs the camera exactly nothing: everything it hides is already
		# behind it. Raising near +Z would have to be paid for out of MAX_HIDDEN; this does not.
		#
		# THE ORDER IS LOAD-BEARING. The pit goes first because it is the room's subject and it has
		# exactly one row it can sit in, while the deck can slide along its own row. Placed the
		# other way round in a shallow room the deck takes the middle row's flights and the arena
		# is refused — the same feature, worse room, for no reason but the order of two lines.
		"zones": [
			{"role": Z_PIT, "level": -1, "affinity": A_CENTRE, "want": Vector2i(5, 1)},
			{"role": Z_WALK, "level": 1, "affinity": A_WALL, "want": Vector2i(4, 1)},
		],
		"relations": [
			{"from": Z_GROUND, "to": Z_PIT, "kind": R_REACH},
			{"from": Z_GROUND, "to": Z_WALK, "kind": R_REACH},
		],
	},
	"arena": {
		"cover": P_CORNERS, "light": L_PERIMETER,
		"large": 1.0, "density": 0.3, "lights": 6,
		"dais": D_NONE,
		"chamfer": CHAMFER_NONE,
		"gallery": G_NONE,
	},
	"threshold": {
		"cover": P_NONE, "light": L_DOORS,
		"large": 0.0, "density": 0.0, "lights": 3,
		"dais": D_NONE,
		"chamfer": CHAMFER_NONE,
		"gallery": G_NONE,
	},
	"chambers": {
		"cover": P_SCATTER, "light": L_PERIMETER,
		"large": 0.55, "density": 0.45, "lights": 5,
		"dais": D_NONE,
		"chamfer": 0.3,
		"gallery": G_NONE,
	},
}


## Which program a room runs. TYPE wins over kind, because a boss arena is an arena whatever module
## shape it happened to land on — the fight is the room's purpose and everything else is decoration.
##
## THERE IS NO PROGRAM FOR A STAIRWELL, deliberately. RoomPlan never weaves one: everything in a
## stair room rides the flight, and the weave works on a flat tile grid. Declaring a "flight"
## program that nothing could ever reach would be vocabulary with no implementation — the same
## defect as DungeonLayout's unused EdgeType.DOOR.
static func for_room(rd: DungeonLayout.RoomData) -> String:
	# THE FIELD IS THE RECORD OF WHAT THE LAYOUT DECIDED; the classifier is the decision. Reading the
	# field is what lets a purpose depend on the room's NEIGHBOURS, which no function of one room can.
	#
	# The fallback is not dead weight: verify_dungeon hand-builds RoomData objects that never went
	# through generate(), and they must still resolve to the same program rather than to "".
	return rd.purpose if rd.purpose != "" else RoomPurpose.classify(rd)


static func rules(name: String) -> Dictionary:
	return PROGRAMS.get(name, PROGRAMS["chambers"])

@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomPurpose
extends Object
## WHAT A ROOM WAS FOR — the semantic axis, decided at the LAYOUT and recorded on the room.
##
## THREE AXES, NOT ONE, and each is decided at a different moment for a different reason:
##
##   `kind`     GEOMETRY — which module was placed. Fixed earliest, at the module roll, before the
##              room's position is even known. A church and a prison can share a shape.
##   `type`     MISSION ROLE — START / COMBAT / BOSS / TREASURE / STAIR. Fixed last, after both BFS
##              passes, and it drives invariants the suite asserts: the boss is the farthest
##              dead-end, the treasure is a dead-end, the key is reachable without its own lock.
##   `purpose`  MEANING — what the place was for. This file.
##
## WHY IT HAD TO MOVE UP HERE. `RoomProgram.for_room(rd)` is a pure function of ONE room: it reads
## `rd.type`, `rd.kind` and whether the room is deeper than it is wide, and returns a name. A
## function of one room structurally cannot express a constraint that involves TWO rooms ("a prison
## is never next to a church") or ALL of them ("at least one prison per dungeon"). The limitation was
## never a lack of vocabulary — it was a lack of ARITY. Deciding purpose where the whole graph is
## visible is the whole of the fix.
##
## `type` PINS `purpose` WHERE THE MISSION DEPENDS ON IT. START, BOSS and TREASURE keep the purposes
## they have always derived. That is not tidiness: as long as nothing here ever writes `type`, this
## layer is STRUCTURALLY INCAPABLE of breaking a mission invariant, because every one of those
## assertions keys off `type` alone. A guarantee by construction beats one by inspection.


## THE PURPOSES A QUOTA CAN SEAT, and what a room must be for one to live in it. This is the DOMAIN
## of the constraint problem: purpose p is legal in room r iff r satisfies p's requirements.
##
## `hosts` IS ORDERED BY PREFERENCE, and that ordering is doing real work rather than being tidy. A
## prison can live in a cell or a vault — but a vault is the only host `reliquary` has and it occurs
## about nine times in forty seeds, while cells are the most common room in the dungeon. Taking the
## vault would quietly delete a program; taking a cell costs nothing anybody can name. Scarcity of
## the host, not suitability of the room, is what decides the order.
##
## `min`/`max` are the GLOBAL rule — the integral one, a statement about the whole dungeon. Two
## strengths, and the difference is measured rather than chosen:
##
##   REQUIRED (min 1)      unmet means the layout is wrong. `prison` qualifies: a cell or vault at
##                         depth 2 is present in 399 of 400 seeds, so demanding one is a rule.
##   OPPORTUNISTIC (min 0) seated where a host exists, never a reason to reject a dungeon.
##                         `colosseum` must start here: a hall appears in only 49% of seeds, so
##                         demanding one would reject half of all dungeons — and halls are also the
##                         only host `refectory` has, so a hard quota would starve it.
const CATALOGUE := {
	"prison": {
		"hosts": ["cell", "vault"],
		"min_dist": 2,                ## a gaol is not the first room off the entrance
		"min_doors": 1,
		"min": 1, "max": 1,
	},
	"colosseum": {
		# A HALL OR A WIDE GALLERY, because both are rooms you stand IN rather than walk DOWN.
		# `not_deep` is the same proportion test that splits a nave from a colonnade, and it is what
		# keeps a colosseum out of a deep gallery — a room read from its short end is an approach to
		# something, which is the opposite statement.
		#
		# Halls alone made it too rare to rely on: a hall exists in 49% of seeds, is the only host
		# `refectory` has, and most dungeons have exactly one — so with the "may not delete another
		# purpose" rule it seated in 7% of seeds and turned up twice in the forty the weave suite
		# checks. Wide galleries are abundant (colonnade has 482 rooms in 400 seeds), so drawing from
		# them costs a program nothing and stops this one living on the edge of its own guard.
		"hosts": ["hall", "gallery"],
		"not_deep": true,
		"min_dist": 1,
		"min_doors": 2,               ## you are meant to be able to be cut off in it
		"min": 0, "max": 1,
	},
}

## THE LOCAL RULE — the differential one, a statement about two rooms that share a door. Symmetric,
## so it is stored once as a pair rather than twice as a property of each purpose.
##
## A prison beside a church is the example, and it is not arbitrary: they are the two purposes in
## the catalogue that claim a whole room for a NON-COMBAT idea, and putting them adjacent reads as
## one building that cannot decide what it is.
const APART := [["prison", "church"]]

## What a room becomes when it must STOP being something. Shape-legal by construction: a church is a
## DEEP gallery, and a passage is what a deep gallery is when it is not a nave — columns down its
## length and no raised walk. Demoting to `colonnade` was the first answer and it was wrong for the
## same reason the classifier was: a colonnade declares a walk along a long wall, and a deep room's
## long walls are its sides.
const DEMOTE_TO := {"church": "passage"}

## PURPOSES THAT MAY NOT SIT BESIDE THEMSELVES. The local rule turned on its own kind: three rooms in
## a row all announcing the same thing is the variety failure the whole purpose layer exists to
## avoid, and it reads worse than any single wrong label because the repetition is what the eye
## picks up.
##
## Only `church` needs naming. A prison and a colosseum are capped at one per dungeon, so they cannot
## twin; `chambers` is the residue and repeating it says nothing, which is the point of a residue.
const NO_TWIN := ["church"]


## Is this pair forbidden from sharing a door?
static func apart(a: String, b: String) -> bool:
	for pair: Array in APART:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


## Could this room host this purpose? Shape, depth and degree — everything the requirement names.
## Does NOT consider neighbours: that is the local rule, and it is the seater's business because it
## depends on what the other rooms have already been given.
static func fits(rd: DungeonLayout.RoomData, id: String) -> bool:
	if not CATALOGUE.has(id):
		return false
	var req: Dictionary = CATALOGUE[id]
	# ONLY A COMBAT ROOM. START, BOSS, TREASURE and STAIR have their purpose pinned by `type`,
	# because every mission assertion in the suite keys off `type` alone — so as long as nothing here
	# can seat a purpose on one, this layer is structurally incapable of breaking the mission.
	if rd.type != DungeonLayout.RoomType.COMBAT:
		return false
	if not (req["hosts"] as Array).has(rd.kind):
		return false
	if bool(req.get("not_deep", false)) and rd.size.z > rd.size.x:
		return false
	if rd.dist < int(req["min_dist"]):
		return false
	return rd.lateral_edges() >= int(req["min_doors"])


## How much a purpose prefers this room, lower is better — the index of its host in the preference
## list. See `hosts` above for why that ordering matters.
static func host_rank(rd: DungeonLayout.RoomData, id: String) -> int:
	return (CATALOGUE[id]["hosts"] as Array).find(rd.kind)


## Does this room have a door at BOTH of its short (z) ends? See the gallery arm of classify().
static func _both_ends_open(rd: DungeonLayout.RoomData) -> bool:
	var toward := false
	var away := false
	for d: Vector2i in rd.door_dirs():
		if d.y > 0:
			toward = true
		elif d.y < 0:
			away = true
	return toward and away


## Today's derivation, moved here verbatim and still a pure function of one room. Quotas and
## adjacency come later and are the reason this file exists; at this point it is only a relocation,
## and verify_dungeon holds it to an independent copy of the old table to prove it.
##
## A STAIRWELL HAS NO PURPOSE, and saying so is the correction. This returned a purpose for one on
## the grounds that nothing read it — true of the GENERATOR, and false the moment the layout bench
## started drawing the field. `_add_stairs` re-types a LEAF, and that leaf can be a deep gallery, so
## the old answer put the word "church" on a staircase: a room whose whole floor is one flight, which
## can never have an apse and is never even offered the chance, because zone() hands a climbing room
## straight back.
##
## "Nothing reads it" is a claim about today's callers, and it stopped being true one milestone after
## it was written. An empty purpose is the honest answer and every caller already handles it —
## rules() falls back, the bench draws nothing, and the zone accounting asks for nothing.
static func classify(rd: DungeonLayout.RoomData) -> String:
	if rd.type == DungeonLayout.RoomType.STAIR:
		return ""
	match rd.type:
		DungeonLayout.RoomType.BOSS:
			return "arena"
		DungeonLayout.RoomType.TREASURE:
			return "treasury"
		DungeonLayout.RoomType.START:
			return "threshold"
	match rd.kind:
		"hall":
			# The big one. A 2x2 or 3x2 room with a central aisle, benches down both sides and
			# candelabra along the middle reads as somewhere an army ate; the same room with
			# scattered crates reads as a warehouse.
			return "refectory"
		"gallery":
			# DEEP OR WIDE, and the two are different rooms. A gallery longer in Z than in X is read
			# from its short end: you come in and look down its length, which is a NAVE, and the far
			# end is where the thing the room is about goes. Turn it ninety degrees and you walk
			# ALONG it instead, and a row of columns is the statement rather than an apse.
			#
			# ...AND A NAVE NEEDS AN END TO AIM AT. A deep gallery with a door at BOTH short ends is
			# not a church, it is a passage — you come in one end and leave by the other, and there
			# is no far wall to put anything against. Measured: of 173 rooms classified as churches,
			# only 76 could actually place an apse, and 58 of the 97 failures were exactly this. The
			# rest of the dungeon called them churches anyway, which is a label claiming something
			# the room does not have.
			#
			# Checkable HERE because it is a fact about the room's own edges, which is all the
			# classifier ever gets. Whether three specific tiles are solid is not — that is the
			# shape's business, and the residue it leaves is handled where the shape is known.
			if rd.size.z <= rd.size.x:
				return "colonnade"
			# A DEEP GALLERY OPEN AT BOTH ENDS IS A PASSAGE, not a plainer colonnade. Sending it to
			# `colonnade` was the first answer and it moved the lie rather than removing it: a
			# colonnade declares a raised walk along its long wall, and a deep room's long walls are
			# its SIDES — the row a walk is built on is its short end. Those rooms asked for a walk
			# 44 times and got 3, which is the same shape of complaint as a church with no apse.
			# A passage declares no walk, so it is honestly the whole of what it is.
			return "passage" if _both_ends_open(rd) else "church"
		"vault":
			return "reliquary"
	return "chambers"

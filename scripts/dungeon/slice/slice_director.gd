class_name SliceDirector
extends Node
## Puts the vertical slice's beats into a generated dungeon, by ROOM ROLE rather than by position.
##
## The layout is procedural and the beats are authored, and this is where those two facts are made
## to agree. It never asks "which room is at (1,0,-2)" — it asks for the start, the first fight, the
## treasury, the room on the near side of the locked door, the boss — and the generator's own
## classification answers. Change the seed and the beats move with it, in the same order.
##
## SIX RULES govern everything built here, each one answering a live assertion in verify_dungeon:
##   1. every StaticBody3D sits on collision_layer 1
##   2. no Light3D at all (a lit prop that is not a StaticBody3D counts as a "mount" and has to
##      stand 3 m clear of every doorway — emissive materials sidestep the whole question)
##   3. nothing casts a shadow
##   4. no mesh reaches higher than 3.35 m above the floor, or the cutaway sweep wants to know why
##   5. positions come from the LAYOUT and the room's own occupancy grid, never from a themed
##      piece's measured size — the reskin suite fingerprints every body's position across themes
##   6. nothing below the floor, and gi_mode disabled on every mesh
##
## None of this actually runs in the suites — it is behind DungeonGenerator._furnish, which only a
## subclass overrides — but the rules are what make it safe to stop being behind that hook one day.

## QUERY BOXES ARE THE PROP'S ACTUAL FOOTPRINT, and getting this wrong is not a near miss.
##
## Measured: a room is 12 m deep with a 2 m door lane at each end, so the free floor is a WIDE,
## SHALLOW band. Asking for a square 2.4 x 2.4 (3.1 x 3.1 once the margin is on) fails in most
## rooms while 3.6 x 2.0 — a bigger box by area — succeeds, purely because it is shallower. The
## first version asked in squares, was refused everywhere, and fell through to the room centre.
##
## So each of these is the thing's real plan-view size, and nothing asks for depth it does not use.
const PROBE_SIZE := Vector2(1.2, 1.2)      ## a trigger volume; it only needs to be somewhere walkable
const WALL_SIZE := Vector2(3.4, 1.0)       ## 3.4 wide, 0.45 deep — a wall, not a block
const GATE_SIZE := Vector2(2.6, 1.0)
const LEDGE_SIZE := Vector2(2.6, 1.4)
const PROP_SIZE := Vector2(1.4, 1.4)       ## warden, lever: a person and a post
const PEDESTAL_SIZE := Vector2(1.6, 1.6)


func furnish(gen: Node3D, layout: DungeonLayout, room_nodes: Dictionary) -> void:
	var rooms := _by_role(layout, room_nodes)

	# Every room, always: the fight ends and something is offered. Connected rather than built now —
	# see BoonPedestal's header for why that matters.
	for anchor: Vector3i in room_nodes:
		var room: DungeonRoom = room_nodes[anchor]
		room.cleared.connect(_on_room_cleared.bind(room))

	_furnish_start(rooms.start)

	# THE BEATS CHOOSE THEIR ROOM, rather than being handed one. Measured: seed 42's nearest combat
	# room comes out of the dresser with a free cell count of exactly zero, and forcing the cracked
	# wall into it put a wall across a doorway. Preference order first, then whichever candidate can
	# actually house the thing.
	var used: Array = []
	var wall_room := _furnish_cracked_wall(rooms.combat, used)
	if wall_room:
		used.append(wall_room)
	var ledge_room := _furnish_spectral(_reversed(rooms.combat), used)
	if ledge_room:
		used.append(ledge_room)

	var vault: Array = []
	if rooms.treasure:
		vault.append(rooms.treasure)
	vault.append_array(rooms.combat)
	_furnish_tether(vault, used)

	_furnish_warden(layout, room_nodes)
	if rooms.boss:
		_furnish_boss(rooms.boss)


static func _reversed(rooms: Array) -> Array:
	var out := rooms.duplicate()
	out.reverse()
	return out


## Sort the live rooms by what the layout says they are. `room.data` is the layout row the room was
## built from, so this needs no reverse lookup and cannot disagree with the generator.
func _by_role(layout: DungeonLayout, room_nodes: Dictionary) -> Dictionary:
	var out := {"start": null, "boss": null, "treasure": null, "combat": []}
	var combat: Array = []
	for anchor: Vector3i in room_nodes:
		var room: DungeonRoom = room_nodes[anchor]
		if room.data == null:
			continue
		match room.data.type:
			DungeonLayout.RoomType.START:
				out.start = room
			DungeonLayout.RoomType.BOSS:
				out.boss = room
			DungeonLayout.RoomType.TREASURE:
				out.treasure = room
			DungeonLayout.RoomType.COMBAT:
				combat.append(room)
	# By distance from the entrance, so "the first fight" means the first one you will actually
	# reach rather than whichever came first out of a Dictionary.
	combat.sort_custom(func(a: DungeonRoom, b: DungeonRoom) -> bool:
		return a.data.dist < b.data.dist)
	out.combat = combat
	return out


# --- the beats ----------------------------------------------------------------------------------

## The start room teaches the card exists, with no dice behind it. A check you can fail is a poor
## introduction to a mechanic; this one just speaks.
##
## Placed AWAY from the return portal (which sits at +Z 4), so it fires on the walk out rather than
## in the first half-second of the descent.
func _furnish_start(room: DungeonRoom) -> void:
	if room == null:
		return
	var probe := TraitProbe.new()
	probe.name = "StartProbe"
	probe.which = 2                                  # Traits.Attr.PERCEPTION
	probe.passive = true
	probe.on_success = "The air moves against you, which means it is coming from somewhere, which " \
			+ "means this place is not sealed. Somewhere below, something is open."
	room.add_child(probe)
	probe.position = _spot(room, Vector3(0, 0, -minf(room.footprint.z * 0.5 - 4.0, 6.0)), PROBE_SIZE)


## Logic reads the wall; the hammer opens it. The check does not gate the wall — a player who fails
## it can still notice the crack and swing at it — it gates being TOLD, which is the honest version
## of an observation skill.
func _furnish_cracked_wall(candidates: Array, used: Array) -> DungeonRoom:
	var room: DungeonRoom = null
	var at := NOWHERE
	for c: DungeonRoom in candidates:
		if c in used:
			continue
		var spot := _try_spot(c, Vector3(0, 0, -c.footprint.z * 0.5 + 2.2), WALL_SIZE)
		if spot != NOWHERE:
			room = c
			at = spot
			break
	if room == null:
		return null
	room.plan.reserve(at, WALL_SIZE)

	var wall := CrackedWall.new()
	wall.name = "CrackedWall"
	room.add_child(wall)
	wall.position = at

	# The prize stands where the wall stood: there is no room BEHIND a wall that is flush with the
	# masonry, and collapsing it to reveal what it was covering reads exactly the same.
	var prize := InsightPickup.new()
	prize.name = "VaultPrize"
	prize.hidden = true
	prize.insight = 4
	prize.grants_conviction = "rationalist_delusion"
	prize.grants_tool = "Sunfire Lantern"
	prize.flavour = "A lantern, still warm. Somebody was down here recently enough to matter."
	room.add_child(prize)
	prize.position = at + Vector3(0, 0, -0.9)
	wall.reveal_path = wall.get_path_to(prize)

	var probe := TraitProbe.new()
	probe.name = "CrackProbe"
	probe.which = 0                                  # Traits.Attr.LOGIC
	probe.difficulty = "medium"
	probe.check_id = "crack_%d_%d" % [room.cell.x, room.cell.z]
	probe.on_success = "That is not settling. Settling cracks run with the load — this one runs " \
			+ "ACROSS it, and it is venting cold air. There is a space behind that wall, and " \
			+ "somebody bricked it up in a hurry."
	probe.on_fail = "Cracked masonry. Everything down here is cracked masonry. You are, you " \
			+ "suspect, being asked to have an opinion about a wall."
	room.add_child(probe)
	probe.position = _spot(room, at + Vector3(0, 0, 3.0), PROBE_SIZE)
	return room


## The lantern's puzzle: a ledge that is not there until it is lit, with a tool standing on it.
func _furnish_spectral(candidates: Array, used: Array) -> DungeonRoom:
	var room: DungeonRoom = null
	var at := NOWHERE
	for c: DungeonRoom in candidates:
		if c in used:
			continue
		var spot := _try_spot(c, Vector3(c.footprint.x * 0.5 - 3.5, 0, 0), LEDGE_SIZE)
		if spot != NOWHERE:
			room = c
			at = spot
			break
	if room == null:
		return null
	room.plan.reserve(at, LEDGE_SIZE)

	var deck := SpectralNode.new()
	deck.name = "SpectralLedge"
	deck.deck = Vector3(2.6, 0.3, 2.6)
	room.add_child(deck)
	deck.position = at + Vector3(0, 0.15, 0)

	var prize := InsightPickup.new()
	prize.name = "LedgePrize"
	prize.hidden = true
	prize.insight = 4
	prize.grants_tool = "Shatter Hammer"
	prize.flavour = "Heavier than it has any right to be. You like it immediately."
	deck.add_child(prize)
	prize.position = Vector3(0, 0.2, 0)

	var probe := TraitProbe.new()
	probe.name = "LedgeProbe"
	probe.which = 2                                  # PERCEPTION
	probe.difficulty = "easy"
	probe.check_id = "ledge_%d_%d" % [room.cell.x, room.cell.z]
	probe.on_success = "The dust in this corner is falling wrong. It lands on nothing, at about " \
			+ "knee height, and stops. There is a floor there that has decided not to be seen."
	probe.on_fail = "A corner. Dust. You have looked at a great deal of dust today."
	room.add_child(probe)
	probe.position = _spot(room, at + Vector3(-3.5, 0, 0), PROBE_SIZE)
	return room


## The treasury is pre-cleared by the generator, so nothing interrupts the one puzzle in the run
## that asks you to stand still and think about geometry.
func _furnish_tether(candidates: Array, used: Array) -> DungeonRoom:
	var room: DungeonRoom = null
	var gate_at := NOWHERE
	for c: DungeonRoom in candidates:
		if c in used:
			continue
		var spot := _try_spot(c, Vector3(0, 0, c.footprint.z * 0.5 - 3.0), GATE_SIZE)
		if spot != NOWHERE:
			room = c
			gate_at = spot
			break
	if room == null:
		return null
	room.plan.reserve(gate_at, GATE_SIZE)

	var gate := SliceGate.new()
	gate.name = "VaultGate"
	room.add_child(gate)
	gate.position = gate_at

	var prize := InsightPickup.new()
	prize.name = "TreasuryPrize"
	prize.insight = 6
	prize.grants_conviction = "heroic_hubris"
	prize.flavour = "You take it the way you would take an award."
	room.add_child(prize)
	prize.position = gate_at + Vector3(0, 0, 1.6)

	# ACROSS the room from the gate. There is nothing to press and no way to reach it that matters —
	# the anchor has no interact zone at all, so the rope is not the intended solution, it is the
	# only one.
	var anchor := TetherAnchor.new()
	anchor.name = "VaultLever"
	room.add_child(anchor)
	anchor.position = _spot(room, Vector3(-room.footprint.x * 0.5 + 2.5, 0, -2.0), PROP_SIZE)
	anchor.opens_path = anchor.get_path_to(gate)
	return room


## The warden stands on the near side of the locked door — the side you arrive from, which is the
## only side where offering you a choice means anything.
func _furnish_warden(layout: DungeonLayout, room_nodes: Dictionary) -> void:
	var best: DungeonRoom = null
	var best_edge: DungeonLayout.Edge = null
	for anchor: Vector3i in layout.rooms:
		var rd: DungeonLayout.RoomData = layout.rooms[anchor]
		for e: DungeonLayout.Edge in rd.edges:
			if e.type != DungeonLayout.EdgeType.LOCKED:
				continue
			# Near side = closer to the entrance. The far side is behind the door the warden is
			# guarding, where nobody can talk to him.
			if best == null or rd.dist < best.data.dist:
				best = room_nodes.get(anchor)
				best_edge = e
	if best == null or best_edge == null:
		return
	var warden := WardenGate.new()
	warden.name = "Warden"
	warden.key_id = best_edge.key_id
	warden.check_id = "warden_%d_%d" % [best.cell.x, best.cell.z]
	best.add_child(warden)
	# Beside the doorway, not in it: the door lane is 2 m either side and the occupancy grid already
	# knows that, so asking for free floor near the door does the stepping-aside for us.
	var door_at := DungeonLayout.door_local(best.data, best_edge)
	var inward := -Vector3(best_edge.dir.x, 0, best_edge.dir.z) * 3.0
	warden.position = _spot(best, door_at + inward, PROP_SIZE)


## The boss gets a Logic check on the way in — the "there is a second phase" beat, delivered before
## it happens rather than after it kills you.
func _furnish_boss(room: DungeonRoom) -> void:
	var probe := TraitProbe.new()
	probe.name = "BossProbe"
	probe.which = 0                                  # LOGIC
	probe.difficulty = "challenging"
	probe.check_id = "boss_%d_%d" % [room.cell.x, room.cell.z]
	probe.on_success = "Look at the floor. The scoring runs in rings, not in lines — whatever " \
			+ "lives here fights in a circle and it does it more than once. When it stops, it is " \
			+ "not finished. It is winding up."
	probe.on_fail = "Something big has been pacing in here. That is as much as the marks are " \
			+ "willing to say, and you have a sword."
	room.add_child(probe)
	probe.position = _spot(room, Vector3(0, 0, room.footprint.z * 0.5 - 3.5), PROBE_SIZE)


func _on_room_cleared(room: DungeonRoom) -> void:
	var run := get_node_or_null("/root/Run")
	if run and run.has_method("note_room_cleared"):
		run.note_room_cleared()
		# The walk home looks identical whether you beat the boss or gave up and took the return
		# portal. This is the only place that knows the difference, so it is the place that records
		# it — Run banks the result when the world stops being a dungeon.
		if room.is_boss:
			run.boss_down = true
	var pedestal := BoonPedestal.new()
	pedestal.name = "BoonPedestal"
	room.add_child(pedestal)
	pedestal.position = _spot(room, Vector3.ZERO, PEDESTAL_SIZE)


# ------------------------------------------------------------------------------------------------

## Nearest genuinely free floor to where the beat WANTS to be.
##
## Straight through the room's own occupancy grid, which already knows about carved corners, the
## dais, every prop the dresser placed and — the one that matters most here — the 2 m door lanes.
## Guessing a position from the footprint instead would put furniture in doorways in exactly the
## carved rooms where a doorway is hardest to predict.
## THE FALLBACK CHAIN IS THE WHOLE FUNCTION. Asking for space near a point can genuinely fail — a
## small room whose cover pass filled it, a wall the crack wants that has a doorway in it — and the
## first version simply returned `want` when it did. That put a warden in a doorway and a cracked
## wall across a corridor mouth on one seed in three, silently, because a position was still
## returned and nothing downstream had any way to know it was a refusal.
##
## So: near where the beat wants to be, else anywhere at all, else the room centre — which
## RoomPlan's own shape guarantees is solid floor.
const NOWHERE := Vector3(INF, INF, INF)


## Can this room take a fixture of `size` near `want` at all? NOWHERE means no, and means it
## HONESTLY — reserving nothing and telling the caller to look elsewhere. The beats that have a
## choice of room use this; the ones pinned to a particular room (the warden at its door, the boss
## check at its entrance) go through _spot below and take what they can get.
func _try_spot(room: DungeonRoom, want: Vector3, size: Vector2) -> Vector3:
	if room.plan == null:
		return NOWHERE
	var at: Vector3 = room.plan.free_near(want, size, 0.2, NOWHERE)
	if at == NOWHERE:
		at = room.plan.find_free(size, 0.2, NOWHERE)
	return at


func _spot(room: DungeonRoom, want: Vector3, size: Vector2) -> Vector3:
	if room.plan == null:
		return want
	var at := _try_spot(room, want, size)
	if at == NOWHERE:
		at = room.plan.find_free(Vector2(1.0, 1.0), 0.0, NOWHERE)
	if at == NOWHERE:
		at = _last_resort(room, want)
	room.plan.reserve(at, size)                      # so two beats in one room cannot stack
	return at


## When the room has NO unclaimed floor left at all — measured: it happens, one room in seed 42 has
## a free cell count of exactly zero after the dresser has finished with it.
##
## The trade made here is deliberate: this ignores whether a cell is CLAIMED, but never whether it
## is real floor and never whether it is in a doorway. A pedestal that clips a crate is untidy; a
## pedestal in a doorway is a room you cannot leave, and a warden in one is a conversation you
## cannot walk away from. Overlap is the acceptable failure.
func _last_resort(room: DungeonRoom, want: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	var hx: float = room.footprint.x * 0.5 - 2.0
	var hz: float = room.footprint.z * 0.5 - 2.0
	var x := -hx
	while x <= hx:
		var z := -hz
		while z <= hz:
			var p := Vector3(x, 0.0, z)
			if not room.plan.in_door_lane(p) and room.plan.is_ground(p, Vector2(0.9, 0.9)):
				var d := p.distance_squared_to(want)
				if d < best_d:
					best_d = d
					best = p
			z += 1.0
		x += 1.0
	return best

extends SceneTree
## Headless dungeon verification. Run:
##   Godot_console.exe --headless --path . --script res://scripts/dungeon/tests/verify_dungeon.gd
## Results also written to user://verify_dungeon.txt (stdout capture is flaky on Windows).
## Non-zero exit code on any failure.

var _fails: Array[String] = []
var _log := ""

## Every suite reports itself done. A GDScript runtime error inside an AWAITED suite unwinds it
## silently — the run once printed PASS while the reskin suite had actually crashed halfway — so
## the count is checked at the end and a missing suite is a failure.
const EXPECTED_SUITES := 19

## walls() over 60 seeds, reduced to one number. See _span_suite for what it is holding still.
##
## Moved twice since it was captured. Once when a flight stopped being allowed to stand in a doorway;
## once here, when the colosseum grew tiers -- 25 rooms in 200 seeds gained a raised far row, which
## is a retaining wall along it and a riser at each flight. Every other milestone has had to
## reproduce it to the bit, which is the whole point of writing the number down.
const PINNED_WALL_HASH := 2513190683

## And the whole plan -- tiles, levels, bevels, ramps, slots, spawns -- over the independence suite's
## 24 seeds. Captured at 220a9fd, before the zone graph replaced the hard-coded gallery and dais;
## re-pinned when the colosseum's tiers made it the first room to hold a raised AND a sunken zone.
##
## Re-pinned again when stair flights gained a landing (DungeonLayout.STAIR_LANDING). A flight used
## to reach the next floor's height exactly at the room edge, which is where the passage's floor
## strip overhangs back into the room -- so its top surface stood ~0.3 m proud of a still-climbing
## flight and walled off the only exit. Measured before the fix: a player-shaped body walking up the
## middle stopped at 9.19 m of a 10 m run, on every seed. climb_height now spreads the rise over the
## run MINUS the landing, so every wall and torch riding a flight sits a little differently. The
## WALL hash did not move, which is the check that this is the plan changing and not the shape.
const PINNED_PLAN_HASH := 2149192071

## And the GRAPH those rooms hang off -- every room and every edge over 200 seeds. Captured before M9
## gave a room a purpose; re-pinned here, the first time a purpose actually steered where rooms go.
## The walk now weights the kinds an unmet required purpose can live in, so the graph moves by
## construction -- which is the milestone, not a regression. See _demand_suite.
const PINNED_LAYOUT_HASH := 141036082
var _suites_done := 0


func _initialize() -> void:
	_layout_suite()
	_module_suite()
	_plan_suite()
	_span_suite()
	_wall_run_suite()
	_reach_suite()
	_demand_suite()
	_independence_suite()
	_weave_suite()
	_theme_suite()
	_template_suite()
	_build_suite()   # async: _ready of added zones runs on processed frames; it quits at the end


func _finish() -> void:
	_check(_suites_done == EXPECTED_SUITES,
			"only %d/%d suites ran to completion — one crashed" % [_suites_done, EXPECTED_SUITES])
	var verdict := "PASS" if _fails.is_empty() else "FAIL (%d)" % _fails.size()
	_out("[VERIFY] DUNGEON %s" % verdict)
	for f in _fails:
		_out("  FAIL: " + f)
	var fa := FileAccess.open("user://verify_dungeon.txt", FileAccess.WRITE)
	fa.store_string(_log)
	fa.close()
	quit(0 if _fails.is_empty() else 1)


func _out(s: String) -> void:
	print(s)
	_log += s + "\n"
	if s.begins_with("[VERIFY] ") and s.contains("suite"):
		_suites_done += 1


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## EVERY PROMISE A RoomModule MAKES, over 200 seeds.
##
## Each of these is a constraint applied at PLACEMENT time and then re-opened by a later pass:
## `_add_loop_rooms` joins everything a junction touches, `_grow_dead_end` bolts a room onto an
## arbitrary parent, `_add_stairs` re-types a leaf. A module's guarantee is therefore never local to
## the walk, and the walk is the only place it is easy to remember to check.
##
## The dead-end promise is the one that matters most: BOSS and TREASURE are chosen from dead-ends, so
## a vault that silently gained a second door does not fail here — it fails as a boss room with a
## corridor running through it, several passes later and with nothing pointing back to the cause.
func _module_suite() -> void:
	var lifted := 0
	var vaults := 0
	for s in range(1, 201):
		var lay := DungeonLayout.generate(s, 9)
		var per_seed := {}
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			per_seed[rd.module_id] = int(per_seed.get(rd.module_id, 0)) + 1
			# EVERY ROOM IS FOR SOMETHING, and it is what it always was. The classifier moved out of
			# RoomProgram and into the layout so that a purpose can one day depend on its
			# neighbours; until it does, the only thing worth asserting is that moving it changed
			# nothing. Checked against this file's own transcription, never against the moved code.
			_check(rd.purpose != "" or rd.type == DungeonLayout.RoomType.STAIR,
					"seed %d %s: no purpose" % [s, anchor])
			# A ROOM'S PURPOSE IS ITS CLASSIFICATION UNLESS A QUOTA MOVED IT, and there are exactly
			# two ways it can move: the room was SEATED with a quota purpose, or it was DEMOTED so a
			# required one could sit beside it. Anything else is a purpose that changed for a reason
			# nobody named — which is the failure this keeps catching, now that classify() and the
			# field have genuinely parted company.
			var base := _purpose_reference(rd)
			var moved: bool = RoomPurpose.CATALOGUE.has(rd.purpose) 					or rd.purpose == RoomPurpose.DEMOTE_TO.get(base, "")
			_check(rd.purpose == base or moved,
					"seed %d %s: purpose '%s' is neither its classification '%s', nor a seated "
					% [s, anchor, rd.purpose, base] + "quota, nor that classification's demotion")
			# AND A QUOTA MAY ONLY SIT ON A COMBAT ROOM. Every mission assertion in this file keys
			# off `type` alone, so this is what keeps the purpose layer structurally unable to break
			# one — not an argument, a check.
			_check(not RoomPurpose.CATALOGUE.has(rd.purpose)
					or rd.type == DungeonLayout.RoomType.COMBAT,
					"seed %d %s: quota purpose '%s' seated on a room of type %d"
							% [s, anchor, rd.purpose, rd.type])
			_check(RoomProgram.for_room(rd) == rd.purpose,
					"seed %d %s: for_room says '%s' but the room carries '%s'"
							% [s, anchor, RoomProgram.for_room(rd), rd.purpose])
			var m := RoomModule.by_id(rd.module_id)
			_check(m != null, "seed %d %s: unknown module '%s'" % [s, anchor, rd.module_id])
			if m == null:
				continue
			_check(rd.size == m.size,
					"seed %d %s: module %s is %s but the room is %s"
					% [s, anchor, m.id, m.size, rd.size])
			# THE DEAD-END PROMISE. A stair edge is diagonal, so it is excluded by lateral_edges().
			_check(rd.lateral_edges() <= m.max_edges,
					"seed %d %s: module %s takes %d lateral doors, cap is %d"
					% [s, anchor, m.id, rd.lateral_edges(), m.max_edges])
			if rd.kind == "vault":
				vaults += 1
				_check(rd.lateral_edges() == 1,
						"seed %d %s: a vault is not a dead-end (%d doors)"
						% [s, anchor, rd.lateral_edges()])
			# SOCKETS. Only `landing` declares any, and its whole reason to exist is that its single
			# door lands on an X face — which is exactly what _add_stairs can lift.
			if not m.sockets.is_empty():
				for e: DungeonLayout.Edge in rd.edges:
					if e.dir.y != 0:
						continue           # a flight leaves through the floor, not through a socket
					_check(m.sockets.has(Vector2i(e.dir.x, e.dir.z)),
							"seed %d %s: module %s has a door on face %s, sockets are %s"
							% [s, anchor, m.id, Vector2i(e.dir.x, e.dir.z), m.sockets])
			if rd.module_id == "landing" and rd.type == DungeonLayout.RoomType.STAIR:
				lifted += 1
		for m in RoomModule.catalogue():
			# .get, not [], on BOTH sides: the message is built before _check is called, so indexing
			# a module this seed never placed crashes the suite rather than failing it.
			var placed := int(per_seed.get(m.id, 0))
			_check(placed <= m.max_instances,
					"seed %d: %d x %s, cap is %d" % [s, placed, m.id, m.max_instances])
	# A landing that never becomes a staircase is a module paying an acceptance-rate cost for
	# nothing. It cannot be every landing — `stair_count` is 1, and a second one has nowhere to go —
	# so this is a floor, not an equality.
	# THE FIELD MUST WIN OVER THE CLASSIFIER, and this is the only check in the run that can tell.
	# Everywhere else `purpose` equals `classify()` by construction, so "reads the field" and
	# "recomputes it" are indistinguishable — deleting the field read from for_room passes the entire
	# suite. It stops being indistinguishable the moment a quota makes a room something its own shape
	# would not have chosen, which is the next milestone; asserting it now means that milestone
	# arrives on a foundation that was actually tested rather than assumed.
	var forced := DungeonLayout.RoomData.new()
	forced.kind = "vault"
	forced.type = DungeonLayout.RoomType.COMBAT
	_check(RoomPurpose.classify(forced) == "reliquary",
			"a vault classifies as '%s', so the override below is not overriding anything"
					% RoomPurpose.classify(forced))
	forced.purpose = "prison"
	_check(RoomProgram.for_room(forced) == "prison",
			"a room carrying purpose 'prison' resolved to '%s' — for_room is recomputing the "
			% RoomProgram.for_room(forced) + "classifier instead of reading what the layout decided")

	_check(lifted >= 20, "only %d landings of 200 seeds became staircases" % lifted)
	_out("[VERIFY] module suite: 200 seeds, %d vaults all dead-ends, %d landings lifted"
			% [vaults, lifted])


## 200 seeds of pure-data layout checks — runs in milliseconds.
## WHAT `for_room` USED TO COMPUTE, transcribed and kept here on purpose.
##
## A DELIBERATE DUPLICATE, the same instrument _independence_suite uses with _pass_names. The point
## of moving the classifier was that the OUTPUT must not change, and a test that called the moved
## function would agree with it however it had been mangled on the way. This copy is the only thing
## in the run that still knows what the answer was before.
func _purpose_reference(rd: DungeonLayout.RoomData) -> String:
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
			return "refectory"
		"gallery":
			if rd.size.z <= rd.size.x:
				return "colonnade"
			var toward := false
			var away := false
			for d: Vector2i in rd.door_dirs():
				if d.y > 0:
					toward = true
				elif d.y < 0:
					away = true
			return "passage" if (toward and away) else "church"
		"vault":
			return "reliquary"
	return "chambers"


## THE WHOLE GRAPH, as one order-preserving string: every room in placement order with the fields the
## walk and the post-passes decide, and every edge with its type and key.
##
## `tries_used`/`max_streak`/`relax_max` are DELIBERATELY ABSENT. They are an instrument, not an
## output — including them would make the pin fail whenever the walk took a different path to the
## same dungeon, which is the opposite of what it is for.
func _layout_signature(lay: DungeonLayout) -> String:
	var lines: Array[String] = []
	for cell: Vector3i in lay.rooms:
		var rd: DungeonLayout.RoomData = lay.rooms[cell]
		lines.append("room %s %s t%d %s/%s d%d k'%s'"
				% [rd.cell, rd.size, rd.type, rd.kind, rd.module_id, rd.dist, rd.holds_key])
		for e: DungeonLayout.Edge in rd.edges:
			lines.append("  edge %s %s t%d '%s'" % [e.from_cell, e.dir, e.type, e.key_id])
	return "
".join(lines)


## THE DEMAND FILTER, and the half of it that is not about dungeons at all.
##
## `_pick_module` narrows nothing and adds no draw: it multiplies the weights of the kinds an unmet
## required purpose can live in, takes its ONE roll, and returns. The rng is a single stream shared by
## the whole walk, so a second draw here — or a draw taken only on some branches — would desynchronise
## every seed after it and move every pinned number in this file at once, looking exactly like a
## content change while being nothing of the kind.
##
## So the state is compared directly rather than inferred from the hashes: same rng, same everything
## else, three different `owed` sets, and the stream must stand in the same place afterwards.
func _demand_suite() -> void:
	var lay := DungeonLayout.new()
	var states: Array[int] = []
	for owed: Array in [[], ["cell"], ["gallery", "hall"], ["nothing_of_the_sort"]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		lay._pick_module(rng, 3, {}, DungeonLayout.RELAX_NONE, owed)
		states.append(int(rng.state))
	for i in range(1, states.size()):
		_check(states[i] == states[0],
				"the rng stands at %d after a pick with a demand and %d without — the filter is "
						% [states[i], states[0]] + "taking a draw, and every seed downstream has moved")

	# AND IT MUST STILL BE DOING SOMETHING. A filter that never changes the answer passes the state
	# test perfectly, which is exactly how a no-op ships — so the CHANGE is measured too, and over a
	# distribution rather than one draw. Written as "these two picks differ" first, at one seed, and
	# it failed while the weights were being applied correctly: a single roll agreeing twice says
	# nothing at all, which is the same mistake as testing a die by throwing it once.
	var plain_hits := 0
	var boosted_hits := 0
	for s in 500:
		for pass_i in 2:
			var rng := RandomNumberGenerator.new()
			rng.seed = s
			var owed: Array = ["gallery", "hall"] if pass_i == 1 else []
			var m := lay._pick_module(rng, 3, {}, DungeonLayout.RELAX_NONE, owed)
			if m.kind == "gallery" or m.kind == "hall":
				if pass_i == 1:
					boosted_hits += 1
				else:
					plain_hits += 1
	_check(boosted_hits >= int(plain_hits * 1.3),
			"a demand for galleries and halls drew %d of them against %d undemanded — the weights "
					% [boosted_hits, plain_hits] + "are not being applied")

	# A DEMAND NAMING A KIND THE POOL CANNOT SUPPLY MUST BE HARMLESS, not a fall-through to the
	# unconstrained 1x1 — which is the shape most demands are asking for the opposite of, so the
	# failure would look like the feature working.
	var bare := DungeonLayout.new()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	bare._pick_module(rng2, 3, {}, DungeonLayout.RELAX_NONE, ["nothing_of_the_sort"])
	_check(bare.demand_missed == 1,
			"a demand for a kind nothing supplies was counted %d times, not once" % bare.demand_missed)
	_check(bare.pool_escapes == 0,
			"_pick_module escaped to plain() %d times with a full pool" % bare.pool_escapes)

	# OVER REAL SEEDS: the steering fires, it never escapes, and it does not starve a kind. `hall` is
	# the one that matters — it is the only host `refectory` has, and _weave_suite requires every
	# program to occur. The first version of this filter RESTRICTED the pool instead of weighting it
	# and took halls from 5.3% of all rooms to 1.9%, which is that program deleted to guarantee a
	# purpose nobody would have missed.
	var steered := 0
	var escapes := 0
	var dropped := 0
	var halls := 0
	var total := 0
	for s in range(1, 201):
		var l := DungeonLayout.generate(s, 9)
		steered += l.demand_steered
		escapes += l.pool_escapes
		dropped += 1 if l.demand_dropped else 0
		for anchor: Vector3i in l.rooms:
			total += 1
			if (l.rooms[anchor] as DungeonLayout.RoomData).kind == "hall":
				halls += 1
	_check(steered > 0, "the demand filter never fired over 200 seeds")
	_check(escapes == 0, "the walk escaped to plain() %d times — an over-narrow demand is producing "
			% escapes + "the very shape it was steering away from")
	_check(dropped <= 20, "%d of 200 seeds ran out of demand patience — the filter is costing the "
			% dropped + "walk more than it is buying")
	_check(float(halls) / float(total) >= 0.025,
			"halls are %.1f%% of all rooms, under the 2.5%% floor — a hall is refectory's only host"
					% (100.0 * halls / float(total)))
	_out("[VERIFY] demand suite: steered %d picks, %d escapes, %d seeds out of patience, halls %.1f%%"
			% [steered, escapes, dropped, 100.0 * halls / float(total)])


func _layout_suite() -> void:
	var layout_hash := 0
	var seated := {}
	var unmet := {}
	var demoted := 0
	var apart_bad := 0
	var twin_bad := 0
	var rerolled := 0
	var degraded := 0
	for s in range(1, 201):
		var lay := DungeonLayout.generate(s, 9)
		# WHAT THE QUOTAS DID, walked out of `rooms` and `edges` by this file rather than asked of
		# lay.check_purposes(). The verifier and the seater are already independent of each other;
		# making the TEST a third independent reading is what stops all three agreeing about
		# something none of them does — the lesson this suite already records elsewhere.
		var here := {}
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			if RoomPurpose.CATALOGUE.has(rd.purpose):
				here[rd.purpose] = int(here.get(rd.purpose, 0)) + 1
			for e: DungeonLayout.Edge in rd.edges:
				var n := lay.room_at(e.from_cell + e.dir)
				if n == null:
					continue
				if RoomPurpose.apart(rd.purpose, n.purpose):
					apart_bad += 1
				# ...and nothing sits beside a copy of itself. Reported from a screenshot: three
				# rooms in a row all labelled "church", which reads worse than any single wrong
				# label because the repetition is what the eye picks up.
				if n.cell != rd.cell and RoomPurpose.NO_TWIN.has(rd.purpose) 						and n.purpose == rd.purpose:
					twin_bad += 1
		for id: String in here:
			seated[id] = int(seated.get(id, 0)) + 1
			_check(here[id] <= int(RoomPurpose.CATALOGUE[id]["max"]),
					"seed %d: %d rooms are '%s', over its cap of %d"
							% [s, here[id], id, RoomPurpose.CATALOGUE[id]["max"]])
		for id: String in lay.purposes_unmet:
			unmet[id] = int(unmet.get(id, 0)) + 1
		demoted += lay.purposes_demoted
		# EVERY SEED, not a hand-picked few. Checked here because it is only interesting on a seed
		# that RE-ROLLED, and which seeds those are is not knowable in advance — a spot check on
		# three seeds that all succeed on attempt 0 never exercises the path at all.
		_check(lay.seed_used == s, "seed %d reports seed_used %d after %d attempts — a re-roll moved "
				% [s, lay.seed_used, lay.attempt] + "the number that keys every room's interior")
		if lay.attempt > 0:
			rerolled += 1
		if lay.degraded:
			degraded += 1
		layout_hash = hash("%d|%s" % [layout_hash, _layout_signature(lay)])
		var n := lay.rooms.size()
		# base rooms, plus one per stair (each brings the room it leads to) and one per loop junction
		_check(n >= 6 and n <= 14, "seed %d: room count %d out of bounds" % [s, n])
		_check_stairs(s, lay)
		# reachability + edge reciprocity
		var seen := {}
		var queue: Array[Vector3i] = [Vector3i.ZERO]
		seen[Vector3i.ZERO] = true
		while not queue.is_empty():
			var cell: Vector3i = queue.pop_front()
			var r: DungeonLayout.RoomData = lay.rooms[cell]
			for e: DungeonLayout.Edge in r.edges:
				var other := lay.room_at(e.from_cell + e.dir)
				_check(other != null, "seed %d: edge %s->%s into void" % [s, cell, e.dir])
				if other != null:
					_check(other.has_edge(-e.dir),
							"seed %d: edge %s->%s not reciprocal" % [s, cell, e.dir])
					_check(lay.occupied.get(e.from_cell) == cell,
							"seed %d: edge on %s leaves from %s, not its own cell" % [s, cell, e.from_cell])
					if not seen.has(other.cell):
						seen[other.cell] = true
						queue.append(other.cell)
		_check(seen.size() == n, "seed %d: only %d/%d rooms reachable" % [s, seen.size(), n])
		# specials
		var boss: DungeonLayout.RoomData = null
		var treasure: DungeonLayout.RoomData = null
		var max_dead_end_dist := 0
		for cell: Vector3i in lay.rooms:
			var r: DungeonLayout.RoomData = lay.rooms[cell]
			if r.type == DungeonLayout.RoomType.BOSS:
				boss = r
			elif r.type == DungeonLayout.RoomType.TREASURE:
				treasure = r
			if r.edges.size() == 1 and r.type != DungeonLayout.RoomType.START:
				max_dead_end_dist = maxi(max_dead_end_dist, r.dist)
		_check(boss != null, "seed %d: no boss room" % s)
		if boss:
			_check(boss.edges.size() == 1, "seed %d: boss not a dead-end" % s)
			_check(boss.dist == max_dead_end_dist, "seed %d: boss not the farthest dead-end" % s)
		_check(treasure != null, "seed %d: no treasure room" % s)
		if treasure:
			_check(treasure.edges.size() == 1, "seed %d: treasure not a dead-end" % s)
		_check_loops(s, lay)
		_check_mission(s, lay)
	# A stairless dungeon is a silent regression: the lift only fires on a leaf whose run is along
	# the long axis, so it is easy for a refactor to make that condition never hold.
	_check(_multi_floor_seeds >= 150,
			"only %d/200 seeds produced a second floor" % _multi_floor_seeds)
	_check(_multi_cell_seeds >= 180,
			"only %d/200 seeds produced a hall or gallery" % _multi_cell_seeds)
	_check(_loop_seeds >= 130, "only %d/200 seeds closed a loop" % _loop_seeds)
	# THE LOCAL RULE HOLDS EVERYWHERE. A prison and a church may never share a door; the seater
	# prefers a clean seat and demotes a neighbour when it cannot get one, and this is what says the
	# combination of the two actually worked.
	_check(apart_bad == 0, "%d pairs of rooms share a door they are forbidden to share" % apart_bad)
	_check(twin_bad == 0, "%d pairs of adjacent rooms announce the same purpose" % twin_bad)

	# THE GLOBAL RULE MOSTLY HOLDS, and where it does not it is COUNTED. `prison` is required and its
	# host — a COMBAT cell or vault at depth 2 — is present in most but not all dungeons; the ones
	# that miss are what the re-roll exists for, and until it lands they are reported rather than
	# hidden. The floor is set well under the measured 92% so this guards against collapse rather
	# than pinning a number that is allowed to drift.
	_check(int(seated.get("prison", 0)) >= 150,
			"prison was seated in only %d of 200 seeds" % int(seated.get("prison", 0)))
	_check(int(seated.get("colosseum", 0)) >= 30,
			"colosseum was seated in only %d of 200 seeds — an opportunistic purpose that almost "
			% int(seated.get("colosseum", 0)) + "never appears is a rule nobody is testing")
	# A DUNGEON THAT SHIPS WITHOUT ITS OWN RULES MET IS THE THING THAT MUST STAY RARE. Measured at
	# zero over 400 seeds — every seed that cannot seat a prison on attempt 0 finds one within four —
	# so the ceiling is a guard against that changing, not a tolerance being spent.
	_check(degraded <= 3, "%d of 200 seeds shipped degraded — a rule that is usually honoured is a "
			% degraded + "rule the dungeon cannot be built around")
	# ...and the re-roll must stay a rare correction rather than the normal path. If most seeds
	# re-roll, the quota is too demanding and the fix is the quota, not more attempts.
	# TIGHTENED FROM 40 WHEN DEMAND REACHED THE WALK. The rate was 8.3% of 400 seeds before the walk
	# preferred the kinds a required purpose needs and 2.5% after — so a ceiling of 40 (20%) would no
	# longer notice the steering being broken, which is the only thing it is there to notice. 12 sits
	# above the measured 5 with room for the distribution to drift and well under the old behaviour.
	_check(rerolled <= 12, "%d of 200 seeds re-rolled — at that rate the population of dungeons is "
			% rerolled + "being selected rather than generated")
	_out("[VERIFY] purposes: prison %d/200 seeds, colosseum %d/200, unmet %d, demotions %d, "
			% [int(seated.get("prison", 0)), int(seated.get("colosseum", 0)),
					int(unmet.get("prison", 0)), demoted]
			+ "re-rolled %d, degraded %d" % [rerolled, degraded])

	# THE SEED STILL IDENTIFIES THE DUNGEON. A re-roll changes which layout a seed produces; it must
	# not change whether a seed produces the SAME layout twice, and `seed_used` must survive it
	# because every room's interior randomness hangs off that number and not off the attempt.
	for s2 in [3, 17, 41]:
		var one := DungeonLayout.generate(s2, 9)
		var two := DungeonLayout.generate(s2, 9)
		_check(_layout_signature(one) == _layout_signature(two),
				"seed %d built two different layouts — the re-roll is not deterministic" % s2)
		# AND A LATER ATTEMPT MUST ACTUALLY BE A DIFFERENT DUNGEON, or the derived seed is not
		# deriving and four attempts are four copies of one failure.
		_check(_layout_signature(DungeonLayout._generate_once(s2, 0, 9, 1, 2))
				!= _layout_signature(DungeonLayout._generate_once(s2, 1, 9, 1, 2)),
				"seed %d: attempt 1 is the same layout as attempt 0" % s2)

	# THE LAYOUT ITSELF, held still. The wall hash holds what walls() emits and the plan hash holds
	# what a gameplay pass decides INSIDE a room; neither can see the graph those rooms hang off. M9
	# is about to give every room a purpose and then let that purpose steer where rooms go, so the
	# thing that must be provably unmoved first is the graph.
	_check(layout_hash == PINNED_LAYOUT_HASH,
			"the layout over 200 seeds hashes to %d, not the pinned %d — the graph moved"
					% [layout_hash, PINNED_LAYOUT_HASH])
	_check(_locked_seeds >= 130, "only %d/200 seeds gated the boss behind a key" % _locked_seeds)
	_out("[VERIFY] layout suite: 200 seeds, %d two-floor, %d halls, %d looped, %d key-gated"
			% [_multi_floor_seeds, _multi_cell_seeds, _loop_seeds, _locked_seeds])


## The mission has to be SOLVABLE, and it has to be a mission. Both halves matter:
##   - the key must be reachable from the entrance WITHOUT opening the lock, or the dungeon is
##     dead on arrival;
##   - the boss must NOT be reachable without it, or the lock is scenery.
## Simulated by walking the graph twice, once refusing locked gates and once allowing them.
func _check_mission(s: int, lay: DungeonLayout) -> void:
	var locks := {}
	for anchor: Vector3i in lay.rooms:
		for e: DungeonLayout.Edge in (lay.rooms[anchor] as DungeonLayout.RoomData).edges:
			if e.type == DungeonLayout.EdgeType.LOCKED:
				locks[e.key_id] = true
				_check(e.key_id != "", "seed %d: locked gate at %s carries no key id" % [s, anchor])
	if locks.is_empty():
		return
	_locked_seeds += 1

	var boss: DungeonLayout.RoomData = null
	var key_rooms := {}
	for anchor: Vector3i in lay.rooms:
		var r: DungeonLayout.RoomData = lay.rooms[anchor]
		if r.type == DungeonLayout.RoomType.BOSS:
			boss = r
		if r.holds_key != "":
			key_rooms[r.holds_key] = r
	_check(boss != null, "seed %d: locked dungeon with no boss" % s)

	for key_id in locks:
		_check(key_rooms.has(key_id), "seed %d: nothing holds %s" % [s, key_id])
		if not key_rooms.has(key_id):
			continue
		var without := _walk_graph(lay, {})
		_check(without.has((key_rooms[key_id] as DungeonLayout.RoomData).cell),
				"seed %d: %s is behind its own lock" % [s, key_id])
		if boss:
			_check(not without.has(boss.cell),
					"seed %d: boss reachable without %s — the lock is scenery" % [s, key_id])
			var with_key := _walk_graph(lay, {key_id: true})
			_check(with_key.has(boss.cell),
					"seed %d: boss unreachable even holding %s" % [s, key_id])


## Rooms reachable from the entrance while holding `keys`.
func _walk_graph(lay: DungeonLayout, keys: Dictionary) -> Dictionary:
	var seen := {Vector3i.ZERO: true}
	var queue: Array = [lay.rooms[Vector3i.ZERO]]
	while not queue.is_empty():
		var r: DungeonLayout.RoomData = queue.pop_front()
		for e: DungeonLayout.Edge in r.edges:
			if e.type == DungeonLayout.EdgeType.LOCKED and not keys.has(e.key_id):
				continue
			var n := lay.room_at(e.from_cell + e.dir)
			if n != null and not seen.has(n.cell):
				seen[n.cell] = true
				queue.append(n)
	return seen


var _locked_seeds := 0


## A shortcut must be a genuine alternative route, not a second door onto the room you just left,
## and it must never be hung off a destination or a stairwell.
func _check_loops(s: int, lay: DungeonLayout) -> void:
	var loops := 0
	for anchor: Vector3i in lay.rooms:
		var r: DungeonLayout.RoomData = lay.rooms[anchor]
		for e: DungeonLayout.Edge in r.edges:
			if e.type != DungeonLayout.EdgeType.SHORTCUT:
				continue
			loops += 1
			# a destination must stay a destination, and a stairwell has exactly two ends
			_check(r.type != DungeonLayout.RoomType.BOSS
					and r.type != DungeonLayout.RoomType.TREASURE
					and r.type != DungeonLayout.RoomType.STAIR,
					"seed %d: shortcut on a type-%d room at %s" % [s, r.type, anchor])
			var other := lay.room_at(e.from_cell + e.dir)
			_check(other != null and other.has_edge(-e.dir),
					"seed %d: shortcut at %s not reciprocal" % [s, anchor])
	if loops > 0:
		_loop_seeds += 1
	# A SHORTCUT is by definition an edge outside the spanning tree, so the edge count must be
	# exactly (rooms - 1) + one per shortcut pair. If that does not hold, the labelling is wrong.
	var edge_ends := 0
	for anchor: Vector3i in lay.rooms:
		edge_ends += (lay.rooms[anchor] as DungeonLayout.RoomData).edges.size()
	_check(edge_ends / 2 == lay.rooms.size() - 1 + loops / 2,
			"seed %d: %d edges for %d rooms and %d shortcut ends"
			% [s, edge_ends / 2, lay.rooms.size(), loops])


var _loop_seeds := 0


## A stair room is the only thing that may change floor, and it has to do it cleanly: exactly two
## exits, on OPPOSITE walls (so the flight runs straight through), exactly one of them climbing.
## Also: no two rooms may share the same x/z on different floors, or the upper one is built inside
## the lower one's ceiling.
func _check_stairs(s: int, lay: DungeonLayout) -> void:
	var footprints := {}
	var floors := {}
	for cell: Vector3i in lay.rooms:
		var r: DungeonLayout.RoomData = lay.rooms[cell]
		floors[cell.y] = true
		for c: Vector3i in r.cells():
			var xz := Vector2i(c.x, c.z)
			_check(not footprints.has(xz),
					"seed %d: cells %s and %s stack on the same footprint" % [s, footprints.get(xz), c])
			footprints[xz] = c
			_check(lay.occupied.get(c) == cell,
					"seed %d: cell %s of room %s not registered as occupied" % [s, c, cell])

		var climbs := 0
		for e: DungeonLayout.Edge in r.edges:
			if e.dir.y != 0:
				climbs += 1
				# one END of a vertical edge is the stairwell; the other is the room it serves
				var other := lay.room_at(e.from_cell + e.dir)
				_check(r.type == DungeonLayout.RoomType.STAIR
						or (other != null and other.type == DungeonLayout.RoomType.STAIR),
						"seed %d: cell %s changes floor with no stairwell at either end" % [s, cell])
				_check(e.type == DungeonLayout.EdgeType.STAIR,
						"seed %d: cell %s vertical edge not typed STAIR" % [s, cell])
		if r.type != DungeonLayout.RoomType.STAIR:
			continue
		_check(r.edges.size() == 2, "seed %d: stair %s has %d exits" % [s, cell, r.edges.size()])
		_check(climbs == 1, "seed %d: stair %s has %d climbing exits" % [s, cell, climbs])
		if r.edges.size() == 2:
			var a: Vector3i = r.edges[0].dir
			var b: Vector3i = r.edges[1].dir
			_check(a.x == -b.x and a.z == -b.z,
					"seed %d: stair %s exits are not opposite (%s vs %s)" % [s, cell, a, b])
	# the whole point: seeds should actually produce a second floor
	if floors.size() > 1:
		_multi_floor_seeds += 1
	for anchor: Vector3i in lay.rooms:
		if (lay.rooms[anchor] as DungeonLayout.RoomData).size != Vector3i.ONE:
			_multi_cell_seeds += 1
			break


var _multi_floor_seeds := 0
var _multi_cell_seeds := 0


## The gameplay/style contract, checked without loading a single mesh: plan every room of every
## layout and assert the slots make sense. This is the pass that has to stay fast — it is the
## reason RoomPlan is not allowed to touch art.
func _plan_suite() -> void:
	var checked := 0
	for s in range(1, 61):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			RoomPlan.plan_interior(rd, ctx)
			checked += 1

			# every doorway the layout promises must exist in the built shell, whatever the shape
			var doorways := 0
			for slot: RoomContext.Slot in ctx.slots:
				if slot.tag == RoomPlan.T_WALL_DOORWAY:
					doorways += 1
			_check(doorways == rd.door_dirs().size(),
					"seed %d %s: %d doorways for %d exits" % [s, cell, doorways, rd.door_dirs().size()])
			# the carving rule always leaves the middle cross intact
			var min_tiles: int = ctx.shape.cols + ctx.shape.rows - 1
			_check(ctx.shape.tile_count() >= min_tiles,
					"seed %d %s: shape carved to %d tiles, below the cross (%d)"
					% [s, cell, ctx.shape.tile_count(), min_tiles])

			var blockers: Array = []
			for slot: RoomContext.Slot in ctx.slots:
				_check(slot.tag in RoomPlan.ALL_TAGS,
						"seed %d %s: unknown slot tag '%s'" % [s, cell, slot.tag])
				# TAG AND ROLE, which is what the dresser will actually ask for. Checking the bare
				# tag passes on a slot whose role has no art and would build the wrong piece — and
				# fails on a tag that only ever appears WITH a role, which a gallery's always does.
				_check(RoomDresser.piece_for(slot.tag, null, slot.role) != "",
						"seed %d %s: tag '%s' role '%s' has no piece"
								% [s, cell, slot.tag, slot.role])
				if slot.footprint == Vector2.ZERO:
					continue
				var p: Vector3 = slot.transform.origin
				# nothing may stand over a carved-out corner
				_check(ctx.shape.contains_box(p, slot.footprint),
						"seed %d %s: %s at %s hangs over a hole" % [s, cell, slot.tag, p])
				# inside the interior
				_check(absf(p.x) + slot.footprint.x * 0.5 <= ctx.footprint.x * 0.5
						and absf(p.z) + slot.footprint.y * 0.5 <= ctx.footprint.z * 0.5,
						"seed %d %s: %s at %s escapes the room" % [s, cell, slot.tag, p])
				# never blocking the mouth of a doorway. NOTE this is the real requirement — "can
				# the player get in" — not the stricter whole-lane rule plan_interior uses to pick
				# procedural spots. A treasure altar sits dead centre by design, which is inside
				# the lane but 6 m clear of the door, and that is fine.
				_check(not ctx.near_door(p, 4.0),
						"seed %d %s: %s at %s blocks a doorway" % [s, cell, slot.tag, p])
				# never overlapping another solid piece
				var r := Rect2(p.x - slot.footprint.x * 0.5, p.z - slot.footprint.y * 0.5,
						slot.footprint.x, slot.footprint.y)
				for other: Rect2 in blockers:
					_check(not r.intersects(other),
							"seed %d %s: %s at %s overlaps another piece" % [s, cell, slot.tag, p])
				blockers.append(r)

			# enemies must not spawn inside the cover that was just planted, nor over a hole
			for def in ctx.spawn_defs:
				var sp: Vector3 = def.pos
				_check(ctx.shape.contains(Vector3(sp.x, 0, sp.z)),
						"seed %d %s: %s spawns over a hole at %s" % [s, cell, def.kind, sp])
				for other: Rect2 in blockers:
					_check(not other.has_point(Vector2(sp.x, sp.z)),
							"seed %d %s: %s spawns inside a prop at %s" % [s, cell, def.kind, sp])
			if rd.type == DungeonLayout.RoomType.COMBAT or rd.type == DungeonLayout.RoomType.BOSS:
				_check(not ctx.spawn_defs.is_empty(),
						"seed %d %s: fight room with no enemies" % [s, cell])
	# THE SIDE-OF-A-WALL PLUMBING, asserted while it still has only cardinal directions to be right
	# about. All three of these exist to make a 45-degree piece possible, and all three can be proved
	# now — before any such piece exists — precisely because each one has to agree with the behaviour
	# it replaces on the four axes. Landing them alone, provably inert, is the point of doing it as
	# its own step: a regression here afterwards would be indistinguishable from a chamfer bug.
	const AXES: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0),
	]
	const CANON_YAW := [0.0, PI, -PI * 0.5, PI * 0.5]
	for i in AXES.size():
		var y := RoomShape._inward_yaw(AXES[i])
		# EXACTLY, not approximately. -PI is the same rotation as PI and a different float, and the
		# atan2 form returns it unless the negative zero is kept out (see _inward_yaw).
		_check(y == CANON_YAW[i],
				"_inward_yaw(%s) = %.17f, was %.17f" % [AXES[i], y, CANON_YAW[i]])
		_check(RoomShape.out_of_yaw(y) == AXES[i],
				"out_of_yaw does not invert _inward_yaw at %s" % AXES[i])

	# The dot rule must agree with the equality it replaces on every cardinal pair. Sixteen cases,
	# which is all of them, so this is exhaustive rather than a sample.
	for a in AXES:
		for b in AXES:
			_check(RoomDresser.faces(a, b) == (a == b),
					"faces(%s, %s) disagrees with the equality it generalises" % [a, b])
	# ...and it must actually generalise, or it is equality with extra steps.
	_check(RoomDresser.faces(Vector2i(1, 1), Vector2i(0, 1)),
			"a chamfer facing half-toward the camera is not detected as facing it")
	_check(not RoomDresser.faces(Vector2i(1, -1), Vector2i(0, 1)),
			"a chamfer facing away from the camera is detected as facing it")

	# EVERY WALL SLOT CARRIES ITS SIDE, and this is where carrying it starts to matter rather than
	# merely being tidier. On a right angle the carried value and the one recovered from the basis
	# must still agree — that is the compatibility half. On a chamfer they must DISAGREE, because
	# out_of_yaw rounds a diagonal to a cardinal, and a run of this suite that never saw a disagreement
	# would be a run that never saw a chamfer and proved nothing about either.
	var carried := 0
	var diagonal := 0
	var recovered_wrong := 0
	for s0 in range(1, 21):
		var lay0 := DungeonLayout.generate(s0, 9)
		for anchor: Vector3i in lay0.rooms:
			var rd0: DungeonLayout.RoomData = lay0.rooms[anchor]
			var ctx0 := RoomContext.create(rd0, lay0.seed_used)
			RoomPlan.plan_shell(rd0, ctx0)
			for slot: RoomContext.Slot in ctx0.slots:
				if slot.out == Vector2i.ZERO:
					continue                   # stands in open floor; it has no side
				carried += 1
				var from_basis := RoomShape.out_of_yaw(slot.transform.basis.get_euler().y)
				_check(RoomDresser.side_of(slot) == slot.out,
						"side_of ignored the %s's carried out %s" % [slot.tag, slot.out])
				if absi(slot.out.x) + absi(slot.out.y) == 2:
					diagonal += 1
					if from_basis != slot.out:
						recovered_wrong += 1
					continue
				_check(RoomDresser.side_of(slot) == from_basis,
						"a square %s carries out %s but its basis says %s"
								% [slot.tag, slot.out, from_basis])
	_check(carried > 0, "no slot carries an `out` — plan_shell is dropping it again")
	_check(diagonal > 0, "20 seeds produced no chamfer — the diagonal half of this check never ran")

	# THE RUNS MEET. A bevelled corner replaces two 4 m walls with three runs of 2.83 / 2 / 2, and
	# the arithmetic that positions them is the one thing here with no forgiving failure mode: get a
	# centre or a half-length wrong and the room has a slot in its wall that the player can see the
	# void through, from one camera angle, in one room, on some seeds. So every chamfer endpoint is
	# required to land on another run's endpoint.
	#
	# COUNTS COINCIDENCES rather than measuring to the nearest OTHER endpoint. Written the second way
	# first, it discarded everything within 1e-4 as "itself" — throwing away the matching endpoint it
	# existed to find — and then reported the next-nearest run at 2 m as if it were a gap.
	var chamfer_runs := 0
	var unjoined := 0
	for s1 in range(1, 31):
		var lay1 := DungeonLayout.generate(s1, 9)
		for anchor: Vector3i in lay1.rooms:
			var rd1: DungeonLayout.RoomData = lay1.rooms[anchor]
			var ctx1 := RoomContext.create(rd1, lay1.seed_used)
			RoomPlan.plan_shell(rd1, ctx1)
			var runs := ctx1.shape.walls()
			var ends: Array[Vector3] = []
			for w: Dictionary in runs:
				ends.append_array(_run_ends(w))
			for w: Dictionary in runs:
				if w.role != "chamfer":
					continue
				chamfer_runs += 1
				for e in _run_ends(w):
					var touching := 0
					for o in ends:
						if e.distance_to(o) < 0.0001:
							touching += 1
					if touching < 2:
						unjoined += 1
	_check(chamfer_runs > 0, "no chamfer runs to check")
	_check(unjoined == 0,
			"%d of %d chamfer endpoints join nothing — there is a slot in a room's wall"
					% [unjoined, chamfer_runs * 2])
	# THE WHOLE REASON THE FIELD EXISTS. If the basis could still be trusted on a diagonal there
	# would be nothing to carry.
	_check(recovered_wrong > diagonal / 2,
			"only %d of %d chamfers are misread by out_of_yaw" % [recovered_wrong, diagonal])

	_out("[VERIFY] plan suite: %d rooms planned, %d wall slots carry their side" % [checked, carried])


## EVERY WALL'S SPAN MUST BE THE SPAN OF THE PIECE THAT WILL BE BUILT FOR IT.
##
## The role-to-length question had four answers: Kit.SIZES, which decides the real collider; this
## file's _run_ends; the layout lab's wall drawing; and the dresser's fixed 1.1 m clutter row. Three
## of them could be right about a 4 m wall and wrong about a 2.83 m one and nothing would say so —
## which is exactly what happened, since all four were written when every run was 4 m. Now walls()
## carries `span`, RoomShape.span_of computes it, and this closes the loop to the geometry.
##
## THE CHECK GOES THROUGH piece_for, not through a table of roles, because the piece is what the
## player walks into. A role whose art is a different length from its run leaves a gap in the wall or
## overlaps its neighbour, and it does so silently.
func _span_suite() -> void:
	# 1e-12, NOT is_equal_approx. Its epsilon is ~1e-5 relative, and the value this guards was
	# actually written as 2.8284 in three places — 4.3 um short of 2*sqrt(2), which is a real gap
	# between a bevel and the runs either side of it and which is_equal_approx waves straight
	# through. A literal standing in for an exact number has to be checked to the precision it
	# claims, or the check is only testing that someone typed roughly the right thing.
	_check(absf(RoomShape.CHAMFER_DIAG - RoomShape.CHAMFER_LEG * sqrt(2.0)) < 1e-12,
			"CHAMFER_DIAG is %.15f, not CHAMFER_LEG * sqrt(2) = %.15f"
					% [RoomShape.CHAMFER_DIAG, RoomShape.CHAMFER_LEG * sqrt(2.0)])
	var roles := {}
	var walls := 0
	var wall_hash := 0
	var fixtures := 0
	for s in range(1, 61):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			# THE GRID AGREES WITH ITS OWN INDEX. `_solid` is keyed Vector3i(x, level, z) and `_column`
			# is a Vector2i index over it; the index is what fifty call sites actually ask, so if the
			# two ever parted the dungeon would build from one and be measured by the other. Also the
			# place ONE TILE PER COLUMN is enforced rather than assumed — the key can express two
			# storeys, nothing yet builds or clears one, and the day something does this assertion is
			# what will say so instead of a room quietly appearing with a floor over its floor.
			var sh := ctx.shape
			_check(sh.cells().size() == sh.tiles().size(),
					"seed %d %s: %d cells over %d columns — something built a second storey before "
					% [s, cell, sh.cells().size(), sh.tiles().size()] + "anything can clear one")
			# THE FIXTURE LAYER, and that it is currently doing nothing. Every bevel is a one-tile
			# fixture and nothing else is one, so these two counts must agree — if set_chamfer's
			# add_fixture ever started failing, the corner would silently stop being cut and only the
			# wall hash would notice, three assertions later and without saying why.
			# Bevels and ramps are the two kinds, so the counts must add up exactly. If either
			# constructor's add_fixture started failing, the corner would stop being cut or the
			# flight would stop being built, and only a hash three assertions later would notice —
			# without saying why.
			var ramp_tiles := 0
			for t: Vector2i in sh.tiles():
				if sh.is_ramp(t):
					ramp_tiles += 1
			_check(sh.fixture_count() == sh.chamfer_count() + sh.ramp_count() + sh.run_count(),
					"seed %d %s: %d fixtures for %d bevels, %d ramps and %d wall runs"
							% [s, cell, sh.fixture_count(), sh.chamfer_count(), sh.ramp_count(),
									sh.run_count()])
			fixtures += sh.fixture_count()
			for t: Vector2i in sh.tiles():
				# WHO OWNS THE SLAB, per kind, because the two answers are opposite and each is
				# invisible to the wall hash. A ramp builds its own walk surface and must consume it,
				# or the room gets a flat slab AND a flight in the same tile. A bevel stands on
				# ordinary floor with a corner cut off — `contains`'s job, not the slab's — so if it
				# ever started consuming, a slab would vanish from under the player and no wall would
				# move.
				# ONLY A RAMP CONSUMES ITS FLOOR. A bevel stands on a slab with a corner cut off and a
				# wall run stands beside one — both keep their tiles.
				_check(sh.consumes_floor(t) == sh.is_ramp(t),
						"seed %d %s: tile %s consumes_floor=%s but is_ramp=%s"
								% [s, cell, t, sh.consumes_floor(t), sh.is_ramp(t)])
			for c3: Vector3i in sh.cells():
				var xz := Vector2i(c3.x, c3.z)
				_check(sh.is_solid(xz) and sh.level_of(xz) == c3.y,
						"seed %d %s: cell %s is not what the column index says about %s"
								% [s, cell, c3, xz])
			for w: Dictionary in ctx.shape.walls():
				walls += 1
				# Order-DEPENDENT, deliberately: walls() emits in tile order and the dresser builds in
				# that order, so a re-key that produced the same set in a different sequence would
				# change which piece got which positional roll. Rounded to the millimetre so the hash
				# is about geometry rather than about float noise.
				var at3: Vector3 = w.at
				wall_hash = hash("%d|%s|%.3f,%.3f,%.3f|%.5f|%d,%d|%s|%.4f"
						% [wall_hash, w.role, at3.x, at3.y, at3.z, w.yaw,
								(w.out as Vector2i).x, (w.out as Vector2i).y, cell, w.span])
				var role := String(w.role)
				roles[role] = true
				# A FIXTURE RUN CARRIES ITS OWN LENGTH; every other role gets it from the table.
				if RoomShape.has_fixed_span(role):
					_check(is_equal_approx(float(w.span), RoomShape.span_of(role)),
							"seed %d %s: a '%s' run carries span %.4f, span_of says %.4f"
									% [s, cell, role, w.span, RoomShape.span_of(role)])
				else:
					_check(float(w.span) >= 3.0 * RoomShape.TILE
							and is_equal_approx(fmod(float(w.span), RoomShape.TILE), 0.0),
							"seed %d %s: a '%s' run is %.4f m, not a whole number of modules over 3"
									% [s, cell, role, w.span])
				# ONE BAY PER MODULE. This was "one bay per run, at the run's own point", which was
				# the INERTNESS proof for making the mount pass bay-relative — true only while every
				# run in the dungeon was a single 4 m module. A 16 m wall run yielding four bays is
				# the mechanism finally doing the thing it was built for, not a regression, and the
				# single-bay case still has to return `at` itself rather than a recomputed midpoint.
				var bays := RoomShape.wall_bays(w)
				var want_bays := maxi(1, roundi(float(w.span) / RoomShape.TILE))
				_check(bays.size() == want_bays,
						"seed %d %s: a %.0f m '%s' run yielded %d bays, not %d"
								% [s, cell, w.span, role, bays.size(), want_bays])
				if want_bays == 1:
					_check(bays[0] == w.at, "seed %d %s: a single-bay '%s' run moved its own point"
							% [s, cell, role])
				var piece := RoomDresser.piece_for(RoomPlan.T_WALL, null, role)
				var size: Vector3 = Kit.SIZES.get(piece, Vector3.ZERO)
				_check(size != Vector3.ZERO, "seed %d: wall role '%s' -> piece '%s' has no size"
						% [s, role, piece])
				# THE TABLE ONLY ANSWERS FOR A FIXED-LENGTH ROLE. A fixture run resolves to the same
				# module every other wall does and is then BUILT to its own length by run_piece, so
				# comparing its span against the module's would report a slot in a wall that has none
				# — the module is the profile, not the extent.
				if RoomShape.has_fixed_span(role):
					_check(is_equal_approx(size.x, float(w.span)),
							"seed %d %s: a '%s' run is %.4f m but its piece '%s' is %.4f m — that is a "
							% [s, cell, role, w.span, piece, size.x] + "slot in the wall")
	# All four roles must actually occur, or three quarters of this suite is checking nothing.
	for want in ["", "half", "chamfer", "riser"]:
		_check(roles.has(want), "no wall with role '%s' in 60 seeds — span is untested for it" % want)

	# AND THEN PAST THE TABLE, to the collider that ships. Kit.SIZES only decides the GREYBOX: a role
	# with a real .tscn, or a themed variant, takes an earlier branch of Kit._resolve and never
	# consults it. So a size table agreeing with itself proves nothing about the wall the player walks
	# into — and it was wrong, by 4.3 um, in exactly the piece that has a .tscn.
	var theme := load("res://scenes/dungeon/themes/crypt.tres") as DungeonTheme
	for role: String in roles:
		var want := RoomShape.span_of(role)
		if not RoomShape.has_fixed_span(role):
			want = 4.0 * RoomShape.TILE
		# A VARIABLE-LENGTH ROLE IS BUILT TO LENGTH, not resolved to a fixed piece. Asking Kit.piece
		# for a 16 m run hands back the 4 m module it falls back to, which is the right answer to the
		# wrong question — the dresser calls run_piece for exactly this reason.
		var want_len := RoomShape.span_of(role) if RoomShape.has_fixed_span(role) else 4.0 * RoomShape.TILE
		for roll in [0.05, 0.5, 0.95]:               # each variant the theme might hand back
			var piece := RoomDresser.piece_for(RoomPlan.T_WALL, theme, role)
			var node: Node3D = (Kit.piece(piece, theme, roll) if RoomShape.has_fixed_span(role)
					else Kit.run_piece(piece, want_len, theme))
			var got := _collider_x(node)
			node.free()
			_check(got > 0.0, "wall role '%s' -> '%s' builds nothing that collides" % [role, piece])
			_check(absf(got - want) < 1e-6,
					("wall role '%s' at roll %.2f builds '%s' %.7f m wide, but its run is %.7f m"
					+ " — the wall has a gap or an overlap at every corner") % [role, roll, piece,
							got, want])
	# AND THE OTHER HALF: a run longer than one module must actually subdivide, or the inertness
	# above is satisfied by a function that returns [at] and nothing else. Synthetic, because no run
	# in the dungeon is long enough yet — which is the point of landing the mechanism before the
	# geometry that needs it.
	var long_wall := {"at": Vector3(0.0, 0.0, 10.0), "out": Vector2i(0, 1), "role": "", "span": 16.0}
	var bays := RoomShape.wall_bays(long_wall)
	_check(bays.size() == 4, "a 16 m run subdivides into %d bays, not 4" % bays.size())
	if bays.size() == 4:
		# ON THE SET, not on the order. `along` is the (-n.z, n.x) perpendicular the whole codebase
		# uses — _run_ends and the layout lab's wall drawing take the same one — so on this wall it
		# points at -X and the bays come out far-to-near. That is a convention, not a property: the
		# thing that has to be true is that four bays sit evenly along the run, a half-module in from
		# each end so none hangs off the wall it belongs to.
		var xs: Array[float] = []
		for b: Vector3 in bays:
			_check(is_equal_approx(b.z, 10.0), "bay %s left the run's own line" % b)
			xs.append(b.x)
		xs.sort()
		for k in 4:
			var want := -6.0 + k * 4.0
			_check(is_equal_approx(xs[k], want),
					"the 16 m run's bays sit at %s, not at -6/-2/2/6" % [xs])
	# THE PIN. Every wall the dungeon emits over 60 seeds, reduced to one number, captured while the
	# tile grid was still keyed in 2-D and asserted unchanged after it was re-keyed to
	# Vector3i(x, level, z). With every tile at level 0 the 3-D grid must reproduce the 2-D one
	# EXACTLY — same runs, same order, same positions to the bit — and that is the only thing that
	# makes a change touching fifty call sites safe to land. The fixture mechanism rewrites walls()
	# again straight afterwards and is held to the same number.
	#
	# A hash rather than a stored corpus because the corpus is 14461 runs; the failure mode of a hash
	# is that it tells you something moved without telling you what, which for an assertion whose only
	# job is "nothing moved" is the whole content.
	_check(wall_hash == PINNED_WALL_HASH,
			"walls() over 60 seeds hashes to %d, not the pinned %d — the re-key changed the geometry"
					% [wall_hash, PINNED_WALL_HASH])
	# THE FREEZE, which is the one thing about fixtures that fails silently rather than loudly.
	# RoomContext._ensure_grid snapshots shape.contains() for the whole room and never re-reads it,
	# so a fixture installed afterwards changes the geometry and not the grid — the cover pass, the
	# mounts and the encounter all go on believing the tile is square, and every one of them places
	# things inside masonry while looking entirely correct. add_fixture must refuse.
	#
	# The ERROR line this prints is the point of the check, not a fault in it.
	var lay0 := DungeonLayout.generate(1, 9)
	for cell: Vector3i in lay0.rooms:
		var rd0: DungeonLayout.RoomData = lay0.rooms[cell]
		var c0 := RoomContext.create(rd0, lay0.seed_used)
		RoomPlan.plan_shell(rd0, c0)
		var before := c0.shape.fixture_count()
		c0.reserve(Vector3.ZERO, Vector2.ONE)          # bakes the grid, and freezes the shape
		var late := RoomShape.Fixture.new()
		late.kind = "chamfer"
		late.anchor = (c0.shape.tiles() as Array)[0]
		_check(not c0.shape.add_fixture(late),
				"a fixture was accepted after the occupancy grid was baked — the grid does not know "
				+ "about it and every pass after this one is planning on floor that is not there")
		_check(c0.shape.fixture_count() == before,
				"the refused fixture was recorded anyway (%d -> %d)"
						% [before, c0.shape.fixture_count()])
		# ...AND A WALL RUN IS DELIBERATELY STILL ALLOWED, because it moves no floor. The exemption
		# is asserted rather than assumed: if it were ever withdrawn the wall-run pass would stop
		# running entirely, and the only symptom would be walls quietly going back to 4 m modules.
		var side := Vector2i(0, -1)
		var anchor := Vector2i(1, 0)
		var free := true
		for k in 3:
			var t := anchor + Vector2i(k, 0)
			if not (c0.shape.is_solid(t) and not c0.shape.is_solid(t + side)
					and c0.shape.fixture_at(t) == null):
				free = false
		if free:
			_check(RoomPlan.try_wall_run(rd0, c0, anchor, side, 3),
					"a wall run was refused after the grid was baked — it moves no floor, and the "
					+ "zones that bake the grid are what it has to be installed after")
		break
	_check(fixtures > 0, "no room in 60 seeds installed a fixture — the mechanism has no user")
	_out("[VERIFY] span suite: %d runs over 60 seeds, %d roles, matched to table AND collider, "
			% [walls, roles.size()] + "one bay each, %d fixtures, hash %d" % [fixtures, wall_hash])


## The widest X extent of everything a built piece collides with, in the piece's own space. Taken
## from the SHAPE rather than from an AABB of the mesh, because collision is what decides whether two
## runs meet and a mesh may legitimately overhang it.
func _collider_x(node: Node) -> float:
	var widest := 0.0
	for n in _walk(node):
		if not (n is CollisionShape3D):
			continue
		var cs := n as CollisionShape3D
		var half := 0.0
		if cs.shape is BoxShape3D:
			half = (cs.shape as BoxShape3D).size.x * 0.5
		elif cs.shape is ConvexPolygonShape3D:
			for p: Vector3 in (cs.shape as ConvexPolygonShape3D).points:
				half = maxf(half, absf(p.x))
		else:
			continue
		# The shape's own transform relative to the piece root, so a shape offset along X still
		# reports the extent the piece actually occupies.
		var off := absf(cs.transform.origin.x)
		widest = maxf(widest, (half + off) * 2.0)
	return widest


## THE VEIL, DRIVEN. Nothing ran CourseVeil._process before this: _cutaway_suite checks the collect
## walk finds every stamped piece and then EXEMPTS all of them from its occlusion sweep on the
## grounds that the veil handles them. So the one mechanism standing between the player and a course
## over their head had its bookkeeping tested and its decision not tested at all.
##
## Synthetic rather than over a built dungeon, because the interesting cases are ones the dungeon
## cannot produce yet — that is the point of landing this before long pieces exist.
func _veil_suite() -> void:
	var player := Node3D.new()
	var piece := Node3D.new()
	var veil := CourseVeil.new()
	# IN THE TREE, because global_position is only defined there — outside it Godot returns identity
	# and logs an error per access, so the sweep below would have compared two rules that both saw
	# the piece at the origin and agreed perfectly about nothing.
	var holder := Node3D.new()
	root.add_child(player)
	root.add_child(holder)
	holder.add_child(piece)
	# AND ONE FRAME, so they are genuinely inside the tree. Without it global_position returns
	# identity and logs an error per access — and the sweep below would then have compared two rules
	# that both saw the piece at the origin and agreed perfectly about nothing. That is exactly the
	# vacuous pass its own comment warns of, and it is why this suite runs with the async ones rather
	# than in the synchronous block above, where nothing added to root is in the tree yet.
	await process_frame
	veil._player = player

	# 1. A 4 M PIECE REPRODUCES TODAY'S BOUNDARIES. The lane, the reach and the sightline test all
	# became piece-relative, so the guarantee that makes a change this central safe is that at one
	# module they come back to the constants they replaced. Compared decision by decision against the
	# old rule written out verbatim, over a grid that straddles every threshold — not at a handful of
	# chosen points, where a boundary can move a few centimetres and be missed.
	piece.set_meta(RoomDresser.COURSE_META, RoomPlan.T_WALL)
	piece.set_meta(RoomDresser.COURSE_SPAN, RoomShape.TILE)
	piece.set_meta(RoomDresser.COURSE_RISE, DungeonLayout.COURSE_H)
	# THROUGH collect(), not by assigning the arrays. Written the other way first, and it made the
	# suite a test of _process's arithmetic and of nothing else: reverting the lane to a hard-coded
	# 2.6 in _gather passed every check below, because the suite was supplying its own lane and never
	# reading the one the veil computes. A test that hand-builds the state it is checking is testing
	# its own arithmetic — and it would have been a fourth copy of the formula, which is the exact
	# thing the previous milestone was about.
	veil.collect(holder)
	_check(veil.pieces_count() == 1, "the veil collected %d pieces, not the 1 this suite set up"
			% veil.pieces_count())
	var diffs := 0
	var samples := 0
	# Step 0.2 / 0.25 m, which is finer than any threshold here can move without the assertion
	# noticing, and coarse enough that ~9,000 samples is a second rather than a minute.
	for xi in range(-20, 21):
		for zi in range(-4, 73):
			for yi in [0.0, 2.0, 5.0]:
				piece.global_position = Vector3(xi * 0.2, yi, zi * 0.25)
				# Pinned before every sample: the piece's own visibility IS the hysteresis state, so
				# an unpinned sweep would compare two rules that had each taken their own path here.
				piece.visible = true
				veil._process(0.0)
				var got := piece.visible
				# The rule as it stood, transcribed.
				var d := piece.global_position - player.global_position
				var m := -CourseVeil.HYST
				var want := true
				if not (absf(d.x) > 2.6 + m or d.z <= -m or d.z > 16.0 + m):
					want = d.y + DungeonLayout.COURSE_H < d.z * CourseVeil.SLOPE - m
				samples += 1
				if got != want:
					diffs += 1
	_check(diffs == 0, "a 4 m course changed its mind at %d of %d offsets — the piece-relative "
			% [diffs, samples] + "veil is not inert on the pieces the dungeon builds today")

	# 2. AND A LONG ONE MUST HIDE. 16 m of run, the player under its far end: its centre is 7 m to
	# the side, which the old fixed 2.6 m lane rejected outright — the course stood over the player's
	# head and the veil declared it irrelevant. This is the case the milestone exists for, and it is
	# asserted BOTH ways so it cannot pass by the new rule hiding everything.
	piece.set_meta(RoomDresser.COURSE_SPAN, 16.0)
	veil.collect(holder)
	_check(veil.pieces_count() == 1, "the veil collected %d pieces, not the 1 this suite set up"
			% veil.pieces_count())
	piece.global_position = Vector3(7.0, 3.0, 1.0)
	piece.visible = true
	veil._process(0.0)
	_check(not piece.visible,
			"a 16 m course 7 m to the side and 3 m up stayed visible over the player's head")
	_check(absf(piece.global_position.x) > 2.6,
			"the long-piece case is inside the old 2.6 m lane, so it proves nothing")
	# And clear of it, it must come back. 10 m, not 9: the run's end is at 8.0, the lane adds LANE_PAD
	# to 8.6, and a HIDDEN piece carries the hysteresis margin outward to 9.1 before it reappears — so
	# 9.0 is inside the deadband and staying hidden there is the Schmitt trigger working, not a bug.
	# The number a test picks has to clear the deadband as well as the lane.
	piece.global_position = Vector3(10.0, 3.0, 1.0)
	piece.visible = false
	veil._process(0.0)
	_check(piece.visible, "a 16 m course 10 m to the side is 2 m past its own end and must not hide")

	# 3. AND A SHORT PIECE MUST STOP BEING TREATED AS A TALL ONE. Every course was measured at
	# COURSE_H — one full 3 m module — whatever it actually was, so a 0.3 m band and a 0.5 m cornice
	# were tested against ten and six times their own height and vanished far up the corridor. The
	# code's own comment claimed this test "spares the band and most cornices"; with the stand-in it
	# largely did not. 1 m up and 2 m ahead the sightline is at 3.17 m: a 0.3 m band reaches 1.3 and
	# is plainly under it, while the stand-in put it at 4.0 and hid it.
	piece.set_meta(RoomDresser.COURSE_SPAN, RoomShape.TILE)
	piece.set_meta(RoomDresser.COURSE_RISE, DungeonLayout.BAND_H)
	veil.collect(holder)
	_check(veil.pieces_count() == 1, "the veil collected %d pieces, not the 1 this suite set up"
			% veil.pieces_count())
	piece.global_position = Vector3(0.0, 1.0, 2.0)
	piece.visible = true
	veil._process(0.0)
	_check(piece.visible, "a 0.3 m band 1 m up and 2 m ahead was hidden — it is 1.9 m under the "
			+ "sightline, and only the 3 m stand-in ever put it near one")
	var sightline := 2.0 * CourseVeil.SLOPE + CourseVeil.HYST
	_check(1.0 + DungeonLayout.COURSE_H > sightline and 1.0 + DungeonLayout.BAND_H < sightline,
			"the band case no longer straddles the old and new rules, so it proves nothing")

	veil.free()
	holder.queue_free()
	player.queue_free()
	_out("[VERIFY] veil suite: %d offsets inert at one module, long runs hide at their ends"
			% samples)


## EVERY TILE OF FLOOR MUST BE REACHABLE FROM THE ROOM'S OWN LEVEL, walking.
##
## THIS REPLACES A GUARANTEE THAT STOPPED BEING TRUE. RoomShape's carving rule bites rectangles out
## of the four corners so the middle cross always survives, which makes connectivity free with no
## flood fill — and _plan_suite still asserts the tile COUNT that rule implies. But the cross is a
## statement about the 2-D silhouette, and the moment a tile can sit at another level it stops being
## a statement about where a body can walk. A deck reachable only by a flight whose foot was carved
## away is connected on the plan and a perch in the room.
##
## That is not hypothetical: this project shipped exactly that bug once, ramps in the deck row with
## their low ends against the end wall, a staircase usable only from the top. It survived a
## milestone because the walk probe tested a flight on an empty rig instead of a reachable one.
##
## Through RoomShape.walkable, not a rule written again here, because the zone solver will ask the
## same question and two versions of it would eventually disagree about a room the player is in.
func _reach_suite() -> void:
	const SIDES: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var rooms := 0
	var levelled := 0
	for s in range(1, 41):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			var shape := ctx.shape
			rooms += 1
			if shape.level_count() > 0:
				levelled += 1
			# FROM A LEVEL-0 TILE, because that is where every door opens and therefore where the
			# player arrives. A room whose ground floor were unreachable from itself would be a
			# different failure and the seed would have to be entered from a deck.
			var start := Vector2i(-1, -1)
			for t: Vector2i in shape.tiles():
				if shape.level_of(t) == 0:
					start = t
					break
			_check(start.x >= 0, "seed %d %s: no tile at level 0 — nothing opens onto a door" % [s, cell])
			if start.x < 0:
				continue
			var seen := {start: true}
			var queue: Array[Vector2i] = [start]
			while not queue.is_empty():
				var t: Vector2i = queue.pop_back()
				for side: Vector2i in SIDES:
					var n := t + side
					if seen.has(n) or not shape.walkable(t, side):
						continue
					seen[n] = true
					queue.append(n)
			if seen.size() != shape.tile_count():
				var stranded: Array[String] = []
				for t: Vector2i in shape.tiles():
					if not seen.has(t):
						stranded.append("%s@l%d" % [t, shape.level_of(t)])
				_check(false, "seed %d %s: %d of %d tiles cannot be walked to from level 0 — %s"
						% [s, cell, stranded.size(), shape.tile_count(), ", ".join(stranded)])
	_check(levelled >= 20, "only %d of %d rooms have a tile off level 0, so the part of this check "
			% [levelled, rooms] + "that is about levels barely ran")

	# REGIONS, AND THE THREE RULES THEY ANSWER TO. A region is a maximal 4-connected set of tiles at
	# one level; the room's ground floor is one and every deck or pit is another.
	var raised_regions := 0
	for s in range(1, 41):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			var shape := ctx.shape
			var covered := 0
			for r: Dictionary in shape.regions():
				covered += (r.tiles as Array).size()
				if r.level == 0:
					continue
				raised_regions += 1
				# TWO WAYS IN, ALWAYS. One flight makes a region a perch whether it is up or down —
				# you go there, you come back the way you came, and a fight on it has one exit that
				# is also its entrance.
				# A FLIGHT SERVES A REGION IF IT JOINS IT TO ANOTHER LEVEL, and which END of the
				# ramp lies inside depends on which way the region went. A raised deck is reached by
				# a ramp OUTSIDE it whose head lands in; a pit is left by a ramp INSIDE it whose head
				# lands out. Counting heads alone reported every pit as served by zero flights —
				# correct arithmetic, wrong question.
				var flights := 0
				for t: Vector2i in shape.tiles():
					if not shape.is_ramp(t):
						continue
					var head: Vector2i = t + shape.ramp_dir(t)
					var tiles: Array = r.tiles
					if tiles.has(head) != tiles.has(t):
						flights += 1
				_check(flights >= 2, "seed %d %s: a region at level %d is served by %d flights — "
						% [s, cell, r.level, flights] + "one is a perch, not a place")
				# AND A PIT MAY NOT REACH THE WALL. The shell is pinned at y = 0, so a sunken tile on
				# the outline leaves nothing between its floor and that pin — a slot you see out of
				# the level through, at eye height from this camera.
				_check(not (r.level < 0 and r.outline),
						"seed %d %s: a region at level %d touches the room outline" % [s, cell, r.level])
			# Every tile in exactly one region: the partition has to be a partition, or a rule that
			# holds for every region still misses whatever fell between them.
			_check(covered == shape.tile_count(),
					"seed %d %s: regions cover %d of %d tiles" % [s, cell, covered, shape.tile_count()])
	_check(raised_regions >= 20, "only %d regions off level 0 in 40 seeds" % raised_regions)

	# THE RISER STACKS. Synthetic, because no seed builds a two-level boundary yet: the art module is
	# exactly LEVEL_RISE tall, so one slot against a 2.4 m drop is a 1.2 m wall holding back twice
	# its height, with the deck's underside open above it.
	for drop in [1, 2, 3]:
		var st := RoomShape.full(5, 3)
		for j in 3:
			st.set_level(Vector2i(2, j), drop)
		var risers := 0
		for w: Dictionary in st.walls():
			if w.role == "riser":
				risers += 1
		# Two faces of the raised column, three tiles each, one module per level of drop.
		_check(risers == 2 * 3 * drop,
				"a %d-level boundary emitted %d risers, not the %d one module per level needs"
						% [drop, risers, 2 * 3 * drop])
		# ...and they stack rather than piling up at one height.
		var heights := {}
		for w: Dictionary in st.walls():
			if w.role == "riser":
				heights[roundi((w.at as Vector3).y * 100.0)] = true
		_check(heights.size() == drop, "a %d-level boundary put its risers at %d distinct heights"
				% [drop, heights.size()])

	# A PIT ON THE OUTLINE IS REFUSED AT THE POINT IT IS ASKED FOR, not caught downstream. The ERROR
	# it logs is the check working.
	var pit := RoomShape.full(5, 3)
	pit.set_level(Vector2i(0, 0), -1)
	_check(pit.level_of(Vector2i(0, 0)) == 0,
			"a corner tile was sunk despite being on the outline — the shell wall starts at y = 0 "
			+ "and there would be nothing under it")
	pit.set_level(Vector2i(2, 1), -1)
	_check(pit.level_of(Vector2i(2, 1)) == -1,
			"the middle tile of a 5x3 room is not on the outline and must be sinkable")
	# WHAT THE PROGRAMS ASKED FOR AND WHAT THEY GOT. A zone the room could not fit is a statement the
	# program made and the dungeon did not honour — and the room still builds, still looks finished,
	# and is quietly a plainer room than it was meant to be. That is the failure mode a solver has
	# that a hard-coded feature does not: constraints accumulate, fits get rarer, and nothing says so
	# because nothing was ever counted. So it is counted, reported per program, and floored.
	# TWO KINDS OF ZONE, AND THEY ARE HELD TO DIFFERENT STANDARDS, because a rate was the wrong
	# instrument for one of them. A church's apse is REQUIRED — the room is not a church without it,
	# so "44% of churches manage it" is not a degradation to be tolerated at some threshold, it is
	# 97 rooms carrying a label the geometry does not back. That case is now exact: the room demotes
	# instead, so a purpose that survives has everything that defines it, and the assertion is
	# equality rather than a fraction.
	#
	# A gallery's raised walk and a prison's oubliette are OPTIONAL — the room is honestly what it
	# says it is either way, and carving, doors and proportion all legitimately refuse them. Those
	# keep a rate, and it is a collapse guard rather than a target.
	var asked := {}
	var got := {}
	var req_asked := 0
	var req_missing := 0
	for s in range(1, 41):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			# ctx.program, not for_room(rd) — the SETTLED purpose rather than the layout's
			# proposal, which is the whole point of the demotion.
			var pname: String = ctx.program if ctx.program != "" else RoomProgram.for_room(rd)
			var want := 0
			for z: Dictionary in RoomProgram.zones_of(pname):
				if int(z.get("level", 0)) == 0:
					continue
				want += 1
				if not bool(z.get("required", false)):
					continue
				req_asked += 1
				# A REQUIRED ZONE IS PRESENT OR THE ROOM IS NOT THAT THING. Checked from the SHAPE,
				# not from the refusal counter — the counter is what the code thought it did, and the
				# tiles are what it actually did.
				if ctx.shape.level_count() == 0:
					req_missing += 1
			if want == 0:
				continue
			asked[pname] = int(asked.get(pname, 0)) + want
			got[pname] = int(got.get(pname, 0)) + (want - ctx.zones_refused)
	_check(req_missing == 0,
			"%d of %d rooms keep a purpose whose REQUIRED zone was never placed — the label claims "
			% [req_missing, req_asked] + "something the room does not have")
	_check(req_asked > 0, "no program declares a required zone, so the check above proves nothing")
	var lines: Array[String] = []
	for pname: String in asked:
		var a: int = asked[pname]
		var g: int = got[pname]
		lines.append("%s %d/%d" % [pname, g, a])
		# 15%, not a third. The old floor was set when the only zone anybody asked for was a
		# church's apse, which is now exact and no longer counted here; what is left is decoration
		# that a carved room legitimately cannot fit, and a guard against it disappearing entirely.
		_check(float(g) / float(maxi(a, 1)) >= 0.15,
				"program '%s' placed %d of the %d optional zones it asked for — it has stopped "
				% [pname, g, a] + "offering them at all")
	lines.sort()
	_check(asked.size() >= 2, "only %d programs ask for a raised zone" % asked.size())
	_out("[VERIFY] zones: %s   (required zones missing: %d of %d)"
			% [", ".join(lines), req_missing, req_asked])

	# NO FLIGHT MEETS A DOORWAY. Measured in metres against the door positions rather than by asking
	# run_clear again, because re-running the code's own predicate would agree with it however wrong
	# it was — which is how this shipped: run_clear guarded the DECK row, the flights stand in the row
	# below, and nothing tested that row at all. A door opening into a flight's tile puts the side of
	# a staircase across the opening.
	#
	# The <= is load-bearing. A wall door sits EXACTLY on its tile's edge, so a strict < reports zero
	# contacts on a dungeon that is full of them; the first measurement of this bug said "0" for that
	# reason and the plan view is what caught it out.
	var contacts := 0
	var nearest := 999.0
	for s in range(1, 61):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			for t: Vector2i in ctx.shape.tiles():
				if not ctx.shape.is_ramp(t):
					continue
				for probe in [ctx.shape.tile_centre(t),
						ctx.shape.tile_centre(t - ctx.shape.ramp_dir(t))]:
					for e: DungeonLayout.Edge in rd.edges:
						if e.dir.x == 0 and e.dir.z == 0:
							continue
						var d := DungeonLayout.door_local(rd, e)
						var dx: float = absf(d.x - probe.x)
						var dz: float = absf(d.z - probe.z)
						nearest = minf(nearest, Vector2(dx, dz).length())
						if dx <= RoomShape.TILE * 0.5 + 0.01 and dz <= RoomShape.TILE * 0.5 + 0.01:
							contacts += 1
	_check(contacts == 0, "%d flight tiles or feet share a tile with a doorway — you come through "
			% contacts + "the door into the side of a staircase")

	# THE ZONE GRAPH SAYS WHAT THE ROOM IS FOR, AND THE TILES FOLLOW. Two things, and the second is
	# the one worth having.
	#
	# First: a program declares a zone off level 0 exactly when its rooms get one. That is the
	# vocabulary being connected to the outcome rather than sitting beside it.
	#
	# Second, and this is the whole point of a relation: `reach` is what puts the stairs in. The
	# program never says "ramp" — it says a body must be able to get from the ground to the walk, and
	# because the levels differ that IMPLIES a flight. Take the relation away and the walk is refused
	# outright rather than built as a shelf, because a zone nobody can stand on is a hole in the
	# room's program. Driven here rather than left to a sabotage, since it is the difference between
	# a program that describes a feature and one that describes a purpose.
	var with_zone := {}
	for name: String in RoomProgram.PROGRAMS:
		for z: Dictionary in RoomProgram.zones_of(name):
			if int(z.get("level", 0)) != 0:
				with_zone[name] = true
	_check(with_zone.size() >= 2,
			"only %d programs declare a zone off level 0 — the vocabulary is barely used"
					% with_zone.size())
	var zoned_rooms := 0
	var unzoned_rooms := 0
	for s in range(1, 21):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			var declares: bool = with_zone.has(RoomProgram.for_room(rd))
			if ctx.shape.level_count() > 0:
				zoned_rooms += 1
				_check(declares, "seed %d %s: a room whose program declares no raised zone came out "
						% [s, cell] + "with %d tiles off level 0" % ctx.shape.level_count())
			elif declares:
				unzoned_rooms += 1
	_check(zoned_rooms > 0, "no room in 20 seeds was zoned off level 0")
	_check(unzoned_rooms > 0, "every room that declared a raised zone got one — then the refusal "
			+ "paths (carving, doors, no room for the flights) are not being exercised at all")

	# AND THE RELATION IS LOAD-BEARING. Same room, same program, one relation removed.
	var probe_rd: DungeonLayout.RoomData = null
	for s in range(1, 21):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var c := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, c)
			if c.shape.level_count() > 0:
				probe_rd = rd
				break
		if probe_rd != null:
			break
	_check(probe_rd != null, "no zoned room in 20 seeds to test the reach relation on")
	if probe_rd != null:
		var bare := RoomContext.create(probe_rd, 1)
		bare.footprint = DungeonLayout.size_of(probe_rd)
		bare.shape = RoomShape.for_room(probe_rd)
		var zs := RoomProgram.zones_of(RoomProgram.for_room(probe_rd))
		for z: Dictionary in zs:
			if int(z.get("level", 0)) != 0:
				TileProgram._place_walk(probe_rd, bare, z, [], [] as Array[Vector2i])  # no relations
		_check(bare.shape.level_count() == 0,
				"a walk zone with no reach relation was built anyway — %d tiles were raised with no "
				% bare.shape.level_count() + "way onto them")

	# THE CAMERA BUDGET, which replaces "the gallery goes on the far row because we tried the near
	# one and the screenshots were bad". That was a rule about one feature rather than about the
	# thing that made it wrong, so the next pass to raise a floor would have had to rediscover it.
	# The thing that made it wrong is a number, and the number is now the rule.
	var worst := 0.0
	var worst_at := ""
	for s in range(1, 61):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			_check(ctx.shape.camera_legal(),
					"seed %d %s: the room's levels hide %.1f%% of its floor from the camera, past "
					% [s, cell, ctx.shape.hidden_fraction() * 100.0]
					+ "the %.0f%% budget" % (RoomShape.MAX_HIDDEN * 100.0))
			if ctx.shape.hidden_fraction() > worst:
				worst = ctx.shape.hidden_fraction()
				worst_at = "seed %d %s" % [s, cell]
	# THE BIAS MUST STILL DOMINATE. camera_legal already refuses anything past the budget; what this
	# guards is subtler and is the thing a budget invites — that spending a little becomes spending a
	# little everywhere. The far end costs nothing and the near end costs something, so most rooms
	# with a level in them should still be paying zero, and the ones that are not should be nowhere
	# near the ceiling.
	#
	# It was `worst == 0.0` when it was written, which was true and is no longer: an apse takes the
	# near end when the far one carries the door, deliberately and within budget. A pin that
	# describes a state has to become one that describes an invariant the moment the state moves.
	var costed := 0
	var cost_sum := 0.0
	for s in range(1, 61):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			if ctx.shape.level_count() == 0:
				continue
			costed += 1
			cost_sum += ctx.shape.hidden_fraction()
	var mean_cost := cost_sum / maxf(costed, 1)
	# THE MEAN, NOT A HEADCOUNT. This was "most rooms with a level should still pay nothing", which
	# was true while every level went UP against the far wall and became false the moment a pit
	# shipped: a pit's own near rim hides part of the pit, so a sunken room pays by nature. Counting
	# payers therefore measured how many pits exist rather than whether the dungeon is spending
	# casually, which is the thing worth guarding.
	#
	# camera_legal already caps any single room at MAX_HIDDEN. This is the other half: the average
	# room with a level in it should be nowhere near that cap, so a budget cannot quietly become a
	# target.
	_check(mean_cost <= RoomShape.MAX_HIDDEN * 0.35,
			"the average room with a level hides %.1f%% of its floor, more than a third of the "
			% (mean_cost * 100.0) + "%.0f%% budget — the budget is becoming a target"
					% (RoomShape.MAX_HIDDEN * 100.0))
	# 0.6, RAISED FROM 0.5 WHEN PITS SHIPPED. A deck's cost is what it hides BEHIND it and a pit's is
	# part of itself, so a pit is legitimately the more expensive shape — the ceiling has to leave
	# room for the cheap direction to still be affordable.
	_check(worst <= RoomShape.MAX_HIDDEN * 0.6,
			"the worst room hides %.1f%% of its floor (at %s), over half the whole budget — one "
			% [worst * 100.0, worst_at] + "room should not be spending that much of it")

	# AND THE RULE HAS TEETH, checked where the dungeon cannot reach yet. A deck on the row NEAREST
	# the camera hides 0.90 m of the floor behind it per level of drop.
	var near := RoomShape.full(5, 3)
	for i in 5:
		near.set_level(Vector2i(i, 2), 1)              # row 2 is the +Z row, closest to the lens
	var want := 5.0 * RoomShape.TILE * RoomShape.LEVEL_RISE / tan(DungeonRoom.FRAME_PITCH)
	_check(is_equal_approx(near.hidden_by_levels(), want),
			"a near-row deck hides %.2f m2, not the %.2f its 0.90 m per level makes"
					% [near.hidden_by_levels(), want])
	_check(near.camera_legal(), "one level on the near row is %.1f%% and inside the budget"
			% (near.hidden_fraction() * 100.0))
	var deep := RoomShape.full(5, 3)
	for i in 5:
		deep.set_level(Vector2i(i, 2), 2)
	_check(not deep.camera_legal(),
			"a TWO-level boundary facing the camera is legal — it hides 1.8 m of the floor behind "
			+ "it, which is a body standing there entirely out of sight")
	# The far row costs nothing whatever its drop, which is the asymmetry the bias rests on.
	var far := RoomShape.full(5, 3)
	for i in 5:
		far.set_level(Vector2i(i, 0), 3)
	_check(far.hidden_by_levels() == 0.0 and far.camera_legal(),
			"a deck on the FAR row hides %.2f m2 — it should hide nothing, its riser faces the lens"
					% far.hidden_by_levels())

	_out("[VERIFY] reach suite: %d rooms walked, %d with a level change, %d regions off level 0, "
			% [rooms, levelled, raised_regions] + "camera cost mean %.1f%% worst %.1f%% of %.0f%%"
					% [mean_cost * 100.0, worst * 100.0, RoomShape.MAX_HIDDEN * 100.0])


## THE WALL RUN, which nothing in the dungeon builds yet.
##
## That is worth stating plainly rather than burying: this suite is the fixture's only user until a
## room program asks for one in M8. It lands now because the plan orders it before the zone graph and
## because a mechanism whose first caller and first test arrive together gets neither reviewed
## properly — but a capability with no caller is only as real as the test that drives it, so this
## drives the whole path: shape, wall list, slot, courses, dresser, and the veil stamp on the way out.
func _wall_run_suite() -> void:
	var lay := DungeonLayout.generate(1, 9)
	var rd: DungeonLayout.RoomData = null
	for cell: Vector3i in lay.rooms:
		var c: DungeonLayout.RoomData = lay.rooms[cell]
		if c.type == DungeonLayout.RoomType.COMBAT:
			rd = c
			break
	_check(rd != null, "no COMBAT room at seed 1 to build a wall run in")
	if rd == null:
		return

	var ctx := RoomContext.create(rd, lay.seed_used)
	ctx.footprint = DungeonLayout.size_of(rd)
	ctx.shape = RoomShape.full(5, 3)
	var shape := ctx.shape
	# The whole -z face of a 5x3 room: five tiles, none of which has a neighbour that way.
	var before := shape.walls().size()
	_check(shape.add_wall_run(Vector2i(1, 0), Vector2i(0, -1), 4),
			"a 4-tile run down an open face was refused")
	var runs := shape.walls()

	# ONE RUN WHERE THERE WERE FOUR. The count is the assertion: if consumes_wall missed a tile the
	# run would be joined by a stray 4 m module inside it, and if it claimed too much a neighbouring
	# wall would vanish — the first shows as 4 - 1 + 1, the second as fewer.
	_check(runs.size() == before - 3,
			"a 4-tile run left %d walls where %d were expected — it either did not replace its four "
			% [runs.size(), before - 3] + "modules or it swallowed a neighbour's")
	var longs: Array = []
	for w: Dictionary in runs:
		if w.role == "long":
			longs.append(w)
	_check(longs.size() == 1, "%d runs carry the 'long' role, not 1" % longs.size())
	if longs.size() == 1:
		var w: Dictionary = longs[0]
		_check(is_equal_approx(float(w.span), 4.0 * RoomShape.TILE),
				"the run's span is %.2f m, not the 16 its four tiles make" % w.span)
		# CENTRED ON ITS OWN BLOCK. Off by half a module and the run overhangs one end of the face
		# and leaves a 4 m hole at the other — a gap in the room's shell you can walk out of.
		var lo := shape.tile_centre(Vector2i(1, 0))
		var hi := shape.tile_centre(Vector2i(4, 0))
		_check(is_equal_approx((w.at as Vector3).x, (lo.x + hi.x) * 0.5),
				"the run sits at x=%.2f, not its block's centre %.2f"
						% [(w.at as Vector3).x, (lo.x + hi.x) * 0.5])
		# AND THE OTHER SIDES OF ITS OWN TILES SURVIVE. The run covers one face; a tile under it that
		# is also on the room's edge still needs its own outward wall, and consumes_wall returning
		# true for every side would quietly open the room up.
		_check(shape.consumes_wall(Vector2i(1, 0), Vector2i(0, -1)),
				"the run does not own the face it was built on")
		_check(not shape.consumes_wall(Vector2i(1, 0), Vector2i(-1, 0)),
				"the run owns a side it was not built on — that deletes its neighbours' walls")

	# THROUGH THE PLAN AND THE DRESSER. The span has to survive the wall slot, the courses above it,
	# and the piece factory; any one hop can drop it while the others still look right.
	# _plan_walls, NOT plan_shell: plan_shell PICKS the footprint, so it would replace the shape the
	# run was installed into and wall a different room. That is also why the loop is split out — a
	# pass that installs a fixture and then wants its geometry needs somewhere to call in.
	RoomPlan._plan_walls(rd, ctx, Vector3.ZERO)
	var wall_slots := 0
	var course_slots := 0
	var built := 0
	for slot: RoomContext.Slot in ctx.slots:
		if slot.role != "long":
			continue
		_check(slot.span == Vector2i(4, 1), "a 'long' %s slot carries span %s, not (4, 1)"
				% [slot.tag, slot.span])
		if slot.tag == RoomPlan.T_WALL:
			wall_slots += 1
		elif slot.tag in RoomDresser.COURSE_TAGS:
			course_slots += 1
		var node := RoomDresser._instantiate(slot, ctx, null)
		if node == null:
			continue
		built += 1
		var got := _collider_x(node)
		if got <= 0.0:                              # a course has no collider; measure its mesh
			for n in _walk(node):
				if n is MeshInstance3D and (n as MeshInstance3D).mesh is BoxMesh:
					got = maxf(got, ((n as MeshInstance3D).mesh as BoxMesh).size.x)
		_check(is_equal_approx(got, 4.0 * RoomShape.TILE),
				"the dresser built a %.2f m piece for a 16 m '%s' run" % [got, slot.tag])
		# AND IT IS THE AUTHORED ARCADE, NOT A STRETCHED BOX. Kit.run_piece falls back to a greybox for
		# any length nobody has drawn, which is the right degradation and an invisible failure: the box
		# is the correct 16 m, carries the correct collider, and passes every line above. The whole
		# point of a run is to carry a feature ACROSS the tile joints, so a run that renders as one flat
		# panel has failed at the only thing it exists for while measuring perfect.
		#
		# Found the slow way. The lookup key is the MODULE name, and a themed wall is still
		# "wall_straight" (the theme lists variants under that name rather than renaming the tag) — but
		# nothing said so, and an hour went into photographing a wall to decide whether the art was
		# reaching the scene at all. This is that hour, written down.
		if slot.tag == RoomPlan.T_WALL:
			var authored := 0
			for n in _walk(node):
				if n is MeshInstance3D and not ((n as MeshInstance3D).mesh is BoxMesh):
					authored = maxi(authored, (n as MeshInstance3D).mesh.get_faces().size())
			_check(authored > 500,
					"the 16 m run built %d authored vertices — it fell back to the stretched greybox, "
							% authored + "so the arcade that is the run's whole reason for existing is "
							+ "not in the scene")
		# THE VEIL MUST BE TOLD THE TRUTH ABOUT IT. COURSE_SPAN used to come from span_of(role), and
		# a role says nothing about a run's length — a 16 m course stamped 4 m is veiled as though its
		# far end were not over the player's head, which is the exact failure the veil was taught
		# extents to end.
		# ASSERTED, NOT CONDITIONED ON. Guarded with has_meta() first, and that let the real bug
		# through silently: the stretched piece was being returned before the stamping block ran, so
		# it carried no COURSE_META either and the check simply skipped. A conditional assertion
		# passes loudest exactly when the thing it guards has gone missing.
		if slot.tag in RoomDresser.COURSE_TAGS:
			_check(node.has_meta(RoomDresser.COURSE_META),
					"a 16 m %s carries no COURSE_META — CourseVeil will never collect it, and "
					% slot.tag + "_cutaway_suite exempts it from the occlusion sweep regardless")
			_check(node.has_meta(RoomDresser.COURSE_SPAN)
					and is_equal_approx(float(node.get_meta(RoomDresser.COURSE_SPAN)),
							4.0 * RoomShape.TILE),
					"a 16 m course is stamped %s m for CourseVeil"
							% node.get_meta(RoomDresser.COURSE_SPAN, "nothing"))
		node.free()
	_check(wall_slots == 1, "%d wall slots came out of one run" % wall_slots)
	_check(course_slots == 3, "%d course slots over one run, expected band, upper and cornice"
			% course_slots)
	_check(built == wall_slots + course_slots, "%d of %d 'long' slots built anything"
			% [built, wall_slots + course_slots])

	# A DOORWAY IS A PRE-COLLAPSED CELL. Refused outright — not shortened, not nudged — because
	# Kit._doorway hard-codes its jambs to a 4 m module and _plan_suite asserts one doorway slot per
	# exit, so a run over a door produces a blank wall where the exit was and seals the room.
	var door_ctx := RoomContext.create(rd, lay.seed_used)
	door_ctx.footprint = DungeonLayout.size_of(rd)
	door_ctx.shape = RoomShape.for_room(rd)
	var refused := 0
	var offered := 0
	for e: DungeonLayout.Edge in rd.edges:
		var hd := Vector2i(e.dir.x, e.dir.z)
		if hd == Vector2i.ZERO:
			continue
		var door := DungeonLayout.door_local(rd, e)
		var t := door_ctx.shape.tile_at(door)
		var along := Vector2i(-hd.y, hd.x)
		offered += 1
		# Anchored one tile back along the wall so the run straddles the door rather than starting on
		# it — the case a length check alone would wave through.
		if not RoomPlan.try_wall_run(rd, door_ctx, t - along, hd, 3):
			refused += 1
	_check(offered > 0, "seed 1's room has no horizontal exit, so the doorway rule never ran")
	_check(refused == offered, "%d of %d runs straddling a doorway were accepted — each one seals "
			% [refused, offered] + "the exit it covers")
	_check(door_ctx.shape.fixture_count() == 0, "a refused run was installed anyway")
	_out("[VERIFY] wall run suite: 4 tiles to one 16 m piece, courses and veil stamp follow, "
			+ "%d doorway straddles refused" % refused)


## PASS INDEPENDENCE — a later pass may not disturb an earlier one's output.
##
## This is the property the crypt actually rests on, it is claimed in two comments
## (room_plan.gd's "own RNG stream, so re-tuning prop density can never reshuffle the fight" and
## room_context.gd's "one stream per pass is the point"), and until this suite it was asserted
## nowhere. _determinism_suite is not it: rebuilding one seed twice compares a pipeline against
## itself, so a pass that reaches back and moves an earlier decision passes it every time — it moves
## the same decision the same way on both runs.
##
## It lands NOW, before the zone solver, so it is a baseline rather than a reaction. A solver that
## searches and backtracks is free to do so INSIDE its own pass; what it may never do is reach into
## what a previous pass committed. The difference is invisible in a screenshot and this is the only
## thing that can see it.
##
## Two independent halves, because neither catches the other's failure:
##
##  1. PREFIX INVARIANCE. Run the pipeline to depth k and to depth k+1 from fresh contexts; the
##     shorter run's whole output must survive verbatim in the longer one. Catches a later pass
##     mutating a slot, moving the shape, or re-reserving occupancy.
##  2. STREAM DISJOINTNESS. Prefix invariance cannot see the subtler failure, because earlier passes
##     always run first: if two passes draw from ONE named stream, the later one's numbers depend on
##     how many the earlier drew, and re-tuning either silently reshuffles the other. Both rooms
##     still look fine. Only the RNG's own state can tell, so the state of every open stream is
##     snapshotted between passes and any pre-existing one that MOVED is a violation.
##
## THE DECOMPOSITION IS ITSELF ASSERTED. Driving the passes one at a time means this suite keeps its
## own copy of the order plan_interior runs them in, and a copy that drifts is a test that proves
## something about a pipeline nobody ships. So the last depth is compared against a context built by
## calling the real plan_interior: if the two disagree, the decomposition below is wrong and the
## suite says so instead of quietly testing the wrong thing.
func _independence_suite() -> void:
	var checked := 0
	var types := {}
	var plan_hash := 0
	for s in range(1, 25):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			types[rd.type] = true
			var depths := _pass_names(rd)
			var prev := ""
			for k in range(1, depths.size() + 1):
				var ctx := RoomContext.create(rd, lay.seed_used)
				_run_passes(rd, ctx, k)
				var sig := _plan_signature(ctx)
				_check(sig.begins_with(prev),
						"seed %d %s: running through '%s' changed what '%s' had already decided"
								% [s, cell, depths[k - 1], depths[k - 2] if k > 1 else "nothing"])
				prev = sig

			# THE DECOMPOSITION, checked against the shipped one.
			var real := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, real)
			RoomPlan.plan_interior(rd, real)
			plan_hash = hash("%d|%s|%s" % [plan_hash, cell, _plan_signature(real)])
			_check(_plan_signature(real) == prev,
					("seed %d %s: _run_passes no longer reproduces plan_interior — the pass list"
					+ " in _pass_names has drifted from room_plan.gd") % [s, cell])

			# STREAMS. One context, walked pass by pass, watching for a stream that a later pass
			# drew from after an earlier one had already opened it.
			var watch := RoomContext.create(rd, lay.seed_used)
			var before := {}
			for k in range(1, depths.size() + 1):
				_run_passes(rd, watch, k, k - 1)
				var after := watch.stream_states()
				for name: String in before:
					_check(after[name] == before[name],
							("seed %d %s: pass '%s' drew from stream '%s', which an earlier pass"
							+ " had already opened — re-tuning either reshuffles the other")
									% [s, cell, depths[k - 1], name])
				before = after
			checked += 1
	_check(types.size() >= 4,
			("independence suite saw only %d room types — it is not covering the branches"
			+ " plan_interior takes") % types.size())
	# THE WHOLE PLAN, PINNED. The wall hash holds walls() still; this holds everything a gameplay
	# pass decides — every tile with its level, every bevel and ramp, every slot with its tag, role,
	# position, footprint, facing and span, and every spawn, in the order they were decided.
	#
	# It exists for the zone graph. TileProgram replaces the hard-coded gallery and dais with zones
	# and relations, and the plan is explicit that the first commit of that work must produce
	# IDENTICAL tiles, levels and fixtures before the old passes are deleted — otherwise "the zone
	# vocabulary can express what we already had" is an argument rather than a fact, and any drift
	# hides inside a rewrite big enough to explain it away.
	_check(plan_hash == PINNED_PLAN_HASH,
			"the plan over 24 seeds hashes to %d, not the pinned %d — something a gameplay pass "
			% [plan_hash, PINNED_PLAN_HASH] + "decides has moved")
	_out("[VERIFY] independence suite: %d rooms, %d types, prefix + stream state"
			% [checked, types.size()])


## The passes plan_interior runs, in order, for THIS room. Mirrors room_plan.gd:280-316 including
## its early returns — and the mirror is what _independence_suite's decomposition check verifies.
func _pass_names(rd: DungeonLayout.RoomData) -> Array[String]:
	if rd.type == DungeonLayout.RoomType.STAIR:
		return ["shell", "key"]
	var out: Array[String] = ["shell", "dais"]
	if rd.type == DungeonLayout.RoomType.TREASURE:
		out.append("focal")
	out.append_array(["key", "weave"])
	match rd.type:
		DungeonLayout.RoomType.START, DungeonLayout.RoomType.TREASURE:
			pass
		DungeonLayout.RoomType.BOSS:
			out.append("boss")
		_:
			out.append("encounter")
	return out


## Run the first `upto` passes, skipping the first `from` — so a caller can either build a fresh
## context to a depth or advance one it is already watching by a single pass.
func _run_passes(rd: DungeonLayout.RoomData, ctx: RoomContext, upto: int, from: int = 0) -> void:
	var names := _pass_names(rd)
	var lift := 0.0
	var spots: Array[Vector3] = []
	for k in range(0, upto):
		# The dais and the weave HAND VALUES FORWARD, so a run that skips them still has to produce
		# them for the passes that follow. Recomputed rather than cached, which is sound precisely
		# because this is the property under test: if replaying an earlier pass gave a different
		# answer, prefix invariance would already have failed.
		match names[k]:
			"shell":
				if k >= from:
					RoomPlan.plan_shell(rd, ctx)
			"dais":
				lift = TileProgram.plinth(rd, ctx)
			"focal":
				if k >= from:
					ctx.add_slot_at(RoomPlan.T_FOCAL, Vector3(0.0, lift, 0.0), RoomPlan.FOCAL_SIZE)
			"key":
				if k >= from:
					RoomPlan._plan_key(rd, ctx)
			"weave":
				spots = RoomWeave.weave(rd, ctx)
			"boss":
				if k >= from:
					RoomPlan._plan_boss(ctx)
			"encounter":
				if k >= from:
					RoomPlan.plan_encounter(rd, ctx, spots)


## Everything a gameplay pass has decided, in the order it decided it. ORDER-PRESERVING on purpose,
## unlike _build_signature's sorted list: prefix invariance is a statement about a sequence, and a
## sorted signature would call an insertion in the middle a legal append.
func _plan_signature(ctx: RoomContext) -> String:
	var lines: Array[String] = []
	var shape := ctx.shape
	if shape != null:
		for t: Vector2i in shape.tiles():
			lines.append("tile %d,%d l%d %s%s" % [t.x, t.y, shape.level_of(t),
					"C" if shape.is_chamfer(t) else "-", "R" if shape.is_ramp(t) else "-"])
	for slot: RoomContext.Slot in ctx.slots:
		var b := slot.transform.basis
		lines.append("slot %s/%s %.3f,%.3f,%.3f fp%.2f,%.2f out%d,%d yaw%.4f"
				% [slot.tag, slot.role, slot.transform.origin.x, slot.transform.origin.y,
						slot.transform.origin.z, slot.footprint.x, slot.footprint.y,
						slot.out.x, slot.out.y, b.get_euler().y])
	for def in ctx.spawn_defs:
		lines.append("spawn %s %.3f,%.3f,%.3f" % [def.kind, def.pos.x, def.pos.y, def.pos.z])
	# Trailing newline, so "tile 1,1" cannot pass as a prefix of "tile 1,10".
	return "\n".join(lines) + "\n"


## Every tag the plan can emit must resolve in the shipped theme, or a room silently loses pieces.
## THE COMPOSITION, which nothing else here can see.
##
## _plan_suite already proves every slot is legal — on real floor, inside the room, not overlapping,
## not blocking a door. All of that was equally true of the blind 3 m lattice the weave replaced.
## What it cannot tell you is whether the arrangement MEANS anything, and that is the only reason
## the weave exists: a refectory has to read as a refectory, and it does that by being regular.
##
## So this suite asserts the properties an arrangement has and a sprinkle does not.
func _weave_suite() -> void:
	var seen_programs := {}
	var lit_rooms := 0
	var aisle_rooms := 0
	for s in range(1, 41):
		var lay := DungeonLayout.generate(s, 9)
		for cell: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[cell]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			RoomPlan.plan_interior(rd, ctx)
			# A stairwell is never woven (see RoomProgram.for_room), so it has no program and its
			# lighting is still the dresser's. Counting it would report an empty program name.
			if rd.type == DungeonLayout.RoomType.STAIR:
				_check(ctx.program == "", "seed %d %s: a stair room was woven" % [s, cell])
				continue
			seen_programs[ctx.program] = int(seen_programs.get(ctx.program, 0)) + 1

			var anchors := ctx.slots_tagged(RoomPlan.T_WALL_ANCHOR)
			# EITHER the plan owns the lighting or the dresser does — never a half of each.
			# RoomDresser skips its own perimeter pass on seeing ANY anchor (room_dresser.gd:105),
			# so one anchor is strictly worse than none: it suppresses the fallback and leaves the
			# room under the two-light floor _check_room_lighting enforces at build time.
			_check(anchors.is_empty() or anchors.size() >= RoomProgram.MIN_LIGHTS,
					"seed %d %s (%s): %d anchors — below the light floor, and the dresser's "
					% [s, cell, ctx.program, anchors.size()]
					+ "fallback is suppressed by the first one")
			if not anchors.is_empty():
				lit_rooms += 1
			for a: RoomContext.Slot in anchors:
				var at: Vector3 = a.transform.origin
				_check(ctx.shape.contains(at),
						"seed %d %s: light mount at %s is over a hole" % [s, cell, at])
				# The clearance the dresser is held to, applied to the plan that took its job over.
				for e: DungeonLayout.Edge in rd.edges:
					if e.dir.x == 0 and e.dir.z == 0:
						continue
					var door := DungeonLayout.door_local(rd, e)
					door.y = at.y
					_check(at.distance_to(door) >= RoomDresser.MOUNT_DOOR_CLEARANCE - 0.01,
							"seed %d %s: light mount in the %s doorway" % [s, cell, e.dir])

			# REGULARITY, the property that separates a composition from a sprinkle. In a room whose
			# program lays cover in rows, the pieces must share a line — so for each piece there is
			# another at the same local x or the same local z. A random scatter fails this.
			var rules := RoomProgram.rules(ctx.program)
			if rules["cover"] == RoomProgram.P_FLANK or rules["cover"] == RoomProgram.P_COLONNADE:
				var cover: Array[Vector3] = []
				for tag in [RoomPlan.T_COVER_LARGE, RoomPlan.T_COVER_SMALL]:
					for slot: RoomContext.Slot in ctx.slots_tagged(tag):
						cover.append(slot.transform.origin)
				if cover.size() >= 3:
					aisle_rooms += 1
					var aligned := 0
					for a2: Vector3 in cover:
						for b: Vector3 in cover:
							if a2 == b:
								continue
							# 1.0, not 0.01: _place jitters each piece by up to +-0.45 to break the
							# machined look, so "same line" has to mean the line the row sits on.
							if absf(a2.x - b.x) < 1.0 or absf(a2.z - b.z) < 1.0:
								aligned += 1
								break
					_check(aligned >= cover.size() - 1,
							"seed %d %s (%s): only %d of %d cover pieces share a line — the row "
							% [s, cell, ctx.program, aligned, cover.size()]
							+ "reads as scatter")

	# Every program must actually occur. One that never fires is a rule nobody is testing and a
	# room kind nobody is getting.
	for name in RoomProgram.PROGRAMS:
		_check(seen_programs.has(name), "program '%s' never ran in 40 seeds" % name)
	# AND THE ONES A QUOTA COMPETES FOR NEED A FLOOR, not just a pulse. A colosseum wants a hall and
	# a hall is the ONLY host `refectory` has; a prison will take a vault when no cell is free, and a
	# vault is the only host `reliquary` has. "Occurs at least once in 40 seeds" cannot see the
	# difference between a program that is uncommon and one that has been all but eaten — dropping
	# the seater's "an opportunistic purpose may not delete another" rule takes refectory from 19 to
	# 8 and passes every other check in this file, because the only other thing that moves is a
	# pinned hash, and a pin is a change detector rather than a guard.
	for spec in [["refectory", 12], ["reliquary", 4]]:
		var got: int = int(seen_programs.get(spec[0], 0))
		_check(got >= int(spec[1]),
				"program '%s' ran %d times in 40 seeds, under its floor of %d — a quota has eaten "
				% [spec[0], got, spec[1]] + "the only host it has")
	_check(aisle_rooms >= 10, "only %d rooms laid cover in rows — the patterns are not firing"
			% aisle_rooms)
	# A FLOOR ON HOW MANY ROOMS THE PLAN LIGHTS, which lit_rooms did not have — it was counted,
	# printed and never asserted. The per-room check above is `anchors.is_empty() or >= MIN_LIGHTS`,
	# and an empty list satisfies it, so a change that made the mount pass place too few would call
	# _drop_mounts on every room in the dungeon and pass this suite in full: every room lit by the
	# dresser's perimeter ring instead of by its program, and the only visible difference a printed
	# count nobody compares. That is precisely the failure a long wall run would have caused, so the
	# floor lands with the mechanism.
	#
	# 200 of the ~360 rooms 40 seeds produce. Well under today's number, because this is a guard
	# against collapse and not a pin on the lighting rules.
	_check(lit_rooms >= 200,
			"only %d rooms were lit by their own program — the rest fell back to the dresser's "
			% lit_rooms + "perimeter ring, which is what _drop_mounts does when the pass runs short")
	var parts: Array[String] = []
	for name in seen_programs:
		parts.append("%s %d" % [name, seen_programs[name]])
	parts.sort()
	_out("[VERIFY] weave suite: %d rooms lit by plan, %d in rows — %s"
			% [lit_rooms, aisle_rooms, ", ".join(parts)])


func _theme_suite() -> void:
	var theme := load("res://scenes/dungeon/themes/crypt.tres") as DungeonTheme
	_check(theme != null, "crypt theme missing or not a DungeonTheme")
	if theme == null:
		return
	for tag: String in RoomPlan.ALL_TAGS:
		_check(RoomDresser.piece_for(tag, theme) != "",
				"crypt theme: tag '%s' resolves to no piece" % tag)
	# a listed variant that fails to load would silently fall through to the greybox
	for tag in theme.pieces:
		for scene in theme.pieces[tag]:
			_check(scene != null, "crypt theme: null variant listed under '%s'" % tag)

	# PAINT ACTUALLY REACHES THE MESH. `piece_tints` travels theme -> Kit.dress -> an instance
	# uniform, and every link fails QUIETLY: set_instance_shader_parameter is a no-op on a mesh with
	# no material_override, a renamed uniform is ignored, and a key that matches no piece name simply
	# never fires. All three leave a crypt that builds, runs and is the colour it was before — which
	# is indistinguishable from "the tint values need tuning" and sends you to the wrong file.
	var painted := 0
	for key in theme.piece_tints:
		var piece_name := String(key)
		var want := theme.tint_for(piece_name)
		_check(want.w > 0.0, "crypt theme: piece_tints['%s'] has zero strength" % piece_name)
		var node := Kit.piece(piece_name, theme, 0.25)
		var got: Variant = null
		for m in _walk(node):
			if m is MeshInstance3D:
				got = (m as MeshInstance3D).get_instance_shader_parameter("piece_tint")
				break
		_check(got != null and (got as Vector4).is_equal_approx(want),
				"crypt theme: '%s' should carry tint %s but the mesh reads %s"
				% [piece_name, want, str(got)])
		painted += 1
		node.free()
	# THE FLOOR INLAY. Two things, both of which have already gone wrong once.
	#
	# It must RESOLVE: the roles are derived in RoomDresser and never appear in RoomPlan.ALL_TAGS, so
	# the loop above cannot see them. When these first shipped they fell straight through to a code
	# greybox because Kit._resolve reads theme.pieces and scenes/dungeon/kit/*.tscn and nothing else
	# — the .glb existed, was exported, and was never loaded by anything.
	#
	# It must NOT COLLIDE. MapPainter classifies floor-vs-wall per CollisionObject3D, so a second
	# body on a floor tile is at best redundant and at worst flips the tile to WALL and drops a
	# carved room under verify_map's truncation guard.
	for role in ["border", "corner", "threshold", "medallion"]:
		var inlay := RoomDresser.piece_for(RoomDresser.INLAY_TAG, theme, role)
		_check(inlay != "", "crypt theme: floor inlay role '%s' resolves to no piece" % role)
		if inlay == "":
			continue
		var node := Kit.piece(inlay, theme, 0.3)
		var meshes := 0
		for m in _walk(node):
			_check(not (m is CollisionObject3D),
					"floor inlay '%s' carries collision — it must never reach MapPainter" % inlay)
			if m is MeshInstance3D:
				meshes += 1
		_check(meshes > 0, "floor inlay '%s' built nothing" % inlay)
		node.free()

	# GRASS AT THE SKIRTING. Asserted on the placement function rather than on the built MultiMesh
	# because the built one cannot be inspected here: this suite runs headless, the dummy rendering
	# driver keeps no instance buffer, and MultiMesh.get_instance_transform comes back as identity
	# for every instance. A probe written against it reports zero tufts anywhere and looks exactly
	# like a placement bug.
	#
	# MEASURED AGAINST THE WALL FACE, NOT THE FOOTPRINT EDGE, which is the whole point. The first
	# version of this check measured to footprint/2 and passed at 44% while every one of those tufts
	# was 0.6 m inside the masonry — a green result for grass nobody could see. footprint/2 is a grid
	# line; the wall stands proud of it.
	var ctx := RoomContext.new()
	ctx.footprint = Vector3(20.0, 6.0, 12.0)
	var face_x: float = 10.0 - RoomDebris.WALL_FACE
	var face_z: float = 6.0 - RoomDebris.WALL_FACE
	var trng := RandomNumberGenerator.new()
	trng.seed = 4242
	var near_wall := 0
	var on_long := 0
	var inside_wall := 0
	const N := 4000
	for i in N:
		var at: Vector3 = RoomDebris._place_tuft(ctx, trng)
		var dx: float = face_x - absf(at.x)
		var dz: float = face_z - absf(at.z)
		if minf(dx, dz) < 0.0:
			inside_wall += 1
		if minf(dx, dz) <= RoomDebris.WALL_SPREAD:
			near_wall += 1
			# a point pinned in z is against an X-running (long) wall, and vice versa
			if dz < dx:
				on_long += 1
	_check(inside_wall == 0,
			"%d of %d tufts landed behind the wall face — invisible, and the failure looks like "
			% [inside_wall, N] + "no grass at all rather than like a placement bug")
	# _place keeps its floor scatter FLOOR_INSET from the footprint edge, which is further out than
	# the wall band by construction, so anything within WALL_SPREAD of the face can only have come
	# from the wall path — the two populations do not overlap.
	_check(RoomDebris.FLOOR_INSET > RoomDebris.WALL_FACE + RoomDebris.WALL_SPREAD,
			"FLOOR_INSET %.2f no longer clears the wall band; the two tuft populations now overlap"
			% RoomDebris.FLOOR_INSET)
	var wall_frac := float(near_wall) / N
	_check(absf(wall_frac - RoomDebris.WALL_BIAS) < 0.06,
			"tufts at the skirting: %.2f, expected ~%.2f" % [wall_frac, RoomDebris.WALL_BIAS])
	# 18.8 m of long wall against 10.8 m of short, once the wall face is taken off both: roughly two
	# thirds of the skirting is long wall, and drawing the side uniformly instead would put half the
	# grass on a third of the perimeter.
	var long_frac := float(on_long) / maxi(near_wall, 1)
	var want_long: float = face_x / (face_x + face_z)
	_check(absf(long_frac - want_long) < 0.06,
			"skirting tufts on the long walls: %.2f, expected ~%.2f" % [long_frac, want_long])

	_out("[VERIFY] theme suite: %d tags resolve, %d pieces painted, 4 inlay roles, "
			% [RoomPlan.ALL_TAGS.size(), painted]
			+ "%.0f%% of tufts at the skirting (%.0f%% of those on the long walls)"
			% [wall_frac * 100.0, long_frac * 100.0])


## Instantiate the real zone for a handful of seeds and check the built scene. Async because
## _ready of nodes added during _initialize only runs once frames process — await one per seed.
func _build_suite() -> void:
	await _veil_suite()
	for s in [1, 2, 3, 5, 8, 13, 21, 42, 99, 137]:
		var zc := (load("res://scenes/world/zone_crypt.tscn") as PackedScene).instantiate()
		zc.dungeon_seed = s
		root.add_child(zc)
		await process_frame                              # let the _ready cascade generate
		var lay: DungeonLayout = zc.layout
		_check(zc.find_child("SpawnA", true, false) != null, "seed %d: no SpawnA" % s)
		var rp = zc.find_child("ReturnPortal", true, false)
		_check(rp != null, "seed %d: no ReturnPortal" % s)
		if rp:
			_check(rp.target_zone_path == "res://scenes/world/room.tscn",
					"seed %d: ReturnPortal wrong zone" % s)
			_check(rp.target_spawn == "SpawnFromCrypt", "seed %d: ReturnPortal wrong spawn" % s)
		# door count == tree edges; rooms have triggers; combat rooms have spawns
		var edges := 0
		for cell: Vector3i in lay.rooms:
			edges += (lay.rooms[cell] as DungeonLayout.RoomData).edges.size()
		edges /= 2
		var doors := _count_type(zc, "DungeonDoor")
		_check(doors == edges, "seed %d: %d doors for %d edges" % [s, doors, edges])
		var rooms_checked := 0
		for node in _walk(zc):
			if node is DungeonRoom:
				rooms_checked += 1
				_check(node.has_node("RoomTrigger"), "seed %d: room without trigger" % s)
				_check_room_lighting(s, node as DungeonRoom, lay)
		_check(rooms_checked == lay.rooms.size(),
				"seed %d: %d room nodes for %d layout rooms" % [s, rooms_checked, lay.rooms.size()])
		# every generated StaticBody3D on world layer 1
		for node in _walk(zc):
			if node is StaticBody3D:
				_check(node.collision_layer == 1, "seed %d: StaticBody on layer %d" % [s, node.collision_layer])
		zc.free()
	_out("[VERIFY] build suite: 10 seeds done")
	await _dais_suite()
	await _determinism_suite()
	await _reskin_suite()
	await _lock_runtime_suite()
	await _cutaway_suite()
	await _shadow_suite()
	_finish()


## The two ends of one wall run, in room-local space. The half-length is the run's OWN, which for a
## bevelled corner is three different numbers — that is the point of the check that uses this.
func _run_ends(w: Dictionary) -> Array[Vector3]:
	var n := Vector3(w.out.x, 0.0, w.out.y).normalized()
	var along := Vector3(-n.z, 0.0, n.x)
	var half: float = float(w.span) * 0.5
	var at: Vector3 = w.at
	var out: Array[Vector3] = [at - along * half, at + along * half]
	return out


## THE RAISED PLATFORM. Three things, and the third is the only one that proves anything.
##
## A dais is floor at a different Y, in a project where NOTHING climbs a ledge — the player and every
## enemy are `move_and_slide` and gravity with no step logic whatsoever. So the arithmetic checks
## below (slope, height, classification) are necessary and are not sufficient: they would all pass on
## a platform with vertical sides. The walk probe is what says a body can actually get up there, and
## it runs from eight directions because "climbable from every side" is the entire reason this piece
## is a frustum instead of the one flight a dais would normally have.
##
## Driven in ISOLATION rather than inside a generated room, deliberately. In a real treasury the
## walker would meet cover, clutter and candelabra on the way in, and a probe that failed because a
## pillar was in the way would read exactly like a dais that cannot be climbed.
func _dais_suite() -> void:
	# BOTH PIECES, because there are two and only one of them is code. Kit.dais builds the greybox;
	# a theme listing a variant replaces it wholesale with a hand-authored wrapper whose collider is
	# retyped by hand in a .tscn. Nothing makes the two agree, the editor shows a box and a frustum
	# as equally plausible, and the way a mistake there presents is an altar the player can see and
	# never reach. So the probe runs against whichever piece the crypt would actually build.
	var theme := load("res://scenes/dungeon/themes/crypt.tres") as DungeonTheme
	var climbed := 0
	for named in [false, true]:
		var label := "crypt.tres's dais_a" if named else "Kit.dais's greybox"
		climbed += await _probe_dais(named, theme, label)
	_check(theme != null and theme.has_variants("dais"),
			"the crypt theme lists no dais variant — the art half of the check above ran on the "
					+ "greybox twice and proved nothing about the shipped piece")

	# THE PLAN-LEVEL RELATIONSHIP: whatever the room is about stands ON the platform, not in it.
	var with_dais := 0
	var treasuries := 0
	for s in range(1, 41):
		var lay := DungeonLayout.generate(s, 9)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			if rd.type != DungeonLayout.RoomType.TREASURE:
				continue
			treasuries += 1
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			RoomPlan.plan_interior(rd, ctx)
			var dais_slots := ctx.slots_tagged(RoomPlan.T_DAIS)
			if dais_slots.is_empty():
				continue
			with_dais += 1
			_check(dais_slots.size() == 1,
					"seed %d treasury: %d daises" % [s, dais_slots.size()])
			var plinth: RoomContext.Slot = dais_slots[0]
			_check(plinth.footprint == Vector2.ZERO,
					"seed %d: the dais slot claims a footprint — the altar on it would overlap" % s)
			for focal: RoomContext.Slot in ctx.slots_tagged(RoomPlan.T_FOCAL):
				_check(absf(focal.transform.origin.y - RoomPlan.DAIS_RISE) < 0.001,
						"seed %d: the altar sits at y %.2f on a %.2f m dais"
								% [s, focal.transform.origin.y, RoomPlan.DAIS_RISE])
				# XZ only. The whole point is that these two differ in Y and nowhere else, so
				# comparing them in 3-D measures the rise and calls it a misplacement.
				var fo: Vector3 = focal.transform.origin
				var po: Vector3 = plinth.transform.origin
				_check(Vector2(fo.x - po.x, fo.z - po.z).length() < 0.001,
						"seed %d: the altar stands beside its dais, not on it" % s)
	# Not "every treasury", because a dais is refused when the centre tile sits too near a doorway —
	# a real and intended outcome. A FLOOR, so the pass cannot quietly stop producing them at all.
	_check(with_dais > treasuries / 2,
			"only %d of %d treasuries got a dais" % [with_dais, treasuries])

	# NOTHING ELSE STANDS ON THE PLATFORM. The reservation is the entire mechanism by which cover,
	# mounts, the key and every enemy spawn keep off a dais, and it works through tests those passes
	# already make — which means if it ever stops working, nothing anywhere raises its voice. The
	# focal is the one exception, and it is exempt because it was deliberately lifted onto the dais.
	var intruders := 0
	for s in range(1, 41):
		var lay := DungeonLayout.generate(s, 9)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			RoomPlan.plan_interior(rd, ctx)
			var ds := ctx.slots_tagged(RoomPlan.T_DAIS)
			if ds.is_empty():
				continue
			var dp: Vector3 = (ds[0] as RoomContext.Slot).transform.origin
			var plat := Rect2(dp.x - RoomShape.TILE * 0.5, dp.z - RoomShape.TILE * 0.5,
					RoomShape.TILE, RoomShape.TILE)
			for slot: RoomContext.Slot in ctx.slots:
				if slot.footprint == Vector2.ZERO or slot.tag == RoomPlan.T_FOCAL:
					continue
				var o: Vector3 = slot.transform.origin
				var r := Rect2(o.x - slot.footprint.x * 0.5, o.z - slot.footprint.y * 0.5,
						slot.footprint.x, slot.footprint.y)
				if plat.intersects(r):
					intruders += 1
					_check(false, "seed %d %s: a '%s' stands on the dais"
							% [s, anchor, slot.tag])
			for sp: Dictionary in ctx.spawn_defs:
				var p: Vector3 = sp["pos"]
				if plat.has_point(Vector2(p.x, p.z)):
					intruders += 1
					_check(false, "seed %d %s: a '%s' spawns on the dais"
							% [s, anchor, sp["kind"]])

	# THE GALLERY. Three things it must be, and only the third is about traversal.
	var galleries := 0
	var bad_door := 0
	for s in range(1, 41):
		var lay := DungeonLayout.generate(s, 9)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			RoomPlan.plan_interior(rd, ctx)
			# READ OFF THE FLOOR, because that is what a raised floor now is. There is no terrace
			# tag to ask any more: a deck tile is a T_FLOOR slot whose tile is at level 1, and a
			# flight is a T_FLOOR slot with the ramp role. If this ever comes back empty on a room
			# whose shape has levels, the floor pass has stopped reading them.
			var deck: Array[RoomContext.Slot] = []
			var stairs: Array[RoomContext.Slot] = []
			for slot: RoomContext.Slot in ctx.slots_tagged(RoomPlan.T_FLOOR):
				if slot.role == RoomPlan.FLOOR_RAMP:
					# THE FLIGHTS THAT SERVE THE DECK, not every flight in the room. A ramp's slot
					# sits at its LOW end, so one climbing out of a pit starts below zero and one
					# climbing onto a deck starts at the floor. Written as "every ramp" when a room
					# could hold exactly one raised zone and no sunken one; the colosseum now has
					# both, and the arena's two ramps made a correct two-flight gallery report four.
					if slot.transform.origin.y > -0.01:
						stairs.append(slot)
				elif slot.transform.origin.y > 0.01:
					deck.append(slot)
			if deck.is_empty():
				continue
			galleries += 1
			# TWO FLIGHTS, ALWAYS. One is a perch: the whole reason the ends of the run are stairs
			# rather than more deck is that an enemy steering straight at a player up there has to
			# meet a ramp from more than one direction.
			_check(stairs.size() == 2,
					"seed %d %s: a gallery with %d flights" % [s, anchor, stairs.size()])
			for d: RoomContext.Slot in deck:
				_check(absf(d.transform.origin.y - RoomShape.LEVEL_RISE) < 0.001,
						"seed %d: a deck tile sits at y %.2f" % [s, d.transform.origin.y])
			# NO EXIT BEHIND THE PARAPET. A doorway on the gallery's own row would open at y = 0
			# behind a 1.8 m wall — a door into the side of a cliff, and nothing downstream would
			# ever notice, because a doorway that leads nowhere still builds and still measures.
			# THE CAMERA COST, AS A NUMBER RATHER THAN AS A BAN ON ONE WALL. This used to require
			# every deck tile at negative z, which is a rule about the gallery instead of about the
			# thing that makes a gallery wrong there — so the next pass to raise a floor would have
			# had to rediscover it, and a dais or a pit would have escaped it entirely. What makes
			# it wrong is that a raised mass nearer the lens hides the floor behind it: 0.90 m per
			# level, measured by RoomShape.hidden_by_levels and budgeted by camera_legal.
			#
			# The -Z bias is unchanged and is now justified rather than asserted: a far-row deck has
			# its riser turned toward the lens and the sightline grazing its top passes UNDER the
			# deck behind it, so it occludes nothing whatever its drop. Moving the gallery to the
			# near row scores 10.3% on seed 38 and fails the reach suite's "nothing spends the
			# budget" pin.
			_check(ctx.shape.camera_legal(),
					"seed %d %s: this room's levels hide %.1f%% of its floor from the camera"
							% [s, anchor, ctx.shape.hidden_fraction() * 100.0])
			# THE RUN'S OWN EXTENT, in both axes. A gallery covers the longest clear stretch of the
			# far row rather than the whole row, so a door in that row but beyond the run's ends is
			# not built over — and testing the row alone reports two of them as failures.
			var lo: float = deck[0].transform.origin.z - RoomShape.TILE * 0.5
			var hi: float = lo + RoomShape.TILE
			var x0 := INF
			var x1 := -INF
			for run: RoomContext.Slot in deck + stairs:
				x0 = minf(x0, run.transform.origin.x - RoomShape.TILE * 0.5)
				x1 = maxf(x1, run.transform.origin.x + RoomShape.TILE * 0.5)
			for e: DungeonLayout.Edge in rd.edges:
				if e.dir.x == 0 and e.dir.z == 0:
					continue
				var door := DungeonLayout.door_local(rd, e)
				if door.z > lo - 0.01 and door.z < hi + 0.01 						and door.x > x0 - 0.01 and door.x < x1 + 0.01:
					bad_door += 1
	_check(galleries > 0, "40 seeds produced no gallery")
	_check(bad_door == 0, "%d galleries were built over a doorway" % bad_door)

	# EVERY RAMP MUST BE REACHABLE FROM THE FLOOR, which is not the same thing as being walkable.
	# The first version put the ramps at the ENDS of the deck run, climbing along it — so a ramp's
	# low end sat against whatever the run stopped at, the room's end wall or a carved void. It was
	# a staircase you could only use if you were already at the top, and the standalone flight probe
	# below passed the whole time because it tested a flight rather than a flight in a room.
	var ramp_tiles := 0
	var stranded := 0
	for s in range(1, 41):
		var lay := DungeonLayout.generate(s, 9)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			var shape := ctx.shape
			for t: Vector2i in shape.tiles():
				if not shape.is_ramp(t):
					continue
				ramp_tiles += 1
				var d := shape.ramp_dir(t)
				var foot := t - d                # the low end
				var head := t + d                # what it climbs to
				# THE FOOT SITS AT THE RAMP'S OWN LEVEL, not at level 0. A ramp tile is at the LOW
				# end of what it joins, so for a flight UP out of the room the foot is the room
				# floor at 0 — and for a flight up out of a PIT the foot is the pit floor at -1.
				# Written as `== 0` this checked the raised case and called every sunken one broken.
				if not (shape.is_solid(foot) and shape.level_of(foot) == shape.level_of(t)
						and not shape.is_ramp(foot)):
					stranded += 1
					_check(false, "seed %d %s: a ramp at %s starts at nothing walkable"
							% [s, anchor, t])
				_check(shape.is_solid(head) and shape.level_of(head) > shape.level_of(t),
						"seed %d %s: a ramp at %s climbs to nothing" % [s, anchor, t])
	_check(ramp_tiles > 0, "40 seeds produced no ramp")

	# NO COURSE ON A RISER. The band, cornice and vault hood stack at fixed heights above the ROOM's
	# floor; hung off a 1.2 m interior wall they float in mid-air over the gallery, attached to
	# nothing. They are collider-free so nothing fails — they are just there.
	var floating := 0
	for s in range(1, 21):
		var lay := DungeonLayout.generate(s, 9)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			for slot: RoomContext.Slot in ctx.slots:
				if slot.tag in RoomDresser.COURSE_TAGS and slot.role == "riser":
					floating += 1
	_check(floating == 0, "%d courses were stacked on a riser" % floating)

	# ...and that a body with nothing but gravity gets up it. The deck is 1.2 m and the flight
	# climbs it over one 4 m tile, so this is the same worst-case walker the dais uses.
	# THE WALK THAT MATTERS: a real room, built by the real dresser, walked from its floor up onto
	# its gallery. The standalone rig below proves a flight is climbable; only this proves you can
	# GET to one. It is the check the unreachable-ramp bug slipped past for a whole milestone.
	var walked := false
	var tried := 0
	for s in range(1, 41):
		if walked:
			break
		var lay := DungeonLayout.generate(s, 9)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			RoomPlan.plan_interior(rd, ctx)
			var ramp := Vector2i(-1, -1)
			for t: Vector2i in ctx.shape.tiles():
				if ctx.shape.is_ramp(t):
					ramp = t
					break
			if ramp.x < 0:
				continue
			tried += 1
			var live := Node3D.new()
			root.add_child(live)
			RoomDresser.build(live, ctx, load("res://scenes/dungeon/themes/crypt.tres") as DungeonTheme)
			var d := ctx.shape.ramp_dir(ramp)
			var foot := ctx.shape.tile_centre(ramp - d)          # the floor in front of the flight
			var head := ctx.shape.tile_centre(ramp + d)          # the deck it climbs to
			walked = await _walk_between(live, foot, head, RoomShape.LEVEL_RISE)
			live.free()
			break
	_check(tried > 0, "no room with a ramp to walk up")
	_check(walked, "a body on the room floor could not walk up the gallery ramp onto the deck")

	var probe := Node3D.new()
	root.add_child(probe)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(24.0, 0.4, 24.0)
	gs.shape = gb
	gs.position.y = -0.2
	ground.add_child(gs)
	probe.add_child(ground)
	# THE FLIGHT AND THE DECK IT ARRIVES ON, not the flight alone. Kit.stair spans its run centred on
	# its own origin, so the flight is placed with its TOP at the world origin — which is where the
	# walker is driven — and the deck slab continues from there. The junction between the two is the
	# thing worth testing: the deck is anchored at its bottom centre, so a slab hung AT the gallery
	# height would put its surface 20 cm above the flight's top and the walker would stop dead at a
	# step it cannot climb. That is a real mistake this piece can make and it is invisible by eye.
	var flight := Kit.stair(RoomShape.TILE, RoomShape.LEVEL_RISE, RoomShape.TILE)
	probe.add_child(flight)
	flight.position = Vector3(-RoomShape.TILE * 0.5, 0.0, 0.0)
	# An ORDINARY FLOOR TILE at the upper level — which is the whole point of the refactor, and also
	# what makes this check sharper than it was: the deck is dropped by its own thickness exactly
	# like every other floor tile, so if that drop is ever skipped the walker meets a 20 cm step it
	# cannot climb and this fails.
	var deck := Kit.piece("floor_tile")
	probe.add_child(deck)
	var thick: float = (Kit.SIZES["floor_tile"] as Vector3).y
	deck.position = Vector3(RoomShape.TILE * 0.5, RoomShape.LEVEL_RISE - thick, 0.0)
	var got := await _walked_to(probe, Vector2(1, 0), RoomShape.LEVEL_RISE)
	_check(got, "a body walking up a gallery flight never reached the deck")
	probe.free()

	# AND THE STEEPEST FLIGHT THE SLOPE RULE PERMITS, which is not the one any seed builds. Every
	# ramp in the dungeon today is one tile climbing one level; MAX_SLOPE allows two levels over that
	# same tile, and the day a program asks for one this is the geometry it gets. Probing the shipped
	# case only would mean the limit was chosen by arithmetic and never walked — which is how the
	# unreachable gallery ramp shipped, on a probe that tested a flight nobody could reach.
	var steep := Node3D.new()
	root.add_child(steep)
	var sg := StaticBody3D.new()
	sg.collision_layer = 1
	sg.collision_mask = 0
	var sgs := CollisionShape3D.new()
	var sgb := BoxShape3D.new()
	sgb.size = Vector3(24.0, 0.4, 24.0)
	sgs.shape = sgb
	sgs.position.y = -0.2
	sg.add_child(sgs)
	steep.add_child(sg)
	var steep_rise := RoomShape.LEVEL_RISE * 2.0
	var sf := Kit.stair(RoomShape.TILE, steep_rise, RoomShape.TILE)
	steep.add_child(sf)
	sf.position = Vector3(-RoomShape.TILE * 0.5, 0.0, 0.0)
	var sd := Kit.piece("floor_tile")
	steep.add_child(sd)
	sd.position = Vector3(RoomShape.TILE * 0.5,
			steep_rise - (Kit.SIZES["floor_tile"] as Vector3).y, 0.0)
	_check(await _walked_to(steep, Vector2(1, 0), steep_rise),
			"a body could not walk up the steepest flight MAX_SLOPE allows (%.1f m over %.1f m, "
			% [steep_rise, RoomShape.TILE]
			+ "%.1f degrees)" % rad_to_deg(atan2(steep_rise, RoomShape.TILE)))
	steep.free()

	# THE RULE ITSELF, at its own boundary. Two levels over one tile is 31 degrees and legal; three
	# is 42 and past what a body can walk, so add_ramp must refuse rather than build a slope that
	# looks fine and stops the player dead. The refusal prints an ERROR — that is the check working.
	var sh0 := RoomShape.full(5, 3)
	_check(sh0.add_ramp(Vector2i(2, 1), Vector2i(1, 0), 1, 2),
			"add_ramp refused 2 levels over one tile, which is 31 degrees and inside MAX_SLOPE")
	var sh1 := RoomShape.full(5, 3)
	_check(not sh1.add_ramp(Vector2i(2, 1), Vector2i(1, 0), 1, 3),
			"add_ramp accepted 3 levels over one tile — 42 degrees, past what a body can walk")
	_check(sh1.ramp_count() == 0, "the refused ramp was recorded anyway")
	_check(sh1.add_ramp(Vector2i(1, 1), Vector2i(1, 0), 2, 3),
			"add_ramp refused 3 levels over TWO tiles, which is 26 degrees — lengthening is "
			+ "supposed to be the answer to a slope that is too steep")

	# CHEEK WALLS, and only past one level. A ramp's lateral neighbour is ordinary floor at the low
	# level, so the tile loop finds no boundary and emits nothing there. At one level that is wanted
	# — the side is a wedge you can step onto. At two it is a 2.4 m drop you can walk off sideways,
	# and nothing in this project has a ledge to catch on, so the fall is silent.
	var flat := RoomShape.full(5, 3)
	flat.add_ramp(Vector2i(2, 1), Vector2i(1, 0), 1, 1)
	var tall := RoomShape.full(5, 3)
	tall.add_ramp(Vector2i(2, 1), Vector2i(1, 0), 1, 2)
	_check(_risers_beside(flat, Vector2i(2, 1)) == 0,
			"a one-level ramp grew cheek walls — that boxes in a flight you are meant to step onto")
	_check(_risers_beside(tall, Vector2i(2, 1)) == 4,
			"a two-level ramp has %d cheek runs, not the 4 its two sides and two levels need"
					% _risers_beside(tall, Vector2i(2, 1)))

	# THE MULTI-TILE PATH, END TO END, because nothing in the dungeon builds one yet and an untravelled
	# path is an untested one. Driven through the real _fixture_floor and the real dresser rather than
	# by checking the arithmetic in two places: the whole point of a fixture is that its span survives
	# from the shape, through the slot, into the piece, and any one of those three hops can drop it
	# while the other two still look right.
	var wide_rd: DungeonLayout.RoomData = (DungeonLayout.generate(1, 9).rooms.values()[0]
			as DungeonLayout.RoomData)
	var wide := RoomContext.create(wide_rd, 1)
	wide.shape = RoomShape.full(5, 3)
	wide.footprint = Vector3(20.0, 6.8, 12.0)
	_check(wide.shape.add_ramp(Vector2i(1, 1), Vector2i(1, 0), 2, 2),
			"a 2-tile, 2-level ramp is 17 degrees and must be legal")
	RoomPlan._fixture_floor(wide, wide.shape.fixture_at(Vector2i(1, 1)))
	_check(wide.slots.size() == 1, "_fixture_floor laid %d slots for one ramp" % wide.slots.size())
	if wide.slots.size() == 1:
		var rs: RoomContext.Slot = wide.slots[0]
		_check(rs.span == Vector2i(2, 1), "the ramp slot carries span %s, not the (2, 1) block it "
				% rs.span + "occupies — the dresser will build a one-tile flight over two tiles")
		# THE BLOCK'S CENTRE, which for a 2-tile run is the seam between its tiles rather than either
		# tile's middle. Off by half a tile and the flight overhangs one end and stops short at the
		# other, which is a 2 m step at the top and reads as geometry that simply does not meet.
		var mid := (wide.shape.tile_centre(Vector2i(1, 1)).x
				+ wide.shape.tile_centre(Vector2i(2, 1)).x) * 0.5
		_check(is_equal_approx(rs.transform.origin.x, mid),
				"the ramp slot sits at x=%.2f, not the block centre %.2f"
						% [rs.transform.origin.x, mid])
		var built := RoomDresser._instantiate(rs, wide, null)
		var treads := 0
		if built != null:
			for c in built.get_children():
				if c is MeshInstance3D:
					treads += 1
			built.free()
		# 8 m of run over 2.4 m of rise gives 8 steps by Kit.stair's own rule; a flight still sized to
		# one tile would give 6. The number is what proves the span made it all the way through.
		_check(treads == 8, "the dresser built a %d-step flight for a 2-tile ramp — 8 m of run gives "
				% treads + "8, one tile would give 6, so the span was lost on the way")

	# THE DEBRIS FILTER IS LOAD-BEARING, and this is the assertion that says so. RoomDebris scatters
	# over the room's bounding RECT, which is not its floor — a carved room has erased tiles inside
	# that rect and a dais room has a platform standing on it. Counting how many raw draws land
	# somewhere debris must never go proves the rejection does work; if it were ever zero the filter
	# would be dead code, and dead code with a comment explaining why it matters is how it survives
	# to the day it stops being true.
	var off_ground := 0
	var drawn := 0
	var carved_seen := false
	for s in range(1, 31):
		var lay := DungeonLayout.generate(s, 9)
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			RoomPlan.plan_interior(rd, ctx)
			var raised: bool = not ctx.slots_tagged(RoomPlan.T_DAIS).is_empty()
			var carved: bool = ctx.shape.tile_count() < ctx.shape.cols * ctx.shape.rows
			if not raised and not carved:
				continue
			carved_seen = carved_seen or carved
			var drng := ctx.stream("debris_probe")
			for i in 200:
				drawn += 1
				if not ctx.is_ground(RoomDebris._place(ctx, drng), RoomDebris.SPOT_CLEAR):
					off_ground += 1
	_check(off_ground > 0,
			"%d raw debris draws over carved and raised rooms all landed on real floor — the "
					% drawn + "rejection in RoomDebris._spots is doing nothing")
	_check(carved_seen, "no carved room in 30 seeds — the carved half of that check never ran")

	# A STEP HAS TO BE A STEP. The count used to come from the rise alone, so a flight's steps were
	# fixed the moment its storey was and the treads simply got deeper as the room got longer: 42 of
	# the 50 flights 60 seeds build have a 20 m run and 1.0 m treads, and the other 8 are 44 m halls
	# whose treads were 2.2 m. That is a terrace, not a stair, and the side profile stopped reading
	# as a staircase long before it.
	#
	# READ OFF THE BUILT GEOMETRY, not recomputed from the formula — a test that re-derives the
	# number it is checking agrees with any formula it is handed. The sweep covers every run the
	# dungeon produces and well past it, so it stays true as room sizes change, and it pins the two
	# shipped configurations so the inertness claim is not just an argument in a comment.
	var deepest := 0.0
	var tallest := 0.0
	for run in [4.0, 8.0, 12.0, 20.0, 28.0, 44.0, 60.0]:
		for rise in [1.2, 2.4, 4.0, 8.0]:
			var f := Kit.stair(run, rise, 4.0)
			var treads := 0
			for c in f.get_children():
				if c is MeshInstance3D:
					treads += 1
					deepest = maxf(deepest, ((c as MeshInstance3D).mesh as BoxMesh).size.x)
			_check(treads > 0, "a %.0f x %.1f flight built no treads" % [run, rise])
			tallest = maxf(tallest, rise / maxf(treads, 1))
			if is_equal_approx(run, RoomShape.TILE) and is_equal_approx(rise, RoomShape.LEVEL_RISE):
				_check(treads == 4, "the gallery ramp now has %d steps, not the 4 it shipped with"
						% treads)
			if is_equal_approx(run, 20.0) and is_equal_approx(rise, DungeonLayout.FLOOR_HEIGHT):
				_check(treads == 20, "the stair room now has %d steps, not the 20 it shipped with"
						% treads)
			f.free()
	# 1.05 and 0.42 rather than 1.0 and 0.4: the step count is an integer, so a 44.4 m run rounds to
	# 44 steps and its treads are 1.009 m. The guard is against a terrace, not against rounding.
	_check(deepest <= 1.05, "the deepest tread any flight builds is %.3f m — a step you can stand "
			% deepest + "two of yourself on is a terrace")
	_check(tallest <= 0.42, "the tallest riser any flight builds is %.3f m" % tallest)

	_out("[VERIFY] dais suite: %d/16 approaches climbed, %d/%d treasuries raised, "
			% [climbed, with_dais, treasuries]
			+ "%.1f%% of raw debris draws rejected" % [100.0 * off_ground / maxi(drawn, 1)])




func _probe_dais(named: bool, theme: DungeonTheme, label: String) -> int:
	var dais := Kit.piece("dais", theme) as StaticBody3D if named \
			else Kit.dais(RoomShape.TILE, RoomPlan.DAIS_RISE, RoomPlan.DAIS_TOP)
	_check(dais != null, "%s did not build a StaticBody3D" % label)
	if dais == null:
		return 0
	_check(dais.collision_layer == 1 and dais.collision_mask == 0,
			"%s is on layer %d / mask %d" % [label, dais.collision_layer, dais.collision_mask])

	# ONE shape, and it must be the hull. MapPainter judges a piece by the tallest shape in its own
	# body, so a second collider smuggled in here is what would flip the platform to WALL.
	var shapes: Array[CollisionShape3D] = []
	for n in _walk(dais):
		if n is CollisionShape3D:
			shapes.append(n as CollisionShape3D)
	_check(shapes.size() == 1,
			"%s carries %d collision shapes, expected 1" % [label, shapes.size()])
	var hull := shapes[0].shape as ConvexPolygonShape3D if shapes.size() == 1 else null
	_check(hull != null, "%s's collider is not a ConvexPolygonShape3D" % label)

	if hull != null:
		# SLOPE FROM THE BUILT HULL, never from the constants — restating DAIS_RISE / DAIS_TOP here
		# would assert that two numbers I typed match two numbers I typed.
		var lo_x := 0.0
		var hi_x := 0.0
		var top_y := 0.0
		for p: Vector3 in hull.points:
			lo_x = maxf(lo_x, p.x if p.y <= 0.001 else 0.0)      # widest point on the base
			hi_x = maxf(hi_x, p.x if p.y > 0.001 else 0.0)       # widest point on the top
			top_y = maxf(top_y, p.y)
		var face := rad_to_deg(atan2(top_y, lo_x - hi_x))
		# The player never sets floor_max_angle, so it is Godot's 45 degrees. Leave real margin: a
		# slope that merely squeaks under it is one theme tweak away from being unwalkable.
		_check(face < 40.0,
				"%s climbs at %.1f degrees, too close to floor_max_angle" % [label, face])
		_check(top_y <= MapPainter.FLOOR_MAX_Y,
				"%s stands %.2f m, at or over MapPainter.FLOOR_MAX_Y %.2f — it reads as WALL"
						% [label, top_y, MapPainter.FLOOR_MAX_Y])

	# ...and that MapPainter agrees, rather than my reading of its rule agreeing.
	var probe_root := Node3D.new()
	root.add_child(probe_root)
	probe_root.add_child(dais)
	var painted := MapPainter.plan_from_collision(dais, probe_root, true)
	_check(painted.size() == 1 and painted[0]["kind"] == MapPainter.Kind.FLOOR,
			"MapPainter reads %s as %s, not FLOOR"
					% [label, "nothing" if painted.is_empty() else str(painted[0]["kind"])])

	# A floor to walk in from, big enough that the walker starts well clear of the platform.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(24.0, 0.4, 24.0)
	gs.shape = gb
	gs.position.y = -0.2                                          # top face at y = 0
	ground.add_child(gs)
	probe_root.add_child(ground)

	var up := 0
	const APPROACHES: Array[Vector2] = [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1),
	]
	for dir in APPROACHES:
		var got := await _walked_up(probe_root, dir.normalized())
		if got:
			up += 1
		_check(got, "a body walking in from %v never got onto %s" % [dir, label])
	probe_root.free()
	return up

## Drive a body with GRAVITY AND NOTHING ELSE at the dais, and report whether it ended up on top.
##
## Copied in spirit from verify_gladekit's walk probe: no step logic, no snap, no navigation, no
## floor_max_angle override — because that is precisely what the player and every enemy in this
## project are, and a probe with any help in it would pass on geometry they cannot climb.
func _walked_up(world: Node3D, dir: Vector2) -> bool:
	return await _walked_to(world, dir, RoomPlan.DAIS_RISE)


## Drive the walker at the origin from `dir` and report whether it ended up at least `height` above
## the floor. Split out of _walked_up so the gallery's flight is checked by the SAME worst-case body
## as the dais, rather than by a second copy of it that could drift into being kinder.
## Riser runs standing on the two lateral sides of one tile. Counted from walls() rather than from
## the fixture, so it measures what will actually be built.
func _risers_beside(shape: RoomShape, tile: Vector2i) -> int:
	var c := shape.tile_centre(tile)
	var n := 0
	for w: Dictionary in shape.walls():
		if w.role != "riser":
			continue
		var at: Vector3 = w.at
		# On this tile's own +z / -z faces: half a tile across, on its centre line.
		if absf(at.x - c.x) < 0.01 and absf(absf(at.z - c.z) - RoomShape.TILE * 0.5) < 0.01:
			n += 1
	return n


func _walked_to(world: Node3D, dir: Vector2, height: float) -> bool:
	return await _walk_between(world, Vector3(-dir.x * 5.0, 0.0, -dir.y * 5.0),
			Vector3.ZERO, height)


## Drive the walker from one point to another and report whether it ended `height` above the floor.
## Split out so a probe can run inside a REAL room rather than only at the origin of a rig built for
## it — which is the difference between testing a flight and testing a flight you can reach.
func _walk_between(world: Node3D, start: Vector3, target: Vector3, height: float) -> bool:
	var walker := CharacterBody3D.new()
	walker.collision_layer = 0
	walker.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4                                              # player.tscn's capsule exactly
	cap.height = 1.8
	cs.shape = cap
	walker.add_child(cs)
	# Capsule centred on the origin, so standing on y = 0 puts the origin at half its height.
	var stand := cap.height * 0.5
	walker.position = Vector3(start.x, start.y + stand + 0.05, start.z)
	world.add_child(walker)

	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var step: float = 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	for i in 180:                                                 # 3 s at 60 Hz
		await physics_frame
		if walker.is_on_floor():
			walker.velocity.y = 0.0
		else:
			walker.velocity.y -= g * step
		var to_go := Vector3(target.x - walker.position.x, 0.0, target.z - walker.position.z)
		if to_go.length() > 0.05:
			to_go = to_go.normalized() * 4.0                      # a shade under the player's speed
		walker.velocity.x = to_go.x
		walker.velocity.z = to_go.z
		walker.move_and_slide()

	var up: bool = walker.position.y > start.y + stand + height - 0.15
	walker.free()
	return up


## THE DIORAMA CUT, AS AN ASSERTION. The camera-facing wall stopping at its base course is the only
## reason a 6.8 m room is playable at all, and it is invisible to every other suite here: the plan
## emits all four sides, the COLLIDER is full height on all four sides on purpose, and the
## determinism and reskin suites compare a build against another build of itself. If the cut
## silently stopped happening, nothing below would notice and the player would vanish behind a wall.
##
## AABBs, NOT A RAYCAST. The wall collider is deliberately 6.8 m on the cut side too (that is what
## makes the cut unable to change gameplay), so a physics query would report an occluder the camera
## cannot actually see and this suite would fail on correct behaviour.
func _cutaway_suite() -> void:
	# The geometry the whole design rests on, checked rather than left in a comment. A neighbouring
	# room shows its FAR wall through your cutaway; that only stays harmless while its wall cannot
	# hide more of you than your own near wall already does.
	var ceiling: float = DungeonLayout.COURSE_H \
			+ (DungeonLayout.GAP - DungeonLayout.CORNICE_PROJ) * tan(DungeonRoom.FRAME_PITCH)
	_check(DungeonLayout.WALL_HEIGHT <= ceiling,
			"wall %.2f m exceeds the neighbour ceiling %.2f m — a room at +Z will eat the player"
					% [DungeonLayout.WALL_HEIGHT, ceiling])
	# and that the camera has not been re-authored out from under that arithmetic
	_check(absf(DungeonRoom.FRAME_PITCH - atan2(12.5, 9.375)) < 0.001,
			"FRAME_PITCH %.4f no longer matches CameraRig's authored angle" % DungeonRoom.FRAME_PITCH)

	# The camera offset DungeonRoom actually claims: CameraRig's base offset scaled by room_zoom.
	var cam_off := Vector3(0.0, 12.5, 9.375) * 1.15
	var cut := RoomDresser.cutaway_out(DungeonRoom.FRAME_YAW)
	_check(cut != Vector2i.ZERO, "the pinned frame yaw has no single occluding wall — cutaway is off")
	var courses := 0
	var rise_hist := {}

	for s in [1, 42, 99]:
		var zc := (load("res://scenes/world/zone_crypt.tscn") as PackedScene).instantiate()
		zc.dungeon_seed = s
		root.add_child(zc)
		await process_frame
		for node in _walk(zc):
			if not (node is DungeonRoom):
				continue
			var room := node as DungeonRoom

			# (1) THE CUT ITSELF, asserted directly off the meta RoomDresser stamps. This is the
			# real guarantee; the occlusion sweep below is a second opinion that cannot distinguish
			# a surviving course from a stair room's climbing base wall.
			for n in _walk(room):
				if not n.has_meta(RoomDresser.COURSE_META):
					continue
				courses += 1
				# READ BACK WHAT THE DRESSER DECIDED, rather than re-deriving it from the built
				# node's yaw. The derivation is a quarter-turn rounding with no guard, so on any
				# piece that is not square to the room this test would make the same mistake as the
				# code and confirm it.
				var side: Vector2i = n.get_meta(RoomDresser.COURSE_OUT, Vector2i.ZERO)
				_check(not RoomDresser.faces(side, cut),
						"seed %d %s: a %s survived on the camera-facing side"
								% [s, room.name, n.get_meta(RoomDresser.COURSE_META)])

			# (2) NOTHING TALL BETWEEN THE PLAYER AND THE LENS. Skipped for stair rooms: their floor
			# IS the flight, climbing FLOOR_HEIGHT across the room, so "the player's feet at y = 0"
			# has no meaning there and every riser reads as an occluder. The generator marks them by
			# giving them a trigger tall enough to span the climb.
			if room.trigger_height > DungeonLayout.HEAD_ROOM + 0.01:
				continue
			var hx: float = maxf(room.footprint.x * 0.5 - 4.0, 1.0)
			var hz: float = maxf(room.footprint.z * 0.5 - 1.0, 1.0)
			for px in [-hx, 0.0, hx]:
				var from: Vector3 = room.global_position + Vector3(px, 0.05, hz)
				var to := from + cam_off
				for m in _walk(room):
					if not (m is MeshInstance3D):
						continue
					var box := (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
					# Height above THIS ROOM'S floor, not world Y — an upper storey sits at
					# FLOOR_HEIGHT and its own base course would otherwise measure 11 m tall.
					if box.end.y - room.global_position.y <= DungeonLayout.COURSE_H + 0.35:
						continue                  # the base course has always stood there
					# ANYTHING COURSEVEIL HIDES IS EXEMPT, and it is exempt because it is HANDLED,
					# not because it is harmless. This sweep is a STATIC test — it asks "could this
					# mesh ever sit between the player and the lens" — and for a wall course the
					# answer is no once the cut has removed the camera-facing side, which is what
					# makes the sweep meaningful there.
					#
					# A COLUMN standing in open floor is different: it genuinely will come between
					# the two, and the answer is not to forbid it but to fade it, which is exactly
					# what CourseVeil does every frame for everything carrying COURSE_META. Failing
					# it here would forbid tall columns outright and leave the crypt at one storey.
					#
					# The exemption is only sound if the veil really covers every such piece, so
					# that is asserted below rather than assumed.
					if _veiled(m):
						continue
					_check(not box.intersects_segment(from, to),
							"seed %d %s: %s (%.2f m above its floor) is between player and camera"
									% [s, room.name, m.name, box.end.y - room.global_position.y])
		# THE VEIL ACTUALLY COVERS WHAT THE SWEEP LET THROUGH. CourseVeil.collect() walks for
		# COURSE_META and stops descending once it finds one, so a piece that carries the meta on a
		# CHILD rather than on the node RoomDresser stamped would be invisible to it — and the
		# exemption above would then be excusing something nothing hides.
		var veil := CourseVeil.new()
		veil.collect(zc)
		var stamped := 0
		for n in _walk(zc):
			if n is Node3D and n.has_meta(RoomDresser.COURSE_META):
				stamped += 1
		_check(veil.pieces_count() == stamped,
				"seed %d: CourseVeil collected %d of %d COURSE_META pieces — the cutaway suite's "
				% [s, veil.pieces_count(), stamped]
				+ "exemption is excusing geometry nothing fades")
		# AND THE SIZE STAMPS LAND. CourseVeil falls back to a 4 m module and COURSE_H for any piece
		# that lacks them, which is the right behaviour for a template's own courses and the wrong
		# thing to discover about the dungeon's: it would put the veil back on the fixed numbers it
		# just stopped using, and every assertion above would still pass. Distinct values are the
		# tell — the shell mixes 3.0 m uppers with 0.3 m bands and 0.5 m cornices, so one value
		# everywhere means the stamp is not being read.
		var rises := {}
		var spans := {}
		for n in _walk(zc):
			if n is Node3D and n.has_meta(RoomDresser.COURSE_META):
				_check(n.has_meta(RoomDresser.COURSE_RISE) and n.has_meta(RoomDresser.COURSE_SPAN),
						"seed %d: course %s carries no size stamp — the veil will guess" % [s, n.name])
				var r: float = n.get_meta(RoomDresser.COURSE_RISE)
				rises[r] = true
				spans[n.get_meta(RoomDresser.COURSE_SPAN)] = true
				rise_hist[r] = int(rise_hist.get(r, 0)) + 1
		_check(rises.size() >= 3, "seed %d: courses report %d distinct heights, expected at least "
				% [s, rises.size()] + "the upper, the band and the cornice")
		_check(spans.size() >= 2, "seed %d: courses report %d distinct spans — the bevelled corner's "
				% [s, spans.size()] + "2.83 m runs are being reported as full modules")
		veil.free()
		zc.free()
	_check(courses > 0, "no course pieces were built at all — the shell above the base is missing")
	# WHAT THE HEIGHT STAMP ACTUALLY CHANGED, reported rather than assumed. Every one of these was
	# measured at COURSE_H before, so the share that is NOT COURSE_H is the share of the dungeon's
	# masonry whose veiling moved — and it is most of it. A band was being tested against ten times
	# its own height.
	var moved := 0
	for h: float in rise_hist:
		if not is_equal_approx(h, DungeonLayout.COURSE_H):
			moved += int(rise_hist[h])
	_out("[VERIFY] cutaway suite: 3 seeds, %d courses, none on the camera side (%d of them, %d%%, "
			% [courses, moved, roundi(100.0 * moved / maxf(courses, 1))]
			+ "are shorter than the COURSE_H stand-in the veil used to assume)")


## Is this mesh inside something CourseVeil will fade? The meta is stamped on the piece root, so a
## mesh several nodes down is still covered — walk up rather than testing the mesh itself.
func _veiled(node: Node) -> bool:
	var n := node
	while n != null:
		if n.has_meta(RoomDresser.COURSE_META):
			return true
		n = n.get_parent()
	return false


## SHADOWS ARE THE WHOLE LIGHTING MODEL NOW, and every part of them is a property on a node that a
## reskin, a merge or an inspector click can silently clear. For most of this project's life the
## crypt had ninety lights and one caster and nothing anywhere said so — which is precisely how it
## stayed that way for months. Three guarantees, all cheap:
##
##   1. every room can actually cast something,
##   2. no caster escapes into a corridor, where it would light and shadow permanently,
##   3. leaving a room really does stop its shadow maps rendering.
func _shadow_suite() -> void:
	for s in [42, 7]:
		var zc := (load("res://scenes/world/zone_crypt.tscn") as PackedScene).instantiate()
		zc.dungeon_seed = s
		root.add_child(zc)
		await process_frame

		# LIGHT EVERY ROOM FIRST. The generator darkens all but the arrival room at build time, and
		# set_lit(false) is exactly what turns shadow casting off — so inspecting the dungeon as
		# built reports nine rooms out of ten with no caster, which is correct behaviour and a
		# useless test. What is worth guaranteeing is that every room CAN cast when it is the room
		# the player is standing in. Lighting them all up first also exercises the restore path.
		for node in _walk(zc):
			if node is DungeonRoom:
				(node as DungeonRoom).set_lit(true, false)
		await process_frame

		var rooms := 0
		var loose := 0
		for node in _walk(zc):
			# (2) A CASTER OUTSIDE A ROOM IS A CASTER NOBODY CAN TURN OFF. set_lit only reaches
			# lights parented under a DungeonRoom, so one dropped into a corridor by a future pass
			# would render its cube every frame for the rest of the run, in a part of the dungeon
			# the player is looking away from.
			if node is Light3D and (node as Light3D).shadow_enabled \
					and not (node is DirectionalLight3D):
				if _room_of(node) == null:
					loose += 1
			if not (node is DungeonRoom):
				continue
			var room := node as DungeonRoom
			rooms += 1
			var casters := 0
			for n in _walk(room):
				if n is Light3D and (n as Light3D).shadow_enabled:
					casters += 1
			# (1) The generator lights every room it builds, so a room with nothing casting means
			# either the dresser skipped it or a theme cleared the flag on the fill.
			_check(casters >= 1, "seed %d: %s has no shadow-casting light" % [s, room.name])
		_check(loose == 0, "seed %d: %d shadow casters live outside any DungeonRoom" % [s, loose])
		_check(rooms > 0, "seed %d: no rooms built" % s)

		# (3) THE REGRESSION TEST FOR THE ASYMMETRIC set_lit TIMING. Shadows go OFF on a 0.5 s delay
		# when a room goes dark — deliberately, so the fade is never left unoccluded — which means
		# "did they actually go off?" can only be answered after that delay has elapsed. A tween
		# that never fires, or a callback that captured the wrong light, looks identical to working
		# code for exactly half a second and then costs six cube faces a frame forever.
		var first: DungeonRoom = null
		for node in _walk(zc):
			if node is DungeonRoom:
				first = node as DungeonRoom
				break
		if first != null:
			first.set_lit(true, false)
			first.set_lit(false)                 # animated: this is the path with the delay in it
			await _wait(0.7)
			for n in _walk(first):
				if n is Light3D:
					_check(not (n as Light3D).shadow_enabled,
							"seed %d: %s still casts 0.7 s after its room went dark"
									% [s, (n as Node3D).name])
		zc.free()
	_out("[VERIFY] shadow suite: every room casts, nothing casts loose, and set_lit turns it off")


## Real seconds, not frames. The thing being waited on here is a Tween's set_delay, which is driven
## by wall time — counting process_frames instead would pass or fail depending on how fast the
## headless run happens to spin.
func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Nearest DungeonRoom ancestor, or null if this node is not inside one.
static func _room_of(n: Node) -> DungeonRoom:
	var p := n.get_parent()
	while p != null:
		if p is DungeonRoom:
			return p as DungeonRoom
		p = p.get_parent()
	return null


## The mission graph is only real if the BUILT dungeon honours it: a barred gate that ignores its
## key, or a key prop that never got spawned, would pass every layout check above and still leave
## the player stuck at a door.
func _lock_runtime_suite() -> void:
	for s in [42, 7, 3]:
		var zc := (load("res://scenes/world/zone_crypt.tscn") as PackedScene).instantiate()
		zc.dungeon_seed = s
		root.add_child(zc)
		await process_frame

		var locked: Array = []
		var keys: Array = []
		for node in _walk(zc):
			if node is DungeonDoor and (node as DungeonDoor).locked_by != "":
				locked.append(node)
			elif node is DungeonKey:
				keys.append(node)
		_check(not locked.is_empty(), "seed %d: mission locked a gate but none was built" % s)
		_check(not keys.is_empty(), "seed %d: locked dungeon with no key prop in it" % s)

		if not locked.is_empty() and not keys.is_empty():
			var key_id: String = (keys[0] as DungeonKey).key_id
			for d in locked:
				_check((d as DungeonDoor).locked_by == key_id,
						"seed %d: gate barred by '%s' but the key is '%s'"
						% [s, (d as DungeonDoor).locked_by, key_id])
			# the wrong key must not open it
			zc.grant_key("not_a_real_key")
			_check((locked[0] as DungeonDoor).locked_by == key_id,
					"seed %d: gate opened for the wrong key" % s)
			zc.grant_key(key_id)
			for d in locked:
				_check((d as DungeonDoor).locked_by == "",
						"seed %d: gate still barred after its key was taken" % s)
		zc.free()
	_out("[VERIFY] lock runtime suite: 3 seeds unlocked")


## THE POINT OF THE WHOLE SPLIT, as a test: swapping the theme must change what you see and
## nothing about what you fight. Same seed, two themes — every piece and every enemy must land in
## exactly the same place, while the art differs.
func _reskin_suite() -> void:
	var crypt := load("res://scenes/dungeon/themes/crypt.tres") as DungeonTheme
	if crypt == null:
		_check(false, "reskin: crypt theme missing")
		return
	var alt := crypt.duplicate(true) as DungeonTheme
	alt.id = "test_reskin"
	alt.tag_pieces = {RoomPlan.T_COVER_LARGE: "crate"}      # pillars become crates
	alt.greybox_colors = {"crate": Color(0.9, 0.1, 0.1), "floor_slab": Color(0.1, 0.9, 0.1)}
	alt.light_color = Color(0.3, 0.5, 1.0)

	var a := await _theme_probe(4242, crypt)
	var b := await _theme_probe(4242, alt)
	_check(a.gameplay == b.gameplay, "reskin: theme swap moved geometry or enemies")
	_check(a.look != b.look, "reskin: theme swap changed nothing visually")
	_out("[VERIFY] reskin suite: geometry identical, art differs")


## Builds one crypt with a given theme and splits what it produced into a GAMEPLAY fingerprint
## (positions, enemies) and a LOOK fingerprint (albedo + light colours).
func _theme_probe(s: int, theme: DungeonTheme) -> Dictionary:
	var zc := (load("res://scenes/world/zone_crypt.tscn") as PackedScene).instantiate()
	zc.dungeon_seed = s
	zc.theme = theme
	root.add_child(zc)
	await process_frame
	var gameplay: Array[String] = []
	var look: Array[String] = []
	for node in _walk(zc):
		if node is StaticBody3D:
			var p: Vector3 = (node as Node3D).global_position
			gameplay.append("body@%.2f,%.2f,%.2f" % [p.x, p.y, p.z])
		elif node is MeshInstance3D:
			# surface_get_material, not `.material`: that property only exists on PrimitiveMesh, and
			# anything imported from a .glb is an ArrayMesh.
			var mesh := (node as MeshInstance3D).mesh
			if mesh != null:
				for si in mesh.get_surface_count():
					var mat = mesh.surface_get_material(si)
					if mat is StandardMaterial3D:
						look.append("albedo:%s" % (mat as StandardMaterial3D).albedo_color)
		elif node is Light3D:
			# CLASS AND SHADOW FLAG ARE PART OF THE LOOK, not just the colour. A reskin that turns
			# every sconce back into a shadowless omni changes the crypt profoundly and would leave
			# this fingerprint untouched if it only recorded a Color.
			var l := node as Light3D
			look.append("light:%s:%s:%s" % [l.get_class(), l.light_color, l.shadow_enabled])
		if node is DungeonRoom:
			for def in (node as DungeonRoom).spawn_defs:
				gameplay.append("spawn:%s@%s" % [def.kind, def.pos])
	zc.free()
	gameplay.sort()
	look.sort()
	return {"gameplay": "\n".join(gameplay), "look": "\n".join(look)}


## Lighting is DERIVED now (RoomDresser spaces sconces around the perimeter) rather than pinned to
## four hand-picked corners, so it needs a guard: every room must actually be lit, and no mount may
## end up standing in a doorway.
func _check_room_lighting(s: int, room: DungeonRoom, lay: DungeonLayout) -> void:
	# match the node back to its RoomData by world centre — a hall's centre is not on a cell
	var rd: DungeonLayout.RoomData = null
	var cell := Vector3i.ZERO
	for anchor: Vector3i in lay.rooms:
		var candidate: DungeonLayout.RoomData = lay.rooms[anchor]
		if DungeonLayout.room_origin(candidate).distance_to(room.position) < 0.01:
			rd = candidate
			cell = anchor
			break
	if rd == null:
		_check(false, "seed %d: room node at %s maps to no layout room" % [s, room.position])
		return

	# Only the room's OWN lighting. Portals carry their own light and legitimately sit near the
	# start room's door, so their subtree is not part of what the dresser is being judged on.
	#
	# MOUNTS ARE COUNTED SEPARATELY FROM ARCHITECTURE, and the discriminator is the collider.
	# Kit's contract is that a light MOUNT claims no floor and therefore has no collision (see
	# candelabra.tscn's header), while a wall piece is a StaticBody3D. That matters below: the
	# clearance rule polices where the DRESSER hangs sconces, and wall_niche_brick.tscn is a wall
	# that happens to hold a candle. A niche in the segment next to a doorway is not a sconce in a
	# passage, and asserting otherwise made the suite hostage to which wall drew the niche --
	# adding two ruined variants to crypt.tres reshuffled that and seed 2 started failing on art
	# that had not changed.
	var lights: Array[Vector3] = []
	var mounts: Array[Vector3] = []
	for child in room.get_children():
		if str(child.name).ends_with("Portal"):
			continue
		var architecture := child is StaticBody3D
		for node in _walk(child):
			if node is Light3D and not (node is DirectionalLight3D):
				var at: Vector3 = (node as Node3D).global_position - room.global_position
				lights.append(at)
				if not architecture:
					mounts.append(at)
	_check(lights.size() >= 2, "seed %d: room %s has only %d lights" % [s, cell, lights.size()])
	# Doorway clearance is a preference, not a guarantee: a small room with three or four exits has
	# no perimeter that clears them all, and being lit matters more. Only assert it where there was
	# room to honour it.
	if rd.edges.size() <= 2:
		for at: Vector3 in mounts:
			for e: DungeonLayout.Edge in rd.edges:
				if e.dir.x == 0 and e.dir.z == 0:
					continue
				var door := DungeonLayout.door_local(rd, e)
				door.y = at.y
				_check(at.distance_to(door) >= RoomDresser.MOUNT_DOOR_CLEARANCE - 0.01,
						"seed %d: room %s has a light in the %s doorway" % [s, cell, e.dir])


## The seed is PRINTED so a bug can be reproduced — that promise is only real if the same seed
## rebuilds the same dungeon. (It did not: room furnishing used to call Array.shuffle(), which
## draws from the GLOBAL rng.) Build the same seed twice and compare a full scene signature.
func _determinism_suite() -> void:
	for s in [42, 7]:
		var sig_a := await _build_signature(s)
		var sig_b := await _build_signature(s)
		_check(sig_a == sig_b, "seed %d: rebuild differs — generation is not deterministic" % s)
	_out("[VERIFY] determinism suite: 2 seeds rebuilt")


## Everything the generator placed, as one order-independent string: every Node3D's type and
## rounded position, plus every room's enemy spawn list.
func _build_signature(s: int) -> String:
	var zc := (load("res://scenes/world/zone_crypt.tscn") as PackedScene).instantiate()
	zc.dungeon_seed = s
	root.add_child(zc)
	await process_frame
	var lines: Array[String] = []
	for node in _walk(zc):
		if node is Node3D:
			var p: Vector3 = (node as Node3D).global_position
			lines.append("%s@%.2f,%.2f,%.2f" % [node.get_class(), p.x, p.y, p.z])
		if node is DungeonRoom:
			for def in (node as DungeonRoom).spawn_defs:
				lines.append("spawn:%s@%s" % [def.kind, def.pos])
	zc.free()
	lines.sort()
	return "\n".join(lines)


## Every template must load, and its markers must respect the interior contract.
func _template_suite() -> void:
	var dir := DirAccess.open("res://scenes/dungeon/rooms/")
	_check(dir != null, "template dir missing")
	if dir == null:
		return
	var count := 0
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		count += 1
		var tpl := (load("res://scenes/dungeon/rooms/" + f) as PackedScene).instantiate()
		for child in tpl.get_children():
			if child is Marker3D and (str(child.name).begins_with("Prop") or str(child.name).begins_with("Spawn")):
				var p: Vector3 = (child as Node3D).position
				_check(absf(p.x) <= 9.0 and absf(p.z) <= 5.0,
						"%s: %s outside interior bounds" % [f, child.name])
				_check(absf(p.x) >= 2.0 and absf(p.z) >= 2.0,
						"%s: %s inside a door lane" % [f, child.name])
		tpl.free()
	_check(count >= 3, "expected >=3 templates, found %d" % count)
	_out("[VERIFY] template suite: %d templates done" % count)


func _walk(node: Node) -> Array:
	var out := [node]
	for c in node.get_children():
		out += _walk(c)
	return out


func _count_type(node: Node, cls: String) -> int:
	var n := 0
	for x in _walk(node):
		if x.get_class() == cls or (x.get_script() and x.get_script().get_global_name() == cls):
			n += 1
	return n

extends Node
## Autoload "Traits" — the four characteristics, and everything derived from them.
##
## THE ONE IDEA: each characteristic is a single number doing THREE jobs that games usually keep
## apart —
##
##   a combat stat        (crit, i-frames, reach, status chance)
##   a perception layer   (what the world lets you notice at all)
##   a difficulty class   (which checks you pass, and which lines you get to say)
##
## That overlap is the whole design. Raising Perception has to make the secret findable AND the
## swing reach further AND the observation more often right, or the sheet is just a menu.
##
## THIS FILE IS THE MODEL AND NOTHING ELSE. No UI, no scene lookups, no tree walking — Notice draws
## the check card, Sheet draws the menus, ToolBelt reads the modifiers. That split is not tidiness:
## it means the whole progression system can be exercised in a `--script` run with no autoloads and
## no viewport, which is how the dungeon suite already tests itself. Keep it that way.

signal characteristics_changed                 ## a point was spent, or a Conviction shifted a stat
signal insight_changed(amount: int)            ## Insight gained or spent
signal convictions_changed                     ## one was gained, taken up, or completed
signal boons_changed                           ## a run-scoped boon was taken
## A check resolved. Notice draws this; anything else may listen.
signal check_resolved(which: int, dc: int, roll: int, total: int, success: bool)

enum Attr { LOGIC, INSTINCT, PERCEPTION, DRAMA }

const ATTR_NAMES := ["LOGIC", "INSTINCT", "PERCEPTION", "DRAMA"]

## Each characteristic's colour, used EVERYWHERE it appears: the check card, the boon card, the HUD
## pip, the dialogue option that is gated behind it. One table, so a check is recognisable as
## Perception's before a word of it has been read.
const ATTR_COLORS := [
	Color(0.42, 0.72, 0.98),      # LOGIC       — cold instrument blue
	Color(0.92, 0.32, 0.26),      # INSTINCT    — arterial red
	Color(0.72, 0.52, 0.95),      # PERCEPTION  — violet, the edge of the visible spectrum
	Color(1.00, 0.78, 0.34),      # DRAMA       — footlight gold
]

## How each one SOUNDS when it speaks up. Notice prints this under the header, so a player who has
## read no design document still learns that Logic is clinical and Drama is a liar with good timing.
const ATTR_TAGLINE := [
	"cold, clinical, correct",
	"the body, one step ahead of you",
	"everything at once, too loudly",
	"and now — the truth, performed",
]

## THE DIFFICULTY LADDER, named rather than numbered, because the name is what the player reads on
## the card and "Formidable" says something "14" does not.
##
## A check is 2d6 + characteristic. 2d6 rather than d20 on purpose: the middle outcomes are common
## and the miracle is rare, so a characteristic actually moves the whole curve instead of shifting a
## flat one.
const DIFFICULTY := {
	"trivial": 6, "easy": 8, "medium": 10,
	"challenging": 12, "formidable": 14, "legendary": 16,
}

const MIN_ATTR := 1
const MAX_ATTR := 6
## One slot per Conviction that exists. Past that a slot could never be filled, which is the same
## empty purchase buy_point refuses.
const MAX_SLOTS := 4
const SAVE_PATH := "user://traits_save.dat"

# --- PERMANENT STATE (survives death; this is the meta-progression) ---------------------------

var characteristics: Array[int] = [2, 2, 2, 2]  ## indexed by Attr
var unspent := 2                                ## points waiting to be placed
var insight := 0                                ## the run currency
var slots := 2                                  ## how many Convictions you can hold at once
var runs_taken := 0
var deaths := 0
var victories := 0
## The boss has been beaten at least once. The slice's terminal state — the three say different
## things afterwards, and it is what stops the loop from being the only thing there is.
var slice_complete := false

## id -> {"state": "loose"|"held"|"settled", "progress": int}
##
## LOOSE means you are carrying the idea around without having sat with it. That distinction is the
## whole texture of the system: picking an idea up is free, and actually thinking about it costs a
## slot and several descents.
var convictions := {}

# --- RUN STATE (wiped by begin_run) -----------------------------------------------------------

var run_boons: Array[String] = []              ## boon ids taken this descent
var run_insight := 0                           ## banked only when the run ends
var run_rooms_cleared := 0
var run_kills := 0
var last_death_cause := ""                     ## the hub's post-mortem lines read this

## A check, once rolled, is FIXED for the rest of the run. Walking back through the same doorway
## must not re-roll the wall that wasn't hollow — that is save-scumming with your feet, and it turns
## every failed check into an inconvenience instead of a fact about this descent.
var _check_results := {}                       ## check id -> the result Dictionary

## Run-scoped additive modifiers contributed by boons and settled Convictions, keyed by the names
## the getters below read.
var _mods := {}

## Deterministic per-run randomness, seeded once in begin_run — the same discipline the dungeon
## layout already follows, so a run is reproducible from its seed.
var _rng := RandomNumberGenerator.new()


# ==============================================================================================
# CONVICTIONS — the meta-progression
# ==============================================================================================
#
# A Conviction is acquired by SOMETHING HAPPENING TO YOU, never bought. Then you choose whether to
# sit with it, which costs a slot and several descents, and the payoff is deliberately double-edged.
#
# `effect` is DATA, not a Callable, for the same reason DungeonTheme is data: a settled Conviction
# has to survive a save/load round trip, and a Callable does not.
#   attr — permanent characteristic deltas, applied once on settling
#   flag — a named switch other systems ask about via has_flag()
#   mod  — permanent additions to the derived-modifier table
const CONVICTIONS := {
	"fear_of_the_abyss": {
		"name": "Fear of the Abyss",
		"hook": "You looked down, and the dark looked back with interest.",
		"body": "Every descent begins with the same half-second where you consider not going. You "
				+ "have started to suspect that half-second is the only honest part of you.",
		"done": "The fear did not leave. It got organised. You move faster now, and you know "
				+ "exactly why.",
		"runs": 2,
		"effect": {"attr": {Attr.INSTINCT: 1}, "mod": {"crit": -0.04}},
	},
	"rationalist_delusion": {
		"name": "Rationalist Delusion",
		"hook": "You were right about the wall. You have decided you are right about everything.",
		"body": "If the ruin obeys rules, and you can read rules, then the ruin is already solved "
				+ "and the walking is a formality. This has never once been true.",
		"done": "You think better and listen worse. The trade was made knowingly, which is either "
				+ "the point or the joke.",
		"runs": 2,
		"effect": {"attr": {Attr.LOGIC: 1}, "mod": {"drama_check": -2.0}},
	},
	"traumatized_reflexes": {
		"name": "Traumatized Reflexes",
		"hook": "Something hurt you before you saw it. Your body has filed a complaint.",
		"body": "The flinch arrives before the threat does now. It is not fear exactly — it is a "
				+ "very fast opinion.",
		"done": "Pain reads as information. It still finds you; it just tells you something useful "
				+ "on the way in.",
		"runs": 3,
		"effect": {"flag": "pain_reads", "mod": {"poise": -1.0}},
	},
	"heroic_hubris": {
		"name": "Heroic Hubris",
		"hook": "You cleared the room without being touched and you would like everyone to know.",
		"body": "The posture came first and the competence followed it, which is the wrong order "
				+ "and has worked anyway, so far.",
		"done": "You are magnificent and slightly easier to kill. Both were always going to be "
				+ "true at once.",
		"runs": 2,
		"effect": {"attr": {Attr.DRAMA: 1}, "mod": {"max_hp": -1.0}},
	},
}


# ==============================================================================================
# BOONS — run-scoped, chosen three at a time on a pedestal when a room clears
# ==============================================================================================
#
# Each is attributed to one characteristic, and the offer is weighted toward your strong ones, so a
# descent develops a SHAPE: a Perception run notices everything and hits like a rumour.
const BOONS := {
	"logic_weakpoint": {
		"attr": Attr.LOGIC, "name": "Weak Point Analysis",
		"text": "Crit chance +15%. The armour has a seam and you have already found it.",
		"mod": {"crit": 0.15},
	},
	"logic_recursion": {
		"attr": Attr.LOGIC, "name": "Recursive Footwork",
		"text": "Cooldowns −25%. The same three steps, endlessly, correctly.",
		"mod": {"cooldown": -0.25},
	},
	"instinct_iframes": {
		"attr": Attr.INSTINCT, "name": "The Body Decides",
		"text": "Dodge invulnerability +60%. You are already elsewhere.",
		"mod": {"iframes": 0.6},
	},
	"instinct_berserk": {
		"attr": Attr.INSTINCT, "name": "Last Animal Standing",
		"text": "+2 damage while on your final health block.",
		"mod": {"berserk": 2.0},
	},
	"perception_reach": {
		"attr": Attr.PERCEPTION, "name": "The Long Look",
		"text": "Attack reach +0.35 m. You strike where the enemy is about to be.",
		"mod": {"reach": 0.35},
	},
	"perception_spectral": {
		"attr": Attr.PERCEPTION, "name": "Peripheral Truth",
		"text": "Secrets announce themselves from twice as far away.",
		"mod": {"notice": 6.0},
	},
	"drama_fear": {
		"attr": Attr.DRAMA, "name": "Unbearable Presence",
		"text": "25% chance on hit to send an enemy running.",
		"mod": {"fear": 0.25},
	},
	"drama_encore": {
		"attr": Attr.DRAMA, "name": "Encore",
		"text": "Every check this run rolls +2. Conviction is a kind of evidence.",
		"mod": {"check": 2.0},
	},
}


func _ready() -> void:
	load_state()


# ==============================================================================================
# THE SHEET
# ==============================================================================================

## A characteristic's LIVE value: the permanent score plus whatever a settled Conviction shifted.
## Everything reads this and never `characteristics[a]` directly — otherwise a settled Conviction
## shows up in the menu and does nothing in play.
func attr(a: int) -> int:
	return clampi(characteristics[a] + int(_mods.get("attr_%d" % a, 0.0)), MIN_ATTR, MAX_ATTR)


func spend_point(a: int) -> bool:
	if unspent <= 0 or characteristics[a] >= MAX_ATTR:
		return false
	unspent -= 1
	characteristics[a] += 1
	characteristics_changed.emit()
	save_state()
	return true


## Insight buys points at a RISING price, so one lucky descent cannot buy the whole sheet: 3, 5, 7…
func point_price() -> int:
	var bought := characteristics[0] + characteristics[1] + characteristics[2] \
			+ characteristics[3] - 8
	return 3 + 2 * maxi(bought, 0)


## Is there anywhere left to PUT a point? Four characteristics at the ceiling means no, and buying
## one anyway is a pure loss the player cannot see coming: the + buttons all grey out but the price
## keeps being quoted, so Insight goes in and nothing comes out.
func can_place_point() -> bool:
	for i in 4:
		if attr(i) < MAX_ATTR:
			return true
	return false


## True when the sheet is finished — every characteristic at the ceiling. The one measurable
## "you have taken this as far as it goes" the model can offer.
func is_maxed() -> bool:
	return not can_place_point()


func buy_point() -> bool:
	var price := point_price()
	if insight < price or not can_place_point():
		return false
	insight -= price
	unspent += 1
	insight_changed.emit(insight)
	characteristics_changed.emit()
	save_state()
	return true


# --- The combat sheet. Each one is (characteristic × slope) + modifiers. -----------------------

func crit_chance() -> float:
	return clampf(0.04 + 0.06 * attr(Attr.LOGIC) + _mods.get("crit", 0.0), 0.0, 0.95)

## Multiplier on every cooldown the player pays (dash, tools). Logic recovers; boons stack on top.
func cooldown_scale() -> float:
	return clampf(1.0 - 0.05 * attr(Attr.LOGIC) + _mods.get("cooldown", 0.0), 0.25, 1.5)

## Dodge invulnerability as a MULTIPLE of the base dash time — Instinct's signature.
func iframe_scale() -> float:
	return 1.0 + 0.12 * attr(Attr.INSTINCT) + _mods.get("iframes", 0.0)

## Bonus damage on the last health block. Instinct 4+ unlocks the finisher on its own.
func berserk_damage() -> int:
	return (1 if attr(Attr.INSTINCT) >= 4 else 0) + int(_mods.get("berserk", 0.0))

## Metres added to the sword's reach — and to the damage box, which is the only version that is
## not a lie. See Sword.reach().
func reach_bonus() -> float:
	return 0.05 * attr(Attr.PERCEPTION) + _mods.get("reach", 0.0)

## How far away a secret will make itself known. Read by TraitProbe and by the lantern's reveal.
func notice_radius() -> float:
	return 3.0 + 1.4 * attr(Attr.PERCEPTION) + _mods.get("notice", 0.0)

## Chance a landed hit sends an enemy running. Drama's combat face.
func fear_chance() -> float:
	return clampf(0.05 * attr(Attr.DRAMA) + _mods.get("fear", 0.0), 0.0, 0.9)

## Permanent HP shift from settled Convictions (Heroic Hubris costs you a block).
func max_hp_delta() -> int:
	return int(_mods.get("max_hp", 0.0))

## Poise shift from settled Convictions.
func poise_delta() -> int:
	return int(_mods.get("poise", 0.0))


func has_flag(flag_name: String) -> bool:
	return bool(_mods.get("flag_" + flag_name, 0.0))


# ==============================================================================================
# CHECKS — 2d6 + characteristic vs. a named difficulty
# ==============================================================================================

## Roll a check, or return the roll this run already made for `id`.
##
## RETURNS THE WHOLE RESULT rather than a bool, because the interesting part of a check is the
## MARGIN: "Medium: Success" and "Medium: Success, barely" are different sentences and the card
## wants both numbers.
##
## `id` must be stable across frames and unique per site — "crackwall_room3", never "logic". An
## empty id means "roll fresh every time", which should be rare.
func check(a: int, difficulty: String, id := "") -> Dictionary:
	if id != "" and _check_results.has(id):
		return _check_results[id]
	var dc: int = DIFFICULTY.get(difficulty, 10)
	var roll := _rng.randi_range(1, 6) + _rng.randi_range(1, 6)
	var bonus := attr(a) + int(_mods.get("check", 0.0)) + int(_mods.get(_attr_mod_key(a), 0.0))
	var total := roll + bonus
	# SNAKE EYES ALWAYS FAILS AND BOXCARS ALWAYS SUCCEEDS. Without this a Legendary check is simply
	# shut to a low characteristic, and the small chance of the impossible landing is most of the
	# reason anyone rolls at all.
	var success := (total >= dc or roll == 12) and roll != 2
	var result := {
		"attr": a, "dc": dc, "difficulty": difficulty, "roll": roll,
		"bonus": bonus, "total": total, "success": success,
		"critical": roll == 12, "fumble": roll == 2,
	}
	if id != "":
		_check_results[id] = result
	check_resolved.emit(a, dc, roll, total, success)
	return result


## Per-characteristic check modifiers from Convictions (Rationalist Delusion taxes your Drama).
static func _attr_mod_key(a: int) -> String:
	return ["logic_check", "instinct_check", "perception_check", "drama_check"][a]


## Has this check already resolved this run, and how? An empty Dictionary means "not yet rolled".
## Used by anything that must SHOW its state without CAUSING the roll — a gate already open, a wall
## already known to be hollow.
func check_result(id: String) -> Dictionary:
	return _check_results.get(id, {})


## The odds of passing, as a percentage, for a UI that wants to warn you before you gamble. Exact
## rather than sampled: 2d6 has 36 outcomes and counting them is cheaper than rolling.
func odds(a: int, difficulty: String) -> int:
	var dc: int = DIFFICULTY.get(difficulty, 10)
	var bonus := attr(a) + int(_mods.get("check", 0.0)) + int(_mods.get(_attr_mod_key(a), 0.0))
	var wins := 0
	for d1 in range(1, 7):
		for d2 in range(1, 7):
			var roll := d1 + d2
			if (roll + bonus >= dc or roll == 12) and roll != 2:
				wins += 1
	return int(round(100.0 * wins / 36.0))


# ==============================================================================================
# CONVICTIONS
# ==============================================================================================

func gain_conviction(id: String) -> bool:
	if not CONVICTIONS.has(id) or convictions.has(id):
		return false
	convictions[id] = {"state": "loose", "progress": 0}
	convictions_changed.emit()
	save_state()
	return true


func conviction_state(id: String) -> String:
	return convictions.get(id, {}).get("state", "")


## WHAT A FINISHED SHEET IS FOR. Slots are the other half of the progression and the slower half:
## two at a time against four Convictions that take two or three descents each. Once the
## characteristics are at their ceiling this is where Insight goes, and it buys the thing the player
## is actually still short of — room to think about more than two ideas at once.
func slot_price() -> int:
	return 120 + 80 * maxi(slots - 2, 0)


func can_buy_slot() -> bool:
	return slots < MAX_SLOTS


func buy_slot() -> bool:
	var price := slot_price()
	if insight < price or not can_buy_slot():
		return false
	insight -= price
	slots += 1
	insight_changed.emit(insight)
	convictions_changed.emit()
	save_state()
	return true


## How this run's checks went, for anything that wants to describe the descent afterwards.
## Read off the memo, which begin_run clears and end_run leaves standing.
func check_tally() -> Dictionary:
	var passed := 0
	var failed := 0
	for id: String in _check_results:
		if bool(_check_results[id].success):
			passed += 1
		else:
			failed += 1
	return {"passed": passed, "failed": failed, "total": passed + failed}


func slots_used() -> int:
	var n := 0
	for id: String in convictions:
		if convictions[id].state == "held":
			n += 1
	return n


## Take a loose idea seriously: it occupies a slot until it settles.
func take_up(id: String) -> bool:
	if conviction_state(id) != "loose" or slots_used() >= slots:
		return false
	convictions[id].state = "held"
	convictions[id].progress = 0
	convictions_changed.emit()
	save_state()
	return true


## One descent's worth of thinking. Called when a run ENDS, win or lose — you think about these
## things on the way down and on the way back up, and dying is not a reason to stop.
## Returns the ids that settled, so the hub can put them in someone's mouth.
func advance_convictions() -> Array[String]:
	var settled: Array[String] = []
	for id: String in convictions:
		var c: Dictionary = convictions[id]
		if c.state != "held":
			continue
		c.progress = int(c.progress) + 1
		if c.progress >= int(CONVICTIONS[id].runs):
			c.state = "settled"
			settled.append(id)
	if not settled.is_empty():
		_rebuild_mods()
		characteristics_changed.emit()
		convictions_changed.emit()
	save_state()
	return settled


## Fold every SETTLED Conviction's effect into the modifier table, then re-apply this run's boons on
## top. Called on load, on settling, and at the start of every run — never incrementally, because
## "apply the delta once" is exactly the bookkeeping that survives four refactors and then
## double-applies.
func _rebuild_mods() -> void:
	_mods.clear()
	for id: String in convictions:
		if convictions[id].state != "settled":
			continue
		var eff: Dictionary = CONVICTIONS[id].get("effect", {})
		for a: int in eff.get("attr", {}):
			_add_mod("attr_%d" % a, float(eff.attr[a]))
		for k: String in eff.get("mod", {}):
			_add_mod(k, float(eff.mod[k]))
		if eff.has("flag"):
			_add_mod("flag_" + str(eff.flag), 1.0)
	for b: String in run_boons:
		_apply_boon_mods(b)


func _add_mod(key: String, amount: float) -> void:
	_mods[key] = float(_mods.get(key, 0.0)) + amount


# ==============================================================================================
# BOONS AND THE RUN
# ==============================================================================================

## Three boons to choose between, weighted toward your strongest characteristics so investment
## compounds into an identity instead of a flat sheet. Never offers one already taken this run.
func offer_boons(count := 3) -> Array[String]:
	var pool: Array[String] = []
	for id: String in BOONS:
		if id in run_boons:
			continue
		# weight = 1 + characteristic, entered that many times. Crude, legible, does the job.
		for i in 1 + attr(int(BOONS[id].attr)):
			pool.append(id)
	var out: Array[String] = []
	while out.size() < count and not pool.is_empty():
		var pick: String = pool[_rng.randi_range(0, pool.size() - 1)]
		out.append(pick)
		# Rebuild WITHOUT the pick, by hand. Array.filter() returns an UNTYPED Array, which will not
		# assign back into an Array[String] — it fails at runtime, not at parse time, and only on the
		# second boon offered. Building a fresh typed array is the version that runs.
		var rest: Array[String] = []
		for id: String in pool:
			if id != pick:
				rest.append(id)
		pool = rest
	return out


func take_boon(id: String) -> bool:
	if not BOONS.has(id) or id in run_boons:
		return false
	run_boons.append(id)
	_apply_boon_mods(id)
	boons_changed.emit()
	return true


func _apply_boon_mods(id: String) -> void:
	for k: String in BOONS[id].get("mod", {}):
		_add_mod(k, float(BOONS[id].mod[k]))


func add_insight(amount: int) -> void:
	run_insight += amount


## A fresh descent. Boons, checks and run tallies reset; the permanent sheet does not.
func begin_run(seed_value := 0) -> void:
	run_boons.clear()
	_check_results.clear()
	run_insight = 0
	run_rooms_cleared = 0
	run_kills = 0
	last_death_cause = ""
	_rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	_rebuild_mods()                    # drops last run's boons, keeps settled Convictions
	runs_taken += 1
	characteristics_changed.emit()
	boons_changed.emit()


## The descent is over either way. Bank the Insight, advance the cabinet, drop the boons.
## Returns the Convictions that settled.
func end_run(victory: bool) -> Array[String]:
	if victory:
		victories += 1
	else:
		deaths += 1
	insight += run_insight
	insight_changed.emit(insight)
	run_boons.clear()                  # before advance, so _rebuild_mods sheds them
	var settled := advance_convictions()
	_rebuild_mods()
	boons_changed.emit()
	save_state()
	return settled


# ==============================================================================================
# PERSISTENCE
# ==============================================================================================
#
# A plain JSON blob rather than a resource: this is the one file a player would ever want to delete
# to start over, and it should be readable when they do.

func save_state() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"characteristics": characteristics, "unspent": unspent, "insight": insight,
		"slots": slots, "runs": runs_taken, "deaths": deaths, "victories": victories,
		"complete": slice_complete, "convictions": convictions,
	}))


func load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_rebuild_mods()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_rebuild_mods()
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		_rebuild_mods()
		return
	var d: Dictionary = data
	# int(), not a cast: JSON round-trips every number as a float, so the sheet comes back as
	# [2.0, 2.0, …]. Every comparison still works, which is what makes this the kind of bug you find
	# three systems later when something typed refuses the array.
	var loaded: Array = d.get("characteristics", [])
	for i in mini(loaded.size(), 4):
		characteristics[i] = clampi(int(loaded[i]), MIN_ATTR, MAX_ATTR)
	unspent = int(d.get("unspent", 2))
	insight = int(d.get("insight", 0))
	slots = clampi(int(d.get("slots", 2)), 2, MAX_SLOTS)
	runs_taken = int(d.get("runs", 0))
	deaths = int(d.get("deaths", 0))
	victories = int(d.get("victories", 0))
	slice_complete = bool(d.get("complete", false))
	convictions.clear()
	for id: String in d.get("convictions", {}):
		if not CONVICTIONS.has(id):
			continue                   # a save written before this Conviction existed
		var c: Dictionary = d.convictions[id]
		convictions[id] = {"state": str(c.get("state", "loose")), "progress": int(c.get("progress", 0))}
	_rebuild_mods()


## Back to a first-ever launch. The tutor offers this once you have died at least once.
func reset_state() -> void:
	characteristics = [2, 2, 2, 2]
	unspent = 2
	insight = 0
	slots = 2
	runs_taken = 0
	deaths = 0
	victories = 0
	slice_complete = false
	convictions.clear()
	run_boons.clear()
	_check_results.clear()
	_mods.clear()
	save_state()
	characteristics_changed.emit()
	convictions_changed.emit()
	insight_changed.emit(insight)

extends SceneTree
## Headless verification of the characteristic model. Run:
##   Godot_console.exe --headless --path . --script res://scripts/traits/tests/verify_traits.gd
## Non-zero exit code on any failure.
##
## The model is deliberately free of UI and scene lookups (see traits.gd's header), so this suite
## can hold the whole progression system still without a viewport, an autoload or a frame. That is
## the entire reason the split exists — this file is what it buys.
##
## The Traits script is instantiated DIRECTLY rather than reached through /root/Traits: a --script
## run registers no autoloads, and constructing it by hand also means _ready never fires, so no test
## is at the mercy of whatever save file happens to be on this machine.

var _fails: Array[String] = []
var _suites := 0

## Every suite reports itself done, and the count is checked at the end. A runtime error inside a
## suite unwinds silently and would otherwise print PASS having run half the file — the same trap
## verify_dungeon.gd guards against with EXPECTED_SUITES.
const EXPECTED_SUITES := 7

const SAVE_BACKUP := "user://traits_save.dat.verify_backup"


func _initialize() -> void:
	_stash_real_save()

	_check_suite()
	_extremes_suite()
	_memo_suite()
	_conviction_suite()
	_persistence_suite()
	_boon_suite()
	_economy_suite()

	_restore_real_save()

	if _suites != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported — one unwound silently"
				% [_suites, EXPECTED_SUITES])
	if _fails.is_empty():
		print("[VERIFY] TRAITS PASS")
		quit(0)
	else:
		print("[VERIFY] TRAITS FAIL — %d problem(s):" % _fails.size())
		for f in _fails:
			print("   " + f)
		quit(1)


func _new_model() -> Node:
	var t: Node = load("res://scripts/traits/traits.gd").new()
	t.reset_state()
	t.begin_run(12345)
	return t


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _done(name: String, note: String) -> void:
	_suites += 1
	print("[VERIFY] %s suite: %s" % [name, note])


# ----------------------------------------------------------------------------------------------

## 2d6 stays inside 2..12, the bonus is exactly the characteristic, and total is their sum.
func _check_suite() -> void:
	var t := _new_model()
	var lo := 99
	var hi := 0
	for i in 3000:
		var r: Dictionary = t.check(t.Attr.LOGIC, "medium")
		lo = mini(lo, r.roll)
		hi = maxi(hi, r.roll)
		_ok(r.total == r.roll + r.bonus, "total is not roll + bonus")
		_ok(r.bonus == t.attr(t.Attr.LOGIC), "bonus is not the live characteristic")
		if not _fails.is_empty():
			break
	_ok(lo == 2 and hi == 12, "2d6 range was %d..%d, expected 2..12" % [lo, hi])
	_done("check", "3000 rolls span %d..%d, total == roll + bonus" % [lo, hi])
	t.free()


## Snake eyes always fails however good you are; boxcars always succeeds however hard it is.
## Without both, a Legendary check is simply shut to a low characteristic and a Trivial one is
## unloseable — and the rare reversal is most of why anyone rolls.
func _extremes_suite() -> void:
	var t := _new_model()
	for i in 4:
		t.characteristics[i] = t.MAX_ATTR
	var fumbles := 0
	for i in 4000:
		var r: Dictionary = t.check(t.Attr.LOGIC, "trivial")
		if r.roll == 2:
			fumbles += 1
			_ok(not r.success, "snake eyes passed a trivial check at max characteristic")
	_ok(fumbles > 0, "4000 trivial rolls produced no snake eyes — the dice are not 2d6")

	var t2 := _new_model()
	for i in 4:
		t2.characteristics[i] = t2.MIN_ATTR
	var crits := 0
	for i in 4000:
		var r: Dictionary = t2.check(t2.Attr.DRAMA, "legendary")
		if r.roll == 12:
			crits += 1
			_ok(r.success, "boxcars failed a legendary check at minimum characteristic")
	_ok(crits > 0, "4000 legendary rolls produced no boxcars")
	_done("extremes", "%d fumbles forced a fail, %d crits forced a pass" % [fumbles, crits])
	t.free()
	t2.free()


## A check with an id is FIXED for the run — the whole point, since re-entering a room must not
## re-roll the wall that wasn't hollow. And begin_run must forget them all again.
func _memo_suite() -> void:
	var t := _new_model()
	var first: Dictionary = t.check(t.Attr.PERCEPTION, "medium", "wall_a")
	for i in 200:
		var again: Dictionary = t.check(t.Attr.PERCEPTION, "medium", "wall_a")
		_ok(again.roll == first.roll and again.success == first.success,
				"a memoised check re-rolled within the same run")
	_ok(not t.check_result("wall_a").is_empty(), "check_result did not report a resolved check")
	_ok(t.check_result("never_rolled").is_empty(),
			"check_result invented a result for a check that never ran")

	# An id-less check is explicitly allowed to differ; if it never does, memoisation has leaked.
	var seen := {}
	for i in 200:
		seen[t.check(t.Attr.LOGIC, "medium").roll] = true
	_ok(seen.size() > 1, "id-less checks returned one frozen value — memoisation leaked")

	t.begin_run(999)
	_ok(t.check_result("wall_a").is_empty(), "begin_run did not clear the check memo")
	_done("memo", "an id sticks for the run, an empty id never does, begin_run forgets")
	t.free()


## A Conviction settles after exactly `runs` descents and applies its effect exactly ONCE.
## The double-apply is the bug this suite exists for: it is invisible for one run and compounding
## thereafter.
func _conviction_suite() -> void:
	var t := _new_model()
	var base: int = t.attr(t.Attr.INSTINCT)
	_ok(t.gain_conviction("fear_of_the_abyss"), "could not gain a Conviction")
	_ok(not t.gain_conviction("fear_of_the_abyss"), "gained the same Conviction twice")
	_ok(not t.gain_conviction("no_such_idea"), "gained a Conviction that does not exist")
	_ok(t.conviction_state("fear_of_the_abyss") == "loose", "a new Conviction was not loose")
	_ok(t.attr(t.Attr.INSTINCT) == base, "a LOOSE Conviction already changed the sheet")

	_ok(t.take_up("fear_of_the_abyss"), "could not take up a loose Conviction")
	_ok(t.slots_used() == 1, "taking one up did not consume a slot")
	_ok(t.attr(t.Attr.INSTINCT) == base, "a HELD Conviction already changed the sheet")

	# runs == 2, so the first end_run advances it and the second settles it.
	_ok(t.end_run(false).is_empty(), "a Conviction settled a descent early")
	_ok(t.conviction_state("fear_of_the_abyss") == "held", "it left the slot too soon")
	var settled: Array = t.end_run(false)
	_ok(settled.has("fear_of_the_abyss"), "it did not settle on the run it was due")
	_ok(t.attr(t.Attr.INSTINCT) == base + 1, "settling did not apply its characteristic shift")
	_ok(t.slots_used() == 0, "a settled Conviction still occupies its slot")

	# Six more descents must not move it a second time.
	for i in 6:
		t.end_run(false)
	_ok(t.attr(t.Attr.INSTINCT) == base + 1,
			"a settled Conviction applied its effect more than once (%d, expected %d)"
					% [t.attr(t.Attr.INSTINCT), base + 1])

	# Slots are finite: two held, and the third has nowhere to go.
	var t2 := _new_model()
	for id: String in ["fear_of_the_abyss", "rationalist_delusion", "heroic_hubris"]:
		t2.gain_conviction(id)
	_ok(t2.take_up("fear_of_the_abyss") and t2.take_up("rationalist_delusion"),
			"could not fill the two slots")
	_ok(not t2.take_up("heroic_hubris"), "a third Conviction fitted into two slots")
	_done("conviction", "settles on schedule, applies once, and respects the slot count")
	t.free()
	t2.free()


## The sheet survives a save/load round trip — including the settled effect, which is rebuilt from
## the Conviction states rather than stored, so this is really a test that the rebuild is faithful.
func _persistence_suite() -> void:
	var t := _new_model()
	t.gain_conviction("heroic_hubris")
	t.take_up("heroic_hubris")
	t.end_run(false)
	t.end_run(true)                                  # settles: +1 DRAMA, -1 max hp
	t.spend_point(t.Attr.LOGIC)
	t.insight = 41
	t.save_state()

	var drama: int = t.attr(t.Attr.DRAMA)
	var logic: int = t.attr(t.Attr.LOGIC)
	var hp: int = t.max_hp_delta()

	var t2: Node = load("res://scripts/traits/traits.gd").new()
	t2.load_state()
	_ok(t2.attr(t2.Attr.DRAMA) == drama,
			"DRAMA did not survive the round trip (%d vs %d)" % [t2.attr(t2.Attr.DRAMA), drama])
	_ok(t2.attr(t2.Attr.LOGIC) == logic, "a spent point did not survive the round trip")
	_ok(t2.max_hp_delta() == hp, "the settled max-hp penalty did not survive the round trip")
	_ok(t2.insight == 41, "Insight did not survive the round trip")
	_ok(t2.conviction_state("heroic_hubris") == "settled", "the Conviction state did not survive")
	_ok(t2.deaths == 1 and t2.victories == 1, "the run tally did not survive")

	# JSON turns every number into a float; if that leaks through, the sheet stops being ints.
	for i in 4:
		_ok(typeof(t2.characteristics[i]) == TYPE_INT,
				"characteristic %d came back from JSON as a float" % i)
	_done("persistence", "sheet, Conviction and settled effect all survive save/load")
	t.free()
	t2.free()


## Boons: distinct, never repeated, weighted toward strength, and taken boons actually move the
## combat sheet. The typed-array rebuild inside offer_boons is exercised by simply asking twice.
func _boon_suite() -> void:
	var t := _new_model()
	var offer: Array = t.offer_boons(3)
	_ok(offer.size() == 3, "offer_boons returned %d boons, expected 3" % offer.size())
	_ok(offer[0] != offer[1] and offer[1] != offer[2] and offer[0] != offer[2],
			"offer_boons offered the same boon twice in one draw")

	var crit_before: float = t.crit_chance()
	_ok(t.take_boon("logic_weakpoint"), "could not take a boon")
	_ok(not t.take_boon("logic_weakpoint"), "took the same boon twice")
	_ok(absf(t.crit_chance() - (crit_before + 0.15)) < 0.0001,
			"taking a crit boon did not move crit_chance")
	for i in 40:
		_ok(not t.offer_boons(3).has("logic_weakpoint"), "an already-taken boon was offered again")

	# Weighting: a maxed characteristic must dominate the draw over a minimum one.
	var t2 := _new_model()
	t2.characteristics[t2.Attr.DRAMA] = t2.MAX_ATTR
	t2.characteristics[t2.Attr.LOGIC] = t2.MIN_ATTR
	var drama_seen := 0
	var logic_seen := 0
	for i in 400:
		t2.run_boons.clear()
		for id: String in t2.offer_boons(1):
			if t2.BOONS[id].attr == t2.Attr.DRAMA:
				drama_seen += 1
			elif t2.BOONS[id].attr == t2.Attr.LOGIC:
				logic_seen += 1
	_ok(drama_seen > logic_seen,
			"boons are not weighted by characteristic (drama %d vs logic %d)"
					% [drama_seen, logic_seen])

	# A new descent sheds the boons but keeps the permanent sheet.
	var crit_boosted: float = t.crit_chance()
	t.begin_run(7)
	_ok(t.crit_chance() < crit_boosted, "begin_run did not shed last run's boons")
	_ok(t.run_boons.is_empty(), "begin_run left boons on the run")
	_done("boon", "distinct, weighted %d:%d toward strength, shed on a new run"
			% [drama_seen, logic_seen])
	t.free()
	t2.free()


## Insight banks only when the run ends, and points get more expensive as you buy them.
func _economy_suite() -> void:
	var t := _new_model()
	t.add_insight(10)
	_ok(t.insight == 0, "Insight banked mid-run — dying would have kept it")
	_ok(t.run_insight == 10, "run Insight was not tallied")
	t.end_run(true)
	_ok(t.insight == 10, "Insight did not bank when the run ended")

	var first: int = t.point_price()
	t.insight = 999
	_ok(t.buy_point(), "could not buy a point with 999 Insight")
	t.spend_point(t.Attr.LOGIC)
	_ok(t.point_price() > first,
			"the second point cost the same as the first (%d)" % t.point_price())

	# Poverty is enforced.
	var t2 := _new_model()
	t2.insight = 0
	_ok(not t2.buy_point(), "bought a point with no Insight")

	# The ceiling holds.
	var t3 := _new_model()
	t3.characteristics[t3.Attr.LOGIC] = t3.MAX_ATTR
	t3.unspent = 5
	_ok(not t3.spend_point(t3.Attr.LOGIC), "a characteristic went past MAX_ATTR")

	# AND A FINISHED SHEET STOPS SELLING. Every + button greys out at the ceiling while the price
	# kept being quoted, so Insight went in and nothing came out — silently, and for as long as the
	# player kept paying.
	var t4 := _new_model()
	for i in 4:
		t4.characteristics[i] = t4.MAX_ATTR
	t4.insight = 9999
	_ok(t4.is_maxed(), "a sheet at the ceiling does not report itself maxed")
	_ok(not t4.can_place_point(), "can_place_point said yes with every characteristic maxed")
	_ok(not t4.buy_point(), "sold a point that cannot be placed anywhere")
	_ok(t4.insight == 9999, "charged for an unplaceable point (%d left)" % t4.insight)

	# WHERE A FINISHED SHEET'S INSIGHT GOES: room to think about more than two ideas at once.
	var slots_before: int = t4.slots
	var slot_cost: int = t4.slot_price()
	_ok(t4.can_buy_slot(), "a two-slot cabinet says it cannot grow")
	_ok(t4.buy_slot(), "could not buy a slot with 9999 Insight")
	_ok(t4.slots == slots_before + 1, "buying a slot did not add one")
	_ok(t4.insight == 9999 - slot_cost, "a slot did not cost what it quoted")
	_ok(t4.slot_price() > slot_cost, "the second slot cost the same as the first")
	# The ceiling is one slot per Conviction; past that it could never be filled.
	while t4.can_buy_slot():
		t4.buy_slot()
	_ok(t4.slots == t4.MAX_SLOTS, "slots stopped short of MAX_SLOTS at %d" % t4.slots)
	var held_insight: int = t4.insight
	_ok(not t4.buy_slot(), "sold a slot beyond one per Conviction")
	_ok(t4.insight == held_insight, "charged for a slot it refused to sell")

	# A finished sheet is a state the model can report, and the hub asks.
	_ok(t4.is_maxed(), "a maxed sheet does not report itself finished")
	var t5 := _new_model()
	_ok(not t5.is_maxed(), "a fresh sheet reported itself finished")
	t5.free()
	_done("economy", "Insight banks on end_run, points cost %d then %d" % [first, t.point_price()])
	t.free()
	t2.free()
	t3.free()


# --- keep the developer's real save file out of this ------------------------------------------

func _stash_real_save() -> void:
	if FileAccess.file_exists("user://traits_save.dat"):
		DirAccess.copy_absolute("user://traits_save.dat", SAVE_BACKUP)


func _restore_real_save() -> void:
	if FileAccess.file_exists(SAVE_BACKUP):
		DirAccess.copy_absolute(SAVE_BACKUP, "user://traits_save.dat")
		DirAccess.remove_absolute(SAVE_BACKUP)
	elif FileAccess.file_exists("user://traits_save.dat"):
		DirAccess.remove_absolute("user://traits_save.dat")

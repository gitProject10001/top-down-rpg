class_name Health
extends Node
## Hit points + invulnerability for ANY entity (player or enemy).
##
## WHY a component: damage flows through this ONE node, so "i-frames" (dash now, parry later) are
## just a flag here — not logic copy-pasted into every attacker. Anyone who can be hurt has a Health.

signal damaged(amount: int, source: Node)   ## took damage (after it was applied)
signal died                                  ## hp reached zero
signal changed(current: int, maximum: int)   ## hp changed (for HUD later)

@export var max_hp := 5

var hp: int
var invulnerable := false
## The value the scene AUTHORED, kept because max_hp is now something a run can shift (a settled
## Conviction can cost you a block). Without it, applying "+0" twice would drift the ceiling.
var base_max_hp := 5
var _dead := false
## Invulnerability with an EXPIRY, alongside the flag. The flag has four writers already (dash,
## dash-attack's two, and whatever comes next), and they clobber each other: a dash converting into
## a lunge clears i-frames the dash was still meant to be holding. A deadline cannot be cleared by
## somebody else's `false`, so a source that wants "keep these for N more seconds" says so here
## instead of owning a timer and racing.
##
## Real seconds, matching the dash/shoot cooldowns in player.gd — so a slowed clock (a Notice card)
## does not stretch them.
var _invuln_until := 0.0

func _ready() -> void:
	base_max_hp = max_hp
	hp = max_hp
	changed.emit(hp, max_hp)

## Returns the damage actually applied — 0 when dead, invulnerable, or handed nothing. The return
## is what lets attacker feedback (hitstop, shake, sparks) tell a landed blow from an absorbed one;
## a blow that changed no hp is not a hit, however hard it overlapped.
func take_damage(amount: int, source: Node = null) -> int:
	if _dead or is_invulnerable() or amount <= 0:
		return 0
	hp = max(hp - amount, 0)
	changed.emit(hp, max_hp)
	damaged.emit(amount, source)
	if hp == 0:
		_dead = true
		died.emit()
	return amount

func set_invulnerable(value: bool) -> void:
	invulnerable = value

## Hold i-frames for `seconds` beyond now, whatever the flag does in the meantime. Never shortens an
## existing window — two overlapping sources should give you the longer one, not the last one.
func extend_invulnerable(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_invuln_until = maxf(_invuln_until, Time.get_ticks_msec() / 1000.0 + seconds)

func is_invulnerable() -> bool:
	return invulnerable or Time.get_ticks_msec() / 1000.0 < _invuln_until

func is_alive() -> bool:
	return not _dead

## Undo death. `_dead` LATCHES — take_damage returns early forever once it is set — so without this
## a player who dies and is put back in the hub arrives alive-looking and permanently unhittable,
## with zero hp and an FSM parked in Dead. Nothing else clears it.
func revive() -> void:
	_dead = false
	invulnerable = false
	_invuln_until = 0.0
	hp = max_hp
	changed.emit(hp, max_hp)

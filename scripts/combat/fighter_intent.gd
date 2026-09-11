class_name FighterIntent
extends Node
## WHAT A FIGHTER IS TRYING TO DO THIS FRAME, with no opinion about who decided it.
##
## WHY THIS EXISTS. The mirror enemy is meant to be the player — same rig, same states, same
## directional rules — and the only honest way to build that is to let an AI drive a Player body.
## The states could not do that while they read Input directly: Input is a global, and there is
## exactly one of it. So the states now read THIS, a plain surface with no logic in it, and the
## question of where the values came from moves to the child node that fills it in:
##   PlayerIntent  — a person, through Input                (scripts/combat/player_intent.gd)
##   DuelBrain     — the duelist AI                          (scripts/combat/duel_brain.gd)
##
## Player._ready adds a PlayerIntent when a scene brought none, so the three player scenes that
## know nothing about any of this keep working unchanged.
##
## THE RELEASE IS LATCHED, everything else is a level. A guard being held and a direction being
## chosen are states of the world that a physics tick can simply read. "The attack button came up"
## is an EVENT, and a tick that happens not to be running when it fires would drop the swing — so
## it is stored until somebody consumes it, which is the same buffering attack.gd already does for
## a queued chain press.

## Movement request, already in WORLD XZ (x = +X, y = +Z). World rather than stick space because
## mapping a stick through the camera is a decision about input devices, and an AI has no camera.
var move := Vector2.ZERO

## WHERE THIS FIGHTER IS LOOKING, in world XZ, or ZERO for "ask the input device". ZERO is what a
## person leaves it at: their aim comes from the cursor or the left stick, which is Player.aim_point's
## existing job. A brain has neither, and without this it inherited the HUMAN'S CURSOR — the duelist
## turned to face wherever the player's mouse was, acquired its targets through that, and swung at
## empty ground. Anything not driven by a person must say where it is looking.
var look := Vector2.ZERO

## Is the guard up? (the `block` action for a person; a decision for a brain)
var guard := false

## Which way the guard is held. Kept across a lowered guard on purpose: raising it again should
## bring back the direction you last chose, not snap to a default you have to correct.
var guard_dir := SwingDir.UP

## Is an attack being wound up? Held true for as long as the swing is being charged; the release
## is what throws it.
var attack_held := false:
	set(value):
		attack_held = value
		if not value:
			_attack_consumed = false
var _attack_consumed := false

func can_start_attack() -> bool:
	return attack_held and not _attack_consumed

func consume_attack() -> void:
	_attack_consumed = true
	_release = false

## Which way the wind-up is currently aimed. Free to change while `attack_held` — that is the
## feint, and it costs nothing but the time you spend holding.
var attack_dir := SwingDir.UP

var _release := false


## The body this intent drives. Always the parent: an intent that is not a child of a fighter has
## nobody to speak for.
func fighter() -> Player:
	return get_parent() as Player


## "Throw the swing now." Called on the frame the button comes up, or by a brain that has decided.
func request_release() -> void:
	_release = true


## Read once and clear. The caller that consumes it owns the swing; nobody else can also get it.
func consume_release() -> bool:
	var r := _release
	_release = false
	return r


## Drop everything mid-flight — death, a stagger, dialogue. Without this a fighter interrupted
## while holding a swing wakes up still holding it.
func clear() -> void:
	move = Vector2.ZERO
	guard = false
	attack_held = false
	_release = false

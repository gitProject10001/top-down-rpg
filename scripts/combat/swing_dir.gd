class_name SwingDir
extends RefCounted
## THE FOUR-WAY VOCABULARY that every strike and every guard in the directional-combat system
## speaks. One file, because the mechanic is a comparison between two of these values and a
## comparison is only meaningful if both sides derived their value the same way.
##
## THE MIRROR IS THE SUBTLE PART, and it is why this is a class rather than four loose constants.
## A direction is authored in the frame of whoever is holding the weapon: my LEFT swing travels
## from my left. Arriving at the person in front of me, it comes in on THEIR right. So an exchange
## has to flip left and right exactly once, on the defender's side, while up and down pass through
## untouched (my overhead is still an overhead when it lands on your head).
##
## Mount & Blade does flip them: you guard toward the side of the screen the blade is coming from.
## Guard.mirror_incoming turns the flip off for anyone who reads it the other way; what must not
## happen is the flip being applied in two places, or in none.

enum {
	NONE = -1,   ## no direction chosen (stick centred, mouse still) — never matches a guard
	UP = 0,      ## overhead
	DOWN = 1,    ## thrust / low
	LEFT = 2,
	RIGHT = 3,
}

const COUNT := 4
const ALL: Array[int] = [UP, DOWN, LEFT, RIGHT]


## Stick or mouse-travel vector -> direction, on the SCREEN convention the input devices already
## use: +x is right, +y is DOWN (Input.get_vector("aim_up","aim_down") and mouse relative both
## agree on this, so nothing has to be negated at the call site).
##
## Whichever axis is larger wins outright rather than being blended: the mechanic is a match or a
## miss, so a 45-degree stick has to resolve to ONE of the four or the player is guarding nothing.
static func from_vector(v: Vector2, deadzone := 0.35) -> int:
	if v.length() < deadzone:
		return NONE
	if absf(v.x) > absf(v.y):
		return RIGHT if v.x > 0.0 else LEFT
	return DOWN if v.y > 0.0 else UP


## The same swing, seen from the other side of the exchange. See the header.
static func mirror(d: int) -> int:
	match d:
		LEFT:
			return RIGHT
		RIGHT:
			return LEFT
	return d


## For the HUD, the probe output and debug prints.
static func label(d: int) -> String:
	match d:
		UP:
			return "up"
		DOWN:
			return "down"
		LEFT:
			return "left"
		RIGHT:
			return "right"
	return "none"


## A unit vector pointing the way a direction reads on screen — the HUD indicator's geometry, and
## the AI's "which side is open" arithmetic, both want this rather than a switch of their own.
static func to_vector(d: int) -> Vector2:
	match d:
		UP:
			return Vector2(0.0, -1.0)
		DOWN:
			return Vector2(0.0, 1.0)
		LEFT:
			return Vector2(-1.0, 0.0)
		RIGHT:
			return Vector2(1.0, 0.0)
	return Vector2.ZERO

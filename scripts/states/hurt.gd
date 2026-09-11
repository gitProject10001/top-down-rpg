extends State
## Brief stagger after taking a hit: input is ignored, knockback (set by the player when damaged)
## plays out, then control returns. Stops the player from acting through damage.

@export var stun_time := 0.28
## How long a heavy knockback slides before friction takes it. Only applies above 6 m/s, so a
## normal hit still behaves exactly as it did.
@export var slide_time := 0.38

var _elapsed := 0.0
var _knocked := false
var _duration := 0.28

func enter() -> void:
	_elapsed = 0.0
	_duration = stun_time
	_knocked = player.velocity.length() >= 6.0
	player.set_tree_active(true)
	if player.sword:
		player.sword.cancel_swing()
	if player.intent:
		player.intent.consume_attack()
	if player.has_clip("hurt_chest"):
		player.play_clip("hurt_chest")

func extend_stun(seconds: float) -> void:
	_duration = maxf(_duration, seconds)

func physics_update(delta: float) -> void:
	_elapsed += delta
	player.apply_gravity(delta)
	# LET A REAL SHOVE PLAY OUT. Friction from the first frame bled a 12 m/s kick down to nothing
	# inside the 0.28 s stun, so the attack whose entire purpose is to put the player back out at
	# mace range moved them about a third of a metre. Anything above a walking knock gets a moment
	# to travel before the friction starts; ordinary hits are unaffected.
	if _elapsed > slide_time or player.velocity.length() < 6.0:
		player.apply_friction(delta)
	player.move_and_slide()
	# A big shove keeps the player out of control until it has actually carried them, or the stun
	# ends while they are still travelling and they can simply walk back in mid-flight.
	if _elapsed >= maxf(_duration, slide_time if _knocked else 0.0):
		fsm.transition_to("Idle")

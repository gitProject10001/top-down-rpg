extends Node
## THE FEEDBACK LAYER'S FRONT DOOR — the one file that answers "does this effect fire on CONTACT
## or on a BEAT?". That question produced a real bug this project has already paid for once:
## hitstop and two screen shakes fired identically whether the mace hit the player or the floor,
## and the loudest feedback in the game carried no information at all.
##
## Two vocabularies, and every entry point names which one it speaks:
##
##   CONTACT — a blow that changed hp. Driven only from `HitBox.dealt_hit` with `applied > 0`;
##             hitstop lives here and nowhere else, because hitstop is the one effect that
##             operates ON the animation (it stops the arc at the moment of contact), and spent on
##             a whiff it says nothing.
##
##   BEAT    — the animation arrived somewhere. Fires whether or not anything was hit, and that is
##             its job: a mace hitting the ground throws dust at the ground, a footfall thumps,
##             a whiff still shakes a little (the mass arrived, just not on you).
##
## Autoload, resolved defensively: callers that outlive these services (the ogre solver in a bare
## test scene) degrade to silence instead of crashing.

@onready var _fx: Node = get_node_or_null(^"/root/Fx")
@onready var _bus: Node = get_node_or_null(^"/root/EventBus")

## The rumble in flight (see rumble()): its real-clock deadline and motor strengths.
var _rumble_until := 0.0
var _rumble_weak := 0.0
var _rumble_strong := 0.0


## CONTACT. A blow landed and hp changed: freeze the arc, kick the camera, buzz the pad.
## The rumble rides the shake (the two are the same statement in different senses); it is weak-
## motor-led so ordinary contacts tick rather than shudder.
func contact_landed(hitstop: float, hitstop_scale: float, shake: float) -> void:
	if _fx and hitstop > 0.0:
		_fx.hitstop(hitstop, hitstop_scale)
	if _bus and shake > 0.0:
		_bus.combat_impact.emit(shake)
	if shake > 0.0:
		rumble(clampf(shake * 0.9, 0.0, 0.6), clampf(shake * 0.25, 0.0, 0.3), 0.12)


## CONTACT. The PLAYER's hp changed — the receiving half of the vocabulary, fired from the one
## place every damage source converges (player._on_damaged), so a mace, a bolt and a ground wave
## all sting the same way. Heavier in the hands than dealing (strong-motor-led), briefer than an
## attacker's freeze in time: being hit should thud, not stall the fight.
func contact_taken() -> void:
	if _fx:
		_fx.hitstop(0.09, 0.1)
	if _bus:
		_bus.combat_impact.emit(0.35)
	rumble(0.3, 0.8, 0.22)


## CONTACT. The blow that emptied an enemy's Health — a kill reads harder than a chip or the
## fight has no punctuation. Fired from the lethal hit (hp just reached 0, before `died`), so it
## MERGES with the same swing's own contact freeze in Fx.hitstop: latest deadline, deepest scale.
func kill_landed() -> void:
	if _fx:
		_fx.hitstop(0.14, 0.05)
	if _bus:
		_bus.combat_impact.emit(0.3)
	rumble(0.7, 0.5, 0.18)


## The pad's share of a contact. Device 0, and a no-op without a pad — Godot swallows vibration
## on absent devices, so this needs no connected-controller bookkeeping.
##
## MERGED like the hitstop, and for the same reason: start_joy_vibration is last-write-wins, and
## the strong "you were hurt" shudder fires INSIDE HurtBox.apply_hit — milliseconds before the
## attacker's own weak contact tick rides the same call stack and would overwrite it. Overlapping
## asks combine: strongest motors, latest deadline.
func rumble(weak: float, strong: float, duration: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now < _rumble_until:
		weak = maxf(weak, _rumble_weak)
		strong = maxf(strong, _rumble_strong)
		duration = maxf(duration, _rumble_until - now)
	_rumble_weak = weak
	_rumble_strong = strong
	_rumble_until = now + duration
	Input.start_joy_vibration(0, weak, strong, duration)


## BEAT. The animation asks for a camera kick regardless of contact — the whiff share of an
## impact, a detonation, anything whose mass arriving is the message.
func beat_shake(v: float) -> void:
	if _bus and v > 0.0:
		_bus.combat_impact.emit(v)


## BEAT. Dust at a point, sized by the caller.
func beat_dust(at: Vector3, size: float) -> void:
	if _fx and size > 0.0:
		_fx.dust(at, size)


## BEAT. Something heavy met the ground: splash if the ground is water, dust otherwise.
## Water is resolved per call, not at ready — it is an autoload declared AFTER this one, so it is
## not under /root yet when this facade readies. Footfalls are a few per second; the lookup is
## nothing.
## Water wins over dust — a foot coming down in the shallows throws water, not soil — and it wins
## even when the foot is airborne (`grounded` false gates only the dust).
func beat_ground_contact(at: Vector3, dust_size: float, grounded := true,
		splash_size := 1.6) -> void:
	if _fx == null:
		return
	var water := get_node_or_null(^"/root/Water")
	if water and water.is_water(at):
		_fx.splash(at, splash_size)
	elif grounded:
		_fx.dust(at, dust_size)


## BEAT. A footfall's ground shock, felt by the player with a squared distance falloff, floored so
## an ordinary walking step carries no shake at all — what should be felt is the DIFFERENCE
## between a step and something heavier, and a shake that fires one and a half times a second
## forever is noise, not a cue. This owns the player lookup so the animation solver does not have
## to know what a "player" is.
func footfall_shake(from: Vector3, impact: float, shake_range: float, shake_floor: float,
		scale: float) -> void:
	if _bus == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var d := from.distance_to(player.global_position)
	if d >= shake_range:
		return
	var near := 1.0 - d / shake_range
	var force := maxf(impact - shake_floor, 0.0)
	var strength := scale * force * near * near
	if strength > 0.004:
		_bus.combat_impact.emit(clampf(strength, 0.0, 0.25))

class_name HeroTorch
extends OmniLight3D
## The player's carried light: the one light in the game that MOVES and casts, and the reason the
## rest of the crypt's lighting work is worth doing at all. Everything else down there is nailed to
## a wall, so every shadow in the dungeon is static until this thing walks into the room.
##
## THE OFFSET IS THE DESIGN, not decoration. This light used to sit at (0, 1.1, 0) — dead centre of
## the player's own body — with `light_cull_mask` excluding render layer 2 so it would not touch the
## character at all. toon_skin.gd:53 explains why that mask had to exist: a point source at the
## body's centre lights front, back and both sides at once, N·L is positive nearly everywhere, and
## a shadow side becomes geometrically impossible. The mask was a workaround for a light in the
## wrong place.
##
## Put it where a carried torch actually is — out to the side, forward, at hand height — and the
## problem dissolves. N·L varies across the body properly, the far side of the torso becomes a real
## shadow side, and the character can cast its own shadow across the floor. So the mask goes: this
## light lights the player like it lights everything else, which is what a torch does.
##
## FLICKER IS THE CHEAPEST LARGE UPGRADE IN THE LIGHTING PASS. Once the light casts, modulating it
## makes every shadow it throws breathe — the pillar's shadow across the floor, the player's own on
## the wall, the arcade recesses. Nothing else in the plan buys that much motion for eight lines.

## Peak-to-peak swing as a fraction of the authored energy. Fire, not a fault: at 0.10 the room
## breathes; past ~0.2 it reads as a loose connection.
const FLICKER := 0.10
## Hz. Kept well under the display rate on purpose — TAA reprojects over several frames and Phase 7's
## volumetric fog has its own temporal filter, and both will fight a light that strobes faster than
## they resolve. Fire at this scale is a slow flutter anyway; the fast component is in the flame
## sprite, not in the pool of light on the floor.
const RATE := 7.0
## Metres of positional wander. Tiny, and doing far more work than its size suggests: a light that
## only changes BRIGHTNESS moves no shadow edges at all, so the scene pulses instead of guttering.
## Moving the source is what makes the penumbrae swim.
const JITTER := 0.03
## The torch can be PUT OUT: `toggle_light` (L) hides it and lights it again. In the dungeon the
## torches' pools are the level's own light, and the player may want to see it as it is, or hide
## in the dark. Hidden rather than zeroed, so its shadow map goes with it.
const TOGGLE_ACTION := "toggle_light"

var _base_energy := 0.0
var _base_pos := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _t := 0.0


func _ready() -> void:
	_base_energy = light_energy
	_base_pos = position
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0
	# EXEMPT FROM ROOM DIMMING. Today the torch escapes DungeonRoom.set_lit only because the player
	# is not parented under a DungeonRoom — true by accident of scene layout, and it would gutter
	# the player's own torch to 6% the moment somebody reparented the player into the room they are
	# standing in (which is a reasonable thing to want to do). Say it out loud instead.
	set_meta(DungeonRoom.IGNORE_ROOM_DIM, true)


func _process(delta: float) -> void:
	_t += delta * RATE
	# Two decorrelated samples of one noise field rather than two fields, and sin/cos of the same
	# phase for the wander so the source traces a small ellipse instead of vibrating on one axis.
	light_energy = _base_energy * (1.0 + _noise.get_noise_1d(_t) * FLICKER)
	var wob := _noise.get_noise_1d(_t + 128.0) * JITTER
	position = _base_pos + Vector3(cos(_t * 0.7) * wob, wob * 0.5, sin(_t * 0.7) * wob)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		visible = not visible
		get_viewport().set_input_as_handled()

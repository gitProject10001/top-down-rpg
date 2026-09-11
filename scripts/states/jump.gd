extends State
## AIRBORNE. One press, one arc: an impulse tuned to clear one wilds tier (1.2 m) with margin,
## full air control at run speed, and the three UAL pieces of a jump played on the shared
## Slash node (jump_start, then the jump_air loop, then jump_land) via play_clip — no new
## AnimationTree states. On a body whose library has no jump clips (the Mixamo pair), the
## physics still jumps and the tree simply keeps its last locomotion pose.
##
## apply_gravity is deliberately NOT called while airborne: it zeroes velocity.y whenever
## is_on_floor(), and on the frame after the impulse the body still touches down — the jump
## would be wiped before it began. apply_air_gravity is the unguarded half.

const START_CLIP := "jump_start"
const AIR_CLIP := "jump_air"
const LAND_CLIP := "jump_land"

## 5.5 m/s under the project's 9.8 gravity peaks at 1.54 m: one 1.2 m tier, cleared.
@export var jump_velocity := 5.5
## How long the landing pose holds when standing still; move input cancels it instantly.
@export var land_time := 0.18

var _t := 0.0
var _start_len := 0.0
var _airborne := false
var _in_air_clip := false
var _landed := false


func enter() -> void:
	_t = 0.0
	_airborne = false
	_in_air_clip = false
	_landed = false
	player.velocity.y = jump_velocity
	_start_len = player.play_clip(START_CLIP) if player.has_clip(START_CLIP) else 0.0


func physics_update(delta: float) -> void:
	_t += delta
	if _landed:
		player.apply_gravity(delta)
		player.apply_friction(delta)
		player.move_and_slide()
		if player.get_move_input() != Vector2.ZERO:
			fsm.transition_to("Move")
		elif _t >= land_time:
			fsm.transition_to("Idle")
		return

	player.apply_air_gravity(delta)
	player.face_aim_direction(delta)
	var input := player.get_move_input()
	if input != Vector2.ZERO:
		player.apply_movement(input, delta)
	player.move_and_slide()

	if not player.is_on_floor():
		_airborne = true
		if not _in_air_clip and _start_len > 0.0 and _t >= _start_len \
				and player.has_clip(AIR_CLIP):
			_in_air_clip = true
			player.play_clip(AIR_CLIP)
	elif _airborne:
		# Touched down: hold the landing for a beat, unless the player is already moving.
		_landed = true
		_t = 0.0
		if player.has_clip(LAND_CLIP):
			player.play_clip(LAND_CLIP)
	elif _t > 0.35:
		# Never left the ground (a ceiling directly overhead ate the impulse). Stand down.
		fsm.transition_to("Move" if input != Vector2.ZERO else "Idle")

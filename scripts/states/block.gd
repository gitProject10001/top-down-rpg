extends State
## Holding the guard up. Raises the shield on enter, and opens a short PARRY WINDOW at the start:
##   - hit DURING the window (and from the front) -> the player parries (handled in player.on_incoming_hit)
##   - hit AFTER the window (still holding, from the front) -> blocked (no damage)
## Release the block button to drop the guard. You can dash-cancel out of a block.
##
## On a body with no shield node (player3, the sword body) the guard is a POSE instead — the
## UAL sword-parry stance ("block" in its library). Same window, same rules, same stamina;
## only the visual differs. Note the guard answers only PARRIABLE hits: projectile.gd's colour
## contract routes unparriable (purple) bolts past on_incoming_hit entirely.

const GUARD_CLIP := "block"

@export var parry_window := 0.18   ## seconds after raising during which a frontal hit is a parry
@export var move_scale := 0.5      ## fraction of run speed you can shuffle while guarding

var _t := 0.0

func enter() -> void:
	_t = 0.0
	if player.shield:
		player.shield.raise()
	elif player.has_clip(GUARD_CLIP):
		player.play_clip(GUARD_CLIP)

func exit() -> void:
	if player.shield:
		player.shield.lower()

func physics_update(delta: float) -> void:
	_t += delta
	player.apply_gravity(delta)
	player.apply_movement(player.get_move_input(), delta, move_scale)   # slow shuffle, shield stays up
	player.face_aim_direction(delta)          # keep facing the cursor so "front" tracks the threat
	player.move_and_slide()
	# release, or GUARD BREAK when the shield stamina runs dry
	if not Input.is_action_pressed("block") or player.stamina <= 0.0:
		fsm.transition_to("Move" if player.get_move_input() != Vector2.ZERO else "Idle")

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("dash") and player.can_dash():
		fsm.transition_to("Dash")
	# Jump-cancel, mirroring the dash-cancel: the ground wave deliberately ignores the guard
	# ("ground wave = JUMP" is taught on screen), so the escape it teaches must be reachable
	# WHILE guarding — swallowing Space here would punish exactly the player who learned it.
	elif event.is_action_pressed("jump") and player.is_on_floor() and fsm.has_state("Jump"):
		fsm.transition_to("Jump")

## The player checks this when hit to decide block vs parry.
func is_parry_active() -> bool:
	return _t < parry_window

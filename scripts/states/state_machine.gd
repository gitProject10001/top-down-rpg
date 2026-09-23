class_name StateMachine
extends Node
## Owns the player's single ACTIVE gameplay state and routes engine callbacks to it.
##
## WHY a state machine (instead of a big match/if in the player): combat needs mutually
## exclusive modes (you can't dash mid-block, attacks have cancel windows, dash has
## i-frames). An FSM makes illegal transitions structurally impossible and keeps each
## behaviour in its own small file. Cost: a little boilerplate here — worth it by M3.
##
## Each child Node that extends State is auto-registered by its name (case-insensitive),
## so adding a new state later is just "drop a child node in, in the editor".

@export var initial_state: NodePath          ## Which child to start in (e.g. "Idle").

var current_state: State
var _states: Dictionary = {}                 ## lowercased name -> State node

## The body this machine drives. Kept rather than looked up per call because _unhandled_input needs
## it too, to ask whether a person is actually at the controls.
var _body: Player


func _ready() -> void:
	var body := get_parent() as Player   # the Player owns this StateMachine
	_body = body
	for child in get_children():
		if child is State:
			_states[child.name.to_lower()] = child
			child.player = body
			child.fsm = self
	if initial_state:
		current_state = get_node(initial_state) as State
	if current_state:
		current_state.enter()


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)
	if _body:
		_body.update_combat_animation(delta)


func _unhandled_input(event: InputEvent) -> void:
	if Dialogue.active:
		return                       # combat inputs are suppressed during a conversation
	# ONLY A BODY A PERSON IS DRIVING. _unhandled_input reaches every node in the tree, so once an
	# AI could drive a Player body (the duelist — see scripts/enemy_duelist.gd) the enemy started
	# dashing and jumping on the human's key presses, out of its own brain's control entirely.
	# Decisions for an AI body arrive through its FighterIntent and nowhere else.
	if _body != null and not _body.is_input_driven():
		return
	if event.is_action_pressed("sheathe_weapon") and not event.is_echo():
		_body.toggle_sword_sheath()
		get_viewport().set_input_as_handled()
		return
	if current_state:
		current_state.handle_input(event)


## Does this body have that state at all? Loadouts differ — the sword bodies (player3/4) carry no
## bow so they have no Shoot, and in exchange a DashAttack the others don't.
## transition_to() silently no-ops on an unknown name, which is right for "offer it and let it
## fall through", but wrong when there is a FALLBACK to run instead (dash+attack must still
## plain-dash on a body with no lunge). Ask first in that case.
func has_state(state_name: String) -> bool:
	return _states.has(state_name.to_lower())


## Switch to another state by name (case-insensitive). No-ops if unknown or already active.
func transition_to(state_name: String) -> void:
	var key := state_name.to_lower()
	if not _states.has(key) or _states[key] == current_state:
		return
	if current_state:
		current_state.exit()
	if key in ["attack", "dashattack", "dirattack", "guard", "block"] and _body and _body.sword_sheathed:
		_body.set_sword_sheathed(false)
	current_state = _states[key]
	current_state.enter()

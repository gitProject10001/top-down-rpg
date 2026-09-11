class_name State
extends Node
## Base class for every player state. Intentionally tiny — a state is just a bundle of
## behaviour with a clear entry and exit. Concrete states override only what they need.
##
## The StateMachine sets `player` and `fsm` on each state when the scene loads, so inside
## a state you can read input via `player`, and request a switch via `fsm.transition_to(...)`.

var player: Player   ## The body this state drives (set by the StateMachine). Typed as Player so states get autocomplete.
var fsm              ## Back-reference to the StateMachine (untyped to avoid a cyclic class dep).


func enter() -> void:
	## Called once, the moment we switch INTO this state. Set up timers, flags, animations here.
	pass


func exit() -> void:
	## Called once, the moment we leave this state. Tear down whatever enter() set up.
	pass


func physics_update(_delta: float) -> void:
	## Called every physics frame while this state is active. Movement / state logic goes here.
	pass


func handle_input(_event: InputEvent) -> void:
	## Called for unhandled input while active. Good place to catch attack/dash/block presses (M2+).
	pass

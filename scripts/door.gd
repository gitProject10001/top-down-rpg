class_name Door
extends Node3D
## An interactable double door.
##
## This is the textbook example of the Blender/Godot split:
##   - The LOOK (leaf boxes, iron bands) is just art — it could equally come from a .blend.
##   - The BEHAVIOUR lives here in Godot: two hinge pivots (Node3D) the leaves swing around,
##     a Blocker (StaticBody3D) that stops the player while closed, and an InteractZone (Area3D)
##     that lets the player press the `interact` action (E) to open/close.
##
## Why hinges as separate Node3Ds: a door swings around its OUTER edge, not its centre. So each
## leaf is a child offset INWARD from a hinge node placed at the jamb; rotating the hinge swings
## the leaf correctly. (A mesh rotated around its own centre would pivot through the wall.)

@export var open_degrees := 95.0     ## How far each leaf swings open.
@export var open_time := 0.7         ## Seconds for the swing.

@onready var _hinge_l: Node3D = $HingeL
@onready var _hinge_r: Node3D = $HingeR
@onready var _blocker: CollisionShape3D = $Blocker/Shape
@onready var _zone: Area3D = $InteractZone

var _open := false
var _player_near := false

func _ready() -> void:
	_zone.body_entered.connect(_on_enter)
	_zone.body_exited.connect(_on_exit)

func _on_enter(body: Node3D) -> void:
	if body is Player:
		_player_near = true

func _on_exit(body: Node3D) -> void:
	if body is Player:
		_player_near = false

func _unhandled_input(event: InputEvent) -> void:
	# Only react when the player is standing in the doorway's interact zone.
	if _player_near and event.is_action_pressed("interact"):
		toggle()

## Open if closed, close if open. Public so a cutscene/lever could call it too.
func toggle() -> void:
	_open = not _open
	# Stop blocking the moment it starts opening; block again as soon as we ask it to close.
	_blocker.set_deferred("disabled", _open)
	var target_l := deg_to_rad(open_degrees) if _open else 0.0
	var target_r := deg_to_rad(-open_degrees) if _open else 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hinge_l, "rotation:y", target_l, open_time)
	tw.tween_property(_hinge_r, "rotation:y", target_r, open_time)

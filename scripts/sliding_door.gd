class_name SlidingDoor
extends Node3D
## A POCKET DOOR for a Floorplan opening. The bake stands it on the floor at the opening's
## centre, local X along the wall and Z through it, and tells it its width and which way the
## wall run has room for the leaf (`width_m`, `slide_sign`); opening slides the leaf along X into
## the wall band, where the wall mass beside the opening hides it (the cut is only as wide as
## the door).
##
## The behaviour is scripts/door.gd's, with the docs' node for a tween-moved solid: the leaf is
## an AnimatableBody3D with sync_to_physics, so the player is pushed by it rather than through
## it, and there is no blocker to toggle. Two modes, per the legend row that placed it:
##   AUTO      a room door — opens when the player steps into its zone, closes `close_delay`
##             after they leave;
##   INTERACT  a flat's entrance — the interact action (E) toggles it, and it stays as left.
## The zone STRADDLES the door (door.tscn's lesson: a zone on one side is a door that opens
## from one side). `state_changed` is what the room mask (scripts/room_visibility.gd) listens
## to; `is_open` is what it reads.

enum Mode { AUTO, INTERACT }

@export var mode: Mode = Mode.AUTO
## The opening's width; the visual is scaled from `native_width` and the shapes sized to it.
@export var width_m := 1.0
@export var native_width := 1.0
## +1 slides toward local +X, -1 toward -X (the baker picks the longer wall remainder).
@export var slide_sign := 1
@export var open_time := 0.35
@export var close_delay := 0.6
## The leaf's thickness through the wall and the height it blocks.
@export var leaf_depth := 0.1
@export var leaf_height := 2.16

signal state_changed(open: bool)

var is_open := false
var _near := 0
var _tween: Tween

@onready var _leaf: AnimatableBody3D = $Leaf
@onready var _zone: Area3D = $Zone


func _ready() -> void:
	var model := _leaf.get_node_or_null("Model") as Node3D
	if model != null and native_width > 0.0:
		model.scale.x = width_m / native_width
	var shape := _leaf.get_node_or_null("Shape") as CollisionShape3D
	if shape != null:
		var box := BoxShape3D.new()
		box.size = Vector3(width_m, leaf_height, leaf_depth)
		shape.shape = box
		shape.position = Vector3(0.0, leaf_height * 0.5, 0.0)
	var zone_shape := _zone.get_node_or_null("Shape") as CollisionShape3D
	if zone_shape != null:
		var zb := BoxShape3D.new()
		zb.size = Vector3(width_m + 1.0, leaf_height + 0.2, 3.0)   # 1.5 m either side of the wall
		zone_shape.shape = zb
		zone_shape.position = Vector3(0.0, zb.size.y * 0.5, 0.0)
	_zone.body_entered.connect(_on_enter)
	_zone.body_exited.connect(_on_exit)


func _on_enter(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_near += 1
	if mode == Mode.AUTO and not is_open:
		open()


func _on_exit(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_near = maxi(_near - 1, 0)
	if mode == Mode.AUTO and _near == 0:
		get_tree().create_timer(close_delay).timeout.connect(func() -> void:
			if _near == 0 and is_open and mode == Mode.AUTO:
				close())


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.INTERACT and _near > 0 and event.is_action_pressed("interact"):
		toggle()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	_set_open(true)


func close() -> void:
	_set_open(false)


func _set_open(open: bool) -> void:
	if is_open == open:
		return
	is_open = open
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_leaf, "position:x", float(slide_sign) * width_m if open else 0.0, open_time)
	state_changed.emit(open)

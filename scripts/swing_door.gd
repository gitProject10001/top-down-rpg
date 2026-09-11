class_name SwingDoor
extends Node3D
## A HINGED DOOR for a Floorplan opening — one leaf, or two for a gate. The bake stands it on
## the floor at the opening's centre, local X along the wall and Z through it, and tells it its
## width and which jamb has the longer wall beside it (`width_m`, `slide_sign`): the hinge goes
## on that jamb, so the open leaf lies along the wall rather than across a corner. Which side of
## the wall it swings INTO is `swing_sign` (+1 = local +Z), set by whoever placed it — the
## dungeon harness swings every door into its chamber, away from the corridor.
##
## THE LEAF IS THE BODY AND THE HINGE. Each `Leaf*` child is an AnimatableBody3D standing AT the
## jamb with its mesh and shape offset inward, and opening turns the body itself: an
## AnimatableBody3D with sync_to_physics moves its collision only on its OWN transform change
## (measured: a leaf under a rotating parent kept blocking the doorway with the door wide open).
## The player is pushed by the leaf, never walked through, and there is no blocker to toggle.
## INTERACT (the interact action, E, toggles it; it stays as left) is the dungeon's mode; AUTO
## (opens on approach) is kept for parity with the sliding door. The zone STRADDLES the door
## (door.tscn's lesson). `state_changed` fires as the swing starts — the room mask
## (scripts/room_visibility.gd) re-evaluates on it and reads `is_open`.

enum Mode { AUTO, INTERACT }

@export var mode: Mode = Mode.INTERACT
## The opening's width; the leaf (or each of two) is scaled from `native_width`.
@export var width_m := 1.0
@export var native_width := 1.0
## Which jamb carries the hinge: +1 = the hinge at local +X (the baker's "longer remainder").
@export var slide_sign := 1
## Which side of the wall the leaf swings into: +1 = local +Z, -1 = local -Z.
@export var swing_sign := 1
@export var open_degrees := 95.0
@export var open_time := 0.7
@export var close_delay := 0.8
@export var leaf_depth := 0.08
@export var leaf_height := 2.3

signal state_changed(open: bool)

var is_open := false
var _near := 0
var _tween: Tween
var _leaves: Array[Node3D] = []

@onready var _zone: Area3D = $Zone


func _ready() -> void:
	for c in get_children():
		if c is Node3D and String(c.name).begins_with("Leaf"):
			_leaves.append(c)
	var double := _leaves.size() > 1
	var leaf_w := width_m * 0.5 if double else width_m
	for leaf in _leaves:
		var side := signf(leaf.position.x) if double else float(slide_sign)
		if side == 0.0:
			side = 1.0
		leaf.position.x = side * width_m * 0.5          # the body stands at the jamb: the hinge
		var model := leaf.get_node_or_null("Model") as Node3D
		if model != null:
			model.position.x = -side * leaf_w * 0.5
			if native_width > 0.0:
				model.scale.x = (leaf_w / (native_width * 0.5)) if double else (leaf_w / native_width)
		var shape := leaf.get_node_or_null("Shape") as CollisionShape3D
		if shape != null:
			var box := BoxShape3D.new()
			box.size = Vector3(leaf_w, leaf_height, leaf_depth)
			shape.shape = box
			shape.position = Vector3(-side * leaf_w * 0.5, leaf_height * 0.5, 0.0)
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
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for leaf in _leaves:
		# A leaf hinged at +X with its plank toward -X, turned by +angle, swings toward +Z.
		var target := signf(leaf.position.x) * float(swing_sign) * deg_to_rad(open_degrees) if open else 0.0
		_tween.tween_property(leaf, "rotation:y", target, open_time)
	state_changed.emit(open)

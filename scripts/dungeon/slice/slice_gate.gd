class_name SliceGate
extends StaticBody3D
## A barred gate the slice puts wherever it needs one — across a vault, in front of a reward.
##
## NOT A DungeonDoor, and that is a hard requirement rather than a style preference. Two suites
## describe DungeonDoor: one asserts the number of them equals the layout's edge count exactly, so
## an extra one is a failure with a confusing message. And DungeonRoom.shut() is called on every
## door it owns whenever the room activates, so a gate the player opened with a lever would slam
## again the next time a fight started in that room.
##
## This one answers to nothing but open().

const SIZE := Vector3(2.6, 2.9, 0.3)
const BAR_TINT := Color(0.36, 0.33, 0.28)

var is_open := false

var _bars: Node3D
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	_shape.shape = box
	_shape.position.y = SIZE.y * 0.5
	add_child(_shape)

	_bars = Node3D.new()
	add_child(_bars)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BAR_TINT
	mat.metallic = 0.6
	mat.roughness = 0.5
	# Five uprights and a lintel — enough to read as a portcullis, and it lets the player see the
	# reward through it, which is the entire reason a gate beats a wall here.
	for i in 5:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, SIZE.y, 0.14)
		bm.material = mat
		bar.mesh = bm
		bar.position = Vector3(-SIZE.x * 0.5 + 0.3 + i * (SIZE.x - 0.6) / 4.0, SIZE.y * 0.5, 0)
		bar.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_bars.add_child(bar)
	var lintel := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(SIZE.x, 0.22, 0.22)
	lm.material = mat
	lintel.mesh = lm
	lintel.position.y = SIZE.y - 0.11
	lintel.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_bars.add_child(lintel)


## Sink into the floor. The bars move; the body's own origin does not, so nothing that positioned
## this gate has to know it opened.
func open() -> void:
	if is_open:
		return
	is_open = true
	_shape.set_deferred("disabled", true)
	var t := create_tween()
	t.set_ease(Tween.EASE_IN)
	t.tween_property(_bars, "position:y", -SIZE.y - 0.2, 0.7)


func shut() -> void:
	if not is_open:
		return
	is_open = false
	_shape.set_deferred("disabled", false)
	var t := create_tween()
	t.tween_property(_bars, "position:y", 0.0, 0.4)

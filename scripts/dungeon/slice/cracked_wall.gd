class_name CrackedWall
extends StaticBody3D
## A wall that is not quite a wall. The Shatter Hammer opens it; nothing else will.
##
## Built in code like DungeonDoor's greybox, and following DungeonKey's discipline throughout —
## group lookups and get_node_or_null only, never an autoload by name — because everything in this
## folder has to survive being instantiated by a headless suite with no autoloads registered.
##
## THE CRACK HAS TO BE VISIBLE WITHOUT ART. Under a fixed ~53 degree camera a flat inset panel a
## few centimetres proud of the face reads as a fracture, because it catches a different amount of
## the room's torchlight than the wall around it. That is the whole trick, and it is why the panel
## is offset forward rather than recessed: a recess is in shadow and reads as nothing at all.

const SIZE := Vector3(3.4, 2.8, 0.45)
const TINT := Color(0.30, 0.28, 0.33)
const CRACK_TINT := Color(0.13, 0.12, 0.16)

## Made visible and solid when the wall comes down — the vault behind it.
@export var reveal_path: NodePath

var _broken := false


func _ready() -> void:
	add_to_group("cracked_wall")
	collision_layer = 1                       # every body in a dungeon is on layer 1; the suite checks
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y * 0.5
	add_child(shape)

	# The slab. Top sits at 2.8 m, comfortably under the 3.35 m above which anything standing in
	# open floor has to prove it is not between the player and the camera.
	add_child(_panel(SIZE, Vector3(0, SIZE.y * 0.5, 0), TINT))
	# The fracture: a narrow panel proud of the face, plus two shorter ones splaying off it.
	add_child(_panel(Vector3(0.22, 2.1, 0.06), Vector3(0.1, 1.35, SIZE.z * 0.5), CRACK_TINT))
	add_child(_panel(Vector3(0.16, 0.9, 0.06), Vector3(-0.55, 1.9, SIZE.z * 0.5), CRACK_TINT))
	add_child(_panel(Vector3(0.16, 0.7, 0.06), Vector3(0.62, 0.75, SIZE.z * 0.5), CRACK_TINT))


func _panel(size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.95
	box.material = mat
	mi.mesh = box
	mi.position = at
	# RoomGI grows a room's probe to contain every VisualInstance3D under it, and its bake can force
	# a hidden mesh visible again. Nothing built here has any business in the lighting solution.
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


## Called by the Shatter Hammer. Bursts, reveals whatever was behind, and goes.
func shatter() -> void:
	if _broken:
		return
	_broken = true
	remove_from_group("cracked_wall")          # a second slam in the same swing must not re-fire

	var target := get_node_or_null(reveal_path)
	if target:
		if target.has_method("reveal"):
			target.reveal()
		else:
			(target as Node3D).visible = true

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.combat_impact.emit(0.45)
	var run := get_node_or_null("/root/Run")
	if run and run.has_method("note_secret"):
		run.note_secret()

	# Collapse rather than vanish: drop it into the floor and fade it, so the eye follows the wall
	# down and finds the hole where it used to be.
	var shape := get_node_or_null("CollisionShape3D")
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "position:y", position.y - SIZE.y, 0.45)
	t.tween_property(self, "scale", Vector3(1.0, 0.6, 1.0), 0.45)
	t.chain().tween_callback(queue_free)

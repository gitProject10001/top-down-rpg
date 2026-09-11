@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name DungeonDoor
extends Node3D
## A dungeon gate in a doorway: a stone slab that sinks into the floor when open and rises shut
## during combat. SYSTEM-driven only (no interact zone) — DungeonRoom calls open()/shut().
## Mirrors door.gd's idiom: tween the visual, set_deferred the Blocker's shape.
##
## Art pass: add a "Visual" child in scenes/dungeon/kit/dungeon_door.tscn (a .blend gate mesh);
## the greybox slab is only built when no Visual node exists.

const SLAB := Vector3(2.0, 2.2, 0.3)
const LOCKED_TINT := Color(0.75, 0.55, 0.18)

## Non-empty while this gate needs a key. A LOCKED gate ignores open() — the room it belongs to
## still clears normally, it just cannot let you through until you carry the right key.
var locked_by := ""

var _visual: Node3D
var _blocker_shape: CollisionShape3D
var _open := true
var _want_open := true                        ## what the ROOM last asked for, lock aside


func _ready() -> void:
	_visual = get_node_or_null("Visual")
	if _visual == null:
		_visual = MeshInstance3D.new()
		_visual.name = "Visual"
		var box := BoxMesh.new()
		box.size = SLAB
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.32, 0.3, 0.36)
		box.material = mat
		(_visual as MeshInstance3D).mesh = box
		add_child(_visual)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	_blocker_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# NOT WALL HEIGHT, though it looked like it while the wall was 3 m. The blocker only has to fill
	# the CLEAR OPENING — every doorway piece carries solid collider in the spandrel above its
	# lintel, so raising this to the full wall would just bury geometry inside masonry.
	var blocker_h := SLAB.y + 0.8
	bs.size = Vector3(SLAB.x, blocker_h, SLAB.z)
	_blocker_shape.shape = bs
	_blocker_shape.position.y = blocker_h * 0.5
	blocker.add_child(_blocker_shape)
	add_child(blocker)
	# Doors start open (raised rooms shut them) — UNLESS lock() already ran. The generator builds
	# in-tree so lock() always lands after this line; the Forge preview builds the whole dungeon
	# OFF-tree and adds it afterwards, so a locked gate must survive _ready arriving second.
	_apply(locked_by == "" and _want_open, false)
	if locked_by != "":
		_tint(LOCKED_TINT)                    # lock() tinted a Visual that did not exist yet


func open() -> void:
	_want_open = true
	if locked_by == "":
		_apply(true, true)


func shut() -> void:
	_want_open = false
	_apply(false, true)


## Bar this gate until `key_id` is carried. Called once at build time, so it is not animated.
func lock(key_id: String) -> void:
	locked_by = key_id
	_want_open = false
	_apply(false, false)
	_tint(LOCKED_TINT)


## The key turned. Opens straight away unless the room it belongs to is mid-fight, in which case
## the room's own clear will open it.
func unlock(key_id: String) -> void:
	if locked_by == "" or locked_by != key_id:
		return
	locked_by = ""
	_tint(Color(0.32, 0.3, 0.36))
	if _want_open:
		_apply(true, true)


## Recolour the greybox slab so a barred gate reads as barred. A themed Visual is left alone —
## art decides its own locked look.
func _tint(c: Color) -> void:
	var mi := _visual as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var mat = mi.mesh.material if mi.mesh is PrimitiveMesh else null
	if mat is StandardMaterial3D:
		mat.albedo_color = c
		mat.emission_enabled = c != Color(0.32, 0.3, 0.36)
		mat.emission = c
		mat.emission_energy_multiplier = 0.6


func _apply(open_state: bool, animate: bool) -> void:
	if _blocker_shape == null:
		return                                # not in the tree yet; _ready re-applies (line 53)
	if _open == open_state and animate:
		return
	_open = open_state
	_blocker_shape.set_deferred("disabled", open_state)
	# closed: slab fills the doorway (centre 1.1). open: sunk fully below the floor.
	var target_y := -SLAB.y * 0.5 - 0.35 if open_state else SLAB.y * 0.5
	if animate:
		var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(_visual, "position:y", target_y, 0.35)
	else:
		_visual.position.y = target_y

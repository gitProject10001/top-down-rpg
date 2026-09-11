extends Node
## Zone streaming + fade transitions (autoload "World").
##
## The persistent things (Player, CameraRig, WorldEnvironment, UI) live in main.tscn. The current
## ZONE is a separate scene tagged with group "zone". go_to() fades to black, frees the old zone,
## instances the new one, drops the player on a named spawn Marker, snaps the camera, and fades in.
##
## Zones reference each other by PATH string (loaded at runtime), not by ExtResource, to avoid a
## circular scene dependency (hub -> crypt -> hub -> ...).

var _busy := false
var _fade: ColorRect

func _ready() -> void:
	# Build a full-screen black fade overlay we own, so no scene needs to provide one.
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.anchor_right = 1.0
	_fade.anchor_bottom = 1.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)

func go_to(zone_scene: PackedScene, spawn_name := "Spawn") -> void:
	if _busy or zone_scene == null:
		return
	_busy = true
	await _fade_to(1.0, 0.3)

	var old := get_tree().get_first_node_in_group("zone")
	if is_instance_valid(old):
		old.queue_free()
	await get_tree().process_frame

	var zone := zone_scene.instantiate()
	if not zone.is_in_group("zone"):
		zone.add_to_group("zone")
	get_tree().current_scene.add_child(zone)
	await get_tree().physics_frame

	var player := get_tree().get_first_node_in_group("player")
	var spawn := zone.find_child(spawn_name, true, false)
	if player and is_instance_valid(spawn):
		player.global_position = (spawn as Node3D).global_position
		if "velocity" in player:
			player.set("velocity", Vector3.ZERO)
		var rig := get_tree().get_first_node_in_group("camera_rig")
		if rig:                                    # snap the camera so it doesn't slide across the map
			(rig as Node3D).global_position = player.global_position
		EventBus.zone_changed.emit(zone.name)

	await _fade_to(0.0, 0.3)
	_busy = false

func _fade_to(target_alpha: float, dur: float) -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", target_alpha, dur)
	await t.finished


# --- SEAMLESS ENTRY ---------------------------------------------------------------------------
#
# go_to() above is a HARD CUT: fade, free, teleport the player to a spawn, snap the camera. Right
# for the magic crypt portal, wrong for walking through a door.
#
# Seamless entry inverts the whole idea: THE PLAYER NEVER MOVES. The new zone is instantiated and
# positioned so its `Anchor` lands exactly on the doorway the player just walked through, so they
# simply keep walking and the world was swapped around them. No fade, no teleport, and nothing for
# the camera to snap to — because nothing moved.
#
# Both zones stay alive while the player is in the connecting corridor (so looking back still shows
# a world), and the old one is freed only once they have committed to the new side.

var _incoming: Node = null      ## the zone just entered (now the current "zone")
var _outgoing: Node = null      ## the previous zone, still alive until commit
var _prepared := {}             ## path -> true once a threaded load has been requested


## Begin loading a zone on a background thread. Called by Threshold when the player gets NEAR the
## door, so the scene is already in memory by the time they cross it — this is what removes the
## frame hitch that would otherwise give the swap away.
func prepare_zone(path: String) -> void:
	if path == "" or _prepared.has(path):
		return
	_prepared[path] = true
	ResourceLoader.load_threaded_request(path)


## True once a prepare_zone() request has finished — the Threshold can check this to know the
## crossing will be hitch-free.
func is_prepared(path: String) -> bool:
	if not _prepared.has(path):
		return false
	return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED


## Swap in `path` with its `anchor_name` node aligned onto `seam` (the threshold's world transform).
## Returns true if the zone was brought in. The player is never touched.
func enter_seamless(path: String, anchor_name: String, seam: Transform3D) -> bool:
	if _busy or path == "" or _incoming != null:
		return false
	_busy = true

	var packed: PackedScene = null
	if _prepared.has(path):
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
		_prepared.erase(path)
	if packed == null:
		packed = load(path) as PackedScene     # fallback: player outran the preload
	if packed == null:
		_busy = false
		return false

	# Capture the current zone BEFORE adding the new one — the new zone's root is already in the
	# "zone" group (it is saved that way), so afterwards the lookup could return either.
	var old := get_tree().get_first_node_in_group("zone")

	var zone := packed.instantiate() as Node3D
	get_tree().current_scene.add_child(zone)
	await get_tree().process_frame             # let child global transforms resolve

	var anchor := zone.find_child(anchor_name, true, false) as Node3D
	if anchor == null:
		push_warning("Threshold: no anchor '%s' in %s" % [anchor_name, path])
		zone.queue_free()
		_busy = false
		return false

	# THE ALIGNMENT. `local` is the anchor expressed relative to the zone root, so placing the root
	# at `seam * local^-1` puts the anchor exactly ON the seam:
	#     anchor_global = zone_global * local = (seam * local^-1) * local = seam
	var local := zone.global_transform.affine_inverse() * anchor.global_transform
	zone.global_transform = _yaw_only(seam) * local.affine_inverse()

	if is_instance_valid(old) and old != zone:
		old.remove_from_group("zone")           # keep exactly one node in "zone" for existing callers
		old.add_to_group("zone_outgoing")
		_outgoing = old
	if not zone.is_in_group("zone"):
		zone.add_to_group("zone")
	_incoming = zone

	EventBus.zone_changed.emit(zone.name)
	_busy = false
	return true


## The player committed to the new side — drop the zone they came from.
func commit_zone() -> void:
	if is_instance_valid(_outgoing):
		_outgoing.queue_free()
	_outgoing = null
	_incoming = null


## The player stepped back out before committing — drop the zone we brought in and restore the old
## one as current, so walking in again starts from a clean slate.
func cancel_incoming() -> void:
	if is_instance_valid(_incoming):
		_incoming.queue_free()
	if is_instance_valid(_outgoing):
		_outgoing.remove_from_group("zone_outgoing")
		_outgoing.add_to_group("zone")
	_incoming = null
	_outgoing = null


## Strip pitch/roll from a seam transform: the world must never end up tilted, but the full Y
## translation is kept so STAIRS gain height naturally and vertical continuity comes for free.
static func _yaw_only(t: Transform3D) -> Transform3D:
	var fwd := -t.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), t.origin)

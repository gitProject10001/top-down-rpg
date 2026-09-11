class_name Threshold
extends Area3D
## A seam between two zones — put one in a doorway, corridor or stairwell.
##
## Unlike Portal (which hard-cuts via World.go_to), crossing a Threshold NEVER MOVES THE PLAYER.
## It asks World to bring in the target zone positioned so that zone's `Anchor` lands exactly here,
## so the player just keeps walking and the world was swapped around them. See world_manager.gd.
##
## PLACEMENT CONVENTION (this is what makes the return trip work automatically):
##   - `Threshold` sits at the seam with its -Z pointing OUT of the zone it belongs to.
##   - `Anchor` (a Marker3D) sits at the SAME spot with its -Z pointing INTO its own zone,
##     i.e. rotated 180° from the Threshold.
## Both zones own a mirrored half of the connecting corridor, so the halves line up into one
## continuous passage. The swap happens inside that corridor, where neither world is visible.

@export_file("*.tscn") var target_zone_path: String
@export var target_anchor := "Anchor"      ## node in the TARGET zone that lands on this seam
@export var prepare_radius := 14.0         ## start loading in the background at this distance
@export var commit_distance := 6.0         ## how far past the seam before the old zone is freed

enum S { IDLE, CROSSED }

var _state := S.IDLE
var _armed := false                        ## player has been properly inside this zone
var _player: Node3D
var _world: Node


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# get_node_or_null (not `World.`) so this also compiles in the autoload-less headless tests,
	# same reason portal.gd does it.
	_world = get_node_or_null("/root/World")


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return

	# Signed distance along the seam normal: NEGATIVE = still in this threshold's own zone,
	# POSITIVE = through to the other side.
	var side := (_player.global_position - global_position).dot(-global_transform.basis.z)

	match _state:
		S.IDLE:
			# Only arm once the player is genuinely inside our own zone. Without this, the target
			# zone's own Threshold — which materialises at this very spot — would fire instantly
			# and bounce the player straight back.
			if side < -1.0:
				_armed = true
			if _armed and _world and side < prepare_radius:
				_world.prepare_zone(target_zone_path)
		S.CROSSED:
			if side > commit_distance:
				_world.commit_zone()           # frees our own zone; queue_free is deferred, safe
				_state = S.IDLE
				_armed = false
			elif side < -1.0:
				_world.cancel_incoming()       # stepped back out before committing
				_state = S.IDLE


func _on_body_entered(body: Node3D) -> void:
	if _state != S.IDLE or not _armed or target_zone_path == "":
		return
	if not body.is_in_group("player") or _world == null:
		return
	_armed = false
	_state = S.CROSSED
	if not await _world.enter_seamless(target_zone_path, target_anchor, global_transform):
		_state = S.IDLE                        # bring-in failed; leave everything as it was

extends Area3D
## While the player is inside this volume, reframe the camera — pull it back (zoom) and/or swing
## it to a new yaw (e.g. the warehouse rotates the view anticlockwise) — and restore the default
## framing on exit. Finds the CameraRig via its group.

@export var zoom := 2.0
@export var yaw_degrees := 0.0    ## rig yaw while inside; positive = anticlockwise from above
@export var pitch_degrees := 0.0  ## camera angle above horizontal; 0 = keep the default (~53)
## Slide the centre of frame off the player, in WORLD metres. For a vista at the edge of the map,
## where centring on the player would spend half the picture on empty sky.
@export var frame_shift := Vector3.ZERO
## Sun shadow range while inside, in metres; 0 = leave it alone. A wide vista pushes the whole map
## past the 40 m default, and a map with no cast shadows at all reads as flat paper.
@export var shadow_distance := 0.0
## Depth of field while inside, as (near, far, amount) in ABSOLUTE metres. ZERO leaves the authored
## default alone, and that is what every combat zone must use: at gameplay zoom the player sits
## 15.6 m out and the fight happens between 8 and 24 m, so a diorama focal band would blur the
## enemy you are aiming at. A vista is the one framing where the miniature read costs nothing,
## because nothing is being fought.
@export var dof := Vector3.ZERO
## Which claim wins when two zones overlap. Higher beats lower; equal priorities break by RECENCY,
## which is what the rig did for every zone before this existed, so 0 changes nothing.
##
## A vista nested inside a gameplay zone needs 10. The stairs are the case: StairsVistaZone sits
## inside ArenaCameraZone and is entered first, so on recency alone the arena would take the frame
## back two metres into a twenty-five metre descent and keep it.
##
## NOT `priority`. Area3D already has one — it orders overlapping audio-bus/gravity overrides — and
## shadowing it is a hard parse error, which the editor reports on the SCRIPT rather than on the
## scene that instances it.
@export var frame_priority := 0

func _ready() -> void:
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func _on_enter(body: Node3D) -> void:
	if body is Player:
		var rig := get_tree().get_first_node_in_group("camera_rig")
		if rig and rig.has_method("claim_frame"):
			rig.claim_frame(self, zoom, deg_to_rad(yaw_degrees),
				deg_to_rad(pitch_degrees) if pitch_degrees > 0.0 else -1.0, frame_shift,
				shadow_distance, dof, frame_priority)

func _on_exit(body: Node3D) -> void:
	if body is Player:
		var rig := get_tree().get_first_node_in_group("camera_rig")
		if rig and rig.has_method("release_frame"):
			rig.release_frame(self)   # drops our claim wherever it sits; a no-op if we hold none

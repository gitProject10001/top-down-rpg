class_name CameraRig
extends Node3D
## Decoupled follow camera + combat shake + zoom.
##
## FOLLOW: lerp the rig toward the player. SHAKE: driven by EventBus.combat_impact. ZOOM: scales the
## child Camera3D's authored offset along the origin→camera line — because that line's DIRECTION to
## the player is unchanged, the fixed camera angle keeps the player centred while pulling further back
## (wider view). A CameraZone Area3D calls set_zoom() to widen the view in big spaces like the arena.

@export var target_path: NodePath
@export var follow_speed := 6.0
@export var zoom_speed := 4.0
@export var yaw_speed := 3.0            ## how fast the rig swings to a new yaw
@export var peek_distance := 3.5        ## how far the RIGHT STICK can nudge the view (metres)
@export var peek_speed := 7.0           ## how fast the peek eases in and back to centre

# --- BASE FRAMING: THE SHOT ITSELF, AND ZERO ALWAYS MEANS "WHATEVER THE CAMERA3D IS AUTHORED AT".
#
# These four numbers used to be readable only as a Transform3D on the Camera3D child of
# camera_rig.tscn — pitch buried in a rotation basis, distance as the length of an offset nobody
# computes by eye. They are now dials, but they are OVERRIDES, not the source of truth: an unset
# 0 leaves scenes/camera_rig.tscn in charge, so every scene that has ever instanced this rig is
# framed by exactly the same numbers as before and only a scene that asks gets a different shot.
#
# Zero as the sentinel rather than -1 because none of the four has a meaningful zero — a camera
# 0 m from the player at 0 degrees with a 0 degree FOV is not a shot anyone wants — and because
# it is the convention the rest of this file already runs on (set_shadow_distance, set_dof).
#
# Read ONCE, in _ready. Changing them on a running game does nothing; they are authoring dials.
@export_group("Framing", "framing_")
## Viewing angle above horizontal, in degrees. 0 = the authored ~53. This is the DEFAULT the rig
## returns to; a zone claim or the orbit band can still move it while they own the frame.
@export_range(0.0, 89.0, 0.5) var framing_pitch_deg := 0.0
## Distance from the player along that angle, in metres. 0 = the authored 15.625. Zoom multiplies
## this, so the whole zoom range moves with it.
@export var framing_distance := 0.0
## Camera FOV in degrees. 0 = the Camera3D's own 42. Narrow is what keeps the look flat and
## diorama-like; widening it is a different game's camera, not a stronger version of this one.
@export_range(0.0, 120.0, 0.5) var framing_fov := 0.0
## Depth-of-field far plane in metres — where the backdrop starts going soft. 0 = the authored 38.
## The blur AMOUNT is deliberately not here: 0 is a real value for it (no blur), so it could not
## carry the same sentinel, and it lives on the CameraAttributes resource where a strength belongs.
@export var framing_dof_far := 0.0
## ISOMETRIC, as a DIAL rather than a switch: 0 is the game's lens, 1 is a true orthogonal
## camera, and everything between is a longer lens standing further back.
##
## AND THAT IS WHAT IT ACTUALLY IS. An orthogonal projection is the limit of a perspective one
## as the field of view goes to nothing and the camera retreats to keep the same slice of world
## in frame — a very long lens, very far away. So this dial does not blend between two
## projections (there is no such thing); it narrows the fov and dollies out along that curve,
## and only at exactly 1 does it hand over to a real orthogonal lens, by which point the two are
## already all but identical. The middle of the dial is the useful part: the telephoto
## compression that flattens a room without giving up depth of field entirely.
##
## THE ANGLE IS ALREADY THE GAME'S. This camera is authored at ~53 degrees looking down and never
## leaves a top-down band, which is the isometric READ; what perspective still adds is convergence
## — a room's far wall is smaller than its near one, and two identical pillars at opposite ends of
## a hall are different sizes on screen. This dial takes that away and nothing else: pitch, yaw,
## zoom, peek, orbit, lock, shake and the zone framing all keep working exactly as they do.
##
## WHAT MOVES WITH IT. The standoff grows, so two things measured FROM THE CAMERA have to grow
## with it or they quietly stop describing the same scene: the depth-of-field planes, and the
## sun's shadow range. Both are pushed out by exactly the extra metres the dolly added, so a zone
## that asked for "soft past 38 m" still means 38 m past the player. Depth of field survives the
## middle of the dial and dies at 1, because Godot's DOF is a perspective effect — which is one
## more reason the interesting setting is not the end of it.
@export_range(0.0, 1.0, 0.01) var framing_isometric := 0.0
## The metres of world across the viewport height at rest. 0 = whatever the perspective lens is
## showing at the framing distance, so moving the dial does not also change what is in frame.
@export var framing_iso_size := 0.0
## How many times the framing distance the camera stands at the far end of the dial — which is
## the same thing as how long the lens gets, since the two are locked together. 8 puts a 42
## degree lens at about 5, which is already flat; higher is flatter and further from anything the
## streaming and the occlusion fade were tuned for.
@export_range(1.5, 24.0, 0.5) var framing_iso_reach := 8.0
## HOW MUCH OF THE WORLD IS ON SCREEN, and therefore how small the player is. 1 is the shot the
## game is authored at; 2 shows twice as much in each direction and halves the player; 0.5 goes
## the other way. It reads the same in both projections and at every setting of the isometric
## dial, which is the whole reason it exists as its own number.
##
## IT IS A PULL-BACK, NOT A WIDER LENS, and that distinction is the point. It scales the framed
## slice and the camera distance BY THE SAME FACTOR, so the field of view comes out unchanged
## and the shot keeps whatever lens the isometric dial gave it — only further away. Widening the
## fov instead would show more too, and would undo the flattening the dial is there to produce.
## Under an orthogonal lens there is no fov to keep, so the same factor simply scales `size`, and
## the two ends of the dial agree by construction rather than by tuning.
##
## THE OTHER TWO DIALS ARE NOT THIS, which is worth saying because all three change what is on
## screen. `framing_distance` moves the camera and takes the framing with it (same shot, more
## standoff). `framing_iso_size` re-frames at a fixed distance, so in perspective it works by
## changing the fov. This one is the one to reach for when the question is "how much can I see".
@export_range(0.25, 6.0, 0.05) var framing_zoom := 1.0

@export_group("Orbit", "orbit_")
## RIGHT STICK: ONE STICK, TWO BEHAVIOURS, AND ONLY EVER ONE OF THEM AT A TIME.
##
## Off (the default, and what every shipped scene has always had) = PEEK: a limited
## screen-relative nudge of the framing that springs back when released. The angle never changes.
## On = ORBIT: the rig swings around the player, full 360 yaw with the pitch held in a top-down
## band. Turning it on takes the stick away from the peek, which eases back to centre; turning it
## off unwinds the orbit the same way, so it is safe to flip at runtime or from a zone script.
@export var orbit_enabled := false
## LOCK-ON acquisition range (metres from the player). The lock lets go at 1.4x this, so a
## fleeing fight releases the camera instead of pinning it to a dot on the horizon.
@export var lock_range := 20.0
@export var orbit_yaw_speed := 2.6              ## rad/s at full stick
@export var orbit_pitch_speed := 0.9            ## rad/s at full stick
## The pitch band, in degrees above horizontal. The 45 degree floor is the promise this camera
## makes: it can be tilted, it can never become a shoulder camera.
@export_range(15.0, 89.0, 0.5) var orbit_pitch_min_deg := 45.0
@export_range(15.0, 89.0, 0.5) var orbit_pitch_max_deg := 70.0
## RETURN TO FRAME: how fast the pitch eases back once the stick's vertical axis is released, in
## 1/s. 0 = it stays wherever it was left, a sticky orbit.
@export var orbit_pitch_return_speed := 2.0
## What it returns TO, in degrees. 0 = the angle the framing itself is authored at — the game's own
## shot — which is what makes letting go a REFRAME rather than a second preference to maintain.
@export_range(0.0, 89.0, 0.5) var orbit_pitch_rest_deg := 0.0
## Zoom rides the pitch across the band (flatter = slightly closer, steeper = slightly wider), as
## a MULTIPLIER on whatever zoom the framing already asked for.
@export var orbit_zoom_swing := 0.3

@onready var _cam: Camera3D = $Camera3D

var _target: Node3D
var _peek := Vector3.ZERO               ## current screen-relative camera nudge (right stick)
var _orbit_yaw := 0.0                   ## orbit's yaw OFFSET on top of the framing's yaw
var _orbit_pitch := 0.0                 ## orbit's pitch OFFSET, clamped so the SUM stays in band
var _frame_shift := Vector3.ZERO        ## current zone framing offset (world space)
var _frame_shift_target := Vector3.ZERO
var _shake_time := 0.0
var _shake_strength := 0.0
var _base_offset: Vector3
var _base_dist := 0.0
var _base_pitch := 0.0
var _zoom := 1.0
var _zoom_target := 1.0
var _yaw_target := 0.0
var _pitch := 0.0
var _pitch_target := 0.0
var _attrs: CameraAttributesPractical
var _base_dof := 0.0
var _sun: DirectionalLight3D
var _base_shadow := 0.0
var _base_dof_amount := 0.0
var _dof := Vector3.ZERO            ## current (near, far, amount), absolute metres
var _dof_target := Vector3.ZERO     ## what a zone asked for; ZERO = the authored default
var _iso_size := 0.0                ## what the lens frames at the subject, metres, at zoom 1
var _shadow_want := 0.0             ## the shadow range a zone asked for, before the dolly push
var _fog_env: Environment           ## the environment whose depth fog the dolly is pushing
var _fog_base := Vector2.ZERO       ## its authored (begin, end), before the push
var _fog_wrote := Vector2.ZERO      ## and what this rig last wrote there


## Set the dial from a zone script; the same property the inspector slider writes. 0 perspective,
## 1 orthogonal, anything between a longer lens further out.
func set_isometric(amount: float) -> void:
	framing_isometric = clampf(amount, 0.0, 1.0)


## How many times further back the camera stands for the dial's current setting.
##
## The quantity that actually moves is tan(fov / 2) — it is what the framed height divides by,
## and it is the one that reaches zero at orthogonal. Taking it down linearly to 1 / reach is
## what makes the slider feel even; the DISTANCE it implies is 1 over that, which is why the last
## tenth of the dial moves the camera so much further than the first.
func _lens_dolly() -> float:
	# AND AT THE END OF THE DIAL IT COMES STRAIGHT BACK. The standoff exists only to buy a narrow
	# enough lens to look parallel; an orthogonal camera IS parallel and does not care where it
	# stands. All the distance would still do at 1 is decide how much foreground is swept into the
	# shot — a hundred metres of trees and rooftops between the camera and the player that were
	# never in frame before, plus a hundred metres of raycast for the occluder fade to chew on.
	# So the last notch keeps the projection and gives the metres back, and the fog, the shadow
	# range and the focal planes go back to their authored numbers with it.
	if framing_isometric >= 1.0:
		return 1.0
	var reach := maxf(framing_iso_reach, 1.0)
	return 1.0 / lerpf(1.0, 1.0 / reach, clampf(framing_isometric, 0.0, 1.0))


func _ready() -> void:
	if target_path:
		_target = get_node_or_null(target_path)
	_base_offset = _cam.position
	_base_dist = _base_offset.length()
	_base_pitch = atan2(_base_offset.y, _base_offset.z)   # the authored ~53 deg viewing angle
	# The inspector overrides, applied BEFORE _pitch and _pitch_target are seeded off _base_pitch —
	# seeding first would open on the authored angle and then slide to the overridden one.
	if framing_distance > 0.0:
		_base_dist = framing_distance
	if framing_pitch_deg > 0.0:
		# Same clamp set_pitch enforces, so a dial and a zone claim cannot disagree about the limits.
		_base_pitch = clampf(deg_to_rad(framing_pitch_deg), 0.15, 1.45)
	if framing_fov > 0.0:
		_cam.fov = framing_fov
	# AFTER the distance and the fov are settled, because this is derived from both: the slice of
	# world the authored lens frames at the authored distance. Every setting of the dial keeps it,
	# which is what makes the dial a LENS change and not a zoom.
	if framing_iso_size > 0.0:
		_iso_size = framing_iso_size
	else:
		_iso_size = 2.0 * _base_dist * tan(deg_to_rad(_cam.fov) * 0.5)
	_pitch = _base_pitch
	_pitch_target = _base_pitch
	_attrs = _cam.attributes as CameraAttributesPractical
	if _attrs:
		_base_dof = _attrs.dof_blur_far_distance
		if framing_dof_far > 0.0:
			_base_dof = framing_dof_far
		_base_dof_amount = _attrs.dof_blur_amount
		_dof = Vector3(0.0, _base_dof, _base_dof_amount)
	_sun = get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	if _sun:
		_base_shadow = _sun.directional_shadow_max_distance
	EventBus.combat_impact.connect(_on_impact)
	# Both signals are argument-free and single-site (dialogue.gd:61 and :140), and _end() is the
	# only terminator. The handlers must not await: start() can emit `started` and `finished` inside
	# one call when the opening node id is missing.
	_dialogue = get_node_or_null("/root/Dialogue")
	if _dialogue != null:
		_dialogue.started.connect(_on_talk_started)
		_dialogue.finished.connect(_on_talk_finished)

func _on_impact(strength: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = maxf(_shake_time, 0.18)

## Target zoom multiplier (1 = default, >1 = further/wider). Lerped smoothly.
func set_zoom(target: float) -> void:
	_zoom_target = maxf(target, 0.5)

## Target rig yaw in RADIANS (positive = anticlockwise seen from above). The whole rig swings
## around the player while the fixed pitch/offset is preserved. Player movement input is mapped
## through this yaw (player.get_move_input), so WASD stays screen-relative during/after the turn.
func set_yaw(target: float) -> void:
	_yaw_target = target

# --- ZONE FRAMING: A LIST OF CLAIMS. HIGHEST PRIORITY WINS, TIES BROKEN BY RECENCY.
#
# It used to be a single `_frame_owner` slot, last claim wins, and releases that no longer owned the
# frame were ignored. That is simple and it was wrong in one specific way: releasing an INNER claim
# reset to DEFAULT framing instead of restoring the outer one. scenes/world/room.tscn:576 records
# the team hitting this and working around it by MOVING the three NPCs down to the arena floor —
# "leaving the inner zone releases to DEFAULT framing rather than restoring the vista, and the
# establishing shot would be lost for the rest of the visit". A conversation can start anywhere, so
# the push-in below cannot be worked around the same way. Hence a list.
#
# Four rules a naive stack gets wrong, each one measured rather than assumed:
#
#  * A NEW ZONE'S body_entered FIRES BEFORE THE OLD ZONE'S body_exited — not only for adjacent
#    zones but across a teleport between boxes that share no boundary, which is how the shot
#    scripts move the player. The owner being released is routinely NOT the newest entry, so
#    removal is BY IDENTITY from anywhere in the list. Never pop_back().
#  * scripts/dev/crypt_tuner.gd:339-342 releases EVERY DungeonRoom in the zone, most of which never
#    claimed anything, and then remove_child fires body_exited and releases the live one AGAIN.
#    Releasing a non-member must therefore be a silent no-op, and release must be idempotent.
#  * StairsVistaZone sits geometrically INSIDE ArenaCameraZone and is entered EARLIER, so "newest
#    claim wins" would hand the frame to the arena for the whole descent. Priority decides, not
#    recency.
#  * A typed Array[Node] would be the obvious choice and is the wrong one: erase() and find() raise
#    on an entry whose owner has been freed, so the list would jam on a dead zone and never return
#    to default. This one is UNTYPED and is purged by backwards index with is_instance_valid().
#
# THE COST OF THE CHANGE, stated plainly: the old single slot was self-repairing, because every
# claim overwrote it. A list is not. An owner that never releases leaks an entry, so `_purge()`
# runs every frame and no priority is high enough to be un-maskable.

const PRIORITY_ZONE := 0        ## ordinary gameplay CameraZones and DungeonRooms
const PRIORITY_INTERIOR := 5    ## InteriorView's doll's-house pull-in: beats a zone, loses to a vista
const PRIORITY_VISTA := 10      ## vistas, the stairs panoramic, and the conversation push-in

## Conversation framing. 0.7 puts the camera 10.94 m out and a 1.8 m figure at ~175 px of 1080 —
## 1.5x the default framing, and 40% of headroom over set_zoom's floor of 0.5.
const TALK_ZOOM := 0.7

var _claims: Array = []         ## UNTYPED, deliberately — see the fourth rule above
var _seq := 0
var _dialogue: Node = null

## Target camera pitch in RADIANS (angle above horizontal; the authored default is ~0.93 = 53
## deg). Lower values = flatter, more cinematic view. Distance to the player is preserved.
func set_pitch(target: float) -> void:
	_pitch_target = clampf(target, 0.15, 1.45)

## Slide what the camera is CENTRED on off the player, in world space. Zero (the default) keeps the
## player dead centre; a vista standing at the edge of the map needs the frame pushed out over the
## map instead, or half the picture is the sky the player has their back to.
func set_frame_shift(shift: Vector3) -> void:
	_frame_shift_target = shift

## Sun shadow range in metres; 0 restores the authored default. Lives here rather than on the zone
## because the FRAMING owns it: crossing straight from one zone into the next fires the old zone's
## exit after the new zone's enter, and a zone restoring its own value would undo the new one.
func set_shadow_distance(metres: float) -> void:
	# REMEMBERED, not just written: the per-frame lens block adds the dolly's standoff on top of
	# this, and it has to know what it is adding to.
	_shadow_want = maxf(metres, 0.0)
	if _sun:
		_sun.directional_shadow_max_distance = metres if metres > 0.0 else _base_shadow

## AND SO DOES THE FOG, which is the one that turns the whole screen black when it is missed.
##
## A crypt is lit by depth fog closing at 62 m — that IS "outside the room is nothing". Depth fog
## is measured from the camera, so the moment the lens dial pushed the rig past 62 m the level
## went past the far plane of the fog and rendered as an empty black frame. Nothing was broken;
## everything was simply behind the fog. The fix is the same one the shadow range and the
## depth-of-field planes get: the fog keeps meaning "62 m past the thing being looked at".
##
## IT RE-READS ITS OWN BASE, rather than snapshotting once. Two other systems write these
## properties — a zone entering, and DungeonEnv blacking the world out and restoring it — and a
## rig holding a stale snapshot would eventually paste an old crypt's fog onto a garden. So
## anything it finds that is not what it last wrote is taken as the new authored value, which
## makes an environment swap correct itself on the next frame with no coordination at all.
##
## AND THE DEPTH-MODE GUARD IS LOAD-BEARING, not a tidiness check. DungeonEnv SNAPSHOTS these two
## properties on the way in and plays them back on the way out; if the rig had already pushed the
## outdoor values, the snapshot would capture pushed numbers, the restore would hand them back,
## and this would then push them again — a crypt visit would leave the garden a hundred metres
## less foggy every time. It cannot happen, because the overworld fog is EXPONENTIAL and only a
## dungeon switches the mode to DEPTH: the rig writes nothing outside, so there is nothing pushed
## for the snapshot to catch. A future zone wanting depth fog AND a snapshot/restore around it
## would need to say so here.
func _push_fog(push: float) -> void:
	var node := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	var env: Environment = node.environment if node != null else null
	if env == null or not env.fog_enabled or env.fog_mode != Environment.FOG_MODE_DEPTH:
		return
	var here := Vector2(env.fog_depth_begin, env.fog_depth_end)
	if env != _fog_env or not here.is_equal_approx(_fog_wrote):
		_fog_env = env
		_fog_base = here
	_fog_wrote = _fog_base + Vector2(push, push)
	env.fog_depth_begin = _fog_wrote.x
	env.fog_depth_end = _fog_wrote.y


## Depth of field as (near, far, amount) in ABSOLUTE metres; ZERO restores the authored default.
##
## Absolute, not a multiplier, because a vista's frame_shift moves the centre of frame tens of
## metres off the player — TerraceVistaZone by 36 — so the focal band has to be measured to the
## thing being looked at, which is no longer where the player is standing.
func set_dof(dof: Vector3) -> void:
	_dof_target = dof

## Claim the framing. `owner` is UNTYPED so that handing in a freed object can never be a hard
## argument error — the tuner does exactly that. `priority` defaults to 0, so every existing caller
## keeps the old last-write-wins behaviour without changing a line.
func claim_frame(owner, zoom_amount: float, yaw: float, pitch := -1.0,
		shift := Vector3.ZERO, shadow_distance := 0.0, dof := Vector3.ZERO,
		priority := PRIORITY_ZONE) -> void:
	if owner == null:
		return
	_purge()
	_drop(owner)                # a live re-claim updates in place; never two entries per owner
	_seq += 1
	_claims.append({
		"owner": owner,
		"priority": priority,
		"seq": _seq,
		"zoom": zoom_amount,
		"yaw": yaw,
		# THE -1.0 SENTINEL IS RESOLVED HERE, ON THE WAY IN, and it has to be. camera_zone.gd sends
		# -1.0 whenever pitch_degrees is unset, and both other callers take it as the default.
		# set_pitch does NOT understand it — it clamps to [0.15, 1.45] — so a stored -1.0 replayed
		# when this claim later becomes the winner would give 8.6 degrees instead of the authored 53.
		"pitch": pitch if pitch > 0.0 else _base_pitch,
		"shift": shift,
		"shadow": shadow_distance,
		"dof": dof,
	})
	_apply_top()

## Drop this owner's claim from wherever it sits. A no-op if it holds none, and safe to call twice.
func release_frame(owner) -> void:
	_purge()
	_drop(owner)
	_apply_top()
	# DELIBERATELY outside the framing bookkeeping and past every early return: dungeon_room.gd
	# claims bounds in the same breath as the frame, and the tuner releases rooms that never owned
	# the frame but may still own the bounds.
	if _bounds_owner != null and _bounds_owner == owner:
		_bounds_owner = null

func _drop(owner) -> void:
	for i in range(_claims.size() - 1, -1, -1):
		if _claims[i]["owner"] == owner:
			_claims.remove_at(i)

## Drop entries whose owner can no longer be framing anything. Runs BEFORE any read of the list,
## because passing a freed object to anything Node-typed is a hard error rather than a false.
func _purge() -> void:
	for i in range(_claims.size() - 1, -1, -1):
		var o = _claims[i]["owner"]
		if o == null or not is_instance_valid(o):
			_claims.remove_at(i)
		elif o == _dialogue and not _dialogue.active:
			# The conversation's owner is an AUTOLOAD, so it is never freed and is_instance_valid
			# can never rescue a stranded claim. `active` is the only honest liveness test, and it
			# is what covers every way out of a conversation that is not `finished` — dying mid
			# sentence, a Sheet opening over it, a zone change.
			_claims.remove_at(i)
	if _bounds_owner != null and not is_instance_valid(_bounds_owner):
		_bounds_owner = null

func _top_claim() -> Dictionary:
	var top := {}
	for e: Dictionary in _claims:
		if top.is_empty() or e["priority"] > top["priority"] \
				or (e["priority"] == top["priority"] and e["seq"] > top["seq"]):
			top = e
	return top

func _apply_top() -> void:
	var top := _top_claim()
	if top.is_empty():
		set_zoom(1.0)
		set_yaw(0.0)
		set_pitch(_base_pitch)
		set_frame_shift(Vector3.ZERO)
		set_shadow_distance(0.0)
		set_dof(Vector3.ZERO)
		return
	set_zoom(top["zoom"])
	set_yaw(top["yaw"])
	set_pitch(top["pitch"])
	set_frame_shift(top["shift"])
	# Written on EVERY change of winner, unlike the others. Zoom, pitch, yaw, shift and DOF are all
	# lerped toward a target every frame and so repair themselves; set_shadow_distance is a single
	# write-through with no target and no re-assert, so a popped vista's 300 m range would otherwise
	# stay on the sun for the rest of the session.
	set_shadow_distance(top["shadow"])
	set_dof(top["dof"])

## THE CONVERSATION PUSH-IN. It lives here rather than in dialogue.gd because the rig is the thing
## that has to survive a conversation which never ends, and because keeping camera code out of the
## dialogue system is what lets `started`/`finished` stay about dialogue.
func _on_talk_started() -> void:
	# Inherit whatever is framing the player and change ONLY the distance, so a conversation begun
	# inside a vista keeps its yaw, pitch and sun and simply pushes in. Shift and DOF are dropped on
	# purpose: a vista's 36 m frame shift would put both speakers off screen, and a diorama focal
	# band would blur the face being spoken to.
	var under := _top_claim()
	claim_frame(_dialogue, TALK_ZOOM, under.get("yaw", 0.0), under.get("pitch", _base_pitch),
			Vector3.ZERO, under.get("shadow", 0.0), Vector3.ZERO, PRIORITY_VISTA)

func _on_talk_finished() -> void:
	release_frame(_dialogue)


# --- Follow bounds (dungeon rooms): clamp the follow target to a rect so the camera never
# drifts over the walls into a neighbouring room. Inert unless someone claims bounds.

var _bounds_owner: Node = null
var _bounds_center := Vector3.ZERO
var _bounds_half := Vector2.ZERO

func set_follow_bounds(owner: Node, center: Vector3, half_extents: Vector2) -> void:
	_bounds_owner = owner
	_bounds_center = center
	_bounds_half = half_extents

# --- LOCK-ON: press the right stick (or MMB) and the camera fights the enemy, not the player.
#
# The whole feature is one line of geometry riding the ORBIT's own channel: while locked, the
# yaw offset is driven every frame to the value that puts the camera behind the player looking
# at the target, and because WASD is mapped through rig yaw (player.get_move_input), circling
# the enemy becomes "hold left" with no stick corrections — which is the complaint this exists
# to fix. Composing through _orbit_yaw rather than a frame claim keeps every zone's sun, DOF
# and shift untouched, exactly like the orbit; and when the lock drops, yaw simply STAYS where
# the fight left it (orbit scenes) or unwinds to the zone's frame (peek scenes) — the same
# asymmetry _tick_orbit already commits to. Pitch remains the player's throughout.

var _lock_target: Node3D
var _lock_marker: MeshInstance3D

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("lock_cycle"):
		cycle_lock()
		return
	if e.is_action_pressed("lock_on"):
		toggle_lock()

## Public so a probe (or a tutorial script) can lock without synthesizing input events.
func toggle_lock() -> void:
	if _lock_target != null:
		_unlock()
		return
	# Target lock is independent of camera orbit. Fixed dioramas retain their yaw;
	# the character and movement mapping can still face the selected opponent.
	if _target == null or (_dialogue != null and _dialogue.active):
		return
	var best: Node3D = null
	var best_d := lock_range
	for t in _lock_candidates():
		var d: float = _target.global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	if best != null:
		_lock_target = best
		_show_marker()


## EVERYTHING THAT COULD BE LOCKED, in one place. toggle_lock() and cycle_lock() must draw from the
## same filter: two copies would drift, and the cycler would eventually offer a target the acquirer
## refuses -- a reticle that lands on something you cannot lock.
func _lock_candidates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _target == null:
		return out
	for t in get_tree().get_nodes_in_group("enemy"):
		if not (t is Node3D) or t == _target or not _lock_alive(t):
			continue
		if _target.global_position.distance_to((t as Node3D).global_position) > lock_range:
			continue
		out.append(t as Node3D)
	return out


## NEXT TARGET, BY BEARING AROUND THE PLAYER -- not by distance, and the difference is the whole
## feature. A nearest-first cycler makes "next" jump across the screen whenever two enemies are
## within a step of each other, and you cannot predict where the marker will land. Ordering by the
## ANGLE around the player means the reticle always travels the way you pushed, and one full cycle
## visits every enemy exactly once.
##
## Public for the same reason toggle_lock() is: a probe switches targets without synthesising input.
func cycle_lock(dir := 1) -> void:
	if _target == null or (_dialogue != null and _dialogue.active):
		return
	var cands := _lock_candidates()
	if cands.is_empty():
		_unlock()
		return
	if _lock_target == null or not _lock_alive(_lock_target):
		# Nothing held: cycling IS acquiring, so the wheel works from a standing start.
		toggle_lock()
		return
	var here := _bearing_to(_lock_target)
	var best: Node3D = null
	var best_step := TAU
	for t in cands:
		if t == _lock_target:
			continue
		# Signed angular step in the direction asked, wrapped into (0, TAU] so "next" is always
		# ahead and never the target we are already on.
		var step: float = wrapf((_bearing_to(t) - here) * signf(float(dir)), 0.0, TAU)
		if step > 0.0001 and step < best_step:
			best_step = step
			best = t
	if best != null:
		_lock_target = best
		_show_marker()


func _bearing_to(t: Node3D) -> float:
	var d := t.global_position - _target.global_position
	return atan2(d.z, d.x)

func locked() -> Node3D:
	return _lock_target

func _unlock() -> void:
	_lock_target = null
	if _lock_marker != null and not is_instance_valid(_lock_marker):
		_lock_marker = null             # a scene change took it; the next lock rebuilds
	elif _lock_marker != null and _lock_marker.is_inside_tree():
		_lock_marker.get_parent().remove_child(_lock_marker)

## Alive = has no Health, or a Health that says so. The check matters beyond corpses: an enemy's
## death tween scales it away over a second, and a camera pinned to a shrinking body reads as a
## camera that broke.
func _lock_alive(t: Node) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var h := t.get_node_or_null("Health") as Health
	return h == null or h.is_alive()

## The gold diamond over the locked target's head — built once, reparented per lock. NOT a child
## of the target: it must survive the target's own scale/flash tweens untouched.
func _show_marker() -> void:
	if _lock_marker == null:
		var mesh := SphereMesh.new()
		mesh.radius = 0.16
		mesh.height = 0.32
		mesh.radial_segments = 4          # a 4-segment sphere IS an octahedron: the lock diamond
		mesh.rings = 2
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.25)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.8, 0.2)
		mat.emission_energy_multiplier = 2.0
		_lock_marker = MeshInstance3D.new()
		_lock_marker.name = "LockMarker"
		_lock_marker.mesh = mesh
		_lock_marker.material_override = mat
	var cs := get_tree().current_scene
	if cs != null and not _lock_marker.is_inside_tree():
		cs.add_child(_lock_marker)

## Where the diamond floats: just above the target's collision capsule when one is readable,
## else a humanoid-ish guess. Read per frame, so a crouching or hovering body carries it along.
func _marker_height(t: Node3D) -> float:
	var col := t.get_node_or_null("Collision") as CollisionShape3D
	if col != null and col.shape is CapsuleShape3D:
		return col.transform.origin.y + (col.shape as CapsuleShape3D).height * 0.5 + 0.45
	return 2.4

func _exit_tree() -> void:
	# A DETACHED marker is ours alone — nothing else holds it, so a rig dying while unlocked
	# would orphan it (one leaked MeshInstance3D per lock/unlock/reload cycle). A parented one
	# dies with its scene and needs nothing from us.
	# NO PARENT, not "not inside the tree". Those agree everywhere except the one place this runs:
	# during teardown the marker's owner can already be out of the tree while still holding it, and
	# free() then tries to unparent from a parent that is mid-removal ("Parent node is busy
	# adding/removing children"). Detached means unparented -- that is what _unlock() produces and
	# what this was always testing for.
	if is_instance_valid(_lock_marker) and _lock_marker.get_parent() == null:
		_lock_marker.free()

func _tick_lock(delta: float) -> void:
	if _lock_target == null:
		# This branch also catches a target FREED under us while alive (freed == null holds) —
		# a despawner or room reset takes it with no death — so the marker must still be
		# collected on the way out, or it floats at the vanished enemy's last position forever.
		if is_instance_valid(_lock_marker) and _lock_marker.is_inside_tree():
			_unlock()
		return
	if _target == null or not _lock_alive(_lock_target) or _target.global_position.distance_to(
			_lock_target.global_position) > lock_range * 1.4 \
			or (_dialogue != null and _dialogue.active):
		# The dialogue clause: a conversation's push-in owns the yaw through the claim stack,
		# and a lock still writing _orbit_yaw would point the heart-to-heart at a monster.
		_unlock()
		return
	var d := _lock_target.global_position - _target.global_position
	d.y = 0.0
	if orbit_enabled and d.length() > 0.5:
		# The yaw that puts the camera behind the player, looking over them at the target —
		# written as an offset against whatever yaw the framing owns, so a zone's claim and the
		# lock cannot fight: the SUM faces the fight, whoever owns the base.
		_orbit_yaw = wrapf(atan2(-d.x, -d.z) - _yaw_target, -PI, PI)
	if is_instance_valid(_lock_marker) and _lock_marker.is_inside_tree():
		_lock_marker.global_position = _lock_target.global_position \
				+ Vector3(0, _marker_height(_lock_target), 0)
		_lock_marker.rotate_y(delta * 2.4)

## A touch of pull-back as the fight spreads out, so a locked camera at 18 m keeps both bodies
## on screen. A MULTIPLIER like the orbit's, for the same reason: the zone's zoom stays law.
func _lock_zoom() -> float:
	if _lock_target == null or _target == null or not is_instance_valid(_lock_target):
		return 1.0
	var d := _target.global_position.distance_to(_lock_target.global_position)
	return clampf(1.0 + (d - 8.0) * 0.03, 1.0, 1.3)


# --- RIGHT-STICK ORBIT. Off by default; see orbit_enabled.
#
# Deliberately an OFFSET on the framing rather than an entry on the claim stack. The bench this
# came from (scripts/dev/wilds_walk.gd:112) had to push yaw and pitch through claim_frame every
# frame, and so had to restate the wilds zone's shadow_distance of 60 in the same call — a claim
# carries the sun and the DOF with it, and the orbit would otherwise have reset both sixty times
# a second. As an offset it COMPOSES with whatever owns the framing instead of replacing it: a
# vista still chooses where the camera looks, the player just turns relative to it, and no zone's
# sun, DOF or frame shift is touched. The claim stack keeps meaning "which zone owns the shot".

func _tick_orbit(rs: Vector2, delta: float) -> void:
	if not orbit_enabled:
		# Unwind at the rate the orbit turns, so switching this off mid-play does not strand the
		# rig at whatever angle the stick left it at.
		var k := 1.0 - exp(-yaw_speed * delta)
		_orbit_yaw = lerpf(_orbit_yaw, 0.0, k)
		_orbit_pitch = lerpf(_orbit_pitch, 0.0, k)
		return
	# Stick right swings the camera clockwise seen from above; stick up tilts toward top-down
	# (get_vector answers up as NEGATIVE y, hence both signs).
	_orbit_yaw = wrapf(_orbit_yaw - rs.x * orbit_yaw_speed * delta, -PI, PI)
	var lo := deg_to_rad(minf(orbit_pitch_min_deg, orbit_pitch_max_deg))
	var hi := deg_to_rad(maxf(orbit_pitch_min_deg, orbit_pitch_max_deg))
	# PITCH RETURNS, YAW DOES NOT, and the asymmetry is the whole of it. Yaw is where the player
	# chose to LOOK, and WASD is mapped through it (player.get_move_input reads rotation.y), so
	# springing yaw back would turn the controls under the player's thumb. Pitch is a LEAN: let go
	# and the shot reframes to the angle the game is authored at, the way a held door closes.
	#
	# The idle test is the raw axis rather than a timer because get_vector has already applied the
	# deadzone — a stick resting off-centre reads exactly 0, so this cannot fight a drifting pad.
	if orbit_pitch_return_speed > 0.0 and is_zero_approx(rs.y):
		var rest := clampf(_pitch_target, lo, hi)
		if orbit_pitch_rest_deg > 0.0:
			rest = clampf(deg_to_rad(orbit_pitch_rest_deg), lo, hi)
		_orbit_pitch = lerpf(_orbit_pitch, rest - _pitch_target,
				1.0 - exp(-orbit_pitch_return_speed * delta))
		return
	# CLAMPED ON THE SUM, then stored back as an offset. Clamping the offset alone would let the
	# stick wind up a value the band never applies, and the camera would then sit dead at the
	# limit for a beat before answering a pull the other way.
	var absolute := _pitch_target + _orbit_pitch - rs.y * orbit_pitch_speed * delta
	_orbit_pitch = clampf(absolute, lo, hi) - _pitch_target

## Zoom rides the pitch, anchored so the authored ~53 degree angle is exactly 1.0 — steeper pulls
## back, flatter comes in. A MULTIPLIER, so a zone's own zoom still decides the framing it sits on.
func _orbit_zoom(pitch_goal: float) -> float:
	if not orbit_enabled:
		return 1.0
	var band := absf(deg_to_rad(orbit_pitch_max_deg - orbit_pitch_min_deg))
	if band < 0.01:
		return 1.0
	return clampf(1.0 + (pitch_goal - _base_pitch) / band * orbit_zoom_swing, 0.85, 1.2)

func _physics_process(delta: float) -> void:
	# ONE SWEEP PER FRAME, and the list needs it in a way the old single slot did not. A claim can
	# be stranded three ways no caller covers: its owner is freed, a conversation is abandoned
	# without `finished`, or a zone is disabled. Nothing ever frees this rig, so a stranded entry
	# would otherwise own the camera for the rest of the session.
	var before := _claims.size()
	_purge()
	if _claims.size() != before:
		_apply_top()
	# Zoom + pitch (independent of follow): the camera sits on an arc of radius base_dist*zoom
	# around the player; pitch slides it along that arc while look-down matches, so the player
	# stays centred at any framing.
	# READ ONCE, spent below on EITHER the orbit or the peek — never both.
	var rs := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	# The stick selects attack/guard direction while a bumper is held, not camera pitch.
	if Input.is_action_pressed("attack") or Input.is_action_pressed("block"):
		rs = Vector2.ZERO
	if _lock_target != null:
		rs.x = 0.0          # yaw belongs to the lock while it holds; pitch stays the player's
	_tick_orbit(rs, delta)
	# AFTER the orbit on purpose: when orbit is off, _tick_orbit unwinds _orbit_yaw toward zero
	# every frame, and the lock must have the last word on the offset or the two would fight.
	_tick_lock(delta)
	var pitch_goal := clampf(_pitch_target + _orbit_pitch, 0.15, 1.45)
	_zoom = lerpf(_zoom, _zoom_target * _orbit_zoom(pitch_goal) * _lock_zoom(),
			1.0 - exp(-zoom_speed * delta))
	_pitch = lerpf(_pitch, pitch_goal, 1.0 - exp(-yaw_speed * delta))
	# THE LENS, and the whole of it. `frame` is the slice of world the shot holds at the subject
	# and it does NOT move with the dial — the camera retreats and the fov narrows together, so
	# what is on screen stays the same size and only the convergence goes away. `push` is the
	# extra standoff that bought it, and everything measured from the camera owes it that much.
	# `framing_zoom` multiplies BOTH, which is what makes it a pull-back: the ratio between them
	# is the tangent of the half-fov, so scaling them together leaves the lens alone and only
	# moves the camera. `_zoom` — the runtime one a zone or a lock-on drives — has always worked
	# this way; this is the authored dial beside it.
	var view := _zoom * maxf(framing_zoom, 0.01)
	var frame := _iso_size * view
	var dist := _base_dist * view * _lens_dolly()
	var push := dist - _base_dist * _zoom
	_cam.position = Vector3(0.0, sin(_pitch), cos(_pitch)) * dist
	_cam.rotation.x = -_pitch
	if framing_isometric >= 1.0:
		# the limit itself. There is no field of view here, so the shot is `size` — the metres of
		# world across the viewport, which is the same `frame` the perspective end was holding.
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = maxf(frame, 0.1)
	else:
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.fov = rad_to_deg(2.0 * atan(frame * 0.5 / maxf(dist, 0.01)))
	# THE SHADOWS FOLLOW THE CAMERA, not the player. `directional_shadow_max_distance` is measured
	# from the camera, so a rig standing eight times further back with the authored range would
	# cut every shadow in the scene off long before the first one reached the ground.
	if _sun != null:
		_sun.directional_shadow_max_distance = push + (
				_shadow_want if _shadow_want > 0.0 else _base_shadow)
	_push_fog(push)
	rotation.y = lerp_angle(rotation.y, _yaw_target + _orbit_yaw, 1.0 - exp(-yaw_speed * delta))
	# DEPTH OF FIELD, and the one inversion in this file worth reading twice.
	#
	# With no zone owning it, the far plane is pushed out BY THE ZOOM, so pulling back keeps the
	# same amount of world sharp — that is the framing behaviour the rig has always had.
	#
	# A zone that owns the DOF wants the opposite. A diorama read comes from a focal band that does
	# NOT grow with the view: the whole point is that the far edge of the village goes soft while a
	# strip of it stays sharp, which is what makes a real place read as a model of one. So a zone's
	# numbers are absolute metres and the zoom multiply is skipped.
	#
	# Lerped at zoom_speed, the same rate as the pull-back, so the camera moving out and the focus
	# closing in are one gesture rather than a cut at the zone boundary.
	if _attrs:
		var target := _dof_target
		if target == Vector3.ZERO:
			target = Vector3(0.0, _base_dof * _zoom, _base_dof_amount)
		_dof = _dof.lerp(target, 1.0 - exp(-zoom_speed * delta))
		# Near blur is the half that makes it a miniature rather than just hazy distance, and it
		# has never been used in this project — 0 keeps it off, which is every zone but a vista.
		# ...and both planes carry the dolly, for the same reason the shadow range does: a zone
		# asking for "soft past 38 m" means 38 m past the thing being looked at, not 38 m from a
		# camera the lens dial has just moved a hundred metres away.
		_attrs.dof_blur_near_enabled = _dof.x > 0.05
		_attrs.dof_blur_near_distance = _dof.x + push
		_attrs.dof_blur_near_transition = maxf(_dof.x * 0.45, 1.0)
		_attrs.dof_blur_far_distance = _dof.y + push
		_attrs.dof_blur_amount = _dof.z

	if _target == null:
		return
	# RIGHT STICK = a LIMITED camera peek (screen-relative, clamped by peek_distance), NOT a
	# player/camera rotation. Eases back to centre when released. The player never turns with it.
	# When the orbit owns the stick the peek target is zero, so any nudge already on screen eases
	# back to centre rather than freezing there.
	var peek_target := Vector3.ZERO
	if _lock_target != null and is_instance_valid(_lock_target):
		# Locked: lean the frame's centre a little toward the target so both bodies share the
		# shot. Half-strength and capped by the same peek budget the stick would have had.
		var to_e := _lock_target.global_position - _target.global_position
		to_e.y = 0.0
		peek_target = to_e.limit_length(peek_distance) * 0.5
	elif not orbit_enabled:
		peek_target = Vector3(rs.x, 0.0, rs.y).rotated(Vector3.UP, rotation.y) * peek_distance
	_peek = _peek.lerp(peek_target, 1.0 - exp(-peek_speed * delta))
	# Eased at the zoom rate so a vista's pull-back and its slide over the map are one move.
	_frame_shift = _frame_shift.lerp(_frame_shift_target, 1.0 - exp(-zoom_speed * delta))
	var desired := _target.global_position + _peek + _frame_shift
	if _bounds_owner != null:
		desired.x = clampf(desired.x, _bounds_center.x - _bounds_half.x, _bounds_center.x + _bounds_half.x)
		desired.z = clampf(desired.z, _bounds_center.z - _bounds_half.y, _bounds_center.z + _bounds_half.y)
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	if _shake_time > 0.0:
		_shake_time -= delta
		var a := _shake_strength * clampf(_shake_time / 0.18, 0.0, 1.0)
		global_position += Vector3(randf_range(-a, a), randf_range(-a, a), randf_range(-a, a) * 0.3)

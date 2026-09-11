class_name OgreSolver
extends Node3D
## Procedural animation for a four-metre ogre. No clips, no keyframes: the walk, the run, the lean
## and the settle are all computed, every frame, from the creature's own measured proportions.
##
## THE SHAPE OF IT. docs/directed-proceduralism.md splits any generator into three layers — the
## human authors INTENT, rules execute DETAIL. This is that split applied to a body:
##
##   intent / macro   human    a named pose, a target speed, "wind up then hit"
##   rules  / meso    HERE     Froude gait law, foot plant locking, springs, lean-from-acceleration
##   detail / micro   layers   every bone's angle, this frame, on this slope
##
## THIS FILE IS THE MIDDLE ROW, and it is the ONLY place state lives. The SkeletonModifier3D layers
## under the skeleton read what is computed here and write bones; they integrate nothing, query
## nothing, and remember nothing. The reasons, updated for Godot 4.6:
##   - A PhysicsDirectSpaceState3D query from inside a modification pass is a coin flip, so every
##     raycast (`_ground()`) has to run from tick() on the physics clock. This is the reason that
##     still stands, and it alone keeps the state here.
##   - The delta half of the old rationale is OBSOLETE: 4.6 marks `_process_modification()`
##     deprecated in favour of `_process_modification_with_delta(delta)`, which is engine-supplied.
##     The layers override `_process_modification_with_delta` and take time from the engine now;
##     `solver.delta` survives only as a published readout.
##   - Five modifiers sharing state through a sixth node is worse than one owner and five writers.
##
## WHY THE MOTION READS AS HEAVY. Not because it is slow — a slowed-down human reads as a human in
## treacle. Big animals take FEWER, LONGER steps and spend more of the cycle on the ground, and that
## is a law rather than a preference. Everything below is derived from ONE measured number, the hip
## height `leg_length`, so rescaling the creature rescales its motion correctly and for free:
##
##   Froude number       Fr = v^2 / (g*L)       the speed at which creatures of different size are
##                                              dynamically comparable
##   Alexander's stride  s = 2.3 * L * Fr^0.3   fitted across animals from mice upward. Check it
##                                              against a human (L 0.9, v 1.4): it returns a 1.31 m
##                                              stride at 2.1 steps/s, which is how people walk. The
##                                              law is doing real work, not decorating a guess.
##   duty factor         b ~ 0.75 - 0.3*sqrt(Fr), floored at 0.5 so both feet are NEVER off the
##                                              ground at once. A four-metre creature with an aerial
##                                              phase reads as a costume.
##
## FEET DO NOT SKATE, BY CONSTRUCTION. At touchdown the foot's world position is recorded, and for
## the whole of stance the IK target IS that stored point — the body moves over a stationary foot.
## Skate becomes impossible rather than merely small, which is the entire reason for doing it this
## way round. `Foot.last_skate` measures the promise every frame so a regression is visible in the
## lab while you tune, not discovered later by a probe.
##
## CALL IT EXPLICITLY. `tick()` must run AFTER the body has moved, so the body's own
## _physics_process calls it rather than relying on node order. Tree order would work today and
## break silently the day somebody reparents the solver.

const G := 9.81
## Alexander (1976), relative stride length against Froude number.
const ALEXANDER_A := 2.3
const ALEXANDER_B := 0.3

enum Gait { IDLE, WALK, RUN }
enum FootMode { STANCE, SWING }

@export var skeleton_path: NodePath = ^"../Visuals/Model/GeneralSkeleton"
@export var visuals_path: NodePath = ^"../Visuals"
@export var tuning: OgreTuning
## The pose book. Left null it loads the saved `.tres` if the lab has ever written one, and falls
## back to the compiled-in defaults otherwise -- so an edited ogre survives a restart without
## anybody having to remember to wire the resource up.
@export var poses: PoseSet
## Authored clips, by action name. The slam's is Mixamo's downward attack; anything without one
## stays fully procedural. See OgreClipLayer for what a clip is allowed to drive and why.
@export var attack_clip: Animation
const POSES_PATH := "res://assets/models/animations/ogre_poses.tres"
## The runtime clip library: one Animation per action, keyed by the action's name. Grows as
## actions convert to clip-driven, and the human's refined clips drop in here with no code change
## — rebuild it with tools/build_ogre_clips.gd after adding a .res. Distinct from
## ogre_baked_before/, which is the FROZEN diff baseline and must never be played from.
const CLIPS_PATH := "res://assets/models/animations/ogre_clips/ogre_clips.tres"

@export_group("Weapon")
## The mace. Four metres of it -- as long as the ogre is tall, which is what makes it read as a
## two-hander for something this size rather than a club.
@export var weapon_scene: PackedScene
@export var weapon_bone := "RightHand"
## How long the mace is, butt to head, in metres. Used by the clearance correction to know what it
## is keeping out of the body -- a shaft is a segment, not a ray.
@export var weapon_length := 4.0
## The spark the mace and the foot throw when they connect with something. The player's sword has
## had one since it was written; the ogre's weapons produced nothing at all on hitting you.
const HIT_SPARK := preload("res://scenes/fx/hit_spark.tscn")
## Nudges ON TOP of the derived grip, in the hand's own frame. Zero is correct out of the box; these
## exist so the lab can dial the last centimetre without an edit-run cycle.
@export var weapon_grip_pos := Vector3(0.0, 0.0, 0.0)
@export var weapon_grip_rot := Vector3(0.0, 0.0, 0.0)   ## degrees, in the hand's frame

## Fired at each beat of an action, with the world point the beat happens at. The SOLVER owns the
## follow-through (shake, hitstop, dust, the hip dropping under the blow) because that is the
## animation landing; the BODY owns damage, because that is the game. `slam_impact` is where a
## ground slam wants its AreaAttack spawned.
signal action_event(what: StringName, at: Vector3)


## One foot's worth of state. Fields are public on purpose: the IK layer and the lab both read
## them, and a getter apiece would be ten lines of nothing.
class Foot:
	var mode: int = OgreSolver.FootMode.STANCE
	var t := 0.0                       ## 0..1 through the current mode
	var plant := Vector3.ZERO          ## world point the foot is locked to during stance
	var target := Vector3.ZERO         ## world point the ankle is solving to right now
	var predicted := Vector3.ZERO      ## where this foot expects to land (drawn by the lab)
	var normal := Vector3.UP           ## ground normal under the plant
	var grounded := true               ## did the last probe find any floor
	var contact := 1.0                 ## 0..1, blended so touchdown is not a step function
	var steps := 0                     ## footfall counter; also the locality seed
	var last_skate := 0.0              ## m/s the target moved while planted. Must stay near zero.


# --- rig, measured once from the rest pose (never hard-coded: it must survive a rescale) --------
var leg_length := 2.0        ## hip JOINT height above the soles — the inverted pendulum's length
var max_reach := 1.6         ## UpperLeg->Foot chain length; the IK can never exceed this. THE LEG,
                             ## despite the name — the arm chain is `arm_reach` below.
var arm_reach := 0.0         ## UpperArm->Hand chain length, measured in _measure_rig. The strike
                             ## annulus derives from this, so it must exist BEFORE any modifier
                             ## runs — it used to live only in OgreArmIk, which measures itself on
                             ## its first modification pass, and every consumer either guarded
							 ## against reading 0 or (the grip clearance) simply didn't.
var ankle_height := 0.45     ## foot bone height above the sole, at rest
var hip_half_width := 0.39   ## lateral offset of the leg root from centre
var stature := 4.0           ## overall height, for the readout

# --- inputs, written by tick() ------------------------------------------------------------------
var velocity := Vector3.ZERO
var on_floor := true
var facing := 0.0            ## radians — the Visuals yaw
## The last tick's delta. The layers no longer need it (4.6's _process_modification_with_delta
## hands them the engine's own); kept as a readout for anything outside the modifier pass.
var delta := 1.0 / 60.0

# --- derived: mass model ------------------------------------------------------------------------
var speed := 0.0
var accel := Vector3.ZERO    ## world-space, low-passed
var froude := 0.0
var lean_pitch := 0.0        ## radians, positive leaning forward
var lean_roll := 0.0

# --- derived: gait ------------------------------------------------------------------------------
var gait: int = Gait.IDLE
var phase := 0.0             ## 0..1, one full stride (both feet)
var stride := 0.0            ## metres per stride
var stride_freq := 0.0       ## strides per second
var duty := 0.65             ## fraction of the cycle each foot spends planted
var crouch := 0.0            ## how far the pelvis is lowered to buy the legs enough reach
var reach_budget := 0.0      ## how far ahead of the hip the foot can get, at the current crouch
var stride_limited := false  ## true when the legs, not the gait law, are setting the stride
var hip_lift := 1.3          ## measured hip-above-foot, peak-held: what the stride budget spends
var feet: Array = [Foot.new(), Foot.new()]
var double_support := 0.0    ## fraction of the cycle with both feet down

# --- derived: body ------------------------------------------------------------------------------
var hips_offset := Vector3.ZERO   ## metres, in the Visuals frame: bob + settle + sway
var hips_roll := 0.0
var hips_yaw := 0.0
var spine_yaw := 0.0              ## the lagged counter-rotation
var arm_swing := [0.0, 0.0]       ## radians per shoulder, contralateral to the legs
var breath := 0.0                 ## 0..1

# --- derived: actions ---------------------------------------------------------------------------
var pose_weights: Dictionary = {}   ## pose name -> 0..1, what OgrePoseLayer blends
var stance_lock := false            ## an action has both feet planted and the gait phase frozen
var root_request := Vector3.ZERO    ## metres the action wants the body moved, consumed by the body
var action: StringName = &""        ## the running action, or empty
var action_t := 0.0                 ## seconds into it
var action_len := 0.0
## What the ogre is holding: "carry" with the mace, "" with empty hands. Chosen by the body.
var carrying: StringName = &"carry"
## Set by the lab's pose editor: hold this pose at full weight so it can be posed against. Nothing
## else writes it, and an action always wins -- you can fire a slam while editing and it plays.
var preview_pose: StringName = &""
## POSING FREEZE. Set by the editor while it is open.
##
## Everything this system does to look alive works against you while authoring: the idle settle eases
## the foot plants toward a neutral stance, the ground probes re-fire every frame and can catch a
## rock, the pelvis breathes and sways, the hip spring rings, and the weapon eases toward its aim.
## Individually all small; together the body never stops moving, and a pose you just set appears to
## drift and snap under the cursor. You cannot author against a subject that will not hold still.
##
## So: freeze the locomotion, keep the pose. The creature goes back to breathing the moment the
## editor closes.
var posing := false
## What the head watches. Set by the body; null means it looks where it is going.
var look_target: Node3D
## Where a picked-up rock sits, in the grip's frame. Editable by dragging in the pose editor,
## because "the boulder is inside its wrist" is a thing you fix by looking, not by arithmetic.
var rock_hold := Vector3(0.15, 0.05, 0.0)

# --- springs ------------------------------------------------------------------------------------
var hip_spring: Spring
var lean_spring: SpringVec

## The modifier stack. Public so the lab can bypass one at a time — watching the gait with foot IK
## switched off is how you tell a bad gait from a bad IK, and that distinction is most of the
## debugging in a system like this.
var pose_layer: OgrePoseLayer
var clip_layer: OgreClipLayer
var gait_layer: OgreGaitLayer
var dynamics: OgreDynamicsLayer
var foot_ik: OgreFootIk
var limit_layer: OgreLimitLayer
## Diagnostics for the clip stance: how far the pelvis was dropped to afford it, and how wide the
## clip asked the stance to be. Read by the lab so "the legs look wrong" can be a number.
var clip_drop := 0.0
## How far the clearance correction had to swing the weapon this frame, in degrees. Reported so
## "the mace is in the ogre" and "the mace is being shoved about" are separate, visible numbers.
var clear_degrees := 0.0
## How far the weapon turned this frame to let the second hand reach, and whether that was enough.
## Reported so "the grip is out of reach" and "the yield ran out of budget" stay separable.
var yield_degrees := 0.0
var yield_short := 0.0
## The cone's own terms, for when its guarantee and the measured distance disagree.
var yield_dbg := {}
## How long every grip has been lost, and the grip's world velocity, so a dropped weapon leaves the
## hand carrying the speed it had rather than appearing from rest.
var _ungripped := 0.0
var _grip_vel := Vector3.ZERO
var _grip_last := Vector3.ZERO
signal weapon_dropped(at: Vector3)
## Which side the clearance push is committed to for the current intrusion. Latched; see
## _clear_of_body for what happens when it is free to reverse mid-swing.
var _clear_side := 0.0
## The mace's resting orientation in the weapon hand's own frame, measured once by _measure_grip().
var _grip_rest := Basis()
## THE CONTACT POINT: where the ogre's weapon hand holds the mace, IN THE MACE'S OWN COORDINATES.
##
## Two points, on the weapon, and everything else derives from them. There used to be four competing
## answers to "where is it held" -- OgreArmIk.primary_along, OgreArmIk.grip_along,
## OgreSolver.weapon_grip_along and the pose-authored offset -- which did not agree, so the point the
## IK reached for, the point the off hand measured from, and the place the mace was actually hung
## were three different places. All four are gone.
##
## The mace's origin is its BUTT and its shaft runs up +Y (measured: tools/measure_mace.gd), so this
## is "y metres up the haft", plus whatever small cross-shaft offset the base pose asked for.
##
## DERIVED FROM THE BASE POSE, not typed in. See _measure_grip_point().
var grip_point := Vector3(0.0, 0.5, 0.0)
## The same, for the off hand. Two points, both on the axis, deliberately far apart.
var off_point := Vector3(0.0, 2.0, 0.0)
## The swing's angle this frame, in degrees from the plane's up axis. This is the quantity the
## timing is actually shaped in -- head HEIGHT saturates near the top of the arc, so forty per cent
## of the angle already reads as ninety per cent of the height and the shape of the wind-up cannot
## be seen in it at all.
var swing_angle := 0.0
## The terms the floor angle is solved from, for when the head ends up under the ground anyway.
var swing_dbg := {}
## The arm extension the swing settled on, after being solved from the impact point. Watched because
## it pinned at its limit means the ogre is at the edge of what it can reach and the shuffle -- or a
## different attack -- has to make up the rest.
var swing_reach_used := 0.0
## WHERE THIS SWING IS GOING TO LAND, in world space. Springs toward the player while the ogre aims
## and all but freezes once the smash begins -- see OgreTuning's Aim group. Read by the body to
## place and move the ground telegraph, and by the swing itself to decide which way to face.
var aim_point := Vector3.ZERO
var _aim_live := false
## Extra time spent hanging at the top of the wind-up, waiting to be aligned. Subtracted from the
## action clock when the swing computes its phase, so the plateau stretches without disturbing the
## beats or the phase machinery underneath.
var _aim_extra := 0.0
## Which zone the player was in last time the aim looked, and the attack to start instead when this
## one is abandoned. There is deliberately no turn request beside them: the body already turns to
## face the player every frame, rate-capped by yaw_rate(), and a second thing asking for the same
## yaw is two notions of one idea waiting to disagree.
var zone := Zone.STRIKE
## Cached shoulder height, measured from the rest pose the first time it is asked for.
var _hinge_y := 0.0
## Thigh + shin, measured once off the rest pose. The kick's reach is built on it.
var _leg_chain := 0.0
## The volume on the driving foot, and the node it rides. Built the way the mace's is.
var kick_hitbox: HitBox
var _kick_node: Node3D
## Where the driving foot is being sent, in world space, and how far along it is.
var kick_point := Vector3.ZERO
## Is the wind-up waiting at the top for the body to come round? Read by the clock, set by the aim.
var _holding := false
## The damage volume on the mace head, built with the weapon and moving with it.
## WHICH HANDS ARE HOLDING THE WEAPON. Index 0 is the left hand, 1 the right.
##
## A DECLARED STATE, not something inferred. It used to be derived from whether the palm could reach
## the haft, with hysteresis bolted on to stop the resulting switch chattering twice a stride -- and
## a grip that decides for itself whether it exists is a grip that lets go halfway through a swing
## for reasons nothing else in the system knows about. Holding a weapon is a thing a creature
## DECIDES. Set it, and the arm goes there; clear it, and the hand lets go.
var grip_held: Array[bool] = [true, true]
## Which way this swing comes in: -1 from the left, 0 straight down the middle, +1 from the right.
## Chosen once when the action starts, so the whole stroke rolls the same way.
var swing_side := 1
## Where the target was last frame and how fast it is going, for leading the aim.
var _track_last := Vector3.INF
var _track_vel := Vector3.ZERO
## A QUARTER TURN, always. `u` is built perpendicular to `v`, so the head goes from the top of the
## plane to the impact point in exactly 90 degrees -- there is no floor angle to solve, and no tilt
## steep enough to put the ground out of reach.
const LAND_ANG := PI * 0.5
var mace_hitbox: HitBox
var arm_ik: OgreArmIk

var _skel: Skeleton3D
var _visuals: Node3D
var _body: CharacterBody3D
var _body_rid: RID
var _prev_vel := Vector3.ZERO
var _time := 0.0

## tick() calls since ready. The contract is one per physics frame — the combat probe holds the
## AI to it, because two of its branches used to `return` past the tick and nothing noticed.
var ticks := 0
var _bone: Dictionary = {}
var _ready_ok := false
var _actions: Dictionary = {}
var _act: ActionSpec
var _phase_i := -1
var _phase_t := 0.0
var _prev_pose: StringName = &""
var _fired: Dictionary = {}
var _hit_open := false
var _hit_done := false        ## the damage window has already had its turn this action
var _open_hb: HitBox = null   ## the volume this action armed, remembered so an interrupt closes IT

## GAMEPLAY'S VETO over the damage window. The solver owns arming and disarming its own volumes —
## one authority, on its own action clock — and asks this just before arming one. The AI supplies
## it (enemy.gd: "am I in the ATTACK state"); left unset, damage is always allowed, which is what
## the lab puppet wants.
var may_damage: Callable = Callable()
var _weapon: Node3D
var _grip: Node3D
## The shaft's direction in the HAND's own frame, worked out in refresh_grip(). Anything that wants
## a point on the weapon has to ask for it in these terms; a hard-coded local vector is a guess
## about the hand's axes, and the off-hand IK spent a whole pass reaching for one.
var _haft_dir := Vector3.UP
## The weapon's aimed direction in WORLD space, blended from the active poses. The grip is driven to
## match it every frame, so the mace points where the pose says rather than wherever the forearm
## happens to be. See PoseSet.aims for why that separation matters.
var weapon_dir := Vector3.UP
## Where the anchor bone was when the weapon was last placed. Kept so the off hand can work out
## where the PRIMARY hand sits on the shaft.
var _anchor_at := Vector3.ZERO
var _anchor_bone := "RightHand"
## The eased pose-relative placement. Kept separate from the anchor's own motion so the weapon can
## be RIGID to the hand holding it while still easing between poses.
var _w_pos := Vector3.ZERO
var _w_rot := Quaternion.IDENTITY
## Last frame's weapon basis, for the turn-rate limit.
var _w_prev := Basis()


## Which bone the weapon is currently hung off. "Body" means it is placed relative to the creature
## instead, and both hands solve onto it — see OgreArmIk.
func weapon_anchor() -> String:
	return _anchor_bone

# Autoloads held by NODE, not by their global identifier. `EventBus.combat_impact.emit(...)` is what
# the rest of the project writes and it is correct in the game — but a `--script` SceneTree run
# (which is how every probe and measuring tool here starts) has no autoload identifiers at COMPILE
# time, so the bare name fails to parse and takes every dependent script down with it. Resolving by
# path costs one lookup at load and means the solver behaves identically in the game and on the
# bench. The bench is where it gets tested; it has to run there.
## The feedback facade (/root/CombatFeedback) — the ONE game service this solver reports through.
## It used to hold EventBus, Fx and Water separately, which meant the animation addon knew the
## shape of three game systems; now it knows one door, and the door labels every effect CONTACT
## or BEAT.
var _feedback: Node

## Bones the solver touches, resolved once. A -1 here means the retarget failed, and every later
## stage would then fail in a way that reads as bad maths instead of as a bad import.
const BONES := [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]


func _ready() -> void:
	if tuning == null:
		tuning = OgreTuning.new()
	if poses == null and ResourceLoader.exists(POSES_PATH):
		poses = ResourceLoader.load(POSES_PATH) as PoseSet
	if poses == null:
		# The saved file is missing, or failed to load (a moved script path will do it -- promoting
		# this folder to an addon broke exactly that once). Falling back to the built-ins keeps the
		# creature animated instead of crashing every layer that asks it for a pose.
		poses = PoseSet.defaults()
	else:
		# The saved file wins where it speaks; the built-ins fill what it never mentions. Without
		# this the .tres REPLACED the defaults, and any pose the editor had not saved resolved to
		# {} — which is how the kick, backstep and charge came to blend toward an empty pose with
		# no error anywhere.
		poses.merge_defaults()
	var authored := {}
	if ResourceLoader.exists(CLIPS_PATH):
		var clip_lib := ResourceLoader.load(CLIPS_PATH) as AnimationLibrary
		if clip_lib:
			for cn in clip_lib.get_animation_list():
				authored[StringName(cn)] = clip_lib.get_animation(StringName(cn))
	_actions = ActionSpec.library({&"slam": attack_clip}, authored)
	_skel = get_node_or_null(skeleton_path) as Skeleton3D
	_visuals = get_node_or_null(visuals_path) as Node3D
	_body = get_parent() as CharacterBody3D
	if _body:
		_body_rid = _body.get_rid()
	if _skel == null:
		push_error("OgreSolver: no Skeleton3D at %s" % skeleton_path)
		return

	# Modifiers must run in PHYSICS, for the same reason player.gd pins its AnimationTree there: the
	# solver computes plant points once per physics tick, and a modifier running in the idle phase
	# would re-solve against a stale one on every frame that is not a physics tick. Above 60 fps
	# that is a one-frame skate, every frame.
	_skel.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

	# The import ships a junk 0.033 s clip named `mixamo_com` — Mixamo's rest-pose placeholder.
	# `animation/import=false` does NOT drop it in Godot 4.6 (measured), and it carries 49 real bone
	# tracks, so anything that ever plays it silently overwrites the entire solver. Nothing plays it
	# today. This makes sure nothing can tomorrow.
	var junk := _find_animation_player(_visuals)
	if junk:
		junk.queue_free()

	_feedback = get_node_or_null(^"/root/CombatFeedback")
	if _feedback == null:
		push_warning("OgreSolver: no /root/CombatFeedback — shake, dust and hitstop will be silent")

	for b in BONES:
		_bone[b] = _skel.find_bone(b)
	_measure_rig()

	hip_spring = Spring.new(0.0, tuning.hip_omega, tuning.hip_zeta)
	lean_spring = SpringVec.new(Vector3.ZERO, tuning.spine_omega, tuning.spine_zeta)
	_build_layers()
	_attach_weapon()
	_measure_grip()
	_attach_mace_hitbox()
	_attach_kick_hitbox()
	_ready_ok = true
	_reset_feet()


## WHERE THE MACE SITS IN THE FIST, as an orientation relative to the hand bone.
##
## The shaft lies along the hand bone's local -Z. The weapon's own shaft is its +Y, so the grip is
## the rotation taking one onto the other.
##
## MEASURED, and re-measured after a correction elsewhere turned out to be poisoning the
## measurement. The lab's --demo=gripfit scores every candidate axis of the hand against the only
## two things a slam must do -- put the head on the floor IN FRONT at the contact frame, and keep
## the shaft clear of the body:
##
##   axis       head_y@contact   forward   up      clearance
##   -Z             -0.17         +0.64   -0.73      2.64     <- lands, in front, driving down
##   +Y             +0.17         -0.77   -0.63      2.62     <- lands, driving down, but BEHIND
##   forearm        +2.99         -0.91   +0.20      2.99     <- three metres up, pointing UP
##
## The forearm was the first honest guess and reads plausibly: a weapon continues the line of the
## arm. It is three metres wrong at the only frame that matters, and pinning four metres of mace to
## the forearm is also what swung it through the ogre's legs, because a wrist rotation a short sword
## absorbs a long haft cannot.
##
## +Y was the second, and it was measured while a bogus 180 degree clip yaw was in force. With the
## body turned around underneath it, "in front" and "behind" had swapped, so the table said +Y and
## the table was being lied to. Removing the yaw put -Z on top -- and note the two differ by exactly
## the 90 degrees between them, not by the 180 the yaw was supplying.
func _measure_grip() -> void:
	refresh_grip()
	_grip_rest = Basis(Quaternion(Vector3.UP, Vector3.FORWARD))


## Is this hand holding the weapon? The only question the arm IK asks about the grip.
func gripping(side: int) -> bool:
	return side >= 0 and side < grip_held.size() and grip_held[side]


## THE RIGHT HAND'S CONTACT POINT, in world space. A point on the mace, 1/8 of the way up the haft.
func grip_world() -> Vector3:
	return global_position if _grip == null else _grip.global_transform * grip_point


## Where a hand grips, in the mace's own coordinates: straight up the shaft from the butt, because
## the shaft IS the mace's +Y (measured, tools/measure_mace.gd).
func grip_local(frac: float) -> Vector3:
	return Vector3(0.0, weapon_length * frac, 0.0)


## The second hand's point on the haft. Same shaft, offset along it, clamped so it stays on the
## weapon -- a hand cannot grip half a metre past the end of a thing.
## THE LEFT HAND'S, 4/8 of the way up. Far enough from the right that the two are visibly a grip
## and not one point drawn twice.
func off_grip_world() -> Vector3:
	return global_position if _grip == null else _grip.global_transform * off_point


## Hang the mace off the hand.
##
## Built in code, and on a BoneAttachment3D, for the reason enemy.gd's `_attach_sword_visual()`
## gives: the imported skeleton is rebuilt on every reimport, so a scene path into it is a path that
## will one day not resolve.
##
## Unlike that one, there is NO SCALE DIVISION here. enemy.gd has to divide its grip transform by
## the 2.2 scale baked into the scene's Model node, and its own comment notes that changing that
## scale silently breaks the socket. The ogre keeps its size in the import instead
## (nodes/root_scale), so the skeleton is already in metres and the grip is just a transform.
func _attach_weapon() -> void:
	if weapon_scene == null or _skel == null:
		return
	if _skel.find_bone(weapon_bone) < 0:
		push_warning("OgreSolver: no bone %s to hang the weapon on" % weapon_bone)
		return
	# NO BoneAttachment3D, and no node under the skeleton at all. The grip is a plain child of the
	# solver, positioned each frame from the hand bone's end-of-pass position.
	#
	# The obvious construction -- a BoneAttachment3D on the hand with the weapon under it -- is what
	# every other weapon in this project uses and it is wrong HERE, because this weapon is aimed
	# independently of the arm, so its transform has to be written every frame. Writing a transform
	# inside the skeleton's subtree forces the skeleton to resolve, the modifier layers end up
	# running against a pose that has already moved, and it comes back as FOOT SKATE at walking
	# pace. Measured: 0.27 m/s of skate with the weapon attached that way, 0.0001 without.
	# Nothing about the symptom points at a mace.
	_grip = Node3D.new()
	_grip.name = "Grip"
	add_child(_grip)
	_grip.top_level = true
	_weapon = weapon_scene.instantiate() as Node3D
	_grip.add_child(_weapon)
	refresh_grip()


## Where the weapon sits in the hand, DERIVED rather than dialled.
##
## A weapon held in a fist extends along the forearm, so the direction from the elbow to the hand is
## the direction the shaft should point -- and that vector is readable straight off the rest pose,
## in the hand's own frame, without knowing anything about which of the bone's axes is which. This
## is the same move that fixed the feet (TwoBoneIk.flatten): let the rig answer the question instead
## of asserting an axis and being wrong on the next model.
##
## The mace is modelled standing on its butt with the HEAD at the top of its local +Y, so +Y points
## the way the weapon should point: outboard, along the forearm.
##
## Also re-callable at runtime: the lab tunes the nudges with sliders while the ogre is swinging.
func refresh_grip() -> void:
	if _grip == null or _skel == null:
		return
	var ih := _skel.find_bone(weapon_bone)
	var ie := _skel.find_bone("RightLowerArm" if weapon_bone.begins_with("Right") else "LeftLowerArm")
	var dir := Vector3.UP
	if ih >= 0 and ie >= 0:
		var hand := _skel.get_bone_global_rest(ih)
		var elbow := _skel.get_bone_global_rest(ie)
		var along := (hand.origin - elbow.origin).normalized()
		dir = (hand.basis.inverse() * along).normalized()
	# Only the shaft direction is kept. The grip's TRANSFORM is owned by _aim_weapon now, which
	# writes it in world space every frame from the aim and the hand's snapshot position -- there is
	# nothing left for a rest-pose-derived local transform to do.
	_haft_dir = dir


## The modifier stack, built in code rather than saved into the scene — player.gd adds its ArmGuard
## the same way and for the same reason: the imported skeleton is rebuilt on every reimport, so a
## hard scene path into it is a path that will one day not resolve.
##
## CHILD ORDER IS EXECUTION ORDER, and this order is load-bearing:
##
##   PoseLayer  the action's intent, onto the rest pose
##   ClipLayer  an authored clip over the upper body, where a performance beats a solver
##   GaitLayer  locomotion on top of it, backing off wherever a pose owns a bone
##   Dynamics   inertia: the upper body arrives late at whatever those two asked for
##   FootIk     the world-space contact guarantee, which must come after anything that moves the hips
##   ArmIk      the off hand onto the weapon, which can only be solved once the weapon has stopped
##
## See ogre_foot_ik.gd for the general rule that generates this order.
func _build_layers() -> void:
	pose_layer = OgrePoseLayer.new()
	pose_layer.name = "PoseLayer"
	pose_layer.solver = self
	_skel.add_child(pose_layer)

	# The authored clip, over the poses and under the gait: it is INTENT, like a pose, so it belongs
	# with the intent layers rather than with the ones that answer to the world.
	clip_layer = OgreClipLayer.new()
	clip_layer.name = "ClipLayer"
	clip_layer.solver = self
	_skel.add_child(clip_layer)

	gait_layer = OgreGaitLayer.new()
	gait_layer.name = "GaitLayer"
	gait_layer.solver = self
	_skel.add_child(gait_layer)

	# Inertia for everything above the pelvis. AFTER the pose and the gait, because it filters what
	# they produced; BEFORE the foot IK, because contact with the ground still has to be the last
	# word. See ogre_dynamics_layer.gd for what it is for.
	dynamics = OgreDynamicsLayer.new()
	dynamics.name = "Dynamics"
	dynamics.solver = self
	_skel.add_child(dynamics)

	foot_ik = OgreFootIk.new()
	foot_ik.name = "FootIk"
	foot_ik.solver = self
	_skel.add_child(foot_ik)

	# The off hand goes LAST, because its target is a point on a weapon that rides the other hand:
	# it can only be solved once everything that moves the right arm has finished moving it.
	arm_ik = OgreArmIk.new()
	arm_ik.name = "ArmIk"
	arm_ik.solver = self
	_skel.add_child(arm_ik)

	# And after even that, the ANATOMY: a hyper-extension guard clamping the upper body to the
	# shared joint table (scripts/components/joint_limits.gd — the same numbers the ragdoll's
	# physical joints are authored from). Bit-identical while motion stays inside its budgets;
	# it exists for the frames that do not. Legs and hands are exempt by design — see its header.
	limit_layer = OgreLimitLayer.new()
	limit_layer.name = "LimitLayer"
	limit_layer.solver = self
	_skel.add_child(limit_layer)


func bone(n: String) -> int:
	return int(_bone.get(n, -1))


func skeleton() -> Skeleton3D:
	return _skel


func is_ready() -> bool:
	return _ready_ok


## THE BODY FRAME, defined once. Godot's forward is -Z, so a node yawed by `facing` points along
## (-sin, 0, -cos) -- and the ogre matches that because scenes/ogre.tscn bakes a 180 degree yaw into
## the Model to turn the mesh (which faces +Z) around. Getting this by hand at each call site is how
## the left and right feet end up swapped, which looks like a gait bug and is not one.
##
## `facing` is a WORLD yaw -- callers pass the visuals' yaw measured off its global basis, not the
## local Euler, because every layer bridges back through `skel.global_transform` and the two only
## agree if this one is global too. Getting that wrong is what made a rotated Ogre root shear.
##
## YAW ONLY, deliberately. This is hard-constrained to the XZ plane, and `_ground()` casts world-down
## and rebuilds its hit as Vector3(at.x, y, at.z), so a root with PITCH or ROLL is not supported and
## will not be until the ground query and the Vector3.UP convention are reworked together.
func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func right() -> Vector3:
	var f := forward()
	return Vector3(-f.z, 0.0, f.x)


## Which way is foot 0's side of the body? THE ANSWER IS NOT "+right".
##
## This rig's `LeftUpperLeg` sits at model-space +X, and scenes/ogre.tscn yaws the Model 180 degrees
## to turn the mesh around — so the ogre's own LEFT ends up at world -X. Offsetting foot 0 to +right
## puts the left foot on the right-hand side, the legs cross, and every plant point is wrong by
## twice the stance width. It reads as "the legs are inverted", which is exactly what it is.
##
## It is worth stating as a function rather than a sign at three call sites, because the failure is
## quiet: the gait law, the cadence and the stride all stay perfectly correct while the creature
## walks with its ankles crossed.
func side_dir(i: int) -> Vector3:
	return right() * (-1.0 if i == 0 else 1.0)


## Read the creature's proportions off its own rest pose. Everything downstream is derived from
## these four numbers, so a reimport at a different scale retunes the animation automatically —
## which is the whole reason they are measured rather than typed in.
func _measure_rig() -> void:
	var lo := INF
	var hi := -INF
	for i in _skel.get_bone_count():
		var y: float = _skel.get_bone_global_rest(i).origin.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	# The soles sit below the lowest bone (the toe joint, which is inside the foot mesh). The mesh
	# is taller than the bone span by the crown and the sole together; half that surplus is the
	# overhang at each end. Measured at 0.131 m for this rig by tools/measure_ogre_scale.gd.
	var sole := lo - 0.131
	stature = hi - sole
	var up := _rest_pos("LeftUpperLeg")
	var low := _rest_pos("LeftLowerLeg")
	var foot := _rest_pos("LeftFoot")
	leg_length = up.y - sole
	max_reach = up.distance_to(low) + low.distance_to(foot)
	ankle_height = foot.y - sole
	hip_half_width = absf(up.x)
	# The ARM chain, same construction OgreArmIk uses (segment distances on the global rests, the
	# longer of the two sides — this rig is a few millimetres asymmetric) — measured HERE so the
	# strike annulus exists before any modifier has run, instead of reading 0 until the arm-IK
	# layer's first pass.
	arm_reach = 0.0
	for side in [["LeftUpperArm", "LeftLowerArm", "LeftHand"],
			["RightUpperArm", "RightLowerArm", "RightHand"]]:
		var sh := _rest_pos(side[0])
		var el := _rest_pos(side[1])
		var ha := _rest_pos(side[2])
		arm_reach = maxf(arm_reach, sh.distance_to(el) + el.distance_to(ha))


func _rest_pos(n: String) -> Vector3:
	var i := bone(n)
	return Vector3.ZERO if i < 0 else _skel.get_bone_global_rest(i).origin


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var a := _find_animation_player(c)
		if a != null:
			return a
	return null


# =================================================================================================
# THE TICK
# =================================================================================================

## Advance the whole solver. Call from the body's _physics_process AFTER move_and_slide(), so plant
## points are computed against where the body actually ended up rather than where it hoped to go.
func tick(delta: float, vel: Vector3, grounded: bool, yaw: float) -> void:
	if not _ready_ok or delta <= 0.0:
		return
	ticks += 1
	_time += delta
	self.delta = delta
	velocity = vel
	on_floor = grounded
	facing = yaw

	# THE TICK ORDER IS A CONTRACT: aim -> action -> mass -> gait -> feet -> body -> clip-reconcile.
	# Later phases overwrite earlier ones on purpose (_step_body assigns hips_offset outright;
	# _step_clip_stance adds to it and rewrites feet[].target LAST), so reordering these is a
	# behaviour change even when every line inside them is untouched.
	#
	# THREE READS IN THIS PIPELINE ARE ONE FRAME STALE, AND DELIBERATELY SO — they measure what was
	# actually rendered rather than predict what might be:
	#   1. _reach_budget reads foot_ik.hip_lift()          (last modifier pass; see its comment)
	#   2. _step_clip_stance reads clip_layer.hips_offset()/foot_offset()  (last pass's capture)
	#   3. _aim_weapon (idle clock) reads arm_ik's end-of-pass snapshot
	# Changing WHICH frame any of them reads will not fail loudly; it comes back as skate or as the
	# pelvis bouncing. Treat the staleness as part of the contract.
	_step_aim(delta)
	_step_action(delta)
	_step_mass(delta)
	_step_gait(delta)
	_step_feet(delta)
	_step_body(delta)
	_step_clip_stance(delta)


## Speed, acceleration and lean. Acceleration is low-passed because a raw frame-to-frame velocity
## difference is mostly noise from move_and_slide's depenetration, and a lean driven by noise
## jitters the entire torso.
func _step_mass(delta: float) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	speed = planar.length()
	var raw := (planar - _prev_vel) / delta
	_prev_vel = planar
	accel = accel.lerp(raw, 1.0 - exp(-8.0 * delta))
	froude = (speed * speed) / (G * maxf(leg_length, 0.01))

	# tan(lean) = a/g is the physically correct lean for an acceleration — the same reason a
	# motorcyclist banks. Routed through a spring so the torso ARRIVES LATE: inertia is legible
	# only as lag, and a lean that tracks acceleration exactly reads as weightless.
	var want := Vector3(atan(accel.dot(right()) / G), 0.0, atan(accel.dot(forward()) / G)) * tuning.lean_gain
	lean_spring.omega = tuning.spine_omega
	lean_spring.zeta = tuning.spine_zeta
	var l := lean_spring.step(delta, want)
	lean_roll = l.x
	lean_pitch = l.z


# =================================================================================================
# ACTIONS
# =================================================================================================

## Start a move. Interrupts whatever was running, which is the point: `stagger` and `flinch` go
## through this same door, and a wind-up that survives its own interruption is the bug enemy.gd's
## `fear()` docstring spends four paragraphs on -- a feared archer that fires anyway, from across
## the room, while fleeing.
func play_action(n: StringName) -> void:
	if not _actions.has(n):
		return
	# Close a still-open window BEFORE _act is reassigned. The close used to come last, after the
	# swap — and strike_hitbox() branches on the CURRENT action, so an interrupt during a kick's
	# open window deactivated the NEW action's volume and left the kick's live with nothing
	# owning it.
	if _hit_open:
		_hit_open = false
		_close_window()
	_act = _actions[n]
	action = n
	action_len = _act.duration()
	action_t = 0.0
	_aim_extra = 0.0
	_holding = false
	_phase_i = 0
	_phase_t = 0.0
	_fired.clear()
	_hit_done = false
	# The ground telegraph goes up NOW, at the start of the wind-up, not at the moment of impact --
	# a warning that arrives with the blow is not a warning.
	if _act.slam_radius > 0.0:
		action_event.emit(&"slam_telegraph", aim_point if _aim_live else global_position + forward() * (max_reach * 1.4))


## Stop dead and hand the body back. The analogue of enemy.gd's `_attack_tween.kill()`, and it must
## be called from the same three places (stagger, fear, death) for the same reason.
func cancel_action() -> void:
	if _act == null:
		return
	if _hit_open:
		_hit_open = false
		_close_window()
	_act = null
	action = &""
	action_t = 0.0
	_aim_extra = 0.0
	_holding = false
	_phase_i = -1
	stance_lock = false
	if clip_layer:
		clip_layer.weight = 0.0


func is_acting() -> bool:
	return _act != null


## Is the running action driven by its OWN clip (baked or refined)? The clip layer asks this to
## decide whether the mix dials sit out — see OgreClipLayer.clip_share().
func clip_authored() -> bool:
	return _act != null and _act.clip != null and _act.clip_authored


## THE HEIGHT THE SWING HINGES AT: one authored number, measured once, used by the zone and by the
## swing alike. The zone is the set of places that hinge can put the head, so it has to be built on
## the hinge that is actually used — and the rest pose is not it: the ogre hunches and crouches
## into a wind-up, putting its shoulder 0.6 m lower than rest says, and an annulus built at rest
## height has no solution at all (it came out 0.00..0.00, which the behaviour read as "can never
## attack").
##
## It used to be latched from the live shoulder at the moment of contact, which was correct and
## useless: the zone could then only be corrected BY a completed swing, while the swing was gated by
## the zone. Before the ogre had ever landed a blow the zone sat on a fallback that was too small to
## attack from, so it never landed one, so the zone never corrected. A derived quantity must never
## depend on the thing it gates.
##
## 2.89 m is the measured value -- the shoulder's height above the feet at the frame the mace head
## reaches the floor, with the ogre hunched and folded into the strike. Rest reads 3.51 and carry
## reads higher still; both are half a metre out, and at rest height the annulus has no solution at
## all. Re-measure it with --areas-force=slam if the rig or the slam pose changes.
func shoulder_height() -> float:
	return tuning.swing_high


## HOW FAR THE SWING'S ARM REACHES, one answer for the swing and for the zone alike.
##
## From the solver's OWN measurement now, taken in _measure_rig — it used to ask the arm-IK layer,
## which reads 0 until its first modification pass, and an unguarded 0 does not fail: it makes
## both edges of the strike annulus collapse onto the body radius, so the band becomes a single
## point and every range test quietly answers "no". The guard survives for the pathological rig
## with no arm bones.
func swing_arm_full() -> float:
	if arm_reach > 0.01:
		return arm_reach * tuning.swing_reach
	return 1.25


## THE BAND A GIVEN ATTACK WORKS AT, derived from whichever limb delivers it.
##
## The mace swing asks the arm; the kick asks the leg; anything else falls back to the two numbers on
## its own spec. One place to ask, so an attack cannot carry a reach that disagrees with the geometry
## the way the slam's declared 2.2..5.0 disagreed with its actual 0.62..2.37.
func zone_for(a: ActionSpec) -> Vector2:
	if a == null:
		# THE DEFAULT ATTACK'S BAND, not an empty one. Returning Vector2.ZERO here meant that asking
		# about range with nothing running answered ADVANCE for every distance and every bearing at
		# once -- a band with no inside again, and again failing as silence rather than as an error.
		return strike_zone()
	if a.use_strike_zone:
		return strike_zone()
	if a.kick_foot >= 0:
		return kick_zone()
	# THE DECLARED BAND, unmodified. Lowering a ranged attack's near edge to meet the swing's far
	# edge -- the previous attempt at closing the gap between them -- made throwing a rock legal at
	# three metres, and since the chase stops just outside the swing's band that became the only
	# legal attack there. Ten wind-ups in a row, every one a rock throw, never a swing. The gap
	# between "too far to swing" and "far enough to throw" is closed by WALKING, which is what the
	# ADVANCE zone is for; it is not a hole that needs plugging with the wrong attack.
	return Vector2(a.reach_min, a.reach_max)


## HOW FAR A KICK REACHES, from the leg instead of the arm.
##
## The same inversion the swing uses, turned on its side: the foot travels on a chain of known length
## from a hip of known height, and it has to arrive at kick_height rather than at the floor. What is
## left over is horizontal, and that is the reach.
func kick_zone() -> Vector2:
	# HIP HEIGHT, not the crouch. `crouch` is how far the ogre has SUNK, so using it directly put
	# the hip at 0.30 m off the ground -- below the height the foot is being driven to. The rest of
	# the reasoning (why the band must MEET the swing's) lives with the maths in ReachEnvelope.
	return ReachEnvelope.kick_band(leg_chain(), maxf(leg_length - crouch, 0.3),
			tuning.kick_height, tuning.kick_lunge, strike_zone().x, tuning.weapon_clear_radius)


## Thigh plus shin, measured off the rest pose once. The kick's reach is built on it.
func leg_chain() -> float:
	if _leg_chain > 0.0:
		return _leg_chain
	var u := bone("RightUpperLeg")
	var l := bone("RightLowerLeg")
	var f := bone("RightFoot")
	if _skel and u >= 0 and l >= 0 and f >= 0:
		var pu := _skel.get_bone_global_rest(u).origin
		var pl := _skel.get_bone_global_rest(l).origin
		var pf := _skel.get_bone_global_rest(f).origin
		_leg_chain = pu.distance_to(pl) + pl.distance_to(pf)
	return _leg_chain if _leg_chain > 0.0 else 1.6


## Every action the creature owns, so the body can ask about the roster without a second copy of it.
func attack_names() -> Array:
	return _actions.keys()


## EVERY ATTACK WHOSE BAND CONTAINS THIS DISTANCE — the GEOMETRY half of choosing, and the whole
## of what this file answers about attack selection now. Deterministic: same distance, same list.
##
## Which one to actually throw is a DECISION, and decisions live with the AI —
## Enemy.choose_attack() picks among this list (random, one reroll against its own memory of the
## last attack), and Enemy._roll_chain() rolls the follow-up strings. The chooser lived in here
## for a long time, which meant the animation addon owned the ogre's tactics and the roster query
## in zone_of paid for a random roll it never used.
##
## The bands are the actions' own, so an attack carries the range it works at rather than the ogre
## keeping a second list that can disagree with it.
func actions_reaching(dist: float) -> Array[StringName]:
	var fits: Array[StringName] = []
	for n in _actions:
		var a: ActionSpec = _actions[n]
		if not a.is_attack:
			continue
		var b := zone_for(a)
		if dist >= b.x and dist <= b.y:
			fits.append(n)
	return fits


## Where an attack is delivered from, and how the ogre answers a target that is not in it.
enum Zone {
	STRIKE,      ## the arm alone. The IK adapts and nothing else about the ogre moves
	TURN,        ## the arm and the waist. Right distance, wrong bearing -- it comes round
	REPOSITION,  ## the arm, the waist and the feet. It has to step, and stepping is visible
	WRONG,       ## none of that is enough in the time left. Not this attack
}


## HOW FAR FROM THE SHOULDER THE HEAD CAN LAND, near and far, in metres.
##
## Derived, not dialled. The head sits at radius R along the spoke, and to arrive on the floor at
## horizontal distance D from a shoulder H above it, in a plane whose up axis has vertical component
## p, the swing solves R = sqrt(D^2 + (H/p)^2). Turn that around and D = sqrt(R^2 - (H/p)^2); feed it
## the arm's two limits and the reachable annulus falls out.
##
## This is the whole reason for the zone system. Declared, the slam claimed 2.2 to 5.0 m and the body
## attacked from 5.2; derived, this rig can only land between about 1.0 and 2.6 m. The ogre was
## committing to swings it physically could not make, which is why the arm pinned at full extension
## on every single one and the blow drifted off the telegraph.
func strike_zone() -> Vector2:
	# The maths lives in ReachEnvelope (pure, scene-free, named for the literature); this gathers
	# the live inputs. `beyond` is the head's distance past the fist; the lean term is the
	# shoulder's own travel -- solved from the shoulder, quoted from the body, because "how far
	# away is the player" is measured from the body by every caller.
	return ReachEnvelope.swing_annulus(swing_arm_full(), weapon_length - grip_point.y,
			shoulder_height(), tuning.swing_lean, tuning.swing_arm_min, tuning.swing_arm_max,
			tuning.weapon_clear_radius)



## The player's position pulled into the strike zone: angle first, then distance. What comes back is
## somewhere the ogre can actually hit, and the difference between it and the player is exactly what
## the body has to fix by moving.
func clamp_to_zone(target: Vector3) -> Vector3:
	return ReachEnvelope.clamp_into(global_position, forward(), target, zone_for(_act),
			deg_to_rad(tuning.strike_yaw))


## How far in and out the TURN band reaches past the strike band, for whatever wants to draw it.
## Shared with zone_of on purpose: a picture of a rule drawn from its own copy of the numbers is a
## picture that will one day disagree with the rule.
func turn_reach_bonus() -> float:
	var lunge: float = _act.root_motion.get(1, 0.0) if _act != null else spec(&"slam").root_motion.get(1, 0.0)
	return absf(lunge) * tuning.turn_reach


## HOW MUCH THE OGRE HAS TO DO TO HIT SOMETHING STANDING THERE.
##
## Four answers, and they are nested by the amount of the creature that has to move -- which is the
## useful way to slice it, because each one costs more than the last and each one is a different
## thing to watch for as a player.
##
##   STRIKE      the arm alone. The IK adapts and nothing else moves.
##   TURN        the arm and the waist. Right distance, wrong bearing: it comes round to face you.
##   REPOSITION  the arm, the waist and the feet. It has to step, and stepping is visible.
##   WRONG       none of that is enough in the time left. Not this attack.
##
## The first three are drawn yellow, orange and blue. The bands are not fixed shapes: TURN and
## REPOSITION are TIME BUDGETS -- how far the ogre can swing its bearing, and how far it can carry
## its body, before the mace comes down. So they are wide early in a wind-up and shrink as it runs
## out, which is exactly the information a player needs and cannot otherwise see.
func zone_of(target: Vector3, a: ActionSpec = null) -> Zone:
	var flat := target - global_position
	flat.y = 0.0
	var d := flat.length()
	var z := zone_for(a if a != null else _act)
	var off := absf(forward().signed_angle_to(flat.normalized(), Vector3.UP)) if d > 0.001 else 0.0
	var lim := deg_to_rad(tuning.strike_yaw)
	var t := _aim_time_left(a if a != null else _act)
	# What the body can still buy, in the time it has left.
	var turn_budget: float = yaw_rate(speed) * tuning.aim_turn_boost * t
	# WHAT IT CAN ACTUALLY COVER, and it can RUN. Budgeting the chase at the shuffle speed meant
	# breaking range put you outside every band almost at once, the attack was abandoned, and
	# sprinting away was not merely safe -- it was the single most effective thing a player could do.
	# A creature winding up to hit you does not stand and watch you leave.
	var step_budget: float = maxf(tuning.aim_shuffle, run_speed()) * t
	if d >= z.x and d <= z.y and off <= lim:
		return Zone.STRIKE
	# THE TURN BAND IS WIDER THAN THE STRIKE BAND IN EVERY DIRECTION, not just round the sides. The
	# ogre carries its weight into the blow -- that is the lunge -- so it covers ground on the strike
	# without taking a step, and a player drifting nearer or further is still answerable by leaning
	# and reaching rather than by repositioning. Cut only angularly, the orange band left running
	# straight at or away from the ogre as the cheap escape it always was.
	var lunge: float = _act.root_motion.get(1, 0.0) if _act != null else 0.0
	var reach_in: float = maxf(z.x - absf(lunge) * tuning.turn_reach, 0.0)
	var reach_out: float = z.y + absf(lunge) * tuning.turn_reach
	if d >= reach_in and d <= reach_out and off <= lim + turn_budget:
		return Zone.TURN
	var need_step := 0.0
	if d < z.x:
		need_step = z.x - d
	elif d > z.y:
		need_step = d - z.y
	if need_step <= step_budget and off <= lim + turn_budget:
		return Zone.REPOSITION
	# GIVING UP IS ABOUT THE ROSTER, NOT ABOUT THE DISTANCE. Cancelling because the player has left
	# the band is what made panic-sprinting the correct answer to every telegraph: run, and the
	# wind-up simply evaporated. If some OTHER attack covers where they have got to, this is a
	# handover -- the ogre switches to the one that reaches, and running has bought a rock instead of
	# a mace rather than buying safety. Only when nothing at all reaches them does it stand down.
	#
	# WRONG in both cases; whether a handover follows is the ENEMY's call (its &"abandoned" handler
	# asks actions_reaching() and chooses). This used to answer REPOSITION whenever any attack
	# reached -- which kept the WRONG attack stepping after a player it could never cover, and made
	# the handover both comments promise unreachable: WRONG only fired when NOTHING reached, so the
	# hint the aim computed was empty by construction.
	return Zone.WRONG

## The same budget the zones are cut from, for anything that wants to DRAW them. Idle, it answers
## with a whole wind-up, so the bands show what the ogre could do if it started an attack now
## rather than collapsing to nothing whenever it happens not to be swinging.
func aim_time_budget() -> float:
	if _act != null and _act.is_attack:
		return _aim_time_left(_act)
	return _aim_time_left(spec(&"slam"))


func _aim_time_left(a: ActionSpec = null) -> float:
	var spec: ActionSpec = a if a != null else _act
	if spec == null:
		return 0.0
	var commit := maxf(spec.time_of(&"strike"), 0.01) * tuning.swing_wind_at
	if spec != _act or not is_acting():
		# ASKED ABOUT AN ATTACK THAT HAS NOT STARTED, the answer is its whole wind-up. Returning 0
		# here made every bearing past the shoulder limit answer WRONG, because a creature with no
		# time cannot turn -- so the zone table said the ogre would refuse to attack anything it had
		# to pivot towards, which is not what it does at all.
		return commit + tuning.aim_hold_max
	return maxf(commit - action_t, 0.0) + maxf(tuning.aim_hold_max - _aim_extra, 0.0)


## WHERE THE PLAYER WILL BE WHEN THE MACE ARRIVES, not where they are now.
##
## Aiming at a moving target's CURRENT position is aiming behind it, always, by exactly the distance
## it covers during the wind-up. A player running a circle around the ogre exploits that perfectly
## without even meaning to: the impact point trails them round, permanently one wind-up late, and
## the blow lands in the footprints they left. Leading it puts the circle in FRONT of them, so
## running is answered by the ogre swinging where you are going -- and dodging becomes a decision
## about the moment rather than a jog.
##
## The lead time is the time left until the blow lands, so it needs no tuning to stay right when the
## wind-up is retimed. `aim_lead` scales it: 0 aims at the feet, 1 aims at the full prediction, and
## something short of 1 is usually better, because a perfect lead is unbeatable and reads as psychic.
func _lead_target(player: Node3D, dt: float) -> Vector3:
	var here := player.global_position
	if _track_last == Vector3.INF:
		_track_last = here
	# Measured from the position rather than read off the body, so it works for anything the ogre
	# might have to hit, and smoothed because a single frame's delta is mostly noise.
	var raw := (here - _track_last) / maxf(dt, 0.001)
	raw.y = 0.0
	_track_vel = _track_vel.lerp(raw, 1.0 - exp(-tuning.aim_lead_smooth * dt))
	_track_last = here
	var t_left: float = maxf(_act.time_of(&"strike") - action_t, 0.0)
	return here + _track_vel * t_left * tuning.aim_lead


## THE IMPACT POINT, chasing the player on a spring.
##
## The ogre does not decide where to hit at the start of the swing and then commit blindly, and it
## does not track perfectly either. It leans after the player while it is winding up -- so standing
## still is not a plan -- and then STOPS leaning the moment the mace starts down, which is what makes
## the attack dodgeable at all.
##
## That freeze is the dodge window, and it is a window in TIME rather than a distance: move too early
## and the aim simply follows you across; move too late and you are already under it. The only clean
## answer is to move as the smash begins, which is the moment the animation is loudest about.
func _step_aim(dt: float) -> void:
	if not is_acting() or _act == null or not _act.is_attack:
		_aim_live = false
		_holding = false
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var target := global_position + forward() * zone_for(_act).y
	if player:
		target = _lead_target(player, dt)

	# THE IMPACT POINT IS THE PLAYER, PULLED INTO THE STRIKE ZONE. What comes out is somewhere the
	# ogre can actually hit; the difference between it and the player is exactly what the body has to
	# fix by moving, and that one quantity drives the turning, the stepping and the giving up.
	var want := clamp_to_zone(target)
	if not _aim_live:
		aim_point = want
		_aim_live = true
		return
	var rate: float = tuning.aim_follow if aim_tracking() else tuning.aim_follow_smash
	aim_point = aim_point.lerp(want, 1.0 - exp(-rate * dt))
	# THE KICK AIMS AT A BODY, NOT AT THE FLOOR. The swing's impact point is where the head comes
	# down; the foot's is a point in the air at shin height. Same spring, same commit, different
	# altitude -- and it has to be the same spring, or the two attacks would telegraph differently
	# for no reason the player could learn.
	# WHICH WAY THIS ONE COMES IN, chosen once and then left alone. Picked from where the blow is
	# going relative to the way the ogre is facing: a target off to the right gets a stroke that
	# comes in from the right, one straight ahead gets the overhead chop. Re-picking it mid-swing
	# would roll the plane under a mace already travelling along it, so it is decided while the aim
	# is still live and holds from there.
	if aim_tracking():
		var off := forward().signed_angle_to((aim_point - global_position).normalized(), Vector3.UP)
		swing_side = 0 if absf(off) < deg_to_rad(tuning.swing_centre_arc) else int(signf(off))
	if _act.kick_foot >= 0:
		kick_point = aim_point
		kick_point.y = global_position.y + tuning.kick_height

	if player == null or not aim_tracking():
		return
	var flat := player.global_position - global_position
	flat.y = 0.0
	var d := flat.length()
	if d < 0.01:
		return

	# ONE DISPATCH, FOUR ANSWERS. The zone decides; nothing here re-derives what it already knows.
	zone = zone_of(player.global_position)
	match zone:
		Zone.STRIKE:
			# Right there. The arm does all of it and the body holds still, which is what makes a
			# blow from inside this band feel like it was aimed rather than stumbled into.
			_holding = false
		Zone.TURN:
			# Right distance, wrong bearing. Come round -- the body already turns toward the player
			# every frame under a cap that is raised while aiming, so there is nothing to ask for
			# here but the patience to let it finish.
			_holding = aim_tracking()
			if _aim_extra >= tuning.aim_hold_max:
				_holding = false
		Zone.REPOSITION:
			# Out of range but not out of reach. Step, and keep holding the mace up while stepping,
			# so closing the distance is itself part of the telegraph.
			_turn_and_step(flat, d, dt)
			_holding = aim_tracking()
			if _aim_extra >= tuning.aim_hold_max:
				# OUT OF PATIENCE IS COMMIT, NOT CANCEL. Abandoning here is what made breaking the
				# ogre's range so cheap: step out of the band and the whole wind-up evaporated, with
				# no swing to punish and nothing to dodge. A creature that has committed its weight
				# does not get to take it back because you moved -- it finishes at the best place it
				# can still reach, and misses, and the miss is the opening.
				_holding = false
		Zone.WRONG:
			# Not merely hard -- meaningless. This is the only thing that cancels -- unless the
			# action COMMITS (a throw with the rock already aloft), or the wind-up is past the
			# COMMIT POINT (tuning.commit_past): then it is REPOSITION's out-of-patience doctrine
			# instead -- finish at the best reachable point, and miss. The abandon used to run
			# all the way to the strike, and breaking range a frame before delivery erased a
			# fully-telegraphed blow.
			if _act.commits or action_t >= maxf(_act.time_of(&"strike"), 0.01) * tuning.commit_past:
				_holding = false
			else:
				# CANCEL FIRST, ANNOUNCE SECOND. The emit is synchronous: the enemy's handler may
				# start the follow-up right there -- and when the emit came first, control
				# returned HERE and cancel_action() destroyed the chain it had just started. The
				# order is the fix; do not "tidy" it back.
				#
				# THE SOLVER ONLY REPORTS. It used to name the follow-up too (switch_hint), which
				# put the ogre's tactics inside the animation addon; the enemy now asks
				# actions_reaching() and chooses for itself in its &"abandoned" handler.
				cancel_action()
				action_event.emit(&"abandoned", global_position)


## Turn toward the target and correct the range, both bounded by what the creature can do in a
## second. Only ever while aiming -- once the mace is coming down this stops, or the commitment that
## makes the attack dodgeable would be a lie told at walking pace.
func _turn_and_step(flat: Vector3, d: float, dt: float) -> void:
	var z := zone_for(_act)
	var err := 0.0
	if d < z.x:
		err = d - z.x                                 # negative: give ground
	elif d > z.y:
		err = d - z.y                                 # positive: close
	if absf(err) > 0.05:
		# PROPORTIONAL, not one flat speed. A fixed shuffle is too slow to catch a player who breaks
		# range and too twitchy once it has caught them; scaling it by how far out of band they are
		# closes a big gap fast and settles instead of hunting. Capped, because a heavy creature
		# lunging four metres in a frame is not repositioning, it is teleporting.
		var urgency: float = clampf(absf(err) / maxf(tuning.aim_shuffle_span, 0.1), 0.25, 1.0)
		root_request += flat.normalized() * signf(err) * tuning.aim_shuffle * urgency * dt


## THE PLANE THE SWING LIVES IN, BUILT THROUGH THE PLACE IT HAS TO LAND.
##
## The old plane was a fixed 45 degree tilt off vertical, and everything wrong with the attack came
## out of that one choice. A plane picked before you know where the blow is going does not pass
## through where the blow is going: the head came down 2.9 m to one side, the telegraph had to be
## corrected after the fact to point at it, and the reach had to be solved backwards through a tilt
## that was fighting it.
##
## Turn it around. The impact point is the ruler, so the plane is CONSTRUCTED from it: it contains
## the hinge and the impact point, and the only thing left to choose is the roll about that line.
## That roll is the swing's character -- straight down the middle, or diagonally in from the right or
## the left -- and it changes how the mace arrives without moving where it arrives.
##
## Two things fall out for free. The arc's far end IS the impact point, so the telegraph cannot lie
## about where the blow lands; there is no correction step because there is nothing to correct. And
## the swing is always exactly a quarter turn from the top of the plane to the floor, because `u` is
## built perpendicular to `v` -- no floor angle to solve, no tilt to divide by, no degenerate case
## where the arm cannot reach the ground.
##
##   v -- from the hinge to the impact point. The arc ends here.
##   u -- the in-plane direction nearest straight up. The arc passes through here on the way down.
##   R -- how far the head is from the hinge, which is what the arm has to make up.
func swing_frame(target: Vector3) -> Dictionary:
	var flat := target - global_position
	flat.y = 0.0
	var fwd := flat.normalized() if flat.length_squared() > 0.0001 else forward()
	var hinge := swing_hinge(fwd)
	var to := target - hinge
	var r := to.length()
	var v := to / maxf(r, 0.001)
	# The plane's normal: perpendicular to the swing line, level to start with, then ROLLED about
	# that line to give the stroke its character.
	var n := v.cross(Vector3.UP)
	if n.length_squared() < 0.000001:
		n = side_dir(1)
	n = n.normalized().rotated(v, deg_to_rad(tuning.swing_roll) * float(swing_side))
	var u := n.cross(v).normalized()
	if u.y < 0.0:
		u = -u                                    # the overhead half of the plane, not the buried one
	return {"hinge": hinge, "u": u, "v": v, "r": r}


## WHERE THE SWING TURNS ABOUT, for the swing and the prediction alike.
##
## Authored rather than read off the bone, because the two consumers need it at different moments:
## the prediction is made while the mace is still going up, and the swing happens a second later
## with the trunk driven forward into it. A live reading answers honestly for the instant it is
## asked and differently for each of them, which is exactly what must not happen here.
## A HORIZONTAL SWEEP IS NOT A TILTED PLANE — it is a CONE.
##
## The first version set the impact point a metre off the ground and expected a flat stroke to fall
## out of the existing arc. It does not: the arc swings the spoke through a plane that contains the
## hinge and the target, so raising the target only makes the overhead land higher. The mace still
## came down. It was a shallower chop, not a sweep.
##
## For the head to travel horizontally at a fixed height, the spoke has to keep a fixed ELEVATION
## and rotate about the VERTICAL axis. The head then traces a horizontal circle at that height,
## which is what a sweep is, and what a jump gets above.
##
## Fixed elevation is also what makes the jump honest: the head is at `strike_height` for the whole
## stroke rather than only at the end, so being in the air clears it for the whole stroke too.
func _flat_sweep_dir(hinge: Vector3, radius: float, aim: Vector3, ang: float, wind: float) -> Vector3:
	var flat := aim - hinge
	flat.y = 0.0
	var fwd := flat.normalized() if flat.length_squared() > 0.0001 else forward()
	# The elevation that puts the head at the target's height, given the spoke it is riding on.
	var drop: float = (aim.y - hinge.y) / maxf(radius, 0.01)
	var el := asin(clampf(drop, -1.0, 1.0))
	# WHERE ROUND THE CIRCLE. The stroke arrives ON the aim at contact and continues past it, so the
	# damage window sits in the middle of the travel rather than at the end of it -- a sweep that
	# stopped dead on the target would read as a poke.
	var t: float = (ang - wind) / maxf(LAND_ANG - wind, 0.01)
	var yaw: float = deg_to_rad(tuning.sweep_arc) * (1.0 - t)
	return (fwd.rotated(Vector3.UP, yaw) * cos(el) + Vector3.UP * sin(el)).normalized()


func swing_hinge(fwd: Vector3) -> Vector3:
	return global_position + Vector3.UP * tuning.swing_high + fwd * tuning.swing_lean


func predicted_impact() -> Vector3:
	# NOTHING TO SOLVE ANY MORE. The swing plane is built through the impact point, so the arc ENDS
	# there by construction -- the telegraph and the blow are not two calculations that have to be
	# kept in agreement, they are the same point. Every version of this before now solved the arc a
	# second time and then argued with itself about hinges, tilts and leans.
	var target := aim_point if _aim_live else global_position + forward() * strike_zone().y
	# CLAMPED ONLY WHILE IT IS STILL AIMING. The clamp is relative to where the body IS, so once the
	# ogre commits and drives its weight forward, re-clamping every frame drags the target along with
	# it -- the disc freezes, the swing does not, and they part company by exactly the distance the
	# ogre travels. After the commit the impact point is a place in the WORLD, and the arm reaches
	# for it. That is also what makes the commit mean anything: a target that follows the body is not
	# frozen, whatever the aim spring is set to.
	if aim_tracking():
		target = clamp_to_zone(target)
	# AT THE ACTION'S OWN HEIGHT. An overhead arrives on the floor; a sweep arrives at waist height
	# and travels flat, which is what a player in the air is above. The arc solves a plane through
	# whatever point it is given, so raising the point is the entire difference between the two --
	# no second code path, and the volume that misses a jumping player is the one they can see pass
	# underneath them.
	var h: float = _act.strike_height if _act != null else 0.0
	return Vector3(target.x, global_position.y + h, target.z)


func aim_tracking() -> bool:
	if not is_acting() or _act == null:
		return false
	return action_t < maxf(_act.time_of(&"strike"), 0.01) * tuning.swing_wind_at


## The spec behind a named action, so the body can read its radius and damage without a second copy
## of those numbers living somewhere else.
func spec(n: StringName) -> ActionSpec:
	return _actions.get(n)


## The node a carried thing hangs off. The mace is already parented here, so a rock picked up rides
## in exactly the same place without anyone having to agree on a second socket.
func grip_node() -> Node3D:
	return _grip


## Drive the weapon to the aim the active poses ask for, and hang it off the hand at the grip.
##
## Called from _process, and safe there ONLY because the grip is top_level and this reads the IK
## layer's end-of-pass snapshot rather than the skeleton. The first version did neither: it wrote a
## transform that had to be resolved against the BoneAttachment, which forced the skeleton to update
## outside the modifier pass, the layers ran against a pose that had already moved, and it surfaced
## as foot skate at walking pace -- two systems away from anything to do with a weapon.
##
## Original note, still true: It is a node transform rather than a bone, so a
## modifier is the wrong place for it -- but doing it on the idle frame is worse: writing to a
## BoneAttachment3D child forces the skeleton to update outside the modifier pass, the layers run
## against a pose that has already moved, and it comes back as foot skate at walking speed. Every
## piece of this system that touches the skeleton belongs on the same clock.
## Set false to prove whether the weapon's transform is disturbing the skeleton. See probe --noaim.
var aim_weapon := true

func _process(dt: float) -> void:
	_aim_weapon(dt)


func _aim_weapon(dt: float) -> void:
	if _grip == null or not _ready_ok or not aim_weapon:
		return
	grip_point = grip_local(tuning.grip_right)
	off_point = grip_local(tuning.grip_left)

	# THE MACE LEADS. Its path is authored and the arms are solved onto it -- see ActionSpec.
	# mace_leads and _swing_arc(). Everything below this is the other direction, where the weapon
	# hangs off a hand, and it is still what carrying and the non-clip actions use.
	if _act != null and _act.mace_leads and is_acting():
		_grip.global_transform = _swing_arc()
		weapon_dir = _grip.global_basis.y.normalized()
		_anchor_bone = "Body"
		_anchor_at = _grip.global_position
		clear_degrees = 0.0
		_w_prev = _grip.global_basis
		# The swing returns early, and this is the one branch where the weapon CAN be dropped -- the
		# hands have to reach it here rather than being welded to it. Leaving the check below the
		# return meant it never ran in the only case it applies to.
		if dt > 0.0 and _grip_last != Vector3.ZERO:
			_grip_vel = (_grip.global_position - _grip_last) / dt
		_grip_last = _grip.global_position
		_check_dropped(dt)
		return

	# Blend the weapon's placement across whatever poses are active. Position blends linearly;
	# ROTATION blends as quaternions, because a mace swings through 140 degrees between the wind-up
	# and the strike and averaging Euler angles across that arc takes it the wrong way round.
	var anchor := "RightHand"
	var pos := Vector3.ZERO
	var rot := Quaternion.IDENTITY
	var total := 0.0
	var best_w := -1.0
	for n in pose_weights:
		var w: float = pose_weights[n]
		if w <= 0.001:
			continue
		var wp: Dictionary = poses.weapon_of(n)
		pos += (wp["pos"] as Vector3) * w
		var q := Basis.from_euler((wp["rot"] as Vector3) * (PI / 180.0), EULER_ORDER_XYZ) \
				.get_rotation_quaternion()
		rot = q if total <= 0.001 else rot.slerp(q, w / (total + w))
		total += w
		# The anchor is a NAME and names do not average. The dominant pose owns it, which means a
		# weapon changes hands at the point one pose takes over rather than smearing between them.
		if w > best_w:
			best_w = w
			anchor = wp["bone"]
	if total > 0.001:
		pos /= total
	else:
		var wp: Dictionary = poses.weapon_of(carrying if carrying != &"" else &"carry")
		anchor = wp["bone"]
		pos = wp["pos"]
		rot = Basis.from_euler((wp["rot"] as Vector3) * (PI / 180.0), EULER_ORDER_XYZ) \
				.get_rotation_quaternion()

	# Into world space through the body's own frame, so a placement authored facing one way is
	# correct facing any other.
	var body := Basis(Vector3.UP, facing)
	var pts := arm_ik.bone_positions() if arm_ik else PackedVector3Array()
	var at := global_position + Vector3.UP * (leg_length * 1.35)
	if anchor == "Body":
		# Placed on the creature rather than in a fist. The reference is the body's own origin, so
		# the mace stays put relative to the ogre while the arms come to IT.
		at = global_position
	else:
		var bi := bone(anchor)
		if bi >= 0 and bi < pts.size():
			at = pts[bi]
	_anchor_at = at
	_anchor_bone = anchor

	# EASE THE PLACEMENT, NOT THE ANCHOR. The pose-relative offset and rotation are smoothed so a
	# mace does not teleport between poses; the anchor's own motion is then applied on top with no
	# lag at all. Easing the final world transform instead made the weapon swim behind the hand
	# holding it — the fist moved, the mace followed a few frames later, and the two visibly ran out
	# of step. A weapon that lags the hand gripping it is not attached to it.
	var k := 1.0 if posing else 1.0 - exp(-tuning.weapon_aim_speed * dt)
	_w_pos = _w_pos.lerp(pos, k)
	_w_rot = _w_rot.slerp(rot, k)

	# THE OFFSET IS IN THE WEAPON'S OWN FRAME, NOT THE BODY'S -- which is what keeps the mace in the
	# fist. Authored as (0, -0.65, 0) it means "the hand grips 0.65 m up the haft", and because the
	# shaft is the weapon's local +Y, that stays 0.65 m up the haft through a 140-degree swing.
	#
	# In the body frame it meant "0.65 m below the hand in world terms", which is only ON the shaft
	# while the mace happens to point straight up. Through a slam the hand ended up 0.68 m off the
	# shaft's axis -- the mace visibly left the hand at the top of the wind-up and swung beside it.
	# Translation is still free (give the offset an X or Z component and the grip moves off-axis on
	# purpose); it is the DEFAULT that is now glued rather than coincidental.
	var wb := body * Basis(_w_rot)

	# THE MACE FOLLOWS THE FIST WHEN A CLIP IS SWINGING IT.
	#
	# The authored `rot` above is body-relative, and while POSES drove the arm that was right: the
	# same pose set the shoulder and the weapon, so the hand and the shaft agreed by construction.
	# A clip breaks that. It swings the hand through its own arc on its own schedule while the aim
	# still interpolates between poses, the two come apart, and the mace ends up pointing somewhere
	# the fist is not -- which then drags the off hand, solving onto that shaft, into the ogre's
	# chest.
	#
	# So where the clip owns the arm, the weapon is rigid to the hand instead: the fist's measured
	# orientation times the grip taken from the carry pose. The two are slerped by the same share,
	# which means mix_weapon reads as what it says -- 0 is held, 1 is aimed, between is between.
	# AN AUTHORED CLIP LEAVES THE WEAPON ALONE. The fist-follow branch below exists for a
	# BORROWED clip, whose hand arc never knew this weapon; an action's own clip recorded the
	# weapon moving on the pose-aim path, with the arm IK solved onto it, so the identity playback
	# is that same path untouched. Engaging fist-follow here sent the mace somewhere the recording
	# never put it, and the off-hand IK reached 100-odd degrees after it at the fade-out.
	var share: float = 0.0 if clip_authored() 			else (clip_layer.clip_share(anchor) if clip_layer else 0.0)
	if share > 0.001 and arm_ik:
		var ih := bone(anchor)
		if ih >= 0:
			var fist := (arm_ik.bone_basis(ih).orthonormalized() * _grip_rest).orthonormalized()
			wb = Basis(wb.get_rotation_quaternion().slerp(fist.get_rotation_quaternion(),
					share * clip_layer.share_of("weapon")))

	# AND SLIDE THE GRIP TO THE BUTT while the clip has it. Along the shaft only -- the direction is
	# untouched, so the head still lands exactly where the swing sends it, and only the stub that was
	# ending up inside the ogre is taken away.
	var pos_used := _w_pos.lerp(Vector3(0.0, -tuning.clip_grip, 0.0), share)

	# AND THEN REFUSE TO PUT IT THROUGH THE OGRE. The clip proposes the weapon's aim; this is where
	# the solver declines the proposals that are not physically available -- the same bargain the
	# feet get from the foot IK, applied to four metres of iron.
	#
	# BEFORE THE GRIP, and that ordering has now been wrong in both directions, so here is the whole
	# argument. Run LAST it vetoes the grip yield -- and with the ogre actually walking that cost the
	# left hand its hold on 190 frames out of 360, snapping the palm at 22 m/s and the elbow at 23.
	# Run FIRST it lets the yield turn the mace back inboard, which is the hug.
	#
	# First is right now only because the yield became small: with the clavicle free to swing
	# (OgreArmIk.shoulder_assist) the turn needed fell from 17 degrees to about 5, so what it undoes
	# of this correction is a few centimetres rather than a quarter of a metre. The grip is the thing
	# being looked at; the clearance is a safety net that can afford to give a little.
	#
	# It is needed because a clip cannot know what it is holding. The animator swung a sword, and a
	# sword's arc through a wrist that tucks toward the chest on the recovery is fine. Give the same
	# wrist a mace as long as the creature is tall and the shaft leaves the fist straight through the
	# ribs -- which is exactly what it did, most visibly after the strike, where the mace disappeared
	# inside the body and came out the other side.
	# ITERATED, because the constraint is not linear. Turning the shaft changes WHICH point on it is
	# closest to the trunk, and the grip rides on the weapon's own basis so the whole segment shifts
	# when the aim does. One pass got a deep intrusion most of the way out and left up to 0.59 m of
	# mace inside the ogre; three passes converge on the frames that matter and cost nothing.
	var before := wb.y.normalized()
	for _pass in 3:
		var dir := wb.y.normalized()
		var clear := _clear_of_body(at + wb * pos_used, dir)
		if clear.is_equal_approx(dir):
			break
		wb = Basis(Quaternion(dir, clear)) * wb
	# CLAMPED. Whatever the geometry wants, the weapon is only ever nudged -- see
	# OgreTuning.weapon_clear_max. Past that limit the correction stops being a safety net and starts
	# being the animator, and it is a much worse one.
	var pushed := rad_to_deg(before.angle_to(wb.y.normalized()))
	var cap := tuning.weapon_clear_max
	if pushed > cap and pushed > 0.001:
		wb = Basis(Quaternion(before, wb.y.normalized()).slerp(Quaternion.IDENTITY,
				1.0 - cap / pushed)) * Basis(Quaternion(wb.y.normalized(), before)) * wb
		pushed = cap
	clear_degrees = pushed
	# MACE TO HAND. Not attacking, so the HAND is the authority and the weapon hangs off it -- and
	# "hangs off it" means the mace's own grip point sits ON THE PALM, exactly, by construction.
	#
	# It used to be placed from the ANCHOR BONE plus an authored offset, and the anchor bone is the
	# wrist. Nothing in that ever required the grip point to end up on the palm, so it did not: the
	# marker on the shaft and the marker on the hand sat a hand's width apart and no amount of
	# tuning the offset would have closed them, because the offset was answering a different
	# question. Solving for the placement that puts them together answers this one.
	#
	# The authored rotation still aims the weapon; only its POSITION is now derived.
	#
	# (During an attack the arrow points the other way -- the mace leads and the arms are solved onto
	# it, which is _swing_arc above. Which way the glue runs depends on who is in charge.)
	var side := 1 if _anchor_bone.begins_with("Right") else 0
	if arm_ik and _anchor_bone != "Body":
		var palm: Vector3 = arm_ik.palm_position(side)
		if palm != Vector3.ZERO:
			at = palm
			pos_used = -grip_point
			wb = _yield_to_off_hand(at, wb)
			# The glue moved the anchor to the palm, so the clearance check below must test the
			# shaft from where it now actually is.
			pos_used = -grip_point

	# A RATE LIMIT, because nothing this heavy changes direction instantly.
	#
	# It is also a backstop against every discontinuity upstream at once. Blending two orientations
	# that are most of a half-turn apart, on a weight that is itself moving, produces frames where
	# the aim crosses 45 degrees in a single tick -- 2700 deg/s, which is not a swing, it is a
	# teleport, and it reads as the mace snapping to the other side of the ogre. The clip's own
	# fastest motion measures about 1100 deg/s (tools/scan_clip.gd), so a ceiling above that leaves
	# the real swing untouched and takes the teleports out.
	if _w_prev != Basis():
		var moved := _w_prev.y.angle_to(wb.y)
		var turn_cap := deg_to_rad(tuning.weapon_turn_max) * maxf(dt, 0.0001)
		if moved > turn_cap and moved > 0.0001:
			wb = Basis(_w_prev.get_rotation_quaternion().slerp(
					wb.get_rotation_quaternion(), turn_cap / moved))
	_w_prev = wb

	var placed := at + wb * pos_used
	if dt > 0.0 and _grip_last != Vector3.ZERO:
		_grip_vel = (placed - _grip_last) / dt
	_grip_last = placed
	_grip.global_transform = Transform3D(wb, placed)
	_check_dropped(dt)
	weapon_dir = _grip.global_basis.y.normalized()


## A point on the shaft in WORLD space, `along` metres up from the BUTT (the weapon's own origin).
## The off hand solves to one of these.
func haft_world(along: float) -> Vector3:
	if _grip == null:
		return global_position
	# CLAMPED TO THE WEAPON. `along` is composed from a grip position plus an off-hand offset, and
	# those add up to points that are not on the mace: with the grip slid to the butt, the off hand
	# was asking for -0.47 m, half a metre off the end of it, and reaching into empty air.
	return _grip.global_position + _grip.global_basis.y.normalized() 			* clampf(along, 0.0, weapon_length)


## WHEN NOTHING IS HOLDING IT, IT FALLS.
##
## The grips can fail honestly -- a target out of the arm's reach is refused rather than lunged at,
## which is the right call and leaves the hand where it is. What was wrong was what happened next:
## nothing. The mace went on being carried by a fist that was not touching it, hanging in the air on
## the strength of a transform.
##
## So losing every grip has a consequence. Held by nothing for drop_after seconds, the weapon stops
## being animated and becomes what it actually is: four metres of iron with a velocity, falling.
func _check_dropped(dt: float) -> void:
	if _weapon == null or carrying == &"" or arm_ik == null or dt <= 0.0:
		return
	# POSING IS NOT LETTING GO. The pose editor drops the grip IK to zero on purpose, so that an arm
	# can be posed without being immediately hauled back onto the haft. Read as "nothing is holding
	# the mace" that put the weapon on the floor the moment F4 was pressed, which is the one time you
	# most need it in the hand.
	if posing:
		_ungripped = 0.0
		return
	# WHILE CARRYING, THE ANCHOR HAND IS HOLDING IT BY CONSTRUCTION. The mace is placed so its grip
	# point IS that palm -- there is no IK involved, and so no grip strength to read. Taking the
	# maximum across both hands therefore asked only the OFF hand, and the moment that one let go
	# the weapon fell out of a fist it was welded to.
	#
	# Dropping is a question for when the hands have to REACH the weapon, which is when the mace
	# leads. Nothing can be dropped that is being carried.
	if _anchor_bone != "Body":
		_ungripped = 0.0
		return
	# NOBODY IS HOLDING IT means both switches are off -- not that the IK's grip strength happens to
	# have fallen low this frame. Reading the strength made the drop a consequence of the reach rule
	# as well: the mace fell whenever the solve got weak, which included opening the pose editor and
	# simply walking with the second hand out of span.
	if gripping(0) or gripping(1):
		_ungripped = 0.0
		return
	_ungripped += dt
	if _ungripped >= tuning.drop_after:
		drop_weapon()


## Hand the mace over to the physics engine, where it belongs once nobody is holding it.
##
## Built in code rather than as a scene, the way rock.gd builds its own mesh: the collision is two
## primitives that describe a mace -- a cylinder for the haft and a sphere at the head -- and the
## visual is the very node that was being carried, reparented rather than duplicated, so what lands
## on the floor is the same object that was in the fist.
func drop_weapon() -> Node3D:
	if _weapon == null or _grip == null:
		return null
	grip_held[0] = false
	grip_held[1] = false
	var w := _weapon
	var xf := _grip.global_transform

	var rb := RigidBody3D.new()
	rb.name = "DroppedMace"
	rb.mass = tuning.weapon_mass
	rb.collision_layer = 1
	rb.collision_mask = 1
	var haft := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = weapon_length
	cyl.radius = 0.16
	haft.shape = cyl
	haft.position = Vector3(0.0, weapon_length * 0.5, 0.0)
	rb.add_child(haft)
	var head := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.42
	head.shape = sph
	head.position = Vector3(0.0, weapon_length, 0.0)
	rb.add_child(head)

	_weapon = null
	carrying = &""
	_ungripped = 0.0
	w.get_parent().remove_child(w)
	rb.add_child(w)
	w.transform = Transform3D.IDENTITY
	var host := get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(rb)
	rb.global_transform = xf
	# It leaves with the speed it had. A weapon that drops from rest looks placed, not lost.
	rb.linear_velocity = _grip_vel.limit_length(20.0)
	weapon_dropped.emit(xf.origin)
	return rb


## THE DAMAGE IS ON THE MACE, not on a box in front of the ogre.
##
## A fixed volume on the body is a lie about a weapon this size: it is the same shape whether the
## mace is overhead, behind, or buried in the floor. Hung on the head, the damage is wherever the
## head actually is -- which is also the thing the player has been watching for the whole wind-up.
##
## Built in code with the weapon, so it cannot be forgotten in a scene, and parented to the grip so
## it rides the swing for free. HitBox draws its own volume under F3.
## THE DAMAGE ON THE FOOT, built the way the mace's is built and moved the same way.
##
## A node that rides the foot rather than a box bolted to the body: what hurts you has to be the
## thing that arrives, or the kick is a timer with an animation playing near it.
func _attach_kick_hitbox() -> void:
	if kick_hitbox != null:
		return
	_kick_node = Node3D.new()
	_kick_node.name = "KickFoot"
	_kick_node.top_level = true                       # driven in world space, like the grip
	add_child(_kick_node)
	kick_hitbox = HitBox.new()
	kick_hitbox.name = "KickHitBox"
	kick_hitbox.collision_layer = 0
	kick_hitbox.collision_mask = 2
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = tuning.kick_hit_radius
	cs.shape = sp
	kick_hitbox.add_child(cs)
	kick_hitbox.hit_vfx = HIT_SPARK
	_kick_node.add_child(kick_hitbox)
	kick_hitbox.dealt_hit.connect(_on_dealt_hit)


## WHICH VOLUME DELIVERS THE RUNNING ATTACK. One question, one answer -- the body should never have
## to know that a kick hurts with a foot and a slam hurts with a mace.
func strike_hitbox() -> HitBox:
	if _act != null and _act.kick_foot >= 0:
		return kick_hitbox
	return mace_hitbox


func _attach_mace_hitbox() -> void:
	if _grip == null or mace_hitbox != null:
		return
	mace_hitbox = HitBox.new()
	mace_hitbox.name = "MaceHitBox"
	mace_hitbox.collision_layer = 0
	mace_hitbox.collision_mask = 2
	mace_hitbox.hit_vfx = HIT_SPARK
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = tuning.mace_hit_radius
	cs.shape = sp
	cs.position = Vector3(0.0, weapon_length, 0.0)
	mace_hitbox.add_child(cs)
	# AND THE SHAFT, on the SAME volume rather than a second one.
	#
	# The head is where the blow is aimed, but the haft is most of the weapon and it sweeps the
	# whole middle of the arc -- with a ball on the end and nothing else, stepping inside the head
	# let the swing pass through the player, which reads as the attack missing when it plainly did
	# not. `_grip` is the BUTT of the mace and the shaft runs up its +Y to the head, which is the
	# same axis drop_weapon() builds its haft cylinder on, so the two descriptions of the weapon
	# agree.
	#
	# One HitBox, two shapes, deliberately: HitBox clears `_already_hit` per activate(), so a swing
	# that touches the player with both the shaft and the head still bills them once. Two separate
	# volumes would hit twice. It also means the shaft is live exactly when the head is -- the
	# damage window the action already opens -- and needs no arming of its own.
	var shaft_h: float = weapon_length * (1.0 - tuning.mace_shaft_from)
	if shaft_h > 0.01:
		var scs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.height = shaft_h
		cyl.radius = tuning.mace_shaft_radius
		scs.shape = cyl
		scs.position = Vector3(0.0, weapon_length - shaft_h * 0.5, 0.0)
		mace_hitbox.add_child(scs)
	_grip.add_child(mace_hitbox)
	mace_hitbox.dealt_hit.connect(_on_dealt_hit)


## Put the weapon away, or bring it back. Hidden rather than freed: the socket, the grip transform
## and the off-hand IK target all stay exactly where they were, so picking the mace back up costs
## nothing and cannot come back subtly misaligned.
func show_weapon(v: bool) -> void:
	if _weapon:
		_weapon.visible = v


## How far into the running action a named beat falls, in seconds. The body reads this so its
## gameplay timing comes FROM the animation rather than being guessed alongside it -- the same move
## enemy.gd makes when it takes `strike` from the clip instead of hard-coding 0.45.
func action_time(n: StringName, ev: StringName) -> float:
	var a: ActionSpec = _actions.get(n)
	return 0.0 if a == null else a.time_of(ev)


## Is the running action one-handed? The off hand does not grip if so.
func one_handed() -> bool:
	return _act != null and _act.one_handed and is_acting()


## HOW COMMITTED THIS ARM IS TO THE WEAPON, 0 to 1. Asked by the gait so it can stop swinging an
## arm that is holding something.
##
## Answered from INTENT, not from the achieved grip. Reading the IK's grip strength would close a
## loop with no way out: the arm swings, so the haft goes out of reach, so the grip reads zero, so
## the arm keeps swinging. While the mace is carried both hands are meant to be on it, and that is
## the fact the gait needs.
func hold_influence(bone: String) -> float:
	if carrying == &"" or _weapon == null:
		return 0.0
	return 1.0 if bone.contains("Arm") or bone.contains("Hand") else 0.0


## How much of a bone is currently owned by a pose. The gait layer backs its own contribution off by
## this, so an arm being swung overhead is not simultaneously being swung by the walk cycle.
func pose_influence(bone: String) -> float:
	var w := 0.0
	for n in pose_weights:
		if poses.bones_of(n).has(bone):
			w += float(pose_weights[n])
	# The clip counts too. Two systems writing the same shoulder do not average into something
	# better -- they cancel into mush, which is what the arm swing and a swing animation did to each
	# other before this line existed.
	if clip_layer:
		w += clip_layer.influence(bone)
	return clampf(w, 0.0, 1.0)


## Metres of root motion the action wants applied, taken once. The body adds it to its velocity --
## never a teleport, so it still collides with the world and can be stopped by a wall.
func consume_root_motion() -> Vector3:
	var r := root_request
	root_request = Vector3.ZERO
	return r


func _step_action(delta: float) -> void:
	pose_weights = {}
	stance_lock = false
	if _act == null:
		if preview_pose != &"" and poses.has_pose(preview_pose):
			pose_weights[String(preview_pose)] = 1.0
		elif carrying != &"" and poses.has_pose(carrying):
			# Nothing running: hold the carry pose if the ogre has something in its hands, so it
			# does not stand around with its arms hanging while shouldering a four-metre mace.
			pose_weights[String(carrying)] = 1.0
		return

	# THE HOLD AT THE TOP STOPS THE CLOCK -- all of it. Stretching only the arc's plateau (the first
	# version of this) left the beats running on the old schedule, so the damage opened with the mace
	# still overhead: the head was 5.86 m up and 5.4 m from the disc it had promised. The telegraph
	# and the blow have to stay the same equation, and that means the same clock. Freeze it and the
	# phases, the beats, the damage window and the arc all wait together.
	if _holding and _aim_extra < tuning.aim_hold_max:
		_aim_extra += delta
	else:
		_holding = false
		action_t += delta
		_phase_t += delta

	# The clip runs on the ACTION'S clock, not its own. Its weight follows the pose blend, so it
	# fades in over the wind-up and out through the recovery rather than snapping on -- and because
	# it shares a clock with the beats, its contact frame and the damage window cannot drift.
	if clip_layer:
		if _act.clip != null:
			# PINNED AT CONTACT. Both clocks are measured from the instant the weapon lands, so the
			# clip's impact frame and the beat that opens the hitbox are the same moment by
			# construction rather than by a matching pair of offsets someone has to keep in step.
			clip_layer.clip = _act.clip
			clip_layer.time = clampf(
					_act.clip_contact + (action_t - _act.time_of(&"strike")) * _act.clip_speed,
					0.0, _act.clip.length - 0.001)
			# NO RAMP FOR AN AUTHORED CLIP. The fade exists so a BORROWED clip's frame one does
			# not teleport the upper body; an action's own clip begins and ends at the carry
			# stance the body is already in, by construction. And the ramp cannot be kept for
			# free: mid-fade the clip is slerped against a HALF-strength live pose, which lands at
			# neither -- played back over its own recording that read as the off-arm missing by a
			# hundred degrees through the fade-out.
			clip_layer.weight = 1.0 if _act.clip_authored else _clip_weight()
		else:
			clip_layer.weight = 0.0
	var ph: ActionSpec.Phase = _act.phases[_phase_i]

	# The blend, then the hold. `f` is how far into this phase's pose we are.
	var f := 1.0 if ph.blend <= 0.0 else clampf(_phase_t / ph.blend, 0.0, 1.0)
	f = _ease(ph.ease, f)
	var from: StringName = _prev_pose
	if from == &"" and carrying != &"":
		from = carrying                      # blend out of the carry, not out of nothing
	if from != &"" and poses.has_pose(from) and f < 1.0:
		pose_weights[String(from)] = 1.0 - f
	if ph.pose != &"" and poses.has_pose(ph.pose):
		pose_weights[String(ph.pose)] = f
	elif carrying != &"" and poses.has_pose(carrying):
		# An empty pose name means "return to normal", which for a creature holding something means
		# the carry pose rather than the bare rest pose.
		pose_weights[String(carrying)] = f

	stance_lock = _act.planted.has(_phase_i)

	# Root motion is spread across the phase's blend rather than dumped in one frame: a lunge is a
	# shove that lasts, and a single-frame impulse reads as a teleport no matter how big it is.
	if _act.root_motion.has(_phase_i) and ph.blend > 0.0 and _phase_t <= ph.blend:
		var metres: float = _act.root_motion[_phase_i]
		root_request += forward() * (metres * delta / ph.blend)

	_beats()

	if _phase_t >= ph.total():
		_prev_pose = ph.pose
		_phase_t -= ph.total()
		_phase_i += 1
		if _phase_i >= _act.phases.size():
			_act = null
			action = &""
			_phase_i = -1
			_prev_pose = &""
			if clip_layer:
				clip_layer.weight = 0.0


## Everything that happens at a moment rather than over one: the beat events, the damage window, and
## the impact -- shake, hitstop, the hip dropping under the blow, dust, and the ground slam.
## How much of the clip is showing. Ramped in and out at the ends so the authored pose arrives from
## the carry stance and returns to it, instead of the upper body teleporting into frame one.
func _clip_weight() -> float:
	var total := maxf(action_len, 0.01)
	var t := action_t / total
	var fade := 0.12
	return clampf(minf(t / fade, (1.0 - t) / fade), 0.0, 1.0)


func _beats() -> void:
	var ph: ActionSpec.Phase = _act.phases[_phase_i]
	if ph.event != &"" and not _fired.has(ph.event) and _phase_t >= ph.blend:
		_fired[ph.event] = true
		action_event.emit(ph.event, global_position)
		if ph.event == &"strike":
			_impact()

	# ONCE PER ACTION. Without `_hit_done` the window re-opens on the very next frame -- the close
	# clears `_hit_open`, and `action_t >= hit_at` is still true -- so the damage volume flickers
	# open and shut about thirty times per swing. HitBox clears its already-hit list on every
	# activate(), so that is not a cosmetic flicker: it is one swing able to damage the player over
	# and over. Measured at 96 opens across 3 attacks before this.
	if not _hit_done and not _hit_open and action_t >= _act.hit_at and not _act.damage_from_ring:
		# WHEN THE RING IS THE ATTACK, THE MACE IS THEATRE. `damage_from_ring` promised exactly
		# that ("the ring carries the damage rather than the mace head does") and nothing here ever
		# read it — the pound's ring detonated AND the mace window opened, two damage sources for
		# one blow, standing on opposite sides of the code base.
		#
		# THE ACTION'S OWN DAMAGE, applied to whichever volume is about to open. The specs have
		# carried `damage` since they were written and NOTHING EVER READ IT: the hitboxes are built
		# in code and never assigned one, so every attack this creature has ever thrown -- the
		# two-metre overhead slam included -- dealt HitBox's default 1. It threatened about 0.3
		# damage a second while the player dealt 2.
		var hb := strike_hitbox()
		if hb:
			hb.damage = _act.damage
			hb.set_meta("knockback", _act.knockback)
			# THE SOLVER ARMS ITS OWN VOLUME. It used to be armed by the enemy's beat handler,
			# gated on the AI enum — while the close was ungated. Two authorities over one window
			# meant an interrupt could strand a volume open. One owner now, on one clock; gameplay
			# keeps its veto through `may_damage`.
			if not may_damage.is_valid() or bool(may_damage.call()):
				hb.activate()
				_open_hb = hb
		_hit_open = true
		action_event.emit(&"hit_open", global_position)
	elif _hit_open and action_t >= _act.hit_at + _act.hit_for:
		_hit_open = false
		_hit_done = true
		_close_window()


## Disarm whatever volume this action armed, and say so. Deactivates the REMEMBERED hitbox rather
## than asking strike_hitbox() again — by interrupt time the answer can already be the next
## action's volume, which is exactly the swap that used to strand a kick's box live.
func _close_window() -> void:
	if _open_hb != null and is_instance_valid(_open_hb):
		_open_hb.deactivate()
	_open_hb = null
	action_event.emit(&"hit_close", global_position)


## The follow-through. A four-metre mace arriving is not a damage event with a sound on it -- the
## hip drops, the screen jolts, the ground comes up, and time hesitates. Fired together, on one
## frame, because that is what makes a blow feel like it had mass behind it.
## THE MACE ARRIVING SOMEWHERE. Fired on the beat, so it happens whether or not it found you.
##
## What belongs here is only what a four-metre mace hitting the GROUND does: dust, the hip dropping
## under it, and a knock through the floor. What does NOT belong here is hitstop, and most of the
## shake -- see _on_dealt_hit. Everything used to fire here, identically for a hit and a whiff, which
## made the loudest feedback in the game carry no information at all: you could not tell from the
## screen whether you had just been hit, and the recovery this is supposed to open was announced by
## a full-screen freeze that also played when the ogre swung at nothing.
func _impact() -> void:
	if _act.hip_drop > 0.0:
		hip_spring.impulse(-_act.hip_drop * tuning.hip_omega * 0.5)
	if _feedback and _act.shake > 0.0:
		_feedback.beat_shake(_act.shake * tuning.whiff_shake)
	var at := global_position + forward() * (max_reach * 1.4)
	if _feedback and _act.dust > 0.0:
		_feedback.beat_dust(at, _act.dust)
	if _act.slam_radius > 0.0:
		action_event.emit(&"slam_impact", at)


## IT ACTUALLY HIT SOMEONE. The only place hitstop is allowed to fire.
##
## Hitstop is the one effect that operates on the ANIMATION rather than around it -- it stops the
## arc dead at the moment of contact, which is what sells that the contact happened. Spent on a
## whiff it says nothing; spent here it is the difference between the two, and it costs nothing to
## move because the signal was already there and unconnected.
func _on_dealt_hit(_target: Node, at: Vector3, applied: int) -> void:
	if _act == null:
		return
	# A blocked or i-framed contact applied nothing. It used to fire the full hitstop, the full
	# impact shake and a hit spark anyway — on top of the block's own feedback — so the screen
	# said "that landed" about a blow the player had just successfully refused.
	if applied <= 0:
		return
	if _feedback:
		_feedback.contact_landed(_act.hitstop, 0.06, _act.shake * (1.0 - tuning.whiff_shake))
	action_event.emit(&"landed", at)


func _ease(kind: String, t: float) -> float:
	match kind:
		"slow_in":
			return t * t                          # loads into the next beat
		"snap":
			return 1.0 - pow(1.0 - t, 3.0)        # arrives hard, then decelerates
		"settle":
			return smoothstep(0.0, 1.0, t)
	return t


## The gait law. Stride and cadence come from the Froude number rather than from sliders, which is
## what makes a four-metre creature move like one instead of like a slowed-down person.
func _step_gait(delta: float) -> void:
	var run_at := run_speed()
	if speed < 0.12:
		gait = Gait.IDLE
	elif speed < run_at:
		gait = Gait.WALK
	else:
		gait = Gait.RUN

	# Alexander's relation: relative stride length grows as Fr^0.3. Floored so a creeping ogre does
	# not ask for an infinitely short step taken infinitely often.
	var fr := maxf(froude, 0.02)
	stride = maxf(ALEXANDER_A * pow(fr, ALEXANDER_B) * leg_length * tuning.stride_gain, 0.25)

	# Duty factor: more of the cycle on the ground the slower it goes, and NEVER below the floor.
	# That floor is the mass rule — under 0.5, both feet leave the ground at once.
	duty = clampf(0.75 - 0.30 * sqrt(fr) + tuning.duty_bias, tuning.duty_floor, 0.9)
	double_support = maxf(0.0, 2.0 * duty - 1.0)

	_reach_budget(delta)
	stride_freq = (speed / stride) * tuning.cadence_gain

	if posing:
		pass                     # phase frozen: no stride advances while the editor is open
	elif stance_lock:
		# An action has both feet planted. Freezing the PHASE (rather than just forcing STANCE) is
		# what makes the ogre drive through a swing instead of walking out from under it, and the
		# planted feet are most of what makes the blow read as heavy.
		pass
	elif gait == Gait.IDLE:
		# Do not freeze mid-stride — that leaves the ogre standing on one leg. Unwind to phase 0,
		# which is both feet planted, and stop there.
		if phase > 0.02:
			phase = fmod(phase + delta * 0.4, 1.0)
			if phase > 0.97 or phase < 0.02:
				phase = 0.0
	else:
		phase = fposmod(phase + stride_freq * delta, 1.0)


## THE REACH BUDGET — where the gait law stops being the whole story and the creature's own legs
## get a say.
##
## This ogre is nearly straight-legged at rest: the hip joint sits 2.04 m up, the ankle 0.47 m, and
## the leg chain is only 1.64 m long. That leaves sqrt(1.60^2 - 1.57^2) = THIRTY-ONE CENTIMETRES of
## forward reach — against a stride that wants a metre. Left alone the IK simply clamps at full
## extension every frame, the knees never bend, and the feet ride along with the body. That is not a
## subtle degradation; it is the difference between walking and being dragged.
##
## The answer is the one a real animal uses: BEND THE KNEES. Lowering the pelvis trades height for
## reach, and the trade is exact —
##
##     reach = sqrt(R^2 - (hip_height - ankle_height)^2)      R = the leg chain, less a safety margin
##
## so the crouch needed for a given stride can be solved for rather than dialled. And because a foot
## planted at touchdown ends up the same distance BEHIND the hip at toe-off, the reach a stride
## actually demands is a tidy closed form with no speed in it at all:
##
##     demand = duty * stride / 2
##
## If even a full crouch cannot buy that, the STRIDE gives way instead of the knees — the ogre
## shortens its step rather than folding double. `stride_limited` says when that is happening, so
## the lab can show you that you are looking at the legs' answer and not the law's.
func _reach_budget(delta: float) -> void:
	var r := max_reach * tuning.reach_margin
	# EVERYTHING that puts distance between hip and foot has to be paid for here, not just the
	# stride. Budget for the stride alone and the plan lands exactly on its own limit, so the first
	# perturbation pushes the foot out of reach and the IK clamps -- which drags the foot for the
	# last third of every stance and looks precisely like the skate the plant lock exists to stop.
	#   forward  the stride: half ahead at touchdown, half behind at toe-off
	#   lateral  the feet track WIDER than the hip joints, by (stance_width - 1) hip half-widths
	#   bob      the pelvis rises at midstance and the leg must still reach at the top of it
	#   pelvis   the list and yaw swing each hip joint about the spine
	#   settle   the footfall spring, whose peak is roughly impulse / omega
	var forward_demand := duty * stride * 0.5
	var lateral := hip_half_width * maxf(tuning.stance_width - 1.0, 0.0)
	var bob := _bob_amplitude()
	# Combined in QUADRATURE, not by adding them up. The list peaks at midswing, the yaw at the
	# stride extremes and the settle just after touchdown, so their worst moments do not coincide;
	# summing the peaks budgets for a frame that never happens and buys the headroom by shortening
	# the stride, which is the one thing that must not be spent.
	var list_slack := hip_half_width * sin(deg_to_rad(tuning.pelvis_list_deg))
	var yaw_slack := hip_half_width * sin(deg_to_rad(tuning.pelvis_yaw_deg))
	var settle_slack := tuning.footfall_kick * 1.5 / maxf(tuning.hip_omega, 1.0)
	var slack := sqrt(list_slack * list_slack + yaw_slack * yaw_slack + settle_slack * settle_slack)

	var demand := sqrt(forward_demand * forward_demand + lateral * lateral) + slack
	var vertical := sqrt(maxf(r * r - demand * demand, 0.0))

	# PREDICT THE CROUCH, MEASURE THE STRIDE BUDGET.
	#
	# No closed form for the hip's height above the foot survives contact with the rest of the
	# solver: it is the crouch plus the bob plus the settle spring plus the pelvis roll plus the
	# offset between the body's origin and the hip joint. Each term the budget forgets makes it a
	# centimetre or two optimistic, the IK clamps at the end of stance, and the planted foot drags
	# along the reach sphere. Chasing them analytically is a losing game -- there is always one more.
	#
	# So the crouch stays a prediction (it only has to be roughly right; it sets a pose) and the
	# STRIDE budget is computed from the hip height the IK actually saw last pass. Peak-held with a
	# slow bleed, so the worst moment of the cycle is what gets budgeted for rather than the average.
	#
	# Two earlier versions of this are worth not repeating. Paying for the shortfall in CROUCH made
	# every number green while the ogre sank onto its haunches -- it satisfied "no skate" by
	# squatting until its legs could reach. Paying for it by integrating the error into the stride
	# ran away instead: the integrator ratcheted, the stride hit its floor and the cadence went to
	# 14 Hz. A direct measurement has neither failure mode.
	crouch = clampf(leg_length + bob - (ankle_height + vertical),
			tuning.crouch_base, tuning.crouch_max)
	var seen := 0.0
	if foot_ik:
		seen = maxf(foot_ik.hip_lift(0), foot_ik.hip_lift(1))
	hip_lift = maxf(seen, hip_lift - 0.35 * delta)

	# What the legs can actually deliver at the crouch they got, measured at the worst moment, with
	# the slack and the lateral offset already spent. What is left is the usable HALF-STRIDE.
	var span := sqrt(maxf(r * r - hip_lift * hip_lift, 0.0))
	var usable := maxf(span - slack, 0.0)
	reach_budget = sqrt(maxf(usable * usable - lateral * lateral, 0.0))
	# 0.97, not 1.0. Clamping the stride to exactly the reach budget leaves the leg sitting ON its
	# own limit for the whole of stance, so ANY later disturbance -- and the dynamics layer moving
	# the spine is one -- tips it over and the IK clamps. It cost a regression to learn that a limit
	# with no headroom is not a limit, it is a coin toss.
	var max_stride := 2.0 * reach_budget / maxf(duty, 0.01) * 0.97
	stride_limited = stride > max_stride
	if stride_limited:
		stride = maxf(max_stride, 0.25)


## Half the pelvis's vertical travel, from the inverted pendulum. Needed by the reach budget as well
## as by the pose, so it lives in one place rather than being derived twice and drifting.
func _bob_amplitude() -> float:
	if gait == Gait.IDLE:
		return 0.0
	var half := clampf(stride * 0.5 / maxf(leg_length, 0.01), -1.0, 1.0)
	return leg_length * (1.0 - cos(asin(half))) * tuning.hip_bob_gain * 0.5


## WHERE THE DRIVING FOOT IS, this frame.
##
## Out of the plant, up, forward to the impact point, and back. The same shape as the swing: a slow
## haul then a fast strike, so the two attacks read as the same creature.
func _kick_arc(f: Foot) -> Vector3:
	var strike_t := maxf(_act.time_of(&"strike"), 0.01)
	var u := clampf(action_t / strike_t, 0.0, 2.0)
	var home := f.plant
	var goal := kick_point
	if goal == Vector3.ZERO:
		goal = global_position + forward() * kick_zone().y
		goal.y = global_position.y + tuning.kick_height
	var travel: float
	if u <= 1.0:
		# The wind-up: eased, and only a third of the way out. Most of this phase is the lift.
		travel = ease(u, 2.2) * 0.34
	else:
		# The strike, and then the recovery back to the plant.
		var v := clampf(u - 1.0, 0.0, 1.0)
		travel = 0.34 + (1.0 - 0.34) * (1.0 - pow(1.0 - minf(v * 3.0, 1.0), 2.0))
		travel *= 1.0 - smoothstep(0.35, 1.0, v)
	var at := home.lerp(goal, travel)
	# The lift is highest in the middle of the journey, so the foot is hauled over rather than
	# dragged through the ground.
	at.y += sin(clampf(travel, 0.0, 1.0) * PI) * tuning.kick_lift
	return at


## The foot state machine, and the reason nothing skates. Left leads at phase 0, right at 0.5.
func _step_feet(delta: float) -> void:
	var cycle := 1.0 / maxf(stride_freq, 0.001)
	var stance_time := duty * cycle
	var swing_time := (1.0 - duty) * cycle
	for i in 2:
		var f: Foot = feet[i]
		var local := fposmod(phase - (0.0 if i == 0 else 0.5), 1.0)
		var was: int = f.mode
		if gait == Gait.IDLE or stance_lock:
			f.mode = FootMode.STANCE
			f.t = 0.0
		elif local < duty:
			f.mode = FootMode.STANCE
			f.t = local / maxf(duty, 0.001)
		else:
			f.mode = FootMode.SWING
			f.t = (local - duty) / maxf(1.0 - duty, 0.001)

		if was == FootMode.SWING and f.mode == FootMode.STANCE:
			_touchdown(f)
		elif was == FootMode.STANCE and f.mode == FootMode.SWING:
			f.steps += 1

		if _act != null and _act.kick_foot == i and is_acting():
			# THE KICKING FOOT IS NOT A FOOT ANY MORE, it is the weapon. Released from the plant and
			# driven along an arc to the impact point, exactly as the mace head is -- which is why
			# the leg is not an authored pose: the foot IK runs last and would haul any pose straight
			# back down to the ground.
			f.mode = FootMode.SWING
			f.t = 1.0
			f.target = _kick_arc(f)
			f.last_skate = 0.0
			f.contact = 0.0
			continue
		if posing:
			# Hold exactly where they are. Re-grounding every frame is what lets a foot catch the
			# edge of a rock and jump, which reads as the whole ogre twitching.
			f.mode = FootMode.STANCE
			f.t = 0.0
			f.target = f.plant
			f.last_skate = 0.0
			f.contact = 1.0
		elif f.mode == FootMode.STANCE and gait == Gait.IDLE and not stance_lock:
			# STANDING STILL IS NOT THE SAME AS STOPPING. Freezing the plants where the last stride
			# left them parks the ogre with its feet a full stride apart, splayed, forever. A real
			# creature brings its feet under itself. Easing the plant toward the neutral stance does
			# that, and because it is the PLANT that moves (not the foot relative to it) it reads as
			# a shuffle rather than a slide.
			var neutral := _ground(global_position + side_dir(i) * hip_half_width
					* tuning.stance_width, f)
			f.plant = f.plant.lerp(neutral, 1.0 - exp(-3.0 * delta))
			f.target = f.plant
			f.last_skate = 0.0
			f.contact = 1.0
		elif f.mode == FootMode.STANCE:
			# THE LOCK. The target IS the stored world point, so the body moves over a stationary
			# foot and skate cannot happen. Measure it anyway — a promise nobody checks is a wish.
			f.last_skate = f.target.distance_to(f.plant) / delta
			f.target = f.plant
			f.contact = minf(1.0, f.contact + delta * 12.0)
		else:
			_swing(f, i, swing_time, stance_time, delta)
			f.contact = maxf(0.0, f.contact - delta * 12.0)

	# The damage volume rides the driving foot, and is parked out of the way when nothing is
	# kicking. Placed AFTER the loop that writes the kick arc: it used to sit at the top of this
	# function, which put the hitbox on LAST frame's arc point — the kick's damage volume trailed
	# its own foot by one physics tick. That lag was never deliberate, unlike the three stale
	# reads the tick-order contract names.
	if _kick_node:
		if _act != null and _act.kick_foot >= 0 and is_acting():
			_kick_node.global_position = feet[_act.kick_foot].target
		else:
			_kick_node.global_position = global_position - Vector3.UP * 50.0


## Where the foot is going, re-predicted every frame so a turn taken mid-swing is obeyed. The
## landing point is the balance-preserving one — half a stance's travel ahead of where the hip WILL
## be — so the body passes symmetrically over the planted foot instead of tripping over it.
func _swing(f: Foot, i: int, swing_time: float, stance_time: float, delta: float) -> void:
	var remaining := (1.0 - f.t) * swing_time
	var side := side_dir(i) * hip_half_width * tuning.stance_width
	var hip_ground := global_position + side
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var land := _ground(hip_ground + planar * (remaining + stance_time * 0.5), f)
	# Smoothed, not snapped: a raw re-prediction jitters when the ground probe crosses an edge, and
	# the exponential ease is this project's house idiom for exactly that.
	f.predicted = land if f.t < 0.02 else f.predicted.lerp(land, 1.0 - exp(-14.0 * delta))

	# The arc. Horizontal on a smoothstep; vertical peaks EARLY (step_apex below 0.5) so the foot
	# snatches up and then falls. Heavy feet are dropped, not placed.
	var e := smoothstep(0.0, 1.0, f.t)
	var flat := f.plant.lerp(f.predicted, e)
	var span := maxf(f.plant.distance_to(f.predicted), 0.3)
	f.target = flat + Vector3.UP * (_arc(f.t, tuning.step_apex) * span * tuning.step_height)


## A one-humped curve peaking at `apex`, zero at both ends. Two quarter-sines joined at the peak, so
## the rise can be quick and the fall slow without a kink at the top.
func _arc(t: float, apex: float) -> float:
	var a := clampf(apex, 0.05, 0.95)
	if t <= a:
		return sin(PI * 0.5 * (t / a))
	return sin(PI * 0.5 * (1.0 - (t - a) / (1.0 - a)))


## Lock a foot to the floor, and pay for it: the hip dips, the camera shakes, water splashes.
func _touchdown(f: Foot) -> void:
	f.plant = _ground(f.predicted, f)
	f.target = f.plant
	var impact := absf(velocity.y) + speed * 0.35 + 0.4
	# An impulse, not a displacement. The impact gives the pelvis downward VELOCITY and the spring
	# decides how far it sinks — so a heavy landing sinks further than a light one, for free.
	hip_spring.impulse(-tuning.footfall_kick * impact)
	_footfall(f, impact)


## Drop a point onto the floor. Mirrors blob_shadow.gd's probe exactly, including the owner-RID
## exclusion — without which the ogre's own four-metre capsule eats every ray.
## THE CLIP PROPOSES, THE SOLVER DISPOSES — the lower body's half of the blend.
##
## An authored attack is a whole-body performance. The torso swing is only the visible half of it;
## underneath, the pelvis loads back and drives down, and the feet brace into a wide lunge that the
## swing is thrown from. Masking all of that off and keeping the arms — which is what this layer did
## first — leaves a torso swinging over a lower body that has no idea an attack is happening. It
## reads as broken because it IS broken: there is nothing holding the swing up.
##
## But the clip cannot simply be handed the legs either. It was authored on a flat treadmill by
## someone who did not know where this ground is, how fast the ogre is travelling, or that its legs
## are a different length from the actor's. Give it the legs outright and the feet skate and float,
## and every guarantee the foot IK exists to make is gone.
##
## So neither one wins. The clip states its INTENT — where it wants the pelvis, where it wants the
## feet — and the solver reconciles that against what the world will actually allow:
##
##   THE PELVIS shift is ADDED to the gait's own displacement rather than replacing it, so the bob,
##   the footfall settle and the reach budget's crouch all still apply on top of it.
##
##   THE FEET take their horizontal placement from the clip and their HEIGHT from the ground, by the
##   same raycast every other footfall goes through. The stance the animator authored survives; the
##   floor still has the last word on where a foot can be.
##
##   `plant` IS LEFT ALONE. Only the visible target is blended, so the anchor each foot returns to
##   when the action ends is still the one the gait locked, and the ogre settles back out of the
##   attack instead of inheriting wherever the clip's last frame happened to put its feet.
func _step_clip_stance(_delta: float) -> void:
	if clip_layer == null or _skel == null or clip_layer.weight <= 0.001:
		return
	# AN AUTHORED CLIP GETS THE FEET HALF ONLY. The pelvis echo below would feed the recording's
	# own bob and drop back on top of the live pelvis (the position channel is live for authored
	# clips). But the FOOT targets it must keep: slam's lunge carries the pelvis a metre forward
	# while `planted` pins the rear foot -- without the clip's stance pulling the feet back under
	# the body, the legs split, the reach budget buys the shortfall in crouch, and the recovery
	# played from a body sunk to its knees and folded flat. The clip's legs are the recorded
	# SOLVED legs, ground-disposed like any other target.
	var authored := clip_authored()
	var w: float = clip_layer.weight
	# Skeleton space through to the body frame. It goes through the SKELETON's basis, not the body
	# yaw alone, because the model carries a 180 degree rotation of its own -- the same one that put
	# the legs on the wrong sides until side_dir() existed.
	var b := _skel.global_transform.basis.orthonormalized()
	if not authored:
		hips_offset += Basis(Vector3.UP, facing).inverse() * (b * clip_layer.hips_offset()) 				* clip_layer.share_of("pelvis")

	# THE STANCE IS PAID FOR IN CROUCH, NOT TAKEN OUT OF THE FEET.
	#
	# A leg of length `reach` holding a pelvis `lift` above the floor has only
	# sqrt(reach^2 - lift^2) of horizontal span left. The clip's lunge asks for about 1.2 m per
	# foot; the ogre stands with its pelvis near 1.7 m on 2.04 m legs, which leaves about 0.65 m. So
	# the targets sit well beyond what the legs can do, and taken literally the IK has nowhere to
	# put a knee and the whole lower body folds up under the swing. It did exactly that.
	#
	# Clamping the feet inward fixes the folding and loses the animation: the brace collapses to a
	# narrow squat and the swing goes back to having nothing under it. What a real creature does
	# instead is DROP -- it sinks to widen its base, which is why a heavy wind-up reads as a coil.
	#
	# So the shortfall is paid in pelvis height, up to the same crouch limit the stride budget uses,
	# and only the remainder is taken out of the stance. This is the reach budget's own trade made
	# for a different reason: there it buys stride, here it buys a base to swing from.
	var reach: float = max_reach * tuning.reach_margin
	var want_flat := [Vector3.ZERO, Vector3.ZERO]
	var lift := [0.0, 0.0]
	var drop := 0.0
	for i in 2:
		var o: Vector3 = clip_layer.foot_offset(i)
		# THE LEGS DIAL APPLIES TO AUTHORED CLIPS TOO, and that is CALIBRATION, not principle.
		# By the ownership rule an authored stance should bypass this mix dial (clip_share()
		# does) — but it was MEASURED: at full width the recorded stances exceed what the leg
		# geometry affords, the crouch trade digs ~0.3 m deeper to pay for it, the arms then
		# solve from a sunken shoulder (hands 80 degrees off baseline on the slam), and the
		# punish window collapses. The 0.7 is part of the operating point every clip and
		# baseline was built around; the probe's stance-width floor (check 15) pins where that
		# point actually sits so a real regression cannot hide under this note.
		want_flat[i] = Vector3(o.x, 0.0, o.z) * clip_layer.share_of("legs")
		# THE LIFT THIS FOOT WOULD HAVE HAD WITHOUT LAST FRAME'S DROP. Measuring the pelvis, then
		# lowering the pelvis by what the measurement implied, then measuring again next frame is a
		# loop that argues with itself: the drop it asks for vanishes the moment it is applied, the
		# pelvis springs back, and the ogre bounces. Adding the previous drop back recovers the
		# stable input the decision should have been made from in the first place.
		lift[i] = (foot_ik.hip_lift(i) if foot_ik else leg_length * 0.85) + clip_drop
		# The pelvis height this foot's stance actually needs, and how far short the ogre is.
		var need := sqrt(maxf(reach * reach - minf(want_flat[i].length(), reach) ** 2, 0.04))
		drop = maxf(drop, lift[i] - need)
	drop = clampf(drop, 0.0, tuning.crouch_max) * w
	hips_offset.y -= drop
	clip_drop = drop

	for i in 2:
		# THE KICKING FOOT IS THE WEAPON, not a foot — _step_feet drives it along the aimed arc
		# and parks the damage volume on it. Reconciling it toward the clip's stance dragged the
		# kick 1.27 m off its own hitbox (the probe's trailing-foot assertion caught it).
		if _act != null and _act.kick_foot == i and is_acting():
			continue
		var f: Foot = feet[i]
		# Clamped as a VECTOR, not per axis, so the lunge keeps its DIRECTION and loses only its
		# excess -- the shape the animator posed survives being scaled to a body that, even coiled,
		# cannot quite make it.
		var span := sqrt(maxf(reach * reach - maxf(lift[i] - drop, 0.1) ** 2, 0.04))
		# Horizontal only: Y is thrown away and re-derived from the ground, so a stance authored on
		# a flat floor still lands correctly on a slope.
		var want := _ground(global_position + b * (want_flat[i] as Vector3).limit_length(span), f)
		f.target = f.target.lerp(want, w)


## THE SWING: THE ARM AND THE WEAPON TURN TOGETHER, ABOUT THE SHOULDER.
##
## Not about the hand. That was the whole mistake, and it is visible the moment both ends of the
## mace are drawn: rotate about the grip and the butt traces a circle 0.5 m across while the head
## traces one seven metres across, so the butt effectively stays put -- parked against the ogre's
## stomach for the length of the swing. Rotate the ARM about the SHOULDER and everything on the
## assembly sweeps: the hand on a radius of about 1.3 m, the butt on 0.8, the head on 4.8. Two
## concentric arches, which is what a swing looks like from the side.
##
## So the whole arm-plus-weapon is treated as one rigid thing hinged at the shoulder, and the swing
## is one angle. The hand is no longer somewhere the path is told to go; it is where the arm
## reaches when the arm is at that angle.
##
## THE STRIKE ANGLE IS STILL DERIVED, and now from the shoulder rather than the grip:
##
##     cos(angle) = -(shoulder height) / (shoulder to head)
##
## so the head arrives on the floor whatever the ogre's stance, and it arrives out in FRONT rather
## than dropping down the ogre's own side.
func _swing_arc() -> Transform3D:
	var strike_t := maxf(_act.time_of(&"strike"), 0.01)
	var s := action_t / strike_t
	# THE SWING FACES WHERE IT IS GOING TO LAND, not where the body happens to point. The aim leads
	# the feet: a heavy creature turns slowly, so the mace is already tracking while the body is
	# still coming round, and the telegraph stays honest about where the blow will fall.
	var fwd := forward()
	if _aim_live:
		var to := aim_point - global_position
		to.y = 0.0
		if to.length_squared() > 0.04:
			fwd = to.normalized()
	# THE PLANE, BUILT THROUGH THE LANDING PLACE -- see swing_frame. Everything the old fixed
	# 45 degree tilt needed afterwards to stay honest (a floor angle solved through the tilt, a yaw
	# correction for the sideways drift it caused, a hinge argument with the prediction) is gone,
	# because a plane that contains the impact point does not need to be argued into containing it.
	var target := predicted_impact()
	var f := swing_frame(target)
	var hinge: Vector3 = f["hinge"]
	var u_ax: Vector3 = f["u"]
	var v_ax: Vector3 = f["v"]
	var carry := deg_to_rad(tuning.swing_carry_deg)
	var wind := deg_to_rad(tuning.swing_windup_deg)
	var at := tuning.swing_wind_at
	# THE ARM IS WHAT IS LEFT OVER. The head has to be f.r from the hinge to arrive at the impact
	# point, and the haft beyond the grip is fixed, so the arm makes up the difference. It is in
	# range without clamping because the aim was pulled into the strike zone first, and the zone is
	# defined as the distances this arm can make up.
	var full := swing_arm_full()
	var beyond := weapon_length - grip_point.y
	var arm := clampf(float(f["r"]) - beyond,
			full * tuning.swing_arm_min, full * tuning.swing_arm_max)
	swing_reach_used = arm
	var radius := arm + beyond

	# THE FLOOR IS THE END OF THE SWING, and the angle it happens at is not a constant.
	# LAND_ANG lands the head ON the target only while the arm can make the spoke match the
	# distance to it. When the player is INSIDE the arc the arm clamps at its minimum, the
	# spoke stays longer than the reach, and a fixed ninety degrees drives the head through
	# the ground — measured at 0.90 m under, with the arm pinned at 0.51 m on a 4.01 m spoke
	# swung from a hinge 2.89 m up. Geometry, not tuning: no angle both reaches that close a
	# target and stays above the floor.
	#
	# So the descent ends where the circle meets the ground. The blow lands ON the floor and
	# MISSES a player standing inside the spoke, which is the honest read of that position and
	# the same thing the strike zone's inner edge has always said.
	#
	# TWO EXEMPTIONS, both about what the attack IS. The flat sweep solves its own elevation
	# from the aim and never dives. The POUND is meant to end in the earth — that is the whole
	# reason its damage comes from the ring and not the weapon — so it is exempted by that same
	# flag rather than by name, which is also how the combat probe's floor check spells it.
	var land := LAND_ANG
	if not _act.flat_sweep and not _act.damage_from_ring:
		land = _floor_angle(hinge, radius, u_ax, v_ax, target.y)

	var u := 0.0
	var ang := carry
	## The follow-through, as a yaw about the vertical — see the recovery branch for why it
	## cannot be more elevation.
	var through_yaw := 0.0
	if s <= at:
		# PREPARE, RAISE, AIM -- see OgreTuning.swing_prepare. Three pieces, not one ease, because a
		# single smoothstep spends its speed in the middle of the wind-up and leaves the top of it
		# rushing past. The telegraph wants the opposite: get the weapon moving at once, climb slowly
		# where the player is reading it, and then HOLD, so there is a moment to react to.
		var w := clampf(s / maxf(at, 0.01), 0.0, 1.0)
		var p := tuning.swing_prepare
		var lift := tuning.swing_prepare_lift
		var raise_end := 1.0 - tuning.swing_aim_hold
		if w <= p:
			u = lift * smoothstep(0.0, 1.0, w / maxf(p, 0.001))
		elif w <= raise_end:
			u = lift + (1.0 - lift) * ((w - p) / maxf(raise_end - p, 0.001))
		else:
			u = 1.0
		ang = lerpf(carry, wind, u)
	elif s <= 1.0:
		u = pow(clampf((s - at) / maxf(1.0 - at, 0.01), 0.0, 1.0), 1.6)
		ang = lerpf(wind, land, u)
	else:
		# INERTIA THROUGH THE CRATER, AND EACH SHAPE FOLLOWS ITS OWN ARC. The head used to stop
		# dead at the landing angle and haul straight back, which reads as a hammer meeting a
		# nail rather than a hundred kilos of iron meeting the floor. It now carries PAST the
		# landing point while the momentum spends itself (sine ease out of the impact,
		# decelerating to the far edge), and only then does the recovery pull it home.
		#
		# WHAT "PAST" MEANS IS NOT THE SAME FOR BOTH, and one term for both is exactly the bug
		# that was here: `ang` is elevation IN THE SWING PLANE, and LAND_ANG is where the head
		# reaches the landing point — which for an overhead is the FLOOR, as swing_dbg has
		# always named it. Carrying `ang` past LAND_ANG continued the horizontal correctly
		# (_flat_sweep_dir reads the angle as yaw and solves its own elevation) and drove the
		# vertical UNDERGROUND on every slam. So the two shapes own their continuations:
		#
		#   FLAT   keep turning in the swing's own plane, past the aim — the stroke carries on
		#          round at the height it was already travelling at.
		#   OVERHEAD  the floor is in the way; the descent is finished. What is left of the
		#          momentum drags the head ROUND on the ground at the height it landed at,
		#          which is what a heavy head glancing off packed earth actually does.
		var span := maxf(action_len / strike_t - 1.0, 0.01)
		var rec := clampf((s - 1.0) / span, 0.0, 1.0)
		var through := deg_to_rad(tuning.swing_through_deg)
		var at_p: float = tuning.swing_through_at
		var carried := 0.0
		if rec < at_p:
			carried = through * sin(clampf(rec / maxf(at_p, 0.01), 0.0, 1.0) * PI * 0.5)
			u = 0.0
		else:
			u = smoothstep(0.0, 1.0, (rec - at_p) / maxf(1.0 - at_p, 0.01))
			carried = through * (1.0 - u)
		if _act.flat_sweep:
			ang = lerpf(land + carried, carry, u)
		else:
			ang = lerpf(land, carry, u)
			through_yaw = carried

	swing_angle = rad_to_deg(ang)
	swing_dbg = {"ang": rad_to_deg(ang), "floor": rad_to_deg(land),
			"hinge_y": hinge.y, "feet_y": global_position.y, "arm": arm,
			"plane_up_y": u_ax.y, "radius": radius,
			# What the ARC itself thinks the head will be at, so it can be held against what the
			# grip node actually ends up reporting.
			"head_y": hinge.y + radius
					* ((u_ax * cos(ang) + v_ax * sin(ang)).normalized().y)}
	var dir := (u_ax * cos(ang) + v_ax * sin(ang)).normalized()
	if _act.flat_sweep:
		dir = _flat_sweep_dir(hinge, radius, target, ang, wind)
	elif through_yaw != 0.0:
		# The overhead's ground drag (see the recovery branch). A turn about the VERTICAL, so
		# the head keeps the height it landed at and the floor cannot be crossed however far
		# the follow-through is dialled. Signed by the side the swing came from, so the head
		# carries on the way it was already travelling instead of doubling back through the
		# ogre's own legs.
		dir = dir.rotated(Vector3.UP, through_yaw * (-1.0 if swing_side >= 0 else 1.0))
	# The mace continues the line of the arm, so hand, butt and head all ride the same spoke.
	var hand := hinge + dir * arm
	return Transform3D(Basis(Quaternion(Vector3.UP, dir)), hand - dir * grip_point.y)


## WHERE THE SWING'S CIRCLE MEETS THE GROUND — the angle at which the mace head arrives at
## `floor_y`, or LAND_ANG if the head never gets that low (a short spoke stops in the air, which
## is the existing behaviour and not this function's problem).
##
## Bisected rather than solved in closed form: the closed form is one asin and an atan2 phase,
## and picking the right branch of it is the kind of thing that is wrong for a month before
## anyone sees it. The head's height is monotonic across the descent, so sixteen halvings land
## within a hundredth of a degree — the same "iterate, it is cheap at this scale" the arm IK's
## two-pass palm solve already uses.
func _floor_angle(hinge: Vector3, radius: float, u_ax: Vector3, v_ax: Vector3,
		floor_y: float) -> float:
	if _head_height(hinge, radius, u_ax, v_ax, LAND_ANG) >= floor_y:
		return LAND_ANG
	var lo := 0.0                      # above the floor by construction: the arc starts high
	var hi := LAND_ANG                 # below it, or we would have returned already
	for _i in 16:
		var mid := (lo + hi) * 0.5
		if _head_height(hinge, radius, u_ax, v_ax, mid) >= floor_y:
			lo = mid
		else:
			hi = mid
	return lo


func _head_height(hinge: Vector3, radius: float, u_ax: Vector3, v_ax: Vector3,
		ang: float) -> float:
	return hinge.y + radius * (u_ax * cos(ang) + v_ax * sin(ang)).normalized().y


func _yield_to_off_hand(held: Vector3, wb: Basis) -> Basis:
	if arm_ik == null or tuning.grip_yield <= 0.0:
		return wb
	var other := 0 if _anchor_bone.begins_with("Right") else 1
	# THE UPPER ARM, not the shoulder. Those are different bones -- the clavicle and the arm -- and
	# the arm IK measures its reach from the UPPER ARM. Yielding until the grip was inside the
	# CLAVICLE's reach satisfied a constraint nothing was testing: the geometry came out exactly on
	# target, 0.0 degrees short of what was asked, and the IK still only applied a third of the solve
	# because by its own measure the grip was still too far away.
	var ib := bone("LeftUpperArm" if other == 0 else "RightUpperArm")
	var pts := arm_ik.bone_positions()
	if ib < 0 or ib >= pts.size():
		return wb
	var shoulder: Vector3 = pts[ib]

	var gap := off_point - grip_point                        # along the haft, in mace space
	var r := gap.length()
	var lv := shoulder - held
	var lp := lv.length()
	if r < 0.001 or lp < 0.001:
		return wb
	# The solver's own measured chain — this was the one arm_reach() consumer with NO zero guard,
	# quietly computing a degenerate cos_max on any frame before the layer's first pass.
	var d := arm_reach * tuning.grip_reach
	var cos_max := (r * r + lp * lp - d * d) / (2.0 * r * lp)
	yield_dbg = {"r": r, "L": lp, "d": d, "cos_max": cos_max,
			"have": (wb * gap).normalized().dot(lv / lp),
			"predicted": sqrt(maxf(r * r + lp * lp - 2.0 * r * lp * (wb * gap).normalized().dot(lv / lp), 0.0)),
			"shoulder": shoulder}
	yield_degrees = 0.0
	yield_short = 0.0
	if cos_max <= -1.0:
		return wb                                            # everything is in reach already
	if cos_max >= 1.0:
		yield_short = 999.0                                  # sphere and reach do not intersect
		return wb

	var toward := lv / lp
	var cur := (wb * gap).normalized()
	var have := cur.dot(toward)
	if have >= cos_max:
		return wb                                            # already inside the cone
	var need := acos(clampf(cos_max, -1.0, 1.0))
	var want_turn := acos(clampf(have, -1.0, 1.0)) - need

	# ALL OR NOTHING. Turning as far as the budget allows and stopping short helps nobody: the hand
	# still cannot reach, so it lets go anyway, and the weapon has been dragged inboard for a grip
	# that never happened. Measured, that cost 0.23 m of the clearance it had just been given. Either
	# the turn buys the grip or it is not made.
	if want_turn > deg_to_rad(tuning.grip_yield):
		yield_short = rad_to_deg(want_turn - deg_to_rad(tuning.grip_yield))
		return wb
	var turn := want_turn
	yield_degrees = rad_to_deg(turn)
	if turn <= 0.0001:
		return wb
	var axis := cur.cross(toward)
	if axis.length_squared() < 0.000001:
		return wb
	return Basis(Quaternion(axis.normalized(), turn)) * wb


## Swing the shaft out of the ogre's own trunk, and return the direction that does it.
##
## PUSHED SIDEWAYS, NOT LIFTED. The correction is applied about a horizontal axis only, because the
## other way out of a torso is upward and lifting the mace over the ogre's head to avoid its chest
## trades one nonsense pose for a worse one.
##
## ROTATED ABOUT THE GRIP, NOT TRANSLATED. The hand is holding it, so the butt cannot move -- only
## the aim can. That also means the head sweeps as the shaft turns, and the angle is worked out from
## the LEVER: the further along the shaft the intrusion is, the smaller the turn needed to clear it.
##
## FADED IN OVER A MARGIN. A correction that switches on the instant the shaft crosses the radius is
## a pop, and this runs every frame on a weapon the eye is following.
func _clear_of_body(origin: Vector3, dir: Vector3) -> Vector3:
	var r := tuning.weapon_clear_radius
	if r <= 0.001:
		return dir
	# THE TRUNK LEANS. Taken from the pelvis and the upper chest as the pose actually leaves them,
	# not as a vertical line rising from the feet: this creature spends the back half of a slam bent
	# most of the way over, and a plumb line through a folded body defends the wrong volume.
	var a0 := global_position + Vector3.UP * tuning.weapon_clear_low
	var a1 := global_position + Vector3.UP * tuning.weapon_clear_high
	if arm_ik:
		var pts := arm_ik.bone_positions()
		var ih := bone("Hips")
		var ic := bone("UpperChest")
		if ih >= 0 and ic >= 0 and ic < pts.size():
			a0 = pts[ih]
			a1 = pts[ic]
	var from := origin + dir * minf(tuning.weapon_clear_skip, weapon_length * 0.5)
	var hit := _closest_between(from, origin + dir * weapon_length, a0, a1)
	var p: Vector3 = hit[0]
	var c: Vector3 = hit[1]
	var d: float = p.distance_to(c)
	var band := r + tuning.weapon_clear_margin
	if d >= band:
		_clear_side = 0.0
		return dir
	var n := p - c
	n.y = 0.0
	if n.length_squared() < 0.000001:
		n = side_dir(1)
	n = n.normalized()

	# LATCH WHICH WAY IT GETS PUSHED, for as long as one correction lasts.
	#
	# `n` is the outward normal from the trunk, and it REVERSES as the shaft sweeps across the
	# midline -- which is the very frame the shaft is closest and the push is hardest. Recomputed
	# freely, the mace is shoved left, then flipped and shoved right, at maximum amplitude. That is
	# the swing "starting to his left and then switching to the right".
	var want_side := signf(n.dot(right()))
	if _clear_side == 0.0:
		_clear_side = want_side if want_side != 0.0 else 1.0
	if want_side != 0.0 and want_side != _clear_side:
		n = (n - right() * (2.0 * n.dot(right()))).normalized()

	# THE MARGIN HAS TO BE IN THE ANGLE, not just in the early-out. The first version multiplied
	# `atan(max(r - d, 0) / lever)` by the fade -- but max(r - d, 0) is zero across the whole margin
	# band, so the fade multiplied nothing and the correction still switched on hard at d = r.
	var lever := maxf((p - origin).length(), 0.5)
	var theta := atan(maxf(band - d, 0.0) / lever) * smoothstep(0.0, 1.0,
			clampf((band - d) / maxf(tuning.weapon_clear_margin, 0.001), 0.0, 1.0))
	if theta <= 0.0001:
		return dir
	var ax := dir.cross(n)
	if ax.length_squared() < 0.000001:
		return dir
	return dir.rotated(ax.normalized(), theta).normalized()


## Closest pair of points between two segments: [on the first, on the second].
static func _closest_between(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a > 0.000001:
		var c := d1.dot(r)
		if e > 0.000001:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 0.000001 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
		else:
			s = clampf(-c / a, 0.0, 1.0)
	elif e > 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]


func _ground(at: Vector3, f: Foot) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return at
	var from := Vector3(at.x, global_position.y + leg_length * 0.6, at.z)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (leg_length * 1.8), 1)
	if _body_rid.is_valid():
		q.exclude = [_body_rid]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		f.grounded = false
		f.normal = Vector3.UP
		return Vector3(at.x, global_position.y + ankle_height, at.z)
	f.grounded = true
	f.normal = hit.normal
	return Vector3(at.x, hit.position.y + ankle_height, at.z)


## Everything a footfall does to the world. All of it rides signals that already exist — which is
## why the loudest "four metres" cue in the whole system costs no new plumbing.
func _footfall(f: Foot, impact: float) -> void:
	# THE SCREEN SHAKE, and it is mostly about what does NOT shake it.
	#
	# Two changes from the obvious version, both because a walking ogre was rattling the camera the
	# whole time it was on screen:
	#
	#   FLOOR. Only the part of an impact above an ordinary walking footfall registers. A shake that
	#   fires one and a half times a second forever is not a cue -- it carries no information after
	#   the first few steps and reads as noise. What should be felt is the DIFFERENCE between a step
	#   and something heavier, so the step itself is subtracted off.
	#
	#   FALLOFF. Squared, with distance. The old version was a hard cutoff: identical shake at 13 m
	#   and at 2 m, then nothing at 14. Ground shock does not work like that and neither should this
	#   -- an ogre approaching should be felt to approach.
	# The facade owns the falloff maths AND the player lookup — this used to be the solver's second
	# get_first_node_in_group("player"), an animation file asking the scene tree who the player is.
	if _feedback:
		_feedback.footfall_shake(global_position, impact, tuning.shake_range, tuning.shake_floor,
				tuning.footfall_shake)
		_feedback.beat_ground_contact(f.plant - Vector3.UP * ankle_height,
				clampf(tuning.dust_scale * impact, 0.3, 2.2), f.grounded)


## The pelvis and everything hanging off it: bob, settle, sway, roll, counter-rotation, arm swing.
func _step_body(delta: float) -> void:
	hip_spring.omega = tuning.hip_omega
	hip_spring.zeta = tuning.hip_zeta
	var moving := 0.0 if gait == Gait.IDLE else 1.0

	# The inverted pendulum. The pelvis vaults over the stance leg, rising at midstance and falling
	# at double support — twice per stride. The raw geometry is comically large because real knees
	# absorb most of it, and hip_bob_gain is that absorption.
	var bob_now := -cos(phase * TAU * 2.0) * _bob_amplitude()

	# Breathing. Metabolic rate scales as mass^-0.26, and the ogre masses about eleven times a
	# human, so it breathes roughly half as often — an elephant manages six breaths a minute.
	# Nobody consciously notices this. Everybody notices its absence.
	breath = 0.5 - 0.5 * cos(_time * TAU / maxf(tuning.breath_period, 0.1))
	var idle := 1.0 - moving
	var sway := sin(_time * TAU / maxf(tuning.sway_period, 0.1)) * tuning.sway_amount * idle

	var settle := hip_spring.step(delta, 0.0)
	if posing:
		# The crouch stays -- it is part of the pose's shape -- and everything that MOVES goes.
		hips_offset = Vector3(0.0, -crouch, 0.0)
		hips_roll = 0.0
		hips_yaw = 0.0
		spine_yaw = 0.0
		arm_swing[0] = 0.0
		arm_swing[1] = 0.0
		breath = 0.0
		return
	hips_offset = Vector3(sway, bob_now + settle - crouch + breath * tuning.breath_depth * idle, 0.0)

	# Pelvic list: the SWING-side hip drops. Phase-locked, so it reads as the pelvis being carried
	# rather than as a wobble.
	var swing_side := 0.0
	if feet[0].mode == FootMode.SWING:
		swing_side = 1.0
	elif feet[1].mode == FootMode.SWING:
		swing_side = -1.0
	var list := deg_to_rad(tuning.pelvis_list_deg) * swing_side * moving
	hips_roll = lerpf(hips_roll, list, 1.0 - exp(-9.0 * delta))

	# Pelvic yaw, and the chest counter-rotating it a beat later. THE LAG IS THE CUE: a heavy torso
	# cannot turn with the hips, and a rig where they turn together looks like a puppet on a stick.
	var yaw_amp := deg_to_rad(tuning.pelvis_yaw_deg) * clampf(stride / maxf(leg_length, 0.01), 0.0, 1.5)
	hips_yaw = sin(phase * TAU) * yaw_amp * moving
	var lag_phase := fposmod(phase - tuning.spine_lag * stride_freq, 1.0)
	spine_yaw = -sin(lag_phase * TAU) * yaw_amp * tuning.spine_counter_gain * moving

	# Arms swing contralateral to the legs, and trail them. Long heavy arms hang back.
	var arm_phase := fposmod(phase - tuning.arm_lag * stride_freq, 1.0)
	var amp := deg_to_rad(tuning.arm_swing_deg) * clampf(speed / maxf(walk_speed(), 0.1), 0.0, 1.4)
	arm_swing[0] = -sin(arm_phase * TAU) * amp
	arm_swing[1] = sin(arm_phase * TAU) * amp


## Put both feet under the body, standing still, springs at rest. Used on spawn and by the lab's
## reset key — a half-carried state is a worse lie than a clean restart.
func _reset_feet() -> void:
	for i in 2:
		var f: Foot = feet[i]
		var side := side_dir(i) * hip_half_width * tuning.stance_width
		f.plant = _ground(global_position + side, f)
		f.target = f.plant
		f.predicted = f.plant
		f.mode = FootMode.STANCE
		f.contact = 1.0
		f.last_skate = 0.0
	phase = 0.0
	if hip_spring:
		hip_spring.reset()
	if lean_spring:
		lean_spring.reset()


func reset() -> void:
	_prev_vel = Vector3.ZERO
	accel = Vector3.ZERO
	if dynamics:
		# Otherwise the upper body spends half a second unwinding from the pose it held before the
		# teleport, and appears to be dragged across the level after arriving.
		dynamics.reset()
	_reset_feet()


## The speed at which this creature naturally walks, and the one at which it breaks into a run.
## Exposed because enemy.gd's move_speed should be DERIVED from the body, not guessed at.
func walk_speed() -> float:
	return sqrt(0.25 * G * leg_length)


func run_speed() -> float:
	return sqrt(0.5 * G * leg_length)


## Turn-rate ceiling, rad/s. Lateral acceleration is limited by how far a heavy body dares to lean,
## and turning IS lateral acceleration: omega = a_max / v. enemy.gd's usual `1 - exp(-10*delta)`
## smoothing is an effective ~570 deg/s, roughly ten times too fast for this creature. A slow turn
## is what makes flanking a readable mechanic instead of a stat.
func yaw_rate(at_speed: float) -> float:
	return minf(deg_to_rad(tuning.yaw_rate_deg), tuning.max_accel / maxf(at_speed, 0.6))

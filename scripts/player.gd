class_name Player
extends CharacterBody3D
## The player avatar.
##
## DESIGN: this script is deliberately THIN. It owns velocity + shared helpers (movement, facing,
## dash cooldown) and wires Health up to the state machine. The decision of WHICH helpers to call
## each frame belongs to the current state in the StateMachine child — not a giant _physics_process.
##
## CharacterBody3D (not RigidBody3D) is chosen for arcade-precise, predictable control.

@export var move_speed := 6.0           ## Top running speed (m/s).
@export var acceleration := 40.0        ## How fast we reach / leave top speed (m/s^2).
@export var rotation_speed := 12.0      ## How fast the visuals swing to face the cursor.
@export var dash_cooldown := 0.5        ## Seconds before you can dash again.
@export var shoot_cooldown := 0.55      ## Seconds before you can fire the bow again.
@export var knockback_force := 8.0      ## Push-back speed when hit.

# --- Procedural "juice" animation (no skeleton needed) ---
@export var bob_speed := 11.0           ## Run-bounce frequency.
@export var bob_height := 0.09          ## Run-bounce height (m).
@export var lean_amount := 0.16         ## How far the body leans into a run (radians).

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _dash_ready_at := 0.0
var _shoot_ready_at := 0.0
var _anim_t := 0.0

## Sword, bow and shield are OPTIONAL. A player scene that carries no bow and no shield (player3)
## simply omits those nodes, and everything downstream null-checks rather than branching on a
## loadout flag — get_node_or_null is the whole mechanism. The Shoot and Block STATES are likewise
## just absent from that scene's StateMachine, and transition_to() no-ops on a name it doesn't
## know, so Idle/Move can keep offering them without caring who is listening.
@onready var visuals: Node3D = $Visuals               ## yaw-pivot we rotate (never the collider)
@onready var sword: Sword = get_node_or_null("Visuals/Sword")
@onready var bow: Bow = get_node_or_null("Visuals/Bow")
@onready var health: Health = $Health
@onready var _fsm: StateMachine = $StateMachine
@onready var shield: Shield = get_node_or_null("Visuals/ArmL/Shield")
@onready var dash_trail: BladeTrail = $DashTrail   ## dodge smear; the Dash state switches it on

var _anim: AnimationPlayer                            ## the model's imported animations (fallback)
var _tree: AnimationTree                              ## visual state machine, owns the clip library
var _playback: AnimationNodeStateMachinePlayback

## Weapon "weight": the sword/shield CHASE their hand sockets with a damped follow, so a fast
## swing trails the hand slightly (heft) instead of welding rigidly. The run/idle/block clips are
## authored holding the weapons, so the hands already move right — the sockets just keep the real
## sword/shield meshes riding those hands, and this adds a little swing lag. Lower = heavier.
@export var sword_weight := 12.0
@export var shield_weight := 16.0

## HOW MUCH OF THE WRIST THE CARRIED BLADE OBEYS, outside an attack.
##
## The blade used to be welded to the hand socket outright, which is correct ONLY if the clips were
## authored holding a sword. player/player2 run the Mixamo sword-and-shield set, where they were —
## so 1.0, the default, keeps them exactly as they were.
##
## player3/player4 run Quaternius' library, whose locomotion is EMPTY-HANDED: the fists pump and the
## wrist rolls freely, because nothing was ever meant to be in them. A blade obeying that wrist
## measured 108 degrees away from where a carried sword should point, inside a single idle loop. So
## those bodies take their carry ANGLE from the torso — forward, a little out, a little down, which
## is the pose _calibrate_grips describes — and only a hint of it from the hand, for life.
##
## Attacks always use 1.0 regardless: the swing arc is the whole point of an attack clip, and it
## lives in the hand.
@export var hand_follow := 1.0
@export var attack_follow_speed := 40.0   ## how fast the blade hands over to the wrist mid-swing
@export var attack_speed := 2.3         ## playback speed-up for unassigned melee clips (atk_combo)

## THE COMBO CADENCE ("ta.. taa.. taaaa"): each chain step gets its own weight. Per clip:
##   strike/cancel = authored fractions of the ORIGINAL clip (where the blade connects / where a
##                   buffered press may chain — the Death's Door per-animation-event way)
##   speed  = uniform speed-up (later swings play slower = heavier)
##   windup = seconds from swing start to CONTACT (grows per step — that's the rhythm's beat)
##   tail   = playback scale of everything AFTER the cancel point (<1 = slower, weightier
##            follow-through/recovery)
##   cancel_min = optional floor on the post-warp cancel fraction — the finisher (atk_d) is
##                barely cancellable, so after the 3rd hit the combo breathes before looping.
## `attack_meta` holds the POST-warp fractions the Attack state actually uses.
## CALIBRATING THE COMBO — the knobs, and which one does what.
##   strike  : when the blade connects (fraction of the ORIGINAL clip)
##   cancel  : when a buffered press may chain into the next swing. THIS is the responsiveness dial
##             — the strike has already landed by then, so everything after is recovery.
##   speed   : whole-clip speed-up. Later swings are slower = heavier.
##   windup  : seconds from press to CONTACT. THIS is the snappiness dial (~0.08-0.26).
##   tail    : playback speed AFTER the cancel point (<1 = slower, weightier recovery).
##   cancel_min : floor on the post-warp cancel fraction, used to make a swing a real beat.
##
## THE TRAIL SETS A FLOOR ON `cancel`. Chaining calls BladeTrail.burst(), which restarts the ribbon
## — so a swing cancelled sooner than the trail's own memory (Sword's Trail.seconds, 0.24 s) has its
## arc WIPED BEFORE IT FINISHES DRAWING. That reads as a flicker rather than a swing, which is
## exactly what spamming atk_h looked like: measured, its ribbon lived 0.200 s against a 0.233 s
## memory. Rule: cancel * clip_length >= trail seconds, with headroom so the arc also PERSISTS a
## moment. This is a real constraint now, not a matter of taste — check it when retiming a clip.
##
## ANTI-SPAM AND RESPONSIVENESS ARE NOT OPPOSED. Spam is prevented by COMMITMENT (you cannot abort
## a swing already in flight) plus the chain's own rhythm. Responsiveness comes from buffering the
## press, being able to dash or move out, and opening `cancel` soon after the strike. Using a long
## recovery LOCKOUT to stop spam is the mistake — it just feels unresponsive. Measured: the old
## finisher (cancel_min 0.93, tail 0.60) locked the player for 850 ms after its hit landed.
##
## EXPORTED, not const: the timings are authored against a PARTICULAR set of clips, and a different
## body brings different clips. player/player2 run the Mixamo set (atk_h/atk_b/atk_d); player3 runs
## Quaternius' sword chain (atk_a/atk_b/atk_c) and needs its own beats. The dial meanings above are
## the same whatever the clips are called.
@export var attack_timing := {
	"atk_h": {"strike": 0.42, "cancel": 0.55, "speed": 2.6, "windup": 0.08, "tail": 0.85,
			"cancel_min": 0.45},
	"atk_b": {"strike": 0.42, "cancel": 0.55, "speed": 2.3, "windup": 0.16, "tail": 0.75},
	"atk_d": {"strike": 0.45, "cancel": 0.60, "speed": 2.0, "windup": 0.26, "tail": 0.78,
			"cancel_min": 0.70},
}

## Clips to sanitize at load: locomotion and aim sets whose hips must be pinned (see
## _strip_root_drift). Exported for the same reason as attack_timing — player3's set is different.
@export var locomotion_clips: PackedStringArray = [
	"idle", "run_fwd", "run_back", "strafe_left", "strafe_right",
	"aim_idle", "aim_fwd", "aim_back", "aim_left", "aim_right",
	"atk_h", "atk_b", "atk_d", "atk_combo",
]

## Clips the tree must LOOP that the source pack did not mark as looping. Quaternius' Sword_Idle is
## a one-shot in the GLB, but it is player3's standing pose and has to cycle; rather than editing
## the .res (and losing it on the next re-extract) we force the mode here, the same way the
## fallback "run" clip below is forced.
@export var loop_clips: PackedStringArray = []

var attack_meta: Dictionary = {}

var _grip_r: BoneAttachment3D                         ## right-hand socket (sword)
var _grip_l: BoneAttachment3D                         ## left-hand socket (shield)
var _arm_guard: ArmGuard                              ## procedural shield-up (left-arm override)
var _guard := 0.0                                     ## eased 0..1 guard blend

@export var guard_raise_speed := 14.0                 ## how fast the shield comes up / drops

## Grip offsets: socket space -> weapon space. SELF-CALIBRATED at spawn for ANY rig: we describe
## the desired weapon pose in the character's FACING frame ("blade forward-down from the palm",
## "shield upright on the forearm") and solve the offset against the live hand sockets. No
## per-rig hand-tuned numbers — swap the model, grips just work.
var _sword_grip := Transform3D.IDENTITY
var _shield_grip := Transform3D.IDENTITY
var _grips_ready := false
var _sword_basis := Basis.IDENTITY      ## the blade's damped orientation (see hand_follow)
var _sword_basis_ready := false


## THE CARRY POSE: blade forward, a bit outward and down, described in the character's FACING frame.
## Recomputed live rather than frozen at calibration, because it is what a body-relative carry MEANS
## — turn the character and the sword turns with them, whatever the wrist is doing.
func _carry_basis() -> Basis:
	var fwd := -visuals.global_transform.basis.z
	var right := visuals.global_transform.basis.x
	var up := Vector3.UP
	var d := (fwd * 0.95 + right * 0.30 - up * 0.05).normalized()
	var bz := -d                              # the blade mesh extends along its local -Z
	var bx := up.cross(bz).normalized()
	return Basis(bx, bz.cross(bx), bz)


func _calibrate_grips() -> void:
	for i in 3:
		await get_tree().physics_frame        # let the idle pose reach the sockets first
	if _grip_r == null or _grip_l == null:
		return
	var fwd := -visuals.global_transform.basis.z
	var right := visuals.global_transform.basis.x
	var up := Vector3.UP
	# sword: the carry pose, solved into a HAND-RELATIVE offset. Only its rotation is used now —
	# Sword.set_grip places the hilt at the palm directly — but that rotation is what lets the blade
	# follow the wrist through a swing while still starting from a sane carried angle.
	if sword:
		var b := _carry_basis()
		var gr := _grip_r.global_transform
		var sock_r := Transform3D(gr.basis.orthonormalized(), gr.origin)
		var desired_r := Transform3D(b, gr.origin - b * sword.grip_point())
		_sword_grip = sock_r.affine_inverse() * desired_r
	# shield: board upright on the left forearm, facing forward-left
	if shield:
		var n := (fwd * 0.95 - right * 0.30).normalized()
		var sx := up.cross(n).normalized()
		var gl := _grip_l.global_transform
		var sock_l := Transform3D(gl.basis.orthonormalized(), gl.origin)
		_shield_grip = sock_l.affine_inverse() * Transform3D(Basis(sx, n.cross(sx), n), gl.origin)
	_grips_ready = true


var tool_belt: ToolBelt


## The tool-weapons are built HERE rather than authored into each player scene. There are four
## player scenes and one tool set; adding a node to all four so that three of them can carry a rope
## is bookkeeping with no decision in it. Same doctrine the autoloads follow — Dialogue and Hud
## construct their own UI rather than asking every scene to provide it.
func _setup_tools() -> void:
	tool_belt = ToolBelt.new()
	tool_belt.name = "ToolBelt"
	add_child(tool_belt)


# --- Who is driving ---------------------------------------------------------------------------
#
# The states used to read Input directly, which quietly said "there is exactly one of these
# bodies". The directional-combat work needed an enemy that IS the player — same rig, same states,
# same rules — and an AI cannot drive a body whose decisions come from a global. So the decisions
# moved to a FighterIntent child, and the states read that. See scripts/combat/fighter_intent.gd.
#
# Nothing else had to change: a scene that brought no intent gets a PlayerIntent here, so the
# three player scenes that know nothing about any of this behave exactly as they did.

var intent: FighterIntent                     ## what this body is trying to do (person or brain)
var guard_pose: GuardPose                     ## the directional guard's arm override, if any

## The group this body swings at. The human's enemies are in "enemy"; the duelist built from this
## same script flips it to "player". Read by acquire_target and by the duel brain.
@export var target_group := &"enemy"


func _setup_intent() -> void:
	for c in get_children():
		if c is FighterIntent:
			intent = c as FighterIntent
			_intent_first()
			return
	intent = PlayerIntent.new()
	intent.name = "PlayerIntent"
	add_child(intent)
	_intent_first()


## THE INTENT MUST TICK BEFORE THE STATE THAT READS IT. Physics callbacks run in tree order, so an
## intent appended after the StateMachine is filled in AFTER the state has already read it — every
## decision arrives a frame late, which on a directional guard is the difference between covering
## the blow and not. Moving it to the front costs nothing and removes the whole class of bug.
func _intent_first() -> void:
	if intent and intent.get_index() != 0:
		move_child(intent, 0)


## Is a person at the controls? The state machine asks before it forwards InputEvents: without
## this, every AI-driven body in the scene would also react to the human's key presses, because
## _unhandled_input reaches every node in the tree.
func is_input_driven() -> bool:
	return intent is PlayerIntent


## The current state's name, or "" — the one thing several collaborators want off the FSM and the
## only reason they would otherwise need a reference to it.
func state_name() -> String:
	return String(_fsm.current_state.name) if _fsm and _fsm.current_state else ""


## True while aiming from the left stick rather than the mouse. Read by PlayerIntent, which owns
## the movement mapping that depends on it.
func gamepad_aim() -> bool:
	return _gamepad_aim


## Pause or resume the animation clock, never the mixer itself. While paused,
## DirAttack evaluates at zero delta so modifiers always receive the authored pose.
func set_tree_active(on: bool) -> void:
	if _tree:
		_tree.active=true
		if _fsm.has_state("DirAttack"):
			_tree["parameters/Slash/ActionClock/scale"] = 1.0 if on else 0.0
		else:
			_tree.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS if on else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

func evaluate_held_pose() -> void:
	if _tree and not _fsm.has_state("DirAttack"):
		_tree.advance(0.0)

func update_combat_animation(delta: float) -> void:
	if not _tree or not _fsm.has_state("DirAttack"): return
	var st := state_name()
	var mobile: bool = st == "Guard" or (st == "DirAttack" and _fsm.current_state.charging())
	var speed := Vector2(velocity.x, velocity.z).length()
	var target := 1.0 if mobile else 0.0
	var path := "parameters/Slash/Legs/blend_amount"
	_tree[path] = move_toward(float(_tree[path]), target, delta * 9.0)
	_tree["parameters/Slash/Gait/blend_position"] = clampf(speed / 1.8, 0.0, 1.0)


## Which way this body's guard is pointing, or SwingDir.NONE if it is not guarding. The opponent's
## AI and the HUD both read it; neither should have to know the state machine's shape.
func current_guard_dir() -> int:
	var st = _fsm.current_state if _fsm else null
	if st != null and st.has_method("guard_dir"):
		return st.guard_dir()
	return SwingDir.NONE


## Which way this body's wind-up is aimed, or SwingDir.NONE if it is not winding one up. THE TELL:
## it is what the duelist reads to time its guard, and what the HUD draws so a person can do the
## same. A swing already thrown answers NONE — by then there is nothing left to react to.
func charging_dir() -> int:
	var st = _fsm.current_state if _fsm else null
	if st != null and st.has_method("charging") and st.charging():
		return st.pending_dir()
	return SwingDir.NONE


## Someone's guard answered our swing. Punishes the attacker rather than merely sparing the
## defender, which is what makes a correct read worth making. Found by _find_entity from the
## hitbox, the same walk _do_parry already uses to reach stagger(). Named for the event rather
## than the effect ("recoil") because Shield already has a recoil() and the walk up from a sword
## hitbox must not be able to find the wrong one.
func on_swing_blocked() -> void:
	var st = _fsm.current_state if _fsm else null
	if st != null and st.has_method("blocked"):
		st.blocked()


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_toon = get_node_or_null("ToonSkin")   # the body's flash channel; every current hero has one
	_setup_intent()
	_setup_animations()
	_setup_weapon_sockets()
	_setup_tools()
	# The dodge smear is NOT oriented here: it lies flat across the dash direction, which is only
	# known when a dash starts, so the Dash state spans it on entry.


## BoneAttachment3D is the standard "ride a bone" node. The sockets are created in code
## because the skeleton lives INSIDE the imported .blend scene (found by search, like the
## AnimationPlayer — hard paths would break on reimport). If anything is missing the
## weapons simply keep their old fixed poses.
func _setup_weapon_sockets() -> void:
	var skel := find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skel == null:
		return
	if skel.find_bone("RightHand") < 0 or skel.find_bone("LeftHand") < 0:
		return
	_grip_r = BoneAttachment3D.new()
	_grip_r.name = "GripR"
	skel.add_child(_grip_r)
	_grip_r.bone_name = "RightHand"
	_grip_l = BoneAttachment3D.new()
	_grip_l.name = "GripL"
	skel.add_child(_grip_l)
	_grip_l.bone_name = "LeftHand"
	# Procedural "shield up": a modifier under the skeleton that raises the left arm to guard.
	# Added AFTER the sockets so it sits later in the child order (runs after the pose is set);
	# the GripL socket then reads the guarded hand and carries the shield up with it.
	# Skipped entirely on a shieldless body — nothing would ever set its amount above 0.
	if shield:
		_arm_guard = ArmGuard.new()
		_arm_guard.name = "ArmGuard"
		skel.add_child(_arm_guard)
		shield.hand_driven = true
	# THE DIRECTIONAL GUARD, on the same principle and for the same reason: the library has one
	# `block` stance and the mechanic needs four, so the sword arm is rotated out of it here rather
	# than in clips nobody authored. Only a body carrying the Guard state can ever raise it, so it
	# is skipped everywhere else — see scripts/combat/guard_pose.gd.
	if _fsm and _fsm.has_state("Guard"):
		guard_pose = load("res://scripts/combat/guard_ik.gd").new()
		guard_pose.name = "GuardPose"
		skel.add_child(guard_pose)
	if sword:
		sword.hand_driven = true
	_calibrate_grips()                        # async: solves the grips once the pose settles


## The retargeted clips live in player3_anims.tres, assigned to the AnimationTree in the editor
## (extracted from the FBXs at import via "Save to File" — so the editor sees them too, not just
## the game). Here we only sanitize what import options can't express, then switch the tree on.
## The model's AnimationPlayer is found by SEARCH (the imported tree rebuilds on reimport, so a
## hard path would break) and only serves the hand-authored fallback clip.
func _setup_animations() -> void:
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim and _anim.has_animation("run"):
		_anim.get_animation("run").loop_mode = Animation.LOOP_LINEAR
	_tree = get_node_or_null("AnimationTree") as AnimationTree
	if _tree and _tree.has_animation("idle"):
		# Every fighter owns its clip timing and Slash selection. Imported resources are shared.
		_tree.active = false
		_tree.tree_root = _tree.tree_root.duplicate(true)
		for library_name in _tree.get_animation_library_list():
			var original := _tree.get_animation_library(library_name)
			var library := AnimationLibrary.new()
			for animation_name in original.get_animation_list():
				library.add_animation(animation_name, original.get_animation(animation_name).duplicate(true))
			_tree.remove_animation_library(library_name)
			_tree.add_animation_library(library_name, library)
		for clip in locomotion_clips:
			if _tree.has_animation(clip):
				_strip_root_drift(_tree.get_animation(clip))
		for clip in loop_clips:
			if _tree.has_animation(clip):
				_tree.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		# Carve the combo CADENCE into the clips (see ATTACK_TIMING): per step — speed up the
		# whole swing, compress the wind-up to that step's beat, then SLOW the tail after the
		# cancel point. Gameplay reads the post-warp fractions from attack_meta, always in sync.
		if _fsm.has_state("DirAttack") and _tree.has_animation("atk_cross"):
			attack_timing = attack_timing.duplicate(true)
			attack_timing["atk_cross"] = attack_timing["atk_jab"].duplicate()
			_strip_root_drift(_tree.get_animation("atk_cross"))
		for clip: String in attack_timing:
			if not _tree.has_animation(clip):
				continue
			var cfg: Dictionary = attack_timing[clip]
			var a := _tree.get_animation(clip)
			if _fsm.has_state("DirAttack") and clip in ["atk_c","atk_cross","atk_b","atk_swing"]:
				var duration:=1.10 if clip=="atk_c" else .94
				_retime(a,a.length/duration)
				attack_meta[clip]={"strike":.34 if clip == "atk_swing" else .48,"cancel":.88}
				continue
			_retime(a, cfg.speed)
			var strike_t: float = a.length * cfg.strike
			var cancel_t: float = a.length * cfg.cancel
			var shift := _compress_windup(a, strike_t, cfg.windup)
			strike_t -= shift
			cancel_t -= shift
			_stretch_tail(a, cancel_t, cfg.tail)
			attack_meta[clip] = {
				"strike": strike_t / a.length,
				"cancel": maxf(cancel_t / a.length, cfg.get("cancel_min", 0.0)),
			}
		if _tree.has_animation("atk_combo"):
			_retime(_tree.get_animation("atk_combo"), attack_speed)
		# Advance the tree in PHYSICS so it writes bone poses BEFORE the idle-phase skeleton
		# modifier (ArmGuard) runs — otherwise the animation overwrites the procedural guard.
		if _fsm.has_state("DirAttack"):
			load("res://scripts/combat/combat_animation_layers.gd").install(_tree)
		_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		_tree.active = true
		_playback = _tree["parameters/playback"]
		_playback.start("Idle")
	else:
		_tree = null


## Mixamo clips not exported "in place" walk the hips across the floor — but the CAPSULE owns
## locomotion here. Pin the hips' XZ to the first key (the vertical bob stays).
func _strip_root_drift(a: Animation) -> void:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D \
				and str(a.track_get_path(i)).ends_with(":Hips"):
			if a.track_get_key_count(i) == 0:
				continue
			var first: Vector3 = a.track_get_key_value(i, 0)
			for k in a.track_get_key_count(i):
				var v: Vector3 = a.track_get_key_value(i, k)
				a.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))


## Piecewise time-warp: squeeze everything BEFORE `strike_t` into `target` seconds and shift the
## rest left, so contact comes fast but the swing itself stays readable. Monotonic (no re-sort).
## Returns the seconds removed (0 if the wind-up was already short enough).
func _compress_windup(a: Animation, strike_t: float, target: float) -> float:
	if strike_t <= target:
		return 0.0
	var shift := strike_t - target
	var k := target / strike_t
	for i in a.get_track_count():
		for j in a.track_get_key_count(i):
			var t := a.track_get_key_time(i, j)
			a.track_set_key_time(i, j, t * k if t < strike_t else t - shift)
	a.length -= shift
	return shift


## Slow everything AFTER `from_t` by `scale` (<1 = slower): the follow-through/recovery gains
## weight while the strike stays crisp. Monotonic — keys before from_t untouched.
func _stretch_tail(a: Animation, from_t: float, scale: float) -> void:
	if scale >= 0.999 or scale <= 0.0:
		return
	for i in a.get_track_count():
		# DESCENDING: times grow, so walking backward can never collide with a not-yet-moved
		# key ahead of us (ascending would trigger a mid-loop re-sort and corrupt indices)
		for j in range(a.track_get_key_count(i) - 1, -1, -1):
			var t := a.track_get_key_time(i, j)
			if t > from_t:
				a.track_set_key_time(i, j, from_t + (t - from_t) / scale)
	a.length = from_t + (a.length - from_t) / scale


## Uniformly retime a clip: divide every key time (and the length) by `scale`. >1 speeds up, <1
## slows down. Lets the slow melee mocap read as snappy combat — and lets a clip that is ALREADY
## too fast to read (Quaternius' 0.43 s Sword_Regular_A) be stretched out instead.
##
## DIRECTION MATTERS, for the reason _stretch_tail spells out below: moving a key past its
## neighbour makes Godot re-sort the track, and every index after it shifts under the loop. Speeding
## up pulls keys EARLIER, so ascending is safe — each key lands before anything we haven't touched.
## Slowing down pushes them LATER, so it has to walk backward instead. Getting this wrong doesn't
## look like a bad clip: the track array shrinks mid-iteration and the read runs off the end.
func _retime(a: Animation, scale: float) -> void:
	if scale <= 0.0 or is_equal_approx(scale, 1.0):
		return
	var moves_later := scale < 1.0
	for i in a.get_track_count():
		var n := a.track_get_key_count(i)
		for j in n:
			var k := (n - 1 - j) if moves_later else j
			a.track_set_key_time(i, k, a.track_get_key_time(i, k) / scale)
	a.length = a.length / scale


## Play one clip on the shared "Slash" state by swapping its animation (no per-action tree
## states needed). Returns the clip's (retimed) length so the caller can time itself. Used by
## the combo states for swings and by Jump for its start/air/land pieces.
func play_clip(clip: String) -> float:
	if _tree == null or _playback == null:
		return 0.4
	# Never point the shared action node at a missing clip (which outputs rest pose).
	if not _tree.has_animation(clip):
		push_warning("Missing action animation: " + clip)
		return 0.4
	var sm := _tree.tree_root as AnimationNodeStateMachine
	var slash := sm.get_node("Slash")
	var node := (slash.get_node("Action") if slash is AnimationNodeBlendTree else slash) as AnimationNodeAnimation
	if node:
		node.animation = clip
	if _playback.get_current_node() == "Slash":
		_playback.start("Slash")       # restart with the new clip (a combo step)
	else:
		_playback.travel("Slash")      # blend in when entering fresh
	var a := _tree.get_animation(clip)
	return a.length if a else 0.4


## The combo states' original entry point — same mechanism, attack-flavoured name.
func play_attack(clip: String) -> float:
	return play_clip(clip)


## Whether the body's library carries this clip — the Mixamo pair has no jump pieces, and a
## state that plays clips blindly would hand play_clip a name get_animation answers null to.
func has_clip(clip: String) -> bool:
	return _tree != null and _tree.has_animation(clip)


## Procedural body animation, driven purely by how fast we're moving. Runs every rendered frame
## (independent of the state machine): a run-bounce + a lean into the run, and a gentle idle breathe.
## Animates the Visuals node only — the collider stays put.
func _process(delta: float) -> void:
	_anim_t += delta
	_update_aim()                        # refresh the stick aim direction (if on a controller)
	_update_resources(delta)             # shield stamina drain/regen + arrow quiver refill
	var planar := Vector2(velocity.x, velocity.z).length()
	var run := clampf(planar / move_speed, 0.0, 1.0)

	# ANIMATION: gameplay decides, the AnimationTree blends (the standard Godot split).
	# One blend axis: -1 = backpedal, 0.4 = slow run, 1.0 = fast run. Backpedal = moving
	# mostly against the facing (we aim with the mouse, so running from an enemy while
	# facing it reads correctly as a backward run).
	if _playback:
		var state_name: String = String(_fsm.current_state.name) if _fsm.current_state else ""
		if state_name in ["Attack", "DashAttack", "Jump", "DirAttack"] or (state_name == "Hurt" and has_clip("hurt_chest")):
			# These states drive the Slash node themselves, swapping its clip per swing (or per
			# jump phase). Anything that also writes the tree here would fight them — and the
			# locomotion branch below WOULD, because a lunge (or a running jump) is moving fast
			# enough to satisfy `run > 0.15`. That is the whole bug: the swing plays for one
			# frame and then the run blend takes the body back.
			pass
		elif state_name == "Guard":
			# The DIRECTIONAL guard holds the `block` stance on the Slash node and rotates the arm
			# out of it with a skeleton modifier. Both would be stomped within a frame by the
			# locomotion branch below — the same fight documented above, and the reason a guarded
			# fighter used to snap back into a run pose the instant they shuffled.
			pass
		elif state_name == "Block" and shield == null:
			# The SHIELDLESS guard: Block plays the sword-parry pose on the Slash node and the
			# branches below would stomp it within a frame — the exact
			# fight documented above. Shield bodies fall through on purpose: they keep their
			# locomotion while guarding, because their guard visual is the shield itself.
			pass
		elif state_name == "Shoot":
			# Drawing the bow: the aim-walk set, blended by movement in FACING space
			# (x = strafe right, y = forward — matches the BlendSpace2D points).
			# Normalized against the shoot state's slowed speed so the shuffle reads
			# as a full walk, not a barely-moving blend.
			var fwd := -visuals.global_transform.basis.z
			var right := visuals.global_transform.basis.x
			var cap: float = move_speed * float(_fsm.current_state.get("move_scale"))
			var amount := clampf(planar / maxf(cap, 0.01), 0.0, 1.0)
			var dir := Vector3(velocity.x, 0.0, velocity.z).normalized() if planar > 0.1 else Vector3.ZERO
			_tree["parameters/Aim/blend_position"] = Vector2(right.dot(dir), fwd.dot(dir)) * amount
			if _playback.get_current_node() != "Aim":
				_playback.travel("Aim")
		elif run > 0.15:
			# Move is a 2D blend of the sword-and-shield locomotion clips (they carry the
			# weapons): forward/back + strafe left/right, placed in the character's FACING
			# frame (x = strafe right, y = forward) — same convention as the Aim blend. So
			# running sideways-to-your-aim plays the strafe, not a moonwalk.
			#
			# A face_movement body has no strafes to blend into (see face_aim_direction), so its
			# Move is a 1D SPEED ramp instead — walk through jog to sprint, normalized 0..1 against
			# move_speed. The body is already pointed down its travel direction, so speed is the
			# only thing left to say.
			if face_movement:
				_tree["parameters/Move/blend_position"] = run
			else:
				var fwd := -visuals.global_transform.basis.z
				var right := visuals.global_transform.basis.x
				var vdir := Vector3(velocity.x, 0.0, velocity.z).normalized()
				_tree["parameters/Move/blend_position"] = Vector2(right.dot(vdir), fwd.dot(vdir))
			if _playback.get_current_node() != "Move":
				_playback.travel("Move")
		elif _playback.get_current_node() != "Idle":
			_playback.travel("Idle")
	elif _anim and _anim.has_animation("run"):
		# fallback: the single hand-authored clip, if the Mixamo set isn't available
		if run > 0.15:
			if _anim.current_animation != "run":
				_anim.play("run", 0.2)
			_anim.speed_scale = 0.7 + 0.6 * run
		elif _anim.current_animation == "run":
			_anim.play("T-Pose", 0.25)

	# Procedural shield-up: ease the left-arm guard in while the Block state is active and out
	# otherwise. The body keeps playing normal locomotion (Idle/Move) underneath — the guard is
	# a bone override layered on top, so you can walk/run/strafe with the shield raised.
	var want_guard := 1.0 if state_name() in ["Block", "Guard"] else 0.0
	_guard = lerpf(_guard, want_guard, 1.0 - exp(-guard_raise_speed * delta))
	if _arm_guard:
		_arm_guard.amount = _guard

	var target_bob: float
	if _anim != null:
		target_bob = 0.0                          # skeletal clips own the body motion
	elif run > 0.15:
		target_bob = absf(sin(_anim_t * bob_speed)) * bob_height * run
	else:
		target_bob = (sin(_anim_t * 2.2) * 0.5 + 0.5) * 0.02              # subtle idle breathe
	visuals.position.y = lerpf(visuals.position.y, target_bob, 1.0 - exp(-14.0 * delta))

	# Lean forward (about the visuals' local X, i.e. in the facing direction) proportional to speed.
	var target_lean := -lean_amount * run
	visuals.rotation.x = lerp_angle(visuals.rotation.x, target_lean, 1.0 - exp(-10.0 * delta))

	# Weapons chase their hand sockets with a damped follow (swing lag = heft). The socket
	# basis is orthonormalized so the model's 2.2 scale never leaks into the weapon.
	# DURING AN ATTACK the sword SNAPS to the hand (no lag) so the blade traces the fast slash
	# arc exactly — the heft-lag that reads nicely while walking makes the swing look detached.
	var attacking: bool = _fsm.current_state != null \
			and _fsm.current_state.name in ["Attack", "DashAttack", "DirAttack", "Guard"]
	if _grips_ready and _grip_r and sword:
		var gr := _grip_r.global_transform
		var sock := Transform3D(gr.basis.orthonormalized(), gr.origin)
		# Two opinions about which way the blade points, blended: the WRIST's (right during a
		# swing, nonsense during an empty-handed run) and the TORSO's (a stable carry pose,
		# recomputed live so it follows the body as it turns).
		var from_hand := (sock * _sword_grip).basis.orthonormalized()
		var want := _carry_basis().slerp(from_hand, 1.0 if attacking else hand_follow)
		if not _sword_basis_ready:
			_sword_basis = want
			_sword_basis_ready = true
		else:
			var speed := attack_follow_speed if attacking else sword_weight
			_sword_basis = _sword_basis.slerp(want, 1.0 - exp(-speed * delta))
		# The hilt is PLACED at the palm, never chased toward it — see Sword.set_grip.
		sword.set_grip(_sword_basis.orthonormalized(), gr.origin)
	if _grips_ready and _grip_l and shield:
		var gl := _grip_l.global_transform
		var t_l := Transform3D(gl.basis.orthonormalized(), gl.origin) * _shield_grip
		shield.follow_grip(t_l, 1.0 - exp(-shield_weight * delta))


# --- Movement helpers (called BY the active state) ------------------------------------------

## Where this body is trying to go, in world XZ. The mapping that produces it — camera yaw,
## lock-on bearing, the bow's planted aim — moved WHOLE into scripts/combat/player_intent.gd, and
## the reason is the mirror enemy: those are facts about a person at a screen, and an AI driving
## the same body has no screen. What is left here is the read, so every state keeps its old call.
func get_move_input() -> Vector2:
	return intent.move if intent else Vector2.ZERO

var _camera_rig: Node3D
var _toon: Node                     ## ToonSkin child — the body's hit-flash channel (red sting)
var _aim_dir := Vector3(0, 0, -1)   ## aim/facing direction (world, ground plane) — for gamepad
var _gamepad_aim := false           ## true = aim from the LEFT STICK, false = aim from the mouse


## Track the active device so we switch between mouse cursor and controller. The RIGHT stick is
## camera-only (see CameraRig), so it doesn't flip aiming here — a joypad BUTTON or the LEFT stick
## does. Non-consuming — states still get the same events.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 1.0:
		_gamepad_aim = false
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_gamepad_aim = true
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if m.axis <= JOY_AXIS_LEFT_Y and absf(m.axis_value) > 0.5:   # left stick / triggers, not the aim stick
			_gamepad_aim = true


## On a controller, the player faces/aims with the LEFT STICK — where you move is where you face,
## and where melee swings and the bow fires. The RIGHT stick is camera-only. Keep the last
## direction while the stick is centred so the body holds its facing (incl. planted bow aim).
func _update_aim() -> void:
	if not _gamepad_aim:
		return
	if _camera_rig == null:
		_camera_rig = get_tree().get_first_node_in_group("camera_rig") as Node3D
	var yaw: float = _camera_rig.rotation.y if _camera_rig else 0.0
	var ls := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if ls.length() > 0.15:
		var v := Vector3(ls.x, 0.0, ls.y).rotated(Vector3.UP, yaw)
		if v.length() > 0.01:
			_aim_dir = v.normalized()


## Depth-driven wading multiplier, written each physics tick by the WaterWader child (1.0 on
## dry land). Lives in the movement helper so every state that walks through apply_movement
## slows in water for free — and Dash, which writes velocity directly, deliberately does not.
var water_slow := 1.0


## Drive the body toward `input`. `speed_scale` < 1 gives the "slower, not frozen" feel while
## attacking / blocking / shooting; with input == 0 this naturally decelerates (acts as friction).
func apply_movement(input: Vector2, delta: float, speed_scale := 1.0) -> void:
	var dir := Vector3(input.x, 0.0, input.y).normalized()
	var target := dir * move_speed * speed_scale * water_slow
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

func apply_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)

func apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


## The unguarded half, for the Jump state: no floor-zeroing, because the frame after the jump
## impulse the body is still touching down and apply_gravity would wipe the launch.
func apply_air_gravity(delta: float) -> void:
	velocity.y -= _gravity * delta

## THE STRAFE QUESTION. player/player2 always face the CURSOR, so running sideways plays a strafe
## clip and reads correctly. player3's clip set (Quaternius UAL) has no strafes and no backpedal —
## forward locomotion only — so a cursor-facing body running sideways would moonwalk. With
## `face_movement` on, the body turns to where it TRAVELS instead, which is the ordinary top-down
## answer and costs nothing but the ability to walk one way while aiming another.
##
## Attacks are the exception, and always aim: attack.gd passes force_aim so a swing still lands
## where the cursor is. Between swings the body is free to turn back into its run.
@export var face_movement := false

## Smoothly rotate ONLY the visuals. Forward = local -Z (Godot convention).
func face_aim_direction(delta: float, force_aim := false) -> void:
	var to_aim: Vector3
	var locked_target := combat_lock_target()
	if locked_target:
		to_aim = locked_target.global_position-global_position
	elif face_movement and not force_aim and Vector2(velocity.x, velocity.z).length() > 0.5:
		to_aim = Vector3(velocity.x, 0.0, velocity.z)
	else:
		to_aim = aim_point() - global_position
	to_aim.y = 0.0
	if to_aim.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-to_aim.x, -to_aim.z)
	visuals.global_rotation.y = lerp_angle(visuals.global_rotation.y, target_yaw, 1.0 - exp(-rotation_speed * delta))

## Rotate the visuals to look at a world point. Same easing as face_aim_direction — this is what a
## swing uses once it has committed to a target, so the turn reads as the player choosing it.
func combat_lock_target() -> Node3D:
	if not is_input_driven(): return null
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig == null or not rig.has_method("locked"): return null
	var target: Node3D = rig.locked()
	if not is_instance_valid(target): return null
	var hp := target.get_node_or_null("Health") as Health
	return target if hp == null or hp.is_alive() else null

func face_point(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	visuals.global_rotation.y = lerp_angle(visuals.global_rotation.y, atan2(-to.x, -to.z),
			1.0 - exp(-rotation_speed * delta))


# --- Targeting -------------------------------------------------------------------------------
#
# THE MEASURED PROBLEM (tools/measure_attack.gd). The damage volume is a box 1.484 m deep and
# 0.781 m to each side, so contact against a 0.6 m-radius enemy ends at 2.08 m dead ahead. Two
# things follow, and both are invisible to the player:
#
#   1. The cliff is SHARP. At 2.10 m you are 16 mm short and the swing simply passes through. You
#      swing again from the same spot and miss again — there is no feedback telling you that a
#      hand's width forward is the whole difference.
#   2. Dead ahead is the WORST angle. A box's corner reaches further than its face, so the same
#      2.10 m that whiffs head-on connects at 20 degrees off. Aiming carefully makes it worse.
#
# Neither is fixable by tuning the box; a bigger box hits things you did not mean to. The fix is
# for a swing to COMMIT to a target — turn exactly at it (kills the angular error) and close the
# last few centimetres (kills the cliff). Everything here supports those two moves.

@export var attack_step_max := 1.0    ## furthest a swing will close on its own (m)
@export var attack_step_speed := 9.0  ## cap on how fast it closes (m/s)
@export var target_arc := 70.0        ## half-angle a swing may correct across (deg)


## The radius of a target's hurt volume — how much of the gap its own body closes. Read off the
## HurtBox shape so a big enemy is genuinely easier to reach than a small one, and so this keeps
## working for anything with a HurtBox rather than only for the training dummy.
## A null target means "the typical enemy" — used when sizing the acquisition radius, before we
## know who we are swinging at.
const TYPICAL_HURT_RADIUS := 0.6

static func hurt_radius_of(target: Node) -> float:
	if target == null:
		return TYPICAL_HURT_RADIUS
	if target.has_method("hurt_radius"):
		return target.hurt_radius()
	var hb := target.get_node_or_null("HurtBox")
	if hb:
		for c in hb.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is CapsuleShape3D:
				return ((c as CollisionShape3D).shape as CapsuleShape3D).radius
	return TYPICAL_HURT_RADIUS


## Centre-to-centre distance at which a swing connects with `target`, dead ahead.
##
## Sword.reach() folds in Perception's bonus AND grows the damage box by the same amount, so this
## number and the volume it describes cannot drift apart — which they would if the bonus were added
## here instead. See the comment on Sword.reach().
func contact_range(target: Node) -> float:
	return (sword.reach() if sword else 1.4) + hurt_radius_of(target)


## WHAT A SWING IS WORTH. Rolled ONCE per swing by the state that owns it — never inside
## HitBox._try_hit, which runs per target and would hand a swing that catches three enemies three
## separate verdicts. One swing, one crit.
##
## Here rather than in attack.gd because DashAttack asks the same question, and two states holding
## two opinions about what a hit is worth is exactly the drift this file's header warns about.
func swing_damage() -> int:
	var traits := get_node_or_null("/root/Traits")
	if traits == null:
		return 1
	var dmg := 1
	# THE BERSERK FINISHER, on the last block only. Instinct's promise is that being nearly dead is
	# a state you fight BETTER in, not merely one you survive.
	if health.hp <= 1:
		dmg += int(traits.berserk_damage())
	if randf() < float(traits.crit_chance()):
		dmg *= 2
		EventBus.combat_impact.emit(0.34)   # a crit that lands like a normal hit is not a crit
	return dmg


## Pick the enemy this swing should commit to.
##
## SCORED BY ANGLE FIRST, distance second, because the two errors are not equally forgivable: a few
## degrees off puts you outside the box entirely, while a few centimetres short is something the
## attack step can close. So a slightly further enemy you are pointing AT beats a nearer one you
## are pointing PAST. Returns null when nothing is worth turning toward, and the swing then goes
## wherever the cursor said — never silently steering a deliberate whiff into a hit.
func acquire_target(max_range: float, half_angle_deg: float) -> Node3D:
	var aim := aim_point() - global_position
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		aim = -visuals.global_transform.basis.z
	aim = aim.normalized()
	var best: Node3D = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group(target_group):
		var e := n as Node3D
		if e == null or e == self or not is_instance_valid(e):
			continue
		var hp := e.get_node_or_null("Health") as Health
		if hp and not hp.is_alive():
			continue
		var to := e.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.01 or dist > max_range:
			continue
		var ang := rad_to_deg(aim.angle_to(to / dist))
		if ang > half_angle_deg:
			continue
		var score := ang / maxf(half_angle_deg, 1.0) + 0.5 * dist / maxf(max_range, 0.01)
		if score < best_score:
			best_score = score
			best = e
	return best


## Where the player is aiming, as a world point on the player's ground plane. With a controller
## it's a point far along the LEFT-stick facing direction (the bow clamps distance by charge,
## melee only cares about direction). With mouse+keyboard it's the point under the cursor.
func aim_point() -> Vector3:
	# A body that named its own facing (any AI-driven one) is authoritative about it. Falling
	# through to the branches below would hand it the human's mouse — see FighterIntent.look.
	if intent and intent.look != Vector2.ZERO:
		var l := intent.look.normalized()
		return global_position + Vector3(l.x, 0.0, l.y) * 50.0
	if _gamepad_aim:
		return global_position + _aim_dir * 50.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position + Vector3(0, 0, -1)
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var ground := Plane(Vector3.UP, global_position.y)
	var hit = ground.intersects_ray(from, dir)
	return hit if hit != null else global_position + Vector3(0, 0, -1)


# --- Input buffering (the Death's Door pattern) ----------------------------------------------
# A press that can't act RIGHT NOW (e.g. attack pressed mid-dash) is remembered briefly and
# consumed the moment the current action allows — instead of being dropped. Mash-friendly.

@export var attack_buffer_time := 0.3   ## seconds an early attack press stays valid

var _attack_buffer_until := 0.0

func buffer_attack() -> void:
	_attack_buffer_until = Time.get_ticks_msec() / 1000.0 + attack_buffer_time

func consume_attack_buffer() -> bool:
	if Time.get_ticks_msec() / 1000.0 <= _attack_buffer_until:
		_attack_buffer_until = 0.0
		return true
	return false


# --- Stamina (spent ONLY by blocked hits) & arrow ammo ---------------------------------------
# DESIGN: dodging is the real defence; the shield is a SAFETY CARD you can't overuse. Holding
# the guard up costs nothing — stamina only drops when the shield actually EATS A HIT (~3 hits
# empty it; a parry is free, that's the skill reward). It refills SLOWLY, and only while the
# shield is down — you can't turtle and recover at the same time. Empty = guard break (Block
# force-exits, can't re-raise until can_block()).
# Arrows are a small quiver that refills one arrow every arrow_regen_time seconds.

@export var max_stamina := 100.0
@export var block_hit_stamina := 35.0   ## cost when the shield eats a hit (3 hits = guard break)
@export var stamina_regen := 8.0        ## per second while the shield is DOWN (slow on purpose)
@export var max_arrows := 6
@export var arrow_regen_time := 2.5     ## seconds to recover one arrow

var stamina := 100.0
var arrows := 6
var _arrow_regen_t := 0.0

func _update_resources(delta: float) -> void:
	# BOTH GUARDS, or the directional one refills while it is up — and "you cannot turtle and
	# recover at the same time" is the whole reason the stamina exists.
	var blocking: bool = state_name() in ["Block", "Guard", "DirAttack"]
	if not blocking:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
	if arrows < max_arrows:
		_arrow_regen_t += delta
		if _arrow_regen_t >= arrow_regen_time:
			_arrow_regen_t = 0.0
			arrows += 1

func can_block() -> bool:
	return stamina > 15.0                # hysteresis: no shield-flicker at the empty edge

func spend_block_hit() -> void:
	stamina = maxf(stamina - block_hit_stamina, 0.0)

func use_arrow() -> void:
	arrows = maxi(arrows - 1, 0)


# --- Dash cooldown --------------------------------------------------------------------------

func can_dash() -> bool:
	return Time.get_ticks_msec() / 1000.0 >= _dash_ready_at

func start_dash_cooldown() -> void:
	_dash_ready_at = Time.get_ticks_msec() / 1000.0 + dash_cooldown

func can_shoot() -> bool:
	return arrows > 0 and Time.get_ticks_msec() / 1000.0 >= _shoot_ready_at

func start_shoot_cooldown() -> void:
	_shoot_ready_at = Time.get_ticks_msec() / 1000.0 + shoot_cooldown


# --- Damage reactions (Health drives the state machine) -------------------------------------

func _on_damaged(_amount: int, source: Node) -> void:
	# Knock back away from whatever hit us, then stagger.
	if source is Node3D:
		var away := global_position - (source as Node3D).global_position
		away.y = 0.0
		if away.length() > 0.01:
			# THE ATTACK'S OWN SHOVE, when it has one. A kick that merely hurts is a worse slam;
			# a kick that PUTS YOU BACK OUT at the range the mace works at is what makes spacing
			# the subject of the fight. Carried on the hitbox rather than passed as an argument,
			# because take_damage's signature is shared by everything that deals damage.
			var kb := knockback_force
			if source and source.has_meta("knockback"):
				kb = maxf(kb, float(source.get_meta("knockback")))
			# Sword cuts stagger a person; they do not launch them like a mace.
			if source and int(source.get_meta("swing_dir", SwingDir.NONE)) != SwingDir.NONE:
				kb = 1.1
				var attacker := _find_entity(source,"on_swing_blocked") as Node3D
				if attacker:
					away = global_position-attacker.global_position
					away.y = 0.0
			velocity = away.normalized() * kb
	# THE STING — everything below is gated by construction on a hit that actually applied
	# (Health only emits `damaged` after hp changed), which is what keeps the absorbed-hit-
	# silence rule intact without a single extra check here.
	#   Body: the red flash, through the same toon channel enemies use.
	#   Hands/screen/time: contact_taken (thud hitstop, shake, strong-motor rumble); the HUD's
	#   damage vignette listens to this same `damaged` signal on its own.
	#   Mercy: a short post-hit window so a fan of three bolts costs one heart, not three —
	#   simultaneous multi-hits read as ONE blow, and hp should agree with the read.
	if _toon != null:
		_toon.flash(Color(1.0, 0.22, 0.18), 1.0, 0.35)
	CombatFeedback.contact_taken()
	health.extend_invulnerable(0.5)
	_fsm.transition_to("Hurt")

func _on_died() -> void:
	_fsm.transition_to("Dead")


# --- Block / parry ---------------------------------------------------------------------------
# Called by the HurtBox before damage is applied (via apply_hit -> on_incoming_hit). Returns the
# damage that should actually go through: 0 if we blocked or parried a frontal attack.

func on_incoming_hit(damage: int, source: Node) -> int:
	# THE COLOUR CONTRACT (see projectile.gd): a purple bolt is unparriable — neither the guard
	# nor the window answers it, so it skips this interception entirely and only feet help
	# (dash i-frames live in Health, a jump takes you off the ground wave's floor). It exists
	# so that holding block is a choice with a counter, not a stance.
	if source is Projectile and not (source as Projectile).parriable:
		return damage
	var st = _fsm.current_state

	# THE DIRECTIONAL GUARD, checked first because it is stricter. A hit that carries a swing
	# direction (sword.gd stamps one on every directional swing) is answered only by a guard
	# pointing the way it came from; guess wrong and the whole blow lands. That asymmetry IS the
	# mechanic — a guard that half-works is a guard you never have to aim.
	#
	# Everything WITHOUT a direction falls through to the omni-guard below: projectiles, the
	# thrown rock, any blow whose attacker never picked a direction. So a fight only tightens where
	# both sides can play by the strict rule.
	var incoming: int = int(source.get_meta("swing_dir", SwingDir.NONE)) if source else SwingDir.NONE
	if st != null and st.has_method("blocks") and incoming != SwingDir.NONE:
		if "--trace-combat" in OS.get_cmdline_user_args(): print("GUARD_CONTACT ",name," incoming=",incoming," guard=",st.guard_dir()," frontal=",_is_frontal_hit(source)," valid=",st.blocks(incoming)," stamina=",stamina)
		if stamina <= 0.0 or not _is_frontal_hit(source) or not st.blocks(incoming):
			return damage                     # read wrong: take it in full
		if st.is_parry_active():
			_do_parry(source)
		else:
			_do_block(source)
		return 0

	if st != null and st.has_method("is_parry_active") and _is_frontal_hit(source):
		if st.is_parry_active():
			_do_parry(source)
		else:
			_do_block(source)
		return 0
	return damage

## Is the attack coming from in front of us? (a shield only guards the way you face)
func _is_frontal_hit(source: Node) -> bool:
	if not (source is Node3D):
		return true
	var origin: Node3D=source as Node3D
	var wielder:=_find_entity(source,"on_swing_blocked") as Node3D
	if wielder: origin=wielder
	var to_src: Vector3 = origin.global_position - global_position
	to_src.y = 0.0
	if to_src.length() < 0.05:
		return true
	var facing := -visuals.global_transform.basis.z
	facing.y = 0.0
	if "--trace-combat" in OS.get_cmdline_user_args(): print("FRONTAL ",name," from=",origin.name," to=",to_src," facing=",facing," at=",global_position)
	return facing.normalized().dot(to_src.normalized()) > 0.25

func on_swing_parried() -> void:
	var st = _fsm.current_state
	if st != null and st.has_method("blocked"):
		if st.name == "DirAttack":
			st.blocked(0.65)
		else:
			st.blocked()

func _do_block(source: Node) -> void:
	EventBus.combat_impact.emit(0.045)
	_sword_block_feedback(source, false)
	spend_block_hit()                         # blocked hits chip the shield stamina
	if shield:                                # the sword body guards with a pose, not a board
		shield.recoil()
	# THE ATTACKER PAYS FOR BEING READ. Without this a blocked swing costs the attacker nothing but
	# time, and the defender's correct guess buys them only the absence of damage — there is no
	# opening to punish into, so the exchange never resolves and both fighters just take turns.
	var swinger := _find_entity(source, "on_swing_blocked")
	if swinger:
		swinger.on_swing_blocked()
	if stamina <= 0.0 and _fsm.has_state("Hurt"):
		_fsm.transition_to("Hurt")
		_fsm.current_state.extend_stun(0.55)
	if source is Node3D:                      # small shove backward
		var away := global_position - (source as Node3D).global_position
		if swinger is Node3D:
			away = global_position - swinger.global_position
		away.y = 0.0
		if away.length() > 0.01:
			var kick := .35 if sword and shield == null else 3.0
			velocity.x = away.normalized().x * kick
			velocity.z = away.normalized().z * kick

func _do_parry(source: Node) -> void:
	stamina = maxf(0.0, stamina - 10.0)
	_sword_block_feedback(source, true)
	if shield:
		shield.flash_parry()
		shield.recoil()
	Fx.hitstop(0.055, 0.18)
	EventBus.combat_impact.emit(0.10)
	var scene := load("res://scenes/fx/parry_flash.tscn")
	if scene and shield:
		var flash := (scene as PackedScene).instantiate()
		get_tree().current_scene.add_child(flash)
		(flash as Node3D).global_position = global_position + Vector3(0, 1.0, 0) - visuals.global_transform.basis.z * 0.8
	var enemy := _find_entity(source, "stagger")
	if enemy:
		enemy.stagger()
	elif _find_entity(source,"on_swing_parried"):
		_find_entity(source,"on_swing_parried").on_swing_parried()
	elif source is Projectile:
		# No attacker on the end of this hit — the projectile IS the attack. The parry reward
		# for melee is a stagger; for a bolt it is the bolt itself, sent home (see deflect()).
		(source as Projectile).deflect()


func _sword_block_feedback(source: Node, parried: bool) -> void:
	if shield or not sword: return
	var attacker := _find_entity(source,"on_swing_blocked") as Player
	if is_input_driven() or (attacker and attacker.is_input_driven()):
		CombatFeedback.rumble(.42 if parried else .18, .10 if parried else .14, .09 if parried else .055)
	if guard_pose and guard_pose.has_method("contact_recoil"):
		guard_pose.contact_recoil(parried)
	if not parried: Fx.hitstop(.028,.3)
	var segment := sword.blade_segment()
	var point: Vector3 = (segment[0]+segment[1])*.5
	if source and source.has_meta("contact_point"):
		point = source.get_meta("contact_point")
	load("res://scripts/fx/sword_contact.gd").spawn(get_tree().current_scene,point,parried)

func _find_entity(node: Node, method: String) -> Node:
	var n := node
	while n != null:
		if n.has_method(method):
			return n
		n = n.get_parent()
	return null

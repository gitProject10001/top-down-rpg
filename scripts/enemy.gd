class_name Enemy
extends CharacterBody3D
## A simple melee dummy that makes the combat loop real: idle → chase the player → telegraph →
## strike, on a cooldown. Takes sword hits via its HurtBox/Health, flashes, and dies.
##
## NOTE: enemy logic is a small enum state-switch here (not the player's Node-FSM) on purpose — a
## basic enemy doesn't need that much structure. If enemies grow complex we'll graduate them to the
## same [[state-machine]] pattern the player uses.

@export var move_speed := 3.0
@export var aggro_range := 10.0
@export var attack_range := 2.2
## Can this thing be routed? The Fear trait rolls against every sword hit (see sword.gd), which is
## right for the things it was written for and wrong for a boss: an ogre that turns and runs after a
## lucky proc throws away the whole encounter, and from the player's side it reads as a bug rather
## than as a stat working.
@export var fearless := false
## Does this one get the bar at the top of the screen? Set in code rather than by a group in the
## scene file: enemy_ogre.tscn is an INHERITED scene, and a `groups = [...]` line on the root of one
## of those does not survive being instanced -- the group was written, saved, and resolved to
## nothing at runtime.
@export var is_boss := false
## Seconds this thing will still wait before answering, once it has been hit. Negative disables the
## behaviour and the full cooldown always runs. Short, but not zero: an instant reply to every hit
## removes the punish window the cooldown exists to give.
@export var retaliate_after := -1.0
## HOW LONG IT STAYS OPEN AFTER A SWING, in seconds. Zero disables the behaviour.
##
## Sized from the PLAYER, not guessed: the window has to fit the walk in, a full combo, and the walk
## back out, or it is not a window -- it is a taunt. On this player that is about 0.25 s to close
## 1.5 m, 0.6 s for three swings, 0.2 s to leave. Birkhead's rule for this is unusually blunt:
## anything less than one full combo is NOT ENOUGH, and Death's Door ships a 2-3 hit window after
## every boss combo.
##
## It is a window in the ogre's BEHAVIOUR, not merely the absence of one: for its duration the
## creature is committed to standing there, whatever else it would rather do.
@export var punish_window := 0.9
## HOW MANY HITS THE WINDOW IS WORTH. Take this many and it closes early and the ogre answers --
## which is the rhythm the fight is built on: land your combo, then get out.
##
## Without it the window was a fixed stretch of time in which the ogre was in S.ATTACK, so the
## CHASE branch never ran and the two moves it has for being crowded -- the backstep and the kick --
## could not fire at all. It stood there and took everything until the clock ran out, however close
## you were and however many times you hit it. That is what a punchbag IS, and no amount of shorter
## windows fixes it, because the problem was never the length.
@export var punish_hits := 3
## Inside this range the ogre stops trying to attack and hops backwards instead. Zero disables it.
@export var backstep_at := 4.0
## Seconds between backsteps, so it cannot chatter when a player hovers on the edge of the range.
@export var backstep_every := 0.8
## Inside this it kicks instead of hopping back: there is no room left to make, and the kick's
## knockback is what puts the player back out where the mace is dangerous.
@export var shove_at := 2.9
## Seconds between rest beats -- the roar. A fight that is all chorus is exhausting; Acid Nerve's
## own words for this are that a game needs verses as well. Zero disables it.
@export var rest_every := 22.0
## Seconds between attacks thrown from beyond mace range. Without a clock of its own the ogre
## simply stops walking: something always reaches at 12 m, so it would stand there using it.
@export var ranged_every := 5.0
## The colour it wears while open. A tell the player can read from anywhere on the screen -- a pose
## would say it better and is the next step, but a pose cannot be seen through the ogre's own leg
## at melee range and this can.
@export var winded_tint := Color(0.45, 0.75, 1.0)
## HOW MUCH MASS THIS BODY BRINGS TO A CONTACT, as a multiplier on the hitstop and shake a landed
## blow produces -- in BOTH directions: what it feels like to hit this thing, and what it feels like
## to be hit by it. 1.0 is a person.
##
## The feedback layer exists because hitstop that fires identically for every contact carries no
## information (see combat_feedback.gd). That argument does not stop at "did it connect": a sword
## going through a four-metre ogre and a sword going through a swarmling froze the screen for the
## same 70 ms, so the loudest cue in the game said nothing about WHAT you hit. Heft is that missing
## half. It only ever scales an existing contact -- it cannot invent one on a whiff.
@export_range(0.5, 2.5, 0.05) var heft := 1.0
@export var attack_cooldown := 1.6

## What this enemy does when it attacks. One script, three behaviours (data-driven) so we don't
## fork the shared chase / flash / stagger / die logic three ways.
##   MELEE  — close in and swing the AttackHitBox (the original dummy)
##   RANGED — keep its distance and fire a Projectile at the player (an archer)
##   AREA   — close in and drop a telegraphed ground-slam (AreaAttack) — a heavy brute
enum AttackKind { MELEE, RANGED, AREA }
@export var attack_kind: AttackKind = AttackKind.MELEE
@export var projectile_scene: PackedScene    ## RANGED: the arrow to fire (res://scenes/fx/arrow.tscn)
@export var area_attack_scene: PackedScene   ## AREA: the slam to drop (res://scenes/fx/area_attack.tscn)
@export var preferred_range := 8.0           ## RANGED: distance it tries to hold from the player
@export var projectile_damage := 1

## RANGED band answers — the ogre's M1/M2/M3 idea, for a shooter. The bands are the SAME numbers
## _chase_ranged already steers by; feet and trigger must read one ruler or the enemy kites out of
## a band while firing the answer for the one it just left.
##   NEAR (dist < preferred_range*0.7, the kite band) — a flat fan of `burst_count` straight
##        bolts: the get-off-me answer, fired while backpedalling. 0 or 1 = no fan, plain shot.
##   HOLD (between, the stand-and-shoot band) — the aimed ballistic single, as ever.
##   FAR  (dist > preferred_range, still closing) — with `far_lob` on, the same ballistic at lob
##        speed: slower horizontally = higher, longer arc = the impact ring warns the far player
##        LONGER, exactly as the ogre's longest-range attacks are its most telegraphed.
@export var burst_count := 0
@export var burst_spread_deg := 24.0
@export var far_lob := false

## The wilder shots, all dormant at defaults (the archer is bit-identical without them):
##   homing_deg/homing_time — straight bolts (the NEAR fan) curve toward the player at up to
##     this many deg/sec for this long, then fly true. Follow-to-a-degree: the cap is what
##     keeps them dodgeable, the window is what makes the chase end.
##   pierce_every — every Nth trigger pull, whatever the band, is THE PURPLE ONE: a single
##     unparriable homing bolt launched deliberately off the line (up and to a side) so the
##     player watches it swing back in. Purple = the guard does not answer it (the colour
##     contract in projectile.gd); it is dodged with feet, and it teaches that block is a
##     choice, not a stance. 0 disables.
##   impact_wave_scene — the SURFACE ATTACK: spawned where a lobbed shot LANDS (only a missed
##     lob lands — a direct hit already paid). A GroundWave ring propagates from the crater;
##     jump over it. Null disables.
@export var homing_deg := 0.0
@export var homing_time := 0.5
@export var pierce_every := 0
@export var impact_wave_scene: PackedScene

## The purple of the colour contract — kept well away from the parriable warm orange.
const PIERCE_COLOR := Color(0.72, 0.25, 1.0)

## FEAR is appended rather than slotted in beside STAGGER so every existing ordinal keeps its value
## — the enum is compared by name everywhere, but a reordered enum is the kind of change that is
## free until the day something serialises one.
enum S { IDLE, CHASE, ATTACK, FLINCH, STAGGER, DEAD, FEAR }

@export var attack_anim_speed := 1.6   ## skeletal melee only: slash clip speed-up. Deliberately

## WHOSE CLIPS ARE THESE? A body built on the shared humanoid set takes the cached library, the
## per-step speed warp and the damage-window method track injected into atk_h -- all of which exist
## because that library is SHARED and rebuilt per speed. A body with its own rig brings its own
## library and its own Call Method track, authored into the clip and carried across reimports by the
## importer's `save_to_file/keep_custom_tracks`. There is nothing to swap, and swapping would hand
## it a skeleton it does not have. (ogre2: its own Biped rig, its own 20-clip pack.)
@export var shared_clips := true
## The attack STATES in this body's AnimationTree, for a creature with more than one swing. Empty
## means the single state named "Slash", which is what every shared-clip enemy has. Each state
## carries its own damage window in its own clip, so adding one costs no code here.
@export var attack_states: Array[StringName] = []
									   ## slower than the player's — the wind-up IS the telegraph.

## POISE — the hit-reaction rule (Death's-Door / Souls). Two reactions:
##   FLINCH  — a tiny recoil on every hit (grunts), rewards aggression but doesn't stop a heavy.
##   STAGGER — the big break when POISE runs out (or on a parry): cancels the wind-up, opens a
##             window. You must CHAIN hits to break poise before it regenerates.
## Data-driven per variant (grunt vs. armored elite) via these exports — same one-script pattern.
@export var max_poise := 2             ## poise damage absorbed before a break (grunt low, elite high)
@export var poise_regen := 1.0         ## poise/sec recovered once poise_regen_delay has passed
@export var poise_regen_delay := 1.0   ## seconds since the last hit before poise starts refilling
@export var flinches_on_hit := true    ## grunts flinch on EVERY hit; armored foes ignore light hits
@export var flinch_time := 0.14        ## micro-stun duration of a flinch
@export var flinch_knockback := 3.0    ## recoil speed away from the attacker on a flinch

var _state := S.IDLE
var _player: Node3D
var _cool := 0.0
var _stagger_t := 0.0
var _flinch_t := 0.0
var _fear_t := 0.0
var _poise := 0.0
var _since_hit := 999.0
## Seconds left of the punish window, and whether we are inside it.
var _winded_t := 0.0
var _winded_hits := 0
## The attack this one flows into, rolled once at the recover beat so the answer cannot change
## between deciding there is no window and acting on it.
var _next_chain: StringName = &""
var _fallback_open := false   ## the body box is standing in for a missing weapon volume
## The last attack this AI actually threw - the chooser's anti-repeat memory. AI state, kept
## here: it lived in the solver while the chooser did, which meant the animation addon owned
## the ogre's tactics.
var _last_attack: StringName = &""
## Counts down to the next rest beat.
var _rest_t := 0.0
var _far_t := 0.0
var _step_t := 0.0
## The rock currently in its hands, if any.
var _held: Node3D
const THROWN_ROCK := preload("res://scenes/props/thrown_rock.tscn")                ## seconds since last damage — gates poise regen
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _flash_mats: Array[BaseMaterial3D] = []
var _anim_pb: AnimationNodeStateMachinePlayback   ## set only on skeletal variants (swordsman)
var _tree: AnimationTree                          ## the mixer itself, for blend params + signals
var _slash_len := 1.0                             ## enemy slash clip length (unwarped copy)
var _slash_strike := 0.45                         ## seconds into the slash when the blade lands
var _attack_tween: Tween                          ## the live wind-up→strike→recover chain (killable)
var _ragdoll: PhysicalBoneSimulator3D             ## skeletal: the AUTHORED death ragdoll, found at load
var _look: LookAtModifier3D                       ## skeletal: engine head-tracking
var _look_target: Marker3D
var _knock_len := 1.0                             ## knockdown/getup clip lengths — the FSM's
var _getup_len := 1.0                             ## stagger timer is their sum, one clock
var _attack_watch := 0.0                          ## skeletal ATTACK deadline (signal backstop)
var _last_hit_dir := Vector3.FORWARD              ## the killing blow's push, for the ragdoll
var _last_hit_kb := 6.0                           ## ...and its knockback weight (F = ma)

## THE OPT-IN, AND IT IS THE WHOLE SAFETY ARGUMENT. A scene that hands this body a
## NavigationAgent3D child is a scene asking for coordinated movement; a scene that does not gets
## the file that shipped, instruction for instruction. Every hook below tests this first, and
## _steer() returns literally `to_player.normalized()` when it is null -- the same expression the
## chase used before any of this existed, not something equivalent to it. The four player_vs_*
## benches carry no agent, which is what makes "those baselines are undisturbed" provable.
var _agent: NavigationAgent3D
## The NavigationServer does not synchronise its maps until the END of a physics frame, so a path
## queried in _ready() comes back EMPTY and get_next_path_position() answers with our own position
## -- a body that stands still forever, which is exactly how that bug presents. Until this is true
## _steer() falls back to the straight line, which is today's behaviour rather than a freeze.
var _nav_ready := false
## RVO's answer to last frame's wish. It arrives from velocity_computed AFTER _physics_process has
## returned, so it is always exactly one frame old; _nav_safe_age counts how old.
var _nav_safe := Vector3.ZERO
var _nav_safe_age := 99
## What we want THIS frame, for the one set_velocity() call beside move_and_slide(). INF means the
## branch did not ask for anything -- see the single reporting site.
var _nav_wish := Vector3.INF
## Did _goal() answer "the player" this frame? It decides which arrival distance applies.
var _goal_is_player := true
## The goal last handed to the NavigationAgent, for the overlay and for debugging a body that is
## walking somewhere surprising.
var _nav_target := Vector3.INF
## Do we hold the director's attack token? A CACHE, never the truth: CombatDirector owns that and
## reclaims on its own watchdog, so a desync here costs one wasted call, not a jammed fight.
var _has_token := false
## HAS THIS TURN ACTUALLY BEEN SPENT YET? A turn is granted while the body is still walking in --
## it has to be, or a body waiting on the ring could never ask for one -- so "not attacking" is
## true for the whole approach. Without this flag the release line below fired at the end of the
## very frame the turn was granted, the body lost it before reaching the player, and it drifted in
## re-claiming and re-releasing every frame. Measured on the brute: granted at 6.2 m, still had no
## turn at 3.3 m, and never once reached S.ATTACK during the approach.
var _turn_used := false

@onready var _visuals: Node3D = $Visuals
@onready var _health: Health = $Health
## WHERE THE DAMAGE LIVES. A body box in front of the chest is the default because most bodies have
## no weapon to hang it on -- but it is the same shape whether the weapon is overhead, behind, or
## buried in the floor, which is a lie the player can read. A body that carries a weapon points this
## at a volume riding the weapon itself, and then what hurts you is the thing you have been watching.
## (ogre2: a sphere on the hammer head and a cylinder down the haft, both on its BoneAttachment3D.)
@export var attack_hitbox_path: NodePath = ^"Visuals/AttackHitBox"
@onready var _attack_hitbox: HitBox = get_node(attack_hitbox_path)

var _toon: Node                        ## ToonSkin cel-shader applier, if this variant ships one

## RANGED: optional Marker3D named "Muzzle" anywhere in the scene — projectiles leave from it
## (the robot's crown). Without one the old chest-height guess stands, so the archer is untouched.
var _muzzle: Node3D
## Trigger pulls since spawn — the pierce_every clock. Counts VOLLEYS, not bolts: a 3-bolt fan
## advances it once, so "every 4th shot is the purple one" stays true whatever band fired.
var _volleys := 0

## Set on variants animated by addons/procedural_anim instead of by clips (the ogre). Everything
## that touches it is guarded, so no other enemy is affected by a single line of this.
var _solver: OgreSolver
## The ground telegraph currently up, so it can be dragged after the aim until the ogre commits.
var _slam_area: Node3D

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_poise = max_poise
	if is_boss:
		add_to_group("boss")
	_setup_solver()
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	# CONTACT feedback for the basic melee box (swordsman, brute's body fallback): these swings
	# landed on the player in total silence — no hitstop, no shake, no rumble — while the ogre's
	# solver-built volumes spoke. One connection closes the gap; `applied` gates it as ever.
	_attack_hitbox.dealt_hit.connect(_on_attack_landed)
	_toon = get_node_or_null("ToonSkin")
	if _toon == null:                  # greybox capsule etc.: fall back to emission-tinted materials
		_setup_flash_materials()
	_muzzle = find_child("Muzzle", true, false) as Node3D
	_setup_animations()
	# BY TYPE, NOT BY NAME. Every other discovery in this file names a node (OgreSolver, Muzzle)
	# because those are unique things; an agent is a CAPABILITY, and a scene should be free to call
	# it whatever it likes. DIRECT CHILDREN ONLY -- an agent buried inside an imported model
	# hierarchy would be an accident of the asset, not a decision of the scene.
	for c in get_children():
		if c is NavigationAgent3D:
			_agent = c as NavigationAgent3D
			break
	if _agent != null:
		_agent.velocity_computed.connect(_on_safe_velocity)
		_arm_navigation.call_deferred()


## FREED WITHOUT DYING -- a scene reload (KEY_R in every dev harness), a room reset, a despawner.
## Health never fired, so _on_died never ran and the state line never saw a non-ATTACK state.
func _exit_tree() -> void:
	if _has_token:
		_has_token = false
		_turn_used = false
		CombatDirector.release_attack(self)


## THE FIRST PHYSICS FRAME. NavigationServer3D rebuilds its maps at the END of a physics step, so
## a region added this frame is not in the map yet and get_next_path_position() answers with our
## own position. Awaiting one frame is the documented workflow; _ready() itself must never await.
func _arm_navigation() -> void:
	await get_tree().physics_frame
	_nav_ready = is_instance_valid(_agent)


# --- Skeletal variant support (enemy_swordsman) --------------------------------------------
# If the scene ships an AnimationTree (humanoid model + the shared clip library), drive it.
# CRITICAL: the PLAYER warps the cached library clips for its own combat cadence (fast wind-ups)
# — an enemy must NOT inherit that, its slow wind-up is the player's dodge window. So we load a
# fully independent copy of the library (deep ignore-cache) and re-time only ours.
const _SLASH_STRIKE_FRAC := 0.42   # where atk_h connects, fraction of the ORIGINAL clip

## Enemy clip library, built ONCE and shared by every enemy using the same attack_anim_speed.
##
## MEASURED: doing this per instance cost ~11 ms of _ready() — CACHE_MODE_IGNORE_DEEP re-reads the
## library AND all 14 clips from disk each time, then we walk every track. Three swordsmen entering
## a dungeon room was ~33 ms, i.e. two dropped frames and a visible spawn stutter. Cached: ~0 ms
## after the first.
##
## Still IGNORE_DEEP for that first build: the player MUTATES the normally-cached library (wind-up
## compression, cadence warping), and enemies must not inherit those fast timings — a slow, readable
## enemy wind-up is the player's dodge window.
static var _lib_cache: Dictionary = {}


## Build the shared clip library (and pull the enemy scenes into the resource cache) BEFORE the
## player can trigger a spawn. Called while a zone is generating, so the ~10 ms first-build lands
## under the loading fade instead of on the frame you walk into a room.
## PROCEDURALLY ANIMATED VARIANTS. The ogre has no clips at all -- its walk, its swing and its
## settle are computed -- so it takes the branch below instead of the AnimationTree one.
##
## The integration is deliberately small, and all of it guarded: the solver's whole input contract
## is (velocity, on_floor, facing), which every CharacterBody3D already knows. That is what made it
## possible to build and prove the animation against a keyboard-driven puppet and then drop the AI
## in underneath without the animation code changing.
func _setup_solver() -> void:
	_solver = find_child("OgreSolver", true, false) as OgreSolver
	if _solver == null:
		return
	_solver.action_event.connect(_on_solver_event)
	# The solver arms and disarms its own damage volumes on its own action clock; this is the AI's
	# veto over the arming half. It used to be a gate on the hit_open HANDLER while hit_close ran
	# ungated — two authorities over one window.
	_solver.may_damage = func() -> bool: return _state == S.ATTACK
	_solver.look_target = _player
	# Its own proportions decide how fast it walks. A four-metre creature's comfortable speed is a
	# fact about its legs, not a number to guess -- see OgreSolver.walk_speed().
	if move_speed <= 0.0:
		move_speed = _solver.walk_speed()


## The solver says WHEN; this says WHAT. Beats fire as the animation reaches them, so gameplay
## timing comes FROM the animation rather than being guessed alongside it -- the same move the
## skeletal branch makes when it takes `strike` off the clip instead of hard-coding 0.45.
func _on_solver_event(what: StringName, at: Vector3) -> void:
	match what:
		&"hit_open":
			# The solver arms its own weapon volume now (see OgreSolver.may_damage). This branch
			# only covers the weapon-attach failure, where the solver has no volume to arm: the
			# body box steps in — loudly, because a silent swap to a 3-damage box the size of the
			# torso is a very different attack.
			if _state == S.ATTACK and _solver.strike_hitbox() == null:
				push_warning("Enemy: ogre has no weapon hitbox — falling back to the body box")
				_attack_hitbox.activate()
				_fallback_open = true
		&"hit_close":
			if _fallback_open:
				_attack_hitbox.deactivate()
				_fallback_open = false
		&"slam_telegraph":
			if _state == S.ATTACK:
				_spawn_slam(at)
		&"strike":
			# The blow is landing NOW — the driven telegraph detonates on this beat, not on a
			# timer of its own that the aim hold could not pause.
			if is_instance_valid(_slam_area):
				_slam_area.detonate_now()
			# THE ROCK ACTIONS' MISSING HALF. rock_lift and rock_throw have been in the library
			# since they were written, with poses, timings and a projectile scene -- and no handler,
			# so even when one was chosen it played a mime.
			if _solver.action == &"rock_lift":
				_grab_rock()
			elif _solver.action == &"rock_throw":
				_release_rock()
		&"recover":
			# THE INVITATION. The swing is spent, the mace is on the floor, and for the next
			# `punish_window` seconds the ogre will stand there and take it. This is the beat the
			# whole fight is built around and until now it was emitted and ignored: the recovery
			# existed but nothing held the ogre in it and nothing told the player it was happening.
			if _state == S.ATTACK:
				# ROLLED ONCE, HERE. A string denies the window on purpose -- that is what makes a
				# player who attacks after the second hit of a three-hit string eat the third, and
				# it is the only thing in a fight that punishes greed specifically. But the roll has
				# to happen at one moment and be remembered, or "is there a window" and "was there a
				# window" answer differently and the tell is a lie.
				_winded_hits = 0
				_next_chain = _roll_chain(_solver.action)
				# You cannot throw a rock you have not picked up, and you cannot stand holding one.
				if _solver.action == &"rock_lift":
					_next_chain = &"rock_throw"
				elif _held != null and _solver.action != &"rock_throw":
					_next_chain = &"rock_throw"
				if _next_chain == &"" and punish_window > 0.0:
					_winded_t = punish_window
					_cool = maxf(_cool, punish_window)
					_flash(winded_tint)
		&"abandoned":
			# The ogre gave the swing up because the player broke its range. Drop the telegraph with
			# it -- a warning disc left behind by an attack that is not coming is worse than none,
			# because the next one will be believed less.
			if is_instance_valid(_slam_area):
				_slam_area.queue_free()
			_slam_area = null
			if _state == S.ATTACK:
				# CONCATENATE. If some other attack suits where the player has got to, go straight
				# into it -- the wind-up flows into the next move instead of the ogre dropping back
				# to standing about, which is what makes an abandoned swing read as a decision
				# rather than a stumble. THE CHOICE IS MADE HERE now: the solver reports the
				# abandon and answers range queries; naming the follow-up is tactics, and tactics
				# are this file's job. Refusing the attack that was just abandoned is what the
				# reroll-plus-guard buys.
				var next: StringName = choose_attack(_dist_to_player())
				if next != &"" and next != _last_attack:
					_note_attack(next)
					_solver.play_action(next)
				else:
					_state = S.CHASE


## WHICH VOLUME THIS SWING DAMAGES WITH. The mace's own, when it is carrying one -- the damage
## belongs on the weapon, which is the thing the player has been reading for the whole wind-up, and
## a fixed box in front of the body is the same shape whether the mace is overhead or in the floor.
## Falls back to the body box for anything not holding a weapon.
func _swing_hitbox() -> HitBox:
	if _solver:
		# The solver knows which limb is delivering; the body should not have to. A kick hurts with a
		# foot and a slam with a mace, and asking for "the mace" during a kick opened a volume four
		# metres from anything that was moving.
		var h: HitBox = _solver.strike_hitbox()
		if h:
			return h
	return _attack_hitbox


## THE TELEGRAPH FOLLOWS THE AIM until the ogre commits.
##
## The disc is dragged after the player while the mace is still going up, and stops dead the instant
## the smash begins. That freeze is the dodge: leave too early and the disc simply comes with you,
## leave too late and you are already inside it. The window is the moment the mace starts down --
## which is the loudest thing on screen, so it can be read without being told.
func _track_slam() -> void:
	if _slam_area == null or not is_instance_valid(_slam_area):
		_slam_area = null
		return
	if _solver == null:
		return
	# THE DISC RUNS ON THE ACTION CLOCK. It used to run on its own wall-clock Tween while the aim
	# hold froze action_t — sampled once at spawn, the two clocks could disagree by up to the whole
	# hold (0.7 s), and the ring detonated before the blow it was warning about. For the pound the
	# ring IS the damage, so that was a hit arriving early out of an honest-looking circle. Driven
	# from action_t, the hold is simply VISIBLE: the circle stops growing while the ogre waits.
	if not _solver.is_acting():
		_slam_area.dismiss()               # stagger or fear killed the swing; retract the promise
		return
	var spec := _solver.spec(_solver.action)
	if spec != null and spec.hit_at < 100.0:
		_slam_area.set_progress(_solver.action_t / maxf(spec.hit_at, 0.01))
	if not _solver.aim_tracking():
		return
	# The PREDICTED IMPACT, not the aim point. The aim is where the swing is pointed; this is where
	# the head actually arrives, and the difference between them is the difference between a circle
	# that tells the truth and one that is merely nearby.
	var a: Vector3 = _solver.predicted_impact()
	_slam_area.global_position = Vector3(a.x, global_position.y + 0.05, a.z)


## The ground slam's warning disc, spawned at the START of the wind-up so it grows for exactly as
## long as the mace takes to come down. One number feeds the animation and the telegraph, so they
## cannot drift apart.
func _spawn_slam(at: Vector3) -> void:
	var spec := _solver.spec(_solver.action)
	if spec == null or spec.slam_radius <= 0.0 or area_attack_scene == null:
		return
	var area := area_attack_scene.instantiate() as AreaAttack
	area.windup = maxf(spec.hit_at - _solver.action_t, 0.05)
	area.radius = spec.slam_radius
	# A WARNING, NOT A WEAPON. The disc used to deal the damage itself, on its own timer, whether or
	# not the mace ever arrived -- so you could be hit by a circle on the floor while the weapon was
	# still in the air. The damage comes from the mace's own volume meeting your hurtbox now; this
	# only says where it is going to land.
	# A WARNING, unless the ring IS the attack. For the slam the mace is the weapon and a disc that
	# also hurt would double-dip; for the pound the mace goes into the floor and there is nothing
	# else to carry the damage, so it fired as pure theatre and could not hurt anyone.
	var ring_spec: ActionSpec = _solver.spec(_solver.action)
	area.damage = ring_spec.damage if (ring_spec != null and ring_spec.damage_from_ring) else 0
	# This enemy HAS a clock — the solver's — so the disc is driven from it (see _track_slam) and
	# detonated on the strike beat, instead of racing a wall-clock tween the aim hold cannot pause.
	area.driven = true
	get_parent().add_child(area)
	var spot: Vector3 = _solver.predicted_impact()
	area.global_position = Vector3(spot.x, global_position.y + 0.05, spot.z)
	_slam_area = area


static func warm_caches(speed := 1.6) -> void:
	_shared_library(speed)


## Reaction clips merged into the library copy at load. They live in the Quaternius set (the
## player3 library's sources) — every rig here retargets onto GeneralSkeleton, so the two
## libraries cross-play; player4 already proves it in the other direction.
const _REACTION_CLIPS := {
	&"hurt": "res://assets/models/animations/quaternius/hurt_chest.res",
	&"hurt_knockback": "res://assets/models/animations/quaternius/hurt_knockback.res",
	&"getup": "res://assets/models/animations/quaternius/getup.res",
	&"death": "res://assets/models/animations/quaternius/death.res",
}

static func _shared_library(speed: float) -> Dictionary:
	var key := snappedf(speed, 0.01)
	if _lib_cache.has(key):
		return _lib_cache[key]
	var lib := ResourceLoader.load("res://assets/models/animations/player_anims.tres", "",
			ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AnimationLibrary
	var slash_len := 1.0
	var knock_len := 1.0
	var getup_len := 1.0
	if lib:
		for clip_name in ["idle", "run_fwd", "atk_h"]:
			var a := lib.get_animation(clip_name)
			if a:
				_strip_hips_drift(a)
		var slash := lib.get_animation("atk_h")
		if slash:
			for i in slash.get_track_count():
				for k in slash.track_get_key_count(i):
					slash.track_set_key_time(i, k, slash.track_get_key_time(i, k) / speed)
			slash.length /= speed
			slash_len = slash.length
			# THE DAMAGE WINDOW LIVES IN THE CLIP — a Call Method track, the engine's own way
			# of keying gameplay to a timeline. It replaced a create_tween() stopwatch running
			# beside the animation; two clocks for one moment is the failure this project has
			# hit more than any other. The keys call the ENEMY (two steps up from the tree's
			# root_node Visuals/Model), not the hitbox directly, and the enemy consents only in
			# S.ATTACK — the same shape as the ogre's may_damage veto — because a travel out of
			# Slash only stops keys BEYOND the 0.05 s fade: a flinch landing inside the open
			# window (or a hair before the activate key) otherwise left the box live forever.
			var mt := slash.add_track(Animation.TYPE_METHOD)
			slash.track_set_path(mt, NodePath("../.."))
			slash.track_insert_key(mt, slash.length * _SLASH_STRIKE_FRAC,
					{"method": &"open_melee_window", "args": []})
			slash.track_insert_key(mt, minf(slash.length * _SLASH_STRIKE_FRAC + 0.18,
					slash.length - 0.01), {"method": &"close_melee_window", "args": []})
		for reaction_name: StringName in _REACTION_CLIPS:
			var clip := ResourceLoader.load(_REACTION_CLIPS[reaction_name], "",
					ResourceLoader.CACHE_MODE_IGNORE) as Animation
			if clip == null:
				continue
			_strip_hips_drift(clip)
			# LOOP_NONE, forced: an AT_END transition and animation_finished both wait for an
			# end a looping clip never reaches — one imported loop flag would hang the tree.
			clip.loop_mode = Animation.LOOP_NONE
			lib.add_animation(reaction_name, clip)
			if reaction_name == &"hurt_knockback":
				knock_len = clip.length
			elif reaction_name == &"getup":
				getup_len = clip.length
	var entry := {"lib": lib, "slash_len": slash_len,
			"knock_len": knock_len, "getup_len": getup_len}
	_lib_cache[key] = entry
	return entry


func _setup_animations() -> void:
	# The AUTHORED ragdoll is found for ANY body with a skeleton — the ogre has one and no
	# AnimationTree, so this must sit above the tree gate or the ogre dies in a squash forever.
	var death_skel := find_child("GeneralSkeleton", true, false) as Skeleton3D
	_ragdoll = null
	if death_skel != null:
		for c in death_skel.get_children():
			if c is PhysicalBoneSimulator3D:
				_ragdoll = c
				break
	var tree := get_node_or_null("AnimationTree") as AnimationTree
	if tree == null:
		return
	if shared_clips:
		var entry := _shared_library(attack_anim_speed)
		var lib: AnimationLibrary = entry["lib"]
		if lib:
			_slash_len = entry["slash_len"]
			_slash_strike = _slash_len * _SLASH_STRIKE_FRAC
			_knock_len = entry["knock_len"]
			_getup_len = entry["getup_len"]
			if tree.has_animation_library(&""):
				tree.remove_animation_library(&"")
			tree.add_animation_library(&"", lib)
	else:
		_measure_own_clips(tree)
	tree.active = true
	_tree = tree
	# The attack's END comes from the animation itself: the AT_END transition returns the tree,
	# and this signal returns the FSM — the stopwatch that used to run beside the clip is gone.
	tree.animation_finished.connect(_on_anim_finished)
	_anim_pb = tree["parameters/playback"]
	_anim_pb.start("Idle")
	_attach_sword_visual()
	_setup_head_look(death_skel)


## The same three clocks the shared library hands back, taken from a library this scene brought
## itself. ASKED OF THE TREE, not of the library: a state name is what the FSM travels to, and only
## the state knows which clip it plays -- guessing by clip name would break the moment a state was
## repointed. Anything missing keeps its 1.0 default, which only ever makes a backstop generous.
func _measure_own_clips(tree: AnimationTree) -> void:
	var lib := tree.get_animation_library(&"")
	if lib == null:
		return
	var length := func(state: StringName) -> float:
		var sm := tree.tree_root as AnimationNodeStateMachine
		if sm == null or not sm.has_node(state):
			return 0.0
		var node := sm.get_node(state) as AnimationNodeAnimation
		if node == null or not lib.has_animation(node.animation):
			return 0.0
		return lib.get_animation(node.animation).length
	var longest := 0.0
	for st in (attack_states if not attack_states.is_empty() else [&"Slash"] as Array[StringName]):
		longest = maxf(longest, length.call(st))
	if longest > 0.0:
		_slash_len = longest
	# The strike moment is IN the clip as a method key; this only feeds the readout.
	_slash_strike = _slash_len * _SLASH_STRIKE_FRAC
	_knock_len = maxf(length.call(&"Knockdown"), 0.1)
	_getup_len = maxf(length.call(&"Getup"), 0.1)


## The FSM's half of the clip-owned attack ending. `animation_finished` can be swallowed by a
## cross-fade that starts before the clip's last frame, so `_attack_watch` (a physics-side
## deadline, see the ATTACK branch) backstops it — the two agree on the green path and the
## watchdog only speaks when the signal went missing.
func _on_anim_finished(anim: StringName) -> void:
	if anim == &"atk_h" and _state == S.ATTACK:
		_state = S.CHASE


## The clip's method-track keys land here; the FSM consents. The window may only OPEN while the
## attack is still real — an interrupt has 0.05 s of cross-fade in which a stale key can still
## fire — but a CLOSE is always obeyed, whoever asks.
func open_melee_window() -> void:
	if _state == S.ATTACK:
		_attack_hitbox.activate()


func close_melee_window() -> void:
	_attack_hitbox.deactivate()


## LookAtModifier3D — the engine's own head-tracking, our first use of a standard skeleton
## modifier on an enemy. Child of the skeleton so it runs after the AnimationTree writes the
## pose; influence is eased per-state in _physics_process (a committed swing should not
## owl-track, and a corpse must not track at all).
func _setup_head_look(skel: Skeleton3D) -> void:
	if skel == null or skel.find_bone("Head") < 0:
		return
	_look_target = Marker3D.new()
	_look_target.name = "LookTarget"
	add_child(_look_target)
	_look = LookAtModifier3D.new()
	_look.name = "HeadLook"
	skel.add_child(_look)
	_look.bone_name = "Head"
	_look.target_node = _look.get_path_to(_look_target)
	# The model carries the 180-degree scene yaw, so the bone's forward in skeleton space is +Z.
	_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	_look.use_angle_limitation = true
	_look.primary_limit_angle = deg_to_rad(110.0)
	_look.influence = 0.0

## Pin the hips XZ (clips not exported in-place walk away from the capsule).
static func _strip_hips_drift(a: Animation) -> void:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D \
				and str(a.track_get_path(i)).ends_with(":Hips"):
			if a.track_get_key_count(i) == 0:
				continue
			var first: Vector3 = a.track_get_key_value(i, 0)
			for k in a.track_get_key_count(i):
				var v: Vector3 = a.track_get_key_value(i, k)
				a.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))

## A simple blade riding the right hand (the clips are sword-and-shield mocap). The grip
## transform is the VRoid rig's known-good calibration; origin/basis divided by the model
## scale because this sits INSIDE the scaled skeleton (unlike the player's world-space follow).
func _attach_sword_visual() -> void:
	var skel := find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skel == null or skel.find_bone("RightHand") < 0:
		return
	var sock := BoneAttachment3D.new()
	skel.add_child(sock)
	sock.bone_name = "RightHand"
	# 1.0 since the model's size moved into the IMPORT (root_scale) — the skeleton node is
	# unscaled now and the calibration numbers below are already world metres.
	var model_scale: float = 1.0
	var grip := Transform3D(
			Basis(Vector3(0.938, -0.299, -0.171), Vector3(0.0, -0.497, 0.868),
					Vector3(-0.344, -0.814, -0.466)) * (1.0 / model_scale),
			Vector3(-0.328, 0.154, -0.027) / model_scale)
	var holder := Node3D.new()
	holder.transform = grip
	sock.add_child(holder)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.45, 0.42, 0.4)
	steel.metallic = 0.6
	steel.roughness = 0.4
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 1.1)
	bm.material = steel
	blade.mesh = bm
	blade.position = Vector3(0.35, 0.1, -0.75)
	holder.add_child(blade)
	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.32, 0.06, 0.08)
	gm.material = steel
	guard.mesh = gm
	guard.position = Vector3(0.35, 0.1, -0.22)
	holder.add_child(guard)

# Give this instance its own copy of every mesh material under Visuals, so a hit-flash tints THIS
# enemy only. Works for the greybox capsule or an imported character model (any MeshInstance3D).
func _setup_flash_materials() -> void:
	for mi: MeshInstance3D in _find_meshes(_visuals):
		for s in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_active_material(s)
			if m is BaseMaterial3D:
				var dup: BaseMaterial3D = (m as BaseMaterial3D).duplicate()
				mi.set_surface_override_material(s, dup)
				_flash_mats.append(dup)

func _find_meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += _find_meshes(c)
	return out

func _physics_process(delta: float) -> void:
	_track_slam()
	if _state == S.DEAD:
		return
	_nav_safe_age += 1
	_nav_wish = Vector3.INF
	# TOLD, NOT REGISTERED, and deliberately outside the match -- the same argument _face() makes
	# below. `_state = S.CHASE` is written at eleven sites in this file and three of them are inside
	# tween lambdas; a register/unregister hook at each is eleven chances to leak a slot. The
	# director is simply told what is true now, every frame, and reconciles. A body that stops
	# reporting -- dead (the return above), freed, or disengaged -- ages out of its ring on its own,
	# so there is no unregister call to forget.
	if _agent != null:
		CombatDirector.report(self, _player, _state != S.IDLE and _state != S.FEAR)
		# THE CACHE FOLLOWS ITS OWNER. The director can take a turn back without asking -- a watchdog
		# reclaim, a stale sweep, the whole thing being switched off and on again -- and a body that
		# kept believing it held one would keep swinging on that belief. Re-synced once a frame,
		# before anything reads it.
		if _has_token and not CombatDirector.holds_token(self):
			_has_token = false
			_turn_used = false
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	_cool = max(_cool - delta, 0.0)
	_rest_t = max(_rest_t - delta, 0.0)
	_far_t = max(_far_t - delta, 0.0)
	_step_t = max(_step_t - delta, 0.0)
	if _winded_t > 0.0:
		_winded_t = maxf(_winded_t - delta, 0.0)
		if _winded_t <= 0.0:
			_flash(Color(1, 1, 1, 0))          # back to normal; the invitation is withdrawn

	# Poise refills only after a lull — so a broken-off combo lets the wall come back, but a
	# sustained flurry punches through it. Capped at max_poise.
	_since_hit += delta
	if _since_hit > poise_regen_delay and _poise < max_poise:
		_poise = minf(_poise + poise_regen * delta, max_poise)

	var to_player := Vector3.ZERO
	var dist := 9999.0
	if is_instance_valid(_player):
		to_player = _player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()
		# This call is OUTSIDE the match because every state wants to keep tracking the player —
		# which is precisely why the one state that does not has to be answered here. A fleeing
		# enemy that keeps facing you moonwalks away, and the whole read of Fear is lost.
		_face(-to_player if _state == S.FEAR else to_player, delta)

	match _state:
		S.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			if dist < aggro_range:
				_state = S.CHASE
		S.CHASE:
			if attack_kind == AttackKind.RANGED:
				_chase_ranged(to_player, dist)
			else:
				# ASK FOR THE TURN FIRST, THEN DECIDE WHERE TO WALK -- and the order is the whole fix.
				# The request used to live down at the swing site, which a body can only reach once it
				# is already inside its own strike band. But a body WAITING sits on its ring, outside
				# that band by construction, so it never reached the request and could never be given a
				# turn: whoever happened to be close when the ring first formed did all the fighting and
				# the cap of two was never once reached. Measured: peak 1 concurrent attacker.
				# "Am I attacking or waiting" is decided HERE, and the answer steers the feet as well as
				# the sword -- a body granted a turn walks at the player, everyone else walks to a slot.
				if _cool <= 0.0 and not _has_token:
					_claim_token()
				# WHERE THIS BODY IS ACTUALLY WALKING. With no director -- every frame of every scene
				# that does not opt in -- the goal IS the player and `gdist` IS `dist`, so the two
				# lines below collapse to the test they replaced.
				var goal := _goal()
				var gdist := _goal_dist(goal, dist)
				if gdist > _goal_reach():
					# ON THE WAY IN. The charge and the rock throw only exist out here, and gating
					# every attack on being at mace range meant they could never be chosen -- but
					# widening "in range" to cover them stopped the ogre closing at all. They get
					# their own slower clock instead, so approaching is still what it mostly does
					# and the long game is a punctuation rather than a stance.
					var far_started := false
					if _cool <= 0.0 and _far_t <= 0.0 and _solver and ranged_every > 0.0:
						var far_pick: StringName = choose_attack(dist)
						# With the charge retired, the throw needs an actual rock (held or near)
						# or the far game is walking — miming a lift used to be the charge's job
						# to prevent, and _start_attack's fallback would whiff a slam from 12 m.
						if far_pick == &"rock_throw" and _held == null and not _rock_near():
							far_pick = &""
						if far_pick != &"" and _is_ranged(far_pick):
							_far_t = ranged_every
							_start_attack()
							far_started = true
							# No `return` here: bailing out of the whole function skipped
							# move_and_slide() and _solver.tick() for this frame, so starting a far
							# attack silently cost the solver a frame of aim, action clock, gait and
							# foot planting. The solver must tick exactly once per physics frame.
							velocity.x = 0.0
							velocity.z = 0.0
					if not far_started:
						var d := _steer(goal, to_player)
						# RUN WHEN THERE IS GROUND TO MAKE UP. move_speed is the ogre's WALK, derived
						# from its stride law, and it was being used for the whole chase -- 2.24 m/s
						# after a player who runs at 6.0. It could never close, so simply running away
						# beat everything the attack does, and no amount of aiming fixes being lapped.
						# It still cannot outrun you, which is correct for something this heavy; it can
						# now follow you, which it could not.
						var sp := move_speed
						if _solver and dist > _reach() * 1.35:
							sp = _solver.run_speed()
						velocity.x = d.x * sp
						velocity.z = d.z * sp
				elif _solver and _step_t <= 0.0 and backstep_at > 0.0 and dist < backstep_at \
						and _solver.forward().dot(to_player.normalized()) > 0.3:
					# The facing gate: the hop retreats along the ogre's own backward, and with
					# the kick retired it fires for EVERY crowd — including a player who dodged
					# through and now stands behind. Backstepping while facing away hopped the
					# ogre INTO the crowder (measured: 3.3 m toward them). Facing first, then
					# the answer; the turn takes a beat and the player earns that beat.
					# TOO CLOSE TO SWING AT. A four-metre creature with a four-metre mace cannot
					# bring it down on something standing on its feet -- that is geometry, not
					# tuning -- so standing there used to be the safest place on the map. It makes
					# ROOM instead, and the backstep chains into a sweep, so crowding it is punished
					# rather than merely undone.
					# A REACTION, NOT AN ATTACK, so it does not queue behind the attack cooldown.
					# Gating it on _cool was most of why the ogre read as a heavy bag: a player who
					# walked in during its recovery could stand there hitting it, and the one move
					# it has for exactly that could not fire until the recovery it was interrupting
					# had finished. It has its own short timer so it cannot chatter.
					# ONE ANSWER TO BEING CROWDED, since the kick's retirement (see its spec):
					# make room. Hop back and sweep, so your swings hit air and then the mace
					# comes through where you were standing. The kick's shove used to cover the
					# innermost band; now the backstep's own displacement opens that gap and its
					# sweep chain carries the punish.
					_state = S.ATTACK
					_step_t = backstep_every
					_cool = minf(_cool, 0.2)
					_note_attack(&"backstep")
					_solver.play_action(&"backstep")
				else:
					velocity.x = 0.0
					velocity.z = 0.0
					if _cool <= 0.0 and _solver and rest_every > 0.0 and _rest_t <= 0.0:
						# THE VERSE. It costs the player nothing and buys the fight a breath, which
						# is the one thing a 30-second all-chorus encounter cannot give itself.
						_rest_t = rest_every
						_state = S.ATTACK
						_cool = attack_cooldown
						_solver.play_action(&"roar")
					elif _cool <= 0.0 and _may_attack():
						_start_attack()
			if dist > aggro_range * 1.4:
				_state = S.IDLE
		S.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 6.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, move_speed * 6.0 * delta)
			# Hand back when the solver has actually finished, and not while the punish window it
			# just opened is still running. Anything else lets the next attack eat the recovery.
			# CROWDED WHILE OPEN. The window is a reward for making it whiff, not a licence to
			# stand inside its guard: once the hits are spent it may answer immediately, without
			# waiting to fall back through CHASE first.
			if _solver and _winded_t <= 0.0 and _step_t <= 0.0 and backstep_at > 0.0 					and dist < backstep_at and not _solver.is_acting() \
					and _solver.forward().dot(to_player.normalized()) > 0.3:
				# Same facing gate as the CHASE branch — an attack routinely ends with the
				# player behind the ogre, which is exactly the hop-into-the-crowder case.
				_step_t = backstep_every
				_cool = minf(_cool, 0.2)
				_note_attack(&"backstep")
				_solver.play_action(&"backstep")
				# An `elif` follows instead of the `return` that used to be here: returning
				# skipped move_and_slide() and _solver.tick(), so the crowd-answer's own first
				# frame was a frame the solver never saw. It ticks exactly once per physics frame.
			elif _solver and not _solver.is_acting() and _winded_t <= 0.0:
				if _next_chain != &"":
					var nxt := _next_chain
					_next_chain = &""
					_note_attack(nxt)
					_solver.play_action(nxt)
				else:
					_state = S.CHASE
		S.FLINCH:
			# micro-stun: let the recoil knockback carry, then snap back to chasing
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, move_speed * 4.0 * delta)
			_flinch_t -= delta
			if _flinch_t <= 0.0:
				_state = S.CHASE
		S.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 6.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, move_speed * 6.0 * delta)
			_stagger_t -= delta
			if _stagger_t <= 0.0:
				_state = S.CHASE
		S.FEAR:
			# Directly away, slightly faster than it chases. The speed bonus is the point: a feared
			# enemy that retreats at walking pace just looks like it lost interest, and Drama's
			# whole promise is that you made something happen to it.
			if dist > 0.1:
				var away := -to_player.normalized()
				velocity.x = away.x * move_speed * 1.15
				velocity.z = away.z * move_speed * 1.15
			_fear_t -= delta
			if _fear_t <= 0.0:
				_state = S.CHASE
	# ONE RELEASE SITE, AND IT IS THE HIGHEST-RISK LINE IN THIS FEATURE. An attack ends nine ways in
	# this file -- the RANGED, AREA and melee tweens, the clip's own animation_finished, the
	# _attack_watch deadline, the solver handing back -- plus three interrupts (stagger, fear,
	# flinch) that skip all of them. Handing the token back at each of those is nine chances to
	# leak, and a leaked token is a fight that STOPS: the cap is full, nobody is swinging, and every
	# body stands on its ring waiting for a turn that never comes.
	#
	# The STATE is the one thing all nine of them write. So the turn is handed back against the
	# state, once, here. The two paths this CANNOT catch are covered explicitly: DEAD returns before
	# this line (see _on_died) and a freed body never reaches it (see _exit_tree).
	# A turn ends when it has been SPENT and left, not merely when the body is not swinging this
	# instant -- see _turn_used. The approach is covered by the director's own approach deadline, so
	# a body granted a turn it never uses still cannot hold it for ever.
	if _has_token and _state == S.ATTACK:
		_turn_used = true
	elif _has_token and _turn_used:
		_has_token = false
		_turn_used = false
		CombatDirector.release_attack(self)
	# ONE set_velocity PER FRAME, WHATEVER THE STATE CHOSE, and the unconditional part is the point.
	# RVO predicts every agent from its LAST reported velocity, so an agent that reports only while
	# walking is -- to the simulation -- a body that stopped existing the moment it stood still, and
	# the crowd then walks straight through the one enemy planted in the strike band. Reporting a
	# standing body's zero is what makes it an obstacle to the others.
	# `_nav_wish` is what the branch ASKED for, falling back to what we actually committed to,
	# because the wish is only computed on the frames that steer.
	if _agent != null and _nav_ready and _agent.avoidance_enabled:
		_agent.set_velocity(_nav_wish if _nav_wish != Vector3.INF
				else Vector3(velocity.x, 0.0, velocity.z))
	move_and_slide()

	# Procedural variants: advance the solver AFTER the body has moved. It locks feet to world
	# points, and a plant computed against where the body hoped to go rather than where it ended up
	# is a plant that slides.
	if _solver:
		# CHASING WITH THE MACE UP. The solver asks for ground during a wind-up (see the REPOSITION
		# zone) and this is where the body pays for it -- uncapped by move_speed, because the request
		# is already rate-limited by what the solver believes the ogre can cover, and clamping it to
		# a walk here would quietly reintroduce the thing that made running away free.
		var push := _solver.consume_root_motion()
		if push.length_squared() > 0.0:
			global_position += push        # an action's lunge, as displacement rather than a jump
		_solver.tick(delta, velocity, is_on_floor(), _visual_yaw())

	# skeletal variants: locomotion anim follows velocity; Slash is started by _start_attack.
	# GATED ON THE FSM, not just the tree: gating on the current NODE alone was measured to
	# fail — get_current_node() is stale for a frame after a reaction's travel() is queued, and
	# the follower reading "Idle" plus a knockback velocity issued travel("Move") that REPLACED
	# the queued Knockdown outright. The FSM knows the truth the tree hasn't processed yet:
	# reaction states (FLINCH/STAGGER/DEAD) own the tree, and the follower only speaks in the
	# locomotion states. The node check stays as the second key — a Getup still playing after
	# the FSM returned to CHASE must finish before the follower takes the wheel.
	if _anim_pb and (_state == S.IDLE or _state == S.CHASE or _state == S.FEAR):
		var cur := _anim_pb.get_current_node()
		if cur == &"Idle" or cur == &"Move":
			var planar := Vector2(velocity.x, velocity.z).length()
			var want := "Move" if planar > 0.4 else "Idle"
			if String(cur) != want:
				_anim_pb.travel(want)
			if _tree != null and cur == &"Move":
				# The 1D blend: idle at 0, run at 1 — acceleration reads as a lean-in.
				_tree.set("parameters/Move/blend_position",
						clampf(planar / maxf(move_speed, 0.1), 0.0, 1.0))
	# skeletal ATTACK deadline: the clip's own ending (animation_finished + the AT_END edge) is
	# the real return path; this deadline only speaks if a cross-fade swallowed the signal.
	if _anim_pb and _state == S.ATTACK and _attack_watch > 0.0:
		_attack_watch -= delta
		if _attack_watch <= 0.0:
			_state = S.CHASE
	# Engine head-tracking: LookAtModifier3D does the work — this only says WHERE (the player's
	# head) and HOW MUCH (eased per state: full while reading the fight, damped mid-swing so a
	# committed attack does not owl-track, zero while hurt, staggered, fleeing or dead).
	if _look != null and is_instance_valid(_player):
		_look_target.global_position = _player.global_position + Vector3(0, 1.4, 0)
		var want_inf := 0.0
		match _state:
			S.IDLE, S.CHASE:
				want_inf = 1.0
			S.ATTACK:
				want_inf = 0.4
		_look.influence = move_toward(_look.influence, want_inf, delta * 4.0)


## THE BODY YAW IS A WORLD FACT. The solver's whole frame is world-space -- forward(), side_dir(),
## every plant point and the knee pole -- while each modifier layer converts back through
## `skel.global_transform`. Reading this as a LOCAL Euler made the two halves agree only while every
## ancestor sat at identity. Rotate the Ogre root and they disagree by exactly the root's rotation:
## the knee pole swings alongside the limb, the two-bone solve hits the degenerate case it bails out
## of, and the rig shears. Taken off the basis rather than global_rotation.y so no Euler-order or
## scale assumption rides along -- the death tween squashes Visuals to 0.08 in Y.
func _visual_yaw() -> float:
	var f := -_visuals.global_basis.z
	return atan2(-f.x, -f.z)


## Aim a WORLD yaw through the local slot, as a delta -- no Euler round-trip.
func _set_visual_yaw(world_yaw: float) -> void:
	_visuals.rotation.y += wrapf(world_yaw - _visual_yaw(), -PI, PI)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	if _solver:
		# A HARD RATE LIMIT, not an exponential ease. Turning is lateral acceleration and a heavy
		# body can only lean so far into it, so the solver derives a ceiling from its own mass --
		# about 55 deg/s at a walk against the 570 the ease below produces. That difference is the
		# single loudest tell that a big model is a small character scaled up, and it is what makes
		# flanking a four-metre creature a readable tactic instead of a reaction test.
		#
		# An ease is also fastest when the error is LARGEST, which is exactly when something heavy
		# should look most reluctant.
		var cap := _solver.yaw_rate(_solver.speed) * delta
		if _solver.aim_tracking():
			# TURNING IS PART OF THE ATTACK. The walking cap is about lateral acceleration on a heavy
			# body and it is right for walking, but applied to a creature mid-wind-up it meant a
			# player could simply walk round the shoulder and the swing had no answer. A wind-up is
			# the one time the ogre is allowed to be visibly trying.
			cap *= _solver.tuning.aim_turn_boost
		_set_visual_yaw(_visual_yaw() + clampf(wrapf(yaw - _visual_yaw(), -PI, PI), -cap, cap))
		return
	_set_visual_yaw(lerp_angle(_visual_yaw(), yaw, 1.0 - exp(-10.0 * delta)))

# RANGED movement: hold a firing distance — back-pedal if the player crowds us, close in if
# they run, otherwise stand and shoot when off cooldown.
func _chase_ranged(to_player: Vector3, dist: float) -> void:
	var dir := to_player.normalized()
	if dist < preferred_range * 0.7:
		velocity.x = -dir.x * move_speed          # too close → kite backwards
		velocity.z = -dir.z * move_speed
	elif dist > preferred_range:
		velocity.x = dir.x * move_speed           # too far → close the gap
		velocity.z = dir.z * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if _cool <= 0.0 and dist <= aggro_range:
		_start_attack()


## PICK UP A ROCK. Ported from the puppet, whose header asked for exactly this: "when this becomes
## a real Enemy the whole function moves to enemy.gd unchanged."
##
## The arena has had eight rocks sitting in it since it was built and the ogre has never touched
## one, because rock_throw could not be chosen and had no beat handler if it had been. It is the
## cheapest attack in the creature — everything it needs was already written.
func _grab_rock() -> void:
	if _held != null:
		return
	var best: Node3D
	var best_d := 6.5
	for r in get_tree().get_nodes_in_group("rock"):
		var d: float = global_position.distance_to((r as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = r
	if best == null:
		return
	_held = best
	_held.call("take", _rock_hand(), _solver.rock_hold)
	# Both hands are on the rock now, so stow the mace as well as dropping the carry pose — a
	# four-metre weapon still hanging off the fist while the ogre hefts a boulder reads as a bug.
	_solver.carrying = &""
	_solver.show_weapon(false)


## Let it go. A ballistic lob rather than a straight shot: the arc IS the tell, and a rock you can
## see coming is a rock you can walk away from, which is the difference between a threat and a tax
## on reaction time.
func _release_rock() -> void:
	if _held == null:
		return
	var from: Vector3 = _held.global_position
	# A Vector3, not a float -- it is the mesh scale times the radius. Wrapping it in float() threw
	# on the first rock the ogre ever picked up.
	var size: Vector3 = _held.call("visual_scale")
	_held.queue_free()
	_held = null
	_solver.carrying = &"carry"
	_solver.show_weapon(true)
	var rock := THROWN_ROCK.instantiate() as Projectile
	get_parent().add_child(rock)
	rock.global_position = from
	rock.shooter = self          # a parried rock flies back at the ogre that heaved it
	var m := rock.get_node_or_null("Model/Mesh") as MeshInstance3D
	if m:
		m.scale = size / 0.55
	var aim: Vector3 = _player.global_position if is_instance_valid(_player) \
			else global_position + _solver.forward() * 14.0
	# Mask 2 is the player's hurtbox. The same ballistic solver the archer's arrow and its aim
	# preview both use, so the arc drawn and the arc flown cannot disagree.
	rock.setup_ballistic(aim, 2, rock.damage, Color(0.55, 0.53, 0.5))


## Where a carried thing rides: the weapon socket the solver already built, so a rock and the mace
## are held in the same place by construction.
func _rock_hand() -> Node3D:
	var g: Node3D = _solver.grip_node()
	return g if g != null else self


## Does this attack live beyond the range the ogre closes to? Those are the ones that need their own
## clock -- everything else happens when it arrives.
func _is_ranged(n: StringName) -> bool:
	var a: ActionSpec = _solver.spec(n)
	return a != null and not a.use_strike_zone and a.reach_min >= _reach()


## Is there anything to pick up? Without this the ogre commits to a lift, finds nothing, and stands
## there having mimed it -- which is what the unwired version did whenever it was reachable.
func _rock_near() -> bool:
	for r in get_tree().get_nodes_in_group("rock"):
		if global_position.distance_to((r as Node3D).global_position) < 6.5:
			return true
	return false


## HOW FAR THIS THING CAN ACTUALLY HIT FROM.
##
## Taken from the solver's own strike zone when there is one, because the exported number was a
## guess and the geometry is not: `attack_range` said 5.2 m while the arm can only put the mace head
## 2.6 m from the shoulder. The ogre was starting swings from twice its reach, straining at every one
## of them, and every other fix for that was cosmetic.
##
## A little past the far edge, because the ogre is allowed to start a swing it will close the last
## of the distance on -- that is what the ADVANCE zone is for.
func _reach() -> float:
	if _solver == null:
		return attack_range
	# INSIDE the band, not past it. The +0.6 that used to be here was meant as an allowance for the
	# ogre closing the last of the distance during its wind-up, but it stops the chase at a range
	# where the swing cannot reach -- and the attack chooser, asked at that range, answers with
	# whatever ranged attack does fit. The two disagreed, and the ogre threw rocks forever.
	# HOW CLOSE IT WANTS TO BE, which is a different question from what can reach. Taking the
	# furthest of ALL its attacks put this at 16 m -- the rock throw's outer edge -- so `dist >
	# _reach()` was almost never true and the ogre stopped walking anywhere at all. It stood at
	# range and lobbed things, which is not the fight.
	#
	# It closes to the mace. The long attacks get their chance on the way in (see the chase), not by
	# redefining where "in range" is.
	return _solver.strike_zone().y * 0.9


## HOW FAR THIS BODY CAN HIT FROM, for anyone outside it. The director sizes its waiting ring off
## this and must NOT re-derive it: a ring computed from the exported `attack_range` while the body
## actually swings from strike_zone().y * 0.9 is a ring in the wrong place for exactly the creature
## whose exported number was a guess -- see this function's own header, where a declared 5.2 m met
## a measured 2.6 m arm.
func reach() -> float:
	return _reach()


## HOW CLOSE COUNTS AS ARRIVED, for whatever we are walking to. The player's own strike band when
## we are going for them -- _reach(), the number the whole chase has always turned on. A tight
## SLOT_ARRIVE when we are going to a waiting slot, because a ring position honoured to within
## 2.4 m is not a ring, it is a suggestion. SLOT_ARRIVE also equals the agent's own
## target_desired_distance, so the FSM and the NavigationAgent cannot disagree about having got
## there; two clocks for one moment is the failure this project has hit more often than any other.
const SLOT_ARRIVE := 0.7

func _goal_reach() -> float:
	return _reach() if _goal_is_player else SLOT_ARRIVE


## WHERE WE ARE WALKING. The player when it is our turn, when we never opted in, or when the
## director has no opinion -- which is every frame of every scene without an agent, and is why the
## branch that calls this collapses to the one that shipped.
##
## Otherwise a point on a ring OUTSIDE this body's own reach. Waiting your turn has to mean standing
## SOMEWHERE, and standing in the player's back is what made four enemies read as one enemy with
## four sprites.
func _goal() -> Vector3:
	_goal_is_player = true
	if not is_instance_valid(_player):
		return global_position
	if _agent == null or _has_token:
		return _player.global_position
	var slot: Vector3 = CombatDirector.slot_for(self)
	if slot == Vector3.INF:
		return _player.global_position
	_goal_is_player = false
	return slot


## Planar distance to the goal. Handed `dist` so the player case costs nothing and, more to the
## point, returns the SAME float the caller already computed -- no second length() that could round
## differently and drop the branch on the other side of its comparison.
func _goal_dist(goal: Vector3, dist: float) -> float:
	if _goal_is_player:
		return dist
	var to := goal - global_position
	to.y = 0.0
	return to.length()


## THE STEERING DIRECTION, and the no-op is the point: with no agent this returns
## `to_player.normalized()` -- not something equivalent to it, the same expression the chase used
## before any of this existed. With one, it is the path corner (so the body walks AROUND a rock
## instead of into it) bent by RVO (so it walks around a swordsman too).
##
## Normalised on the way out because SPEED belongs to this file. The agent's max_speed exists only
## to bound RVO's search; move_speed and _solver.run_speed() still decide the pace, which is what
## keeps "it can follow you but never outrun you" true.
##
## NAMED SIMPLIFICATION: this keeps RVO's DIRECTION and discards its MAGNITUDE, which is the other
## half of how RVO resolves a conflict. If two bodies ever deadlock head-on at full speed, the
## one-line experiment is to fold `out.length() / _agent.max_speed` back in as a factor on `sp`.
func _steer(goal: Vector3, to_player: Vector3) -> Vector3:
	if _agent == null or not _nav_ready:
		return to_player.normalized()
	# RE-TARGETED EVERY FRAME, DELIBERATELY. A debounce was tried here -- only re-point the agent
	# once the goal has moved half a metre -- because a waiting body's goal drifts every frame and
	# re-pathing every frame is wasteful. It also leaves a STALE PATH behind whenever the body is
	# moved rather than walking (a teleport, a scene reset, a knockback), and the whole pack simply
	# stopped approaching: measured at 7-8 m out, motionless, turns granted and reclaimed unspent.
	# Correctness first; if this ever costs measurable frame time, cache on the AGENT's position as
	# well as the goal's, not on the goal alone.
	_nav_target = goal
	_agent.target_position = goal
	var next := _agent.get_next_path_position()
	var wish := next - global_position
	wish.y = 0.0
	if wish.length() < 0.05:
		# NO PATH THIS FRAME -- an unreachable goal, or a server that has not synced. Head straight
		# for THE GOAL, which is the honest fallback for whatever we were asked to walk to: when the
		# goal is the player this is exactly the expression that shipped, and when it is a ring
		# position "go there directly" is right where "charge the player" was precisely backwards.
		var direct := goal - global_position
		direct.y = 0.0
		return direct.normalized() if direct.length() > 0.05 else to_player.normalized()
	wish = wish.normalized()
	_nav_wish = wish * maxf(move_speed, 0.1)      # reported once, beside move_and_slide()
	if not _agent.avoidance_enabled or _nav_safe_age > 2:
		return wish
	var out := _nav_safe
	out.y = 0.0
	return out.normalized() if out.length() > 0.05 else wish


## RVO'S ANSWER, ONE FRAME LATE, AND DELIBERATELY NOT WHERE THE DOCS PUT IT.
##
## set_velocity() hands our wish to the NavigationServer, which runs the avoidance simulation on
## its own sync and emits this AFTER _physics_process has already returned. The documented sample
## calls move_and_slide() from inside this callback. THIS FILE CANNOT: move_and_slide() is followed
## by consume_root_motion() and _solver.tick(), and three comments in this file record the bugs
## that came from those running any number of times other than once per physics frame. A second
## move_and_slide() here would integrate gravity twice and desync every foot plant by a frame of
## travel.
##
## So this only STORES. The cost is one frame -- 16 ms at 60 Hz -- of avoidance lag on a body whose
## fastest turn is 55 deg/s, i.e. a quarter of a degree of stale heading. The cost of the
## alternative is the invariant.
func _on_safe_velocity(safe: Vector3) -> void:
	_nav_safe = safe
	_nav_safe_age = 0


## The director raises this body's avoidance_priority while it holds a turn, which is the entire
## "the crowd parts for the committed attacker" behaviour. Asked for rather than reached into: the
## director re-finding the agent itself would be a second copy of the discovery rule in _ready().
func nav_agent() -> NavigationAgent3D:
	return _agent


## MAY WE SWING? The cached answer to the request made above, and unconditionally true for a body
## that never opted in -- which is what keeps this branch identical for every scene without agents.
func _may_attack() -> bool:
	return _agent == null or _has_token


## ASK FOR A TURN. False means someone else is mid-swing: the caller simply does not attack this
## frame, keeps its cooldown at zero, and asks again. Returns true unconditionally for a body that
## never opted in, which is every frame of every scene without an agent.
func _claim_token() -> bool:
	if _agent == null:
		return true
	var had := _has_token
	_has_token = CombatDirector.request_attack(self, _player)
	if _has_token and not had:
		_turn_used = false
	return _has_token


## Flat distance to the player, or a large number if there is none.
func _dist_to_player() -> float:
	if not is_instance_valid(_player):
		return 9999.0
	var to := _player.global_position - global_position
	to.y = 0.0
	return to.length()

## WHICH ATTACK TO THROW at this distance -- the DECISION half of attack selection, living here
## on purpose. The solver answers only actions_reaching() (what the body could do, deterministic);
## this picks among that list at random with one reroll against the last attack thrown, so the
## same range stays unpredictable without ever naming something that cannot reach.
func choose_attack(dist: float) -> StringName:
	if _solver == null:
		return &""
	var fits: Array[StringName] = _solver.actions_reaching(dist)
	if fits.is_empty():
		return &""
	if fits.size() == 1:
		return fits[0]
	var pick: StringName = fits[randi() % fits.size()]
	if pick == _last_attack:
		pick = fits[randi() % fits.size()]
	return pick


## The weighted follow-up roll -- a decision, so it rolls here; the weights are the spec's own
## data, read through spec() (a data query, not a delegation of the choice). Strings are what stop
## an attack set being a menu: a player who has learned that a backstep is followed by a sweep is
## reading the creature rather than reacting to it.
func _roll_chain(n: StringName) -> StringName:
	if _solver == null:
		return &""
	var a: ActionSpec = _solver.spec(n)
	if a == null or a.chains.is_empty():
		return &""
	var total := 0.0
	for k in a.chains:
		total += float(a.chains[k])
	if total <= 0.0:
		return &""
	var roll := randf() * maxf(total, 1.0)
	for k in a.chains:
		roll -= float(a.chains[k])
		if roll <= 0.0:
			return k
	return &""


## Remember an attack this AI just threw (non-attacks are ignored), so the chooser's reroll has
## something to reroll against. Called at every play site the AI owns; the dev harnesses drive the
## solver directly and keep no memory, which is correct -- they are not playing tactics.
func _note_attack(n: StringName) -> void:
	if _solver == null:
		return
	var a: ActionSpec = _solver.spec(n)
	if a != null and a.is_attack:
		_last_attack = n


func _start_attack() -> void:
	_state = S.ATTACK
	_cool = attack_cooldown
	_flash(Color(1.0, 0.55, 0.1))                 # telegraph (orange wind-up)

	# THE SOLVER OWNS THE ATTACK when there is one, whatever `attack_kind` says. Its action already
	# knows the wind-up, the strike, the damage window and (for a slam) the ground telegraph, and it
	# fires them as the animation reaches them -- so routing an ogre down the AREA branch as well
	# would spawn a second, unsynchronised blast. This check went BELOW the match first and the ogre
	# simply never attacked: kind was AREA, the match consumed it, and play_action was never reached.
	if _solver:
		_attack_tween = null
		# WHICH ATTACK, not just "the attack". The slam has a hole in the middle of it -- it cannot
		# reach inside the ogre's own footprint -- and always playing it meant a player standing
		# close got a wind-up that was abandoned a moment later, every time. The solver picks by
		# range from the actions' own derived bands, and falls back to the slam so a distance no
		# attack claims still produces the telegraph the chase is built around.
		var pick: StringName = choose_attack(_dist_to_player())
		if _held != null:
			# HOLDING A BOULDER, THE ANSWER IS THE BOULDER — whatever the range. The throw's
			# 5..16 m band gated this before, and a held rock deadlocked the whole fight: it
			# chains rock_throw on every recover (you cannot stand holding one), the chain only
			# plays from the ATTACK branch, and any pass through CHASE forgot it — so a player
			# who stayed close locked the punish window shut for an entire probe run (0.00 s,
			# measured). A rock leaves the hand at the first opportunity, full stop.
			pick = &"rock_throw"
		elif pick == &"rock_throw":
			# The throw is the second half of a two-part action. Ask for the first. No rock in
			# reach cannot happen from the far branch any more (it gates on one), so the slam
			# fallback below catches the leftover case the retired charge used to.
			pick = &"rock_lift" if _rock_near() else &""
		var played: StringName = pick if pick != &"" else &"slam"
		_note_attack(played)
		_solver.play_action(played)
		# THE ACTION SAYS WHEN IT IS DONE, not a stopwatch started beside it. This was a tween on
		# action_len * 0.85, and the two clocks do not agree: the wind-up can HOLD at the top for up
		# to aim_hold_max while the ogre turns, and holding freezes the action's clock. So the
		# stopwatch reached the handoff while the swing was still at t=1.20 of 2.22 -- the state
		# went back to CHASE mid-recovery, the cooldown was already spent, and the next slam started
		# on top of the one still finishing. Seven attacks in a fight and the recover beat fired
		# ONCE: there was no recovery to punish because the ogre never played one.
		return

	# Kept as a member so a stagger (poise break / parry) can KILL it mid-wind-up — otherwise the
	# queued callbacks (arrow fire, slam, hitbox activate) fire even though the swing was
	# interrupted. Created only PAST the solver branch: the solver path returned above without
	# ever adding a tweener, and the empty tween printed "started with no Tweeners" once per
	# attack, every fight.
	var t := create_tween()
	_attack_tween = t

	match attack_kind:
		AttackKind.RANGED:
			t.tween_callback(func(): if _state == S.ATTACK: _fire_projectile()).set_delay(0.4)
			t.tween_callback(func(): if _state == S.ATTACK: _state = S.CHASE).set_delay(0.25)
		AttackKind.AREA:
			t.tween_callback(func(): if _state == S.ATTACK: _spawn_area_attack()).set_delay(0.25)
			t.tween_callback(func(): if _state == S.ATTACK: _state = S.CHASE).set_delay(0.5)
		_:
			# melee: strike after the wind-up. Skeletal variants play the Slash clip and take
			# their timing FROM it — the animation is the telegraph, damage lands on the blade.
			var strike := 0.45
			var recover := 0.25
			if _solver:
				# The procedural branch. The hitbox is opened and closed by the solver's own beats
				# (see _on_solver_event), so this tween only has to hand the state back afterwards.
				_solver.play_action(&"slam")
				t.tween_callback(func(): if _state == S.ATTACK: _state = S.CHASE) \
						.set_delay(_solver.action_len * 0.85)
				return
			if _anim_pb:
				# THE CLIP OWNS THE SWING. The damage window is a Call Method track inside
				# atk_h (see _shared_library) and the ending is the clip's own AT_END edge +
				# animation_finished — this branch starts the state and sets a deadline, and
				# that is ALL. `_attack_tween` deliberately stays null here: the probe reads it
				# as the proof the stopwatch path did not run. An interrupt needs no guard —
				# travelling out of Slash stops the clip, and unreached keys never fire.
				t.kill()
				_attack_tween = null
				# WHICH SWING. One state for a body with one attack; a body that brought several
				# picks among them, and each carries its own window in its own clip.
				_anim_pb.start(attack_states.pick_random() if not attack_states.is_empty() else &"Slash")
				_attack_watch = _slash_len + 0.8
				return
			# guard the strike: a mid-wind-up interrupt (stagger) must never spawn the hit
			t.tween_callback(func(): if _state == S.ATTACK: _attack_hitbox.activate()).set_delay(strike)
			t.tween_callback(_attack_hitbox.deactivate).set_delay(0.18)
			t.tween_callback(func(): if _state == S.ATTACK: _state = S.CHASE).set_delay(recover)

# Lob an arrow onto the player's CURRENT position (mask 2 = player hurtbox layer only).
# Ballistic + a RED impact marker for the flight time = the player sees where it will land
# and can dodge out — telegraphed ranged pressure instead of an unreactable hitscan.
#
# WHICH shot is decided by the band the player stands in AT FIRE TIME (the band exports above):
# the distance read when the wind-up started is ~0.4 s stale by now, and a player who closed
# during the wind-up has earned the near-band answer, not the one they dodged into range of.
func _fire_projectile() -> void:
	if projectile_scene == null or not is_instance_valid(_player):
		return
	_volleys += 1
	if pierce_every > 0 and _volleys % pierce_every == 0:
		_fire_pierce()
		return
	var dist := _dist_to_player()
	if burst_count > 1 and dist < preferred_range * 0.7:
		_fire_burst()
		return
	var arrow := projectile_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = _spawn_point()
	arrow.shooter = self                       # a parry sends it back HERE
	var target: Vector3 = _player.global_position
	var lobbed := far_lob and dist > preferred_range
	var h := -1.0
	if lobbed:
		h = arrow.speed * 0.45             # slower horizontally = a TOWERING arc = longer warning
	var flight := arrow.setup_ballistic(target, 2, projectile_damage, Color(1.0, 0.5, 0.2), h)
	if lobbed and impact_wave_scene != null:
		# The surface attack: only a lob that LANDS detonates (impacted never fires on a body
		# hit — a direct hit already paid). Dodging the ring buys the player a second problem.
		arrow.impacted.connect(_spawn_impact_wave)
	var marker := (load("res://scenes/fx/impact_marker.tscn") as PackedScene).instantiate() as ImpactMarker
	marker.color = Color(1.0, 0.35, 0.2)
	get_tree().current_scene.add_child(marker)
	marker.global_position = Vector3(target.x, target.y - 0.85, target.z)   # capsule centre -> floor
	marker.start_lifetime(flight)

## Where a projectile leaves from: the Muzzle marker when the scene ships one, else the legacy
## chest-height guess that predates any enemy having an actual barrel.
func _spawn_point() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	return global_position + Vector3(0, 1.3, 0)

# The NEAR-band answer: a horizontal fan of straight bolts around the line to the player's chest.
# Straight setup() flight, not ballistic — at 4 m an arc has no room to arc, and the point of this
# shot is pressure NOW while the feet are already kiting; the fan is dodged sideways. No impact
# marker either: a marker warns about a landing, and these do not land, they fly until they hit.
func _fire_burst() -> void:
	var spawn := _spawn_point()
	var base: Vector3 = _player.global_position + Vector3(0, 0.6, 0) - spawn
	for i in burst_count:
		var ang := deg_to_rad(burst_spread_deg) * (float(i) - float(burst_count - 1) * 0.5)
		var bolt := projectile_scene.instantiate() as Projectile
		get_tree().current_scene.add_child(bolt)
		bolt.global_position = spawn
		bolt.shooter = self
		bolt.setup(base.rotated(Vector3.UP, ang), 2, projectile_damage, Color(1.0, 0.5, 0.2))
		if homing_deg > 0.0:
			# The fan closes gently on a strafing player — enough to punish standing STILL in
			# the kite band, capped low enough that the dodge stays a sidestep, not a sprint.
			bolt.home(_player, homing_deg, homing_time)

# THE PURPLE ONE. A single unparriable bolt, launched deliberately OFF the line — swung wide to
# a side (alternating) and pitched up — then homing pulls it back in hard. The wrong-way launch
# is not decoration: it is the read. A bolt that starts wide and bends toward you says "this one
# follows" in the first tenth of a second, which is exactly the warning an attack that ignores
# the guard owes the player. It stops steering after homing runs out, so running its turning
# circle beats it — follow-to-a-degree, never a guarantee.
func _fire_pierce() -> void:
	var spawn := _spawn_point()
	var bolt := projectile_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = spawn
	bolt.shooter = self
	bolt.parriable = false
	var side := 1.0 if (_volleys / maxi(pierce_every, 1)) % 2 == 0 else -1.0
	var chest: Vector3 = _player.global_position + Vector3(0, 0.6, 0)
	var dir := (chest - spawn).normalized().rotated(Vector3.UP, side * deg_to_rad(55.0))
	dir = (dir + Vector3.UP * 0.5).normalized()
	bolt.setup(dir, 2, projectile_damage, PIERCE_COLOR)
	bolt.home(_player, 180.0, 1.1)

## The surface attack, at the lob's crater. The wave scene owns everything from here —
## propagation, the jump-over rule, the unblockable routing (see ground_wave.gd).
func _spawn_impact_wave(pos: Vector3) -> void:
	if impact_wave_scene == null:
		return
	var wave := impact_wave_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(wave)
	# The ballistic "lands" at its target's capsule-centre height, not the floor — same
	# convention (and same -0.85) as the impact marker two functions up. A hardcoded y=0 here
	# would strand the wave below any fight that happens on raised ground.
	wave.global_position = Vector3(pos.x, maxf(pos.y - 0.85, 0.0) + 0.03, pos.z)

# Drop a telegraphed ground-slam at our feet; the AreaAttack owns its own warn→pulse timing.
func _spawn_area_attack() -> void:
	if area_attack_scene == null:
		return
	var slam := area_attack_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(slam)
	slam.global_position = global_position

## The big break — from a parry OR a poise depletion. Stop, flash blue, cancel any wind-up in
## progress, and can't act for a moment (the punish window). Poise refills so the next flurry
## has to earn its break again.
func stagger() -> void:
	if _state == S.DEAD:
		return
	if _state == S.STAGGER and _anim_pb != null:
		# Already broken — likely FLOORED (the knockdown reuses this state). A second break must
		# not SHORTEN the clock (1.3 s vs a ~2.2 s knockdown) or yank a body off the floor into
		# the standing hurt pose: keep the longer timer, refill poise, leave the pose alone.
		_stagger_t = maxf(_stagger_t, 1.3)
		_poise = max_poise
		return
	_state = S.STAGGER
	_stagger_t = 1.3
	_cool = attack_cooldown
	_poise = max_poise
	if _attack_tween:
		_attack_tween.kill()          # abort the interrupted swing's queued strike
	if _solver:
		# Exactly the same reason the tween is killed: a wind-up that survives its own interruption
		# lands a blow the player already dodged. fear()'s docstring below spells out the shape of
		# that bug; this is the procedural half of it.
		_solver.cancel_action()
		_solver.play_action(&"stagger")
	_attack_hitbox.deactivate()
	if _anim_pb:
		# The break is a REACTION CLIP now (used to be start("Idle") — dropping the sword said
		# "interrupted" but nothing said "hit"). Hurt's AT_END edge hands Idle back by itself.
		_anim_pb.travel("Hurt")
	_flash(Color(0.5, 0.85, 1.0))
	EventBus.combat_impact.emit(0.35) # a break kicks the camera harder than a normal trade


## THE FINISHER'S ANSWER: floored, then up again — hurt_knockback then getup, chained by the
## tree's own AT_END edges with zero timers on the animation side. The FSM reuses S.STAGGER
## for "cannot act" (no new state — AiGraph's hand-authored graph stays honest) with a timer
## computed from the SAME clip lengths the tree is playing, so the two clocks cannot drift.
func _knockdown() -> void:
	_state = S.STAGGER
	_stagger_t = maxf(_knock_len + _getup_len - 0.2, 0.5)
	_cool = attack_cooldown
	_poise = max_poise
	if _attack_tween:
		_attack_tween.kill()
	_attack_hitbox.deactivate()
	velocity.x = _last_hit_dir.x * flinch_knockback * 2.0
	velocity.z = _last_hit_dir.z * flinch_knockback * 2.0
	_anim_pb.travel("Knockdown")
	_flash(Color(1.0, 0.6, 0.2))
	EventBus.combat_impact.emit(0.3)


## DRAMA'S DOING: this one turns and runs for `duration` seconds.
##
## Modelled on stagger() above, and it has to be — the same four safety moves apply. In particular
## _attack_tween owns the QUEUED STRIKE of a swing already in flight, and killing the state does not
## kill the tween: a feared archer whose wind-up was left running fires its arrow anyway, from
## across the room, while fleeing. That is not a corner case, it is what happens whenever Fear procs
## on the hit that interrupted an attack — which is most of them.
##
## Poise is deliberately NOT refilled. A stagger is a punish you earned and it resets the wall; fear
## is a windfall, and it should not also hand back the poise you had just spent a combo breaking.
func fear(duration := 2.0) -> void:
	if _state == S.DEAD or duration <= 0.0 or fearless:
		return
	_state = S.FEAR
	_fear_t = duration
	_cool = attack_cooldown
	if _attack_tween:
		_attack_tween.kill()
	if _solver:
		_solver.cancel_action()
	_attack_hitbox.deactivate()
	if _anim_pb:
		_anim_pb.start("Move")            # skeletal: it is running, so play running
	_flash(Color(1.0, 0.78, 0.34))        # Drama's gold, so the cause is legible
	EventBus.combat_impact.emit(0.2)

## CONTACT. This enemy's basic melee box landed on someone whose hp changed.
func _on_attack_landed(_target: Node, _pos: Vector3, applied: int) -> void:
	if applied > 0:
		# Scaled by our own mass: a mace arriving should not land like a dagger.
		CombatFeedback.contact_landed(minf(0.06 * heft, 0.16), clampf(0.1 / heft, 0.03, 1.0),
				0.25 * heft)


## Every landed hit routes here. Grunts flinch on each hit (rewards aggression); armored foes
## shrug off light hits and only react when POISE runs out. Either way the hit chips poise, and
## depleting it triggers the big stagger above.
func _on_damaged(amount: int, _source: Node) -> void:
	_flash(Color(1, 1, 1))
	if _health.hp == 0:
		# THE KILLING BLOW, read here and not in _on_died: hp is already zeroed when `damaged`
		# fires and `died` (next in the same chain) carries no amount or source. The kill's
		# longer, deeper freeze MERGES with the sword's own contact stop inside Fx.hitstop —
		# latest deadline, deepest scale — so a kill reads harder than a chip, every time.
		CombatFeedback.kill_landed()
	if _state == S.DEAD:
		return
	_since_hit = 0.0
	if _winded_t > 0.0:
		_winded_hits += 1
		if _winded_hits >= punish_hits:
			# SPENT. The combo landed; now it answers. Ending the window rather than letting it run
			# is what turns "the ogre is open" into "the ogre is open for three hits", which is a
			# rhythm a player can learn instead of a stretch of time they can stand in.
			_winded_t = 0.0
			_cool = 0.0
			_step_t = 0.0
	# BEING HIT PROVOKES A REPLY. The cooldown is a breather for the PLAYER -- it is the punish
	# window after a swing -- but it was also being served while standing still being beaten, which
	# turns a boss into a heavy bag: 3.4 s of nothing per attack, and a player inside its guard can
	# spend all of that hitting it. A creature that is being hit does not wait out its own recovery.
	# Cutting the REMAINING cooldown rather than clearing it keeps the post-swing punish intact --
	# you still get your window, you just cannot extend it indefinitely by standing there.
	# RETALIATION DOES NOT CUT SHORT THE PUNISH WINDOW. Cutting the remaining cooldown is the right
	# answer to being beaten on while idle, and exactly the wrong one during recovery: the player's
	# first landed hit would close the window they had just earned, which is the punish window
	# deleting itself the moment it is used.
	if retaliate_after >= 0.0 and _winded_t <= 0.0:
		_cool = minf(_cool, retaliate_after)
	if _source is Node3D:
		var push := global_position - (_source as Node3D).global_position
		push.y = 0.0
		if push.length() > 0.05:
			_last_hit_dir = push.normalized()   # the blow's direction — the ragdoll's shove
		# ...and its WEIGHT: the attack's own knockback number, the same meta the living body's
		# shove reads. F = ma for the corpse — a kick at 22 throws what a bolt at 6 nudges.
		_last_hit_kb = float(_source.get_meta("knockback", 6.0)) if _source != null else 6.0
	_poise -= amount
	if _poise <= 0.0:
		stagger()                     # poise broken → full interrupt (resets poise itself)
	elif _anim_pb != null and _source != null and bool(_source.get_meta("finisher", false)) \
			and _state != S.STAGGER:
		# The combo FINISHER floors a skeletal enemy even with poise to spare — the hitbox
		# carries the fact the same way it carries knockback (a meta, written per swing).
		_knockdown()
	elif flinches_on_hit and _state != S.STAGGER:
		_flinch(_source)

## Micro-stun: a brief recoil away from the attacker + white flash (already done above). Does NOT
## cancel a committed heavy — that separation is what makes armored foes read differently.
func _flinch(source: Node) -> void:
	_state = S.FLINCH
	_flinch_t = flinch_time
	# Like stagger() and fear(): a flinch that aborts a swing mid-window must close the window
	# itself — the clip's own close key is out of reach once the travel stops the fade.
	_attack_hitbox.deactivate()
	var away := Vector3.ZERO
	if source is Node3D:
		away = global_position - (source as Node3D).global_position
	elif is_instance_valid(_player):
		away = global_position - _player.global_position
	away.y = 0.0
	if away.length() > 0.01:
		away = away.normalized()
		velocity.x = away.x * flinch_knockback
		velocity.z = away.z * flinch_knockback
	if _anim_pb:
		# The reaction is a CLIP now. Before this, the locomotion follower read the knockback
		# velocity and travelled to Move — the swordsman visibly JOGGED while being hit.
		_anim_pb.travel("Hurt")
	if _solver and not _solver.is_acting():
		# The ogre's half of the same statement — the flinch action (hunter_dmg_f through the
		# skin) finally reachable from gameplay. Only between actions: a flinch that cancelled
		# a committed heavy would erase exactly the distinction this function documents.
		_solver.play_action(&"flinch")

func _on_died() -> void:
	_state = S.DEAD
	# THE ONE RELEASE THE STATE-DRIVEN LINE CANNOT MAKE: _physics_process returns on DEAD before it
	# ever reaches that line. A body killed mid-swing would take its turn to the grave, the cap
	# would never refill, and the surviving pack would stand on its ring forever. The director's
	# watchdog would reclaim it in 0.25 s; this makes it the same frame, which is the difference
	# between a rhythm and a hitch -- and it keeps the watchdog counter at zero, which is what lets
	# the probe treat any reclaim at all as a leak.
	_has_token = false
	_turn_used = false
	CombatDirector.release_attack(self)
	$HurtBox.set_deferred("monitorable", false)
	_attack_hitbox.deactivate()
	EventBus.enemy_died.emit(self)
	if _ragdoll != null:
		_die_ragdoll()
		return
	if _anim_pb != null:
		# Skeletal but the ragdoll builder resolved no bones: the death CLIP is the fallback.
		_anim_pb.travel("Death")
		var dt := create_tween()
		dt.tween_interval(2.6)
		dt.tween_callback(queue_free)
		return
	var t := create_tween()
	t.tween_property(_visuals, "scale", Vector3(1, 0.08, 1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


## DEATH IS THE ENGINE'S PHYSICS: stop the mixer, hand the skeleton to the PhysicalBone
## simulation, shove it along the killing blow's direction. The body capsule is disabled first —
## the bones share layer 1 with it and would otherwise land on their own corpse's collider.
## No sink/shrink on the way out: simulated bones live in world space and ignore Visuals
## transforms, so the corpse simply lies where physics left it until the timer frees it.
func _die_ragdoll() -> void:
	if _look != null:
		_look.influence = 0.0
		_look.active = false
	if _tree != null:
		_tree.active = false
	if _solver != null:
		# The ogre: a mid-swing death must close its windows and telegraphs before the corpse
		# takes over — the solver's layers themselves stand down in _start_ragdoll.
		_solver.cancel_action()
	# Deferred BOTH, in order: the capsule's disable is necessarily deferred (we are inside a
	# physics callback), and a simulation started before it flushes sees the live capsule for
	# one frame — the corpse pops. The deferred queue preserves order: disable, then simulate.
	$Collision.set_deferred("disabled", true)
	_start_ragdoll.call_deferred()
	var t := create_tween()
	t.tween_interval(2.5)
	t.tween_callback(queue_free)


func _start_ragdoll() -> void:
	if _ragdoll == null or not is_instance_valid(_ragdoll):
		return
	# Every OTHER skeleton modifier stands down first — the LookAt today, a solver's layers the
	# day the ogre gets its ragdoll. Two modifiers writing one corpse is the fold-in-half trap.
	var skel := _ragdoll.get_parent() as Skeleton3D
	if skel != null:
		for c in skel.get_children():
			if c is SkeletonModifier3D and c != _ragdoll:
				(c as SkeletonModifier3D).active = false
	_ragdoll.physical_bones_start_simulation()
	# MOMENTUM CONTINUITY — the F = ma the developer asked for by name. Every bone is seeded
	# with the launch velocity (the body was a moving mass when it died; a corpse that forgets
	# that is the bag of potatoes), scaled by the killing blow's own knockback weight, plus
	# half of whatever motion the body already carried. Seeded AFTER start_simulation on
	# purpose: the kinematic→rigid transition resets body state, and velocities written before
	# it are wiped.
	var launch := (_last_hit_dir + Vector3.UP * 0.35).normalized() \
			* clampf(_last_hit_kb * 0.55, 2.0, 9.0) + velocity * 0.5
	var core := (_last_hit_dir + Vector3.UP * 0.6).normalized() * 3.5 * (_last_hit_kb / 6.0)
	for pb in _ragdoll.get_children():
		if pb is PhysicalBone3D:
			(pb as PhysicalBone3D).linear_velocity = launch
			if String((pb as PhysicalBone3D).bone_name) in ["Hips", "Chest"]:
				# The accent through the core — the blow went THROUGH this body, not past it.
				(pb as PhysicalBone3D).apply_central_impulse(core * (pb as PhysicalBone3D).mass)

func _flash(c: Color) -> void:
	# Cel-shaded variants flash via the toon shader's flash uniform; greybox ones tint emission.
	if _toon:
		_toon.flash(c)
		return
	if _flash_mats.is_empty():
		return
	for m in _flash_mats:
		m.emission_enabled = true
		m.emission = c
	var t := create_tween()
	t.tween_method(func(e: float):
		for m in _flash_mats:
			m.emission_energy_multiplier = e
	, 2.5, 0.0, 0.3)

extends Node3D
## THE DIRECTIONAL-COMBAT BENCH. Two identical fighters, one of them a person and one of them a
## brain, and a set of assertions about the only thing that makes them different: which way a
## swing was thrown and which way a guard was pointing.
##
## THE GATE (run as a SCENE, never --script — the AnimationTree must actually advance, so no
## --headless either):
##   godot --resolution 900x760 res://scenes/dev/duel_probe.tscn --log-file duel.log -- --demo=probe
## Eyes (four guard poses and a wind-up, as PNGs, for tuning guard_pose.gd's angles):
##   ... -- --demo=shots --out=renders/duel
## Hands: run it with no --demo at all and fight the duelist yourself.
##
## HOW IT DRIVES THEM, and this is the part worth understanding. Neither fighter is puppeteered
## through Input or through its state machine — the probe writes the SAME FighterIntent fields a
## person's hands and the duelist's brain write, with the intent's own _physics_process switched
## off so nothing overwrites the script. If a check here passes, the identical sequence of
## decisions passes in a real fight, because there is no other path into these states.

const SETTLE := 20        ## physics frames to let a spawn/transition settle before asserting
const SWING_MAX := 240    ## frames to wait on a swing before calling it hung

var fails: Array[String] = []
var notes: Array[String] = []

@onready var player: Player = $Player
@onready var duelist: Player = $Duelist
@onready var readout: Label = $UI/Readout


func _ready() -> void:
	var mode := ""
	var out := "renders/duel"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			mode = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
	match mode:
		"probe":
			_run_probe()
		"shots":
			_run_shots(out)
		"axes":
			_run_axes(out)


func _process(_delta: float) -> void:
	if readout == null or not is_instance_valid(player):
		return
	readout.text = "\n".join([
		"player   %s  guard %s  charging %s  hp %d  stam %.0f  v %.2f" % [
			player.state_name(), SwingDir.label(player.current_guard_dir()),
			SwingDir.label(player.charging_dir()), player.health.hp, player.stamina,
			Vector2(player.velocity.x, player.velocity.z).length()],
		"duelist  %s  guard %s  charging %s  hp %d" % [
			duelist.state_name(), SwingDir.label(duelist.current_guard_dir()),
			SwingDir.label(duelist.charging_dir()), duelist.health.hp],
		"gap %.2f m" % player.global_position.distance_to(duelist.global_position),
	])


# --- The probe -------------------------------------------------------------------------------

func _run_probe() -> void:
	await _frames(SETTLE)

	# Both fighters go on strings. Turning the intent's own _physics_process off is the whole
	# mechanism: the fields stay exactly as this script last wrote them.
	player.intent.set_physics_process(false)
	duelist.intent.set_physics_process(false)
	player.intent.clear()
	duelist.intent.clear()

	await _check_identity()
	await _check_mirror_is_pure()
	await _check_poses_distinct()
	await _check_guard_speed()
	await _check_matched_guard()
	await _check_mismatched_guard()
	await _check_root()
	await _check_commitment_and_interrupts()
	await _check_held_footwork()
	await _check_all_contacts()
	await _check_parry_contact()
	await _check_guard_break_and_cover()
	await _check_spacing()
	await _check_guard_feedback()
	await _check_contact_assist()
	await _check_lock_facing()
	await _check_brain()

	for f in fails:
		print("[PROBE] FAIL  " + f)
	for msg in notes:
		print("[PROBE] note  " + msg)
	print("[PROBE] %s — %d checks failed" % ["RED" if fails.size() else "GREEN", fails.size()])
	get_tree().quit(1 if fails.size() else 0)


## The duelist has to be an enemy in every way the rest of the project asks the question, and the
## layers have to be swapped BOTH ways or one fighter is invulnerable and the bug looks like a
## missed swing.
func _check_identity() -> void:
	if not duelist.is_in_group("enemy"):
		fails.append("duelist is not in the \"enemy\" group")
	if duelist.is_in_group("player"):
		fails.append("duelist is still in the \"player\" group")
	if duelist.is_input_driven():
		fails.append("duelist is input-driven; the human's keys would move it")
	if not player.is_input_driven():
		fails.append("player did not get a PlayerIntent")
	var hurt := duelist.get_node_or_null("HurtBox") as Area3D
	if hurt == null or hurt.collision_layer != 4:
		fails.append("duelist HurtBox is not on the enemy layer; the player's sword cannot reach it")
	var hb := duelist.sword.get_node_or_null("HitBox") as Area3D if duelist.sword else null
	if hb == null or hb.collision_mask != 2:
		fails.append("duelist sword HitBox does not mask the player; its swings cannot land")
	if not player.get_node("StateMachine").has_state("DirAttack"):
		fails.append("player3 has no DirAttack state")
	if not player.get_node("StateMachine").has_state("Guard"):
		fails.append("player3 has no Guard state")


## The one flip in the whole system. If mirror is ever made symmetric on the vertical axis, every
## overhead becomes unblockable and every thrust becomes unmissable, and no damage test would say so.
func _check_mirror_is_pure() -> void:
	if SwingDir.mirror(SwingDir.LEFT) != SwingDir.RIGHT:
		fails.append("mirror(LEFT) is not RIGHT")
	if SwingDir.mirror(SwingDir.RIGHT) != SwingDir.LEFT:
		fails.append("mirror(RIGHT) is not LEFT")
	if SwingDir.mirror(SwingDir.UP) != SwingDir.UP or SwingDir.mirror(SwingDir.DOWN) != SwingDir.DOWN:
		fails.append("mirror flipped the vertical axis; up and down do not swap across an exchange")


## Four directions that look the same are four directions nobody can read, and every damage check
## in this file would still pass.
func _check_poses_distinct() -> void:
	var pose := player.guard_pose
	if pose == null:
		fails.append("player has no GuardPose modifier")
		return
	var seen: Array[Vector3] = []
	for d in SwingDir.ALL:
		var e: Vector3 = pose.euler_for(d)
		if e == Vector3.ZERO:
			fails.append("guard pose for %s is the identity" % SwingDir.label(d))
		if e in seen:
			fails.append("guard pose for %s duplicates another direction" % SwingDir.label(d))
		seen.append(e)


## Guarding costs you the ground. The number is the Guard state's own move_scale against the
## player's top speed, read back rather than hard-coded, so retuning either one keeps this honest.
func _check_guard_speed() -> void:
	var guard_state := player.get_node("StateMachine/Guard")
	_face_off()
	player.intent.guard = true
	player.intent.guard_dir = SwingDir.UP
	# SIDEWAYS, deliberately. Walking at the other fighter measures the collision between two
	# capsules, not the guarded speed — the first version of this check read 0.00 m/s for exactly
	# that reason and looked like a broken guard.
	player.intent.move = Vector2(1, 0)
	await _until(func(): return player.state_name() == "Guard", 60, "player never entered Guard")
	await _frames(25)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var want: float = player.move_speed * float(guard_state.move_scale)
	if absf(speed - want) > 0.6:
		fails.append("guarded walk is %.2f m/s, expected about %.2f" % [speed, want])
	else:
		notes.append("guarded walk %.2f m/s (free run %.2f)" % [speed, player.move_speed])
	player.intent.clear()
	await _frames(SETTLE)


## THE MECHANIC. The duelist guards the direction the swing is actually coming from: no damage,
## and the attacker is left open.
func _check_matched_guard() -> void:
	var thrown := SwingDir.LEFT
	_face_off()
	duelist.intent.guard = true
	duelist.intent.guard_dir = SwingDir.mirror(thrown)   # the guard that answers it
	await _until(func(): return duelist.state_name() == "Guard", 90, "duelist never raised its guard")

	var hp_before: int = duelist.health.hp
	await _swing(player, thrown)
	await _frames(20)

	if duelist.health.hp != hp_before:
		fails.append("a matched guard let %d damage through" % (hp_before - duelist.health.hp))
	else:
		notes.append("matched guard: 0 damage")
	if player.state_name() != "DirAttack":
		fails.append("player left DirAttack before the block could recoil it")
	else:
		var st := player.get_node("StateMachine/DirAttack")
		if st.charging():
			fails.append("blocked swing is somehow still charging")
	if duelist.stamina >= duelist.max_stamina:
		fails.append("a blocked hit cost the defender no stamina")
	_reset()
	await _frames(SETTLE)


## And the other half: the guard that is pointing the wrong way is not a guard at all.
func _check_mismatched_guard() -> void:
	var thrown := SwingDir.LEFT
	_face_off()
	duelist.intent.guard = true
	# Deliberately the guard that would have worked, flipped — a wrong READ, not a missing guard.
	duelist.intent.guard_dir = SwingDir.UP
	await _until(func(): return duelist.state_name() == "Guard", 90, "duelist never raised its guard")

	var hp_before: int = duelist.health.hp
	await _swing(player, thrown)
	await _frames(20)

	if duelist.health.hp >= hp_before:
		fails.append("a mismatched guard took no damage; the guard is not directional")
	else:
		notes.append("mismatched guard: %d damage through" % (hp_before - duelist.health.hp))
	_reset()
	duelist.health.revive()
	await _frames(SETTLE)


## A swing plants you. Without the root, circling beats reading.
func _check_root() -> void:
	_face_off()
	player.intent.move = Vector2(1, 0)
	player.intent.attack_dir = SwingDir.UP
	player.intent.attack_held = true
	await _until(func(): return player.state_name() == "DirAttack", 60, "player never entered DirAttack")
	var st := player.get_node("StateMachine/DirAttack")
	await _until(func(): return not st.charging(), SWING_MAX, "swing never left the wind-up",
			func(): player.intent.attack_held = false)
	# MEASURE INSIDE THE STRIKE, not after it. Past the clip's cancel point a held direction
	# move-cancels straight back into Move and the body accelerates to full speed again — which is
	# correct, and which read as a root failure when this waited six frames instead of two.
	await _frames(2)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if speed > player.move_speed * 0.2:
		print("ROOT_TRACE state=",player.state_name()," phase=",st._phase," t=",st._t," length=",st._len," cap=",st.root_speed)
		fails.append("body still moving at %.2f m/s during the strike; the swing is not rooted" % speed)
	else:
		notes.append("rooted at %.2f m/s through the strike" % speed)
	_reset()
	await _frames(SETTLE)


## Hand the duelist back its own mind and watch it fight. Not scored on winning — scored on doing
## the two things the mechanic is made of.
func _check_commitment_and_interrupts() -> void:
	_reset()
	_face_off()
	_park_duelist()
	var a := player.get_node("AnimationTree") as AnimationTree
	var b := duelist.get_node("AnimationTree") as AnimationTree
	if a.tree_root == b.tree_root or a.get_animation("chop") == b.get_animation("chop"):
		fails.append("fighters share mutable action animation resources")
	for d in SwingDir.ALL:
		player.intent.attack_dir = d
		player.intent.attack_held = true
		await _frames(48)
		var st := player.get_node("StateMachine/DirAttack")
		if not st.charging(): fails.append("held swing lost its windup")
		if not a.active: fails.append("held swing disabled the skeleton's animation tree")
		player.get_node("StateMachine").transition_to("Hurt")
		await _frames(25)
		if a.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			fails.append("hurt interruption left the animation clock frozen")
		if player.state_name() == "DirAttack": fails.append("held input retriggered after interruption")
		player.intent.attack_held = false
		await _frames(2)
	# Holding beyond the automatic release must produce exactly one committed blow.
	player.stamina = player.max_stamina
	player.intent.attack_held = true
	await _frames(190)
	if player.state_name() == "DirAttack": fails.append("held button repeats attacks without a new press")
	_reset()
	notes.append("independent animation resources; four held-pose interruptions; no hold-to-repeat")
	await _frames(SETTLE)

func _check_held_footwork() -> void:
	_reset()
	_face_off()
	_park_duelist()
	player.intent.attack_held = true
	await _frames(40)
	player.intent.move = Vector2(0,-1)
	await _frames(12)
	var skel := player.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var knee := skel.find_bone("LeftLowerLeg")
	if knee < 0:
		fails.append("footwork test cannot find knee")
	else:
		var before := skel.get_bone_pose_rotation(knee)
		await _frames(12)
		if before.angle_to(skel.get_bone_pose_rotation(knee)) < .03:
			fails.append("held attack still freezes the moving fighter's knee")
	var tree := player.get_node("AnimationTree") as AnimationTree
	if float(tree["parameters/Slash/ActionClock/scale"]) != 0.0:
		fails.append("footwork resumed the held weapon animation")
	if float(tree["parameters/Slash/Legs/blend_amount"]) < .9:
		fails.append("lower-body gait mask did not engage")
	_reset()
	await _frames(SETTLE)
	notes.append("held weapon clock stays paused while lower-body gait advances")

func _check_all_contacts() -> void:
	for d in SwingDir.ALL:
		_reset()
		_face_off()
		duelist.health.revive()
		await _frames(SETTLE)
		var hp := duelist.health.hp
		await _swing(player, d)
		await _frames(40)
		if duelist.health.hp >= hp:
			fails.append("%s blade arc missed an unguarded opponent at 1.4 m" % SwingDir.label(d))
		elif hp - duelist.health.hp != player.sword.get_node("HitBox").damage:
			fails.append("%s swing damaged the same opponent more than once" % SwingDir.label(d))
	_reset()
	_face_off()
	_park_duelist()
	duelist.health.revive()
	var hp := duelist.health.hp
	await _swing(player, SwingDir.UP)
	await _frames(60)
	if duelist.health.hp != hp: fails.append("out-of-range swing hit")
	_reset()
	notes.append("tested all four blade arcs, single-hit damage and out-of-range miss")
	await _frames(SETTLE)

func _check_parry_contact() -> void:
	_reset()
	_face_off()
	player.health.revive()
	duelist.health.revive()
	await _frames(SETTLE)
	await _swing(player, SwingDir.LEFT)
	duelist.intent.guard_dir = SwingDir.RIGHT
	duelist.intent.guard = true
	var hp := duelist.health.hp
	await _frames(20)
	var st := player.get_node("StateMachine/DirAttack")
	if duelist.health.hp != hp: fails.append("timed matched guard took damage")
	if duelist.stamina > 91.0 or duelist.stamina < 89.0:
		fails.append("timed contact was not a parry (stamina %.1f)" % duelist.stamina)
	if st._phase != st.Phase.RECOIL:
		fails.append("parry did not recoil the attacker")
	if player.sword.get_node("HitBox")._active:
		fails.append("parried blade remained damaging")
	_reset()
	await _frames(SETTLE)
	notes.append("timed parry contact: recoil, reduced stamina cost, damage window cancelled")

func _check_guard_break_and_cover() -> void:
	_reset()
	_face_off()
	duelist.intent.guard = true
	duelist.intent.guard_dir = SwingDir.RIGHT
	await _frames(30)
	duelist.stamina = 20.0
	await _swing(player, SwingDir.LEFT)
	await _frames(20)
	if duelist.state_name() != "Hurt": fails.append("exhausted guard did not stagger")
	if duelist.stamina > 5.0: fails.append("guard break did not exhaust stamina")
	_reset()
	_face_off()
	duelist.health.revive()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,4,.12)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = Vector3(0,1,0)
	await _frames(SETTLE)
	var hp := duelist.health.hp
	await _swing(player, SwingDir.LEFT)
	await _frames(45)
	if duelist.health.hp != hp: fails.append("blade damaged an opponent through solid cover")
	wall.queue_free()
	_reset()
	await _frames(SETTLE)
	notes.append("guard-break stagger and solid-cover rejection")

func _check_spacing() -> void:
	_reset()
	_face_off()
	var brain := duelist.intent as DuelBrain
	brain._opponent = player
	brain._mode = brain.Mode.SWING
	brain._step_start = duelist.global_position - Vector3(.36,0,0)
	brain._swing_t = 0.0
	brain._drive(.016, 2.0, Vector2(0,1))
	if brain.move.length() > .001: fails.append("attack approach exceeded its step budget")
	brain._mode = brain.Mode.RESET
	brain._drive(.016, 1.0, Vector2(0,1))
	if brain.move.dot(Vector2(0,1)) >= 0.0: fails.append("crowded reset did not request retreat")
	_reset()
	_face_off()
	player.global_position.z = .45
	duelist.global_position.z = -.45
	var saved_aggression := brain.aggression
	brain.aggression = 0.0
	brain._reset_left = 1.2
	brain._was_committed = false
	brain.set_physics_process(true)
	await _frames(75)
	var gap := Vector2(player.global_position.x-duelist.global_position.x, player.global_position.z-duelist.global_position.z).length()
	if gap < 1.4: fails.append("crowded duel failed to reopen spacing: %.2f m" % gap)
	brain.set_physics_process(false)
	brain.aggression = saved_aggression
	brain._reset_left = 0.0
	brain._mode = brain.Mode.WAIT
	_reset()
	await _frames(SETTLE)
	notes.append("bounded approach and crowded-start recovery: %.2f m separation" % gap)

func _check_guard_feedback() -> void:
	_reset()
	_face_off()
	duelist.intent.guard = true
	var skel := duelist.find_child("GeneralSkeleton",true,false) as Skeleton3D
	var head := skel.find_bone("Head")
	for direction in SwingDir.ALL:
		duelist.intent.guard_dir = direction
		await _frames(30)
		await RenderingServer.frame_post_draw
		var head_point := skel.global_transform * skel.get_bone_global_pose(head).origin
		var segment := duelist.sword.blade_segment()
		var nearest := Geometry3D.get_closest_point_to_segment(head_point,segment[0],segment[1])
		if nearest.distance_to(head_point) < .20:
			fails.append("guard blade crowds head in %s: %.2f m" % [SwingDir.label(direction),nearest.distance_to(head_point)])
	duelist.intent.guard_dir = SwingDir.RIGHT
	await _frames(30)
	player.intent.attack_dir = SwingDir.LEFT
	player.get_node("StateMachine").transition_to("DirAttack")
	player.sword.hit(.3,false,1,SwingDir.LEFT)
	var blade := duelist.sword.blade_segment()
	var middle := (blade[0]+blade[1])*.5
	var intercepted := player.sword._try_blade_interception(middle-Vector3.RIGHT*.2,middle+Vector3.RIGHT*.2)
	if not intercepted: fails.append("crossing swords did not intercept a matching guard")
	if not player.sword.get_node("HitBox").has_meta("contact_point"):
		fails.append("sword interception supplied no contact position")
	if Vector2(duelist.velocity.x,duelist.velocity.z).length() > .36:
		fails.append("sword block still applies excessive body shove")
	if duelist.guard_pose._impact_strength <= 0:
		fails.append("sword block did not trigger arm recoil")
	_reset()
	await _frames(SETTLE)
	notes.append("four guard head-clearances; crossing-blade interception; restrained block recoil")

func _check_contact_assist() -> void:
	_reset()
	_face_off()
	player.visuals.global_rotation.y = 0.0
	duelist.global_position = player.global_position+Vector3(.04,0,-1.48)
	player.intent.attack_held = true
	player.get_node("StateMachine").transition_to("DirAttack")
	var st := player.get_node("StateMachine/DirAttack")
	st._target = duelist
	var before := player.global_position
	for i in 10:
		st._assist_elapsed = i*.016
		st._face(.016)
	var travelled := before.distance_to(player.global_position)
	if travelled < .01 or travelled > .101:
		fails.append("near-edge assist moved %.3f m, expected >0 and <=0.10" % travelled)
	if absf(player.visuals.global_rotation.y) > deg_to_rad(5.01):
		fails.append("contact assist exceeded its turn cap")
	st._phase = st.Phase.SWING
	before = player.global_position
	var yaw := player.visuals.global_rotation.y
	duelist.global_position.x += .3
	st._face(.1)
	if before != player.global_position or yaw != player.visuals.global_rotation.y:
		fails.append("released attack still follows its target")
	st._begin(SwingDir.RIGHT)
	st._target = duelist
	if st._assist_travel < travelled-.001: fails.append("direction change reset the assist budget")
	st._assist_elapsed = 0.0
	duelist.global_position = player.global_position+Vector3(0,0,-2.0)
	st._face(.1)
	if before != player.global_position: fails.append("assist rescued an out-of-range attack")
	duelist.global_position = player.global_position+Vector3(0,0,1.45)
	st._face(.1)
	if before != player.global_position: fails.append("assist targeted behind the fighter")
	_reset()
	await _frames(SETTLE)
	notes.append("contact assist %.3f m; capped turn; no pursuit after release or at bad range" % travelled)

func _check_lock_facing() -> void:
	_reset()
	_face_off()
	var rig := get_tree().get_first_node_in_group("camera_rig") as CameraRig
	var orbit := rig.orbit_enabled
	rig.orbit_enabled = false
	if rig.locked(): rig.toggle_lock()
	rig.toggle_lock()
	if rig.locked() != duelist: fails.append("fixed-camera lock-on failed to acquire duelist")
	for movement in [Vector2(1,0),Vector2(0,1)]:
		player.intent.move = movement
		await _frames(25)
		var bearing := duelist.global_position-player.global_position
		bearing.y = 0.0
		var facing := -player.visuals.global_basis.z
		facing.y = 0.0
		if facing.normalized().dot(bearing.normalized()) < .85:
			fails.append("locked movement turned the player's back on the enemy")
	rig.toggle_lock()
	if player.combat_lock_target() != null: fails.append("lock toggle did not release target")
	rig.orbit_enabled = orbit
	_reset()
	await _frames(SETTLE)
	notes.append("fixed-camera lock, strafe/backward facing and unlock")

func _check_brain() -> void:
	_face_off()
	_reset()
	player.health.revive()
	duelist.health.revive()
	# ONLY THE DUELIST GETS ITS MIND BACK. The player stays on strings and keeps swinging: a probe
	# has no hands, and a duelist standing opposite someone who never attacks has nothing to guard
	# against, so "it never raised a guard" would be a fact about the test rather than the AI.
	duelist.intent.set_physics_process(true)

	var guarded := false
	var swung := false
	var dirs_seen: Dictionary = {}
	var attack_clock := 0
	for i in 900:
		await get_tree().physics_frame
		if duelist.current_guard_dir() != SwingDir.NONE:
			guarded = true
		var c: int = duelist.charging_dir()
		if c != SwingDir.NONE:
			swung = true
			dirs_seen[c] = true
		# A slow drumbeat of swings from the player: wind up for half a second, release, pause.
		attack_clock += 1
		var beat := attack_clock % 90
		if beat == 1:
			player.intent.attack_dir = SwingDir.ALL[(attack_clock / 90) % SwingDir.COUNT]
			player.intent.attack_held = true
		elif beat == 32:
			player.intent.attack_held = false
			player.intent.request_release()
		player.intent.look = _bearing(player, duelist)

	if not guarded:
		fails.append("the duelist never raised a guard in 15 seconds")
	if not swung:
		fails.append("the duelist never wound up a directional swing in 15 seconds")
	notes.append("duelist used %d of the 4 attack directions" % dirs_seen.size())


# --- Helpers ---------------------------------------------------------------------------------

## Wind up in `dir` and let go, the way a person would.
func _swing(who: Player, dir: int) -> void:
	who.intent.attack_dir = dir
	who.intent.attack_held = true
	await _until(func(): return who.state_name() == "DirAttack", 60,
			"%s never entered DirAttack" % who.name)
	var st := who.get_node("StateMachine/DirAttack")
	# Let it reach the apex, then release — the same two-step a held swing always is.
	await _until(func(): return st.pending_dir() == dir, 30, "swing did not take its direction")
	await _frames(30)
	who.intent.attack_held = false
	who.intent.request_release()
	await _until(func(): return not st.charging(), SWING_MAX, "swing never left the wind-up")


## Put them face to face inside contact range, still and neutral.
func _face_off() -> void:
	player.global_position = Vector3(0, 1.1, .7)
	duelist.global_position = Vector3(0, 1.1, -.7)
	player.velocity = Vector3.ZERO
	duelist.velocity = Vector3.ZERO
	player.stamina = player.max_stamina
	duelist.stamina = duelist.max_stamina
	# AIM THEM. Without a look direction a scripted fighter falls back to Player.aim_point's cursor
	# branch, and in a probe the "cursor" is the top-left corner of the window — the swing turns
	# away and misses, and every damage assertion below quietly passes for the wrong reason.
	player.intent.look = Vector2(0, -1)
	duelist.intent.look = Vector2(0, 1)


func _reset() -> void:
	player.intent.clear()
	duelist.intent.clear()
	player.get_node("StateMachine").transition_to("Idle")
	duelist.get_node("StateMachine").transition_to("Idle")
	player.intent.look = Vector2(0, -1)
	duelist.intent.look = Vector2(0, 1)


## One body in frame. Two of them in a pose comparison is one sword too many to attribute, and it
## must run AFTER _face_off, which puts both fighters back on their marks.
func _park_duelist() -> void:
	duelist.global_position = Vector3(0, 1.1, -30)
	duelist.intent.clear()


## World-XZ direction from one fighter to another — what FighterIntent.look wants.
func _bearing(from: Node3D, to: Node3D) -> Vector2:
	var d: Vector3 = to.global_position - from.global_position
	return Vector2(d.x, d.z).normalized() if Vector2(d.x, d.z).length() > 0.01 else Vector2(0, -1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Wait for a condition, and FAIL LOUDLY rather than hanging if it never comes. A probe that hangs
## on a regression reports nothing at all, which is worse than reporting the wrong thing.
func _until(cond: Callable, limit: int, msg: String, each := Callable()) -> void:
	for i in limit:
		if cond.call():
			return
		if each.is_valid():
			each.call()
		await get_tree().physics_frame
	fails.append(msg)


# --- Eyes ------------------------------------------------------------------------------------

## One frame per guard direction plus a held wind-up, so the four poses can be compared side by
## side. This is how guard_pose.gd's angles get tuned — they are not measurements and must not be
## treated as any.
func _run_shots(out: String) -> void:
	await _frames(SETTLE)
	player.intent.set_physics_process(false)
	duelist.intent.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	_face_off()
	_park_duelist()
	# ITS OWN CAMERA, rather than the bench rig. The rig is framed for a fight you are watching and
	# eases toward that framing over time; these frames exist to compare four arm positions, and at
	# the fighting distance the whole difference is about a dozen pixels of sword. A fixed camera
	# also makes the four frames directly comparable, which is the entire point of taking them.
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	# Offsets are from the body ORIGIN, which sits at the capsule centre near the floor, not at the
	# eyes — hence the lift on both the camera and the point it looks at.
	cam.global_position = player.global_position + Vector3(3.8, 2.0, 3.4)
	cam.look_at(player.global_position + Vector3(0, 0.05, 0), Vector3.UP)
	cam.make_current()

	for d in SwingDir.ALL:
		player.intent.clear()
		player.intent.look = Vector2(0, -1)   # clear() wipes it, and facing must not drift between frames
		player.intent.guard = true
		player.intent.guard_dir = d
		await _frames(45)
		await _shot("%s/guard_%s.png" % [out, SwingDir.label(d)])

	for d in SwingDir.ALL:
		player.intent.clear()
		player.intent.look = Vector2(0, -1)
		await _frames(30)
		player.stamina = player.max_stamina
		player.intent.attack_dir = d
		player.intent.attack_held = true
		await _frames(45)
		await _shot("%s/windup_%s.png" % [out, SwingDir.label(d)])
		player.intent.attack_held = false
		player.intent.request_release()
		await _frames(17)
		await _shot("%s/strike_%s.png" % [out, SwingDir.label(d)])
		await _frames(55)
		await _shot("%s/recovered_%s.png" % [out, SwingDir.label(d)])

	print("[SHOTS] written to res://%s" % out)
	get_tree().quit(0)


## WHICH AXIS DOES WHAT, rendered rather than assumed. The offsets in guard_pose.gd are applied in
## skeleton space, and this rig arrives through a humanoid retarget with a 180-degree correction on
## the model — so "pitch the arm up" is an empirical question about this skeleton, not something to
## be reasoned out from the axis names. One frame per axis, at an angle large enough to be
## unmistakable.
func _run_axes(out: String) -> void:
	await _frames(SETTLE)
	player.intent.set_physics_process(false)
	duelist.intent.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	_face_off()
	_park_duelist()
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	cam.global_position = player.global_position + Vector3(3.4, 2.1, 2.6)
	cam.look_at(player.global_position + Vector3(0, 0.85, 0), Vector3.UP)
	cam.make_current()

	var pose := player.guard_pose
	player.intent.clear()
	player.intent.look = Vector2(0, -1)
	player.intent.guard = true
	player.intent.guard_dir = SwingDir.UP
	for probe in [["none", Vector3.ZERO], ["x+60", Vector3(60, 0, 0)], ["x-60", Vector3(-60, 0, 0)],
			["y+60", Vector3(0, 60, 0)], ["y-60", Vector3(0, -60, 0)],
			["z+60", Vector3(0, 0, 60)], ["z-60", Vector3(0, 0, -60)]]:
		pose.up_euler = probe[1]
		await _frames(40)
		await _shot("%s/axis_%s.png" % [out, probe[0]])
	print("[AXES] written to res://%s" % out)
	get_tree().quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://" + path)

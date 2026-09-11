extends Node3D
## PLAYER VERSUS SWORDSMAN — the STANDARD-GODOT enemy, provable.
##
## The robot proved the behaviour layer generalizes on zero new systems; this scene proves the
## OTHER commitment: that where the engine ships the machinery, we use the engine's. The
## swordsman's swing window is a Call Method track inside its attack clip, its attack END is
## the clip's own AT_END edge + animation_finished, its locomotion is a BlendSpace1D, its hit
## reactions are tree states that hand back through AUTO transitions, its death is a
## PhysicalBone3D ragdoll, and its head tracks the player through LookAtModifier3D. The FSM,
## bands, hitboxes, feedback, lock-on and the F5 AI graph are the same shared code every enemy
## runs — behaviour custom (Godot has no AI), animation standard (Godot has plenty).
##
## KEYS: WASD move · LMB attack (3rd swing floors it) · Space jump · Shift dash ·
##       RMB guard/parry · MMB/R3 lock · R restart · F1 readout · F3 hitboxes · F5 AI graph
##
## THE GATE (run as a SCENE, never --script):
##   godot --resolution 900x760 res://scenes/dev/player_vs_swordsman.tscn --log-file s.log -- --demo=probe
## Eyes:
##   ... -- --demo=shots --out=<dir>

@onready var _player: Node3D = $Player
## WHICH BODY IS ON TRIAL. Everything below this line already speaks to the enemy through the
## shared contract -- Health, HurtBox, AnimationTree, the FSM -- so the only thing that ever tied
## this lab to the swordsman was the node name. Exported instead, and player_vs_ogre2.tscn reuses
## this whole harness (readout, F-keys, lock-on, restart) by pointing it at a different node.
@export var enemy_node: NodePath = ^"Swordsman"
@onready var _enemy: Enemy = get_node(enemy_node)
@onready var _readout: Label = $UI/Readout

var _hits_on_enemy := 0
var _hits_on_player := 0
var _t := 0.0


func _ready() -> void:
	(_enemy.get_node("Health") as Health).damaged.connect(func(_a, _s): _hits_on_enemy += 1)
	var ph := _player.get_node_or_null("Health")
	if ph:
		ph.damaged.connect(func(_a, _s): _hits_on_player += 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			_demo(a.substr(7).rstrip("/\\"))


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.is_pressed() or e.is_echo():
		return
	match (e as InputEventKey).keycode:
		KEY_R:
			get_tree().reload_current_scene()
		KEY_F1:
			($UI as CanvasLayer).visible = not ($UI as CanvasLayer).visible


func _process(_delta: float) -> void:
	var dbg := get_node_or_null("/root/Dbg")
	if dbg != null and bool(dbg.clean):
		($UI as CanvasLayer).visible = false
	_t += _delta
	if not is_instance_valid(_enemy):
		_readout.text = "swordsman down after %.1f s — R to restart" % _t
		return
	var dist := 0.0
	if is_instance_valid(_player):
		dist = _player.global_position.distance_to(_enemy.global_position)
	var hp := _enemy.get_node("Health") as Health
	var pb: AnimationNodeStateMachinePlayback = _enemy.get("_anim_pb")
	var lines := PackedStringArray()
	lines.append("distance %5.2f m      melee reach %.1f m" % [dist, _enemy.attack_range])
	# FSM state ⇄ tree node on ONE line: the pair the whole standard wiring promises to keep in
	# step. If these two ever disagree for more than a cross-fade, something above is lying.
	lines.append("fsm      %-8s  tree  %s" % [
			["IDLE", "CHASE", "ATTACK", "FLINCH", "STAGGER", "DEAD", "FEAR"][int(_enemy.get("_state"))],
			String(pb.get_current_node()) if pb != null else "-"])
	lines.append("hp %d/%d   poise %.0f/%.0f   next swing %.1f s"
			% [hp.hp, hp.max_hp, float(_enemy.get("_poise")), float(_enemy.get("max_poise")),
			float(_enemy.get("_cool"))])
	lines.append("")
	lines.append("hits on it %d      hits on you %d      %.0f s" % [_hits_on_enemy, _hits_on_player, _t])
	lines.append("3rd combo swing FLOORS it · kill = ragdoll · it watches you (head)")
	lines.append("WASD · LMB attack · Space jump · Shift dash · RMB guard · MMB lock · F5 AI graph · R restart")
	_readout.text = "\n".join(lines)


# ---------------------------------------------------------------------------------------------
# Headless proof of the STANDARD wiring specifically.

func _demo(kind: String) -> void:
	match kind:
		"probe":
			_demo_probe()
		"shots":
			var out := "user://swordsman_shots"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--out="):
					out = a.split("=", true, 1)[1]
			_demo_shots(out)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _place(dist: float) -> void:
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	var pos := _enemy.global_position
	_player.global_position = Vector3(pos.x, 1.1, pos.z + dist)


func _heal() -> void:
	(_player.get_node("Health") as Health).revive()


## The probe chips the SUBJECT too (interrupt, flinch, finisher all deal real damage to a 4-hp
## enemy) — heal it between blocks or the finisher test performs an accidental execution and
## every later block interrogates a corpse.
func _heal_enemy() -> void:
	if is_instance_valid(_enemy):
		(_enemy.get_node("Health") as Health).revive()
		# Poise too: a subject entering the finisher test one chip from broken takes the poise
		# STAGGER instead of the knockdown, and the test reads a different mechanism than it
		# thinks it is testing.
		_enemy._poise = _enemy.max_poise


## A distance this body can actually hit from: inside its own trigger range, but far enough out
## that a long weapon has swung through. Scales with the body instead of assuming a swordsman.
func _strike_distance() -> float:
	return maxf(float(_enemy.get("attack_range")) * 0.9, 1.5)


## Which tree states count as "attacking" for THIS body. See the note at the assertion.
func _attack_state_names() -> Array:
	var declared: Array = _enemy.get("attack_states")
	return declared if declared != null and not declared.is_empty() else [&"Slash"]


## How long does the clip in this tree state run? See the note at its use.
func _state_clip_len(state: StringName) -> float:
	var tree := _enemy.get_node_or_null("AnimationTree") as AnimationTree
	if tree == null:
		return 0.0
	var sm := tree.tree_root as AnimationNodeStateMachine
	if sm == null or not sm.has_node(state):
		return 0.0
	var node := sm.get_node(state) as AnimationNodeAnimation
	var lib := tree.get_animation_library(&"")
	if node == null or lib == null or not lib.has_animation(node.animation):
		return 0.0
	return lib.get_animation(node.animation).length


## Does the body's AnimationTree have this state at all?
func _has_state(state: StringName) -> bool:
	var tree := _enemy.get_node_or_null("AnimationTree") as AnimationTree
	if tree == null:
		return false
	var sm := tree.tree_root as AnimationNodeStateMachine
	return sm != null and sm.has_node(state)


## LookAtModifier3D needs a bone called exactly "Head" (see enemy.gd:_setup_head_look).
func _find_head_bone() -> bool:
	var skel := _enemy.find_child("*Skeleton*", true, false) as Skeleton3D
	return skel != null and skel.find_bone("Head") >= 0


func _demo_probe() -> void:
	var fails: Array[String] = []
	var notes: Array[String] = []
	var pb: AnimationNodeStateMachinePlayback = _enemy.get("_anim_pb")
	_enemy._cool = 9.0
	# Deterministic subject: the sword rolls Drama's fear on every landed hit, and a probe whose
	# finisher randomly sends its subject sprinting is a probe that fails on dice.
	_enemy.fearless = true
	await _settle(20)

	# --- The standard wiring is PRESENT, not just its effects -----------------------------
	if pb == null:
		fails.append("no AnimationTree playback — this scene exists to prove the tree path")
	if _enemy.get("_solver") != null:
		fails.append("a solver on the swordsman — wrong enemy")
	var tree := _enemy.get_node("AnimationTree") as AnimationTree
	var lib := tree.get_animation_library(&"")
	for clip_name in [&"hurt", &"hurt_knockback", &"getup", &"death"]:
		if lib == null or not lib.has_animation(clip_name):
			fails.append("library is missing the merged reaction clip '%s'" % clip_name)
	var slash: Animation = lib.get_animation(&"atk_h") if lib else null
	var method_keys := 0
	if slash != null:
		for i in slash.get_track_count():
			if slash.track_get_type(i) == Animation.TYPE_METHOD:
				method_keys = slash.track_get_key_count(i)
	if method_keys != 2:
		fails.append("atk_h carries %d method keys — the damage window must live IN the clip" % method_keys)
	# A CORPSE IS EITHER SIMULATED OR AUTHORED. The swordsman falls as a PhysicalBone3D ragdoll;
	# a body whose pack ships a death animation uses that instead (enemy.gd:_die already prefers the
	# ragdoll and falls back to travel("Death")). Requiring both would fail a body for shipping the
	# better asset -- but a body with NEITHER has nothing to die with, and that is still a fail.
	if _enemy.get("_ragdoll") == null and not _has_state(&"Death"):
		fails.append("no ragdoll and no Death state — nothing to die with")
	# The head-track needs a bone literally named Head; a rig that names it otherwise cannot arm it.
	if _enemy.get("_look") == null:
		if _find_head_bone():
			fails.append("no LookAtModifier3D — the head-track never armed")
		else:
			notes.append("head-track: this rig has no bone named 'Head' — not armed")

	# --- ATTACK: the clip drives the window, the tween provably does not ------------------
	# IN REACH OF THIS BODY'S WEAPON, not a fixed 1.8 m. A swordsman connects at arm's length; a
	# four-metre ogre swinging a three-metre hammer lands it between 3.5 and 5 m and sweeps clean
	# over anything hugging its legs. One distance for both tests the swordsman and slanders the ogre.
	_place(_strike_distance())
	_enemy._cool = 0.0
	var frames := 3 * 60
	while int(_enemy.get("_state")) != Enemy.S.ATTACK and frames > 0:
		await get_tree().physics_frame
		frames -= 1
	if int(_enemy.get("_state")) != Enemy.S.ATTACK:
		fails.append("ATTACK: never attacked a player in its face")
	else:
		await _settle(3)
		# WHICHEVER SWING IT CHOSE. A body with one attack has the single state "Slash"; one that
		# brought several declares them in attack_states and picks among them, so the assertion is
		# "the tree is in an attack state", not "the tree is in that one state".
		if pb != null and not _attack_state_names().has(pb.get_current_node()):
			fails.append("ATTACK: FSM says ATTACK but the tree is in '%s'" % pb.get_current_node())
		if _enemy.get("_attack_tween") != null:
			fails.append("ATTACK: the old stopwatch tween is running — the clip must own the window")
		# Ride the swing: the hitbox must open in the clip's strike band and close again.
		var hb: HitBox = _enemy.get("_attack_hitbox")
		# AGAINST THE SWING THAT ACTUALLY PLAYED. _slash_len is the LONGEST attack this body has, so
		# on a multi-attack body a short swing's window reads as far too early against it -- atk_h
		# opens at 47% of its own 1.63 s and at 25% of skill's 3.03 s. Ask the state what it plays.
		var swing_state: StringName = pb.get_current_node() if pb != null else &"Slash"
		var slash_len: float = _state_clip_len(swing_state)
		if slash_len <= 0.0:
			slash_len = _enemy.get("_slash_len")
		var opened_at := -1.0
		var closed := false
		var tt := 0.0
		while tt < slash_len + 0.6:
			await get_tree().physics_frame
			tt += 1.0 / 60.0
			var live := bool(hb.get("_active"))
			if live and opened_at < 0.0:
				opened_at = tt
			if not live and opened_at >= 0.0:
				closed = true
			if int(_enemy.get("_state")) != Enemy.S.ATTACK and opened_at >= 0.0 and closed:
				break
		if opened_at < 0.0:
			fails.append("ATTACK: the method track never opened the hitbox")
		elif opened_at < slash_len * 0.25 or opened_at > slash_len * 0.70:
			fails.append("ATTACK: window opened at %.2f of a %.2f s clip — off the strike beat"
					% [opened_at, slash_len])
		else:
			notes.append("method track opened the window at %.2f / %.2f s" % [opened_at, slash_len])
		if not closed:
			fails.append("ATTACK: the window never closed")
		if _hits_on_player == 0:
			var hb3: HitBox = _enemy.get("_attack_hitbox")
			fails.append("ATTACK: a point-blank swing never landed (dist %.2f, box at %s, enemy %s, player %s, overlaps %d)"
					% [_player.global_position.distance_to(_enemy.global_position),
					str((hb3 as Area3D).global_position), str(_enemy.global_position),
					str(_player.global_position), (hb3 as Area3D).get_overlapping_areas().size()])
		# The END came back from the animation (signal or watchdog), not a stopwatch.
		frames = int((slash_len + 1.0) * 60.0)
		while int(_enemy.get("_state")) == Enemy.S.ATTACK and frames > 0:
			await get_tree().physics_frame
			frames -= 1
		if int(_enemy.get("_state")) == Enemy.S.ATTACK:
			fails.append("ATTACK: never returned to CHASE — the clip's ending was lost")
	_enemy._cool = 9.0
	_heal()
	await _settle(30)

	# --- Interrupt: keys not reached never fire -------------------------------------------
	_place(_strike_distance())
	_enemy._cool = 0.0
	frames = 3 * 60
	while int(_enemy.get("_state")) != Enemy.S.ATTACK and frames > 0:
		await get_tree().physics_frame
		frames -= 1
	if int(_enemy.get("_state")) == Enemy.S.ATTACK:
		var ehb := _enemy.get_node("HurtBox") as HurtBox
		# ENOUGH HITS TO BREAK THIS BODY, not two. Poise is per-enemy (a grunt has 2, an armoured
		# boss 12+), and a fixed pair only ever broke the swordsman.
		for _p in maxi(int(_enemy.get("max_poise")), 2):
			ehb.apply_hit(1, _player)
		await _settle(2)
		if int(_enemy.get("_state")) != Enemy.S.STAGGER and int(_enemy.get("_state")) != Enemy.S.DEAD:
			fails.append("INTERRUPT: poise break mid-windup did not stagger (state %d)"
					% int(_enemy.get("_state")))
		var hb2: HitBox = _enemy.get("_attack_hitbox")
		var leaked := false
		for i in int(float(_enemy.get("_slash_len")) * 60.0):
			await get_tree().physics_frame
			if bool(hb2.get("_active")):
				leaked = true
		if leaked:
			fails.append("INTERRUPT: the aborted swing's window still opened — a key fired past the exit")
		else:
			notes.append("interrupted swing: unreached method keys never fired")
	_enemy._cool = 9.0
	_heal()
	_heal_enemy()
	await _settle(60)

	# --- Flinch is a CLIP, and never the run cycle ----------------------------------------
	_place(4.0)
	await _settle(10)
	(_enemy.get_node("HurtBox") as HurtBox).apply_hit(1, _player)
	var reach_hurt := 15         # travel + a 0.05 xfade take a few frames to report the new node
	while reach_hurt > 0 and pb != null and pb.get_current_node() != &"Hurt":
		await get_tree().physics_frame
		reach_hurt -= 1
	if not bool(_enemy.get("flinches_on_hit")):
		notes.append("flinch: armoured body (flinches_on_hit off) — reaction clip not expected")
	elif pb != null and pb.get_current_node() != &"Hurt":
		fails.append("FLINCH: tree is in '%s', not Hurt" % pb.get_current_node())
	var ran := false
	for i in 20:
		await get_tree().physics_frame
		if pb != null and pb.get_current_node() == &"Move":
			ran = true
	if ran:
		fails.append("FLINCH: the knockback played the run cycle — the old moonwalk is back")
	else:
		notes.append("flinch played the Hurt clip, never the run")
	_heal_enemy()
	await _settle(60)

	# --- The finisher floors it; a step-0 swing does not ----------------------------------
	_place(1.5)
	_enemy._cool = 9.0
	var sword: Node = _player.get("sword")
	_face_enemy()
	sword.begin_swing(2, 0.3)              # the combo ender, through the REAL sword path
	sword.hit(0.2, false, 1)
	var before_fin := _hits_on_enemy
	var first_nodes := PackedStringArray()
	for i in 10:
		await get_tree().physics_frame
		if pb != null:
			first_nodes.append(String(pb.get_current_node()))
	if int(_enemy.get("_state")) != Enemy.S.STAGGER:
		fails.append("FINISHER: did not floor the swordsman (state %d, sword hits landed %d, first frames %s)"
				% [int(_enemy.get("_state")), _hits_on_enemy - before_fin, str(first_nodes)])
	notes.append("finisher first frames: %s" % str(first_nodes))
	var saw_knock := false
	var saw_getup := false
	var seen := {}
	for i in int((float(_enemy.get("_knock_len")) + float(_enemy.get("_getup_len")) + 1.0) * 60.0):
		await get_tree().physics_frame
		if pb == null:
			break
		var cur := pb.get_current_node()
		seen[String(cur)] = true
		if cur == &"Knockdown":
			saw_knock = true
		elif cur == &"Getup":
			saw_getup = true
		elif saw_getup and (cur == &"Idle" or cur == &"Move"):
			break
	if not saw_knock or not saw_getup:
		fails.append("FINISHER: knockdown/getup incomplete (down %s, up %s; saw %s; knock_len %.2f getup_len %.2f)"
				% [saw_knock, saw_getup, str(seen.keys()),
				float(_enemy.get("_knock_len")), float(_enemy.get("_getup_len"))])
	else:
		# The tree's AT_END fades overlap ~0.35 s, so it lands on Idle a shade before the FSM's
		# summed-clip timer expires — give the slower clock its own tail before judging it.
		await _settle(45)
		if int(_enemy.get("_state")) == Enemy.S.STAGGER:
			fails.append("FINISHER: it got up but the FSM never did")
		else:
			notes.append("finisher: floored, got up, resumed — tree and FSM in step")
	await _settle(30)
	sword.begin_swing(0, 0.3)              # meta hygiene: an opener must NOT knock down
	sword.hit(0.2, false, 1)
	await _settle(5)
	if pb != null and pb.get_current_node() == &"Knockdown":
		fails.append("FINISHER: a step-0 swing floored it — the meta leaked")
	_heal()
	_heal_enemy()
	await _settle(60)

	# --- Lock-on, standard camera side ----------------------------------------------------
	var rig := $CameraRig as CameraRig
	rig.toggle_lock()
	if rig.locked() != _enemy:
		fails.append("LOCK: did not acquire the swordsman (got %s, dist %.1f, alive %s)"
				% [str(rig.locked()), _player.global_position.distance_to(_enemy.global_position),
				str((_enemy.get_node("Health") as Health).is_alive())])
	if rig.locked() != null:
		rig.toggle_lock()

	# --- Head-track: the engine modifier is doing real work -------------------------------
	var skel := _enemy.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var head_i: int = skel.find_bone("Head") if skel else -1
	if head_i >= 0:
		_enemy._cool = 9.0             # a mid-measurement swing damps influence to 0.4
		_place(6.0)
		await _settle(50)                  # influence eases in during CHASE
		var cc: Vector3 = _enemy.global_position
		_player.global_position = Vector3(cc.x - 6.0, 1.1, cc.z)
		await _settle(45)
		var fwd_l: Vector3 = (skel.global_transform * skel.get_bone_global_pose(head_i)).basis.z
		_player.global_position = Vector3(cc.x + 6.0, 1.1, cc.z)
		await _settle(45)
		var fwd_r: Vector3 = (skel.global_transform * skel.get_bone_global_pose(head_i)).basis.z
		var swung := rad_to_deg(Vector2(fwd_l.x, fwd_l.z).angle_to(Vector2(fwd_r.x, fwd_r.z)))
		if absf(swung) < 8.0:
			fails.append("HEAD: player crossed the room and the head moved %.1f deg" % absf(swung))
		else:
			notes.append("head tracked the player across %.0f deg" % absf(swung))

	# --- Death: the engine's own ragdoll --------------------------------------------------
	var expect_dir := _enemy.global_position - _player.global_position
	expect_dir.y = 0.0
	expect_dir = expect_dir.normalized()
	(_enemy.get_node("HurtBox") as HurtBox).apply_hit(99, _player)
	var kmin := Engine.time_scale
	for i in 12:
		await get_tree().physics_frame
		kmin = minf(kmin, Engine.time_scale)
	if kmin > 0.2:
		fails.append("KILL: the killing blow missed the deep freeze (%.2f)" % kmin)
	if int(_enemy.get("_state")) != Enemy.S.DEAD:
		fails.append("KILL: not dead after 99 damage")
	var rag: PhysicalBoneSimulator3D = _enemy.get("_ragdoll")
	if rag == null:
		if _has_state(&"Death"):
			notes.append("death: played the authored Death clip (no ragdoll on this body)")
		else:
			fails.append("KILL: neither a ragdoll nor a Death clip")
	else:
		var hips: PhysicalBone3D = null
		for c in rag.get_children():
			if c is PhysicalBone3D and String((c as PhysicalBone3D).bone_name) == "Hips":
				hips = c
		if hips == null:
			fails.append("KILL: no Hips physical bone")
		else:
			var p0 := hips.global_position
			var sane := true
			for i in 60:
				await get_tree().physics_frame
				if not is_instance_valid(hips):
					break
				var y := hips.global_position.y
				if is_nan(y) or y < -0.5 or y > 3.5:
					sane = false
			if not sane:
				fails.append("KILL: ragdoll exploded (hips left the sane band)")
			elif is_instance_valid(hips) and hips.global_position.distance_to(p0) < 0.05:
				fails.append("KILL: ragdoll never moved — simulation did not start")
			elif is_instance_valid(hips):
				# F = ma: the corpse must be THROWN along the killing blow, not dropped in
				# place — the seeded momentum is the assertion, not a garnish.
				var disp := hips.global_position - p0
				disp.y = 0.0
				var along := disp.dot(expect_dir)
				if along < 0.3:
					fails.append("KILL: corpse moved %.2f m along the blow — dropped, not thrown" % along)
				else:
					notes.append("corpse thrown %.2f m along the killing blow" % along)
	var free_frames := 5 * 60
	while is_instance_valid(_enemy) and free_frames > 0:
		await get_tree().physics_frame
		free_frames -= 1
	if is_instance_valid(_enemy):
		fails.append("KILL: the corpse never freed")

	for f in fails:
		print("[PROBE] FAIL  " + f)
	for msg in notes:
		print("[PROBE] note  " + msg)
	print("[PROBE] %s — %d checks failed" % ["RED" if fails.size() else "GREEN", fails.size()])
	get_tree().quit(1 if fails.size() else 0)


## Point the player's Visuals at the enemy so the sword's frontal geometry is honest.
func _face_enemy() -> void:
	var vis := _player.get_node("Visuals") as Node3D
	var to := _enemy.global_position - _player.global_position
	vis.rotation.y = atan2(-to.x, -to.z)


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOTS] " + path)


func _demo_shots(out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	var pb: AnimationNodeStateMachinePlayback = _enemy.get("_anim_pb")
	_enemy._cool = 9.0
	var dbg := get_node_or_null("/root/Dbg")
	if dbg != null:
		dbg.show_hitboxes = true           # the window must be VISIBLE opening from the clip

	# 1) Orbit: the sword riding the hand, the model, the shadow.
	_place(28.0)
	await _settle(40)
	for k in 4:
		var ang := TAU * float(k) / 4.0
		var c := _enemy.global_position + Vector3(0, 1.4, 0)
		cam.global_position = c + Vector3(sin(ang) * 4.5, 0.5, cos(ang) * 4.5)
		cam.look_at(c)
		await _snap(out_dir + "/orbit_%03d.png" % int(round(rad_to_deg(ang))))

	# 2) The swing: wind-up, then THE frame the method track opens the box (bright red).
	_place(1.8)
	await _settle(5)
	_side_cam(cam)
	_enemy._cool = 0.0
	var frames := 180
	while int(_enemy.get("_state")) != Enemy.S.ATTACK and frames > 0:
		await get_tree().physics_frame
		frames -= 1
	await _settle(8)
	await _snap(out_dir + "/slash_windup.png")
	var hb: HitBox = _enemy.get("_attack_hitbox")
	frames = 120
	while not bool(hb.get("_active")) and frames > 0:
		await get_tree().physics_frame
		frames -= 1
	await _snap(out_dir + "/slash_strike.png")
	_enemy._cool = 9.0
	_heal()
	await _settle(60)

	# 3) The move blend mid-chase.
	_place(9.0)
	await _settle(25)
	_side_cam(cam)
	await _snap(out_dir + "/move_blend.png")

	# 4) Hurt reaction.
	_place(4.0)
	await _settle(15)
	_face_cam(cam)
	(_enemy.get_node("HurtBox") as HurtBox).apply_hit(1, _player)
	await _settle(8)
	await _snap(out_dir + "/hurt_react.png")
	await _settle(60)

	# 5) The finisher: floored, then rising.
	_place(1.5)
	_face_enemy()
	var sword: Node = _player.get("sword")
	sword.begin_swing(2, 0.3)
	sword.hit(0.2, false, 1)
	await _settle(20)
	_face_cam(cam)
	await _snap(out_dir + "/knockdown_floor.png")
	frames = 600
	while frames > 0 and pb != null and pb.get_current_node() != &"Getup":
		await get_tree().physics_frame
		frames -= 1
	await _settle(12)
	await _snap(out_dir + "/getup_rise.png")
	_heal()
	await _settle(90)

	# 6) Head-track: close on the face, player off to one side.
	_place(6.0)
	await _settle(40)
	var cc: Vector3 = _enemy.global_position
	_player.global_position = Vector3(cc.x - 5.0, 1.1, cc.z + 2.0)
	await _settle(45)
	var head := _enemy.global_position + Vector3(0, 2.0, 0)
	cam.global_position = head + Vector3(0.6, 0.25, 2.6)
	cam.look_at(head)
	await _snap(out_dir + "/headtrack.png")

	# 7) Death: the ragdoll falling, then at rest.
	_face_cam(cam)
	(_enemy.get_node("HurtBox") as HurtBox).apply_hit(99, _player)
	await _settle(14)
	await _snap(out_dir + "/ragdoll_fall.png")
	await _settle(75)
	# The corpse slides where the impulse took it — frame the shot on the HIPS BONE, not on
	# where the enemy stood, or the constraint check photographs an empty patch of floor.
	var rag: PhysicalBoneSimulator3D = _enemy.get("_ragdoll") if is_instance_valid(_enemy) else null
	if rag != null and is_instance_valid(rag):
		for c in rag.get_children():
			if c is PhysicalBone3D and String((c as PhysicalBone3D).bone_name) == "Hips":
				var at := (c as Node3D).global_position
				cam.global_position = at + Vector3(1.8, 2.6, 1.8)
				cam.look_at(at)
	await _snap(out_dir + "/ragdoll_rest.png")
	print("[SHOTS] done -> " + out_dir)
	get_tree().quit(0)


func _side_cam(cam: Camera3D) -> void:
	var a := _enemy.global_position
	var b := _player.global_position
	var mid := (a + b) * 0.5 + Vector3(0, 1.2, 0)
	var line := b - a
	line.y = 0.0
	var side := line.cross(Vector3.UP).normalized()
	cam.global_position = mid + side * (line.length() * 0.9 + 3.5) + Vector3(0, 1.6, 0)
	cam.look_at(mid)


func _face_cam(cam: Camera3D) -> void:
	var c := _enemy.global_position + Vector3(0, 1.2, 0)
	var to_p := _player.global_position - _enemy.global_position
	to_p.y = 0.0
	cam.global_position = c + to_p.normalized() * 4.0 + Vector3(0, 0.8, 0)
	cam.look_at(c)

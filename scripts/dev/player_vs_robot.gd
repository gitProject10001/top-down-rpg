extends Node3D
## PLAYER VERSUS ROBOT — the generic-system proof, in scene form.
##
## The ogre took a solver, six modifier layers and a clip library to move. This fight exists to
## show the OTHER half of the refactor's claim: a brand-new enemy costs no systems at all. The
## robot is enemy.gd's data-driven RANGED path with a model and export values — no OgreSolver, no
## clips, no subclass. It answers each of its range bands with a different shot (the band exports
## in enemy.gd): NEAR = kite + fan burst, HOLD = stand + aimed ballistic, FAR = advance + high
## lob. The rings on the floor ARE those bands — the ogre's M1/M2/M3 idea, ranged.
##
## KEYS: WASD move · LMB attack · Space dash · RMB block · R restart · F1 readout · F3 hitboxes
##
## THE PROOF GATE (run as a SCENE, never --script — projectiles reference EventBus):
##   godot --resolution 900x760 res://scenes/dev/player_vs_robot.tscn --log-file r.log -- --demo=probe
## Visual evidence (crown spawn, fan, lob, flash — the eyes' half of the check):
##   ... -- --demo=shots --out=<dir>

@onready var _player: Node3D = $Player
@onready var _robot: Enemy = $Robot
@onready var _readout: Label = $UI/Readout

var _hits_on_robot := 0
var _hits_on_player := 0
var _t := 0.0
var _rings: Node3D


func _ready() -> void:
	(_robot.get_node("Health") as Health).damaged.connect(func(_a, _s): _hits_on_robot += 1)
	var ph := _player.get_node_or_null("Health")
	if ph:
		ph.damaged.connect(func(_a, _s): _hits_on_player += 1)
	_rings = _make_rings()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			_demo(a.substr(7).rstrip("/\\"))


## The bands, drawn where they actually are — read from the robot's own exports, so a retuned
## preferred_range moves the rings with it and the floor cannot lie. Colours follow the ogre's
## ring convention: yellow closest, orange, blue farthest.
func _make_rings() -> Node3D:
	var root := Node3D.new()
	root.name = "BandRings"
	add_child(root)
	var bands: Array = [
		[_robot.preferred_range * 0.7, Color(0.95, 0.85, 0.25)],
		[_robot.preferred_range, Color(1.0, 0.55, 0.15)],
		[_robot.aggro_range, Color(0.35, 0.55, 1.0)],
	]
	for b: Array in bands:
		var mesh := TorusMesh.new()
		mesh.inner_radius = float(b[0]) - 0.06
		mesh.outer_radius = float(b[0]) + 0.06
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(b[1].r, b[1].g, b[1].b, 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.scale = Vector3(1, 0.02, 1)      # a torus squashed flat = a floor ring
		root.add_child(mi)
	return root


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.is_pressed() or e.is_echo():
		return
	match (e as InputEventKey).keycode:
		KEY_R:
			# Reload rather than reposition — same reasoning as player_vs_ogre.gd.
			get_tree().reload_current_scene()
		KEY_F1:
			($UI as CanvasLayer).visible = not ($UI as CanvasLayer).visible


func _band_name(dist: float) -> String:
	if dist < _robot.preferred_range * 0.7:
		return "NEAR — it kites and fans"
	if dist <= _robot.preferred_range:
		return "HOLD — it stands and aims"
	if dist <= _robot.aggro_range:
		return "FAR — it advances, lobs high"
	return "OUT — it has not seen you"


func _process(delta: float) -> void:
	var dbg := get_node_or_null("/root/Dbg")
	if dbg != null and bool(dbg.clean):
		($UI as CanvasLayer).visible = false
	_t += delta
	if not is_instance_valid(_robot):
		if _rings != null:
			_rings.visible = false
		_readout.text = "robot down after %.1f s — R to restart" % _t
		return
	if _rings != null:
		_rings.global_position = Vector3(_robot.global_position.x, 0.05, _robot.global_position.z)
	var dist := 0.0
	if is_instance_valid(_player):
		dist = _player.global_position.distance_to(_robot.global_position)
	var hp := _robot.get_node("Health") as Health
	var lines := PackedStringArray()
	lines.append("distance %5.2f m" % dist)
	lines.append("band     %s" % _band_name(dist))
	lines.append("robot    hp %d/%d      next shot %.1f s" % [hp.hp, hp.max_hp, _robot._cool])
	lines.append("")
	lines.append("hits on robot %d      hits on you %d      %.0f s"
			% [_hits_on_robot, _hits_on_player, _t])
	lines.append("orange = parry it back · purple = dodge it · ground wave = JUMP")
	lines.append("WASD move · LMB attack · Space jump · Shift dash · RMB guard/parry · MMB/R3 lock · R restart")
	_readout.text = "\n".join(lines)


# ---------------------------------------------------------------------------------------------
# Headless proof. The probe asserts what the eyes then confirm in --demo=shots: the right shot
# leaves the right place in the right band, and the shared damage plumbing carries it both ways.

var _shots: Array[Node3D] = []       # projectiles seen since the last clear
var _spawn_ys: Array[float] = []     # their global y at spawn — the crown-vs-chest witness
var _spawn_pos: Array[Vector3] = []  # full spawn position — the off-the-line launch witness
var _vels: Array[Vector3] = []       # their launch velocity — flat vs aimed vs lob witness
var _markers := 0                    # impact rings seen since the last clear
var _waves := 0                      # ground waves seen since the last clear


func _demo(kind: String) -> void:
	match kind:
		"probe":
			_demo_probe()
		"shots":
			var out := "user://robot_shots"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--out="):
					out = a.split("=", true, 1)[1]
			_demo_shots(out)


func _on_node_added(nd: Node) -> void:
	if nd is Projectile:
		# Deferred: add_child fires this BEFORE _fire_projectile sets position and velocity.
		_record_shot.call_deferred(nd)
	elif nd is ImpactMarker:
		_markers += 1
	elif nd is GroundWave:
		_waves += 1


func _record_shot(p: Node3D) -> void:
	if not is_instance_valid(p):
		return
	_shots.append(p)
	_spawn_ys.append(p.global_position.y)
	_spawn_pos.append(p.global_position)
	_vels.append(p.get("_vel"))


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## Teleport the player to `dist` metres due +Z of the robot, standing still.
func _place(dist: float) -> void:
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	var pos := _robot.global_position
	_player.global_position = Vector3(pos.x, 1.1, pos.z + dist)


## Average of dot(robot velocity, direction to player) over moving frames:
## +1 = running at the player, -1 = backing away, 0.0 = it never moved.
func _avg_closing(frames: int) -> float:
	var acc := 0.0
	var n := 0
	for i in frames:
		await get_tree().physics_frame
		if not is_instance_valid(_robot) or not is_instance_valid(_player):
			break
		var to_p := _player.global_position - _robot.global_position
		to_p.y = 0.0
		var v := _robot.velocity
		v.y = 0.0
		if v.length() > 0.2 and to_p.length() > 0.01:
			acc += v.normalized().dot(to_p.normalized())
			n += 1
	return acc / maxf(n, 1.0)


## Wait for the next volley: first projectile (up to `timeout`), then room for its siblings —
## a burst spawns in one frame, and the recorder runs deferred.
func _await_volley(timeout: float) -> int:
	var frames := int(timeout * 60.0)
	while _shots.is_empty() and frames > 0:
		await get_tree().physics_frame
		frames -= 1
	if _shots.is_empty():
		return 0
	await _settle(20)
	return _shots.size()


func _hv(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## The probe deals real damage to the player on purpose (bolts land, waves pass) — heal between
## blocks so no test inherits another's hp, and no sequence of passes adds up to a probe death.
func _heal() -> void:
	(_player.get_node("Health") as Health).revive()


func _demo_probe() -> void:
	get_tree().node_added.connect(_on_node_added)
	var fails: Array[String] = []
	var notes: Array[String] = []
	_robot._cool = 9.0                       # nothing fires until a test asks for it
	await _settle(20)

	# --- The scene contract the generic path depends on -----------------------------------
	if _robot._muzzle == null:
		fails.append("no Muzzle found — bolts would leave the legacy chest offset")
	if (_robot._flash_mats as Array).is_empty():
		fails.append("no flash materials — the imported model yielded no BaseMaterial3D")
	if _robot._solver != null:
		fails.append("a solver found its way into the robot — this scene must prove the data path")
	if _robot.pierce_every <= 0 or _robot.impact_wave_scene == null or _robot.homing_deg <= 0.0:
		fails.append("the wilder dials are off — pierce/wave/homing must be armed on this robot")
	if _player.get("_toon") == null:
		fails.append("the hero has no ToonSkin wired — the red hurt-flash has no channel")

	# --- Feet: each band moves the right way ----------------------------------------------
	_place(4.0)
	await _settle(10)
	var closing := await _avg_closing(40)
	if closing > -0.5:
		fails.append("NEAR: not kiting (closing %.2f, want < -0.5)" % closing)
	_place(7.0)
	await _settle(10)
	closing = await _avg_closing(40)
	if absf(closing) > 0.3:
		fails.append("HOLD: not holding (closing %.2f, want ~0)" % closing)
	_place(13.0)
	await _settle(10)
	closing = await _avg_closing(40)
	if closing < 0.5:
		fails.append("FAR: not advancing (closing %.2f, want > 0.5)" % closing)

	# --- Trigger: each band fires the right shot from the right place ---------------------
	# HOLD: one aimed ballistic from the crown, one impact ring, full horizontal speed.
	_place(7.0)
	await _settle(10)
	_shots.clear(); _spawn_ys.clear(); _spawn_pos.clear(); _vels.clear(); _markers = 0
	_robot._cool = 0.0
	var n := await _await_volley(4.0)
	if n != 1:
		fails.append("HOLD: expected 1 aimed shot at 7 m, got %d" % n)
	if _markers != 1:
		fails.append("HOLD: expected 1 impact ring, got %d" % _markers)
	if n >= 1:
		if _spawn_ys[0] < 2.0:
			fails.append("HOLD: bolt spawned at y=%.2f — chest offset, not the crown" % _spawn_ys[0])
		else:
			notes.append("bolt left the crown at y=%.2f" % _spawn_ys[0])
		if _hv(_vels[0]) < 10.0:
			fails.append("HOLD: aimed shot flies at %.1f m/s horizontal — that is the lob" % _hv(_vels[0]))
		if is_instance_valid(_shots[0]) and _shots[0].get("parriable") != true:
			fails.append("HOLD: the orange aimed shot must be parriable — the colour contract")
	_robot._cool = 9.0
	await _settle(90)
	_heal()

	# NEAR: the fan — burst_count straight bolts, spread wide, and NO impact rings.
	_place(4.0)
	await _settle(10)
	_shots.clear(); _spawn_ys.clear(); _spawn_pos.clear(); _vels.clear(); _markers = 0
	_robot._cool = 0.0
	n = await _await_volley(4.0)
	if n != _robot.burst_count:
		fails.append("NEAR: expected a %d-bolt fan, got %d" % [_robot.burst_count, n])
	if _markers != 0:
		fails.append("NEAR: the fan drew %d impact rings — straight bolts do not land" % _markers)
	if n >= 2:
		var a0 := Vector2(_vels[0].x, _vels[0].z).angle()
		var a1 := Vector2(_vels[n - 1].x, _vels[n - 1].z).angle()
		var spread := absf(wrapf(a1 - a0, -PI, PI))
		if spread < deg_to_rad(30.0):
			fails.append("NEAR: fan spread only %.0f deg" % rad_to_deg(spread))
		else:
			notes.append("fan spread %.0f deg across %d bolts" % [rad_to_deg(spread), n])
		if is_instance_valid(_shots[0]) and float(_shots[0].get("_home_deg")) <= 0.0:
			fails.append("NEAR: fan bolts carry no homing — they should close on a strafer")
	_robot._cool = 9.0
	await _settle(90)
	_heal()

	# FAR: the lob — same ballistic, now TOWERING (0.45x horizontal), still ringed. And the
	# second half of its threat: step off the ring and the crater raises a ground wave that
	# comes after you anyway.
	_place(13.0)
	await _settle(10)
	_shots.clear(); _spawn_ys.clear(); _spawn_pos.clear(); _vels.clear(); _markers = 0; _waves = 0
	_robot._cool = 0.0
	n = await _await_volley(4.0)
	_robot._cool = 9.0
	if n != 1:
		fails.append("FAR: expected 1 lobbed shot at 13 m, got %d" % n)
	if _markers != 1:
		fails.append("FAR: expected 1 impact ring, got %d" % _markers)
	if n >= 1:
		if _hv(_vels[0]) > 6.5:
			fails.append("FAR: lob flies at %.1f m/s horizontal — not the towering arc" % _hv(_vels[0]))
		else:
			notes.append("lob at %.1f m/s horizontal vs %.1f flat" % [_hv(_vels[0]), 12.0])
		if is_instance_valid(_shots[0]) and float(_shots[0].get("_home_deg")) > 0.0:
			fails.append("FAR: the lob is homing — a bent arc makes its impact ring a lie")
		# Dodge it: the lob lands where we WERE, and the crater's wave crosses the 4 m to us.
		(_player as CharacterBody3D).velocity = Vector3.ZERO
		_player.global_position += Vector3(4.0, 0, 0)
		var hit_far := _hits_on_player
		var fr := 5 * 60
		while _waves == 0 and fr > 0:
			await get_tree().physics_frame
			fr -= 1
		if _waves == 0:
			fails.append("FAR: the dodged lob never raised a ground wave at its crater")
		else:
			fr = 2 * 60
			while _hits_on_player == hit_far and fr > 0:
				await get_tree().physics_frame
				fr -= 1
			if _hits_on_player == hit_far:
				fails.append("FAR: the crater wave passed a grounded player 4 m out without hitting")
			else:
				notes.append("dodged lob -> crater wave -> grounded hit at 4 m")
	await _settle(60)
	_heal()

	# THE PURPLE ONE: every pierce_every-th pull, unparriable, launched wide and homing back in.
	_place(7.0)
	await _settle(10)
	_shots.clear(); _spawn_ys.clear(); _spawn_pos.clear(); _vels.clear(); _markers = 0
	_robot._volleys = _robot.pierce_every - 1
	_robot._cool = 0.0
	n = await _await_volley(4.0)
	_robot._cool = 9.0
	if n != 1:
		fails.append("PIERCE: expected the single purple bolt, got %d" % n)
	if _markers != 0:
		fails.append("PIERCE: it drew an impact ring — straight homers do not land")
	if n >= 1 and is_instance_valid(_shots[0]):
		if _shots[0].get("parriable") != false:
			fails.append("PIERCE: the purple bolt must be unparriable — the colour contract")
		var chest: Vector3 = _player.global_position + Vector3(0, 0.6, 0)
		var off_line := rad_to_deg(_vels[0].angle_to(chest - _spawn_pos[0]))
		if off_line < 25.0:
			fails.append("PIERCE: launched only %.0f deg off the line — the wide swing IS the tell" % off_line)
		# The honest convergence test is the OUTCOME, not a mid-swing bearing: a bolt launched
		# wide swings through a worse angle before a better one (its turning circle is real).
		# Against a stationary player the swing must end on them within the homing window.
		var hitp := _hits_on_player
		var hf := 100
		while hf > 0 and is_instance_valid(_shots[0]) and not bool(_shots[0].get("_stuck")) \
				and _hits_on_player == hitp:
			await get_tree().physics_frame
			hf -= 1
		if _hits_on_player > hitp or not is_instance_valid(_shots[0]) \
				or bool(_shots[0].get("_stuck")):
			notes.append("purple launched %.0f deg wide and swung home" % off_line)
		else:
			fails.append("PIERCE: launched %.0f deg wide and never came back — homing not biting" % off_line)
	await _settle(60)
	_heal()

	# --- The surface attack obeys the jump rule -------------------------------------------
	_place(7.0)
	await _settle(10)
	var hit0 := _hits_on_player
	var wave := (load("res://scenes/fx/ground_wave.tscn") as PackedScene).instantiate() as Node3D
	add_child(wave)
	wave.global_position = Vector3(_player.global_position.x + 2.5, 0.03, _player.global_position.z)
	var wf := 90
	while _hits_on_player == hit0 and wf > 0:
		await get_tree().physics_frame
		wf -= 1
	if _hits_on_player == hit0:
		fails.append("WAVE: a grounded player was never hit by the passing front")
	else:
		# ...and exactly once: ride out the wave's whole remaining life. A front that hits the
		# same body twice has lost its "passes you once" identity, knockback or not.
		await _settle(85)
		if _hits_on_player > hit0 + 1:
			fails.append("WAVE: the front hit the same player twice (%d hits)" % (_hits_on_player - hit0))
	await _settle(40)
	_heal()
	_place(7.0)
	_player.global_position.y += 2.5             # airborne: falling counts, exactly like a jump
	await _settle(2)
	hit0 = _hits_on_player
	var wave2 := (load("res://scenes/fx/ground_wave.tscn") as PackedScene).instantiate() as Node3D
	add_child(wave2)
	wave2.global_position = Vector3(_player.global_position.x + 2.5, 0.03, _player.global_position.z)
	await _settle(45)
	if _hits_on_player != hit0:
		fails.append("WAVE: an AIRBORNE player was hit — the jump rule is broken")
	else:
		notes.append("wave: grounded hit, airborne spared")
	await _settle(40)
	_heal()

	# --- The colour contract, both halves, through the real guard -------------------------
	_place(7.0)
	await _settle(10)
	var vis := _player.get_node("Visuals") as Node3D
	var fwd: Vector3 = -vis.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var fsm: Node = _player.get("_fsm")
	_raise_guard(fsm)                            # the window opens NOW; no await before the hit
	var orange := (load("res://scenes/fx/bolt.tscn") as PackedScene).instantiate() as Projectile
	add_child(orange)
	orange.global_position = _player.global_position + fwd * 1.5 + Vector3(0, 1.0, 0)
	orange.shooter = _robot
	orange.setup(-fwd, 2, 1, Color(1.0, 0.5, 0.2))
	var hb_before := _hits_on_robot
	var got_through: int = _player.on_incoming_hit(1, orange)
	if got_through != 0:
		fails.append("PARRY: a frontal orange bolt beat the open window (returned %d)" % got_through)
	if orange.collision_mask != 4:
		fails.append("PARRY: the bolt was not deflected (mask %d)" % orange.collision_mask)
	else:
		var em := ((orange.get_node("Model") as MeshInstance3D).get_active_material(0)
				as BaseMaterial3D).emission
		if em.b <= em.r:
			fails.append("PARRY: the sent-back bolt still wears a warm tint — the colour must flip")
		var pf := 3 * 60
		while _hits_on_robot == hb_before and pf > 0:
			await get_tree().physics_frame
			pf -= 1
		if _hits_on_robot == hb_before:
			fails.append("PARRY: the deflected bolt never found its way home to the robot")
		else:
			notes.append("orange parried back: the robot ate its own bolt")
	fsm.transition_to("Idle")
	_raise_guard(fsm)                            # a fresh window — which purple must not care about
	var purple := (load("res://scenes/fx/bolt.tscn") as PackedScene).instantiate() as Projectile
	add_child(purple)
	purple.global_position = _player.global_position + fwd * 1.5 + Vector3(0, 1.0, 0)
	purple.shooter = _robot
	purple.parriable = false
	purple.setup(-fwd, 2, 1, Enemy.PIERCE_COLOR)
	got_through = _player.on_incoming_hit(1, purple)
	if got_through != 1:
		fails.append("CONTRACT: a purple bolt was answered by the guard (returned %d)" % got_through)
	else:
		notes.append("purple ignored the guard, as the colour promises")
	purple.queue_free()
	fsm.transition_to("Idle")
	await _settle(20)
	_heal()

	# --- LOCK-ON: the camera fights the enemy, not the player ------------------------------
	var rig := $CameraRig as CameraRig
	_robot._cool = 9.0
	_place(7.0)
	await _settle(10)
	# Acquire through the REAL binding, not the method — a broken lock_on action with a working
	# toggle_lock() is exactly the regression a method-only probe would bless.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	Input.parse_input_event(release)
	await _settle(3)
	if rig.locked() != _robot:
		fails.append("LOCK: the MMB binding did not acquire the robot")
	else:
		await _settle(80)
		var dl: Vector3 = _robot.global_position - _player.global_position
		var want := atan2(-dl.x, -dl.z)
		var yaw_err := absf(wrapf(rig.rotation.y - want, -PI, PI))
		if yaw_err > 0.15:
			fails.append("LOCK: camera settled %.2f rad off the fight line" % yaw_err)
		# THE feature: step a quarter-circle around the robot with NO stick input — the camera
		# must come around on its own, or circling still means fighting it.
		var rr := _player.global_position.distance_to(_robot.global_position)
		var cc: Vector3 = _robot.global_position
		(_player as CharacterBody3D).velocity = Vector3.ZERO
		_player.global_position = Vector3(cc.x + rr, 1.1, cc.z)
		await _settle(80)
		dl = _robot.global_position - _player.global_position
		want = atan2(-dl.x, -dl.z)
		yaw_err = absf(wrapf(rig.rotation.y - want, -PI, PI))
		if yaw_err > 0.2:
			fails.append("LOCK: circled 90 deg and the camera lagged %.2f rad behind" % yaw_err)
		else:
			notes.append("lock: circled 90 deg, camera stayed on the fight (%.2f rad off)" % yaw_err)
		# WALKED circle, not teleported: hold pure strafe for 2 s. Movement maps through the
		# lock bearing, so the radius must HOLD — through the camera's lagged yaw instead, a
		# held strafe provably spirals outward at ~v^2/(3r). This is that fix's tripwire.
		var r0 := _player.global_position.distance_to(_robot.global_position)
		Input.action_press("move_left")
		await _settle(120)
		Input.action_release("move_left")
		await _settle(10)
		var r1 := _player.global_position.distance_to(_robot.global_position)
		if absf(r1 - r0) > 1.5:
			fails.append("LOCK: a held strafe spiralled from %.1f m to %.1f m radius" % [r0, r1])
		else:
			notes.append("lock: held strafe circled, radius %.1f m -> %.1f m" % [r0, r1])
	if rig.locked() == _robot:
		rig.toggle_lock()
		if rig.locked() != null:
			fails.append("LOCK: second press did not release")
	rig.toggle_lock()          # re-armed: the death below must break it with no press at all

	# --- Damage, both directions, through the shared plumbing -----------------------------
	# A ballistic aimed at a stationary player must actually land on them.
	_place(7.0)
	await _settle(10)
	var hits_before := _hits_on_player
	_robot._cool = 0.0
	var frames := 8 * 60
	while _hits_on_player == hits_before and frames > 0:
		await get_tree().physics_frame
		frames -= 1
	_robot._cool = 9.0
	if _hits_on_player == hits_before:
		fails.append("a ballistic aimed at a stationary player never landed")
	else:
		# THE STING: the hit that just landed must have frozen time (contact_taken) — sample
		# across the freeze's real-time span, then confirm the clock comes all the way back.
		var min_ts := Engine.time_scale
		for i in 12:
			await get_tree().physics_frame
			min_ts = minf(min_ts, Engine.time_scale)
		if min_ts > 0.95:
			fails.append("HURT: the player was hit and time never flinched (min %.2f)" % min_ts)
		else:
			await _settle(30)
			if Engine.time_scale < 0.99:
				fails.append("HURT: time_scale stuck at %.2f after the freeze" % Engine.time_scale)
			else:
				notes.append("hurt freeze fired (min time_scale %.2f) and released" % min_ts)

	# MERCY: two blows in the same instant cost ONE heart — the second lands inside the post-hit
	# window. Healed first (revive clears any window a previous block left running).
	_heal()
	await _settle(40)
	var phb := _player.get_node("HurtBox") as HurtBox
	var first := phb.apply_hit(1, _robot)
	var second := phb.apply_hit(1, _robot)
	if first != 1 or second != 0:
		fails.append("MERCY: simultaneous hits applied %d then %d — want 1 then 0" % [first, second])
	else:
		notes.append("mercy window: the second simultaneous hit applied 0")
	await _settle(50)
	_heal()

	# And the robot must take hits and die through the same HurtBox path as everyone else.
	var applied := (_robot.get_node("HurtBox") as HurtBox).apply_hit(1, _player)
	if applied != 1:
		fails.append("robot HurtBox swallowed a hit (applied %d)" % applied)
	await _settle(5)
	if _hits_on_robot < 1:
		fails.append("robot Health never reported the hit")
	(_robot.get_node("HurtBox") as HurtBox).apply_hit(99, _player)
	# KILL PUNCTUATION: the lethal hit must reach the deep freeze (kill_landed, 0.05 scale) —
	# a kill that feels like a chip is the exact blandness this pass exists to kill.
	var kmin := Engine.time_scale
	for i in 12:
		await get_tree().physics_frame
		kmin = minf(kmin, Engine.time_scale)
	if kmin > 0.2:
		fails.append("KILL: the killing blow never hit the deep freeze (min time_scale %.2f)" % kmin)
	else:
		notes.append("kill freeze fired (min time_scale %.2f)" % kmin)
	await _settle(10)
	if is_instance_valid(_robot) and _robot._state != Enemy.S.DEAD:
		fails.append("robot survived 99 damage in state %d" % _robot._state)
	if ($CameraRig as CameraRig).locked() != null:
		fails.append("LOCK: the robot died and the camera stayed locked to the corpse")
	else:
		notes.append("lock released itself on the robot's death")

	for f in fails:
		print("[PROBE] FAIL  " + f)
	for msg in notes:
		print("[PROBE] note  " + msg)
	print("[PROBE] %s — %d checks failed" % ["RED" if fails.size() else "GREEN", fails.size()])
	get_tree().quit(1 if fails.size() else 0)


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOTS] " + path)


## A camera square to the robot→player line, framing both — where an arc's height can be seen.
func _side_cam(cam: Camera3D, height: float) -> void:
	var a := _robot.global_position
	var b := _player.global_position
	var mid := (a + b) * 0.5 + Vector3(0, 1.2, 0)
	var line := b - a
	line.y = 0.0
	var side := line.cross(Vector3.UP).normalized()
	cam.global_position = mid + side * (line.length() * 0.9 + 4.0) + Vector3(0, height, 0)
	cam.look_at(mid)


func _demo_shots(out_dir: String) -> void:
	get_tree().node_added.connect(_on_node_added)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	_robot._cool = 9.0

	# 1) The robot itself, 4 angles — facing, hover, crown, shadow. Player parked out of aggro.
	_place(28.0)
	await _settle(40)
	for k in 4:
		var ang := TAU * float(k) / 4.0
		var c := _robot.global_position + Vector3(0, 1.4, 0)
		cam.global_position = c + Vector3(sin(ang) * 5.0, 0.6, cos(ang) * 5.0)
		cam.look_at(c)
		await _snap(out_dir + "/orbit_%03d.png" % int(round(rad_to_deg(ang))))

	# 2) HOLD: the aimed ballistic leaving the crown, then mid-flight with its ring.
	_place(7.0)
	await _settle(30)
	_side_cam(cam, 2.2)
	_shots.clear(); _markers = 0
	_robot._cool = 0.0
	while _shots.is_empty():
		await get_tree().physics_frame
	await _snap(out_dir + "/hold_muzzle.png")
	await _settle(22)
	await _snap(out_dir + "/hold_flight.png")
	_robot._cool = 9.0
	await _settle(90)

	# 3) NEAR: the fan, top-down so the spread reads. Placed DEEP in the band and fired fast —
	# the robot kites at 4 m/s the moment it is crowded, and 30 settle frames here once let it
	# back clear out of NEAR before the trigger read the band (the screenshot said HOLD).
	_place(3.2)
	await _settle(10)
	cam.global_position = _robot.global_position + Vector3(0, 13.0, 0.1)
	cam.look_at(_robot.global_position)
	_shots.clear()
	_robot._cool = 0.0
	while _shots.is_empty():
		await get_tree().physics_frame
	await _settle(5)
	await _snap(out_dir + "/near_burst_spawn.png")   # the fan still tight, three bolts distinct
	await _settle(10)
	await _snap(out_dir + "/near_burst_top.png")     # the fan opened across the kite band
	_robot._cool = 9.0
	await _settle(90)

	# 4) FAR: the towering lob from the side — then DODGE it, and photograph the crater wave
	# that comes after us anyway.
	_place(13.0)
	await _settle(30)
	_side_cam(cam, 4.0)
	_shots.clear()
	_waves = 0
	_robot._cool = 0.0
	while _shots.is_empty():
		await get_tree().physics_frame
	_robot._cool = 9.0
	await _settle(55)
	await _snap(out_dir + "/far_lob_side.png")
	var crater: Vector3 = _player.global_position
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.global_position += Vector3(4.0, 0, 0)
	cam.global_position = crater + Vector3(-2.0, 8.0, 8.0)
	cam.look_at(crater + Vector3(1.0, 0, 0))
	while _waves == 0:
		await get_tree().physics_frame
	await _settle(4)
	await _snap(out_dir + "/wave_1_spawn.png")
	await _settle(14)
	await _snap(out_dir + "/wave_2_front.png")
	await _settle(18)
	await _snap(out_dir + "/wave_3_passed.png")
	await _settle(60)

	# 5) THE PURPLE ONE, top-down: launched wide of the player, bending back onto them.
	_place(7.0)
	await _settle(20)
	var mid: Vector3 = (_robot.global_position + _player.global_position) * 0.5
	cam.global_position = mid + Vector3(0, 14.0, 0.1)
	cam.look_at(mid)
	_shots.clear()
	_robot._volleys = _robot.pierce_every - 1
	_robot._cool = 0.0
	while _shots.is_empty():
		await get_tree().physics_frame
	_robot._cool = 9.0
	await _settle(6)
	await _snap(out_dir + "/pierce_1_launch.png")
	await _settle(13)
	await _snap(out_dir + "/pierce_2_bend.png")
	await _settle(13)
	await _snap(out_dir + "/pierce_3_close.png")
	await _settle(30)

	# 6) The hit flash on the imported material.
	(_robot.get_node("HurtBox") as HurtBox).apply_hit(1, _player)
	var c2 := _robot.global_position + Vector3(0, 1.4, 0)
	cam.global_position = c2 + Vector3(3.5, 1.2, 3.5)
	cam.look_at(c2)
	await _settle(3)
	await _snap(out_dir + "/hit_flash.png")

	# 7) The shieldless guard — RMB held programmatically so Block survives its physics frames.
	_robot._cool = 9.0
	_place(6.0)
	await _settle(20)
	var vis := _player.get_node("Visuals") as Node3D
	var pc := _player.global_position + Vector3(0, 0.9, 0)
	cam.global_position = pc + (-vis.global_transform.basis.z) * 3.2 + Vector3(0, 0.5, 0)
	cam.look_at(pc)
	Input.action_press("block")
	_raise_guard(_player.get("_fsm") as Node)
	await _settle(25)
	await _snap(out_dir + "/guard_pose.png")
	Input.action_release("block")

	# 7b) THE STING, seen: the red body flash + the screen's damage breath, frames after a hit.
	# The freeze slows the flash tween with everything else, so the snap catches it near peak.
	await _settle(30)
	var pc2 := _player.global_position + Vector3(0, 0.9, 0)
	cam.global_position = pc2 + (-(_player.get_node("Visuals") as Node3D)
			.global_transform.basis.z) * 3.2 + Vector3(0, 0.5, 0)
	cam.look_at(pc2)
	(_player.get_node("HurtBox") as HurtBox).apply_hit(1, _robot)
	await _settle(2)
	await _snap(out_dir + "/hurt_sting.png")
	await _settle(40)

	# 8) LOCK-ON through the rig's OWN camera: locked on, then the player steps a quarter of the
	# way around the robot — the shot must come around by itself, fight always framed.
	cam.current = false
	var rigc := $CameraRig as CameraRig
	(rigc.get_node("Camera3D") as Camera3D).current = true
	_robot._cool = 9.0
	_place(7.0)
	await _settle(20)
	rigc.toggle_lock()
	await _settle(55)
	await _snap(out_dir + "/lock_behind.png")
	var lc: Vector3 = _robot.global_position
	(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.global_position = Vector3(lc.x + 7.0 * 0.7071, 1.1, lc.z + 7.0 * 0.7071)
	await _settle(55)
	await _snap(out_dir + "/lock_circled_45.png")
	_player.global_position = Vector3(lc.x + 7.0, 1.1, lc.z)
	await _settle(55)
	await _snap(out_dir + "/lock_circled_90.png")
	rigc.toggle_lock()
	print("[SHOTS] done -> " + out_dir)
	get_tree().quit(0)


## RAISE WHATEVER GUARD THIS BODY HAS. player3 carries the DIRECTIONAL guard now (Guard, see
## scripts/states/guard.gd) and the shield bodies still carry Block; transition_to no-ops on a name
## a body does not know, so asking for the wrong one silently left the player unguarded and the
## parry checks below failed for a reason that had nothing to do with parrying.
##
## Guard also reads its held/direction state from the FighterIntent rather than from Input, so the
## intent has to say the guard is up or it drops again on the next physics tick.
func _raise_guard(fsm: Node) -> void:
	if fsm.has_state("Guard"):
		var intent = _player.get("intent")
		if intent:
			intent.guard = true
		fsm.transition_to("Guard")
	else:
		fsm.transition_to("Block")

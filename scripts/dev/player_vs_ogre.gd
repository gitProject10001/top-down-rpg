extends Node3D
## PLAYER VERSUS OGRE — the fight, in the game's own terms.
##
## WHY THIS EXISTS SEPARATELY FROM THE LAB. `enemy_procedural_animation_test.tscn` is a bench: it
## drives the ogre from the keyboard, freezes it, bypasses layers and prints twenty numbers, and its
## lighting is deliberately flat so motion reads. All of that is the right way to BUILD an animation
## and the wrong way to judge a fight.
##
## The questions here are different, and none of them can be answered on the bench:
##   - Is the wind-up long enough to dodge, and short enough not to be boring?
##   - Does the slow turn make flanking a real tactic, or just make it easy?
##   - At four metres, can you see what it is about to do while standing close enough to hit it?
##   - Does the recovery leave a punish window you can actually take?
##
## THE SCENE OWNS THE SCENE. The player, the ogre, the rocks, the arena and the camera's target are
## all nodes in `player_vs_ogre.tscn`, placed by hand. An earlier version spawned them from `_ready`
## and pointed the camera in code, which meant the one scene you would most want to open and
## rearrange showed nothing but an empty floor until you pressed play. Where the combatants stand and
## where the cover sits are design decisions, and design decisions belong in the editor.
##
## So this file keeps only the two things that are genuinely behaviour: the readout, and the reset.
##
## KEYS
##   WASD move · LMB attack · Space dash · RMB block
##   R    restart the fight     F1  show/hide the readout
##   F3   hitboxes (the Dbg autoload's own key, so it behaves exactly as it does in the game)

@onready var _player: Node3D = $Player
@onready var _ogre: Enemy = $Ogre
@onready var _readout: Label = $UI/Readout

var _hits_on_ogre := 0
var _hits_on_player := 0
var _t := 0.0
var _solver: OgreSolver
## Which zones the aim reported, counted. A run that is all ADVANCE is an ogre that never got close
## enough to swing -- which reads in every other metric as zeroes, and looks like a broken swing.
var _zones := {}


func _ready() -> void:
	_solver = _ogre.find_child("OgreSolver", true, false) as OgreSolver
	_ogre.get_node("Health").damaged.connect(func(_a, _s): _hits_on_ogre += 1)
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
			# Reload rather than reposition. A finished fight leaves poise, cooldowns, i-frames,
			# springs and a half-played action lying about, and a reset that puts the bodies back
			# but not all of that is a worse lie than no reset at all.
			get_tree().reload_current_scene()
		KEY_F1:
			($UI as CanvasLayer).visible = not ($UI as CanvasLayer).visible


func _process(delta: float) -> void:
	# The dev readout is not gameplay UI either, so it goes with everything else on F8. F1 still
	# toggles it alone, for when the areas are wanted but the numbers are not.
	var dbg := get_node_or_null("/root/Dbg")
	if dbg != null and bool(dbg.clean):
		($UI as CanvasLayer).visible = false
	_t += delta
	if not is_instance_valid(_ogre):
		_readout.text = "ogre down after %.1f s — R to restart" % _t
		return
	var dist := 0.0
	if is_instance_valid(_player):
		dist = _player.global_position.distance_to(_ogre.global_position)

	# Only what you need to argue about a fight you just lost. The bench has the other twenty.
	var lines := PackedStringArray()
	lines.append("distance %5.2f m      (it reaches 5.2 m)" % dist)
	if _solver:
		var act := "-" if _solver.action == &"" \
				else "%s  %.2f / %.2f s" % [_solver.action, _solver.action_t, _solver.action_len]
		lines.append("ogre     %-28s turn cap %3.0f deg/s"
				% [act, rad_to_deg(_solver.yaw_rate(_solver.speed))])
		lines.append("speed    %5.2f m/s   %s"
				% [_solver.speed, "PLANTED — it cannot follow you" if _solver.stance_lock else ""])
	lines.append("")
	lines.append("hits on ogre %d      hits on you %d      %.0f s"
			% [_hits_on_ogre, _hits_on_player, _t])
	lines.append("WASD move · LMB attack · Space jump · Shift dash · RMB guard · R restart · F3 hitboxes")
	_readout.text = "\n".join(lines)


## THE COMBAT GATE. Everything the gait and IK probes cannot see.
##
## `probe_ogre_gait.gd` and `probe_ik.gd` test locomotion and reach, and they are good at it. They
## are also completely blind to the fight, and that blindness has been expensive: every serious bug
## in this combat system passed both of them the whole time it existed. The damage field that no
## code read, so every attack dealt 1. The hitstop that fired identically on a whiff. The punish
## window that put the ogre in a state where its own defensive moves could not run. The ogre
## throwing rocks forever because two range numbers disagreed. Green, all of them, all the way.
##
## So this asserts the fight's invariants instead of its locomotion. It exists so that a refactor --
## particularly one running unattended -- has a finish line that means something.
##
##   godot --resolution 900x760 res://scenes/dev/player_vs_ogre.tscn --log-file p.log -- --demo=probe
##
## Run as a SCENE, never `--script`: the moment an attack spawns a telegraph disc or a thrown rock
## it pulls in files that reference EventBus at compile time, and the script harness registers no
## autoloads.
func _demo_probe() -> void:
	var fails: Array[String] = []
	var notes: Array[String] = []

	# ---------------------------------------------------------------- static checks, no play needed
	# 1. EVERY ATTACK IS REACHABLE. An action nobody can select does not exist -- three of this
	#    creature's seven spent their lives that way, fully authored and never once chosen.
	#    actions_reaching() is deterministic, so this sweep covers the roster exactly (the old
	#    attack_for sweep sampled a random chooser and could miss a rarely-rolled band).
	var reachable := {}
	for d in range(0, 161):
		for n0 in _solver.actions_reaching(float(d) * 0.1):
			reachable[n0] = true
	for n in _solver.attack_names():
		var a: ActionSpec = _solver.spec(n)
		if a != null and a.is_attack and not reachable.has(n):
			fails.append("attack '%s' is never chosen at any distance from 0 to 16 m" % n)

	# 2. NO DEAD BAND inside the range the ogre will attack from. A ring where nothing is chosen is
	#    a place to stand and be ignored, and it is invisible until someone stands there.
	var gap_lo := -1.0
	for d in range(0, 121):
		var dist := float(d) * 0.1
		if _solver.actions_reaching(dist).is_empty():
			if gap_lo < 0.0:
				gap_lo = dist
		elif gap_lo >= 0.0:
			if dist - gap_lo > 0.3:
				fails.append("no attack covers %.1f..%.1f m" % [gap_lo, dist])
			gap_lo = -1.0

	# 3. THE REACTION FLOOR. From the first frame of movement to the hitbox going live must be at
	#    least 340 ms or the attack is memorisation rather than reaction -- the published budget is
	#    ~100 ms to perceive, ~70 to decide, ~70 to act, plus input latency. The kick was once 140 ms
	#    and read as "illegible", which is exactly what an unreactable attack feels like.
	for n in _solver.attack_names():
		var a2: ActionSpec = _solver.spec(n)
		if a2 == null or not a2.is_attack or a2.hit_at > 100.0:
			continue
		if a2.hit_at < 0.34:
			fails.append("'%s' opens damage %.0f ms after it starts (floor is 340 ms)"
					% [n, a2.hit_at * 1000.0])

	# ------------------------------------------------------------- the crowding, provoked on purpose
	# 8. CROWDING GETS AN ANSWER. The kick is retired (see its spec: illegible next to the pack's
	#    clips, and nothing in the pack kicks), so the backstep is now the ONLY reply to a player
	#    standing inside the ogre's guard — and this pins that it actually fires. Crowd at 2 m:
	#    a backstep must come, and the ogre it leaves behind must have made real room. Runs before
	#    the fight while the player still has all their hp; the main loop re-ranges them anyway.
	# Displacement is measured over the BACKSTEP ITSELF (start position to the frame it hands
	# off), not as the final gap — the step chains into a sweep whose forward lunge closes part
	# of what the hop opened, deliberately.
	var stepped := false
	var step_from := Vector3.ZERO
	var away := Vector3.ZERO
	var made_room := -1.0
	for i0 in 420:
		await get_tree().physics_frame
		if not (is_instance_valid(_player) and is_instance_valid(_ogre)):
			break
		var to0: Vector3 = _player.global_position - _ogre.global_position
		to0.y = 0.0
		if not stepped and to0.length() > 0.01:
			_player.global_position = _ogre.global_position + to0.normalized() * 2.0 \
					+ Vector3.UP * (_player.global_position.y - _ogre.global_position.y)
		if not stepped and _solver.is_acting() and _solver.action == &"backstep":
			stepped = true
			step_from = _ogre.global_position
			away = -to0.normalized()
		elif stepped and (_solver.action != &"backstep" or not _solver.is_acting()):
			var moved: Vector3 = _ogre.global_position - step_from
			moved.y = 0.0
			made_room = moved.dot(away)
			break                              # one full backstep observed, that is enough
	if not stepped:
		fails.append("crowding the ogre at 1.2 m never produced a backstep — no answer to crowding")
	elif made_room < 1.0:
		fails.append("the backstep retreated only %.1f m — it is not making room (moved %s, away %s, facing %s)"
				% [made_room, _ogre.global_position - step_from, away, _solver.forward()])

	# ---------------------------------------------------------------- the abandon, provoked on purpose
	# 11. AN ABANDONED SWING CHAINS. Stand in range until a wind-up starts, then break the range
	#     hard (8 m, straight behind). The solver names a switch_hint and the enemy plays it in
	#     the SAME tick — a path that was documented at length and could never fire, because the
	#     emit came before cancel_action() and the cancel destroyed the chain the handler had just
	#     started. Sampled on the frame after the abandon: the chain must still be alive.
	var pend := {"n": 0}
	var abandons := 0
	var chains := 0
	var on_ab := func(w: StringName, _at: Vector3) -> void:
		if w == &"abandoned":
			pend["n"] += 1
	_solver.action_event.connect(on_ab)
	for i1 in 3:
		var started := false
		for j in 300:
			await get_tree().physics_frame
			if not (is_instance_valid(_player) and is_instance_valid(_ogre)):
				break
			var tv: Vector3 = _player.global_position - _ogre.global_position
			tv.y = 0.0
			if tv.length() > 0.01:
				_player.global_position = _ogre.global_position \
						+ tv.normalized() * (_solver.strike_zone().y * 0.8) \
						+ Vector3.UP * (_player.global_position.y - _ogre.global_position.y)
			if _solver.is_acting() and _solver.spec(_solver.action) != null \
					and _solver.spec(_solver.action).is_attack:
				started = true
				break
		if not started:
			break
		var seen: int = pend["n"]
		for j2 in 300:
			if not (is_instance_valid(_player) and is_instance_valid(_ogre)):
				break
			_player.global_position = _ogre.global_position - _solver.forward() * 11.0 \
					+ Vector3.UP * (_player.global_position.y - _ogre.global_position.y)
			await get_tree().physics_frame
			if pend["n"] > seen:
				abandons += 1
				if _solver.is_acting():
					chains += 1
				break
			if not _solver.is_acting():
				break                          # it committed and finished instead — allowed; retry
	_solver.action_event.disconnect(on_ab)
	if abandons == 0:
		notes.append("no abandon could be provoked (every swing committed) — chain check skipped")
	elif chains == 0:
		fails.append("%d swing(s) abandoned and none chained — the CONCATENATE path is dead"
				% abandons)
	else:
		notes.append("abandons %d, chained %d" % [abandons, chains])

	# ---------------------------------------------------------------- then actually fight
	var beats := {}
	var dmg_seen := {}
	_solver.action_event.connect(func(w: StringName, _at: Vector3) -> void:
		beats[w] = int(beats.get(w, 0)) + 1)
	var hp_node: Node = _player.get_node("Health")
	var hp_was: int = int(hp_node.hp)
	var hits_taken := 0
	var window_seen := 0.0
	var hp0: int = hp_was

	# 9. THE SOLVER TICKS EVERY FRAME. Integer tick counter against integer frame count — clocks
	#    are useless here because hitstop scales every delta. Two AI branches used to `return`
	#    past the tick and silently cost the solver frames of aim, action clock, gait and planting.
	var ticks0: int = int(_solver.ticks)
	var frames := 0
	var stranded := ""
	var orphan_frames := 0
	var worst_orphan := 0
	# 15. THE AUTHORED STANCE'S OPERATING POINT HOLDS. The legs mix dial scales authored
	#     stances — measured to be load-bearing calibration, not a bug: removing it
	#     destabilized the whole fight (see _step_clip_stance's note). This floor pins where
	#     the point sits, so a change that squeezes the base further cannot pass silently.
	#     RE-PINNED for the hunter-skin era: the solver's own bakes asked modest stances and
	#     landed at ~0.70; the pack's clips ask theatrically wide ones against the same legs
	#     and the same reach clamp, so the RATIO reads lower (~0.47) while the absolute width
	#     on screen is no narrower. The floor moves with the clips it measures.
	var span_min := 1.0
	var span_seen := false
	# 16. THE MACE HEAD STAYS OUT OF THE GROUND. The swing's angle is elevation in its own plane
	#     and the landing angle IS the floor for an overhead, so anything that carries the swing
	#     "further" — a follow-through, a deeper landing, a longer arm — buries the head in the
	#     earth on the VERTICAL while leaving the horizontal looking perfect, because the flat
	#     sweep reads that same angle as yaw. That shipped exactly once, from a follow-through
	#     that was right for the sweep and wrong for the slam. The head may kiss the floor (it
	#     lands there) but never sink through it.
	#
	#     PER ACTION, because one attack is exempt on purpose: the pound drives the mace INTO
	#     the earth — that is why its damage comes from the ring and not the weapon. Exempting
	#     it by that same flag rather than by name keeps the rule about what an attack IS.
	var buried_by := {}
	var buried_dbg := {}
	var miss_by := {}
	var miss_why := {}

	# 13. AN ABSORBED HIT IS SILENT. The fight opens with the player i-framed: contacts land,
	#     apply 0, and none of them may freeze time — hitstop firing identically on an absorbed
	#     hit was the bug that made the loudest feedback in the game carry no information.
	var blocked := {"n": 0}
	var on_hit := func(_t: Node, _p: Vector3, applied: int) -> void:
		if applied <= 0:
			blocked["n"] += 1
	var mh0: HitBox = _solver.get("mace_hitbox")
	var kh0: HitBox = _solver.get("kick_hitbox")
	if mh0:
		mh0.dealt_hit.connect(on_hit)
	if kh0:
		kh0.dealt_hit.connect(on_hit)
	hp_node.extend_invulnerable(8.0)
	var min_ts := 1.0
	var last_hit_frame := -999

	for i in 1600:
		await get_tree().physics_frame
		frames += 1
		if not (is_instance_valid(_player) and is_instance_valid(_ogre)):
			break
		# Stand in range and DO NOT DODGE. The question is whether the ogre can hit a stationary
		# target at all, which is the floor below which nothing else about the fight matters.
		var to: Vector3 = _player.global_position - _ogre.global_position
		to.y = 0.0
		var want: float = _solver.strike_zone().y * 0.8
		if absf(to.length() - want) > 0.6 and to.length() > 0.01:
			var d3 := to.normalized()
			_player.global_position = _ogre.global_position + d3 * want \
					+ Vector3.UP * (_player.global_position.y - _ogre.global_position.y)
		var hp: int = int(hp_node.hp)
		if hp < hp_was:
			hits_taken += 1
			hp_was = hp
			last_hit_frame = i
		# Sample the absorbed-silence rule only OUTSIDE the wake of a real hit: a landed blow now
		# legitimately freezes time (contact_taken) AND grants a 0.5 s mercy window — invulnerable
		# no longer implies absorbed. The invariant is unchanged (a contact that applied 0 must
		# not freeze), only the instrument stopped conflating the two kinds of invulnerability.
		if hp_node.is_invulnerable() and i - last_hit_frame > 60:
			min_ts = minf(min_ts, Engine.time_scale)
		if float(_ogre.get("_winded_t")) > 0.0:
			window_seen += get_physics_process_delta_time()
		# HOW BADLY DOES IT MISS? "It never hit" is the same message whether the mace passed a
		# hand's width away or three metres, and those want opposite fixes.
		if _solver.is_acting() and _solver.mace_hitbox and _solver.mace_hitbox.visible:
			var gm := _solver.grip_node()
			if gm:
				var hm: Vector3 = gm.global_position \
						+ gm.global_basis.y.normalized() * _solver.weapon_length
				var miss := hm.distance_to(_player.global_position)
				if miss < float(miss_by.get(_solver.action, 99.0)):
					miss_by[_solver.action] = miss
					# ...and WHY it missed: how far the head is from the body (is the weapon
					# even extended?) against how far the player is (did the lunge arrive?).
					var relm: Vector3 = hm - _ogre.global_position
					var gapm: Vector3 = _player.global_position - _ogre.global_position
					miss_why[_solver.action] = "head %.2f m out, player %.2f m out" % [
							Vector2(relm.x, relm.z).length(), Vector2(gapm.x, gapm.z).length()]
		if _solver.is_acting():
			var gf := _solver.grip_node()
			if gf:                                          # check 16, sampled every frame
				var hdf: Vector3 = gf.global_position \
						+ gf.global_basis.y.normalized() * _solver.weapon_length
				var dy: float = hdf.y - _ogre.global_position.y
				if dy < float(buried_by.get(_solver.action, 99.0)):
					buried_by[_solver.action] = dy
					buried_dbg[_solver.action] = _solver.swing_dbg.duplicate()
		if hp <= 0:
			break
		# 12. NO TELEGRAPH DISC OUTLIVES ITS ACTION. A short overhang is the disc detonating out
		#     of a finished swing; a whole second of warning circle with no attack behind it is
		#     the orphan the abandoned handler exists to prevent.
		if _slam_ref() != null and not _solver.is_acting():
			orphan_frames += 1
			worst_orphan = maxi(worst_orphan, orphan_frames)
		else:
			orphan_frames = 0
		# 10. NO VOLUME OUTLIVES ITS ACTION. The kick's box may only be live during a kick, the
		#     mace's only during a mace attack — an interrupt used to close the NEW action's box
		#     and strand the old one, because the close ran after _act was reassigned.
		if _solver.is_acting() and _solver.clip_authored():
			var sw_spec: ActionSpec = _solver.spec(_solver.action)
			if sw_spec != null and not sw_spec.planted.is_empty() and sw_spec.kick_foot < 0 \
					and absf(_solver.action_t - _solver.action_time(_solver.action, &"strike")) < 0.1:
				var asked: Vector3 = _solver.clip_layer.foot_offset(0) - _solver.clip_layer.foot_offset(1)
				asked.y = 0.0
				var got: Vector3 = _solver.feet[0].target - _solver.feet[1].target
				got.y = 0.0
				if asked.length() > 0.4:
					span_seen = true
					span_min = minf(span_min, got.length() / asked.length())
		if stranded == "":
			var spec_now: ActionSpec = _solver.spec(_solver.action) if _solver.is_acting() else null
			var kick_now: bool = spec_now != null and spec_now.kick_foot >= 0
			# 14. …and for a ring attack (pound) the mace may NEVER arm: the ring is the damage,
			#     and the mace window opening alongside it was two sources for one blow.
			var ring_now: bool = spec_now != null and spec_now.damage_from_ring
			var kh: HitBox = _solver.get("kick_hitbox")
			var mh: HitBox = _solver.get("mace_hitbox")
			if kh != null and bool(kh.get("_active")) and not kick_now:
				stranded = "kick volume live outside a kick"
			elif mh != null and bool(mh.get("_active")) and (spec_now == null or kick_now or ring_now):
				stranded = "mace volume live outside a mace-carried attack"
		# 4. DAMAGE IS THE SPEC'S, NOT THE DEFAULT. Sampled while a window is open, because that is
		#    the only moment it is assigned. This is the exact bug that made every attack deal 1.
		if _solver.is_acting():
			var hb: HitBox = _solver.strike_hitbox()
			var spec: ActionSpec = _solver.spec(_solver.action)
			if hb != null and spec != null and spec.is_attack and spec.hit_at < 100.0 \
					and _solver.action_t >= spec.hit_at and _solver.action_t < spec.hit_at + spec.hit_for:
				dmg_seen[_solver.action] = [hb.damage, spec.damage]

	# ---------------------------------------------------------------- verdict
	var ticked: int = int(_solver.ticks) - ticks0
	if absi(frames - ticked) > 1:
		fails.append("solver ticked %d time(s) across %d physics frames — %d skipped"
				% [ticked, frames, frames - ticked])
	if stranded != "":
		fails.append(stranded)
	if worst_orphan > 60:
		fails.append("a telegraph disc sat on the ground %d frames with no action behind it"
				% worst_orphan)
	if int(blocked["n"]) == 0:
		notes.append("no contact landed during the i-frame stretch — absorbed-hit check untested")
	elif min_ts < 0.95:
		fails.append("an absorbed hit (%d applied 0) still froze time (time_scale hit %.2f)"
				% [blocked["n"], min_ts])
	else:
		notes.append("absorbed contacts: %d, all silent" % blocked["n"])
	if span_seen and span_min < 0.35:
		fails.append("an authored stance arrived squeezed to %.0f%% of its asked width" % (span_min * 100.0))
	elif span_seen:
		notes.append("authored stances at %.0f%% of asked width at strike" % (span_min * 100.0))
	# Landing ON the floor is the job; 12 cm of give covers the head's own radius settling into
	# the crater. Anything deeper is the swing continuing through solid ground.
	for an in buried_by:
		var abur: ActionSpec = _solver.spec(an)
		var low := float(buried_by[an])
		var exempt: bool = abur != null and abur.damage_from_ring
		notes.append("mace head lowest during '%s': %+.2f m%s"
				% [an, low, "  (into the earth by design)" if exempt else ""])
		if low < -0.12 and not exempt:
			fails.append("the mace head went %.2f m UNDER the floor during '%s' %s"
					% [-low, an, buried_dbg.get(an, {})])
	for mn in miss_by:
		notes.append("closest the '%s' head came to the player while live: %.2f m  (%s)"
				% [mn, float(miss_by[mn]), miss_why.get(mn, "")])
	if int(beats.get(&"strike", 0)) < 1:
		fails.append("no attack ever reached its strike beat")
	if int(beats.get(&"recover", 0)) < 1:
		fails.append("no attack ever reached its recover beat -- there is no punish window")
	if window_seen < 0.2:
		fails.append("the punish window was never open (%.2f s total)" % window_seen)
	if hits_taken < 1:
		fails.append("the ogre never hit a stationary player standing inside its strike zone")
	for k in dmg_seen:
		var pair: Array = dmg_seen[k]
		if int(pair[0]) != int(pair[1]):
			fails.append("'%s' hitbox deals %d but its spec says %d" % [k, pair[0], pair[1]])
	notes.append("beats: %s" % str(beats))
	notes.append("stationary player took %d hit(s), %d hp lost" % [hits_taken, hp0 - hp_was])
	notes.append("punish window open for %.2f s total" % window_seen)
	notes.append("damage checked on: %s" % str(dmg_seen.keys()))

	for n2 in notes:
		print("[COMBAT] %s" % n2)
	if fails.is_empty():
		print("PASS - the fight still works.")
	else:
		for f in fails:
			print("[COMBAT] FAIL %s" % f)
		print("FAIL - %d combat invariant(s) broken." % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## Watch the AI drive the procedural animation, unattended. Proves the seam: enemy.gd decides, the
## solver animates, and the beats it fires open and close a real damage volume.
## THE TWO EXTREMES: rush inside the mace, and break away from it. The ogre should shuffle to hold
## its range, and when that cannot save the swing, abandon it -- but only while aiming.
## THE PUNCHBAG TEST: stand at sword range and mash, exactly as a player complaining about a
## punchbag is doing.
##
## Every other band in this file moves the player and never presses attack, so `hits on ogre` has
## been 0 in every run ever recorded here — which means the failure the fight was actually being
## judged on had never once been measured. A test that does not do the thing proves nothing about
## the thing.
##
## What it reports is the shape of the loop, not a verdict: how much of the fight the ogre spent
## unable to act, how often it answered being crowded, and how far a kick actually moved anyone.
func _demo_mash() -> void:
	var acted := {"win": 0.0, "stag": 0.0, "acting": 0.0, "idle": 0.0}
	var answers := {}
	var kick_push := 0.0
	var hits_taken := 0
	_solver.action_event.connect(func(w: StringName, _at: Vector3) -> void:
		if w == &"telegraph":
			answers[_solver.action] = int(answers.get(_solver.action, 0)) + 1)
	var was_hp: int = int(_player.get_node("Health").hp)
	for i in 90:
		await get_tree().physics_frame
		if not (is_instance_valid(_player) and is_instance_valid(_ogre)):
			break
		# STAND IN ITS FACE AND SWING. Held down, because that is what mashing is.
		var c: Vector3 = _ogre.global_position
		var to: Vector3 = _player.global_position - c
		to.y = 0.0
		if to.length() > 2.5:
			var d := to.normalized()
			_player.velocity.x = -d.x * 6.0
			_player.velocity.z = -d.z * 6.0
		# A REAL EVENT, not Input.action_press. The player's states read the button through
		# handle_input, which is fed by _unhandled_input, and action_press only sets the polled
		# state -- it generates no event, so the first version of this test mashed for forty
		# seconds and landed nothing. A harness that does not do the thing measures nothing.
		var ev := InputEventAction.new()
		ev.action = "attack"
		ev.pressed = true
		Input.parse_input_event(ev)
		# Where the player was before, so a shove shows up as displacement -- over the whole stun,
		# not per frame, because 12 m/s for one frame is 0.2 m and says nothing about how far you
		# actually end up.
		var before: Vector3 = _player.global_position
		for _k in 24:
			await get_tree().physics_frame
		if not (is_instance_valid(_player) and is_instance_valid(_ogre)):
			break                                     # somebody died; the run is over
		var moved := before.distance_to(_player.global_position)
		var hp: int = int(_player.get_node("Health").hp)
		if hp < was_hp:
			hits_taken += 1
			was_hp = hp
			kick_push = maxf(kick_push, moved)
		# What the ogre was doing with its time.
		var dt := get_physics_process_delta_time() * 25.0
		if int(_ogre.get("_state")) == 4:                       # S.STAGGER
			acted["stag"] += dt
		elif float(_ogre.get("_winded_t")) > 0.0:
			acted["win"] += dt
		elif _solver.is_acting():
			acted["acting"] += dt
		else:
			acted["idle"] += dt
	var total: float = maxf(acted["win"] + acted["stag"] + acted["acting"] + acted["idle"], 0.01)
	print("[MASH] over %.1f s of standing in its face and swinging:" % total)
	print("[MASH]   ogre ACTING %.0f%%  |  punish window %.0f%%  |  staggered %.0f%%  |  idle %.0f%%"
			% [acted["acting"] / total * 100.0, acted["win"] / total * 100.0,
			acted["stag"] / total * 100.0, acted["idle"] / total * 100.0])
	print("[MASH]   it hit the player %d time(s); the biggest shove moved them %.2f m in a frame"
			% [hits_taken, kick_push])
	print("[MASH]   what it answered with: %s" % str(answers))
	var mx := 0
	if is_instance_valid(_ogre):
		mx = int(_ogre.get_node("Health").max_hp)
	print("[MASH]   hits landed on the ogre: %d of its %d hp" % [_hits_on_ogre, mx])
	print("[MASH]   player alive at the end: %s" % str(is_instance_valid(_player)))
	get_tree().quit()


func _demo_band(kind: String) -> void:
	var abandoned := {"n": 0, "at": ""}
	_solver.action_event.connect(func(w: StringName, _at: Vector3) -> void:
		if w == &"abandoned":
			abandoned["n"] += 1
			abandoned["at"] = "aiming" if _solver.aim_tracking() else "MID-SMASH (should never happen)")
	var sz: Vector2 = _solver.strike_zone()
	var kz: Vector2 = _solver.kick_zone()
	var picked := {}
	_solver.action_event.connect(func(w: StringName, _at: Vector3) -> void:
		if w == &"telegraph":
			picked[_solver.action] = int(picked.get(_solver.action, 0)) + 1)
	print("[BAND] %s | slam %.2f..%.2f m, kick %.2f..%.2f m"
			% [kind, sz.x, sz.y, kz.x, kz.y])
	var tries := 0
	var shuffled := 0.0
	var kicks := 0
	for i in 900:
		await get_tree().physics_frame
		if not (is_instance_valid(_player) and is_instance_valid(_ogre)):
			break
		if _solver.is_acting() and _solver.aim_tracking():
			# Once it starts aiming, do the awful thing.
			var c: Vector3 = _ogre.global_position
			var to: Vector3 = (_player.global_position - c)
			to.y = 0.0
			# INSIDE THE SLAM'S HOLE for the rush, so the test actually exercises the case the
			# kick exists for. The literal 0.7 m that used to be here sat just outside it, so every
			# rush was answered by a slam and the short-range branch was never once reached.
			var want: float = (_solver.strike_zone().x * 0.6) if kind == "rush" else 9.0
			var dir: Vector3 = to.normalized() if to.length() > 0.01 else Vector3.FORWARD
			var target: Vector3 = c + dir * want
			_player.global_position = _player.global_position.move_toward(
					Vector3(target.x, _player.global_position.y, target.z), 0.18)
			var before: Vector3 = _ogre.global_position
			await get_tree().physics_frame
			shuffled += before.distance_to(_ogre.global_position)
			tries += 1
			if _solver.action == &"kick":
				kicks += 1
	print("[BAND] %d aiming frames (%d of them kicking) | ogre shuffled %.2f m | abandoned %d time(s), %s"
			% [tries, kicks, shuffled, abandoned["n"], abandoned["at"] if abandoned["n"] > 0 else "-"])
	print("[BAND] attacks started, by name: %s" % str(picked))
	get_tree().quit()


## The live telegraph disc, if there is one.
func _slam_ref() -> Node3D:
	if not is_instance_valid(_ogre):
		return null
	# `is_instance_valid` on the HANDLE, not on the returned value: the enemy clears its reference
	# lazily, so between the disc being freed and that happening the field still holds a dead object,
	# and returning it is an error rather than a null.
	var a = _ogre.get("_slam_area")
	return a if (a != null and is_instance_valid(a)) else null


## THE DEATH GATE: the ogre's authored ragdoll, exercised and photographed. Kill it, assert the
## engine's simulation actually runs and stays sane at four metres of creature, and leave two
## frames for eyes. Usage: ... player_vs_ogre.tscn -- --demo=death --out=<dir>
func _demo_death() -> void:
	var fails: Array[String] = []
	var out_dir := "user://ogre_death"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.split("=", true, 1)[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	for i in 30:
		await get_tree().physics_frame
	var rag: PhysicalBoneSimulator3D = null
	var skel := _ogre.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skel != null:
		for c in skel.get_children():
			if c is PhysicalBoneSimulator3D:
				rag = c
	if rag == null:
		fails.append("no authored ragdoll under the ogre's skeleton")
	var c0: Vector3 = _ogre.global_position + Vector3(0, 2.2, 0)
	cam.global_position = c0 + Vector3(6.0, 2.0, 6.0)
	cam.look_at(c0)
	var expect_dir: Vector3 = _ogre.global_position - _player.global_position
	expect_dir.y = 0.0
	expect_dir = expect_dir.normalized()
	(_ogre.get_node("HurtBox") as HurtBox).apply_hit(999, _player)
	await get_tree().physics_frame
	if rag != null and not rag.is_simulating_physics():
		# One deferred hop between death and simulation start (collision-disable ordering).
		for i in 5:
			await get_tree().physics_frame
		if not rag.is_simulating_physics():
			fails.append("the ragdoll never started simulating")
	for i in 12:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + "/ogre_ragdoll_fall.png")
	var hips: PhysicalBone3D = null
	if rag != null:
		for c in rag.get_children():
			if c is PhysicalBone3D and String((c as PhysicalBone3D).bone_name) == "Hips":
				hips = c
	var p0 := hips.global_position if hips != null else Vector3.ZERO
	var sane := true
	for i in 70:
		await get_tree().physics_frame
		if hips != null and is_instance_valid(hips):
			var y := hips.global_position.y
			if is_nan(y) or y < -0.5 or y > 8.0:
				sane = false
	if not sane:
		fails.append("the four-metre ragdoll left the sane band — scale trouble")
	elif hips != null and is_instance_valid(hips):
		# F = ma at four metres: the blow's direction must carry the corpse.
		var disp := hips.global_position - p0
		disp.y = 0.0
		if disp.dot(expect_dir) < 0.3:
			fails.append("the corpse moved %.2f m along the blow — dropped, not thrown"
					% disp.dot(expect_dir))
	if hips != null and is_instance_valid(hips):
		var at := hips.global_position
		cam.global_position = at + Vector3(3.5, 4.5, 3.5)
		cam.look_at(at)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + "/ogre_ragdoll_rest.png")
	for f in fails:
		print("[DEATH] FAIL  " + f)
	print("[DEATH] %s — frames in %s" % ["RED" if fails.size() else "GREEN", out_dir])
	get_tree().quit(1 if fails.size() else 0)


func _demo(out: String) -> void:
	# Dispatch on the --demo= value FIRST. The documented gate invocation is `-- --demo=probe`,
	# but reaching the probe used to require a separate literal `--probe`; the documented command
	# fell through to the band demo, wrote a screenshot into a folder named "probe", and exited 0.
	# A gate that cannot be reached cannot fail. Both spellings work now.
	match out:
		"probe":
			await _demo_probe()
			return
		"death":
			await _demo_death()
			return
		"mash":
			await _demo_mash()
			return
		"rush", "flee":
			await _demo_band(out)
			return
	for a in OS.get_cmdline_user_args():
		if a == "--probe":
			await _demo_probe()
			return
		if a == "--mash":
			await _demo_mash()
			return
		if a == "--rush":
			await _demo_band("rush")
			return
		if a == "--flee":
			await _demo_band("flee")
			return
	var start := _ogre.global_position
	var seen := {}
	_solver.action_event.connect(func(w: StringName, _at: Vector3) -> void:
		seen[w] = int(seen.get(w, 0)) + 1)
	# Sum every shake the ogre asks for, so "less shaking" is a number rather than an impression.
	#
	# A DICTIONARY, not three locals. GDScript lambdas capture locals BY VALUE, so `count += 1`
	# inside one increments a copy and the outer variable never moves -- the listener fires happily
	# and reports zero, which is indistinguishable from a game that never shakes. A Dictionary is a
	# reference, so mutating it works. (`seen` above is a Dictionary for the same reason, which is
	# why its numbers were trustworthy while these were not.)
	var tally := {"n": 0, "sum": 0.0, "peak": 0.0, "steps": 0, "step_sum": 0.0, "step_peak": 0.0}
	var bus := get_node_or_null(^"/root/EventBus")
	if bus:
		bus.combat_impact.connect(func(v: float) -> void:
			tally["n"] += 1
			tally["sum"] += v
			tally["peak"] = maxf(tally["peak"], v)
			# Split them: a slam is meant to hit hard and a footstep is not, so one number covering
			# both answers nothing about whether walking is too noisy.
			if v < 0.3:
				tally["steps"] += 1
				tally["step_sum"] += v
				tally["step_peak"] = maxf(tally["step_peak"], v))
	# Prove the listener works before trusting a zero from it: a counter that never fires and a
	# game that never shakes look identical from here.
	if bus:
		bus.combat_impact.emit(0.001)
		print("[FIGHT] listener self-test: %d event(s) — %s"
				% [tally["n"], "wired" if tally["n"] > 0 else "NOT WIRED, the zero below means nothing"])
		# CLEARED IN PLACE, not reassigned. The lambda captured this dictionary by value -- the
		# reference itself -- so rebinding the variable leaves it mutating the old one while this
		# prints the new one. The same capture rule that broke the counters, one level deeper.
		for k in tally:
			tally[k] = 0 if k == "n" or k == "steps" else 0.0
	else:
		print("[FIGHT] no EventBus at /root — cannot measure shake")
	# TRACE THE WEAPON THROUGH A REAL FIGHT. The lab has the ogre standing still; here it walks and
	# TURNS to face the player, and `facing` is an input to the weapon's aim. The reported symptom --
	# the swing starting to one side and switching to the other -- is a discontinuity in time, so it
	# gets sampled every physics frame rather than at a handful of poses.
	var skel := _solver.skeleton()
	var rh := skel.find_bone(_solver.weapon_bone)
	var tr := PackedStringArray()
	var prev_dir := Vector3.ZERO
	var worst_jump := 0.0
	var worst_detach := 0.0
	var worst_perp := 0.0
	var worst_r := 0.0
	var worst_l := 0.0
	var miss := PackedStringArray()
	# DOES THE AIM ACTUALLY COMMIT? The impact point should chase the player while the ogre winds up
	# and go still the moment the mace starts down. Measured as how far it travels per second in each
	# phase: a big number while aiming, near zero during the smash, is the dodge window existing.
	var track_move := 0.0
	var track_time := 0.0
	var commit_move := 0.0
	var commit_time := 0.0
	var prev_aim := Vector3.ZERO
	var dbg := get_node_or_null(^"/root/Dbg")
	if dbg:
		dbg.show_hitboxes = true
	var shot := false
	# WHERE IS THE MACE WHEN THE DAMAGE TURNS ON? If the volume opens while the head is still in the
	# air, the ogre can hit you with a weapon that is over its own head.
	var open_h := {"y": -99.0, "d": 99.0}
	var near_head := 99.0
	var lie := 0.0
	var was_tracking := false
	var dropped := {"n": 0}
	_solver.weapon_dropped.connect(func(_at: Vector3) -> void: dropped["n"] += 1)
	# FLAGGED HERE, MEASURED AFTER THE DRAW. hit_open fires in the physics tick and the weapon's
	# transform is written in _process, so reading the grip from inside this handler compares this
	# frame's beat against last frame's mace -- the same cross-clock mistake that once had me
	# reporting the grip 0.9 m out when it was fine.
	_solver.action_event.connect(func(w: StringName, _at: Vector3) -> void:
		if w == &"hit_open":
			open_h["pending"] = true)
	var closest := 999.0
	for i in 900:
		await get_tree().physics_frame
		# STRAFE THE PLAYER, or the test proves nothing: an aim that chases has nothing to chase
		# against a target standing still, and both phases read the same.
		if is_instance_valid(_player) and is_instance_valid(_ogre):
			var c: Vector3 = _ogre.global_position
			# A FIXED radius, DERIVED from the ogre's own strike zone. Orbiting at "whatever
			# distance it happens to be" let the player drift out of range and the ogre never
			# attacked at all -- a test that measures nothing, reported as zeroes. The literal 4.2 m
			# that used to be here had the same failure with extra steps: it was written against a
			# declared 5.2 m reach, and the moment the reach became the real one it put the player
			# permanently out of it.
			var r: float = _solver.strike_zone().y * 0.85
			var a := float(i) * 0.035
			_player.global_position = Vector3(c.x + cos(a) * r, _player.global_position.y,
					c.z + sin(a) * r)
		# One frame mid-smash with the volumes drawn, so the telegraph and the thing that actually
		# hits you can be compared at a glance.
		if _solver and _solver.aim_tracking():
			var zn: String = ["STRIKE", "TURN", "REPOSITION", "WRONG"][_solver.zone]
			_zones[zn] = _zones.get(zn, 0) + 1
		if not shot and _solver and _solver.is_acting() and not _solver.aim_tracking():
			shot = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/hit_shot.png" % out)
		# HOW HONEST IS THE CIRCLE? The gap between where the telegraph sits and where the head
		# actually comes down. A warning that is merely nearby is worse than none.
		# ONLY WHILE THE TELEGRAPH IS STILL TRACKING. After the commit the disc is deliberately
		# frozen and the prediction goes on moving with the ogre, so a gap there is the mechanic
		# working rather than the circle lying -- measuring it caught 6.62 m and meant nothing.
		# AT THE MOMENT OF COMMIT, which is the promise the player acts on. A worst-case across the
		# whole wind-up catches the single frame where a new disc replaces the last one and reports
		# metres of "lie" that no player ever sees.
		var disc := _slam_ref()
		if _solver and disc != null:
			var now := _solver.aim_tracking()
			if was_tracking and not now:
				var pr: Vector3 = _solver.predicted_impact()
				var dr: Vector3 = disc.global_position
				lie = maxf(lie, Vector2(pr.x - dr.x, pr.z - dr.z).length())
			was_tracking = now
		if open_h.get("pending", false):
			open_h["pending"] = false
			await RenderingServer.frame_post_draw
			var d4 := _slam_ref()
			var g4 := _solver.grip_node()
			if g4 and d4:
				# DID IT LAND IN ITS OWN CIRCLE? The head's resting place against the disc that
				# promised it, at the moment the damage goes live.
				var hd5: Vector3 = g4.global_position 						+ g4.global_basis.y.normalized() * _solver.weapon_length
				open_h["in_disc"] = Vector2(hd5.x - d4.global_position.x,
						hd5.z - d4.global_position.z).length()
			if g4 and is_instance_valid(_player):
				var hd4: Vector3 = g4.global_position 						+ g4.global_basis.y.normalized() * _solver.weapon_length
				open_h["y"] = hd4.y - _ogre.global_position.y
				open_h["d"] = hd4.distance_to(_player.global_position)
				open_h["dbg"] = _solver.swing_dbg.duplicate()
		# The CLOSEST the mace head gets to the player while the damage is live. If this never gets
		# near the hurtbox, an overlap can never happen however long the window is.
		if _solver and _solver.mace_hitbox and _solver.mace_hitbox.visible and is_instance_valid(_player):
			var g2 := _solver.grip_node()
			if g2 and _solver.is_acting():
				var h2: Vector3 = g2.global_position + g2.global_basis.y.normalized() * _solver.weapon_length
				near_head = minf(near_head, h2.distance_to(_player.global_position))
		if _solver and _solver.is_acting() and _solver.aim_point != Vector3.ZERO:
			var dt := get_physics_process_delta_time()
			if prev_aim != Vector3.ZERO:
				var moved: float = prev_aim.distance_to(_solver.aim_point)
				if _solver.aim_tracking():
					track_move += moved
					track_time += dt
				elif _solver.action_t < _solver.spec(_solver.action).time_of(&"strike"):
					# The SMASH WINDOW only -- between committing and the blow landing. The
					# recovery after it is not the dodge window and averaging it in hides the
					# thing being measured.
					commit_move += moved
					commit_time += dt
			prev_aim = _solver.aim_point
		else:
			prev_aim = Vector3.ZERO
		if _solver.is_acting() and is_instance_valid(_ogre):
			var g := _solver.grip_node()
			var pts := _solver.arm_ik.bone_positions()
			if g and rh < pts.size():
				var dir: Vector3 = g.global_basis.y.normalized()
				# IS IT EVEN IN THE HAND? The butt should sit within a few centimetres of the fist.
				# Metres here means the mace is not being held at all, which is what the screenshots
				# of it lying across the arena look like.
				var detach: float = g.global_position.distance_to(pts[rh])
				worst_detach = maxf(worst_detach, detach)
				# THE QUESTIONS THAT MATTER, separated. "Is the point on the mace" and "is the hand
				# on the point" are different failures with the same look, and only one of them is
				# about the weapon's coordinates.
				var pt := _solver.grip_world()
				var v := pt - g.global_position
				var perp := (v - dir * v.dot(dir)).length()
				worst_perp = maxf(worst_perp, perp)
				var lh := _solver.bone("LeftHand")
				var reach_r := pts[rh].distance_to(pt)
				var reach_l := 0.0 if lh < 0 or lh >= pts.size() 						else pts[lh].distance_to(_solver.off_grip_world())
				worst_r = maxf(worst_r, reach_r)
				worst_l = maxf(worst_l, reach_l)
				if reach_r > 0.5 and miss.size() < 6:
					miss.append("[MISS] t=%.2f anchor %-10s R hand %.2f m from its point (grip %.2f) | L %.2f (grip %.2f)"
							% [_solver.action_t, _solver.weapon_anchor(), reach_r,
							_solver.arm_ik.grip_strength(1), reach_l,
							_solver.arm_ik.grip_strength(0)])
				# How far the aim moved in ONE frame. A swing is fast; a teleport is not a swing.
				var jump := 0.0 if prev_dir == Vector3.ZERO else rad_to_deg(prev_dir.angle_to(dir))
				if jump > worst_jump:
					worst_jump = jump
				if jump > 25.0:
					tr.append("[JUMP] t=%.2f aim moved %.0f deg in one frame | push %.0f | detach %.2f m | facing %.0f"
							% [_solver.action_t, jump, _solver.clear_degrees, detach,
							rad_to_deg(_solver.facing)])
				prev_dir = dir
		else:
			prev_dir = Vector3.ZERO
		if is_instance_valid(_player) and is_instance_valid(_ogre):
			closest = minf(closest, _player.global_position.distance_to(_ogre.global_position))
	for l in tr:
		print(l)
	for m in miss:
		print(m)
	print("[FIGHT] point-off-shaft %.3f m (should be ~0) | R hand worst %.2f m from point | L hand worst %.2f m"
			% [worst_perp, worst_r, worst_l])
	print("[FIGHT] worst one-frame aim jump %.0f deg; worst butt-to-fist gap %.2f m"
			% [worst_jump, worst_detach])
	print("[FIGHT] AIM (player strafing): chases at %.2f m/s over %.1f s of aiming; %.2f m/s over %.1f s of smash"
			% [track_move / maxf(track_time, 0.001), track_time,
			commit_move / maxf(commit_time, 0.001), commit_time])
	print("[FIGHT] when the damage opened, the mace head was %.2f m up and %.2f m from the player"
			% [open_h["y"], open_h["d"]])
	if open_h.has("dbg"):
		var d3: Dictionary = open_h["dbg"]
		print("[FIGHT]   angle %.1f of a floor angle of %.1f | hinge y %.2f, feet y %.2f, arm %.2f, radius %.2f, plane_up.y %.2f"
				% [d3["ang"], d3["floor"], d3["hinge_y"], d3["feet_y"], d3["arm"], d3["radius"],
				d3["plane_up_y"]])
		print("[FIGHT]   the ARC says the head is at y %.2f; the GRIP node reports %.2f"
				% [d3.get("head_y", 0.0), open_h["y"]])
	print("[FIGHT] is the ogre still holding the mace at the end? %s  (carrying=%s)"
			% ["yes" if _solver.grip_node() and _solver.mace_hitbox and _solver.carrying != &"" else "*** NO -- it was DROPPED ***",
			str(_solver.carrying)])
	print("[FIGHT] mace dropped %d time(s) during the fight" % dropped["n"])
	print("[FIGHT] at the moment it commits, telegraph vs prediction: %.3f m apart at worst" % lie)
	print("[FIGHT] at the moment of damage, the head landed %.2f m from the disc centre (disc radius %.2f)"
			% [open_h.get("in_disc", -1.0), _solver.spec(&"slam").slam_radius])
	print("[FIGHT] arm extension the swing asked for: %.2f m (limits %.2f..%.2f)"
			% [_solver.swing_reach_used, _solver.arm_ik.arm_reach() * _solver.tuning.swing_reach
			* _solver.tuning.swing_arm_min, _solver.arm_ik.arm_reach()
			* _solver.tuning.swing_reach * _solver.tuning.swing_arm_max])
	print("[FIGHT] closest the mace head came to the player during a swing: %.2f m" % near_head)
	print("[FIGHT] damage volume: %s"
			% ("on the MACE" if (_solver and _solver.mace_hitbox) else "*** still the body box ***"))
	print("[FIGHT] ogre travelled %.2f m toward the player"
			% start.distance_to(_ogre.global_position))
	print("[ZONE] hinge %.3f  arm_reach %.3f  weapon_len %.3f  grip.y %.3f  solver.gp.y %.3f"
			% [_solver.shoulder_height(), _solver.arm_ik.arm_reach(), _solver.weapon_length,
			_solver.grip_point.y, _solver.global_position.y])
	var kz: Vector2 = _solver.kick_zone()
	print("[ZONE] kick band %.2f..%.2f  leg chain %.2f  crouch %.2f | picks: %s"
			% [kz.x, kz.y, _solver.leg_chain(), _solver.crouch,
			str([_solver.actions_reaching(0.4), _solver.actions_reaching(0.9),
			_solver.actions_reaching(1.6), _solver.actions_reaching(2.2),
			_solver.actions_reaching(4.0)])])
	var z: Vector2 = _solver.strike_zone()
	print("[FIGHT] closest approach %.2f m   (strike zone %.2f..%.2f m from the shoulder)"
			% [closest, z.x, z.y])
	print("[FIGHT] zones seen while aiming: %s" % str(_zones))
	print("[FIGHT] solver beats fired: %s" % str(seen))
	print("[FIGHT] player hit %d times" % _hits_on_player)
	print("[FIGHT] camera shake: %d events, total %.3f, peak %.3f (a slam alone is 1.000)"
			% [tally["n"], tally["sum"], tally["peak"]])
	print("[FIGHT]   of which FOOTSTEPS: %d, total %.4f, peak %.4f"
			% [tally["steps"], tally["step_sum"], tally["step_peak"]])
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/demo_fight.png" % out)
	get_tree().quit()

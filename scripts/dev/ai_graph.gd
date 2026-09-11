extends Node
## Autoload "AiGraph" — the enemy AI's state machine, drawn live while you fight it (F5).
##
## WHY THIS EXISTS. The enemies deliberately do not use AnimationTree state machines: their
## BEHAVIOUR is a hand-written enum FSM in enemy.gd (one script, three attack kinds by data),
## and their MOTION is either a procedural solver (the ogre) or nothing at all (the hovering
## robot). That buys exactness, but it means there is no editor graph to stare at when the
## question is "why is it doing that" — the answer lives in a private int and five timers. This
## panel is that graph, reconstructed: the real states, the real transition that just fired, the
## real dials, and the range bands the decisions are made from, all read every frame off the
## live enemy.
##
## WHICH ENEMY: the camera lock's target when one is held (the enemy you are fighting IS the one
## you are debugging), else the nearest Enemy to the player. Swarmlings run their own tiny
## script and are not Enemies; the panel says so rather than guessing.
##
## READ-ONLY, ALWAYS — the same law as the Areas overlay: it reads private fields with get()
## and never writes one. The edge list below is hand-authored to MIRROR enemy.gd's actual
## transitions; if a transition fires that the map does not know, the log still shows it
## (the log is driven by observed state changes, not by the map).
##
## KEYS: F5 toggles. F8 (clean view) hides it with everything else. F6/Areas draws the same
## fight's world-space zones; this is the flowchart half of that picture.

const STATE_NAMES: Array[String] = ["IDLE", "CHASE", "ATTACK", "FLINCH", "STAGGER", "DEAD", "FEAR"]

## Node positions in panel space, hand-laid: the main loop reads left to right, the reaction
## states sit under it, the terminal state to the side.
const STATE_POS := {
	0: Vector2(60, 64),      # IDLE
	1: Vector2(185, 64),     # CHASE
	2: Vector2(310, 64),     # ATTACK
	3: Vector2(95, 148),     # FLINCH
	4: Vector2(220, 148),    # STAGGER
	6: Vector2(345, 148),    # FEAR
	5: Vector2(408, 64),     # DEAD
}

## The transitions enemy.gd actually performs, with the condition each fires on. Hand-authored
## and worth keeping honest: this is documentation that can be watched.
const EDGES := [
	[0, 1, "see"], [1, 0, "1.4x aggro"], [1, 2, "attack"], [2, 1, "done"],
	[1, 3, "hit"], [3, 1, ""], [2, 4, "poise/parry"], [4, 1, "1.3s"],
	[1, 6, "drama"], [6, 1, ""], [2, 5, "hp 0"],
]

const NODE_R := 26.0
const PANEL_W := 470.0
const COL_BG := Color(0.06, 0.07, 0.10, 0.82)
const COL_DIM := Color(0.55, 0.58, 0.65, 0.8)
const COL_LIVE := Color(1.0, 0.8, 0.25)
const COL_FLASH := Color(1.0, 0.45, 0.15)
const COL_TEXT := Color(0.92, 0.93, 0.96)
## The band colours, matching the Areas overlay and the robot scene's floor rings exactly —
## one vocabulary of colour across every debug surface, or none of them teaches anything.
const COL_NEAR := Color(1.00, 0.80, 0.25)
const COL_MID := Color(1.00, 0.55, 0.12)
const COL_FAR := Color(0.35, 0.72, 1.00)

## THE RING BLOCK IS APPENDED, NEVER INTERLEAVED. With no CombatDirector ring around this enemy's
## target the panel is exactly the 350 px it has always been, so the four player_vs_* benches (and
## any --ai-shot capture of them) are pixel-identical. Only a coordinated pack grows the panel.
const RING_BLOCK_H := 128.0
const RING_PLAN_R := 46.0        ## radius of the little plan view, in panel pixels

var enabled := false

var _panel: Control
var _target: Node          ## the Enemy being described
var _prev_state := -1
var _edge_flash := 0.0     ## seconds left of the just-fired transition's highlight
var _flash_from := -1
var _flash_to := -1
var _log: Array[String] = []
var _t := 0.0
var _shot_path := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ai-shot="):
			_shot_path = a.split("=", true, 1)[1]
			enabled = true
	var layer := CanvasLayer.new()
	layer.layer = 40                            # per docs/architecture.md: dev panels live at 40
	add_child(layer)
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_panel)
	layer.add_child(_panel)
	if _shot_path != "":
		_shoot.call_deferred()


## Two frames of the panel over a live fight, then out — the same self-verifying idiom as the
## Areas overlay's --areas-shot.
func _shoot() -> void:
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path + "/ai_graph_1.png")
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path + "/ai_graph_2.png")
	print("[AIGRAPH] frames written to " + _shot_path)
	get_tree().quit()


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not (e as InputEventKey).echo \
			and (e as InputEventKey).physical_keycode == KEY_F5:
		enabled = not enabled
		print("[AiGraph] %s" % ("ON" if enabled else "OFF"))


func _process(dt: float) -> void:
	_t += dt
	_edge_flash = maxf(_edge_flash - dt, 0.0)
	var dbg := get_node_or_null("/root/Dbg")
	var show := enabled and not (dbg != null and bool(dbg.clean))
	_panel.visible = show
	if not show:
		return
	_pick_target()
	if _target != null:
		var st := int(_target.get("_state"))
		if st != _prev_state:
			if _prev_state >= 0:
				_flash_from = _prev_state
				_flash_to = st
				_edge_flash = 0.8
				_log.push_front("%6.1fs  %s -> %s" % [_t, _name_of(_prev_state), _name_of(st)])
				if _log.size() > 6:
					_log.resize(6)
			_prev_state = st
	_panel.queue_redraw()


## The lock's target first — the enemy you are FIGHTING is the one you are debugging — else the
## nearest Enemy to the player. Reset the transition log when the subject changes.
func _pick_target() -> void:
	var next: Node = null
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("locked") and rig.locked() is Enemy:
		next = rig.locked()
	if next == null:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		var best := 1e9
		for t in get_tree().get_nodes_in_group("enemy"):
			if not (t is Enemy) or not is_instance_valid(t):
				continue
			var d: float = (t as Node3D).global_position.distance_to(p.global_position) \
					if p != null else 0.0
			if d < best:
				best = d
				next = t
		# HYSTERESIS, WHICH ONLY A PACK NEEDS. Nearest-wins is fine for a duel and useless with
		# four bodies orbiting at the same radius: the subject flickers between them several times
		# a second, the transition log resets on every switch, and the panel becomes unreadable
		# exactly when you most need it. A challenger must be 20% closer to take over; hold the
		# lock (MMB) to choose deliberately.
		if _target != null and is_instance_valid(_target) and next != _target and p != null \
				and get_tree().get_nodes_in_group("enemy").has(_target):
			var cur: float = (_target as Node3D).global_position.distance_to(p.global_position)
			if best > cur * 0.8:
				next = _target
	if next != _target:
		_target = next
		_prev_state = int(_target.get("_state")) if _target != null else -1
		_log.clear()
		_edge_flash = 0.0


func _name_of(s: int) -> String:
	return STATE_NAMES[s] if s >= 0 and s < STATE_NAMES.size() else str(s)


# ---------------------------------------------------------------------------------------------
# Drawing. Everything is offsets from the panel's top-right corner.
# ---------------------------------------------------------------------------------------------

func _draw_panel() -> void:
	var font := ThemeDB.fallback_font
	var o := Vector2(_panel.size.x - PANEL_W - 14.0, 46.0)
	var ring: Dictionary = _ring_snapshot()
	var panel_h := 350.0 + (RING_BLOCK_H if not ring.is_empty() else 0.0)
	_panel.draw_rect(Rect2(o, Vector2(PANEL_W, panel_h)), COL_BG)
	if _target == null or not is_instance_valid(_target):
		_panel.draw_string(font, o + Vector2(16, 30), "AI GRAPH — no Enemy in the scene",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TEXT)
		return
	var e := _target as Node3D
	var title := "AI  %s%s" % [e.name,
			"   [locked]" if _lock_is(e) else ""]
	_panel.draw_string(font, o + Vector2(16, 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_LIVE)
	_panel.draw_string(font, o + Vector2(PANEL_W - 30, 24), "F5", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_DIM)

	var st := int(e.get("_state"))
	var go := o + Vector2(10, 26)          # graph origin

	# Edges first, nodes over them. The one that just fired burns orange and fades.
	for edge in EDGES:
		var a: Vector2 = STATE_POS[edge[0]]
		var b: Vector2 = STATE_POS[edge[1]]
		var col := COL_DIM * Color(1, 1, 1, 0.5)
		var wide := 1.0
		if _edge_flash > 0.0 and edge[0] == _flash_from and edge[1] == _flash_to:
			col = Color(COL_FLASH.r, COL_FLASH.g, COL_FLASH.b, clampf(_edge_flash / 0.8, 0.0, 1.0))
			wide = 3.0
		_arrow(go + a, go + b, col, wide)
		if String(edge[2]) != "":
			var mid := go + (a + b) * 0.5 + Vector2(2, -4)
			_panel.draw_string(font, mid, String(edge[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					COL_DIM * Color(1, 1, 1, 0.85))
	for s in STATE_POS:
		var at: Vector2 = go + STATE_POS[s]
		var live: bool = int(s) == st
		_panel.draw_circle(at, NODE_R, Color(0.12, 0.13, 0.18, 0.95) if not live else
				Color(COL_LIVE.r, COL_LIVE.g, COL_LIVE.b, 0.25))
		_panel.draw_arc(at, NODE_R, 0, TAU, 32, COL_LIVE if live else COL_DIM, 2.0 if live else 1.0)
		var nm := _name_of(s)
		_panel.draw_string(font, at + Vector2(-nm.length() * 3.4, 4), nm,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_LIVE if live else COL_TEXT)

	# The dials the decisions run on — the timers you otherwise reconstruct from prints.
	var y := o.y + 212.0
	var cool := float(e.get("_cool"))
	var poise := float(e.get("_poise"))
	var maxp := float(e.get("max_poise"))
	var winded := float(e.get("_winded_t"))
	var lines: Array[String] = []
	lines.append("cool %4.1fs    poise %.0f/%.0f    %s" % [cool, poise, maxp,
			("OPEN %.1fs" % winded) if winded > 0.0 else ""])
	var chain: StringName = e.get("_next_chain")
	if chain != StringName(""):
		lines.append("chained next: %s" % chain)
	var solver: Node = e.get("_solver")
	if solver != null:
		var act: StringName = solver.get("action")
		lines.append("solver: %s   zone %s" % [
				("%s %.2f/%.2f" % [act, float(solver.get("action_t")),
				float(solver.get("action_len"))]) if act != StringName("") else "-",
				["STRIKE", "TURN", "REPOSITION", "WRONG"][int(solver.get("zone"))]])
	elif int(e.get("attack_kind")) == 1:
		var pe := int(e.get("pierce_every"))
		if pe > 0:
			var until_purple := pe - (int(e.get("_volleys")) % pe)
			lines.append("volley %d   purple in %d shot%s" % [int(e.get("_volleys")),
					until_purple, "" if until_purple == 1 else "s"])
	for ln in lines:
		_panel.draw_string(font, Vector2(o.x + 16, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_TEXT)
		y += 18.0

	_draw_bands(font, e, Vector2(o.x + 16, o.y + 272.0))
	if not ring.is_empty():
		_draw_ring(font, o, e, ring)

	# The observed-transition log: what it DID, stamped, newest first.
	var ly := o.y + 318.0
	for i in _log.size():
		_panel.draw_string(font, Vector2(o.x + 16 + 150 * (i % 3), ly + 14 * (i / 3)), _log[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_DIM if i > 0 else COL_TEXT)


## The pack this enemy is fighting in, or {} when it is fighting alone. Read through the
## director's own snapshot() rather than get() on its privates: enemy.gd and OgreSolver are not
## ours to reshape for a debug panel, but the director is, so it can simply answer the question.
func _ring_snapshot() -> Dictionary:
	var cd := get_node_or_null("/root/CombatDirector")
	if cd == null or _target == null or not is_instance_valid(_target):
		return {}
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return {}
	var snap: Dictionary = cd.snapshot(p)
	if snap.is_empty() or int(snap.get("members", 0)) < 2:
		# One body is not a pack, and drawing a ring for it would claim coordination that is not
		# happening. This is also what keeps the duel benches at 350 px.
		return {}
	return snap


## THE RING, TOLD VERSUS ACTUAL.
##
## A plan view, because that is the honest shape for a question about bearings, and because this
## panel is a 2D Control with no 3D drawing of its own -- the world-space half of the picture is
## Areas (F6), which draws nothing for a body with no solver, i.e. for every member of a pack.
##
## Per member: a FILLED dot where the director told it to wait, a HOLLOW dot where it actually is,
## and a hairline joining them. The gap between the two IS the bug report -- the same idea the
## combat overlay's "lie" line uses for promised-versus-actual impact, and for the same reason.
func _draw_ring(font: Font, o: Vector2, e: Node3D, snap: Dictionary) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var top := o.y + 350.0
	_panel.draw_line(Vector2(o.x + 12, top + 4), Vector2(o.x + PANEL_W - 12, top + 4),
			COL_DIM * Color(1, 1, 1, 0.35), 1.0)
	var c := Vector2(o.x + 16 + RING_PLAN_R + 8, top + 8 + RING_PLAN_R + 8)

	var melee: Array = snap.get("melee", [])
	var holders: Array = snap.get("holders", [])
	var slots: Dictionary = snap.get("slots", {})
	# Scale so the widest ring in the pack fills the plan view. One scale for every body, or the
	# brute's 6.08 m and the swordsman's 3.24 m would draw the same size and the whole point of
	# per-body radii would be invisible.
	var widest := 1.0
	for m in melee:
		if is_instance_valid(m):
			widest = maxf(widest, p.global_position.distance_to((m as Node3D).global_position))
			var sp: Vector3 = slots.get(String(m.name), Vector3.INF)
			if sp != Vector3.INF:
				widest = maxf(widest, p.global_position.distance_to(sp))
	var scale := RING_PLAN_R / maxf(widest, 0.1)

	# The distinct slot radii, one dashed arc each.
	var drawn: Array[float] = []
	for m in melee:
		var sp: Vector3 = slots.get(String(m.name), Vector3.INF)
		if sp == Vector3.INF:
			continue
		var rad: float = p.global_position.distance_to(sp)
		var seen := false
		for d in drawn:
			if absf(d - rad) < 0.05:
				seen = true
		if seen:
			continue
		drawn.append(rad)
		for k in 24:
			if k % 2 == 1:
				continue
			var a0: float = TAU * float(k) / 24.0
			var a1: float = TAU * float(k + 1) / 24.0
			_panel.draw_line(c + Vector2(cos(a0), sin(a0)) * rad * scale,
					c + Vector2(cos(a1), sin(a1)) * rad * scale, COL_DIM * Color(1, 1, 1, 0.4), 1.0)
	# The target itself.
	_panel.draw_line(c - Vector2(3, 0), c + Vector2(3, 0), COL_TEXT, 1.0)
	_panel.draw_line(c - Vector2(0, 3), c + Vector2(0, 3), COL_TEXT, 1.0)

	for m in melee:
		if not is_instance_valid(m):
			continue
		var body := m as Node3D
		var here := c + Vector2(body.global_position.x - p.global_position.x,
				body.global_position.z - p.global_position.z) * scale
		var col: Color = COL_FLASH if holders.has(m) else COL_DIM
		if m == e:
			col = COL_LIVE
		var sp: Vector3 = slots.get(String(m.name), Vector3.INF)
		if sp != Vector3.INF:
			var told := c + Vector2(sp.x - p.global_position.x, sp.z - p.global_position.z) * scale
			_panel.draw_line(told, here, col * Color(1, 1, 1, 0.45), 1.0)
			_panel.draw_circle(told, 3.0, col)
		_panel.draw_arc(here, 3.5, 0, TAU, 10, col, 1.5)
	for m in snap.get("ranged", []):
		if not is_instance_valid(m):
			continue
		var body2 := m as Node3D
		var here2 := c + Vector2(body2.global_position.x - p.global_position.x,
				body2.global_position.z - p.global_position.z) * scale
		_panel.draw_arc(here2, 3.5, 0, TAU, 10, COL_FAR, 1.5)

	var tx := o.x + 16 + RING_PLAN_R * 2 + 26
	var ty := top + 26
	var held := PackedStringArray()
	for h in holders:
		if is_instance_valid(h):
			held.append(String(h.name))
	var mine: Vector3 = slots.get(String(e.name), Vector3.INF)
	var lines := [
		"tokens %d/%d   %s" % [holders.size(), int(snap.get("cap", 0)),
				("turn: " + ", ".join(held)) if held.size() > 0 else "nobody swinging"],
		"pack %d melee + %d ranged   reslot %.1fs" % [melee.size(),
				snap.get("ranged", []).size(), float(snap.get("next_assign", 0.0))],
		"turns %d granted / %d unspent / %d leaked" % [int(snap.get("turns_granted", 0)),
				int(snap.get("approach_reclaims", 0)), int(snap.get("leak_reclaims", 0))],
		("this one: %s, %.1f m off its slot" % ["ITS TURN" if holders.has(e) else "waiting",
				Vector2(e.global_position.x - mine.x, e.global_position.z - mine.z).length()])
				if mine != Vector3.INF else "this one: not slotted",
	]
	for ln in lines:
		_panel.draw_string(font, Vector2(tx, ty), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT)
		ty += 15.0


func _lock_is(e: Node) -> bool:
	var rig := get_tree().get_first_node_in_group("camera_rig")
	return rig != null and rig.has_method("locked") and rig.locked() == e


## THE RULER — every band the AI's choices key off, as one horizontal strip with the player's
## live distance as a cursor. For a RANGED enemy the strip IS _chase_ranged's three answers
## (kite / hold / advance, the same thresholds that pick the shot); for the ogre it is kick +
## strike + aggro read off the solver; for plain melee, attack range and aggro.
func _draw_bands(font: Font, e: Node3D, at: Vector2) -> void:
	var w := PANEL_W - 32.0
	var h := 12.0
	var aggro := float(e.get("aggro_range"))
	if aggro <= 0.0:
		return
	var segs: Array = []          # [from_m, to_m, colour, label]
	var solver: Node = e.get("_solver")
	if solver != null:
		var sz: Vector2 = solver.call("strike_zone")
		var kz: Vector2 = solver.call("kick_zone")
		segs = [[0.0, kz.y, COL_NEAR, "kick"], [sz.x, sz.y, COL_MID, "strike"],
				[sz.y, aggro, COL_FAR, "approach"]]
	elif int(e.get("attack_kind")) == 1:
		var pref := float(e.get("preferred_range"))
		segs = [[0.0, pref * 0.7, COL_NEAR, "NEAR kite+fan"],
				[pref * 0.7, pref, COL_MID, "HOLD aim"],
				[pref, aggro, COL_FAR, "FAR advance+lob"]]
	else:
		segs = [[0.0, float(e.get("attack_range")), COL_MID, "melee"],
				[float(e.get("attack_range")), aggro, COL_FAR, "chase"]]
	for s in segs:
		var x0: float = at.x + w * clampf(float(s[0]) / aggro, 0.0, 1.0)
		var x1: float = at.x + w * clampf(float(s[1]) / aggro, 0.0, 1.0)
		var c: Color = s[2]
		_panel.draw_rect(Rect2(Vector2(x0, at.y), Vector2(maxf(x1 - x0, 1.0), h)),
				Color(c.r, c.g, c.b, 0.55))
		_panel.draw_string(font, Vector2(x0 + 2, at.y + h + 12), String(s[3]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c)
	# The player, ON the ruler. This cursor crossing a boundary is the exact moment the AI's
	# answer changes — watching it sit on a line explains most "why does it dither" reports.
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		var d := Vector2(p.global_position.x - e.global_position.x,
				p.global_position.z - e.global_position.z).length()
		var cx: float = at.x + w * clampf(d / aggro, 0.0, 1.0)
		_panel.draw_rect(Rect2(Vector2(cx - 1.5, at.y - 5), Vector2(3, h + 10)), COL_TEXT)
		_panel.draw_string(font, Vector2(cx - 14, at.y - 8), "%.1fm" % d,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TEXT)


func _arrow(a: Vector2, b: Vector2, c: Color, wide: float) -> void:
	var dir := (b - a).normalized()
	var from := a + dir * NODE_R
	var to := b - dir * NODE_R
	# Paired transitions (CHASE<->IDLE etc.) bow apart so their arrows do not overlap.
	var side := Vector2(-dir.y, dir.x) * 6.0
	from += side
	to += side
	_panel.draw_line(from, to, c, wide)
	var tip := to
	_panel.draw_line(tip, tip - dir.rotated(0.5) * 8.0, c, wide)
	_panel.draw_line(tip, tip - dir.rotated(-0.5) * 8.0, c, wide)

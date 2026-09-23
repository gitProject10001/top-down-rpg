extends Node
## Autoload "Hud" — the in-game HUD, bottom-left (per the user's sketch):
##   ▲▲▲▲          arrow quiver (one chevron per arrow left)
##   ■ ■ ■ ■ ■     health blocks (Death's-Door-style chunks)
##   ▬▬▬▬▬▬        shield stamina bar (drains while guarding, refills after)
##
## Built in code (same doctrine as Dialogue): one CanvasLayer, zero per-scene setup. Values are
## POLLED from the player each frame — a handful of rects, cheap, and no signal plumbing to keep
## in sync. Hidden during dialogue (the portrait occupies the same corner).

const ACCENT := Color(1.0, 0.82, 0.5)          # warm gold (project palette)
const HP_FULL := Color(0.85, 0.28, 0.24)       # health block, filled
const HP_EMPTY := Color(0.22, 0.12, 0.12, 0.8) # health block, lost
const STAMINA := Color(0.4, 0.72, 0.95)        # shield stamina (the "blue")
const GUARD_LIT := Color(1.0, 0.86, 0.55)      # where YOUR guard is pointing
const GUARD_DIM := Color(1.0, 1.0, 1.0, 0.16)  # the three directions you are not covering
const THREAT := Color(0.95, 0.35, 0.28)        # where THEIR wind-up is aimed

var _root: Control
var _arrow_box: HBoxContainer
var _hp_box: HBoxContainer
var _stam_fill: ColorRect
var _stam_width := 148.0

var _player: Node
var _arrow_labels: Array[Label] = []
var _hp_rects: Array[ColorRect] = []
var _suppressed := false

var _traits_box: HBoxContainer
var _trait_labels: Array[Label] = []
var _tool_lbl: Label
var _cd_fill: ColorRect

# THE GUARD DIAL. Four segments around a centre, bottom-middle of the screen.
#
# WHY IT IS NOT OPTIONAL. A directional fight is a reading contest, and neither half of the read
# is legible from the 3D scene alone: your own guard is a small change in how one arm is held, and
# their wind-up is an animation you have a third of a second to identify. Mount & Blade draws
# exactly this for exactly this reason. Gold says where you are covered, red says where the blow
# is coming from, and the whole thing hides itself the moment neither is true — so every scene
# that does not use the mechanic never sees it.
var _dial: Control
var _dial_rects: Array[ColorRect] = []         # indexed by SwingDir


## Hide the HUD for something that FREEZES THE TREE. Dialogue can be polled from _process because
## the world keeps running through a conversation; a full-screen pause cannot — this node stops
## processing the instant the map takes its hold, so the last thing _process did was make the HUD
## visible, and it would stay that way until the tree resumes. Push, don't poll.
func suppress(on: bool) -> void:
	_suppressed = on
	if _root:
		_root.visible = not Dialogue.active and not on


const BOSS_W := 460.0
const BOSS_FULL := Color(0.80, 0.24, 0.22)
const BOSS_LOW := Color(0.95, 0.55, 0.15)
var _boss_root: Control
var _boss_fill: ColorRect
var _boss_name: Label
var _boss_seen := 0.0

var _vignette: TextureRect          ## the red damage breath at the screen edges

## THE FRAME-RATE READOUT — top-right, in every scene (it does not wait for a player): the
## engine's own counter (`Engine.get_frames_per_second`, what the editor's "Display FPS" shows)
## and the frame time from the Performance monitor, refreshed four times a second so the digits
## are readable. F3 toggles it.
var _fps_lbl: Label
var _fps_clock := 0.0
var _vignette_tween: Tween
var _wired_health: Node = null      ## whose Health.damaged the vignette currently listens to


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20                            # grade 10 · HUD 20 · dialogue 25 · map 28 · pause 30
	add_child(layer)

	# THE DAMAGE VIGNETTE — a red radial breath at the screen edges when the player's hp drops.
	# Added FIRST so every widget draws over it, and hung off the CanvasLayer rather than _root:
	# _root's visibility answers dialogue/suppression, and a hit taken mid-conversation should
	# still read (the hp it reports is real). Fed by the player's own Health.damaged signal —
	# the same convergence point the body flash and the thud use — wired lazily in _process
	# because the player is found by polling, not injection.
	_vignette = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.12, 0.1, 0.0))
	grad.set_color(1, Color(0.9, 0.12, 0.1, 0.75))
	grad.add_point(0.55, Color(0.9, 0.12, 0.1, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 0.0)
	gtex.width = 256
	gtex.height = 256
	_vignette.texture = gtex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	layer.add_child(_vignette)

	_fps_lbl = Label.new()
	_fps_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_lbl.position = Vector2(-16, 12)
	_fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_lbl.add_theme_font_size_override("font_size", 15)
	_fps_lbl.add_theme_color_override("font_color", ACCENT)
	_fps_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_fps_lbl.add_theme_constant_override("outline_size", 4)
	_fps_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_lbl.text = "-- fps"
	layer.add_child(_fps_lbl)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# Tucked into the bottom-left corner. The offset is the stack's HEIGHT, so it grew when the
	# characteristics row, the tool name and its cooldown bar were added — at the old -132 the tool
	# label sat half off the bottom of the screen and the cooldown bar was entirely gone.
	_root.position = Vector2(28, -214)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)
	_build_boss_bar(layer)
	_build_guard_dial(layer)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_root.add_child(vb)

	_arrow_box = HBoxContainer.new()
	_arrow_box.add_theme_constant_override("separation", 4)
	vb.add_child(_arrow_box)

	_hp_box = HBoxContainer.new()
	_hp_box.add_theme_constant_override("separation", 6)
	vb.add_child(_hp_box)

	var stam_back := ColorRect.new()
	stam_back.color = Color(0.08, 0.09, 0.12, 0.85)
	stam_back.custom_minimum_size = Vector2(_stam_width + 4, 12)
	vb.add_child(stam_back)

	_stam_fill = ColorRect.new()
	_stam_fill.color = STAMINA
	_stam_fill.position = Vector2(2, 2)
	_stam_fill.size = Vector2(_stam_width, 8)
	stam_back.add_child(_stam_fill)

	# The characteristic sheet, four pips wide. Values, not bars: these are small integers that
	# change a handful of times per session, and a bar would imply a continuum they do not have.
	_traits_box = HBoxContainer.new()
	_traits_box.add_theme_constant_override("separation", 10)
	vb.add_child(_traits_box)

	_tool_lbl = Label.new()
	_tool_lbl.add_theme_font_size_override("font_size", 15)
	vb.add_child(_tool_lbl)

	var cd_back := ColorRect.new()
	cd_back.color = Color(0.08, 0.09, 0.12, 0.85)
	cd_back.custom_minimum_size = Vector2(_stam_width + 4, 6)
	vb.add_child(cd_back)
	_cd_fill = ColorRect.new()
	_cd_fill.position = Vector2(2, 1)
	_cd_fill.size = Vector2(_stam_width, 4)
	cd_back.add_child(_cd_fill)


## Four bars around a gap: up and down are tall, left and right are wide, so the shape says which
## is which without a label. Sized for the pixel-art scenes, where the whole frame is 450 rows.
func _build_guard_dial(layer: CanvasLayer) -> void:
	_dial = Control.new()
	_dial.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dial.position = Vector2(0, -132)
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dial.visible = false
	layer.add_child(_dial)
	# offset from centre, then size — one entry per SwingDir, in its enum order
	var spec := [
		[Vector2(-5, -40), Vector2(10, 26)],   # UP
		[Vector2(-5, 14), Vector2(10, 26)],    # DOWN
		[Vector2(-40, -5), Vector2(26, 10)],   # LEFT
		[Vector2(14, -5), Vector2(26, 10)],    # RIGHT
	]
	for e in spec:
		var r := ColorRect.new()
		r.position = e[0]
		r.size = e[1]
		r.color = GUARD_DIM
		_dial.add_child(r)
		_dial_rects.append(r)


## Gold for your guard, red for their wind-up, and red wins when they coincide — the one thing you
## must not miss is the blow you are not covering.
func _update_guard_dial() -> void:
	if _dial != null and _player != null and not _player.has_node("StateMachine/DirAttack"):
		_dial.hide()
		return
	if _dial == null:
		return
	var mine := SwingDir.NONE
	if _player.has_method("current_guard_dir"):
		mine = _player.current_guard_dir()
	if mine == SwingDir.NONE and _player.has_method("charging_dir"):
		mine = _player.charging_dir()
	var threat := SwingDir.mirror(_incoming_dir())
	var intent: Node = _player.get("intent")
	if intent and intent.has_method("screen_direction"):
		mine = intent.screen_direction(mine)
		threat = intent.screen_direction(threat)
	_dial.visible = _root.visible and (mine != SwingDir.NONE or threat != SwingDir.NONE)
	if not _dial.visible:
		return
	for i in _dial_rects.size():
		var c := GUARD_DIM
		if i == mine:
			c = GUARD_LIT
		# THE MIRROR, applied once, here, for display only: a swing thrown from their left arrives
		# on your right, and the dial has to agree with the guard that actually stops it. See
		# SwingDir's header — guard.gd applies the same flip when it resolves the hit.
		if threat != SwingDir.NONE and i == threat:
			c = THREAT
		_dial_rects[i].color = c


## The nearest enemy that is winding a directional swing up, if any.
func _incoming_dir() -> int:
	var best := SwingDir.NONE
	var best_d := INF
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e) or not e.has_method("charging_dir"):
			continue
		var d: int = e.charging_dir()
		if d == SwingDir.NONE:
			continue
		var dist: float = e.global_position.distance_to((_player as Node3D).global_position)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F3:
		_fps_lbl.visible = not _fps_lbl.visible


func _process(delta: float) -> void:
	_fps_clock += delta
	if _fps_clock >= 0.25 and _fps_lbl.visible:
		_fps_clock = 0.0
		var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_fps_lbl.text = "%d fps · %.1f ms" % [Engine.get_frames_per_second(), ms]
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			_root.visible = false
			if _dial:
				_dial.visible = false
			_update_boss()
			return
	_wire_vignette()
	_root.visible = not Dialogue.active and not _suppressed
	_update_boss()

	# health blocks (rebuild only when max changes)
	var hp: int = _player.health.hp
	var max_hp: int = _player.health.max_hp
	if _hp_rects.size() != max_hp:
		for c in _hp_box.get_children():
			c.queue_free()
		_hp_rects.clear()
		for i in max_hp:
			var r := ColorRect.new()
			r.custom_minimum_size = Vector2(24, 24)
			_hp_box.add_child(r)
			_hp_rects.append(r)
	for i in _hp_rects.size():
		_hp_rects[i].color = HP_FULL if i < hp else HP_EMPTY

	# arrow chevrons (rebuild only when max changes)
	var max_arrows: int = _player.max_arrows
	if _arrow_labels.size() != max_arrows:
		for c in _arrow_box.get_children():
			c.queue_free()
		_arrow_labels.clear()
		for i in max_arrows:
			var l := Label.new()
			l.text = "▲"
			l.add_theme_font_size_override("font_size", 18)
			_arrow_box.add_child(l)
			_arrow_labels.append(l)
	var arrows: int = _player.arrows
	for i in _arrow_labels.size():
		_arrow_labels[i].add_theme_color_override("font_color",
				ACCENT if i < arrows else Color(0.3, 0.28, 0.25, 0.7))

	# shield stamina
	var frac: float = clampf(_player.stamina / _player.max_stamina, 0.0, 1.0)
	_stam_fill.size.x = _stam_width * frac
	_stam_fill.color = STAMINA if frac > 0.16 else Color(0.9, 0.4, 0.3)   # warn when nearly broken

	_update_traits()
	_update_tool()
	_update_guard_dial()


## Subscribe the vignette to the CURRENT player's Health — re-wired whenever the polled player
## changes (scene reloads swap the node under us; a stale connection dies with its Health).
func _wire_vignette() -> void:
	var h: Node = _player.health
	if h == _wired_health or h == null:
		return
	_wired_health = h
	h.damaged.connect(func(_a, _s): _pulse_vignette())


func _pulse_vignette() -> void:
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette.modulate.a = 1.0
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "modulate:a", 0.0, 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The four characteristics and the Insight you have banked. Polled like everything else here —
## a handful of labels is cheaper than keeping five signal connections in sync.
func _update_traits() -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits == null:
		return
	if _trait_labels.size() != 5:
		for c in _traits_box.get_children():
			c.queue_free()
		_trait_labels.clear()
		for i in 5:
			var l := Label.new()
			l.add_theme_font_size_override("font_size", 15)
			_traits_box.add_child(l)
			_trait_labels.append(l)
	for i in 4:
		# First letter only. The full names do not fit beside the health blocks, and after one
		# conversation with Maren the player knows which letter is which.
		_trait_labels[i].text = "%s %d" % [String(traits.ATTR_NAMES[i]).substr(0, 1), traits.attr(i)]
		_trait_labels[i].add_theme_color_override("font_color", traits.ATTR_COLORS[i])
	# Insight shows the RUN's take alongside the bank, because the run's take is the number you are
	# gambling every time you push one room further.
	var run := get_node_or_null("/root/Run")
	var pending: int = traits.run_insight if (run and run.in_run) else 0
	_trait_labels[4].text = "◆ %d" % traits.insight if pending == 0 \
			else "◆ %d (+%d)" % [traits.insight, pending]
	_trait_labels[4].add_theme_color_override("font_color", ACCENT)


func _update_tool() -> void:
	var belt = _player.get("tool_belt")
	if belt == null:
		_tool_lbl.text = ""
		_cd_fill.size.x = 0.0
		return
	var tool = belt.active_tool()
	if tool == null:
		_tool_lbl.text = ""
		_cd_fill.size.x = 0.0
		return
	var held: int = belt.carried().size()
	_tool_lbl.text = "Q  %s%s" % [tool.tool_name, "   [Tab]" if held > 1 else ""]
	_tool_lbl.add_theme_color_override("font_color", tool.tint)
	# Drains left-to-right as it comes back, so "full bar" always means ready.
	_cd_fill.size.x = _stam_width * (1.0 - tool.cooldown_frac())
	_cd_fill.color = tool.tint


## THE BOSS BAR. Top centre, and only while there is a boss alive to describe.
##
## Not decoration. A fight with no readout of progress reads as a fight that is not going anywhere,
## and "damage sponge" is a feeling a player gets from not being able to see the end — it is not a
## fact about the health value. The ogre has 34 hit points and the player deals about 1.16 a swing;
## without a bar those thirty swings are indistinguishable from a hundred.
##
## Polled, like the rest of this file. `Health.changed` is emitted by every entity in the game and
## has never been connected to anything, but a poll cannot go stale when a boss dies mid-signal and
## it matches how the player's own blocks are drawn two metres above.
func _build_boss_bar(layer: CanvasLayer) -> void:
	_boss_root = Control.new()
	# ANCHORS AND OFFSETS, not a preset plus a position. set_anchors_preset writes the offsets as
	# well, so assigning `position` afterwards is overwritten the next time the Control lays itself
	# out -- the bar was built, was visible, and sat at zero size off the corner of the screen.
	_boss_root.anchor_left = 0.5
	_boss_root.anchor_right = 0.5
	_boss_root.offset_left = -BOSS_W * 0.5
	_boss_root.offset_right = BOSS_W * 0.5
	_boss_root.offset_top = 26.0
	_boss_root.offset_bottom = 42.0
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_root.visible = false
	layer.add_child(_boss_root)

	var back := ColorRect.new()
	back.size = Vector2(BOSS_W, 16.0)
	back.color = Color(0.10, 0.06, 0.07, 0.85)
	_boss_root.add_child(back)

	_boss_fill = ColorRect.new()
	_boss_fill.size = Vector2(BOSS_W, 16.0)
	_boss_fill.color = BOSS_FULL
	_boss_root.add_child(_boss_fill)

	_boss_name = Label.new()
	_boss_name.position = Vector2(0.0, -20.0)
	_boss_name.size = Vector2(BOSS_W, 18.0)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_color_override("font_color", Color(0.92, 0.88, 0.84))
	_boss_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_boss_name.add_theme_constant_override("outline_size", 4)
	_boss_root.add_child(_boss_name)


func _update_boss() -> void:
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss == null or not is_instance_valid(boss):
		_boss_root.visible = false
		_boss_seen = 0.0
		return
	var h: Node = boss.get_node_or_null("Health")
	if h == null or not bool(h.call("is_alive")):
		_boss_root.visible = false
		return
	var hp := float(h.get("hp"))
	var mx := maxf(float(h.get("max_hp")), 1.0)
	_boss_root.visible = true
	_boss_name.text = str(boss.name).to_upper()
	# FILLS ON FIRST SIGHT rather than snapping to full. The bar arriving is itself a beat -- it is
	# the moment the fight announces how big it is, and it costs one lerp.
	_boss_seen = minf(_boss_seen + get_process_delta_time() * 1.6, 1.0)
	var frac: float = (hp / mx) * ease(_boss_seen, 0.4)
	_boss_fill.size.x = BOSS_W * clampf(frac, 0.0, 1.0)
	_boss_fill.color = BOSS_LOW if hp <= mx * 0.3 else BOSS_FULL

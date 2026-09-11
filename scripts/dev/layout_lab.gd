extends Control
## THE GENERATION BENCH: the crypt's rules drawn as a schematic, so they can be read instead of
## reasoned about.
##
##   Godot_v4.6.3-stable_win64_console.exe --path . res://scenes/dev/layout_lab.tscn
##
## WHY THIS EXISTS ALONGSIDE scripts/dev/crypt_tuner.gd. That one builds a real, playable dungeon
## and answers "how does it LOOK" — it costs a full build, a VoxelGI bake and several seconds per
## seed, which is the right price for judging fog density and wrong for judging a placement rule.
## This one answers "how does it WORK". DungeonLayout, RoomShape and RoomPlan are pure data with no
## nodes and no art, so a seed costs microseconds: you can hold the arrow key down and watch the
## rules fire.
##
## It is also NOT scripts/dungeon/tests/verify_dungeon.gd. That asserts an exit code — "is this
## allowed to ship". This shows a distribution — "what should I change". A suite tells you the
## floor-fraction check passes; the batch pane tells you the mean is 0.56 and the threshold is doing
## all the work.
##
## THREE VIEWS AND A BATCH:
##   LAYOUT  the whole dungeon, one floor at a time. Cell blocks by room type, passages by EdgeType.
##   ROOM    one room's 4 m tile grid: the surviving cross, the carved bites, the wall segments
##           RoomShape.walls() emits, every planned slot and every spawn.
##   BUILD   the REAL zone, built and flown through, with the schematic's vocabulary projected onto
##           it — room type, module, and every planned enemy where it will actually stand. This is
##           the view that answers what the numbers feel like at 1:1; the schematics answer what the
##           rules decided. Lazy: nothing 3D is loaded until you ask for it.
##   BATCH   N seeds run head-down, reported as statistics rather than as a picture.
##
## KEYS   left/right = seed -1/+1   [ ] = floor   R = reroll   TAB = cycle views   B = batch
##        G = rebuild the 3D at the current seed
##        click a room in LAYOUT to open it in ROOM;  in BUILD, RMB+WASD to fly
##
## NO class_name, deliberately — see the note at the top of tuning_panel.gd. Registering a global
## class forces an editor rescan, and a rescan is what re-saved a tuned .tres over itself last cycle.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")

const PANEL_W := 320
## Left margin for the drawing area. NOT PANEL_W: build_panel adds its own 12 px offset, 16 px of
## content margin and a scrollbar on top of the width it is given, and the panel draws on a
## CanvasLayer ABOVE this Control — so a gutter of exactly PANEL_W silently eats the first three
## characters of every HUD line rather than overlapping visibly.
const GUTTER := PANEL_W + 64.0
const MARGIN := 28.0

enum View { LAYOUT, ROOM, BUILD, ASSEMBLY }

## BUILD view only. The zone is the game's own, not a stand-in — a bench that builds its own
## approximation of a dungeon is a bench that agrees with itself and nothing else.
const ZONE := "res://scenes/world/zone_crypt.tscn"
const MAIN := "res://scenes/main.tscn"
const THEME := "res://scenes/dungeon/themes/crypt.tres"

const TYPE_NAME := ["START", "COMBAT", "BOSS", "TREASURE", "STAIR"]
const TYPE_COLOR: Array[Color] = [
	Color(0.30, 0.62, 0.38),      # START
	Color(0.30, 0.31, 0.36),      # COMBAT
	Color(0.62, 0.26, 0.26),      # BOSS
	Color(0.66, 0.55, 0.24),      # TREASURE
	Color(0.27, 0.44, 0.64),      # STAIR
]

const EDGE_NAME := ["DOOR", "CORRIDOR", "STAIR", "LOCKED", "SHORTCUT", "SECRET"]
const EDGE_COLOR: Array[Color] = [
	Color(0.55, 0.55, 0.60),      # DOOR
	Color(0.72, 0.72, 0.78),      # CORRIDOR
	Color(0.45, 0.68, 0.95),      # STAIR
	Color(0.95, 0.35, 0.32),      # LOCKED
	Color(0.45, 0.85, 0.55),      # SHORTCUT
	Color(0.75, 0.50, 0.92),      # SECRET
]

const INK := Color(0.86, 0.86, 0.90)
const DIM := Color(0.50, 0.50, 0.56)
const WARN := Color(0.98, 0.45, 0.40)

# --- generation parameters, all live --------------------------------------------------------
var _seed := 42
var _room_count := 9
var _stair_count := 1
var _loop_count := 2
var _batch_n := 200

# --- current state --------------------------------------------------------------------------
var _lay: DungeonLayout
var _floor := 0
var _view: int = View.LAYOUT
var _picked: Vector3i = Vector3i.ZERO       ## anchor of the room open in ROOM view
var _has_pick := false

## Cached plan for the picked room. Rebuilt only when the pick or the seed changes — plan_interior
## is cheap but not free, and _draw runs on every mouse move.
var _ctx: RoomContext
var _rd: DungeonLayout.RoomData
var _shapes: Dictionary = {}                ## anchor -> RoomShape, for the schematic's tile fill

## Screen rects of every room drawn this frame, for click picking. Rebuilt by _draw because that is
## the only place the world->screen transform is known.
var _hit: Array = []                        ## [{rect: Rect2, anchor: Vector3i}]

var _seed_line: Label
var _stat_line: Label
var _pane: RichTextLabel
var _view_opt: OptionButton
var _font: Font

# --- BUILD view -----------------------------------------------------------------------------
var _subject: Node3D                        ## parent of the built zone
var _cam: FlyCamera
var _zone: Node3D
var _zone_seed := -1                        ## which seed the standing zone was built from
var _reveal := true                         ## override show_around(), which hides all but 3 rooms
var _labels := true
var _legend := true

## How BUILD renders. LIT is the game. The other two exist because the crypt is DARK by design — a
## black room is the right answer to "how does it look" and the wrong answer to "what shape is it",
## which is the question this bench is for.
enum Render { LIT, UNSHADED, BY_TYPE }
var _render: int = Render.LIT
## MeshInstance3D -> the material_override it had before BY_TYPE replaced it. Saving is not optional:
## Kit.dress() hangs the THEME MATERIAL on every piece as a material_override, so clearing to null
## would strip the dungeon's whole surface treatment and there would be nothing to put back.
var _saved_mats := {}
var _type_mats := {}
var _render_opt: OptionButton
var _gi_probe: Node3D
var _gi_follow := true


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# PASS, not the default STOP. STOP makes this Control swallow every mouse event it receives, so
	# FlyCamera's right-drag look never reached _unhandled_input and the 3D camera was stuck at
	# whatever angle _build_3d pointed it — which does not read as "look is broken", it reads as
	# "W and S zoom and A and D pan", because a camera pitched 52 degrees down moves mostly downward
	# when it moves forward. PASS still delivers _gui_input (room picking below), but anything that
	# handler does not accept_event() carries on to the camera.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	_regen()

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--selftest="):
			_selftest(a.trim_prefix("--selftest="))
			return


# ---------------------------------------------------------------- the panel -----------------

func _build_ui() -> void:
	var box := Tuning.build_panel(self, PANEL_W, 780)

	Tuning.header(box, "SEED")
	_seed_line = Tuning.line(box, "", INK)
	var row := HBoxContainer.new()
	box.add_child(row)
	for spec in [["<", -1], [">", 1]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.custom_minimum_size = Vector2(40, 0)
		var step: int = spec[1]
		b.pressed.connect(func() -> void:
			_seed = maxi(1, _seed + step)
			_regen())
		row.add_child(b)
	var reroll := Button.new()
	reroll.text = "reroll"
	reroll.pressed.connect(func() -> void:
		_seed = randi() % 1000000 + 1
		_regen())
	row.add_child(reroll)
	Tuning.number(box, "seed", _seed, 1.0, func(v: float) -> void:
		_seed = maxi(1, int(v))
		_regen())

	Tuning.header(box, "LAYOUT PARAMETERS")
	Tuning.slider(box, "room_count", 3, 24, 1, _room_count, func(v: float) -> void:
		_room_count = int(v)
		_regen())
	Tuning.slider(box, "stair_count", 0, 4, 1, _stair_count, func(v: float) -> void:
		_stair_count = int(v)
		_regen())
	Tuning.slider(box, "loop_count", 0, 6, 1, _loop_count, func(v: float) -> void:
		_loop_count = int(v)
		_regen())

	Tuning.header(box, "VIEW")
	_view_opt = Tuning.option(box, "", PackedStringArray(["LAYOUT", "ROOM", "BUILD (3D)", "ASSEMBLY"]), 0,
			func(i: int) -> void: _set_view(i))
	Tuning.button(box, "floor -", func() -> void:
		_floor -= 1
		queue_redraw())
	Tuning.button(box, "floor +", func() -> void:
		_floor += 1
		queue_redraw())
	_stat_line = Tuning.line(box, "", DIM)

	Tuning.header(box, "BUILD (3D)")
	Tuning.button(box, "rebuild at this seed  [G]", func() -> void: _build_3d())
	_render_opt = Tuning.option(box, "shading", PackedStringArray(
			["lit (the game)", "unshaded", "flat colour by room type"]), 0,
			func(i: int) -> void: _set_render(i))
	Tuning.check(box, "VoxelGI follows camera", _gi_follow, func(on: bool) -> void:
		_gi_follow = on
		queue_redraw())
	Tuning.check(box, "reveal every room", _reveal, func(on: bool) -> void:
		_reveal = on
		_apply_reveal())
	Tuning.check(box, "room + spawn labels", _labels, func(on: bool) -> void:
		_labels = on
		queue_redraw())
	Tuning.check(box, "legend  [L]", _legend, func(on: bool) -> void:
		_legend = on
		queue_redraw())

	Tuning.header(box, "ASSEMBLY")
	Tuning.button(box, "build the picked room  [V]", func() -> void:
		_set_view(View.ASSEMBLY)
		_asm_build())
	var arow := HBoxContainer.new()
	box.add_child(arow)
	for spec in [["|<", -99], ["< back", -1], ["step >", 1], [">|", 99]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var d: int = spec[1]
		b.pressed.connect(func() -> void:
			_asm_playing = false
			_asm_go(_asm_step + d))
		arow.add_child(b)
	Tuning.button(box, "play / pause  [space]", func() -> void:
		if _asm_step >= STAGES.size() - 1:
			_asm_go(0)
		_asm_playing = not _asm_playing
		_asm_clock = 0.0
		queue_redraw())
	Tuning.slider(box, "seconds per step", 0.15, 3.0, 0.05, _asm_speed, func(v: float) -> void:
		_asm_speed = v)

	Tuning.header(box, "BATCH")
	Tuning.slider(box, "seeds", 20, 1000, 10, _batch_n, func(v: float) -> void:
		_batch_n = int(v))
	Tuning.button(box, "run batch", func() -> void: _batch(_batch_n))
	_pane = Tuning.log_pane(box, 300)

	Tuning.header(box, "KEYS")
	Tuning.line(box, "left/right  seed -1 / +1", DIM)
	Tuning.line(box, "R reroll    TAB cycle views", DIM)
	Tuning.line(box, "[ ] floor   B batch   G rebuild", DIM)
	Tuning.line(box, "L legend    V assembly", DIM)
	Tuning.line(box, "WASD/QE fly (3D views) — never bind these", DIM)
	Tuning.line(box, "space play/pause   , . step", DIM)
	Tuning.line(box, "click a room to open it in ROOM", DIM)


## Only BUILD view needs a per-frame redraw, and only because its labels are projected through a
## camera that moves. The schematics redraw on change, which is why holding an arrow key to scrub
## seeds stays instant.
func _process(_delta: float) -> void:
	_asm_tick(_delta)
	if _view != View.BUILD:
		return
	if _gi_follow:
		_drive_gi()
	queue_redraw()


## Park the GI stand-in in the room UNDER the camera, not at the camera.
##
## RoomGI._room_of_player only accepts a point within half a floor height (4 m) of a room's origin,
## so a camera flying at 26 m is outside every room and the lookup returns null — which is
## indistinguishable from "no player" and leaves the GI wherever prime() left it. Dropping the probe
## to the floor of whichever room's footprint lies below the camera is what makes flying and lighting
## agree. Over the void between rooms nothing matches, the probe is left alone, and the last room to
## light stays lit rather than flickering off in a corridor.
func _drive_gi() -> void:
	if _gi_probe == null or _zone == null or not is_instance_valid(_zone):
		return
	# WHERE YOU ARE LOOKING, not where you are. The camera is pitched ~53 degrees, so at a great
	# hall's framing distance it sits 36 m back from the room it is aimed at and is inside no room
	# at all — the probe stayed put and the room being photographed was lit by its neighbour's
	# bounce. Casting the view ray down onto each candidate's floor plane asks the question that
	# actually matters.
	var eye := _cam.global_position
	var fwd := -_cam.global_transform.basis.z
	var best: DungeonRoom = null
	var best_t := INF
	for n in _zone.get_children():
		if not (n is DungeonRoom):
			continue
		var r := n as DungeonRoom
		var plane_y: float = r.global_position.y
		if absf(fwd.y) < 0.001:
			continue
		var t := (plane_y - eye.y) / fwd.y
		if t <= 0.0 or t >= best_t:
			continue                      # behind the lens, or further than one already found
		var hit := eye + fwd * t
		var d: Vector3 = hit - r.global_position
		if absf(d.x) <= r.footprint.x * 0.5 and absf(d.z) <= r.footprint.z * 0.5:
			best_t = t
			best = r
	if best != null:
		_gi_probe.global_position = best.global_position + Vector3(0.0, 1.0, 0.0)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		# physical_keycode, for the same reason FlyCamera uses is_physical_key_pressed: a keycode is
		# the key's LABEL under the current OS layout, so these shortcuts would land on different
		# keys on an AZERTY board than the ones the legend names.
		match (e as InputEventKey).physical_keycode:
			KEY_LEFT:
				_seed = maxi(1, _seed - 1)
				_regen()
			KEY_RIGHT:
				_seed += 1
				_regen()
			KEY_R:
				_seed = randi() % 1000000 + 1
				_regen()
			KEY_TAB:
				_set_view((_view + 1) % View.size())
			# V, NOT A. FlyCamera polls physical W/A/S/D/Q/E every frame, so A was bound twice: it
			# strafed the camera left AND rebuilt the assembly, and the rebuild's reframing put the
			# camera straight back where the strafe had just moved it from. That reads exactly as
			# "A rebuilds but will not fly, while D flies" — the flying was happening and being
			# undone 60 times a second. Nothing here may use WASDQE while the fly camera lives.
			KEY_V:
				_set_view(View.ASSEMBLY)
				_asm_build()
			KEY_SPACE:
				if _view == View.ASSEMBLY:
					if _asm_step >= STAGES.size() - 1:
						_asm_go(0)
					_asm_playing = not _asm_playing
					_asm_clock = 0.0
					queue_redraw()
			KEY_PERIOD:
				if _view == View.ASSEMBLY:
					_asm_playing = false
					_asm_go(_asm_step + 1)
			KEY_COMMA:
				if _view == View.ASSEMBLY:
					_asm_playing = false
					_asm_go(_asm_step - 1)
			KEY_G:
				_build_3d()
			KEY_L:
				_legend = not _legend
				queue_redraw()
			KEY_B:
				_batch(_batch_n)
			KEY_BRACKETLEFT:
				_floor -= 1
				queue_redraw()
			KEY_BRACKETRIGHT:
				_floor += 1
				queue_redraw()

## MOUSE GOES THROUGH _gui_input, NOT _unhandled_input. This Control is full-rect with the default
## MOUSE_FILTER_STOP, so it consumes mouse events before the unhandled pass ever runs — keys arrived
## and clicks silently did not, which reads as "picking is broken" rather than as an input-routing
## mistake. Keys stay in _unhandled_input above, because they need no focus and no hit test.
##
## The panel still gets its clicks first: it lives on CanvasLayer 40 and GUI input is offered
## front-to-back across layers.
func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton):
		return
	var mb := e as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _hit_test(mb.position):
		accept_event()


## Shared by the click handler and the selftest, so what the test proves is what the mouse does.
func _hit_test(at: Vector2) -> bool:
	for h in _hit:
		if (h.rect as Rect2).has_point(at):
			_pick(h.anchor)
			return true
	return false


# ---------------------------------------------------------------- generation ----------------

func _regen() -> void:
	_lay = DungeonLayout.generate(_seed, _room_count, _stair_count, _loop_count)
	_seed = _lay.seed_used
	_floor = 0
	# Keep the pick if that anchor still exists in the new layout; otherwise fall back to START, so
	# stepping the seed in ROOM view stays in ROOM view instead of bouncing back to the schematic.
	if not _lay.rooms.has(_picked):
		_has_pick = false
		for anchor: Vector3i in _lay.rooms:
			if (_lay.rooms[anchor] as DungeonLayout.RoomData).type == DungeonLayout.RoomType.START:
				_picked = anchor
				_has_pick = true
				break
	_plan_shapes()
	_plan_pick()
	if _seed_line != null:
		_seed_line.text = "seed %d   (crypt_tuner takes the same number)" % _seed
	queue_redraw()


func _pick(anchor: Vector3i) -> void:
	_picked = anchor
	_has_pick = true
	_plan_pick()
	_set_view(View.ROOM)


## The ONE place `_view` is written. Clicking a room jumps to ROOM view, and a dropdown still
## reading LAYOUT while the screen shows a tile grid is the kind of small lie that makes you doubt
## every other control on the panel.
func _set_view(v: int) -> void:
	_view = v
	if _view_opt != null and _view_opt.selected != v:
		_view_opt.select(v)
	# The fly camera polls WASD every frame, so leaving it running would drift the 3D view while you
	# are typing in a schematic. It is also the cheapest way to state that BUILD owns the camera.
	if _cam != null:
		_cam.set_process(_view == View.BUILD or _view == View.ASSEMBLY)
	# The two 3D views own the same rig and the same subject node, so one has to put its scene away
	# before the other stands its own up — otherwise a whole zone and a lone room occupy the same
	# origin and the assembly is buried inside the dungeon.
	if _view != View.ASSEMBLY:
		_asm_clear()
	if _view == View.ASSEMBLY:
		_stage_3d()
		if _zone != null and is_instance_valid(_zone):
			_subject.remove_child(_zone)
			_zone.queue_free()
			_zone = null
			_zone_seed = -1
		if _asm_room == null or not is_instance_valid(_asm_room):
			_asm_build()
	if _view == View.BUILD:
		# Lazy, and stale-checked: entering BUILD after scrubbing the seed should show THAT seed,
		# but scrubbing while already in BUILD must not rebuild on every keypress.
		if _zone == null or not is_instance_valid(_zone) or _zone_seed != _seed:
			_build_3d()
	queue_redraw()


# ---------------------------------------------------------------- BUILD (3D) ---------------
#
# The schematic answers "what did the rules decide". This answers "and what is that actually like to
# stand in" — how far apart the cover really is, whether a great hall reads as a hall or as a field,
# where the enemies wake up. Everything here is LAZY: the 3D staging costs a scene load and a build,
# and the two schematic views are the ones you scrub with the arrow keys.


## Create the 3D rig once. The environment is LIFTED from main.tscn rather than authored here,
## because a bench with its own hand-written Environment shows a look the game never ships.
##
## `duplicate(true)` is not optional and the reason is unobvious: DungeonGenerator._dim_world
## MUTATES whatever environment it finds in the `world_env` group, and main.tscn's is a shared
## cached sub-resource. Without the copy this bench would leave a blacked-out environment in the
## resource cache for every other scene opened afterwards.
func _stage_3d() -> void:
	if _subject != null:
		return
	_subject = Node3D.new()
	_subject.name = "Subject"
	add_child(_subject)

	var main := (load(MAIN) as PackedScene).instantiate()
	var src: Environment = null
	for n in _flatten(main):
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			src = (n as WorldEnvironment).environment
			break
	var we := WorldEnvironment.new()
	we.environment = src.duplicate(true) if src != null else Environment.new()
	we.add_to_group("world_env")            # DungeonGenerator._dim_world looks the group up
	add_child(we)
	main.free()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.add_to_group("sun")
	add_child(sun)

	_cam = FlyCamera.new()
	_cam.name = "FlyCam"
	_cam.speed = 16.0                       # rooms are 20 m across; the walking default crawls
	_cam.current = true
	add_child(_cam)

	# THE GI PROBE, and why the lit view needs one.
	#
	# RoomGI drives everything off `get_first_node_in_group("player")`: it bakes the room the player
	# is in and, crucially, `_only()`s that room so it is the ONLY VoxelGI contributing — which is
	# what keeps the crypt reading as torchlit rather than as one evenly bounced cave. A bench has
	# no player, so `_room_of_player` returns null, `_process` bails on its first line every tick,
	# and the lit view shows exactly what `prime()` left behind: the start room lit, its neighbours
	# baked but switched off, and everything else with no bounce at all. Flying somewhere and
	# judging how it looks would be judging a room the game never shows you.
	#
	# So the bench supplies a stand-in, handed to RoomGI through its `probe` property. It is NOT put
	# in the `player` group: eight other systems read that group and Hud dereferences `.health` on
	# whatever it finds, so a fake player is a fake player to all of them. A bare Node3D is also
	# deliberate — not being a PhysicsBody, it cannot trip DungeonRoom's Area3D trigger, so no doors
	# slam and no fight starts while you are looking around.
	_gi_probe = Node3D.new()
	_gi_probe.name = "GIProbe"
	add_child(_gi_probe)


## Free-then-await-then-add, and the ordering is load-bearing: DungeonGenerator._dim_world's
## re-entrancy guard protects ONE generator from applying twice, not TWO from overlapping. If the
## new zone's _ready runs before the old one's _exit_tree, the newcomer snapshots the already
## blacked-out environment and will later "restore" the crypt's void over everything.
## Re-entrancy is a real hazard here, not a theoretical one: this function awaits a frame between
## freeing and adding, and both a keypress and the view switch can call it. A second call landing in
## that gap adds a zone while the first is still mid-free — which is precisely the overlapping-
## generator case the free-then-await ordering exists to prevent.
var _building := false


func _build_3d() -> void:
	if _building:
		return
	_building = true
	_stage_3d()
	if _zone != null and is_instance_valid(_zone):
		_subject.remove_child(_zone)
		_zone.queue_free()
		_zone = null
		await get_tree().process_frame

	_zone = (load(ZONE) as PackedScene).instantiate() as Node3D
	_zone.set("dungeon_seed", _seed)
	_zone.set("room_count", _room_count)
	_zone.set("stair_count", _stair_count)
	_zone.set("loop_count", _loop_count)
	_subject.add_child(_zone)
	_zone_seed = _seed

	# The zone parks itself at (500, 0, 500) in its own _ready, so the camera has to follow it there
	# — otherwise you open 700 m away looking at the inside of the fog.
	# The generator builds RoomGI in its own _ready, so the hook can only be attached now.
	var gi := _zone.get_node_or_null("RoomGI")
	if gi != null:
		gi.probe = _gi_probe

	# Open on the GAME'S OWN framing, not a survey shot. CameraRig sits at (0, 12.5, 9.375) scaled by
	# the crypt's room_zoom of 1.15, which is ~53 degrees down — the only angle a player ever sees,
	# and the one every art decision has to be judged from. Opening 26 m up made the layout legible
	# and everything standing on the floor too small to judge.
	var start := _start_of(_zone)
	_cam.global_position = start + Vector3(0.0, 12.5, 9.375) * 1.15
	_cam.look_at(start, Vector3.UP)
	_apply_reveal()
	# The overrides are keyed to mesh instances that the rebuild just destroyed, so the table has to
	# be dropped rather than restored — restoring would write onto freed nodes.
	_saved_mats.clear()
	_apply_render()
	_building = false
	queue_redraw()


## show_around() draws the current room and its neighbours and hides the rest — right for the game,
## wrong for a fly-around, where the whole point is seeing the layout you just read in the schematic.
## Lighting every room at once is not what the game looks like, which is why it is a toggle and not
## the default behaviour of the bench.
func _apply_reveal() -> void:
	if _zone == null or not is_instance_valid(_zone):
		return
	for n in _flatten(_zone):
		if n is DungeonRoom:
			(n as Node3D).visible = true
			if _reveal:
				(n as DungeonRoom).set_lit(true)


## Flat shading, and flat shading COLOURED BY ROOM TYPE — the mode that makes the 3D and the
## schematic the same statement. A green room in BUILD is the green room in LAYOUT, so "where am I"
## stops needing the labels at all, and the silhouette of a carved room reads instantly because
## nothing is hidden in shadow.
##
## UNSHADED is the viewport's own debug draw, which shows real albedo with the lighting removed.
## BY_TYPE goes further and overrides the material, because albedo alone is still six shades of the
## same stone.
## The ONE place `_render` is written, for the same reason `_set_view` exists: a dropdown reading
## "lit (the game)" over a flat-shaded frame teaches you to distrust the panel.
func _set_render(mode: int) -> void:
	_render = mode
	if _render_opt != null and _render_opt.selected != mode:
		_render_opt.select(mode)
	_apply_render()
	queue_redraw()


func _apply_render() -> void:
	if _zone == null or not is_instance_valid(_zone):
		return
	var vp := get_viewport()
	vp.debug_draw = (Viewport.DEBUG_DRAW_UNSHADED if _render == Render.UNSHADED
			else Viewport.DEBUG_DRAW_DISABLED)

	# Always restore first, so switching between modes cannot layer one override over another.
	for mi in _saved_mats:
		if is_instance_valid(mi):
			(mi as GeometryInstance3D).material_override = _saved_mats[mi]
	_saved_mats.clear()
	if _render != Render.BY_TYPE:
		return

	for n in _flatten(_zone):
		if not (n is DungeonRoom):
			continue
		var rd: DungeonLayout.RoomData = _lay.rooms.get((n as DungeonRoom).cell) if _lay else null
		var mat := _type_mat(rd.type if rd != null else DungeonLayout.RoomType.COMBAT)
		# GeometryInstance3D, not MeshInstance3D: RoomDebris draws its pebbles and tufts through two
		# MultiMeshInstance3Ds per room, and leaving those lit speckles a flat room with the dark
		# scatter that flat shading was turned on to get rid of.
		for m in _flatten(n):
			if m is GeometryInstance3D:
				_saved_mats[m] = (m as GeometryInstance3D).material_override
				(m as GeometryInstance3D).material_override = mat


func _type_mat(type: int) -> StandardMaterial3D:
	if _type_mats.has(type):
		return _type_mats[type]
	var m := StandardMaterial3D.new()
	# The schematic's own palette, lifted a long way: those colours were chosen to sit behind white
	# label text on a dark panel, and at full strength a whole room of one is unreadable.
	m.albedo_color = TYPE_COLOR[type].lightened(0.35)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_type_mats[type] = m
	return m


func _start_of(zone: Node) -> Vector3:
	for n in _flatten(zone):
		if n is Marker3D and n.name == "SpawnA":
			return (n as Node3D).global_position
	return (zone as Node3D).position


func _flatten(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for c in root.get_children():
		out.append_array(_flatten(c))
	return out


## Labels floating over the real geometry. This is the half that makes the 3D view a BENCH rather
## than a screenshot: the schematic's vocabulary — room type, module, depth, the planned spawns —
## projected onto the thing it describes, so "great_hall at d2" and "this room is enormous and has
## four archers in it" are visibly the same statement.
func _draw_build() -> void:
	var y := MARGIN
	if _zone == null or not is_instance_valid(_zone):
		_text(Vector2(GUTTER, y), "building…", 15, DIM)
		return
	_text(Vector2(GUTTER, y), "BUILD   seed %d   RMB+WASD fly, Q/E down/up, shift x3"
			% _zone_seed, 15, INK)
	y += 18
	# LIVE CAMERA STATE, because "look does not work" and "look works and I am pointed at a wall"
	# look identical from the outside. `look` flipping to ON when you hold right-mouse is the proof
	# that the event is arriving at all.
	var looking: bool = _cam._looking
	_text(Vector2(GUTTER, y), "look %s   yaw %.0f°  pitch %.0f°   at (%.0f, %.0f, %.0f)   speed %.0f"
			% ["ON" if looking else "off", rad_to_deg(_cam.rotation.y),
			rad_to_deg(_cam.rotation.x), _cam.global_position.x, _cam.global_position.y,
			_cam.global_position.z, _cam.speed],
			12, Color(0.45, 0.85, 0.55) if looking else DIM)
	y += 16
	# WHICH ROOM IS ACTUALLY BOUNCING LIGHT. Only one VoxelGI contributes at a time (RoomGI._only),
	# so without this the lit view has a hidden variable: a room can look wrong simply because its
	# probe is not the live one, which is a property of the bench and not of the dungeon.
	var gi := _zone.get_node_or_null("RoomGI")
	if gi != null:
		var lit_room := "—"
		for room: Node in gi._data:
			var v: VoxelGI = gi._data[room]
			if is_instance_valid(v) and v.visible:
				lit_room = room.name
		_text(Vector2(GUTTER, y), "VoxelGI: %s lit, %d baked%s"
				% [lit_room, gi._data.size(), "" if _gi_follow else "  (not following camera)"],
				12, DIM)
		y += 16
	if _zone_seed != _seed:
		_text(Vector2(GUTTER, y), "seed is now %d — press G to rebuild" % _seed, 13, WARN)

	if not _labels:
		return
	for n in _flatten(_zone):
		if not (n is DungeonRoom):
			continue
		var room := n as DungeonRoom
		var rd: DungeonLayout.RoomData = _lay.rooms.get(room.cell) if _lay != null else null
		var head := room.global_position + Vector3(0.0, 7.5, 0.0)
		# unproject_position is meaningless behind the camera — it mirrors the point in front of you,
		# so without this every room behind your back draws a label on top of the one you are in.
		if not _cam.is_position_behind(head):
			var label := "%s  %s" % [room.name, "" if rd == null else rd.module_id]
			_text(_cam.unproject_position(head), label, 12, Color(0.55, 0.85, 1.0))
		for def in room.spawn_defs:
			var at: Vector3 = room.global_position + (def.pos as Vector3)
			if _cam.is_position_behind(at):
				continue
			var p := _cam.unproject_position(at)
			draw_circle(p, 6.0, Color(0.90, 0.28, 0.30, 0.85))
			_text(p + Vector2(-3, 4), String(def.kind).substr(0, 1).to_upper(), 11, Color.BLACK)


## Run the real gameplay planner over the picked room. This is the whole point of the bench: the
## shape, the walls, the cover and the spawns drawn in ROOM view are the ones the game would build,
## produced by the same code paths, not a re-implementation that can drift.
## EVERY ROOM'S FLOOR PLAN, not just the picked one. The schematic drew each room as a flat block of
## its type colour, which answered "what kind of room and where" and nothing at all about the thing
## the shape layer actually decides — which corners were bitten off, which were bevelled, how much
## floor is really there. A carved L and a full rectangle looked identical.
##
## Cheap enough to do eagerly: a dozen rooms per regen, and only plan_shell, which is the pass that
## picks the shape. It deliberately does NOT run plan_interior — furniture is the ROOM view's job and
## planning it for every room on every redraw is work nobody asked for.
func _plan_shapes() -> void:
	_shapes.clear()
	if _lay == null:
		return
	for anchor: Vector3i in _lay.rooms:
		var rd: DungeonLayout.RoomData = _lay.rooms[anchor]
		var ctx := RoomContext.create(rd, _lay.seed_used)
		RoomPlan.plan_shell(rd, ctx)
		_shapes[anchor] = ctx.shape


func _plan_pick() -> void:
	_ctx = null
	_rd = null
	if not _has_pick or _lay == null or not _lay.rooms.has(_picked):
		return
	_rd = _lay.rooms[_picked]
	_ctx = RoomContext.create(_rd, _lay.seed_used)
	RoomPlan.plan_shell(_rd, _ctx)
	if _rd.template_path == "":
		RoomPlan.plan_interior(_rd, _ctx)


# ---------------------------------------------------------------- drawing -------------------

func _draw() -> void:
	_hit.clear()
	# NO background fill in BUILD view: the canvas draws over the 3D, so painting it opaque is
	# exactly how you get a bench that renders a dungeon nobody can see.
	if _view != View.BUILD and _view != View.ASSEMBLY:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.10, 0.12))
	if _lay == null:
		return
	match _view:
		View.LAYOUT:
			_draw_layout()
		View.ROOM:
			_draw_room()
		View.BUILD:
			_draw_build()
		View.ASSEMBLY:
			_draw_assembly()
	if _legend:
		_draw_legend()


# --- the legend ------------------------------------------------------------------------------
#
# Drawn rather than built out of Controls, for one reason: every entry needs to show the ACTUAL
# colour or stroke the view uses, taken from the same constant. A legend that restates the palette
# in words is a second copy of it, and the day someone retunes TYPE_COLOR the words start lying.

## The semantic axis in the LAYOUT view. Deliberately not a TYPE_COLOR: purpose is orthogonal to
## type, and colouring it the same would suggest it is derived from it.
const PURPOSE_INK := Color(0.72, 0.95, 0.72)

const LEGEND_W := 208.0


func _draw_legend() -> void:
	var rows := _legend_rows()
	if rows.is_empty():
		return
	var h := 20.0 + rows.size() * 15.0
	var box := Rect2(size.x - LEGEND_W - 14.0, MARGIN, LEGEND_W, h)
	draw_rect(box, Color(0.06, 0.06, 0.08, 0.92))
	draw_rect(box, Color(0.30, 0.30, 0.36), false, 1.0)
	_text(box.position + Vector2(8, 14), "LEGEND   [L] hides", 10, DIM)
	var y := box.position.y + 30.0
	for row in rows:
		var swatch := Rect2(box.position.x + 8.0, y - 8.0, 14.0, 10.0)
		match row.get("mark", "fill"):
			"fill":
				draw_rect(swatch, row.color)
			"line":
				draw_line(Vector2(swatch.position.x, swatch.get_center().y),
						Vector2(swatch.end.x, swatch.get_center().y), row.color, row.get("w", 2.5))
			"dash":
				_draw_dashed(Vector2(swatch.position.x, swatch.get_center().y),
						Vector2(swatch.end.x, swatch.get_center().y), row.color, 2.5)
			"dot":
				draw_circle(swatch.get_center(), 5.0, row.color)
			"ring":
				draw_arc(swatch.get_center(), 5.0, 0.0, TAU, 16, row.color, 2.0)
			"none":
				pass
		_text(Vector2(box.position.x + 30.0, y), row.text, 11,
				row.get("ink", INK) as Color)
		y += 15.0


func _legend_rows() -> Array:
	var rows: Array = []
	match _view:
		View.LAYOUT:
			for t in TYPE_NAME.size():
				rows.append({"color": TYPE_COLOR[t], "text": TYPE_NAME[t]})
			rows.append({"color": Color(1.0, 0.85, 0.3), "text": "holds the key", "mark": "ring"})
			for t in EDGE_NAME.size():
				var mark := "dash" if t == DungeonLayout.EdgeType.SHORTCUT \
						or t == DungeonLayout.EdgeType.SECRET else "line"
				var w := 4.0 if t == DungeonLayout.EdgeType.LOCKED else 2.5
				rows.append({"color": EDGE_COLOR[t], "text": EDGE_NAME[t], "mark": mark, "w": w})
			rows.append({"color": PURPOSE_INK, "text": "what the room is FOR", "mark": "none",
					"ink": PURPOSE_INK})
			rows.append({"color": DIM, "text": "^ F1 = stair to floor 1", "mark": "none",
					"ink": DIM})
		View.ROOM:
			rows.append({"color": Color(0.30, 0.33, 0.42),
					"text": "the cross (never carved)"})
			rows.append({"color": Color(0.24, 0.25, 0.30), "text": "floor tile"})
			rows.append({"color": Color(0.14, 0.14, 0.17), "text": "carved away"})
			rows.append({"color": Color(0.45, 0.16, 0.16), "text": "UNREACHABLE"})
			# ELEVATION, and the shades are DERIVED from the same level_tint() the tiles are drawn
			# with rather than typed in here. A legend with its own copy of the colours is a legend
			# that goes on looking right after the drawing changes, which is worse than none.
			var base := Color(0.24, 0.25, 0.30)
			rows.append({"color": level_tint(base, 1), "text": "raised  (+N on the tile)"})
			rows.append({"color": level_tint(base, -1), "text": "sunken  (-N on the tile)"})
			rows.append({"color": base.lightened(0.4), "text": "ramp — treads climb to the light",
					"mark": "line", "w": 2.5})
			rows.append({"color": Color(0.95, 0.62, 0.85), "text": "bevelled corner", "mark": "line",
					"w": 2.0})
			rows.append({"color": Color(0.35, 0.85, 0.72), "text": "reserved, extent unknown",
					"mark": "ring"})
			rows.append({"color": Color(0.62, 0.63, 0.70), "text": "wall", "mark": "line",
					"w": 3.0})
			rows.append({"color": Color(0.95, 0.72, 0.30), "text": "doorway", "mark": "line",
					"w": 5.0})
			rows.append({"color": Color(0.85, 0.55, 0.30), "text": "cover_large (pillar)"})
			rows.append({"color": Color(0.70, 0.62, 0.42), "text": "cover_small (crate)"})
			rows.append({"color": Color(0.95, 0.80, 0.35), "text": "focal (altar)"})
			rows.append({"color": Color(1.0, 0.85, 0.30), "text": "the key"})
			rows.append({"color": Color(1.0, 0.62, 0.20), "text": "light mount (candelabra)",
					"mark": "dot"})
			rows.append({"color": Color(0.45, 0.68, 0.95), "text": "stair flight"})
			rows.append({"color": Color(0.90, 0.28, 0.30), "text": "enemy  M/A/B/S", "mark": "dot"})
		View.BUILD:
			rows.append({"color": DIM, "text": "RMB drag = look", "mark": "none", "ink": INK})
			rows.append({"color": DIM, "text": "W/A/S/D = move", "mark": "none", "ink": INK})
			rows.append({"color": DIM, "text": "Q / E = down / up", "mark": "none", "ink": INK})
			rows.append({"color": DIM, "text": "shift = x3,  wheel = speed", "mark": "none",
					"ink": INK})
			rows.append({"color": DIM, "text": "(physical keys: ZQSD on AZERTY)", "mark": "none",
					"ink": DIM})
			rows.append({"color": Color(0.90, 0.28, 0.30), "text": "planned enemy", "mark": "dot"})
			if _render == Render.BY_TYPE:
				for t in TYPE_NAME.size():
					rows.append({"color": TYPE_COLOR[t].lightened(0.35), "text": TYPE_NAME[t]})
	rows.append({"color": DIM, "text": "TAB cycles views", "mark": "none", "ink": DIM})
	return rows


## The drawing area. The legend is opaque and sits at the right edge, so it has to come out of the
## plot rather than be drawn over it — a schematic scaled to the full width would put the boss room
## under the swatches exactly when you went looking for it.
func _plot() -> Rect2:
	var right := LEGEND_W + 28.0 if _legend else MARGIN
	return Rect2(GUTTER, MARGIN, maxf(size.x - GUTTER - right, 64.0),
			maxf(size.y - MARGIN * 2.0, 64.0))


func _text(at: Vector2, s: String, px := 12, col := INK) -> void:
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


# --- LAYOUT view ------------------------------------------------------------------------------

func _draw_layout() -> void:
	var here: Array = []
	for anchor: Vector3i in _lay.rooms:
		var rd: DungeonLayout.RoomData = _lay.rooms[anchor]
		if rd.cell.y == _floor:
			here.append(rd)
	if here.is_empty():
		_text(Vector2(GUTTER, MARGIN + 20), "no rooms on floor %d" % _floor, 16, WARN)
		return

	# World bounds of this floor, in XZ, so the schematic fills whatever window it is given.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for rd: DungeonLayout.RoomData in here:
		var c := DungeonLayout.room_origin(rd)
		var s := DungeonLayout.size_of(rd)
		lo.x = minf(lo.x, c.x - s.x * 0.5)
		lo.y = minf(lo.y, c.z - s.z * 0.5)
		hi.x = maxf(hi.x, c.x + s.x * 0.5)
		hi.y = maxf(hi.y, c.z + s.z * 0.5)
	lo -= Vector2(DungeonLayout.GAP, DungeonLayout.GAP) * 2.0
	hi += Vector2(DungeonLayout.GAP, DungeonLayout.GAP) * 2.0

	var plot := _plot()
	var span := hi - lo
	var k: float = minf(plot.size.x / maxf(span.x, 1.0), plot.size.y / maxf(span.y, 1.0))
	var off := plot.position + (plot.size - span * k) * 0.5 - lo * k
	var to_screen := func(w: Vector3) -> Vector2: return Vector2(w.x, w.z) * k + off

	for rd: DungeonLayout.RoomData in here:
		_draw_room_block(rd, to_screen, k)
	# Passages second, so they sit on top of the blocks they join and a LOCKED gate is never hidden
	# behind a room fill.
	for rd: DungeonLayout.RoomData in here:
		_draw_edges(rd, to_screen, k)

	_draw_layout_hud(here)


func _draw_room_block(rd: DungeonLayout.RoomData, to_screen: Callable, k: float) -> void:
	var c := DungeonLayout.room_origin(rd)
	var s := DungeonLayout.size_of(rd)
	var a: Vector2 = to_screen.call(c - Vector3(s.x, 0, s.z) * 0.5)
	var b: Vector2 = to_screen.call(c + Vector3(s.x, 0, s.z) * 0.5)
	var r := Rect2(a, b - a)
	_draw_room_fill(rd, r)
	draw_rect(r, TYPE_COLOR[rd.type].lightened(0.35), false, 2.0)
	_hit.append({"rect": r, "anchor": rd.cell})

	if _has_pick and rd.cell == _picked:
		draw_rect(r.grow(4.0), Color(1.0, 0.95, 0.6), false, 2.0)
	# The key is the mission layer's whole point; ring it so a glance answers "is the key behind the
	# gate", which is the one thing _add_lock can get wrong in a way nothing else notices.
	if rd.holds_key != "":
		draw_arc(r.get_center(), minf(r.size.x, r.size.y) * 0.32, 0.0, TAU, 28,
				Color(1.0, 0.85, 0.3), 3.0)

	if r.size.y > 26.0:
		var label := "%s  d%d" % [TYPE_NAME[rd.type], rd.dist]
		if rd.size.x > 1 or rd.size.z > 1:
			label += "  %dx%d" % [rd.size.x, rd.size.z]
		_text(r.position + Vector2(6, 16), label, 12, INK)
		# The module is the thing a placement rule can be judged by: a `vault` that is not a
		# dead-end, or a `landing` that never became a staircase, is visible here and nowhere else.
		_text(r.position + Vector2(6, 30), rd.module_id, 11, Color(0.55, 0.78, 0.95))
		# WHAT THE ROOM IS FOR, beside what SHAPE it is — the two are different axes and the whole
		# point of the purpose layer is that they can disagree. Read straight off the field, which is
		# why this costs nothing: before the layout decided purpose, the only way to know a room's
		# program was to run plan_interior on it, and this view never does.
		if rd.purpose != "":
			_text(r.position + Vector2(6, 44), rd.purpose, 11, PURPOSE_INK)
		if rd.template_path != "":
			_text(r.position + Vector2(6, 58), "template", 11, Color(0.6, 0.9, 1.0))
		if rd.holds_key != "":
			_text(r.position + Vector2(6, r.size.y - 8), "KEY " + rd.holds_key, 11,
					Color(1.0, 0.85, 0.3))


## The room's actual floor, tile by tile, inside its block. Carved bites read as gaps and a bevelled
## corner as a cut corner, so the schematic finally shows what the shape layer decided.
##
## Falls back to the flat block if the shape is missing, which keeps the view working for a layout
## that was generated before the cache existed rather than drawing nothing.
func _draw_room_fill(rd: DungeonLayout.RoomData, r: Rect2) -> void:
	var shape: RoomShape = _shapes.get(rd.cell)
	if shape == null:
		draw_rect(r, TYPE_COLOR[rd.type])
		return
	# The void the room stands in, so a bite reads as an absence rather than as darker floor.
	draw_rect(r, Color(0.10, 0.10, 0.13))
	var base := TYPE_COLOR[rd.type]
	var tw := r.size.x / float(shape.cols)
	var th := r.size.y / float(shape.rows)
	var gap: float = minf(1.0, minf(tw, th) * 0.08)
	for j in shape.rows:
		for i in shape.cols:
			var t := Vector2i(i, j)
			if not shape.is_solid(t):
				continue
			var tr := Rect2(r.position + Vector2(i * tw, j * th), Vector2(tw, th)).grow(-gap)
			# ELEVATION, WHERE IT IS DECIDED. A level is a property of the tile, so the schematic
			# that shows the floor plan has to show it too — otherwise the one view that answers
			# "what did the shape layer choose" stays silent about the choice most worth seeing, and
			# a raised gallery is indistinguishable from a flat row.
			var lvl := shape.level_of(t)
			var fill := base if lvl == 0 else level_tint(base, lvl)
			var pts := tile_poly(shape, t, tr)
			if pts.is_empty():
				draw_rect(tr, fill)
			else:
				draw_colored_polygon(pts, fill)
			if shape.is_ramp(t):
				_draw_ramp(tr, shape.ramp_dir(t), base)
			elif lvl != 0 and pts.is_empty():
				draw_rect(tr, level_tint(base, lvl).lightened(0.3), false, 1.5)


## THE OUTLINE OF ONE TILE, empty for the ordinary square case so a caller can take the cheap
## `draw_rect` path. Shared by the LAYOUT thumbnail and the ROOM plan for one reason: they are two
## drawings of the same decision, and a bevel that exists in one and not the other is the bench
## contradicting itself about what the shape layer chose.
##
## A BEVELLED TILE IS A PENTAGON. `d` points out of the corner that was cut, and in screen space +x
## is +x and +z is DOWN, which is the same handedness the tile grid is indexed in — so the corner to
## drop is simply the one at (d + 1) / 2 of the rect.
static func tile_poly(shape: RoomShape, t: Vector2i, tr: Rect2) -> PackedVector2Array:
	if not shape.is_chamfer(t):
		return PackedVector2Array()
	var d: Vector2i = shape.chamfer_dir(t)
	var cx: float = tr.position.x if d.x < 0 else tr.end.x
	var cz: float = tr.position.y if d.y < 0 else tr.end.y
	var leg := RoomShape.CHAMFER_LEG / RoomShape.TILE
	var raw: Array[Vector2] = []
	for corner in [Vector2(tr.position.x, tr.position.y), Vector2(tr.end.x, tr.position.y),
			Vector2(tr.end.x, tr.end.y), Vector2(tr.position.x, tr.end.y)]:
		if not (is_equal_approx(corner.x, cx) and is_equal_approx(corner.y, cz)):
			raw.append(corner)
	raw.append(Vector2(cx - signf(d.x) * tr.size.x * leg, cz))
	raw.append(Vector2(cx, cz - signf(d.y) * tr.size.y * leg))
	# SORTED BY ANGLE rather than emitted in walk order. Which of the two cut points comes first
	# depends on which of the four corners was dropped, and getting it wrong makes a
	# self-intersecting pentagon that Godot refuses to triangulate. The tile is convex, so sorting
	# round its centroid is right for all four cases and needs no special case.
	var mid := tr.get_center()
	raw.sort_custom(func(u: Vector2, v: Vector2) -> bool:
		return (u - mid).angle() < (v - mid).angle())
	var pts := PackedVector2Array()
	for q in raw:
		pts.append(q)
	return pts


## The colour of a tile at level `lvl`. UP LIGHTENS, DOWN DARKENS, which is the one mapping that
## needs no legend — and it is signed on purpose, ahead of the sunken regions M7 introduces, so a
## pit does not arrive reading identically to a deck. Clamped past ±3 because the ramp between two
## adjacent levels must stay visible against both of them.
static func level_tint(base: Color, lvl: int) -> Color:
	var f: float = clampf(float(lvl) / 3.0, -1.0, 1.0)
	return base.lightened(0.40 * f) if f > 0.0 else base.darkened(-0.34 * f)


## A ramp tile, as the treads you would walk up. Drawn rather than tinted because a ramp is the one
## tile whose height is not a single number — it is the JOIN between two levels, and which way it
## climbs is the thing worth seeing.
func _draw_ramp(tr: Rect2, dir: Vector2i, ink: Color) -> void:
	var along := Vector2(dir.x, dir.y)
	var across := Vector2(-along.y, along.x)
	var c := tr.get_center()
	var half_a: float = (tr.size.x if absf(along.x) > 0.5 else tr.size.y) * 0.5
	var half_c: float = (tr.size.y if absf(along.x) > 0.5 else tr.size.x) * 0.5
	for k in 4:
		var t := (float(k) + 0.5) / 4.0
		var p := c + along * (half_a * (t * 2.0 - 1.0))
		draw_line(p - across * half_c, p + across * half_c, ink.lightened(0.55 * t), 1.5)


## One stroke per exit, drawn from the door on the wall out across the GAP — which is exactly the
## passage `dungeon_generator._build_corridor` will build. Vertical edges have no neighbour on this
## floor, so they get a chevron at the door instead of a line to nowhere.
func _draw_edges(rd: DungeonLayout.RoomData, to_screen: Callable, k: float) -> void:
	var origin := DungeonLayout.room_origin(rd)
	for e: DungeonLayout.Edge in rd.edges:
		var door: Vector2 = to_screen.call(origin + DungeonLayout.door_local(rd, e))
		var col := EDGE_COLOR[e.type]
		if e.dir.y != 0:
			var up := e.dir.y > 0
			var tip := door + Vector2(0, -10 if up else 10)
			draw_line(door + Vector2(-7, 0), tip, col, 2.0)
			draw_line(door + Vector2(7, 0), tip, col, 2.0)
			_text(door + Vector2(10, 4), "F%d" % (rd.cell.y + e.dir.y), 10, col)
			continue
		var out := Vector2(e.dir.x, e.dir.z) * (DungeonLayout.GAP * k)
		var width := 4.0 if e.type == DungeonLayout.EdgeType.LOCKED else 2.5
		if e.type == DungeonLayout.EdgeType.SHORTCUT or e.type == DungeonLayout.EdgeType.SECRET:
			_draw_dashed(door, door + out, col, width)
		else:
			draw_line(door, door + out, col, width)
		if e.type == DungeonLayout.EdgeType.LOCKED:
			var mid := door + out * 0.5
			draw_circle(mid, 5.0, col)
			_text(mid + Vector2(7, -6), e.key_id, 10, col)


func _draw_dashed(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var n := maxi(2, int(a.distance_to(b) / 5.0))
	for i in n:
		if i % 2 == 1:
			continue
		draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, width)


func _draw_layout_hud(here: Array) -> void:
	var floors := {}
	for anchor: Vector3i in _lay.rooms:
		floors[(_lay.rooms[anchor] as DungeonLayout.RoomData).cell.y] = true
	var counts := {}
	var edge_kinds := {}
	var dead_ends := 0
	for anchor: Vector3i in _lay.rooms:
		var rd: DungeonLayout.RoomData = _lay.rooms[anchor]
		counts[rd.type] = int(counts.get(rd.type, 0)) + 1
		if rd.edges.size() == 1:
			dead_ends += 1
		for e: DungeonLayout.Edge in rd.edges:
			edge_kinds[e.type] = int(edge_kinds.get(e.type, 0)) + 1

	var parts: Array[String] = []
	for t in TYPE_NAME.size():
		if counts.has(t):
			parts.append("%s %d" % [TYPE_NAME[t], counts[t]])
	var ekinds: Array[String] = []
	for t in EDGE_NAME.size():
		if edge_kinds.has(t):
			# Every edge is stored on both rooms, so the raw tally is double the passage count.
			ekinds.append("%s %d" % [EDGE_NAME[t], int(edge_kinds[t]) / 2])

	var y := MARGIN
	_text(Vector2(GUTTER, y), "LAYOUT   seed %d   floor %d of %s   %d rooms"
			% [_lay.seed_used, _floor, str(floors.keys()), _lay.rooms.size()], 15, INK)
	y += 18
	_text(Vector2(GUTTER, y), "rooms: " + "  ".join(parts) + "    dead-ends %d" % dead_ends, 12, DIM)
	y += 15
	_text(Vector2(GUTTER, y), "passages: " + "  ".join(ekinds), 12, DIM)
	if _stat_line != null:
		_stat_line.text = "%d rooms, %d on this floor" % [_lay.rooms.size(), here.size()]


# --- ROOM view --------------------------------------------------------------------------------

func _draw_room() -> void:
	if _ctx == null or _rd == null:
		_text(Vector2(GUTTER, MARGIN + 20), "no room picked — click one in LAYOUT view", 15, WARN)
		return
	var shape := _ctx.shape
	var plot := _plot()
	var span := Vector2(shape.cols, shape.rows) * RoomShape.TILE
	var k: float = minf(plot.size.x / span.x, (plot.size.y - 90.0) / span.y)
	var off := plot.position + Vector2(0, 74) \
			+ (Vector2(plot.size.x, plot.size.y - 90.0) - span * k) * 0.5
	# Room-local (x, z) -> screen. The room's own origin is its centre, which is what every
	# RoomShape and RoomPlan coordinate is relative to.
	var to_screen := func(l: Vector3) -> Vector2:
		return off + (Vector2(l.x, l.z) + span * 0.5) * k

	var reach := _reachable(shape)
	var mid_col := (shape.cols - 1) / 2
	var mid_row := (shape.rows - 1) / 2
	var orphans := 0

	for j in shape.rows:
		for i in shape.cols:
			var t := Vector2i(i, j)
			var c := shape.tile_centre(t)
			var a: Vector2 = to_screen.call(c - Vector3(RoomShape.TILE, 0, RoomShape.TILE) * 0.5)
			var r := Rect2(a, Vector2(RoomShape.TILE, RoomShape.TILE) * k)
			if not shape.is_solid(t):
				# A carved bite. Drawn hollow so the silhouette reads as an absence rather than as
				# another kind of floor.
				draw_rect(r.grow(-1.0), Color(0.14, 0.14, 0.17))
				draw_line(r.position, r.end, Color(0.24, 0.24, 0.28), 1.0)
				continue
			var fill := Color(0.24, 0.25, 0.30)
			# The CROSS: the middle column and row RoomShape's carving rule always spares. Tinting it
			# is the whole connectivity argument in one picture — every surviving tile touches it.
			if i == mid_col or j == mid_row:
				fill = Color(0.30, 0.33, 0.42)
			if not reach.has(t):
				fill = Color(0.45, 0.16, 0.16)     # unreachable from the cross — a softlock waiting
				orphans += 1
			# ELEVATION ON TOP OF, NOT INSTEAD OF, the connectivity colour. Those are two independent
			# facts about the same tile and the view is asked about both, so level rides as a
			# lightness shift over whatever the reachability pass decided — an unreachable DECK stays
			# red, and stays legibly raised.
			var lvl := shape.level_of(t)
			var tr := r.grow(-1.0)
			var pts := tile_poly(shape, t, tr)
			if pts.is_empty():
				draw_rect(tr, level_tint(fill, lvl))
				draw_rect(tr, Color(0.36, 0.37, 0.44), false, 1.0)
			else:
				draw_colored_polygon(pts, level_tint(fill, lvl))
				var loop := pts.duplicate()
				loop.append(pts[0])
				draw_polyline(loop, Color(0.95, 0.62, 0.85), 1.6)
			if shape.is_ramp(t):
				_draw_ramp(tr, shape.ramp_dir(t), fill)
			elif lvl != 0:
				# THE NUMBER, not just the shade. A shade answers "is this the same height as that
				# one"; only a number answers "how far up", and once levels are signed integers with
				# several regions per room that is the question the view exists for.
				draw_rect(tr, level_tint(fill, lvl).lightened(0.45), false, 1.6)
				if tr.size.x > 26.0:
					_text(tr.get_center() + Vector2(-4, 4), ("+%d" % lvl) if lvl > 0 else str(lvl),
							11, Color(0.96, 0.96, 1.0, 0.85))

	_draw_room_walls(shape, to_screen, k)
	_draw_room_slots(to_screen, k)
	_draw_room_hud(shape, orphans, reach.size())


## Every boundary between floor and not-floor, exactly as RoomShape.walls() emits it — and the
## doorway test re-run the same way RoomPlan.plan_shell runs it, so a doorway that the shape cannot
## carry shows up here as a missing highlight rather than as a warning in a test three days later.
func _draw_room_walls(shape: RoomShape, to_screen: Callable, k: float) -> void:
	for wall: Dictionary in shape.walls():
		var is_door := false
		for e: DungeonLayout.Edge in _rd.edges:
			var hd := Vector2i(e.dir.x, e.dir.z)
			if hd != Vector2i.ZERO \
					and RoomShape.is_doorway(wall, hd, DungeonLayout.door_local(_rd, e)):
				is_door = true
				break
		var at: Vector3 = wall.at
		var out: Vector2i = wall.out
		# The segment runs along the wall, perpendicular to its outward normal — and a chamfer's
		# normal is diagonal, where `(out.y, out.x)` is not perpendicular at all but parallel. The
		# LENGTH now comes off the wall itself rather than being re-derived here from its role: the
		# bench drawing a different length from the one the kit builds is the bench lying about the
		# only thing it exists to show.
		var n := Vector3(out.x, 0, out.y).normalized()
		var along := Vector3(-n.z, 0, n.x) * (float(wall.span) * 0.5)
		var p0: Vector2 = to_screen.call(at - along)
		var p1: Vector2 = to_screen.call(at + along)
		draw_line(p0, p1, Color(0.95, 0.72, 0.30) if is_door else Color(0.62, 0.63, 0.70),
				5.0 if is_door else 3.0)


func _draw_room_slots(to_screen: Callable, k: float) -> void:
	const SLOT_COLOR := {
		RoomPlan.T_COVER_LARGE: Color(0.85, 0.55, 0.30),
		RoomPlan.T_COVER_SMALL: Color(0.70, 0.62, 0.42),
		RoomPlan.T_FOCAL: Color(0.95, 0.80, 0.35),
		RoomPlan.T_KEY: Color(1.0, 0.85, 0.30),
		RoomPlan.T_STAIR: Color(0.45, 0.68, 0.95),
		RoomPlan.T_DAIS: Color(0.35, 0.85, 0.72),
		RoomPlan.T_WALL_ANCHOR: Color(1.0, 0.62, 0.20),
	}
	# One letter per tag. Deliberately NOT the tag's first character — cover-Large and cover-Small
	# share one, and Focal/Key/Dais/Stair are the four the view is most often asked to tell apart.
	const SLOT_GLYPH := {
		RoomPlan.T_COVER_LARGE: "C",
		RoomPlan.T_COVER_SMALL: "c",
		RoomPlan.T_FOCAL: "F",
		RoomPlan.T_KEY: "K",
		RoomPlan.T_STAIR: "S",
		RoomPlan.T_DAIS: "D",
		RoomPlan.T_WALL_ANCHOR: "L",
	}
	for slot: RoomContext.Slot in _ctx.slots:
		if not SLOT_COLOR.has(slot.tag):
			continue
		var p: Vector3 = slot.transform.origin
		# LIGHT MOUNTS GET THEIR OWN GLYPH, not just their own colour. They and the crates are both
		# roughly metre-square, so at this scale two similar swatches are indistinguishable — and
		# telling "candelabra down the aisle" from "crates down the aisle" is the entire question
		# this view is being asked.
		if slot.tag == RoomPlan.T_WALL_ANCHOR:
			var c: Vector2 = to_screen.call(p)
			draw_circle(c, 7.0, SLOT_COLOR[slot.tag])
			draw_arc(c, 11.0, 0.0, TAU, 20, SLOT_COLOR[slot.tag], 1.5)
			continue
		# A ZERO FOOTPRINT IS NOT A SMALL PIECE — it is a piece whose extent this layer does not
		# carry. The dais reserves through ctx.reserve() precisely so it stays out of _plan_suite's
		# pairwise Rect2 test, and every fixture after it will do the same; drawing them at the old
		# 1.5 m stand-in put the largest structure in the room on screen as one of the smallest.
		# Neither RoomContext.Slot nor reserve() records the rectangle, so there is nothing here to
		# ask, and inventing a size would be the bench asserting something no pass decided. Marked
		# instead: a hollow diamond means "reserved, extent not carried". M6.6 gives fixtures a real
		# `span`, and this branch becomes a rectangle again with an actual number behind it.
		if slot.footprint == Vector2.ZERO:
			var c2: Vector2 = to_screen.call(p)
			var dia := PackedVector2Array([c2 + Vector2(0, -11), c2 + Vector2(11, 0),
					c2 + Vector2(0, 11), c2 + Vector2(-11, 0), c2 + Vector2(0, -11)])
			draw_polyline(dia, SLOT_COLOR[slot.tag], 2.0)
			_text(c2 + Vector2(-4, 4), SLOT_GLYPH.get(slot.tag, "?"), 12, SLOT_COLOR[slot.tag])
			continue
		var fp: Vector2 = slot.footprint
		var a: Vector2 = to_screen.call(p - Vector3(fp.x, 0, fp.y) * 0.5)
		var r := Rect2(a, fp * k)
		draw_rect(r, SLOT_COLOR[slot.tag])
		draw_rect(r, Color.BLACK, false, 1.0)
		# THE INITIAL, so a swatch says WHAT it is and not merely that something is there. Two
		# metre-square props in the same warm band are one colour to the eye at this scale, and the
		# question the view is asked is which of them is which. Skipped when the swatch is too small
		# to hold a letter, rather than drawing a smear across its neighbours.
		if r.size.x > 13.0 and r.size.y > 13.0:
			_text(r.get_center() + Vector2(-4, 4), SLOT_GLYPH.get(slot.tag, "?"), 12, Color.BLACK)

	for def in _ctx.spawn_defs:
		var sp: Vector3 = def.pos
		var at: Vector2 = to_screen.call(Vector3(sp.x, 0, sp.z))
		var kind := String(def.kind)
		draw_circle(at, 7.0, Color(0.90, 0.28, 0.30))
		_text(at + Vector2(-3, 4), kind.substr(0, 1).to_upper(), 11, Color.BLACK)


func _draw_room_hud(shape: RoomShape, orphans: int, reached: int) -> void:
	var y := MARGIN
	var frac := float(shape.tile_count()) / maxf(shape.cols * shape.rows, 1.0)
	_text(Vector2(GUTTER, y), "ROOM %s   %s   %s   %s   d%d   %dx%d cells"
			% [_rd.cell, TYPE_NAME[_rd.type], _rd.module_id,
			_ctx.program if _ctx.program != "" else "(not woven)", _rd.dist,
			_rd.size.x, _rd.size.z], 15, INK)
	y += 18
	_text(Vector2(GUTTER, y), "tiles %d of %d  (floor fraction %.2f)   grid %dx%d   exits %d"
			% [shape.tile_count(), shape.cols * shape.rows, frac, shape.cols, shape.rows,
			_rd.door_dirs().size()], 12, DIM)
	y += 15
	var cover := 0
	for slot: RoomContext.Slot in _ctx.slots:
		if slot.tag == RoomPlan.T_COVER_LARGE or slot.tag == RoomPlan.T_COVER_SMALL:
			cover += 1
	_text(Vector2(GUTTER, y), "slots %d   cover %d   spawns %d   free cells %d"
			% [_ctx.slots.size(), cover, _ctx.spawn_defs.size(), _ctx.free_cell_count()], 12, DIM)
	y += 15
	if orphans > 0:
		_text(Vector2(GUTTER, y), "%d UNREACHABLE TILES — a key or a spawn here softlocks the room"
				% orphans, 13, WARN)
	else:
		_text(Vector2(GUTTER, y), "all %d floor tiles reach the cross" % reached, 12,
				Color(0.45, 0.85, 0.55))


## Flood fill over solid tiles from the room's middle tile. Today's carving rule makes this
## vacuously true — that IS the guarantee, and drawing it is how you see the guarantee rather than
## take it on trust. It stops being vacuous the moment a solver picks the silhouette instead.
func _reachable(shape: RoomShape) -> Dictionary:
	var start := Vector2i((shape.cols - 1) / 2, (shape.rows - 1) / 2)
	var seen := {}
	if not shape.is_solid(start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	while not queue.is_empty():
		var t: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if shape.is_solid(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


# ---------------------------------------------------------------- batch ---------------------
#
# THE HALF THAT STOPS THE NUMBERS BEING GUESSES. Every threshold in the generator — how often a
# room is carved, how deep a bite may go, how many loops close — was chosen by eye on a handful of
# seeds. This runs the whole planner over hundreds and reports the distribution, which is the only
# way to tell a rule that fires sometimes from a rule that fires almost never.

func _batch(n: int) -> String:
	var t0 := Time.get_ticks_msec()
	var rooms_total := 0
	var room_counts: Array[int] = []
	var type_counts := {}
	var edge_counts := {}
	var module_counts := {}
	# THE THREE PROMISES MILESTONE A MAKES, counted rather than asserted. A vault that is not a
	# dead-end means some pass added a door behind the module's back; a landing that never became a
	# staircase means the module is paying its acceptance-rate cost for nothing; an over-cap means
	# `used` is not being kept.
	var vault_not_dead_end := 0
	var landings := 0
	var landings_lifted := 0
	var over_cap := 0
	var dead_ends := 0
	var carved := 0
	var full := 0
	var orphan_rooms := 0
	var no_treasure := 0
	var no_lock := 0
	var frac_sum := 0.0
	var frac_min := 1.0
	var spawn_total := 0

	for s in range(1, n + 1):
		var lay := DungeonLayout.generate(s, _room_count, _stair_count, _loop_count)
		room_counts.append(lay.rooms.size())
		var saw_treasure := false
		var saw_lock := false
		var per_seed := {}
		for anchor: Vector3i in lay.rooms:
			var rd: DungeonLayout.RoomData = lay.rooms[anchor]
			rooms_total += 1
			type_counts[rd.type] = int(type_counts.get(rd.type, 0)) + 1
			module_counts[rd.module_id] = int(module_counts.get(rd.module_id, 0)) + 1
			per_seed[rd.module_id] = int(per_seed.get(rd.module_id, 0)) + 1
			if rd.kind == "vault" and rd.lateral_edges() != 1:
				vault_not_dead_end += 1
			if rd.module_id == "landing":
				landings += 1
				if rd.type == DungeonLayout.RoomType.STAIR:
					landings_lifted += 1
			if rd.edges.size() == 1:
				dead_ends += 1
			if rd.type == DungeonLayout.RoomType.TREASURE:
				saw_treasure = true
			for e: DungeonLayout.Edge in rd.edges:
				edge_counts[e.type] = int(edge_counts.get(e.type, 0)) + 1
				if e.type == DungeonLayout.EdgeType.LOCKED:
					saw_lock = true

			var ctx := RoomContext.create(rd, lay.seed_used)
			RoomPlan.plan_shell(rd, ctx)
			if rd.template_path == "":
				RoomPlan.plan_interior(rd, ctx)
			spawn_total += ctx.spawn_defs.size()
			var shape := ctx.shape
			var frac := float(shape.tile_count()) / maxf(shape.cols * shape.rows, 1.0)
			frac_sum += frac
			frac_min = minf(frac_min, frac)
			if frac < 0.999:
				carved += 1
			else:
				full += 1
			if _reachable(shape).size() != shape.tile_count():
				orphan_rooms += 1
		if not saw_treasure:
			no_treasure += 1
		if not saw_lock:
			no_lock += 1
		for m in RoomModule.catalogue():
			if int(per_seed.get(m.id, 0)) > m.max_instances:
				over_cap += 1

	room_counts.sort()
	var ms := Time.get_ticks_msec() - t0

	var out: Array[String] = []
	out.append("[b]%d seeds, %d rooms, %d ms[/b]" % [n, rooms_total, ms])
	out.append("rooms/dungeon: min %d  median %d  max %d"
			% [room_counts[0], room_counts[room_counts.size() / 2], room_counts[-1]])
	var tparts: Array[String] = []
	for t in TYPE_NAME.size():
		if type_counts.has(t):
			tparts.append("%s %.2f" % [TYPE_NAME[t], float(type_counts[t]) / n])
	out.append("per dungeon: " + "  ".join(tparts))
	var eparts: Array[String] = []
	for t in EDGE_NAME.size():
		if edge_counts.has(t):
			eparts.append("%s %.2f" % [EDGE_NAME[t], float(edge_counts[t]) / 2.0 / n])
	out.append("passages: " + "  ".join(eparts))
	var sparts: Array[String] = []
	for key in module_counts:
		sparts.append("%s %.0f%%" % [key, 100.0 * float(module_counts[key]) / rooms_total])
	sparts.sort()
	out.append("modules: " + "  ".join(sparts))
	out.append("landings %d, of which %d became staircases" % [landings, landings_lifted])
	out.append("dead-ends %.2f/dungeon   spawns %.1f/room"
			% [float(dead_ends) / n, float(spawn_total) / rooms_total])
	out.append("carved %.0f%%  full %.0f%%   floor fraction mean %.3f  min %.3f"
			% [100.0 * carved / rooms_total, 100.0 * full / rooms_total,
			frac_sum / rooms_total, frac_min])
	# The three that are meant to read ZERO. A non-zero orphan count is the softlock class the
	# silhouette solver has to be built against; the other two mean a seed shipped without its
	# treasure beat or without its gate.
	var bad := orphan_rooms > 0 or no_treasure > 0 or no_lock > 0 \
			or vault_not_dead_end > 0 or over_cap > 0
	out.append("[color=%s]orphan rooms %d   no TREASURE %d   no LOCK %d   "
			% ["#fa7368" if bad else "#73d98c", orphan_rooms, no_treasure, no_lock]
			+ "vaults not dead-ends %d   over cap %d[/color]" % [vault_not_dead_end, over_cap])

	var text := "\n".join(out)
	if _pane != null:
		_pane.text = text
	print("[LayoutLab] batch\n" + text.replace("[b]", "").replace("[/b]", ""))
	return text


# ---------------------------------------------------------------- selftest ------------------
#
# A SMOKE TEST FOR THE BENCH ITSELF. An interactive scene is otherwise unverifiable from a terminal
# — it never exits, so `timeout` kills it and takes every buffered print with it, which is exactly
# how crypt_tuner's first run came back with an empty log and no way to tell whether it had worked
# or crashed in _ready.
#
#   … res://scenes/dev/layout_lab.tscn -- --selftest=user://lab_out
#
# WRITE OUTSIDE res://. A directory of PNGs inside the project is a directory Godot imports as
# textures on the next scan, which puts screenshots of a debugging session into the asset library
# and into git. user:// is the safe default; an absolute path outside the project works too.

## No lab shortcut may reuse a key FlyCamera flies with. BOTH SIDES ARE READ OUT OF THE SOURCE
## rather than restated here, because a hand-kept copy of either list is a check that passes while
## the thing it guards has drifted. The bug this exists for was silent in exactly that way: A was
## bound to "build the assembly" and to strafe-left at once, and because FlyCamera POLLS its keys
## instead of consuming events, neither binding masked the other — the camera flew and the rebuild
## dragged it back, once per frame, so the symptom was "A refuses to fly" rather than "A is bound
## twice".
func _check_no_key_collision() -> Array[String]:
	var fails: Array[String] = []
	var fly := FileAccess.get_file_as_string("res://scripts/dev/fly_camera.gd")
	var lab := FileAccess.get_file_as_string("res://scripts/dev/layout_lab.gd")
	if fly.is_empty() or lab.is_empty():
		return ["could not read the lab or fly-camera source to check key bindings"]

	var flown := {}
	var rx := RegEx.create_from_string("is_physical_key_pressed\\((KEY_\\w+)\\)")
	for m in rx.search_all(fly):
		flown[m.get_string(1)] = true

	# The match arms of _unhandled_input, which are the only place the lab claims a key. Anchored on
	# the arm's own indentation so a KEY_ constant mentioned in a comment or a string is not read as
	# a binding.
	var arm := RegEx.create_from_string("(?m)^\\t{3}(KEY_\\w+):")
	for m in arm.search_all(lab):
		var k := m.get_string(1)
		if flown.has(k):
			fails.append("lab shortcut %s is also a FlyCamera movement key — pick another" % k)
	if flown.is_empty() or arm.search_all(lab).is_empty():
		fails.append("the key-collision check matched nothing, so it is guarding nothing")
	return fails


func _selftest(out_dir: String) -> void:
	var fails: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	fails.append_array(_check_no_key_collision())


	_seed = 42
	_regen()
	if _lay == null or _lay.rooms.size() < 3:
		fails.append("layout came back with %d rooms" % (0 if _lay == null else _lay.rooms.size()))

	# LAYOUT view must actually draw something: _hit is filled by _draw, so a zero count means the
	# schematic rendered blank — the failure a screenshot alone would not distinguish from a dark
	# theme.
	_set_view(View.LAYOUT)
	await _shot(out_dir + "/layout.png")
	if _hit.is_empty():
		fails.append("LAYOUT view drew no room rects")
	else:
		# PICKING, driven by a REAL event pushed through the viewport rather than by calling the hit
		# test directly. That distinction is the whole value of this check: the bug it exists to
		# catch was input ROUTING — a full-rect Control with the default MOUSE_FILTER_STOP eats
		# mouse events before _unhandled_input runs — and a direct call to _hit_test passes happily
		# either way. Only an event that has to survive the GUI pass can tell the two apart.
		var target: Vector3i = _hit[-1].anchor
		var at: Vector2 = (_hit[-1].rect as Rect2).get_center()
		_picked = Vector3i(9999, 9999, 9999)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = at
		click.global_position = at
		get_viewport().push_input(click)
		await _wait(2)
		if _picked != target:
			fails.append("a click at %v over room %s picked %s — the event never reached the view"
					% [at, target, _picked])
		elif _view != View.ROOM:
			fails.append("picking a room did not switch to ROOM view")
		_set_view(View.LAYOUT)
		queue_redraw()
		await _wait(2)

	# ROOM view over the biggest COMBAT room. Type matters: a TREASURE room plans an altar and
	# nothing else, so photographing one proves the grid draws and proves nothing about the cover
	# and spawn passes — which are the two the bench exists to show.
	var best: Vector3i = _picked
	var best_cells := -1
	for anchor: Vector3i in _lay.rooms:
		var rd: DungeonLayout.RoomData = _lay.rooms[anchor]
		if rd.type != DungeonLayout.RoomType.COMBAT:
			continue
		var cells := rd.size.x * rd.size.z
		if cells > best_cells:
			best_cells = cells
			best = anchor
	if best_cells < 0:
		fails.append("no COMBAT room at seed 42 to photograph")
	_pick(best)
	await _shot(out_dir + "/room.png")

	# A ROOM THAT ACTUALLY HAS A LEVEL IN IT, hunted across seeds rather than hoped for at 42. The
	# level tint, the ±N label and the ramp treads are the only part of this view that says what the
	# shape layer decided about height, and they are drawn by a branch a flat room never enters — so
	# photographing whatever seed 42 happens to give proves the grid renders and proves nothing about
	# elevation. This is also the check that fails loudly if the walk zone ever stops firing: a bench
	# that quietly draws no galleries because none are being made looks exactly like a working bench.
	var raised := Vector3i.ZERO
	var found := false
	for s in range(42, 82):
		_seed = s
		_regen()
		for anchor: Vector3i in _lay.rooms:
			var sh: RoomShape = _shapes[anchor]
			for t: Vector2i in sh.tiles():
				if sh.level_of(t) != 0:
					raised = anchor
					found = true
					break
			if found:
				break
		if found:
			break
	if not found:
		fails.append("no room in seeds 42-81 has a tile off level 0 — elevation never draws")
	else:
		_pick(raised)
		await _shot(out_dir + "/room_raised.png")
	# BACK TO 42 AND BACK TO THE SAME ROOM, because every assertion below reads _ctx and this hunt
	# has been walking the seed. Re-picking explicitly rather than trusting the pick to survive a
	# regen: it happens to, at this seed, and a check that depends on that is a check that reports a
	# different room's spawns under a name that claims otherwise.
	_seed = 42
	_regen()
	_pick(best)
	if _ctx == null or _ctx.shape == null:
		fails.append("ROOM view has no planned context")
	elif _ctx.shape.tile_count() == 0:
		fails.append("ROOM view shape has no tiles")
	elif _ctx.slots.is_empty():
		fails.append("ROOM view planned no slots")
	elif _ctx.spawn_defs.is_empty():
		fails.append("COMBAT room planned no spawns — the encounter pass drew nothing")

	# Every room in the layout must plan without an orphan tile. This is the assertion the bench
	# exists to keep honest once the solver lands; today it should be vacuously true.
	var orphans := 0
	for anchor: Vector3i in _lay.rooms:
		var rd: DungeonLayout.RoomData = _lay.rooms[anchor]
		var ctx := RoomContext.create(rd, _lay.seed_used)
		RoomPlan.plan_shell(rd, ctx)
		if _reachable(ctx.shape).size() != ctx.shape.tile_count():
			orphans += 1
	if orphans > 0:
		fails.append("%d rooms have unreachable floor tiles at seed 42" % orphans)

	# BUILD view. The one that can fail for reasons the schematics never touch — a zone that parks
	# itself 700 m away, an environment the generator blacked out, a camera pointed at fog. Checked
	# by luminance as well as by node count, because a rig in the right place looking at nothing
	# passes every structural test there is.
	# Build FIRST, then switch: _set_view starts a build it cannot await, so switching first would
	# either double-build or race the screenshot against a half-added zone.
	await _build_3d()
	_set_view(View.BUILD)
	_frame_picked()
	# RoomGI ticks on its own 0.35 s schedule, so a handful of frames is not enough for the probe to
	# follow the camera to the room just framed — and a shot taken before it does photographs a room
	# lit by somebody else's bounce.
	for _t in 40:
		_drive_gi()
		await get_tree().process_frame
	await _shot(out_dir + "/build.png")
	var rooms_built := 0
	var spawns_built := 0
	if _zone == null or not is_instance_valid(_zone):
		fails.append("BUILD view produced no zone")
	else:
		for n in _flatten(_zone):
			if n is DungeonRoom:
				rooms_built += 1
				spawns_built += (n as DungeonRoom).spawn_defs.size()
		if rooms_built < 3:
			fails.append("BUILD view built only %d rooms" % rooms_built)
		if spawns_built == 0:
			fails.append("BUILD view planned no spawns to label")
		var img := get_viewport().get_texture().get_image()
		var luma := _mean_luma(img, Rect2(GUTTER, MARGIN, img.get_width() - GUTTER - MARGIN,
				img.get_height() - MARGIN * 2.0))
		if luma < 0.01:
			fails.append("BUILD view photographed a black frame (luma %.4f)" % luma)

		# THE GI ACTUALLY FOLLOWS. Without the probe, RoomGI._process bails on "no player" every
		# tick and the lit view is frozen on whatever prime() baked — the start room lit, the rest
		# with no bounce — which looks like a dark dungeon rather than like a broken bench.
		var gi := _zone.get_node_or_null("RoomGI")
		if gi == null:
			fails.append("the built zone has no RoomGI")
		else:
			var baked0: int = gi._data.size()
			var far: DungeonRoom = null
			for n in _zone.get_children():
				if n is DungeonRoom and (n as DungeonRoom).cell != Vector3i.ZERO:
					far = n
			if far == null:
				fails.append("no second room to fly to")
			else:
				# LOOK at it, not just hover over it. The probe follows the view ray now, so a camera
				# moved without being re-aimed is still asking about whatever it was pointed at.
				_cam.global_position = far.global_position + Vector3(0.0, 18.0, 12.0)
				_cam.look_at(far.global_position, Vector3.UP)
				# RoomGI ticks on its own TICK (0.35 s), so a couple of frames is not enough.
				for _t in 40:
					_drive_gi()
					await get_tree().process_frame
				var lit: Node = null
				for room: Node in gi._data:
					if is_instance_valid(gi._data[room]) and (gi._data[room] as VoxelGI).visible:
						lit = room
				if lit != far:
					fails.append("flew to %s but the lit VoxelGI is %s — GI is not following"
							% [far.name, "none" if lit == null else lit.name])
				if gi._data.size() < baked0:
					fails.append("baked room count went backwards (%d -> %d)"
							% [baked0, gi._data.size()])
			_frame_picked()
			await _wait(4)

		# RIGHT-DRAG LOOK, pushed through the viewport. This is the check for the bug that made the
		# fly camera feel like a zoom slider: the root Control's mouse_filter swallowed the event,
		# the camera never rotated, and because it opens pitched 52 degrees down, "forward" was
		# mostly "downward". Nothing about the camera itself was wrong, so nothing in it could catch
		# this — only an event that has to survive the GUI pass can.
		var yaw0 := _cam.rotation.y
		var pitch0 := _cam.rotation.x
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_RIGHT
		press.pressed = true
		press.position = Vector2(700, 400)
		get_viewport().push_input(press)
		await _wait(2)
		if not _cam._looking:
			fails.append("right-mouse never reached the fly camera — look is dead")
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(120, 60)
		motion.position = Vector2(700, 400)
		get_viewport().push_input(motion)
		await _wait(2)
		if is_equal_approx(_cam.rotation.y, yaw0) and is_equal_approx(_cam.rotation.x, pitch0):
			fails.append("the camera did not rotate on a right-drag (yaw %.3f pitch %.3f)"
					% [_cam.rotation.y, _cam.rotation.x])
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_RIGHT
		release.pressed = false
		release.position = Vector2(700, 400)
		get_viewport().push_input(release)
		await _wait(2)
		if _cam._looking:
			fails.append("releasing right-mouse left the camera in look mode")
		_cam.rotation = Vector3(pitch0, yaw0, 0.0)

		# FLAT COLOUR BY ROOM TYPE, and the round trip back. The restore is the half worth testing:
		# Kit.dress() hangs the theme material on every piece as a material_override, so a mode that
		# forgot to save it would strip the dungeon's surface treatment permanently and the only
		# symptom would be "the crypt looks wrong now".
		var sample: MeshInstance3D = null
		for n in _flatten(_zone):
			if n is MeshInstance3D and (n as MeshInstance3D).material_override != null:
				sample = n
				break
		var was: Material = sample.material_override if sample != null else null
		_set_render(Render.BY_TYPE)
		await _wait(3)
		await _shot(out_dir + "/build_flat.png")
		if _saved_mats.is_empty():
			fails.append("flat-by-type overrode nothing")
		var flat := _mean_luma(get_viewport().get_texture().get_image(),
				Rect2(GUTTER, MARGIN, 700.0, 500.0))
		if flat <= luma:
			fails.append("flat shading (%.3f) is no brighter than lit (%.3f)" % [flat, luma])
		_set_render(Render.LIT)
		if sample != null and sample.material_override != was:
			fails.append("flat mode did not restore the theme material it replaced")

	_set_view(View.LAYOUT)
	var report := _batch(50)
	if not report.contains("seeds"):
		fails.append("batch produced no report")
	var f := FileAccess.open(out_dir + "/census.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(report + "\n")
		f.close()
	else:
		fails.append("could not write census.txt to " + out_dir)

	# THE ASSEMBLY, AND THAT EVERY STAGE OF IT DOES SOMETHING. The stage list is hand-written and
	# the tags it matches on are not — so the failure this exists to catch is a stage that quietly
	# claims nothing, which looks exactly like a step that pauses for a beat and shows the same room.
	# The BEVELS stage is the one most likely to go silently empty, because a bevelled wall's TAG is
	# the same T_WALL as every other wall's and only its role tells them apart.
	# ON THE TREASURY, deliberately, because it is the only room type guaranteed to reach every
	# stage: it is the one that gets a dais and the one that gets a focal. Run on whichever room
	# happened to be picked, this check fails on a plain corridor cell for the entirely correct
	# reason that a corridor has no altar — which is a test that reports the dungeon working as a
	# defect.
	for anchor: Vector3i in _lay.rooms:
		if (_lay.rooms[anchor] as DungeonLayout.RoomData).type == DungeonLayout.RoomType.TREASURE:
			_picked = anchor
			_has_pick = true
			_plan_pick()
			break
	_set_view(View.ASSEMBLY)
	_asm_build()
	await _wait(3)
	if _asm_room == null or not is_instance_valid(_asm_room):
		fails.append("ASSEMBLY built no room")
	else:
		# REBUILDING MUST REFRAME, every time and not only the first. The shortcut that triggers this
		# is also the way back from having flown the camera off somewhere, so a build that framed the
		# room only when it was creating the rig would leave the button doing half its job — and
		# _stage_3d returns early once the rig exists, which is exactly the shape that mistake takes.
		# Flown deliberately out of the room here rather than nudged, so a check that only compares
		# against a tolerance cannot pass by accident.
		var framed := _cam.global_position
		_cam.global_position = framed + Vector3(400.0, 400.0, 400.0)
		_cam.h_offset = 0.0
		_asm_build()
		await _wait(2)
		if not _cam.global_position.is_equal_approx(framed):
			fails.append("rebuilding the assembly left the camera at %v, not the framing %v"
					% [_cam.global_position, framed])
		var empty: Array[String] = []
		for i in STAGES.size():
			# FOOTPRINT has no pieces by construction, and BEVELS is a per-room roll that a given
			# treasury may simply not have won — it is checked across the whole layout below.
			if i == 0 or STAGES[i]["title"] == "4. BEVELS":
				continue
			if _asm_counts[i] == 0:
				empty.append(str(STAGES[i]["title"]))
		if not empty.is_empty():
			fails.append("assembly stages claimed no pieces in a treasury: " + ", ".join(empty))
		# BEVELS cannot go quietly dead either, and it is the stage most likely to: a bevelled
		# wall's TAG is the same T_WALL as every other wall's, so only its role tells them apart.
		var bevelled := 0
		for anchor: Vector3i in _shapes:
			bevelled += (_shapes[anchor] as RoomShape).chamfer_count()
		if bevelled == 0:
			fails.append("no room in this layout has a bevelled corner")
		var total := 0
		for c in _asm_counts:
			total += c
		if total != _asm_room.get_child_count():
			fails.append("assembly stages account for %d of %d built nodes"
					% [total, _asm_room.get_child_count()])
		# The first step must show LESS than the last, or the reveal is not revealing.
		_asm_go(0)
		await _shot(out_dir + "/assembly_1.png")
		var first := _asm_visible()
		_asm_go(3)
		await _shot(out_dir + "/assembly_4.png")
		_asm_go(STAGES.size() - 1)
		await _shot(out_dir + "/assembly_last.png")
		if not (first < _asm_visible()):
			fails.append("stage 1 shows %d nodes and the last shows %d — nothing is being revealed"
					% [first, _asm_visible()])
	_set_view(View.LAYOUT)

	for msg in fails:
		printerr("[LayoutLab] FAIL: " + msg)
	print("[LayoutLab] selftest: %d failures, output in %s" % [fails.size(), out_dir])
	get_tree().quit(1 if not fails.is_empty() else 0)


func _asm_visible() -> int:
	var n := 0
	for c in _asm_room.get_children():
		if c is Node3D and (c as Node3D).visible:
			n += 1
	return n


## Put the camera on the room ROOM view is showing, at the GAME'S framing.
##
## Selftest shots used to look down on the start room from 26 m. That is the wrong subject twice
## over: START runs the `threshold` program, so it has no cover, no clutter rings and nothing to
## judge — and 26 m is not an angle any player sees. Framing the picked room instead makes the two
## screenshots a matched pair, the tile grid and the built room, and puts both at the only camera
## whose opinion counts (anime-look-todo.md: judge from a Godot screenshot at the game camera).
func _frame_picked() -> void:
	if _zone == null or not is_instance_valid(_zone):
		return
	for n in _flatten(_zone):
		if n is DungeonRoom and (n as DungeonRoom).cell == _picked:
			var room := n as DungeonRoom
			var at: Vector3 = room.global_position
			# KEEP THE ANGLE, SCALE THE DISTANCE. CameraRig's offset frames a single cell (20 x 12);
			# a 3x2 great hall is 68 x 28, and at the game's distance the lens is inside it looking at
			# a patch of floor. Backing off along the SAME vector holds the 53 degrees that every art
			# decision is judged at while fitting whatever the room actually is.
			# CAPPED, because the crypt has a fog curtain. crypt.tres sets fog_begin 40 / fog_end 70,
			# and the game's own offset is ~18 m — so backing off far enough to fit a 68 m great hall
			# puts the lens at 49 m and photographs the room through a quarter of the fog. The first
			# read of that shot was "the great hall is too dark"; it was not, it was behind weather.
			# 1.9 keeps the eye inside fog_begin, and a room bigger than that is simply not a thing
			# you can see all of in this game.
			var fit: float = clampf(maxf(room.footprint.x / DungeonLayout.ROOM_SIZE.x,
					room.footprint.z / DungeonLayout.ROOM_SIZE.z), 1.0, 1.9)
			_cam.global_position = at + Vector3(0.0, 12.5, 9.375) * 1.15 * fit
			_cam.look_at(at, Vector3.UP)
			return


func _wait(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## Mean luminance over a screen rect. The check that separates "the rig is in the right place" from
## "the rig is in the right place and there is something there".
func _mean_luma(img: Image, r: Rect2) -> float:
	var total := 0.0
	var n := 0
	var x := int(r.position.x)
	while x < mini(int(r.end.x), img.get_width()):
		var y := int(r.position.y)
		while y < mini(int(r.end.y), img.get_height()):
			var c := img.get_pixel(x, y)
			total += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			n += 1
			y += 8
		x += 8
	return total / maxf(n, 1)


func _shot(path: String) -> void:
	# Two frames, not one: the first lets the redraw queued above actually run, the second lets the
	# renderer present it. A single frame photographs the previous view.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)


# ---------------------------------------------------------------- assembly ------------------

## THE ROOM, BUILT ONE RULE AT A TIME. The bench could already show a finished room, and the
## schematic that decided it, and nothing in between — so the fact that a room is ASSEMBLED, by
## rules that each answer one question, was the one thing the tool could not show. This replays it.
##
## Built from the real pipeline, never a mock: RoomPlan plans the slots, RoomDresser builds them,
## and the stages below only change what is VISIBLE. If a rule changes, this view changes with it,
## which is the only way an explanation printed beside it stays true.
const STAGES: Array[Dictionary] = [
	{
		"title": "1. FOOTPRINT",
		"tags": [],
		"rule": "RoomShape.pick bites RECTANGLES out of the four corners, never deeper than half "
			+ "the grid. That one restriction is what makes the middle column and row — the cross "
			+ "— always survive, and every remaining tile touches the cross. Connectivity is "
			+ "therefore free: no flood fill, no rejected shapes, no room that cannot be walked "
			+ "across. Boss, treasure, start and stair rooms are never carved at all. The shape "
			+ "also decides each tile's LEVEL here, which is why there is no separate step for "
			+ "elevation: a raised floor is floor, and it is laid by the next step like all the rest.",
	},
	{
		"title": "2. FLOOR",
		"tags": [RoomPlan.T_FLOOR],
		"rule": "One 4 m tile per solid cell, laid AT ITS TILE'S OWN HEIGHT — so a gallery's deck "
			+ "appears here, with the floor, rather than as a structure bolted on later. A tile "
			+ "that ramps gets a flight instead of a slab. The flat ones are laid at a random "
			+ "QUARTER turn: two variants at four rotations read as eight, which stops the floor "
			+ "looking like a checkerboard of two patterns. Quarter turns only — a square tile at "
			+ "37 degrees puts its corners through its neighbours.",
	},
	{
		"title": "3. WALLS",
		"tags": [RoomPlan.T_WALL, RoomPlan.T_WALL_DOORWAY],
		"rule": "One wall per boundary between floor and not-floor — so a carved corner gets its "
			+ "walls for free and there is no separate 'irregular room' path anywhere in the "
			+ "generator. A boundary between two LEVELS is the same event, so the retaining wall "
			+ "under a raised floor is emitted by this loop too, for the same reason: the floor "
			+ "stops here. A wall becomes a DOORWAY where an exit's door lands on it, and those "
			+ "tile lines are protected from carving, so a room can never wall off its own exit.",
	},
	{
		"title": "4. BEVELS",
		"tags": [],
		"role": ["chamfer", "half"],
		"rule": "A convex corner may be cut back 2 m along each of its two walls. 2 m is not a "
			+ "taste: it is the only leg that leaves whole modules behind it — one 2.83 m diagonal "
			+ "(2 x root 2) plus a 2 m remainder each side. A full-leg cut needs a 5.66 m diagonal "
			+ "and nothing in the kit is that long. A corner whose wall carries a door is never "
			+ "bevelled, or a 2 m wall would stand where the opening should be.",
	},
	{
		"title": "5. COURSES",
		"tags": [RoomPlan.T_WALL_BAND, RoomPlan.T_WALL_UPPER, RoomPlan.T_WALL_CORNICE,
			RoomPlan.T_WALL_VAULT, RoomPlan.T_COVER_UPPER],
		"rule": "Band, upper course, cornice and vault hood stack on every wall. All of it is "
			+ "COLLIDER-FREE and claims no floor, which is what lets the diorama cut drop the "
			+ "camera-facing side outright and still be provably unable to change a fight. Watch "
			+ "the near wall: its courses are simply never built.",
	},
	{
		"title": "6. PLINTH",
		"tags": [RoomPlan.T_DAIS],
		"rule": "A stepped mound in the middle of a treasury or a reliquary. The one level change "
			+ "that is NOT a tile at a height: its top is 2.4 m on a 4 m tile, so it is a shape "
			+ "WITHIN a tile and the grid cannot express it. Stepped on all four sides, because "
			+ "enemies have no navmesh and no step logic — a platform with one flight is a perch "
			+ "nobody could follow you onto.",
	},
	{
		"title": "7. FOCAL",
		"tags": [RoomPlan.T_FOCAL, RoomPlan.T_KEY],
		"rule": "What the room is ABOUT goes down before the furniture, so the furniture works "
			+ "around it rather than the other way round. On a dais it is placed at the platform's "
			+ "height: the occupancy grid is 2-D and cannot express 'occupied below, free above', "
			+ "so nothing SEARCHES for a spot up there — it is put there deliberately.",
	},
	{
		"title": "8. COVER",
		"tags": [RoomPlan.T_COVER_LARGE, RoomPlan.T_COVER_SMALL],
		"rule": "RoomWeave reads what the room is FOR and lays cover as one composition — flanking "
			+ "rows in a refectory, a colonnade in a gallery, a ring in a treasury, corners only "
			+ "in an arena so the boss keeps its middle open. Every draw is keyed to the TILE and "
			+ "never to an iteration counter, so adding a door somewhere far away cannot re-roll "
			+ "furniture the door never reached.",
	},
	{
		"title": "9. LIGHT",
		"tags": [RoomPlan.T_WALL_ANCHOR],
		"lights": true,
		"rule": "Where the flames stand is composition, not decoration: candelabra spaced evenly "
			+ "round a perimeter read as furniture, the same ones down the middle of a hall read "
			+ "as an aisle, and the second tells you what the room was for. The room fill is "
			+ "deliberately dead, so the only thing lighting a floor is how many flames stand on "
			+ "it.",
	},
	{
		"title": "10. DRESSING",
		"tags": [],
		"rest": true,
		"rule": "Grime, debris, moss, fog and clutter. STYLE ONLY — this pass may never add, move "
			+ "or remove a slot or a spawn, which is what keeps every gameplay guarantee above it "
			+ "true whatever a theme does. It is also the pass that hides the 4 m lattice: debris "
			+ "is biased onto the tile joints, which is exactly where the eye was finding the "
			+ "repeat.",
	},
]

var _asm_room: Node3D
var _asm_env: WorldEnvironment
var _asm_step := 0
var _asm_playing := false
var _asm_clock := 0.0
var _asm_speed := 1.0
var _asm_counts: Array[int] = []


## Which stage a built node belongs to. The tag RoomDresser stamped answers it for everything the
## plan asked for; a light answers for itself; whatever is left came from the dressing pass.
func _asm_stage_of(n: Node) -> int:
	var tag: String = n.get_meta(RoomDresser.SLOT_META, "")
	var role: String = n.get_meta(RoomDresser.SLOT_ROLE, "")
	if tag != "":
		# A ROLE BEATS A TAG. A bevelled wall's tag is T_WALL like every other wall's, so matching
		# on the tag first would put it in stage 3 and leave stage 4 permanently empty.
		for i in STAGES.size():
			if (STAGES[i].get("role", []) as Array).has(role):
				return i
		for i in STAGES.size():
			if (STAGES[i].get("tags", []) as Array).has(tag):
				return i
	if _asm_has_light(n):
		for i in STAGES.size():
			if STAGES[i].get("lights", false):
				return i
	for i in STAGES.size():
		if STAGES[i].get("rest", false):
			return i
	return STAGES.size() - 1


func _asm_has_light(n: Node) -> bool:
	if n is Light3D:
		return true
	for c in n.get_children():
		if _asm_has_light(c):
			return true
	return false


## Build the picked room ON ITS OWN, through the real plan and the real dresser.
func _asm_build() -> void:
	_asm_clear()
	if _ctx == null or _rd == null:
		return
	_asm_room = Node3D.new()
	_asm_room.name = "AssemblyRoom"
	_subject.add_child(_asm_room)
	RoomDresser.build(_asm_room, _ctx, load(THEME) as DungeonTheme)
	for def in _ctx.spawn_defs:
		var m := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.35
		sp.height = 0.7
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.30, 0.30)
		mat.emission_enabled = true
		mat.emission = Color(0.7, 0.1, 0.1)
		sp.material = mat
		m.mesh = sp
		m.position = def["pos"]
		_asm_room.add_child(m)
		m.set_meta(RoomDresser.SLOT_META, "spawn")

	# A ROOM ON ITS OWN HAS NO SKY AND NO NEIGHBOURS, so without this the assembly opens black and
	# every stage looks identical. Deliberately flat and bright rather than the game's lighting:
	# this view is for reading construction, and crypt_tuner is where the look is judged.
	_asm_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.10, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.74, 0.72, 0.70)
	e.ambient_light_energy = 1.2
	_asm_env.environment = e
	_subject.add_child(_asm_env)

	_asm_counts.resize(STAGES.size())
	_asm_counts.fill(0)
	for n in _asm_room.get_children():
		_asm_counts[_asm_stage_of(n)] += 1
	_asm_step = 0
	_asm_apply()

	# FRAMED LOW AND RIGHT, not centred. The rule text is the other half of this view and it lives
	# in the top-left, so a room centred in the plot sits behind its own explanation. h/v_offset
	# shift the frustum rather than the camera, so the angle stays the one chosen here.
	var span := maxf(_ctx.footprint.x, _ctx.footprint.z)
	_cam.global_position = Vector3(0.0, span * 0.62, span * 0.78)
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_cam.h_offset = -span * 0.10
	_cam.v_offset = span * 0.16


func _asm_clear() -> void:
	_asm_playing = false
	if _cam != null:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
	for n in [_asm_room, _asm_env]:
		if n != null and is_instance_valid(n):
			_subject.remove_child(n)
			n.queue_free()
	_asm_room = null
	_asm_env = null


## Everything up to and including the current stage is visible; the rest is not built yet.
func _asm_apply() -> void:
	if _asm_room == null or not is_instance_valid(_asm_room):
		return
	for n in _asm_room.get_children():
		if n is Node3D:
			(n as Node3D).visible = _asm_stage_of(n) <= _asm_step
	queue_redraw()


func _asm_go(step: int) -> void:
	_asm_step = clampi(step, 0, STAGES.size() - 1)
	_asm_apply()


func _asm_tick(delta: float) -> void:
	if not _asm_playing or _view != View.ASSEMBLY:
		return
	_asm_clock += delta
	if _asm_clock < _asm_speed:
		return
	_asm_clock = 0.0
	if _asm_step >= STAGES.size() - 1:
		_asm_playing = false
		queue_redraw()
		return
	_asm_go(_asm_step + 1)


func _draw_assembly() -> void:
	var y := MARGIN
	if _asm_room == null or not is_instance_valid(_asm_room):
		_text(Vector2(GUTTER, y), "no room — pick one in LAYOUT, then press build", 15, WARN)
		return
	# A BACKDROP UNDER THE WORDS. This view draws prose over a lit 3-D room, and pale text on pale
	# masonry is unreadable exactly when the room is interesting.
	var panel_w: float = maxf(320.0, size.x - GUTTER - MARGIN
			- (LEGEND_W + 40.0 if _legend else 0.0))
	draw_rect(Rect2(GUTTER - 12.0, MARGIN - 12.0,
			panel_w + 24.0, 118.0 + STAGES.size() * 15.0), Color(0.07, 0.07, 0.09, 0.82))
	var st: Dictionary = STAGES[_asm_step]
	_text(Vector2(GUTTER, y), "ASSEMBLY   %s   step %d of %d   %s"
			% [st["title"], _asm_step + 1, STAGES.size(),
			"PLAYING" if _asm_playing else "paused"], 16, INK)
	y += 20
	_text(Vector2(GUTTER, y), "%s  %s  seed %d   %d pieces this step, %d standing"
			% [TYPE_NAME[_rd.type], _rd.module_id, _seed,
			_asm_counts[_asm_step], _asm_built_so_far()], 12, DIM)
	y += 24

	# Wrapped by hand: draw_string does no wrapping, and the explanation IS the view, so it cannot
	# be allowed to run off the side of the window.
	for line in _wrap(str(st["rule"]), panel_w, 14):
		_text(Vector2(GUTTER, y), line, 14, Color(0.80, 0.84, 0.92))
		y += 19

	# The whole ladder, so the sequence is visible rather than only where it has reached.
	y += 12
	for i in STAGES.size():
		var done := i <= _asm_step
		var col := INK if i == _asm_step else (Color(0.42, 0.68, 0.48) if done else DIM)
		_text(Vector2(GUTTER, y), "%s %-14s %s"
				% ["[x]" if done else "[ ]", STAGES[i]["title"],
				"%d pieces" % _asm_counts[i] if _asm_counts[i] > 0 else "—"], 12, col)
		y += 15


func _asm_built_so_far() -> int:
	var n := 0
	for i in _asm_counts.size():
		if i <= _asm_step:
			n += _asm_counts[i]
	return n


## Greedy word wrap against the real font metrics, so it stays correct at any window width.
func _wrap(text: String, width: float, px: int) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word in text.split(" ", false):
		var trial: String = word if line == "" else line + " " + word
		if _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out

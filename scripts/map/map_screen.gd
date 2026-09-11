extends Node
## Autoload "MapScreen" — THE VIEW. Built in code on its own CanvasLayer, like Hud, Dialogue and
## Pause: zero per-scene setup, nothing for a zone to provide.
##
## LAYER 28. The documented stack (hud.gd:29) is grade 10, HUD 20, dialogue 25, pause 30, fade 128.
## Above dialogue so a conversation box cannot bleed through the sheet; below pause so the menu is
## still legible if it ever lands on top; below the fade so a zone transition blacks the map out too.
##
## IT PAUSES THE TREE, and does so through Pause.hold() rather than by writing get_tree().paused
## itself. The reason is concrete: pause_menu.gd DERIVES its state from that flag, so a second
## writer desynchronises it — open map, press Esc, hit Resume, and the world unfreezes with the map
## still up. One owner, named holds, no such class of bug.
##
## Pausing rather than a Dialogue-style `active` flag, because NOTHING IN enemy.gd GUARDS ON THAT
## FLAG. The complete list of Dialogue.active guard sites is hud.gd:68, player.gd:480, npc.gd:87 and
## state_machine.gd:38 — a flag-only map means being hit by a brute while reading it, and fixing
## that properly would mean guards in the enemy, spawner, swarmling and projectile code. A real
## pause needs two guard sites and gets camera_rig's right-stick peek and see_through for free.

const LAYER := 28

## Multipliers of the fit-the-whole-zone zoom. Discrete, because the inked geometry is rebuilt per
## zoom level and a continuous zoom would rebuild it every frame — and because a map that snaps to
## a few honest scales reads better than one that drifts.
const ZOOM_STEPS := [0.75, 1.0, 1.6, 2.6, 4.2]
const FIT_MARGIN := 0.92
const PAN_SPEED := 620.0                ## screen px per second at any zoom

## How close the cursor must be to a marker to delete it, in screen px.
const GRAB_PX := 18.0

var open := false

var _layer: CanvasLayer
var _root: Control
var _parchment: ColorRect
var _relief: ColorRect
var _plan: Control
var _fog: ColorRect
var _overlay: Control
var _font: Font

var _zoom_i := 1
var _fit := 1.0
var _zoom := 1.0
var _pan := Vector2.ZERO                ## zone-local metres shown at the view centre
var _floor := 0
var _kind := 0

var _disc: ImageTexture
var _vista_tex: ImageTexture
var _cursor := Vector2.ZERO             ## screen px
var _mouse_driven := false

## Inked geometry, in SHEET px (metres from the grid rect's corner, times zoom). Panning is then a
## pure translation of cached points, so only a zoom or a zone change rebuilds — which also means
## the hand-drawn wobble stays welded to the geometry instead of crawling as you scroll.
var _ink: Array = []
var _ink_zoom := -1.0
var _ink_key := ""
var _ink_floor := -9999

## The view transform the plan was last DRAWN at. _draw_plan resolves _sheet_origin() at draw time,
## but a Control only re-runs _draw() when something queues it — and the only thing queueing it used
## to be _build_ink(), which runs on a zoom or zone change and not on a pan. So panning moved the
## parchment and fog (shader uniforms, set every frame) and the pip, markers and cursor (overlay,
## redrawn every frame) while the ink stayed nailed where it was, and the layers slid apart.
var _drawn_pan := Vector2.INF
var _drawn_zoom := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # must keep drawing while the tree is frozen
	_font = ThemeDB.fallback_font

	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	add_child(_layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP    # eat clicks so they never reach the game
	_root.visible = false
	_layer.add_child(_root)

	_parchment = _full_rect(load("res://shaders/map_parchment.gdshader"))
	# Between the paper and the ink: the shape of the world, including everything you cannot walk on.
	_relief = _full_rect(load("res://shaders/map_relief.gdshader"))
	_plan = Control.new()
	_plan.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan.draw.connect(_draw_plan)
	_root.add_child(_plan)
	_fog = _full_rect(load("res://shaders/map_fog.gdshader"))
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)

	# A portal firing while the sheet is up would leave you reading the map of a zone you have left.
	EventBus.zone_changed.connect(func(_n: String) -> void: close())


func _full_rect(sh: Shader) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	r.material = mat
	_root.add_child(r)
	return r


# --- OPEN / CLOSE ------------------------------------------------------------------------------


func toggle() -> void:
	if open:
		close()
	else:
		show_map()


func show_map() -> void:
	# Never over a conversation, and never on top of the pause menu or a zone fade. `paused` covers
	# the last two without having to know about either.
	if open or Dialogue.active or get_tree().paused:
		return
	if MapData.current == null or MapData.current.grid == null:
		return
	open = true
	_root.visible = true
	Pause.hold(&"map", true)
	Hud.suppress(true)
	_floor = MapData.player_floor()
	_recentre()
	_refresh_discovery()
	_ink_zoom = -1.0                              # force a rebuild: the zone may have changed
	_drawn_pan = Vector2.INF                      # ...and a redraw at whatever _recentre just chose
	_plan.queue_redraw()


func close() -> void:
	if not open:
		return
	open = false
	_root.visible = false
	Pause.hold(&"map", false)
	Hud.suppress(false)
	MapData.save()


## Zoom index the map opens at. Not 0: "the whole zone with margin" is a good overview and a poor
## place to read detail, so one step in is the better first impression.
const DEFAULT_ZOOM := 1


func _recentre() -> void:
	var grid: MapGrid = MapData.current.grid
	var view := _root.size
	# A new zone starts at the default zoom. Carrying the last zone's zoom over means walking out of
	# a 100 m crypt into a 234 m hub and opening the map already scrolled into a corner of it.
	if _ink_key != MapData.current.key:
		_zoom_i = DEFAULT_ZOOM
	_fit = minf(view.x / maxf(grid.rect.size.x, 1.0), view.y / maxf(grid.rect.size.y, 1.0)) * FIT_MARGIN
	_zoom = _fit * ZOOM_STEPS[_zoom_i]
	_pan = MapData.player_local()
	_cursor = view * 0.5
	_mouse_driven = false


# --- INPUT -------------------------------------------------------------------------------------


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not open:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_step_zoom(1)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_step_zoom(-1)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_cursor = (event as InputEventMouseMotion).position
		_mouse_driven = true
		_overlay.queue_redraw()


## Everything analog is polled rather than event-driven: a stick held off-centre produces one
## action_pressed and then nothing, which is wrong for panning and unreliable for stepped zoom.
func _process(delta: float) -> void:
	if not open:
		return
	if MapData.current == null or MapData.current.grid == null:
		close()
		return

	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move != Vector2.ZERO:
		# Divided by zoom so the sheet slides at a constant SCREEN speed however far in you are.
		_pan += move * (PAN_SPEED / _zoom) * delta
		_mouse_driven = false
		_cursor = _root.size * 0.5
		_clamp_pan()

	if Input.is_action_just_pressed("aim_up"):
		_step_zoom(1)
	elif Input.is_action_just_pressed("aim_down"):
		_step_zoom(-1)

	if Input.is_action_just_pressed("dash"):
		_pan = MapData.player_local()
		_clamp_pan()

	if Input.is_action_just_pressed("aim_right") or Input.is_action_just_pressed("ui_right"):
		_kind = wrapi(_kind + 1, 0, MapStyle.MARKER_NAMES.size())
	elif Input.is_action_just_pressed("aim_left") or Input.is_action_just_pressed("ui_left"):
		_kind = wrapi(_kind - 1, 0, MapStyle.MARKER_NAMES.size())

	if Input.is_action_just_pressed("shoot"):
		_cycle_floor()

	if Input.is_action_just_pressed("interact"):
		MapData.add_marker(_kind, _cursor_local(), _floor)
	elif Input.is_action_just_pressed("block"):
		MapData.remove_marker_near(_cursor_local(), GRAB_PX / _zoom)

	_sync_shaders()
	if _ink_zoom != _zoom or _ink_key != MapData.current.key or _ink_floor != _floor:
		_build_ink()
	# The plan moves with the view, so it has to be REDRAWN with the view. Everything else on screen
	# updates every frame for free; this is the one layer that does not.
	if _pan != _drawn_pan or _zoom != _drawn_zoom:
		_drawn_pan = _pan
		_drawn_zoom = _zoom
		_plan.queue_redraw()
	_overlay.queue_redraw()


func _step_zoom(dir: int) -> void:
	var next := clampi(_zoom_i + dir, 0, ZOOM_STEPS.size() - 1)
	if next == _zoom_i:
		return
	_zoom_i = next
	_zoom = _fit * ZOOM_STEPS[_zoom_i]
	_clamp_pan()


## Keep the sheet within reach of the view. Without this, panning at high zoom wanders off into
## blank fog with no landmark to navigate back by.
func _clamp_pan() -> void:
	var r: Rect2 = MapData.current.grid.rect
	var slack := _root.size / _zoom * 0.5
	_pan.x = clampf(_pan.x, r.position.x - slack.x, r.end.x + slack.x)
	_pan.y = clampf(_pan.y, r.position.y - slack.y, r.end.y + slack.y)


func _cycle_floor() -> void:
	var lay := MapData.dungeon_layout()
	if lay == null:
		return
	var floors: Array = []
	for anchor: Vector3i in lay.rooms:
		var f: int = (lay.rooms[anchor] as DungeonLayout.RoomData).cell.y
		if not floors.has(f):
			floors.append(f)
	if floors.size() < 2:
		return
	floors.sort()
	var i := floors.find(_floor)
	_floor = floors[wrapi(i + 1, 0, floors.size())]


# --- TRANSFORMS --------------------------------------------------------------------------------


## Screen px of the grid rect's top-left corner. Everything else is this plus a scaled offset.
func _sheet_origin() -> Vector2:
	var r: Rect2 = MapData.current.grid.rect
	return _root.size * 0.5 + (r.position - _pan) * _zoom


func _to_screen(local: Vector2) -> Vector2:
	return _root.size * 0.5 + (local - _pan) * _zoom


func _to_local(screen: Vector2) -> Vector2:
	return (screen - _root.size * 0.5) / _zoom + _pan


func _cursor_local() -> Vector2:
	return _to_local(_cursor if _mouse_driven else _root.size * 0.5)


func _sync_shaders() -> void:
	var grid: MapGrid = MapData.current.grid
	var view := _root.size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var origin := _sheet_origin() / view
	var size := (grid.rect.size * _zoom) / view
	for rect in [_parchment, _relief, _fog]:
		var m := (rect as ColorRect).material as ShaderMaterial
		m.set_shader_parameter("sheet_uv_origin", origin)
		m.set_shader_parameter("sheet_uv_size", size)
		m.set_shader_parameter("map_uv_origin", origin)
		m.set_shader_parameter("map_uv_size", size)
		m.set_shader_parameter("aspect", view.x / view.y)
	# The capture arrives a few frames after the zone binds, so this is rebound every frame rather
	# than once on open — a map opened during those frames must pick it up when it lands.
	_relief.visible = MapData.current.relief != null
	if _relief.visible:
		(_relief.material as ShaderMaterial).set_shader_parameter("relief", MapData.current.relief)
	var vista: MapGrid = MapData.current.vista
	if grid.dirty or _disc == null or (vista and vista.dirty) or (vista and _vista_tex == null):
		_refresh_discovery()


func _refresh_discovery() -> void:
	var grid: MapGrid = MapData.current.grid
	var img := grid.to_image()
	if _disc == null or _disc.get_size() != Vector2(grid.w, grid.h):
		_disc = ImageTexture.create_from_image(img)
	else:
		_disc.update(img)
	grid.dirty = false
	(_fog.material as ShaderMaterial).set_shader_parameter("discovery", _disc)

	# The vista covers the SAME rect at a coarser cell size, so both textures are addressed by the
	# identical UV and neither shader needs a second transform.
	var vista: MapGrid = MapData.current.vista
	if vista == null:
		_vista_tex = null
	else:
		var vimg := vista.to_image()
		if _vista_tex == null or _vista_tex.get_size() != Vector2(vista.w, vista.h):
			_vista_tex = ImageTexture.create_from_image(vimg)
		else:
			_vista_tex.update(vimg)
		vista.dirty = false
	for rect in [_fog, _relief]:
		(rect.material as ShaderMaterial).set_shader_parameter("vista", _vista_tex)


# --- THE PLAN ----------------------------------------------------------------------------------


func _build_ink() -> void:
	_ink.clear()
	_ink_zoom = _zoom
	_ink_key = MapData.current.key
	_ink_floor = _floor
	if MapData.current.is_dungeon:
		_build_dungeon_ink()
	else:
		_build_world_ink()
	_plan.queue_redraw()


## Sheet px from zone-local metres.
func _sheet(p: Vector2) -> Vector2:
	return (p - MapData.current.grid.rect.position) * _zoom


func _sheet_poly(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = _sheet(poly[i])
	return out


func _build_world_ink() -> void:
	var zone := MapData.zone_node
	if zone == null or not is_instance_valid(zone):
		return
	var plan := MapPainter.plan_from_collision(zone)
	if plan.is_empty():
		return

	# Elevation bands. The hub drops ~14 m from the house to the arena, and a flat fill makes that
	# descent invisible — which matters, because "the arena is BELOW the garden" is most of what a
	# player is confused about here.
	var lo := INF
	var hi := -INF
	for item in plan:
		if item["kind"] == MapPainter.Kind.FLOOR:
			lo = minf(lo, item["y"])
			hi = maxf(hi, item["y"])
	var span := maxf(hi - lo, 0.001)

	# Order matters: floors sorted deepest-first so the house paints over the arena where the ramp
	# bridges them, not the other way round.
	var floors: Array = []
	for item in plan:
		if item["kind"] == MapPainter.Kind.FLOOR:
			floors.append(item)
	floors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["y"] < b["y"])

	var salt := 0
	for item in floors:
		var t: float = clampf((item["y"] - lo) / span, 0.0, 1.0)
		# FILLS ARE NEVER WOBBLED. draw_colored_polygon triangulates, and displacing the vertices of
		# a 0.5 m wall by a px or two at map scale is enough to make it self-intersect — which is
		# exactly the "Invalid polygon data, triangulation failed" this used to spam every frame.
		# The fill sits under a 2 px double-stroke outline anyway, so the raw edge never shows.
		_ink.append({
			"op": "fill",
			"pts": _sheet_poly(item["poly"]),
			"color": MapStyle.DEPTH_LOW.lerp(MapStyle.PARCHMENT, t),
		})
	# The seams between slabs, faint — paving, not walls.
	for item in floors:
		_ink.append({
			"op": "line",
			"pts": MapStyle.wobble(_sheet_poly(item["poly"]), salt, true, MapStyle.WOBBLE * 0.6),
			"color": MapStyle.INK_FAINT,
			"width": 1.0,
		})
		salt += 1

	# THE OUTER BOUNDARY, inked properly. Sixteen rectangles outlined individually read as a pile of
	# rectangles; their union outlined once reads as the edge of the world.
	for poly in MapPainter.merge_floors(plan):
		_ink.append({
			"op": "line",
			"pts": MapStyle.wobble(_sheet_poly(poly), salt, true),
			"color": MapStyle.INK,
			"width": 2.0,
		})
		salt += 1

	for item in plan:
		if item["kind"] != MapPainter.Kind.WALL:
			continue
		var raw := _sheet_poly(item["poly"])
		_ink.append({"op": "fill", "pts": raw, "color": Color(MapStyle.INK, 0.72)})
		_ink.append({
			"op": "line",
			"pts": MapStyle.wobble(raw, salt, true, MapStyle.WOBBLE * 0.5),
			"color": MapStyle.INK,
			"width": 1.3,
		})
		salt += 1


func _build_dungeon_ink() -> void:
	var lay := MapData.dungeon_layout()
	if lay == null:
		return
	var seen: Dictionary = MapData.current.rooms_seen
	var d := MapPainter.plan_from_layout(lay, _floor)
	var salt := 0

	# Corridors under the rooms, so a room's outline closes cleanly over the passage mouth.
	for link: Dictionary in d["links"]:
		var a: Vector2 = link["a"]
		var b: Vector2 = link["b"]
		# Only where BOTH ends are known — otherwise the corridor gives away a room you have not
		# found, which is the one thing a dungeon map must not do.
		if not (_room_seen(seen, lay, a) and _room_seen(seen, lay, b)):
			continue
		var locked: bool = link["type"] == DungeonLayout.EdgeType.LOCKED
		_ink.append({
			"op": "line",
			"pts": MapStyle.wobble(PackedVector2Array([_sheet(a), _sheet(b)]), salt, false),
			"color": MapStyle.DANGER if locked else MapStyle.INK,
			"width": 4.0 if locked else 3.0,
			"closed": false,
		})
		salt += 1

	var outlines: Dictionary = MapData.current.room_outlines
	for room: Dictionary in d["rooms"]:
		var level: int = seen.get(room["cell"], 0)
		if level == 0:
			continue                                  # never seen: it is not on the map at all
		var r: Rect2 = room["rect"]
		# The REAL floor outline where it was measured; the layout's cell block only as a fallback
		# for a room with no floor tiles to measure (nothing generates one today).
		var shapes: Array = outlines.get(room["cell"], [])
		if shapes.is_empty():
			shapes = [PackedVector2Array([
				r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])]

		for shape: PackedVector2Array in shapes:
			var poly := _sheet_poly(shape)
			var pts := MapStyle.wobble(poly, salt, true)
			if level >= 2:
				_ink.append({"op": "fill", "pts": poly, "color": MapStyle.PARCH_DEEP})
				_ink.append({"op": "line", "pts": pts, "color": MapStyle.INK, "width": 2.0})
			else:
				# Known through a door but not entered: outline only, no contents. The Isaac read.
				_ink.append({"op": "line", "pts": pts, "color": MapStyle.KNOWN, "width": 1.4})
			salt += 1

		# One badge per ROOM, not per polygon, and placed on the cell block's centre — the carving
		# rule keeps the middle column and row, so that point is always inside the floor.
		if level >= 2:
			_ink.append({
				"op": "badge",
				"at": _sheet(r.get_center()),
				"type": room["type"],
				"key": room["key"],
			})


## Which room a corridor endpoint belongs to, and whether it is known. The endpoint is a CELL
## centre, so a containment test against room rects is exact — no nearest-room guessing.
func _room_seen(seen: Dictionary, lay: DungeonLayout, at: Vector2) -> bool:
	for anchor: Vector3i in lay.rooms:
		var rd: DungeonLayout.RoomData = lay.rooms[anchor]
		if rd.cell.y != _floor:
			continue
		var mid := DungeonLayout.room_origin(rd)
		var ext := DungeonLayout.size_of(rd)
		var rect := Rect2(mid.x - ext.x * 0.5, mid.z - ext.z * 0.5, ext.x, ext.z).grow(2.0)
		if rect.has_point(at):
			return int(seen.get(anchor, 0)) >= 1
	return false


func _draw_plan() -> void:
	if not open or MapData.current == null:
		return
	_plan.draw_set_transform(_sheet_origin(), 0.0, Vector2.ONE)
	for item: Dictionary in _ink:
		match item["op"]:
			"fill":
				_plan.draw_colored_polygon(item["pts"], item["color"])
			"line":
				MapStyle.ink(_plan, item["pts"], item["color"], item.get("width", 1.7),
						item.get("closed", true))
			"badge":
				_room_badge(item["at"], item["type"], item["key"])
	_plan.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _room_badge(at: Vector2, type: int, key: String) -> void:
	match type:
		DungeonLayout.RoomType.START:
			MapStyle._glyph(_plan, at, MapData.Marker.HOME, 8.0, MapStyle.INK)
		DungeonLayout.RoomType.BOSS:
			_plan.draw_arc(at, 9.0, 0.0, TAU, 16, MapStyle.DANGER, 2.2, true)
			_plan.draw_line(at + Vector2(-4, -4), at + Vector2(4, 4), MapStyle.DANGER, 2.0, true)
			_plan.draw_line(at + Vector2(4, -4), at + Vector2(-4, 4), MapStyle.DANGER, 2.0, true)
		DungeonLayout.RoomType.TREASURE:
			MapStyle._glyph(_plan, at, MapData.Marker.CHEST, 9.0, MapStyle.GOLD)
		DungeonLayout.RoomType.STAIR:
			for i in 4:
				var y := -7.0 + float(i) * 4.0
				_plan.draw_line(at + Vector2(-6, y), at + Vector2(6, y), MapStyle.INK, 1.6, true)
	if key != "":
		_plan.draw_circle(at + Vector2(12, -10), 3.0, MapStyle.GOLD)


# --- OVERLAY -----------------------------------------------------------------------------------


func _draw_overlay() -> void:
	if not open or MapData.current == null:
		return
	var grid: MapGrid = MapData.current.grid

	for m: Dictionary in MapData.markers():
		if MapData.current.is_dungeon and int(m["f"]) != _floor:
			continue
		var at: Vector2 = m["p"]
		MapStyle.marker(_overlay, _to_screen(at), int(m["k"]), 11.0,
				float(grid.value_at(at)) / 255.0)

	MapStyle.pip(_overlay, _to_screen(MapData.player_local()), MapData.player_heading())

	var view := _root.size
	MapStyle.compass(_overlay, Vector2(view.x - 54.0, 54.0), _font)
	_draw_frame(view)
	_draw_palette(view)
	_draw_cursor()

	var title := "THE CRYPT  ·  seed %d" % MapData.current.dungeon_seed \
			if MapData.current.is_dungeon else "THE VALE"
	_overlay.draw_string(_font, Vector2(34, 48), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			MapStyle.INK)
	if MapData.current.is_dungeon:
		_overlay.draw_string(_font, Vector2(34, 74), "floor %d   [Q] next" % _floor,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(MapStyle.INK, 0.7))
	_overlay.draw_string(_font, Vector2(34, view.y - 26),
			"WASD/stick pan   ·   wheel/R-stick zoom   ·   E place   ·   RMB remove   ·   M close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(MapStyle.INK, 0.6))


## A torn-paper edge, so the sheet reads as an object lying over the frozen game rather than as a
## rectangle of UI.
func _draw_frame(view: Vector2) -> void:
	var inset := 18.0
	var edge := PackedVector2Array([
		Vector2(inset, inset), Vector2(view.x - inset, inset),
		Vector2(view.x - inset, view.y - inset), Vector2(inset, view.y - inset)])
	MapStyle.ink(_overlay, MapStyle.wobble(edge, 7, true, 2.6), Color(MapStyle.INK, 0.75), 2.4, true)


func _draw_palette(view: Vector2) -> void:
	# Always visible rather than a modal picker: on a controller "cycle then place" is one fewer
	# mode than "open a dialog, navigate it, confirm", and it keeps the whole marker feature to two
	# bindings that already exist.
	var n := MapStyle.MARKER_NAMES.size()
	var at := Vector2(view.x * 0.5 - float(n - 1) * 20.0, view.y - 62.0)
	for i in n:
		var p := at + Vector2(float(i) * 40.0, 0.0)
		if i == _kind:
			_overlay.draw_circle(p, 17.0, Color(MapStyle.ACCENT, 0.30))
		MapStyle.marker(_overlay, p, i, 11.0, 1.0 if i == _kind else 0.45)
	_overlay.draw_string(_font, at + Vector2(-6, 28), "◄ %s ►" % MapStyle.MARKER_NAMES[_kind],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(MapStyle.INK, 0.8))


func _draw_cursor() -> void:
	var c := _cursor if _mouse_driven else _root.size * 0.5
	_overlay.draw_arc(c, 13.0, 0.0, TAU, 24, Color(MapStyle.INK, 0.55), 1.3, true)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var d := Vector2(cos(a), sin(a))
		_overlay.draw_line(c + d * 7.0, c + d * 17.0, Color(MapStyle.INK, 0.75), 1.3, true)

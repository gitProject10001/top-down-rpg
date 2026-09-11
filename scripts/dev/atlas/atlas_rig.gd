extends RefCounted
## DRIVES THE GLADEKIT PIPELINE FROM OUTSIDE THE ADDON — one stage at a time, so the atlas can show
## a wall assembling itself rule by rule.
##
## DELIBERATELY NO `class_name`, like scripts/dev/tuning_panel.gd: registering a global class forces
## an editor rescan, and a rescan once re-saved and corrupted a tuned style .tres. Consumers
## `preload()` this by path.
##
## THIS FILE IS THE DEMONSTRATION, not just its scaffolding. Every line below uses the addon's
## PUBLIC surface — `GladeStoreyStack.new()`, `GladeWallFrame.new()`, `GladeBuildBuffer.new()`,
## `GladeWallPipeline.STAGES` — and there is no `GladeWall` node anywhere in it, no editor, and no
## private access. Before the refactor the equivalent code was ninety private methods on a
## 3,214-line node and this file could not have been written at all.
##
## WHAT IT DOES NOT DO is diverge from the real thing. `verify_against_wall()` builds an actual
## `GladeWall` from the same intent and compares placements; the atlas shows the result as a badge.
## A second driver of the same pipeline is exactly the sort of thing that rots quietly, so it is
## checked on every rebuild rather than trusted.

const STYLE_STONE := "res://addons/gladekit/styles/alsace_stone.tres"
const STYLE_TIMBER := "res://addons/gladekit/styles/alsace_timber.tres"
const STYLE_CLAY := "res://addons/gladekit/styles/adobe_clay.tres"

## What the caller asks for. Plain data: the atlas edits these and calls `build()` again.
var style_path := STYLE_STONE
## Untyped on purpose: a caller writing `rig.points = [Vector3.ZERO, ...]` hands over an untyped
## Array, and `Array[Vector3]` refuses it outright rather than converting.
var points: Array = []
var wall_height := 2.4
var rng_seed := 7
var storeys: Array = []                        ## Array[GladeStorey]
var openings: Array = []                       ## the opening dictionaries, if any
var weather := 0.0                             ## a uniform mask amount, 0 = clean
var junction_rank := 0
var rival_volumes: Array = []                  ## another building's claim, for the junction knob
var adobe_cell := 0.0                          ## 0 = leave the style's own value

## Marker nodes this rig created for `make_opening()`, freed by `dispose()`. They are never added to
## the tree — they exist only to be the right TYPE.
var _markers: Array = []

## What the last `build()` produced.
var ctx: GladeWallContext = null
var stage_names: PackedStringArray = []        ## one per pipeline stage, in order
var stage_paths: PackedStringArray = []
var stage_ms := PackedFloat32Array()
## Per stage, per slot: [from, to) into `ctx.buffer.xforms[slot]`. This is how the atlas knows which
## pieces a given stage put there.
var stage_ranges: Array = []
var total_ms := 0.0
var error := ""


# ---------------------------------------------------------------- building -------------------


## Assemble a context and run every stage, recording what each one added.
##
## The context is the whole point: it is the ONLY thing a generator is handed, and everything in it
## has a public constructor. Note what is absent — `self`, any node, the scene tree. The four things
## only a Node3D can do arrive as narrow Callables, and here they are satisfied by a plain holder.
func build(holder: Node3D) -> bool:
	error = ""
	ctx = null
	stage_names = PackedStringArray()
	stage_paths = PackedStringArray()
	stage_ms = PackedFloat32Array()
	stage_ranges = []
	total_ms = 0.0

	if points.size() < 2:
		error = "a wall needs at least two points"
		return false

	var style_res := load(style_path) as GladeStyle
	if style_res == null:
		error = "could not load %s" % style_path
		return false
	# `current_style` is the hot-reload guard: a style loaded before a knob existed reads null for
	# it and explodes deep inside generation. The real node calls this too.
	var st := GladeUtil.current_style(style_res)
	if adobe_cell > 0.001:
		st = st.duplicate() as GladeStyle
		st.adobe_cell = adobe_cell

	var curve := Curve3D.new()
	for p: Vector3 in points:
		curve.add_point(p)

	# --- the collaborators, each owning one domain ------------------------------------------
	var stack := GladeStoreyStack.new(storeys, wall_height)
	var frame := GladeWallFrame.new(curve, stack, null, st.corner_angle_deg)
	var buffer := GladeBuildBuffer.new(st.brick_meshes.size())

	ctx = GladeWallContext.new()
	ctx.style = st
	ctx.rng_seed = rng_seed
	ctx.tie = 1
	ctx.tee_quoins = true
	ctx.generate_collision = false             # the atlas draws art, not physics
	ctx.conform = false
	ctx.frame = frame
	ctx.stack = stack
	ctx.buffer = buffer
	ctx.ground = GladeGround.none()
	ctx.claim = GladeClaim.new(rival_volumes, junction_rank, 1, holder.to_global)
	ctx.weather = GladeWeatherField.new(_mask(frame, stack), stack.total_height(), ctx.rng)
	ctx.openings = _prepare_openings(st, frame, stack)
	ctx.breaks = frame.breaks
	ctx.courses = maxi(1, int(round(stack.total_height() / st.course_height)))
	ctx.weather.courses = ctx.courses
	ctx.roofed = false
	# the four node capabilities, satisfied without a node
	ctx.adopt = func(n: Node) -> void: holder.add_child(n)
	ctx.to_world = holder.to_global
	ctx.to_local = holder.to_local
	ctx.origin_world = holder.global_position
	ctx.own_rid = func(_r: RID) -> void: pass
	ctx.neighbours = func() -> Array: return []
	ctx.my_volumes = func() -> Array: return []

	# --- run the stages, recording what each one added --------------------------------------
	var slots := buffer.variants + 1
	for gs: GDScript in GladeWallPipeline.STAGES:
		var before := PackedInt32Array()
		for s in slots:
			before.append(buffer.count(s))

		var t0 := Time.get_ticks_usec()
		(gs.new() as GladeWallStage).run(ctx)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0

		var ranges: Array = []
		for s in slots:
			ranges.append([before[s], buffer.count(s)])
		stage_ranges.append(ranges)
		stage_ms.append(ms)
		total_ms += ms
		stage_paths.append(gs.resource_path)
		stage_names.append(_class_of(gs))
	return true


## AN OPENING DICTIONARY WITH A REAL MARKER IN IT — which is not a formality.
##
## The stages ask `o.node is GladeOpening` to tell an author-placed hole from a `GladePath` crossing
## the wall, and the two are treated very differently: a path's gap is a way through, so it gets no
## sill, no lintel, no jambs and no window frame. Hand the pipeline a dictionary with `node: null`
## and it correctly builds a *path gap*, which is a fine thing to be but is not a window.
##
## That is exactly what the first version of this file did, and the drift badge caught it: the rig
## laid 137 pieces where the node laid 136, missing two lining members and a frame prop. The marker
## is never added to the tree; it exists only so the type test answers truthfully.
func make_opening(at: float, w: float, h: float, sill: float, arched := false) -> Dictionary:
	var m := GladeOpening.new()
	m.width = w
	m.height = h
	m.arched = arched
	_markers.append(m)
	return {"at": at, "w": w, "h": h, "sill": sill, "arched": arched, "node": m,
			"pad_x": 0.0, "pad_b": 0.0, "pad_t": 0.0}


## Free the marker nodes. Call before rebuilding a chapter's openings, and on teardown.
func dispose() -> void:
	for m in _markers:
		if is_instance_valid(m):
			(m as Node).free()
	_markers.clear()


## WHAT THE NODE DOES TO AN OPENING BEFORE THE FILL SEES IT, reproduced here.
##
## `GladeWall._make_context()` does two things to the raw markers, and skipping either makes this
## rig quietly wrong: it snaps openings to bay boundaries in timber mode, and it grows every cut by
## its lining pads so the sill and lintel have a band to fill. The first version of this file did
## neither, and the drift badge caught it immediately — 137 pieces against the node's 154.
##
## Both are done through the addon's own public functions (`GladeFillTimber.bays_of`,
## `GladeStageOpenings.lining_pads`) rather than reimplemented, so there is nothing here to drift.
## Only `_nearest` is inlined, because it is five lines of "closest value in a list".
func _prepare_openings(st: GladeStyle, frame: GladeWallFrame,
		stack: GladeStoreyStack) -> Array:
	var out: Array = []
	for o in openings:
		out.append((o as Dictionary).duplicate())   # never mutate the caller's intent
	if out.is_empty():
		return out

	# THE SAME ROUND TRIP THE NODE APPLIES. A real `GladeOpening` is a marker in space, and
	# `_collect_openings` turns it into an arc offset with `curve.get_closest_offset(o.position)`.
	# That projection is not perfectly idempotent against the baked polyline — it lands within a
	# fraction of a millimetre — and a hole shifted by a fraction of a millimetre is one brick
	# different where its edge falls. Feeding an exact offset in and comparing against a projected
	# one cost exactly one piece, which is the sort of discrepancy that gets waved away as noise.
	for o in out:
		o.at = frame.curve.get_closest_offset(frame.plumb(o.at))

	if _any_timber(st, stack):
		for o in out:
			var lo := 0.0
			var hi := 0.0
			for ri in frame.breaks.size() - 1:
				if o.at >= frame.breaks[ri] and o.at <= frame.breaks[ri + 1]:
					lo = frame.breaks[ri]
					hi = frame.breaks[ri + 1]
					break
			if hi - lo < 0.1:
				continue
			var bays := GladeFillTimber.bays_of(stack.style_at(st, o.sill), lo, hi)
			var e0 := _nearest(bays, o.at - o.w * 0.5)
			var e1 := _nearest(bays, o.at + o.w * 0.5)
			if e1 - e0 < 0.3:
				continue
			var t: float = clampf(st.timber_size, 0.04, 0.5)
			o.at = (e0 + t + e1) * 0.5
			o.w = maxf(e1 - e0 - t, 0.3)

	# AFTER the snap, which moves and resizes the hole — the lining dresses the final opening
	for o in out:
		var pad := GladeStageOpenings.lining_pads(st, o, stack)
		o.pad_x = pad.x
		o.pad_b = pad.bottom
		o.pad_t = pad.top
	return out


static func _any_timber(st: GladeStyle, stack: GladeStoreyStack) -> bool:
	if st.get("wall_mode") == GladeStyle.WallMode.TIMBER:
		return true
	for s in stack.styles:
		if s and s.get("wall_mode") == GladeStyle.WallMode.TIMBER:
			return true
	return false


static func _nearest(values: Array[float], target: float) -> float:
	var best: float = values[0]
	for v in values:
		if absf(v - target) < absf(best - target):
			best = v
	return best


## A uniform weather mask over the whole face, so one slider drives stain → moss → crumble.
## Built through `GladeWeatherField.paint()` — the same function the editor brush calls — rather
## than by writing keys, so the atlas cannot disagree with the brush about what a cell is.
func _mask(frame: GladeWallFrame, stack: GladeStoreyStack) -> Dictionary:
	var m := {}
	if weather <= 0.001:
		return m
	var h := stack.total_height()
	var arc := 0.0
	while arc <= frame.length:
		var z := 0.0
		while z <= h:
			GladeWeatherField.paint(m, arc, z, GladeWeatherField.CELL, weather)
			z += GladeWeatherField.CELL
		arc += GladeWeatherField.CELL
	return m


# ---------------------------------------------------------------- reading it ------------------


## How many pieces stage `i` placed, across every slot.
func placed_by(i: int) -> int:
	if i < 0 or i >= stage_ranges.size():
		return 0
	var n := 0
	for r in stage_ranges[i]:
		n += int(r[1]) - int(r[0])
	return n


## Which stage owns piece `idx` of slot `slot`, or -1.
func owner_of(slot: int, idx: int) -> int:
	for i in stage_ranges.size():
		var r: Array = stage_ranges[i][slot]
		if idx >= int(r[0]) and idx < int(r[1]):
			return i
	return -1


func total_pieces() -> int:
	if ctx == null:
		return 0
	var n := 0
	for s in ctx.buffer.variants + 1:
		n += ctx.buffer.count(s)
	return n


func clay_quads() -> int:
	return ctx.buffer.clay_quads if ctx else 0


# ---------------------------------------------------------------- honesty ---------------------


## THE ANTI-DRIFT CHECK. Build a real `GladeWall` from the same intent and compare placements.
##
## This file is a second driver of the same pipeline, which is exactly the kind of thing that rots
## into a plausible lie. Rather than trust it, the atlas asks the addon directly on every rebuild
## and shows the answer. Returns `{ok, mine, theirs, note}`.
func verify_against_wall(parent: Node) -> Dictionary:
	var w := GladeWall.new()
	var c := Curve3D.new()
	for p: Vector3 in points:
		c.add_point(p)
	w.curve = c
	w.rng_seed = rng_seed
	w.wall_height = wall_height
	w.generate_collision = false
	w.style = load(style_path)
	if not storeys.is_empty():
		w.storeys.assign(storeys)

	# THE SAME HOLES, as real markers. Without these the comparison is between two different walls
	# and the badge reports a divergence that is only the checker's own blind spot.
	#
	# A `GladeOpening` is positioned in the wall's own space and projected onto the curve, so the
	# marker goes at `plumb(at)` raised by the sill — which is exactly how a dragged one behaves.
	var f := GladeWallFrame.new(c, GladeStoreyStack.new(storeys, wall_height), null, 30.0)
	for o in openings:
		var m := GladeOpening.new()
		m.position = f.plumb(o.at) + Vector3.UP * float(o.sill)
		m.width = o.w
		m.height = o.h
		m.arched = o.arched
		w.add_child(m)

	parent.add_child(w)                        # _ready rebuilds synchronously
	w.rebuild()

	var theirs: int = w.snap_transforms.size()
	var mine := total_pieces()
	var note := ""
	if mine != theirs:
		# name the first stage whose tally cannot be reconciled — far more useful than a bare count
		note = "first divergence after stage %d (%s)" % [stage_ranges.size() - 1,
				stage_names[stage_names.size() - 1] if stage_names.size() > 0 else "?"]
	w.free()
	return {"ok": mine == theirs, "mine": mine, "theirs": theirs, "note": note}


# ---------------------------------------------------------------- rendering -------------------


## Draw the buffer, up to and including stage `upto`. Pieces from earlier stages are desaturated so
## the one you are reading about is the one you can see.
##
## One MultiMesh per slot, which is exactly what `GladeWall` commits — the atlas renders the same
## way the tool does, so what you are looking at is not a stand-in.
func render(holder: Node3D, upto: int, dim := true) -> void:
	for ch in holder.get_children():
		ch.queue_free()
	if ctx == null:
		return
	var st := ctx.style
	var buf := ctx.buffer

	for slot in buf.variants + 1:
		var xf: Array = buf.xforms[slot]
		var col: Array = buf.colors[slot]
		var keep_xf: Array[Transform3D] = []
		var keep_col: Array[Color] = []
		for i in xf.size():
			var owner := owner_of(slot, i)
			if owner > upto:
				continue
			keep_xf.append(xf[i])
			var c: Color = col[i]
			if dim and owner < upto:
				# EARLIER STAGES GO DARK AND GREY. The fill lays 94% of the pieces, so a merely
				# "slightly duller" past leaves the forty stones the corner stage added invisible
				# inside six hundred. The shape still has to read, hence grey rather than black.
				var g := (c.r + c.g + c.b) / 3.0
				c = c.lerp(Color(g, g, g), 0.9).darkened(0.55)
			elif dim and owner == upto:
				# ...and the current one warms up, so it is found at a glance rather than hunted for
				c = c.lerp(Color(1.0, 0.78, 0.32), 0.45)
			keep_col.append(c)
		if keep_xf.is_empty():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = GladeBrickMesh.build(GladeBrickMesh.SLAB_CHAMFER) if slot == buf.slab \
				else (st.brick_meshes[slot] if slot < st.brick_meshes.size()
						else GladeBrickMesh.build())
		mm.instance_count = keep_xf.size()
		for i in keep_xf.size():
			mm.set_instance_transform(i, keep_xf[i])
			mm.set_instance_color(i, keep_col[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _plain()
		holder.add_child(mi)

	# the clay is one mesh, not instances — see GladeFillAdobe
	if buf.has_clay():
		var clay := MeshInstance3D.new()
		clay.mesh = buf.clay.commit()
		clay.material_override = _plain()
		holder.add_child(clay)


## A flat vertex-colour material. Deliberately NOT the project's painted shader: the atlas is about
## reading structure, and a stylised shader is one more thing between you and the geometry.
static func _plain() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	return m


static func _class_of(gs: GDScript) -> String:
	var n := gs.get_global_name()
	return n if n != "" else gs.resource_path.get_file()

class_name MapStyle
extends RefCounted
## THE PEN. Palette plus the handful of _draw() primitives that make the map read as drawn rather
## than plotted. Static only — the view owns no style state.
##
## The whole look rests on two tricks, and neither is expensive:
##
##   1. WOBBLE. Every outline is resampled to short segments and each vertex nudged along its own
##      normal by a hash of its index. Deterministic, so it does not shimmer when you pan.
##   2. TWO STROKES. A wide, faint, slightly offset pass under a narrow opaque one. A single clean
##      line reads as CAD; two read as a pen that pressed unevenly. This is the entire difference
##      between "a diagram" and "a map", and it costs one extra draw_polyline.

## The project palette. ACCENT is copy-pasted from hud.gd:11 / dialogue.gd:30 / pause_menu.gd:8 —
## four copies now, which is three too many. Extracting a shared scripts/ui_style.gd is a good
## separate task; this file deliberately does not do it, so the map lands without touching the HUD.
const ACCENT := Color(1.0, 0.82, 0.5)

const PARCHMENT := Color(0.86, 0.78, 0.62)
const PARCH_DEEP := Color(0.74, 0.64, 0.47)
## The deepest elevation band. The hub drops ~14 m from the house floor to the arena, and the first
## version lerped over too narrow a range to see — "the arena is BELOW the garden" is most of what a
## player is confused about here, so the band has to be worth reading.
const DEPTH_LOW := Color(0.58, 0.47, 0.33)
const INK := Color(0.19, 0.14, 0.11)
const INK_FAINT := Color(0.19, 0.14, 0.11, 0.26)
const DANGER := Color(0.72, 0.24, 0.20)         ## boss, locked gates
const GOLD := Color(0.85, 0.66, 0.28)           ## treasure
const KNOWN := Color(0.30, 0.24, 0.18, 0.55)    ## a room seen through a door but not entered

## Resample length in screen px. Short enough that the wobble reads as a shaky hand rather than as
## polygon vertices, long enough that a 200 m outline is not tens of thousands of points.
const SEG := 7.0
const WOBBLE := 1.7                             ## px of deviation, peak


## Resample a polyline to ~SEG px segments and displace each vertex along its normal.
##
## `salt` MUST be stable for a given outline across frames — pass the polygon's index. Derive it
## from anything that changes with pan or zoom and the ink crawls, which is far more distracting
## than a clean line would have been.
static func wobble(pts: PackedVector2Array, salt: int, closed := true,
		amount := WOBBLE) -> PackedVector2Array:
	var n := pts.size()
	if n < 2:
		return pts
	var dense := PackedVector2Array()
	var last := n if closed else n - 1
	for i in last:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var d := a.distance_to(b)
		var steps := maxi(int(d / SEG), 1)
		for s in steps:
			dense.append(a.lerp(b, float(s) / float(steps)))
	if not closed:
		dense.append(pts[n - 1])

	var m := dense.size()
	if m < 3:
		return dense
	var out := PackedVector2Array()
	out.resize(m)
	for i in m:
		var prev := dense[(i - 1 + m) % m]
		var next := dense[(i + 1) % m]
		var tangent := (next - prev)
		if tangent.length_squared() < 0.0001:
			out[i] = dense[i]
			continue
		var normal := tangent.normalized().orthogonal()
		out[i] = dense[i] + normal * (_hash(i * 13 + salt * 7919) - 0.5) * 2.0 * amount
	return out


## The two-stroke pen. Draw the ghost first so the opaque stroke sits on top of it.
static func ink(ci: CanvasItem, pts: PackedVector2Array, color := INK, width := 1.7,
		closed := true) -> void:
	if pts.size() < 2:
		return
	var line := pts
	if closed:
		line = pts.duplicate()
		line.append(pts[0])
	var ghost := PackedVector2Array()
	ghost.resize(line.size())
	for i in line.size():
		ghost[i] = line[i] + Vector2(0.9, 0.7)
	ci.draw_polyline(ghost, Color(color, color.a * 0.30), width * 1.9, true)
	ci.draw_polyline(line, color, width, true)


## A filled shape with its own inked outline — the normal way to draw a room or a floor slab.
static func ink_fill(ci: CanvasItem, poly: PackedVector2Array, fill: Color, outline := INK,
		width := 1.7) -> void:
	if poly.size() < 3:
		return
	ci.draw_colored_polygon(poly, fill)
	ink(ci, poly, outline, width, true)


## The player. A chevron rather than a dot, because "which way am I facing" is half of what you open
## a map to find out. `heading` is a zone-local yaw in radians, already north-up corrected.
static func pip(ci: CanvasItem, at: Vector2, heading: float, size := 9.0) -> void:
	var pts := PackedVector2Array([
		Vector2(0, -size), Vector2(size * 0.72, size * 0.7),
		Vector2(0, size * 0.32), Vector2(-size * 0.72, size * 0.7)])
	var rot := Transform2D(heading, at)
	var world := PackedVector2Array()
	for p in pts:
		world.append(rot * p)
	ci.draw_colored_polygon(world, ACCENT)
	ink(ci, world, INK, 1.4, true)


## Colour per marker kind. Index matches MapData.Marker.
const MARKER_COLORS := [
	Color(0.93, 0.88, 0.80),   # PIN     — a plain note
	GOLD,                      # CHEST
	DANGER,                    # DANGER
	Color(0.55, 0.72, 0.85),   # DOOR
	Color(0.66, 0.52, 0.80),   # SECRET
	ACCENT,                    # HOME
]
const MARKER_NAMES := ["Pin", "Chest", "Danger", "Door", "Secret", "Home"]


## A point of interest. Drawn as a teardrop pin with a glyph inside it, so a marker never reads as
## a piece of the terrain — no room, wall or corridor in this project is teardrop-shaped.
##
## `dim` is the discovery value under the marker: a pin you dropped in ground that is still fogged
## renders faint, which reads exactly right — you remember putting it there, the ground is hazy.
static func marker(ci: CanvasItem, at: Vector2, kind: int, size := 11.0, dim := 1.0) -> void:
	var tint: Color = MARKER_COLORS[clampi(kind, 0, MARKER_COLORS.size() - 1)]
	tint.a *= clampf(dim, 0.25, 1.0)
	var body := PackedVector2Array()
	for i in 14:                                   # the round head
		var a := PI * (0.5 + 2.0 * float(i) / 13.0)
		body.append(at + Vector2(cos(a), sin(a)) * size * 0.62 - Vector2(0, size * 0.34))
	body.append(at)                                # ...drawn down to the point
	ci.draw_colored_polygon(body, tint)
	ink(ci, body, Color(INK, INK.a * dim), 1.4, true)
	_glyph(ci, at - Vector2(0, size * 0.34), kind, size * 0.34, Color(INK, INK.a * dim))


static func _glyph(ci: CanvasItem, at: Vector2, kind: int, r: float, col: Color) -> void:
	match kind:
		1:   # CHEST — a lidded box
			ci.draw_rect(Rect2(at - Vector2(r, r * 0.5), Vector2(r * 2, r * 1.4)), col, false, 1.3)
			ci.draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), col, 1.3, true)
		2:   # DANGER — an exclamation
			ci.draw_line(at - Vector2(0, r), at + Vector2(0, r * 0.25), col, 1.7, true)
			ci.draw_circle(at + Vector2(0, r * 0.8), 1.2, col)
		3:   # DOOR — an arch
			ci.draw_rect(Rect2(at - Vector2(r * 0.7, r), Vector2(r * 1.4, r * 2)), col, false, 1.3)
			ci.draw_circle(at + Vector2(r * 0.35, 0), 1.1, col)
		4:   # SECRET — a question mark, reduced to its hook
			ci.draw_arc(at - Vector2(0, r * 0.35), r * 0.62, PI, TAU + PI * 0.35, 10, col, 1.4, true)
			ci.draw_circle(at + Vector2(0, r), 1.2, col)
		5:   # HOME — a gable
			ci.draw_polyline(PackedVector2Array([
				at + Vector2(-r, r * 0.6), at + Vector2(-r, -r * 0.1), at + Vector2(0, -r),
				at + Vector2(r, -r * 0.1), at + Vector2(r, r * 0.6)]), col, 1.3, true)
		_:   # PIN — deliberately empty; the teardrop IS the mark
			pass


## North-up compass. Drawn once in a corner; the map never rotates, so this is a promise rather
## than an instrument — but a map with no compass reads as a diagram.
static func compass(ci: CanvasItem, at: Vector2, font: Font, r := 20.0) -> void:
	ci.draw_arc(at, r, 0.0, TAU, 32, INK, 1.4, true)
	ci.draw_line(at + Vector2(0, r * 0.75), at - Vector2(0, r * 0.75), INK, 1.2, true)
	var tip := PackedVector2Array([
		at + Vector2(0, -r * 0.9), at + Vector2(r * 0.24, -r * 0.32),
		at + Vector2(-r * 0.24, -r * 0.32)])
	ci.draw_colored_polygon(tip, DANGER)
	if font:
		ci.draw_string(font, at + Vector2(-4, -r - 6), "N",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)


## Deterministic 0..1 from an int. Not a good hash and does not need to be — it needs to be the
## SAME every frame, which sin-fract is and randf() emphatically is not.
static func _hash(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)

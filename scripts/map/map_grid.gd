class_name MapGrid
extends RefCounted
## ONE ZONE'S FOG OF WAR, as pure data. No nodes, no autoloads, no engine state — so the headless
## suite can hammer it directly, the same bargain DungeonLayout makes with the generator.
##
## COORDINATES ARE ZONE-LOCAL XZ, always. The caller does `zone.to_local(player.global_position)`
## before it ever reaches here, and that one line is what makes the whole feature portable: the
## crypt parks itself at (500, 0, 500) and the hub is instanced with a 0.11 degree tilt baked into
## its basis, and neither fact survives to_local. What is left over is the exact space
## DungeonLayout.room_origin() already returns, so the dungeon's map and the dungeon's fog need no
## conversion between them at all.
##
## DISCOVERY IS A BYTE, NOT A BIT. The radial brush writes its own falloff, so the reveal boundary
## is already feathered IN THE DATA — one bilinear fetch in the shader is then soft for free, and
## there is no second "currently visible" pass to keep in sync. A bit-per-cell would have bought
## 8x on a 27 KB array and cost the entire look.

## Metres per cell. 1 m over the hub's 212 x 130 m is 27,560 cells = 27 KB, and at a ~1000 px map
## width that is 4.7 screen px per texel — under the shader's domain warp (+-12 px) the grid is
## structurally invisible. 2 m would make the reveal edge visibly lag the player ("I walked there
## and it didn't open"); 0.5 m is 4x the cost for nothing the warp doesn't already hide.
const DEFAULT_CELL := 1.0

## Where the brush stops being solid, as a fraction of its radius. The inner/outer smoothstep pair
## is deliberately the same shape painted_env.gdshader uses for the see-through cone, so the two
## soft edges in the game are the same soft edge.
const INNER := 0.55

var rect: Rect2                  ## zone-local XZ bounds this grid covers, in metres
var cell := DEFAULT_CELL
var w := 0
var h := 0
var bytes := PackedByteArray()   ## w*h, 0 = unknown, 255 = fully seen

## Set by stamp() when a byte actually changed. The view clears it after uploading, so a texture is
## rebuilt when the fog moved rather than once per stamp — and never at all while nobody is looking.
var dirty := false


## `bounds` is snapped OUTWARD to whole cells, so the grid always covers at least what was asked
## for. Snapping inward would leave a sliver of world that can never be revealed, which reads as a
## permanently fogged hairline down one edge of the map.
static func make(bounds: Rect2, cell_size := DEFAULT_CELL) -> MapGrid:
	var g := MapGrid.new()
	g.cell = maxf(cell_size, 0.05)
	var lo := Vector2(floorf(bounds.position.x / g.cell), floorf(bounds.position.y / g.cell)) * g.cell
	var hi := Vector2(ceilf(bounds.end.x / g.cell), ceilf(bounds.end.y / g.cell)) * g.cell
	g.rect = Rect2(lo, hi - lo)
	g.w = maxi(int(round(g.rect.size.x / g.cell)), 1)
	g.h = maxi(int(round(g.rect.size.y / g.cell)), 1)
	g.bytes = PackedByteArray()
	g.bytes.resize(g.w * g.h)          # resize() zero-fills, which is exactly "nothing discovered"
	return g


func local_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - rect.position.x) / cell), floori((p.y - rect.position.y) / cell))


## The CENTRE of the cell, not its corner. Distances measured to a corner bias every stamp half a
## cell up-left, which at the reveal radius is invisible but at the map's own edge is the difference
## between the last row discovering and never discovering.
func cell_to_local(c: Vector2i) -> Vector2:
	return rect.position + (Vector2(c) + Vector2(0.5, 0.5)) * cell


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func value_at(p: Vector2) -> int:
	var c := local_to_cell(p)
	if not in_bounds(c):
		return 0
	return bytes[c.y * w + c.x]


## Paint a soft disc of discovery. MAX, never overwrite: fog is a ratchet, and a player walking back
## through the faint rim of an old stamp must not dim what they already know.
func stamp(p: Vector2, radius: float) -> void:
	if radius <= 0.0 or bytes.is_empty():
		return
	var lo := local_to_cell(p - Vector2(radius, radius))
	var hi := local_to_cell(p + Vector2(radius, radius))
	# Clamped, not rejected. A stamp straddling the boundary is the NORMAL case at the edge of a
	# zone — the half inside must still land.
	lo.x = maxi(lo.x, 0)
	lo.y = maxi(lo.y, 0)
	hi.x = mini(hi.x, w - 1)
	hi.y = mini(hi.y, h - 1)
	var inner := radius * INNER
	var span := maxf(radius - inner, 0.0001)
	for cy in range(lo.y, hi.y + 1):
		var row := cy * w
		for cx in range(lo.x, hi.x + 1):
			var d := cell_to_local(Vector2i(cx, cy)).distance_to(p)
			if d >= radius:
				continue                       # keeps the disc round inside its square bounding box
			var t := clampf((d - inner) / span, 0.0, 1.0)
			var v := int(roundf(255.0 * (1.0 - t * t * (3.0 - 2.0 * t))))   # smoothstep, inverted
			var i := row + cx
			if bytes[i] < v:
				bytes[i] = v
				dirty = true


## Reveal a RECTANGLE with a soft margin, for discovery that is architectural rather than radial.
##
## A dungeon is not discovered by line of sight, it is discovered a ROOM at a time — and stamping a
## disc around the player there produced circular bulges swelling out of square rooms, which reads
## as a bug rather than as fog. `value` below 255 leaves a thin veil: exactly what a room you have
## seen through a doorway but not walked into should look like.
func stamp_rect(r: Rect2, value := 255, feather := 3.0) -> void:
	if bytes.is_empty() or value <= 0:
		return
	var lo := local_to_cell(r.position - Vector2(feather, feather))
	var hi := local_to_cell(r.end + Vector2(feather, feather))
	lo.x = maxi(lo.x, 0)
	lo.y = maxi(lo.y, 0)
	hi.x = mini(hi.x, w - 1)
	hi.y = mini(hi.y, h - 1)
	var soft := maxf(feather, 0.0001)
	for cy in range(lo.y, hi.y + 1):
		var row := cy * w
		for cx in range(lo.x, hi.x + 1):
			var p := cell_to_local(Vector2i(cx, cy))
			# Distance from the rect itself: zero anywhere inside it.
			var dx := maxf(r.position.x - p.x, maxf(0.0, p.x - r.end.x))
			var dy := maxf(r.position.y - p.y, maxf(0.0, p.y - r.end.y))
			var d := Vector2(dx, dy).length()
			if d >= soft:
				continue
			var t := clampf(d / soft, 0.0, 1.0)
			var v := int(roundf(float(value) * (1.0 - t * t * (3.0 - 2.0 * t))))
			var i := row + cx
			if bytes[i] < v:
				bytes[i] = v
				dirty = true


## Reveal an ARBITRARY outline with a soft margin. The polygon version of stamp_rect, and the reason
## it exists: dungeon rooms are not rectangles — RoomShape carves corner bites out of the tile grid —
## so a rectangular opening would leave an L-shaped room inked inside a square hole in the fog.
## Shape-agnostic on purpose: an oval room needs no new code here.
func stamp_polygon(poly: PackedVector2Array, value := 255, feather := 2.5) -> void:
	if bytes.is_empty() or value <= 0 or poly.size() < 3:
		return
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	var lo := local_to_cell(box.position - Vector2(feather, feather))
	var hi := local_to_cell(box.end + Vector2(feather, feather))
	lo.x = maxi(lo.x, 0)
	lo.y = maxi(lo.y, 0)
	hi.x = mini(hi.x, w - 1)
	hi.y = mini(hi.y, h - 1)
	var soft := maxf(feather, 0.0001)
	var n := poly.size()
	for cy in range(lo.y, hi.y + 1):
		var row := cy * w
		for cx in range(lo.x, hi.x + 1):
			var p := cell_to_local(Vector2i(cx, cy))
			var v := value
			if not Geometry2D.is_point_in_polygon(p, poly):
				# Outside: fall off with the distance to the nearest EDGE, so the softness follows
				# the real silhouette rather than its bounding box.
				var d := INF
				for i in n:
					d = minf(d, p.distance_to(
							Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])))
				if d >= soft:
					continue
				var t := clampf(d / soft, 0.0, 1.0)
				v = int(roundf(float(value) * (1.0 - t * t * (3.0 - 2.0 * t))))
			var i2 := row + cx
			if bytes[i2] < v:
				bytes[i2] = v
				dirty = true


## Straight into FORMAT_R8, which is why discovery is stored as one byte per cell in the first
## place: the upload is a memcpy and the shader's single .r fetch is the whole decode.
func to_image() -> Image:
	return Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes)


## Built-in Variant types ONLY — no objects, no nested Resources. The save layer writes with
## store_var(v, false), and full_objects = false is what stops a tampered save file from
## instantiating anything on load. Keeping the shape honest here is what makes that safe.
func to_dict() -> Dictionary:
	return {
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"cell": cell,
		"w": w,
		"h": h,
		"fog": bytes,
	}


## Returns null on ANY inconsistency rather than guessing. The dangerous failure is not a crash, it
## is a grid that loads successfully against a rect it was not baked for: the map then looks fine
## and is silently, unfixably offset. Caller treats null as "this zone is unexplored".
static func from_dict(d: Variant) -> MapGrid:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var dict := d as Dictionary
	for key in ["rect", "cell", "w", "h", "fog"]:
		if not dict.has(key):
			return null
	if typeof(dict["rect"]) != TYPE_ARRAY or (dict["rect"] as Array).size() != 4:
		return null
	if typeof(dict["fog"]) != TYPE_PACKED_BYTE_ARRAY:
		return null
	if typeof(dict["w"]) != TYPE_INT or typeof(dict["h"]) != TYPE_INT:
		return null
	if typeof(dict["cell"]) != TYPE_FLOAT and typeof(dict["cell"]) != TYPE_INT:
		return null

	var g := MapGrid.new()
	var r: Array = dict["rect"]
	g.rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	g.cell = float(dict["cell"])
	g.w = int(dict["w"])
	g.h = int(dict["h"])
	g.bytes = dict["fog"]
	if g.w <= 0 or g.h <= 0 or g.cell <= 0.0 or g.bytes.size() != g.w * g.h:
		return null
	return g


## Markers, type-checked field by field. Anything that is not exactly the expected shape is DROPPED
## rather than trusted: a marker carrying a String where a Vector2 belongs would sail through
## loading and then crash _draw() on the frame the map is opened, which is the worst possible place
## to discover a bad save file.
##
## Lives here rather than on MapData because MapData is an autoload with no class_name, and the
## headless suite runs with no autoloads registered — validation you cannot test is not validation.
static func clean_markers(raw: Variant, cap := 32) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for m: Variant in (raw as Array):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md := m as Dictionary
		if typeof(md.get("p")) != TYPE_VECTOR2 or typeof(md.get("k")) != TYPE_INT:
			continue
		out.append({
			"p": md["p"],
			"k": md["k"],
			"f": md["f"] if typeof(md.get("f")) == TYPE_INT else 0,
			"n": md["n"] if typeof(md.get("n")) == TYPE_STRING else "",
		})
		if out.size() >= cap:
			break
	return out


## Does this saved grid still describe the world we just loaded? Compared with a tolerance of one
## cell, because rect derivation is floating point and a rebuilt zone can land a hair off without
## having actually moved.
func matches(bounds: Rect2, cell_size: float) -> bool:
	if not is_equal_approx(cell, cell_size):
		return false
	var want := MapGrid.make(bounds, cell_size)
	return want.w == w and want.h == h \
			and want.rect.position.distance_to(rect.position) <= cell

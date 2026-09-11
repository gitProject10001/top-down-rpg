@tool
class_name WorldMap
extends Resource
## THE MAP AS DATA, before a single node exists. A world is generated as an abstract structure —
## cells with polygons, in world metres — saved as a `.tres`, and only then SLICED into scenes on
## disk. Nothing about a 6 km² map has to be in one scene, and nothing has to be regenerated to
## load it.
##
## AUTHORED versus DERIVED. `zones` and `site` are what the author insists on — a brief, where it
## stands, which way it faces, and what the ground around it is — and they are the whole of the
## input. `cells`, `units` and `chunks` are derived, but they are STORED, because a scene is cut
## around them and the streamer has to know what lives where without re-running the generator.
##
## THE FRAME. A zone is generated in its own local metres (the generator's own convention) and
## PLACED by `origin` / `yaw`; from then on every polygon in `cells` is in world XZ. Plan (x, y)
## is world (x, z), as everywhere else in the floorplan tools.
##
## THE GRAIN IS THE GENERATOR'S, NOT A GRID. A chunk is one of the generator's own chunk units —
## a city block, a dungeon ward — written in ITS OWN frame and put back at its `origin`. There is
## no tile grid: Open World Database buckets an item by its OWN size, so cutting the world on a
## 128 m lattice would only produce items too big for it to stream.

const VERSION := 2

@export var version := VERSION
## The folder and the world scene take this name.
@export var name := "city_7"
@export var seed := 7
## The largest OWDB chunk size, metres: the coarsest streaming grain, and the ceiling on how big
## one unit may be. A unit above this is ALWAYS_LOADED — see `check()`.
@export var chunk_m := 128.0
@export_file("*.tres") var kit_path := ""
@export_file("*.tres") var legend_path := ""

## AUTHORED: the zones this world is made of — [{id, brief: ZoneBrief, origin: Vector2, yaw}].
@export var zones: Array[Dictionary] = []
## AUTHORED: the ground the zones stand in, read by `world_terrain.profile_of`. Empty = the
## default ring of mountains around a plateau. Keys, all optional:
##   shore_n, shore_d      the sea as a half-plane: `p.dot(shore_n) > shore_d` is water
##   quay_m, sea_floor_m, shore_fall_m, water_y
##   island_centre, island_r, island_h
##   mountain_m, ramp_m, ridge_pow, detail_m, rock_colour
##   woods                 plant the landward band
@export var site: Dictionary = {}

## DERIVED, kept so slicing and streaming never regenerate: every cell of every zone in walk
## order, polygons in WORLD metres, `parent` the index of its parent (−1 for a zone's root) and
## `zone` the zone it came from. See gen/cell.gd `to_dicts` / `from_dicts`.
@export var cells: Array[Dictionary] = []
## DERIVED: chunk unit id → its index in `chunks`.
@export var units: Dictionary = {}
## DERIVED: one record per chunk unit —
## [{id, zone, origin: Vector2, bounds: Rect2, floors, size_m, path, plan_nodes, ms}].
## `origin` is what the unit's scene was written relative to; `size_m` is the number Open World
## Database itself computes for the baked node, which is why it is stored and not recomputed.
@export var chunks: Array[Dictionary] = []
## DERIVED: where the player lands, world XZ, and what the world covers.
@export var spawn := Vector2.ZERO
@export var bounds := Rect2()
## DERIVED: the generator's own stats per zone, plus the bake's — informative only.
@export var stats := {}


## The record of one chunk unit (empty = no such unit).
func chunk(id: String) -> Dictionary:
	var i := int(units.get(id, -1))
	return chunks[i] if i >= 0 and i < chunks.size() else {}


func cell(id: String) -> Dictionary:
	for c: Dictionary in cells:
		if String(c.id) == id:
			return c
	return {}


## The cells of one zone, in walk order (what `Cell.from_dicts` takes).
func cells_of(zone_id: String) -> Array:
	var out: Array = []
	var remap := {}
	for i in cells.size():
		var c: Dictionary = cells[i]
		if String(c.get("zone", "")) != zone_id:
			continue
		remap[i] = out.size()
		var d := c.duplicate(true)
		d["parent"] = int(remap.get(int(c.get("parent", -1)), -1))
		out.append(d)
	return out


func zone_brief(zone_id: String) -> Resource:
	for z: Dictionary in zones:
		if String(z.id) == zone_id:
			return z.brief
	return null


## What is wrong with the map (empty = nothing): messages, not asserts, so a half-built world can
## still be opened and looked at.
func check() -> Array:
	var out: Array = []
	if zones.is_empty():
		out.append("no zone")
	for i in chunks.size():
		var r: Dictionary = chunks[i]
		if String(r.get("path", "")) == "":
			out.append("unit %s has no scene" % String(r.get("id", "?")))
		# A unit bigger than the coarsest chunk is ALWAYS_LOADED — silent, not an error: it
		# simply never streams. Say so here rather than let a world quietly load whole. Size 0
		# is the opposite and is fine: a unit with nothing to see (a quarter's streets carry no
		# floor of their own) is left out of the manifest instead of being streamed.
		var sz := float(r.get("size_m", 0.0))
		if sz > chunk_m:
			out.append("unit %s is %.0f m, past the %.0f m chunk: it will never stream"
					% [String(r.get("id", "?")), sz, chunk_m])
		if int(units.get(String(r.get("id", "")), -1)) != i:
			out.append("unit %s is not indexed at its own record" % String(r.get("id", "?")))
	for u in units:
		var i := int(units[u])
		if i < 0 or i >= chunks.size():
			out.append("unit %s indexes nothing" % String(u))
	for i in cells.size():
		var p := int((cells[i] as Dictionary).get("parent", -1))
		if p >= i:
			out.append("cell %s has a parent that comes after it" % String((cells[i] as Dictionary).id))
	return out

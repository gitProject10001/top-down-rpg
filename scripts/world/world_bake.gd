@tool
extends RefCounted
## THE SLICER: a world generated as DATA, then cut into scenes on disk, then a world scene that
## streams them. Only the first step knows the generator:
##
##   plan_world(map)   the ensemble runs per zone → every cell in world metres into the WorldMap,
##                     one record per chunk unit. No node is made.
##   bake_units(map)   per unit: a throwaway plan, the drafter writes THAT unit's parts into it,
##                     the floorplan bakes and finalizes it, PackedScene → res://…/unit_<id>.tscn.
##   write_owdb(map)   the streaming manifest: one line per unit, written straight from the map.
##   write_master(map) the zone: its ground, an OpenWorldDatabase and the point it streams about.
##   write_final(map)  the scene you press play on: that zone, a sky, a sun, a player, a camera.
##
## THE GRAIN IS THE GENERATOR'S. A unit is a city block or a dungeon ward — the cells at the
## recipe's own `CHUNK_DEPTH` — not a square of a lattice. Open World Database buckets an item by
## its OWN size and streams the small ones at a short radius and the large ones at a long one, so
## cutting a world on a 128 m grid would hand it items too big for any of its buckets and it
## would simply never let go of them.
##
## The drafter stays the only writer of plan nodes and the floorplan façade the only way to
## geometry — a unit is written exactly the way the dock writes a level, into a plan of its own.
## Nothing here is in the edited scene, so the editor charges nothing per node (README,
## "Performance"): a unit costs a write and a bake, not six milliseconds a node.
##
## Unit scenes are DERIVED files. The `.tres`, the `.owdb` and the two scenes are the artefacts
## worth keeping; the units are rebuilt from them by one command and are not committed.

const Api := preload("res://addons/floorplan/api/floorplan_api.gd")
const Host := preload("res://addons/procedural_architecture/core/module_host.gd")
const Drafter := preload("res://addons/procedural_architecture/core/drafter.gd")
const Generator := preload("res://addons/procedural_architecture/gen/generator.gd")
const Cell := preload("res://addons/procedural_architecture/gen/cell.gd")
const ZoneBrief := preload("res://addons/procedural_architecture/gen/zone_brief.gd")

const Terrain := preload("res://scripts/world/world_terrain.gd")
const Crypt := preload("res://scripts/world/world_crypt.gd")
const Dress := preload("res://scripts/world/world_dress.gd")
const Props := preload("res://scripts/world/world_props.gd")

const ROOM_SCRIPT := "res://scripts/world/crypt_room.gd"

const ZONE_SCRIPT := "res://scripts/world/world_zone.gd"
const FOCUS_SCRIPT := "res://scripts/world/world_focus.gd"
const NODE_UTILS := "res://addons/open-world-database/src/node_utils.gd"
const PLAYER_SCENE := "res://scenes/player/player4.tscn"
const CAMERA_SCENE := "res://scenes/camera_rig.tscn"
## Where the scene you press play on is written — named, committed, beside the hub's own zones,
## while everything it is made of stays in the world's generated folder.
const WORLD_DIR := "res://scenes/world/"
const PORTAL_PATH := "res://scenes/props/portal.tscn"
const RETURN_ZONE := "res://scenes/world/room.tscn"

## THE STREAMING SETTINGS, and not one of them is a taste: Open World Database puts an item in a
## bucket by comparing its size against `chunk_size * threshold_ratio`, and ANYTHING ABOVE THE
## LAST ONE IS `ALWAYS_LOADED` — a category, not an error, so a world with the wrong numbers here
## loads whole and never streams a thing. The stock [8, 16, 64] at ratio 0.25 thresholds at
## [2, 4, 16] m, and a city block is thirty. These three make the threshold the chunk itself:
## a 32 m unit streams at a short radius, a 128 m one at a long one.
const CHUNK_SIZES: Array[float] = [16.0, 64.0, 128.0]
const CHUNK_RATIO := 1.0
const CHUNK_RANGE := 2


## WHAT THE BAKE BUILDS A WALL OUT OF. A town uses the stock blockout kit; a CARVED level needs
## its own numbers, and one of them is not a taste:
##
##   `wall_thickness` is HALF THE GAP between two rooms, and that is what makes the level solid.
##   A ring band lies entirely outside its own outline, so two rooms 2.5 m apart each push
##   1.25 m into the gap and the two bands meet exactly in the middle — no seam, no overlap, and
##   the rock between any two rooms is one continuous collidable mass. The gap itself is
##   `world_crypt.GAP_M`, which is how wide a wall should READ from a top-down camera rather
##   than however much floor the layout happened to leave between two rooms. Thinner is also
##   safer for the mitring in `plan_geometry.wall_pieces`, whose docstring warns about a
##   thickness above half the shortest edge; this is well under it.
##
## `roof_kind` stays NONE: a hip roof over every room would cap a crypt with houses.
static func _kit_of(map: WorldMap) -> Resource:
	if map.kit_path != "" and ResourceLoader.exists(map.kit_path):
		return load(map.kit_path)
	if not bool((map.site as Dictionary).get("carved", false)):
		return null                       # the stock kit, as before
	var kit: Resource = load("res://addons/floorplan/data/blockout_kit.gd").new()
	kit.set("wall_thickness", 1.25)       # = passage_m / 2, and see world_crypt.GAP_M
	# THE CEILING, and it is a CAMERA number rather than an architectural one. 8.5 was
	# DungeonLayout.WALL_HEIGHT at this scale, which is right for a crypt you walk through at eye
	# level and wrong for one you look down into: in an isometric frame a wall is seen mostly as
	# its SIDE, so height is what decides how much of the screen is rock — far more than
	# thickness does. At 4 m the walls read as a plan of the level rather than as canyons, and
	# the cost is that you can see further over them into rooms you have not opened yet.
	kit.set("wall_height", 4.0)
	kit.set("floor_thickness", 0.4)
	kit.set("door_height", 2.75)
	# NO `wall_scene`: the walls are the bake's own geometry with a material on them (see
	# world_dress.gd). Setting one would tile each run with modules instead, which is a
	# different pipeline and would pin the level's grid to the module's length.
	kit.set("roof_kind", 0)               # None
	return kit


## The legend the generated worlds use: the stock rows plus the few keys the recipes dress with.
static func default_legend() -> Resource:
	var legend: Resource = Api.default_legend()
	var rows: Array = legend.get("entries")
	rows.append(Api.legend_row("pendant", Color(1, 1, 0.5), 0, Vector3(0.5, 0.3, 0.5)))
	rows.append(Api.legend_row("locker", Color(0.5, 0.5, 0.5), 1, Vector3(1.0, 2.0, 0.6)))
	rows.append(Api.legend_row("altar", Color(0.8, 0.7, 0.4), 1, Vector3(1.4, 1.0, 1.4)))
	return legend


## A one-zone world: the brief the dock would have used, standing at the origin.
static func new_map(kind: String, size_m: float, seed: int, density := 1.0, world_name := "") -> WorldMap:
	var brief: Resource = ZoneBrief.new()
	brief.id = kind
	brief.kind = kind
	brief.size_m = size_m
	brief.seed = seed
	brief.density = density
	brief.cell_m = 1.0 if kind in ["city", "coast"] else 0.5
	var map := WorldMap.new()
	map.name = world_name if world_name != "" else "%s_%d" % [kind, seed]
	map.seed = seed
	if kind == "coast":
		_coast_site(map, brief, size_m, seed)
	elif kind == "dungeon":
		_crypt_site(map, brief, seed)
	map.zones = [{"id": brief.id, "brief": brief, "origin": Vector2.ZERO, "yaw": 0.0}]
	return map


## A CRYPT IS CARVED, AND IT HAS NO OUTSIDE. Its level design is decided by the game's own
## layout system and arrives here as a plan; `size_m` is ignored, because the extent of a crypt
## is however much ground its rooms took. `carved` tells the ground and the sky to stay away:
## there is no terrain under a level you can never see out of, and the flat fallback collider
## would only put a plane back at y = 0 for every floor slab to fight with.
static func _crypt_site(map: WorldMap, brief: Resource, seed: int) -> void:
	var recipe: GDScript = load("res://addons/procedural_architecture/gen/recipes/dungeon.gd")
	var rules: Dictionary = recipe.RULES
	var plan: Dictionary = Crypt.build(seed, int(rules.rooms), int(rules.stairs), int(rules.loops))
	var b: Rect2 = plan.bounds
	brief.plan = plan
	brief.size_m = maxf(b.size.x, b.size.y)
	brief.boundary = PackedVector2Array([b.position, Vector2(b.end.x, b.position.y), b.end,
			Vector2(b.position.x, b.end.y)])
	brief.entrance = plan.spawn
	map.site = {"carved": true}
	map.chunk_m = 128.0


## THE SEA, AND EVERYTHING THAT AGREES WITH IT. A coastal town and the ground it stands on have
## to be told the same thing about where the water is, and this is the ONE place that decides:
## the outline the recipe partitions, the half-plane its palisade and its gates read out of the
## brief's rules, and the half-plane the terrain drowns everything past. They are written twice
## on purpose — a recipe reads rules, a terrain reads the site — and computed once here.
##
## THE SHAPE IS A D. The chord lies on the water at z = 0 and the arc bulges landward, so the
## town faces the sea across one straight edge instead of being a ring with the sea somewhere
## outside it. Jitter is applied to the RADIUS, so the two ends of the chord stay exactly on the
## waterline whatever it does to the arc.
##
## Two lines, not one, and the difference matters: the terrain floods everything seaward of
## z = 0, while the palisade and the gates stand back by `quay_m`. One line would either fence
## off the quays or flood them.
static func _coast_site(map: WorldMap, brief: Resource, size_m: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|coast|%d" % [map.name, seed])
	var r := size_m * 0.5
	var depth := r * rng.randf_range(0.62, 0.86)      # how far inland the town runs
	var n := clampi(int(round(size_m / 34.0)), 7, 18)
	var poly := PackedVector2Array()
	for k in n + 1:
		var a := PI * float(k) / float(n)
		var j := 1.0 - rng.randf() * 0.16
		poly.append(Vector2(snappedf(r + r * cos(a) * j, 0.25), snappedf(depth * sin(a) * j, 0.25)))
	brief.boundary = poly
	# the sea is to the NORTH (−z); the gate is the landward crown of the arc
	var quay := 8.0
	var shore := Vector2(0.0, -1.0)
	brief.entrance = Vector2(r, snappedf(depth * 0.98, 0.25))
	brief.rules = {"shore_n": shore, "shore_d": -quay, "water_edge": Vector2(r, 0.0)}
	var reach := maxf(r, depth)
	map.site = {
		"shore_n": shore, "shore_d": 0.0, "quay_m": quay,
		"sea_floor_m": 16.0, "shore_fall_m": reach * 0.55, "water_y": -0.6,
		# an island offshore, off to one side: the lake primitive with its sign turned over
		"island_centre": Vector2(r + rng.randf_range(-r * 0.7, r * 0.7), -reach * rng.randf_range(1.1, 1.7)),
		"island_r": reach * rng.randf_range(0.22, 0.36),
		"island_h": rng.randf_range(22.0, 52.0),
		# ROCKIER: taller peaks up a shorter ramp, a sharper ridge and coarser detail
		"mountain_m": rng.randf_range(140.0, 200.0),
		"ramp_m": rng.randf_range(90.0, 130.0),
		"ridge_pow": 3.0, "detail_m": 5.0,
		"rock_colour": Color(0.30, 0.30, 0.31),
		"woods": true,
	}


# ---------------------------------------------------------------- the data --------------------


## STEP ONE: generate every zone, place it in the world, and write the whole structure into the
## map — cells and chunk units. Returns {ms, cells, units, warnings}.
static func plan_world(map: WorldMap, tree: SceneTree) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var warnings := PackedStringArray()
	map.cells = []
	map.units = {}
	map.chunks = []
	map.stats = {}
	var probe: Node = Api.new_plan("WorldProbe", null, _legend_of(map), false)
	tree.root.add_child(probe)
	var ctx := Host.context(probe)
	var bounds := Rect2()
	var first := true
	for z: Dictionary in map.zones:
		var brief: Resource = z.brief
		var res: Dictionary = Generator.generate(brief, ctx)
		var root: RefCounted = res.tree
		warnings.append_array(res.warnings)
		map.stats[String(z.id)] = res.stats
		var xf := Transform2D(float(z.get("yaw", 0.0)), z.get("origin", Vector2.ZERO))
		for c: RefCounted in root.walk():
			c.transformed_in_place(xf)
		var base := map.cells.size()
		for d: Dictionary in Cell.to_dicts(root):
			d["zone"] = String(z.id)
			d["parent"] = int(d.parent) + base if int(d.parent) >= 0 else -1
			map.cells.append(d)
		for u: RefCounted in Generator.chunk_units(root, brief):
			var box := Rect2()
			var floors := 1
			for d: RefCounted in u.walk():
				var b: Rect2 = d.bbox()
				box = b if box.size == Vector2.ZERO else box.merge(b)
				floors = maxi(floors, int(d.floor) + 1)
			if box.size == Vector2.ZERO:
				continue                      # a unit with no geometry is nothing to stream
			# the unit's scene is written relative to its own centre, so the manifest's position
			# and the node's own origin are the same point and OWDB never has to guess
			var at := box.get_center().snappedf(0.05)
			map.units[u.id] = map.chunks.size()
			map.chunks.append({"id": String(u.id), "zone": String(z.id), "origin": at,
					"bounds": box, "floors": floors, "size_m": 0.0, "path": "",
					"plan_nodes": 0, "ms": 0})
			bounds = box if first else bounds.merge(box)
			first = false
		if (root.entrances as PackedVector2Array).size() > 0 and map.spawn == Vector2.ZERO:
			# a step inside the main gate, where the streets start
			var gate: Vector2 = root.entrances[0]
			map.spawn = gate.lerp(root.centroid(), 0.08)
	probe.free()
	map.bounds = bounds
	var ms := Time.get_ticks_msec() - t0
	map.stats["plan_ms"] = ms
	return {"ms": ms, "cells": map.cells.size(), "units": map.units.size(), "warnings": warnings}


## The tree of one zone, back from the map's cells.
static func load_tree(map: WorldMap, zone_id: String) -> RefCounted:
	return Cell.from_dicts(map.cells_of(zone_id))


# ---------------------------------------------------------------- the units -------------------


## STEP TWO: one scene per chunk unit — a block, a ward. `only` bakes just those units (a re-roll
## touches two of two hundred); `finalize` turns the CSG blockout into meshes with collision —
## what a player walks on — and without it the unit keeps its CSG, which is what you want when
## you mean to open one and edit it.
static func bake_units(map: WorldMap, tree: SceneTree, out_dir: String, only := PackedStringArray(),
		finalize := true) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var kit: Resource = _kit_of(map)
	var legend: Resource = _legend_of(map)
	var utils: GDScript = load(NODE_UTILS) if ResourceLoader.exists(NODE_UTILS) else null
	var trees := {}
	var done := 0
	var nodes := 0
	var empty := 0
	var errors := PackedStringArray()
	for rec: Dictionary in map.chunks:
		var id := String(rec.id)
		if only.size() > 0 and not only.has(id):
			continue
		var zone_id := String(rec.zone)
		if not trees.has(zone_id):
			trees[zone_id] = load_tree(map, zone_id)
		var zone_tree: RefCounted = trees[zone_id]
		var brief: Resource = map.zone_brief(zone_id)
		var parts: Array = Generator.parts_for(zone_tree, brief, PackedStringArray([id]))
		var shift := Transform2D(0.0, -(rec.origin as Vector2))
		for p: Dictionary in parts:
			p["draft"] = (p.draft as Resource).call("transformed", shift)
		var t1 := Time.get_ticks_msec()
		var name := id.to_pascal_case()
		var plan: Node = Api.new_plan(name, kit, legend, false)
		tree.root.add_child(plan)
		Drafter.write(plan, parts, zone_id)
		var count := Api.plan_nodes(plan).size()
		var bk: Node3D = Api.build(plan, name)
		tree.root.add_child(bk)
		if finalize:
			await Api.finalize(bk, tree)
		# WHAT IT IS MADE OF, after the bake and outside the tool: the floorplan's flat
		# prototyping colours become the crypt's own stone and cobbles. And WHAT IS IN IT: a
		# room of a crypt puts its enemies up the first time the player walks in, which is a
		# script on the unit's root and no nodes at all until then.
		if bool((map.site as Dictionary).get("carved", false)):
			Dress.dress(bk)
			_inhabit(bk, map, id, rec)
		bk.set_meta("world_unit", {"id": id, "zone": zone_id, "origin": rec.origin,
				"bounds": rec.bounds, "seed": map.seed})
		_own(bk, bk)
		# THE SIZE IS THE ADDON'S OWN NUMBER, never one of ours. Open World Database recomputes
		# `calculate_node_size` on every unload and reallocates the chunk when it differs by a
		# hundredth of a metre, so a manifest written from our idea of the bounds would move
		# every unit the first time it left. (Its AABB merge ignores child transforms, which is
		# exactly the kind of disagreement that would never show up until it did.)
		# A UNIT WITH NOTHING TO SEE IS NOT STREAMED. A quarter's leftover is its streets, and a
		# street carries no floor of its own (the city recipe) — so its scene is region markers
		# and no geometry, the addon measures it as nothing, and there is nothing to spawn or
		# despawn. It keeps its scene, for the static view and for the slice to account for; it
		# just never reaches the manifest. Anything else measured at zero is the same case.
		var size := 0.0
		if utils != null:
			size = float(utils.call("calculate_node_size", bk, true))
		else:
			var b: Rect2 = rec.bounds
			size = maxf(maxf(b.size.x, b.size.y), float(rec.floors) * 3.0)
		if size <= 0.0:
			empty += 1
		if size > map.chunk_m:
			errors.append("%s is %.0f m, past the %.0f m chunk: it will never stream" % [id, size, map.chunk_m])
		var ps := PackedScene.new()
		var err := ps.pack(bk)
		var path := out_dir.path_join("unit_" + id + ".tscn")
		if err == OK:
			err = ResourceSaver.save(ps, path)
		if err != OK:
			errors.append("%s: %s" % [id, error_string(err)])
		rec["path"] = path
		rec["size_m"] = size
		rec["plan_nodes"] = count
		rec["ms"] = Time.get_ticks_msec() - t1
		nodes += count
		done += 1
		plan.free()
		bk.free()
	map.stats["bake_ms"] = Time.get_ticks_msec() - t0
	map.stats["empty_units"] = empty
	return {"units": done, "empty": empty, "plan_nodes": nodes, "ms": Time.get_ticks_msec() - t0,
			"errors": errors}


## WHO IS IN THE ROOM. The counts are the crypt's own — deeper is harder, bigger holds more —
## and they are read off the cell the room was cut from rather than invented here: `rank` is how
## many doors from the entrance it is, `params.type` its mission role, `params.area_m2` its
## floor. Nothing spawns until the player is inside; see `crypt_room.gd` for why.
##
## AND WHAT IS IN IT. The same cell says what the room is FOR, so the pillars, braziers, statues
## and tombs go in here too — as nodes in the packed unit, not at run time. The braziers are not
## decoration: a carved zone is entered under a black sky with the sun off (`world_zone`), so
## they are the room's only light. See `world_props.gd`.
static func _inhabit(bk: Node3D, map: WorldMap, id: String, rec: Dictionary) -> void:
	if not ResourceLoader.exists(ROOM_SCRIPT):
		return
	var cell: Dictionary = map.cell(id)
	if cell.is_empty():
		return
	var params: Dictionary = cell.get("params", {})
	var box: Rect2 = rec.bounds
	bk.set_script(load(ROOM_SCRIPT))
	bk.set("dist", int(cell.get("rank", 0)))
	bk.set("type", int(params.get("type", 1)))
	bk.set("area_m2", float(params.get("area_m2", 240.0)))
	bk.set("footprint", Vector3(box.size.x, 3.0, box.size.y))
	# the unit was written relative to its own origin, so the room's world polygon and its
	# doorways come back into the unit's frame by the same shift the draft took
	var shift: Vector2 = -(rec.origin as Vector2)
	var poly := PackedVector2Array()
	for p: Vector2 in (cell.get("polygon", PackedVector2Array()) as PackedVector2Array):
		poly.append(p + shift)
	var doors := PackedVector2Array()
	for p: Vector2 in (cell.get("entrances", PackedVector2Array()) as PackedVector2Array):
		doors.append(p + shift)
	Props.furnish(bk, poly, _floor_y(bk), params, doors, hash("%s|%d" % [id, map.seed]))


## WHERE THE FLOOR IS, measured off the bake rather than computed from a level height. A room on
## an upper storey is raised by the floorplan itself and nothing here knows by how much; the top
## face of its own floor slab is the one answer that is right on every storey. Zero when a unit
## somehow has no floor, which is a unit with nothing to stand a prop on anyway.
static func _floor_y(bk: Node3D) -> float:
	var best := -1.0e9
	for n: Node in _all(bk):
		if not n.has_meta("floorplan_floor"):
			continue
		var vis: VisualInstance3D = n.get_node_or_null("Mesh") as VisualInstance3D
		if vis == null:
			vis = n as VisualInstance3D
		if vis == null:
			continue
		var box: AABB = vis.global_transform * vis.get_aabb()
		best = maxf(best, box.end.y)
	return 0.0 if best < -1.0e8 else best


static func _all(n: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(n)
	for c: Node in n.get_children():
		_all(c, out)
	return out


## THE STREAMING MANIFEST, written straight from the map. Open World Database keeps its world in
## a `.owdb` beside the scene: one line per node, `uid|"scene"|pos|rot|scale|size|{properties}`,
## tab-indented for hierarchy. Every unit of a generated world is top level, carries no property
## overrides, and stands unrotated at its own origin — so the file is a projection of `chunks`
## and nothing has to be opened in an editor for the addon to have a world to stream.
##
## The unit id becomes the node's name when it is loaded, so ids are kept legible and free of
## the separator the addon splits names on.
static func write_owdb(map: WorldMap, out_dir: String) -> Dictionary:
	var path := out_dir.path_join(map.name + ".owdb")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"error": FileAccess.get_open_error(), "path": path, "units": 0}
	var n := 0
	for rec: Dictionary in map.chunks:
		var scene := String(rec.get("path", ""))
		if scene == "" or float(rec.get("size_m", 0.0)) <= 0.0:
			continue                          # nothing to see: never worth spawning
		var at: Vector2 = rec.origin
		f.store_line("%s|\"%s\"|%s,0.0,%s|0.0,0.0,0.0|1.0,1.0,1.0|%s|{}" % [
				String(rec.id), scene, at.x, at.y, float(rec.size_m)])
		n += 1
	f.close()
	map.stats["owdb"] = path
	return {"error": OK, "path": path, "units": n}


## STEP THREE: the world as a ZONE — its ground, the database that streams its buildings, and
## the point that database is streamed about. Every building is on disk in a unit scene and every
## region of the terrain in its own folder, so this scene stays a few kilobytes; it is a zone
## like any other, so `World.go_to` takes it as it stands.
static func write_master(map: WorldMap, out_dir: String, tree: SceneTree = null) -> Dictionary:
	# out of whatever callback the caller was resumed in first: a Terrain3D entering the tree in
	# the middle of another node's frame work takes the engine down with it
	if tree != null:
		await tree.process_frame
	var map_path := out_dir.path_join(map.name + ".tres")
	var err := ResourceSaver.save(map, map_path)
	if err != OK:
		return {"error": err, "map_path": map_path}
	map.take_over_path(map_path)
	var zone := _zone_of(map, map_path, out_dir, tree)
	if ClassDB.class_exists("Node") and _owdb_available():
		var owdb: Node = _new_owdb()
		zone.add_child(owdb)
		owdb.owner = zone
		# the focus comes AFTER the database, because a node registers with it in `_ready` and a
		# child's `_ready` runs before its parent's: in tree order the database is already up
		var focus: Node3D = Node3D.new()
		focus.set_script(load(FOCUS_SCRIPT))
		focus.name = "Focus"
		focus.set("home", map.spawn)
		zone.add_child(focus)
		focus.owner = zone
	else:
		push_warning("[World] Open World Database is not installed: %s will not stream" % map.name)
	var scene_path := out_dir.path_join(map.name + ".tscn")
	err = _save_scene(zone, scene_path)
	return {"error": err, "map_path": map_path, "scene_path": scene_path}


static func _owdb_available() -> bool:
	return ResourceLoader.exists("res://addons/open-world-database/src/open_world_database.gd")


## The streaming node, told the three things it cannot work out for itself. `follow_editor_camera`
## is OFF on purpose: the addon gives every node it loads an owner, and an owned node is SAVED —
## a world that streamed while its scene sat open would bake a few hundred buildings into the
## file on the next Ctrl+S — which is diff churn, not data loss, because the manifest is what
## the scene is rebuilt from when it opens.
static func _new_owdb() -> Node:
	var script: GDScript = load("res://addons/open-world-database/src/open_world_database.gd")
	var owdb: Node = script.new()
	owdb.name = "OWDB"
	owdb.set("chunk_sizes", CHUNK_SIZES)
	owdb.set("threshold_ratio", CHUNK_RATIO)
	owdb.set("chunk_load_range", CHUNK_RANGE)
	owdb.set("batch_processing_enabled", true)
	owdb.set("batch_time_limit_ms", 6.0)
	owdb.set("batch_interval_ms", 33.0)
	# THE TWO EDITOR SETTINGS, and neither is a convenience.
	#
	# `follow_editor_camera` is the addon's own mechanism for SHOWING THE WORLD IN THE EDITOR:
	# it adds an OWDBPosition that tracks the editor viewport camera, and every node it streams
	# in is given an owner, which is exactly what puts it in the Scene dock as a row you can
	# click. Turning it off is why opening a generated world showed nothing but ground.
	#
	# `load_all_chunks` is not optional either. Saving the scene rewrites the .owdb FROM WHAT IS
	# CURRENTLY LOADED, so with it off and the editor camera parked in a corner one Ctrl+S would
	# write a truncated manifest and lose units from the world permanently.
	owdb.set("follow_editor_camera", true)
	owdb.set("load_all_chunks", true)
	return owdb


## THE WHOLE WORLD AS NODES: the same zone and the same ground, with every unit INSTANCED into
## it and no database at all. This is the scene to OPEN AND LOOK AT — the city is in the Scene
## dock, every building of it, and nothing appears out of nowhere. The world scene beside it is
## the one the game streams; for a site of a few square kilometres this one is the wrong shape,
## which is exactly why both are written.
static func write_static(map: WorldMap, out_dir: String, tree: SceneTree = null) -> Dictionary:
	if tree != null:
		await tree.process_frame
	var map_path := out_dir.path_join(map.name + ".tres")
	var zone := _zone_of(map, map_path, out_dir, tree)
	var units := populate(zone, map)
	var scene_path := out_dir.path_join(map.name + "_static.tscn")
	var err := _save_scene(zone, scene_path)
	return {"error": err, "scene_path": scene_path, "units": units}


## THE MARKS A ZONE IS ENTERED AND LEFT BY, written into the file like everything else. They
## used to be made in `_ready`, which is a small thing to build at run time and still the wrong
## place: the generation step decides where a spawn is, and the scene step writes it down. A
## scene that makes its own marks cannot be looked at in the editor and cannot be edited.
static func _marks(zone: Node3D, map: WorldMap) -> void:
	var spawn := Marker3D.new()
	spawn.name = "SpawnA"
	spawn.position = Vector3(map.spawn.x, 1.0, map.spawn.y)
	zone.add_child(spawn)
	if ResourceLoader.exists(PORTAL_PATH):
		var portal: Node3D = (load(PORTAL_PATH) as PackedScene).instantiate()
		portal.name = "ReturnPortal"
		portal.position = spawn.position + Vector3(4.0, 0.0, 0.0)
		if "target_zone_path" in portal:
			portal.set("target_zone_path", RETURN_ZONE)
		zone.add_child(portal)


## EVERY UNIT AS A NODE under `zone`, each an INSTANCE of its own scene so the file that holds
## them keeps a reference rather than a copy of a thousand meshes. They are OWNED: an owned node
## is a row in the Scene dock, and a row in the Scene dock is the whole point — you can see the
## world, click a building, and expand it to the meshes it is made of.
static func populate(zone: Node3D, map: WorldMap) -> int:
	var units := 0
	for rec: Dictionary in map.chunks:
		var path := String(rec.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var node: Node3D = (load(path) as PackedScene).instantiate()
		node.name = String(rec.id)
		var o: Vector2 = rec.origin
		node.position = Vector3(o.x, 0.0, o.y)
		zone.add_child(node)
		node.owner = zone
		units += 1
	return units


## The zone every world scene is built on: the root, its map, and the ground under it.
##
## The ground is grown in a HOLDER inside the tree and moved under the zone afterwards, because
## the two ends of this pull against each other: a Terrain3D has no `data` until it is in a tree,
## and a zone put in a tree runs its own `_ready` — which stands up a world, on a scene that is
## still being written. The zone therefore never enters the tree here at all.
static func _zone_of(map: WorldMap, map_path: String, out_dir: String, tree: SceneTree) -> Node3D:
	var zone := Node3D.new()
	zone.name = map.name.to_pascal_case()
	zone.set_script(load(ZONE_SCRIPT))
	zone.add_to_group("zone")
	zone.set("map", load(map_path))
	_marks(zone, map)
	if tree != null:
		var holder := Node3D.new()
		holder.name = "TerrainHolder"
		tree.root.add_child(holder)
		Terrain.build(map, holder, out_dir.path_join("terrain"))
		for c: Node in holder.get_children():
			holder.remove_child(c)
			zone.add_child(c)
			c.owner = zone
		holder.get_parent().remove_child(holder)
		holder.free()
	return zone


static func _save_scene(zone: Node3D, path: String) -> Error:
	_own(zone, zone)
	var ps := PackedScene.new()
	var err := ps.pack(zone)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	zone.free()
	return err


## THE SCENE YOU OPEN AND THE SCENE YOU PRESS PLAY ON, and they are the same one: the ground,
## EVERY BUILDING OF THE WORLD AS ITS OWN NODE, a sky, a sun, the player standing on the spawn
## and the camera rig watching them. Nothing is made up at run time and nothing appears out of
## nowhere — open it and the whole place is in the Scene dock, a row per unit, each expandable
## to the meshes it is made of.
##
## NOTHING IS STREAMED HERE, on purpose. Streaming is what a site of several square kilometres
## needs and it is what `<world>/<name>.tscn` beside this is for; what a person wants from the
## scene they open is to SEE the world, and a database that spawns it on the first frame of a
## run shows them an empty node instead. Both are written from the same map, so neither is a
## copy of the other.
##
## It lives under `scenes/world/`, named, beside the hub's own zones, while everything it is
## made of stays in the generated folder: this is the artefact, the folder is the workings.
static func write_final(map: WorldMap, out_dir: String, tree: SceneTree = null,
		world_dir := WORLD_DIR) -> Dictionary:
	if tree != null:
		await tree.process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(world_dir))
	var root := Node3D.new()
	root.name = map.name.to_pascal_case()
	var carved := bool((map.site as Dictionary).get("carved", false))
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = _void() if carved else _sky()
	# THE SAME GROUPS main.tscn PUTS ON ITS OWN. A world entered through the hub's portal renders
	# under main's environment, not this one, and `world_zone._underground` blacks THAT out by
	# group; a standalone world has to answer to the same two names or the zone would find the
	# hub's look in one case and nothing in the other.
	# PERSISTENT, and that second argument is the whole point: `add_to_group(name)` defaults to a
	# RUNTIME group, which `PackedScene.pack` does not write. Without it the groups exist right up
	# until the scene is saved and are gone in the file — so the zone, the camera rig and anything
	# else that looks them up finds nothing, silently, in the built world only.
	env.add_to_group("world_env", true)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -46.0, 0.0)
	sun.position = Vector3(0.0, 30.0, 0.0)
	# A CRYPT IS UNDERGROUND: there is no sun down there, and a dimmed one still renders four
	# shadow cascades every frame for output nobody can see. The node stays so the group has
	# something to hold and so a look-dev pass can turn it back on.
	sun.shadow_enabled = not carved
	sun.light_energy = 0.0 if carved else 1.0
	sun.add_to_group("sun", true)          # persistent, for the reason above
	root.add_child(sun)
	# the world itself, built into THIS file: the zone, its ground, and the database that holds
	# its rooms. They are NOT written into this file as nodes — the addon frees any child of the
	# OWDB node when the scene opens and rebuilds them from the manifest, so a copy here would
	# be discarded and would only churn the diff. What puts them in the Scene dock is the
	# addon's own editor camera, which `_new_owdb` turns on.
	var map_path := out_dir.path_join(map.name + ".tres")
	var world := _zone_of(map, map_path, out_dir, tree)
	world.name = "World"
	# THE MANIFEST IS BESIDE THE WORLD, NOT BESIDE THIS SCENE. A zone finds its .owdb by its own
	# scene's name, which is right while the zone IS the scene; here the zone is a node inside a
	# scene under scenes/world, and the manifest stayed in the generated folder with everything
	# else it describes. Say so rather than let it look in the wrong place and stream nothing.
	world.set("manifest", out_dir.path_join(map.name + ".owdb"))
	var units := 0
	if _owdb_available():
		var owdb: Node = _new_owdb()
		world.add_child(owdb)
		owdb.owner = world
		var focus: Node3D = Node3D.new()
		focus.set_script(load(FOCUS_SCRIPT))
		focus.name = "Focus"
		focus.set("home", map.spawn)
		world.add_child(focus)
		focus.owner = world
		units = (map.chunks as Array).size()
	else:
		units = populate(world, map)      # no addon: the world as plain nodes, as before
	root.add_child(world)
	var at := Vector3(map.spawn.x, 1.0, map.spawn.y)
	var player: Node3D = null
	if ResourceLoader.exists(PLAYER_SCENE):
		player = (load(PLAYER_SCENE) as PackedScene).instantiate()
		player.name = "Player"
		player.position = at
		root.add_child(player)
	if ResourceLoader.exists(CAMERA_SCENE):
		var rig: Node3D = (load(CAMERA_SCENE) as PackedScene).instantiate()
		rig.name = "CameraRig"
		rig.position = at
		if player != null and "target_path" in rig:
			rig.set("target_path", NodePath("../Player"))
		root.add_child(rig)
	# owned to the ROOT, so every unit is a row in the dock; `_own` stops inside an instance and
	# at the Terrain3D, so the file references its units and does not copy them
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	var scene_path := world_dir.path_join(map.name + ".tscn")
	if err == OK:
		err = ResourceSaver.save(ps, scene_path)
	root.free()
	return {"error": err, "scene_path": scene_path, "units": units}


## THE VOID a carved world is looked at under — no sky, no ambient from one, and depth fog that
## has swallowed everything before the next room. This is the FILE's answer to "outside is pitch
## black"; `world_zone._underground` is the RUN TIME's, for a crypt entered through the hub's
## portal, and it uses the crypt's own `DungeonEnv` on whatever environment is live. Both end in
## the same place, which is the point: opening this scene and walking in through a portal look
## alike.
static func _void() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.16, 0.19)
	env.ambient_light_energy = 0.12
	env.ambient_light_sky_contribution = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.05, 0.06)
	env.fog_light_energy = 0.0
	env.fog_density = 1.0                     # in DEPTH mode this is the maximum, not a rate
	env.fog_depth_begin = 26.0                # past the room the top-down camera is looking at
	env.fog_depth_end = 62.0
	env.fog_sky_affect = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.6                     # brick scale, not the outdoor 1.5 m
	env.ssao_intensity = 2.0
	env.ssao_light_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 0.9              # the braziers are the only light: let them bloom
	return env


## The sky a generated world is looked at under — the hub's own, in code, so a world scene needs
## no resource beside it.
static func _sky() -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.7, 0.83, 0.95)
	sky_mat.ground_bottom_color = Color(0.42, 0.5, 0.45)
	sky_mat.ground_horizon_color = Color(0.62, 0.68, 0.62)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	return env


## THE WHOLE WORLD AS ONE PLAN, beside the units it was cut into. The units are what the game
## streams; this is what a designer OPENS — a plain floorplan scene, every node of it, the same
## one the dock's Generate level would have written, so the tools that edit a plan all still
## work on a world. Nothing reads it back yet: a re-cut regenerates from the map.
static func write_plan(map: WorldMap, tree: SceneTree, out_dir: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var plan: Node = Api.new_plan(map.name.to_pascal_case(), null, _legend_of(map), false)
	tree.root.add_child(plan)
	for z: Dictionary in map.zones:
		var zone_tree: RefCounted = load_tree(map, String(z.id))
		if zone_tree == null:
			continue
		Drafter.write(plan, Generator.to_parts(zone_tree, z.brief), String(z.id))
	var count := Api.plan_nodes(plan).size()
	var path := out_dir.path_join(map.name + "_plan.tscn")
	var err := Api.save_plan(plan, path)
	plan.free()
	return {"error": err, "path": path, "nodes": count, "ms": Time.get_ticks_msec() - t0}


## STEP ONE, GENERATION: everything that is a function of the brief — the map, one baked scene
## per unit, the ground's regions, the streaming manifest and the designer's plan. It writes a
## FOLDER, and it makes no scene anybody plays.
static func generate_world(map: WorldMap, tree: SceneTree, out_dir: String, finalize := true) -> Dictionary:
	var dir := out_dir.path_join(map.name)
	var plan: Dictionary = plan_world(map, tree)
	var baked: Dictionary = await bake_units(map, tree, dir, PackedStringArray(), finalize)
	var manifest: Dictionary = write_owdb(map, dir)
	var scene: Dictionary = write_plan(map, tree, dir)
	map.stats["plan_scene"] = scene.path
	var map_path := dir.path_join(map.name + ".tres")
	var err := ResourceSaver.save(map, map_path)
	map.take_over_path(map_path)
	return {"plan": plan, "baked": baked, "owdb": manifest, "plan_scene": scene, "dir": dir,
			"map_path": map_path, "error": err}


## STEP TWO, THE SCENE: a generated folder assembled into scenes. Nothing here runs the
## generator — it reads the map and the units that are already on disk — so it can be run again
## on its own after an edit to the assembly without regenerating a thing.
static func assemble_world(map: WorldMap, tree: SceneTree, dir: String) -> Dictionary:
	var master: Dictionary = await write_master(map, dir, tree)
	var still: Dictionary = await write_static(map, dir, tree)
	map.stats["static_scene"] = still.scene_path
	var final: Dictionary = await write_final(map, dir, tree)
	map.stats["scene"] = final.scene_path
	ResourceSaver.save(map, String(master.map_path))
	return {"master": master, "static": still, "final": final, "dir": dir,
			"map_path": master.map_path, "scene_path": master.scene_path,
			"static_path": still.scene_path, "final_path": final.scene_path}


## Both steps, for the one command and the one button that want them.
static func build_world(map: WorldMap, tree: SceneTree, out_dir: String, finalize := true) -> Dictionary:
	var gen: Dictionary = await generate_world(map, tree, out_dir, finalize)
	var made: Dictionary = await assemble_world(map, tree, String(gen.dir))
	return gen.merged(made, true)


## The map of a world already on disk (null when there is none).
static func load_world(dir: String, world_name: String) -> WorldMap:
	var path := dir.path_join(world_name).path_join(world_name + ".tres")
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as WorldMap


## A re-roll of one cell: its subtree is generated again and only the units that hold a piece of
## it are baked again. The rest of the world is not touched, on disk or in memory.
static func regenerate(map: WorldMap, cell_id: String, salt: int, tree: SceneTree, out_dir: String) -> Dictionary:
	var zone_id := String((map.cell(cell_id) as Dictionary).get("zone", ""))
	if zone_id == "":
		return {"error": ERR_DOES_NOT_EXIST, "cell": cell_id}
	var probe: Node = Api.new_plan("WorldProbe", null, _legend_of(map), false)
	tree.root.add_child(probe)
	var zone_tree: RefCounted = load_tree(map, zone_id)
	var brief: Resource = map.zone_brief(zone_id)
	var res: Dictionary = Generator.regenerate(zone_tree, cell_id, brief, Host.context(probe), salt)
	probe.free()
	# the map's cells for that zone, rewritten; the units that held a piece of the subtree rebaked
	var touched := PackedStringArray()
	var sub: RefCounted = zone_tree.find(cell_id)
	if sub != null:
		for d: RefCounted in sub.walk():
			if map.units.has(d.id) and not touched.has(String(d.id)):
				touched.append(String(d.id))
	var keep: Array = []
	for c: Dictionary in map.cells:
		if String(c.get("zone", "")) != zone_id:
			keep.append(c)
	var base := keep.size()
	for d: Dictionary in Cell.to_dicts(zone_tree):
		d["zone"] = zone_id
		d["parent"] = int(d.parent) + base if int(d.parent) >= 0 else -1
		keep.append(d)
	map.cells.assign(keep)
	var dir := out_dir.path_join(map.name)
	var baked: Dictionary = await bake_units(map, tree, dir, touched, true)
	write_owdb(map, dir)
	ResourceSaver.save(map, dir.path_join(map.name + ".tres"))
	return {"warnings": res.warnings, "units": touched, "baked": baked}


# ---------------------------------------------------------------- internals -------------------


static func _legend_of(map: WorldMap) -> Resource:
	if map.legend_path != "" and ResourceLoader.exists(map.legend_path):
		return load(map.legend_path)
	return default_legend()


## A packed scene keeps only what the root owns — and a Terrain3D builds its own children
## (labels, multimeshes, a mouse viewport) the moment it enters a tree, so owning THOSE would
## save a second copy of them into the scene and hand the extension a tree it did not make.
static func _own(n: Node, root: Node) -> void:
	for c: Node in n.get_children():
		c.owner = root
		# stop at anything that is a scene of its own: owning the children of an INSTANCE writes
		# every one of them into the file as an override (3.4 MB of units that were already on
		# disk), and a Terrain3D builds its own children the moment it enters a tree
		if c.get_class() == "Terrain3D" or c.scene_file_path != "":
			continue
		_own(c, root)

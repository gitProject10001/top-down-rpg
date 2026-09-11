extends SceneTree
## Headless verification of the WORLD pipeline (scripts/world): the map as data, the slice into
## one scene per generated unit, the manifest that names them, and the database that puts them up
## and takes them down. Run:
##   Godot_console.exe --headless --path . --script res://scripts/procedural_architecture_tests/verify_world.gd --log-file <fresh path>
## Non-zero exit on any failure.
##
## WHY IT WRITES INTO res://. Open World Database instantiates a unit from its scene path, and it
## treats anything that does not begin with `res://` as a CLASS NAME, not a scene — so a world
## baked into `user://` cannot be streamed at all and the streaming suite would be testing
## nothing. It writes into the generated-worlds folder, where derived worlds already live and
## nothing is committed, under a name of its own, and wipes it at both ends of the run.

const WorldBake := preload("res://scripts/world/world_bake.gd")
const Cell := preload("res://addons/procedural_architecture/gen/cell.gd")
const ZoneBrief := preload("res://addons/procedural_architecture/gen/zone_brief.gd")
const Generator := preload("res://addons/procedural_architecture/gen/generator.gd")
const Api := preload("res://addons/floorplan/api/floorplan_api.gd")
const Host := preload("res://addons/procedural_architecture/core/module_host.gd")
const Stream := preload("res://scripts/world/world_stream.gd")
const Terrain := preload("res://scripts/world/world_terrain.gd")

const EXPECTED_SUITES := 8
const OUT := "res://scenes/world/gen/_verify"

var _fails: Array[String] = []
var _log := ""
var _suites_done := 0
var _world: WorldMap = null


func _initialize() -> void:
	_wipe(OUT)
	_cell_suite()
	await _world_suite()
	_unit_suite()
	_slice_suite()
	await _scene_suite()
	_owdb_suite()
	await _stream_suite()
	_terrain_suite()
	if _suites_done != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported done — one crashed silently" % [_suites_done, EXPECTED_SUITES])
	_wipe(OUT)
	var f := FileAccess.open("user://verify_world.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log)
	if _fails.is_empty():
		_say("[VERIFY] WORLD PASS")
		quit(0)
	else:
		for line in _fails:
			_say("[VERIFY] FAIL: " + line)
		quit(1)


## A CELL TREE IS DATA: it goes to dictionaries and comes back the same tree — that is what lets
## a whole map live in a .tres and be sliced later without regenerating anything.
func _cell_suite() -> void:
	var plan: Node = Api.new_plan("CellSuite", null, WorldBake.default_legend(), false)
	root.add_child(plan)
	var map: WorldMap = WorldBake.new_map("city", 240.0, 5, 0.9, "cellsuite")
	var brief: Resource = (map.zones[0] as Dictionary).brief
	var res: Dictionary = Generator.generate(brief, Host.context(plan))
	var tree: RefCounted = res.tree
	var before := Cell.to_dicts(tree)
	var back: RefCounted = Cell.from_dicts(before)
	var after := Cell.to_dicts(back)
	_check(before.size() == after.size(), "cell: %d cells out, %d back" % [before.size(), after.size()])
	_check(str(before) == str(after), "cell: the tree changed on the way back")
	# the shape of the tree, not just its contents
	var walked := (back.walk() as Array).size()
	_check(walked == before.size(), "cell: %d cells walk, %d were saved" % [walked, before.size()])
	_check(back.find(String((before[before.size() - 1] as Dictionary).id)) != null, "cell: the last cell cannot be found")
	for c: RefCounted in back.walk():
		if c.parent != null:
			_check((c.parent.children as Array).has(c), "cell: %s is not among its parent's children" % c.id)
	# and the parts a restored tree writes are the parts the original wrote
	var p1 := Generator.to_parts(tree, brief)
	var p2 := Generator.to_parts(back, brief)
	_check(p1.size() == p2.size(), "cell: %d parts before, %d after" % [p1.size(), p2.size()])
	# moved in the world: every point shifted, the shape unchanged
	var a0: float = tree.area()
	for c: RefCounted in tree.walk():
		c.transformed_in_place(Transform2D(0.0, Vector2(1000.0, -500.0)))
	_check(is_equal_approx(tree.area(), a0), "cell: the area changed when the zone was placed")
	_check((tree.centroid() as Vector2).distance_to(back.centroid() + Vector2(1000.0, -500.0)) < 0.01,
			"cell: the zone did not land where it was placed")
	plan.free()
	_done("cell suite done (%d cells round-tripped)" % before.size())


## THE MAP AS DATA: planned without a single node, saved, loaded, and still the same world.
func _world_suite() -> void:
	var map: WorldMap = WorldBake.new_map("city", 260.0, 11, 0.8, "worldsuite")
	var res: Dictionary = WorldBake.plan_world(map, self)
	_check(int(res.cells) > 50, "world: %d cells planned" % int(res.cells))
	_check(int(res.units) > 5, "world: %d chunk units" % int(res.units))
	_check(map.bounds.size.x > 100.0, "world: the bounds are %s" % str(map.bounds))
	_check(map.spawn != Vector2.ZERO, "world: no spawn")
	# before a bake every unit is legitimately missing a scene and a size, and nothing else may
	# be wrong: two complaints per unit, never a third
	var problems: Array = map.check()
	_check(problems.size() <= map.chunks.size() * 2, "world: %s" % str(problems.slice(0, 3)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var path := OUT.path_join("worldsuite.tres")
	_check(ResourceSaver.save(map, path) == OK, "world: the map would not save")
	var back: WorldMap = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(back != null, "world: the map would not load")
	if back != null:
		_check(back.cells.size() == map.cells.size(), "world: %d cells saved, %d loaded" % [map.cells.size(), back.cells.size()])
		_check(back.units.size() == map.units.size(), "world: %d units saved, %d loaded" % [map.units.size(), back.units.size()])
		_check(back.chunks.size() == map.chunks.size(), "world: %d units saved, %d loaded" % [map.chunks.size(), back.chunks.size()])
		_check(back.spawn.is_equal_approx(map.spawn), "world: the spawn moved")
		var b0: Resource = (back.zones[0] as Dictionary).brief
		_check(b0 != null and int(b0.get("seed")) == 11, "world: the brief did not survive the round trip")
		# and the tree comes back out of the loaded map
		var tree: RefCounted = WorldBake.load_tree(back, "city")
		_check(tree != null and (tree.walk() as Array).size() == back.cells.size(),
				"world: the loaded map does not rebuild its tree")
	_world = map
	_done("world suite done (%d cells, %d units, %d ms)" % [
			int(res.cells), int(res.units), int(res.ms)])


## ONE RECORD PER UNIT, indexed by its own id, whole: what makes a unit a place rather than a
## bag, now that the grain is the generator's and not a lattice.
func _unit_suite() -> void:
	if _world == null:
		_fails.append("unit: no world")
		return
	var tree: RefCounted = WorldBake.load_tree(_world, "city")
	var brief: Resource = _world.zone_brief("city")
	var units: Array = Generator.chunk_units(tree, brief)
	_check(_world.chunks.size() == _world.units.size(),
			"unit: %d records, %d indexed" % [_world.chunks.size(), _world.units.size()])
	_check(units.size() >= _world.chunks.size(),
			"unit: %d units in the tree, %d records" % [units.size(), _world.chunks.size()])
	var seen := {}
	for i in _world.chunks.size():
		var rec: Dictionary = _world.chunks[i]
		var id := String(rec.id)
		_check(not seen.has(id), "unit: %s has two records" % id)
		seen[id] = true
		_check(int(_world.units.get(id, -1)) == i, "unit: %s is not indexed at its own record" % id)
		_check((rec.bounds as Rect2).size.length() > 0.0, "unit: %s covers nothing" % id)
		# the scene is written relative to the record's origin, so the two must agree
		_check((rec.origin as Vector2).distance_to((rec.bounds as Rect2).get_center()) < 0.2,
				"unit: %s is written about a point that is not its own centre" % id)
	# a unit travels whole: no descendant of one unit is a unit of its own
	for u: RefCounted in units:
		if not _world.units.has(u.id):
			continue
		for d: RefCounted in u.walk():
			if d == u:
				continue
			_check(not _world.units.has(d.id), "unit: %s is inside %s and a unit of its own" % [d.id, u.id])
	_done("unit suite done (%d units)" % seen.size())


## THE SLICE: a unit scene is written from ITS cell and nothing else, and the units together hold
## the whole world exactly once.
func _slice_suite() -> void:
	if _world == null:
		_fails.append("slice: no world")
		return
	var tree: RefCounted = WorldBake.load_tree(_world, "city")
	var brief: Resource = _world.zone_brief("city")
	# what the units TOGETHER must hold: every unit's own regions and its subtree's. The regions
	# of an ancestor that is not a unit — a quarter, which spans units — belong to no unit, and
	# that is the point of slicing by unit.
	var every := PackedStringArray()
	for id in _world.units:
		every.append(String(id))
	var whole: Array = Generator.parts_for(tree, brief, every)
	var whole_regions := {}
	for p: Dictionary in whole:
		for r: Dictionary in (p.draft as Resource).get("regions"):
			whole_regions["%s_%s" % [String((p.brief as Resource).get("id")), String(r.id)]] = true
	var seen := {}
	var twice := 0
	for rec: Dictionary in _world.chunks:
		var parts: Array = Generator.parts_for(tree, brief, PackedStringArray([String(rec.id)]))
		_check(not parts.is_empty(), "slice: unit %s wrote nothing" % String(rec.id))
		for p: Dictionary in parts:
			for r: Dictionary in (p.draft as Resource).get("regions"):
				var key := "%s_%s" % [String((p.brief as Resource).get("id")), String(r.id)]
				if seen.has(key):
					twice += 1
				seen[key] = true
				_check(whole_regions.has(key), "slice: unit %s invented the region %s" % [String(rec.id), key])
	_check(twice == 0, "slice: %d regions are written by two units" % twice)
	_check(seen.size() == whole_regions.size(),
			"slice: %d regions over the units, %d in the whole world" % [seen.size(), whole_regions.size()])
	# an empty slice is an empty slice, never the whole level
	_check(Generator.parts_for(tree, brief, PackedStringArray()).is_empty(),
			"slice: a slice with no units wrote the whole world")
	var walls := _wall_ownership()
	_done("slice suite done (%d regions, %d walls over the units, none twice)" % [seen.size(), walls])


## WHO OWNS A SHARED WALL. A run between two units is ONE wall in the world, and in a world cut
## one unit to a scene the two sides are two different scenes — so exactly one of them may draw
## it. Requiring both sides present loses every such wall; requiring either draws each of them
## twice, at the same place, in two scenes. Neither failure shows up in a region tally and both
## are invisible until somebody walks into the world, so it is counted here — on a DUNGEON,
## because a city's quarters and blocks are drawn with no partitions at all and would prove
## nothing. Returns how many walls the slices wrote.
func _wall_ownership() -> int:
	# ON A CELL TREE BUILT BY HAND, because no recipe draws partition walls any more: the city
	# and the coast set `boundary = "none"` and a crypt is carved, so its only walls are the
	# bands around its floor islands. The rule under test belongs to `to_parts`, not to a recipe,
	# and testing it on one recipe's incidental output is how it came to be tested at all.
	var tree: RefCounted = Cell.make("owner", "zone", PackedVector2Array([
			Vector2(0, 0), Vector2(40, 0), Vector2(40, 20), Vector2(0, 20)]), 0)
	var a: RefCounted = tree.add_child("A1", "room", PackedVector2Array([
			Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)]))
	var b: RefCounted = tree.add_child("B1", "room", PackedVector2Array([
			Vector2(20, 0), Vector2(40, 0), Vector2(40, 20), Vector2(20, 20)]))
	a.leaf = true
	b.leaf = true
	# the run they share, and the boundary that says it means a wall
	tree.adjacency = [{"a": 0, "b": 1, "p": Vector2(20, 0), "q": Vector2(20, 20)}]
	tree.boundary = "wall"
	tree.wall_m = 0.5
	var brief: Resource = ZoneBrief.new()
	brief.id = "owner"
	brief.seed = 1
	var whole := 0
	for p: Dictionary in Generator.to_parts(tree, brief):
		whole += ((p.draft as Resource).get("walls") as Array).size()
	var sliced := 0
	for id in [String(a.id), String(b.id)]:
		for p: Dictionary in Generator.parts_for(tree, brief, PackedStringArray([String(id)])):
			sliced += ((p.draft as Resource).get("walls") as Array).size()
	_check(whole == 1, "slice: the whole tree drew %d walls, want 1" % whole)
	# EXACTLY ONE OF THE TWO SIDES DRAWS IT. Requiring both present loses the wall entirely when
	# each side is its own scene; accepting either draws it twice, in two scenes, at one place.
	_check(sliced == whole, "slice: %d walls over the two slices, %d in the whole" % [sliced, whole])
	return sliced


## THE UNITS ON DISK: real scenes, each saying which unit it is, walkable (collision) and
## finalized (no CSG left to compute at load).
func _scene_suite() -> void:
	var map: WorldMap = WorldBake.new_map("city", 220.0, 3, 0.8, "scenesuite")
	WorldBake.plan_world(map, self)
	var dir := OUT.path_join(map.name)
	var baked: Dictionary = await WorldBake.bake_units(map, self, dir, PackedStringArray(), true)
	_check(int(baked.units) == map.chunks.size(), "scene: %d units of %d written" % [int(baked.units), map.chunks.size()])
	_check((baked.errors as PackedStringArray).is_empty(), "scene: %s" % str(baked.errors))
	var manifest: Dictionary = WorldBake.write_owdb(map, dir)
	_check(int(manifest.error) == OK, "scene: the manifest would not save")
	var master: Dictionary = await WorldBake.write_master(map, dir, self)
	_check(int(master.error) == OK, "scene: the world scene would not save (%s)" % error_string(int(master.error)))
	_check(FileAccess.file_exists(String(master.scene_path)), "scene: no world scene on disk")
	if FileAccess.file_exists(String(master.scene_path)):
		var zone: Node3D = (load(String(master.scene_path)) as PackedScene).instantiate()
		_check(zone.get_node_or_null("OWDB") != null, "scene: the world scene has nothing to stream with")
		_check(zone.get_node_or_null("Focus") != null, "scene: the world scene has no focus")
		var owdb: Node = zone.get_node_or_null("OWDB")
		if owdb != null:
			# the settings that decide whether anything streams at all, and whether an open scene
			# would save what it streamed
			var sizes: Array = owdb.get("chunk_sizes")
			_check(sizes.size() > 0 and float(sizes[sizes.size() - 1]) >= map.chunk_m,
					"scene: the coarsest chunk is %s, under the map's %.0f m" % [str(sizes), map.chunk_m])
			_check(float(owdb.get("threshold_ratio")) >= 1.0,
					"scene: the size threshold is a fraction of the chunk — every unit is ALWAYS_LOADED")
			# THE TWO EDITOR SETTINGS, both of which have to be ON. The camera one is how a
			# streamed world becomes rows in the Scene dock at all; `load_all_chunks` is what
			# stops a Ctrl+S rewriting the manifest from whatever happened to be loaded.
			_check(bool(owdb.get("follow_editor_camera")),
					"scene: the world would not show itself in the editor")
			_check(bool(owdb.get("load_all_chunks")),
					"scene: saving the scene could truncate the manifest")
		zone.free()
	# THE WORLD AS NODES: the same world with every unit instanced and no database — what a person
	# opens and looks at, and what nothing has to make up at run time
	var still: Dictionary = await WorldBake.write_static(map, dir, self)
	_check(int(still.error) == OK, "scene: the static scene would not save (%s)" % error_string(int(still.error)))
	_check(int(still.units) == map.chunks.size(), "scene: %d units as nodes of %d" % [int(still.units), map.chunks.size()])
	if FileAccess.file_exists(String(still.scene_path)):
		var node: Node3D = (load(String(still.scene_path)) as PackedScene).instantiate()
		var as_nodes := 0
		for c: Node in node.get_children():
			if map.units.has(String(c.name)):
				as_nodes += 1
		_check(as_nodes == map.chunks.size(), "scene: %d unit nodes in the static scene of %d" % [as_nodes, map.chunks.size()])
		_check(node.get_node_or_null("OWDB") == null, "scene: the static scene still streams")
		_check(node.get_node_or_null("Terrain") != null or not ClassDB.class_exists("Terrain3D"),
				"scene: the static scene has no ground")
		node.free()
	else:
		_check(false, "scene: no static scene on disk")
	# THE SCENE YOU OPEN: the world, its ground, EVERY UNIT AS A NODE, the spawn, the portal, a
	# sun, a player, a camera — every one of them in the file. This is the assembly step, and
	# what it must never need is the generator: it reads what step one left on disk.
	var final: Dictionary = await WorldBake.write_final(map, dir, self, OUT.path_join("final"))
	_check(int(final.error) == OK, "scene: the final scene would not save (%s)" % error_string(int(final.error)))
	_check(int(final.get("units", 0)) == map.chunks.size(),
			"scene: %d units as nodes of %d" % [int(final.get("units", 0)), map.chunks.size()])
	if FileAccess.file_exists(String(final.scene_path)):
		var node: Node3D = (load(String(final.scene_path)) as PackedScene).instantiate()
		var world: Node3D = node.get_node_or_null("World")
		_check(world != null, "scene: the final scene holds no world")
		_check(node.get_node_or_null("Sun") != null, "scene: the final scene has no light")
		_check(node.get_node_or_null("Player") != null or not ResourceLoader.exists("res://scenes/player/player4.tscn"),
				"scene: the final scene has nobody in it")
		if world != null:
			# THE ROOMS ARE NOT IN THIS FILE, and that is the addon's design rather than a
			# regression: it frees any child of its database node when the scene opens and
			# rebuilds them from the manifest, so a copy here would be discarded. What puts
			# them in the Scene dock is the editor camera, checked above.
			_check(world.get_node_or_null("OWDB") != null, "scene: the scene has nothing to stream with")
			_check(world.get_node_or_null("Focus") != null, "scene: the scene has no focus")
			# the spawn and the portal ARE nodes in the file: nothing is built at `_ready`
			_check(world.get_node_or_null("SpawnA") != null, "scene: the spawn is not a node in the file")
			# and the manifest it reads is the WORLD's, not one named after this scene
			var owdb_path := String(world.get("manifest"))
			_check(owdb_path != "" and FileAccess.file_exists(owdb_path),
					"scene: the world points at no manifest (%s)" % owdb_path)
		node.free()
	var bodies := 0
	var csg := 0
	var checked := 0
	for rec: Dictionary in map.chunks:
		var path := String(rec.path)
		_check(FileAccess.file_exists(path), "scene: %s is not on disk" % path)
		if not FileAccess.file_exists(path):
			continue
		var node: Node3D = (load(path) as PackedScene).instantiate()
		checked += 1
		_check(node.has_meta("world_unit"), "scene: %s does not say which unit it is" % path)
		if node.has_meta("world_unit"):
			_check(String((node.get_meta("world_unit") as Dictionary).id) == String(rec.id),
					"scene: %s carries the wrong unit" % path)
		for n in _walk(node):
			if n is CSGShape3D:
				csg += 1
			if n is CollisionShape3D:
				bodies += 1
		node.free()
	_check(csg == 0, "scene: %d CSG nodes survived the finalize" % csg)
	_check(bodies > 0, "scene: not one collision shape in %d units — nothing to walk on" % checked)
	_done("scene suite done (%d units, %d collision shapes, %d ms)" % [checked, bodies, int(baked.ms)])


## THE MANIFEST: the file Open World Database actually reads. It is written by us, headlessly, so
## it is checked as a FILE — a line per unit, in the addon's own format, with a size that lands
## in a streaming bucket rather than in ALWAYS_LOADED.
func _owdb_suite() -> void:
	var path := OUT.path_join("scenesuite").path_join("scenesuite.tres")
	if not ResourceLoader.exists(path):
		_fails.append("owdb: the scene suite left no world at %s" % path)
		return
	var map: WorldMap = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var db := OUT.path_join("scenesuite").path_join("scenesuite.owdb")
	if not FileAccess.file_exists(db):
		_fails.append("owdb: no manifest at %s" % db)
		return
	var lines := PackedStringArray()
	for l in FileAccess.get_file_as_string(db).split("\n"):
		if String(l).strip_edges() != "":
			lines.append(String(l))
	# a unit with nothing to see is left out on purpose: streets carry no geometry
	var streamable := 0
	for rec: Dictionary in map.chunks:
		if float(rec.get("size_m", 0.0)) > 0.0:
			streamable += 1
	_check(lines.size() == streamable, "owdb: %d lines for %d streamable units of %d" % [
			lines.size(), streamable, map.chunks.size()])
	var seen := {}
	for l in lines:
		# a unit is TOP LEVEL: an indented line would make it a child of the line above it
		_check(not l.begins_with("\t"), "owdb: %s is written as somebody's child" % l.split("|")[0])
		var parts := l.split("|")
		_check(parts.size() >= 7, "owdb: %s has %d fields, not 7" % [l.substr(0, 40), parts.size()])
		if parts.size() < 7:
			continue
		var id := String(parts[0])
		_check(not seen.has(id), "owdb: %s is written twice" % id)
		seen[id] = true
		var rec: Dictionary = map.chunk(id)
		_check(not rec.is_empty(), "owdb: %s is in no record" % id)
		if rec.is_empty():
			continue
		var scene := String(parts[1]).strip_edges().trim_prefix("\"").trim_suffix("\"")
		_check(ResourceLoader.exists(scene), "owdb: %s points at %s, which is not there" % [id, scene])
		var at := _vec3(String(parts[2]))
		var want: Vector2 = rec.origin
		_check(Vector2(at.x, at.z).distance_to(want) < 0.06,
				"owdb: %s is written at %s, its scene at %s" % [id, str(Vector2(at.x, at.z)), str(want)])
		var size := String(parts[5]).to_float()
		_check(absf(size - float(rec.size_m)) < 0.01,
				"owdb: %s is %.2f m in the file, %.2f m in the map" % [id, size, float(rec.size_m)])
		# THE CLIFF: a unit larger than the coarsest chunk is ALWAYS_LOADED, silently, for ever
		_check(size > 0.0 and size <= map.chunk_m,
				"owdb: %s is %.0f m, past the %.0f m chunk: it would never stream" % [id, size, map.chunk_m])
	var problems: Array = map.check()
	_check(problems.is_empty(), "owdb: the finished map still complains: %s" % str(problems.slice(0, 3)))
	_done("owdb suite done (%d units in the manifest)" % seen.size())


func _vec3(s: String) -> Vector3:
	var p := s.strip_edges().split(",")
	return Vector3(p[0].to_float(), p[1].to_float() if p.size() > 1 else 0.0,
			p[2].to_float() if p.size() > 2 else 0.0)


## THE STREAM: units come up around the focus and go down behind it, in batches the addon paces
## itself, and the spawn's own unit is standing SYNCHRONOUSLY — before the frame the player is
## put on the spawn, which is the one guarantee `World.go_to` cannot wait for.
func _stream_suite() -> void:
	var path := OUT.path_join("scenesuite").path_join("scenesuite.tres")
	var scene_path := OUT.path_join("scenesuite").path_join("scenesuite.tscn")
	if not ResourceLoader.exists(path) or not ResourceLoader.exists(scene_path):
		_fails.append("stream: the scene suite left no world at %s" % path)
		return
	var map: WorldMap = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var zone: Node3D = (load(scene_path) as PackedScene).instantiate()
	root.add_child(zone)
	# the addon looks its world up from the CURRENT scene, which under `World.go_to` is the hub
	# and here is nothing at all: say what it is, the way the game's own main scene does
	current_scene = zone
	await process_frame
	var owdb: Node = zone.get_node_or_null("OWDB")
	var focus: Node3D = zone.get_node_or_null("Focus")
	if owdb == null or focus == null:
		_fails.append("stream: the world scene has no database to stream with")
		zone.free()
		return
	var streamable := 0
	for rec: Dictionary in map.chunks:
		if float(rec.get("size_m", 0.0)) > 0.0:
			streamable += 1
	_check(int(owdb.get_total_database_nodes()) == streamable,
			"stream: %d units known of %d" % [int(owdb.get_total_database_nodes()), streamable])
	var warmed: int = Stream.warm(owdb, focus)
	_check(warmed > 0, "stream: warm put up nothing at the spawn")
	# the unit nearest the spawn and the one farthest from it: one arrives, the other leaves
	var near := ""
	var near_d := 1.0e20
	var far := ""
	var far_d := -1.0
	for rec: Dictionary in map.chunks:
		if float(rec.get("size_m", 0.0)) <= 0.0:
			continue
		var d := (rec.origin as Vector2).distance_to(map.spawn)
		if d < near_d:
			near_d = d
			near = String(rec.id)
		if d > far_d:
			far_d = d
			far = String(rec.id)
	_check(far != near, "stream: the world has only one unit to walk to")
	_check(bool(focus.call("has_unit", near)), "stream: the spawn's own unit %s is not standing" % near)
	var to: Vector2 = (map.chunk(far) as Dictionary).origin
	focus.set("home", to)
	for i in 480:
		await process_frame
		if bool(focus.call("has_unit", far)) and not bool(focus.call("has_unit", near)):
			break
	_check(bool(focus.call("has_unit", far)), "stream: the far unit %s never arrived" % far)
	_check(not bool(focus.call("has_unit", near)), "stream: the spawn's unit never left")
	var standing: int = focus.call("standing")
	_check(standing > 0 and standing < streamable,
			"stream: %d units of %d are up — nothing is being held back" % [standing, streamable])
	current_scene = null
	root.remove_child(zone)
	zone.free()
	_done("stream suite done (%d warmed, walked from %s to %s)" % [warmed, near, far])


## THE GROUND: flat under the town whatever else it does, mountains around it, a lake in the
## ring — and a body to stand on. Skipped, not failed, where the extension is not installed.
func _terrain_suite() -> void:
	var map: WorldMap = WorldBake.new_map("city", 240.0, 5, 0.9, "terrainsuite")
	WorldBake.plan_world(map, self)
	var prof: RefCounted = Terrain.profile_of(map)
	# the plateau: every point inside the city outline is exactly zero, or a house would float
	var outline: PackedVector2Array = Terrain.city_outline(map)
	var flat := 0
	for p: Vector2 in outline:
		var inward: Vector2 = p.lerp(prof.centre as Vector2, 0.25)
		flat += 1 if is_zero_approx(Terrain.height_at(prof, inward)) else 0
	_check(flat == outline.size(), "terrain: %d of %d points inside the walls are not flat" % [outline.size() - flat, outline.size()])
	_check(is_zero_approx(Terrain.height_at(prof, prof.centre as Vector2)), "terrain: the middle of the town is not at zero")
	# the mountains: the ring is high, and it is high all the way round
	var reach := 0.0
	for r in (prof.radius as PackedFloat32Array):
		reach = maxf(reach, r)
	var far: float = reach + float(prof.skirt_m) + float(prof.ramp_m) * 1.4
	var high := 0
	var tried := 0
	for i in 24:
		var a := TAU * float(i) / 24.0
		var p: Vector2 = (prof.centre as Vector2) + Vector2.RIGHT.rotated(a) * far
		if (p - (prof.lake_centre as Vector2)).length() < float(prof.lake_r) + float(prof.lake_shore_m):
			continue          # the lake is allowed to be low
		tried += 1
		if Terrain.height_at(prof, p) > float(prof.mountain_m) * 0.3:
			high += 1
	_check(tried > 0 and high >= int(float(tried) * 0.8),
			"terrain: only %d of %d directions have mountains" % [high, tried])
	# the lake: a basin under the water line
	_check(Terrain.height_at(prof, prof.lake_centre) < float(prof.water_y),
			"terrain: the lake bed at %.1f m is not under the water at %.1f m" % [
					Terrain.height_at(prof, prof.lake_centre), float(prof.water_y)])
	_check(float(prof.lake_r) > 20.0 and ((prof.lake_centre as Vector2) - (prof.centre as Vector2)).length() > reach,
			"terrain: the lake is inside the walls")
	_sea_of_a_coast()
	# and it is the same ground every run
	var prof2: RefCounted = Terrain.profile_of(map)
	var same := true
	for i in 8:
		var p: Vector2 = (prof.centre as Vector2) + Vector2.RIGHT.rotated(TAU * float(i) / 8.0) * far
		same = same and is_equal_approx(Terrain.height_at(prof, p), Terrain.height_at(prof2, p))
	_check(same, "terrain: two readings of the same map disagree")
	if not ClassDB.class_exists("Terrain3D"):
		_done("terrain suite done (heights only: Terrain3D is not installed)")
		return
	var zone := Node3D.new()
	root.add_child(zone)
	var node: Node3D = Terrain.build(map, zone)
	_check(node != null, "terrain: the extension is installed but built nothing")
	if node != null:
		var data: Object = node.get("data")
		_check(int(data.call("get_region_count")) > 0, "terrain: no regions")
		var c: Vector2 = prof.centre
		var h: float = data.call("get_height", Vector3(c.x, 0.0, c.y))
		_check(not is_nan(h) and absf(h) < 0.6, "terrain: the ground under the town reads %s" % str(h))
		var range: Vector2 = data.call("get_height_range")
		_check(range.y > float(prof.mountain_m) * 0.5, "terrain: the highest ground is %.0f m" % range.y)
		_check(range.x < float(prof.water_y), "terrain: the lowest ground is %.1f m, above the water line" % range.x)
		var water := zone.get_node_or_null("LakeSurface")
		_check(water != null, "terrain: no water surface over the lake")
	zone.free()
	_done("terrain suite done (%d directions of mountain, lake %.0f m across)" % [tried, float(prof.lake_r) * 2.0])


## THE SEA. A coastal site is the one place the ground stops being radial: everything past the
## shore half-plane is water, whatever the mountains were doing there. What has to be true is
## that the sea is deep, the plateau under the town is STILL exactly flat — the law the walls
## and the houses stand on, and the thing an ocean is most likely to have quietly broken — and
## the island is land in the middle of it.
func _sea_of_a_coast() -> void:
	var map: WorldMap = WorldBake.new_map("coast", 380.0, 5, 0.6, "seasuite")
	WorldBake.plan_world(map, self)
	var prof: RefCounted = Terrain.profile_of(map)
	var site: Dictionary = map.site
	var shore_n: Vector2 = site.shore_n
	var shore_d := float(site.shore_d)
	_check((prof.shore_n as Vector2) != Vector2.ZERO, "sea: the profile has no shore")
	_check(float(prof.lake_r) == 0.0, "sea: a coastal world also grew a lake")
	# the plateau, unchanged: the ocean starts at the waterline and the town is landward of it
	var outline: PackedVector2Array = Terrain.city_outline(map)
	var wet := 0
	for p: Vector2 in outline:
		var inward: Vector2 = p.lerp(prof.centre as Vector2, 0.25)
		if inward.dot(shore_n) - shore_d > 0.0:
			continue                     # this bit of the grown outline is over the water
		if not is_zero_approx(Terrain.height_at(prof, inward)):
			wet += 1
	_check(wet == 0, "sea: %d points inside the town are no longer flat" % wet)
	# deep water where the sea is
	var deep: Vector2 = (prof.centre as Vector2) + shore_n * (float(prof.shore_fall_m) * 2.5)
	_check(Terrain.height_at(prof, deep) < float(prof.water_y) - 2.0,
			"sea: %.1f m out it is only %.1f m deep" % [float(prof.shore_fall_m) * 2.5, Terrain.height_at(prof, deep)])
	# and the island is land, standing out of it
	_check(float(prof.island_r) > 20.0, "sea: no island (%.0f m)" % float(prof.island_r))
	_check(Terrain.height_at(prof, prof.island_centre) > float(prof.water_y) + 5.0,
			"sea: the island is under the water at %.1f m" % Terrain.height_at(prof, prof.island_centre))
	_check((prof.island_centre as Vector2).dot(shore_n) - shore_d > 0.0, "sea: the island is on the land")
	_say("[VERIFY]   sea: %.0f m deep, an island %.0f m across %.0f m high, peaks to %.0f m" % [
			-Terrain.height_at(prof, deep), float(prof.island_r) * 2.0, float(prof.island_h),
			float(prof.mountain_m)])


## Everything this run wrote, gone: a derived folder is not left lying in the project.
func _wipe(dir: String) -> void:
	var abs := ProjectSettings.globalize_path(dir)
	var d := DirAccess.open(abs)
	if d == null:
		return
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(abs.path_join(f))
	DirAccess.remove_absolute(abs)


func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _done(msg: String) -> void:
	_suites_done += 1
	_say("[VERIFY] " + msg)


func _say(msg: String) -> void:
	print(msg)
	_log += msg + "\n"

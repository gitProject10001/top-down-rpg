class_name DungeonGenerator
extends Node3D
## The crypt zone root (attached to scenes/world/zone_crypt.tscn). Generates a fresh Isaac-style
## dungeon SYNCHRONOUSLY in _ready() — which runs inside World.go_to's add_child, BEFORE its
## SpawnA lookup — so creating the SpawnA marker + ReturnPortal here satisfies the existing
## portal contract with zero changes to the hub.
##
## Layout is pure data (DungeonLayout), rooms are kit-built (RoomBuilder), runtime flow lives in
## DungeonRoom. A new random layout every entry; set dungeon_seed != 0 to pin one for debugging.

@export var dungeon_seed := 0            ## 0 = new dungeon every entry (seed printed for repro)
@export var room_count := 9
## Flights of stairs to a floor above. Each one also adds the room it leads to.
@export var stair_count := 1
## Extra edges closing loops, so the dungeon has routes rather than one path in and back out.
@export var loop_count := 2
@export var room_zoom := 1.15            ## camera zoom claimed by every room (close, Isaac-tight)
@export var template_chance := 0.5       ## odds a combat room uses a handcrafted template

## Everything about how this dungeon LOOKS. Swap it to re-skin the crypt without touching the
## layout or the encounters. Left empty, the crypt theme is loaded.
@export var theme: DungeonTheme

@export_group("Theme overrides")
## -1 = use the theme's value. The crypt is TORCHLIT: the persistent sun is dimmed while inside.
@export var sun_factor := -1.0
@export var ambient_factor := -1.0

const TEMPLATE_DIR := "res://scenes/dungeon/rooms/"
const RETURN_ZONE := "res://scenes/world/room.tscn"
const DEFAULT_THEME := "res://scenes/dungeon/themes/crypt.tres"

var layout: DungeonLayout

## Gates waiting on a key, and the keys taken so far. Kept on the zone root (group "dungeon") so
## the pickup can find it by group instead of via an autoload — the headless suite runs without
## autoloads registered.
var _locked: Array = []
var _keys_held := {}


## Holds the preloaded enemy scenes for the zone's lifetime. Godot's resource cache keeps a
## resource only while something references it, so dropping these would un-cache them.
var _warm: Array = []


func _ready() -> void:
	add_to_group("dungeon")                  # how a key pickup finds us, without an autoload
	# park the dungeon far from the hub's persistent leftovers in main.tscn (enemies, NPC, props
	# hand-placed around the origin) so nothing bleeds into the crypt's airspace
	position = Vector3(500.0, 0.0, 500.0)

	# Pay the one-off costs NOW, while the zone is still loading behind a fade, instead of on the
	# frame the player walks into a room. Measured: the swordsman scene alone took 417 ms to load
	# cold (it drags in a 13 MB character), and building the shared clip library another ~10 ms.
	#
	# `_warm` MUST hold the references. Godot's resource cache only keeps what is still referenced,
	# so `ResourceLoader.load(path)` with the result discarded frees it again immediately and caches
	# nothing — which is exactly the bug this line originally had.
	Enemy.warm_caches()
	for path in DungeonRoom.ENEMY_SCENES.values():
		if ResourceLoader.exists(path):
			_warm.append(ResourceLoader.load(path))

	if theme == null and ResourceLoader.exists(DEFAULT_THEME):
		theme = load(DEFAULT_THEME) as DungeonTheme

	layout = DungeonLayout.generate(dungeon_seed, room_count, stair_count, loop_count)
	print("[Crypt] seed=%d rooms=%d" % [layout.seed_used, layout.rooms.size()])
	# Dungeon-level stream, decoupled from the layout walk. Per-ROOM randomness does not live here:
	# each room derives its own named streams from (seed, cell, pass) via RoomContext.
	var tpl_rng := RandomNumberGenerator.new()
	tpl_rng.seed = layout.seed_used + 7919

	var pool := _scan_templates()
	_assign_templates(tpl_rng, pool)

	# rooms
	var room_nodes := {}
	for anchor: Vector3i in layout.rooms:
		var rd: DungeonLayout.RoomData = layout.rooms[anchor]
		var room := DungeonRoom.new()
		room.name = "Room_%d_%d_%d" % [anchor.x, anchor.y, anchor.z]
		room.cell = anchor                       # the map keys its discovery on this
		room.data = rd                           # the layout row, so a live room knows its own role
		room.position = DungeonLayout.room_origin(rd)
		room.footprint = DungeonLayout.size_of(rd)
		room.room_zoom = room_zoom
		room.is_boss = rd.type == DungeonLayout.RoomType.BOSS
		if rd.type == DungeonLayout.RoomType.STAIR:
			# the climb plus head room — NOT plus wall height, which is a different quantity now
			room.trigger_height = DungeonLayout.FLOOR_HEIGHT + DungeonLayout.HEAD_ROOM
		add_child(room)
		var ctx := RoomContext.create(rd, layout.seed_used)
		room.spawn_defs = RoomBuilder.build(room, rd, ctx, theme)
		# KEEP THE PLAN. The occupancy grid is thrown away today, and anything wanting to add a
		# fixture afterwards has to re-derive "where is there floor" from something weaker — the
		# footprint (a bounding box that knows nothing about carved corners), the slot metas (which
		# carry no footprints and miss the dresser's own clutter), or a physics query (which returns
		# nothing at all this early, because the bodies added microseconds ago have not reached the
		# server). RoomContext is a RefCounted, so holding it adds no node, no position and no
		# collision shape — it is invisible to every suite that walks this tree.
		room.plan = ctx
		if rd.type in [DungeonLayout.RoomType.START, DungeonLayout.RoomType.TREASURE,
				DungeonLayout.RoomType.STAIR]:
			room.state = DungeonRoom.State.CLEARED       # safe rooms never lock
		room_nodes[anchor] = room

	# connections: one passage + gate per adjacent pair (each edge is stored on both rooms, so
	# exactly one side builds it)
	for anchor: Vector3i in layout.rooms:
		var rd: DungeonLayout.RoomData = layout.rooms[anchor]
		for e: DungeonLayout.Edge in rd.edges:
			if not EdgeCraft.owns_edge(e.dir):
				continue                                 # the neighbour builds this one
			var other := layout.room_at(e.from_cell + e.dir)
			if other == null:
				continue
			var door := EdgeCraft.build_edge(self, layout, e, theme)
			if door == null:
				continue
			if e.type == DungeonLayout.EdgeType.LOCKED:
				door.lock(e.key_id)
				_locked.append(door)
			(room_nodes[anchor] as DungeonRoom).doors.append(door)
			(room_nodes[other.cell] as DungeonRoom).doors.append(door)

	# zone contract: SpawnA marker + the way home, both in the start room
	var start_room: DungeonRoom = room_nodes[Vector3i.ZERO]
	var spawn := Marker3D.new()
	spawn.name = "SpawnA"
	spawn.position = Vector3(0, 1.2, 0)
	start_room.add_child(spawn)
	var portal := (load("res://scenes/props/portal.tscn") as PackedScene).instantiate()
	portal.name = "ReturnPortal"
	portal.target_zone_path = RETURN_ZONE
	portal.target_spawn = "SpawnFromCrypt"
	start_room.add_child(portal)
	(portal as Node3D).position = Vector3(0, 0, 4)

	_furnish(room_nodes)

	# torchlit crypt: dim the persistent sun/ambient while this zone is alive (restored in
	# _exit_tree), and start every room dark except the one the player arrives in
	_dim_world(true)
	for anchor: Vector3i in room_nodes:
		(room_nodes[anchor] as DungeonRoom).set_lit(anchor == Vector3i.ZERO, false)
	# ...and draw only the arrival room and what adjoins it. Must come after the door loop above:
	# show_around() reads adjacency off the shared DungeonDoor refs, which do not exist yet when
	# the rooms themselves are built.
	start_room.show_around()

	# The static cutaway (RoomDresser.cutaway_out) clears the camera-facing side of every room, but
	# it cannot know that the player has walked THROUGH a wall — leaving a room puts that room's far
	# wall between them and the lens. This picks up the residual, per frame, off the same meta.
	var veil := CourseVeil.new()
	veil.name = "CourseVeil"
	add_child(veil)
	veil.collect(self)

	# BAKED GI, PRIMED BEFORE THE PLAYER CAN SEE ANYTHING. This runs inside the zone's _ready, which
	# is inside World.go_to's add_child, which is behind the portal fade — the one window where
	# several seconds of blocked main thread cost nothing. Only the arrival room and its immediate
	# neighbours are baked here (show_around makes the rest invisible anyway); RoomGI keeps up from
	# there, one room per tick.
	var gi := RoomGI.new()
	gi.name = "RoomGI"
	add_child(gi)
	gi.setup(self)
	gi.prime(start_room)


## GAMEPLAY FURNITURE GOES HERE, and only in a subclass. Empty on the base crypt, so
## zone_crypt.tscn — which eleven test suites instantiate and two pinned hashes describe — is
## provably unchanged: the proof is these two words, not a trace through a conditional.
##
## A `@export var slice := false` would have done the same job and is one merge or one editor
## re-save away from being true in a scene nobody meant to change. A subclass cannot arrive in
## zone_crypt.tscn by accident.
##
## CALLED HERE, and the position is not a matter of taste. It is after the door loop (a director
## needs room.doors populated) and after SpawnA/ReturnPortal (so it can avoid the arrival lane), and
## it MUST be before _dim_world/set_lit below — DungeonRoom caches its light list on the first
## set_lit call, so a light added afterwards is never dimmed and never has its shadow dropped, and
## burns at full energy in a room the player left.
func _furnish(_room_nodes: Dictionary) -> void:
	pass


## Called by DungeonKey when the player picks one up. Opens every gate that was waiting on it.
func grant_key(key_id: String) -> void:
	if _keys_held.has(key_id):
		return
	_keys_held[key_id] = true
	for door in _locked:
		if is_instance_valid(door):
			door.unlock(key_id)
	print("[Crypt] key taken: %s" % key_id)


func has_key(key_id: String) -> bool:
	return _keys_held.has(key_id)


## Everything DungeonEnv took from the persistent outdoor Environment, so it can be handed back
## intact. Empty = we are not currently holding the world.
var _env_snap := {}

## Swap the persistent outdoor look for this theme's dungeon look, and back again. All twenty-odd
## properties live in DungeonEnv; this end only owns the lifecycle.
func _dim_world(dim: bool) -> void:
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	var env_node = get_tree().get_first_node_in_group("world_env")
	var env: Environment = env_node.environment if env_node else null
	if dim:
		# RE-ENTRANCY GUARD. Latent in the old loose-variable version: if two zones are ever alive at
		# once, the second one snapshots the ALREADY DIMMED values and later "restores" the crypt's
		# black void onto the hub. With three floats that was a curiosity; with a whole environment
		# it is an overworld nobody can get the daylight back into.
		if not _env_snap.is_empty():
			return
		_env_snap = DungeonEnv.apply(env, sun, theme, sun_factor, ambient_factor,
				_outdoor_scenery())
	else:
		DungeonEnv.restore(env, sun, _env_snap)
		_env_snap.clear()


## Persistent overworld MESHES that have to go away while a dungeon is alive. Blacking out the
## Environment cannot reach these — a CloudSea is a 700 m MeshInstance3D under the world, and the
## crypt was rendering a lid of daylit cloud below its own floor.
##
## By CLASS rather than by group, deliberately: main.tscn would need a group added to it and every
## future scene would need somebody to remember, whereas a CloudSea is a CloudSea. If a second kind
## of persistent scenery ever appears, it gets one more line here and nothing else changes.
func _outdoor_scenery() -> Array:
	# From the tree ROOT, not from current_scene. The zone the crypt lives in is swapped in by
	# WorldManager, and which node counts as "current" during that swap is exactly the kind of
	# detail that would make this work in one code path and silently not in another.
	var out: Array = []
	_collect_scenery(get_tree().root, out)
	return out


static func _collect_scenery(n: Node, out: Array) -> void:
	if n is CloudSea:
		out.append(n)
		return
	for c in n.get_children():
		_collect_scenery(c, out)


func _exit_tree() -> void:
	_dim_world(false)                       # leaving the crypt restores the outdoor light


# The passage builders (owns_edge, build_corridor, the light at the door) lived here until the
# Dungeon Forge editor preview became their second caller; they moved verbatim to
# scripts/dungeon/edge_craft.gd so a preview cannot drift from the game one piece at a time.


func _scan_templates() -> Array[String]:
	var pool: Array[String] = []
	var dir := DirAccess.open(TEMPLATE_DIR)
	if dir == null:
		return pool
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			pool.append(TEMPLATE_DIR + f)
		elif f.ends_with(".tscn.remap"):                 # exported builds rename resources
			pool.append(TEMPLATE_DIR + f.trim_suffix(".remap"))
	return pool


func _assign_templates(rng: RandomNumberGenerator, pool: Array[String]) -> void:
	if pool.is_empty():
		return
	var boss_tpl := TEMPLATE_DIR + "room_brute.tscn"
	for anchor: Vector3i in layout.rooms:
		var rd: DungeonLayout.RoomData = layout.rooms[anchor]
		# templates are authored against the single-cell footprint (+-9 x +-5); a hall would leave
		# their props marooned in one corner
		if rd.size != Vector3i.ONE:
			continue
		match rd.type:
			DungeonLayout.RoomType.COMBAT:
				if rng.randf() < template_chance:
					rd.template_path = pool[rng.randi_range(0, pool.size() - 1)]
			DungeonLayout.RoomType.BOSS:
				if pool.has(boss_tpl):
					rd.template_path = boss_tpl

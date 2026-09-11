extends Node3D
## The wilds zone root (attached to scenes/world/zone_wilds.tscn). Same contract and the same
## shape as DungeonGenerator: generate SYNCHRONOUSLY in _ready() — inside World.go_to's
## add_child, before its SpawnA lookup — park away from the hub's airspace, and never @tool
## (opening the scene must not build a forest in the editor; the Wilds addon's preview is the
## editor path).

const Terrain := preload("res://scripts/wilds/wilds_terrain.gd")
const Flora := preload("res://scripts/wilds/wilds_flora.gd")
const RETURN_ZONE := "res://scenes/world/room.tscn"

## The authored map. Left empty, a fresh rolling map is derived from a random seed each entry —
## the crypt's dungeon_seed contract, at landscape scale.
@export var map: WildsMap
## Non-zero pins the seed over whatever the map carries (0 = respect the map / roll fresh).
@export var map_seed := 0
@export var style: WildsStyle
## STREAM the world: only the sections around the player exist — mesh, collider and forest —
## spawned and despawned as they move (scripts/wilds/wilds_stream.gd). Off = the old eager
## full build, which the shot harness uses to photograph the whole map at once.
@export var stream := true

var derived: Dictionary = {}
var built_map: WildsMap = null


func _ready() -> void:
	# Park clear of the hub origin AND the crypt's own parking spot at (500, 0, 500).
	position = Vector3(-500.0, 0.0, 500.0)

	var m: WildsMap = map
	if m == null:
		m = WildsMap.new()
		m.seed = randi() % 1000000 + 1
	if map_seed != 0:
		m = m.duplicate(true)
		m.seed = map_seed
	built_map = m

	# THREE OPENINGS, by size and purpose:
	#  - eager (stream off): full derive + full build — the shot harness and the bake.
	#  - guarantee (streamed, <= 256 per side): one global LIGHT derive, so reachability
	#    repair still runs and the suites' contract holds; chunks mesh lazily from it.
	#  - lazy (streamed, bigger): NO global derivation at all — each section derives its own
	#    region as it streams in. Traversal is the jump plus painted ramps; entry cost is the
	#    spawn ring, whatever the map size. The 14 km answer.
	var lazy := stream and (m.cells_w > 256 or m.cells_h > 256)
	if lazy:
		derived = {}
		print("[Wilds] seed=%d cells=%dx%d LAZY stream (region derive per section)"
				% [m.seed, m.cells_w, m.cells_h])
	else:
		derived = WildsGen.derive_light(m) if stream else WildsGen.derive(m)
		print("[Wilds] seed=%d cells=%dx%d tiers %d..%d auto_ramps=%d shelves=%d stream=%s"
				% [m.seed, m.cells_w, m.cells_h, derived.min_tier, derived.max_tier,
				derived.auto_ramps, derived.shelves, stream])

	var terrain: StaticBody3D = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	if lazy:
		terrain.build_lazy(m, style)
	elif stream:
		terrain.build_streaming(m, derived, style)
	else:
		terrain.build(m, derived, style)
	# Centre the map on the zone origin so the camera's numbers stay small.
	terrain.position = Vector3(-m.cells_w * m.cell_size * 0.5, 0.0,
			-m.cells_h * m.cell_size * 0.5)

	# Where the player lands: the derivation's spawn when one exists; on a lazy map, the
	# authored spawn_cell, else a deterministic non-water pick near the map centre found by
	# deriving just that one region.
	var sp: Vector2i
	if lazy:
		sp = m.spawn_cell
		if not m.in_bounds(sp) or WildsGen.is_water(m, m.idx(sp)) \
				or WildsGen._in_border(m, sp):
			sp = _spawn_near_centre(m)
	else:
		sp = derived.spawn

	# The forest itself — a sibling of the terrain at the same origin, so flora-local XZ is
	# terrain-local XZ and the foliage ground contract needs no translation.
	var flora := Node3D.new()
	flora.name = "Flora"
	flora.position = terrain.position
	add_child(flora)
	if stream:
		var streamer := preload("res://scripts/wilds/wilds_stream.gd").new()
		streamer.name = "Stream"
		streamer.setup(terrain, flora, m, derived, style)
		streamer.spawn_cell = sp
		add_child(streamer)
		# The spawn ring stands SYNCHRONOUSLY, before SpawnA is placed — there must be ground
		# to stand on the frame the player arrives.
		streamer.warm(sp)
	else:
		Flora.build(flora, m, derived, terrain, style)
	if lazy:
		# Beyond the streamed ring, the FAR LOD: one coarse backdrop mesh + canopy masses for
		# the whole map, sitting a hand below the true surface so streamed sections always
		# cover it. No collision, no shadows — scenery for the horizon. The streamer clears
		# its canopy masses around the player, so the ring's real trees are never doubled.
		var far: Node3D = preload("res://scripts/wilds/wilds_far.gd").build(m, style)
		far.position = terrain.position
		add_child(far)
		var streamer_node := get_node_or_null("Stream")
		if streamer_node != null:
			streamer_node.set("far", far)

	# One camera claim over the whole map (the W1 deferral, honoured): outdoors the sun must
	# reach past the rig's 40 m default or the far terraces read as flat paper. DOF stays ZERO —
	# this is a combat space, not a vista (camera_zone.gd's own argument).
	var cam_zone := Area3D.new()
	cam_zone.name = "WildsCameraZone"
	cam_zone.set_script(load("res://scripts/camera_zone.gd"))
	cam_zone.set("shadow_distance", 60.0)
	var cam_shape := CollisionShape3D.new()
	var cam_box := BoxShape3D.new()
	cam_box.size = Vector3(m.cells_w * m.cell_size + 20.0, 40.0,
			m.cells_h * m.cell_size + 20.0)
	cam_shape.shape = cam_box
	cam_zone.add_child(cam_shape)
	add_child(cam_zone)
	cam_zone.position = Vector3(0.0, 10.0, 0.0)

	# Zone contract: SpawnA on the spawn cell, and the way home. On a lazy map the height
	# comes from the ground contract — the spawn ring is warm, so this is a cache hit.
	var ground_y: float = terrain.height_at((Vector2(sp) + Vector2(0.5, 0.5)) * m.cell_size)
	var spawn := Marker3D.new()
	spawn.name = "SpawnA"
	spawn.position = terrain.position + Vector3((sp.x + 0.5) * m.cell_size, ground_y + 1.2,
			(sp.y + 0.5) * m.cell_size)
	add_child(spawn)
	if ResourceLoader.exists("res://scenes/props/portal.tscn"):
		var portal := (load("res://scenes/props/portal.tscn") as PackedScene).instantiate()
		portal.name = "ReturnPortal"
		portal.set("target_zone_path", RETURN_ZONE)
		portal.set("target_spawn", "SpawnFromCrypt")
		add_child(portal)
		# Beside the spawn, on whatever the ground there actually is. EAST of it, never south:
		# the rig looks from the south, and a portal 4 m south of the spawn stands exactly on
		# the sightline — the player materialises as a silhouette inside the portal glow
		# (measured in the walk bench).
		var plocal := Vector2((sp.x + 0.5) * m.cell_size + 4.0, (sp.y + 0.5) * m.cell_size)
		(portal as Node3D).position = terrain.position \
				+ Vector3(plocal.x, terrain.height_at(plocal), plocal.y)


## A deterministic landing spot on a map too big to derive whole: derive the centre REGION
## and take the non-water cell nearest the centre. No modal-tier statistics — those need the
## world, and the world is the thing we refuse to compute.
func _spawn_near_centre(m: WildsMap) -> Vector2i:
	var centre := Vector2i(m.cells_w / 2, m.cells_h / 2)
	@warning_ignore("integer_division")
	var origin := Vector2i(centre.x / WildsGen.CHUNK * WildsGen.CHUNK,
			centre.y / WildsGen.CHUNK * WildsGen.CHUNK)
	var region := WildsGen.derive_region(m, Rect2i(origin,
			Vector2i(WildsGen.CHUNK, WildsGen.CHUNK)))
	var best := centre
	var best_d := 1 << 30
	var rect: Rect2i = region.rect
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			var c := Vector2i(cx, cz)
			if WildsGen.is_water(m, m.idx(c)) or WildsGen._in_border(m, c):
				continue
			var dist := (c - centre).length_squared()
			if dist < best_d:
				best_d = dist
				best = c
	return best

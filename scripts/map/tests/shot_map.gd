extends SceneTree
## PHOTOGRAPH THE MAP, after walking far enough to have something to show. Run WITHOUT --headless —
## the dummy renderer has no pixels, so a headless run saves black frames.
##
##   Godot_console.exe --path . --resolution 1600x1000 --script res://scripts/map/tests/shot_map.gd -- \
##       --out=C:/some/folder
##
## Walks the player in 1 m steps rather than teleporting between landmarks, because the thing being
## photographed is the TRAIL: a jump of 30 m produces two discs with a hole between them, which
## would be a picture of the throttle being broken rather than of the map.

const STEP := 1.0

## World-space (main.tscn) waypoints: house, out to the garden portal, back through the hall, down
## the ramp, and across the arena floor 14 m below.
const PATH := [
	Vector3(6.88, 4.5, -21.5),
	Vector3(6.88, 4.5, -38.0),
	Vector3(6.88, 4.5, -14.0),
	Vector3(6.88, 4.2, -11.0),
	Vector3(6.88, -9.0, 4.0),
	Vector3(6.88, -9.0, 26.0),
	Vector3(30.0, -9.0, 36.0),
]

var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		push_error("no main.tscn")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	# World.go_to adds the new zone to current_scene, which a hand-added root child does not set.
	# Without this the crypt leg fails with "Cannot call method 'add_child' on a null value".
	current_scene = main
	for i in 30:
		await process_frame

	var player := root.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		push_error("no node in group 'player'")
		quit(1)
		return

	# THE PERSISTENCE CHECK, and the reason this harness is worth running twice: on a clean profile
	# this prints 0, and on the second run it must print whatever the first run finished with. That
	# is the whole "exploration survives quitting" requirement, end to end through a real save file.
	var md0 := root.get_node_or_null("/root/MapData")
	print("[SHOT] discovered at boot: %d cells" % _discovered(md0))

	for i in range(1, PATH.size()):
		var from: Vector3 = PATH[i - 1]
		var to: Vector3 = PATH[i]
		var steps := maxi(int(from.distance_to(to) / STEP), 1)
		for s in range(steps + 1):
			player.global_position = from.lerp(to, float(s) / float(steps))
			if "velocity" in player:
				player.set("velocity", Vector3.ZERO)
			await physics_frame
	print("[SHOT] walked %d waypoints" % PATH.size())

	var md := root.get_node_or_null("/root/MapData")
	var ms := root.get_node_or_null("/root/MapScreen")
	if md == null or ms == null:
		push_error("map autoloads missing")
		quit(1)
		return
	print("[SHOT] zone=%s grid=%dx%d rect=%s"
			% [md.current.key, md.current.grid.w, md.current.grid.h, md.current.grid.rect])

	# A couple of markers, so the step-2 half is in the photograph too.
	md.add_marker(1, Vector2(0.0, -16.0))         # CHEST, out in the garden
	md.add_marker(2, Vector2(0.0, 56.0))          # DANGER, in the arena

	# The other half of the render-layer change: moving the cloud sea to its own layer must not stop
	# the PLAYER's camera drawing it. Asserted numerically rather than eyeballed off a screenshot —
	# "is that pale surface the cloud sea or the arena floor" is not a question a picture answers.
	var pcam := root.get_viewport().get_camera_3d()
	var seas: Array[Node3D] = []
	_collect_clouds(root, seas)
	for s in seas:
		print("[SHOT] hub cloud sea: visible=%s layers=%d | camera cull_mask=%d renders it=%s"
				% [s.visible, (s as VisualInstance3D).layers, pcam.cull_mask,
				(pcam.cull_mask & (s as VisualInstance3D).layers) != 0])
	await _shoot("hub_world")

	ms.show_map()
	await _shoot("map_fit")

	ms._step_zoom(1)
	ms._step_zoom(1)
	await _shoot("map_close")

	# PANNED. The plan is the only layer that does not update itself every frame, so a pan is the
	# case where the ink can slide off the fog it belongs to. Shoot it off-centre and the alignment
	# is checkable by eye: the house outline must still sit inside the revealed ground.
	ms._step_zoom(-1)
	ms._pan += Vector2(26.0, 14.0)
	await _shoot("map_pan")
	ms.close()                                      # close() flushes the save
	print("[SHOT] discovered after the walk: %d cells" % _discovered(md))
	var rel: Texture2D = md.current.relief
	print("[SHOT] relief: %s" % ["none" if rel == null else str(rel.get_size())])
	if rel:
		rel.get_image().save_png(_out + "relief_raw.png")

	await _crypt(md, ms, player)
	quit(0)


## Into the crypt, entering rooms the way the player does — by standing in them, so the room trigger
## fires and the map learns the dungeon through the same hook the torches use.
func _crypt(md: Node, ms: Node, _player: Node3D) -> void:
	var world := root.get_node_or_null("/root/World")
	world.go_to(load("res://scenes/world/zone_crypt.tscn"), "SpawnA")
	for i in 120:                                   # two 0.3 s fades plus generation
		await process_frame

	var dungeon := root.get_tree().get_first_node_in_group("dungeon") as Node3D
	if dungeon == null:
		print("[SHOT] no dungeon — skipped")
		return
	var lay: DungeonLayout = dungeon.get("layout")
	var anchors: Array = lay.rooms.keys()
	anchors.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return (lay.rooms[a] as DungeonLayout.RoomData).dist \
				< (lay.rooms[b] as DungeonLayout.RoomData).dist)

	# Four rooms deep: enough for entered rooms, their outlined neighbours, and at least one
	# corridor drawn between two known ends. Plus the STAIR room wherever it is — a flight is the
	# one piece whose walkable surface is a tilted ramp rather than floor tiles, so it is the room
	# most worth having in the photograph.
	var visit: Array = anchors.slice(0, mini(4, anchors.size()))
	for a: Vector3i in anchors:
		if (lay.rooms[a] as DungeonLayout.RoomData).type == DungeonLayout.RoomType.STAIR \
				and not visit.has(a):
			visit.append(a)

	var who := root.get_tree().get_first_node_in_group("player") as Node3D
	for i in visit.size():
		var rd: DungeonLayout.RoomData = lay.rooms[visit[i]]
		who.global_position = dungeon.to_global(DungeonLayout.room_origin(rd) + Vector3(0, 1.2, 0))
		for f in 14:
			await physics_frame
	print("[SHOT] crypt seed=%d rooms=%d, entered %d"
			% [lay.seed_used, lay.rooms.size(), md.current.rooms_seen.size()])

	# THE REGRESSION. DungeonEnv hides the cloud sea for as long as you are underground; the relief
	# capture used to force it back on afterwards, and the crypt rendered sitting on daylit cloud.
	# Drawing a map must leave the world exactly as it found it. Kept even though the capture no
	# longer touches visibility at all — the property under test is "the map changed nothing", which
	# outlives whichever mechanism happens to implement it.
	var clouds: Array[Node3D] = []
	_collect_clouds(root, clouds)
	var lit := 0
	for c in clouds:
		if c.visible:
			lit += 1
	print("[SHOT] cloud sea in crypt: %d of %d visible (expect 0)" % [lit, clouds.size()])
	await _shoot("crypt_world")                     # the 3D view, so clouds would be plain to see

	ms.show_map()
	await _shoot("map_crypt")
	ms.close()


func _collect_clouds(n: Node, out: Array[Node3D]) -> void:
	if n is CloudSea:
		out.append(n as Node3D)
		return
	for c in n.get_children():
		_collect_clouds(c, out)


func _discovered(md: Node) -> int:
	if md == null or md.current == null or md.current.grid == null:
		return -1
	var n := 0
	for b in (md.current.grid as MapGrid).bytes:
		if b > 0:
			n += 1
	return n


func _shoot(name: String) -> void:
	for i in 45:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + name + ".png"
	if img.save_png(path) == OK:
		print("[SHOT] ok   %s (%d x %d)" % [path, img.get_width(), img.get_height()])
	else:
		print("[SHOT] FAILED %s" % path)

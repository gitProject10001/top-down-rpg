@tool
extends Node3D
## WALK THE GENERATED WORLD — the smallest scene that puts the player inside one: a generated
## world's master scene, the player, the camera rig, a sun. Nothing here is the game's flow (that
## is `World.go_to`, and a generated world is a zone like any other); this is the scene you press
## F6 on to see whether a city is a place you can walk in.
##
## IT SHOWS ITS WORLD IN THE EDITOR. Opening this scene puts the world in the viewport at once
## (a PREVIEW: added unowned, so looking at a world never saves one into this scene),
## so the Scene dock is not four nodes and an empty sky. The generated `<world>_walk.tscn` is the
## other way round — there every node IS in the file — and that is the scene to press play on.
##
## NOTHING IS GENERATED HERE. It walks a world that already exists on disk, and it prefers the
## `_static` scene of it: every tile instanced as a NODE, no streamer, so what you press F6 on is
## what you saw in the editor. Generating is a separate act with a button of its own (the
## Architecture dock's *Generate world*, or `tools/pa_world.gd`).
##
## IT FINDS ITS OWN WORLD, though: a generated world is a DERIVED folder — whoever generated it
## has one, a fresh checkout has none — so naming one here makes a scene that only works on the
## machine it was written on. Empty `world` means "the newest CITY under `scenes/world/gen`".
##
## The zone parks itself and builds its own SpawnA in `_ready`, so the player is moved onto it
## the frame after — an author cannot know where the spawn is, only the map does.
##
##   --world=res://scenes/world/gen/<name>/<name>.tscn  a particular world instead of the newest.
##   --shot=res://…png                                  saves one frame after landing and quits
##                                                      (windowed, not --headless: it renders).
##   --wide                                             takes that shot from high above instead of
##                                                      the game camera, to judge the terrain.

const GEN_DIR := "res://scenes/world/gen"
## Worlds an older version of this scene generated for itself; still walkable, never written to.
const FALLBACK_DIR := "user://gen"
## Below this the player has fallen out of the world and is put back on the spawn.
const FLOOR_Y := -60.0

## A particular world's master scene. EMPTY = the newest world of `prefer_kind` under
## `scenes/world/gen`.
@export_file("*.tscn") var world := ""
## Which world this scene is for. A project holds worlds of several kinds and the newest is
## whichever was generated last — this scene is called city_walk, so it walks a CITY unless
## there is none. `--kind=` overrides it; empty takes the newest of any kind.
@export var prefer_kind := "city"
## Print what the streamer is holding every second (how a stream is judged without a profiler).
@export var report := true

var _zone: Node3D = null
var _player: Node3D = null
var _t := 0.0
var _shot := ""
var _wide := false
var _frames := 0
var _falls := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world = a.trim_prefix("--world=")
		elif a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		elif a == "--wide":
			_wide = true
		elif a.begins_with("--kind="):
			prefer_kind = a.trim_prefix("--kind=")
	_player = get_node_or_null("Player")
	var path := _find_world()
	if path == "":
		push_error(("[CityWalk] no world under %s. Generate one first: the Architecture dock's "
				+ "Generate world (set the kind to city), or tools/pa_world.gd --kind=city.") % GEN_DIR)
		return
	print("[CityWalk] world %s" % path)
	_zone = (load(path) as PackedScene).instantiate()
	add_child(_zone)
	await get_tree().process_frame
	_land()


## THE EDITOR'S COPY: the world stood up the moment the scene is opened, so it can be looked at
## and flown through. Unowned, so it is never written into this scene; freed with it.
func _preview() -> void:
	for c in get_children():
		if String(c.name) == "WorldPreview":
			c.free()
	var path := _find_world()
	if path == "":
		return
	var world: Node = (load(path) as PackedScene).instantiate()
	world.name = "WorldPreview"
	add_child(world)
	print("[CityWalk] preview %s" % path)


## The world to walk: the one asked for, else the newest one the PROJECT holds, else the newest
## this scene generated for itself, else nothing. A world is a folder whose master scene carries
## the folder's own name.
func _find_world() -> String:
	if world != "" and ResourceLoader.exists(world):
		return world
	# the project's own worlds first, whatever this scene left in user:// on some earlier run
	for dir in [GEN_DIR, FALLBACK_DIR]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var wanted := ""
		var wanted_at := -1
		var any := ""
		var any_at := -1
		for name in d.get_directories():
			# the world AS NODES first: same world, every tile a node in the scene
			var path := "%s/%s/%s_static.tscn" % [dir, name, name]
			if not ResourceLoader.exists(path):
				path = "%s/%s/%s.tscn" % [dir, name, name]
			if not ResourceLoader.exists(path):
				continue
			var at := int(FileAccess.get_modified_time(ProjectSettings.globalize_path(path)))
			var kind := _kind_of(dir, name)
			print("[CityWalk]   %s (%s)" % [path, kind])
			if at > any_at:
				any_at = at
				any = path
			if prefer_kind != "" and kind == prefer_kind and at > wanted_at:
				wanted_at = at
				wanted = path
		if wanted != "":
			return wanted
		if any != "":
			if prefer_kind != "":
				push_warning("[CityWalk] no %s world under %s: walking %s instead" % [prefer_kind, dir, any])
			return any
	return ""


## What a world is: the kind of its first zone's brief. The folder name is only a hint (a world
## may be named anything), so the map itself is asked.
func _kind_of(dir: String, name: String) -> String:
	var map_path := "%s/%s/%s.tres" % [dir, name, name]
	if ResourceLoader.exists(map_path):
		var map: Resource = ResourceLoader.load(map_path)
		if map != null and not (map.get("zones") as Array).is_empty():
			var brief: Resource = ((map.get("zones") as Array)[0] as Dictionary).get("brief")
			if brief != null:
				return String(brief.get("kind"))
	return name.get_slice("_", 0)


## The player onto the zone's own spawn marker, and the camera with them.
func _land() -> void:
	if _zone == null or _player == null:
		return
	var spawn: Node3D = _zone.get_node_or_null("SpawnA")
	if spawn == null:
		push_warning("[CityWalk] the world left no SpawnA")
		return
	_player.global_position = spawn.global_position + Vector3(0.0, 0.5, 0.0)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	var rig := get_node_or_null("CameraRig")
	if rig != null and rig.has_method("snap_to_target"):
		rig.call("snap_to_target")
	print("[CityWalk] landed at %s" % str(_player.global_position))
	if _wide:
		# the whole site from above: mountains, lake and town in one frame. The game's camera is
		# a 15 m diorama and would show two houses.
		var map: Resource = _zone.get("map")
		var b: Rect2 = map.bounds if map != null else Rect2(Vector2.ZERO, Vector2(200, 200))
		var reach: float = maxf(b.size.x, b.size.y) + 700.0
		var cam := Camera3D.new()
		cam.name = "WideCam"
		var at := Vector3(b.get_center().x, 0.0, b.get_center().y) + _zone.global_position
		cam.position = at + Vector3(0.0, reach * 0.62, reach * 0.62)
		cam.look_at_from_position(cam.position, at, Vector3.UP)
		cam.far = reach * 4.0
		add_child(cam)
		cam.make_current()


func _process(delta: float) -> void:
	if _shot != "" and _zone != null:
		# a few frames for the tiles to stand and the camera to settle, then one picture
		_frames += 1
		if _frames > 90:
			var img := get_viewport().get_texture().get_image()
			var abs := ProjectSettings.globalize_path(_shot) if _shot.begins_with("res://") else _shot
			DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
			print("[CityWalk] shot %s (%s)" % [_shot, error_string(img.save_png(abs))])
			get_tree().quit(0)
			return
	# FALLING IS A BUG, NOT A STATE: say what was missing and put the player back, rather than
	# let them drop for ever while the scene looks fine.
	if _player != null and _zone != null and _player.global_position.y < FLOOR_Y:
		_falls += 1
		push_warning("[CityWalk] the player fell out of the world (%d): nothing had collision under %s"
				% [_falls, str(_player.global_position.round())])
		_land()
	if not report or _zone == null:
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	if _player == null:
		return
	var focus: Node = _zone.get_node_or_null("Focus")
	if focus != null:
		print("[CityWalk] %d units standing, player %s" % [int(focus.call("standing")), str(_player.global_position.round())])
	else:
		# the world as nodes: nothing streams, so what there is to say is where the player is
		print("[CityWalk] player %s" % str(_player.global_position.round()))

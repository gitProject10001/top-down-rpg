extends Node
## Autoload "MapData" — THE MODEL. What has been discovered, and where the player's markers are.
## Owns no UI and knows nothing about drawing; MapScreen reads it. That split is what lets the
## interesting half (grid maths, serialisation) be hammered headless without a renderer.
##
## PAUSABLE ON PURPOSE. When the map screen freezes the tree this node stops, which is exactly
## right: nothing should be discovered while you are staring at the map. Inheriting the default is
## the whole implementation of that rule.

## Metres of travel between stamps. An order of magnitude below REVEAL_R, so consecutive discs
## overlap heavily and the revealed corridor is continuous — including through a dash, because the
## test is distance-since-last-stamp evaluated every physics frame rather than a timer. A dash that
## covers 8 m still lands five stamps.
const MOVE_STEP := 1.5

## Reveal radius, metres. Roughly what the fixed 53-degree camera shows you of the ground.
const REVEAL_R := 14.0

## THE VISTA — a second, much coarser discovery grid, because YOU SEE FURTHER THAN YOU WALK. The
## fine grid answers "where have I set foot", which is what the walkable plan and the hard fog edge
## need. On its own it makes the hub read as a sock floating in cloud: the hills, buildings and
## ground you looked at from thirty metres away are simply absent from the map.
##
## So a second pass records what was in VIEW. It only thins the fog rather than clearing it, and
## only the muted relief layer shows through — the surroundings as a hazy impression, with the
## walked ground still the only thing drawn sharply. 4 m cells over the hub is 59 x 37 = 2 KB.
const VISTA_CELL := 4.0
const VISTA_R := 55.0

const SAVE_PATH := "user://map_save.dat"
const SAVE_VERSION := 1

## TESTING SWITCH — false means every launch starts with the whole map unexplored.
##
## Deliberately one flag gating BOTH ends rather than commented-out calls: exploration you cannot
## reset is exploration you cannot test, and a half-disabled save (loading but not writing, or the
## reverse) is worse than either. Set this back to true to restore persistence; nothing else moves.
##
## Note it does not DELETE an existing user://map_save.dat, so turning persistence back on will
## resume from whatever was last written before the switch was thrown.
const PERSIST := false

## What a zone gets if it has no world collision at all to measure. Small on purpose: a wrong big
## rect is a map of nothing at a useless scale, a wrong small one is obviously wrong.
const FALLBACK_RECT := Rect2(-32, -32, 64, 64)


## One zone's discovered state. Everything here is either a MapGrid or built-in Variants, so the
## whole thing serialises through store_var without full_objects.
class ZoneMap:
	extends RefCounted
	var key := ""
	var grid: MapGrid                  ## where you have WALKED — fine, hard-edged
	var vista: MapGrid                 ## what you have SEEN — coarse, only thins the fog
	var markers: Array = []            ## [{p: Vector2, k: int, f: int, n: String}]
	var rooms_seen := {}               ## Vector3i -> 2 entered, 1 known through a door
	## Vector3i -> Array[PackedVector2Array]: each room's REAL floor outline in dungeon-local XZ,
	## measured off the built tiles rather than assumed from the layout's cell block. Runtime only —
	## it belongs to one generated dungeon and is worthless the moment the seed changes.
	var room_outlines := {}
	var dungeon_seed := 0
	var is_dungeon := false
	## Flat top-down capture of the zone's geometry (MapRelief). RUNTIME ONLY — never saved: it is
	## several MB, it is derivable in four frames, and a stale one would draw a level that has since
	## been edited.
	var relief: Texture2D = null


var zones := {}                        ## key String -> ZoneMap
var current: ZoneMap = null
var zone_node: Node3D = null           ## the live node `current` describes

var _last_stamp := Vector2.INF
var _watched_id := 0
var _save_pending := false


func _ready() -> void:
	_load()
	# A hint, not the source of truth: the hub is instanced statically in main.tscn, so this never
	# fires at boot and a signal-driven design would start with no zone at all. The poll in
	# _physics_process is what actually tracks the zone; this just flushes the save on the way out.
	EventBus.zone_changed.connect(_on_zone_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


func _physics_process(_delta: float) -> void:
	# Resolve group "zone", never "zone_outgoing" — a seamless crossing keeps BOTH alive and the
	# outgoing one is explicitly moved to the other group (world_manager.gd:138).
	var z := get_tree().get_first_node_in_group("zone") as Node3D
	if z == null:
		return
	if z.get_instance_id() != _watched_id:
		_bind_zone(z)
	if current == null or current.grid == null:
		return
	# A dungeon reveals itself a ROOM at a time, from the room triggers — see note_room_entered.
	# Radial stamping there fought the architecture: circular blobs swelling out of square rooms.
	if current.is_dungeon:
		return

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# ZONE-LOCAL, always. This one call is what makes the crypt's +500 offset and the hub's baked
	# 0.11-degree tilt both stop existing before any grid maths happens.
	var l := zone_node.to_local(player.global_position)
	var p := Vector2(l.x, l.z)
	if _last_stamp.is_finite() and p.distance_squared_to(_last_stamp) < MOVE_STEP * MOVE_STEP:
		return
	current.grid.stamp(p, REVEAL_R)
	if current.vista:
		current.vista.stamp(p, VISTA_R)
	_last_stamp = p


## Where the player is, in the current zone's local XZ. Null-safe; MapScreen calls it every redraw.
func player_local() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or zone_node == null or not is_instance_valid(zone_node):
		return Vector2.ZERO
	var l := zone_node.to_local(player.global_position)
	return Vector2(l.x, l.z)


## The player's heading in zone-local space. Deliberately NOT the camera's yaw: the map is always
## north-up (a rotating map makes marker placement unlearnable and makes the parchment swim), so the
## only thing that may turn is the chevron.
func player_heading() -> float:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or zone_node == null or not is_instance_valid(zone_node):
		return 0.0
	var fwd := zone_node.global_transform.basis.inverse() * (-player.global_transform.basis.z)
	return atan2(fwd.x, -fwd.z)


# --- THE DUNGEON -------------------------------------------------------------------------------


## Called by DungeonRoom the first time the player is genuinely inside it. `near` is that room's
## door-sharing neighbours, which become KNOWN but not entered — you can see there is a room through
## that door without having gone through it.
func note_room_entered(cell: Vector3i, near: Array) -> void:
	# NOT MERELY DEFENSIVE. A dungeon room's coordinates are dungeon-local — cells around the origin,
	# a few tens of metres across — and the hub's grid covers (-46, -45) to (188, 103). They overlap
	# almost exactly. So a room reported while the hub is still the bound zone does not fail, it
	# quietly stamps ten rooms' worth of rectangles into the middle of the overworld map and saves
	# them. Room discovery belongs to a dungeon ZoneMap or to nothing.
	if current == null or not current.is_dungeon:
		return
	current.rooms_seen[cell] = 2
	_reveal_room(cell, 255)
	for room in near:
		if room == null or not is_instance_valid(room):
			continue
		var c: Vector3i = room.get("cell")
		var known: bool = int(current.rooms_seen.get(c, 0)) >= 2
		if not current.rooms_seen.has(c):
			current.rooms_seen[c] = 1
			# A VEIL, not a reveal. Enough for the outline to show through the cloud, not enough to
			# read as somewhere you have been.
			_reveal_room(c, 132)
		_reveal_between(cell, c, 190 if known else 132)


## Open the fog over one room's footprint, taken from the layout so the opening lands exactly on
## the walls the plan draws.
func _reveal_room(cell: Vector3i, value: int) -> void:
	var lay := dungeon_layout()
	if lay == null or current == null or current.grid == null:
		return
	var rd: DungeonLayout.RoomData = lay.rooms.get(cell)
	if rd == null:
		return
	# The measured outline, so the hole in the fog is the shape of the room and not of its envelope.
	var shapes: Array = current.room_outlines.get(cell, [])
	if not shapes.is_empty():
		for shape: PackedVector2Array in shapes:
			current.grid.stamp_polygon(shape, value, 2.5)
		return
	var mid := DungeonLayout.room_origin(rd)
	var ext := DungeonLayout.size_of(rd)
	current.grid.stamp_rect(
			Rect2(mid.x - ext.x * 0.5, mid.z - ext.z * 0.5, ext.x, ext.z), value, 2.5)


## ...and over the passage joining two known rooms, so a corridor is not a drawn line under cloud.
##
## Deliberately a SMALL patch at the midpoint rather than the box spanning both centres: that box
## contains both rooms entirely, so it would have re-stamped an unentered neighbour at the
## corridor's brightness and undone the veil that makes "seen through a doorway" legible.
func _reveal_between(a: Vector3i, b: Vector3i, value: int) -> void:
	var lay := dungeon_layout()
	if lay == null or current == null or current.grid == null:
		return
	var ra: DungeonLayout.RoomData = lay.rooms.get(a)
	var rb: DungeonLayout.RoomData = lay.rooms.get(b)
	if ra == null or rb == null or ra.cell.y != rb.cell.y:
		return
	var pa := DungeonLayout.room_origin(ra)
	var pb := DungeonLayout.room_origin(rb)
	var mid := Vector2((pa.x + pb.x) * 0.5, (pa.z + pb.z) * 0.5)
	var half := DungeonLayout.GAP * 0.9
	current.grid.stamp_rect(Rect2(mid - Vector2(half, half), Vector2(half, half) * 2.0), value, 2.0)


## The live layout of the crypt, if that is the zone we are in. MapScreen draws straight from it.
func dungeon_layout() -> DungeonLayout:
	if zone_node == null or not is_instance_valid(zone_node) or not zone_node.is_in_group("dungeon"):
		return null
	return zone_node.get("layout") as DungeonLayout


## Which floor the player is standing on, for the dungeon map's default view.
func player_floor() -> int:
	var lay := dungeon_layout()
	if lay == null:
		return 0
	var p := player_local()
	var best := 0
	var best_d := INF
	for anchor: Vector3i in lay.rooms:
		var rd: DungeonLayout.RoomData = lay.rooms[anchor]
		var mid := DungeonLayout.room_origin(rd)
		var d := Vector2(mid.x, mid.z).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = rd.cell.y
	return best


# --- MARKERS -----------------------------------------------------------------------------------

enum Marker { PIN, CHEST, DANGER, DOOR, SECRET, HOME }

## Bounded so both the save file and the _draw() loop stay bounded. If somebody genuinely needs
## more than 32 pins in one zone, the zone is the problem.
const MARKER_CAP := 32


func add_marker(kind: int, at: Vector2, floor_index := 0, label := "") -> bool:
	if current == null or current.markers.size() >= MARKER_CAP:
		return false
	current.markers.append({"p": at, "k": kind, "f": floor_index, "n": label})
	return true


## Returns the removed marker, or an empty Dictionary. Nearest-within-radius rather than
## first-within-radius, so overlapping pins delete in the order you would expect.
func remove_marker_near(at: Vector2, radius: float) -> Dictionary:
	if current == null:
		return {}
	var best := -1
	var best_d := radius * radius
	for i in current.markers.size():
		var d: float = (current.markers[i]["p"] as Vector2).distance_squared_to(at)
		if d <= best_d:
			best_d = d
			best = i
	if best < 0:
		return {}
	var gone: Dictionary = current.markers[best]
	current.markers.remove_at(best)
	return gone


func markers() -> Array:
	return current.markers if current else []


# --- ZONE BINDING ------------------------------------------------------------------------------


func _bind_zone(z: Node3D) -> void:
	if _save_pending:
		save()
	zone_node = z
	_watched_id = z.get_instance_id()
	_last_stamp = Vector2.INF

	# scene_file_path, not name: names are renameable and instanced names pick up suffixes, and this
	# string is the key a save file is written under.
	var key := z.scene_file_path
	if key == "":
		key = z.name
	var is_dungeon := z.is_in_group("dungeon")
	var lay: DungeonLayout = z.get("layout") as DungeonLayout if is_dungeon else null

	var zm: ZoneMap = zones.get(key)
	if zm == null:
		zm = ZoneMap.new()
		zm.key = key
		zones[key] = zm
	zm.is_dungeon = is_dungeon

	# A NEW CRYPT IS A NEW MAP. dungeon_seed defaults to 0, which DungeonLayout reads as "random
	# every entry" — so a retained crypt map would describe rooms that no longer exist. Keying on
	# the seed means the reset is automatic, and means that the day somebody pins a seed the map
	# persists across entries with no further code.
	if is_dungeon and lay != null and zm.dungeon_seed != lay.seed_used:
		zm.dungeon_seed = lay.seed_used
		zm.rooms_seen.clear()
		zm.markers.clear()
		zm.room_outlines.clear()
		zm.grid = null
		zm.vista = null

	var bounds := _bounds_for(z)
	var cell := 2.0 if is_dungeon else MapGrid.DEFAULT_CELL
	if zm.grid == null or not zm.grid.matches(bounds, cell):
		zm.grid = MapGrid.make(bounds, cell)
	# NO VISTA IN A DUNGEON, and this is a design rule rather than an optimisation: a 55 m sight
	# radius underground would thin the fog over rooms two doors away and hand you the layout you
	# are supposed to be discovering. The crypt reveals itself strictly a room at a time.
	if is_dungeon:
		zm.vista = null
	elif zm.vista == null or not zm.vista.matches(bounds, VISTA_CELL):
		zm.vista = MapGrid.make(bounds, VISTA_CELL)
	current = zm
	_save_pending = true

	# Fire and forget: the map is perfectly usable without it (the ink plan is the map), so nothing
	# waits on this. Captured on ENTRY rather than on open, so it is ready before the player can ask.
	#
	# NEVER UNDERGROUND. Not an optimisation — the relief is multiplied by the vista, and a dungeon
	# has no vista, so the capture could only ever produce a texture nothing samples. Meanwhile it
	# costs an extra render of the whole world and briefly touches scenery visibility inside a zone
	# that is in the middle of managing exactly that. Free to skip, and one less thing to get wrong.
	if zm.relief == null and not is_dungeon:
		_capture_relief(z, zm, zm.grid.rect)
	if is_dungeon and zm.room_outlines.is_empty():
		_measure_rooms(z, zm)


## Measure every room's real floor outline, once, right after the dungeon is generated.
##
## Now rather than lazily on first entry: it runs inside the same portal fade the generator and the
## GI prime already spend time behind (dungeon_generator.gd:148), the whole crypt is ~11 rooms of
## ~15 tiles, and doing it up front means the map never stalls on the frame somebody opens it.
func _measure_rooms(z: Node3D, zm: ZoneMap) -> void:
	for child in z.get_children():
		if child is DungeonRoom:
			var outline := MapPainter.room_outline(child as Node3D, z)
			if not outline.is_empty():
				zm.room_outlines[(child as DungeonRoom).cell] = outline


func _capture_relief(z: Node3D, zm: ZoneMap, rect: Rect2) -> void:
	var tex: Texture2D = await MapRelief.capture(self, z, rect)
	# The player may have left the zone during the capture; binding the texture to the ZoneMap it
	# was taken from rather than to `current` keeps it with the right zone either way.
	if tex != null and is_instance_valid(zm):
		zm.relief = tex


## Measured from the level's own collision every time, never configured. No zone has to declare
## anything, nothing goes stale when the hub is edited, and a GladeKit-generated zone nobody has
## hand-measured maps correctly the first time it is walked into.
func _bounds_for(z: Node3D) -> Rect2:
	var derived := MapPainter.derive_rect(z)
	return derived if derived.size != Vector2.ZERO else FALLBACK_RECT


func _on_zone_changed(_zone_name: String) -> void:
	# Behind World.go_to's 0.3 s fade, so a ~30 KB synchronous write costs nothing visible.
	save()


# --- PERSISTENCE -------------------------------------------------------------------------------
#
# The project's first save file, and deliberately single-purpose rather than a general save system.
#
# store_var over ConfigFile because the payload is a PackedByteArray per zone, which ConfigFile
# would base64 into something slow and unreadable for no gain. store_var over ResourceSaver because
# a Resource save embeds the path of the script that wrote it, so moving or renaming this file would
# break every existing save — crypt_tuner.gd made the same call for the same reason.
#
# full_objects = false is not a detail. A save file is untrusted input, and full_objects = true on a
# tampered one is arbitrary object instantiation. Storing nothing but Dictionary / Array /
# PackedByteArray / Vector2 / int / float / String closes that off structurally — which is also why
# markers are Dictionaries and not a class.


func save() -> void:
	if not PERSIST:
		_save_pending = false
		return
	var out := {"v": SAVE_VERSION, "zones": {}}
	for key: String in zones:
		var zm: ZoneMap = zones[key]
		# A crypt map is a current-run map; persisting it would restore rooms of a layout the next
		# entry will not generate.
		if zm.is_dungeon or zm.grid == null:
			continue
		var d := zm.grid.to_dict()
		d["markers"] = zm.markers.duplicate(true)
		if zm.vista:
			d["vista"] = zm.vista.to_dict()
		out["zones"][key] = d
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("MapData: cannot write %s (%d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	f.store_var(out, false)
	f.close()
	_save_pending = false


func _load() -> void:
	if not PERSIST:
		return
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: Variant = f.get_var(false)
	f.close()
	# Every failure below falls through to "no saved map", never to a broken boot.
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("MapData: save file is not a dictionary — ignored")
		return
	var d := raw as Dictionary
	if d.get("v") != SAVE_VERSION:
		push_warning("MapData: save version %s != %d — starting fresh" % [d.get("v"), SAVE_VERSION])
		return
	if typeof(d.get("zones")) != TYPE_DICTIONARY:
		return
	for key: Variant in (d["zones"] as Dictionary):
		if typeof(key) != TYPE_STRING:
			continue
		var entry: Variant = (d["zones"] as Dictionary)[key]
		var grid := MapGrid.from_dict(entry)
		if grid == null:
			continue                      # mismatched or corrupt: that zone is simply unexplored
		var zm := ZoneMap.new()
		zm.key = key
		zm.grid = grid
		# Independently validated: a vista that fails to load costs a hazy backdrop, not the map.
		zm.vista = MapGrid.from_dict((entry as Dictionary).get("vista"))
		zm.markers = MapGrid.clean_markers((entry as Dictionary).get("markers"), MARKER_CAP)
		zones[key] = zm

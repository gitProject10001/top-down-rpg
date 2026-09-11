extends Node3D
## A ROOM OF A GENERATED CRYPT, and the run that is played through it: enemies the first time
## the player walks in, a boss at the end of the crypt, and the way home once it is dead.
##
## WHY NOT `DungeonRoom`. The crypt the hand-built generator makes runs the full Isaac beat —
## first entry SHUTS the doors, killing everything opens them, only the room you are in is lit.
## That wants a room to own its doors as `DungeonDoor` nodes and its own lights, and a
## floorplan-baked room owns neither: its doorways are holes cut through rock with nothing to
## hang a leaf on. So this keeps the half that needs nothing — the fight, the clear, and the
## boss that ends the run — and leaves the doors open. `dungeon_room.gd` is where the other half
## already lives, and this deliberately borrows its shape so the two can converge later.
##
## SPAWNED ON ENTRY, NOT PLACED. An enemy's aggro reach is bigger than a small room, so enemies
## sitting in the level from the start wake through walls and walk at you down a corridor you
## have not opened yet. Waiting for the trigger is what keeps a room a room.
##
## THE LOOP. `world_props` has already put the furniture, the light and the set piece in this
## room at bake time; what is left at run time is who is in it. The entrance never fights and
## holds the NPC who says where you are. Every other room's pack gets harder the further from
## the entrance it is. The BOSS room holds one thing, it is on the "boss" group so the HUD gives
## it the boss bar, and killing it opens a portal back to the hub — which is what "finishing"
## the crypt means, the same way it means it in the hand-built one.

## What a room can be asked to hold, by the same names `dungeon_room.gd` uses.
const ENEMY_SCENES := {
	"melee": "res://scenes/enemy_swordsman.tscn",
	"archer": "res://scenes/enemy_archer.tscn",
	"brute": "res://scenes/enemy_brute.tscn",
}
## THE THING AT THE END. The four-metre ogre — the only enemy in the project built to be one
## fight rather than one of a pack: its own animation tree, measured damage windows, a poise bar
## and the HUD's singular boss bar (`hud.gd`, and `player_vs_pack` asserts that it is singular).
const BOSS_SCENE := "res://scenes/enemy_ogre2.tscn"
## Where killing it sends you: the hub, on the marker beside the arch you came in through.
const HOME_ZONE := "res://scenes/world/room.tscn"
const HOME_SPAWN := "SpawnFromCrypt"
const PORTAL_SCENE := "res://scenes/props/portal.tscn"
## Who is standing in the entrance.
const NPC_SCENE := "res://scenes/npc.tscn"

## `RoomPlan`'s own yardstick: the area of a one-cell room, which every count is scaled against.
const BASE_AREA := 240.0
## `DungeonLayout.RoomType`.
const START := 0
const BOSS := 2
const TREASURE := 3
## START and TREASURE rooms get no fight — the first is a threshold and the second is a reward.
const PEACEFUL := [START, TREASURE]

## How many doors from the entrance this room is: the pressure dial.
@export var dist := 0
## Its mission role, `DungeonLayout.RoomType`.
@export var type := 1
## The room's floor area, m² — the other dial.
@export var area_m2 := BASE_AREA
## The box the trigger fills, metres. Inset from the walls so entering means genuinely inside.
@export var footprint := Vector3(20.0, 3.0, 12.0)
## Off for a room that should never fight whatever its type says.
@export var fights := true

var _spawned := false
var _alive: Array[Node] = []
var _cleared := false


func _ready() -> void:
	if type == START:
		_greeter()
	if not fights or PEACEFUL.has(type):
		return
	var trigger := Area3D.new()
	trigger.name = "RoomTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 1                # the player's CharacterBody3D is on layer 1
	trigger.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(footprint.x - 3.0, 2.0), 3.0, maxf(footprint.z - 3.0, 2.0))
	shape.shape = box
	shape.position.y = 1.5
	trigger.add_child(shape)
	trigger.body_entered.connect(_on_body_entered)
	add_child(trigger)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.enemy_died.connect(_on_enemy_died)


func _on_body_entered(body: Node3D) -> void:
	if _spawned or not body.is_in_group("player"):
		return
	_spawned = true
	if type == BOSS:
		_spawn_boss()
		return
	for at: Vector3 in _places(_count()):
		_spawn(ENEMY_SCENES.get(_kind(), ""), at)


## THE FIGHT THAT ENDS THE CRYPT. One ogre in the middle of the room, on the boss group, plus a
## thin escort — two swordsmen, so the arena is not a duel in an empty hall and the player has
## something to punish while the boss recovers. `is_boss` is what puts the bar on the HUD, and
## `enemy.gd` reads it in `_ready`, so it has to be set BEFORE the scene enters the tree.
func _spawn_boss() -> void:
	# IN FRONT OF THE THRONE, not on it. `world_props` puts a dais and a throne at the middle of a
	# boss room at bake time, and spawning the ogre on the same point drops a four-metre capsule
	# inside a solid one.
	var boss := _spawn(BOSS_SCENE, Vector3(0.0, 0.5, footprint.z * 0.18), func(e: Node) -> void:
			e.set("is_boss", true))
	if boss == null:                          # no ogre in this build: a hard pack rather than none
		for at: Vector3 in _places(4):
			_spawn(ENEMY_SCENES.brute, at)
		return
	for at: Vector3 in _places(2):
		_spawn(ENEMY_SCENES.melee, at)


func _spawn(path: String, at: Vector3, tweak := Callable()) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var e: Node3D = (load(path) as PackedScene).instantiate()
	if tweak.is_valid():
		tweak.call(e)
	add_child(e)
	e.global_position = global_position + at
	_alive.append(e)
	return e


## The room is CLEARED when the last thing it spawned is gone. Only the boss room does anything
## with that today — the doors are already open everywhere else — and what it does is put the way
## home in the room you finished the crypt in.
func _on_enemy_died(enemy: Node) -> void:
	if _cleared or not _spawned:
		return
	_alive = _alive.filter(func(e: Node) -> bool: return is_instance_valid(e) and e != enemy)
	if not _alive.is_empty():
		return
	_cleared = true
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.combat_impact.emit(0.3)           # the room-clear sting, as the hand-built crypt does
	if type == BOSS:
		_way_home()


## THE END OF THE RUN. A portal in the boss room back to the hub — the same one
## `DungeonRoom._spawn_victory_portal` opens, targeting the same marker, so finishing the
## generated crypt and finishing the hand-built one land the player in the same place.
func _way_home() -> void:
	if not ResourceLoader.exists(PORTAL_SCENE):
		return
	var portal: Node3D = (load(PORTAL_SCENE) as PackedScene).instantiate()
	portal.set("target_zone_path", HOME_ZONE)
	portal.set("target_spawn", HOME_SPAWN)
	add_child(portal)
	portal.position = Vector3(0.0, 0.0, -footprint.z * 0.5 + 3.0)
	print("[Crypt] the crypt is finished — the way out is open")


## WHO MEETS YOU AT THE DOOR. The entrance room is the one place in a generated crypt where
## something can be said out loud, and a dungeon that opens on a locked silence tells the player
## nothing about what it wants from them. The lines are this crypt's, not the garden Wisp's, so
## they are handed over as data — see `npc.gd`, whose `conversation` export exists for exactly
## this.
func _greeter() -> void:
	if not ResourceLoader.exists(NPC_SCENE):
		return
	var npc: Node3D = (load(NPC_SCENE) as PackedScene).instantiate()
	npc.name = "Keeper"
	npc.set("conversation", CRYPT_CONVO)
	add_child(npc)
	npc.position = Vector3(0.0, 0.0, footprint.z * 0.5 - 4.0)


const CRYPT_CONVO := {
	"start": {
		"speaker": "The Keeper",
		"text": "You came down the stair, then. Nobody comes down the stair.",
		"responses": [
			{"text": "What is this place?", "next": "place"},
			{"text": "What am I looking for?", "next": "goal"},
			{"text": "Nothing. (Leave)", "next": ""},
		],
	},
	"place": {
		"speaker": "The Keeper",
		"text": "Rock, mostly. The rooms were cut, not built — everything between them is solid, "
				+ "and the only way on is a doorway somebody troubled to open.",
		"responses": [
			{"text": "And the light?", "next": "light"},
			{"text": "So what am I looking for?", "next": "goal"},
		],
	},
	"light": {
		"speaker": "The Keeper",
		"text": "The braziers are all there is. Past their reach it is not dark — it is nothing. "
				+ "Do not go looking for a wall out there; there isn't one.",
		"next": "goal",
	},
	"goal": {
		"speaker": "The Keeper",
		"text": "Deep in, something large keeps the last room. Kill it and the way out opens "
				+ "where it stood. That is the whole arrangement.",
		"responses": [
			{"text": "How large?", "next": "large"},
			{"text": "Then I'll be quick.", "next": "quick"},
		],
	},
	"large": {
		"speaker": "The Keeper",
		"text": "Twice your height and it does not hurry. It has nowhere to be — you do.",
		"next": "",
	},
	"quick": {
		"speaker": "The Keeper",
		"text": "They all say quick. Come back up the stair and I'll believe it.",
		"next": "",
	},
}


## HOW MANY. Depth sets the pressure and area scales it, which is the crypt's own rule: a hall
## of four times the floor holds twice the fight, not four times it.
func _count() -> int:
	var base := clampi(1 + dist / 2, 1, 4)
	return clampi(int(round(float(base) * sqrt(maxf(area_m2, 1.0) / BASE_AREA))), 1, 8)


## WHAT. Archers appear once there is somewhere to shoot from, brutes deeper still, and the
## roll is keyed to WHERE the room is rather than to when it was entered.
func _kind() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d" % [name, dist, _alive.size()])
	var roll := rng.randf()
	if dist >= 3 and roll < 0.2:
		return "brute"
	if dist >= 1 and roll < 0.5:
		return "archer"
	return "melee"


## WHERE. A ring inside the room, well clear of the walls and of the middle the player walks in
## on, jittered so a fight never reads as a formation.
func _places(n: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|places" % name)
	var reach := minf(footprint.x, footprint.z) * 0.3
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		var r := reach * rng.randf_range(0.7, 1.0)
		out.append(Vector3(cos(a) * r, 0.5, sin(a) * r))
	return out

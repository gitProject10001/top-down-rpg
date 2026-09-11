class_name DungeonRoom
extends Node3D
## One live dungeon room: knows its doors, its enemy spawn list, and its state. The Isaac beat:
## first entry SHUTS the doors and spawns the enemies; killing them all opens every door of the
## room and it stays cleared forever. The room's own trigger claims the camera frame (and a
## follow clamp) on entry — no separate camera_zone needed.
##
## Enemies SPAWN ON ACTIVATION (not pre-placed): their aggro range (10m) is bigger than a room,
## so pre-placed ones would wake through walls — and the doors-slam-then-spawn moment IS the feel.

## The fight in this room is over. Emitted once, from _clear().
##
## A SIGNAL RATHER THAN A CALL, because what happens on a clear is not this room's business — the
## crypt wants nothing, and the vertical slice wants a pedestal to rise. Routing it through a signal
## keeps the base crypt's behaviour identical whether or not anything is listening, which is the
## same reason DungeonGenerator._furnish is a hook.
signal cleared

enum State { UNVISITED, ACTIVE, CLEARED }

const ENEMY_SCENES := {
	"melee": "res://scenes/enemy_swordsman.tscn",   # the humanoid swordsman (player1's model+clips)
	"archer": "res://scenes/enemy_archer.tscn",
	"brute": "res://scenes/enemy_brute.tscn",
	# The nest counts as THE enemy for room-clear purposes: it goes in _alive, its swarmlings do
	# not (they are children of the room, not of this spawn list, so _on_enemy_died ignores them).
	# So killing the nest opens the doors even if a few swarmlings are still chasing you out —
	# which is the read we want: destroy the source, then leave or mop up as you please.
	"swarm": "res://scenes/props/swarm_spawner.tscn",
}

## THE PINNED CAMERA FRAME. This room has always claimed the frame at yaw 0; naming it makes the
## diorama cutaway DERIVABLE (RoomDresser.cutaway_out) instead of guessed, and turns "the camera
## un-pinned" into a one-line change the dresser notices rather than a silent art bug.
## A light carrying this meta is NOT the room's to dim. The player's torch is the only one today,
## and it currently escapes only because the player happens not to be parented under a DungeonRoom
## — an accident of scene layout, not a decision. Reparenting the player into the room they stand
## in is a reasonable thing to want, and it would gutter their own torch to 6%.
const IGNORE_ROOM_DIM := "ignore_room_dim"

const FRAME_YAW := 0.0
## CameraRig's authored angle, atan2(12.5, 9.375) — see camera_rig.gd. The occlusion arithmetic the
## cutaway rests on is tan(this) = 4/3, asserted in verify_dungeon._cutaway_suite.
const FRAME_PITCH := 0.9272952

## This room's layout anchor, set by the generator. The map keys discovery on it, and it is the one
## piece of DungeonLayout identity a live room otherwise throws away.
var cell := Vector3i.ZERO
## The layout row this room was built from — type, purpose, edges, whether it holds the key. `cell`
## alone forces every consumer to carry the whole DungeonLayout around to ask what a room IS.
var data: DungeonLayout.RoomData
## The occupancy grid this room was planned against, kept so anything added later can ask the room
## itself where there is floor. See the comment at the assignment in dungeon_generator.gd.
var plan: RoomContext
var doors: Array = []                  ## DungeonDoor refs (shared with neighbour rooms)
var spawn_defs: Array = []             ## [{kind: String, pos: Vector3 local}]
var room_zoom := 1.7
var is_boss := false
## Interior extent — per room now that halls and closets exist, not a global constant.
var footprint := DungeonLayout.ROOM_SIZE
## A stairwell is entered at the bottom and left at the top, so its trigger has to span the climb
## or the room stops being "current" (and goes dark) halfway up.
## HEAD_ROOM, not wall height — the two only looked like the same number while the wall was 3 m.
var trigger_height := DungeonLayout.HEAD_ROOM
var state := State.UNVISITED

var _alive: Array = []
var _rig: Node3D
var _lights: Array = []                ## the room's OmniLights (torches, altar...)
var _flames: Array = []                ## emissive torch-flame meshes (meta "torch_flame")
var _light_energy: Dictionary = {}     ## light -> its authored full energy
var _light_shadow: Dictionary = {}     ## light -> whether it was AUTHORED to cast (see set_lit)
var _flame_energy: Dictionary = {}     ## flame mesh -> its authored full emission energy
var _lit := true
var _near: Array = []                  ## door-sharing neighbours, computed once (see show_around)


func _ready() -> void:
	var trigger := Area3D.new()
	trigger.name = "RoomTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 1               # the player's CharacterBody3D lives on layer 1
	trigger.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# inset from the walls so activation only fires once you're genuinely inside, past the door
	box.size = Vector3(footprint.x - 3.0, trigger_height, footprint.z - 3.0)
	shape.shape = box
	shape.position.y = trigger_height * 0.5
	trigger.add_child(shape)
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)
	add_child(trigger)
	# defensive lookup: the headless test suite instantiates rooms without game autoloads
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.enemy_died.connect(_on_enemy_died)


func _on_body_entered(body: Node3D) -> void:
	# group check, not `is Player`: keeps this script compiling without the game's autoloads
	if not body.is_in_group("player"):
		return
	_rig = get_tree().get_first_node_in_group("camera_rig") as Node3D
	if _rig:
		_rig.claim_frame(self, room_zoom, FRAME_YAW)
		_rig.set_follow_bounds(self, global_position,
				Vector2(maxf(footprint.x * 0.5 - 4.0, 1.0), maxf(footprint.z * 0.5 - 1.0, 1.0)))
	# only the CURRENT room is lit — everything outside falls dark (its torches gutter out)
	for sib in get_parent().get_children():
		if sib is DungeonRoom:
			sib.set_lit(sib == self)
	show_around()
	# The map learns the dungeon the same way the lights do — from the trigger that already means
	# "genuinely inside, past the door". Reverse-mapping the player's position to a cell would be a
	# different question: the trigger is INSET from the walls (see _ready), deliberately.
	#
	# get_node_or_null, not MapData directly: the headless suite instantiates rooms with no game
	# autoloads registered (see the header of dungeon_generator.gd).
	var map_data := get_node_or_null("/root/MapData")
	if map_data:
		map_data.note_room_entered(cell, neighbours())
	if state == State.UNVISITED:
		_activate()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and _rig:
		_rig.release_frame(self)


func _activate() -> void:
	state = State.ACTIVE
	for d in doors:
		if is_instance_valid(d):
			d.shut()
	for def in spawn_defs:
		var scene := load(ENEMY_SCENES[def.kind]) as PackedScene
		if scene == null:
			continue
		var e := scene.instantiate()
		add_child(e)                                     # child of the room: dies with the zone
		(e as Node3D).global_position = global_position + (def.pos as Vector3)
		_alive.append(e)
		e.tree_exited.connect(_on_enemy_gone.bind(e))    # fallback: freed without dying signal
	if _alive.is_empty():
		_clear()


func _on_enemy_died(enemy: Node) -> void:
	if enemy in _alive:
		_alive.erase(enemy)
		_check_clear()


func _on_enemy_gone(enemy: Node) -> void:
	if not is_inside_tree():
		return                                           # zone being freed — not a room clear
	if enemy in _alive:
		_alive.erase(enemy)
		_check_clear()


func _check_clear() -> void:
	if state == State.ACTIVE and _alive.is_empty():
		_clear()


func _clear() -> void:
	state = State.CLEARED
	for d in doors:
		if is_instance_valid(d):
			d.open()
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.combat_impact.emit(0.3)                      # the room-clear sting
	cleared.emit()
	if is_boss:
		_spawn_victory_portal()


## Light or darken this room: torch omnis fade to (almost) nothing and the flame meshes stop
## glowing when the player is elsewhere — outside the current room the crypt falls dark.
func set_lit(on: bool, animate := true) -> void:
	if _lights.is_empty() and _flames.is_empty():
		_collect_lights(self)
	if _lit == on:
		return
	_lit = on
	var t := create_tween().set_parallel(true) if animate else null
	for l in _lights:
		if not is_instance_valid(l):
			continue
		var target: float = _light_energy.get(l, 1.5) * (1.0 if on else 0.06)
		if t:
			t.tween_property(l, "light_energy", target, 0.5)
		else:
			l.light_energy = target
		# SHADOWS FOLLOW THE ROOM, not just brightness. Dimming an OmniLight to 6% does not stop it
		# rendering its shadow cubemap, so every room's fill light would keep paying for six faces
		# of shadow map while contributing nothing visible. Only lights that ASKED for shadows get
		# them back — this must not switch them on for the shadowless sconces.
		#
		# THE TIMING IS NOT SYMMETRIC, and the old code getting that wrong was invisible only
		# because exactly one light in the crypt cast anything. Energy fades over half a second;
		# shadows used to flip instantly. Leaving a room that meant the shadows went off FIRST, so
		# for 0.5 s a near-full-energy light poured through the walls unoccluded — the one thing
		# SDFGI containment cannot fix, because a direct light ignores it. So: ON leads the fade,
		# OFF trails it, and both edges are covered by geometry the player can see.
		if _light_shadow.get(l, false):
			if on:
				l.shadow_enabled = true
			elif t:
				# _lit is re-checked at fire time: walking room→corridor→back inside half a second
				# would otherwise land this callback after the room has re-lit and kill its shadows
				# until the next transition.
				t.tween_callback(func() -> void:
					if is_instance_valid(l) and not _lit:
						l.shadow_enabled = false
				).set_delay(0.5)
			else:
				l.shadow_enabled = false
	for f in _flames:
		if not is_instance_valid(f):
			continue
		var mat := _flame_material(f)
		if mat != null:
			# restore the energy the THEME authored, not a hardcoded crypt value
			var target_e: float = _flame_energy.get(f, 2.2) if on else 0.08
			if t:
				t.tween_property(mat, "emission_energy_multiplier", target_e, 0.5)
			else:
				mat.emission_energy_multiplier = target_e


## Show this room and the rooms one door away; hide the rest of the crypt. Call it on whichever
## room the player is standing in.
##
## THE CHEAPEST LEVER IN THE RENDERER, and the only one that helps every later pass at once. A
## hidden Node3D subtree stops being draw calls, stops being SHADOW CASTERS, stops being voxelised
## for GI and stops being fog sources. Occlusion culling — the obvious answer — does none of that
## except the first: it filters the camera pass only, so it cannot pay for a single shadow map.
## (It also could not be made sound here. CourseVeil hides courses per frame and cutaway_out
## deletes the camera-facing ones, so any occluder tall enough to be worth building would occlude
## through holes that genuinely exist.)
##
## VISIBLE IS A WIDER SET THAN LIT, deliberately. Only the current room is lit, but GAP is 4 m and
## the camera looks down the passage through an open door, so the room next door has to be drawn —
## dark, at 6% — or doorways become black cutouts.
##
## ADJACENCY IS BY SHARED DOOR, NOT BY DISTANCE. The generator appends the same DungeonDoor object
## to both rooms it joins, so identity on that array IS the dungeon graph. Distance would get a
## stairwell wrong (its neighbour is 8 m above it) and would just as happily "connect" two rooms
## that share a wall and no way through.
func show_around() -> void:
	var near := _neighbours()
	for sib in get_parent().get_children():
		if sib is DungeonRoom:
			var room := sib as DungeonRoom
			room.visible = room == self or near.has(room) or room._has_live_enemy()


## The rooms one door from this one. Public because RoomGI needs the same set show_around() uses —
## what is visible and what is worth baking are the same question.
func neighbours() -> Array:
	return _neighbours()


func _neighbours() -> Array:
	if not _near.is_empty() or doors.is_empty():
		return _near
	for sib in get_parent().get_children():
		if sib is DungeonRoom and sib != self:
			for d in (sib as DungeonRoom).doors:
				if d in doors:
					_near.append(sib)
					break
	return _near


## Swarmlings are the exception that stops this being a two-line function. They are parented to the
## ROOM rather than to the nest's spawn list (so they die with the zone, and so killing the nest
## alone clears the room), which means a cleared room can still own three live swarmlings chasing
## the player through the door. Hiding their parent would make them invisible mid-attack while they
## carried on hitting. Shallow scan, once per room per transition — not per frame.
func _has_live_enemy() -> bool:
	for c in get_children():
		if c.is_in_group("enemy"):
			return true
	return false


## The emissive material of a flame mesh. Goes through surface_get_material, NOT `mesh.material`:
## that property only exists on PrimitiveMesh, so a themed flame authored as imported geometry
## (an ArrayMesh) would throw instead of glowing.
static func _flame_material(mi: MeshInstance3D) -> StandardMaterial3D:
	if mi.mesh == null:
		return null
	for si in mi.mesh.get_surface_count():
		var m = mi.get_active_material(si)
		if m is StandardMaterial3D:
			return m
	return null


## EXCLUDING DIRECTIONAL IS NOT PEDANTRY. Everything the room does to its lights is scaled by 6%,
## and a DirectionalLight3D parented into a room — a shaft from a grate, say — is the SUN as far as
## the engine is concerned. Dimming it would dim the whole world from inside one room, and putting
## it back would depend on the player leaving by the door they came in.
func _collect_lights(node: Node) -> void:
	for c in node.get_children():
		if c is Light3D and not (c is DirectionalLight3D) and not c.has_meta(IGNORE_ROOM_DIM):
			var l := c as Light3D
			_lights.append(l)
			_light_energy[l] = l.light_energy
			_light_shadow[l] = l.shadow_enabled
		elif c is MeshInstance3D and c.has_meta("torch_flame"):
			_flames.append(c)
			var m := _flame_material(c as MeshInstance3D)
			if m != null:
				_flame_energy[c] = m.emission_energy_multiplier
		_collect_lights(c)


## Beating the boss reveals the way home (same portal prop the garden uses).
func _spawn_victory_portal() -> void:
	var portal := (load("res://scenes/props/portal.tscn") as PackedScene).instantiate()
	portal.target_zone_path = "res://scenes/world/room.tscn"
	portal.target_spawn = "SpawnFromCrypt"
	add_child(portal)
	(portal as Node3D).position = Vector3(0, 0, -footprint.z * 0.5 + 2.0)

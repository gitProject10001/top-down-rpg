@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomBuilder
extends Object
## Builds ONE room, in two clearly separated halves:
##
##   RoomPlan  (gameplay) -> abstract tagged slots + enemy spawn intents, in the RoomContext
##   RoomDresser (style)  -> those slots become real nodes, via the DungeonTheme
##
## This file is the seam. It owns the one thing that legitimately touches both sides: reading a
## handcrafted TEMPLATE, which is a marker-only scene — gameplay data that happens to be stored
## as a .tscn.
##
## The SHELL (floor, walls, doorway pieces, wall mounts) is ALWAYS planned from scratch, so any
## template fits any door combination. Templates author interiors only.
##
## Template contract (scenes/dungeon/rooms/room_*.tscn): root Node3D at room centre; children are
## name-prefixed Marker3Ds.
##   PropPillar* / PropCrate* / PropAltar* / PropTorch*      -> the matching abstract slot
##   Slot_<tag>*                                             -> that tag directly (any tag)
##   SpawnMelee* / SpawnArcher* / SpawnBrute* / SpawnAny* / SpawnSwarm*  -> enemy spawn points
## Anything else in the template (real meshes, lights) is kept as-is. Interiors stay within
## +-9 x +-5 m and out of the door lanes (|x| >= 2 and |z| >= 2).

const SLOT_PREFIX := "Slot_"

## Legacy marker prefixes, kept so the existing templates keep working unchanged.
const PROP_TAGS := {
	"PropPillar": RoomPlan.T_COVER_LARGE,
	"PropCrate": RoomPlan.T_COVER_SMALL,
	"PropAltar": RoomPlan.T_FOCAL,
	"PropTorch": RoomPlan.T_WALL_ANCHOR,
}
const PROP_FOOTPRINTS := {
	RoomPlan.T_COVER_LARGE: RoomPlan.COVER_LARGE_SIZE,
	RoomPlan.T_COVER_SMALL: RoomPlan.COVER_SMALL_SIZE,
	RoomPlan.T_FOCAL: RoomPlan.FOCAL_SIZE,
}
const SPAWN_KINDS := {
	"SpawnMelee": "melee", "SpawnArcher": "archer", "SpawnBrute": "brute", "SpawnAny": "melee",
	"SpawnSwarm": "swarm",
}


## Plan the room, then dress it. Returns the enemy spawn defs for DungeonRoom to spawn on entry:
## Array of {kind: String, pos: Vector3 (room-local)}.
static func build(room: Node3D, rd: DungeonLayout.RoomData, ctx: RoomContext,
		theme: DungeonTheme = null) -> Array:
	RoomPlan.plan_shell(rd, ctx)
	if rd.template_path != "" and ResourceLoader.exists(rd.template_path):
		_ingest_template(room, rd, ctx)
		# THE KEY IS NOT PART OF THE INTERIOR, and putting it there made dungeons that cannot be
		# finished. `_plan_key` lives inside plan_interior, which this branch skips — so a COMBAT room
		# that both holds the key and wins the 50% template roll (dungeon_generator._assign_templates)
		# got its lock built and its key never placed. Rare enough that the lock suite's three sampled
		# seeds never hit it, permanent when it does: the gate on the way to the boss opens for nothing
		# that exists.
		#
		# AFTER the ingest, not before, so the template's own slots are already reserved and the key
		# lands beside them rather than inside an authored altar.
		RoomPlan._plan_key(rd, ctx)
	else:
		RoomPlan.plan_interior(rd, ctx)
	RoomDresser.build(room, ctx, theme)
	return ctx.spawn_defs


## Read a handcrafted interior: markers become slots and spawns, everything else is kept as
## authored. The markers themselves are dropped — RoomDresser puts the real pieces there.
static func _ingest_template(room: Node3D, rd: DungeonLayout.RoomData, ctx: RoomContext) -> void:
	var tpl: Node3D = (load(rd.template_path) as PackedScene).instantiate()
	room.add_child(tpl)
	for child in tpl.get_children().duplicate():
		var tag := _tag_of(str(child.name))
		if tag != "":
			ctx.add_slot_at(tag, (child as Node3D).position,
					PROP_FOOTPRINTS.get(tag, Vector2.ZERO))
			child.queue_free()
			continue
		var kind := _spawn_of(str(child.name))
		if kind != "":
			ctx.add_spawn(kind, (child as Node3D).position + Vector3(0, 1, 0))
			child.queue_free()
	# A template used as the boss room must still field a boss, however it was authored.
	if rd.type == DungeonLayout.RoomType.BOSS and not _has_kind(ctx.spawn_defs, "brute"):
		ctx.add_spawn("brute", Vector3(0, 1, -2))


static func _tag_of(node_name: String) -> String:
	if node_name.begins_with(SLOT_PREFIX):
		# Slot_cover_large3 -> cover_large: strip the prefix and any trailing digits Godot added.
		var rest := node_name.substr(SLOT_PREFIX.length())
		while rest.length() > 0 and rest[-1] >= "0" and rest[-1] <= "9":
			rest = rest.substr(0, rest.length() - 1)
		return rest if rest in RoomPlan.ALL_TAGS else ""
	for prefix: String in PROP_TAGS:
		if node_name.begins_with(prefix):
			return PROP_TAGS[prefix]
	return ""


static func _spawn_of(node_name: String) -> String:
	for prefix: String in SPAWN_KINDS:
		if node_name.begins_with(prefix):
			return SPAWN_KINDS[prefix]
	return ""


static func _has_kind(defs: Array, kind: String) -> bool:
	for d in defs:
		if d.kind == kind:
			return true
	return false

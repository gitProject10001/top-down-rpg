class_name InteriorView
extends Node
## INDOORS IS A DIFFERENT SHOT. When the player walks into a GladeKit building this takes the lid
## off the storey they are standing on, dims the world outside, and pulls the camera in.
##
## WHY NOT A TRIGGER VOLUME. `scripts/roof_fade.gd` does this for the hand-modelled zones with an
## Area3D somebody placed, which is right when a level is authored by hand. A GladeKit building
## already KNOWS its own footprint and its own storey heights — `junction_volumes()` and `storeys` —
## so an authored trigger here would be a second copy of facts the wall can answer, and it would go
## stale the moment anyone drags a wall. Nothing to place: build a house, walk into it.
##
## THE CUT IS A CEILING, NOT A HOLE. scripts/see_through.gd punches a cone around the player so they
## stay visible; that reveals the PLAYER. Standing next to a wall, a cone is mostly wall. This
## reveals the ROOM: inside the footprint and above the storey's ceiling is discarded outright, so
## the storey reads as a doll's house seen from above. The two compose — the cone still opens the
## near wall of the storey you are in.

## How far the camera pulls in while indoors. 1 = the rig's authored distance.
@export var interior_zoom := 0.72
## Sun and ambient multipliers for the world outside while indoors.
@export var dim_sun_factor := 0.35
@export var dim_ambient_factor := 0.55
@export var dim_time := 0.4
## Grown onto the footprint box so a wall exactly on the boundary is cut cleanly rather than
## z-fighting its own edge.
@export var plan_margin := 0.35
## What the cone opens to while indoors — a wall at arm's length needs a wider hole than a roof
## seen from across the garden.
@export var indoor_see_through := 2.6
@export var target_group := "player"

var _inside: GladeWall = null
var _rig: Node = null
var _see_through: Node = null


## Optional: the cone node to widen while indoors, and the rig to pull in. Both may be null.
func setup(see_through: Node, rig: Node) -> void:
	_see_through = see_through
	_rig = rig


func _exit_tree() -> void:
	_leave()


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group(target_group) as Node3D
	if player == null or not player.is_visible_in_tree():
		_leave()
		return
	var here := _building_at(player.global_position)
	if here == null:
		_leave()
		return
	if here != _inside:
		_leave()
		_enter(here)
	_publish(here, player.global_position)


## The GladeKit building whose footprint this point is inside, or null. Asks each wall's own claim
## volume, which is the same shape the junction system reasons about — so "inside" here means
## exactly what it means everywhere else in the kit.
func _building_at(p: Vector3) -> GladeWall:
	for n in get_tree().get_nodes_in_group(GladeJunction.GROUP):
		var w := n as GladeWall
		if w == null or w.curve == null:
			continue
		for v: GladeVolume in w.junction_volumes():
			if v.contains(p):
				return w
	return null


## The ceiling of the storey this height falls in, in world Y. Read off the wall's `storeys`, which
## is the author's own intent — no second table to keep in sync. A wall with no storeys is one
## room of `wall_height`.
func _ceiling_for(w: GladeWall, world_y: float) -> float:
	var base := w.global_position.y
	var local := world_y - base
	var y := 0.0
	for s in w.storeys:
		if s == null:
			continue
		var top: float = y + s.height
		if local < top:
			return base + top
		y = top
	if y > 0.0:
		return base + y                        # above the top storey: keep the whole building open
	return base + w.total_height()


func _publish(w: GladeWall, player_pos: Vector3) -> void:
	var vols := w.junction_volumes()
	if vols.is_empty():
		return
	var box: AABB = (vols[0] as GladeVolume).aabb()
	var ceiling := _ceiling_for(w, player_pos.y)
	var c := box.get_center()
	RenderingServer.global_shader_parameter_set("interior_center",
			Vector3(c.x, ceiling, c.z))
	RenderingServer.global_shader_parameter_set("interior_half",
			Vector3(box.size.x * 0.5 + plan_margin, 0.0, box.size.z * 0.5 + plan_margin))
	RenderingServer.global_shader_parameter_set("interior_active", 1.0)


func _enter(w: GladeWall) -> void:
	_inside = w
	RoofFade.hold_dim(get_tree(), +1, dim_sun_factor, dim_ambient_factor, dim_time)
	if _rig != null and _rig.has_method("claim_frame"):
		# Priority 5: being indoors should beat an ordinary outdoor CameraZone whose box the building
		# happens to sit inside, but lose to a vista. Nothing exercises this today — the GladeKit
		# scenes carry no CameraZones — but the tier costs nothing and the day one lands there the
		# doll's-house pull-in would otherwise be silently overruled.
		_rig.claim_frame(self, interior_zoom, 0.0, -1.0, Vector3.ZERO, 0.0, Vector3.ZERO,
				CameraRig.PRIORITY_INTERIOR)
	if _see_through != null:
		_see_through.set_meta("outdoor_radius", _see_through.get("radius"))
		_see_through.set("radius", indoor_see_through)


func _leave() -> void:
	if _inside == null:
		return
	_inside = null
	RenderingServer.global_shader_parameter_set("interior_active", 0.0)
	RoofFade.hold_dim(get_tree(), -1, dim_sun_factor, dim_ambient_factor, dim_time)
	# Drops our claim from the rig's list wherever it sits. A CameraZone that claimed while we were
	# indoors is still in that list, so leaving a building now RESTORES its shot rather than
	# resetting to default framing — which is what the single-owner slot used to do.
	if _rig != null and _rig.has_method("release_frame"):
		_rig.release_frame(self)
	if _see_through != null and _see_through.has_meta("outdoor_radius"):
		_see_through.set("radius", _see_through.get_meta("outdoor_radius"))

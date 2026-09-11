class_name OccluderFade
extends Node
## SEE THROUGH WHATEVER STANDS BETWEEN THE CAMERA AND THE PLAYER. The whole occluding mesh
## fades (Disco Elysium style, not a cut-out hole) and comes back the moment it is out of the
## way. A gameplay aid only: the faded wall keeps casting its shadow, and its materials are not
## touched.
##
## HOW, from the documented pieces. `GeometryInstance3D.transparency` is Godot's per-instance
## fade: "1.0 − transparency" becomes the default ALPHA of any spatial shader, it sends the
## mesh through the transparent pipeline, it "will not disable shadow rendering", and it is
## Forward+ only (this project is Forward+). Occluders are found with
## `PhysicsDirectSpaceState3D.intersect_ray` from the camera to a few points on the player's
## body, repeated with a growing exclude list so every body on the line is found, not only the
## first. Holds use the refcounted protocol of scripts/roof_fade.gd (`RoofFade.hold`), so a
## RoofFade zone and this node never fight over one mesh.
##
## NOT SpringArm3D: that is Godot's shipped camera-occlusion node, and it moves the camera IN
## to the obstacle; the brief is to see THROUGH it and keep the framing. Not
## scripts/see_through.gd either: that per-fragment dither lives in painted_env.gdshader alone,
## and a floorplan bake wears whatever material the kit was given.
##
## WHAT A HIT MAPS TO. A finalized floorplan bake is a StaticBody3D with a child named "Mesh"
## (the contract plan_refine.gd builds) — that mesh fades. In the CSG form the room combiner is
## body and geometry at once — floor and every wall in ONE mesh — so nothing fades and a
## warning names the room: FINALIZE the bake (dock → Finalize CSG → meshes) for per-wall
## see-through. A kit-module wall is a holder with instanced modules — everything under it fades.
## Anything else (a hand-modelled prop, a "Create Trimesh Static Body" mesh) fades its own
## geometry. Never faded: MultiMeshInstance3D (a GladeKit brick batch is the whole building),
## movers (CharacterBody3D / RigidBody3D), meshes with a side longer than `max_extent` (terrain),
## the player's own subtree, and anything carrying meta `occluder_fade_skip`. A shader that
## writes ALPHA itself ignores the instance fade — its own value wins.

@export var enabled := true
@export var target_group := "player"
@export_range(0.0, 1.0) var faded := 0.85   ## transparency while occluding (1 = invisible)
@export var fade_time := 0.25
@export_flags_3d_physics var collision_mask := 1
@export var max_hits := 8                    ## bodies followed along one ray
## Heights above the player's FEET, in metres; a ray goes from the camera to each.
@export var sample_heights := PackedFloat32Array([0.2, 1.0, 1.7])
@export var lateral := 0.3125                ## ± sideways at the middle height (capsule radius)
@export var foot_offset := 0.9               ## the player root sits this far above the feet
@export var max_extent := 30.0               ## never fade a mesh with a longer AABB side
@export var generic := true                  ## fade non-floorplan geometry too
## A CURVED WALL IS MANY PIECES: the Floorplan bake makes one wall piece per outline edge, so a
## round room's wall is thirty-odd short slabs and the rays cross two — a slit. With this on,
## the fade spreads from each hit piece along its wall (see spread_walls).
@export var spread_curves := true
@export_range(0.0, 90.0) var curve_deg := 35.0   ## a bend sharper than this is a corner: the spread stops there
@export var join_m := 0.6                    ## how close two pieces' ends must be to count as joined
## FLOORS. Everything on a floor ABOVE the player's is in the way of a camera that looks down —
## the slab above is the ceiling, and the camera orbits 360° — so those levels fade out whole
## (fully, by default), stairs excepted so the way up stays readable. Below stays: it is never
## between the camera and the player, and the stairwell would look into nothing. Levels are the
## bake's `Level_i` nodes (meta `floorplan_level`); the player is on a level once their feet are
## within `level_switch_m` below its floor, so the upper floor appears while they are still on
## the top steps. A shadow-only mesh would do the same without the transparent pass, but it
## cannot fade — the hold protocol keeps one mechanism for everything.
@export var hide_levels_above := true
@export var hide_levels_below := false
@export_range(0.0, 1.0) var level_faded := 1.0
@export var level_switch_m := 1.2

const LEVEL_SCAN_S := 1.0    # how often the tree is searched for Level_i nodes

var _held := {}          # instance id → GeometryInstance3D (held by the rays)
var _level_held := {}    # instance id → GeometryInstance3D (held by the floor rule)
var _levels: Array = []  # [{node, index, meshes}]
var _levels_at := -10.0
var _sig := ""
var _target: Node3D
static var _warned := {}  # CSG rooms already reported


func _physics_process(_delta: float) -> void:
	if not enabled:
		_release_all()
		return
	var cam := get_viewport().get_camera_3d()
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(target_group) as Node3D
	if cam == null or _target == null:
		_release_all()
		return
	var feet := _target.global_position - Vector3.UP * foot_offset
	if hide_levels_above or hide_levels_below:
		_scan_levels()
		apply_levels(levels_hidden(_levels, feet.y, level_switch_m, hide_levels_above, hide_levels_below))
	else:
		apply_levels([])
	var points: Array[Vector3] = []
	for h in sample_heights:
		points.append(feet + Vector3.UP * h)
	if sample_heights.size() > 1 and lateral > 0.0:
		var mid := feet + Vector3.UP * sample_heights[1]
		var side := cam.global_transform.basis.x * lateral
		points.append(mid + side)
		points.append(mid - side)
	var exclude: Array[RID] = []
	if _target is CollisionObject3D:
		exclude.append((_target as CollisionObject3D).get_rid())
	var space := get_viewport().world_3d.direct_space_state
	var found := occluders(space, cam.global_position, points, exclude, collision_mask, max_hits,
			_target, generic, max_extent)
	if spread_curves:
		found = spread_walls(found, cam.global_position, _target.global_position, curve_deg, join_m,
				_target, generic, max_extent)
	# A mesh the floor rule already holds is not the rays' business: a second hold at the rays'
	# lighter level would pull it back from invisible.
	var rays: Array[GeometryInstance3D] = []
	for gi in found:
		if not _level_held.has(gi.get_instance_id()):
			rays.append(gi)
	apply(rays)


func _exit_tree() -> void:
	_release_all()


## Every piece of geometry on the lines `from` → each of `points`: the set of meshes to fade.
## Pure — a space state, no camera node — so a headless test can ask it directly.
static func occluders(space: PhysicsDirectSpaceState3D, from: Vector3, points: Array[Vector3],
		exclude: Array[RID], mask: int, max_hits: int, skip_under: Node = null,
		generic_geometry := true, max_side := 30.0) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for p in points:
		var ex: Array[RID] = exclude.duplicate()
		for i in max_hits:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, p, mask, ex))
			if hit.is_empty():
				break
			ex.append(hit.rid)
			var col: Node = hit.collider
			if col == null or col is CharacterBody3D or col is RigidBody3D:
				continue
			for gi in meshes_of(col, skip_under, generic_geometry, max_side):
				if not out.has(gi):
					out.append(gi)
	return out


## The meshes one body stands for (see the header).
static func meshes_of(col: Node, skip_under: Node = null, generic_geometry := true,
		max_side := 30.0) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var unit := col
	var n := col
	while n != null:
		if n.has_meta("floorplan_wall") or n.has_meta("floorplan_floor") \
				or n.has_meta("floorplan_room") or n.has_meta("floorplan_stair") or n.has_meta("floorplan_roof"):
			unit = n
			break
		n = n.get_parent()
	if unit.has_meta("occluder_fade_skip"):
		return out
	# The size guard is for terrain and other generic geometry; a bake's floor slab is as big
	# as the room and is exactly what must fade.
	if unit != col or unit.has_meta("floorplan_wall") or unit.has_meta("floorplan_floor") \
			or unit.has_meta("floorplan_room") or unit.has_meta("floorplan_stair") or unit.has_meta("floorplan_roof"):
		max_side = INF
	if unit is GeometryInstance3D:
		if unit is CSGShape3D and unit.has_meta("floorplan_room"):
			# A CSG room is ONE mesh (floor and every wall): nothing to fade wall by wall, and
			# ghosting the floor under the player is worse than nothing. Say so, once.
			if not _warned.has(unit.get_instance_id()):
				_warned[unit.get_instance_id()] = true
				push_warning("OccluderFade: %s is a CSG room (one mesh) — Finalize the bake (dock → Finalize CSG → meshes) for per-wall see-through." % unit.get_path())
			return out
		if _fadeable(unit, max_side):
			out.append(unit)
		return out
	var mesh := unit.get_node_or_null("Mesh") as GeometryInstance3D
	if mesh != null:
		if _fadeable(mesh, max_side):
			out.append(mesh)
		return out
	if unit != col or unit.has_meta("floorplan_kit") or generic_geometry:
		_collect(unit, skip_under, max_side, out)
	if out.is_empty() and generic_geometry:
		# "Create Trimesh Static Body" puts the body UNDER the mesh.
		var parent := col.get_parent() as GeometryInstance3D
		if parent != null and _fadeable(parent, max_side):
			out.append(parent)
	return out


## THE WHOLE CURVED WALL, from the pieces the rays hit. A neighbour joins when its end touches
## this piece's end (within `join_m` — mitred pieces meet at their centre lines within
## t·sin(θ/2)), the run bends by less than `curve_deg` (a corner stops the spread, so a
## rectangular room still fades one wall), and it SEPARATES the camera from the player: the two
## lie on opposite sides of the piece's plane. That test is sign-free on purpose — a slab's
## local Y points in or out with the ring's winding. Only bodies carrying the `floorplan_wall`
## meta take part; the wall's centre line is its origin ± X · len/2 (plan_baker.wall_slab).
static func spread_walls(found: Array[GeometryInstance3D], cam: Vector3, player: Vector3,
		curve_deg: float, join_m: float, skip_under: Node = null, generic_geometry := true,
		max_side := 30.0) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = found.duplicate()
	var seen := {}
	var cos_curve := cos(deg_to_rad(curve_deg))
	for gi in found:
		var unit := _wall_unit(gi)
		if unit == null or seen.has(unit.get_instance_id()) or unit.get_parent() == null:
			continue
		var pieces: Array = []
		for c in unit.get_parent().get_children():
			if c is Node3D and c.has_meta("floorplan_wall"):
				var info: Dictionary = c.get_meta("floorplan_wall")
				var half := float(info.get("len", 0.0)) * 0.5
				var xf: Transform3D = (c as Node3D).global_transform
				var dir := xf.basis.x.normalized()
				pieces.append({"node": c, "a": xf.origin - dir * half, "b": xf.origin + dir * half,
						"dir": dir, "m": xf.basis.y.normalized(), "c": xf.origin})
		var queue: Array = []
		for p in pieces:
			if p.node == unit:
				seen[unit.get_instance_id()] = true
				queue.append(p)
		while not queue.is_empty():
			var cur: Dictionary = queue.pop_back()
			for p in pieces:
				var id: int = (p.node as Node).get_instance_id()
				if seen.has(id):
					continue
				if absf((p.dir as Vector3).dot(cur.dir)) < cos_curve:
					continue                                   # a corner
				if not _ends_touch(cur, p, join_m) or not _separates(p, cam, player):
					continue
				seen[id] = true
				queue.append(p)
				for m in meshes_of(p.node, skip_under, generic_geometry, max_side):
					if not out.has(m):
						out.append(m)
	return out


static func _wall_unit(gi: Node) -> Node:
	var n := gi
	while n != null:
		if n.has_meta("floorplan_wall"):
			return n
		n = n.get_parent()
	return null


static func _ends_touch(u: Dictionary, v: Dictionary, join_m: float) -> bool:
	for e in [u.a, u.b]:
		for f in [v.a, v.b]:
			if (e as Vector3).distance_to(f) <= join_m:
				return true
	return false


static func _separates(p: Dictionary, cam: Vector3, player: Vector3) -> bool:
	var m: Vector3 = p.m
	var c: Vector3 = p.c
	return signf(m.dot(cam - c)) != signf(m.dot(player - c))


static func _collect(n: Node, skip_under: Node, max_side: float, out: Array[GeometryInstance3D]) -> void:
	for c in n.get_children():
		if c == skip_under:
			continue
		if c is GeometryInstance3D and _fadeable(c, max_side):
			out.append(c)
		_collect(c, skip_under, max_side, out)


static func _fadeable(gi: GeometryInstance3D, max_side: float) -> bool:
	if gi is MultiMeshInstance3D or not gi.is_visible_in_tree():
		return false
	var size := gi.get_aabb().size * gi.global_transform.basis.get_scale()
	return maxf(maxf(size.x, size.y), size.z) <= max_side


## Hold exactly this set: release what left, hold what arrived, do nothing when the answer
## has not moved (a per-frame tween restart on forty walls is the obvious trap).
func apply(found: Array[GeometryInstance3D]) -> void:
	for id in _held.keys():
		if not is_instance_valid(_held[id]):
			_held.erase(id)
	var ids: Array[int] = []
	for gi in found:
		ids.append(gi.get_instance_id())
	ids.sort()
	var sig := ""
	for id in ids:
		sig += "%d," % id
	if sig == _sig:
		return
	_sig = sig
	for id in _held.keys():
		if not ids.has(id):
			RoofFade.hold(_held[id], -1, faded, fade_time)
			_held.erase(id)
	for gi in found:
		var id := gi.get_instance_id()
		if not _held.has(id):
			RoofFade.hold(gi, +1, faded, fade_time)
			_held[id] = gi


func _release_all() -> void:
	for id in _held.keys():
		var gi: GeometryInstance3D = _held[id]
		if is_instance_valid(gi):
			RoofFade.hold(gi, -1, faded, fade_time)
	_held.clear()
	_sig = ""
	apply_levels([])


# ---------------------------------------------------------------- floors ----------------------


func _scan_levels() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _levels_at < LEVEL_SCAN_S:
		return
	_levels_at = now
	var from: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	_levels = find_levels(from)


## Every `Level_i` under `from`, with the meshes it owns — stairs and opted-out nodes excepted.
static func find_levels(from: Node) -> Array:
	var out: Array = []
	_find_levels(from, out)
	return out


static func _find_levels(n: Node, out: Array) -> void:
	if n.has_meta("floorplan_level"):
		var meshes: Array[GeometryInstance3D] = []
		_level_meshes(n, meshes)
		out.append({"node": n, "index": int(n.get_meta("floorplan_level")), "meshes": meshes})
		return
	for c in n.get_children():
		_find_levels(c, out)


static func _level_meshes(n: Node, out: Array[GeometryInstance3D]) -> void:
	for c in n.get_children():
		if c.has_meta("floorplan_stair") or c.has_meta("occluder_fade_skip"):
			continue
		if c is GeometryInstance3D and not c is MultiMeshInstance3D:
			out.append(c)
		_level_meshes(c, out)


## The levels the player cannot be allowed to see: those above (and, if asked, below) the
## highest floor their feet have reached, `switch_m` of climb counting as arrived.
static func levels_hidden(levels: Array, feet_y: float, switch_m: float, above: bool, below: bool) -> Array:
	var current := -1
	var best_y := -INF
	for lv in levels:
		# a level can LEAVE while the scan is still cached: a streamed world frees the tile the
		# player walked away from, and its Level_i goes with it
		if not is_instance_valid(lv.node):
			continue
		var y: float = (lv.node as Node3D).global_position.y
		if feet_y + switch_m >= y and y > best_y:
			best_y = y
			current = int(lv.index)
	var out: Array = []
	for lv in levels:
		var i := int(lv.index)
		if (above and i > current) or (below and i < current):
			out.append(lv)
	return out


## Hold exactly these levels' meshes at `level_faded`; release the rest.
func apply_levels(hidden: Array) -> void:
	var want := {}
	for lv in hidden:
		for m in lv.meshes:
			if is_instance_valid(m):
				want[m.get_instance_id()] = m
	for id in _level_held.keys():
		if not want.has(id):
			var gi: GeometryInstance3D = _level_held[id]
			if is_instance_valid(gi):
				RoofFade.hold(gi, -1, level_faded, fade_time)
			_level_held.erase(id)
	for id in want:
		if not _level_held.has(id):
			RoofFade.hold(want[id], +1, level_faded, fade_time)
			_level_held[id] = want[id]

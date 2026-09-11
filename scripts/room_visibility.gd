class_name RoomVisibility
extends Node
## THE GREY MASK: the room the player stands in is clear, and so is every room reached through
## an OPEN door within `max_door_distance` that the player has a clear line to, chaining on
## through those rooms; every other room is filtered by a flat dark-grey mask. The light itself
## is untouched — the mask is a SLAB over the room: a MeshInstance3D box the height of the walls
## in an unshaded dark-grey StandardMaterial3D, faded with GeometryInstance3D.transparency (the
## per-instance fade the camera's see-through already uses) — mostly opaque over a masked room,
## invisible (and hidden, RoofFade's rule) over a clear one. Its border is the room's own
## polygon, exact to the pixel; a doorway into a masked room shows its side as a grey curtain.
## (Local fog — FogVolume per room — was tried first: the froxel grid is a project-wide 64³
## setting, so the mask's edge was a metre of blur and could not be a border.)
##
## ROOMS NEST, SLABS DO NOT. A bedroom sits inside a flat inside the storey's island, and the
## Floorplan bake gives each of them a REGION (Level_i/Regions/<name>, an Area3D, parented by
## containment). Each region's slabs cover ITS OWN FLOOR ONLY — its polygon minus its
## children's (the flat's slabs are the living space around its rooms) — so every slab is
## independent. Boxes come from `boxes_of` (a horizontal band sweep, exact for rectilinear
## rooms), built by `build_mask` when the scene is dressed, under each region's Area3D.
##
## WHICH ROOM: one physics point query per tick on the regions' own layer, deepest hit wins —
## stateless, so a spawn inside a room or a teleport needs no enter/exit bookkeeping. DOORS are
## the bake's `floorplan_door` nodes (regions on either side, `is_open` on the leaf scene, a grey
## box counts as shut); a STAIR is a `floorplan_link`, an always-open door between storeys.
## STOREYS: a level the camera rig's see-through hides above the player (OccluderFade's rule,
## shared here) has no slabs shown either. THE SEE-THROUGH STAYS: a masked room's slab that
## stands between the camera and the player is faded like the wall under it (the see-through
## cannot reach it — it has no collision, on purpose), so the player is never behind the mask.
## SHADOWS FOLLOW THE MASK: a fire in a masked room keeps its light (the room is only dimmed)
## but drops its shadow map — the fires are Dynamic-bake lights (direct + shadows real-time, so
## the player casts a shadow on the baked floor), and a shadow map per torch in every greyed
## room doubled the frame. A prop's `floorplan_region_name` says whose room its lights are.

@export var enabled := true
@export var target_group := "player"
## A door further than this from the player's eye does not open a room to view.
@export var max_door_distance := 12.0
## The player's eye above their node origin (player3's origin is `foot_offset` above the floor).
@export var eye_height := 1.6
@export var foot_offset := 0.9
## Where on a door the line of sight is checked, above the floor.
@export var door_probe_height := 1.1
@export_flags_3d_physics var collision_mask := 1
@export_flags_3d_physics var region_mask := 1 << 15
## How much of a masked room the slab hides (1 = a solid grey block, 0 = nothing).
@export_range(0.0, 1.0) var mask_opacity := 0.95
@export var mask_grey := Color(0.05, 0.05, 0.06)
## A slab between the camera and the player fades to this (the see-through's own level).
@export_range(0.0, 1.0) var see_through_faded := 0.9
## Heights above the player's feet the camera line is checked at, as the see-through does.
@export var sample_heights: PackedFloat32Array = PackedFloat32Array([0.2, 1.0, 1.7])
@export var fade_time := 0.35
## Turn `shadow_enabled` off on the lights of masked rooms (and back on when they clear).
@export var shadow_gate := true
@export var level_switch_m := 1.2

var _target: Node3D
var _regions: Dictionary = {}     # path "Level_i/Regions/<name>" → Area3D
var _path_of: Dictionary = {}     # Area3D → path
var _parent_of: Dictionary = {}   # path → parent path ("" = a root)
var _level_of: Dictionary = {}    # path → level index
var _edges: Array = []            # {node, a, b, link}
var _slabs: Dictionary = {}       # path → Array of MeshInstance3D
var _lights: Dictionary = {}      # path → Array of Light3D that were authored with shadows
var _current := ""
var _sig := ""
var _levels: Array = []
var _tweens: Dictionary = {}


func _ready() -> void:
	_collect.call_deferred()


# ---------------------------------------------------------------- pure helpers -----------------


## Axis-aligned rectangles covering `polygon` minus the `cuts` (metres, xz as Vector2): a
## horizontal band between every pair of consecutive vertex y's (the cuts' included, so a cut
## spans whole bands), clipped to the polygon, each cut clipped out, each piece's bounding box.
## Exact for rectilinear rooms; a curved room gets a staircase of bands (one per vertex row).
static func boxes_of(polygon: PackedVector2Array, cuts: Array = []) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if polygon.size() < 3:
		return out
	var ys: Array = []
	var xmin := INF
	var xmax := -INF
	for v in polygon:
		xmin = minf(xmin, v.x)
		xmax = maxf(xmax, v.x)
	var sources: Array = [polygon]
	sources.append_array(cuts)
	for poly: PackedVector2Array in sources:
		for v in poly:
			var seen := false
			for y in ys:
				if absf(float(y) - v.y) < 1e-4:
					seen = true
					break
			if not seen:
				ys.append(v.y)
	ys.sort()
	for i in ys.size() - 1:
		var y0 := float(ys[i])
		var y1 := float(ys[i + 1])
		if y1 - y0 < 1e-4:
			continue
		var band := PackedVector2Array([Vector2(xmin - 1.0, y0), Vector2(xmax + 1.0, y0),
				Vector2(xmax + 1.0, y1), Vector2(xmin - 1.0, y1)])
		var pieces: Array = Geometry2D.intersect_polygons(polygon, band)
		for cut: PackedVector2Array in cuts:
			var kept: Array = []
			for piece: PackedVector2Array in pieces:
				kept.append_array(Geometry2D.clip_polygons(piece, cut))
			pieces = kept
		for piece: PackedVector2Array in pieces:
			if piece.size() < 3 or Geometry2D.is_polygon_clockwise(piece):
				continue                       # a hole polygon: nothing of its own to cover
			var r := Rect2(piece[0], Vector2.ZERO)
			for v in piece:
				r = r.expand(v)
			if r.size.x > 1e-3 and r.size.y > 1e-3:
				out.append(r)
	return out


## The children of every region (Area3D nodes of one level), by parent name, from their own
## `parent` metadata.
static func children_of(regions: Array) -> Dictionary:
	var out := {}
	for a in regions:
		var info: Dictionary = a.get_meta("floorplan_region")
		var parent := String(info.parent)
		if parent == "":
			continue
		if not out.has(parent):
			out[parent] = []
		out[parent].append(a)
	return out


## The regions in view from `start`: itself, and through every edge that `is_open`, is `near`
## and has line of sight (`los`) — links (stairs) skip the last two — on through those.
static func visible_set(start: String, edges: Array, is_open: Callable, near: Callable, los: Callable) -> Dictionary:
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var r: String = queue.pop_front()
		for e: Dictionary in edges:
			var other := ""
			if String(e.a) == r:
				other = String(e.b)
			elif String(e.b) == r:
				other = String(e.a)
			if other == "" or seen.has(other):
				continue
			if not is_open.call(e):
				continue
			if not bool(e.get("link", false)) and (not near.call(e) or not los.call(e)):
				continue
			seen[other] = true
			queue.append(other)
	return seen


## Dress a bake with its mask: one slab per rectangle of every region's OWN floor (its polygon
## minus its children's), invisible until masked, under the region's Area3D. One shared
## unshaded material; the fade is per instance. Returns the count.
static func build_mask(root: Node, height: float, grey := Color(0.1, 0.1, 0.12)) -> int:
	var made := 0
	var mat := StandardMaterial3D.new()
	mat.resource_name = "RoomMask"
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(grey.r, grey.g, grey.b, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var by_level := {}
	for n in _walk(root):
		if n.has_meta("floorplan_region"):
			var li := int((n.get_meta("floorplan_region") as Dictionary).level)
			if not by_level.has(li):
				by_level[li] = []
			by_level[li].append(n)
	for li in by_level:
		var kids := children_of(by_level[li])
		for n in by_level[li]:
			var info: Dictionary = n.get_meta("floorplan_region")
			var cuts: Array = []
			for c in kids.get(String(info.name), []):
				cuts.append((c.get_meta("floorplan_region") as Dictionary).polygon)
			var k := 0
			for r: Rect2 in boxes_of(info.polygon, cuts):
				var slab := MeshInstance3D.new()
				slab.name = "Mask_%d" % k
				var box := BoxMesh.new()
				# A hair above the wall tops and a hair inside the room's outline: no z-fighting
				# with the walls it meets, and the wall between two masked rooms still shows.
				box.size = Vector3(r.size.x - 0.02, height + 0.05, r.size.y - 0.02)
				slab.mesh = box
				slab.material_override = mat
				slab.position = Vector3(r.position.x + r.size.x * 0.5, box.size.y * 0.5, r.position.y + r.size.y * 0.5)
				slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				slab.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				slab.transparency = 1.0
				slab.visible = false
				slab.set_meta("occluder_fade_skip", true)   # never the see-through's business
				slab.set_meta("room_mask", true)
				n.add_child(slab)
				# Owned here: the baker's own_tree() never descends into a node that is already
				# owned (an instanced scene's internals must stay its own), and the region is.
				if root.is_ancestor_of(slab):
					slab.owner = root
				made += 1
				k += 1
	return made


# ---------------------------------------------------------------- runtime ----------------------


func _collect() -> void:
	var root := get_parent()
	if root == null:
		return
	_levels = OccluderFade.find_levels(root)
	for level in root.get_children():
		if not level.has_meta("floorplan_level"):
			continue
		var li := int(level.get_meta("floorplan_level"))
		var regs := level.get_node_or_null("Regions")
		if regs != null:
			for a in regs.get_children():
				if not a.has_meta("floorplan_region"):
					continue
				var info: Dictionary = a.get_meta("floorplan_region")
				var path := "Level_%d/Regions/%s" % [li, info.name]
				_regions[path] = a
				_path_of[a] = path
				_parent_of[path] = ("Level_%d/Regions/%s" % [li, info.parent]) if String(info.parent) != "" else ""
				_level_of[path] = li
				var slabs: Array = []
				for c in a.get_children():
					if c.has_meta("room_mask"):
						slabs.append(c)
				_slabs[path] = slabs
		var props := level.get_node_or_null("Props")
		if props != null:
			for p in props.get_children():
				if not p.has_meta("floorplan_region_name"):
					continue
				var path := "Level_%d/Regions/%s" % [li, String(p.get_meta("floorplan_region_name"))]
				for l in [p] + _walk(p):
					if l is Light3D and (l as Light3D).shadow_enabled:
						if not _lights.has(path):
							_lights[path] = []
						(_lights[path] as Array).append(l)
		for d in _walk(level):
			if d.has_meta("floorplan_door"):
				var info: Dictionary = d.get_meta("floorplan_door")
				var ra := String(info.regions[0])
				var rb := String(info.regions[1])
				if ra != "" and rb != "":
					_edges.append({"node": d, "a": "Level_%d/Regions/%s" % [li, ra],
							"b": "Level_%d/Regions/%s" % [li, rb], "link": false})
			elif d.has_meta("floorplan_link"):
				var info: Dictionary = d.get_meta("floorplan_link")
				_edges.append({"node": d, "a": String(info.regions[0]), "b": String(info.regions[1]), "link": true})


func _physics_process(_delta: float) -> void:
	if not enabled:
		if _sig != "off":
			_sig = "off"
			_apply({})
		return
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(target_group) as Node3D
		if _target == null:
			return
	if _regions.is_empty():
		return
	var space := get_viewport().world_3d.direct_space_state
	var feet := _target.global_position - Vector3.UP * foot_offset
	var here := _region_at(space, feet + Vector3.UP * 0.5)
	if here != "":
		_current = here
	if _current == "":
		return
	var hidden_levels := {}
	for lv: Dictionary in OccluderFade.levels_hidden(_levels, feet.y, level_switch_m, true, false):
		hidden_levels[int(lv.index)] = true
	var eye := _target.global_position + Vector3.UP * (eye_height - foot_offset)
	var is_open := func(e: Dictionary) -> bool:
		if bool(e.get("link", false)):
			return true
		var node: Node = e.node
		return bool(node.get("is_open")) if "is_open" in node else false
	var near := func(e: Dictionary) -> bool:
		return (e.node as Node3D).global_position.distance_to(eye) <= max_door_distance
	var los := func(e: Dictionary) -> bool:
		var door := e.node as Node3D
		var to := door.global_position + Vector3.UP * door_probe_height
		var q := PhysicsRayQueryParameters3D.create(eye, to, collision_mask)
		q.exclude = [_target.get_rid()] if _target is CollisionObject3D else []
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var col: Object = hit.collider
		return col is Node and (col == door or door.is_ancestor_of(col))
	var seen := visible_set(_current, _edges, is_open, near, los)
	# A hidden storey shows nothing at all — no mask either.
	var targets := {}
	var cam := get_viewport().get_camera_3d()
	for path in _regions:
		var masked := not seen.has(path) and not hidden_levels.has(int(_level_of[path]))
		targets[path] = 1.0 - mask_opacity if masked else 1.0
		if masked and cam != null and _between(path, cam.global_position, feet):
			targets[path] = maxf(float(targets[path]), see_through_faded)
	var sig := str(targets)
	if sig == _sig:
		return
	_sig = sig
	_apply(targets)


## Does one of the region's slabs stand on the line from the camera to the player?
func _between(path: String, from: Vector3, feet: Vector3) -> bool:
	for s: GeometryInstance3D in _slabs.get(path, []):
		if not is_instance_valid(s):
			continue
		var box: AABB = s.global_transform * s.get_aabb()
		for h in sample_heights:
			if box.intersects_segment(from, feet + Vector3.UP * float(h)):
				return true
	return false


## The deepest region holding `point`, as its path, or "".
func _region_at(space: PhysicsDirectSpaceState3D, point: Vector3) -> String:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = point
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = region_mask
	var best := ""
	var best_depth := -1
	for hit: Dictionary in space.intersect_point(q, 32):
		var col: Object = hit.collider
		if not _path_of.has(col):
			continue
		var depth := int((col.get_meta("floorplan_region") as Dictionary).get("depth", 0))
		if depth > best_depth:
			best_depth = depth
			best = _path_of[col]
	return best


## `targets`: region path → the slabs' transparency (1 = clear room, hidden slab).
func _apply(targets: Dictionary) -> void:
	if shadow_gate:
		for path in _lights:
			var lit := float(targets.get(path, 1.0)) >= 1.0
			for l: Light3D in _lights[path]:
				if is_instance_valid(l):
					l.shadow_enabled = lit
	for path in _slabs:
		var want := float(targets.get(path, 1.0))
		var slabs: Array = _slabs[path]
		if slabs.is_empty():
			continue
		var from := (slabs[0] as GeometryInstance3D).transparency
		if is_equal_approx(from, want):
			continue
		if _tweens.has(path) and (_tweens[path] as Tween).is_valid():
			(_tweens[path] as Tween).kill()
		for s: GeometryInstance3D in slabs:
			s.visible = true
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(t: float) -> void: _set_slabs(slabs, t), from, want, fade_time)
		if want >= 1.0:
			# Fully faded means hidden (RoofFade's rule: an instance at transparency 1 is still
			# drawn, through the transparent pipeline).
			tw.tween_callback(func() -> void:
				for s: GeometryInstance3D in slabs:
					if is_instance_valid(s) and s.transparency >= 1.0:
						s.visible = false)
		_tweens[path] = tw


func _set_slabs(slabs: Array, t: float) -> void:
	for s: GeometryInstance3D in slabs:
		if is_instance_valid(s):
			s.transparency = t


static func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out

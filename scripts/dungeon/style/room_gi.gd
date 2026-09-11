@tool # so the Dungeon Forge GI bake can reuse this in the editor. Inert at runtime; attached to no scene.
class_name RoomGI
extends Node
## One baked VoxelGI per crypt room, kept ahead of the player.
##
## WHY THIS EXISTS AND WHY IT IS NOT FREE. Measured on the hero frame by crypt_lookdev's
## `_voxel_gi_ab`, a baked room against the same room unbaked:
##
##     mean 0.0542 -> 0.0885     readable 0.5146 -> 0.8201     saturation 0.6574 -> 0.7947
##
## That is the difference between a crypt lit by fixtures and a crypt that looks lit. SDFGI cannot
## do it here: it re-fits cascades around a moving camera and gathers almost nothing in a sealed
## room whose only emitters are small and warm.
##
## The cost is 1.4 s of BLOCKING bake per room and 119 MB of VRAM per room. Both numbers matter and
## one of them was wrong for a long time: voxelgi_probe.gd recorded 649 -> 1135 MB and that figure
## was used to reject VoxelGI outright, but the probe had asked bake() for a debug MultiMesh of
## 66,000 instances and was measuring the debug mesh. A clean bake is 119 MB, which is affordable.
##
## SO THE PROBLEM IS SCHEDULING, NOT BUDGET, and the dungeon already answers it. show_around() keeps
## only the room you are in and its door-neighbours VISIBLE, so those are the only rooms whose GI can
## ever be seen — three or four at a time, not ten. Bake that set, keep a few more resident against
## backtracking, evict the rest.
##
## TWO THINGS THAT WILL BITE ANYONE EDITING THIS:
##
##   * A ROOM MUST BE VISIBLE TO BAKE. VoxelGI only voxelises meshes that are GI_MODE_STATIC *and*
##     visible in tree, and show_around() has already hidden every room you want to bake ahead. So
##     the bake temporarily unhides its subject. That is safe only because bake() is synchronous —
##     no frame renders between the unhide and the restore, so the player never sees it.
##   * BAKE ONE PER TICK, NEVER A LOOP. Each is 1.4 s of frozen main thread. A loop over four rooms
##     is a six-second hang; one per tick is four stutters spread over four ticks, and if the tick
##     lands during the doors-shut combat lock (DungeonRoom._activate) nobody sees any of them.

## Rooms kept baked at once. The visible set is at most four, so this leaves headroom for
## backtracking without re-baking. 6 x 119 MB is about 715 MB — real, but affordable against the
## crypt's ~1.5 GB, and the alternative is a 1.4 s stall every time the player turns around.
const RESIDENT := 6
## Room plus its walls. Larger spills into the corridor and wastes cells on the void; smaller fails
## to voxelise the walls themselves, which are the occluders the whole effect depends on.
##
## THE FALLBACK ONLY. This is a single cell's interior (20 x 12) plus MARGIN, and it used to be the
## size handed to every VoxelGI regardless of the room — so a 2x2 hall, whose interior is 44 x 28,
## was lit by a probe covering less than half of it, and the far end of every hall fell back to
## ambient. Rooms now derive their own; see _extent_for.
const EXTENT := Vector3(21.5, 8.0, 13.5)
## Clearance past the interior on each axis, so the walls themselves land inside the probe. They are
## the occluders the whole effect depends on — a probe flush with the floor plan bounces off nothing.
##
## RAISED FROM 1.5 FOR THE LIGHTS THAT LIVE OUTSIDE THE ROOM. A breached wall's shaft is cast from
## BEHIND the masonry, and at 1.5 the volume reached only 0.75 m past each wall — so the lamp sat
## outside its own room's VoxelGI and its bounce reached the floor not at all. The beam lit the fog
## and nothing else, which is exactly what "the god rays look flat" turns out to mean. 4.0 puts a
## lamp up to 2 m out inside the probe.
##
## It is not free: same subdiv over a bigger box means coarser voxels (a single cell goes from ~0.17
## to ~0.19 m). GI is low-frequency by nature and that is well inside what it can carry — but if a
## future piece wants a lamp further out than 2 m, move the lamp, do not grow this.
const MARGIN := 4.0
const LIFT := 3.4
## The clear opening a doorway keeps in the proxy: the height DungeonDoor's blocker fills
## (SLAB.y + 0.8, dungeon_door.gd:44). Below this the wall is passage; above it is spandrel.
const DOOR_CLEAR := 3.0
## How hard the bounce comes back. VoxelGIData ships at energy 1.0 / propagation 0.7 and nothing
## here ever changed them — fine for a daylit scene with plenty of light to redistribute, thin for a
## crypt whose emitters are candle-sized. Tune these in scenes/dev/godray_lab.tscn, which writes them
## live onto the room's baked data.
const GI_ENERGY := 1.90
## How far light travels through the voxel grid per step. Higher reaches the far corners of a hall;
## too high and the whole room washes to one value and the torchlit falloff goes with it.
const GI_PROPAGATION := 0.85
## Seconds between checks. The work is a footprint test over a handful of rooms; there is no reason
## to do it every frame and every frame is when a stutter is least welcome.
const TICK := 0.35
## The proxy shell's albedo — roughly the stone shader's mid stop, since that is what the real walls
## average out to and GI only ever sees an average.
const PROXY_ALBEDO := Color(0.355, 0.328, 0.297)
## Seconds in one room before ahead-baking is allowed on the "settled" rule. Long enough that
## walking straight through never triggers it, short enough that pausing to look around does.
const DWELL := 2.0

var _data := {}                       ## DungeonRoom -> VoxelGI
var _order: Array[Node] = []          ## least-recently-wanted first
var _zone: Node3D
var _t := 0.0
var _current: Node                    ## room the player is in, for the dwell timer
var _dwell := 0.0


func setup(zone: Node3D) -> void:
	_zone = zone


## Bake the arrival room and everything one door from it, right now, blocking. Called from the
## generator while the zone is still being added — the player is mid-portal-transition behind a
## fade, which is the one moment several seconds of stall costs nothing.
func prime(start: Node) -> void:
	if start == null:
		return
	_ensure(start)
	for n in (start as DungeonRoom).neighbours():
		_ensure(n)
	# Set the initial contribution here rather than waiting for the first tick. _process bails when
	# it cannot find a player, and the look-dev rig has none — without this the rig would photograph
	# every primed room contributing at once, which is the leak _only() exists to prevent.
	_only(start)


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK or _zone == null or not is_instance_valid(_zone):
		return
	_t = 0.0
	var here := _room_of_player()
	if here == null:
		return
	if here != _current:
		_current = here
		_dwell = 0.0
	else:
		_dwell += TICK
	_only(here)

	# THE ROOM YOU ARE STANDING IN IS NOT NEGOTIABLE. If it is somehow unbaked — a seed with more
	# neighbours than prime() covered, or a room reached faster than the scheduler could work — bake
	# it now and take the hitch, because the alternative is standing in a room that is visibly
	# darker than every other one.
	if _ensure(here):
		return

	# EVERYTHING ELSE WAITS FOR A MOMENT WHEN 127 ms CANNOT BE SEEN, which is the whole point of
	# scheduling rather than just spreading the work out. Two such moments exist and the dungeon
	# already creates both:
	#
	#   * COMBAT. DungeonRoom._activate() shuts every door on first entry and does not open them
	#     until the room is cleared. The player is locked in, the camera is on them, and they are
	#     not about to walk through a door that is barred — so a frame spent baking the room beyond
	#     it is a frame nobody is looking at.
	#   * DWELL. Standing still, reading the room, picking up loot. If the player has been in the
	#     same room for a couple of seconds they are not sprinting a corridor, and the next room can
	#     be prepared without interrupting anything.
	#
	# Outside those, do nothing. A player running flat out through cleared rooms may outrun the
	# scheduler and hit one bake on arrival; that is the honest worst case and it is one blink, not
	# a hang. Fixing it properly means baking off the main thread, which Godot's renderer does not
	# offer here.
	if not _safe_to_bake(here):
		return
	for n in (here as DungeonRoom).neighbours():
		if _ensure(n):
			return


func _safe_to_bake(here: Node) -> bool:
	return (here as DungeonRoom).state == DungeonRoom.State.ACTIVE or _dwell >= DWELL


## ONLY THE ROOM YOU ARE IN CONTRIBUTES ITS GI, and this is not an optimisation — it is the whole
## reason the crypt still reads as torchlit.
##
## Baking the neighbours ahead is what avoids a 1.4 s stall in every doorway, but a baked volume
## keeps emitting whatever it captured, and VoxelGI cone-traces through 0.5 m walls that are only
## three cells thick at SUBDIV_128. Leaving them all on measured a lit/unlit room ratio of 3.35
## against a bound of 12 — the neighbouring room lit itself from its own bake and "only the room you
## are in is lit", which the entire black-void pass exists to protect, was gone.
##
## So: keep the bake, drop the contribution. `visible` on a VoxelGI switches its contribution off
## without discarding the texture, so walking next door is still instant.
func _only(here: Node) -> void:
	for room: Node in _data:
		var v: VoxelGI = _data[room]
		if is_instance_valid(v):
			v.visible = room == here


## The probe that fits THIS room, rather than the one that fits a single cell.
##
## MEMORY IS NOT THE COST HERE, which is worth stating because it is the obvious worry and it is the
## wrong one. `subdiv` fixes the cell count along the longest axis, so every bake costs the same
## whatever `size` is; RESIDENT can stay at 6. What a bigger room actually spends is RESOLUTION — a
## great hall's 68 m across SUBDIV_128 gives 0.53 m voxels where a single cell's 20 m gives 0.17 m.
## GI is low-frequency by nature (see the proxy-bake note below), so half-metre voxels in the room
## that most needs a probe at all is a better trade than a probe that stops two thirds of the way
## along it.
func _extent_for(room: Node) -> Vector3:
	var fp := _footprint_of(room)
	if fp.x <= 0.0 or fp.z <= 0.0:
		return EXTENT
	return Vector3(fp.x + MARGIN, EXTENT.y, fp.z + MARGIN)


## Duck-typed rather than cast: a DungeonRoom carries `footprint` as a property, and so does the
## Forge preview's stand-in room — the bake logic is identical for both, and a hard cast was the
## only thing keeping the editor preview from reusing it.
static func _footprint_of(room: Node) -> Vector3:
	var fp: Variant = room.get("footprint")
	return fp if fp is Vector3 else Vector3.ZERO


## HOW FAR THE ROOM GOES BELOW ITS OWN FLOOR, in metres, 0 for a flat one.
##
## THE PROBE USED TO ASSUME A ROOM'S FLOOR WAS ITS BOTTOM, and for two years it was. `size` is the
## FULL box, so at LIFT 3.4 and 8.0 tall the volume ran y = -0.6 to 7.4 — six hundred millimetres of
## slack under the floor, which is plenty for a room that has no under.
##
## Then levels went signed and a colosseum put an arena a level down. At -1.2 the whole arena — its
## floor, its retaining walls, the ramps out of it — sits UNDER the probe, and this crypt is lit
## almost entirely by bounce from candle-sized emitters, so outside the volume means unlit means
## black. Three omnis stood inside the pit and it still photographed as a trench cut through the
## floor. Nothing failed: the slabs are built, visible, unoccluded and at the right height, which is
## how it survived a milestone whose own suite checks reachability across exactly those tiles.
##
## Measured off the room's own geometry rather than assumed from RoomShape.LEVEL_RISE, because a
## deeper pit or a stacked one must not need this constant edited to be lit — the failure mode is
## silent and the next person would have no reason to look here.
func _drop_of(room: Node) -> float:
	var low := 0.0
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var box: AABB = vi.global_transform * vi.get_aabb()
			low = minf(low, box.position.y - (room as Node3D).global_position.y)
	return maxf(-low, 0.0)


## Returns true if it actually baked (so the caller can stop for this tick).
func _ensure(room: Node) -> bool:
	if room == null or not is_instance_valid(room):
		return false
	_touch(room)
	if _data.has(room):
		return false

	# THE BOX GROWS DOWNWARD ONLY. `size` is centred on the node, so adding the drop and leaving the
	# centre alone would spend half of it on ceiling nobody is standing under; the centre comes down
	# by half of what the box gained, and the top stays exactly where it was. A flat room gets drop 0
	# and is bit-identical to before.
	var drop := _drop_of(room)
	var ext := _extent_for(room)
	ext.y += drop
	var vgi := VoxelGI.new()
	vgi.size = ext
	vgi.subdiv = VoxelGI.SUBDIV_128
	add_child(vgi)
	vgi.global_position = (room as Node3D).global_position 			+ Vector3(0.0, LIFT - drop * 0.5, 0.0)

	# BAKE A PROXY, NOT THE BRICKWORK. This is the difference between a tool and a stutter.
	#
	# A crypt room is ~350,000 primitives of modelled masonry, and VoxelGI's bake cost is dominated
	# by walking geometry rather than by voxel resolution — voxelgi_probe measured 1103 ms at
	# SUBDIV_64 against 1548 at 128, eight times the cells for 40% more time. Baking the real kit
	# therefore froze the main thread for 1.4 s per room however coarse the grid.
	#
	# But GI is low-frequency by nature: it needs to know where the walls are and roughly what colour
	# they are, not where each brick is. Six boxes carry that. So the bake swaps the room's real
	# meshes out for a proxy shell, bakes, and swaps back — safe only because bake() is synchronous,
	# so no frame renders while the room is made of boxes.
	#
	# UNHIDE TO BAKE, too: show_around() has very likely hidden this room already, and a hidden mesh
	# voxelises to nothing.
	var t0 := Time.get_ticks_msec()
	var was := (room as Node3D).visible
	(room as Node3D).visible = true
	var proxy := _proxy_for(room)
	(room as Node3D).add_child(proxy)
	var hidden := _hide_real(room, proxy)
	vgi.bake(room, false)
	# THE BOUNCE STRENGTH, which bake() leaves at defaults and nothing has ever set. A crypt lit
	# only by small fires has very little light to bounce in the first place, so 1.0 energy and a
	# single bounce puts almost nothing back into the room — and a shaft of daylight through a
	# breach, which is by far the strongest emitter in the building, was giving up most of its
	# effect on the way. Two bounces is what carries light off the floor and back onto the walls,
	# which is the difference between a lit beam and a lit ROOM.
	if vgi.data != null:
		vgi.data.energy = GI_ENERGY
		vgi.data.propagation = GI_PROPAGATION
		vgi.data.use_two_bounces = true
	for n in hidden:
		(n as Node3D).visible = true
	proxy.queue_free()
	(room as Node3D).visible = was

	_data[room] = vgi
	_evict()
	print("[RoomGI] baked %s in %d ms (%d resident)"
			% [(room as Node3D).name, Time.get_ticks_msec() - t0, _data.size()])
	return true


## The room's PLAN, as boxes — not a crate around its footprint. The old proxy was a floor and
## four solid walls at the bounding box, which was enough while every room was a flat rectangle
## and stopped being honest the moment they weren't: a carved L bounced light out of its own
## void, a colosseum's pit had no walls and a flat floor over it, a doorway was masonry (so no
## light ever coupled to the corridor the way the real bake couples it), and a pillar occluded
## nothing. GI is low-frequency — it never needed the bricks — but it does need the SHAPE, and
## the room already carries its shape: DungeonRoom keeps its RoomContext (`plan`, kept at
## dungeon_generator.gd for exactly this kind of consumer), whose RoomShape knows every tile,
## level, wall and doorway. So the proxy is now the plan re-read as slabs:
##
##   floors    one slab per solid tile, AT THE TILE'S LEVEL — a pit floor sits down in the pit
##   walls     one slab per walls() segment, spans and diagonals included; a DOORWAY keeps only
##             its spandrel (above DOOR_CLEAR), so rooms and passages exchange light like the
##             built geometry does
##   risers    LEVEL_RISE-tall retaining slabs exactly where walls() stacks them
##   cover     a box per planned pillar and crate — the mid-room occluders
##
## Cost: ~40-70 boxes against the six before, which is still nothing next to the ~164k
## triangles per room the real kit would make bake() walk (measured 2026-08-25; the proxy is
## roughly 10x faster live). The dais still doesn't appear — its slot carries no extent
## (see layout_lab's "reserved, extent unknown" diamond); it joins when fixtures carry a span.
##
## Rooms with no plan (none the game builds today) fall back to the old shell, so the function
## can never do worse than it used to.
func _proxy_for(room: Node) -> Node3D:
	var root := Node3D.new()
	root.name = "GIProxy"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _gi_albedo_of(room)
	mat.roughness = 1.0

	var plan: Variant = room.get("plan")
	var shape: RoomShape = plan.shape if plan is RoomContext else null
	if shape == null:
		_shell_slabs(root, mat, _footprint_of(room))
		return root
	var rd: Variant = room.get("data")                     # RoomData, for the doorway test

	# FLOORS — per tile, on its own level, so a deck is high and a pit is deep.
	for j in shape.rows:
		for i in shape.cols:
			var t := Vector2i(i, j)
			if not shape.is_solid(t):
				continue
			var c := shape.tile_centre(t)                  # y carries level * LEVEL_RISE
			_slab(root, mat, Vector3(RoomShape.TILE, 0.5, RoomShape.TILE),
					Vector3(c.x, c.y - 0.25, c.z), 0.0)

	# WALLS — every segment the shape emits, exactly where it emits it.
	var h := DungeonLayout.WALL_HEIGHT
	for w: Dictionary in shape.walls():
		var at: Vector3 = w.at
		var span: float = w.get("span", RoomShape.TILE)
		var yaw: float = w.yaw
		if String(w.role) == "riser":
			# One LEVEL_RISE module per entry; walls() already stacked them at their own bases.
			_slab(root, mat, Vector3(span, RoomShape.LEVEL_RISE, 0.5),
					Vector3(at.x, at.y + RoomShape.LEVEL_RISE * 0.5, at.z), yaw)
			continue
		var doorway := false
		if rd is DungeonLayout.RoomData:
			for e: DungeonLayout.Edge in rd.edges:
				var hd := Vector2i(e.dir.x, e.dir.z)
				if hd != Vector2i.ZERO \
						and RoomShape.is_doorway(w, hd, DungeonLayout.door_local(rd, e)):
					doorway = true
					break
		if doorway:
			# The spandrel only: the clear opening below it is how this room's light reaches the
			# passage and the passage's candelabra reaches back — the coupling the crate proxy
			# never had and the real bake always did.
			_slab(root, mat, Vector3(span, h - DOOR_CLEAR, 0.5),
					Vector3(at.x, (h + DOOR_CLEAR) * 0.5, at.z), yaw)
		else:
			_slab(root, mat, Vector3(span, h, 0.5), Vector3(at.x, h * 0.5, at.z), yaw)

	# THE MID-ROOM OCCLUDERS — planned cover with a real footprint. Heights are kit-roughly:
	# a pillar is a wall-course piece, a crate is a metre of box; GI cannot tell finer.
	for slot: RoomContext.Slot in (plan as RoomContext).slots:
		var tall := slot.tag == RoomPlan.T_COVER_LARGE
		if not tall and slot.tag != RoomPlan.T_COVER_SMALL:
			continue
		if slot.footprint == Vector2.ZERO:
			continue                                       # extent not carried; nothing honest to build
		var ch := 3.0 if tall else 1.0
		var o := slot.transform.origin
		_slab(root, mat, Vector3(slot.footprint.x, ch, slot.footprint.y),
				Vector3(o.x, o.y + ch * 0.5, o.z), slot.transform.basis.get_euler().y)
	return root


## What colour this room's stone bounces: the theme's answer when a theme is reachable — the
## preview room carries one, the generator above a DungeonRoom carries one — and the shader's
## mid stop when nothing is. Duck-typed like _footprint_of, and for the same reason.
func _gi_albedo_of(room: Node) -> Color:
	var t: Variant = room.get("theme")
	if not t is DungeonTheme and room.get_parent() != null:
		t = room.get_parent().get("theme")
	return (t as DungeonTheme).gi_albedo if t is DungeonTheme else PROXY_ALBEDO


## The pre-plan shell: floor and four solid walls at the footprint. Kept as the fallback for a
## room that carries no plan, which nothing the game builds today is.
func _shell_slabs(root: Node3D, mat: Material, fp: Vector3) -> void:
	var w: float = fp.x
	var d: float = fp.z
	var h := DungeonLayout.WALL_HEIGHT
	_slab(root, mat, Vector3(w, 0.5, d), Vector3(0.0, -0.25, 0.0), 0.0)
	_slab(root, mat, Vector3(0.5, h, d), Vector3(-w * 0.5, h * 0.5, 0.0), 0.0)
	_slab(root, mat, Vector3(0.5, h, d), Vector3(w * 0.5, h * 0.5, 0.0), 0.0)
	_slab(root, mat, Vector3(w, h, 0.5), Vector3(0.0, h * 0.5, -d * 0.5), 0.0)
	_slab(root, mat, Vector3(w, h, 0.5), Vector3(0.0, h * 0.5, d * 0.5), 0.0)


func _slab(root: Node3D, mat: Material, size: Vector3, at: Vector3, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Hide every real GI contributor in the room for the duration of the bake, and report what was
## hidden so it can be put back. Anything already invisible, or already excluded from GI, is left
## alone — putting it back visible would be a bug, not a restore.
func _hide_real(room: Node, proxy: Node) -> Array[Node]:
	var out: Array[Node] = []
	for n in _walk(room):
		if n == proxy or proxy.is_ancestor_of(n):
			continue
		if n is GeometryInstance3D and (n as Node3D).visible \
				and (n as GeometryInstance3D).gi_mode == GeometryInstance3D.GI_MODE_STATIC:
			(n as Node3D).visible = false
			out.append(n)
	return out


static func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _touch(room: Node) -> void:
	_order.erase(room)
	_order.append(room)


## Drop the least-recently-wanted bakes once past RESIDENT. Frees the VoxelGI node outright rather
## than hiding it: a hidden VoxelGI still holds its texture, and the texture is the whole cost.
func _evict() -> void:
	while _order.size() > RESIDENT:
		var old: Node = _order.pop_front()
		if _data.has(old):
			var v: VoxelGI = _data[old]
			if is_instance_valid(v):
				v.queue_free()
			_data.erase(old)


## Footprint containment, not nearest centre. A distance test picks the wrong room whenever the
## player is near a boundary, and gets stairwells badly wrong because their floors are only
## FLOOR_HEIGHT apart in Y.
## A STAND-IN FOR THE PLAYER, for the benches that have none. When set it wins over the group
## lookup; left null, nothing about the game changes.
##
## This exists because the obvious alternative is worse. A bench can always add its camera to the
## `player` group — but eight other systems read that group (Hud, CourseVeil, MapData, Enemy, Npc,
## CloudSea, GrassPatch, RoofFade), and Hud immediately dereferences `.health` on whatever it finds.
## Faking the player to move a light probe means impersonating it for every one of them. One
## explicit property is cheaper and does not lie to anybody.
var probe: Node3D = null


func _room_of_player() -> Node:
	var p := probe if probe != null and is_instance_valid(probe) \
			else get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return null
	var at := p.global_position
	for n in _zone.get_children():
		if not (n is DungeonRoom):
			continue
		var r := n as DungeonRoom
		var d: Vector3 = at - r.global_position
		if absf(d.y) < DungeonLayout.FLOOR_HEIGHT * 0.5 \
				and absf(d.x) <= r.footprint.x * 0.5 and absf(d.z) <= r.footprint.z * 0.5:
			return r
	return null

@tool
extends RefCounted
## WHAT STANDS IN A ROOM, put in after the bake and before the unit is packed.
##
## The bake gives a room its floor, its walls and its doorways — the void carved out of rock —
## and nothing else. This fills it: the pillars that break a twenty-metre hall into cover, the
## braziers that are the only light down here, a statue or a sarcophagus where the room's
## purpose asks for one, and rubble where a crypt would have rubble.
##
## THE PIECES ARE THE CRYPT'S OWN. `scenes/dungeon/kit/` and `scenes/props/dungeon/` are a
## finished library — modelled, textured, collidered to a stated contract, and already lit the
## way the hand-built crypt lights itself. Nothing here models anything; it decides WHERE.
## That is also why a brazier is the light source rather than a bare OmniLight3D: the kit piece
## carries the light, the flame mesh and the `torch_flame` / `theme_light` metas that the
## crypt's own room lighting reads, so a generated room is the same kind of object as an
## authored one and a later round can gate it the same way.
##
## LIGHT IS NOT DECORATION HERE. `world_zone` blacks the world out when a carved zone is
## entered — no sky, no sun, fog to the edge of the room — so a room with no brazier in it is a
## room the player cannot see. `_lights()` runs before anything else and is the one pass that
## may not come back empty.
##
## PLACEMENT IS A LATTICE, NOT A SCATTER. Every room polygon is the boundary of square tiles
## (see `world_crypt`), so candidate points are taken on that same lattice, inset from the walls
## and cleared of the doorways. A prop is never half in the rock, never in a doorway, and the
## same seed always puts it in the same place.

## The kit, by what the piece is for. Every one is a StaticBody3D whose ROOT carries the
## collider (the kit's own contract), so it can be instanced anywhere without being re-rigged.
const KIT := "res://scenes/dungeon/kit/"
const PROPS := "res://scenes/props/dungeon/"

## AND A KIT PIECE ARRIVES UNPAINTED. Its `.glb` carries the shape and nothing else, because the
## kit's contract is that `Kit.dress` hangs the theme's stone on every mesh in it — that is what
## gives a pillar the same courses and the same damp as the wall behind it, and why an undressed
## one renders as a white block. It is also what normalises the lights: a brazier ships at 7.5
## energy over 14 m and comes out of `dress` on the theme's own 4.0, the same as every sconce in
## the hand-built crypt.
##
## The `scenes/props/dungeon/` pieces are NOT dressed, and that is the kit's rule as well: they
## are clutter with authored materials of their own (wood, iron, bone), and painting them stone
## would be a worse dungeon, not a more consistent one.
const THEME := "res://scenes/dungeon/themes/crypt.tres"

const BRAZIER := KIT + "brazier_a.tscn"
const CANDELABRA := KIT + "candelabra.tscn"
const PILLARS := [KIT + "pillar_brick_a.tscn", KIT + "pillar_brick_b.tscn"]
const BROKEN := KIT + "pillar_broken_a.tscn"
const STATUES := [KIT + "statue_a.tscn", KIT + "statue_b.tscn"]
const ALTAR := KIT + "altar.tscn"
const DAIS := KIT + "dais_a.tscn"
const CLUTTER := [PROPS + "sarcophagus.tscn", PROPS + "tomb_slab.tscn", PROPS + "bone_pile.tscn",
		PROPS + "rubble.tscn", PROPS + "barrel.tscn", PROPS + "crate.tscn",
		PROPS + "skull_stack.tscn", PROPS + "weapon_rack.tscn"]
const CHEST := PROPS + "chest.tscn"
const THRONE := PROPS + "throne.tscn"

## `DungeonLayout.RoomType`, by name so a reader does not have to count.
const START := 0
const COMBAT := 1
const BOSS := 2
const TREASURE := 3
const STAIR := 4

## THE KIT IS BUILT TO A 4 m TILE and this crypt is drawn at `world_crypt.SCALE`, so a native
## pillar is three metres in an eight-metre room — short enough to read as furniture rather than
## as architecture. Everything is scaled by the same one number the level is.
const SCALE := 1.25
## How far inside the wall a prop may stand, metres. Half a doorway plus a body: closer than
## this and the player scrapes along it on the way past.
const INSET := 3.6
## And how far from a doorway. `world_crypt` puts a gate point at the far END of its stub, so
## the clearance is measured from there and covers the whole plug.
const DOOR_CLEAR := 5.0
## The lattice candidates are taken on — the room's own tile, scaled.
const STEP := 5.0
## No two pieces closer than this, whatever the lattice offers.
const APART := 4.0

## Roughly one clutter piece per this many square metres of floor. A crypt is not a warehouse:
## past this it stops reading as a room with things in it and starts reading as storage.
const M2_PER_PROP := 130.0
## HOW MANY SHADOW-CASTING LIGHTS A ROOM MAY HAVE. Every kit brazier and candelabra ships with
## `shadow_enabled`, which is right for the hand-built crypt because only the room the player is
## standing in is ever lit. Nothing gates a generated room yet, so a dozen streamed rooms would
## be rendering thirty shadow maps at once for rooms nobody is looking at — and the frame rate is
## a requirement here, not a nicety. One caster per room keeps the shafts and the pillar shadows
## that make the place read; the rest light without casting, which is invisible in a room that
## already has one.
const CASTERS_PER_ROOM := 1
## HOW FAR A ROOM LIGHT REACHES, metres, and why it is set here instead of taken from the theme.
## The kit's 14 m is measured against the hand-built crypt, whose rooms are one or two 20 x 12 m
## modules; a generated hall is up to 85 m long at `SCALE`, and three 14 m pools in it leave more
## floor dark than lit. A light is also the only thing down here that says where the walls are,
## so the reach is a readability number, not a mood one — the mood is the theme's colour and the
## fog, both of which are left alone.
const LIGHT_RANGE := 22.0
const LIGHT_ENERGY := 5.5
## WHERE A ROOM LIGHT STOPS BEING PAID FOR, metres from the camera. A 4 m wall does not occlude
## the room behind it the way an 8.5 m one did, so a top-down shot now holds seven or eight lit
## rooms instead of three and the frame time doubled with them. Godot has the lever for this on
## the light itself: `distance_fade_shadow` drops the shadow map for a light further away than
## this while the light keeps working, and the light itself then fades out entirely over
## FADE_BEGIN..+FADE_LENGTH. So the room you are fighting in casts, the rooms across the level
## still glow, and nothing renders a shadow cubemap for a brazier you can barely see.
##
## ONLY THE SHADOW HALF IS ARMED, and the light half is parked deliberately out of reach. Both
## distances are measured FROM THE CAMERA, and the camera rig's isometric dial can legitimately
## stand a hundred and twenty-five metres back (`camera_rig.framing_isometric`) — so a light fade
## tuned for the normal shot would switch the entire level off at the top of that dial, which is
## the same trap the depth fog fell into. Four hundred metres is past the level's own diagonal
## plus the furthest the dial can go, so the light itself never fades and the saving comes
## entirely from the shadow maps, which is where the cost was.
const FADE_SHADOW := 30.0
const FADE_BEGIN := 400.0
const FADE_LENGTH := 100.0

## The crypt theme, loaded once per room rather than once per piece.
static var _theme: Resource = null
static var _casters := 0


## Furnish one baked room. `poly` is its outline in the unit's own frame (metres, plan XZ), `y`
## the height of its floor, `params` the cell's own — type, area — and `doors` its gate points
## in the same frame. Returns how many pieces were placed.
static func furnish(room: Node3D, poly: PackedVector2Array, y: float, params: Dictionary,
		doors: PackedVector2Array, seed_value: int) -> int:
	if poly.size() < 3:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_theme = load(THEME) if ResourceLoader.exists(THEME) else null
	_casters = 0
	var type := int(params.get("type", COMBAT))
	var area := float(params.get("area_m2", 240.0))
	var spots := _lattice(poly, doors)
	if spots.is_empty():
		# a room too small to hold anything at arm's length from its own walls still has to be
		# LIT, so it gets its centre whatever the clearances say
		spots = PackedVector2Array([_centre(poly)])
	var used := PackedVector2Array()
	var n := 0
	n += _centrepiece(room, poly, used, y, type, rng)
	n += _lights(room, spots, used, y, area, rng)
	n += _cover(room, spots, used, y, area, type, rng)
	n += _clutter(room, spots, used, y, area, rng)
	return n


## THE LIGHT. One brazier per two hundred square metres, never fewer than two, spread as far
## apart as the free spots allow — a single lamp in the middle of a hall leaves its corners
## black, and the corners are where the archers stand.
static func _lights(room: Node3D, spots: PackedVector2Array, used: PackedVector2Array,
		y: float, area: float, rng: RandomNumberGenerator) -> int:
	var want := clampi(int(round(area / 130.0)) + 1, 3, 9)
	var n := 0
	for i in want:
		var at: Variant = _spread(spots, used, rng)
		if at == null:
			break
		var path: String = CANDELABRA if n % 3 == 2 else BRAZIER
		if _place(room, path, at, y, rng) != null:
			n += 1
	return n


## WHAT THE ROOM IS FOR, in one object at its middle. The boss gets a throne on a dais, the
## treasury an altar and a chest, the entrance a mourner to walk past. An ordinary fighting room
## is left clear on purpose: the middle of a combat room is where the fight is.
static func _centrepiece(room: Node3D, poly: PackedVector2Array, used: PackedVector2Array,
		y: float, type: int, rng: RandomNumberGenerator) -> int:
	var mid := _centre(poly)
	var n := 0
	match type:
		BOSS:
			if _place(room, DAIS, mid, y, rng, 0.0) != null:
				n += 1
			if _place(room, THRONE, mid, y + 0.45 * SCALE, rng, 0.0) != null:
				n += 1
			# flanked, which is what makes it read as a hall and not a room with a chair in it
			for s: Vector2 in _flank(poly, mid, 7.0):
				if _place(room, STATUES[rng.randi() % STATUES.size()], s, y, rng, 0.0) != null:
					n += 1
					used.append(s)
			used.append(mid)
		TREASURE:
			if _place(room, ALTAR, mid, y, rng, 0.0) != null:
				n += 1
			if _place(room, CHEST, mid + Vector2(0.0, 2.0), y, rng, 0.0) != null:
				n += 1
			used.append(mid)
		START:
			for s: Vector2 in _flank(poly, mid, 6.0):
				if _place(room, STATUES[0], s, y, rng, 0.0) != null:
					n += 1
					used.append(s)
	return n


## COVER. Pillars in a big room — a broken one every so often, so the row does not read as a
## colonnade nobody ever walked past.
static func _cover(room: Node3D, spots: PackedVector2Array, used: PackedVector2Array, y: float,
		area: float, type: int, rng: RandomNumberGenerator) -> int:
	if area < 300.0:
		return 0
	var want := clampi(int(area / 220.0), 1, 6)
	if type == TREASURE:
		want = mini(want, 2)
	var n := 0
	for i in want:
		var at: Variant = _spread(spots, used, rng)
		if at == null:
			break
		var path: String = BROKEN if rng.randf() < 0.22 else PILLARS[rng.randi() % PILLARS.size()]
		if _place(room, path, at, y, rng, 0.0) != null:
			n += 1
	return n


## EVERYTHING ELSE — the tombs, the bones, the rubble a crypt has lying about. Placed last, on
## whatever the lattice has left, and rotated freely: it is the only pass whose pieces do not
## have to line up with anything.
static func _clutter(room: Node3D, spots: PackedVector2Array, used: PackedVector2Array,
		y: float, area: float, rng: RandomNumberGenerator) -> int:
	var want := clampi(int(area / M2_PER_PROP), 1, 8)
	var n := 0
	for i in want:
		var at: Variant = _spread(spots, used, rng)
		if at == null:
			break
		if _place(room, CLUTTER[rng.randi() % CLUTTER.size()], at, y, rng) != null:
			n += 1
	return n


## THE CANDIDATE POINTS: the room's own tile lattice, inset from every wall and cleared of every
## doorway. `is_point_in_polygon` alone is not enough — a point one centimetre inside a wall is
## inside the polygon — so the inset is measured as a distance to the boundary itself.
static func _lattice(poly: PackedVector2Array, doors: PackedVector2Array) -> PackedVector2Array:
	var box := _bounds(poly)
	var out := PackedVector2Array()
	var x := box.position.x + STEP * 0.5
	while x < box.end.x:
		var z := box.position.y + STEP * 0.5
		while z < box.end.y:
			var p := Vector2(x, z)
			if Geometry2D.is_point_in_polygon(p, poly) and _edge_distance(p, poly) >= INSET:
				var clear := true
				for d: Vector2 in doors:
					if p.distance_to(d) < DOOR_CLEAR:
						clear = false
						break
				if clear:
					out.append(p)
			z += STEP
		x += STEP
	return out


## Take the free spot furthest from everything already placed, and record it. `null` when the
## room has run out of room, which is how every pass knows to stop.
static func _spread(spots: PackedVector2Array, used: PackedVector2Array,
		rng: RandomNumberGenerator) -> Variant:
	var best: Variant = null
	var best_d := APART
	for p: Vector2 in spots:
		var d := 1.0e9
		for u: Vector2 in used:
			d = minf(d, p.distance_to(u))
		# ties broken by the rng, so a symmetrical room does not fill one side up first
		d += rng.randf() * 0.5
		if d > best_d:
			best_d = d
			best = p
	if best != null:
		used.append(best)
	return best


static func _place(room: Node3D, path: String, at: Vector2, y: float, rng: RandomNumberGenerator,
		yaw := -1.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.position = Vector3(at.x, y, at.y)
	n.rotation.y = rng.randf_range(0.0, TAU) if yaw < 0.0 else yaw
	n.scale = Vector3.ONE * SCALE
	room.add_child(n)
	if path.begins_with(KIT) and _theme != null:
		# the roll is what decorrelates one pillar from the next — the kit derives its value
		# jitter, its moss bias and its variant from the same number
		Kit.dress(n, _theme, rng.randf(), y, path.get_file().get_basename())
	_budget_shadows(n)
	_persist(n, room)
	return n


## MAKE THE CHANGES SURVIVE THE PACK, and this is the trap the first version of this file fell
## into. `PackedScene.pack` records a property override on a node INSIDE an instance only if that
## node has an owner; `world_bake._own` deliberately stops at every instance, because owning the
## children of a nested unit scene wrote megabytes of redundant overrides. A prop is the case
## that rule was not written for: everything that makes it look right — the stone the kit dresses
## it in, the theme's light energy, the shadow budget — is a property of a node inside it, and
## without an owner every one of those was silently dropped and the crypt filled up with white
## blocks. A pillar is three nodes, so this costs lines, not megabytes.
static func _persist(n: Node, root: Node) -> void:
	for c: Node in n.get_children():
		c.owner = root
		_persist(c, root)


## Leave the first light in a room casting and take the shadow off the rest. Walks the instance
## because the light is a child of the kit piece, not the piece itself.
static func _budget_shadows(n: Node) -> void:
	if n is Light3D:
		var l := n as Light3D
		if _casters < CASTERS_PER_ROOM:
			_casters += 1
		else:
			l.shadow_enabled = false
		# only the sconces — anything that took the theme's colour and energy is claiming to be
		# "the light this dungeon lights itself by", and the altar's cold blue is not
		if l.has_meta("theme_light"):
			l.light_energy = LIGHT_ENERGY
			if l is OmniLight3D:
				(l as OmniLight3D).omni_range = LIGHT_RANGE
			elif l is SpotLight3D:
				(l as SpotLight3D).spot_range = LIGHT_RANGE
		l.distance_fade_enabled = true
		l.distance_fade_shadow = FADE_SHADOW
		l.distance_fade_begin = FADE_BEGIN
		l.distance_fade_length = FADE_LENGTH
	for c: Node in n.get_children():
		_budget_shadows(c)


## Two points either side of `mid` on the room's long axis, `d` metres out — where a pair of
## statues flanking a throne goes.
static func _flank(poly: PackedVector2Array, mid: Vector2, d: float) -> PackedVector2Array:
	var box := _bounds(poly)
	var along := Vector2(1.0, 0.0) if box.size.x >= box.size.y else Vector2(0.0, 1.0)
	var out := PackedVector2Array()
	for s: float in [-1.0, 1.0]:
		var p: Vector2 = mid + along * (d * s)
		if Geometry2D.is_point_in_polygon(p, poly) and _edge_distance(p, poly) >= 2.0:
			out.append(p)
	return out


static func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var d := 1.0e9
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return d


static func _centre(poly: PackedVector2Array) -> Vector2:
	var box := _bounds(poly)
	var mid := box.get_center()
	if Geometry2D.is_point_in_polygon(mid, poly):
		return mid
	var c := Vector2.ZERO
	for p: Vector2 in poly:
		c += p
	return c / float(poly.size())


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly:
		r = r.expand(p)
	return r

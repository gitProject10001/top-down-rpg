@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name Kit
extends Object
## The modular piece factory — THE Blender handoff contract for the crypt, and the one place
## where an abstract slot tag turns into actual geometry.
##
## `Kit.piece(name, theme, roll)` resolves in three steps, first hit wins:
##   1. THEME VARIANTS — `theme.pieces[name]`, picked by the stable `roll`. This is where a
##      dungeon gets its own look, and where fifteen pillar variants live. Data, not code.
##   2. KIT WRAPPER — `res://scenes/dungeon/kit/<name>.tscn`. Author it in the editor: root
##      carries the COLLISION shapes at the canonical footprint below, visual = a child instance
##      of your imported .blend — the same split the hub uses. Themeless art for every dungeon.
##   3. GREYBOX — built in code, sized/coloured by the theme if it says so, else by the consts
##      below. Means a half-finished theme still builds and the headless suite needs no art.
##
## So the art pass is: model the piece in Blender → either save a wrapper .tscn at the known
## path, or list it in a theme → done. Zero generator changes, collisions never live in the
## Blender file.
##
## CANONICAL FOOTPRINTS (origin at the BOTTOM CENTRE of the piece):
##   floor_slab    20 x 0.2 x 12   (one slab per room; its TOP is the walk surface at y=0)
##   wall_straight  4 x 3 x 0.5
##   wall_doorway   4 x 3 x 0.5 with a centred 2m-wide x 2.2m-tall opening
##   pillar         1 x 3 x 1
##   crate          1 x 1 x 1
##   torch          pole + warm OmniLight (no collision)
##   altar          2.4 x 0.8 x 2.4

const KIT_DIR := "res://scenes/dungeon/kit/"

const SIZES := {
	"floor_slab": Vector3(20.0, 0.2, 12.0),     # legacy whole-room slab; corridors use its height
	"floor_tile": Vector3(4.0, 0.2, 4.0),       # one per RoomShape tile — irregular rooms need it
	"wall_straight": Vector3(4.0, 3.0, 0.5),
	# THE BEVELLED CORNER and what is left of the two walls it cut into. The lengths come from
	# RoomShape rather than being typed here: RoomShape.span_of() is what every other consumer asks,
	# and a kit whose collider disagreed with the run it was built for would leave a slot in the wall.
	"wall_chamfer": Vector3(RoomShape.CHAMFER_DIAG, 3.0, 0.5),
	"wall_half": Vector3(RoomShape.CHAMFER_LEG, 3.0, 0.5),
	"pillar": Vector3(1.0, 3.0, 1.0),
	"crate": Vector3(1.0, 1.0, 1.0),
	"altar": Vector3(2.4, 0.8, 2.4),
	# A raised platform inside a room. The 0.6 is the whole design constraint in one number: it must
	# stay under MapPainter.FLOOR_MAX_Y (1.0) or the minimap reads the platform as a WALL, and it
	# must stay well under the step ring's 0.8 m so the walk surface is 36.9 degrees rather than the
	# 45 that CharacterBody3D's default floor_max_angle would refuse. Built by Kit.dais, not by the
	# greybox path — a plain box here would be a 0.6 m LEDGE, and nothing in this project climbs one.
	"dais": Vector3(4.0, 0.6, 4.0),
	# THE WALL UNDER A RAISED FLOOR. Its 1.8 m is what makes the map read it as masonry, while the
	# floor it carries is an ordinary 0.2 m tile that the map reads as floor however high it hangs —
	# which is exactly what each of them is. Build the pair as one solid mass instead and the map
	# loses the room's whole edge.
	"wall_riser": Vector3(4.0, RoomShape.LEVEL_RISE, 0.5),
	"table": Vector3(2.2, 0.78, 0.9),           # modelled asset — wrapper in scenes/dungeon/kit/
	"candelabra": Vector3(0.42, 1.5, 0.42),     # modelled asset — stands in for "torch"
	# Bridge the GAP between adjacent rooms. Authored along local X (the passage direction) and
	# rotated per axis, so they must be sized to the gap plus a little overlap into both doorways.
	"corridor_floor": Vector3(5.0, 0.2, 2.6),
	"corridor_wall": Vector3(5.0, 3.0, 0.5),
	# The courses stacked on a base wall. NOTE these are the ART modules; the base wall's COLLIDER is
	# the full DungeonLayout.WALL_HEIGHT and lives in the kit wrappers, so a wall's collision height
	# and `wall_straight`'s entry here legitimately disagree. See COURSE_TAGS in RoomDresser.
	"wall_band": Vector3(4.0, DungeonLayout.BAND_H, 0.5 + DungeonLayout.BAND_PROJ * 2.0),
	"wall_upper": Vector3(4.0, DungeonLayout.COURSE_H, 0.5),
	"wall_band_chamfer": Vector3(RoomShape.CHAMFER_DIAG, DungeonLayout.BAND_H, 0.5 + DungeonLayout.BAND_PROJ * 2.0),
	"wall_upper_chamfer": Vector3(RoomShape.CHAMFER_DIAG, DungeonLayout.COURSE_H, 0.5),
	"wall_cornice_chamfer": Vector3(RoomShape.CHAMFER_DIAG, DungeonLayout.CORNICE_H,
			0.5 + DungeonLayout.CORNICE_PROJ * 2.0),
	"wall_band_half": Vector3(RoomShape.CHAMFER_LEG, DungeonLayout.BAND_H, 0.5 + DungeonLayout.BAND_PROJ * 2.0),
	"wall_upper_half": Vector3(RoomShape.CHAMFER_LEG, DungeonLayout.COURSE_H, 0.5),
	"wall_cornice_half": Vector3(RoomShape.CHAMFER_LEG, DungeonLayout.CORNICE_H,
			0.5 + DungeonLayout.CORNICE_PROJ * 2.0),
	"wall_cornice": Vector3(4.0, DungeonLayout.CORNICE_H, 0.5 + DungeonLayout.CORNICE_PROJ * 2.0),
	"wall_vault": Vector3(4.0, 0.9, 2.1),
	# A breached upper course. Same module as wall_upper; it is a separate piece name only so the
	# dresser can PLACE one rather than roll for it.
	"wall_breach": Vector3(4.0, DungeonLayout.COURSE_H, 0.5),
	# The column's upper half, standing on a 1 x 3 x 1 pillar drum. No collider -- it is a course.
	"column_shaft": Vector3(1.0, 3.4, 1.0),
	# THE FLOOR INLAY, laid over a floor_tile. Y here is a real 2 cm of thickness, not a collider
	# height — these have no collider at all (see NO_COLLIDE). The entries exist so a missing .glb
	# greyboxes as something floor-shaped instead of Kit's Vector3.ONE default, which would put a
	# one-metre cube in the middle of the room.
	"floor_inlay_border": Vector3(4.0, 0.02, 0.76),
	"floor_inlay_corner": Vector3(4.0, 0.02, 4.0),
	"floor_inlay_threshold": Vector3(4.0, 0.02, 0.9),
	"floor_inlay_medallion": Vector3(2.96, 0.02, 2.96),
}

const COLORS := {
	"floor_slab": Color(0.33, 0.31, 0.36),
	"floor_tile": Color(0.33, 0.31, 0.36),
	"wall_straight": Color(0.42, 0.39, 0.45),
	"wall_chamfer": Color(0.42, 0.39, 0.45),
	"wall_half": Color(0.42, 0.39, 0.45),
	"wall_band_chamfer": Color(0.46, 0.43, 0.48),
	"wall_upper_chamfer": Color(0.44, 0.41, 0.46),
	"wall_cornice_chamfer": Color(0.48, 0.45, 0.5),
	"wall_band_half": Color(0.46, 0.43, 0.48),
	"wall_upper_half": Color(0.44, 0.41, 0.46),
	"wall_cornice_half": Color(0.48, 0.45, 0.5),
	"wall_doorway": Color(0.42, 0.39, 0.45),
	"pillar": Color(0.48, 0.45, 0.5),
	"crate": Color(0.45, 0.34, 0.22),
	"altar": Color(0.3, 0.24, 0.38),
	"dais": Color(0.36, 0.33, 0.39),
	"wall_riser": Color(0.40, 0.37, 0.43),
	"corridor_floor": Color(0.3, 0.28, 0.33),
	"corridor_wall": Color(0.42, 0.39, 0.45),
	"stair_flight": Color(0.38, 0.36, 0.41),
	"wall_band": Color(0.46, 0.43, 0.48),
	"wall_upper": Color(0.44, 0.41, 0.46),
	"wall_cornice": Color(0.48, 0.45, 0.5),
	"wall_vault": Color(0.4, 0.38, 0.43),
	"column_shaft": Color(0.48, 0.45, 0.5),
}

## Tags whose greybox is a MESH ONLY, no collision. Everything here sits above head height and
## projects inward; a collider on an overhang catches thrown objects and clips head-space for
## nothing. It also keeps "only the base wall collides" true in the greybox dungeon the headless
## suite builds, not just in the art-dressed one.
## The floor inlay is here for a DIFFERENT and stricter reason than the courses, and it is the one
## entry in this list that is load-bearing rather than tidy. MapPainter classifies floor-vs-wall per
## CollisionObject3D: a thin shape counts as floor only if nothing else in its own body is tall. Give
## an inlay a collider and it becomes a second body sitting on the same 4 m tile — at best redundant
## geometry in the map's union, at worst, if a variant ever grows past 1 m, a tile that flips to WALL
## and drops a carved room under verify_map's 33% truncation guard. Having no collider at all is not
## an optimisation here; it is what keeps the floor the greybox's floor.
const NO_COLLIDE := [
	"wall_band", "wall_upper", "wall_cornice", "wall_vault", "column_shaft", "wall_breach",
	"wall_band_chamfer", "wall_upper_chamfer", "wall_cornice_chamfer",
	"wall_band_half", "wall_upper_half", "wall_cornice_half",
	"floor_inlay_border", "floor_inlay_corner", "floor_inlay_threshold", "floor_inlay_medallion",
]


## ART THAT FACES +Z, turned round to face the room. The wall contract is "the face is
## authored on local -Z" (room_dresser.gd's border note states it as the contract every wall
## piece already uses); the ashlar/arcade family shipped facing +Z, so every upper course
## showed the room its BACK — relief lit inside-out and daylight through the joints. The turn
## lives on a child INSIDE a shell, because the dresser ASSIGNS rotation.y on whatever it
## places (room_dresser.gd:135) and a rotation on the root would not survive placement. Remove
## a name here when its art is re-exported facing -Z; nothing else has to change.
const FACES_BACKWARD := ["wall_upper"]


static func _faced(node: Node3D, piece_name: String) -> Node3D:
	if not piece_name in FACES_BACKWARD:
		return node
	var shell := Node3D.new()
	node.rotation.y = PI
	shell.add_child(node)
	return shell


## Meshes (and whole subtrees) the dressing pass must not touch. See `dress`.
const NO_PAINT := "no_paint"
## An OmniLight3D that wants the theme's colour/energy/range rather than the ones its scene authored.
const THEME_LIGHT := "theme_light"


## `theme` may be null and `roll` may be left at 0 — a bare `Kit.piece(name)` still builds the
## same greybox it always did, which is what the headless suite and the corridor builder use.
## `base_y` is how far above its room's floor this piece will stand — the stone shader needs it to
## keep grime and moss at the FLOOR rather than restarting them at the foot of every stacked course.
## Defaulted, so callers that place things on the ground say nothing.
static func piece(piece_name: String, theme: DungeonTheme = null, roll := 0.0,
		base_y := 0.0) -> Node3D:
	var node := _faced(_resolve(piece_name, theme, roll), piece_name)
	dress(node, theme, roll, base_y, piece_name)
	return node


static func _resolve(piece_name: String, theme: DungeonTheme, roll: float) -> Node3D:
	if theme != null and theme.has_variants(piece_name):
		var scene := theme.pick(piece_name, roll)
		if scene != null:
			return scene.instantiate()

	var path := KIT_DIR + piece_name + ".tscn"
	if ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate()

	match piece_name:
		"wall_doorway":
			return _doorway(theme)
		"torch":
			return _torch(theme)
		"key":
			return _key(theme)
		_:
			var size := _size_of(piece_name, theme)
			var color := _color_of(piece_name, theme)
			if piece_name in NO_COLLIDE:
				return _box_mesh(size, color)
			return _box_body(size, color)


## THE ONE PLACE A DUNGEON GETS ITS LOOK. Every kit piece passes through `piece()`, so this is the
## choke point for the two things a theme owns but a .tscn cannot know: hang `theme.material` on
## every stone MeshInstance3D as a `material_override` with the per-piece constants that stop forty
## copies of one wall reading identically, and retune any light that asked to follow the theme.
##
## Empty sockets degrade rather than error: no `theme.material` and pieces keep the material their
## .glb was imported with; no `theme_light` meta and a light keeps what its scene authored.
##
## Painting a DETACHED node is fine and is what happens: `material_override` and
## `set_instance_shader_parameter` are node state, not tree state, and the shader reads world
## position from MODEL_MATRIX at draw time, so it does not care that RoomDresser positions the piece
## afterwards.
##
## ONE SHARED MATERIAL RESOURCE FOR EVERYTHING, deliberately. Per-instance shader uniforms only work
## that way — a material per piece would defeat them — and Godot 4's Forward+ renderer auto-instances
## identical mesh+material pairs, so forty `wall_brick_a` copies collapse into one draw.
## `roll` < 0 means "no stable roll available here" — the shader then hashes the piece's own world
## origin instead, so a flight of stairs still differs from the one in the next room.
## `piece_name` is optional because not everything that gets dressed came from `piece()` — clutter is
## instantiated by RoomDresser straight from the theme. Without it there is simply no paint, which is
## the right default: a prop nobody named cannot have been given a colour.
static func dress(node: Node3D, theme: DungeonTheme, roll := -1.0, base_y := 0.0,
		piece_name := "") -> void:
	if node == null or theme == null:
		return
	# Resolved ONCE here rather than per node: the tint is a property of the piece, and looking it up
	# at every MeshInstance3D in a twenty-box staircase would be twenty dictionary probes for one
	# answer.
	_dress_walk(node, theme, _paint_params(roll), base_y, theme.tint_for(piece_name))


## WHAT IS EXEMPT, AND WHY EACH ONE MATTERS
##
##   torch_flame  — the silent one. DungeonRoom._flame_material() calls get_active_material(), which
##                  RETURNS material_override when one is set, then tests `is StandardMaterial3D`.
##                  A ShaderMaterial fails that test, returns null, and set_lit() quietly stops
##                  guttering every flame in the dungeon. It does not error; it just looks like a
##                  lighting bug three days later.
##   NO_PAINT     — anything that is not stone: the candelabra (DungeonBronze + DungeonTallow), the
##                  table (DungeonWood), the greybox torch's wooden pole, the emissive key whose
##                  amber is a GAMEPLAY signal paired with DungeonDoor.LOCKED_TINT.
##
## Both skip the WHOLE SUBTREE, so marking a root is enough.
##
## Not listed because they never come through here at all: the return portal and DungeonDoor (added
## directly by the generator), theme clutter (instantiated by RoomDresser), and the non-marker
## children of a room template (kept as authored by RoomBuilder). Those are deliberate holes — a
## template's hand-placed props should stay as the author left them. If clutter ever wants painting
## the honest fix is a second `theme.clutter_material`, not a wider walk here.
static func _dress_walk(node: Node, theme: DungeonTheme, params: Vector4, base_y: float,
		tint: Vector4) -> void:
	if node.has_meta(NO_PAINT) or node.has_meta("torch_flame"):
		# A FLAME MUST NOT CAST A SHADOW, and getting this wrong produced the strangest artefact of
		# the whole lighting pass: a hard black disc a metre across, dead centre of the brightest
		# pool of light in the room.
		#
		# It is pure projection arithmetic. A candelabra's OmniLight sits at y = 1.55 and its outer
		# flame boxes at y = 1.49 — six centimetres below the light. An occluder that close to a
		# point source is magnified by the ratio of the distances, so a 5.5 cm box throws
		# 5.5 cm x (1.55 / 0.06) = 1.4 m of shadow onto the floor beneath it. The brazier does the
		# same at 7x. Nothing was wrong with the shadow maps; they were correctly rendering the
		# shadow of the fire.
		#
		# And fire does not cast shadows. These meshes are emissive stand-ins for flame, so the
		# right answer is not a bias tweak or moving the light — it is that they were never
		# supposed to be occluders. Done here rather than in the four .tscn files so that a themed
		# flame from any future kit is covered by the meta it already has to carry.
		if node is GeometryInstance3D and node.has_meta("torch_flame"):
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	if node is MeshInstance3D and theme.material != null:
		# ORDER MATTERS: set_instance_shader_parameter is a no-op on a mesh with no override, so the
		# material has to be hung first.
		(node as MeshInstance3D).material_override = theme.material
		(node as MeshInstance3D).set_instance_shader_parameter("piece_params", params)
		(node as MeshInstance3D).set_instance_shader_parameter("piece_base", base_y)
		(node as MeshInstance3D).set_instance_shader_parameter("piece_tint", tint)
	# A LIGHT THAT ASKED TO FOLLOW THE THEME. Opt-in, not blanket: the altar's OmniLight is a cold
	# blue on purpose and a theme has no business flattening it to torch amber. Only art that says
	# `theme_light` is claiming to be "the sconce this dungeon lights itself by".
	#
	# RANGE AND ATTENUATION ARE NAMED PER TYPE, which is the whole reason this is a type switch and
	# not one branch. `omni_range` does not exist on a SpotLight3D, and Object.set on a property
	# that is not there fails SILENTLY — so an omni sconce converted to a spot would keep taking the
	# theme's colour and energy and quietly stop taking its range. That is precisely the class of
	# regression the theme_light meta was introduced to kill, reappearing one level down.
	elif node is Light3D and node.has_meta(THEME_LIGHT):
		var l := node as Light3D
		l.light_color = theme.light_color
		l.light_energy = theme.light_energy
		if l is OmniLight3D:
			(l as OmniLight3D).omni_range = theme.light_range
			(l as OmniLight3D).omni_attenuation = theme.light_attenuation
		elif l is SpotLight3D:
			(l as SpotLight3D).spot_range = theme.light_range
			(l as SpotLight3D).spot_attenuation = theme.light_attenuation
	for c in node.get_children():
		_dress_walk(c, theme, params, base_y, tint)


## The per-piece constants, packed into one vec4 because Godot gives instance uniforms a small fixed
## buffer and four named scalars would burn four slots for nothing.
##   x, y = seeds   z = value jitter [-1, 1]   w = moss bias [0, 1)
##
## Derived from the SAME stable roll that picked the variant, which is keyed to (seed, cell, tag,
## position) — so this obeys edit locality by construction and the determinism suites cannot see it.
## The odd multipliers decorrelate the components, or a piece's moss would be locked to its variant.
static func _paint_params(roll: float) -> Vector4:
	if roll < 0.0:
		return Vector4(-1.0, -1.0, -1.0, -1.0)     # the shader's "hash my own origin" sentinel
	return Vector4(roll, fmod(roll * 7.31, 1.0), fmod(roll * 13.7, 1.0) * 2.0 - 1.0,
			fmod(roll * 29.3, 1.0))


## A MODULE STRETCHED TO A LENGTH. One builder for the wall run and for every course above it,
## because they differ only in the size entry they start from — a band is the same run at 0.3 m tall
## with a projection, a cornice the same again.
##
## Procedural like Kit.stair and for the same reason: a piece sized to its room cannot be a fixed
## .tscn, and the moment it could be, there would be one per length. The Y and Z come from the
## module's own SIZES entry so the run keeps the profile its neighbours have; only X moves.
##
## THE BASE WALL TAKES THE SHELL HEIGHT, NOT THE ART MODULE'S. Kit.SIZES["wall_straight"] is 3 m
## because it describes one masonry course, while the shipped wrapper's collider is the full
## WALL_HEIGHT — a disagreement that file already documents. A greybox run at 3 m would be a wall you
## can see over standing exactly where a 6.8 m one stands either side of it.
static func run_piece(module: String, length: float, theme: DungeonTheme = null) -> Node3D:
	var size := _size_of(module, theme)
	size.x = length
	var color := _color_of(module, theme)
	if module in NO_COLLIDE:
		var deco := _faced(_box_mesh(size, color), module)
		dress(deco, theme, 0.0, 0.0, module)
		return deco
	# AUTHORED ART AT THIS EXACT LENGTH, IF THERE IS ANY. A run's whole reason for existing is to
	# carry a feature across the tile joints, and a stretched box carries nothing — so a wrapper at
	# `<module>_run<N>` wins over the greybox whenever someone has drawn one. Any other length still
	# builds, as a box, which is the same degradation every unthemed piece in this kit makes.
	var runs := int(round(length / RoomShape.TILE))
	var authored := KIT_DIR + module + "_run" + str(runs) + ".tscn"
	if ResourceLoader.exists(authored):
		var art := _faced((load(authored) as PackedScene).instantiate() as Node3D, module)
		dress(art, theme, 0.0, 0.0, module)
		return art
	var node := _box_body(size, color)
	# THE COLLIDER IS THE WHOLE SHELL AND THE MESH IS ONE COURSE, which is the kit's contract and not
	# a detail — Kit.SIZES' own comment says a base wall's collision height and its size entry
	# legitimately disagree, because the courses above it are separate pieces that carry no collider
	# and are veiled per frame.
	#
	# Built as one 6.8 m box first, and _cutaway_suite caught it immediately: a 16 m solid standing
	# to full shell height IS between the player and the lens, and it had swallowed the very course
	# pieces whose collider-free-ness is what makes the diorama cut provably gameplay-neutral. The
	# mesh stays one course tall; only the shape grows.
	if module == "wall_straight":
		for c in node.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var bs := (c as CollisionShape3D).shape as BoxShape3D
				bs.size.y = DungeonLayout.WALL_HEIGHT
				(c as CollisionShape3D).position.y = DungeonLayout.WALL_HEIGHT * 0.5
	var faced := _faced(node, module)
	dress(faced, theme, 0.0, 0.0, module)
	return faced


static func _size_of(piece_name: String, theme: DungeonTheme) -> Vector3:
	var fallback: Vector3 = SIZES.get(piece_name, Vector3.ONE)
	return theme.size_for(piece_name, fallback) if theme else fallback


static func _color_of(piece_name: String, theme: DungeonTheme) -> Color:
	var fallback: Color = COLORS.get(piece_name, Color(0.5, 0.5, 0.5))
	return theme.color_for(piece_name, fallback) if theme else fallback


## A collidable greybox: StaticBody3D (world layer 1) + box mesh + box shape, origin bottom-centre.
static func _box_body(size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	mesh.mesh = box
	mesh.position.y = size.y * 0.5
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position.y = size.y * 0.5
	body.add_child(shape)
	return body


## The same greybox with no collision at all — see NO_COLLIDE. Returns a Node3D holder rather than a
## bare MeshInstance3D so the caller can hang metadata on the piece the way it does for every other.
static func _box_mesh(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	mesh.mesh = box
	mesh.position.y = size.y * 0.5
	root.add_child(mesh)
	return root


## Wall segment with a centred 2m x 2.2m opening: two jambs + a lintel, one body.
static func _doorway(theme: DungeonTheme = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var color := _color_of("wall_doorway", theme)
	var h := DungeonLayout.WALL_HEIGHT
	for sx in [-1.5, 1.5]:                                  # jambs: 1m wide, full wall height
		body.add_child(_sub_box(Vector3(1.0, h, 0.5), Vector3(sx, h * 0.5, 0.0), color))
	body.add_child(_sub_box(Vector3(2.0, 0.8, 0.5), Vector3(0.0, 2.6, 0.0), color))   # lintel
	# THE SPANDREL. The 2 x 2.2 m clear opening is the gameplay contract (see wall_door_brick_a.tscn)
	# and does NOT scale with the wall — a human-scale door in a monumental wall is the whole point.
	# So a taller wall grows masonry ABOVE the lintel. Leave this out and the greybox doorway is a
	# 3.8 m hole you can walk a projectile through.
	var spandrel := h - 3.0
	if spandrel > 0.01:
		body.add_child(_sub_box(Vector3(2.0, spandrel, 0.5),
				Vector3(0.0, 3.0 + spandrel * 0.5, 0.0), color))
	return body


static func _sub_box(size: Vector3, at: Vector3, color: Color) -> Node3D:
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	mesh.mesh = box
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	holder.position = at
	holder.add_child(mesh)
	holder.add_child(shape)
	return holder


## A flight of steps climbing `rise` over `run`, `width` across, built along local +X with its
## bottom at local (−run/2, 0) and its top at (+run/2, rise). Origin at the middle of the flight,
## on the lower floor.
##
## The VISUAL is discrete steps; the COLLIDER is one smooth ramp. That split is deliberate:
## CharacterBody3D does not climb ledges, so stepped colliders would stop the player dead at the
## first riser, while a ramp well under floor_max_angle is walked up with no special casing at all.
##
## The `color.darkened()` tread banding below is overwritten when a theme paints this. That is
## accepted, not overlooked: the stone shader's world-space grunge breaks the treads up better than
## a fixed two-tone stripe did, and it does not repeat identically on every flight in the dungeon.
## `landing` reserves the last stretch of the run as FLAT floor at the top height, instead of
## climbing the whole way. A flight that tops out exactly at the room edge is the bug this closes:
## the passage's floor strip is longer than the gap it spans and overhangs half a metre back into
## the room, so its top surface stood ~0.3 m proud of a flight that was still climbing underneath
## it. Measured, a player-shaped body walked up the middle and stopped dead at 9.19 m of a 10 m run,
## every seed. move_and_slide has no step-up, so a 0.3 m lip across the only exit is a wall.
##
## Zero for the gallery ramps, which meet a level floor exactly and want no landing.
static func stair(run: float, rise: float, width: float, theme: DungeonTheme = null,
		landing := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var color := _color_of("stair_flight", theme)

	# HOW MANY STEPS, from the RUN as well as the rise. Taken from the rise alone, a flight's step
	# count was fixed the moment its height was — so a 20 m hall and a 44 m one climbing the same
	# 8 m storey both got 20 steps, and the long one's treads came out 2.2 m deep. A step you can
	# stand two of yourself on is not a step, it is a terrace, and the profile stopped reading as a
	# staircase from the side long before that.
	#
	# 0.4 m of rise or 1 m of run per step, whichever asks for more, floored at 4 so a shallow flight
	# is still a flight. Both are monumental rather than domestic — the crypt's stairs are meant to be
	# processional — but a metre of tread is a stride and 2.2 m is a jump. Verified inert on both
	# shipped callers: the stair room's 20 m run gives 20 steps as it did, and the gallery ramp's 4 m
	# run over 1.2 m gives 4, which is what maxi(4, ...) was already producing from the rise.
	# The CLIMB is the run minus the landing; everything below measures against it, so a flight with
	# a landing is the same staircase with its last stretch flat rather than a compressed one.
	var climb_run := maxf(run - landing, 0.5)
	var steps := maxi(4, int(round(maxf(rise / 0.4, climb_run / 1.0))))
	var depth := climb_run / steps
	for i in steps:
		# Each step is a solid block from the floor up to its own tread, so the profile reads as a
		# staircase from the side rather than a row of floating slabs. Tread height is taken at the
		# step's CENTRE (i + 0.5), which is exactly where the ramp collider is — take it at (i + 1)
		# and every tread sits half a step proud of the surface the player actually walks on.
		var h := rise * (i + 0.5) / float(steps)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(depth, h, width)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.darkened(0.04 * (i % 2))     # faint tread banding, reads the climb
		box.material = mat
		mesh.mesh = box
		mesh.position = Vector3(-run * 0.5 + depth * (i + 0.5), h * 0.5, 0.0)
		body.add_child(mesh)

	# The landing itself: one solid block from the floor to the top height, filling the last stretch.
	if landing > 0.0:
		var pad_mesh := MeshInstance3D.new()
		var pad_box := BoxMesh.new()
		pad_box.size = Vector3(landing, rise, width)
		var pad_mat := StandardMaterial3D.new()
		pad_mat.albedo_color = color
		pad_box.material = pad_mat
		pad_mesh.mesh = pad_box
		pad_mesh.position = Vector3(run * 0.5 - landing * 0.5, rise * 0.5, 0.0)
		body.add_child(pad_mesh)

		var pad := CollisionShape3D.new()
		var pad_bs := BoxShape3D.new()
		pad_bs.size = Vector3(landing, 0.6, width)
		pad.shape = pad_bs
		pad.position = Vector3(run * 0.5 - landing * 0.5, rise - 0.3, 0.0)   # top face AT `rise`
		body.add_child(pad)

	var slope := atan2(rise, climb_run)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(sqrt(climb_run * climb_run + rise * rise), 0.6, width)
	shape.shape = bs
	# top face of the tilted box passes through both ends of the CLIMB. Shifted back by half the
	# landing, because the climb no longer occupies the whole run and the box is centred on it.
	shape.transform = Transform3D(Basis(Vector3(0, 0, 1), slope),
			Vector3(-landing * 0.5, rise * 0.5, 0))
	shape.position -= Vector3(0, 0.3 / cos(slope), 0)         # sink it so the surface is the tread
	body.add_child(shape)
	# A flight is sized to its room so it cannot be a kit piece, which means it does not come through
	# piece() and has to ask for its own coat of paint. No stable roll reaches here, so the shader
	# hashes the flight's world origin instead.
	dress(body, theme)
	return body


## A STEPPED MOUND standing `rise` above the floor on a `tile` square, with a flat `top` square to
## put something on. Origin at the centre of its tile, on the lower floor.
##
## Same split as stair() and for the same reason — discrete steps to look at, one smooth surface to
## walk on — but the surface is a FRUSTUM rather than a tilted box, because the whole point of this
## piece is that it is climbable from every direction. Enemies have no navmesh and no step logic
## (enemy.gd flattens to_player.y and steers straight at it), so a platform with one flight would be
## a perch the player could stand on and never be followed onto. Four sloped faces means whichever
## way something walks at it, it walks up it.
##
## THE TIER WIDTHS ARE NOT A FREE CHOICE. Spacing them evenly from `tile` down to `top` is what puts
## the frustum through the MIDDLE of every tread — at 4.0 / 3.2 / 2.4 over a 0.6 m rise the surface
## crosses half-width 1.73 at the first tread (which spans 1.6 to 2.0) and 1.47 at the second (1.2
## to 1.6), and meets the tile edge at y = 0 and the flat top at y = rise exactly. Pick the widths
## any other way and the walk surface either floats above the bottom step or sinks under the top.
##
## The corners are the SHALLOWEST approach, not the steepest: the diagonal run is sqrt(2) times the
## face run for the same rise, so a 36.9-degree face is a 27.9-degree corner. Whatever walks at this
## thing has an easier time the further it is from square-on.
static func dais(tile: float, rise: float, top: float, theme: DungeonTheme = null) -> StaticBody3D:
	const TIERS := 3
	var body := StaticBody3D.new()
	body.name = "Dais"
	body.collision_layer = 1
	body.collision_mask = 0
	var color := _color_of("dais", theme)

	for i in TIERS:
		# Each tier is solid from the floor up to its own tread, so the profile reads as a mound cut
		# in steps rather than as stacked plates — the same reason stair() builds solid blocks.
		var w: float = lerpf(tile, top, float(i) / float(TIERS - 1))
		var h: float = rise * (i + 1) / float(TIERS)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w, h, w)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.darkened(0.04 * (i % 2))
		box.material = mat
		mesh.mesh = box
		mesh.position.y = h * 0.5
		body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	var hb: float = tile * 0.5
	var ht: float = top * 0.5
	hull.points = PackedVector3Array([
		Vector3(-hb, 0.0, -hb), Vector3(hb, 0.0, -hb),
		Vector3(hb, 0.0, hb), Vector3(-hb, 0.0, hb),
		Vector3(-ht, rise, -ht), Vector3(ht, rise, -ht),
		Vector3(ht, rise, ht), Vector3(-ht, rise, ht),
	])
	shape.shape = hull
	body.add_child(shape)
	# Sized to its tile rather than looked up as a kit piece, so like a flight it never comes through
	# piece() and has to ask for its own coat of paint.
	dress(body, theme)
	return body


## A key pickup: a small glowing token on a plinth-height float, plus its own light so it is
## visible from across a dark room. Area3D, not a body — the player walks onto it.
static func _key(theme: DungeonTheme = null) -> Area3D:
	var area := Area3D.new()
	# The key's amber is not decoration, it is the pairing with the gate it opens (DungeonDoor.
	# LOCKED_TINT). A stone coat would delete a gameplay signal, so the whole pickup opts out.
	area.set_meta(NO_PAINT, true)
	area.set_script(load("res://scripts/dungeon/dungeon_key.gd"))
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	shape.shape = sphere
	shape.position.y = 0.8
	area.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.42, 0.16)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DungeonDoor.LOCKED_TINT   # same amber as the gate it opens: read the pairing
	mat.emission_enabled = true
	mat.emission = DungeonDoor.LOCKED_TINT
	mat.emission_energy_multiplier = 2.4
	box.material = mat
	mesh.mesh = box
	mesh.position.y = 0.85
	mesh.rotation = Vector3(0.0, 0.0, PI * 0.25)
	area.add_child(mesh)

	var light := OmniLight3D.new()
	light.light_color = DungeonDoor.LOCKED_TINT
	light.light_energy = 1.1
	light.omni_range = 5.0
	light.position.y = 0.9
	area.add_child(light)
	return area


## Wall torch: thin pole + warm omni (shadowless, like the hub's fire lights). No collision.
## Colour/energy/range come from the theme — a crypt burns amber, an ice vault could burn blue.
static func _torch(theme: DungeonTheme = null) -> Node3D:
	var root := Node3D.new()
	# Wood and fire, not stone — and crypt.tres maps wall_anchor to the modelled candelabra anyway,
	# so this greybox only ever stands in for a theme that has no light-mount art yet.
	root.set_meta(NO_PAINT, true)
	var pole := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 1.3, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.2, 0.16)
	box.material = mat
	pole.mesh = box
	pole.position.y = 0.65
	root.add_child(pole)
	var flame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.2, 0.25, 0.2)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.7, 0.3)
	fmat.emission_enabled = true
	fmat.emission = theme.flame_color if theme else Color(1.0, 0.62, 0.25)
	fmat.emission_energy_multiplier = theme.flame_energy if theme else 2.2
	fm.material = fmat
	flame.mesh = fm
	flame.position.y = 1.42
	flame.set_meta("torch_flame", true)     # DungeonRoom dims flames with the room's lights
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = theme.light_color if theme else Color(1.0, 0.75, 0.45)
	light.light_energy = theme.light_energy if theme else 1.5
	light.omni_range = theme.light_range if theme else 7.0
	light.omni_attenuation = theme.light_attenuation if theme else 1.6
	light.position.y = 1.5
	root.add_child(light)
	return root

extends Node3D
## THE FOLIAGE BENCH. Every dial that shapes a bush or a tree, in one panel, next to the thing it
## shapes — including the ones that live in Blender.
##
##   Godot_v4.6.3-stable_win64_console.exe --path . res://scenes/dev/foliage_lab.tscn
##
## WHY THIS SCENE EXISTS, AND WHAT MAKES IT DIFFERENT FROM THE OTHER LOOK-DEVS.
##
## Foliage is authored on BOTH sides of the pipeline, and that is the whole problem with tuning it:
##
##   Blender (tools/make_foliage_cards.py)     Godot (materials + BushPatch)
##   ---------------------------------------   ------------------------------------
##   card size, count, canopy radius           wind strength / height / speed
##   branch count, length, spread              alpha_cut and its distance falloff
##   leaf atlas: count, size, droop            wrap, shadow tint, saturation
##   vertex colour ramp, normal pivot          scatter count, clumping, scale, sink
##
## A panel that only reached the right-hand column would leave half the shape unreachable, and the
## usual answer -- alt-tab to Blender, rebuild, re-import, look again -- is slow enough that nobody
## does it twice. So the GEOMETRY section drives the real generator: it launches Blender headless
## with the dials as arguments, has it export in the same session, and loads the .glb back through
## GLTFDocument at RUNTIME. No editor import, no restart, and no second copy of the generator's
## maths living in GDScript to drift away from the one that ships.
##
## The environment is lifted from main.tscn with duplicate(true) rather than authored here, per
## docs/anime-look-todo.md sec A3: "a look-dev scene that does not run the game's own post stack is
## not a look-dev scene -- it is a second look, drifting."

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const ScatterField := preload("res://addons/foliage_brush/nodes/scatter_field.gd")
const TerrainField := preload("res://scripts/terrain_field.gd")

const PIECES := ["veg_leaf_bush", "veg_leaf_bush_b", "veg_leaf_bush_c",
				 "veg_leaf_tree", "veg_leaf_tree_b"]
const BLENDER := "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"

## Matches DIAL in tools/make_foliage_cards.py. 1.0 reproduces the authored plants exactly.
var _dials := {
	"card_scale": 1.0, "card_density": 1.0, "canopy": 1.0,
	"limbs": 1.0, "limb_len": 1.0, "spread": 1.0,
	"leaf_density": 1.0, "leaf_size": 1.0, "droop": 1.0, "pivot_k": 1.0,
	# A multiplier on levels of ramification, rounded: 4 levels x 0.75 = 3. It is the most
	# expensive dial in the panel — each extra level roughly doubles the tip count, and every tip
	# carries a lobe of cards — so it is also the first one to reach for when trimming cost.
	"depth": 1.0,
}

## Every key above must exist in DIAL in tools/make_foliage_cards.py, or the slider silently does
## nothing: the generator ignores arguments it does not recognise.
const GENERATOR := "res://tools/make_foliage_cards.py"

var _scatter := {"count": 40, "clump_size": 3.2, "scale_min": 1.0, "scale_max": 2.0, "sink": 0.06}

## TERRAIN DIALS. Floats throughout, including the ones that are really an integer or a flag, so the
## whole dictionary saves and restores through one loop the way _dials and _scatter already do.
##
## `max_slope` at 30 is the important default. This project has no navmesh and no step logic, so a
## face over CharacterBody3D's 45 degrees is a trap an enemy never escapes; 30 leaves margin under
## the 35 that scripts/dungeon/gameplay/room_shape.gd:219 caps its own ramps at. The Cliff brush is
## how you opt out of it deliberately, per stroke.
##
## The noise defaults are probe_cliff.gd:154's, which is the one parameter set in this repo already
## known to read as rolling ground.
var _terra := {
	"strength": 0.25, "max_slope": 30.0, "lake_depth": 1.6, "overlay": 0.0,
	"noise_seed": 5.0, "noise_freq": 0.018, "noise_octaves": 2.0, "noise_amp": 3.2,
}

## Heights are too big for the bench's ConfigFile and have no business in .tscn text, so they get
## their own binary file. EXPORT writes the res:// copy, which is the one that can be checked in.
const TERRAIN_STATE := "user://foliage_lab_terrain.dat"
const TERRAIN_EXPORT := "res://scenes/dev/terrain_lab.dat"

var _specimens: Node3D
var _patch: MultiMeshInstance3D
var _log: RichTextLabel
var _leaf_bush: ShaderMaterial
var _leaf_tree: ShaderMaterial
var _busy := false
var _unsaved: Array[String] = []


## WHERE THE BENCH REMEMBERS ITSELF.
##
## A tuning session that resets to defaults every time you open it is not a bench, it is a demo:
## the whole activity is coming back tomorrow and pushing the same slider a bit further. So the
## lab's own state — geometry dials, scatter, and every grass parameter — is written to user:// on
## every change and read back on load.
##
## It deliberately does NOT persist the leaf MATERIALS. Those are project files with their own save
## button, and a bench that quietly rewrote them on exit would edit the game without being asked.
## Anything the bench remembers is the bench's; anything that ships goes through a Save button.
const LAB_STATE := "user://foliage_lab.cfg"

## Grass parameters the bench remembers. Its own field, so unlike SAVE GRASS this one keeps layout
## too — the bench's rectangle is a workbench, not a shipping decision.
const GRASS_STATE := ["region_size", "count", "rng_seed"]


func _ready() -> void:
	_leaf_bush = load("res://assets/materials/painted_foliage_leaf_bush.tres")
	_leaf_tree = load("res://assets/materials/painted_foliage_leaf_tree.tres")
	_load_state()
	_lift_environment()
	_specimens = Node3D.new()
	add_child(_specimens)
	_patch = MultiMeshInstance3D.new()
	_patch.position = Vector3(0.0, 0.0, 9.0)
	_patch.material_override = _leaf_bush
	_patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_patch)
	_layers = Node3D.new()
	_layers.name = "PaintedLayers"
	add_child(_layers)
	_load_terrain()
	_rebuild_specimens()
	_rebuild_patch()
	_build_panel()


## The ground the bench was left with, restored before anything is placed on it. Falls back to the
## checked-in res:// copy when there is no user file yet, so a fresh machine opens on the same
## terrain the repo has rather than on a flat plane.
func _load_terrain() -> void:
	var t := _terrain()
	if t == null:
		return
	t.max_slope_deg = float(_terra.max_slope)
	_apply_overlay()
	for path in [TERRAIN_STATE, TERRAIN_EXPORT]:
		if t.load_from(path):
			print("[FOLIAGE] terrain restored from %s" % path)
			_reseat(true)
			return


func _save_terrain() -> void:
	var t := _terrain()
	if t != null and autosave:
		t.save_to(TERRAIN_STATE)


func _apply_overlay() -> void:
	var t := _terrain()
	if t != null:
		t.material().set_shader_parameter("overlay", _terra.overlay > 0.5)


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAB_STATE) != OK:
		return
	for k: String in _dials.keys():
		_dials[k] = cfg.get_value("dials", k, _dials[k])
	for k: String in _scatter.keys():
		_scatter[k] = cfg.get_value("scatter", k, _scatter[k])
	for k: String in _terra.keys():
		_terra[k] = cfg.get_value("terrain", k, _terra[k])
	# Children run _ready() BEFORE their parent, so the Grass node has already built itself from the
	# scene's defaults by the time this runs. Restoring the values is only half the job — without
	# the rebuild the panel would show yesterday's numbers over today's default mesh.
	var g := get_node_or_null("Grass") as GrassPatch
	if g:
		for k: String in GRASS_KEYS + GRASS_STATE:
			# has_section_key first: passing null as get_value's default counts as NO default, and
			# it errors on any key an older state file predates — which every new dial does.
			if cfg.has_section_key("grass", k):
				g.set(k, cfg.get_value("grass", k))
		g.rebuild()
	print("[FOLIAGE] restored bench state from %s" % LAB_STATE)


func _save_state() -> void:
	var cfg := ConfigFile.new()
	for k: String in _dials.keys():
		cfg.set_value("dials", k, _dials[k])
	for k: String in _scatter.keys():
		cfg.set_value("scatter", k, _scatter[k])
	for k: String in _terra.keys():
		cfg.set_value("terrain", k, _terra[k])
	var g := get_node_or_null("Grass") as GrassPatch
	if g:
		for k: String in GRASS_KEYS + GRASS_STATE:
			cfg.set_value("grass", k, g.get(k))
	cfg.save(LAB_STATE)


## Called by every knob in the panel. ConfigFile.save on a file this small is far cheaper than the
## rebuild that triggered it, so there is nothing to gain by debouncing.
func _touch() -> void:
	_save_state()


## OFF FOR HARNESSES. scripts/dev/shot_terrain.gd drives this bench for real — it sculpts, paints and
## then quits — and every one of those goes through the same autosave a human session does. Without
## this, taking a verification shot would silently overwrite whatever terrain the user had left in
## the bench, which is a tool destroying the work it exists to check.
var autosave := true


func _exit_tree() -> void:
	if not autosave:
		return
	_save_state()
	_save_terrain()


## The game's own environment and post stack, copied rather than re-authored.
func _lift_environment() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var here := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and here:
		here.environment = we.environment.duplicate(true)
	var grade := main.get_node_or_null("PainterlyGrade")
	if grade:
		main.remove_child(grade)
		grade.owner = null      # else it still claims main.tscn as its owner and Godot complains
		add_child(grade)
		grade.visible = true
	main.queue_free()


# ---------------------------------------------------------------- specimens and scatter
func _runtime_mesh(stem: String) -> Mesh:
	"""Load a .glb straight off disk, bypassing the import pipeline.

	This is what lets the Rebuild button show its result without an editor reimport: Blender has
	just overwritten the file, and res:// still points at the cached .scn from the last import."""
	var abs_path := ProjectSettings.globalize_path("res://assets/models/%s.glb" % stem)
	if not FileAccess.file_exists(abs_path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(abs_path, state) != OK:
		return null
	var scene := doc.generate_scene(state)
	var mesh := _first_mesh(scene)
	scene.queue_free()
	return mesh


static func _first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _rebuild_specimens() -> void:
	for c in _specimens.get_children():
		c.queue_free()
	var x := -6.0
	var tris := 0
	for stem: String in PIECES:
		var mesh := _runtime_mesh(stem)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(x, 0.0, 0.0)
		mi.material_override = _leaf_tree if stem.contains("tree") else _leaf_bush
		_specimens.add_child(mi)
		var arrays := mesh.surface_get_arrays(0)
		tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		x += 3.0
	_say("specimens rebuilt — %d tris across %d pieces" % [tris, _specimens.get_child_count()])


func _rebuild_patch() -> void:
	var mesh := _runtime_mesh("veg_leaf_bush_b")
	if mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	# The SAME scatter the game uses, not a lab copy — so what is tuned here is what ships.
	# Read out as floats first: the dials live in a Dictionary, so every value arrives as a Variant
	# and an inferred local would refuse to type.
	var lo := float(_scatter.scale_min)
	var hi := float(_scatter.scale_max)
	var sink := float(_scatter.sink)
	var spots := ScatterField.clumped_points(rng, Vector2(16.0, 10.0), int(_scatter.count),
			float(_scatter.clump_size), [] as Array[Rect2])
	mm.instance_count = spots.size()
	for i in spots.size():
		var s := rng.randf_range(lo, hi)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
		var drop := -sink * rng.randf_range(0.5, 1.5)
		mm.set_instance_transform(i, Transform3D(b, Vector3(spots[i].x, drop, spots[i].y)))
		mm.set_instance_color(i, Color(1.0 + rng.randf_range(-0.14, 0.14),
									   1.0 + rng.randf_range(-0.07, 0.07),
									   1.0 + rng.randf_range(-0.14, 0.14)))
	_patch.multimesh = mm
	_say("patch: %d plants" % mm.instance_count)


# ---------------------------------------------------------------- the Blender round trip
func _rebuild_in_blender() -> void:
	if _busy:
		return
	if not FileAccess.file_exists(BLENDER):
		_say("[color=#ff8080]Blender not found at %s — edit BLENDER in this script[/color]" % BLENDER)
		return
	_busy = true
	_say("running Blender…")
	# OS.execute BLOCKS, so without yielding a frame first the message above never reaches the
	# screen — the panel simply freezes for several seconds with no explanation.
	await get_tree().process_frame
	var args := PackedStringArray(["-b", "--python",
			ProjectSettings.globalize_path(GENERATOR), "--", "--export"])
	for k: String in _dials.keys():
		args.append("--%s=%.4f" % [k.replace("_", "-"), _dials[k]])

	var out := []
	var code := OS.execute(BLENDER, args, out, true)
	_busy = false
	if code != 0:
		_say("[color=#ff8080]Blender exited %d[/color]" % code)
	for line: String in str(out[0] if out.size() > 0 else "").split("\n"):
		if line.begins_with("[CARDS] Leaf") or line.strip_edges().begins_with("Leaf"):
			_say(line.strip_edges())
	_rebuild_specimens()
	_rebuild_patch()


## WHY GRASS NEEDS ITS OWN SAVE, AND WHY IT WRITES TO A SCENE.
##
## The leaf materials are Resources, so tuning them edits a .tres that already exists on disk. Grass
## has no material to save into — every dial is an export on the GrassPatch NODE, and nodes live in
## scenes. So this patches the ArenaGrass* nodes in the hub scene, which is where the shipping
## fields actually are; saving into foliage_lab.tscn would tune the bench and leave the game alone.
##
## SHAPE, PALETTE, AND DENSITY. region_size, rng_seed, transform and exclusion_rects stay put: they
## are per-field LAYOUT, three patches deliberately differ in them, and copying the bench's single
## rectangle over all three would collapse the arena's variety into one repeated field.
##
## `count` used to be lumped in with those and left behind, which was wrong and obviously so the
## first time a tuned field reached the arena: the bench ran ~46 tufts/m² and the arena ~10, so a
## carpet of grass arrived as scattered sprigs. Raw count IS layout — 9,000 means nothing without
## the area it covers — but DENSITY is look. So the bench's tufts-per-square-metre is carried over
## and each field recomputes its own count from its own area.
const GRASS_SCENE := "res://scenes/world/room.tscn"
const GRASS_KEYS := ["density", "species", "blades", "tuft_height", "blade_width", "blade_bow",
		"blade_droop", "blade_taper", "height_variation", "sway_strength", "clump_size", "sink",
		"base_color", "tip_color", "color_variation", "flower_color", "flower_chance",
		"flower_size", "occlusion_strength", "occlusion_radius", "occlusion_saturation",
		"patch_variation", "patch_scale"]


func _save_grass() -> void:
	var g := get_node_or_null("Grass") as GrassPatch
	if g == null:
		return
	var f := FileAccess.open(GRASS_SCENE, FileAccess.READ)
	if f == null:
		_say("[color=#ff8080]cannot read %s[/color]" % GRASS_SCENE)
		return
	var lines := f.get_as_text().split("\n")
	f.close()

	var want := {}
	for k: String in GRASS_KEYS:
		want[k] = _fmt(g.get(k))

	# Tufts per square metre, which is the thing that actually reads as "density". An explicitly set
	# density wins; otherwise it is derived from the bench field's own count and area.
	var lab_area := maxf(g.region_size.x * g.region_size.y, 0.001)
	var density := g.density if g.density > 0.0 else float(g.count) / lab_area

	# Buffered per node block, because a field's count can only be worked out once its own
	# region_size has been read, and that line may come after the count line.
	#
	# NOT A LAMBDA, and this is the second time that has mattered in this file: GDScript captures a
	# local by VALUE when the lambda is created. A closure over `in_grass` and `block` therefore saw
	# `false` and an empty array forever, appended nothing for every block, and wrote out a room.tscn
	# with the scene deleted. It failed loudly enough to catch, which is the only good thing about it.
	var out: Array[String] = []
	var block: Array[String] = []
	var in_grass := false
	var touched := 0
	var fields := 0

	for raw: String in lines:
		if raw.begins_with("[node "):
			var done := _patch_grass_block(block, in_grass, want, density)
			out.append_array(done[0])
			touched += int(done[1])
			if in_grass:
				fields += 1
			block = []
			in_grass = raw.contains('name="ArenaGrass')
		block.append(raw)
	var last := _patch_grass_block(block, in_grass, want, density)
	out.append_array(last[0])
	touched += int(last[1])
	if in_grass:
		fields += 1

	var w := FileAccess.open(GRASS_SCENE, FileAccess.WRITE)
	if w == null:
		_say("[color=#ff8080]cannot write %s[/color]" % GRASS_SCENE)
		return
	w.store_string("\n".join(out))
	w.close()
	_say("grass: %d values into %d fields at %.1f tufts/m2" % [touched, fields, density])


## One node block, patched. Returns [lines, values_written].
##
## A non-grass block passes straight through. A grass block gets the shape and palette overwritten,
## and its count RECOMPUTED from the bench's density against that field's own area — which is why
## the block has to be buffered rather than streamed: region_size may be written after count.
func _patch_grass_block(block: Array[String], is_grass: bool, want: Dictionary,
		density: float) -> Array:
	if not is_grass:
		return [block, 0]

	var region := Vector2(10.0, 10.0)
	for l: String in block:
		if l.begins_with("region_size = Vector2("):
			var nums := l.get_slice("(", 1).trim_suffix(")").split(",")
			if nums.size() == 2:
				region = Vector2(nums[0].to_float(), nums[1].to_float())
	var n := int(round(density * maxf(region.x * region.y, 0.001)))

	var touched := 0
	var seen := {}
	var patched: Array[String] = []
	for l: String in block:
		var key := l.split(" = ")[0]
		if key == "count":
			patched.append("count = %d" % n)
			seen[key] = true
			touched += 1
		elif want.has(key):
			patched.append("%s = %s" % [key, want[key]])
			seen[key] = true
			touched += 1
		else:
			patched.append(l)

	# Anything the block never carried is appended — but BEFORE the blank line that ends it, or the
	# property lands outside its own node and Godot reads it as belonging to the next one.
	var tail: Array[String] = []
	while patched.size() > 0 and patched[patched.size() - 1].strip_edges() == "":
		tail.append(patched.pop_back())
	for k: String in GRASS_KEYS:
		if not seen.has(k):
			patched.append("%s = %s" % [k, want[k]])
			touched += 1
	if not seen.has("count"):
		patched.append("count = %d" % n)
		touched += 1
	patched.append_array(tail)
	_say("  %.0f x %.0f m  ->  %d tufts" % [region.x, region.y, n])
	return [patched, touched]


# ---------------------------------------------------------------- the brush
## PAINTING, AND WHY EACH STROKE MAKES ITS OWN LAYER.
##
## "The properties should be applied at the brush" is the whole design: what you paint is whatever
## the panel says right now. But a MultiMesh carries one mesh and one material, so a patch cannot
## hold two different grasses — which means the properties cannot live on the brush and be varied
## within a patch. They live on a LAYER instead: paint, change the dials, press NEW LAYER, and the
## next stroke starts a fresh patch carrying the new settings. Both stay on screen, both stay
## editable, and each is one draw call.
##
## Strokes are stored on the patch (brush_points), so a painted field is data rather than a baked
## mesh and survives being reopened, retuned and rebuilt.
## Planting brushes first, then the ones that move the ground. The order matches the dropdown, and
## SCULPT_FIRST is the single test everything downstream uses to tell them apart — add a planting
## brush at the end and it silently becomes a sculpt brush.
enum Brush { GRASS, BUSH, TREE, LIGHT, ERASE, RAISE, LOWER, SMOOTH, FLATTEN, CLIFF, LAKE }

const BRUSH_NAMES := ["Grass", "Bush", "Tree", "Light", "Erase",
		"Raise", "Lower", "Smooth", "Flatten", "Cliff", "Lake"]
const SCULPT_FIRST := Brush.RAISE

## Brush -> TerrainField.Mode. Spelled out through the real enum rather than as 0..5, because the
## two lists are in different files and a reordering that broke them apart would show up as the
## wrong brush doing the wrong thing rather than as an error.
const SCULPT_MODE := {
	Brush.RAISE: TerrainField.Mode.RAISE,
	Brush.LOWER: TerrainField.Mode.LOWER,
	Brush.SMOOTH: TerrainField.Mode.SMOOTH,
	Brush.FLATTEN: TerrainField.Mode.FLATTEN,
	Brush.CLIFF: TerrainField.Mode.CLIFF,
	Brush.LAKE: TerrainField.Mode.LAKE,
}

var _brush := Brush.GRASS
var _brush_radius := 2.0
## How much of what is under the brush a single erase dab takes away. Low on purpose: a path is
## worn in by going over it, and an eraser that clears in one pass cannot feather an edge.
var _erase_strength := 0.35
var _painting := false
var _layers: Node3D
var _active_grass: GrassPatch
var _active_bush: BushPatch
var _tree_index := 0


func _unhandled_input(event: InputEvent) -> void:
	if _brush_mode_off():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_painting = event.pressed
		if event.pressed:
			_begin_stroke()
			_dab()
		else:
			_finish_stroke()
	elif event is InputEventMouseMotion:
		_move_ring()
		if _painting:
			_dab()


func _brush_mode_off() -> bool:
	return not _paint_enabled


var _paint_enabled := false


## Where the cursor meets the ground.
##
## This used to intersect the y = 0 plane, and its comment said the ground "has no collider and does
## not need one" — true right up until the ground could be sculpted. It now asks the height field,
## which answers by marching its own array rather than by querying physics; scripts/terrain_field.gd
## explains why that is the better question to ask (chiefly: it is right on the same frame as a
## sculpt dab, where a physics query would still describe the previous shape).
##
## The plane maths is kept as the fallback, because a bench with no Ground node should still paint.
func _cursor_ground() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.INF
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var t := _terrain()
	if t != null:
		return t.raycast(from, dir)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var k := -from.y / dir.y
	return from + dir * k if k > 0.0 else Vector3.INF


func _terrain() -> Node:
	return get_node_or_null("Ground")


## Ground height at a world XZ, in world Y. Used to sit things on the terrain that are placed rather
## than scattered — the brush ring, a stamped tree, a stamped light.
func _ground_y(at: Vector3) -> float:
	var t := _terrain()
	if t == null:
		return 0.0
	var l: Vector3 = t.to_local(at)
	return t.to_global(Vector3(l.x, t.height_at(Vector2(l.x, l.z)), l.z)).y


## Mouse-down. FLATTEN and LAKE need the height they started from, before the stroke moves it.
func _begin_stroke() -> void:
	if _brush < SCULPT_FIRST:
		return
	var t := _terrain()
	var at := _cursor_ground()
	if t == null or at == Vector3.INF:
		return
	var l: Vector3 = t.to_local(at)
	t.max_slope_deg = float(_terra.max_slope)
	t.begin_stroke(Vector2(l.x, l.z), SCULPT_MODE[_brush], float(_terra.lake_depth))


func _dab() -> void:
	var at := _cursor_ground()
	if at == Vector3.INF:
		return
	if _brush >= SCULPT_FIRST:
		_sculpt_at(at)
		return
	match _brush:
		Brush.GRASS:
			_paint_into(_ensure_grass_layer(), at)
		Brush.BUSH:
			_paint_into(_ensure_bush_layer(), at)
		Brush.TREE:
			_stamp_tree(at)
		Brush.LIGHT:
			_stamp_light(at)
		Brush.ERASE:
			_erase_at(at)


## Move the ground, then re-seat everything standing on it.
##
## reproject() is the cheap per-dab path: it rewrites one float per instance and re-rolls nothing.
## It does not re-tilt anything — that costs a rebuild, and rebuild() runs once on mouse-up. Same
## split settle() already uses for occlusion, and for the same reason: the accurate pass depends on
## what the rest of the stroke has not done yet.
func _sculpt_at(at: Vector3) -> void:
	var t := _terrain()
	if t == null:
		return
	var l: Vector3 = t.to_local(at)
	t.sculpt(Vector2(l.x, l.z), _brush_radius, SCULPT_MODE[_brush], float(_terra.strength))
	_reseat(false)


## Erasing works on EVERY painted layer under the cursor, not just the active one. You are rubbing
## out ground, and the ground does not know which layer put a plant there.
func _erase_at(at: Vector3) -> void:
	var gone := FoliageBrush.erase_at(_layers.get_children(), at, _brush_radius, _erase_strength)
	if gone > 0:
		_say("erased %d" % gone)


func _paint_into(node: Node3D, at: Vector3) -> void:
	# The bench's patches carry a live TerrainField, which outranks a baked surface, so the normal
	# handed over here only matters for a layer painted with no terrain attached.
	var t := _terrain()
	var n := Vector3.UP
	if t != null:
		var l: Vector3 = t.to_local(at)
		n = t.normal_at(Vector2(l.x, l.z))
	FoliageBrush.paint_into(node, at, _brush_radius, n)


## Mouse-up: settle the stroke — bake occlusion over what was painted, WITHOUT moving any of it.
##
## This used to call rebuild(), which regenerates every position from the stroke list, so releasing
## the button re-rolled the entire field and it visibly jumped. A patch that has settle() keeps its
## plants where they were put.
func _finish_stroke() -> void:
	if _brush >= SCULPT_FIRST:
		_reseat(true)
		_save_terrain()
		return
	# EVERY layer, not just the active pair. An erase thins whatever is under the cursor, so a layer
	# the stroke never "belonged" to can still have lost a third of its plants — and it would go on
	# carrying occlusion baked for the density it used to have.
	if _brush == Brush.ERASE:
		FoliageBrush.settle(_layers.get_children())
	else:
		FoliageBrush.settle([_active_grass, _active_bush])


## Put every painted layer back on the ground after it has moved.
##
## `exact` picks between the two paths described on GrassPatch.reproject(): the per-dab float
## rewrite, or a full replay that also re-tilts each plant to the new slope. Stamped trees and
## lights are single nodes, so they just get their Y set either way.
func _reseat(exact: bool) -> void:
	if _layers == null:
		return
	for n in _layers.get_children():
		if n.has_method("reproject"):
			if exact and n.has_method("rebuild"):
				n.call("rebuild")
			else:
				n.call("reproject")
		elif n is Node3D:
			var p := (n as Node3D).position
			(n as Node3D).position = Vector3(p.x, _ground_y(Vector3(p.x, 0.0, p.z)) + _stamp_lift(n),
					p.z)
	var g := get_node_or_null("Grass") as GrassPatch
	if g:
		if exact:
			g.rebuild()
		else:
			g.reproject()


## How far above the ground a stamped node sits. Lights hang; trees stand on it.
func _stamp_lift(n: Node) -> float:
	return 2.5 if n is OmniLight3D else 0.0


## A fresh layer copies the panel's CURRENT settings, which is what makes the brush carry them.
func _ensure_grass_layer() -> GrassPatch:
	if _active_grass != null:
		return _active_grass
	var src := get_node_or_null("Grass") as GrassPatch
	var g := GrassPatch.new()
	for k: String in GRASS_KEYS:
		g.set(k, src.get(k))
	g.density = src.density if src.density > 0.0 else \
			float(src.count) / maxf(src.region_size.x * src.region_size.y, 1.0)
	g.paint_only = true          # empty until painted, not a rectangle waiting under the stroke
	g.name = "PaintedGrass%d" % _layers.get_child_count()
	g.rng_seed = 100 + _layers.get_child_count()
	_layers.add_child(g)
	# After add_child, because a NodePath is resolved relative to a node that is in the tree.
	g.terrain = g.get_path_to(_terrain()) if _terrain() != null else NodePath()
	_active_grass = g
	_say("new grass layer: %s at %.1f tufts/m2" % [g.name, g.density])
	return g


func _ensure_bush_layer() -> BushPatch:
	if _active_bush != null:
		return _active_bush
	var b := BushPatch.new()
	b.mesh_source = load("res://assets/models/veg_leaf_bush_b.glb")
	b.material_override = _leaf_bush
	b.density = 0.25
	b.scale_range = Vector2(float(_scatter.scale_min), float(_scatter.scale_max))
	b.sink = float(_scatter.sink)
	b.paint_only = true
	b.name = "PaintedBush%d" % _layers.get_child_count()
	b.rng_seed = 200 + _layers.get_child_count()
	_layers.add_child(b)
	b.terrain = b.get_path_to(_terrain()) if _terrain() != null else NodePath()
	_active_bush = b
	_say("new bush layer: %s" % b.name)
	return b


## Trees are STAMPED, not scattered: they are big enough that you place each one, and a brush that
## sprayed them would be a worse tool than a click.
func _stamp_tree(at: Vector3) -> void:
	var stems := ["veg_leaf_tree", "veg_leaf_tree_b"]
	var mesh := _runtime_mesh(stems[_tree_index % stems.size()])
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _leaf_tree
	mi.position = at
	mi.rotation.y = randf() * TAU
	var s := randf_range(0.85, 1.2)
	mi.scale = Vector3(s, s, s)
	mi.name = "PaintedTree%d" % _layers.get_child_count()
	_layers.add_child(mi)
	_tree_index += 1
	_painting = false        # one tree per click, never a drag
	_say("tree at (%.1f, %.1f)" % [at.x, at.z])


## LIGHTS, the same idea the crypt bench uses: drop one where you are looking and tune it in place.
## Foliage is judged by how light moves through it, and a single fixed sun cannot show that.
func _stamp_light(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.position = at + Vector3(0.0, 2.5, 0.0)
	l.light_color = _light_color
	l.light_energy = _light_energy
	l.omni_range = _light_range
	l.shadow_enabled = true
	l.name = "PaintedLight%d" % _layers.get_child_count()
	_layers.add_child(l)
	_painting = false
	_say("light at (%.1f, %.1f)" % [at.x, at.z])


var _light_color := Color(1.0, 0.86, 0.66)
var _light_energy := 4.0
var _light_range := 9.0


## A RING ON THE GROUND, because a brush whose size you cannot see is a brush you tune by accident.
## Unshaded and depth-test-disabled so it stays readable through tall grass, which is exactly where
## you need it most.
## THE RING IS DRAWN, NOT SCALED, now that the ground can be shaped.
##
## It used to be a TorusMesh at radius 1 scaled to the brush radius, which is exact on a plane and
## wrong on anything else: a flat disc over a hill buries half its circumference and floats the
## other half, so the one thing the ring is for — showing you what the next dab will touch — stops
## being true exactly where sculpting gets interesting. Sixty-four points resampled from the height
## field per mouse move costs nothing and follows the ground.
##
## Unshaded and depth-test-disabled, as before, because the place you most need to see the brush is
## through tall grass.
const RING_SEGMENTS := 64


func _ensure_ring() -> MeshInstance3D:
	if _ring != null:
		return _ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.5)
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 2
	mat.vertex_color_use_as_albedo = false
	_ring = MeshInstance3D.new()
	_ring.mesh = ImmediateMesh.new()
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	return _ring


func _move_ring() -> void:
	var ring := _ensure_ring()
	ring.visible = _paint_enabled
	if not _paint_enabled:
		return
	var at := _cursor_ground()
	if at == Vector3.INF:
		ring.visible = false
		return
	ring.global_position = at
	var im := ring.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in RING_SEGMENTS + 1:
		var a := TAU * i / float(RING_SEGMENTS)
		var w := at + Vector3(cos(a), 0.0, sin(a)) * _brush_radius
		# 6 cm of lift, which clears the grass sink and the z-fighting without reading as a hover.
		im.surface_add_vertex(Vector3(w.x, _ground_y(w) + 0.06, w.z) - at)
	im.surface_end()


var _ring: MeshInstance3D


func _clear_layers() -> void:
	for c in _layers.get_children():
		c.queue_free()
	_active_grass = null
	_active_bush = null
	_say("layers cleared")


func _dirty_materials(nm: String) -> void:
	if not _unsaved.has(nm):
		_unsaved.append(nm)


## PATCH THE .tres LINE BY LINE. NEVER ResourceSaver.save().
##
## The obvious call rewrites the file from the resource, and measured on this project that costs
## two things worth more than the convenience: every `;` comment in the header is deleted -- 13
## lines of why-this-material-exists on the bush alone -- and every float is re-emitted at full
## precision, so an authored 0.5 becomes 0.499999988824 and the next diff is unreadable.
##
## This repo treats materials as documented artefacts, and godray_lab.gd already established the
## alternative: find the line, replace the value, leave the rest of the file alone.
func _save_materials() -> void:
	for mat: ShaderMaterial in [_leaf_bush, _leaf_tree]:
		_patch_tres(mat)
	_unsaved.clear()


func _patch_tres(mat: ShaderMaterial) -> void:
	var path := mat.resource_path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_say("[color=#ff8080]cannot read %s[/color]" % path.get_file())
		return
	var lines := f.get_as_text().split("\n")
	f.close()
	# A trailing newline splits into a final empty element; leaving it there puts a blank line in
	# the middle of the block when a missing parameter gets appended.
	while lines.size() > 0 and lines[lines.size() - 1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)

	var wrote := 0
	for entry in mat.shader.get_shader_uniform_list():
		var nm := String(entry.get("name", ""))
		var v: Variant = mat.get_shader_parameter(nm)
		# Textures and anything else object-shaped are ExtResource references in the file; writing
		# a formatted value over one would break the reference outright.
		if nm == "" or v == null or typeof(v) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT,
				TYPE_COLOR, TYPE_VECTOR2, TYPE_VECTOR3]:
			continue
		var key := "shader_parameter/%s = " % nm
		var found := false
		for i in lines.size():
			if lines[i].begins_with(key):
				lines[i] = key + _fmt(v)
				found = true
				wrote += 1
				break
		if not found:
			lines.append(key + _fmt(v))
			wrote += 1

	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_say("[color=#ff8080]cannot write %s[/color]" % path.get_file())
		return
	out.store_string("\n".join(lines) + "\n")
	out.close()
	_say("patched %d values into %s" % [wrote, path.get_file()])


func _fmt(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_COLOR:
			var c: Color = v
			return "Color(%s, %s, %s, %s)" % [_num(c.r), _num(c.g), _num(c.b), _num(c.a)]
		TYPE_VECTOR2:
			var v2: Vector2 = v
			return "Vector2(%s, %s)" % [_num(v2.x), _num(v2.y)]
		TYPE_VECTOR3:
			var v3: Vector3 = v
			return "Vector3(%s, %s, %s)" % [_num(v3.x), _num(v3.y), _num(v3.z)]
	return _num(float(v))


## Short, stable text for a float: 0.5 stays "0.5" rather than becoming "0.499999988824".
func _num(f: float) -> String:
	var s := "%.4f" % f
	while s.contains(".") and s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s += "0"
	return s


func _say(msg: String) -> void:
	if _log:
		_log.append_text(msg + "\n")
	print("[FOLIAGE] " + msg)


# ---------------------------------------------------------------- panel
func _build_panel() -> void:
	var box := Tuning.build_panel(self, 330, 700)

	Tuning.header(box, "GEOMETRY  (Blender — needs a rebuild)")
	Tuning.line(box, "1.00 = the authored plant. Rebuild to apply.", Color(0.6, 0.62, 0.7))
	for key: String in _dials.keys():
		var k := key
		# depth is a count, not a scale — a 0.05 step on it would spend most of the slider's travel
		# rounding to the same integer.
		if k == "depth":
			Tuning.slider(box, k, 0.5, 1.5, 0.25, _dials[k], func(v: float) -> void: _dials[k] = v; _touch())
		else:
			Tuning.slider(box, k, 0.3, 2.5, 0.05, _dials[k], func(v: float) -> void: _dials[k] = v; _touch())
	Tuning.button(box, "REBUILD IN BLENDER", _rebuild_in_blender)
	_log = Tuning.log_pane(box, 110)

	Tuning.header(box, "SCATTER  (live)")
	Tuning.slider(box, "count", 1, 200, 1, _scatter.count,
			func(v: float) -> void: _scatter.count = v; _rebuild_patch(); _touch())
	Tuning.slider(box, "clump_size", 0.0, 8.0, 0.1, _scatter.clump_size,
			func(v: float) -> void: _scatter.clump_size = v; _rebuild_patch(); _touch())
	Tuning.slider(box, "scale_min", 0.3, 3.0, 0.05, _scatter.scale_min,
			func(v: float) -> void: _scatter.scale_min = v; _rebuild_patch(); _touch())
	Tuning.slider(box, "scale_max", 0.3, 4.0, 0.05, _scatter.scale_max,
			func(v: float) -> void: _scatter.scale_max = v; _rebuild_patch(); _touch())
	Tuning.slider(box, "sink", 0.0, 0.4, 0.01, _scatter.sink,
			func(v: float) -> void: _scatter.sink = v; _rebuild_patch(); _touch())

	# "Add a uniform, get a knob" — every painted_env dial, generated from the shader itself, so
	# this section cannot fall behind the shader the way a hand-written list would.
	# from_shader's setter writes the parameter itself and THEN calls back with (name, value).
	# A zero-argument lambda here throws on every drag — the material still updated, so the error
	# looked unrelated to the slider that caused it.
	var noted := func(nm: String, _v: Variant) -> void: _dirty_materials(nm)
	Tuning.header(box, "LEAF MATERIAL — bush  (live)")
	Tuning.from_shader(box, _leaf_bush, noted)
	Tuning.header(box, "LEAF MATERIAL — tree  (live)")
	Tuning.from_shader(box, _leaf_tree, noted)
	# Live edits change the loaded resource in memory only. Without this the session's tuning is
	# lost on exit, which is the same reason lookdev.gd carries a save button.
	Tuning.button(box, "SAVE BOTH LEAF MATERIALS", _save_materials)

	# GRASS is live in a way the plants are not: its mesh is built in GDScript by GrassPatch, so a
	# shape change costs a rebuild() and no Blender launch at all. That is the whole reason grass
	# stayed engine-side when the bushes moved to Blender.
	Tuning.header(box, "GRASS  (live — no rebuild)")
	var g := get_node_or_null("Grass") as GrassPatch
	if g:
		var redo := func() -> void: g.rebuild(); _touch()
		Tuning.option(box, "species", PackedStringArray(["Blade", "Reed", "Frond", "Flowering"]),
				g.species, func(i: int) -> void: g.species = i; g.rebuild(); _touch())
		for spec in [["density", 0.0, 80.0, 0.5], ["count", 100.0, 12000.0, 100.0],
					 ["blades", 1.0, 12.0, 1.0],
					 ["tuft_height", 0.1, 2.5, 0.05], ["blade_width", 0.01, 0.4, 0.005],
					 ["blade_bow", 0.0, 0.5, 0.01], ["blade_droop", 0.0, 1.0, 0.02],
					 ["blade_taper", 0.05, 1.2, 0.05], ["height_variation", 0.0, 0.9, 0.05],
					 ["clump_size", 0.0, 8.0, 0.1], ["sink", 0.0, 0.4, 0.01],
					 ["flower_chance", 0.0, 1.0, 0.05], ["flower_size", 0.1, 3.0, 0.05],
					 ["sway_strength", 0.0, 0.4, 0.01],
					 ["occlusion_strength", 0.0, 1.0, 0.05], ["occlusion_radius", 0.1, 2.0, 0.05],
					 ["occlusion_saturation", 2.0, 40.0, 1.0],
					 ["patch_variation", 0.0, 0.8, 0.02], ["patch_scale", 0.01, 0.5, 0.01]]:
			var nm: String = spec[0]
			Tuning.slider(box, nm, spec[1], spec[2], spec[3], g.get(nm),
					func(v: float) -> void:
						g.set(nm, int(v) if nm in ["count", "blades", "occlusion_saturation"] else v)
						redo.call())
		for cname in ["base_color", "tip_color", "flower_color"]:
			var cn: String = cname
			Tuning.color(box, cn, g.get(cn), func(c: Color) -> void: g.set(cn, c); redo.call())
		Tuning.button(box, "SAVE GRASS -> room.tscn", _save_grass)

	# THE BRUSH. Paint mode swallows the left mouse button, so it is off by default and the fly
	# camera keeps working until you ask for it.
	Tuning.header(box, "BRUSH  (paint on the ground)")
	Tuning.check(box, "paint mode  (LMB paints)", _paint_enabled,
			func(on: bool) -> void: _paint_enabled = on)
	Tuning.option(box, "brush", PackedStringArray(BRUSH_NAMES),
			_brush, func(i: int) -> void: _brush = i as Brush)
	Tuning.slider(box, "brush radius", 0.3, 8.0, 0.1, _brush_radius,
			func(v: float) -> void: _brush_radius = v)
	Tuning.slider(box, "erase strength", 0.02, 1.0, 0.02, _erase_strength,
			func(v: float) -> void: _erase_strength = v)
	Tuning.line(box, "A layer keeps the settings it was started with.", Color(0.6, 0.62, 0.7))
	Tuning.button(box, "NEW LAYER  (adopt current settings)", func() -> void:
			_active_grass = null
			_active_bush = null
			_say("next stroke starts a new layer"))
	Tuning.button(box, "CLEAR PAINTED", _clear_layers)
	Tuning.slider(box, "light energy", 0.0, 16.0, 0.25, _light_energy,
			func(v: float) -> void: _light_energy = v)
	Tuning.slider(box, "light range", 1.0, 40.0, 0.5, _light_range,
			func(v: float) -> void: _light_range = v)
	Tuning.color(box, "light colour", _light_color, func(c: Color) -> void: _light_color = c)

	# THE GROUND. The last six entries in the brush dropdown sculpt it; these are their dials.
	Tuning.header(box, "TERRAIN  (Raise/Lower/Smooth/Flatten/Cliff/Lake)")
	Tuning.line(box, "Sculpt with the brush above. Foliage follows.", Color(0.6, 0.62, 0.7))
	Tuning.slider(box, "strength", 0.02, 1.5, 0.02, _terra.strength,
			func(v: float) -> void: _terra.strength = v; _touch())
	Tuning.slider(box, "max slope deg", 5.0, 60.0, 1.0, _terra.max_slope,
			func(v: float) -> void:
				_terra.max_slope = v
				var t := _terrain()
				if t != null:
					t.max_slope_deg = v
				_touch())
	Tuning.slider(box, "lake depth", 0.3, 6.0, 0.1, _terra.lake_depth,
			func(v: float) -> void: _terra.lake_depth = v; _touch())
	# The one diagnostic that keeps "a few blocking cliffs" a decision. Green walks, amber is the
	# margin, red is a wall no enemy in this project can climb or path around.
	Tuning.check(box, "slope overlay  (red = enemies stuck)", _terra.overlay > 0.5,
			func(on: bool) -> void:
				_terra.overlay = 1.0 if on else 0.0
				_apply_overlay()
				_touch())
	Tuning.slider(box, "noise seed", 0.0, 64.0, 1.0, _terra.noise_seed,
			func(v: float) -> void: _terra.noise_seed = v; _touch())
	Tuning.slider(box, "noise freq", 0.002, 0.08, 0.002, _terra.noise_freq,
			func(v: float) -> void: _terra.noise_freq = v; _touch())
	Tuning.slider(box, "noise octaves", 1.0, 5.0, 1.0, _terra.noise_octaves,
			func(v: float) -> void: _terra.noise_octaves = v; _touch())
	Tuning.slider(box, "noise amp", 0.2, 12.0, 0.1, _terra.noise_amp,
			func(v: float) -> void: _terra.noise_amp = v; _touch())
	Tuning.button(box, "NOISE FILL  (whole field)", func() -> void:
			var t := _terrain()
			if t == null:
				return
			t.max_slope_deg = float(_terra.max_slope)
			t.noise_fill(int(_terra.noise_seed), float(_terra.noise_freq),
					int(_terra.noise_octaves), float(_terra.noise_amp))
			_reseat(true)
			_save_terrain()
			_say("noise fill: seed %d, amp %.1f m" % [int(_terra.noise_seed), _terra.noise_amp]))
	Tuning.button(box, "RESET FLAT", func() -> void:
			var t := _terrain()
			if t == null:
				return
			t.reset_flat()
			_reseat(true)
			_save_terrain()
			_say("terrain reset to flat"))
	Tuning.button(box, "EXPORT TERRAIN -> res://", func() -> void:
			var t := _terrain()
			if t != null and t.save_to(TERRAIN_EXPORT):
				_say("wrote %s" % TERRAIN_EXPORT)
			else:
				_say("EXPORT FAILED"))

	Tuning.header(box, "SUN  (live)")
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		Tuning.slider(box, "energy", 0.0, 4.0, 0.05, sun.light_energy,
				func(v: float) -> void: sun.light_energy = v)
		Tuning.slider(box, "pitch deg", 5.0, 89.0, 1.0, 40.0,
				func(v: float) -> void: sun.rotation.x = -deg_to_rad(v))
		Tuning.slider(box, "yaw deg", -180.0, 180.0, 1.0, 35.0,
				func(v: float) -> void: sun.rotation.y = deg_to_rad(v))
		Tuning.color(box, "colour", sun.light_color,
				func(c: Color) -> void: sun.light_color = c)

	Tuning.line(box, "RMB + WASD to fly, Q/E down/up, Shift to sprint.",
			Color(0.6, 0.62, 0.7))

extends SceneTree
## Headless verification for the Dungeon Forge editor preview. Run:
##   Godot_console.exe --headless --path . --script res://scripts/dungeon/tests/verify_forge_preview.gd
## Results also written to user://verify_forge_preview.txt. Non-zero exit code on any failure.
##
## What this proves: the STRIPPED build (addons/dungeon_forge/preview/forge_preview_builder.gd)
## walks the same pipeline as the game — same rooms, same doors, same template assignments — and
## carries NONE of the runtime systems. It runs in plain SceneTree context, where @tool is inert,
## because the builder's logic is the thing under test; only EditorInterface glue (the plugin and
## dock) needs an editor, and they deliberately contain no build logic.

const PreviewBuilder := preload("res://addons/dungeon_forge/preview/forge_preview_builder.gd")
const ForgeGI := preload("res://addons/dungeon_forge/preview/forge_gi.gd")
const THEME := "res://scenes/dungeon/themes/crypt.tres"

## Same crash-detection idiom as verify_dungeon.gd:10 — an error inside an awaited suite unwinds
## silently, so the count is checked at the end and a missing suite is a failure.
const EXPECTED_SUITES := 6

var _fails: Array[String] = []
var _log := ""
var _suites_done := 0


func _initialize() -> void:
	_preview_suite()
	await _parity_suite()
	_determinism_suite()
	_gi_suite()
	_proxy_suite()
	await _bake_persistence_suite()

	if _suites_done != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported done — one crashed silently"
				% [_suites_done, EXPECTED_SUITES])
	var f := FileAccess.open("user://verify_forge_preview.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log)
	if _fails.is_empty():
		_say("[VERIFY] FORGE PREVIEW PASS")
		quit(0)
	else:
		for line in _fails:
			_say("[VERIFY] FAIL: " + line)
		quit(1)


## The stripped build, three seeds: counts match the layout, and the runtime systems are ABSENT.
func _preview_suite() -> void:
	var theme: DungeonTheme = load(THEME)
	for s in [7, 42, 137]:
		var lay := DungeonLayout.generate(s, 9, 1, 2)
		var pv := PreviewBuilder.build(lay, theme, 0.5)
		root.add_child(pv)
		_check(pv.has_meta("forge_preview"), "seed %d: preview root unmarked" % s)

		var rooms := 0
		var doors := 0
		for node in _walk(pv):
			if node.has_meta("forge_anchor"):
				rooms += 1
				_check(lay.rooms.has(node.get_meta("forge_anchor")),
						"seed %d: room node with anchor the layout does not have" % s)
			if node is DungeonDoor:
				doors += 1
			# THE ABSENCE LIST — each of these is a runtime system the preview must not carry.
			# Enemies are checked as CharacterBody3D rather than by class: naming `Enemy` here
			# would compile enemy.gd at script-load time, before autoload identifiers (EventBus)
			# exist in --script mode, and the whole test fails to load. Kit pieces are
			# StaticBody3D; the only CharacterBody3D a dungeon ever holds is something alive.
			_check(not node is DungeonRoom, "seed %d: a DungeonRoom in the preview" % s)
			_check(not node is CourseVeil, "seed %d: a CourseVeil in the preview" % s)
			_check(not node is RoomGI, "seed %d: a RoomGI in the preview" % s)
			_check(not node is CharacterBody3D, "seed %d: something alive in the preview" % s)
			_check(node.name != "SpawnA", "seed %d: a SpawnA in the preview" % s)
			_check(node.name != "ReturnPortal", "seed %d: a ReturnPortal in the preview" % s)

		_check(rooms == lay.rooms.size(),
				"seed %d: %d room nodes for %d layout rooms" % [s, rooms, lay.rooms.size()])
		var edges := 0
		for cell: Vector3i in lay.rooms:
			edges += (lay.rooms[cell] as DungeonLayout.RoomData).edges.size()
		edges /= 2                                       # stored on both rooms
		_check(doors == edges, "seed %d: %d doors for %d edges" % [s, doors, edges])
		pv.free()
	_done("preview suite: 3 seeds — counts match, runtime systems absent")


## The preview agrees with the REAL zone at the same seed: room count, door count, and — because
## both run the same rng discipline (seed + 7919) — the same template on the same room.
func _parity_suite() -> void:
	var s := 42
	var zc := (load("res://scenes/world/zone_crypt.tscn") as PackedScene).instantiate()
	zc.dungeon_seed = s
	root.add_child(zc)
	await process_frame                                  # let the _ready cascade generate
	var zone_lay: DungeonLayout = zc.layout

	var lay := DungeonLayout.generate(s, 9, 1, 2)
	var pv := PreviewBuilder.build(lay, load(THEME), 0.5)
	root.add_child(pv)

	_check(lay.rooms.size() == zone_lay.rooms.size(), "layouts disagree on room count")
	_check(_count_doors(pv) == _count_doors(zc),
			"preview %d doors, zone %d" % [_count_doors(pv), _count_doors(zc)])
	for anchor: Vector3i in lay.rooms:
		var mine: String = (lay.rooms[anchor] as DungeonLayout.RoomData).template_path
		var zones: String = (zone_lay.rooms[anchor] as DungeonLayout.RoomData).template_path
		_check(mine == zones, "template drift at %s: preview '%s', zone '%s'"
				% [anchor, mine, zones])

	pv.free()
	zc.free()
	_done("parity suite: seed %d — preview and zone_crypt agree on rooms, doors, templates" % s)


## The same seed builds the same preview, node for node — the editor promise that stepping back
## to a seed shows what you saw.
func _determinism_suite() -> void:
	var theme: DungeonTheme = load(THEME)
	# SEQUENTIAL, not side by side: two "DungeonPreview" siblings would make Godot auto-rename
	# the second, and the signature would fail on the rename rather than on the build.
	var sig_a := 0
	var sig_b := 0
	for pass_n in 2:
		var lay := DungeonLayout.generate(7, 9, 1, 2)
		var pv := PreviewBuilder.build(lay, theme, 0.5)
		root.add_child(pv)                               # in-tree, so DungeonDoor._ready runs
		if pass_n == 0:
			sig_a = _tree_signature(pv)
		else:
			sig_b = _tree_signature(pv)
		pv.free()
	_check(sig_a == sig_b, "seed 7 built two different previews")
	_done("determinism suite: seed 7 reproduces its preview exactly")


## The GI bake: one probe per room, the editor's own bake over real geometry, interior set,
## and REPLACE-NOT-STACK — a second press leaves exactly one probe per room, which is the
## idempotency the whole design promises (a manual Precalcola press keeps the same data
## resource and parameters; measured in the scratch probe, asserted structurally here).
func _gi_suite() -> void:
	var lay := DungeonLayout.generate(42, 8, 0, 1)
	var pv := PreviewBuilder.build(lay, load(THEME), 0.0)
	root.add_child(pv)
	var n: int = ForgeGI.bake(pv)
	_check(n == lay.rooms.size(), "baked %d probes for %d rooms" % [n, lay.rooms.size()])
	var n2: int = ForgeGI.bake(pv)                       # press it again
	_check(n2 == n, "a second bake changed the probe count")
	var probes := 0
	for node in _walk(pv):
		if node is VoxelGI:
			probes += 1
			_check((node as VoxelGI).data != null, "a probe carries no baked data")
			_check((node as VoxelGI).data != null and (node as VoxelGI).data.interior,
					"a probe is not interior — the editor sky would wash the room")
			_check((node as Node3D).visible, "a probe is not contributing")
			_check(node.get_parent().has_meta("forge_anchor"),
					"a probe is not under the room it lights")
		_check(not node is RoomGI, "the borrowed sizing RoomGI was left in the preview")
	_check(probes == lay.rooms.size(),
			"%d probes standing for %d rooms — bakes must replace, never stack"
			% [probes, lay.rooms.size()])
	pv.free()
	_done("gi suite: %d rooms lit by the button's own bake, interior, idempotent"
			% lay.rooms.size())


## The GI proxy IS the plan: per-tile floors, one slab per walls() segment (a doorway keeping
## only its spandrel), a box per planned cover, all in the theme's bounce colour. Classified by
## slab height, which no two kinds share.
func _proxy_suite() -> void:
	var theme: DungeonTheme = load(THEME)
	var lay := DungeonLayout.generate(42, 9, 1, 2)
	var pv := PreviewBuilder.build(lay, theme, 0.0)
	root.add_child(pv)
	var gi := RoomGI.new()
	var h := DungeonLayout.WALL_HEIGHT
	for room in pv.get_children():
		if not room.has_meta("forge_anchor"):
			continue
		var plan: RoomContext = room.get("plan")
		_check(plan != null and plan.shape != null, "%s carries no plan" % room.name)
		if plan == null or plan.shape == null:
			continue
		var proxy := gi._proxy_for(room)
		var floors := 0
		var walls := 0
		var spandrels := 0
		var risers := 0
		var covers := 0
		var bad_albedo := 0
		for c in proxy.get_children():
			var size: Vector3 = ((c as MeshInstance3D).mesh as BoxMesh).size
			if ((c as MeshInstance3D).material_override as StandardMaterial3D).albedo_color \
					!= theme.gi_albedo:
				bad_albedo += 1
			if is_equal_approx(size.y, 0.5):
				floors += 1
			elif is_equal_approx(size.y, h):
				walls += 1
			elif is_equal_approx(size.y, h - RoomGI.DOOR_CLEAR):
				spandrels += 1
			elif is_equal_approx(size.y, RoomShape.LEVEL_RISE):
				risers += 1
			else:
				covers += 1
		var expected_cover := 0
		for slot: RoomContext.Slot in plan.slots:
			if (slot.tag == RoomPlan.T_COVER_LARGE or slot.tag == RoomPlan.T_COVER_SMALL) \
					and slot.footprint != Vector2.ZERO:
				expected_cover += 1
		_check(floors == plan.shape.tile_count(),
				"%s: %d floor slabs for %d tiles" % [room.name, floors, plan.shape.tile_count()])
		_check(walls + spandrels + risers == plan.shape.walls().size(),
				"%s: %d wall slabs for %d wall segments"
				% [room.name, walls + spandrels + risers, plan.shape.walls().size()])
		_check(spandrels >= 1, "%s: a room with exits has no doorway spandrel" % room.name)
		_check(covers == expected_cover,
				"%s: %d cover boxes for %d planned" % [room.name, covers, expected_cover])
		_check(bad_albedo == 0, "%s: %d slabs not in the theme's gi_albedo"
				% [room.name, bad_albedo])
		proxy.free()
	# And the fallback: a room with no plan still gets the five-slab shell.
	var bare := Node3D.new()
	root.add_child(bare)
	var shell := gi._proxy_for(bare)
	_check(shell.get_child_count() == 5, "plan-less fallback built %d slabs, wanted the shell's 5"
			% shell.get_child_count())
	shell.free()
	bare.free()
	gi.free()
	pv.free()
	_done("proxy suite: the proxy is the plan — floors, walls, doorways, cover, theme bounce")


## THE BAKE SURVIVES THE DISK — the editor checklist item made headless. Reproduces what the
## plugin's Bake to scene does (script strip + the same ownership recursion), packs, saves,
## loads, and asserts: every room and every GI probe came back, no preview-room script rode
## along, and a DungeonDoor rebuilt its Visual/Blocker exactly once (they are deliberately
## unowned — dungeon_door.gd:24 rebuilds them — so a doubled slab here is R4 come true).
func _bake_persistence_suite() -> void:
	var lay := DungeonLayout.generate(42, 9, 1, 2)
	var pv := PreviewBuilder.build(lay, load(THEME), 0.5)
	var host := Node3D.new()                            # stands in for the edited scene root
	root.add_child(host)
	host.add_child(pv)
	var probes: int = ForgeGI.bake(pv)

	# The plugin's _on_bake, replicated: strip the stand-in scripts, own everything except
	# below instanced scenes and self-building nodes (plugin.gd:_bake_set_owners).
	for room in pv.get_children():
		if room.has_meta("forge_anchor") and room.get_script() != null:
			room.set_script(null)
	_own_like_bake(pv, host)
	# The data is dropped BEFORE saving, headless-only: under the dummy renderer a probe's field
	# textures are 0-byte images and serializing them fails (in the real editor they carry real
	# bytes and Godot's own save path handles them — that half is the engine's promise, not
	# ours). What this suite owns is the NODES surviving the disk.
	for node in _walk(pv):
		if node is VoxelGI:
			(node as VoxelGI).data = null
	# THE PAINT, counted before the disk. It is NOT serialized (it lives on instance internals,
	# which a save discards); the bake records it as metadata and dungeon_bake.gd re-derives it
	# on load — reloaded-as-bare-plastic and the duplicated-node collision wall were the two
	# defects this block replays.
	var painted_before := _count_painted(pv)
	_check(painted_before > 0, "nothing in the preview carries the theme material at all")
	var paint := {}
	_collect_paint_like_bake(pv, pv, paint)
	_check(paint.size() == painted_before, "the paint record missed %d meshes"
			% (painted_before - paint.size()))
	pv.set_script(load("res://scripts/dungeon/dungeon_bake.gd"))
	pv.set("theme", load(THEME))
	pv.set_meta("forge_paint", paint)
	var nodes_before := _walk(host).size()
	var packed := PackedScene.new()
	_check(packed.pack(host) == OK, "bake failed to pack")
	var path := "user://verify_forge_bake.tscn"
	_check(ResourceSaver.save(packed, path) == OK, "bake failed to save")
	pv.free()
	host.free()

	var back := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			as PackedScene).instantiate()
	root.add_child(back)
	await process_frame                                 # doors rebuild in _ready
	var rooms := 0
	var back_probes := 0
	var scripted := 0
	for node in _walk(back):
		if node.has_meta("forge_anchor"):
			rooms += 1
			if node.get_script() != null:
				scripted += 1
		if node is VoxelGI:
			back_probes += 1
		if node is DungeonDoor:
			var visuals := 0
			for c in node.get_children():
				if String(c.name).begins_with("Visual"):
					visuals += 1
			_check(visuals == 1, "a door came back with %d Visuals — R4" % visuals)
	_check(rooms == lay.rooms.size(),
			"%d rooms survived the disk of %d" % [rooms, lay.rooms.size()])
	_check(back_probes == probes and probes == lay.rooms.size(),
			"%d probes survived the disk of %d baked" % [back_probes, probes])
	_check(scripted == 0, "%d baked rooms still carry the addon's stand-in script" % scripted)
	var painted_after := _count_painted(back)
	_check(painted_after == painted_before,
			"%d of %d painted meshes repainted after the disk"
			% [painted_after, painted_before])
	# And the collision wall stays down, asserted exactly: a save that leaked instance
	# internals as scene-authored nodes duplicates them on load, so the reloaded tree would
	# hold MORE nodes than the one that was packed. Equality is the whole claim.
	var nodes_after := _walk(back).size()
	_check(nodes_after == nodes_before,
			"%d nodes after the disk, %d before — instance internals leaked into the save"
			% [nodes_after, nodes_before])
	back.free()
	_done(("bake persistence suite: %d rooms + %d probes + %d repainted meshes round-trip the "
			+ "disk, doors build once, no collisions") % [rooms, back_probes, painted_after])


## plugin.gd:_collect_paint, replicated — change them together.
func _collect_paint_like_bake(n: Node, root_node: Node, out: Dictionary) -> void:
	if n is GeometryInstance3D \
			and (n as GeometryInstance3D).material_override is ShaderMaterial:
		var mi := n as GeometryInstance3D
		out[root_node.get_path_to(mi)] = [
			mi.get_instance_shader_parameter("piece_params"),
			mi.get_instance_shader_parameter("piece_base"),
			mi.get_instance_shader_parameter("piece_tint"),
		]
	for c in n.get_children():
		_collect_paint_like_bake(c, root_node, out)


## Meshes wearing the theme's stone: material_override is how Kit.dress() paints, and a
## ShaderMaterial override is its signature (greybox uses plain StandardMaterials).
func _count_painted(n: Node) -> int:
	var count := 0
	for node in _walk(n):
		if node is GeometryInstance3D \
				and (node as GeometryInstance3D).material_override is ShaderMaterial:
			count += 1
	return count


## plugin.gd:_bake_set_owners, replicated for the headless rig (the plugin needs an editor).
## If the two ever diverge, this suite is asserting a lie — change them together.
func _own_like_bake(n: Node, root_node: Node) -> void:
	n.owner = root_node
	if n.scene_file_path == "" and not n is DungeonDoor:
		for c in n.get_children():
			_own_like_bake(c, root_node)


func _tree_signature(n: Node) -> int:
	var parts: Array = []
	_signature_walk(n, parts)
	return hash(parts)


func _signature_walk(n: Node, parts: Array) -> void:
	# Auto-generated names (@Node3D@1234) carry a GLOBAL monotonic counter, so two identical
	# builds never share them; the class stands in. Authored names are the real signature.
	parts.append(n.get_class() if String(n.name).begins_with("@") else String(n.name))
	if n is Node3D:
		parts.append((n as Node3D).transform)
	for c in n.get_children():
		_signature_walk(c, parts)


func _count_doors(n: Node) -> int:
	var count := 0
	for node in _walk(n):
		if node is DungeonDoor:
			count += 1
	return count


func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _done(msg: String) -> void:
	_suites_done += 1
	_say("[VERIFY] " + msg)


func _say(msg: String) -> void:
	print(msg)
	_log += msg + "\n"

extends SceneTree
## THE EDITOR-SAFETY GATE for the foliage patches.
##
##   Godot_console.exe --path . --resolution 640x360 \
##       --script res://scripts/dev/probe_editor_foliage.gd
##
## Marking a node @tool hands the editor the right to run and SAVE it, and both of those go wrong in
## ways that are invisible until a scene file has already been ruined. Each check below is one of
## those ways:
##
##   1 NO GENERATED DATA IN THE SCENE — the reason _validate_property() exists. A painted field is
##     its stroke list; the instance buffer is derived. If the buffer serializes, one Ctrl+S writes
##     180,000 floats per field into scenes/world/room.tscn and the derivation becomes a lie.
##   2 THE FLAG IS ACTUALLY OFF — check 1 could pass for the wrong reason (an empty buffer), so the
##     property's usage bits are read directly.
##   3 REBUILD OUTSIDE THE TREE — a property setter fires before a node is in the tree, and that is
##     now the normal path into rebuild(). get_tree() is null there, not empty.
##   4 UNBUILT TERRAIN IS NOT GROUND — terrain_field.gd is deliberately NOT @tool, so in the editor
##     its grid is never allocated. Asking it for a height indexes an empty array once per instance.
##   5 A THICKET WITHOUT A MESH IS QUIET — creating a layer means it exists before its mesh_source
##     does, and a warning per rebuild would fill the Output panel with normal behaviour.
##   6 THE PAST DOES NOT CHANGE SIZE — brush_radius used to be one number for the whole field, so
##     changing it reshaped every dab already laid the next time anything rebuilt.
##   7 A REBUILT THICKET IS THE THICKET THAT WAS PAINTED — the property the eraser depends on, and
##     the one BushPatch did not have before it was given an eraser.

var _fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_check_not_serialized()
	_check_storage_flag()
	_check_rebuild_detached()
	_check_unbuilt_terrain()
	_check_quiet_without_mesh()
	_check_radius_history()
	_check_bush_erase()
	await _check_shipping_scene()
	_check_surface_follow()

	print("")
	print("[EDFOL] %s" % ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _ok(name: String, pass_: bool, detail: String) -> void:
	print("[EDFOL] %-16s %s  %s" % [name, "PASS" if pass_ else "FAIL", detail])
	if not pass_:
		_fails += 1


## 1. Pack and save a scene holding a painted patch, then read the file back as TEXT. Text, not a
## re-load: the question is what landed on disk, and a loader would happily rebuild the field and
## hide the answer.
func _check_not_serialized() -> void:
	var root := Node3D.new()
	root.name = "Root"
	get_root().add_child(root)

	var g := GrassPatch.new()
	g.name = "Painted"
	g.paint_only = true
	g.density = 6.0
	g.rng_seed = 11
	root.add_child(g)
	g.owner = root
	for k in 5:
		g.append_stroke(Vector2(-4.0 + k * 2.0, 0.0))

	var b := BushPatch.new()
	b.name = "Thicket"
	b.paint_only = true
	b.mesh_source = load("res://assets/models/veg_leaf_bush_b.glb")
	root.add_child(b)
	b.owner = root
	b.append_stroke(Vector2.ZERO)

	var packed := PackedScene.new()
	var packed_err := packed.pack(root)
	var path := "user://_probe_editor_foliage.tscn"
	var save_err := ResourceSaver.save(packed, path)
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.open(path, FileAccess.READ).get_as_text()

	var has_mm := text.contains('sub_resource type="MultiMesh"')
	var has_mat := text.contains('sub_resource type="ShaderMaterial"')
	var has_strokes := text.contains("brush_points")
	var instances: int = g.multimesh.instance_count if g.multimesh else 0

	_ok("not serialized", packed_err == OK and save_err == OK
			and not has_mm and not has_mat and has_strokes and instances > 0,
			"%d live instances, MultiMesh in file: %s, ShaderMaterial in file: %s, strokes kept: %s"
			% [instances, has_mm, has_mat, has_strokes])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.queue_free()


## 2. Read the usage bits straight off the property list. Check 1 passing with an EMPTY buffer would
## look identical to check 1 passing because the flag is off, and only one of those is the feature.
func _check_storage_flag() -> void:
	var g := GrassPatch.new()
	var b := BushPatch.new()
	var report := {}
	for pair: Array in [[g, "multimesh"], [g, "material_override"], [b, "multimesh"],
			[b, "material_override"]]:
		var node: Node = pair[0]
		for p: Dictionary in node.get_property_list():
			if p.name == pair[1]:
				report["%s.%s" % [node.get_class() if node is BushPatch else "Grass", pair[1]]] = \
						(int(p.usage) & PROPERTY_USAGE_STORAGE) != 0
	var grass_mm: bool = report.get("Grass.multimesh", true)
	var grass_mat: bool = report.get("Grass.material_override", true)
	# BushPatch KEEPS material_override storable on purpose — the scene assigns a real .tres there.
	var bush_mat: bool = report.get("MultiMeshInstance3D.material_override", false)
	_ok("storage flag", not grass_mm and not grass_mat and bush_mat,
			"grass multimesh stored=%s, grass material stored=%s, bush material stored=%s (bush must be true)"
			% [grass_mm, grass_mat, bush_mat])
	g.free()
	b.free()


## 3. The setters added for the Inspector call _mark_dirty(), and Godot applies exported values
## BEFORE a node enters the tree. rebuild() must survive being reached there.
func _check_rebuild_detached() -> void:
	var g := GrassPatch.new()
	g.paint_only = true
	g.density = 4.0
	g.rebuild()                      # never added to any tree
	var b := BushPatch.new()
	b.mesh_source = load("res://assets/models/veg_leaf_bush_b.glb")
	b.rebuild()
	_ok("detached rebuild", true, "GrassPatch and BushPatch both rebuilt outside the tree")
	g.free()
	b.free()


## 4. Stand in for the editor's view of a TerrainField: a node that answers side() with 0 and would
## fault if its heights were ever read. The guard must never ask.
class UnbuiltGround extends Node3D:
	var asked := false

	func side() -> int:
		return 0

	func height_at(_local: Vector2) -> float:
		asked = true
		return 0.0

	func normal_at(_local: Vector2) -> Vector3:
		asked = true
		return Vector3.UP


func _check_unbuilt_terrain() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var ground := UnbuiltGround.new()
	ground.name = "Ground"
	root.add_child(ground)

	var g := GrassPatch.new()
	g.paint_only = true
	g.density = 6.0
	root.add_child(g)
	g.terrain = g.get_path_to(ground)
	for k in 4:
		g.append_stroke(Vector2(k * 2.0, 0.0))

	var flat := true
	for i in g.multimesh.instance_count:
		if absf(g.multimesh.get_instance_transform(i).origin.y) > 0.5:
			flat = false
			break
	_ok("unbuilt terrain", not ground.asked and g.multimesh.instance_count > 0 and flat,
			"height queried: %s, %d instances, all near y=0: %s"
			% [ground.asked, g.multimesh.instance_count, flat])
	root.queue_free()


## 5. No Output-panel noise for the ordinary case of a layer that has not been given its mesh yet.
func _check_quiet_without_mesh() -> void:
	var b := BushPatch.new()
	b.paint_only = true
	b.rebuild()
	b.append_stroke(Vector2.ZERO)
	var count: int = b.multimesh.instance_count if b.multimesh else 0
	_ok("quiet no-mesh", count == 0, "mesh-less thicket built %d instances and no warning" % count)
	b.free()


## 6. Paint at one radius, change the brush, rebuild — the first dabs must come back the size they
## were laid. Compared as an instance count, which is what a radius change actually moves.
func _check_radius_history() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var g := GrassPatch.new()
	g.paint_only = true
	g.density = 8.0
	g.rng_seed = 5
	g.brush_radius = 1.5
	root.add_child(g)
	for k in 4:
		g.append_stroke(Vector2(k * 3.0, 0.0))
	var painted: int = g.multimesh.instance_count

	g.brush_radius = 4.0            # the next dab would be wider; the four already laid must not be
	g.rebuild()
	var replayed: int = g.multimesh.instance_count

	_ok("radius history", painted == replayed and g.brush_radii.size() == 4,
			"%d painted, %d after a radius change and rebuild, %d radii recorded"
			% [painted, replayed, g.brush_radii.size()])
	root.queue_free()


## 9. PAINT LANDS ON THE SURFACE, NOT ON THE PATCH'S OWN PLANE.
##
## This is the check that was missing when the brush first went into a real scene. A patch scatters
## on its local XZ plane, and the plugin adds a new layer at the scene root — so every plant landed
## at the root's Y no matter where the ray hit. Paint a village floor 13 m down and the grass hangs
## in the air above it.
##
## Two halves, because fixing only the first one terraces the field: the HEIGHT has to follow the
## surface, and so does the SLOPE, or each dab is a level disc stepping against its neighbours.
func _check_surface_follow() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var g := GrassPatch.new()
	g.paint_only = true
	g.density = 8.0
	g.rng_seed = 21
	g.sink = 0.0
	g.slope_align = 0.0          # isolate placement from tilt
	root.add_child(g)

	# A 30-degree slope descending along +X, sampled at three points along it, exactly as a brush
	# dragged across a hillside would.
	var slope := deg_to_rad(30.0)
	var n := Vector3(sin(slope), cos(slope), 0.0)
	for k in 3:
		var c := Vector2(-4.0 + k * 4.0, 0.0)
		FoliageBrush.paint_into(g, Vector3(c.x, -12.0 - c.x * tan(slope), c.y), 2.0, n)

	var worst := 0.0
	var lifted := 0
	for i in g.multimesh.instance_count:
		var o := g.multimesh.get_instance_transform(i).origin
		var want := -12.0 - o.x * tan(slope)      # the plane the strokes were laid on
		worst = maxf(worst, absf(o.y - want))
		if o.y < -1.0:
			lifted += 1
	_ok("surface follow", g.multimesh.instance_count > 0 and worst < 0.01
			and lifted == g.multimesh.instance_count,
			"%d plants, worst %.4f m off the slope they were painted on, %d below y=-1"
			% [g.multimesh.instance_count, worst, lifted])
	root.queue_free()


## 8. THE SAME QUESTION, ASKED OF THE REAL SCENE. Check 1 builds a small field on purpose; this one
## loads scenes/world/room.tscn — four grass fields and four thickets, ~21,000 live instances — lets
## them build, re-packs it exactly as Ctrl+S does, and requires the result to carry none of it.
##
## This is the check that stands in for "open the hub in the editor and save it". If it ever fails,
## the next person to press Ctrl+S adds megabytes of generated floats to a shipping scene.
func _check_shipping_scene() -> void:
	var scene := load("res://scenes/world/room.tscn") as PackedScene
	var room := scene.instantiate()
	get_root().add_child(room)
	for _i in 20:
		await process_frame

	var live := 0
	for n in _all_patches(room):
		live += n.multimesh.instance_count if n.multimesh else 0

	var repacked := PackedScene.new()
	repacked.pack(room)
	var path := "user://_probe_room_resave.tscn"
	ResourceSaver.save(repacked, path)
	var text := FileAccess.open(path, FileAccess.READ).get_as_text()
	var mm := text.count('type="MultiMesh"')
	var kb := text.length() / 1024

	# The assertion is about SERIALIZATION, not about how much grass the hub happens to contain, so
	# it demands only that something built and that none of it reached the file. It used to require
	# more than 10,000 instances, which quietly made the test a second opinion on scene content —
	# and it went red the day three grass fields were removed from room.tscn, reporting a
	# serialization failure that had not happened.
	_ok("shipping scene", mm == 0 and live > 0,
			"%d live instances across the hub, %d MultiMesh sub-resources written, %d KB scene"
			% [live, mm, kb])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	room.queue_free()


func _all_patches(n: Node, out: Array = []) -> Array:
	if n is GrassPatch or n is BushPatch:
		out.append(n)
	for c in n.get_children():
		_all_patches(c, out)
	return out


## 7. A carved gap must survive a rebuild, which it can only do if the rebuild reproduces the same
## thicket the erase was recorded against.
func _check_bush_erase() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var b := BushPatch.new()
	b.paint_only = true
	b.density = 3.0
	b.rng_seed = 9
	b.mesh_source = load("res://assets/models/veg_leaf_bush_b.glb")
	root.add_child(b)
	for k in 5:
		b.append_stroke(Vector2(-4.0 + k * 2.0, 0.0))
	var before: int = b.multimesh.instance_count
	var removed: int = b.erase_stroke(Vector2.ZERO, 3.0, 0.8)
	var after: int = b.multimesh.instance_count

	# Capture every surviving position, then regenerate from the stroke record alone.
	var kept: Array[Vector3] = []
	for i in after:
		kept.append(b.multimesh.get_instance_transform(i).origin)
	b.rebuild()
	var same := b.multimesh.instance_count == after
	if same:
		for i in after:
			if b.multimesh.get_instance_transform(i).origin.distance_to(kept[i]) > 0.0001:
				same = false
				break

	_ok("bush erase", removed > 0 and after == before - removed and same,
			"%d shrubs, erased %d, %d left, replay identical: %s" % [before, removed, after, same])
	root.queue_free()

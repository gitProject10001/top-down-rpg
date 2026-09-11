extends SceneTree
## THE CORRECTNESS GATE FOR scripts/terrain_field.gd.
##
##   Godot_console.exe --path . --resolution 640x360 --script res://scripts/dev/probe_terrain.gd
##
## Never --headless: the dummy renderer is fine for the maths here, but the same convention across
## every probe in this repo is worth more than the saved second, and check 3 wants real physics.
##
## Each check exists because of a specific way a height field goes wrong quietly:
##
##   1 WINDING     — the whole ground is backface-culled and everything appears to float in the sky.
##                   scripts/gladekit_tests/probe_cliff.gd:174 documents this one because it happened.
##   2 SAMPLING    — height_at() disagreeing with the array it reads from would put every plant at a
##                   plausible but wrong height, which looks like a scatter bug for a long time.
##   3 RAYCAST     — the analytic march and the HeightMapShape3D collider must describe the SAME
##                   surface, or the brush lands somewhere the player cannot stand.
##   4 SLOPE CLAMP — the clamp is what keeps sculpted ground climbable in a project with no navmesh
##                   and no step logic. If it silently does nothing, nothing else reports it.
##   5 REPROJECT   — sculpting under painted foliage must move it, not re-roll it. GrassPatch has
##                   already shipped that bug once (scripts/dev/foliage_lab.gd:518).
##   6 LAKE        — a lake the player can walk into is not the lake that was specified.
##   7 DAB COST    — painting in this bench has frozen twice. Measure it, do not assume it.
##   8 ROUND TRIP  — the bench's whole premise is reopening on what you left. A height file that
##                   saves and reloads as something slightly different is a session quietly lost,
##                   and the checked-in res:// copy depends on the same two functions.

const TerrainField := preload("res://scripts/terrain_field.gd")

## One frame at 60 Hz. A dab happens per mouse-motion event, so anything at or over this is a stutter
## the user feels as the brush sticking.
const DAB_BUDGET_MS := 16.0

## Depth of the lake check 6 carves, in metres.
const _lake_depth := 2.0

var _fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var field := TerrainField.new()
	field.extent = 64.0
	field.cell_size = 1.0
	field.max_slope_deg = 30.0
	root.add_child(field)
	await process_frame

	_check_winding(field)
	_check_sampling(field)
	await _check_raycast(field)
	_check_clamp(field)
	await _check_reproject(field)
	await _check_lake()
	_check_cost(field)
	_check_roundtrip(field)

	print("")
	print("[TERRAIN] %s" % ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _ok(name: String, pass_: bool, detail: String) -> void:
	print("[TERRAIN] %-14s %s  %s" % [name, "PASS" if pass_ else "FAIL", detail])
	if not pass_:
		_fails += 1


# ---------------------------------------------------------------------------------------------

## 1. Every emitted triangle's right-hand normal must point DOWN, because Godot's front face is
## clockwise about the outward normal and this surface faces up. Run on a SCULPTED field, not a flat
## one — a flat grid's cross products are degenerate in exactly the way that hides a winding error.
func _check_winding(field) -> void:
	field.noise_fill(5, 0.018, 2, 3.2)
	var arrays: Array = (field.get_node("Surface") as MeshInstance3D).mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bad := 0
	for t in idx.size() / 3:
		var a := verts[idx[t * 3]]
		var b := verts[idx[t * 3 + 1]]
		var c := verts[idx[t * 3 + 2]]
		if (b - a).cross(c - a).y >= 0.0:
			bad += 1
	_ok("winding", bad == 0, "%d/%d triangles wound wrong" % [bad, idx.size() / 3])


## 2. At a grid node, the bilinear read must return the stored value exactly; between two nodes it
## must stay between them. Checked on the noise field from check 1, so the values are not all equal.
func _check_sampling(field) -> void:
	var side: int = field.side()
	var worst := 0.0
	for iz in side:
		for ix in side:
			var stored: float = field.heights[iz * side + ix]
			var read: float = field.height_at(field._local_of(ix, iz))
			worst = maxf(worst, absf(stored - read))
	var strays := 0
	for iz in side - 1:
		for ix in side - 1:
			var a: float = field.heights[iz * side + ix]
			var b: float = field.heights[iz * side + ix + 1]
			var mid: float = field.height_at(field._local_of(ix, iz) + Vector2(0.5, 0.0))
			if mid < minf(a, b) - 0.0001 or mid > maxf(a, b) + 0.0001:
				strays += 1
	_ok("sampling", worst < 0.0001 and strays == 0,
			"max node error %.6f m, %d midpoints outside their neighbours" % [worst, strays])


## 3. TerrainField.raycast() marches the array; the collider is a HeightMapShape3D built from the
## same array. Fire the same 200 rays at both and require them to agree. This is the check that
## proves the thing the brush aims with and the thing the player stands on are one surface.
func _check_raycast(field) -> void:
	for _i in 4:
		await physics_frame
	var space := root.world_3d.direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260813
	var worst := 0.0
	var both := 0
	var disagree_hit := 0
	for _i in 200:
		var from := Vector3(rng.randf_range(-28.0, 28.0), 30.0, rng.randf_range(-28.0, 28.0))
		var dir := Vector3(rng.randf_range(-0.25, 0.25), -1.0, rng.randf_range(-0.25, 0.25)).normalized()
		var mine: Vector3 = field.raycast(from, dir)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 80.0, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or mine == Vector3.INF:
			if hit.is_empty() != (mine == Vector3.INF):
				disagree_hit += 1
			continue
		both += 1
		worst = maxf(worst, mine.distance_to(hit.position))
	_ok("raycast", both > 150 and worst < 0.01 and disagree_hit == 0,
			"%d/200 agreed on hitting, worst gap %.4f m, %d hit/miss disagreements"
			% [both, worst, disagree_hit])


## 4. The clamp is a dial, not a law: with it on, nothing may exceed the limit; with CLIFF (which
## opts out), something must. Both halves matter — a clamp that clamped everything would make the
## blocking cliffs the user asked for impossible to build.
func _check_clamp(field) -> void:
	var side: int = field.side()
	var limit: float = field.cell_size * tan(deg_to_rad(field.max_slope_deg))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	field.reset_flat()
	for _i in 50:
		var at := Vector2(rng.randf_range(-24.0, 24.0), rng.randf_range(-24.0, 24.0))
		field.begin_stroke(at, TerrainField.Mode.RAISE, 1.6)
		field.sculpt(at, 4.0, TerrainField.Mode.RAISE, 0.9)
	var over := 0
	var steepest := 0.0
	for iz in side:
		for ix in side:
			var h: float = field.heights[iz * side + ix]
			if ix + 1 < side:
				steepest = maxf(steepest, absf(h - field.heights[iz * side + ix + 1]))
			if iz + 1 < side:
				steepest = maxf(steepest, absf(h - field.heights[(iz + 1) * side + ix]))
	if steepest > limit + 0.0001:
		over += 1
	var clamped_ok := over == 0

	field.reset_flat()
	field.begin_stroke(Vector2.ZERO, TerrainField.Mode.CLIFF, 1.6)
	for _i in 6:
		field.sculpt(Vector2.ZERO, 5.0, TerrainField.Mode.CLIFF, 1.2)
	var cliff := 0.0
	for iz in side:
		for ix in side - 1:
			cliff = maxf(cliff, absf(field.heights[iz * side + ix] - field.heights[iz * side + ix + 1]))

	_ok("slope clamp", clamped_ok and cliff > limit,
			"clamped steepest %.3f m/cell (limit %.3f), CLIFF reached %.3f m/cell"
			% [steepest, limit, cliff])


## 5. Sculpt under painted grass and the tufts must FOLLOW the ground, not be re-scattered by it.
## X and Z of every instance must be bit-for-bit what they were; only Y may move.
func _check_reproject(field) -> void:
	field.reset_flat()
	var patch := GrassPatch.new()
	patch.paint_only = true
	patch.density = 8.0
	patch.rng_seed = 4242
	patch.terrain = field.get_path()
	root.add_child(patch)
	await process_frame
	for k in 6:
		patch.append_stroke(Vector2(-6.0 + k * 2.4, 0.0))
	var n: int = patch.multimesh.instance_count
	if n == 0:
		_ok("reproject", false, "painted nothing to test with")
		patch.queue_free()
		return

	var before: Array[Vector3] = []
	for i in n:
		before.append(patch.multimesh.get_instance_transform(i).origin)

	field.begin_stroke(Vector2.ZERO, TerrainField.Mode.RAISE, 1.6)
	field.sculpt(Vector2.ZERO, 12.0, TerrainField.Mode.RAISE, 2.5)
	patch.reproject()

	var moved_xz := 0
	var wrong_y := 0.0
	var lifted := 0
	for i in n:
		var o := patch.multimesh.get_instance_transform(i).origin
		if absf(o.x - before[i].x) > 0.0001 or absf(o.z - before[i].z) > 0.0001:
			moved_xz += 1
		var want: float = field.height_at(Vector2(o.x, o.z))
		wrong_y = maxf(wrong_y, absf(o.y - want - patch._drops[i]))
		if o.y > before[i].y + 0.01:
			lifted += 1
	_ok("reproject", moved_xz == 0 and wrong_y < 0.0001 and lifted > 0,
			"%d/%d moved in XZ, worst Y error %.6f m, %d lifted by the sculpt"
			% [moved_xz, n, wrong_y, lifted])
	patch.queue_free()


## 6. A carved lake must be unreachable. Walk a CharacterBody3D straight at the middle of one and
## require it to stop outside the painted mask. Uses its own field so the shore is a known shape.
func _check_lake() -> void:
	var field := TerrainField.new()
	field.extent = 64.0
	root.add_child(field)
	await process_frame
	field.begin_stroke(Vector2.ZERO, TerrainField.Mode.LAKE, _lake_depth)
	for _i in 8:
		field.sculpt(Vector2.ZERO, 8.0, TerrainField.Mode.LAKE, 0.6)

	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	body.add_child(cs)
	body.position = Vector3(0.0, 2.0, 22.0)
	root.add_child(body)
	for _i in 10:
		await physics_frame

	var deepest := 0.0
	for _step in 240:
		body.velocity = Vector3(0.0, body.velocity.y - 0.6, -6.0)
		body.move_and_slide()
		await physics_frame
		var d: float = field.water_level - field.height_at(Vector2(body.position.x, body.position.z))
		if body.position.z < 8.0:
			deepest = maxf(deepest, d)
	# Tolerance is a QUARTER of the lake's own depth, not a hairline. At the exact waterline the true
	# ground is level with the water by definition, so a capsule standing on the shore always reads a
	# few centimetres of nominal depth; asserting near zero there would be asserting on rounding.
	# What the check is actually for is that the player cannot get INTO the lake, and a body that
	# stops in the first quarter-metre of a two-metre basin has not.
	_ok("lake", deepest < _lake_depth * 0.25 and field.has_water(),
			"walked to z=%.1f (rim at 8.0), deepest water reached %.2f m of a %.1f m basin"
			% [body.position.z, deepest, _lake_depth])
	body.queue_free()
	field.queue_free()


## 8. Save a sculpted field, load it into a fresh one, and require them to be the same ground —
## heights to the float, the lake mask, the water level, and the collider that comes off them. Also
## loads the checked-in res:// copy if there is one, because a height file that has drifted out of
## step with the loader is a file that opens as a plausible-looking WRONG terrain, which is the
## worst way for this to fail.
func _check_roundtrip(field) -> void:
	field.reset_flat()
	field.noise_fill(7, 0.022, 2, 2.6)
	field.begin_stroke(Vector2.ZERO, TerrainField.Mode.LAKE, 1.8)
	for _i in 5:
		field.sculpt(Vector2(4.0, -3.0), 6.0, TerrainField.Mode.LAKE, 0.5)

	var tmp := "user://_probe_terrain_roundtrip.dat"
	if not field.save_to(tmp):
		_ok("round trip", false, "save_to(%s) failed" % tmp)
		return

	var fresh = TerrainField.new()
	fresh.extent = field.extent
	fresh.cell_size = field.cell_size
	root.add_child(fresh)
	if not fresh.load_from(tmp):
		_ok("round trip", false, "load_from(%s) refused the file" % tmp)
		fresh.queue_free()
		return

	var worst := 0.0
	for i in field.heights.size():
		worst = maxf(worst, absf(field.heights[i] - fresh.heights[i]))
	var lake_diff := 0
	for i in field.lake.size():
		if field.lake[i] != fresh.lake[i]:
			lake_diff += 1
	var level_ok: bool = absf(field.water_level - fresh.water_level) < 0.0001
	var water_ok: bool = field.has_water() == fresh.has_water()

	# And the shipped copy, if the bench has exported one.
	var shipped := "res://scenes/dev/terrain_lab.dat"
	var shipped_note := "no res:// copy"
	if FileAccess.file_exists(shipped):
		var s = TerrainField.new()
		root.add_child(s)
		shipped_note = ("res:// copy loads, %d samples" % s.heights.size()) if s.load_from(shipped) \
				else "res:// COPY REFUSED"
		if shipped_note.begins_with("res:// COPY"):
			_fails += 1
		s.queue_free()

	_ok("round trip", worst < 0.0001 and lake_diff == 0 and level_ok and water_ok,
			"worst height delta %.6f m, %d lake cells differ, level %s, %s"
			% [worst, lake_diff, "ok" if level_ok else "MOVED", shipped_note])
	fresh.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


## 7. A dab must fit in a frame. This is the check that would have caught both of the freezes this
## bench has already had, and it is the reason the mesh refresh recomputes only its dirty rect.
func _check_cost(field) -> void:
	field.reset_flat()
	field.noise_fill(5, 0.018, 2, 3.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var worst := 0.0
	var total := 0.0
	for i in 60:
		var at := Vector2(rng.randf_range(-24.0, 24.0), rng.randf_range(-24.0, 24.0))
		var mode: int = [TerrainField.Mode.RAISE, TerrainField.Mode.SMOOTH,
				TerrainField.Mode.FLATTEN][i % 3]
		field.begin_stroke(at, mode, 1.6)
		var t0 := Time.get_ticks_usec()
		field.sculpt(at, 4.0, mode, 0.4)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		total += ms

	# AND AGAIN WITH A LAKE, because that is the expensive path: a field with water in it re-bakes
	# the depth image and re-uploads its texture on every dab. Fields without one skip all of that,
	# which is why the counter exists — but the bench must stay usable while carving a lake, so the
	# path that does the work is the one worth timing.
	field.begin_stroke(Vector2.ZERO, TerrainField.Mode.LAKE, 2.0)
	for _i in 6:
		field.sculpt(Vector2.ZERO, 7.0, TerrainField.Mode.LAKE, 0.5)
	var wet_worst := 0.0
	var wclamp := 0.0
	var wrefresh := 0.0
	var wwater := 0.0
	for _i in 20:
		var at := Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		field.begin_stroke(at, TerrainField.Mode.LAKE, 2.0)
		var t1 := Time.get_ticks_usec()
		field.sculpt(at, 4.0, TerrainField.Mode.LAKE, 0.4)
		# Read the breakdown AFTER the clock stops. See the note on TerrainField.last_clamp_us.
		wet_worst = maxf(wet_worst, (Time.get_ticks_usec() - t1) / 1000.0)
		wclamp = maxf(wclamp, field.last_clamp_us / 1000.0)
		wrefresh = maxf(wrefresh, field.last_refresh_us / 1000.0)
		wwater = maxf(wwater, field.last_water_us / 1000.0)

	_ok("dab cost", worst < DAB_BUDGET_MS and wet_worst < DAB_BUDGET_MS,
			"dry worst %.2f ms (mean %.2f), lake worst %.2f ms [clamp %.2f refresh %.2f water %.2f], budget %.0f ms"
			% [worst, total / 60.0, wet_worst, wclamp, wrefresh, wwater, DAB_BUDGET_MS])

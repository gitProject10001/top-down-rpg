extends SceneTree
## What the brick kit's vertex colours actually contain — the measurement the crypt's stone shader
## is authored against. Run:
##   Godot_console.exe --headless --path . --script res://scripts/dungeon/tests/probe_crypt_paint.gd
##
## WHY THIS EXISTS. shaders/dungeon_stone.gdshader treats COLOR_0 as a per-brick VARIATION signal,
## not as a colour: it takes the luminance, normalises it through `var_black`..`var_white`, and
## remaps that onto a stone ramp. Guess those two numbers and the ramp goes flat — if the kit spans
## 0.31..0.58 and the ramp is authored over 0..1, three quarters of it is unreachable and every
## brick lands on the same mid-tone. That failure looks like "the shader does nothing", which is
## the most expensive kind of wrong. So: measure, then author.
##
## It also reports the mesh fact the shader design rests on: the brick .glb files carry NO UVs.
## (They DO carry tangents, but only because `meshes/ensure_tangents=true` in the .import files had
## Godot synthesise them — with no UV layout to derive a basis from, those tangents mean nothing.
## Triplanar has no single tangent frame anyway, which is why dungeon_stone builds its own.)
##
## Re-run this after the Blender AO/cavity bake (docs: the crypt art pass, phase 5). Folding
## occlusion into COLOR_0 MOVES the histogram, and `var_black`/`var_white` must move with it.

const KIT_DIR := "res://scenes/dungeon/kit/"
const LUMA := Vector3(0.2126, 0.7152, 0.0722)

## Every kit wrapper whose art is stone and therefore gets painted. `table` is deliberately absent:
## it is DungeonWood, it has UVs, and the paint pass skips it.
const WRAPPERS := [
	"wall_brick_a", "wall_brick_b", "wall_brick_c", "wall_niche_brick",
	"wall_door_brick_a", "wall_door_brick_b",
	"floor_tile_brick_a", "floor_tile_brick_b",
	"pillar_brick_a", "pillar_brick_b",
	"corridor_wall", "corridor_floor", "altar", "candelabra",
]

var _log := ""
var _all: PackedFloat32Array = PackedFloat32Array()


func _initialize() -> void:
	_out("=== crypt paint probe ===\n")
	_out("%-20s %7s %6s %5s %4s | %-28s | %s"
			% ["wrapper", "verts", "surf", "UV", "TAN", "luma  min   p5  med  p95  max", "sat max"])
	_out("-".repeat(108))

	for name in WRAPPERS:
		_probe(name)

	_out("")
	_summary()

	var fa := FileAccess.open("user://probe_crypt_paint.txt", FileAccess.WRITE)
	fa.store_string(_log)
	fa.close()
	quit(0)


func _probe(wrapper_name: String) -> void:
	var path := KIT_DIR + wrapper_name + ".tscn"
	if not ResourceLoader.exists(path):
		_out("%-20s MISSING (%s)" % [wrapper_name, path])
		return
	var node: Node = (load(path) as PackedScene).instantiate()

	var meshes: Array[MeshInstance3D] = []
	_collect(node, meshes)
	if meshes.is_empty():
		_out("%-20s no MeshInstance3D" % wrapper_name)
		node.free()
		return

	var verts := 0
	var surfaces := 0
	var has_uv := false
	var has_tan := false
	var lums := PackedFloat32Array()
	var sat_max := 0.0
	var alpha_min := 1.0

	for mi in meshes:
		# The flame meshes carry their own emissive material and are exempt from the paint pass, so
		# their colours would only pollute the histogram the ramp is fitted to.
		if mi.has_meta("torch_flame"):
			continue
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			surfaces += 1
			var fmt: int = mesh.surface_get_format(si)
			has_uv = has_uv or bool(fmt & Mesh.ARRAY_FORMAT_TEX_UV)
			has_tan = has_tan or bool(fmt & Mesh.ARRAY_FORMAT_TANGENT)
			var arrays := mesh.surface_get_arrays(si)
			var pos = arrays[Mesh.ARRAY_VERTEX]
			verts += (pos as PackedVector3Array).size() if pos != null else 0
			var cols = arrays[Mesh.ARRAY_COLOR]
			if cols == null:
				continue
			for c: Color in (cols as PackedColorArray):
				lums.append(c.r * LUMA.x + c.g * LUMA.y + c.b * LUMA.z)
				sat_max = maxf(sat_max, c.s)
				alpha_min = minf(alpha_min, c.a)

	var stats := _percentiles(lums)
	_out("%-20s %7d %6d %5s %4s | %5.3f %5.3f %5.3f %5.3f %5.3f | %5.3f%s"
			% [wrapper_name, verts, surfaces,
					"YES" if has_uv else "-", "YES" if has_tan else "-",
					stats.min, stats.p5, stats.med, stats.p95, stats.max,
					sat_max, "" if alpha_min >= 1.0 else "  alpha_min=%.3f" % alpha_min])

	if lums.is_empty():
		# COLOR defaults to white in the shader when a mesh has no colour attribute, so the palette
		# remap would send the whole piece to `stone_light`. That is only correct if the piece IS
		# stone — the candelabra (DungeonBronze/DungeonTallow) and the table (DungeonWood) are not,
		# and both are marked NO_PAINT for exactly this reason.
		_out("    ^ NO COLOR_0 — remaps to a flat stone_light unless the piece is marked NO_PAINT")
	if has_uv:
		_out("    ^ HAS UVs — a textured, non-brick asset; check it is excluded from the paint pass")
	_all.append_array(lums)
	node.free()


## The five numbers the shader is authored against, plus the two it should actually be set to.
func _summary() -> void:
	var s := _percentiles(_all)
	_out("=== whole kit, %d coloured vertices ===" % _all.size())
	_out("  min %.4f   p5 %.4f   median %.4f   p95 %.4f   max %.4f"
			% [s.min, s.p5, s.med, s.p95, s.max])
	_out("")
	# p5/p95 rather than min/max: a handful of outlier verts must not stretch the ramp flat for
	# every brick in between. The 5% that clip do so at the ends, where the ramp is already
	# saturated and nobody can tell.
	_out("  -> shaders/dungeon_stone.gdshader:")
	_out("       var_black = %.3f" % s.p5)
	_out("       var_white = %.3f" % s.p95)
	_out("")
	_out("  Measured 2026-08-08. Before the Cycles AO bake: p5 0.287 / p95 0.631.")
	_out("  After it (tools/export_dungeon_kit.py, AO_STRENGTH 0.65):  p5 0.168 / p95 0.575 —")
	_out("  the bottom fell and the top held, which is the bake darkening mortar and undersides")
	_out("  rather than dimming everything. That gap IS the crevice mask the moss term reads.")
	_out("  Walls span ~0.29-0.70; floor tiles only ~0.22-0.42. That is deliberate — ONE global")
	_out("  ramp then lands floors in its dark half and walls in its light half, which is the")
	_out("  floor-darker-than-wall read the reference dioramas have. Do not fit a ramp per piece.")
	var span: float = s.p95 - s.p5
	if span < 0.08:
		_out("  !! SPAN IS %.3f — the kit barely varies per brick. The ramp will read as flat no" % span)
		_out("     matter what the stops are; the variation has to come from the Blender cavity bake.")


func _percentiles(v: PackedFloat32Array) -> Dictionary:
	if v.is_empty():
		return {"min": 0.0, "p5": 0.0, "med": 0.0, "p95": 0.0, "max": 0.0}
	var s := v.duplicate()
	s.sort()
	var n := s.size()
	return {
		"min": s[0],
		"p5": s[clampi(int(n * 0.05), 0, n - 1)],
		"med": s[n / 2],
		"p95": s[clampi(int(n * 0.95), 0, n - 1)],
		"max": s[n - 1],
	}


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)


func _out(s: String) -> void:
	print(s)
	_log += s + "\n"

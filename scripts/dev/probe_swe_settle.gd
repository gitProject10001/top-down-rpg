extends SceneTree
## DOES THE LAKE EVER STOP VIBRATING, and is it the whole lake or only its edge?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_settle.gd
##
## The report is that the water "is like vibrating", with the observation that in reality vibrations
## go off after some time, and the suspicion that it is "how you fill the lake". Both halves are
## testable, and they predict different SHAPES:
##
##   IF IT IS THE FILL, the seed carries a one-off perturbation - h is stored in float16, so
##   w = b + h misses the flat surface it was seeded to by up to half an ulp per cell - and with
##   drag at 0.7 (a one-second half-life) it must DECAY. Roughness falls and stays down.
##
##   IF IT IS THE STORE, round_store dithers h every cell every step and the staggered scheme has no
##   diffusion to sweep it up, so roughness falls to a FLOOR and sits there for ever.
##
## THE FLAT PAN ALREADY ANSWERED HALF OF IT and ruled the store out: on a flat bed both schemes hold
## 0.00 ulp for 1200 steps at 0.55 m AND at 2.25 m, because a resting cell has no increment and
## round_store's v_prev guard hands it straight back. The store does not shake a lake that is
## sitting still.
##
## So this runs the REAL THING - water_lab's wilds-generated lake - and separates the MIDDLE from
## the SHORE, because "the water is vibrating" and "the shoreline is ringing" look identical from a
## camera and want completely different fixes. What is different about this lake is its edge: the
## wilds bed falls from 0.2 m below the tier top at a corner touching dry to lake_depth at
## mid-water, which at 2.6 m is a 2.4 m drop across ONE 2 m cell - a 120 % slope, against the 3 %
## the bench's analytic beds use.

var _rip: Node = null
var _lab: Node = null
var _fail := 0


func _initialize() -> void:
	_lab = (load("res://scenes/dev/water_lab.tscn") as PackedScene).instantiate()
	root.add_child(_lab)
	current_scene = _lab
	for _i in 90:
		await process_frame
	_rip = root.get_node("/root/Ripples")
	_rip.set("paused", true)

	var res := int(_rip.get("RES"))
	var depth := 2.25
	var ulp: float = pow(2.0, floor(log(depth) / log(2.0)) - 10.0)
	print("[SETTLE] wilds lake, %.2f m, one float16 ulp = %.4f mm; depth_mode %s staggered %s"
			% [depth, ulp * 1000.0, _rip.get("depth_mode"), _rip.get("staggered")])
	print("[SETTLE] POLICY: wave_scale %.2f (c = %.2f m/s), smooth_grid %.3f"
			% [float(_rip.call("sim_get", &"wave_scale")),
			sqrt(9.81 * depth * float(_rip.call("sim_get", &"wave_scale"))),
			float(_rip.call("sim_get", &"smooth_grid"))]
			+ ", ripple_kill %.4f m of curvature"
			% float(_rip.call("sim_get", &"ripple_kill")))
	print("[SETTLE] roughness is |w - mean(neighbour w)| in ULPS: 0 is glass, 1 is a texel-scale "
			+ "step the eye reads as vibration")

	var mid := "[SETTLE] MIDDLE @0,30,120,300,600,1200,2400:"
	var edge := "[SETTLE] SHORE  @0,30,120,300,600,1200,2400:"
	mid += " %.2f" % (_rough(res, false) / ulp)
	edge += " %.2f" % (_rough(res, true) / ulp)
	var first := _rough(res, true)
	var at := 0
	var last := first
	for n: int in [30, 120, 300, 600, 1200, 2400]:
		await _run(n - at)
		at = n
		last = _rough(res, true)
		mid += "  %.2f" % (_rough(res, false) / ulp)
		edge += "  %.2f" % (last / ulp)
	print(mid)
	print(edge)

	# THE SHAPE IS THE ANSWER. Forty seconds is forty drag half-lives: anything merely LEFT OVER
	# from the seed is down by a factor of 10^12. What is still moving is being made.
	if last > first * 0.25 and last > ulp * 0.10:
		print("[SETTLE] THE SHORE IS NOT SETTLING: %.2f ulp after 40 s, from %.2f at the seed. "
				% [last / ulp, first / ulp] + "Forty drag half-lives cannot leave that behind, so "
				+ "something re-creates it every step.")
	else:
		print("[SETTLE] the shore settled: %.2f ulp from %.2f at the seed - the fill decaying away"
				% [last / ulp, first / ulp])
	# THE FILTER HAS TO BE SELECTIVE OR IT IS JUST DAMPING. Poke a wave far bigger than a texel and
	# watch it survive: if the grid shimmer dies in a third of a second and a four-metre wave is
	# still there twenty seconds later, the k^2 weighting is doing what it claims. If both die, the
	# dial is a fog machine and should be turned down.
	var zone := get_first_node_in_group("zone") as Node3D
	var terr := zone.get_node_or_null("Terrain") as Node3D if zone != null else null
	if terr != null:
		var here := terr.to_global(Vector3(70.0, 0.0, 67.0))
		_rip.call("splash", here, 4.0, -0.25)
		var amp := PackedFloat32Array()
		var k := 0
		for n: int in [10, 60, 180, 600, 1200]:
			await _run(n - k)
			k = n
			amp.append(_wave(res))
		var line := "[SETTLE] a 4 m wave, peak-to-peak mm @10,60,180,600,1200:"
		for a2v in amp:
			line += " %.1f" % (a2v * 1000.0)
		print(line)
		if amp[amp.size() - 1] < amp[0] * 0.05:
			print("[SETTLE]    the filter is eating the waves too, not just the shimmer - turn "
					+ "smooth_grid down")

	print("[SETTLE] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## The largest surface excursion anywhere - a wave, as opposed to the texel-scale roughness above.
func _wave(res: int) -> float:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	var bd: Image = (_rip.call("bed_texture") as Texture2D).get_image()
	if img == null or bd == null:
		return 0.0
	var fres := bd.get_width()
	var lo := 1e9
	var hi := -1e9
	for z in range(8, res - 8, 3):
		for x in range(8, res - 8, 3):
			var w := _surf(img, bd, x, z, res, fres)
			if w <= -1e8:
				continue
			lo = minf(lo, w)
			hi = maxf(hi, w)
	return 0.0 if hi < lo else hi - lo


## GRID-SCALE surface roughness: mean |w - mean(neighbours' w)|. Near zero for any smooth surface
## however tilted, equal to the amplitude for a texel-scale step - so it measures what the eye reads
## as "vibrating" and ignores what it reads as "a wave".
##
## Split by whether a texel touches dry ground, which is the solver's own definition of an edge, so
## the two cannot disagree about where the shore is.
func _rough(res: int, near_shore: bool) -> float:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	var bd: Image = (_rip.call("bed_texture") as Texture2D).get_image()
	if img == null or bd == null:
		return 0.0
	var fres := bd.get_width()
	var total := 0.0
	var n := 0
	for z in range(4, res - 4, 2):
		for x in range(4, res - 4, 2):
			var c := _surf(img, bd, x, z, res, fres)
			if c <= -1e8:
				continue
			var s := 0.0
			var k := 0
			var dry_near := false
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var v := _surf(img, bd, x + o.x, z + o.y, res, fres)
				if v <= -1e8:
					dry_near = true
				else:
					s += v
					k += 1
			if k == 0 or dry_near != near_shore:
				continue
			total += absf(c - s / float(k))
			n += 1
	return total / maxf(float(n), 1.0)


func _surf(img: Image, bd: Image, x: int, z: int, res: int, fres: int) -> float:
	var cx := clampi(x, 0, res - 1)
	var cz := clampi(z, 0, res - 1)
	var h: float = img.get_pixel(cx, cz).r
	if h <= 0.002:
		return -1e9
	# THE SAME BILINEAR BED THE SOLVER USES, and reading it NEAREST here would have measured this
	# probe's own reconstruction error instead of the water. On a shore that falls 2.4 m across one
	# 2 m cell, nearest-versus-bilinear differs by centimetres per texel - which is exactly the size
	# of the "vibration" being investigated, and would have been reported as the finding.
	var b := _bed_bilinear(bd, cx, cz, res, fres)
	if b > 500.0:
		return -1e9
	return b + h


## bed_at() from the sim shader, in GDScript: bilinear over the terrain texels, with the off-map
## sentinel never interpolated.
func _bed_bilinear(bd: Image, cx: int, cz: int, res: int, fres: int) -> float:
	var t := Vector2((float(cx) + 0.5) / float(res) * float(fres) - 0.5,
			(float(cz) + 0.5) / float(res) * float(fres) - 0.5)
	var i0 := Vector2i(floori(t.x), floori(t.y))
	var fr := t - Vector2(i0)
	var q := PackedFloat32Array([0, 0, 0, 0])
	var top := -1e9
	for k in 4:
		var p := Vector2i(clampi(i0.x + (k & 1), 0, fres - 1), clampi(i0.y + (k >> 1), 0, fres - 1))
		q[k] = bd.get_pixel(p.x, p.y).r
		top = maxf(top, q[k])
	if top > 500.0:
		var n := Vector2i(clampi(int((float(cx) + 0.5) / float(res) * float(fres)), 0, fres - 1),
				clampi(int((float(cz) + 0.5) / float(res) * float(fres)), 0, fres - 1))
		return bd.get_pixel(n.x, n.y).r
	return lerpf(lerpf(q[0], q[1], fr.x), lerpf(q[2], q[3], fr.x), fr.y)


func _run(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame

extends SceneTree
## DOES THE LAKE STAY THE SAME LAKE, left alone?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_drain.gd
##
## The report is that the lake dries out over time, and that an environment which changes on its own
## is a gameplay bug whatever the size of the number. That is exactly right, and it makes this the
## one probe on this branch whose tolerance is not set by the store: a lake may lose nothing at all.
##
## THERE ARE THREE CANDIDATES AND THEY ARE NOT THE SAME KIND OF THING.
##
##   SEEP is deliberate. `h_new = max(h_new - seep*dt, 0)` removes a flat rate from every wet cell,
##   ships at 0.001 m/s, and exists so a spring-fed chain self-balances - each pool rises until
##   seepage matches its inflow. On a lake with NO spring it is simply a hole in the bottom:
##   0.001 m/s is 3.6 m/hour, so a 1.04 m lake is gone in about seventeen minutes of play.
##
##   POKES delete water. `h_new -= min(poke, poke_frac*h)` subtracts and never puts it back, so
##   every splash and every wake ring the raft leaves is water removed from the world permanently.
##
##   THE SCHEME ITSELF drifts, and this is the only one that would be a numerical error. The bench
##   measures it at -0.006 % per 600 steps on a sloping bed, which is a hundred times slower than
##   seep and in the opposite category: it is a bound to be checked, not a bug to be removed.
##
## So the probe runs the lake with each term switched off in turn. Attribution first; a fix that is
## not aimed at the dominant term is a fix that will not be noticed.

const STEPS := 3600                           ## a minute of play at 60 Hz
const SAMPLE := 600
## The shipped values, restated per case so no case inherits the one before it.
const SEEP := 0.001
const SPRING := 0.02

var _rip: Node = null
var _res := 0
var _t := 0.0
var _fail := 0


func _initialize() -> void:
	var lab := (load("res://scenes/dev/water_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in 90:
		await process_frame
	_rip = root.get_node("/root/Ripples")
	_rip.set("paused", true)
	_res = int(_rip.get("RES"))
	_t = float(_rip.get("SIZE_M")) / float(_res)

	var zone := get_first_node_in_group("zone") as Node3D
	var terr := zone.get_node_or_null("Terrain") as Node3D if zone != null else null
	var m: Object = zone.get("built_map") if zone != null else null
	var column := 0.0
	if terr != null and m != null:
		column = float(terr.water_depth_at(Vector2(35.0, 33.5) * float(m.cell_size)))
	print("[DRAIN] wilds lake, column %.3f m, dx %.3f m, seep %.4f m/s (= %.2f m/hour)"
			% [column, _t, float(_rip.call("sim_get", &"seep")),
			float(_rip.call("sim_get", &"seep")) * 3600.0])
	# WHAT THE SHADER ACTUALLY HAS, not what a script asked for. sim_set writes to _mats, and if it
	# is called before the driver has built them it is a silent no-op - the policy dial reads as set
	# on the game's side and is absent in the solver.
	print("[DRAIN] level_keep = %.4f  (water_lab asks for 0.033)"
			% float(_rip.call("sim_get", &"level_keep")))
	print("[DRAIN] a lake left alone may lose NOTHING. This is the one tolerance on this branch that")
	print("[DRAIN] is set by the game rather than by the float16 store.")

	# ATTRIBUTION BEFORE REPAIR. Two terms can move a lake's volume with nobody touching it - the
	# spring pouring in and the seepage taking away - and they are switched off one at a time here
	# because a fix aimed at the wrong one is a fix that changes nothing.
	# EVERY CASE STATES EVERY TERM. The first draft passed -1 for "leave this one alone" and never
	# restored anything, so "spring = 0" silently ran with seep still zeroed from the case before it
	# and the two rows were the same experiment under different names.
	await _case("as it ships", SEEP, SPRING, 0, true)
	await _case("no falls", SEEP, SPRING, 0, false)
	await _case("no falls, no seep", 0.0, SPRING, 0, false)
	await _case("no falls, no spring", SEEP, 0.0, 0, false)
	await _case("falls+seep+spring off", 0.0, 0.0, 0, false)
	# THE WINDOW RIM, which is the one term nobody had counted. edge_mode 0 (HORIZON) forces the
	# outer 6 % of the window back to the REST depth every step - a ~3.8 m ring, some 900 m2, held
	# at a fixed level by creating or destroying whatever water that takes. Deliberate: it is what
	# lets a window follow the camera without reflecting waves off its own edge. Also, unavoidably,
	# a reservoir. edge_mode 1 (WALL) removes it.
	await _case("rim WALL, all off", 0.0, 0.0, 1, false)
	await _case("rim WALL, ships", SEEP, SPRING, 1, true)

	print("[DRAIN] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## Settle, then watch the volume for a minute of play with nothing touching the water.
func _case(tag: String, seep: float, spring_rate: float, edge: int, falls: bool) -> void:
	_rip.call("sim_set", &"seep", seep)
	_rip.call("sim_set", &"spring_rate", spring_rate)
	# ON THE NODE, not through sim_set: edge_mode is rebound from the property every step
	# (ripple_field.gd:517), so a uniform written here is overwritten before the next frame - the
	# same trap that ran an entire vortex study with the advective term switched off.
	_rip.set("edge_mode", edge)
	# AND THE WATERFALLS HAVE TO BE STOPPED, not just accounted for. They splash from
	# _physics_process, which ticks on real time and NOT with the stepped sim, so the number of
	# impulses they land per simulated step depends on how fast the machine happens to be. That is
	# why this probe did not reproduce itself: the same case measured +198 m3/min in one run and +62
	# in the next. It is also a live gameplay bug in its own right - a waterfall pours faster on a
	# slower machine - and it is recorded here rather than fixed here.
	for n in root.find_children("*", "Node3D", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("waterfall.gd"):
			n.set_physics_process(falls)
			n.set_process(falls)
	_rip.set("reset_empty", false)
	_rip.call("reset_now")
	await _run(900)

	var first := _volume()
	var line := "[DRAIN] %-14s m3 @0" % tag
	line += " %.2f" % first
	var last := first
	for n in range(SAMPLE, STEPS + 1, SAMPLE):
		await _run(SAMPLE)
		last = _volume()
		line += "  %.2f" % last
	print(line)
	var moved := last - first
	var pct := moved / maxf(first, 1e-6) * 100.0
	print("[DRAIN] %-14s %+.3f m3 in %d steps = %+.2f%%  (%+.1f m3 per minute of play)"
			% [tag, moved, STEPS, pct, moved / maxf(float(STEPS) / 3600.0, 1e-6)])
	# MAGNITUDE, NOT LOSS. The first draft of this test asked whether the lake had gone DOWN, and
	# duly passed a run in which it rose sixteen per cent in a minute - a lake that floods is the
	# same gameplay bug as a lake that dries, wearing the other sign. The bar is not "small", it is
	# "not visibly changing", and a minute is a short walk.
	if absf(pct) > 0.05:
		_fail += 1


## Total water standing in the window, in cubic metres.
func _volume() -> float:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	if img == null:
		return 0.0
	var cell := _t * _t
	var v := 0.0
	for z in _res:
		for x in _res:
			var h: float = img.get_pixel(x, z).r
			if h > 0.002:
				v += h * cell
	return v


func _run(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame

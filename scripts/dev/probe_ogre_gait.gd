extends SceneTree
## THE SKATE TEST, and the rest of the gait's promises, measured rather than admired.
##
##   Godot_console.exe --path . --resolution 1280x800 \
##       --script res://scripts/dev/probe_ogre_gait.gd -- --out=C:/some/folder [--yaw=90]
##
## `--yaw=` rotates the puppet ROOT. Every number this probe reports is rotation-invariant, so
## the yawed runs must match the 0 run; that is the regression test for the world/local frame fix.
##
## RUN WITHOUT --headless if you want the screenshots; the dummy renderer saves black frames. The
## measurements themselves are honest headless — bone poses are CPU-side, so unlike the MultiMesh
## determinism trap documented in docs/directed-proceduralism.md, get_bone_global_pose() tells the
## truth with no renderer at all.
##
## WHAT IT IS FOR. "It looks like it walks" is not a claim anyone can check, and foot skate in
## particular is nearly invisible at a glance and glaring on a second viewing. The solver claims a
## planted foot CANNOT slide, because during stance the IK target is a stored world point rather
## than a computed one. That is a structural claim, so it deserves a structural test: drive the ogre
## across a range of speeds and watch the actual world-space position of the foot bone.
##
## Note it measures the FOOT BONE, not the solver's own `target`. Checking the solver against its
## own intention would pass even if the IK never reached the target at all.

const PUPPET := "res://scenes/dev/ogre_puppet.tscn"
const SPEEDS := [0.6, 1.2, 2.0, 2.8, 3.6, 4.4]
const SETTLE := 90              ## physics frames to reach steady state before recording
const SAMPLE := 620             ## frames recorded per speed — long enough for ~7 full strides, so a
                                ## part-finished cycle cannot masquerade as an asymmetry

# The promises, and the number each one is allowed to miss by.
const MAX_SKATE := 0.05         ## m/s of a PLANTED foot. 2% of walking speed.
const STRIDE_TOL := 0.06        ## stride sum vs distance travelled
const SYM_TOL := 0.08           ## left/right stance-duration difference
const MIN_KNEE := 8.0           ## degrees. A locked knee is the pop the soft clamp exists to stop.

var _out := ""
## Root yaw, in degrees, applied to the PUPPET ROOT -- not to Visuals. The solver decides in
## world space and every layer bridges back through skel.global_transform, so a rotated root is
## exactly the case those two halves used to disagree about. Every measurement below is
## rotation-invariant by construction (skate is a planted foot's world speed, stride is a sum of
## world distances), so a run at --yaw=90 must reproduce --yaw=0 inside the same tolerances. It
## did not before the frame fix: the knee pole swung alongside the limb and the legs mangled.
var _yaw_deg := 0.0
var _ogre: OgrePuppet
var _cam: Camera3D

## Print a few frames of raw geometry per speed. The summary table says a foot missed by 0.8 m; only
## this says whether the hip was in the wrong place, the target was, or the leg simply could not
## stretch that far.
const TRACE := false
const SHOW_DIST := true
## Set true to run the one-variable-at-a-time isolation at 0.6 m/s instead of the normal sweep.
const DIAGNOSE := false
var _fails: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
		elif a.begins_with("--yaw="):
			_yaw_deg = float(a.substr(6))


func _init() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	world.add_child(_light())
	world.add_child(_floor())

	var packed := load(PUPPET) as PackedScene
	if packed == null:
		print("FAIL: cannot load ", PUPPET)
		quit(1)
		return
	_ogre = packed.instantiate() as OgrePuppet
	# PLACED AND AIMED BEFORE IT ENTERS THE TREE. The solver stores its plant points in WORLD space,
	# so moving or rotating the ogre after _ready() has run leaves every stored point stale by exactly
	# that displacement, and the first stride is spent recovering from it. At yaw 0 the rotation write
	# was a no-op so the transient never showed; at any other yaw it surfaced as a one-frame skate
	# spike at the slowest speed, which is a probe artefact and not the gait.
	_ogre.position = Vector3(0, 0.2, 40)
	_ogre.rotation.y = deg_to_rad(_yaw_deg)
	# PRE-ALIGN THE BODY, or the probe measures the turn-in instead of the gait. Every sweep drives
	# toward world -Z, and at yaw 0 the puppet already faces that way. A yawed root does not: the ogre
	# would first have to turn up to 180 degrees against the solver's mass-derived cap, which at
	# 0.6 m/s takes ~200 physics frames -- more than double SETTLE -- and a body still rotating
	# reports every planted foot as skating. Cancelling the root yaw leaves the WORLD facing at 0 for
	# every run, so the only thing --yaw changes is the frame the solver must reason in.
	(_ogre.get_node("Visuals") as Node3D).rotation.y = -_ogre.rotation.y
	world.add_child(_ogre)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	world.add_child(_cam)
	_cam.current = true

	for i in 30:
		await process_frame

	var s := _ogre.solver
	for a in OS.get_cmdline_user_args():
		if a == "--noaim":
			s.aim_weapon = false
			print("(--noaim: weapon transform not written)")
		if a == "--nopose":
			# Diagnostic: strip the upper-body pose and inertia and measure the legs alone. If the
			# gait passes without them and fails with them, the fault is above the pelvis.
			s.carrying = &""
			if s.dynamics:
				s.dynamics.active = false
			if s.pose_layer:
				s.pose_layer.active = false
			print("(--nopose: carry pose and upper-body inertia disabled)")
	print("=== ogre, as measured off its own rest pose ===")
	print("  stature %.3f m   leg L %.3f m   reach %.3f m   ankle %.3f m   hip half-width %.3f m"
			% [s.stature, s.leg_length, s.max_reach, s.ankle_height, s.hip_half_width])
	print("  walk %.2f m/s (Fr 0.25)   run %.2f m/s (Fr 0.50)   yaw cap %.0f deg/s at a walk"
			% [s.walk_speed(), s.run_speed(), rad_to_deg(s.yaw_rate(s.walk_speed()))])
	print("")
	print("%-6s %-6s %-7s %-7s %-6s %-6s %-7s %-7s %-9s %-9s %-8s %-7s %-7s"
			% ["cmd", "actual", "stride", "f_step", "duty", "dbl", "crouch", "reach", "skate max",
					"skate p99", "strd err", "min knee", "hipY"])
	print("-".repeat(104))

	if DIAGNOSE:
		# One variable at a time, at the speed that still misbehaves. Reasoning about which of three
		# coupled effects is responsible is slower and less reliable than switching each off.
		var t := _ogre.solver.tuning
		print("  --- isolating the 0.6 m/s spike ---")
		await _sweep(0.6)
		quit(0)
		return
		var k := t.footfall_kick
		t.footfall_kick = 0.0
		print("  (no footfall spring)")
		await _sweep(0.6)
		t.footfall_kick = k
		var a := _ogre.solver.foot_ik.ankle_to_ground
		_ogre.solver.foot_ik.ankle_to_ground = 0.0
		print("  (no ankle-to-ground align)")
		await _sweep(0.6)
		_ogre.solver.foot_ik.ankle_to_ground = a
		var pl := t.pelvis_list_deg
		t.pelvis_list_deg = 0.0
		print("  (no pelvis list)")
		await _sweep(0.6)
		t.pelvis_list_deg = pl
		var py := t.pelvis_yaw_deg
		t.pelvis_yaw_deg = 0.0
		print("  (no pelvis yaw)")
		await _sweep(0.6)
		t.pelvis_yaw_deg = py
		quit(0)
		return

	for v in SPEEDS:
		await _sweep(v)

	await _stairs()

	print("")
	if _fails.is_empty():
		print("PASS — every gait promise held across %d speeds." % SPEEDS.size())
		quit(0)
	else:
		for f in _fails:
			print("FAIL: ", f)
		quit(1)


## Drive at one commanded speed, then watch what the feet actually do.
func _sweep(cmd: float) -> void:
	var s := _ogre.solver
	_ogre.teleport(Vector3(0, 0.2, 40))
	_ogre.commanded_speed = cmd
	_ogre.drive = Vector3(0, 0, -1)
	for i in SETTLE:
		await physics_frame

	var prev := [_foot(s, 0), _foot(s, 1)]
	var start := _ogre.global_position
	var skates: Array[float] = []
	var min_knee := 180.0
	var speed_sum := 0.0
	var miss_sum := 0.0        ## how far the solved ankle sits from the target it was given
	var miss_n := 0
	# Stride is counted on the LEFT FOOT ONLY. Each foot advances one full stride per cycle, so
	# summing both feet double-counts the ground covered and reports a healthy gait as 100% wrong.
	var stride_sum := 0.0
	var stride_n := 0
	var last_plant: Vector3 = s.feet[0].plant
	var span_from := Vector3.ZERO
	var span_to := Vector3.ZERO
	# Symmetry from COMPLETED stance intervals, not from a frame tally: a tally over a window that
	# does not divide evenly into cycles differs left-to-right by a partial stance no matter how
	# good the gait is, which is an artefact of the ruler rather than a fact about the ogre.
	var stance_runs := [[], []]
	var run_len := [0, 0]
	var was_stance := [true, true]
	var prev_plant := [s.feet[0].plant, s.feet[1].plant]
	var bad := 0
	var worst_sk := 0.0
	var worst_at := 0.0

	for i in SAMPLE:
		await physics_frame
		var dt := 1.0 / 60.0
		var now := [_foot(s, 0), _foot(s, 1)]
		for k in 2:
			var f = s.feet[k]
			var planted: bool = f.mode == OgreSolver.FootMode.STANCE
			if planted:
				miss_sum += now[k].distance_to(f.target)
				miss_n += 1
			# Sample skate ONLY across a pair of frames that were both planted at the SAME plant
			# point. Without the second condition the touchdown frame — where the foot legitimately
			# arrives from somewhere else — is counted as a slide, and a solver that holds its feet
			# perfectly still still reports a metre per second. That is the discontinuity being
			# measured, not the sliding, and they are different claims.
			if planted and was_stance[k] and f.plant == prev_plant[k]:
				var sk: float = prev[k].distance_to(now[k]) / dt
				skates.append(sk)
				if sk > 0.05:
					bad += 1
					if DIAGNOSE and k == 0 and bad < 14:
						print("      BAD f%d phase %.3f t %.3f knee %5.1f  hip %v  tgt %v  got %v  prev %v  d %.4f"
								% [k, s.phase, f.t, rad_to_deg(s.foot_ik.knee_angles()[0]),
										s.foot_ik.hip_world(0), f.target, now[k], prev[k], sk / 60.0])
					worst_at = maxf(worst_at, f.t) if sk >= worst_sk else worst_at
					if sk >= worst_sk:
						worst_sk = sk
						worst_at = f.t
			if planted:
				run_len[k] += 1
			elif was_stance[k]:
				if run_len[k] > 0:
					stance_runs[k].append(run_len[k])
				run_len[k] = 0
			was_stance[k] = planted
			prev_plant[k] = f.plant
		# Strides are compared against the travel BETWEEN the first and last plant, not against the
		# whole window. The window opens and closes mid-stride, and those two part-strides are worth
		# about a seventh of the total here -- which is the entire size of the discrepancy this was
		# reporting as a gait fault.
		if s.feet[0].mode == OgreSolver.FootMode.SWING and last_plant != s.feet[0].plant:
			if stride_n == 0:
				span_from = _ogre.global_position
			else:
				stride_sum += last_plant.distance_to(s.feet[0].plant)
			span_to = _ogre.global_position
			stride_n += 1
			last_plant = s.feet[0].plant
		prev = now
		var knees: Array = s.foot_ik.knee_angles()
		min_knee = minf(min_knee, minf(rad_to_deg(knees[0]), rad_to_deg(knees[1])))
		speed_sum += s.speed

	var travelled := Vector3(span_from.x - span_to.x, 0.0, span_from.z - span_to.z).length()
	var actual := speed_sum / float(SAMPLE)
	skates.sort()
	var smax: float = skates[-1] if not skates.is_empty() else 0.0
	var p99: float = skates[int(skates.size() * 0.99)] if skates.size() > 4 else smax
	var p50: float = skates[int(skates.size() * 0.50)] if skates.size() > 4 else smax
	var p90: float = skates[int(skates.size() * 0.90)] if skates.size() > 4 else smax
	print("     skate distribution: p50 %.4f  p90 %.4f  p99 %.4f  max %.4f   over-limit %d/%d  worst at stance t=%.2f"
			% [p50, p90, p99, smax, bad, skates.size(), worst_at])
	var stride_err := 0.0 if stride_n == 0 else absf(stride_sum - travelled) / maxf(travelled, 0.01)
	# Drop each foot's FIRST completed run: the window opens mid-stance, so that one is truncated by
	# however far through it happened to be. With only a handful of runs per foot that single short
	# sample is worth ~13% of the mean, which the ruler then reports as a limping ogre.
	var mean_l := _mean(stance_runs[0].slice(1))
	var mean_r := _mean(stance_runs[1].slice(1))
	var sym := 0.0
	if mean_l > 0.0 and mean_r > 0.0:
		sym = absf(mean_l - mean_r) / ((mean_l + mean_r) * 0.5)

	var miss := 0.0 if miss_n == 0 else miss_sum / float(miss_n)
	if TRACE:
		_trace(cmd)
	print("%-6.2f %-6.2f %-7.2f %-7.2f %-6.2f %-6.2f %-7.2f %-7.2f %-9.4f %-9.4f %-8.1f%% %-7.1f %-7.3f%s"
			% [cmd, actual, s.stride, s.stride_freq, s.duty, s.double_support, s.crouch,
					s.reach_budget, smax, p99, stride_err * 100.0, min_knee, s.hip_lift,
					"  (legs limit)" if s.stride_limited else ""])

	if p99 > MAX_SKATE:
		_fails.append("skate p99 %.4f m/s at %.1f m/s (limit %.3f)" % [p99, cmd, MAX_SKATE])
	if s.duty < s.tuning.duty_floor - 0.001:
		_fails.append("duty %.3f below the floor at %.1f m/s — both feet left the ground" % [s.duty, cmd])
	if min_knee < MIN_KNEE:
		_fails.append("knee locked to %.1f deg at %.1f m/s" % [min_knee, cmd])
	if stride_n > 3 and stride_err > STRIDE_TOL:
		_fails.append("stride sum off travel by %.1f%% at %.1f m/s" % [stride_err * 100.0, cmd])
	if sym > SYM_TOL:
		_fails.append("left/right stance asymmetry %.1f%% at %.1f m/s" % [sym * 100.0, cmd])

	if _out != "":
		# Frame FIRST, then let it render. Moving the camera and grabbing the buffer in the same
		# breath photographs the previous frame, from the previous camera position.
		_frame_ogre()
		for j in 12:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(_out + "ogre_gait_%.1f.png" % cmd)


## Hip, target and result for one foot, in world space, over a handful of frames.
func _trace(cmd: float) -> void:
	var s := _ogre.solver
	print("  --- trace @ %.1f m/s ---" % cmd)
	print("     root.y %.3f   crouch %.3f   hips_off.y %+.3f   reach_budget %.3f"
			% [_ogre.global_position.y, s.crouch, s.hips_offset.y, s.reach_budget])
	for k in 4:
		var hip: Vector3 = s.foot_ik.hip_world(0)
		var f = s.feet[0]
		var got := s.foot_ik.solved_world(0)
		print("     hip %v  target %v  got %v  |hip-tgt| %.3f  miss %.3f  %s"
				% [hip, f.target, got, hip.distance_to(f.target), got.distance_to(f.target),
						"STANCE" if f.mode == OgreSolver.FootMode.STANCE else "SWING"])
		await physics_frame


## UNEVEN GROUND, which is the only test that says whether the foot IK is real: a solver that simply
## drops both feet to y=0 passes every flat-ground check ever written.
##
## A RAMP, not stairs. Godot's CharacterBody3D has no step-up of its own, so a riser is a wall to it
## and the ogre just walks into the bottom step forever -- which tests the character controller, not
## the animation. Climbing steps is real work and it belongs to the body, not the solver. On a slope
## the body travels and the feet have to find ground at a different height on every stride, which is
## the question this probe is actually asking.
func _stairs() -> void:
	print("")
	print("=== 12 degree ramp ===")
	var world := current_scene
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14, 0.6, 26)
	col.shape = box
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	body.add_child(mi)
	body.position = Vector3(0, 2.4, -13.0)
	body.rotation_degrees = Vector3(12.0, 0, 0)
	world.add_child(body)
	await physics_frame

	_ogre.teleport(Vector3(0, 0.2, 2.0))
	_ogre.commanded_speed = 1.6
	_ogre.drive = Vector3(0, 0, -1)
	var s := _ogre.solver
	# Settle before reading anything. solved_world only updates during the modifier pass, so a
	# sample taken straight after a teleport compares a pre-teleport foot with a post-teleport one
	# and reports several hundred metres per second of skate -- which is the teleport, not the gait.
	for i in SETTLE:
		await physics_frame
	var worst_gap := 0.0
	var worst_skate := 0.0
	var prev := [_foot(s, 0), _foot(s, 1)]
	var prev_plant := [s.feet[0].plant, s.feet[1].plant]
	var was := [true, true]
	var climbed := 0.0
	# Record only once it is properly ON the slope. The stride for the first step onto a ramp is
	# planned with the flat-ground reach budget, because the budget is driven by the hip height the
	# IK actually saw and it has not seen the slope yet. That one transitional stride clamps; the
	# steady state is the claim worth testing, and a max over the transition hides it.
	var gaps: Array[float] = []
	var skates: Array[float] = []
	for i in 420:
		await physics_frame
		var now := [_foot(s, 0), _foot(s, 1)]
		var settled := _ogre.global_position.y > 0.7
		for k in 2:
			var f = s.feet[k]
			var planted: bool = f.mode == OgreSolver.FootMode.STANCE
			if settled and planted and f.grounded:
				# The ankle must sit on the plant point the raycast found, whatever height that was.
				gaps.append(absf(now[k].y - f.plant.y))
			if settled and planted and was[k] and f.plant == prev_plant[k]:
				skates.append(prev[k].distance_to(now[k]) * 60.0)
			was[k] = planted
			prev_plant[k] = f.plant
		prev = now
		climbed = maxf(climbed, _ogre.global_position.y)
	gaps.sort()
	skates.sort()
	worst_gap = gaps[int(gaps.size() * 0.95)] if gaps.size() > 8 else 0.0
	worst_skate = skates[int(skates.size() * 0.95)] if skates.size() > 8 else 0.0
	print("  on-slope samples: %d   gap max %.4f   skate max %.4f"
			% [gaps.size(), gaps[-1] if not gaps.is_empty() else 0.0,
					skates[-1] if not skates.is_empty() else 0.0])
	print("  climbed to y = %.3f m   gap p95 %.4f m   skate p95 %.4f m/s"
			% [climbed, worst_gap, worst_skate])
	if climbed < 0.8:
		_fails.append("did not climb the ramp (reached only y=%.2f)" % climbed)
	if worst_gap > 0.03:
		_fails.append("foot sat %.3f m off its own plant point on the slope" % worst_gap)
	if worst_skate > 0.15:
		_fails.append("feet skated %.3f m/s on the slope" % worst_skate)


## Put the camera where the ogre actually is. A fixed camera photographs an empty field once the
## subject has walked twenty metres, which is how a working gait gets filed as a broken one.
func _frame_ogre() -> void:
	var at := _ogre.global_position
	_cam.global_position = at + Vector3(7.0, 4.2, 7.0)
	_cam.look_at(at + Vector3.UP * 1.9)


## The ankle's TRUE final position: taken from the last layer in the stack, not from the foot IK's
## own record of what it wrote.
##
## The foot IK is no longer last -- the off-hand IK runs after it -- and any later layer that writes
## bones forces the skeleton to recompute, so what the foot IK recorded is not necessarily where the
## foot ended up. Measuring the earlier snapshot reported 0.33 m/s of skate that the feet were not
## doing, and sent a long hunt after a solver bug that was a ruler bug.
func _foot(s: OgreSolver, i: int) -> Vector3:
	var pts := s.arm_ik.bone_positions() if s.arm_ik else PackedVector3Array()
	var b := s.bone("LeftFoot" if i == 0 else "RightFoot")
	if b >= 0 and b < pts.size():
		return pts[b]
	return s.foot_ik.solved_world(i)


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())


func _floor() -> Node3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.64, 0.6)
	mat.uv1_scale = Vector3(200, 200, 1)
	mi.material_override = mat
	body.add_child(mi)
	return body


func _light() -> Node3D:
	var holder := Node3D.new()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	holder.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	holder.add_child(env)
	return holder

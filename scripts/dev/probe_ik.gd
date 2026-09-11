extends SceneTree
## THE IK IN ISOLATION — no gait, no crouch, no world transform, no springs.
##
##   Godot_console.exe --headless --path . --script res://scripts/dev/probe_ik.gd
##
## WHY SEPARATELY. probe_ogre_gait.gd reported the ankle finishing a metre from the target it was
## handed. That is either bad IK maths, a bad space conversion, or a write that does not stick — and
## with the gait running there is no way to tell which, because every one of them looks like "the
## feet are wrong". So this hands the solver targets it has already proven it can reach (the rest
## pose's own ankle, nudged by a known amount) and asks one question: did the bone go there.
##
## The checks, in the order they narrow the problem down:
##   1. IDENTITY  — solve to exactly where the ankle already is. Any error here is the write path,
##                  not the trigonometry.
##   2. NUDGE     — small offsets, well inside reach. Tests the maths on easy targets.
##   3. SWEEP     — targets across the whole reachable volume, checking accuracy and the knee's
##                  bend direction.
##   4. OVERREACH — targets past full extension must land ON the line to the target at max reach,
##                  and must not flip the knee.
##   5. CONTINUITY— a 1 mm move of the target must not move a joint more than a degree. This is the
##                  one that catches the full-extension pop, which is invisible at 60 fps and
##                  unmistakable in slow motion.

const MODEL := "res://assets/models/ogre.fbx"
const TOL := 0.002              ## metres. A 4 m creature may miss by 2 mm; not by more.

var _fails: Array[String] = []
var _skel: Skeleton3D
var _iu := -1
var _il := -1
var _if := -1


func _init() -> void:
	await process_frame
	var packed := load(MODEL) as PackedScene
	var inst := packed.instantiate() as Node3D
	root.add_child(inst)
	current_scene = inst
	await process_frame

	_skel = _find(inst)
	if _skel == null:
		print("FAIL: no skeleton")
		quit(1)
		return
	_iu = _skel.find_bone("LeftUpperLeg")
	_il = _skel.find_bone("LeftLowerLeg")
	_if = _skel.find_bone("LeftFoot")

	var a := _skel.get_bone_global_rest(_iu).origin
	var b := _skel.get_bone_global_rest(_il).origin
	var c := _skel.get_bone_global_rest(_if).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	print("=== two-bone IK, left leg ===")
	print("  hip  %v" % a)
	print("  knee %v" % b)
	print("  ankle %v" % c)
	print("  l1 %.4f   l2 %.4f   reach %.4f   rest hip->ankle %.4f" % [l1, l2, l1 + l2, a.distance_to(c)])
	print("")

	_identity(c)
	_nudge(c, l1 + l2)
	_sweep(a, l1 + l2)
	_overreach(a, c, l1 + l2)
	_continuity(c)

	print("")
	if _fails.is_empty():
		print("PASS — the IK reaches what it is given.")
		quit(0)
	else:
		for f in _fails:
			print("FAIL: ", f)
		quit(1)


## Solve to a target and report where the ankle actually finished, all in SKELETON space.
func _try(target: Vector3, pole: Vector3) -> Vector3:
	_skel.reset_bone_poses()
	TwoBoneIk.solve(_skel, _iu, _il, _if, target, pole)
	return _skel.get_bone_global_pose(_if).origin


func _pole_for(target: Vector3) -> Vector3:
	# Forward and outward of the knee. In this rig's rest space the body faces -Z and +X is its left.
	return target + Vector3(0.6, 1.2, -1.4)


## The one that isolates the write path from the trigonometry.
func _identity(rest_ankle: Vector3) -> void:
	var got := _try(rest_ankle, _pole_for(rest_ankle))
	var err := got.distance_to(rest_ankle)
	print("1. IDENTITY   target %v -> %v   err %.4f m" % [rest_ankle, got, err])
	if err > TOL:
		_fails.append("solving to the ankle's own rest position missed by %.4f m — the write path is wrong, not the maths" % err)


## Offsets that stay INSIDE the leg's reach. The rest pose already stands at 98% extension, so a
## nudge straight down is unreachable by construction and the solver is right to clamp it — testing
## that and calling the clamp a failure just teaches you to ignore the probe. The over-reach case
## has its own test below, which is where it belongs.
func _nudge(rest_ankle: Vector3, _reach: float) -> void:
	var worst := 0.0
	for d in [Vector3(0.2, 0.15, 0), Vector3(-0.2, 0.15, 0), Vector3(0, 0.2, 0.3),
			Vector3(0, 0.2, -0.3), Vector3(0, 0.25, 0), Vector3(0.15, 0.3, 0.25)]:
		var t: Vector3 = rest_ankle + d
		worst = maxf(worst, _try(t, _pole_for(t)).distance_to(t))
	print("2. NUDGE      worst err over 6 small offsets: %.4f m" % worst)
	if worst > TOL:
		_fails.append("small offsets missed by up to %.4f m" % worst)


func _sweep(hip: Vector3, reach: float) -> void:
	var worst := 0.0
	var n := 0
	for i in 12:
		for j in 8:
			var yaw := TAU * float(i) / 12.0
			var pitch := -PI * 0.5 + PI * 0.9 * float(j) / 7.0
			var r := reach * (0.35 + 0.6 * float((i * 7 + j) % 5) / 4.0)
			var t := hip + Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * r
			worst = maxf(worst, _try(t, _pole_for(t)).distance_to(t))
			n += 1
	print("3. SWEEP      worst err over %d reachable targets: %.4f m" % [n, worst])
	if worst > TOL:
		_fails.append("reachable sweep missed by up to %.4f m" % worst)


func _overreach(hip: Vector3, rest_ankle: Vector3, reach: float) -> void:
	var worst_off_line := 0.0
	var worst_over := 0.0
	for m in [1.05, 1.3, 2.0, 5.0]:
		var t: Vector3 = hip + (rest_ankle - hip).normalized() * reach * m
		var got := _try(t, _pole_for(t))
		var d := got.distance_to(hip)
		worst_over = maxf(worst_over, d - reach)
		# It must stop short, but it must stop short ALONG THE LINE to the target rather than
		# somewhere off to the side.
		var along := (got - hip).normalized().dot((t - hip).normalized())
		worst_off_line = maxf(worst_off_line, 1.0 - along)
	print("4. OVERREACH  max extension past reach: %+.4f m   worst direction error: %.5f"
			% [worst_over, worst_off_line])
	if worst_over > 0.001:
		_fails.append("extended %.4f m past its own leg length" % worst_over)
	if worst_off_line > 0.001:
		_fails.append("over-reach landed off the line to the target")


## The pop test. Walking the target through full extension in 1 mm steps, the ankle must move in
## 1 mm steps too — no frame where the knee flips to the other side.
func _continuity(rest_ankle: Vector3) -> void:
	var prev := Vector3.INF
	var worst := 0.0
	for i in 400:
		var t: Vector3 = rest_ankle + Vector3(0, -0.001, 0) * float(i)
		var got := _try(t, _pole_for(t))
		if prev != Vector3.INF:
			worst = maxf(worst, prev.distance_to(got))
		prev = got
	print("5. CONTINUITY biggest ankle jump for a 1 mm target step: %.5f m" % worst)
	if worst > 0.02:
		_fails.append("ankle jumped %.4f m for a 1 mm target move — the knee is flipping" % worst)


func _find(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find(c)
		if s != null:
			return s
	return null

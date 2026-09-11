class_name OgreArmIk
extends SkeletonModifier3D
## Puts hands on the haft, so the mace is genuinely held rather than merely near a fist.
##
## TWO DIRECTIONS, AND BOTH ARE NEEDED. The relationship between a hand and a weapon runs either
## way, and which one is right depends on the pose:
##
##   ANCHORED TO A HAND  (anchor = RightHand / LeftHand)
##     The weapon hangs off that hand and goes wherever it goes. The arm is posed; the mace obeys.
##     Only the OFF hand is solved onto the shaft. Right for carrying, and for a swing where the
##     arm's motion is the thing you authored.
##
##   ANCHORED TO THE BODY  (anchor = Body)
##     The weapon is placed relative to the creature and BOTH hands are solved onto it. The mace is
##     the thing you authored; the arms obey. This is the "glued" case, and it is right whenever the
##     weapon's PATH is the point — a two-handed swing that has to pass through a particular arc —
##     because implying that arc through shoulder angles is fighting the tool.
##
## THE WEAPON IS RIGID TO ITS ANCHOR. Pose-to-pose the placement eases, because a mace that
## teleports between poses throws away the weight the dynamics layer just bought. But the ANCHOR's
## own motion transfers with NO lag: easing that made the mace swim behind the hand holding it, and
## a weapon that lags the fist gripping it reads as unattached, which is what it then is.

## 0 = hands are left alone, 1 = fully on the haft. The pose editor drops this to 0 while it is open
## so posing an arm is not immediately overwritten.
@export_range(0.0, 1.0, 0.01) var amount := 1.0
## Which way the elbows point. Down and out, like a person bracing a heavy shaft.
@export_range(0.0, 1.5, 0.01) var elbow_droop := 0.55
## How far along the wrist-to-knuckles span the grip sits. A fist closes around a haft between the
## two, not at either end.
@export_range(0.0, 1.5, 0.05) var palm_grip := 0.65
## How far the CLAVICLE may turn to help the arm reach, in degrees.
##
## An arm is not a rotation about a pinned joint. The shoulder girdle moves -- reaching for something
## at the edge of your span, the whole shoulder goes with the arm -- and on a creature this size that
## is tens of centimetres of reach that the two-bone solve, which pins the shoulder and rotates only
## the two arm segments, was throwing away.
##
## It is why the second hand could not get to the haft, why the weapon had to be dragged inboard to
## meet it instead, and why the grip flickered: the reach test kept crossing its threshold, so the
## hand snapped between the haft and wherever the pose had left it.
@export_range(0.0, 70.0, 1.0) var shoulder_assist := 34.0
## Roll of the palm about the haft, in degrees. Positive turns it upward.
##
## The IK places the palm and says nothing about which way it faces, so the hand arrives at the right
## point in whatever orientation the chain happened to end in -- which is not how a hand holds a
## shaft. This is the wrist doing the last part of the job.
@export_range(-90.0, 90.0, 1.0) var palm_roll := 18.0

var solver: OgreSolver

const SIDES := [
	{"up": "LeftUpperArm", "low": "LeftLowerArm", "hand": "LeftHand", "clav": "LeftShoulder"},
	{"up": "RightUpperArm", "low": "RightLowerArm", "hand": "RightHand", "clav": "RightShoulder"},
]

var _idx: Dictionary = {}
var _reach := [0.0, 0.0]         ## per side: shoulder-to-hand chain length
var _fade := [0.0, 0.0]          ## per side: eased reach blend, so letting go is not a jump
var _dist := [0.0, 0.0]
var _grip := [0.0, 0.0]
var _snap := PackedVector3Array()
var _dt := 1.0 / 60.0            ## this pass's engine delta, for the grip fade
## Which bone the weapon hung off last pass, so a change of grip can be told from a loss of one.
var _last_anchor := ""
## Bone ORIENTATIONS at the end of the pass, alongside the positions. The weapon needs the fist's
## rotation to sit in it rigidly, and _aim_weapon reads this snapshot rather than the skeleton for
## the same reason it reads the positions from here: touching the skeleton from _process forces an
## update outside the modifier pass, the layers then run against a pose that has already moved, and
## it surfaces two systems away as foot skate at walking pace.
var _snap_basis: Array[Basis] = []
## WHERE THE PALM IS, per side, in the hand bone's own frame.
##
## Skeleton3D reports a bone's ORIGIN, and a hand bone's origin is the WRIST -- the joint. The bone
## then runs out through the palm to the finger roots. Solving the hand bone onto a haft therefore
## puts the ogre's WRIST on the weapon and leaves the palm a whole hand past it: measured on this
## rig, 0.50 m past it, which at four metres tall is not a detail.
##
## Derived from the five finger roots, because they are the only thing in the rig that knows where
## the hand ends. Nothing is authored.
var _palm := [Vector3.ZERO, Vector3.ZERO]


## Every bone's position in WORLD space, as of the END of the modifier pass.
##
## Sampled here because this layer runs last, and AFTER the solve because this layer moves the arms:
## a snapshot taken before it shows them where they used to be, and the debug skeleton then draws an
## arm off the mesh — which looks exactly like a broken bind pose and is an overlay out of date.
func bone_positions() -> PackedVector3Array:
	return _snap


## One bone's world ORIENTATION, as of the end of the modifier pass. Same snapshot, same reason.
func bone_basis(i: int) -> Basis:
	return Basis() if i < 0 or i >= _snap_basis.size() else _snap_basis[i]


## How firmly each hand is on the haft, and how far that grip point is from its shoulder. Reported
## because "the hand is not on the weapon" has two opposite causes — the layer is off, or the grip is
## out of reach — and these numbers are the only way to tell them apart.
func grip_strength(side := 0) -> float:
	return _grip[side]


func grip_distance(side := 0) -> float:
	return _dist[side]


## Shoulder-to-hand chain length, the longer of the two arms. The swing asks so it can keep the
## grip somewhere the arms can actually reach.
## The palm's world position for one side, from the end-of-pass snapshot. This is the point that is
## actually holding something -- `bone_positions()[Hand]` is the wrist.
func palm_position(side: int) -> Vector3:
	var i: int = _idx.get(SIDES[side]["hand"], -1)
	if i < 0 or i >= _snap.size():
		return Vector3.ZERO
	return _snap[i] + _snap_basis[i] * _palm[side]


func arm_reach() -> float:
	return maxf(_reach[0], _reach[1])


func _process_modification_with_delta(delta: float) -> void:
	_dt = delta
	var skel := get_skeleton()
	if skel == null or solver == null or not solver.is_ready():
		return
	if _idx.is_empty():
		_resolve(skel)

	if amount > 0.001 and solver.carrying != &"":
		var lone := solver.one_handed()
		if solver.weapon_anchor() == "Body":
			# GLUED: the weapon is placed, and both hands come to it. Both targets are POINTS ON THE
			# MACE -- solver.grip_point and its offset partner -- so what the IK reaches for and what
			# the weapon is hung from are the same thing by construction, rather than two distances
			# that have to be kept equal by hand.
			_solve_arm(skel, 1, solver.grip_world())
			if lone:
				# One-handed: the off hand is not on the weapon and must not be dragged toward it.
				_fade[0] = 0.0
				_grip[0] = 0.0
			else:
				_solve_arm(skel, 0, solver.off_grip_world())
		else:
			# Anchored to a hand: that arm is posed, and only the off hand is solved -- onto THE SAME
			# measured point the swing uses. Carry and swing agreed about nothing before this: the
			# swing solved to solver.off_grip_world() while carry computed its own target from a
			# separate pair of constants, so the moment an action started the off hand was asked to
			# be somewhere else and had to travel there.
			var off := 0 if solver.weapon_anchor() == "RightHand" else 1
			_solve_arm(skel, off, solver.off_grip_world())
	else:
		for i in 2:
			_fade[i] = 0.0
			_grip[i] = 0.0

	# THE ANCHORED HAND NEVER GOES THROUGH _solve_arm ("that arm is posed"), which was exactly
	# right while poses drove it: the weapon hangs off that hand, so they agreed by construction.
	# An authored clip's hand agrees with nothing by construction -- the weapon is placed with
	# authored offsets and eased by the turn limiter -- so the fist read as an open palm hovering
	# beside its own haft through the whole wind-up. Orientation only: the wrist stays where the
	# clip put it, the palm turns onto the shaft.
	if amount > 0.001 and solver.carrying != &"" and solver.clip_authored() 			and solver.weapon_anchor() != "Body":
		var anchored := 1 if solver.weapon_anchor() == "RightHand" else 0
		if solver.gripping(anchored):
			_wrap_fist(skel, anchored, 1.0)

	_snapshot(skel)
	_last_anchor = solver.weapon_anchor()


func _resolve(skel: Skeleton3D) -> void:
	for s in SIDES:
		for k in s:
			_idx[s[k]] = skel.find_bone(s[k])
	for side in 2:
		var u: int = _idx[SIDES[side]["up"]]
		var l: int = _idx[SIDES[side]["low"]]
		var h: int = _idx[SIDES[side]["hand"]]
		if h >= 0:
			# The palm: the average of the finger roots, in the hand bone's frame, taken a fraction
			# of the way out. A fist closes around a haft between the wrist and the knuckles, not at
			# either end of that span.
			var avg := Vector3.ZERO
			var n := 0
			for b in skel.get_bone_count():
				if skel.get_bone_parent(b) == h:
					avg += skel.get_bone_global_rest(b).origin
					n += 1
			if n > 0:
				avg /= n
				_palm[side] = (skel.get_bone_global_rest(h).affine_inverse() * avg) * palm_grip
		if u >= 0 and l >= 0 and h >= 0:
			_reach[side] = skel.get_bone_global_rest(u).origin.distance_to(
					skel.get_bone_global_rest(l).origin) \
					+ skel.get_bone_global_rest(l).origin.distance_to(
					skel.get_bone_global_rest(h).origin)


## Solve one arm onto a world-space point on the shaft.
func _solve_arm(skel: Skeleton3D, side: int, target_world: Vector3) -> void:
	var iu: int = _idx.get(SIDES[side]["up"], -1)
	var il: int = _idx.get(SIDES[side]["low"], -1)
	var ih: int = _idx.get(SIDES[side]["hand"], -1)
	if iu < 0 or il < 0 or ih < 0:
		return
	var target: Vector3 = skel.global_transform.affine_inverse() * target_world

	# THE SHOULDER GOES TOO. Before solving the arm, swing the clavicle toward the target -- which
	# carries the whole arm with it and buys reach the two-bone solve cannot, because that solve pins
	# the shoulder and only rotates what hangs off it.
	#
	# Capped, and only ever a help: it turns toward the target by at most shoulder_assist degrees,
	# and it is applied BEFORE the reach test so the fade is judged against the reach the arm
	# actually has rather than the reach it would have with its shoulder nailed down.
	# NOT FOR AN AUTHORED CLIP. The grip solve below stands down where a clip owns the arm, but
	# this assist ran unconditionally -- and an action's own recorded curves already CONTAIN it, so
	# playback added a second capped turn on top and the off shoulder sat a constant 34 degrees
	# wrong for the whole clip. (Borrowed clips keep the assist: their recording never met this
	# rig, and the assist-on-top is the behaviour their tuning was measured against.)
	var ic: int = _idx.get(SIDES[side]["clav"], -1)
	if ic >= 0 and shoulder_assist > 0.0 			and (not solver.clip_authored() or solver.gripping(side)):
		var pivot: Vector3 = skel.get_bone_global_pose(ic).origin
		var cur := skel.get_bone_global_pose(iu).origin - pivot
		var want := target - pivot
		if cur.length_squared() > 0.000001 and want.length_squared() > 0.000001:
			var axis := cur.cross(want)
			if axis.length_squared() > 0.000001:
				var turn := minf(cur.angle_to(want), deg_to_rad(shoulder_assist))
				if turn > 0.0005:
					TwoBoneIk.rotate(skel, ic, Quaternion(axis.normalized(), turn))

	var shoulder: Vector3 = skel.get_bone_global_pose(iu).origin
	var d := shoulder.distance_to(target)

	# THE GRIP IS A SWITCH. It used to be a reach test -- fade in as the palm came within arm's
	# length of the haft, fade out as it left, with hysteresis so the switch did not chatter twice
	# a stride. That is a mechanic deciding itself from geometry, and it let go in the middle of
	# swings for reasons no other layer could see or override. Now the solver says whether the hand
	# is holding and this only blends the pose so it does not pop; nothing here decides anything.
	var want_fade: float = 1.0 if solver.gripping(side) else 0.0
	if solver.weapon_anchor() != _last_anchor:
		_fade[side] = want_fade
	else:
		_fade[side] = lerpf(float(_fade[side]), want_fade, 1.0 - exp(-18.0 * _dt))
	_dist[side] = d
	# LET GO OF AN ARM THE CLIP HAS TAKEN. Every other layer already yields where the clip owns a
	# bone -- the pose layer by clip_share, the gait layer through pose_influence -- and this one did
	# not, so it went on hauling the off hand onto the haft at full strength while the clip drove the
	# same arm somewhere else. Nothing arbitrated, and the loser was the silhouette: the left arm
	# ended up inside the ogre's own chest.
	#
	# Through the same mix dial as everything else, so at mix_arms 0 the clip has the arms outright
	# and at 1 the grip IK behaves exactly as it always did.
	# EXCEPT WHEN THE MACE LEADS. Standing down for the clip is right while the weapon hangs off a
	# hand -- there the arm is the animation and the mace merely follows it. When the WEAPON's path
	# is the authored thing, the arms exist to reach it, and yielding to the clip here zeroes the
	# grip solve exactly when it is the only thing doing any work. The mace swung its arc and the
	# ogre stood there with its hands by its sides.
	# LET GO PROPERLY WHEN THE GRIP CANNOT BE MADE. The weapon yields a little to bring the second
	# hand's point within reach, and when that budget runs out the hand is simply not going to get
	# there. Half-reaching for it -- which is what the reach fade does on its own, and it measured
	# 0.30 -- is the worst of the three states: the arm is neither holding the mace nor hanging like
	# an arm, it is stretched partway toward something it never arrives at.
	# The yield_short release that used to sit here was the reach rule again in another form: when
	# the weapon could not be turned enough to bring the second point within span, the hand gave up
	# on its own. That decision belongs to whoever sets the switch.
	var claimed := 0.0
	if solver.clip_authored():
		# FOR AN AUTHORED CLIP THE SWITCH IS THE GRIP, nothing else. A gripping hand solves LIVE
		# at full strength -- the clip's arm was authored around the RECORDED weapon path, and in
		# the game the weapon is re-aimed and re-placed every frame; standing the solve down left
		# the hand floating open beside the shaft through the whole wind-up, from every camera
		# angle. A hand the solver has LET GO of belongs to the clip outright: the recording
		# already eased it off the haft, and re-easing from a different base flickered the off
		# arm fifty degrees through every release window.
		claimed = 0.0 if solver.gripping(side) else 1.0
	elif solver.clip_layer and solver.weapon_anchor() != "Body":
		claimed = solver.clip_layer.influence(SIDES[side]["hand"])
	_grip[side] = amount * float(_fade[side]) * (1.0 - claimed)
	if _grip[side] <= 0.001:
		return

	# Pole below and outboard. The direction vectors are WORLD and `shoulder` is in SKELETON space,
	# so they are rotated in before being added — the model carries a 180 degree yaw, and adding a
	# world "down and to the left" to a skeleton-space point puts the elbow on the wrong side.
	var inv := skel.global_transform.basis.orthonormalized().inverse()
	var out: Vector3 = solver.side_dir(side) * (_reach[side] * elbow_droop)
	var pole: Vector3 = shoulder + inv * (Vector3.DOWN * float(_reach[side]) + out)

	# AIM THE PALM, NOT THE WRIST. The IK places the hand BONE's origin, which is the wrist, so
	# asking it for the haft directly hangs the mace half a metre off the ogre's hand. Instead the
	# wrist is sent to wherever it has to be for the PALM to land on the target -- solved by
	# iteration, because where the palm ends up depends on the orientation the chain adopts, which
	# depends on where the wrist was sent. Two passes is enough at this scale.
	var shaft := solver.grip_node().global_basis.y.normalized() if solver.grip_node() else Vector3.UP
	var here := skel.get_bone_global_pose(ih).origin
	var want := here.lerp(target, float(_grip[side]))
	for _pass in 2:
		TwoBoneIk.solve(skel, iu, il, ih, want, pole)
		var hand_xf := skel.get_bone_global_pose(ih)
		var palm: Vector3 = hand_xf * _palm[side]
		var miss: Vector3 = (here.lerp(target, float(_grip[side]))) - palm
		if miss.length() < 0.002:
			break
		want += miss

	# Roll the palm about the haft. Placing the hand says nothing about which way it faces, and a
	# hand that arrives at the right point in the wrong orientation is not holding anything.
	#
	# NOT FOR AN AUTHORED CLIP: unlike the solve above (absolute -- it lands where it lands), this
	# is a RELATIVE twist, and the action's own recording already carries it. Re-applied on top it
	# doubled to a constant 18 degrees on both hands, and the rotated palm offset then dragged the
	# wrist target with it -- fifty-degree elbow spikes at the strike were this one twist echoing.
	if solver.clip_authored():
		_wrap_fist(skel, side, float(_grip[side]))
	elif absf(palm_roll) > 0.01:
		var sgn := 1.0 if side == 1 else -1.0
		TwoBoneIk.rotate(skel, ih, Quaternion(shaft, deg_to_rad(palm_roll) * sgn))


## WRAP THE FIST ONTO THE LIVE SHAFT, orientation only. The clip's hand rotation was authored
## around the RECORDED weapon; the live weapon points somewhere else, and a palm aligned to the
## wrong shaft reads as an open hand hovering beside the haft. The shaft lies along the hand
## bone's local -Z (measured -- see OgreSolver._measure_grip), so turn the hand by the shortest
## arc from where its shaft axis is to where the shaft actually is. The clip's own recorded roll
## about the shaft survives the alignment.
func _wrap_fist(skel: Skeleton3D, side: int, strength: float) -> void:
	var ih: int = _idx.get(SIDES[side]["hand"], -1)
	if ih < 0 or strength <= 0.001 or solver.grip_node() == null:
		return
	var shaft_w := solver.grip_node().global_basis.y.normalized()
	var shaft_s := (skel.global_transform.basis.orthonormalized().inverse() * shaft_w).normalized()
	var hand_axis := (skel.get_bone_global_pose(ih).basis * Vector3(0, 0, -1)).normalized()
	var wrap_axis := hand_axis.cross(shaft_s)
	if wrap_axis.length_squared() > 0.000001:
		var wrap := hand_axis.angle_to(shaft_s) * strength
		if wrap > 0.0005:
			TwoBoneIk.rotate(skel, ih, Quaternion(wrap_axis.normalized(), wrap))


func _snapshot(skel: Skeleton3D) -> void:
	if _snap.size() != skel.get_bone_count():
		_snap.resize(skel.get_bone_count())
		_snap_basis.resize(skel.get_bone_count())
	var xf := skel.global_transform
	for b in skel.get_bone_count():
		var g := skel.get_bone_global_pose(b)
		_snap[b] = xf * g.origin
		_snap_basis[b] = xf.basis * g.basis

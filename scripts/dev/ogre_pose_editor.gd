extends RefCounted
## THE POSE EDITOR — pose the ogre by dragging its bones, the way you would in Blender.
##
## THIS IS THE KEYFRAME TOOL. A pose IS a keyframe; an `ActionSpec` is the timing and easing between
## keyframes, which is what a curve is. There is no separate animation pipeline to go and find: pose
## here, press SAVE, and the attacks use it immediately.
##
## ─────────────────────────────────────────────────────────────────────────────────────────────
## WHAT YOU AUTHOR — ten poses, and what each is for
## ─────────────────────────────────────────────────────────────────────────────────────────────
##   carry          THE BASE POSE. How it stands and walks holding the mace. Everything blends out
##                  of and back into this one, so do it first and get it right.
##
##   slam_windup    Mace hauled up and back, weight BACK. This is the telegraph — the frame the
##                  player reads as "move now" — so make it unmistakable from across an arena.
##   slam_strike    Mace driven into the floor in front. The head should reach the ground.
##   slam_recover   Follow-through: swung past, being hauled back under control.
##
##   rock_lift      Bent down, both hands at the ground. The grab fires on this one.
##   throw_windup   Rock cocked back over the shoulder, torso wound the opposite way.
##   throw_release  Torso unwound, arm through. The throw fires on this one.
##
##   roar           Chest open, head back. No damage; it gives the fight a beat.
##   stagger        Knocked off balance, weight on the back foot.
##   flinch         A small recoil. Spine and shoulders only — it plays over everything else.
##
## You do NOT author: the walk, the run, turning, footfalls, the crouch, or any settling. Those are
## computed, and posing them would fight the solver.
##
## ─────────────────────────────────────────────────────────────────────────────────────────────
## HOW TO DRIVE IT
## ─────────────────────────────────────────────────────────────────────────────────────────────
##   F4              open the editor. The ogre holds the pose being edited.
##   F2              show the skeleton. Do this first — you cannot pick what you cannot see.
##   LEFT-CLICK      select the joint nearest the cursor.
##   DRAG            IK by default: the joint FOLLOWS the cursor and the limb bends to keep up, so
##                   dragging a hand swings the shoulder and the elbow together. Untick IK to get
##                   FK instead, where the drag rotates only the selected bone and everything below
##                   it swings along -- which is what you want for a spine or a shoulder.
##   SHIFT+DRAG      manipulate the MACE instead of a bone, in whichever gizmo mode is active.
##   G / R           gizmo mode: G moves, R rotates. Applies to the mace and to nothing else --
##                   bones only rotate, because a bone cannot be anywhere but on the end of its
##                   parent.
##   anchor          which bone the mace hangs off. Change it to move the weapon to the other hand,
##                   onto the back, or onto the belt; the placement is stored per pose, so a weapon
##                   can be stowed in one pose and drawn in the next.
##   CTRL+DRAG       move the ROCK in the hand (while one is held).
##   sliders         still there, for roll and for exact numbers.
##   CTRL+Z          undo. Every drag, slider move and button press is one step.
##   AXIS RINGS      three coloured rings at the selected joint - red pitch, green yaw, blue roll.
##                   Click ON a ring to lock the drag to that axis; click the joint for free rotate.
##   MIRROR          copy this bone's angles to the other side.
##   SAVE            writes assets/models/animations/ogre_poses.tres, which the solver then prefers
##                   over the built-in defaults. Your work survives a restart.
##
## WHY DRAGGING, AND WHY THE SLIDERS STAYED. Aiming a bone is two degrees of freedom, and you have
## an opinion about where the hand goes rather than about what its pitch is. Roll is the third, is
## not implied by "point at this", and occasionally you want to type an exact number — so both.
##
## THE DRAG IS INCREMENTAL, deliberately: each frame it takes the rotation from where the bone
## points to where the cursor is and adds that to the pose, in the ogre's own axes. No Euler
## decomposition, nothing to go singular, and it converges on the cursor from any starting
## orientation.

const TuningPanel := preload("res://scripts/dev/tuning_panel.gd")

## The joints worth posing. Everything below the wrist is left alone: twenty finger bones is not
## where an ogre's readability lives, and listing them buries the ones that are.
const BONES: Array[String] = [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperLeg", "RightLowerLeg", "LeftUpperLeg", "LeftLowerLeg",
]

## One line per pose, shown while you edit it, so the panel says what the pose is FOR instead of
## making you remember.
const GUIDE := {
	"carry": "BASE POSE. Standing and walking with the mace. Do this first — all blending goes through it.",
	"slam_windup": "TELEGRAPH. Mace up and back, weight BACK. Must read from across the arena.",
	"slam_strike": "Mace driven into the floor in front. The head should reach the ground.",
	"slam_recover": "Follow-through. Swung past, being hauled back.",
	"rock_lift": "Bent down, both hands at the ground. The grab fires here.",
	"throw_windup": "Rock cocked back over the shoulder, torso wound the other way.",
	"throw_release": "Torso unwound, arm through. The throw fires here.",
	"roar": "Chest open, head back. Pure theatre.",
	"stagger": "Knocked off balance, weight on the back foot.",
	"flinch": "Small recoil. Spine and shoulders only — it plays on top of everything.",
}

var solver: OgreSolver
var enabled := false
var bone := "RightUpperArm"
var pose := "carry"

var _layer: CanvasLayer
var _pose_opt: OptionButton
var _target_opt: OptionButton
var _mode_opt: OptionButton
var _anchor_opt: OptionButton
var _bone_opt: OptionButton
var _sliders: Array[HSlider] = []
var _guide: Label
var _log: RichTextLabel
var _dragging := false
var _mode := 0                  ## 0 bone, 1 weapon aim, 2 held rock
## IK moves the joint you grabbed and bends the limb behind it; FK rotates the bone you grabbed and
## carries its children round with it. Both are needed and they are not interchangeable: a hand
## wants IK (you know where it should BE), a spine wants FK (you know which way it should TURN).
var use_ik := true
## Which axis ring is grabbed: -1 free, 0 pitch (red), 1 yaw (green), 2 roll (blue). The lab draws
## them from `axis_rings()`.
var axis := -1
## What the gizmo is acting on: 0 the selected bone, 1 the mace.
var target_mode := 0
## 0 rotate, 1 move. Bones ignore it -- only the weapon has a position of its own to change.
var gizmo_mode := 0
## Whether the off hand solves onto the haft while the editor is open. DEFAULT OFF, and that is the
## important part: the off-hand IK is a runtime convenience -- it keeps the second hand on the shaft
## through a swing -- and while authoring it is simply an overwrite. With it on, the mace GLUES the
## left arm: you drag the arm, the IK puts it back on the haft, and the arm reads as broken when it
## is only obedient. Tick it to preview the grip once the pose is right.
var off_hand_grip := false
## Radius of the gizmo rings, in metres. Scaled for a four-metre creature.
const RING_R := 0.42

## Where the mace can be hung. A weapon that can only live in one fist is not really placeable --
## stowing it on the back between fights is a pose, not a feature that needs new code.
## Where the mace can be hung. "Body" is the odd one out and the important one: it places the
## weapon on the CREATURE rather than in a fist, and both hands then solve onto the shaft. Use it
## whenever the weapon's path is what you are authoring and the arms should follow.
const ANCHORS: Array[String] = ["RightHand", "LeftHand", "Body", "UpperChest", "Hips"]

## Undo stack. One entry per EDIT - a drag is one step, not one per frame, or a single gesture would
## bury everything before it under two hundred entries.
var _undo: Array[Dictionary] = []


func build(host: Node, s: OgreSolver) -> void:
	solver = s
	var box := TuningPanel.build_panel(host, 340, 520)
	_layer = box.get_parent().get_parent().get_parent() as CanvasLayer
	_layer.layer = 41                       # above the tuning panel, which sits at 40
	_layer.visible = false

	TuningPanel.header(box, "POSE EDITOR  —  F4")
	TuningPanel.line(box, "Click a joint, DRAG to point it.  Shift+drag aims the mace.  Ctrl+drag moves a held rock.",
			Color(0.72, 0.84, 0.72))
	_guide = TuningPanel.line(box, "", Color(0.95, 0.85, 0.5))

	_target_opt = TuningPanel.option(box, "editing", PackedStringArray(["bone", "MACE"]), 0,
			func(i: int) -> void:
				target_mode = i
				_note("editing %s" % ["bones", "the mace"][i]))
	_mode_opt = TuningPanel.option(box, "gizmo  (G / R)",
			PackedStringArray(["rotate", "move"]), 0,
			func(i: int) -> void:
				gizmo_mode = i
				_note("gizmo: %s" % ["rotate", "move"][i]))
	_anchor_opt = TuningPanel.option(box, "mace anchor bone",
			PackedStringArray(ANCHORS), 0,
			func(i: int) -> void:
				_push_undo()
				var w := _weapon()
				w["bone"] = ANCHORS[i]
				solver.poses.set_weapon(StringName(pose), w)
				_note("mace anchored to %s" % ANCHORS[i]))

	_pose_opt = TuningPanel.option(box, "pose", _pose_names(), 0,
			func(i: int) -> void:
				pose = _pose_opt.get_item_text(i)
				_refresh())
	_bone_opt = TuningPanel.option(box, "bone", PackedStringArray(BONES), BONES.find(bone),
			func(i: int) -> void:
				bone = BONES[i]
				_refresh())

	for i in 3:
		var nm: String = ["pitch (tip fwd)", "yaw (twist)", "roll (tilt)"][i]
		var idx := i
		_sliders.append(TuningPanel.slider(box, nm, -180.0, 180.0, 1.0, 0.0,
				func(v: float) -> void: _set_axis(idx, v)))

	TuningPanel.check(box, "preview off-hand grip  (off while posing)", false,
			func(v: bool) -> void:
				off_hand_grip = v
				_off_hand(true)
				_note("off hand %s" % ("solving to the haft" if v else "RELEASED - the left arm is yours")))
	TuningPanel.check(box, "IK  (drag MOVES the joint; off = FK, drag rotates it)", true,
			func(v: bool) -> void:
				use_ik = v
				_note("drag mode: %s" % ("IK — joint follows the cursor" if v else "FK — bone rotates")))
	TuningPanel.button(box, "MIRROR to other side", _mirror)
	TuningPanel.button(box, "UNDO   (Ctrl+Z)", undo)
	TuningPanel.button(box, "RESET bone", func() -> void:
		_push_undo()
		_bones().erase(bone)
		_refresh())
	TuningPanel.button(box, "RESET pose", func() -> void:
		_push_undo()
		solver.poses.poses[pose] = {}
		_refresh())
	TuningPanel.button(box, "SAVE all poses", _save)
	TuningPanel.button(box, "RELOAD from disk", _reload)
	_log = TuningPanel.log_pane(box, 84)
	_note("F2 shows the skeleton — turn it on before picking.")
	_refresh()


func toggle() -> void:
	enabled = not enabled
	_layer.visible = enabled
	# Holding the pose is what makes editing possible at all: without it the ogre blends back to
	# `carry` and every change disappears half a second later.
	solver.preview_pose = StringName(pose) if enabled else &""
	# INERTIA OFF WHILE POSING. The dynamics layer makes every bone arrive late, so with it running
	# the skeleton you are dragging is showing where the pose WAS, not what it is -- the drag chases
	# a lagging target and converges at a crawl. Off, you see the pose exactly. Close the editor and
	# the weight comes back.
	# Hold the body still. See OgreSolver.posing for why every one of these has to stop.
	solver.posing = enabled
	if solver.dynamics:
		solver.dynamics.active = not enabled
	# Editor open: the left arm belongs to you. Editor closed: the IK takes it back and puts it on
	# the haft, which is what it is for during play.
	_off_hand(true)
	_note("editor %s%s" % ["ON" if enabled else "off",
			"  (body frozen and inertia paused - what you set is what you see)" if enabled else ""])


# =================================================================================================
# DIRECT MANIPULATION
# =================================================================================================

## Returns true when the editor consumed the event, so the lab does not act on it as well.
func handle_input(e: InputEvent, cam: Camera3D) -> bool:
	if not enabled or cam == null:
		return false
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var k := e as InputEventKey
		if k.keycode == KEY_Z and k.ctrl_pressed:
			undo()
			return true
		if k.keycode == KEY_G or k.keycode == KEY_R:
			gizmo_mode = 1 if k.keycode == KEY_G else 0
			_mode_opt.select(gizmo_mode)
			_note("gizmo: %s" % ["rotate", "move"][gizmo_mode])
			return true
		return false
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		_dragging = mb.pressed
		if mb.pressed:
			_mode = 1 if (mb.shift_pressed or target_mode == 1) else (2 if mb.ctrl_pressed else 0)
			_push_undo()          # one entry per GESTURE, taken as the button goes down
			_pick(cam, mb.position)
		return true
	if e is InputEventMouseMotion and _dragging:
		match _mode:
			1:
				_drag_mace(cam, (e as InputEventMouseMotion).position)
			2:
				_drag_rock(cam, (e as InputEventMouseMotion).position)
			_:
				_drag_bone(cam, (e as InputEventMouseMotion).position)
		return true
	return false


## The three axis rings for the selected joint: centre, then each ring's normal. Red is pitch,
## green yaw, blue roll - the same order as the sliders, so the gizmo and the panel agree about
## what the second one means.
func axis_rings() -> Array:
	var skel := solver.skeleton()
	var pts := _points()
	if skel == null or pts.is_empty():
		return []
	var centre: Vector3
	if target_mode == 1 or _mode == 1:
		var g := solver.grip_node()
		if g == null:
			return []
		centre = g.global_position
	else:
		var i := skel.find_bone(bone)
		if i < 0 or i >= pts.size():
			return []
		centre = pts[i]
	return [centre, solver.right(), Vector3.UP, solver.forward()]


## Select the joint nearest the cursor, or one of its axis rings - which locks the next drag to that
## axis alone. Free rotation is what you want most of the time; an axis is what you want when the
## free version keeps introducing a twist you did not ask for.
func _pick(cam: Camera3D, at: Vector2) -> void:
	var pts := _points()
	var skel := solver.skeleton()
	if pts.is_empty() or skel == null:
		return
	var best := ""
	var best_d := 60.0                      # pixels; past this you meant to click nothing
	if _mode == 1:
		axis = -1
		var wr := axis_rings()
		if wr.size() >= 4:
			for ax in 3:
				if _near_ring(cam, at, wr[0], wr[ax + 1]):
					axis = ax
					_note("mace axis locked: %s" % ["pitch", "yaw", "roll"][ax])
					return
		_note("mace: free %s" % ["rotate", "move"][gizmo_mode])
		return
	for b in BONES:
		var i := skel.find_bone(b)
		if i < 0 or i >= pts.size() or cam.is_position_behind(pts[i]):
			continue
		var d := cam.unproject_position(pts[i]).distance_to(at)
		if d < best_d:
			best_d = d
			best = b
	# Rings first: they sit ON the joint, so testing the joint first would always win.
	var rings := axis_rings()
	if not rings.is_empty():
		var centre: Vector3 = rings[0]
		for ax in 3:
			if _near_ring(cam, at, centre, rings[ax + 1]):
				axis = ax
				_note("axis locked: %s" % ["pitch", "yaw", "roll"][ax])
				return
	axis = -1
	if best != "":
		bone = best
		_bone_opt.select(BONES.find(bone))
		_refresh()
		_note("selected %s  (free rotate; click a ring to lock an axis)" % bone)


## Is the cursor on the ring whose plane has normal `n`? Sampled around the circle rather than
## solved: a projected circle is an ellipse, and sampling is shorter and immune to the degenerate
## case where the ring is edge-on to the camera.
func _near_ring(cam: Camera3D, at: Vector2, centre: Vector3, n: Vector3) -> bool:
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u).normalized()
	for k in 24:
		var a := TAU * float(k) / 24.0
		var pt := centre + (u * cos(a) + v * sin(a)) * RING_R
		if cam.is_position_behind(pt):
			continue
		if cam.unproject_position(pt).distance_to(at) < 14.0:
			return true
	return false


## Drag the selection. IK moves it; FK rotates it. See `use_ik`.
func _drag_bone(cam: Camera3D, at: Vector2) -> void:
	var skel := solver.skeleton()
	if skel == null:
		return
	var i := skel.find_bone(bone)
	var pts := _points()
	if i < 0 or i >= pts.size():
		return
	# Where the cursor is, placed at the joint's own distance from the camera, so a drag moves it in
	# the plane you are looking at rather than toward or away from you.
	var depth := maxf(cam.global_position.distance_to(pts[i]), 0.5)
	var want := cam.project_ray_origin(at) + cam.project_ray_normal(at) * depth

	if axis >= 0:
		_drag_axis(pts, i, want, skel)
		_push_sliders()
		return

	var lower := skel.get_bone_parent(i)
	var upper := skel.get_bone_parent(lower) if lower >= 0 else -1
	# Both bones the IK would rotate have to be ones the pose layer actually applies, or the drag
	# writes angles into a bone that is silently ignored and the joint appears not to move at all.
	var solvable: bool = upper >= 0 and lower < pts.size() and upper < pts.size() 			and BONES.has(skel.get_bone_name(lower)) and BONES.has(skel.get_bone_name(upper))
	if use_ik and solvable:
		_drag_ik(pts, i, lower, upper, want, skel)
	else:
		_drag_fk(pts, i, want, skel)
	_push_sliders()


## Constrained rotation: swing the bone about ONE body axis. The angle is the signed angle between
## the bone and the cursor, both flattened into the ring's plane - so dragging round the ring turns
## the bone round the ring, and dragging across it does nothing.
func _drag_axis(pts: PackedVector3Array, i: int, want: Vector3, skel: Skeleton3D) -> void:
	var child := _child_of(skel, i)
	if child < 0 or child >= pts.size():
		return
	var axes := [solver.right(), Vector3.UP, solver.forward()]
	var n: Vector3 = axes[axis]
	var head: Vector3 = pts[i]
	var a := (pts[child] - head).slide(n)
	var b := (want - head).slide(n)
	if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
		return
	_apply_rotation(bone, Quaternion(n, a.signed_angle_to(b, n)))


## FK: rotate the selected bone so it points at the cursor. Everything below it comes along, which
## is exactly what you want when the thing you are placing is a whole chain — a spine, a shoulder.
func _drag_fk(pts: PackedVector3Array, i: int, want: Vector3, skel: Skeleton3D) -> void:
	var child := _child_of(skel, i)
	if child < 0 or child >= pts.size():
		return
	_apply_delta(bone, pts[child] - pts[i], want - pts[i])


## IK: move the grabbed joint to the cursor and bend the two bones above it to reach.
##
## Analytic, and the same law-of-cosines construction TwoBoneIk uses at runtime — but the result is
## written into the POSE as body-relative angles rather than onto the skeleton, because the pose is
## the thing being authored. Both bones are rotated in one pass: the upper toward the solved elbow,
## then the lower from that NEW elbow toward the target. Using the old elbow for the second step is
## the classic mistake and leaves the forearm solving against a shoulder that has already moved.
##
## Incremental, like the FK drag, so it converges on the cursor over a few frames from wherever the
## limb started and never has to invert anything.
func _drag_ik(pts: PackedVector3Array, tip: int, lower: int, upper: int, want: Vector3,
		skel: Skeleton3D) -> void:
	var a: Vector3 = pts[upper]
	var b: Vector3 = pts[lower]
	var c: Vector3 = pts[tip]
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 0.001 or l2 < 0.001:
		return
	var to := want - a
	if to.length_squared() < 0.0001:
		return
	var dir := to.normalized()
	# Short of full extension, for the reason TwoBoneIk's header gives: at exactly full reach the
	# bend plane is undefined and the joint flips.
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.98)
	# Keep the bend plane the limb is already in, so the elbow does not swap sides mid-drag.
	var n := dir.cross(b - a)
	if n.length_squared() < 0.000001:
		n = dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	n = n.normalized()
	var alpha := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var b_new := a + (Quaternion(n, alpha) * dir) * l1
	var c_new := a + dir * d
	_apply_delta(skel.get_bone_name(upper), b - a, b_new - a)
	_apply_delta(skel.get_bone_name(lower), c - b, c_new - b_new)


## Add the rotation that takes `from` onto `to` into a bone's pose entry.
##
## SOLVED, not split. The obvious version projects the delta onto the three body axes and adds each
## to the matching angle -- and that is only correct for small rotations, because the pose composes
## its three angles in sequence and sequenced rotations do not commute. With any real pitch on the
## bone, the yaw term rotates about an axis that pitch has already moved, the parts interfere, and
## the drag walks the joint steadily AWAY from the cursor. That is not a subtle inaccuracy: the
## first version pushed the hand nearly two metres in the wrong direction.
##
## So the delta is composed onto the pose's existing rotation and the whole thing is converted back
## to angles through the same construction the pose layer applies. Exact at any angle.
##
## Still stepped, because the target moves under the cursor and a partial step each frame reads as
## the limb following your hand rather than snapping to it.
const STEP := 0.5

func _apply_delta(bone_name: String, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return
	_apply_rotation(bone_name, Quaternion(from.normalized(), to.normalized()))


## Compose a world-space rotation onto a bone's pose entry and solve back to three angles.
func _apply_rotation(bone_name: String, q: Quaternion) -> void:
	var frame := PoseSet.body_frame(solver.right(), Vector3.UP, solver.forward())
	var d := _bones()
	var cur: Vector3 = d.get(bone_name, Vector3.ZERO)
	var want := Basis(Quaternion.IDENTITY.slerp(q.normalized(), STEP)) * PoseSet.to_basis(cur, frame)
	var a := PoseSet.from_basis(want, frame)
	d[bone_name] = Vector3(wrapf(a.x, -180.0, 180.0), wrapf(a.y, -180.0, 180.0),
			wrapf(a.z, -180.0, 180.0))


## The IK drag, addressed by a WORLD POINT rather than by a cursor. Same code path the mouse takes —
## it exists so a probe can drive the drag without synthesising mouse events, which is the only way
## to test that the tool actually moves the ogre rather than merely running without errors.
func _drag_ik_to(want: Vector3) -> void:
	var skel := solver.skeleton()
	if skel == null:
		return
	var i := skel.find_bone(bone)
	var pts := _points()
	if i < 0 or i >= pts.size():
		return
	if axis >= 0:
		_drag_axis(pts, i, want, skel)
		_push_sliders()
		return

	var lower := skel.get_bone_parent(i)
	var upper := skel.get_bone_parent(lower) if lower >= 0 else -1
	if upper < 0 or upper >= pts.size():
		return
	_drag_ik(pts, i, lower, upper, want, skel)


## Move or rotate the mace, in the ogre's own frame, storing the result on the pose.
##
## Everything is expressed relative to the BODY, not the world: a placement authored while the ogre
## faces one way has to be correct facing any other, and the anchor bone moves as the creature does.
func _drag_mace(cam: Camera3D, at: Vector2) -> void:
	var grip := solver.grip_node()
	if grip == null:
		return
	var origin := grip.global_position
	var depth := maxf(cam.global_position.distance_to(origin), 0.5)
	var want := cam.project_ray_origin(at) + cam.project_ray_normal(at) * depth
	var body := Basis(Vector3.UP, solver.facing)
	var w := _weapon()
	var axes := [solver.right(), Vector3.UP, solver.forward()]

	if gizmo_mode == 1:
		# MOVE. The offset is stored from the anchor bone, so the drag is converted back through
		# the anchor rather than being an absolute world position.
		# Through the WEAPON'S frame, because that is the frame the offset is stored in -- see the
		# note in OgreSolver._aim_weapon(). Converting through the body frame here would author a
		# number the solver then reads as meaning something else, and the mace would jump the
		# instant you let go of it.
		var anchor := _anchor_world(w)
		var wb := grip.global_basis.orthonormalized()
		var target_pos: Vector3 = wb.inverse() * (want - anchor)
		var cur_pos: Vector3 = w["pos"]
		if axis >= 0:
			# Locked: keep every component but the one on the grabbed ring's axis.
			var n: Vector3 = wb.inverse() * axes[axis]
			var along := (target_pos - cur_pos).dot(n)
			target_pos = cur_pos + n * along
		w["pos"] = cur_pos.lerp(target_pos, STEP)
	else:
		# ROTATE. The shaft is the mace's local +Y, so the drag turns that toward the cursor.
		var shaft := grip.global_basis.y.normalized()
		var q: Quaternion
		if axis >= 0:
			var n: Vector3 = axes[axis]
			var a := shaft.slide(n)
			var b := (want - origin).slide(n)
			if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
				return
			q = Quaternion(n, a.signed_angle_to(b, n))
		else:
			var d := want - origin
			if d.length_squared() < 0.0001:
				return
			q = Quaternion(shaft, d.normalized())
		# Into the body frame, where the pose stores it.
		var q_body := (body.inverse() * Basis(q.normalized()) * body).get_rotation_quaternion()
		var cur_rot := Basis.from_euler((w["rot"] as Vector3) * (PI / 180.0), EULER_ORDER_XYZ)
		var new_rot := Basis(Quaternion.IDENTITY.slerp(q_body, STEP)) * cur_rot
		w["rot"] = new_rot.get_euler(EULER_ORDER_XYZ) * (180.0 / PI)
	solver.poses.set_weapon(StringName(pose), w)


func _weapon() -> Dictionary:
	return solver.poses.weapon_of(StringName(pose))


func _anchor_world(w: Dictionary) -> Vector3:
	var pts := _points()
	var bi := solver.bone(w.get("bone", "RightHand"))
	if bi >= 0 and bi < pts.size():
		return pts[bi]
	return solver.global_position + Vector3.UP * (solver.leg_length * 1.35)


## Slide a held rock around in the hand.
func _drag_rock(cam: Camera3D, at: Vector2) -> void:
	var grip := solver.grip_node()
	if grip == null:
		return
	var depth := maxf(cam.global_position.distance_to(grip.global_position), 1.0)
	var want := cam.project_ray_origin(at) + cam.project_ray_normal(at) * depth
	solver.rock_hold = grip.global_transform.affine_inverse() * want
	_note("rock hold %v" % solver.rock_hold)


func _points() -> PackedVector3Array:
	return solver.arm_ik.bone_positions() if solver.arm_ik else PackedVector3Array()


## The joint this bone points AT — its longest child, so dragging an upper arm swings the elbow.
func _child_of(skel: Skeleton3D, i: int) -> int:
	var kids := skel.get_bone_children(i)
	if kids.is_empty():
		return -1
	var best: int = kids[0]
	var best_d := -1.0
	var here := skel.get_bone_global_rest(i).origin
	for k in kids:
		var d := here.distance_to(skel.get_bone_global_rest(k).origin)
		if d > best_d:
			best_d = d
			best = k
	return best


# =================================================================================================
# PANEL
# =================================================================================================

## Let the off hand go, or put it back on the haft. Off while placing the weapon: with it on, moving
## the mace drags the arm after it and you cannot tell whether the arm is where you want it or
## merely where the weapon dragged it.
func _off_hand(_ignored: bool) -> void:
	if solver.arm_ik == null:
		return
	# While the editor is open the grip is opt-in; outside it, it is always on.
	solver.arm_ik.amount = 1.0 if (not enabled or off_hand_grip) else 0.0


func _pose_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n in solver.poses.names():
		out.append(String(n))
	return out


func _bones() -> Dictionary:
	if not solver.poses.poses.has(pose):
		solver.poses.poses[pose] = {}
	return solver.poses.poses[pose]


func _angles() -> Vector3:
	return _bones().get(bone, Vector3.ZERO)


func _set_axis(which: int, deg: float) -> void:
	_push_undo()
	var a := _angles()
	a[which] = deg
	_bones()[bone] = a


func _refresh() -> void:
	if enabled:
		solver.preview_pose = StringName(pose)
	if _guide:
		_guide.text = GUIDE.get(pose, "")
	if _anchor_opt:
		var b: String = _weapon().get("bone", "RightHand")
		if ANCHORS.has(b):
			_anchor_opt.select(ANCHORS.find(b))
	_push_sliders()


## Write the selected bone's angles into the sliders without those sliders writing them back.
func _push_sliders() -> void:
	var a := _angles()
	var names := ["pitch (tip fwd)", "yaw (twist)", "roll (tilt)"]
	for i in mini(3, _sliders.size()):
		var sl: HSlider = _sliders[i]
		sl.set_block_signals(true)
		sl.value = a[i]
		sl.set_block_signals(false)
		# The caption is written by the handler that was just blocked, so it is set here too. A
		# slider reading 0 beside a bone bent 118 degrees is worse than showing no number at all.
		var cap := sl.get_parent().get_child(sl.get_index() - 1) as Label
		if cap:
			cap.text = "%s  %.2f" % [names[i], a[i]]


# =================================================================================================
# UNDO
# =================================================================================================

## Snapshot the pose being edited. Cheap - a dictionary of at most eighteen Vector3s - so there is
## no reason to be clever about storing deltas.
func _push_undo() -> void:
	var snap := {
		"pose": pose,
		"bones": _bones().duplicate(true),
		"weapon": _weapon().duplicate(true),
	}
	if not _undo.is_empty() and _undo[-1]["pose"] == pose \
			and _undo[-1]["bones"] == snap["bones"] and _undo[-1]["weapon"] == snap["weapon"]:
		return                                  # nothing changed since the last step
	_undo.append(snap)
	if _undo.size() > 64:
		_undo.pop_front()


func undo() -> void:
	if _undo.is_empty():
		_note("nothing to undo")
		return
	var snap: Dictionary = _undo.pop_back()
	pose = snap["pose"]
	solver.poses.poses[pose] = snap["bones"]
	solver.poses.set_weapon(StringName(pose), snap["weapon"])
	var names := _pose_names()
	for i in names.size():
		if names[i] == pose:
			_pose_opt.select(i)
			break
	_refresh()
	_note("undo  (%d left)" % _undo.size())


func _mirror() -> void:
	_push_undo()
	var other := PoseSet.opposite(bone)
	if other == bone:
		_note("%s has no opposite side" % bone)
		return
	_bones()[other] = PoseSet.mirror_angles(_angles())
	_note("mirrored %s -> %s" % [bone, other])


func _save() -> void:
	var err := ResourceSaver.save(solver.poses, OgreSolver.POSES_PATH)
	_note("SAVED (%s)" % ("ok" if err == OK else "error %d" % err))


func _reload() -> void:
	if not ResourceLoader.exists(OgreSolver.POSES_PATH):
		_note("no saved file yet")
		return
	var ps := ResourceLoader.load(OgreSolver.POSES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PoseSet
	if ps:
		solver.poses = ps
		_refresh()
		_note("reloaded from disk")


func _note(t: String) -> void:
	if _log:
		_log.append_text(t + "\n")

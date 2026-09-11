extends Node3D
## THE OGRE LAB — a bench for procedural animation with no keyframes in it anywhere.
##
## WHY IT EXISTS. The ogre's walk, run and settle are computed rather than authored, which means
## there is no clip to scrub and no curve to look at. The only way to judge the thing is to drive it
## and watch, so this scene is built for exactly that: bare lighting, a metre grid, ground that is
## not flat, and every dial on a slider while the creature is moving.
##
## THE LIGHTING IS DELIBERATELY PLAIN, copied from scenes/dev/player_test.tscn along with its
## reasoning: the game's painterly stack flattens contact shadows and limb separation, which are
## precisely the cues you need to read motion. Judge the look in main.tscn; judge the movement here.
##
## THE GROUND IS DELIBERATELY NOT FLAT. Flat ground proves nothing about foot placement — a solver
## that simply drops both feet to y=0 passes it. The ramp and the steps are where you find out
## whether the IK is real.
##
## READ THE NUMBERS, NOT THE VIBE. The readout is rebuilt every frame from the solver's own fields,
## so it cannot disagree with what is on screen (player_test.gd makes the same argument for reading
## the AnimationTree's own playback). The one that matters most is SKATE: the solver claims a
## planted foot cannot slide, and that column is the claim being tested continuously rather than
## once, later, by a probe.

const TuningPanel := preload("res://scripts/dev/tuning_panel.gd")
## Loaded at RUNTIME rather than preloaded. A preload failure is reported as "could not resolve
## script" on THIS file and swallows the real parse error in the other one, which turns a one-line
## typo into a hunt. Loading it here costs nothing and the error arrives with its own line number.
const POSE_EDITOR := "res://scripts/dev/ogre_pose_editor.gd"
const PUPPET := preload("res://scenes/dev/ogre_puppet.tscn")
const PLAYER := "res://scenes/player/player3.tscn"
const ROCK := preload("res://scenes/props/rock.tscn")

## Actions on the number row, in the order you want to try them: the big one first.
const MOVES: Array[StringName] = [&"slam", &"rock_lift", &"rock_throw", &"roar", &"stagger", &"flinch"]

@onready var _ogre: OgrePuppet = $Ogre
@onready var _readout: Label = $UI/Readout
@onready var _rig: CameraRig = $CameraRig
@onready var _debug: MeshInstance3D = $Debug

var _player: Node3D
var _panel_layer: CanvasLayer
## WHAT THE OVERLAY SHOWS. Cycled with F2, named in the readout, because an overlay that draws
## everything at once teaches nothing -- the grip markers were being read as foot targets and the
## foot targets as grip markers.
##
## The order is deliberate: the grip alone first, because that is the thing being debugged, and the
## legs come last because they are the part that is finished and does not want looking at.
const DRAW_MODES: Array[String] = [
	"off", "grip only", "grip + upper body", "grip + whole skeleton", "everything", "attack zones",
]
var _draw := 1
var _step_once := false
## Set by a demo that wants to drive the ogre itself. See _physics_process.
var demo_driving := false
var demo_drive := Vector3.ZERO
var _skate_peak := 0.0
var _mat: StandardMaterial3D
var _demo_cam: Camera3D
var _editor: RefCounted
var _show_bones := false
var _parent_of := PackedInt32Array()
var _drag := false
var _drag_from := Vector2.ZERO
var _fly: FlyCamera
## The rest-stance reference captured by the first bake of a run, exported once as its own .glb.
var _carry_ref: Animation


## BAKE A PROCEDURAL ACTION TO KEYFRAMES, AND WRITE IT OUT FOR BLENDER.
##
## The ogre's motion does not exist as data anywhere. It is computed every frame from a gait law, an
## arc and six springs, which is why there is nothing to open in Blender and nothing to hand an
## animator. The pose editor in this lab can author a KEY POSE, but a pose is not a curve, and the
## interesting part of a swing -- the mace mid-attack, the moment the weight transfers -- lives
## between the poses where nobody can reach it.
##
## This samples the skeleton while the solver drives it and writes what it finds as a real
## `Animation`: one rotation track per bone, plus the hips' position. That resource can then be
## played back like any imported clip, and exported.
##
## GODOT CANNOT WRITE FBX. It writes glTF, which is the better interchange anyway and which Blender
## imports natively -- and this project already round-trips glTF with Blender for the foliage
## generator (`scripts/dev/foliage_lab.gd:234` reads one back at runtime). So the loop is:
##
##     --demo=bake  ->  .glb  ->  Blender  ->  refine  ->  .glb/.fbx  ->  Godot import  ->  clip
##
## WHY SAMPLE RATHER THAN RECOMPUTE. The solver's output depends on state no formula can be handed:
## where the feet were planted, what the springs were carrying, how far the body had turned. The
## only honest way to capture it is to watch it happen, which is also why every measurement in this
## project is taken from the rendered pose rather than predicted.
func _demo_bake(out: String) -> void:
	var which := "slam"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--action="):
			which = a.split("=", true, 1)[1]
	if out == "":
		# A bare `--demo=bake` used to write to the drive root. The default lands the result inside
		# the project, where it is committable and the curve diff has a stable address.
		out = "res://assets/models/animations/ogre_baked"
	var sv: OgreSolver = _ogre.solver
	var skel := sv.skeleton()
	if skel == null:
		print("[BAKE] no skeleton")
		get_tree().quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

	# `--action=all` bakes the whole library in one run, in a stable order. Eleven separate
	# launches is eleven chances to bake a partial set and not notice; the value of the baked
	# library is that it is COMPLETE — a clip for every action, not for the ones somebody
	# remembered.
	var todo: Array[String] = []
	if which == "all":
		var actions: Dictionary = sv.get("_actions")
		for n in actions.keys():
			todo.append(String(n))
		todo.sort()
	else:
		todo.append(which)

	var home: Vector3 = _ogre.global_position
	var lib := AnimationLibrary.new()
	for name in todo:
		# Every action starts from the same stance on the same spot. teleport() zeroes the velocity
		# and resets the solver (feet, springs), and the settle lets it re-plant — without this the
		# second bake starts with the first one's momentum still in the springs.
		_ogre.teleport(home)
		# Pin the breath. `_time` drives the chest oscillator and never resets, and the lab's 0.6 s
		# startup timer fires after a VARIABLE number of physics frames — so two bakes of identical
		# code differed by up to 0.36 deg on the chest, purely from breath phase. Zeroing it here
		# makes the settle, and everything after it, start from the same phase every run.
		# (The 40-frame settle now lives inside _bake_one, which samples it as the carry
		# reference — same frames, same alignment, the .res curves cannot move.)
		sv.set("_time", 0.0)
		var anim := await _bake_one(sv, skel, name, out)
		if anim != null:
			lib.add_animation(StringName(name), anim)

	if todo.size() > 1:
		var lib_path := "%s/ogre_baked.tres" % out
		ResourceSaver.save(lib, lib_path)
		print("[BAKE] library: %d clip(s) -> %s" % [lib.get_animation_list().size(), lib_path])
	if _carry_ref != null:
		_export_glb(sv, skel, _carry_ref, "carry_reference", out)
	_save_glb_readme("%s/glb/README.txt" % out)
	get_tree().quit()


## One action recorded to keyframes, plus its beat timeline. Returns null when the action refuses
## to start — an unknown name would otherwise bake as a three-frame shrug and pass every diff.
func _bake_one(sv: OgreSolver, skel: Skeleton3D, which: String, out: String) -> Animation:
	var names: Array[String] = []
	for b in skel.get_bone_count():
		names.append(skel.get_bone_name(b))
	var hips := skel.find_bone("Hips")

	# THE SETTLE IS ALSO THE REST REFERENCE. These are the same 40 frames the bake always waited
	# out; sampling them costs nothing and answers the animator's first two questions about any
	# clip — "what does rest look like?" and "does my edit still start and end there?". They go
	# into the .glb as a second animation (carry_reference), never into the runtime .res.
	var c_rot: Array = []
	var c_pos: Array[Vector3] = []
	var c_mace: Array[Transform3D] = []
	var c_times: Array[float] = []
	for _b in names.size():
		c_rot.append([])
	for i in 40:
		await get_tree().physics_frame
		_sample_pose(sv, skel, names, c_rot, c_pos, c_mace, hips)
		c_times.append(float(i) / 60.0)

	var rot: Array = []          # per bone, an Array[Quaternion]
	var pos: Array[Vector3] = [] # hips only
	var mace: Array[Transform3D] = []
	var times: Array[float] = []
	for _b in names.size():
		rot.append([])

	# The beat timeline rides along with the curves: every action_event, stamped with the
	# SOLVER'S OWN action clock. A refactor that moves hit_open by two frames is a gameplay change
	# no rotation track can see, and this sidecar is what the diff catches it with.
	var events: Array = []
	var recorder := func(what: StringName, _at: Vector3) -> void:
		events.append({"beat": String(what), "t": sv.action_t})
	sv.action_event.connect(recorder)

	sv.play_action(StringName(which))
	if not sv.is_acting():
		sv.action_event.disconnect(recorder)
		print("[BAKE] %s: refused to start — skipped" % which)
		return null
	var t := 0.0
	for _i in 2000:
		await get_tree().physics_frame
		if not sv.is_acting() and t > 0.05:
			break
		_sample_pose(sv, skel, names, rot, pos, mace, hips)
		# KEY TIMESTAMPS ARE THE ACTION CLOCK, NOT A HAND-KEPT ONE. The sampled pose is the result
		# of a tick that already advanced action_t, so a key stamped with the pre-advance time
		# holds the pose of one frame LATER -- and playback (clip time == action time) then ran
		# one frame ahead of the recording, which read as seventy degrees of error at the one
		# moment the recovery snaps. Stamping with sv.action_t makes curve(t) mean "the pose at
		# action_t == t", which is the identity playback's exact contract.
		times.append(sv.action_t)
		t += 1.0 / 60.0
	sv.action_event.disconnect(recorder)

	var anim := Animation.new()
	anim.length = maxf(t, 0.1)
	anim.loop_mode = Animation.LOOP_NONE
	anim.resource_name = "ogre_%s_baked" % which
	# ONE TRACK PER BONE, addressed the way every other clip in this project is: the node part is
	# thrown away by OgreClipLayer._resolve() and by Godot's own retargeting, so what matters is
	# that the bone name after the colon is a GeneralSkeleton name.
	#
	# EVERY bone goes into the .res, moving or not — the .res is the diff artifact. A threshold
	# filter here made the track SET nondeterministic: a thumb hovering exactly at the cutoff was
	# baked in one run and dropped in the next, and the curve diff read the flap as "track added"
	# on four clips of eleven. Still bones are recorded here and stripped only from the .glb,
	# which is the artifact with an animator on the other end.
	var still_paths: Array[NodePath] = []
	for b in names.size():
		var still := true
		for k in range(1, rot[b].size()):
			if rot[b][k].angle_to(rot[b][0]) > 0.0005:
				still = false
				break
		var p := NodePath("%%GeneralSkeleton:%s" % names[b])
		var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(ti, p)
		for k in times.size():
			anim.rotation_track_insert_key(ti, times[k], rot[b][k])
		if still:
			still_paths.append(p)
	if hips >= 0:
		var pi := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pi, NodePath("%GeneralSkeleton:Hips"))
		for k in times.size():
			anim.position_track_insert_key(pi, times[k], pos[k])

	var res_path := "%s/ogre_%s_baked.res" % [out, which]
	print("[BAKE] %s: %d frames, %.2f s, %d tracks (%d still), %d beat(s) -> %s"
			% [which, times.size(), anim.length, anim.get_track_count(), still_paths.size(),
			events.size(), res_path])
	# FLAG_CHANGE_PATH so the AnimationLibrary written after the loop references these as external
	# resources (the shape player3_anims.tres has) instead of embedding a second copy of each.
	ResourceSaver.save(anim, res_path, ResourceSaver.FLAG_CHANGE_PATH)
	_save_events(events, "%s/ogre_%s_baked.events.json" % [out, which])
	# The Blender copy: the same curves minus the bones that never moved (noise in a curve
	# editor), PLUS everything an animator needs that the runtime must not see -- the mace as an
	# animated node, and the rest stance as a second animation. The .res above keeps every bone
	# and nothing else, so two bakes always disagree in values, never in track sets.
	var glb_anim := anim.duplicate(true) as Animation
	for i in range(glb_anim.get_track_count() - 1, -1, -1):
		if glb_anim.track_get_type(i) == Animation.TYPE_ROTATION_3D \
				and glb_anim.track_get_path(i) in still_paths:
			glb_anim.remove_track(i)
	_add_mace_tracks(glb_anim, mace, times)
	var carry_anim := Animation.new()
	carry_anim.length = c_times.back() if not c_times.is_empty() else 0.1
	carry_anim.loop_mode = Animation.LOOP_LINEAR
	carry_anim.resource_name = "carry_reference"
	# EVERY bone, still or not: this one is a POSE reference, and a rest stance is mostly still.
	for b in names.size():
		var cti := carry_anim.add_track(Animation.TYPE_ROTATION_3D)
		carry_anim.track_set_path(cti, NodePath("%%GeneralSkeleton:%s" % names[b]))
		for k in c_times.size():
			carry_anim.rotation_track_insert_key(cti, c_times[k], c_rot[b][k])
	if hips >= 0:
		var cpi := carry_anim.add_track(Animation.TYPE_POSITION_3D)
		carry_anim.track_set_path(cpi, NodePath("%GeneralSkeleton:Hips"))
		for k in c_times.size():
			carry_anim.position_track_insert_key(cpi, c_times[k], c_pos[k])
	_add_mace_tracks(carry_anim, c_mace, c_times)
	if _carry_ref == null:
		_carry_ref = carry_anim          # every action settles into the same stance; one is enough
	_save_beats_txt(events, anim.length, which, "%s/glb/ogre_%s_baked.beats.txt" % [out, which])
	_export_glb(sv, skel, glb_anim, which, out)
	return anim


## The mace, riding along as node tracks. A two-handed swing without the thing being swung cannot
## be read, let alone refined -- but the runtime never sees these: the weapon is aimed LIVE in the
## game, and the clip layer resolves bone names only, so a "Mace" node track is inert in a .res.
func _add_mace_tracks(anim: Animation, mace: Array[Transform3D], times: Array[float]) -> void:
	if mace.is_empty():
		return
	var tp := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(tp, NodePath("Mace"))
	var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(tr, NodePath("Mace"))
	for k in times.size():
		anim.position_track_insert_key(tp, times[k], mace[k].origin)
		anim.rotation_track_insert_key(tr, times[k],
				mace[k].basis.orthonormalized().get_rotation_quaternion())


## One frame of the RENDERED pose, plus the weapon, in skeleton space.
##
## FROM THE END-OF-PASS SNAPSHOT, which is the only place the finished pose exists: the layers
## write into the modification buffer, and from outside the pass both get_bone_pose_rotation()
## and get_bone_global_pose() show what the USER set, not what the stack produced -- sampled
## either of those ways the slam came out with eight moving bones of sixty-five.
##
## THE ROOT IS THE TRAP. The snapshot is world space; every other bone's parent-inverse cancels
## the skeleton's own transform, but the root kept it -- the baked Hips carried the model's 180
## degree yaw and played back a half turn wrong. In skeleton space a root's global pose IS its
## local pose, which is what a track must hold; the hips position and the mace live in the same
## space for the same reason.
func _sample_pose(sv: OgreSolver, skel: Skeleton3D, names: Array[String], rot: Array,
		pos: Array[Vector3], mace: Array[Transform3D], hips: int) -> void:
	var snap: PackedVector3Array = sv.arm_ik.bone_positions()
	var to_skel := skel.global_transform.affine_inverse()
	for b in names.size():
		var g := Transform3D(sv.arm_ik.bone_basis(b), snap[b] if b < snap.size() else Vector3.ZERO)
		var par := skel.get_bone_parent(b)
		var loc := g
		if par >= 0 and par < snap.size():
			loc = Transform3D(sv.arm_ik.bone_basis(par), snap[par]).affine_inverse() * g
		else:
			loc = to_skel * g
		rot[b].append(loc.basis.orthonormalized().get_rotation_quaternion())
	pos.append(to_skel * snap[hips] if hips >= 0 and hips < snap.size() else Vector3.ZERO)
	var gn := sv.grip_node()
	mace.append((to_skel * gn.global_transform) if gn else Transform3D.IDENTITY)


## THE 360-DEGREE CONTORTION CHECK, in the game itself. A clip can be sane in Blender and the
## pose still wrong on screen -- the grip solve, the live mace and every layer add their part --
## so this photographs ONE action from a ring of angles at a set of moments. One clean replay per
## angle, NO freezing: pausing the tick while the render clock keeps easing the weapon turned the
## instrument itself into a source of contortions.
##
##   --demo=orbit --action=slam --out=user://orbit
func _demo_orbit(out: String) -> void:
	var which := "slam"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--action="):
			which = a.split("=", true, 1)[1]
	if out == "":
		out = "user://orbit"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var sv: OgreSolver = _ogre.solver
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.current = true
	_show_bones = false
	var fracs := [0.15, 0.35, 0.55, 0.75, 0.95]
	var angles := 8
	var home: Vector3 = _ogre.global_position
	for ai in angles:
		var ang := TAU * float(ai) / float(angles)
		_ogre.teleport(home)
		sv.set("_time", 0.0)
		for _i in 40:
			await get_tree().physics_frame
		var centre: Vector3 = _ogre.global_position + Vector3.UP * 2.4
		cam.global_position = centre + Vector3(sin(ang), 0.30, cos(ang)) * 8.0
		cam.look_at(centre)
		sv.play_action(StringName(which))
		if not sv.is_acting():
			print("[ORBIT] %s refused to start" % which)
			get_tree().quit(1)
			return
		for fi in fracs.size():
			var want: float = float(fracs[fi]) * sv.action_len
			while sv.is_acting() and sv.action_t < want:
				await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					"%s/%s_t%02d_a%d.png" % [out, which, int(float(fracs[fi]) * 100.0), ai])
		while sv.is_acting():
			await get_tree().physics_frame
	print("[ORBIT] %d shots -> %s" % [fracs.size() * angles, out])
	get_tree().quit()


## WHERE DOES THIS ATTACK ACTUALLY LAND? Plays each attack and reports, at its strike beat, how
## far from the body the mace head is and how high — plus the lowest the head gets across the
## whole action.
##
## THE QUESTION ONLY EXISTS BECAUSE THE ANIMATION OWNS THE WEAPON NOW. While the solver aimed
## the mace, "where does it land" was answered by construction: at the aim point, because the
## arc was solved to reach it. A bought performance swings where the animator swung, so the
## reach is a MEASUREMENT — and the attack's band, its lunge and its telegraph all have to be
## set from that measurement rather than from the arm geometry that used to imply it.
##
##   --demo=reach
func _demo_reach(_out: String) -> void:
	var sv: OgreSolver = _ogre.solver
	await get_tree().physics_frame
	print("[REACH] action      strike    head dist   head y   lowest y")
	for which in [&"slam", &"sweep", &"pound", &"rock_throw", &"backstep"]:
		if sv.spec(which) == null:
			continue
		sv.play_action(which)
		if not sv.is_acting():
			print("[REACH] %-10s refused to start" % which)
			continue
		var want: float = sv.spec(which).time_of(&"strike")
		var from: Vector3 = _ogre.global_position
		var at_strike := {}
		var low := 99.0
		var series: Array = []
		var prev := Vector3.INF
		var fastest := {"v": -1.0}
		for _i in 900:
			if not sv.is_acting():
				break
			await get_tree().physics_frame
			var g := sv.grip_node()
			if g == null:
				continue
			var head: Vector3 = g.global_position \
					+ g.global_basis.y.normalized() * sv.weapon_length
			var rel: Vector3 = head - _ogre.global_position
			low = minf(low, rel.y)
			var spd := 0.0
			if prev != Vector3.INF:
				spd = head.distance_to(prev) / get_physics_process_delta_time()
			prev = head
			# THE CLIP'S OWN IMPACT INSTANT: where the head is travelling fastest. That is the
			# moment the action's strike beat has to be pinned to, and the distance the head is
			# at THEN is the range the attack actually covers.
			if spd > float(fastest["v"]):
				fastest = {"v": spd, "t": sv.action_t,
						"d": Vector2(rel.x, rel.z).length(), "y": rel.y}
			if at_strike.is_empty() and sv.action_t >= want:
				# THE BAND IS HEAD + LUNGE. The attack is chosen from where the ogre STANDS,
				# and the lunge carries it forward before the head arrives — so the distance
				# it should be picked at is the head's reach at contact PLUS the ground the
				# body covers getting there. Measuring both is the only way to set a band that
				# an animation, rather than an arm, decides.
				var travelled: float = Vector2(_ogre.global_position.x - from.x,
						_ogre.global_position.z - from.z).length()
				# AND ON WHAT BEARING. The animator's swing does not necessarily come down the
				# body's centre line — an overhead crosses from the shoulder — so aiming the
				# BODY at the player still misses by whatever that offset is. Signed degrees
				# from forward, positive to the ogre's right.
				var fwd: Vector3 = sv.forward()
				var flat := Vector3(rel.x, 0.0, rel.z)
				var bearing := 0.0
				if flat.length() > 0.05:
					flat = flat.normalized()
					bearing = rad_to_deg(atan2(flat.dot(sv.right()), flat.dot(fwd)))
				at_strike = {"d": Vector2(rel.x, rel.z).length(), "y": rel.y,
						"lunge": travelled, "bearing": bearing}
			var flat2 := Vector3(rel.x, 0.0, rel.z)
			var bear2 := 0.0
			if flat2.length() > 0.05:
				flat2 = flat2.normalized()
				bear2 = rad_to_deg(atan2(flat2.dot(sv.right()), flat2.dot(sv.forward())))
			series.append([sv.action_t, Vector2(rel.x, rel.z).length(), rel.y, spd, bear2,
					sv.clip_layer.time])
		print("[REACH] %-10s %6.2f s %8.2f m %8.2f m %8.2f m | lunge %.2f -> PICK AT %.2f m | BEARING %+.0f deg"
				% [which, want, at_strike.get("d", -1.0), at_strike.get("y", -1.0), low,
				at_strike.get("lunge", 0.0),
				float(at_strike.get("d", 0.0)) + float(at_strike.get("lunge", 0.0)),
				at_strike.get("bearing", 0.0)])
		var step: int = maxi(1, series.size() / 14)
		for si in range(0, series.size(), step):
			var r: Array = series[si]
			# clip_t is the number that goes in HUNTER_SKIN's `contact`: pick the row where the
			# head is IN FRONT (bearing near zero), low, and moving — that is the blow.
			print("[REACH]      t=%.2f clip %.2f  dist %.2f  y %+.2f  bearing %+4.0f  %5.1f m/s"
					% [r[0], r[5], r[1], r[2], r[4], r[3]])
		for _i in 60:
			await get_tree().physics_frame
	print("[REACH] the band each attack is chosen at must contain its head distance, or it swings at air")
	get_tree().quit()


## ANY LIBRARY CLIP, RAW, ON THE OGRE — the viewer for clips that are not (yet) actions.
## An ARDY-generated clip lands in ogre_clips.tres wired to no ActionSpec, so --demo=orbit
## cannot show it; this plays it straight through the clip layer with every procedural layer
## off, looping in real time. With --out it screenshots one pass and quits (evidence mode);
## without, it loops until the window closes (the human mode).
##
##   --demo=viewclip --action=ardy_kick [--out=user://viewclip]
func _demo_viewclip(out: String) -> void:
	var which := "slam"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--action="):
			which = a.split("=", true, 1)[1]
	var lib := ResourceLoader.load("res://assets/models/animations/ogre_clips/ogre_clips.tres") \
			as AnimationLibrary
	if lib == null or not lib.has_animation(StringName(which)):
		print("[VIEWCLIP] no clip '%s' in ogre_clips.tres" % which)
		get_tree().quit(1)
		return
	var anim := lib.get_animation(StringName(which))

	var sv: OgreSolver = _ogre.solver
	# The pureclip recipe: arm_ik stays ACTIVE at amount 0 because it is the thing that
	# snapshots bone positions, and the weapon is placed from that snapshot. PLUS the limit
	# layer off — unlike a baked clip (solver output, inside the joint budgets by
	# construction), a foreign clip can stand outside them, and the clamp squashing it into
	# budget reads as a broken retarget. MEASURED: the ARDY kick was pose-perfect under
	# manual FK while this viewer showed a deep squat; the clamp was the whole difference.
	sv.pose_layer.active = false
	sv.gait_layer.active = false
	sv.dynamics.active = false
	sv.foot_ik.active = false
	sv.limit_layer.active = false
	sv.arm_ik.amount = 0.0
	sv.clip_layer.raw = true
	sv.clip_layer.clip = anim
	sv.clip_layer.weight = 1.0
	sv.clip_layer.time = 0.0
	sv.posing = true

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	_show_bones = true
	print("[VIEWCLIP] %s: %.2f s, %d tracks, looping" % [which, anim.length, anim.get_track_count()])

	var shots := 8
	var next_shot := 0
	var t := 0.0
	var done_pass := false
	if out != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	while true:
		t += get_physics_process_delta_time()
		# GROUND THE PERFORMANCE. Raw playback holds the hips at skeleton rest, and a clip
		# whose legs are straighter than the ogre's bent stance (any human-sourced clip) then
		# hangs in the air — in gameplay the foot IK owns ground contact, so the float is a
		# raw-mode artifact, not a retarget fault; it cost half a day of chasing the retarget.
		# The support foot (lower of the two, read from the arm_ik snapshot — the only record
		# of what the mesh shows; poses read after the update have reverted to rest) is glued
		# to the floor by offsetting the whole body, smoothed so a kick doesn't pogo the rig.
		var bp: PackedVector3Array = sv.arm_ik.bone_positions()
		var skel := sv.clip_layer.get_skeleton()
		var rfb := skel.find_bone("RightFoot")
		var lfb := skel.find_bone("LeftFoot")
		if bp.size() > maxi(rfb, lfb):
			var sole: float = minf(bp[rfb].y, bp[lfb].y) - _ogre.global_position.y
			var want_y: float = sv.ankle_height - sole
			_ogre.global_position.y = lerpf(_ogre.global_position.y, want_y, 0.2)
		# SIDE ON, the pureclip doctrine: the ogre faces -Z, so from +X the whole performance
		# happens in the plane of the screen. The three-quarter view this started with hid the
		# kick behind the body and got a correct clip called a broken one.
		var xf: Transform3D = _ogre.global_transform
		cam.global_position = xf.origin * Vector3(1, 0, 1) + Vector3(11.0, 3.2, 0.0)
		cam.look_at(xf.origin * Vector3(1, 0, 1) + Vector3.UP * 2.0)
		if t >= anim.length:
			t = fmod(t, anim.length)
			done_pass = true
		sv.clip_layer.time = t
		await get_tree().physics_frame
		if out != "" and not done_pass and t >= anim.length * float(next_shot) / float(shots):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					"%s/%s_%02d.png" % [out, which, next_shot])
			next_shot += 1
		if out != "" and done_pass:
			print("[VIEWCLIP] %d shots -> %s" % [next_shot, out])
			get_tree().quit()
			return


## ROUND-TRIP CHECK for a directory of baked clips: each .res is played back through the clip
## layer in raw mode (every other layer off) and must actually move the skeleton. This catches the
## one bake failure a diff can never see — tracks that resolve onto nothing (wrong bone names, an
## empty clip), which plays as a statue and diffs as a perfect match against itself.
##
##   --demo=bakecheck --out=res://assets/models/animations/ogre_baked_before
func _demo_bakecheck(out: String) -> void:
	if out == "":
		out = "res://assets/models/animations/ogre_baked_before"
	var sv: OgreSolver = _ogre.solver
	var fails: Array[String] = []
	var d := DirAccess.open(out)
	if d == null:
		print("[BAKECHECK] no such dir: %s" % out)
		get_tree().quit(1)
		return
	var clips := PackedStringArray()
	for f in d.get_files():
		if f.ends_with(".res"):
			clips.append(f)
	clips.sort()
	if clips.is_empty():
		print("[BAKECHECK] no .res clips in %s" % out)
		get_tree().quit(1)
		return

	# Raw-clip mode, same recipe as --demo=pureclip: every procedural layer off; arm_ik stays
	# ACTIVE at amount 0 because it is the thing that snapshots bone positions.
	sv.pose_layer.active = false
	sv.gait_layer.active = false
	sv.dynamics.active = false
	sv.foot_ik.active = false
	sv.arm_ik.amount = 0.0
	sv.clip_layer.raw = true
	sv.posing = true

	for f in clips:
		var anim := ResourceLoader.load("%s/%s" % [out, f]) as Animation
		if anim == null:
			fails.append("%s: did not load" % f)
			continue
		sv.clip_layer.clip = anim
		sv.clip_layer.weight = 1.0
		sv.clip_layer.time = 0.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		var base: PackedVector3Array = sv.arm_ik.bone_positions().duplicate()
		var moved := 0.0
		var steps := 8
		for i in steps:
			sv.clip_layer.time = anim.length * float(i + 1) / float(steps + 1)
			await get_tree().physics_frame
			await get_tree().physics_frame
			var now: PackedVector3Array = sv.arm_ik.bone_positions()
			for b in mini(base.size(), now.size()):
				moved = maxf(moved, base[b].distance_to(now[b]))
		print("[BAKECHECK] %-28s len %.2f s  max bone travel %.3f m" % [f, anim.length, moved])
		# 5 cm on a four-metre creature is nothing: a real action swings hands through metres.
		if moved < 0.05:
			fails.append("%s: skeleton barely moved (%.3f m) — tracks resolving onto nothing?"
					% [f, moved])

	for msg in fails:
		print("[BAKECHECK] FAIL %s" % msg)
	if fails.is_empty():
		print("PASS - every baked clip plays back on the rig.")
	else:
		print("FAIL - %d baked clip(s) do not play." % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## The beat timeline sidecar, one JSON per clip, diffed by tools/diff_bake.gd alongside the curves.
static func _save_events(events: Array, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[BAKE] could not write %s" % path)
		return
	f.store_string(JSON.stringify(events, "  "))
	f.close()


## THE HALF THAT LEAVES THE ENGINE. A scene holding the rig and one AnimationPlayer, handed to
## GLTFDocument. Built fresh rather than exporting the live ogre, because the live one carries the
## solver, six modifiers, a mace, hitboxes and a blob shadow, none of which an animator wants and
## some of which do not survive the trip.
func _export_glb(sv: OgreSolver, skel: Skeleton3D, anim: Animation,
		which: String, out: String) -> void:
	var root := Node3D.new()
	root.name = "OgreBake"
	# The rig itself. duplicate() so the exporter cannot disturb the running scene -- the ogre is
	# still standing in the lab while this happens.
	var rig := skel.duplicate(DUPLICATE_USE_INSTANTIATION) as Skeleton3D
	rig.name = "GeneralSkeleton"
	# The duplicate carries the lab's passengers — the six SkeletonModifier3D layers (exported as
	# empties named ArmIk, ClipLayer, ...) and the bone-viz spheres. None of them are the
	# animator's business; keep the skinned body and drop the rest.
	for c in rig.get_children().duplicate():
		var drop := c is SkeletonModifier3D or c is BoneAttachment3D 				or (c is MeshInstance3D and (c as MeshInstance3D).skin == null)
		if drop:
			rig.remove_child(c)
			c.free()
	root.add_child(rig)
	rig.owner = root
	for c in rig.get_children():
		_own(c, root)
	# THE MACE, as an animated reference node with the real mesh under it. Without it a two-handed
	# swing is unreadable in Blender -- the whole motion is organised around a thing that was not
	# in the file. Reference only: at runtime the weapon is aimed live and these tracks are inert.
	var mace_node := Node3D.new()
	mace_node.name = "Mace"
	root.add_child(mace_node)
	mace_node.owner = root
	if sv.weapon_scene:
		var w := sv.weapon_scene.instantiate() as Node3D
		if w:
			_strip_to_visuals(w)
			mace_node.add_child(w)
			_own(w, root)
	# ONE animation per file, deliberately. The rest stance used to ride along as a second
	# animation in every file -- and Blender made IT the active action, so the animator opened a
	# 2.2 s slam and watched 0.65 s of breathing, reported as "the glb only plays a fraction".
	# The rest stance is its own file now: ogre_carry_reference_baked.glb.
	var lib := AnimationLibrary.new()
	lib.add_animation(StringName(which), anim)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.owner = root
	ap.add_animation_library(&"", lib)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err != OK:
		print("[BAKE] glTF append failed: %d" % err)
		root.queue_free()
		return
	# The .glb files live in a .gdignore'd subfolder: they are for Blender, which reads them off
	# the filesystem — inside res:// the editor would otherwise import all eleven as scenes.
	var glb_dir := "%s/glb" % out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(glb_dir))
	if not FileAccess.file_exists(glb_dir + "/.gdignore"):
		var gi := FileAccess.open(glb_dir + "/.gdignore", FileAccess.WRITE)
		if gi:
			gi.close()
	var glb_path := "%s/ogre_%s_baked.glb" % [glb_dir, which]
	err = doc.write_to_filesystem(state, glb_path)
	print("[BAKE] glTF %s -> %s" % ["written" if err == OK else "FAILED %d" % err, glb_path])
	root.queue_free()


## Keep only what an animator can see: scripts dropped, physics pruned. The mace scene ships a
## HitBox and collision shapes that neither Blender nor glTF wants.
static func _strip_to_visuals(n: Node) -> void:
	n.set_script(null)
	for c in n.get_children().duplicate():
		if c is CollisionObject3D or c is CollisionShape3D or c is CollisionPolygon3D:
			n.remove_child(c)
			c.free()
		else:
			_strip_to_visuals(c)


## The beat timeline, humanly readable, next to the .glb it describes. glTF cannot carry markers,
## and an animator should not have to open a JSON to learn where the strike lands.
static func _save_beats_txt(events: Array, length: float, which: String, path: String) -> void:
	# This runs BEFORE the glb export creates the folder; FileAccess fails silently on a missing
	# dir, which is how the first beats file quietly did not exist.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("%s — %.2f s. A refined clip must KEEP this length: the damage timings" % [which, length])
	f.store_line("and beats below do not stretch with the curves. First and last frame must sit")
	f.store_line("on the carry stance (see ogre_carry_reference_baked.glb in this folder).")
	f.store_line("Blender setup: Scene fps 60; set the timeline end to %.0f." % (length * 60.0))
	f.store_line("")
	var rows := [[0.0, "start (carry stance)"]]
	for e in events:
		# A beat can be stamped a frame past the last sampled key (it fires inside the tick that
		# ends the action); clamp the display so "recover" does not print after "end".
		rows.append([minf(float(e.get("t", 0.0)), length), String(e.get("beat", "?"))])
	rows.append([length, "end (back at carry stance)"])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	for r in rows:
		f.store_line("  %.3f  %s" % [r[0], r[1]])
	f.close()


## The authoring contract, once per bake, where the animator will actually look.
static func _save_glb_readme(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("""OGRE BAKED CLIPS — what these files are and how to refine one

Each action .glb holds the rig, the mace (an animated reference node), and ONE animation:
the recorded motion, on the game's own clock, complete from rest to rest.
ogre_carry_reference_baked.glb is the rest stance by itself — the pose every clip must
start and end on.

BLENDER SETUP (or the timeline will look wrong): the clips are keyed at 60 fps and Blender
defaults to 24 fps with a 250-frame range. Set Scene fps to 60 BEFORE importing — the
importer maps seconds onto frames with the fps of that moment, so importing at 24 squeezes
an 83-frame clip onto 33 frames and no later fps change unsqueezes it. Then set the
timeline end to the frame count in the clip's .beats.txt. If the viewport plays the wrong
thing, pick the action in the Dope Sheet's Action Editor.

WHAT THE GAME USES from a refined clip: the upper body only — Hips rotation, spine, chest,
neck, head, shoulders, arms, hands. Everything else in these files is REFERENCE:
  - legs, feet and pelvis HEIGHT are solved live (foot planting, ground, crouch);
  - the mace is aimed live at the target (keep the hands near the reference shaft and the
    game's grip solve does the rest).

THE THREE RULES:
  1. First and last frame stay on the carry stance (match carry_reference). There is no
     runtime crossfade to hide a mismatch — the clip snaps on and off there.
  2. Keep the clip length. Beat times (see the .beats.txt next to each file) are the damage
     windows and telegraphs; they do not stretch with your curves.
  3. Interruptions (stagger, abandon) cut a clip mid-flight by design. Do not author for
     them.

THE ROUND TRIP: edit in Blender -> export -> import in Godot -> save the animation as
<action>.res -> drop it at assets/models/animations/ogre_clips/<action>.res -> run
tools/build_ogre_clips.gd. No code. Then run the four gates (docs/combat-refactor.md,
"The four gates").
""")
	f.close()


static func _own(n: Node, root: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_own(c, root)


## Record a scripted demo instead of waiting for a keyboard:
##
##   Godot_console.exe --path . --resolution 1280x800 ##       res://scenes/dev/enemy_procedural_animation_test.tscn -- --demo=slam --out=C:/folder
##
## WHY THE LAB AND NOT A TOOL SCRIPT. The `--script` harness that runs every other probe here does
## not register autoloads, and the moment an action spawns something real -- the AreaAttack disc, a
## thrown rock -- it pulls in project files that reference `EventBus` at COMPILE time and the load
## fails. Those files are perfectly correct in the game; the harness is the thing that is unusual.
## A scene runs the way the game runs, so anything that photographs gameplay has to be one.
func _demo(what: String, out: String) -> void:
	await get_tree().create_timer(0.6).timeout
	_ogre.target = null
	if what == "bake":
		await _demo_bake(out)
		return
	if what == "bakecheck":
		await _demo_bakecheck(out)
		return
	if what == "orbit":
		await _demo_orbit(out)
		return
	if what == "viewclip":
		await _demo_viewclip(out)
		return
	if what == "reach":
		await _demo_reach(out)
		return
	if what == "zones":
		# THE ZONE TABLE. A grid of distances and bearings, each answered with the zone it falls in
		# and the attack the ogre would choose there. This is the gameplay layer printed as text: no
		# rig, no clip, no frame -- just the geometry answering the only question the behaviour ever
		# asks it, which is "can I hit something standing there".
		var sv := _ogre.solver
		await get_tree().physics_frame
		# One swing first, so the hinge is the measured one rather than the authored fallback. The
		# zone is deliberately allowed to differ before the creature has ever swung, and a table
		# printed in that state would be describing a transient.
		sv.play_action(&"slam")
		for _i in 200:
			await get_tree().physics_frame
			if not sv.is_acting():
				break
		var sz: Vector2 = sv.strike_zone()
		var kz: Vector2 = sv.kick_zone()
		print("[ZONES] strike %.2f..%.2f m, wedge +/-%.0f deg | kick %.2f..%.2f m | advance to %.1f m"
				% [sz.x, sz.y, sv.tuning.strike_yaw, kz.x, kz.y, sv.tuning.advance_max])
		print("[ZONES] %-6s %-6s  %-8s  %s" % ["dist", "bear", "zone", "attack"])
		var names := ["STRIKE", "TURN", "REPOSITION", "WRONG"]
		for d in [0.4, 0.9, 1.5, 2.2, 3.0, 5.0, 9.0]:
			for bear in [0.0, 40.0, 80.0, 140.0]:
				var at: Vector3 = sv.global_position 						+ sv.forward().rotated(Vector3.UP, deg_to_rad(bear)) * d
				# The chooser moved to the AI (Enemy.choose_attack); the bench has no AI, so it asks
				# the geometry directly and shows the first reaching attack -- deterministic, which
				# suits a table better than a roll anyway.
				var fits: Array[StringName] = sv.actions_reaching(d)
				var pick: StringName = fits[0] if not fits.is_empty() else &""
				# ASKED ABOUT THE ATTACK IT COULD ACTUALLY THROW. Asking in the abstract answers
				# about the swing, which says ADVANCE for everything a kick would have handled.
				var about: ActionSpec = sv.spec(pick) if pick != &"" else null
				print("[ZONES] %-6.2f %-6.0f  %-8s  %s"
						% [d, bear, names[sv.zone_of(at, about)], pick if pick != &"" else "-"])
		get_tree().quit()
		return
	if what == "drop":
		# TAKE THE GRIPS AWAY AND SEE WHAT THE MACE DOES. Setting the IK's amount to zero is exactly
		# the state a grip failure produces -- hands no longer reaching for the haft -- so this is
		# the real path, not a special case wired in for the test.
		var sv := _ogre.solver
		var cam := Camera3D.new()
		cam.fov = 44.0
		add_child(cam)
		cam.global_position = _ogre.global_position + Vector3(7.0, 3.4, 7.0)
		cam.look_at(_ogre.global_position + Vector3.UP * 1.6)
		cam.current = true
		var fell := {"at": Vector3.ZERO, "yes": false}
		sv.weapon_dropped.connect(func(at: Vector3) -> void:
			fell["at"] = at
			fell["yes"] = true)
		for _w in 60:
			await get_tree().physics_frame
		# The mace can only be DROPPED while it leads -- carried, it is welded to the anchor palm and
		# there is nothing to lose hold of. So this drops it mid-swing, which is the real case.
		sv.play_action(&"slam")
		for _w in 30:
			await get_tree().physics_frame
		print("[DROP] letting go mid-swing...")
		sv.arm_ik.amount = 0.0
		var rb: Node3D = null
		for i in 260:
			await get_tree().physics_frame
			if rb == null:
				rb = get_tree().current_scene.get_node_or_null("DroppedMace")
			if i in [20, 60, 120, 250]:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/drop_%03d.png" % [out, i])
		if not fell["yes"]:
			print("[DROP] *** the mace was never dropped ***")
		else:
			print("[DROP] dropped at %s" % str(fell["at"].snappedf(0.01)))
			if rb:
				print("[DROP] it is a %s, now resting at y %.2f (floor is y %.2f), sleeping %s"
						% [rb.get_class(), rb.global_position.y, _ogre.global_position.y,
						str((rb as RigidBody3D).sleeping)])
			else:
				print("[DROP] *** no DroppedMace body in the scene ***")
		get_tree().quit()
		return

	if what == "arc":
		# THE PATH THE MACE HEAD ACTUALLY TRAVELS, in the ogre's own frame: forward and up. A wide
		# sweep and a narrow chop are the same start and the same end; only the shape between them
		# differs, so the shape is what has to be looked at.
		var sv := _ogre.solver
		for _w in 20:
			await get_tree().physics_frame
		sv.play_action(&"slam")
		var pts := PackedVector2Array()
		var butt := PackedVector2Array()
		var tt := PackedFloat32Array()
		while sv.is_acting():
			await get_tree().physics_frame
			var g := sv.grip_node()
			if g == null:
				continue
			var dir: Vector3 = g.global_basis.y.normalized()
			var hd: Vector3 = g.global_position + dir * sv.weapon_length
			var rel: Vector3 = hd - sv.global_position
			pts.append(Vector2(rel.dot(sv.forward()), rel.y))
			# The BUTT's path too, because the complaint is that it has none.
			var bt: Vector3 = g.global_position - sv.global_position
			butt.append(Vector2(bt.dot(sv.forward()), bt.y))
			tt.append(sv.swing_angle)
		# Printed as a coarse plot, because a column of numbers does not have a shape.
		var lo_f := 999.0
		var hi_f := -999.0
		var hi_y := -999.0
		for v in pts:
			lo_f = minf(lo_f, v.x); hi_f = maxf(hi_f, v.x); hi_y = maxf(hi_y, v.y)
		for v in butt:
			lo_f = minf(lo_f, v.x); hi_f = maxf(hi_f, v.x); hi_y = maxf(hi_y, v.y)
		var hi_t := -999.0
		var lo_t := 999.0
		for v in tt:
			hi_t = maxf(hi_t, v)
			lo_t = minf(lo_t, v)
		print("[ARC] %d samples | # = mace HEAD, o = mace BUTT | forward %.1f .. %.1f | peak %.1f m"
				% [pts.size(), lo_f, hi_f, hi_y])
		# HEIGHT AGAINST TIME, which is the curve the timing is actually judged on -- the arc plot
		# below says where the mace goes, this says when.
		print("[TIME] SWING ANGLE over the action -- prepare, raise, aim, smash")
		var n := tt.size()
		for r in 14:
			var y_hi: float = lerpf(hi_t, lo_t, float(r) / 14.0)
			var y_lo: float = lerpf(hi_t, lo_t, float(r + 1) / 14.0)
			var line := ""
			for c in 60:
				var hit := false
				for k in n:
					if int(float(k) * 60.0 / float(n)) == c and tt[k] <= y_hi and tt[k] > y_lo:
						hit = true
						break
				line += "#" if hit else "."
			print("[TIME] %5.1f |%s" % [y_hi, line])
		print("[TIME]       +%s>  t" % "-".repeat(58))

		var rows := 18
		var cols := 46
		for r in rows:
			var y_hi: float = hi_y * (1.0 - float(r) / float(rows))
			var y_lo: float = hi_y * (1.0 - float(r + 1) / float(rows))
			var line := ""
			for c in cols:
				var f_lo: float = lo_f + (hi_f - lo_f) * float(c) / float(cols)
				var f_hi: float = lo_f + (hi_f - lo_f) * float(c + 1) / float(cols)
				var ch := "."
				for v in butt:
					if v.x >= f_lo and v.x < f_hi and v.y >= y_lo and v.y < y_hi:
						ch = "o"
						break
				for v in pts:
					if v.x >= f_lo and v.x < f_hi and v.y >= y_lo and v.y < y_hi:
						ch = "#"
						break
				line += ch
			print("[ARC] %5.1f |%s" % [y_hi, line])
		print("[ARC]       +%s" % "-".repeat(cols / 2))
		print("[ARC]        back %.1f  ...  front %.1f  (the ogre stands at forward 0)" % [lo_f, hi_f])
		get_tree().quit()
		return

	if what == "carrysweep":
		# THE YIELD BUDGET, SWEPT WHILE ACTUALLY WALKING. The earlier version of this swept a
		# stationary ogre, which is how a budget one twenty-fifth of a degree too small looked fine.
		var sv := _ogre.solver
		_ogre.commanded_speed = 2.0
		demo_driving = true
		print("[CARRY] budget | grip lost | palm snap | elbow snap | shaft clear")
		for cap in [8.0, 12.0, 16.0, 20.0, 26.0]:
			sv.tuning.grip_yield = cap
			for _w in 60:
				await get_tree().physics_frame
			var lost := 0
			var snap := 0.0
			var elb := 0.0
			var clear := 99.0
			var pl := Vector3.ZERO
			var pe := Vector3.ZERO
			for i in 240:
				await get_tree().physics_frame
				demo_drive = Vector3(sin(float(i) * 0.02), 0.0, -1.0).normalized()
				var dt: float = maxf(get_physics_process_delta_time(), 0.001)
				var lp: Vector3 = sv.arm_ik.palm_position(0)
				var ep: Vector3 = sv.arm_ik.bone_positions()[sv.bone("LeftLowerArm")]
				if pl != Vector3.ZERO:
					snap = maxf(snap, pl.distance_to(lp) / dt)
					elb = maxf(elb, pe.distance_to(ep) / dt)
				pl = lp
				pe = ep
				if sv.arm_ik.grip_strength(0) < 0.5:
					lost += 1
				clear = minf(clear, -_shaft_penetration())
			print("[CARRY]  %4.0f deg |  %3d/240  |  %5.1f m/s |  %5.1f m/s |  %.2f m"
					% [cap, lost, snap, elb, clear])
		print("[CARRY] (walking the whole time; grip lost and the two snaps should all go to zero)")
		get_tree().quit()
		return

	if what == "glue":
		# IS THE MACE GLUED TO THE HAND WHILE CARRYING? Walk the ogre about, never attack, and watch
		# the distance between the mace's grip point and the palm it is supposed to be sitting on.
		var sv := _ogre.solver
		var travelled := _ogre.global_position
		var worst := 0.0
		var worst_l := 0.0
		var shoulder_d := 0.0
		var yd := 0.0
		var ys := 0.0
		var gs := 0.0
		var snap := 0.0
		var lost := 0
		var prev_lp := Vector3.ZERO
		var dbg := {}
		var prev_el := [Vector3.ZERO, Vector3.ZERO]
		var elbow := [0.0, 0.0]
		_ogre.commanded_speed = 2.0
		demo_driving = true
		for i in 420:
			await get_tree().physics_frame
			# Turn while walking, because the weapon's aim is built from `facing` and a turn is
			# where a placement that only looks right standing still comes apart.
			demo_drive = Vector3(sin(float(i) * 0.02), 0.0, -1.0).normalized()
			if i > 60:
				# SNAPPING, as a number. A grip that keeps being made and lost shows up as the palm
				# jumping between frames -- toward the haft and back to wherever the pose puts it,
				# which on this rig is up by the face.
				var lp: Vector3 = sv.arm_ik.palm_position(0)
				if prev_lp != Vector3.ZERO:
					snap = maxf(snap, prev_lp.distance_to(lp) / maxf(get_physics_process_delta_time(), 0.001))
				prev_lp = lp
				if sv.arm_ik.grip_strength(0) < 0.5:
					lost += 1
				# THE ELBOWS, frame to frame. A snap is a joint moving metres per second on a body
				# that is walking at two; a harmonic swing is smooth and slow.
				for e in 2:
					var eb: int = sv.bone("LeftLowerArm" if e == 0 else "RightLowerArm")
					var ep: Vector3 = sv.arm_ik.bone_positions()[eb]
					if prev_el[e] != Vector3.ZERO:
						var v: float = prev_el[e].distance_to(ep) / maxf(get_physics_process_delta_time(), 0.001)
						if v > elbow[e]:
							elbow[e] = v
					prev_el[e] = ep
				worst = maxf(worst, sv.arm_ik.palm_position(1).distance_to(sv.grip_world()))
				var e: float = sv.arm_ik.palm_position(0).distance_to(sv.off_grip_world())
				if e > worst_l:
					worst_l = e
					var sh: int = sv.bone("LeftUpperArm")
					shoulder_d = sv.off_grip_world().distance_to(sv.arm_ik.bone_positions()[sh])
					yd = sv.yield_degrees
					ys = sv.yield_short
					gs = sv.arm_ik.grip_strength(0)
					dbg = sv.yield_dbg.duplicate()
					dbg["actual"] = e
					dbg["shoulder_now"] = sv.arm_ik.bone_positions()[sv.bone("LeftUpperArm")]
		print("[GLUE] carrying, walking and turning | RIGHT palm off its point %.4f m | LEFT %.4f m"
				% [worst, worst_l])
		print("[GLUE] at the worst LEFT frame: grip sat %.2f m from the left upper arm (arm %.2f, need <%.2f)"
				% [shoulder_d, sv.arm_ik.arm_reach(), sv.arm_ik.arm_reach() * sv.tuning.grip_reach])
		print("[GLUE]   weapon yielded %.1f deg, %.1f deg SHORT of what was asked | grip strength %.2f"
				% [yd, ys, gs])
		# A close-up on the hand, the same view the complaint came in on.
		_ogre.commanded_speed = 0.0
		demo_drive = Vector3.ZERO
		for _w in 40:
			await get_tree().physics_frame
		print("[GLUE] left hand: lost its grip on %d of 360 frames | fastest palm move %.1f m/s"
				% [lost, snap])
		print("[GLUE] the ogre travelled %.1f m during the test (if ~0 it never walked and the"
				% travelled.distance_to(_ogre.global_position))
		print("[GLUE]   smoothness numbers below mean nothing)")
		print("[GLUE] fastest ELBOW move while walking: left %.1f m/s  right %.1f m/s"
				% [elbow[0], elbow[1]])
		if not dbg.is_empty():
			print("[GLUE] cone at that frame: r %.2f  L %.2f  d %.2f  cos_max %+.3f  have %+.3f"
					% [dbg["r"], dbg["L"], dbg["d"], dbg["cos_max"], dbg["have"]])
			print("[GLUE]   cone PREDICTS the grip is %.2f m from the arm; it MEASURED %.2f m"
					% [dbg["predicted"], dbg["actual"]])
			print("[GLUE]   arm the cone used %s | arm now %s | moved %.2f m"
					% [str((dbg["shoulder"] as Vector3).snappedf(0.01)),
					str((dbg["shoulder_now"] as Vector3).snappedf(0.01)),
					(dbg["shoulder"] as Vector3).distance_to(dbg["shoulder_now"])])
		print("[GLUE] shaft to trunk while carrying: %.2f m clear" % -_shaft_penetration())
		var cam := Camera3D.new()
		add_child(cam)
		cam.current = true
		# The hand, and then the whole creature from the front three-quarter -- the angle the "it is
		# hugging the mace" complaint came in on, which a close-up on the fist cannot show.
		var hand := sv.arm_ik.palm_position(1)
		cam.fov = 26.0
		cam.global_position = hand + Vector3(1.9, 0.9, 1.9)
		cam.look_at(hand)
		for _w in 6:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/glue_closeup.png" % out)
		cam.fov = 46.0
		cam.global_position = _ogre.global_position + Vector3(3.6, 3.0, 5.4)
		cam.look_at(_ogre.global_position + Vector3.UP * 2.0)
		for _w in 6:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/glue_carry.png" % out)
		print("[GLUE] wrote the close-up")
		get_tree().quit()
		return

	if what == "gripspread":
		# HOW FAR APART CAN THE HANDS ACTUALLY BE? The right hand grips at 1/8 and holds; the left is
		# asked for 4/8 and cannot get there. This sweeps the left point down the haft and reports
		# how close each arm gets, so the answer is a number rather than an argument.
		var sv := _ogre.solver
		print("[SPREAD] left grip | spread | worst R error | worst L error   (arm reach %.2f m)"
				% sv.arm_ik.arm_reach())
		for frac in [0.5, 0.4, 0.35, 0.3, 0.25, 0.2]:
			sv.tuning.grip_left = frac
			sv.cancel_action()
			for _w in 25:
				await get_tree().physics_frame
			sv.play_action(&"slam")
			var wr := 0.0
			var wl := 0.0
			while sv.is_acting():
				await get_tree().physics_frame
				if sv.action_t > 0.35:      # past the handover, while the swing is committed
					wr = maxf(wr, sv.arm_ik.palm_position(1).distance_to(sv.grip_world()))
					wl = maxf(wl, sv.arm_ik.palm_position(0).distance_to(sv.off_grip_world()))
			print("[SPREAD]   %.3f  |  %.2f m |     %.2f m     |     %.2f m"
					% [frac, sv.weapon_length * (frac - sv.tuning.grip_right), wr, wl])
		get_tree().quit()
		return

	if what == "trace":
		# EVERY PHYSICS FRAME, not twelve samples. The complaint is that the attack starts to the
		# ogre's left and then switches to its right -- a discontinuity in TIME, which a contact
		# sheet cannot show however many frames it has, because the artefact lives between them.
		#
		# lat is the mace head's sideways offset in the ogre's OWN frame: negative left, positive
		# right. A sign change is the flip, and whatever else changes sign on the same frame is the
		# cause.
		var sv := _ogre.solver
		var skel := sv.skeleton()
		var ih := skel.find_bone("Hips")
		# Bisect the stack: whichever layer's removal makes the jump vanish is the one causing it.
		for a2 in OS.get_cmdline_user_args():
			if a2 == "--nodyn":
				sv.dynamics.active = false
			elif a2 == "--nopose":
				sv.pose_layer.active = false
			elif a2 == "--nogait":
				sv.gait_layer.active = false
			elif a2 == "--yaw0":
				sv.tuning.clip_yaw = 0.0
		sv.play_action(&"slam")
		var out_lines := PackedStringArray()
		var prev_lat := 0.0
		var prev_hand := Vector3.ZERO
		var prev_hips := Quaternion.IDENTITY
		var prev_dir := Vector3.ZERO
		var flips := 0
		var i := 0
		while sv.is_acting():
			await get_tree().physics_frame
			var g := sv.grip_node()
			if g == null:
				continue
			var dir := g.global_basis.y.normalized()
			var head := g.global_position + dir * sv.weapon_length
			var rel := head - sv.global_position
			var lat := rel.dot(sv.right())
			var fwd := rel.dot(sv.forward())
			# Where the PELVIS is pointing, against where the body says it faces. If the clip's yaw
			# correction is being blended the long way round, this is where it shows.
			var hips_fwd := -sv.arm_ik.bone_basis(ih).z
			hips_fwd.y = 0.0
			var hy := 0.0
			if hips_fwd.length_squared() > 0.0001:
				hy = rad_to_deg(hips_fwd.normalized().signed_angle_to(sv.forward(), Vector3.UP))
			# ISOLATE THE CULPRIT. If the HAND's own axis jumps as much as the aim does, the
			# skeleton is flipping and the weapon is faithfully following it. If the hand is smooth
			# and only the aim jumps, the fault is in _aim_weapon.
			# The PELVIS's own LOCAL rotation, frame to frame. The hand's world orientation is the
			# product of every bone above it, so a jump there says nothing about where it started.
			var hips_q := skel.get_bone_pose_rotation(ih)
			var hips_jump := 0.0 if prev_hips == Quaternion.IDENTITY else rad_to_deg(prev_hips.angle_to(hips_q))
			prev_hips = hips_q
			var hand_y := sv.arm_ik.bone_basis(sv.bone(sv.weapon_bone)).y.normalized()
			var hand_jump := 0.0 if prev_hand == Vector3.ZERO else rad_to_deg(prev_hand.angle_to(hand_y))
			var aim_jump := 0.0 if prev_dir == Vector3.ZERO else rad_to_deg(prev_dir.angle_to(dir))
			prev_hand = hand_y
			prev_dir = dir
			var flip := i > 2 and signf(lat) != signf(prev_lat) and absf(lat - prev_lat) > 0.8
			if flip:
				flips += 1
			# WHICH WAY IS THE BODY ACTUALLY FACING? Taken from the shoulder line, which is a real
			# anatomical direction rather than a bone axis convention: right shoulder minus left is
			# the creature's own +right, and forward follows from it.
			#
			# This is the question the whole yaw correction turns on. If the clip's swing was made
			# to travel forward by spinning the ogre through 180 degrees, then it is not fixed at
			# all -- it is attacking with its back turned, and the arithmetic only looked right.
			var ls := sv.arm_ik.bone_positions()[skel.find_bone("LeftShoulder")]
			var rs := sv.arm_ik.bone_positions()[skel.find_bone("RightShoulder")]
			var body_r := (rs - ls)
			body_r.y = 0.0
			var facing_dot := 0.0
			if body_r.length_squared() > 0.0001:
				facing_dot = (-body_r.normalized().cross(Vector3.UP)).dot(sv.forward())
			if i % 12 == 0:
				out_lines.append("[FACE] t=%.2f  body faces %s (dot %+.2f)  clipT %.2f"
						% [sv.action_t, "FORWARD" if facing_dot > 0.0 else "BACKWARD >>>",
						facing_dot, sv.clip_layer.time])
			if aim_jump > 40.0 or hand_jump > 40.0 or hips_jump > 40.0:
				out_lines.append("[TRACE] t=%.3f  AIM %5.1f | HAND %5.1f | HIPS-LOCAL %5.1f deg | share %.2f | clipT %.3f"
						% [sv.action_t, aim_jump, hand_jump, hips_jump,
						sv.clip_layer.clip_share("RightHand"), sv.clip_layer.time])
			prev_lat = lat
			i += 1
		for l in out_lines:
			print(l)
		print("[TRACE] %d frames, %d sudden side flips" % [i, flips])
		get_tree().quit()
		return

	if what == "whole":
		# THE ENTIRE ACTION, from the angle the complaint came from -- front and above, looking down
		# on a hunched ogre. Every frame I had rendered until now was a side elevation across the
		# swing window, which is the right view for judging an ARC and the wrong one for judging
		# whether a pose makes any sense as a body. The frames after the strike were never in shot.
		var sv := _ogre.solver
		var cam := Camera3D.new()
		cam.fov = 44.0
		add_child(cam)
		cam.global_position = _ogre.global_position + Vector3(2.6, 6.4, -7.0)
		cam.look_at(_ogre.global_position + Vector3.UP * 1.7)
		cam.current = true
		_show_bones = false
		# Let the carry pose settle so the grip points get measured off it before an action starts.
		for _w in 20:
			await get_tree().physics_frame
		sv.play_action(&"slam")
		var total: float = sv.action_len
		var n := 12
		for i in n:
			var want := total * float(i) / float(n - 1) * 0.99
			while sv.is_acting() and sv.action_t < want:
				await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/whole_%02d.png" % [out, i])
			var pen := _shaft_penetration()
			# DOES THE HEAD ACTUALLY REACH THE FLOOR, and does it land inside its own telegraph?
			var g3 := sv.grip_node()
			var head_y := 0.0
			var head_f := 0.0
			if g3:
				var hd: Vector3 = g3.global_position + g3.global_basis.y.normalized() * sv.weapon_length
				head_y = hd.y - sv.global_position.y
				head_f = (hd - sv.global_position).dot(sv.forward())
			var pts4 := sv.arm_ik.bone_positions()
			var er := 0.0
			var el := 0.0
			var ir4 := sv.bone("RightHand")
			var il4 := sv.bone("LeftHand")
			if ir4 >= 0 and ir4 < pts4.size():
				er = sv.arm_ik.palm_position(1).distance_to(sv.grip_world())
			if il4 >= 0 and il4 < pts4.size():
				el = sv.arm_ik.palm_position(0).distance_to(sv.off_grip_world())
			# WHERE THE BUTT IS. The end below the hand is exempt from the shaft clearance test, so
			# nothing has been watching it -- and it is the end that ends up in the ogre's stomach.
			var butt_d := 0.0
			if g3:
				var bp: Vector3 = g3.global_position
				var ax0: Vector3 = sv.global_position + Vector3.UP * sv.tuning.weapon_clear_low
				var ax1: Vector3 = sv.global_position + Vector3.UP * sv.tuning.weapon_clear_high
				butt_d = _seg_seg(bp, bp, ax0, ax1) - sv.tuning.weapon_clear_radius
			print("[WHOLE] frame %02d  t=%.2f  head y %+5.2f fwd %+5.2f | butt %+5.2f | PALM R %.2f L %.2f | shaft %s"
					% [i, sv.action_t, head_y, head_f, butt_d, er, el,
					("INSIDE %.2f" % pen) if pen > 0.001 else ("clear %.2f" % -pen)])
		print("[WHOLE] done")
		get_tree().quit()
		return

	if what == "gripfit":
		# WHICH WAY DOES A WEAPON LIE IN THIS HAND? Measured, not assumed.
		#
		# The shaft currently follows the forearm, and mid-swing that points it straight down through
		# the ogre's own legs while the hand is overhead. A clip's hand rotation is authored around
		# whatever axis the animator's weapon lay along -- for a Mixamo melee clip, a sword -- and
		# guessing which of the hand's axes that was is how you get a 4 m mace sweeping through a
		# torso. So every candidate axis is scored against what a slam has to do:
		#
		#   land  the head must reach the floor at the contact frame, out in FRONT
		#   clear the shaft must stay outside the body for the whole swing
		#
		# One pass over the clip serves every candidate, because all any of them needs is the hand's
		# position and orientation per frame.
		var sv := _ogre.solver
		for a3 in OS.get_cmdline_user_args():
			if a3 == "--yaw0":
				sv.tuning.clip_yaw = 0.0
		sv.pose_layer.active = false
		sv.gait_layer.active = false
		sv.dynamics.active = false
		sv.foot_ik.active = false
		sv.arm_ik.amount = 0.0
		sv.clip_layer.raw = true
		sv.clip_layer.clip = sv.attack_clip
		sv.clip_layer.weight = 1.0
		sv.posing = true
		var rh := sv.skeleton().find_bone(sv.weapon_bone)
		var reach := 3.4                     # hand to mace head, metres
		var cands := [
			["+X", Vector3.RIGHT], ["-X", Vector3.LEFT],
			["+Y", Vector3.UP], ["-Y", Vector3.DOWN],
			["+Z", Vector3.BACK], ["-Z", Vector3.FORWARD],
			["forearm", sv._haft_dir], ["-forearm", -sv._haft_dir],
		]
		var score := {}
		for c in cands:
			score[c[0]] = {"clear": 999.0, "y": 0.0, "fwd": 0.0, "up": 0.0}
		var contact := 1.133
		var n := 40
		for i in n + 1:
			var t := 0.30 + (1.70 - 0.30) * float(i) / float(n)
			sv.clip_layer.time = t
			await get_tree().physics_frame
			await get_tree().physics_frame
			var hand: Vector3 = sv.arm_ik.bone_positions()[rh]
			var hb: Basis = sv.arm_ik.bone_basis(rh).orthonormalized()
			for c in cands:
				var dir: Vector3 = (hb * (c[1] as Vector3)).normalized()
				var head := hand + dir * reach
				# Distance from the ogre's own vertical axis, only while the head is at body height.
				var d := Vector2(head.x - sv.global_position.x, head.z - sv.global_position.z).length()
				if head.y > 0.4 and head.y < 3.4:
					score[c[0]]["clear"] = minf(score[c[0]]["clear"], d)
				if absf(t - contact) < 0.02:
					score[c[0]]["y"] = head.y
					score[c[0]]["fwd"] = dir.dot(sv.forward())
					score[c[0]]["up"] = dir.y
		print("[GRIPFIT] axis      head_y@contact  fwd@contact  up@contact  min_clearance")
		for c in cands:
			var v: Dictionary = score[c[0]]
			print("[GRIPFIT] %-9s  %+8.2f       %+6.2f      %+6.2f      %6.2f"
					% [c[0], v["y"], v["fwd"], v["up"], v["clear"]])
		print("[GRIPFIT] want: head_y near 0, fwd positive (lands in front), up negative, clearance > 0.9")
		get_tree().quit()
		return

	if what == "pureclip" or what == "blended":
		# THE IMPORTED ANIMATION, ALONE -- and the same swing with the solver on, at matching
		# granularity, so the two can be compared frame for frame.
		#
		# This is the only way to tell a bad RETARGET from a bad BLEND. If the clip is broken on its
		# own then no amount of mixing rescues it and the fault is in the import; if it is clean
		# alone and wrong when blended, the fault is ours. Guessing which without looking is how you
		# spend a day tuning weights against a broken source.
		var sv := _ogre.solver
		var raw := what == "pureclip"
		var cam := Camera3D.new()
		cam.fov = 40.0
		add_child(cam)
		# SIDE ON. The ogre faces -Z, so the camera goes out on +X and the whole swing happens in
		# the plane of the screen. A three-quarter view hides exactly the thing being judged: how
		# far the mace travels and whether it reaches the floor.
		cam.global_position = _ogre.global_position + Vector3(13.0, 3.2, 0.0)
		cam.look_at(_ogre.global_position + Vector3.UP * 2.0)
		cam.current = true
		_show_bones = true

		if raw:
			# Every procedural layer off. arm_ik STAYS ACTIVE with amount 0 -- it solves nothing but
			# it is the thing that snapshots bone positions, and the weapon is placed from that
			# snapshot. Switched off entirely, the mace hangs off a hand position from before the
			# clip started.
			sv.pose_layer.active = false
			sv.gait_layer.active = false
			sv.dynamics.active = false
			sv.foot_ik.active = false
			sv.arm_ik.amount = 0.0
			sv.clip_layer.raw = true
			sv.clip_layer.clip = sv.attack_clip
			sv.clip_layer.weight = 1.0
			sv.posing = true

		var lo := 0.25
		var hi := 1.70
		var n := 12
		for i in n:
			var ct := lo + (hi - lo) * float(i) / float(n - 1)
			if raw:
				sv.clip_layer.time = ct
				await get_tree().physics_frame
				await get_tree().physics_frame
			else:
				# Drive the real action to the SAME clip time, so frame i of one set is frame i of
				# the other.
				if not sv.is_acting():
					sv.play_action(&"slam")
				var want: float = sv.action_time(&"slam", &"strike") 						+ (ct - 1.133) / maxf(sv.spec(&"slam").clip_speed, 0.01)
				while sv.is_acting() and sv.action_t < want:
					await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					"%s/%s_%02d.png" % [out, what, i])
			var pen := _shaft_penetration()
			# WHERE along the shaft the deepest point is, measured from the BUTT in metres. Under
			# 0.65 means it is the stub behind the hand fouling the body -- which a grip slide would
			# fix outright -- and beyond that it is the working length, which would not.
			var sv2: OgreSolver = _ogre.solver
			var g2 := sv2.grip_node()
			var along := 0.0
			if g2:
				var dir2 := g2.global_basis.y.normalized()
				var best := 999.0
				for k in 81:
					var u := 4.0 * float(k) / 80.0
					var pt := g2.global_position + dir2 * u
					var ax := Vector3(sv2.global_position.x, clampf(pt.y, sv2.global_position.y + 0.5,
							sv2.global_position.y + 3.4), sv2.global_position.z)
					var dd := pt.distance_to(ax)
					if dd < best:
						best = dd
						along = u
			print("[%s] frame %02d  clip t=%.3f  shaft %-18s deepest %.2f m up the haft (hand at 0.65)"
					% [what.to_upper(), i, ct,
					("INSIDE by %.2f m" % pen) if pen > 0.0 else ("clear by %.2f m" % -pen), along])
		print("[%s] done" % what.to_upper())
		get_tree().quit()
		return

	if what == "mixsweep":
		# THE MIX, AS A PICTURE. The same instant of the same slam at three settings of mix_arms:
		# 0 is the imported animation, 1 is the solver's own posed swing, 0.5 is genuinely both.
		# A number cannot show this and a slider cannot be put in a commit message.
		var sv := _ogre.solver
		var cam := Camera3D.new()
		cam.fov = 42.0
		add_child(cam)
		cam.global_position = _ogre.global_position + Vector3(11.0, 4.2, 8.0)
		cam.look_at(_ogre.global_position + Vector3.UP * 2.0)
		cam.current = true
		for mix in [0.0, 0.5, 1.0]:
			sv.tuning.mix_arms = mix
			sv.tuning.mix_spine = mix
			sv.tuning.mix_weapon = 0.0
			sv.play_action(&"slam")
			var strike := sv.action_time(&"slam", &"strike")
			while sv.is_acting() and sv.action_t < strike:
				await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					"%s/demo_mix_%d.png" % [out, int(mix * 100)])
			print("[MIX] mix_arms=%.2f -> clip owns RightHand at %.2f"
					% [mix, sv.clip_layer.clip_share("RightHand")])
			sv.cancel_action()
			for i in 40:
				await get_tree().physics_frame
		get_tree().quit()
		return

	if what == "clipsweep":
		# WHERE IS THE CLIP'S OWN IMPACT? The action's `strike` beat is what opens the hitbox and
		# detonates the telegraph, so the clip has to be offset until its contact frame lands on it.
		# Guessing that offset put the mace beside the ogre's head on the frame the ground was
		# supposed to break, so it gets measured: step the clip frame by frame with everything else
		# frozen, and find where the weapon hand bottoms out. That is contact.
		var sv := _ogre.solver
		var clip: Animation = sv.attack_clip
		if clip == null:
			print("[CLIP] no attack_clip assigned — nothing to measure")
			get_tree().quit()
			return
		var skel := sv.skeleton()
		var rh := skel.find_bone("RightHand")
		var best := {"y": 9999.0, "t": 0.0}
		var n := 48
		for i in n + 1:
			var t := clip.length * float(i) / float(n)
			sv.clip_layer.clip = clip
			sv.clip_layer.time = t
			sv.clip_layer.weight = 1.0
			await get_tree().physics_frame
			await get_tree().physics_frame
			var hand: float = sv.arm_ik.bone_positions()[rh].y - sv.global_position.y
			var head: float = sv.haft_world(3.4).y - sv.global_position.y
			print("[CLIP] t=%.3f  hand y %+6.2f  head y %+6.2f | pelvis %s | L foot %s | R foot %s"
					% [t, hand, head, str(sv.clip_layer.hips_offset().snappedf(0.01)),
					str(sv.clip_layer.foot_offset(0).snappedf(0.01)),
					str(sv.clip_layer.foot_offset(1).snappedf(0.01))])
			if hand < best["y"]:
				best["y"] = hand
				best["t"] = t
		print("[CLIP] contact (hand lowest) at clip t=%.3f s of %.3f, hand y %+.2f"
				% [best["t"], clip.length, best["y"]])
		get_tree().quit()
		return

	if what == "grip2":
		# Two questions. Does the mace stay RIGID to the hand it hangs off while the ogre walks?
		# And does the Body anchor actually glue BOTH hands to the shaft?
		var sv := _ogre.solver
		_ogre.commanded_speed = 2.0
		demo_driving = true
		demo_drive = Vector3(0, 0, -1)
		for i in 90:
			await get_tree().physics_frame
		var skel := sv.skeleton()
		var rh := skel.find_bone("RightHand")
		var lo := 999.0
		var hi := -999.0
		for i in 300:
			await get_tree().physics_frame
			var hand: Vector3 = sv.arm_ik.bone_positions()[rh]
			var along := (hand - sv.grip_node().global_position).dot(
					sv.grip_node().global_basis.y.normalized())
			lo = minf(lo, along)
			hi = maxf(hi, along)
		print("[RIGID] hand sits %.4f..%.4f m along the shaft while walking (spread %.4f m)"
				% [lo, hi, hi - lo])

		# Now glue it: place the mace on the BODY and let both hands come to it.
		# Across the chest, butt toward the off shoulder, so BOTH hands are inside their reach.
		# Where the shaft is decides whether a hand can grip it; that is a placement question and
		# the readout prints both distances so it can be answered by looking.
		sv.poses.set_weapon(&"carry", {"bone": "Body",
				"pos": Vector3(-0.30, 2.30, -0.45), "rot": Vector3(-8, -52, 0)})
		for i in 150:
			await get_tree().physics_frame
		print("[GLUED] anchor %s   L grip %.2f (%.2f m)   R grip %.2f (%.2f m)"
				% [sv.weapon_anchor(), sv.arm_ik.grip_strength(0), sv.arm_ik.grip_distance(0),
						sv.arm_ik.grip_strength(1), sv.arm_ik.grip_distance(1)])
		_show_bones = true
		var cam := Camera3D.new()
		cam.fov = 42.0
		add_child(cam)
		cam.global_position = _ogre.global_position + Vector3(8.0, 3.4, 7.0)
		cam.look_at(_ogre.global_position + Vector3.UP * 2.2)
		cam.current = true
		for i in 20:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/demo_glued.png" % out)
		get_tree().quit()
		return
	if what == "walkgrip":
		# The complaint as a number: while WALKING, does the off hand jump, and does it end up at
		# the ogre's face? A hand that teleports is a hand whose target crossed a hard edge.
		_ogre.commanded_speed = 2.0
		demo_driving = true
		demo_drive = Vector3(0, 0, -1)
		for i in 90:
			await get_tree().physics_frame
		var skel := _ogre.solver.skeleton()
		var lh := skel.find_bone("LeftHand")
		var hd := skel.find_bone("Head")
		var prev: Vector3 = _ogre.solver.arm_ik.bone_positions()[lh]
		var worst_jump := 0.0
		var closest_head := 999.0
		var jumps := 0
		for i in 420:
			await get_tree().physics_frame
			var pts := _ogre.solver.arm_ik.bone_positions()
			var now: Vector3 = pts[lh]
			var j := prev.distance_to(now)
			if j > 0.12:
				jumps += 1
			worst_jump = maxf(worst_jump, j)
			closest_head = minf(closest_head, now.distance_to(pts[hd]))
			prev = now
		print("[WALKGRIP] worst frame jump %.4f m   frames over 12 cm: %d/420" % [worst_jump, jumps])
		print("[WALKGRIP] closest the left hand came to the head: %.3f m" % closest_head)
		print("[WALKGRIP] off-hand grip strength %.2f  haft %.2f m from shoulder"
				% [_ogre.solver.arm_ik.grip_strength(), _ogre.solver.arm_ik.grip_distance()])
		get_tree().quit()
		return
	if what == "offhand":
		# Does posing the left arm STICK, or does the off-hand IK put it back on the haft?
		# The complaint was that the mace glues the left arm; this is that complaint as a number.
		_editor.toggle()
		_editor.pose = "carry"
		for i in 40:
			await get_tree().physics_frame
		var skel := _ogre.solver.skeleton()
		var lh := skel.find_bone("LeftHand")
		var before: Vector3 = _ogre.solver.arm_ik.bone_positions()[lh]
		# A big, unmistakable change to the left arm.
		_ogre.solver.poses.poses["carry"]["LeftUpperArm"] = Vector3(-120, -30, 30)
		for i in 40:
			await get_tree().physics_frame
		var posed: Vector3 = _ogre.solver.arm_ik.bone_positions()[lh]
		# Now switch the grip back on and see it get overwritten.
		_editor.off_hand_grip = true
		_editor._off_hand(true)
		for i in 40:
			await get_tree().physics_frame
		var gripped: Vector3 = _ogre.solver.arm_ik.bone_positions()[lh]
		print("[OFFHAND] editor open, grip released:")
		print("[OFFHAND]   before pose  %v" % before)
		print("[OFFHAND]   after  pose  %v   moved %.3f m  <- the pose must win here"
				% [posed, before.distance_to(posed)])
		print("[OFFHAND] grip previewed on:")
		print("[OFFHAND]   after  grip  %v   moved %.3f m  <- the IK takes it back"
				% [gripped, posed.distance_to(gripped)])
		get_tree().quit()
		return
	if what == "frames":
		# Where does the MESH think the skeleton is, versus where the overlay draws it?
		#
		# A skinned mesh is deformed by bone poses expressed relative to the SKELETON, but it is
		# rendered at the MESH INSTANCE's transform. If that instance carries a transform of its own
		# the two frames differ by exactly that, the mesh renders in one place and any debug drawing
		# in another -- and every pose looks subtly wrong in a way that is impossible to argue with
		# and impossible to fix by posing.
		var skel := _ogre.solver.skeleton()
		print("[FRAME] skeleton.transform        %s" % skel.transform)
		print("[FRAME] skeleton.global_transform %s" % skel.global_transform)
		for mi: MeshInstance3D in _meshes_of(skel):
			print("[FRAME] mesh %s" % mi.name)
			print("[FRAME]   local  %s" % mi.transform)
			print("[FRAME]   global %s" % mi.global_transform)
			print("[FRAME]   skeleton path: %s -> %s" % [mi.skeleton, mi.get_node_or_null(mi.skeleton)])
			print("[FRAME]   skin: %s" % mi.skin)
		var hb := skel.find_bone("RightHand")
		var pose := skel.get_bone_global_pose(hb)
		print("[FRAME] RightHand via skeleton.global  %v" % (skel.global_transform * pose.origin))
		for mi2: MeshInstance3D in _meshes_of(skel):
			print("[FRAME] RightHand via mesh.global      %v" % (mi2.global_transform * pose.origin))
		get_tree().quit()
		return
	if what == "mace":
		# Prove the weapon transform: three placements on three different anchor bones, each
		# photographed. If the mace does not move, the pose data is not reaching the solver; if it
		# moves but ignores the anchor, the bone lookup is wrong. Both look like "the mace is in the
		# wrong place" and they need opposite fixes.
		_show_bones = true
		var cam := Camera3D.new()
		cam.fov = 42.0
		add_child(cam)
		cam.global_position = _ogre.global_position + Vector3(8.5, 3.6, 7.5)
		cam.look_at(_ogre.global_position + Vector3.UP * 2.2)
		cam.current = true
		var places := [
			["RightHand", Vector3(0.1, -0.7, 0.05), Vector3(-55, -30, 0), "hand"],
			["UpperChest", Vector3(-0.35, -0.3, -0.35), Vector3(-20, 40, 25), "back"],
			["Hips", Vector3(0.45, -0.1, 0.1), Vector3(-75, 10, 0), "belt"],
		]
		for pl in places:
			_ogre.solver.poses.set_weapon(&"carry",
					{"bone": pl[0], "pos": pl[1], "rot": pl[2]})
			for i in 70:
				await get_tree().physics_frame
			var g := _ogre.solver.grip_node()
			print("[MACE] %-5s anchor %-10s origin %v" % [pl[3], pl[0], g.global_position])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/demo_mace_%s.png" % [out, pl[3]])
		get_tree().quit()
		return
	if what == "ikdrag":
		# Prove the IK drag actually moves the joint. Compiling is not evidence: the drag writes
		# angles into a POSE, the pose layer applies them a frame later, and any break in that chain
		# looks identical to "the tool works but the ogre ignores it".
		_show_bones = true
		_editor.toggle()
		_editor.pose = "carry"
		_editor.bone = "RightHand"
		_editor.use_ik = true
		var cam := Camera3D.new()
		cam.fov = 40.0
		add_child(cam)
		cam.global_position = _ogre.global_position + Vector3(9.0, 3.6, 7.0)
		cam.look_at(_ogre.global_position + Vector3.UP * 2.2)
		cam.current = true
		for i in 30:
			await get_tree().physics_frame
		var skel := _ogre.solver.skeleton()
		var hand := skel.find_bone("RightHand")
		var start: Vector3 = _ogre.solver.arm_ik.bone_positions()[hand]
		# Drag toward a point out in front and low — where a hand would go to reach for something.
		# IN FRONT of the ogre and within arm's reach. The first version of this test used a fixed
		# +Z offset, which is BEHIND a creature that faces -Z: the arm clamped at full extension and
		# the probe reported a working tool as broken.
		var s2 := _ogre.solver
		var goal: Vector3 = _ogre.global_position + s2.forward() * 1.3 				+ s2.right() * 0.9 + Vector3.UP * 1.5
		for i in 90:
			_editor._drag_ik_to(goal)
			await get_tree().physics_frame
		var got: Vector3 = _ogre.solver.arm_ik.bone_positions()[hand]
		print("[IK] hand start %v" % start)
		print("[IK] hand end   %v" % got)
		print("[IK] goal       %v" % goal)
		print("[IK] moved %.3f m, now %.3f m from goal (was %.3f)"
				% [start.distance_to(got), got.distance_to(goal), start.distance_to(goal)])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/demo_ikdrag.png" % out)
		get_tree().quit()
		return
	if what == "editor":
		# Proof the authoring loop closes: open the editor, move a bone, confirm the ogre changed,
		# save, and read the file back. If any link in that chain is broken there is no way to
		# author a pose at all, and every attack stays wrong forever.
		_show_bones = true
		_editor.toggle()
		_editor.pose = "carry"
		_editor.bone = "RightUpperArm"
		var cam := Camera3D.new()
		cam.fov = 40.0
		add_child(cam)
		cam.global_position = _ogre.global_position + Vector3(9.0, 3.6, 7.0)
		cam.look_at(_ogre.global_position + Vector3.UP * 2.3)
		cam.current = true
		for shot in [Vector3(-118, 12, -14), Vector3(-40, 20, -30)]:
			_ogre.solver.poses.poses["carry"]["RightUpperArm"] = shot
			for i in 45:
				await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					"%s/demo_editor_%d.png" % [out, int(shot.x)])
			print("[DEMO] editor RightUpperArm=%v" % shot)
		_editor._save()
		print("[DEMO] saved: %s exists=%s"
				% [OgreSolver.POSES_PATH, ResourceLoader.exists(OgreSolver.POSES_PATH)])
		get_tree().quit()
		return
	if what == "stand":
		# Just stand there, close in, with the bones on. This is the shot for checking a grip or a
		# pose -- the thing you cannot judge from an action sequence going past at speed.
		_show_bones = true
		var cam := Camera3D.new()
		cam.fov = 38.0
		add_child(cam)
		cam.global_position = _ogre.global_position + Vector3(8.0, 3.4, 6.5)
		cam.look_at(_ogre.global_position + Vector3.UP * 2.3)
		cam.current = true
		for i in 40:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/demo_stand.png" % out)
		print("[DEMO] stand")
		get_tree().quit()
		return
	if what == "rock":
		await _demo_action(&"rock_lift", out, "rock_lift")
		await get_tree().create_timer(0.4).timeout
		await _demo_action(&"rock_throw", out, "rock_throw")
	else:
		await _demo_action(StringName(what), out, what)
	await get_tree().create_timer(1.2).timeout
	get_tree().quit()


func _demo_action(act: StringName, out: String, tag: String) -> void:
	var s: OgreSolver = _ogre.solver
	# Its OWN camera, made current. Nudging the CameraRig's child is pointless -- the rig rewrites
	# that transform every frame, and the screenshot ends up wherever the rig wanted to be.
	if _demo_cam == null:
		_demo_cam = Camera3D.new()
		_demo_cam.fov = 42.0
		add_child(_demo_cam)
	_demo_cam.global_position = _ogre.global_position + Vector3(11.0, 4.2, 8.0)
	_demo_cam.look_at(_ogre.global_position + Vector3.UP * 2.0)
	_demo_cam.current = true
	s.play_action(act)
	var grip_err := {"max": 0.0}
	var rh := s.skeleton().find_bone(s.weapon_bone)
	var strike := s.action_time(act, &"strike")
	var marks: Array[float] = [0.02, strike * 0.6, strike - 0.02, strike + 0.05,
			strike + 0.16, strike + 0.4, s.action_len * 0.95]
	var k := 0
	while k < marks.size():
		if s.action_t >= marks[k] or not s.is_acting():
			await RenderingServer.frame_post_draw
			# MEASURED AFTER THE DRAW, which is the only honest moment. The grip is placed in
			# _process and the bone snapshot is taken in the physics pass, so sampling between the
			# two compares a weapon from one frame against a hand from the next and reports most of
			# a fast swing's hand travel as if it were slop in the grip. After the frame is
			# presented both are the values that were actually rendered.
			var g := s.grip_node()
			if g and rh >= 0:
				var pts2 := s.arm_ik.bone_positions()
				if rh < pts2.size():
					var to_hand: Vector3 = pts2[rh] - g.global_position
					var axis: Vector3 = g.global_basis.y.normalized()
					var perp := (to_hand - axis * to_hand.dot(axis)).length()
					grip_err["max"] = maxf(grip_err["max"], perp)
					grip_err["at"] = s.action_t
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/demo_%s_%d.png" % [out, tag, k])
			print("[DEMO] %s frame %d at t=%.3f | drop %.2f | knees %.0f/%.0f | feet apart %.2f"
					% [tag, k, s.action_t, s.clip_drop,
					rad_to_deg(s.foot_ik.knee_angles()[0]), rad_to_deg(s.foot_ik.knee_angles()[1]),
					s.feet[0].target.distance_to(s.feet[1].target)])
			k += 1
			continue
		await get_tree().physics_frame
	print("[GRIP] %s: hand sat up to %.3f m OFF the shaft axis (worst at t=%.2f)"
			% [tag, grip_err["max"], grip_err.get("at", 0.0)])


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = true
	_mat.vertex_color_use_as_albedo = true
	_debug.mesh = ImmediateMesh.new()
	_debug.material_override = _mat
	_debug.top_level = true
	_build_panel()
	_editor = (load(POSE_EDITOR) as GDScript).new()
	_editor.build(self, _ogre.solver)
	# A camera you can fly. Posing is a 3D job and one fixed angle cannot show you whether a hand is
	# in front of the chest or behind it -- which is most of what goes wrong in a pose.
	_fly = FlyCamera.new()
	_fly.name = "FlyCam"
	add_child(_fly)
	_fly.global_position = _ogre.global_position + Vector3(7.5, 3.4, 7.5)
	_fly.look_at(_ogre.global_position + Vector3.UP * 2.0)
	_fly.current = false
	_make_readout_draggable()
	_scatter_rocks()
	var what := ""
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			what = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6).rstrip("/\\")
	if what != "":
		# A tuning panel and a wall of numbers over the subject is a wasted screenshot.
		_panel_layer.visible = false
		($UI as CanvasLayer).visible = false
		_demo(what, out)


func _unhandled_input(event: InputEvent) -> void:
	# The editor gets first refusal on the mouse: while it is open, a left-drag is posing a bone and
	# must not also be doing whatever else the lab would have done with it.
	if _editor and _editor.handle_input(event, get_viewport().get_camera_3d()):
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_6:
		_ogre.solver.play_action(MOVES[key - KEY_1])
		return
	match key:
		KEY_0:
			# The interrupt test, by hand. A wind-up that survives being cancelled is the bug
			# enemy.gd's fear() docstring is about, and it is worth being able to provoke.
			_ogre.solver.cancel_action()
		KEY_B:
			_scatter_rocks()
		KEY_P:
			_toggle_player()
		KEY_G:
			_draw = (_draw + 1) % DRAW_MODES.size()
		KEY_F3:
			($UI as CanvasLayer).visible = not ($UI as CanvasLayer).visible
		KEY_L:
			_cycle_bypass()
		KEY_K:
			_ogre.frozen = not _ogre.frozen
		KEY_PERIOD:
			_step_once = true
		KEY_R:
			_ogre.teleport(Vector3(0, 0.2, 0))
			_skate_peak = 0.0
		KEY_F1:
			_panel_layer.visible = not _panel_layer.visible
		KEY_F2:
			_show_bones = not _show_bones
		KEY_F4:
			_editor.toggle()
			# Posing needs a camera you can move and a skeleton you can see, so opening the editor
			# turns both on rather than making you remember two more keys.
			if _editor.enabled:
				_fly.current = true
				_show_bones = true
		KEY_TAB:
			_fly.current = not _fly.current


func _physics_process(_delta: float) -> void:
	# One frame of motion while frozen, so a suspicious pose can be walked into rather than caught.
	if _ogre.frozen and _step_once:
		_ogre.frozen = false
		_ogre.call_deferred("set", "frozen", true)
	_step_once = false

	# WASD belongs to whoever is being driven. With the fly camera live it is flying the camera, and
	# having the ogre walk off at the same time makes posing impossible -- you lose the subject and
	# the framing in the same keystroke.
	var dir := Vector3.ZERO
	if not _ogre.frozen and not (_fly and _fly.current) \
			and not (_editor and _editor.enabled):
		var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if v.length_squared() > 0.01:
			# Camera-relative, so "forward" means away from the viewer no matter where the rig is —
			# the same idiom player.gd uses, and the only one that survives an orbiting camera.
			dir = (Basis(Vector3.UP, _rig.rotation.y) * Vector3(v.x, 0.0, v.y)).normalized()
	# A DEMO DRIVING BEATS THE KEYBOARD. Without this the line below simply overwrote whatever a
	# demo had asked for, every frame, with the zero vector of nobody pressing anything -- so every
	# "while walking" measurement in this file was taken on an ogre standing perfectly still, and
	# reported smooth because nothing was moving.
	_ogre.drive = demo_drive if demo_driving else dir
	_ogre.want_run = Input.is_key_pressed(KEY_SHIFT) and not (_fly and _fly.current)


func _process(_delta: float) -> void:
	_readout.text = _report()
	_redraw()


# =================================================================================================
# READOUT
# =================================================================================================

func _report() -> String:
	var s: OgreSolver = _ogre.solver
	if s == null or not s.is_ready():
		return "solver not ready"
	var f0 = s.feet[0]
	var f1 = s.feet[1]
	_skate_peak = maxf(_skate_peak, maxf(_stance_skate(f0), _stance_skate(f1)))
	var knees: Array = s.foot_ik.knee_angles() if s.foot_ik else [PI, PI]

	var lines := PackedStringArray()
	lines.append("OGRE  %.2f m   leg L %.2f m   reach %.2f m   ankle %.2f m"
			% [s.stature, s.leg_length, s.max_reach, s.ankle_height])
	lines.append("")
	lines.append("speed    %5.2f m/s   (walk %.2f / run %.2f)   Fr %.3f"
			% [s.speed, s.walk_speed(), s.run_speed(), s.froude])
	lines.append("accel    %5.2f m/s2   lean %5.1f deg   yaw cap %.0f deg/s"
			% [s.accel.length(), rad_to_deg(s.lean_pitch), rad_to_deg(s.yaw_rate(s.speed))])
	lines.append("")
	lines.append("gait     %-5s  phase %.2f   f %.2f Hz   stride %.2f m   duty %.2f  dbl %.2f"
			% [_gait_name(s.gait), s.phase, s.stride_freq, s.stride, s.duty, s.double_support])
	lines.append("foot L   %-6s t %.2f   knee %5.1f deg   skate %6.1f mm/s%s"
			% [_mode(f0), f0.t, rad_to_deg(knees[0]), _stance_skate(f0) * 1000.0, _air(f0)])
	lines.append("foot R   %-6s t %.2f   knee %5.1f deg   skate %6.1f mm/s%s"
			% [_mode(f1), f1.t, rad_to_deg(knees[1]), _stance_skate(f1) * 1000.0, _air(f1)])
	lines.append("skate peak this run: %.1f mm/s      steps L%d R%d" % [_skate_peak * 1000.0, f0.steps, f1.steps])
	lines.append("")
	lines.append("hips     y %+.3f   roll %+5.1f   yaw %+5.1f   spine %+5.1f   breath %.2f"
			% [s.hips_offset.y, rad_to_deg(s.hips_roll), rad_to_deg(s.hips_yaw),
					rad_to_deg(s.spine_yaw), s.breath])
	var act := "-" if s.action == &"" else "%s  t %.2f / %.2f" % [s.action, s.action_t, s.action_len]
	lines.append("action   %-34s %s" % [act, "PLANTED" if s.stance_lock else ""])
	lines.append("poses    %s" % _pose_text(s))
	if s.clip_layer:
		lines.append("clip     %s  t %.2f   weight %.2f"
				% ["-" if s.clip_layer.clip == null else "slam", s.clip_layer.time,
						s.clip_layer.weight])
	var lag := s.dynamics.lag_degrees() if s.dynamics else 0.0
	lines.append("upper    inertia lag %5.1f deg   %s" % [lag, _lag_bar(lag)])
	if s.arm_ik:
		lines.append("hands    L grip %.2f (%.2f m)   R grip %.2f (%.2f m)   anchor %s"
				% [s.arm_ik.grip_strength(0), s.arm_ik.grip_distance(0),
						s.arm_ik.grip_strength(1), s.arm_ik.grip_distance(1),
						s.weapon_anchor()])
	lines.append("layers   %s %s %s"
			% [_flag("GAIT", s.gait_layer), _flag("IK", s.foot_ik),
					"FROZEN" if _ogre.frozen else ""])
	lines.append("")
	lines.append("1 slam  2 lift  3 throw  4 roar  5 stagger  6 flinch   0 cancel   B rocks")
	if _editor and _editor.enabled:
		lines.append("EDIT     pose %s   bone %s   %s   Ctrl+Z undo"
				% [_editor.pose, _editor.bone,
						"axis LOCKED: %s" % ["pitch", "yaw", "roll"][_editor.axis]
						if _editor.axis >= 0 else "free rotate"])
	var sv: OgreSolver = _ogre.solver
	if sv and sv.is_ready() and sv.arm_ik:
		var pts := sv.arm_ik.bone_positions()
		var ir := sv.bone("RightHand")
		var il := sv.bone("LeftHand")
		var er := 0.0
		var el := 0.0
		if ir >= 0 and ir < pts.size():
			er = sv.arm_ik.palm_position(1).distance_to(sv.grip_world())
		if il >= 0 and il < pts.size():
			el = sv.arm_ik.palm_position(0).distance_to(sv.off_grip_world())
		lines.append("GRIP  PALM off its point:  R %.2f m   L %.2f m      (grip strength R %.2f L %.2f)"
				% [er, el, sv.arm_ik.grip_strength(1), sv.arm_ik.grip_strength(0)])
	lines.append("F4 POSE EDITOR   F2 skeleton(%s)   Tab flycam(%s)   F1 dials   F3 hide   (drag this box)"
			% ["on" if _show_bones else "off", "on" if (_fly and _fly.current) else "off"])
	lines.append("WASD drive  Shift run   P player   G draw: %s   L bypass   K freeze   . step   R reset"
			% DRAW_MODES[_draw])
	return "\n".join(lines)


## Skate is only meaningful while the foot is planted — a swinging foot is SUPPOSED to move, and
## reporting its speed as skate is how a healthy solver gets accused of a bug.
## Which poses are live and how much of each. Two overlapping names is a blend in progress; one at
## 1.00 is a pose being held.
## The inertia layer, made visible. A still frame cannot show lag, so this is how you tell the upper
## body is being MOVED rather than posed: it sits near zero standing still and spikes when a strike
## fires. Flat zero through a slam means the dynamics layer is not doing its job.
func _lag_bar(deg: float) -> String:
	var n := clampi(int(deg / 1.5), 0, 28)
	return "[" + "|".repeat(n) + " ".repeat(28 - n) + "]"


func _pose_text(s: OgreSolver) -> String:
	if s.pose_weights.is_empty():
		return "(rest)"
	var parts := PackedStringArray()
	for n in s.pose_weights:
		parts.append("%s %.2f" % [n, s.pose_weights[n]])
	return "  ".join(parts)


func _stance_skate(f) -> float:
	return f.last_skate if f.mode == OgreSolver.FootMode.STANCE else 0.0


func _mode(f) -> String:
	return "STANCE" if f.mode == OgreSolver.FootMode.STANCE else "SWING"


func _air(f) -> String:
	return "" if f.grounded else "   NO GROUND"


func _gait_name(g: int) -> String:
	return ["IDLE", "WALK", "RUN"][g]


func _flag(n: String, m: SkeletonModifier3D) -> String:
	if m == null:
		return "[%s?]" % n
	return n if m.active else "[%s off]" % n


func _cycle_bypass() -> void:
	# modifier.active is the BUILT-IN bypass. Watching the gait with the foot IK switched off is how
	# you tell a bad gait from a bad IK, and that is most of the debugging in a system like this.
	var s: OgreSolver = _ogre.solver
	if s.gait_layer.active and s.foot_ik.active:
		s.foot_ik.active = false
	elif s.gait_layer.active:
		s.gait_layer.active = false
		s.foot_ik.active = true
	else:
		s.gait_layer.active = true
		s.foot_ik.active = true


# =================================================================================================
# DEBUG DRAW
# =================================================================================================

func _redraw() -> void:
	var mesh := _debug.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _draw == 0:
		return
	var s: OgreSolver = _ogre.solver
	if s == null or not s.is_ready():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if _draw == 5:
		# THE GAMEPLAY LAYER, ON ITS OWN. Not a debug view of the animation -- the zones ARE the
		# fight, and everything the body does about range is decided from these two rings and the
		# wedge across them. "Why did it not attack" stops being a guess.
		_draw_zones(mesh, s)
		mesh.surface_end()
		return
	_draw_grip(mesh, s)
	if _draw >= 2:
		_draw_skeleton(mesh, s, _draw == 2)
	if _draw >= 4:
		# The legs, and the balance line they hold up. Last, and off by default: this half is
		# finished and does not need watching, and drawn alongside the grip markers it is just
		# clutter with a similar shape.
		for i in 2:
			var f = s.feet[i]
			var planted: bool = f.mode == OgreSolver.FootMode.STANCE
			_cross(mesh, f.plant, 0.35, Color(0.2, 1.0, 0.3) if planted else Color(0.25, 0.5, 0.3))
			_cross(mesh, f.target, 0.22, Color(1, 1, 1))
			if not planted:
				_cross(mesh, f.predicted, 0.30, Color(1.0, 0.85, 0.1))
				_line(mesh, f.target, f.predicted, Color(1.0, 0.85, 0.1, 0.5))
		var com := s.global_position + Vector3.UP * (s.leg_length + s.hips_offset.y)
		_line(mesh, s.feet[0].plant, s.feet[1].plant, Color(0.4, 0.7, 1.0))
		_cross(mesh, com, 0.4, Color(1.0, 0.3, 0.3))
		_line(mesh, com, com + s.accel * 0.5, Color(0.5, 0.5, 1.0))
	mesh.surface_end()


## THE ATTACK ZONES, on the ground, body-local.
##
## The strike annulus with the wedge the shoulder allows, the kick's disc inside its hole, and the
## line out to where the ogre will advance from. Body-local is the point: they turn with the ogre,
## which is exactly why it cannot swing behind its own shoulder, and seeing them swing round as it
## turns is the whole explanation of that rule in one picture.
func _draw_zones(mesh: ImmediateMesh, s: OgreSolver) -> void:
	var o := s.global_position + Vector3.UP * 0.05
	var sz: Vector2 = s.strike_zone()
	var kz: Vector2 = s.kick_zone()
	var lim: float = deg_to_rad(s.tuning.strike_yaw)
	var fwd := s.forward()
	# The strike wedge: two arcs and the two spokes that close them.
	_arc(mesh, o, fwd, sz.x, -lim, lim, Color(1.0, 0.75, 0.15))
	_arc(mesh, o, fwd, sz.y, -lim, lim, Color(1.0, 0.75, 0.15))
	for sgn in [-1.0, 1.0]:
		var d := fwd.rotated(Vector3.UP, sgn * lim)
		_line(mesh, o + d * sz.x, o + d * sz.y, Color(1.0, 0.75, 0.15))
	# The kick: a full ring, because a kick has no wedge worth speaking of at this range.
	_arc(mesh, o, fwd, kz.y, -PI, PI, Color(0.35, 0.85, 1.0))
	# How far it will walk in rather than give up.
	_arc(mesh, o, fwd, s.tuning.advance_max, -lim, lim, Color(0.5, 0.5, 0.55, 0.6))
	# Where the blow is currently aimed, and where the geometry says the head will actually land.
	if s.is_acting():
		_cross(mesh, s.aim_point, 0.35, Color(1.0, 0.3, 0.3))
		_cross(mesh, s.predicted_impact(), 0.5, Color(1.0, 0.1, 0.6))


## One arc on the ground, swept about `fwd`.
func _arc(mesh: ImmediateMesh, o: Vector3, fwd: Vector3, r: float, a0: float, a1: float,
		c: Color) -> void:
	if r <= 0.01:
		return
	var steps := 28
	var prev := o + fwd.rotated(Vector3.UP, a0) * r
	for i in range(1, steps + 1):
		var a: float = a0 + (a1 - a0) * (float(i) / float(steps))
		var at := o + fwd.rotated(Vector3.UP, a) * r
		_line(mesh, prev, at, c)
		prev = at


## THE SKELETON, drawn from the pose the solver actually produced.
##
## Positions come from OgreArmIk's end-of-pass snapshot, not from reading the skeleton here: a read
## from outside the modifier pass returns the pose from BEFORE the pass, so a skeleton drawn that
## way shows the rest pose while the ogre visibly does something else. That discrepancy is a very
## expensive thing to stare at while trying to pose.
##
## The bone being edited is drawn hot, with a cross on its head, so you can see which joint the
## sliders are about to move before you move it.
func _draw_skeleton(mesh: ImmediateMesh, s: OgreSolver, upper_only := false) -> void:
	var skel := s.skeleton()
	if skel == null or s.arm_ik == null:
		return
	var pts := s.arm_ik.bone_positions()
	if pts.size() != skel.get_bone_count():
		return
	if _parent_of.size() != pts.size():
		_parent_of.resize(pts.size())
		for b in pts.size():
			_parent_of[b] = skel.get_bone_parent(b)
	var sel := -1
	if _editor and _editor.enabled:
		sel = skel.find_bone(_editor.bone)
	for b in pts.size():
		var p: int = _parent_of[b]
		if p < 0:
			continue
		# UPPER BODY ONLY leaves the pelvis and legs out. They are the finished half and they are
		# drawn in the same blue as the arms, so at a glance the leg chains read as more grip
		# geometry -- which is exactly the confusion this mode exists to remove.
		if upper_only and _is_lower(skel.get_bone_name(b)):
			continue
		var hot: bool = (b == sel or p == sel)
		_line(mesh, pts[p], pts[b], Color(1.0, 0.85, 0.2) if hot else Color(0.45, 0.75, 1.0, 0.75))
	if sel >= 0:
		_cross(mesh, pts[sel], 0.22, Color(1.0, 0.85, 0.2))
		_gizmo(mesh)


## Pelvis and legs, by name. Named rather than indexed because the skeleton is rebuilt on every
## reimport and a hard-coded bone index is a number that will one day point at an ear.
func _is_lower(bone: String) -> bool:
	return bone == "Hips" or bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toe")


## THE ROTATION GIZMO: three rings at the selected joint, one per body axis.
##
## Red is pitch, green yaw, blue roll, in the same order as the editor's three sliders — so the
## thing you grab and the number that moves are obviously the same thing. Clicking a ring locks the
## drag to that axis; clicking the joint itself rotates freely.
##
## Drawn here rather than in the editor because the lab already owns the overlay mesh and its
## unshaded no-depth-test material, and a second one would be a second thing to keep in step.
func _gizmo(mesh: ImmediateMesh) -> void:
	var rings: Array = _editor.axis_rings()
	if rings.size() < 4:
		return
	var centre: Vector3 = rings[0]
	var cols := [Color(1.0, 0.35, 0.35), Color(0.4, 1.0, 0.45), Color(0.45, 0.6, 1.0)]
	for ax in 3:
		var n: Vector3 = rings[ax + 1]
		# The grabbed ring is drawn solid and the others faint, so the mode you are in is visible
		# without reading the log.
		var c: Color = cols[ax]
		if _editor.axis >= 0 and _editor.axis != ax:
			c.a = 0.25
		var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := n.cross(u).normalized()
		var prev: Vector3 = centre + u * _editor.RING_R
		for k in range(1, 33):
			var a := TAU * float(k) / 32.0
			var pt: Vector3 = centre + (u * cos(a) + v * sin(a)) * _editor.RING_R

			_line(mesh, prev, pt, c)
			prev = pt


## THE GRIP. FIVE THINGS, and nothing else:
##
##   1. a PURPLE LINE down the mace's axis, butt to head
##   2. the RIGHT hand's grip point, on that line          (warm, large)
##   3. the LEFT  hand's grip point, on that line          (cool, large)
##   4. the RIGHT palm                                     (warm, small)
##   5. the LEFT  palm                                     (cool, small)
##
## COLOURED BY HAND so a pair is obviously a pair, SIZED BY KIND so a point on the mace can be told
## from a point on a hand when the two have come apart. In normal operation each pair sits on top of
## itself and you see two markers, not four.
##
## A LINE APPEARS ONLY WHEN A PAIR HAS COME APART. Under GRIP_SLACK nothing is drawn, so seeing any
## line at all means a hand has lost its point -- which is the only moment the number is wanted.
##
## Nothing else goes in here. It previously drew nine things, including the wrists and the spans
## from wrist to palm, which were left over from diagnosing the wrist/palm confusion and afterwards
## served only to be mistaken for the markers that matter.
const GRIP_SLACK := 0.05

func _draw_grip(mesh: ImmediateMesh, s: OgreSolver) -> void:
	var g := s.grip_node()
	# Nothing to draw a grip for once the weapon is on the floor -- the grip node is still there,
	# but it is no longer holding anything.
	if g == null or s.arm_ik == null or s.carrying == &"":
		return
	var right := Color(1.0, 0.5, 0.15)
	var left := Color(0.3, 0.7, 1.0)

	# 1 -- the axis
	var dir := g.global_basis.y.normalized()
	_line(mesh, g.global_position, g.global_position + dir * s.weapon_length,
			Color(0.75, 0.35, 1.0))

	# 2..5 -- one pair per hand: the point ON THE MACE, and the PALM that should be on it
	for side in 2:
		var col: Color = left if side == 0 else right
		var on_mace: Vector3 = s.off_grip_world() if side == 0 else s.grip_world()
		var palm: Vector3 = s.arm_ik.palm_position(side)
		_dot(mesh, on_mace, 0.16, col)
		_dot(mesh, palm, 0.09, col)
		if palm.distance_to(on_mace) > GRIP_SLACK:
			_line(mesh, palm, on_mace, Color(col.r, col.g, col.b, 0.9))


## A point marker: three short segments through it. Small enough to read as a dot rather than as
## another cross competing with the foot targets.
func _dot(mesh: ImmediateMesh, at: Vector3, r: float, c: Color) -> void:
	_line(mesh, at - Vector3.RIGHT * r, at + Vector3.RIGHT * r, c)
	_line(mesh, at - Vector3.UP * r, at + Vector3.UP * r, c)
	_line(mesh, at - Vector3.BACK * r, at + Vector3.BACK * r, c)


func _cross(mesh: ImmediateMesh, at: Vector3, r: float, c: Color) -> void:
	_line(mesh, at - Vector3.RIGHT * r, at + Vector3.RIGHT * r, c)
	_line(mesh, at - Vector3.FORWARD * r, at + Vector3.FORWARD * r, c)
	_line(mesh, at, at + Vector3.UP * r, c)


func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Color) -> void:
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(b)


# =================================================================================================
# PANEL AND PLAYER
# =================================================================================================

## Six lines, sixty sliders. TuningPanel.from_object reads the property list and builds a row per
## @export — correct bounds from @export_range, headers from @export_group. Adding a dial to
## ogre_tuning.gd adds a slider here with no edit to this file, which is the whole reason the tuning
## lives in a Resource.
func _build_panel() -> void:
	var box := TuningPanel.build_panel(self, 340, 660)
	_panel_layer = box.get_parent().get_parent().get_parent() as CanvasLayer
	TuningPanel.header(box, "OGRE — procedural animation")
	TuningPanel.from_object(box, _ogre.solver.tuning, [], func(_n, _v): pass)


## THE READOUT GETS OUT OF THE WAY. A wall of numbers pinned over the middle of the subject is a
## readout you end up fighting -- and the thing it is describing is exactly what it is covering.
## Drag it anywhere; F3 hides it outright.
##
## Done on the Label itself rather than by reparenting it into a panel: it needs a background to be
## legible over the scene anyway, and a Label takes one through a theme override.
func _make_readout_draggable() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.07, 0.72)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	_readout.add_theme_stylebox_override("normal", bg)
	_readout.mouse_filter = Control.MOUSE_FILTER_STOP
	_readout.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_readout.tooltip_text = "drag to move"
	_readout.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drag = (e as InputEventMouseButton).pressed
			_drag_from = _readout.get_local_mouse_position()
		elif e is InputEventMouseMotion and _drag:
			_readout.position += _readout.get_local_mouse_position() - _drag_from)


func _meshes_of(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += _meshes_of(c)
	return out


## Boulders for the ogre to pick up. Placed in a ring rather than a line so a throw can be tried
## from any facing without repositioning the whole scene.
func _scatter_rocks() -> void:
	for r in get_tree().get_nodes_in_group("rock"):
		(r as Node).queue_free()
	for i in 7:
		var a := TAU * float(i) / 7.0
		var rock := ROCK.instantiate() as Rock
		rock.radius = 0.45 + 0.22 * float(i % 3)
		rock.seed_offset = i
		add_child(rock)
		# Close enough that the ogre can actually reach one without walking. The first pass ringed
		# them at 7 m against a 6 m reach and the throw fired with an empty hand, which looks exactly
		# like a broken throw and was a broken scene.
		rock.global_position = Vector3(cos(a), 0.0, sin(a)) * (4.2 + 1.3 * float(i % 4))
		rock.global_position.y = rock.radius * 0.75


## The scale reference that matters. A 4 m number means nothing; a 1.8 m person standing next to it
## means everything — and the player is also a look-at target and something with a hurtbox.
func _toggle_player() -> void:
	if _player and is_instance_valid(_player):
		_player.queue_free()
		_player = null
		_ogre.target = null
		_rig.target_path = _rig.get_path_to(_ogre)
		return
	var packed := load(PLAYER) as PackedScene
	if packed == null:
		return
	_player = packed.instantiate() as Node3D
	add_child(_player)
	_player.global_position = _ogre.global_position + Vector3(6.0, 1.1, 3.0)
	_ogre.target = _player


## Closest distance between two SEGMENTS. The mace is a 4 m pole and the ogre is a capsule, so
## "does the weapon intersect the body" is a segment-to-segment question and nothing less will do.
##
## The metric this replaces measured the mace HEAD against the body axis, which is why it reported
## 2.81 m of clearance for a swing that visibly ran the shaft through the ogre's chest: a four-metre
## pole can have both ENDS far from a body and still pass straight through the middle of it.
func _seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return r.length()
	if a <= 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 0.000001 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()


## How far the mace shaft is INSIDE the ogre, in metres. Zero or less means clear.
func _shaft_penetration() -> float:
	var sv: OgreSolver = _ogre.solver
	var g := sv.grip_node()
	if g == null:
		return 0.0
	# THE SAME TRUNK THE CONSTRAINT USES. A metric that disagrees with the thing it is grading is
	# worse than no metric: the first version measured against the 0.9 m collision capsule, which
	# swallows the whole region an arm occupies, and so reported the mace as buried on every frame
	# including the ones that were fine.
	var dir := g.global_basis.y.normalized()
	var d := _seg_seg(g.global_position + dir * sv.tuning.weapon_clear_skip,
			g.global_position + dir * sv.weapon_length,
			sv.global_position + Vector3.UP * sv.tuning.weapon_clear_low,
			sv.global_position + Vector3.UP * sv.tuning.weapon_clear_high)
	return sv.tuning.weapon_clear_radius - d

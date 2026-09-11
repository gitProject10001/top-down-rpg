extends Node3D
class_name CombatDebug
## THE GAMEPLAY LAYER, MADE VISIBLE — every area the fight is actually decided by, drawn in world
## space over the top of the game.
##
## This is not a debug view of the animation. `docs/combat-architecture.md` splits the fight into a
## GAMEPLAY layer (zones, the impact point, the volumes that hurt, the beats that open them) and a
## VISUAL layer (IK, springs, poses) — and the gameplay layer is nothing but spheres, rings, line
## segments and a clock. All of it can be drawn. When "it does not attack" or "the circle is not
## where it lands", the answer is in these shapes and nowhere else, so they are worth being able to
## see at any moment rather than reconstructing from printed numbers afterwards.
##
## Drop it into any scene that has an ogre. It finds the solver itself and draws nothing at all if
## there isn't one, so it is safe to leave in a scene permanently.
##
## KEY: F6 cycles the modes. F7 freezes what is drawn (see `frozen`), which is the only way to study
## a shape that exists for two frames in the middle of a smash. F3 is the existing hitbox view and
## is unrelated.
##
## IT IS AN AUTOLOAD ("Areas"), beside Dbg. That is the whole point: a debug view you have to
## remember to add to a scene is a debug view that is not there the one time you need it, and the
## question this answers -- "why did it not attack" -- always comes up while playing something, not
## while setting a scene up. It costs nothing when switched off and finds its own ogre, so scenes
## with no ogre in them never know it exists.
##
## READ-ONLY, ALWAYS. It never writes a bone, a transform or a solver field. Two of the expensive
## bugs in this system came from debug code that touched the skeleton outside the modifier pass and
## surfaced as foot skate — so this reads the arm IK's end-of-pass snapshot exactly the way the lab's
## overlay does, and never asks the skeleton anything directly.

## What is drawn, in order of how much of it there is. Each mode is a superset of the one before,
## because the question is usually "and where is X relative to what I was already looking at".
const MODES: Array[String] = [
	"off",
	"zones",                       # where each attack can reach, body-local
	"zones + impact",              # ...plus where this blow is going and what promised it
	"zones + impact + volumes",    # ...plus everything that can actually hurt someone
	"everything",                  # ...plus the weapon, the grips and the feet
]

## Colours, kept in one place because a legend is only useful if it cannot go stale.
const C_STRIKE := Color(1.00, 0.75, 0.15)      ## the mace's annulus and its shoulder wedge
const C_KICK := Color(0.35, 0.85, 1.00)        ## the kick's ring
const C_TURN := Color(1.00, 0.45, 0.05)        ## reachable by rotating: the waist joins in
const C_REPOSITION := Color(0.15, 0.60, 1.00)  ## reachable by stepping: the feet join in
const C_ADVANCE := Color(0.50, 0.50, 0.55)     ## how far it will walk in rather than give up
const C_AIM := Color(1.00, 0.35, 0.20)         ## where the swing is DIRECTED
const C_LAND := Color(1.00, 0.10, 0.60)        ## where the head will actually ARRIVE
const C_PROMISE := Color(0.95, 0.20, 0.20)     ## where the telegraph disc says it will arrive
const C_LIE := Color(1.00, 1.00, 0.00)         ## the gap between the last two, when there is one
const C_HIT := Color(1.00, 0.20, 0.20)         ## damage dealers
const C_HURT := Color(0.20, 1.00, 0.40)        ## damage receivers
const C_WEAPON := Color(0.75, 0.35, 1.00)      ## the mace axis
const C_GRIP_R := Color(1.00, 0.60, 0.20)
const C_GRIP_L := Color(0.40, 0.70, 1.00)
const C_FOOT := Color(0.30, 1.00, 0.45)

## The bands, named. M1 is where the arm alone reaches, and each one after it needs more of the
## creature to move -- which is also the order in which they become easier for a player to see
## coming, so the numbering is the difficulty ladder as well as the anatomy.
const MARKS: Array[String] = ["M1", "M2", "M3"]
const MARK_COLS: Array[Color] = [
	Color(1.00, 0.80, 0.25), Color(1.00, 0.55, 0.12), Color(0.35, 0.72, 1.00),
]

## A promise and a landing place closer than this are not worth drawing a line between.
const LIE_SLACK := 0.12

@export var mode := 2
## Which ogre to describe. Left empty it takes the first one it finds, which is what every scene
## here wants; set it explicitly once a scene has two.
@export var ogre_path: NodePath
## Draw the ring the mace head sweeps through, not just where it lands. Off by default: it is a big
## shape and it hides the small ones.
@export var show_swing_ring := false

var _ogre: Node3D
var _solver: OgreSolver
var _mesh_node: MeshInstance3D
var _mat: StandardMaterial3D
## Frozen frames keep their geometry instead of re-deriving it, so a shape that exists for two
## frames in the middle of a smash can actually be looked at.
var frozen := false
var _label: Label
var _hits: Array[Node] = []
var _hurts: Array[Node] = []
var _rescan := 0.0
## Where --areas-shot= wants its frames, or empty for a normal interactive run.
var _shot_dir := ""
## An action the screenshot demo drives directly, so a defect in the CHOOSER cannot hide a defect in
## the SWING. The overlay never does this -- only the demo, which is a driver, not an observer.
var _force: StringName = &""
var _beats := {}
var _marks: Array[Label3D] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--areas-shot="):
			_shot_dir = a.split("=", true, 1)[1]
		if a.begins_with("--areas-force="):
			_force = StringName(a.split("=", true, 1)[1])
	if _shot_dir != "":
		mode = 4
		_shoot.call_deferred()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = true
	_mat.vertex_color_use_as_albedo = true
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "CombatDebugMesh"
	_mesh_node.mesh = ImmediateMesh.new()
	_mesh_node.material_override = _mat
	# TOP LEVEL, so the drawing is in world space no matter where this node is parented. Every
	# position below comes from the solver in world coordinates; inheriting a parent's transform
	# would rotate the whole overlay with whatever it happens to hang off.
	_mesh_node.top_level = true
	add_child(_mesh_node)
	_build_marks()
	_build_legend()


## PHOTOGRAPH THE AREAS AT THE MOMENTS THAT MATTER.
##
## Not on a timer. A swing spends most of its length winding up, so evenly spaced frames catch the
## same picture six times and miss the one frame where the head arrives -- which is the only frame
## that can show whether the telegraph told the truth. These are keyed to the action's own clock,
## the same way the lab's contact sheets are.
func _shoot() -> void:
	await get_tree().create_timer(1.0).timeout
	# WHAT THE ACTION ACTUALLY DID, beat by beat. A run of wind-up frames with no contact between
	# them says the swings are being restarted, and only the beats say why.
	_solver.action_event.connect(func(w: StringName, _at: Vector3) -> void:
		_beats[w] = int(_beats.get(w, 0)) + 1
		if w == &"abandoned" or w == &"strike" or w == &"recover" or w == &"landed":
			print("[AREAS] beat %s at t=%.2f zone=%s action=%s"
					% [w, _solver.action_t,
					["STRIKE", "TURN", "REPOSITION", "WRONG"][_solver.zone], _solver.action]))
	var shots := 0
	var last_act: StringName = &""
	var want_impact := false
	for i in 3000:
		await RenderingServer.frame_post_draw
		if _solver == null:
			continue
		if _force != &"" and not _solver.is_acting():
			_solver.play_action(_force)
		# One frame as each attack starts, so the zones are visible with the wind-up beginning.
		if _solver.action != last_act:
			last_act = _solver.action
			if _solver.is_acting():
				await RenderingServer.frame_post_draw
				_save("%02d_%s_windup" % [shots, last_act])
				shots += 1
				want_impact = true
		# And one AT CONTACT, which is the frame that answers the question.
		if want_impact and _solver.is_acting() 				and _solver.action_t >= _solver.action_time(_solver.action, &"strike"):
			want_impact = false
			await RenderingServer.frame_post_draw
			_save("%02d_%s_impact" % [shots, last_act])
			shots += 1
		if shots >= 10:
			break
	# And a last one whatever happened, so a run where nothing attacked still produces a picture of
	# the zones -- "it did nothing" is itself the thing being reported.
	await RenderingServer.frame_post_draw
	_save("%02d_final" % shots)
	print("[AREAS] %d frames written to %s" % [shots + 1, _shot_dir])
	print("[AREAS] beats over the whole run: %s" % str(_beats))
	get_tree().quit()


func _save(tag: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/areas_%s.png" % [_shot_dir, tag])
	var sz: Vector2 = _solver.strike_zone()
	var land := _solver.predicted_impact() if _solver.is_acting() else Vector3.ZERO
	var disc := _telegraph()
	var gap := -1.0
	if disc != null and _solver.is_acting():
		gap = Vector3(disc.global_position.x - land.x, 0.0, disc.global_position.z - land.z).length()
	print("[AREAS] %-22s action=%-11s t=%.2f zone=%s strike=%.2f..%.2f disc-vs-landing=%.2f"
			% [tag, _solver.action if _solver.action != &"" else "-", _solver.action_t,
			["STRIKE", "TURN", "REPOSITION", "WRONG"][_solver.zone], sz.x, sz.y, gap])
	# DOES THE ZONE DESCRIBE WHERE THE MACE ACTUALLY GOES? The zone is drawn as a distance from the
	# BODY, but the reach it is built from is solved from the SHOULDER. Conflating those makes the
	# ring short by however far the shoulder sits from the body centre -- which is exactly what
	# "the yellow area is too small and the mace lands outside it" looks like.
	var body: Vector3 = _solver.global_position
	var g := _solver.grip_node()
	if g == null:
		return
	var head: Vector3 = g.global_position + g.global_basis.y.normalized() * _solver.weapon_length
	var hinge := body
	if _solver.arm_ik != null:
		var pts: Array = _solver.arm_ik.bone_positions()
		var ib: int = _solver.bone("RightShoulder")
		if ib >= 0 and ib < pts.size():
			hinge = pts[ib]
	var d_body := Vector2(head.x - body.x, head.z - body.z).length()
	var d_hinge := Vector2(head.x - hinge.x, head.z - hinge.z).length()
	var sh_off := Vector2(hinge.x - body.x, hinge.z - body.z).length()
	print("[AREAS]     head y %.2f | flat from BODY %.2f | from SHOULDER %.2f | shoulder %.2f ahead of body | zone %.2f..%.2f"
			% [head.y, d_body, d_hinge, sh_off, sz.x, sz.y])
	if disc != null:
		var d_disc := Vector2(disc.global_position.x - body.x, disc.global_position.z - body.z).length()
		print("[AREAS]     disc sits %.2f from body, head lands %.2f from body -- they are %.2f apart"
				% [d_disc, d_body, gap])


## The ogre, found late. Enemies are often spawned after the scene loads, so looking once in _ready
## finds nothing and the overlay silently never draws.
func _find_ogre() -> void:
	if is_instance_valid(_ogre) and _solver != null and is_instance_valid(_solver):
		return
	if not ogre_path.is_empty():
		var n := get_node_or_null(ogre_path)
		if n != null:
			_solver = n.find_child("OgreSolver", true, false) as OgreSolver
			_ogre = n as Node3D
			return
	# BY TYPE, not by group or by path. There is no "enemies" group in this project and the body
	# does not expose the solver as a property -- enemy.gd finds it with find_child("OgreSolver")
	# and keeps it private, so the only reliable handle is the node itself.
	_solver = _first_solver(get_tree().root)
	if _solver == null:
		return
	# The body is the first CharacterBody3D above it: that is what owns the telegraph disc and what
	# the zones are drawn around.
	var up: Node = _solver.get_parent()
	while up != null and not (up is CharacterBody3D):
		up = up.get_parent()
	_ogre = up as Node3D


func _first_solver(n: Node) -> OgreSolver:
	if n is OgreSolver:
		return n
	for c in n.get_children():
		var r := _first_solver(c)
		if r != null:
			return r
	return null


## Every damage and damage-receiving volume in the scene, cached. HitBox and HurtBox are CLASSES
## here, not groups, so there is no index to query -- and walking the whole tree every frame to
## draw four spheres is the wrong trade.
func _refresh_volumes() -> void:
	_hits.clear()
	_hurts.clear()
	_collect(get_tree().root)


func _collect(n: Node) -> void:
	if n is HitBox:
		_hits.append(n)
	elif n is HurtBox:
		_hurts.append(n)
	for c in n.get_children():
		_collect(c)


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not (e as InputEventKey).echo):
		return
	match (e as InputEventKey).physical_keycode:
		KEY_F6:
			mode = (mode + 1) % MODES.size()
			print("[CombatDebug] %s" % MODES[mode])
		KEY_F7:
			frozen = not frozen
			print("[CombatDebug] %s" % ("FROZEN" if frozen else "live"))


## Drawn in _process, not _physics_process. The solver ticks on physics and the weapon is placed in
## _process, so drawing on the visual frame is the only moment both are the values being rendered --
## the same reason every measurement in this system is taken after frame_post_draw.
func _process(dt: float) -> void:
	# ONE SWITCH ABOVE ALL OF THEM. F8 is meant to be a clean look at the game, and an overlay that
	# ignored it would make the switch pointless -- this is the loudest thing on the screen.
	var dbg := get_node_or_null("/root/Dbg")
	if dbg != null and bool(dbg.clean):
		(_mesh_node.mesh as ImmediateMesh).clear_surfaces()
		if _label:
			_label.visible = false
		for m in _marks:
			m.visible = false
		return
	if _label:
		_label.visible = mode > 0
	if frozen:
		return
	_find_ogre()
	# Volumes are created and freed as fights happen (the mace's hitbox is built in code, the
	# telegraph disc comes and goes), so the list is refreshed on a slow timer rather than assumed.
	_rescan -= dt
	if _rescan <= 0.0:
		_rescan = 0.5
		if mode >= 3:
			_refresh_volumes()
	var mesh := _mesh_node.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if mode == 0 or _solver == null or not _solver.is_ready():
		if _label:
			_label.text = ""
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_zones(mesh)
	if mode >= 2:
		_draw_impact(mesh)
	if mode >= 3:
		_draw_volumes(mesh)
	if mode >= 4:
		_draw_weapon(mesh)
	mesh.surface_end()
	if _label:
		_label.text = _readout()


# ---------------------------------------------------------------------------------------------
# The areas
# ---------------------------------------------------------------------------------------------

## WHERE EACH ATTACK CAN REACH, body-local.
##
## Body-local is the whole point, and the reason this is worth drawing rather than printing: the
## rings turn with the ogre, so watching them swing round as it faces you IS the explanation of why
## it cannot hit something standing behind its shoulder.
func _draw_zones(mesh: ImmediateMesh) -> void:
	var o: Vector3 = _solver.global_position + Vector3.UP * 0.04
	var fwd: Vector3 = _solver.forward()
	var tn: OgreTuning = _solver.tuning
	var lim: float = deg_to_rad(tn.strike_yaw)
	var sz: Vector2 = _solver.strike_zone()

	# HOW LONG THE OGRE HAS LEFT, which is what sizes the outer two bands. Idle, it is shown as a
	# whole wind-up's worth, so the shapes mean "what it could do if it started now".
	var left: float = _solver.aim_time_budget()
	var turn_budget: float = _solver.yaw_rate(_solver.speed) * tn.aim_turn_boost * left
	var step_budget: float = tn.aim_shuffle * left
	var wide: float = lim + turn_budget

	# The turn band reaches in and out by the lunge as well as round the sides -- see the solver's
	# zone_of. Drawn the same way it is tested, or the picture is describing a different rule.
	var lunge: float = _solver.turn_reach_bonus()
	var t_in: float = maxf(sz.x - lunge, 0.0)
	var t_out: float = sz.y + lunge
	_place_marks(sz, t_in, t_out, maxf(sz.x - step_budget, 0.0), sz.y + step_budget, fwd, o)

	# BLUE -- rotation AND positioning. It has to carry its body there: step, or run. Drawn first
	# and outermost so the two tighter bands read as being inside it.
	_wedge(mesh, o, fwd, maxf(sz.x - step_budget, 0.0), sz.y + step_budget, wide, C_REPOSITION)
	# ORANGE -- rotation only. The right distance already; it just has to come round to face you.
	_wedge(mesh, o, fwd, t_in, t_out, wide, C_TURN)
	# YELLOW -- the arm on its own. Nothing else about the ogre moves.
	_wedge(mesh, o, fwd, sz.x, sz.y, lim, C_STRIKE)

	# The kick's own reach, and how far it will close rather than give up.
	_arc(mesh, o, fwd, _solver.kick_zone().y, -PI, PI, C_KICK)
	_arc(mesh, o, fwd, tn.advance_max, -lim, lim, Color(C_ADVANCE.r, C_ADVANCE.g, C_ADVANCE.b, 0.5))
	# Which way it is facing, so a band drawn off to one side reads as a facing and not a bug.
	_line(mesh, o, o + fwd * sz.y, Color(C_STRIKE.r, C_STRIKE.g, C_STRIKE.b, 0.5))

	if _solver.is_acting():
		_cross(mesh, _solver.aim_point, 0.3, C_AIM)


## An annulus segment: two arcs and the two spokes that close them.
func _wedge(mesh: ImmediateMesh, o: Vector3, fwd: Vector3, r0: float, r1: float, half: float,
		c: Color) -> void:
	if r1 <= 0.01:
		return
	var a := clampf(half, 0.0, PI)
	_arc(mesh, o, fwd, r0, -a, a, c)
	_arc(mesh, o, fwd, r1, -a, a, c)
	for sgn in [-1.0, 1.0]:
		var d := fwd.rotated(Vector3.UP, sgn * a)
		_line(mesh, o + d * r0, o + d * r1, c)


func _draw_impact(mesh: ImmediateMesh) -> void:
	if not _solver.is_acting():
		return
	# ONLY FOR ATTACKS THAT ACTUALLY LAND A BLOW SOMEWHERE. predicted_impact() solves the SWING'S
	# geometry and answers with a point on the floor whatever is running, so during a rock throw it
	# drew a confident pink circle out to one side of a creature that was not swinging at anything.
	# An overlay that draws a meaningless number is worse than one that draws nothing -- it is the
	# same failure as a telegraph that lies, one layer up.
	var act2: ActionSpec = _solver.spec(_solver.action)
	if act2 == null or not act2.is_attack or not (act2.kick_foot >= 0 or act2.mace_leads):
		return
	var aim: Vector3 = _solver.aim_point
	var land: Vector3 = _solver.predicted_impact()
	_cross(mesh, aim, 0.30, C_AIM)
	_ring(mesh, aim, 0.30, C_AIM)

	# The landing place, drawn at the size of the thing that arrives -- the mace head, not some
	# larger disc chosen for readability. A warning bigger than the blow is its own kind of lie.
	var head_r: float = _solver.tuning.mace_hit_radius
	if _solver.action == &"kick":
		head_r = _solver.tuning.kick_hit_radius
		land = _solver.kick_point
	_cross(mesh, land, 0.45, C_LAND)
	_ring(mesh, land, head_r, C_LAND)

	# What the ground telegraph is actually promising, read off the live disc rather than
	# recomputed -- the point is to catch the two disagreeing, so asking the same function twice
	# would defeat it.
	var disc := _telegraph()
	if disc != null:
		var at: Vector3 = disc.global_position
		var r: float = float(disc.get("radius")) if disc.get("radius") != null else 0.0
		_ring(mesh, at, maxf(r, 0.05), C_PROMISE)
		_cross(mesh, at, 0.25, C_PROMISE)
		var gap := Vector3(at.x - land.x, 0.0, at.z - land.z).length()
		if gap > LIE_SLACK:
			# THE LIE, drawn as a line you cannot miss. Rule 10 of the architecture doc says the
			# telegraph and the blow must be the same equation; this is what it looks like when
			# they are not.
			_line(mesh, at + Vector3.UP * 0.05, land + Vector3.UP * 0.05, C_LIE)
			_line(mesh, at + Vector3.UP * 0.05, at + Vector3.UP * 0.9, C_LIE)
			_line(mesh, land + Vector3.UP * 0.05, land + Vector3.UP * 0.9, C_LIE)

	# The arc the head sweeps, when asked for. Big, and it hides the small shapes, so it is off by
	# default -- but it is the only way to see the swing PLANE, which has been wrong twice.
	if show_swing_ring:
		_swing_ring(mesh)


## EVERY VOLUME THAT CAN HURT SOMEONE, at its live position.
##
## Drawn from the nodes themselves rather than from the numbers that built them, because the
## failure worth catching is a volume that is not where its owner thinks it is.
func _draw_volumes(mesh: ImmediateMesh) -> void:
	for h in _hits:
		if is_instance_valid(h):
			_shape_of(mesh, h, C_HIT if _is_live(h) else Color(C_HIT.r, C_HIT.g, C_HIT.b, 0.28))
	for h in _hurts:
		if is_instance_valid(h):
			_shape_of(mesh, h, Color(C_HURT.r, C_HURT.g, C_HURT.b, 0.55))


## THE WEAPON AND WHAT HOLDS IT: the mace axis, the two grip points on it, and the palms that are
## supposed to be at them. A palm drawn away from its point is a grip that has come off.
func _draw_weapon(mesh: ImmediateMesh) -> void:
	var g := _solver.grip_node()
	if g != null:
		var butt: Vector3 = g.global_position
		var head: Vector3 = butt + g.global_basis.y.normalized() * _solver.weapon_length
		_line(mesh, butt, head, C_WEAPON)
		_dot(mesh, _solver.grip_world(), 0.16, C_GRIP_R)
		_dot(mesh, _solver.off_grip_world(), 0.16, C_GRIP_L)
	if _solver.arm_ik != null:
		for side in 2:
			var palm: Vector3 = _solver.arm_ik.palm_position(side)
			if palm != Vector3.ZERO:
				_dot(mesh, palm, 0.10, C_GRIP_R if side == 1 else C_GRIP_L)
	for i in 2:
		var f = _solver.feet[i]
		_cross(mesh, f.target, 0.20, C_FOOT)


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

## The live telegraph disc, or null. Read off the body by name because it is the body's private
## business; this overlay is a spectator and must not become a reason to widen that API.
func _telegraph() -> Node3D:
	if not is_instance_valid(_ogre):
		return null
	var a = _ogre.get("_slam_area")
	return a if (a != null and is_instance_valid(a)) else null


## Is this damage volume's window actually open? A hitbox is monitoring permanently and gates on its
## own `_active`, so "exists" and "will hurt you right now" are different questions.
func _is_live(h: Node) -> bool:
	var v = h.get("_active")
	return bool(v) if v != null else false


## Draw whatever collision shape a volume carries, at its real world transform.
func _shape_of(mesh: ImmediateMesh, area: Node, c: Color) -> void:
	for ch in area.get_children():
		var cs := ch as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var t := cs.global_transform
		if cs.shape is SphereShape3D:
			_sphere(mesh, t.origin, (cs.shape as SphereShape3D).radius, c)
		elif cs.shape is BoxShape3D:
			_box(mesh, t, (cs.shape as BoxShape3D).size, c)
		elif cs.shape is CapsuleShape3D:
			var cap := cs.shape as CapsuleShape3D
			var up := t.basis.y.normalized() * (cap.height * 0.5 - cap.radius)
			_sphere(mesh, t.origin + up, cap.radius, c)
			_sphere(mesh, t.origin - up, cap.radius, c)
		else:
			_dot(mesh, t.origin, 0.2, c)


## The ring the mace head sweeps this swing, in the swing's own plane. Reconstructed from the same
## hinge and radius the solver reports, so a plane that is wrong is visibly wrong.
func _swing_ring(mesh: ImmediateMesh) -> void:
	var d: Dictionary = _solver.swing_dbg
	if d.is_empty():
		return
	var hinge := Vector3(_solver.global_position.x, float(d.get("hinge_y", 0.0)),
			_solver.global_position.z)
	var r: float = float(d.get("radius", 0.0))
	if r <= 0.01:
		return
	var to := _solver.aim_point - hinge
	to.y = 0.0
	if to.length() < 0.01:
		return
	var out := to.normalized()
	var up := Vector3.UP.rotated(out.cross(Vector3.UP).normalized(),
			deg_to_rad(_solver.tuning.swing_plane))
	var prev := hinge + up * r
	for i in range(1, 41):
		var a: float = TAU * float(i) / 40.0
		var at := hinge + (up * cos(a) + out * sin(a)) * r
		_line(mesh, prev, at, Color(C_LAND.r, C_LAND.g, C_LAND.b, 0.35))
		prev = at


func _readout() -> String:
	var sz: Vector2 = _solver.strike_zone()
	var kz: Vector2 = _solver.kick_zone()
	var d := 0.0
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		var to := p.global_position - _solver.global_position
		to.y = 0.0
		d = to.length()
	var zn: String = ["STRIKE", "TURN", "REPOSITION", "WRONG"][_solver.zone]
	var act: String = "-" if _solver.action == &"" else "%s %.2f/%.2f" \
			% [_solver.action, _solver.action_t, _solver.action_len]
	var lie := "-"
	var disc := _telegraph()
	if disc != null and _solver.is_acting():
		var land: Vector3 = _solver.predicted_impact()
		lie = "%.2f m" % Vector3(disc.global_position.x - land.x, 0.0,
				disc.global_position.z - land.z).length()
	# THE KEY IS PART OF THE TOOL. Six colours of ring mean nothing without one, and a legend kept
	# anywhere but beside the drawing is a legend that goes stale.
	var key := "M1 yellow = arm alone     M2 orange = + rotation and lunge     M3 blue = + stepping
"
	key += "outside M3 = it cancels    pale blue ring = kick reach    PINK = where the head LANDS
"
	key += "red ring = what the disc PROMISED (yellow bars = they disagree)    red hurts, green gets hurt"
	var head := "F6 %s   F7 %s" % [MODES[mode], "FROZEN" if frozen else "live"]
	var geo := "strike %.2f..%.2f m   kick 0..%.2f m   player %.2f m -> %s" % [sz.x, sz.y, kz.y, d, zn]
	var st := "action %s   disc vs landing: %s" % [act, lie]
	return head + "
" + geo + "
" + st + "
" + key


## NAMES ON THE GROUND. A ring is only a ring until it is labelled, and "why did it do that" is much
## easier to answer when the band the player was standing in says M2 on the floor next to them.
##
## Label3D rather than anything drawn into the mesh, because it billboards and stays legible from
## the fight camera's angle -- and the whole point is to read it while playing, not while staring
## straight down at it.
func _build_marks() -> void:
	for i in MARKS.size():
		var l := Label3D.new()
		# PAINTED ON THE GROUND, not held up facing the camera. A billboarded label is a thing
		# floating in the scene at a size that means nothing; lying flat in perspective it belongs to
		# the band it names, shrinks with distance the way the band does, and can be read as a
		# marking on the floor rather than as UI stuck over the top of the game.
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.double_sided = true
		l.pixel_size = 0.012
		l.font_size = 48
		l.outline_size = 12
		l.modulate = MARK_COLS[i]
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.top_level = true
		add_child(l)
		_marks.append(l)


## Park a name in the middle of each band, out along the way the ogre faces. Placed where the band
## IS rather than at a fixed offset, so a band that grows or shrinks takes its label with it and the
## label cannot end up describing the wrong ring.
func _place_marks(sz: Vector2, turn_in: float, turn_out: float, rep_in: float, rep_out: float,
		fwd: Vector3, o: Vector3) -> void:
	var mid: Array[float] = [
		(sz.x + sz.y) * 0.5,
		(turn_out + sz.y) * 0.5,
		(rep_out + turn_out) * 0.5,
	]
	# Fanned apart so three labels on the same spoke do not sit on top of one another.
	var bear: Array[float] = [0.0, -0.42, 0.42]
	for i in _marks.size():
		var l: Label3D = _marks[i]
		l.visible = mode > 0
		l.text = MARKS[i]
		var at := o + fwd.rotated(Vector3.UP, bear[i]) * mid[i] + Vector3.UP * 0.02
		# Face up, and read outward along the ogre's own facing, so the markings turn with the bands
		# they belong to instead of staying fixed to the world while the bands swing round.
		# Reading ACROSS the band rather than along it: laid out radially the words point away from
		# the ogre and you have to tilt your head to read them, which defeats the purpose.
		var yaw := atan2(fwd.x, fwd.z) - PI * 0.5
		l.global_transform = Transform3D(
				Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5), at)


func _build_legend() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40                              # per docs/architecture.md: dev panels live at 40
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(14, 190)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)


# ---------------------------------------------------------------------------------------------
# Primitives. Lines only -- an ImmediateMesh of PRIMITIVE_LINES is the cheapest thing that can
# draw every shape here, and wireframe is what you want on top of a lit scene anyway.
# ---------------------------------------------------------------------------------------------

func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Color) -> void:
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(b)


func _dot(mesh: ImmediateMesh, at: Vector3, r: float, c: Color) -> void:
	_line(mesh, at - Vector3.RIGHT * r, at + Vector3.RIGHT * r, c)
	_line(mesh, at - Vector3.UP * r, at + Vector3.UP * r, c)
	_line(mesh, at - Vector3.BACK * r, at + Vector3.BACK * r, c)


func _cross(mesh: ImmediateMesh, at: Vector3, r: float, c: Color) -> void:
	_line(mesh, at - Vector3.RIGHT * r, at + Vector3.RIGHT * r, c)
	_line(mesh, at - Vector3.FORWARD * r, at + Vector3.FORWARD * r, c)
	_line(mesh, at, at + Vector3.UP * r * 2.0, c)


## A ring on the ground.
func _ring(mesh: ImmediateMesh, at: Vector3, r: float, c: Color) -> void:
	_arc(mesh, at + Vector3.UP * 0.03, Vector3.FORWARD, r, -PI, PI, c)


## An arc on the ground, swept about `fwd` from a0 to a1.
func _arc(mesh: ImmediateMesh, o: Vector3, fwd: Vector3, r: float, a0: float, a1: float,
		c: Color) -> void:
	if r <= 0.01:
		return
	var steps := 32
	var prev := o + fwd.rotated(Vector3.UP, a0) * r
	for i in range(1, steps + 1):
		var a: float = a0 + (a1 - a0) * (float(i) / float(steps))
		var at := o + fwd.rotated(Vector3.UP, a) * r
		_line(mesh, prev, at, c)
		prev = at


## Three great circles. Enough to read a sphere's size and centre, and far cheaper than a real one.
func _sphere(mesh: ImmediateMesh, at: Vector3, r: float, c: Color) -> void:
	var steps := 20
	for axis in 3:
		var prev := Vector3.ZERO
		for i in range(steps + 1):
			var a: float = TAU * float(i) / float(steps)
			var v: Vector3
			match axis:
				0: v = Vector3(cos(a), sin(a), 0.0)
				1: v = Vector3(cos(a), 0.0, sin(a))
				_: v = Vector3(0.0, cos(a), sin(a))
			var p := at + v * r
			if i > 0:
				_line(mesh, prev, p, c)
			prev = p


func _box(mesh: ImmediateMesh, t: Transform3D, size: Vector3, c: Color) -> void:
	var h := size * 0.5
	var pts: Array[Vector3] = []
	for i in 8:
		pts.append(t * Vector3(
				h.x if (i & 1) else -h.x,
				h.y if (i & 2) else -h.y,
				h.z if (i & 4) else -h.z))
	for e in [[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3], [2, 6],
			[3, 7], [4, 5], [4, 6], [5, 7], [6, 7]]:
		_line(mesh, pts[e[0]], pts[e[1]], c)

class_name Sword
extends Node3D
## The player's weapon component: a blade mesh + a HitBox that is only live during the swing's
## "active frames". The Attack STATE decides *when* to swing; the Sword owns *how* (the visual arc
## + the precise hitbox on/off timing). That split keeps timing data next to the weapon, so a
## heavier weapon later just ships different numbers.

@export var glow_time := 0.35      ## how long the blade emissive pulse lasts per swing

## CONTACT FEEL -- the "hitstop" (a.k.a. hitlag / impact freeze): on a landed blow, time itself is
## slowed for a moment so the blade reads as going THROUGH something rather than past it.
##
## `stop` is how long the freeze lasts, `scale` is how far time slows inside it (LOWER is deeper;
## 1.0 would be no slowdown at all), `shake` is the camera kick. The finisher is longer and deeper
## than an opener because a combo's full stop should feel like one.
##
## Every one of these is multiplied by the TARGET's heft (Enemy.heft), so the same swing reads
## heavier through an ogre than through a swarmling -- these numbers are the person-sized baseline.
@export_group("Contact feel")
@export_range(0.0, 0.25, 0.005) var stop_open := 0.07
@export_range(0.02, 1.0, 0.01) var stop_open_scale := 0.12
@export_range(0.0, 0.8, 0.01) var shake_open := 0.14
@export_range(0.0, 0.25, 0.005) var stop_finisher := 0.10
@export_range(0.02, 1.0, 0.01) var stop_finisher_scale := 0.08
@export_range(0.0, 0.8, 0.01) var shake_finisher := 0.22
## A ceiling on the heft-scaled freeze, so a heavy target reads as weight and never as a hang.
@export_range(0.05, 0.4, 0.005) var stop_max := 0.20
@export_group("")
@export var trail_fade := 0.35     ## fraction of the swing the streak spends fading out
## Extra two-centimetre skin around the existing swept blade, not the victim.
@export_range(0.0,.04,.005) var contact_margin := .02

@onready var _hitbox: HitBox = $HitBox
@onready var _blade: Node3D = $Blade
@onready var _blade_mesh: MeshInstance3D = $Blade/BladeMesh
@onready var _guard: Node3D = $Blade/Guard
@onready var _trail: BladeTrail = $Blade/Trail

var _blade_mat: StandardMaterial3D
var _window_id:=0
var _previous_blade:=Transform3D.IDENTITY
var _sweep_ready:=false
var _contact_shape:=CapsuleShape3D.new()
var _swing_step := 0     ## which combo swing is in flight — the finisher's contact hits harder
var hand_driven := false ## blade rides the hand socket; the swing arc comes from the clip.
                         ## The HitBox does NOT follow — it stays player-anchored so the
                         ## combat hit zone is identical either way.

func _ready() -> void:
	_hitbox.dealt_hit.connect(_on_dealt_hit)
	var m := _blade_mesh.get_active_material(0)
	if m is StandardMaterial3D:
		_blade_mat = (m as StandardMaterial3D).duplicate()
		_blade_mesh.set_surface_override_material(0, _blade_mat)
	_fit_trail_to_blade()


## Stretch the trail ribbon across the blade, MEASURED from the mesh rather than hard-coded, so a
## longer sword or a dagger gets a correctly sized streak with no numbers to edit. The blade's
## long axis is simply the largest axis of its AABB; the two end-cap centres become the ribbon's
## ends. (Children are ready before their parent, so the trail has already built itself here.)
func _fit_trail_to_blade() -> void:
	var box := _blade_mesh.get_aabb()
	var axis := 0
	if box.size.y > box.size[axis]:
		axis = 1
	if box.size.z > box.size[axis]:
		axis = 2
	var half := Vector3.ZERO
	half[axis] = box.size[axis] * 0.5
	var to_blade := _blade_mesh.transform                 # BladeMesh space -> Blade space
	_trail.span(to_blade * (box.get_center() - half), to_blade * (box.get_center() + half))

# On a landed hit: a quick hitstop + a small camera shake so the strike has weight.
# `applied` gates all of it: a blow the target absorbed (i-frames, a future blocking enemy)
# changed nothing, and feedback that says otherwise is a lie about the fight.
func _on_dealt_hit(target: Node, _pos: Vector3, applied: int) -> void:
	if applied <= 0:
		return
	var fighter: Node=get_parent()
	while fighter!=null and not fighter is Player:
		fighter=fighter.get_parent()
	# The defender already gives feedback for damage taken. An AI sword must not
	# also fire the player's successful-hit feedback for that same impact.
	if fighter is Player and not fighter.is_input_driven(): return
	# Through the facade, and through its CONTACT door specifically — the layer whose whole point
	# is that "did this fire on contact or on a beat" is answerable by reading one file.
	# The FINISHER (step 2 of the chain, atk_c — already its fastest, hardest swing) freezes
	# longer and deeper than the openers: a combo's full stop should feel like one. The lunge
	# passes step 0 on purpose and reads as an opener.
	# WEIGHTED BY WHAT WAS HIT. The swing already says how hard it swung; heft says what it went
	# through. Both halves matter: without the first every blow reads the same, and without the
	# second a four-metre ogre and a swarmling froze the screen for an identical 70 ms, which is
	# the "loudest cue carries no information" bug this layer was built to end -- one level up.
	# Duration is capped so a heavy target reads as weight and never as the game hanging.
	var heft := _target_heft(target)
	if _swing_step >= 2:
		CombatFeedback.contact_landed(minf(stop_finisher * heft, stop_max),
				clampf(stop_finisher_scale / heft, 0.02, 1.0), shake_finisher * heft)
	else:
		CombatFeedback.contact_landed(minf(stop_open * heft, stop_max),
				clampf(stop_open_scale / heft, 0.02, 1.0), shake_open * heft)
	_maybe_fear(target)


## How meaty the thing we just hit is. Walked up from the HURTBOX exactly the way _maybe_fear walks
## for fear(), because that is the node dealt_hit hands us. Anything that does not declare a heft
## is a person, which is the old behaviour unchanged.
func _target_heft(target: Node) -> float:
	var n := target
	while n != null:
		if n.get("heft") != null:
			return clampf(float(n.get("heft")), 0.5, 2.5)
		n = n.get_parent()
	return 1.0


## DRAMA'S COMBAT FACE. A rolled chance, per target, to send whoever was hit running.
##
## This is the right hook and the neighbouring ones are not: HitBox._try_hit guarantees exactly one
## dealt_hit per target per activation, so a swing that catches three enemies rolls three times and
## a swing that catches one rolls once. Rolling in the Attack state instead would give one verdict
## for the whole arc.
##
## `target` is the HURTBOX, not the body — the same walk-up player.gd uses for parry staggers. And
## it arrives AFTER the damage resolved, so the thing we are about to frighten may already be dead;
## Enemy.fear guards its own DEAD state, and a swarmling has no fear() at all, which is the correct
## no-op rather than a special case.
func _maybe_fear(target: Node) -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits == null:
		return
	var chance: float = traits.fear_chance()
	if chance <= 0.0 or randf() >= chance:
		return
	var n := target
	while n != null:
		if n.has_method("fear"):
			n.fear(2.0)
			return
		n = n.get_parent()

## Called by the Attack state at the START of each combo swing: the wind-up tell (blade glow) and
## the swing streak. The swing ARC itself comes from the attack CLIP (hand_driven); timing is the
## Attack state's, which is why it passes `dur` — the streak has to die with THIS swing, and every
## clip in the chain has a different length after the wind-up compression in player.gd.
func begin_swing(step: int, dur := 0.4, directional := false) -> void:
	_swing_step = step
	# AI windups retain the blade sweep; show a short trail at release.
	if directional:
		_trail.burst(minf(dur, .22), .5)
		return
	_glow_blade()
	_trail.burst(dur, trail_fade)

## Open the damage window for `dur` seconds — called by the Attack state at the swing's CONTACT
## point. The slash crescent spawns HERE, in the same frame the hitbox goes live, so the VFX and
## the damage are always in sync (it used to fire at the wind-up, ~0.4s early). `flip` mirrors
## the crescent per combo step. Each call re-activates, so every swing can land its own hit.
## `dmg` is written just before activate() because HitBox reads `damage` once per target inside the
## window and activate() clears its already-hit list — so one assignment here governs exactly this
## swing and nothing else. It is a parameter rather than something the caller pokes onto the hitbox
## so that the value cannot leak into the NEXT swing: every call site passes it, every swing sets it.
## `dir` is the SwingDir this blow was thrown from, or SwingDir.NONE for the click combo, which has
## no direction to speak of. It rides the hitbox exactly like `finisher` and `knockback` do, and
## for exactly the same reason — take_damage's shared signature has no room for it.
## Directional swings use the swept visible blade; legacy combos retain the box.
func hit(dur := 0.12, flip := false, dmg := 1, dir := SwingDir.NONE) -> void:
	if dir == SwingDir.NONE or dir in [SwingDir.LEFT, SwingDir.RIGHT]:
		_spawn_slash(dir == SwingDir.LEFT if dir != SwingDir.NONE else flip)
	_window_id+=1
	var window:=_window_id
	_hitbox.manual_contact=dir!=SwingDir.NONE
	_sweep_ready=false
	_hitbox.damage = dmg
	if _hitbox.has_meta("contact_point"): _hitbox.remove_meta("contact_point")
	# Written EVERY swing, including the NONE, so a directional strike's claim can never linger on
	# the hitbox and make the next click-combo swing look directional to a defender.
	_hitbox.set_meta("swing_dir", dir)
	# The FINISHER travels on the hitbox the same way knockback does — a meta the victim reads,
	# because take_damage's shared signature has no room for it. Written per swing, so a combo
	# ender's flag can never leak into the next opener. The knockback meta is the swing's
	# WEIGHT: a kill by the finisher throws the ragdoll harder than a kill by an opener (F=ma
	# reads off this same number everywhere — living shoves and corpses alike).
	_hitbox.set_meta("finisher", _swing_step >= 2)
	_hitbox.set_meta("recovery_step", _swing_step == 1)
	_hitbox.set_meta("knockback", 9.0 if _swing_step >= 2 else 5.0)
	_hitbox.activate()
	get_tree().create_timer(dur).timeout.connect(func():
		if window==_window_id: cancel_swing())

func cancel_swing() -> void:
	_trail.stop(.06)
	_window_id+=1
	_hitbox.deactivate()
	_sweep_ready=false

func blade_segment() -> PackedVector3Array:
	var box := _blade_mesh.get_aabb()
	var half := Vector3(0,0,box.size.z*.5)
	return PackedVector3Array([_blade_mesh.global_transform*(box.get_center()+half), _blade_mesh.global_transform*(box.get_center()-half)])

func _physics_process(_delta:float) -> void:
	if not _hitbox._active or not _hitbox.manual_contact: return
	var current:=_blade_mesh.global_transform
	if not _sweep_ready: _previous_blade=current; _sweep_ready=true
	var bounds:=_blade_mesh.get_aabb()
	var start:=bounds.get_center()+Vector3(0,0,bounds.size.z*.5)
	var tip:=bounds.get_center()-Vector3(0,0,bounds.size.z*.5)
	var distance:=maxf((_previous_blade*tip).distance_to(current*tip),(_previous_blade*start).distance_to(current*start))
	var steps:=clampi(ceili(distance/.08),1,16)
	var space:=get_world_3d().direct_space_state
	for step in range(steps+1):
		if not _hitbox._active: break
		var pose:=_previous_blade.interpolate_with(current,float(step)/steps)
		var a:=pose*start
		var b:=pose*tip
		if _try_blade_interception(a,b): break
		_contact_shape.radius=.09+contact_margin
		_contact_shape.height=a.distance_to(b)+2.0*_contact_shape.radius
		var q:=PhysicsShapeQueryParameters3D.new()
		q.shape=_contact_shape
		q.transform=Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*.5)
		q.collision_mask=_hitbox.collision_mask
		q.collide_with_areas=true
		q.collide_with_bodies=false
		for result in space.intersect_shape(q,12):
			var area:Area3D=result.collider
			var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP,area.global_position,1)
			var wielder:Node=get_parent().get_parent()
			var exclusions:Array[RID]=[]
			if wielder is CollisionObject3D: exclusions.append(wielder.get_rid())
			if area.get_parent() is CollisionObject3D: exclusions.append(area.get_parent().get_rid())
			ray.exclude=exclusions
			if space.intersect_ray(ray).is_empty(): _hitbox._try_hit(area)
	_previous_blade=current

func _try_blade_interception(a: Vector3, b: Vector3) -> bool:
	var wielder := get_parent().get_parent() as Player
	if wielder == null: return false
	var incoming: int = _hitbox.get_meta("swing_dir",SwingDir.NONE)
	for candidate in get_tree().get_nodes_in_group(wielder.target_group):
		var defender := candidate as Player
		if defender == null or not defender.sword or not defender.health.is_alive(): continue
		if defender.global_position.distance_squared_to(wielder.global_position) > 9.0: continue
		var state: State = defender.get_node("StateMachine").current_state
		if not state or not state.has_method("blocks") or not state.blocks(incoming): continue
		if defender.stamina <= 0 or not defender._is_frontal_hit(_hitbox): continue
		var blade := defender.sword.blade_segment()
		var pair := Geometry3D.get_closest_points_between_segments(a,b,blade[0],blade[1])
		if pair[0].distance_to(pair[1]) > .14: continue
		var ray := PhysicsRayQueryParameters3D.create(wielder.global_position+Vector3.UP,defender.global_position+Vector3.UP,1)
		ray.exclude = [wielder.get_rid(),defender.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		_hitbox.set_meta("contact_point",(pair[0]+pair[1])*.5)
		_hitbox._try_hit(defender.get_node("HurtBox"))
		if not _hitbox._active: return true
	return false

## Where the wielder's palm sits, in Blade-local space — the point the hand socket must be solved
## against. The GUARD is the crosspiece a hand grips under, so its centre is the anchor, pushed
## back along the blade's own axis (-Z is the blade, so +Z is down the handle) to the middle of
## the grip.
##
## MEASURED, not declared, and it replaces a hand-tuned (0.35, 0.1, 0.0) that lived in player.gd.
## That constant was missing its Z entirely, which put the hilt 19 cm from the palm on player2,
## 24 cm on player and 29 cm on player3 — the sword visibly floated past the hand on every body we
## have. A longer sword or a dagger now re-solves itself instead of needing that number re-guessed.
@export var grip_back := 0.09      ## metres from the guard down the handle to the palm centre

func grip_point() -> Vector3:
	return _guard.position + Vector3(0.0, 0.0, grip_back)


# --- The attack envelope, measured off the HitBox ---------------------------------------------
#
# Combat tuning kept re-guessing these. "How far can I hit from" is not a matter of taste, it is
# the damage volume's forward extent, and it is written down exactly once — in sword.tscn's
# CollisionShape3D. Target acquisition, the attack step and the distance study all read it from
# here, so retuning the box retunes the whole system instead of desynchronising it.
#
# HitBox is a child of the Sword ROOT, not of Blade: it is PLAYER-anchored and does not follow the
# visual blade's swing (see follow_grip). So these are distances from the player's centre, along
# the facing, which is exactly the frame gameplay reasons in.

var _reach := 0.0
var _half_width := 0.0
var _measured := false

## The authored box, kept so the Perception bonus is applied to a FIXED base rather than to whatever
## the box grew to last frame — otherwise the reach compounds every time it is read.
var _shape_node: CollisionShape3D
var _base_depth := 0.0             ## authored size.z
var _base_z := 0.0                 ## authored Shape.position.z
var _applied_bonus := -1.0         ## the bonus currently baked into the box; -1 = never applied


func _measure_envelope() -> void:
	_measured = true
	var shape_node := _hitbox.get_node_or_null("Shape") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return
	var s := shape_node.shape
	# THE SHAPE IS A SHARED SUB-RESOURCE of sword.tscn. Growing it in place would edit the resource
	# every instance of the scene points at — which is invisible today, with one player, and a
	# genuinely baffling bug the moment anything else carries a sword.
	if s is BoxShape3D:
		s = s.duplicate()
		shape_node.shape = s
	_shape_node = shape_node
	var half := Vector3.ZERO
	if s is BoxShape3D:
		half = (s as BoxShape3D).size * 0.5
		_base_depth = (s as BoxShape3D).size.z
		_base_z = shape_node.position.z
	elif s is SphereShape3D:
		half = Vector3.ONE * (s as SphereShape3D).radius
	elif s is CapsuleShape3D:
		var c := s as CapsuleShape3D
		half = Vector3(c.radius, c.height * 0.5, c.radius)
	# -Z is forward, so the far edge is the most negative Z the box covers.
	_reach = -(shape_node.position.z - half.z)
	_half_width = half.x


## How far in front of the player the damage volume ends, in metres.
##
## PERCEPTION MOVES THE BOX, not just this number. Adding the bonus to the return value alone would
## be a lie with teeth: contact_range() feeds target acquisition and the attack step, so the swing
## would turn toward an enemy, close on it, arrive exactly where the maths said — and pass straight
## through, because the damage volume never moved. That is the precise failure the attack step was
## written to eliminate, reintroduced through the front door.
func reach() -> float:
	if not _measured:
		_measure_envelope()
	_sync_reach_bonus()
	return _reach


## Re-cut the box whenever the bonus changes. Polled from reach() rather than pushed on a signal
## because reach() is already called at the top of every swing, and a boon taken mid-room has to
## take effect on the very next one — a cached value would hold last room's reach until something
## thought to invalidate it.
##
## Grows FORWARD only: the depth increases and the centre slides half that far along -Z, so the rear
## face stays exactly where it was. Growing symmetrically would extend the damage volume backwards
## through the player, who would start killing things behind them.
func _sync_reach_bonus() -> void:
	if _shape_node == null:
		return
	var box := _shape_node.shape as BoxShape3D
	if box == null:
		return
	var traits := get_node_or_null("/root/Traits")
	var bonus: float = traits.reach_bonus() if traits else 0.0
	if is_equal_approx(bonus, _applied_bonus):
		return
	_applied_bonus = bonus
	box.size.z = _base_depth + bonus
	_shape_node.position.z = _base_z - bonus * 0.5
	_reach = -(_shape_node.position.z - box.size.z * 0.5)


## Half the damage volume's width. With reach(), this is the swing's angular tolerance: a target
## further off-axis than half_width at its own distance is outside the box no matter how close it
## is. At full reach that is only about 28 degrees, which is why aiming by raw cursor misses.
func half_width() -> float:
	if not _measured:
		_measure_envelope()
	return _half_width


## Put the blade in the hand: its GRIP POINT lands exactly on `palm`, oriented by `basis`.
##
## Position is solved, not chased. The old version damped the whole transform toward the hand for
## "heft", which measured 0.25 m adrift in an idle and 0.66 m during a sprint — a hilt that far from
## the palm is not weight, it is a dropped sword. Heft now lives entirely in how the caller damps
## the BASIS (Player.sword_weight), where lag costs nothing but a little swing trail.
##
## The legacy box stays player-anchored. Directional queries follow this blade transform.
func set_grip(basis: Basis, palm: Vector3) -> void:
	_blade.global_transform = Transform3D(basis, palm - basis * grip_point())

# A bright emissive pulse along the blade = a cheap "slash" read.
func _glow_blade() -> void:
	if _blade_mat == null:
		return
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(0.7, 0.85, 1.0)
	var t := create_tween()
	t.tween_method(func(e: float): _blade_mat.emission_energy_multiplier = e, 3.5, 0.0, glow_time)

# A crescent slash arc that sweeps in front of the player each swing (mirrored per combo step).
func _spawn_slash(flip: bool) -> void:
	var scene := load("res://scenes/fx/slash.tscn")
	if scene == null:
		return
	var s := (scene as PackedScene).instantiate()
	s.flipped = flip
	s.outer_radius = clampf(reach(), 1.0, 1.7)
	add_child(s)
	(s as Node3D).position = Vector3(0.0, 0.8, 0.0)

## Closest point on the visible blade for this target, not a mesh-triangle hit.
func impact_sample(target: Vector3) -> Dictionary:
	var segment := blade_segment()
	var point := Geometry3D.get_closest_point_to_segment(target, segment[0], segment[1])
	var forward := -global_basis.z
	var direction := target - global_position
	direction.y = 0.0
	if direction.length_squared() < .001: direction = forward
	# Across-cut component gives lateral strikes a readable shoulder rotation.
	var lateral := global_basis.x * (-1.0 if _swing_step % 2 == 0 else 1.0)
	direction = (direction.normalized() + lateral * .45).normalized()
	return {"point": point, "direction": direction}

## Persistent warm glow while winding up; reset on every interruption.
func charge_feedback(amount: float) -> void:
	if _blade_mat:
		_blade_mat.emission = Color(1.0, .55, .12)
		_blade_mat.emission_energy_multiplier = amount * 3.0

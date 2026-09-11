class_name OgrePuppet
extends CharacterBody3D
## The ogre with a human driving it. Everything the real enemy will do except decide where to go.
##
## WHY A SEPARATE SCRIPT AT ALL. The solver's entire input contract is
## `tick(delta, velocity, is_on_floor(), yaw)` — three facts any CharacterBody3D already knows. So
## the AI and the keyboard are interchangeable, and that is the whole integration guarantee: when
## this becomes a real Enemy the animation code does not change, only the thing deciding the
## velocity. This file exists so that swap can be proven before the AI is written.
##
## THE TWO CLAMPS ARE THE POINT, and they are not dev conveniences — they belong to the creature and
## will move to enemy.gd verbatim:
##
##   ACCELERATION. `max_accel` is g*tan(12 deg) ~ 2.1 m/s^2, the lateral acceleration a heavy biped
##   can lean into. It means about a second of runway to reach walking speed and the same to stop.
##   The ogre COMMITS: you can bait a charge and step aside, and that is a mechanic rather than a
##   stat.
##
##   TURN RATE. enemy.gd faces its target with `1 - exp(-10 * delta)`, an effective ~570 deg/s.
##   For this creature that is roughly ten times too fast and it is the single loudest tell that a
##   big model is a small character scaled up. Turning is lateral acceleration, so the same lean
##   ceiling caps it: omega = a_max / v, about 55 deg/s at a walk. Flanking becomes readable.

@export var run_multiplier := 1.6
## Above zero this replaces the walk/run choice outright. The probe sweeps commanded speeds to check
## the gait law across its whole range, which "walk or run" cannot express.
@export var commanded_speed := 0.0

var drive := Vector3.ZERO          ## desired direction, unit length, set by the lab each frame
var want_run := false
var frozen := false                ## the lab's freeze key — stop integrating, keep rendering

const AREA_ATTACK := preload("res://scenes/fx/area_attack.tscn")
const THROWN_ROCK := preload("res://scenes/props/thrown_rock.tscn")

@onready var solver: OgreSolver = $OgreSolver
@onready var visuals: Node3D = $Visuals
@onready var hitbox: HitBox = $Visuals/AttackHitBox

## What the ogre is aiming at. The lab sets this to the player when one is spawned; without a target
## a throw just goes where the ogre is facing.
var target: Node3D:
	set(v):
		target = v
		solver.look_target = v

var _held: Rock
var _slam_area: AreaAttack

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	solver.action_event.connect(_on_action_event)
	set_notify_transform(false)
	hitbox.deactivate()


## THE SOLVER SAYS WHEN, THIS SAYS WHAT. Everything here is gameplay -- damage volumes, a ground
## slam that can hurt somebody, a rock leaving the hand. The follow-through that is purely animation
## (shake, hitstop, dust, the hip dropping under the blow) already happened inside the solver,
## because that is the blow landing rather than the game reacting to it.
##
## When this becomes a real Enemy the whole function moves to enemy.gd unchanged: it only ever
## touches components every enemy already has.
func _on_action_event(what: StringName, at: Vector3) -> void:
	match what:
		&"hit_open":
			# The solver arms its own weapon volume now; the body box steps in only when there is
			# no weapon volume to arm. Mirrors enemy.gd — this file's whole promise is that the
			# swap to a real Enemy changes nothing.
			if solver.strike_hitbox() == null:
				hitbox.activate()
		&"hit_close":
			hitbox.deactivate()
		&"slam_telegraph":
			_telegraph_slam(at)
		&"strike":
			# The driven disc detonates on this beat — mirrors enemy.gd; see _telegraph_slam.
			if is_instance_valid(_slam_area):
				_slam_area.detonate_now()
			if solver.action == &"rock_throw":
				_release_rock()
			elif solver.action == &"rock_lift":
				_grab_rock()


## The growing disc from the sketch. Spawned at the START of the wind-up rather than on impact, so
## it is a WARNING and not a report: it grows for exactly as long as the ogre takes to bring the
## mace down, and detonates on the frame the head lands. The player reads the circle, the circle is
## the animation's own clock, and the two cannot drift because one number feeds both.
func _telegraph_slam(at: Vector3) -> void:
	var spec := solver.spec(solver.action)
	if spec == null or spec.slam_radius <= 0.0:
		return
	var area := AREA_ATTACK.instantiate() as AreaAttack
	area.windup = maxf(spec.hit_at - solver.action_t, 0.05)
	area.radius = spec.slam_radius
	area.damage = spec.damage
	# Driven from the solver's own action clock, exactly as enemy.gd does — the disc freezes with
	# the aim hold and detonates on the strike beat instead of racing a wall-clock tween.
	area.driven = true
	get_parent().add_child(area)
	area.global_position = Vector3(at.x, global_position.y + 0.05, at.z)
	_slam_area = area


## Pick up the nearest loose rock, if one is in reach.
func _grab_rock() -> void:
	if _held != null:
		return
	var best: Rock
	var best_d := 6.5
	for r: Rock in get_tree().get_nodes_in_group("rock"):
		var d := global_position.distance_to(r.global_position)
		if d < best_d:
			best_d = d
			best = r
	if best == null:
		return
	_held = best
	_held.take(_hand(), solver.rock_hold)
	# Both hands are on the rock now. Stow the mace as well as dropping the carry pose -- a four
	# metre weapon still hanging off the fist while the ogre hefts a boulder reads as a bug.
	solver.carrying = &""
	solver.show_weapon(false)


## Let it go. A ballistic lob rather than a straight shot: the arc is the tell, and a rock you can
## see coming is a rock you can walk away from -- which is the difference between a threat and a
## tax on reaction time.
func _release_rock() -> void:
	if _held == null:
		return
	var from: Vector3 = _held.global_position
	var size := _held.visual_scale()
	_held.queue_free()
	_held = null
	solver.carrying = &"carry"
	solver.show_weapon(true)

	var rock := THROWN_ROCK.instantiate() as Projectile
	get_parent().add_child(rock)
	rock.global_position = from
	rock.shooter = self          # so a rock parried in the lab flies home, same as in the fight
	var m := rock.get_node_or_null("Model/Mesh") as MeshInstance3D
	if m:
		m.scale = size / 0.55
	var aim: Vector3 = target.global_position if target else 			global_position + solver.forward() * 14.0
	rock.setup_ballistic(aim, 2, rock.damage, Color(0.55, 0.53, 0.5))


## Where a carried thing rides. The weapon socket the solver already built, so a rock and the mace
## are held in the same place by construction.
func _hand() -> Node3D:
	var g := solver.grip_node()
	return g if g != null else visuals


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_drive_slam()
	var target_speed := commanded_speed if commanded_speed > 0.0 			else solver.walk_speed() * (run_multiplier if want_run else 1.0)
	var want := drive * target_speed

	# move_toward, not lerp: a real acceleration ceiling in m/s^2, so the runway is a distance you
	# can measure and design around rather than a smoothing constant nobody can picture.
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	planar = planar.move_toward(want, solver.tuning.max_accel * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()

	if planar.length() > 0.05:
		_face(planar, delta)

	# AFTER move_and_slide, always. The solver locks feet to world points, and a plant computed
	# against where the body HOPED to go rather than where it ended up is a plant that slides.
	# Root motion an action asked for -- the lunge into a slam. Added to velocity rather than
	# teleported, so the ogre still collides with the world on the way through.
	var push := solver.consume_root_motion()
	if push.length_squared() > 0.0:
		global_position += push

	solver.tick(delta, velocity, is_on_floor(), _visual_yaw())


## THE BODY YAW IS A WORLD FACT, same contract as enemy.gd:_visual_yaw(). The solver decides in
## world space and each modifier layer converts back through `skel.global_transform`, so a yaw read
## as a LOCAL Euler only agrees with that bridge while every ancestor sits at identity. The puppet
## normally runs at identity -- it is written this way so the probes stay a faithful stand-in for
## the real enemy, and so a probe can rotate the root to test exactly that.
func _visual_yaw() -> float:
	var f := -visuals.global_basis.z
	return atan2(-f.x, -f.z)


## Aim a WORLD yaw through the local slot, as a delta -- no Euler round-trip.
func _set_visual_yaw(world_yaw: float) -> void:
	visuals.rotation.y += wrapf(world_yaw - _visual_yaw(), -PI, PI)


## Turn toward travel at a hard rate limit. A rate cap, not an exponential ease: an ease is fast
## when the error is large, which is exactly when a heavy creature should look most reluctant.
func _face(dir: Vector3, delta: float) -> void:
	var want := atan2(-dir.x, -dir.z)          # -Z forward, same as enemy.gd:_face
	var cap := solver.yaw_rate(solver.speed) * delta
	_set_visual_yaw(_visual_yaw() + clampf(wrapf(want - _visual_yaw(), -PI, PI), -cap, cap))


func teleport(to: Vector3) -> void:
	global_position = to
	velocity = Vector3.ZERO
	solver.reset()


## Mirror of enemy.gd's _track_slam clock half: the driven disc grows with action_t and is
## dismissed if the action behind it stops existing. Position tracking is the enemy's job; the
## puppet's discs stay where they were aimed.
func _drive_slam() -> void:
	if _slam_area == null or not is_instance_valid(_slam_area):
		_slam_area = null
		return
	if not solver.is_acting():
		_slam_area.dismiss()
		return
	var spec := solver.spec(solver.action)
	if spec != null and spec.hit_at < 100.0:
		_slam_area.set_progress(solver.action_t / maxf(spec.hit_at, 0.01))

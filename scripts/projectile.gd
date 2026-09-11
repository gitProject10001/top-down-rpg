class_name Projectile
extends Area3D
## A flying arrow / bolt used by BOTH the player's bow and ranged enemies.
##
## TEAM SORTING via collision mask, exactly like melee: a PLAYER arrow masks the enemy-hurtbox
## layer (4), an ENEMY arrow masks the player-hurtbox layer (2). Because it only detects the
## OTHER team's hurtbox, it can never hit its own shooter — no self-collision bookkeeping needed.
##
## Damage still flows through HurtBox.apply_hit(), so a target that blocks/parries frontally
## (the player) negates the arrow through the same code path as a sword hit.
##
## VISUAL: the model under $Model is the artist's arrow.blend. The asset pipeline keeps that file
## clean (camera/light removed, object transforms BAKED into the meshes — Blender constraints and
## parent-inverses do NOT survive glTF export, so unbaked files import scattered). The scene only
## re-centers the composed model on the Area origin; it does not second-guess the content.
##
## On impact (hurtbox hit or ballistic landing) the arrow STICKS where it landed for
## `stick_time` seconds, then shrinks away. A miss that never lands despawns after `lifetime`.
## It does NOT stop on walls yet (world geometry shares layer 1 with character bodies, so
## masking it would risk self-hits). A dedicated "world" layer would let us add that later — TODO.

signal impacted(position: Vector3)   ## ballistic arrow reached the ground (did not hit anyone)

@export var speed := 13.0            ## horizontal m/s for ballistic arcs (lower = higher lob)
@export var damage := 1
@export var lifetime := 3.0
@export var stick_time := 5.0        ## seconds a landed arrow stays planted before despawning
@export var impact_vfx: PackedScene  ## optional puff spawned where a ballistic arrow lands
@export var trail_width := 0.14      ## metres across the flight streak

## THE COLOUR CONTRACT. Parriable is a promise the projectile's TINT makes to the player:
## warm/orange = the shield answers it (block negates, a timed parry sends it back), purple =
## it does not — the defender's on_incoming_hit is bypassed entirely and only feet (dash
## i-frames, jumping, walking off the line) help. Whoever fires this must keep tint and flag
## in agreement, because the player can only read one of them.
@export var parriable := true

## Who fired this. A parry aims the deflected bolt back at them; unset, a deflect simply
## reverses. Set by the firer right after instantiate — not an export, it is a runtime fact.
var shooter: Node3D

var _vel := Vector3.ZERO
var _life := 0.0
var _ballistic := false
var _stuck := false
var _impact_y := 0.0
## The physics frame a deflect happened on. A parry runs SYNCHRONOUSLY inside this bolt's own
## hurtbox hit, and that hit must then not stick us — but only THAT hit: a frame-stamp scopes the
## exemption to the hit that caused it, where a latched bool would leak into the deflected bolt's
## next legitimate contact and make it sail through its new victim un-stuck.
var _deflect_frame := -1
## Homing state (see home()): degrees/sec of turn authority and how long it lasts.
var _home_target: Node3D
var _home_deg := 0.0
var _home_t := 0.0
var _g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var _model: Node3D = $Model
@onready var _trail: BladeTrail = $Trail

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	_recenter_model()
	_trail.flat(trail_width)

## Artists rarely model exactly at the origin — the meshes inside the .blend can carry offsets,
## which would render the arrow metres away from its collision sphere. Measure the combined
## visual bounds and shift the model so its centre sits ON the Area origin.
func _recenter_model() -> void:
	var combined := AABB()
	var first := true
	var to_model := _model.global_transform.affine_inverse()
	for mi in _find_meshes(_model):
		var ab: AABB = (to_model * mi.global_transform) * mi.get_aabb()
		combined = ab if first else combined.merge(ab)
		first = false
	if not first:
		_model.position -= _model.transform.basis * combined.get_center()

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).visible:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out

## Fire this arrow. Call AFTER adding it to the tree and setting global_position.
##   direction : unit-ish world vector to fly along (y is respected, usually ~horizontal)
##   team_mask : which hurtbox layer to hit (4 = enemies, 2 = the player)
##   dmg       : hit points
##   color     : emissive team tint (cool = player, warm = enemy) layered OVER the model's own
##               materials — albedo is preserved, so the artist's arrow still looks like itself.
func setup(direction: Vector3, team_mask: int, dmg: int, color: Color) -> void:
	collision_mask = team_mask
	damage = dmg
	_vel = direction.normalized() * speed
	if _vel.length() > 0.01:
		look_at(global_position + _vel, Vector3.UP)   # point the dart along its flight
	_tint(_model, color)
	_launch_trail(color)

## Start the flight streak in the SAME team colour as the arrow itself. This has to happen here,
## not in _ready(): the caller adds the arrow to the tree and only THEN sets global_position, so a
## trail already recording would draw its first samples at the spawner's origin and streak across
## the level. hold() restarts it, discarding that history.
func _launch_trail(color: Color) -> void:
	_trail.retint(color)
	_trail.hold()

func _tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).visible:
		var mi := node as MeshInstance3D
		if mi.material_override is BaseMaterial3D:
			# A whole-mesh override (the thrown rock) outranks per-surface overrides, so tinting
			# the surfaces under it changes nothing on screen — retint the override itself.
			var dup := (mi.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
			dup.emission_enabled = true
			dup.emission = color
			dup.emission_energy_multiplier = 1.4
			mi.material_override = dup
		else:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.get_active_material(s)
				if m is BaseMaterial3D:
					var dup := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
					dup.emission_enabled = true
					dup.emission = color
					dup.emission_energy_multiplier = 1.4
					mi.set_surface_override_material(s, dup)
	for c in node.get_children():
		_tint(c, color)

## THE ballistic solver — the single source of truth shared by the flying arrow AND the aim
## preview (if they solved separately, the plotted curve could lie). Landing point first,
## launch velocity derived from it:
##   t    = horizontal distance / h_speed   (more power -> shorter time -> flatter arc)
##   v_xz = d_xz / t                        (constant horizontal speed)
##   v_y  = d_y / t + g*t/2                 (whatever vertical speed closes the drop at t)
## Returns {"v0": Vector3, "t": float}. Position along the arc: p(s) = origin + v0*s - (0,g/2,0)*s².
static func solve_arc(origin: Vector3, target: Vector3, h_speed: float, g: float, min_time := 0.18) -> Dictionary:
	var d := target - origin
	var t := maxf(Vector2(d.x, d.z).length() / h_speed, min_time)
	return {"v0": Vector3(d.x / t, d.y / t + 0.5 * g * t, d.z / t), "t": t}

## Launch on a gravity arc that lands EXACTLY on `target`. `h_speed` = horizontal power
## (charge); -1 uses the default `speed`. Returns the flight time for marker timing.
func setup_ballistic(target: Vector3, team_mask: int, dmg: int, color: Color, h_speed := -1.0) -> float:
	collision_mask = team_mask
	damage = dmg
	_ballistic = true
	_impact_y = target.y
	var arc := solve_arc(global_position, target, h_speed if h_speed > 0.0 else speed, _g)
	_vel = arc.v0
	lifetime = arc.t + 1.0                                    # failsafe only; impact ends it
	_tint(_model, color)
	_launch_trail(color)
	return arc.t

## Follow `target` for `seconds`, turning at most `deg_per_sec` — homing TO A DEGREE, never a
## guarantee. The cap is what makes it dodgeable (run past its turning circle) and the window is
## what makes it honest: when the clock runs out the bolt flies true and you can shake it.
## Straight flight only — a ballistic shot homing would drag its arc off the impact ring it
## already promised, and the ring must never lie.
func home(target: Node3D, deg_per_sec: float, seconds: float) -> void:
	_home_target = target
	_home_deg = deg_per_sec
	_home_t = seconds

func _steer(delta: float) -> void:
	if _ballistic or _home_t <= 0.0 or _home_target == null or not is_instance_valid(_home_target):
		return
	_home_t -= delta
	var want := (_home_target.global_position + Vector3(0, 0.6, 0) - global_position)
	var cur := _vel.normalized()
	if want.length() < 0.05 or cur.length_squared() < 0.5:
		return
	want = want.normalized()
	var ang := cur.angle_to(want)
	var axis := cur.cross(want)
	if ang < 0.001 or axis.length_squared() < 0.000001:   # already true, or dead astern
		return
	_vel = cur.rotated(axis.normalized(), minf(ang, deg_to_rad(_home_deg) * delta)) * _vel.length()
	look_at(global_position + _vel, Vector3.UP)

func _physics_process(delta: float) -> void:
	_steer(delta)
	if _ballistic:
		_vel.y -= _g * delta
		if _vel.length_squared() > 0.01:
			look_at(global_position + _vel, Vector3.UP)       # nose follows the arc
	global_position += _vel * delta
	# A falling ballistic arrow that reaches its solved landing height has hit the ground.
	if _ballistic and _vel.y < 0.0 and global_position.y <= _impact_y + 0.05:
		_impact()
		return
	_life += delta
	if _life >= lifetime:
		queue_free()

func _impact() -> void:
	impacted.emit(global_position)
	if impact_vfx:
		var fx := impact_vfx.instantiate()
		get_tree().current_scene.add_child(fx)
		(fx as Node3D).global_position = global_position
	_stick()

## THE PARRY REWARD: turn this projectile around. Called synchronously from inside the victim's
## on_incoming_hit (so it runs BEFORE _on_area_entered decides to stick) — the bolt forgets any
## ballistic arc, re-arms against `team_mask`, wears the defender's colour, and flies back: at
## the shooter when one is known, with a little homing so the reward rarely whiffs; else along
## its reversed path. Works on anything built from this script — an ogre's rock included.
func deflect(team_mask := 4, color := Color(0.5, 0.85, 1.0)) -> void:
	_ballistic = false
	_deflect_frame = Engine.get_physics_frames()
	collision_mask = team_mask
	_life = 0.0
	lifetime = 3.0
	var back := -_vel.normalized() if _vel.length_squared() > 0.01 else Vector3.FORWARD
	if shooter != null and is_instance_valid(shooter):
		back = (shooter.global_position + Vector3(0, 1.2, 0) - global_position).normalized()
		home(shooter, 120.0, 0.8)
	else:
		# No one to send it back to (the shooter died mid-flight): plain reversal, and any
		# homing it was fired with dies too — a "sent back" bolt still steering at the
		# defender who parried it would be the parry reward U-turning on them.
		_home_t = 0.0
		_home_target = null
	_vel = back * maxf(speed * 1.35, _vel.length())
	look_at(global_position + _vel, Vector3.UP)
	_tint(_model, color)
	_trail.retint(color)

func _on_area_entered(area: Area3D) -> void:
	# Collision masks guarantee `area` is an opposing HurtBox.
	if area is HurtBox:
		var applied := (area as HurtBox).apply_hit(damage, self)
		if _deflect_frame == int(Engine.get_physics_frames()):
			return                      # THIS hit is the parry that turned us — fly on, no stick
		# CONTACT feedback only when hp actually changed — an absorbed hit is silent, the same
		# rule the melee seam fix bought. The block's own thud comes from _do_block. A light
		# universal projectile contact (both directions: an arrow into an enemy, a bolt into
		# the player, a deflected bolt coming home) — the shake number the raw emit used to be,
		# now with the small freeze and tick of the pad that any landed blow carries.
		if applied > 0:
			CombatFeedback.contact_landed(0.05, 0.15, 0.12)
		_stick(area)

## Plant the arrow where it landed instead of vanishing: physics off, collisions off,
## nose frozen at its flight angle. An arrow that hit a BODY reparents onto it (reparent
## keeps the world transform) so it rides along — and dies with it. After `stick_time`
## the arrow shrinks away. You can read a fight off the ground afterwards.
func _stick(target: Node3D = null) -> void:
	if _stuck:
		return
	_stuck = true
	set_physics_process(false)
	set_deferred("monitoring", false)        # a planted arrow must never hit again
	set_deferred("monitorable", false)
	# Kill the streak on impact. Not just cosmetic: an arrow that hits a BODY reparents onto it and
	# then RIDES it, so a live trail would keep drawing from a walking enemy's chest.
	_trail.stop(0.1)
	if target != null and target.is_inside_tree():
		call_deferred("reparent", target)    # deferred: we're inside a physics callback
	var tw := create_tween()
	tw.tween_interval(stick_time)
	tw.tween_property(_model, "scale", _model.scale * 0.02, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

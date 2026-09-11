extends State
## Charged ballistic archery:
##   HOLD `shoot` — charge = POWER. The impact ring tracks the cursor (clamped to charged
##                  reach, snapped to real ground) and a dotted TRAJECTORY shows the exact
##                  arc: low charge = slow high lob, full charge = fast flat shot — even to
##                  the SAME landing point (t = dist/power, so more power = shorter, flatter).
##   RELEASE      — the arrow flies precisely the previewed arc (same solver, same numbers).
##   DASH         — cancels the aim entirely (no shot, marker and arc vanish).
## You can still shuffle slowly while drawing — kite-and-shoot.

@export var min_range := 3.0       ## landing distance reachable with an instant tap
@export var max_range := 14.0      ## landing distance reachable at full charge
@export var min_power := 8.0       ## horizontal launch speed at zero charge (high lob)
@export var max_power := 22.0      ## horizontal launch speed at full charge (flat + fast)
@export var charge_time := 0.9     ## seconds of hold to reach max range/power
@export var recover_time := 0.15   ## pause after release before control returns
@export var move_scale := 0.3      ## fraction of run speed while drawing

const MARKER_SCENE := "res://scenes/fx/impact_marker.tscn"
const PREVIEW_SCENE := "res://scenes/fx/trajectory_preview.tscn"

var _charge := 0.0
var _recover := 0.0
var _fired := false
var _target := Vector3.ZERO
var _power := 0.0
var _marker: ImpactMarker
var _preview: TrajectoryPreview

func enter() -> void:
	_charge = 0.0
	_recover = 0.0
	_fired = false
	player.face_aim_direction(0.35)
	_marker = (load(MARKER_SCENE) as PackedScene).instantiate() as ImpactMarker
	get_tree().current_scene.add_child(_marker)
	_preview = (load(PREVIEW_SCENE) as PackedScene).instantiate() as TrajectoryPreview
	get_tree().current_scene.add_child(_preview)

func exit() -> void:
	# Cancelled mid-aim (dash/hurt) — the marker is still ours to clean up.
	if is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.face_aim_direction(delta)
	player.apply_movement(player.get_move_input(), delta, move_scale)
	player.move_and_slide()

	if not _fired:
		_charge += delta
		_update_target()
		if not Input.is_action_pressed("shoot"):
			_release()
	else:
		_recover += delta
		if _recover >= recover_time:
			fsm.transition_to("Move" if player.get_move_input() != Vector2.ZERO else "Idle")

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("dash") and player.can_dash():
		fsm.transition_to("Dash")   # exit() removes the marker — a true cancel

## The landing point: toward the cursor, clamped to the charged range, dropped to the ground.
## Charge also sets POWER, and the preview plots the exact arc the arrow would fly right now.
func _update_target() -> void:
	var f := clampf(_charge / charge_time, 0.0, 1.0)
	var reach := lerpf(min_range, max_range, f)
	_power = lerpf(min_power, max_power, f)
	var to_aim := player.aim_point() - player.global_position
	to_aim.y = 0.0
	var dir := to_aim.normalized() if to_aim.length() > 0.01 else -player.visuals.global_transform.basis.z
	var flat := player.global_position + dir * minf(to_aim.length(), reach)
	_target = Vector3(flat.x, _ground_y(flat), flat.z)
	if is_instance_valid(_marker):
		_marker.global_position = _target
	if is_instance_valid(_preview):
		var origin := player.global_position + Vector3(0, 1.0, 0)
		var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
		var arc := Projectile.solve_arc(origin, _target, _power, g)   # SAME solver as the arrow
		_preview.show_arc(origin, arc.v0, arc.t, g)

## Raycast straight down so the marker sits on the actual floor (arena pit, stairs, garden).
func _ground_y(at: Vector3) -> float:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 12, 0), at + Vector3(0, -30, 0), 1, [player.get_rid()])
	var hit := space.intersect_ray(q)
	return hit.position.y if hit else player.global_position.y

func _release() -> void:
	_fired = true
	player.use_arrow()                   # one arrow leaves the quiver (HUD counts them)
	player.start_shoot_cooldown()
	if is_instance_valid(_preview):      # the flying arrow replaces the plot
		_preview.queue_free()
	_preview = null
	var flight := player.bow.shoot_at(_target, player.global_position + Vector3(0, 1.0, 0), _power)
	if is_instance_valid(_marker):
		_marker.start_lifetime(flight)   # marker outlives the state, fades as the arrow lands
	_marker = null                       # ownership transferred — exit() must not free it

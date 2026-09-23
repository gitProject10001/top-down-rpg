class_name EnemyDuelist
extends Player
## THE MIRROR. An enemy that is not "like" the player but literally built from the player scene:
## same rig, same sword, same state machine, same measured attack envelope, same directional
## attack and directional guard. The only difference between the two fighters is which
## FighterIntent child is filling in the decisions.
##
## WHY NOT A SEPARATE ENEMY SCRIPT. A classic enemy chases on a distance check, telegraphs on a
## tween, and keys its damage window into a clip — none of which knows what a swing DIRECTION is.
## Worse, it would be a second implementation of the mechanic, and the whole point of a duel is
## that both sides are bound by one set of rules. So this one is the player, with a brain.
##
## WHAT HAS TO CHANGE, and it is only four things, all of them identity rather than behaviour: the
## groups it answers to, the physics layers its hurtbox and hitbox use, and who it is looking for.
## Doing them in code rather than as inherited-scene property overrides keeps them in one readable
## place — the sword's HitBox in particular lives two instance levels down, where a scene override
## needs editable-children and is invisible to anyone reading the file.

## Physics layers, from sword.tscn and the player scenes: the player's HurtBox sits on layer 2 and
## enemy hitboxes mask it; every enemy's HurtBox sits on layer 4 and the player's sword masks that.
## Being a player body, this one starts on the player's side of both and has to swap.
const LAYER_PLAYER_HURT := 2
const LAYER_ENEMY_HURT := 4


func _ready() -> void:
	super()

	# GROUPS ARE THE PROJECT'S CROSS-CUTTING DISCOVERY, so this is what actually makes it an enemy:
	# the camera rig's lock-on, the HUD's boss bar and the player's own target acquisition all ask
	# the group, never the class. Done here rather than in the .tscn because an inherited scene
	# stores its root's group list wholesale, and a future re-parent of player3.tscn would silently
	# put this body back in the player group.
	remove_from_group("player")
	add_to_group("enemy")

	# Who it swings at. Player.acquire_target reads this; the human's copy stays "enemy".
	target_group = &"player"

	var hurt := get_node_or_null("HurtBox") as Area3D
	if hurt:
		hurt.collision_layer = LAYER_ENEMY_HURT
	if sword:
		var hitbox := sword.get_node_or_null("HitBox") as Area3D
		if hitbox:
			hitbox.collision_mask = LAYER_PLAYER_HURT

	# The hero's personal fill light travels with the hero. Two of them in one scene reads as a
	# lighting bug rather than as a second character.
	var light := get_node_or_null("HeroLight") as Light3D
	if light:
		light.visible = false


func swing_damage() -> int:
	# Hero traits belong to the hero; enemies do not inherit the player's crits.
	return 1


@export_range(0.0, .5, .01) var death_step_distance := .38
@export_range(.1, .6, .01) var death_step_duration := .42
var death_stepping := false
var _death_step_candidate := false
var _death_direction := Vector3.ZERO
var _death_elapsed := 0.0
var _death_origin := Vector3.ZERO

func _on_damaged(amount: int, source: Node) -> void:
	# Capture BEFORE Hurt replaces locomotion velocity and before Dead clears it.
	if health.hp == 0:
		_death_step_candidate = is_on_floor() and death_step_distance > 0 and not (source != null and source.get_meta("finisher", false)) and not (state_name() == "Hurt" and _fsm.current_state.knocked_down)
		var rag := find_child("Ragdoll", true, false)
		if rag and rag.has_method("capture_impact"):
			var point := global_position + Vector3.UP * .35
			var direction := -visuals.global_basis.z
			if source is Node3D:
				direction = global_position - source.global_position
				direction.y = 0.0
				point = source.get_meta("contact_point", point)
				direction = source.get_meta("impact_direction", direction)
			_death_direction = Vector3(direction.x, 0, direction.z).normalized()
			rag.capture_impact(point, direction, velocity, source != null and source.get_meta("finisher", false))
	super(amount, source)

func _on_died() -> void:
	super()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	var hurt := get_node_or_null("HurtBox") as Area3D
	if hurt: hurt.set_deferred("collision_layer", 0)
	if intent:
		intent.clear()
		intent.set_physics_process(false)
	# Defer until collider changes have flushed; never let live animation/IK fight physics.
	_begin_death_transition.call_deferred()
	get_tree().create_timer(6.0).timeout.connect(queue_free)

func _death_path_clear(distance: float) -> bool:
	if _death_direction.length_squared() < .1: return false
	if test_move(global_transform, _death_direction * distance): return false
	if intent is PackBrain and is_instance_valid(intent.director):
		if not intent.director.safe_step(self, Vector2(_death_direction.x, _death_direction.z), distance): return false
	var foot := global_position + _death_direction * distance
	var ray := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * .15, foot - Vector3.UP * 1.3, 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _begin_death_transition() -> void:
	if not _death_step_candidate or not has_clip("recover_walk_back") or not _death_path_clear(death_step_distance):
		_start_death_physics()
		return
	death_stepping = true
	_death_origin = global_position
	_death_elapsed = 0.0
	var local_dir := visuals.global_basis.inverse() * _death_direction
	var clip := "recover_walk_back"
	if absf(local_dir.x) > absf(local_dir.z): clip = "recover_walk_right" if local_dir.x > 0 else "recover_walk_left"
	elif local_dir.z < 0: clip = "walk"
	play_clip(clip)
	var rag := find_child("Ragdoll", true, false)
	if rag: rag.resume_pose_sampling()

func advance_death_step(delta: float) -> void:
	if not death_stepping: return
	_death_elapsed += delta
	var travel := minf(death_step_distance/death_step_duration*delta, maxf(0, death_step_distance - global_position.distance_to(_death_origin)))
	if _death_elapsed >= death_step_duration or not _death_path_clear(maxf(travel*2,.10)):
		death_stepping = false
		var rag := find_child("Ragdoll", true, false)
		if rag: rag.finish_pose_sampling(global_position - _death_origin, velocity)
		_start_death_physics()
		return
	velocity.x = _death_direction.x * travel / delta
	velocity.z = _death_direction.z * travel / delta
	apply_gravity(delta)
	move_and_slide()

func _start_death_physics() -> void:
	set_deferred("collision_mask", 0)
	var rag := find_child("Ragdoll", true, false) as PhysicalBoneSimulator3D
	if rag == null: return # Bodies without authored physics retain the death clip.
	set_process(false)
	_fsm.set_physics_process(false)
	if _tree: _tree.active = false
	var skeleton := rag.get_parent() as Skeleton3D
	for child in skeleton.get_children():
		if child is SkeletonModifier3D and child != rag:
			child.active = false
	# Preserve the last hand pose while the body falls, without the live grip solver.
	if sword and _grip_r:
		sword.reparent(_grip_r, true)
	if shield and _grip_l:
		shield.reparent(_grip_l, true)
	var blob := get_node_or_null("BlobShadow")
	if blob: blob.hide()
	if rag.has_method("start_reaction"):
		rag.start_reaction()
	else:
		rag.physical_bones_start_simulation()



## Its own hurt radius, read by Player.hurt_radius_of when the other side sizes up a swing. The
## capsule lookup in that function already finds this body's HurtBox shape, so nothing is
## overridden here — the note exists because a reader will look for it.

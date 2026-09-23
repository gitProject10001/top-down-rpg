extends Node3D
## Ordered authored checkpoints for traversal studies; no quest rewards or NPC side effects.
signal advanced(index: int)
signal completed
@export var checkpoint_paths: Array[NodePath]=[]
@export_range(.5,8,.1) var reach_radius:=2.5
var player: CharacterBody3D
var step:=0
var elapsed:=0.0
var split_times: Array[float]=[]
var travelled:=0.0
var _last_position:=Vector3.ZERO
var gate: Callable
func configure(hero: CharacterBody3D) -> void:
 player=hero; _last_position=hero.global_position
func reset() -> void:
 step=0; elapsed=0; travelled=0; split_times.clear()
 if is_instance_valid(player): _last_position=player.global_position
func current_checkpoint() -> Node3D:
 if step>=checkpoint_paths.size(): return null
 return get_node_or_null(checkpoint_paths[step]) as Node3D
func _physics_process(delta: float) -> void:
 if not is_instance_valid(player) or not player.health.is_alive(): return
 var distance:=player.global_position.distance_to(_last_position)
 _last_position=player.global_position
 if step>0 and step<checkpoint_paths.size():
  elapsed+=delta
  if distance<3.0: travelled+=distance # Debug teleports are not walking distance.
 var checkpoint:=current_checkpoint()
 if not checkpoint: return
 var offset:=player.global_position-checkpoint.global_position
 if Vector2(offset.x,offset.z).length()>reach_radius or absf(offset.y)>2.0: return
 if gate.is_valid() and not gate.call(step): return
 split_times.append(elapsed); step+=1; advanced.emit(step)
 if step==checkpoint_paths.size(): completed.emit()

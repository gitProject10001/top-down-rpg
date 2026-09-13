@tool
extends Node3D
## Persistent authored support. The parent volume owns the resulting mesh/collider.
@export_storage var support_id := ""
@export_range(0.08,0.8,0.01) var section := 0.18:
	set(value): section=value; refresh()
@export var enabled := true:
	set(value): enabled=value; refresh()
var _observed := Transform3D.IDENTITY
func volume() -> Node3D:
	return get_parent().get_parent() if get_parent() and get_parent().name=="Supports" else null
func _enter_tree() -> void:
	if support_id.is_empty(): support_id="post_"+str(Time.get_ticks_usec())+"_"+str(get_instance_id())
	refresh()
func _exit_tree() -> void: refresh()
func _process(_delta: float) -> void:
	if transform!=_observed:
		_observed=transform; refresh()
func refresh() -> void:
	var host := volume()
	if host: host.request_rebuild()
	if is_inside_tree(): update_gizmos(); update_configuration_warnings()
func height() -> float:
	var host := volume()
	return maxf(0.01,host.post_top(position)-position.y) if host else 1.0
func valid() -> bool:
	var host := volume()
	return host!=null and enabled and host.structure_kind==1 and absf(position.x)<=host.width*0.5 and absf(position.z)<=host.depth*0.5 and position.y<host.post_top(position)-0.1
func _get_configuration_warnings() -> PackedStringArray:
	if enabled and not valid(): return PackedStringArray(["Sostegno fuori dalla copertura o sopra il tetto: spostalo o ridimensionala. Il dato viene conservato ma il palo non viene generato."])
	if not basis.is_equal_approx(Basis.IDENTITY): return PackedStringArray(["Usa posizione e Section: i sostegni di questa versione rimangono verticali e non usano rotazione o scala."])
	return PackedStringArray()

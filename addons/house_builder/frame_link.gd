@tool
extends Node3D
## Endpoints reference persistent support IDs in the same volume.
@export_storage var link_id := ""
@export_storage var support_a := ""
@export_storage var support_b := ""
@export_range(0.08,0.5,0.01) var section := 0.22:
	set(value): section=value; refresh()
@export_range(0.1,1.0,0.01) var roof_offset := 0.25:
	set(value): roof_offset=value; refresh()
@export var braces := true:
	set(value): braces=value; refresh()
@export_range(0.2,1.5,0.05) var brace_drop := 0.65:
	set(value): brace_drop=value; refresh()
@export_range(0.1,0.45,0.01) var brace_fraction := 0.22:
	set(value): brace_fraction=value; refresh()
@export var enabled := true:
	set(value): enabled=value; refresh()
func volume() -> Node3D:
	return get_parent().get_parent() if get_parent() and get_parent().name=="FrameLinks" else null
func _enter_tree() -> void:
	if link_id.is_empty(): link_id="link_"+str(Time.get_ticks_usec())+"_"+str(get_instance_id())
	refresh()
func _exit_tree() -> void: refresh()
func refresh() -> void:
	var host := volume()
	if host: host.request_rebuild()
	if is_inside_tree(): update_gizmos(); update_configuration_warnings()
func support(id: String) -> Node3D:
	var host := volume(); var result: Node3D
	if host==null or not host.has_node("Supports"): return null
	for post in host.get_node("Supports").get_children():
		if post.get("support_id")==id:
			if result!=null: return null
			result=post
	return result
func endpoints() -> PackedVector3Array:
	var a := support(support_a); var b := support(support_b)
	if a==null or b==null: return PackedVector3Array()
	return PackedVector3Array([a.position+Vector3.UP*(a.height()-roof_offset),b.position+Vector3.UP*(b.height()-roof_offset)])
func validation_error() -> String:
	if not enabled: return ""
	var a := support(support_a); var b := support(support_b)
	if a==null or b==null: return "Collegamento sospeso: sostegno mancante o ID duplicato. Ripristina il palo oppure ricrea il collegamento."
	if a==b or not a.valid() or not b.valid(): return "Collegamento sospeso: servono due sostegni distinti e validi."
	if Vector2(a.position.x-b.position.x,a.position.z-b.position.z).length()<section*2: return "Sostegni troppo vicini per questa trave."
	if minf(a.height(),b.height())<roof_offset+(brace_drop if braces else 0.0)+section: return "Il collegamento scende sotto la base dei sostegni: riduci offset o controventi."
	return ""
func segments() -> Array:
	if not enabled or not validation_error().is_empty(): return []
	var points := endpoints(); var a := points[0]; var b := points[1]
	var result: Array=[[a,b,section]]
	if braces:
		result.append([a-Vector3.UP*brace_drop,a.lerp(b,brace_fraction),section*0.7])
		result.append([b-Vector3.UP*brace_drop,b.lerp(a,brace_fraction),section*0.7])
	return result
func _get_configuration_warnings() -> PackedStringArray:
	var error := validation_error()
	return PackedStringArray() if error.is_empty() else PackedStringArray([error])

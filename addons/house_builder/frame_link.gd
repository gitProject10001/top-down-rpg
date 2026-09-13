@tool
extends Node3D
## Endpoints reference persistent support IDs in the same volume.
@export_storage var link_id := ""
@export_storage var support_a := ""
@export_storage var support_b := ""
@export_enum("Due sostegni", "Sostegno e parete") var endpoint_mode := 0:
	set(value): endpoint_mode=value; refresh()
@export_range(-3.0,3.0,0.05) var wall_offset := 0.0:
	set(value): wall_offset=value; refresh()
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
func wall_endpoint() -> Vector3:
	var host := volume(); var post := support(support_a)
	if host==null or post==null: return Vector3.ZERO
	var point := Vector3(post.position.x+wall_offset,0,-host.depth*0.5+host.WALL_THICKNESS+0.08)
	point.y=host.post_top(point)-roof_offset
	return point
func endpoints() -> PackedVector3Array:
	var a := support(support_a); var b := support(support_b)
	if a==null or (endpoint_mode==0 and b==null): return PackedVector3Array()
	return PackedVector3Array([a.position+Vector3.UP*(a.height()-roof_offset),wall_endpoint() if endpoint_mode==1 else b.position+Vector3.UP*(b.height()-roof_offset)])
func validation_error() -> String:
	if not enabled: return ""
	var a := support(support_a); var b := support(support_b)
	if a==null or (endpoint_mode==0 and b==null): return "Collegamento sospeso: sostegno mancante o ID duplicato. Ripristina il palo oppure ricrea il collegamento."
	if not a.valid() or (endpoint_mode==0 and (a==b or not b.valid())): return "Collegamento sospeso: servono sostegni validi e distinti."
	if endpoint_mode==1:
		var host := volume()
		if not host.attached or host.volume_host()==null or not host.volume_error().is_empty(): return "Aggancio alla parete sospeso: riaggancia il portico a una facciata valida."
		var point := wall_endpoint()
		if absf(point.x)+section*0.5>host.width*0.5 or point.y<section: return "Aggancio fuori dalla copertura: riduci Wall Offset o Roof Offset."
		var house: Node3D=host.volume_host()
		var along: float=host.host_offset*house.wall_length(host.host_wall)*0.5+point.x
		for record in house.all_openings():
			var opening: Dictionary=house.resolved_opening(record)
			if opening.wall==host.host_wall and absf(opening.along-along)<(opening.width+section)*0.5 and absf(opening.y-point.y)<(opening.height+section)*0.5:
				return "Aggancio sopra un'apertura: sposta il punto lungo la parete."
	var points := endpoints()
	if Vector2(points[0].x-points[1].x,points[0].z-points[1].z).length()<section*2: return "Estremi troppo vicini per questa trave."
	var clearance: float=a.height() if endpoint_mode==1 else minf(a.height(),b.height())
	if clearance<roof_offset+(brace_drop if braces else 0.0)+section: return "Il collegamento scende sotto la base dei sostegni: riduci offset o controventi."
	return ""
func segments() -> Array:
	if not enabled or not validation_error().is_empty(): return []
	var points := endpoints(); var a := points[0]; var b := points[1]
	var result: Array=[[a,b,section]]
	if braces:
		result.append([a-Vector3.UP*brace_drop,a.lerp(b,brace_fraction),section*0.7])
		if endpoint_mode==0: result.append([b-Vector3.UP*brace_drop,b.lerp(a,brace_fraction),section*0.7])
	return result
func _get_configuration_warnings() -> PackedStringArray:
	var error := validation_error()
	return PackedStringArray() if error.is_empty() else PackedStringArray([error])

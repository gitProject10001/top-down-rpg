@tool
extends "res://addons/house_builder/house.gd"
## A rectangular authored body, with its own openings and roof proportions.
@export_group("Aggancio del volume")
@export_storage var volume_id := ""
@export var attached := true:
	set(value): attached=value; request_rebuild()
@export_enum("Davanti", "Dietro", "Destra", "Sinistra") var host_wall := 2:
	set(value): host_wall=value; request_rebuild()
@export_range(-1,1,0.01) var host_offset := 0.0:
	set(value): host_offset=value; request_rebuild()
var _observed := ""
func volume_host() -> Node3D:
	return get_parent().get_parent() if get_parent() and get_parent().name=="Volumes" else null
func _enter_tree() -> void:
	if volume_id.is_empty(): volume_id="volume_"+str(Time.get_ticks_usec())+"_"+str(get_instance_id())
func _exit_tree() -> void:
	var host := volume_host()
	if host: host.request_rebuild()
func _process(delta: float) -> void:
	var signature := str(dimensions(),openings,attached,host_wall,host_offset,transform if not attached else Transform3D.IDENTITY)
	if signature!=_observed:
		_observed=signature
		var host := volume_host()
		if host: host.request_rebuild()
	super._process(delta)
func prepare_attachment() -> void:
	var host := volume_host()
	if not attached or host==null: return
	var tangent: Vector3=(host.wall_point(host_wall,1,0)-host.wall_point(host_wall,0,0)).normalized()
	transform=Transform3D(Basis(tangent,Vector3.UP,host.wall_normal(host_wall)),host.wall_point(host_wall,host_offset*host.wall_length(host_wall)*0.5,0,depth*0.5-WALL_THICKNESS-0.08))
func rebuild() -> void:
	prepare_attachment()
	super.rebuild()
func volume_error() -> String:
	var host := volume_host()
	if host==null: return "Il corpo accessorio deve stare in Casa / Volumes."
	if not attached: return ""
	if host.has_method("volume_host") or host.wing_enabled or wing_enabled: return "Aggancio supportato al corpo principale senza ala legacy."
	if absf(host_offset*host.wall_length(host_wall)*0.5)+width*0.5>host.wall_length(host_wall)*0.5-0.25: return "Il volume supera il bordo della facciata: riduci larghezza o spostamento."
	if wall_height+roof_height>host.wall_height-0.15: return "Per questo primo raccordo il tetto accessorio deve stare sotto la gronda principale."
	for record in host.openings:
		var opening: Dictionary=host.resolved_opening(record)
		if opening.wall==host_wall and absf(opening.along-host_offset*host.wall_length(host_wall)*0.5)<(width+opening.width)*0.5+0.15:
			return "Il corpo copre un'apertura manuale della casa. Scegli una zona libera."
	for record in openings:
		if int(record.get("wall",0))==1: return "La facciata posteriore è il raccordo: sposta la sua apertura su un lato libero."
	for other in host.authored_volumes():
		if other==self or not other.attached: continue
		# Footprints are transformed to host axes for orthogonal attachments.
		var bounds := AABB(Vector3(-width*0.5,0,-depth*0.5),Vector3(width,1,depth))
		var other_bounds := AABB(Vector3(-other.width*0.5,0,-other.depth*0.5),Vector3(other.width,1,other.depth))
		if (transform*bounds).intersects(other.transform*other_bounds): return "Due corpi accessori si sovrappongono. Spostali prima di raccordarli."
	return ""
func _get_configuration_warnings() -> PackedStringArray:
	var error := volume_error()
	return super._get_configuration_warnings() if error.is_empty() else PackedStringArray([error])

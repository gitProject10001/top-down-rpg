@tool
extends "res://addons/house_builder/house.gd"
## A rectangular authored body, with its own openings and roof proportions.
@export_group("Struttura")
@export_enum("Corpo chiuso", "Portico / tettoia aperta") var structure_kind := 0:
	set(value): structure_kind=value; request_rebuild()
@export var automatic_frame := true:
	set(value): automatic_frame=value; request_rebuild()
@export_enum("Due falde", "Falda singola verso esterno") var canopy_roof := 0:
	set(value): canopy_roof=value; request_rebuild()
@export_range(0.12,0.4,0.01) var post_size := 0.18:
	set(value): post_size=value; request_rebuild()
@export_range(1.5,5.0,0.1) var post_spacing := 3.0:
	set(value): post_spacing=value; request_rebuild()
@export_group("Aggancio del volume")
@export_storage var volume_id := ""
@export var attached := true:
	set(value): attached=value; request_rebuild()
@export_enum("Davanti", "Dietro", "Destra", "Sinistra") var host_wall := 2:
	set(value): host_wall=value; request_rebuild()
@export_range(-1,1,0.01) var host_offset := 0.0:
	set(value): host_offset=value; request_rebuild()
@export_group("Raccordo interno")
@export_enum("Passaggio aperto", "Parete con porta") var junction_mode := 0:
	set(value): junction_mode=value; request_rebuild()
@export_range(0.8,2.5,0.05) var junction_width := 1.2:
	set(value): junction_width=value; request_rebuild()
@export_range(1.8,3.0,0.05) var junction_height := 2.1:
	set(value): junction_height=value; request_rebuild()
@export_range(-1,1,0.01) var junction_offset := 0.0:
	set(value): junction_offset=value; request_rebuild()
@export_storage var junction_open := false
var _observed := ""
func volume_host() -> Node3D:
	return get_parent().get_parent() if get_parent() and get_parent().name=="Volumes" else null
func _enter_tree() -> void:
	if volume_id.is_empty(): volume_id="volume_"+str(Time.get_ticks_usec())+"_"+str(get_instance_id())
func _exit_tree() -> void:
	var host := volume_host()
	if host: host.request_rebuild()
func _process(delta: float) -> void:
	var signature := str(dimensions(),automatic_frame,canopy_roof,structure_kind,post_size,post_spacing,openings,junction_mode,junction_width,junction_height,junction_offset,attached,host_wall,host_offset,transform if not attached else Transform3D.IDENTITY)
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
	if structure_kind==0 and junction_mode==1 and (junction_width>width-0.5 or junction_height>wall_height-0.2): return "La porta del raccordo supera il corpo: riduci larghezza o altezza della porta."
	for record in host.openings:
		var opening: Dictionary=host.resolved_opening(record)
		if opening.wall==host_wall and absf(opening.along-host_offset*host.wall_length(host_wall)*0.5)<(width+opening.width)*0.5+0.15:
			if structure_kind==0: return "Il corpo copre un'apertura manuale della casa. Scegli una zona libera."
			if opening.y+opening.height*0.5>support_height(-depth*0.5+WALL_THICKNESS+0.08)-0.25: return "La copertura interferisce con un'apertura della casa: alza i sostegni o sposta la tettoia."
	for record in openings:
		if structure_kind==0 and int(record.get("wall",0))==1: return "La facciata posteriore è il raccordo: sposta la sua apertura su un lato libero."
	for other in host.authored_volumes():
		if other==self or not other.attached: continue
		# Footprints are transformed to host axes for orthogonal attachments.
		var bounds := AABB(Vector3(-width*0.5,0,-depth*0.5),Vector3(width,1,depth))
		var other_bounds := AABB(Vector3(-other.width*0.5,0,-other.depth*0.5),Vector3(other.width,1,other.depth))
		if (transform*bounds).intersects(other.transform*other_bounds): return "Due corpi accessori si sovrappongono. Spostali prima di raccordarli."
	return ""
func _get_configuration_warnings() -> PackedStringArray:
	var error := volume_error()
	if not error.is_empty(): return PackedStringArray([error])
	return PackedStringArray() if structure_kind==1 else super._get_configuration_warnings()

func junction_record() -> Dictionary:
	var host := volume_host()
	var along: float=host_offset*host.wall_length(host_wall)*0.5+junction_offset*maxf(0,(width-junction_width)*0.5-0.25)
	return {"kind":"door","wall":host_wall,"u":along/(host.wall_length(host_wall)*0.5),"width":junction_width,"height":junction_height,"open":junction_open,"volume_id":volume_id}

func all_openings() -> Array[Dictionary]:
	# Keep authored openings when converting, but never generate floating frames.
	if structure_kind==0: return super.all_openings()
	return []

func opening_fits(record: Dictionary,ignore_index: int=-1) -> bool:
	return structure_kind==0 and super.opening_fits(record,ignore_index)

func _build_shell() -> void:
	if structure_kind==0:
		super._build_shell(); return
	if canopy_roof==1:
		_build_shed_supports(); return
	_build_posts()
	_build_links()
	if not automatic_frame: return
	for side in [-1.0,1.0]:
		var x: float=side*(width-post_size)*0.5
		_box(Vector3(x,wall_height-0.10,0),Vector3(post_size+0.04,0.20,depth),1)
	for z in [-depth*0.5,depth*0.5]:
		_box(Vector3(0,wall_height-0.10,z),Vector3(width,0.20,post_size),1)
		_beam(Vector3(-width*0.5,wall_height,z),Vector3(0,wall_height+roof_height,z),post_size)
		_beam(Vector3(width*0.5,wall_height,z),Vector3(0,wall_height+roof_height,z),post_size)
	_box(Vector3(0,wall_height+roof_height,0),Vector3(post_size,post_size,depth+0.6),1)

func support_height(z: float) -> float:
	return wall_height+roof_height*(0.5-z/depth) if structure_kind==1 and canopy_roof==1 else wall_height

func _build_roof() -> ArrayMesh:
	return RoofMesh.new().generate(width,depth,wall_height,roof_height,house_seed,weathered,structure_kind==1 and canopy_roof==1)

func _build_shed_supports() -> void:
	_build_posts()
	_build_links()
	if not automatic_frame: return
	for side in [-1.0,1.0]:
		var x: float=side*(width-post_size)*0.5
		_beam(Vector3(x,support_height(-depth*0.5)-0.10,-depth*0.5),Vector3(x,support_height(depth*0.5)-0.10,depth*0.5),post_size)
	for z in [-depth*0.5,depth*0.5]:
		_box(Vector3(0,support_height(z)-0.10,z),Vector3(width,0.20,post_size),1)

func automatic_posts() -> Array[Vector3]:
	var result: Array[Vector3]=[]
	var anchored := attached and volume_host()!=null and volume_error().is_empty()
	var bays := maxi(1,ceili((depth-post_size)/post_spacing))
	for side in [-1.0,1.0]:
		for i in bays+1:
			if anchored and i==0: continue
			result.append(Vector3(side*(width-post_size)*0.5,0,-(depth-post_size)*0.5+i*(depth-post_size)/bays))
	return result

func _build_posts() -> void:
	var supports := get_node_or_null("Supports")
	if supports:
		for post in supports.get_children():
			if not post.has_method("valid"): continue
			post.update_gizmos()
			if Engine.is_editor_hint(): post.update_configuration_warnings()
			if post.valid(): _box(post.position+Vector3.UP*post.height()*0.5,Vector3(post.section,post.height(),post.section),1)
	else:
		for point in automatic_posts():
			var h := support_height(point.z)
			_box(point+Vector3.UP*h*0.5,Vector3(post_size,h,post_size),1)

func post_top(point: Vector3) -> float:
	return support_height(point.z) if canopy_roof==1 else wall_height+roof_height*(1.0-absf(point.x)/(width*0.5))

func _build_links() -> void:
	var links := get_node_or_null("FrameLinks")
	if links==null: return
	for link in links.get_children():
		if not link.has_method("segments"): continue
		link.update_gizmos()
		if Engine.is_editor_hint(): link.update_configuration_warnings()
		for segment in link.segments(): _beam(segment[0],segment[1],segment[2])

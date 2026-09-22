@tool
extends "res://addons/house_builder/house.gd"
## A rectangular authored body, with its own openings and roof proportions.
@export_group("Struttura")
@export_enum("Corpo chiuso", "Portico / tettoia aperta") var structure_kind := 0:
	set(value): structure_kind=value; request_rebuild()
@export var battlements_enabled := false:
	set(value): battlements_enabled=value; request_rebuild()
@export_range(0.6,2.0,0.05) var battlement_spacing := 1.0:
	set(value): battlement_spacing=value; request_rebuild()
@export var parapet_enabled := true:
	set(value): parapet_enabled=value; request_rebuild()
@export var automatic_frame := true:
	set(value): automatic_frame=value; request_rebuild()
@export_enum("Due falde", "Falda singola verso esterno", "Piana con parapetto") var canopy_roof := 0:
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
## Explicit upper body; this does not create an InteriorPlan floor.
@export_range(0.0,8.0,0.1) var attachment_elevation := 0.0:
	set(value): attachment_elevation=maxf(0.0,value); request_rebuild()
@export_range(0.0,6.0,0.1) var attachment_inset := 0.0:
	set(value): attachment_inset=maxf(0.0,value); request_rebuild()
@export var roof_junction := false:
	set(value): roof_junction=value; request_rebuild()
@export_group("Porta dal tetto")
@export var roof_door_enabled := false:
	set(value): roof_door_enabled=value; request_rebuild()
@export_storage var roof_door_floor_id := ""
@export_range(-1,1,0.05) var roof_door_offset := 0.0:
	set(value): roof_door_offset=value; request_rebuild()
@export_storage var roof_door_open := false
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
	var signature := str(dimensions(),battlements_enabled,battlement_spacing,roof_door_enabled,roof_door_floor_id,roof_door_offset,parapet_enabled,automatic_frame,canopy_roof,structure_kind,post_size,post_spacing,openings,junction_mode,junction_width,junction_height,junction_offset,attached,host_wall,host_offset,transform if not attached else Transform3D.IDENTITY)
	signature += str(attachment_elevation,attachment_inset,roof_junction,roof_curvature)
	if signature!=_observed:
		_observed=signature
		var host := volume_host()
		if host: host.request_rebuild()
	super._process(delta)
func prepare_attachment() -> void:
	var host := volume_host()
	if not attached or host==null: return
	var tangent: Vector3=(host.wall_point(host_wall,1,0)-host.wall_point(host_wall,0,0)).normalized()
	transform=Transform3D(Basis(tangent,Vector3.UP,host.wall_normal(host_wall)),host.wall_point(host_wall,host_offset*host.wall_length(host_wall)*0.5,attachment_elevation,depth*0.5-WALL_THICKNESS-0.08-attachment_inset))
func rebuild() -> void:
	if not roof_curvature_error().is_empty():
		_pending=false
		if Engine.is_editor_hint(): update_configuration_warnings()
		return
	prepare_attachment()
	super.rebuild()
	var stairs := stair_component()
	if stairs:
		stairs.visible=roof_access_error().is_empty() and stairs.enabled
		if is_instance_valid(stairs.visual): stairs.visual.free()
		if stairs.visible: stairs.rebuild(_material(Vector2(0.5,0),Color(0.60,0.53,0.46)))
	if canopy_roof==2 and is_instance_valid(_generated):
		var collision := _generated.get_node_or_null("HouseCollision")
		if collision:
			var shape := CollisionShape3D.new(); shape.shape=_generated.get_node("Roof").mesh.create_trimesh_shape(); collision.add_child(shape)
		var roof: MeshInstance3D=_generated.get_node("Roof")
		if roof_is_walkable(): roof.mesh=preload("res://addons/house_builder/flagstone_floor.gd").apply(self,roof.mesh)
func volume_error() -> String:
	var host := volume_host()
	if not attached: return ""
	if host==null: return "Il corpo accessorio deve stare in Casa / Volumes."
	if (host.has_method("volume_host") and not host.has_method("supports_accessory_volumes")) or host.wing_enabled or wing_enabled: return "Aggancio supportato al corpo principale senza ala legacy."
	if absf(host_offset*host.wall_length(host_wall)*0.5)+width*0.5>host.wall_length(host_wall)*0.5-0.25: return "Il volume supera il bordo della facciata: riduci larghezza o spostamento."
	if roof_junction:
		if structure_kind!=0 or canopy_roof!=0 or junction_mode!=0 or host_wall<2: return "Il raccordo alto richiede un corpo chiuso a due falde sul fianco del tetto principale."
		if attachment_elevation<3.0 or attachment_elevation>=host.wall_height: return "Il corpo alto deve partire ad almeno 3 metri e sotto la gronda."
		if attachment_elevation+roof_top()>host.wall_height+host.roof_height-0.25: return "Il colmo secondario deve restare sotto quello principale."
		# Bury the whole rear gable inside the host roof, not just its bottom.
		var rear_x: float = host.width*.5-WALL_THICKNESS-0.08-attachment_inset
		var host_surface: float = host.wall_height+host.roof_height*(1.0-absf(rear_x)/(host.width*.5))
		if attachment_elevation+roof_top()>host_surface-0.12: return "Aumenta l'inserimento: il timpano posteriore deve entrare completamente nel tetto principale."
		if depth-WALL_THICKNESS-0.08-attachment_inset<0.25: return "Il corpo deve sporgere almeno 25 cm dalla facciata."
	elif attachment_elevation+roof_top()>host.wall_height-0.15:
		return "Il tetto accessorio deve stare sotto la gronda; attiva Raccordo tetto per un corpo sopraelevato."
	elif attachment_inset>0.0 or attachment_elevation>0.0:
		return "Quota e inserimento aggiuntivi richiedono Raccordo tetto."
	if structure_kind==0 and junction_mode==1 and (junction_width>width-0.5 or junction_height>wall_height-0.2): return "La porta del raccordo supera il corpo: riduci larghezza o altezza della porta."
	for record in host.openings:
		var opening: Dictionary=host.resolved_opening(record)
		if opening.wall==host_wall and absf(opening.along-host_offset*host.wall_length(host_wall)*0.5)<(width+opening.width)*0.5+0.15:
			if opening.y+opening.height*.5<attachment_elevation-.15: continue
			if structure_kind==0 and opening.y-opening.height*0.5>roof_top()+0.15: continue
			if structure_kind==0: return "Il corpo copre un'apertura manuale della casa. Scegli una zona libera."
			if opening.y+opening.height*0.5>support_height(-depth*0.5+WALL_THICKNESS+0.08)-0.25: return "La copertura interferisce con un'apertura della casa: alza i sostegni o sposta la tettoia."
	for record in openings:
		if structure_kind==0 and int(record.get("wall",0))==1: return "La facciata posteriore è il raccordo: sposta la sua apertura su un lato libero."
	if host.get_parent() and host.get_parent().has_method("accessory_error"):
		var error: String=host.get_parent().accessory_error(self)
		if not error.is_empty(): return error
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
	var door_error := roof_door_error()
	if not door_error.is_empty(): return PackedStringArray([door_error])
	var access_error := roof_access_error()
	if not access_error.is_empty(): return PackedStringArray([access_error])
	return PackedStringArray() if structure_kind==1 else super._get_configuration_warnings()

func set_cutaway(enabled: bool,floor_base: float=0.0,storey_height: float=-1.0) -> void:
	# The parent passes floor heights in its own frame; an upper body has a
	# different local zero. Geometry remains collidable while upper visuals hide.
	var offset := attachment_elevation if attached and roof_junction else 0.0
	super.set_cutaway(enabled,floor_base-offset,storey_height)

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
		super._build_shell()
		if attachment_elevation>0.0:
			_box(Vector3(0,.06,0),Vector3(width,.12,depth),2 if masonry_trim else 1)
			if not masonry_trim:
				for x in [-width*.5+.2,width*.5-.2]:
					_beam(Vector3(x,-.42,depth*.5-.9),Vector3(x,0,depth*.5-.12),.18)
		return
	if canopy_roof!=0:
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
	if canopy_roof==2: return _flat_roof()
	return RoofMesh.new().generate(width,depth,wall_height,roof_height,house_seed,weathered,structure_kind==1 and canopy_roof==1,roof_curvature)

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
	return support_height(point.z) if canopy_roof!=0 else wall_height+RoofProfile.height_at(width*.5,roof_height,roof_curvature,point.x)

func _build_links() -> void:
	var links := get_node_or_null("FrameLinks")
	if links==null: return
	for link in links.get_children():
		if not link.has_method("segments"): continue
		link.update_gizmos()
		if Engine.is_editor_hint(): link.update_configuration_warnings()
		for segment in link.segments(): _beam(segment[0],segment[1],segment[2])

func roof_top() -> float:
	return wall_height+0.18+(roof_height if parapet_enabled else 0.0) if canopy_roof==2 else wall_height+roof_height

func _build_gables() -> void:
	if canopy_roof!=2: super._build_gables()

func _volume_planes(size: Vector2,rise: float,frame: Transform3D,padding: float=0.0) -> Array:
	if canopy_roof!=2: return super._volume_planes(size,rise,frame,padding)
	var result: Array=[]
	for pair in [[Vector3.RIGHT,size.x*0.5],[Vector3.LEFT,size.x*0.5],[Vector3.BACK,size.y*0.5],[Vector3.FORWARD,size.y*0.5],[Vector3.DOWN,0.0],[Vector3.UP,wall_height+0.18]]:
		var axis: Vector3=frame.basis*pair[0]
		result.append(Plane(axis,axis.dot(frame.origin)+float(pair[1])+padding))
	return result

func _flat_roof() -> ArrayMesh:
	var previous := _buffers
	_buffers=[]
	for i in 4:
		var buffer := SurfaceTool.new(); buffer.begin(Mesh.PRIMITIVE_TRIANGLES); _buffers.append(buffer)
	_build_roof_slab()
	if parapet_enabled:
		for wall in wall_count():
			var length := wall_length(wall)
			var spans: Array[Vector2]=[Vector2(-length*0.5,length*0.5)]
			if has_roof_access() and wall==stair_wall():
				var half: float=stair_component().width*0.5+0.05
				spans=[Vector2(-length*0.5,stair_center()-half),Vector2(stair_center()+half,length*0.5)]
			spans=connection_spans(wall,spans)
			for span in spans:
				if span.y-span.x<0.01: continue
				_build_parapet_span(wall,span,length)

	var mesh := ArrayMesh.new()
	var stone_material := ShaderMaterial.new(); stone_material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
	var materials := [_plaster_material(),_material(Vector2(0.5,0),Color(0.60,0.53,0.46)),_material(Vector2(0,0.5),Color(0.65,0.63,0.59)),stone_material]
	for i in 4:
		var arrays := _buffers[i].commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX]==null: continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); mesh.surface_set_material(mesh.get_surface_count()-1,materials[i])
	_buffers=previous
	return mesh

# Shared stair interface: terrace and roof access use the same authored stair.
func changed() -> void: request_rebuild()
func house() -> Node3D: return self
func effective_elevation() -> float: return wall_height+0.18
func stair_component() -> Node3D:
	for child in get_children():
		if child.has_method("terrace"): return child
	return null
func stair_ground() -> float:
	var stairs := stair_component()
	return stairs.ground_level if stairs else 0.0
func stair_edge_length() -> float:
	var stairs := stair_component()
	return width if stairs==null or stairs.side==0 else depth
func stair_center() -> float:
	var stairs := stair_component()
	return stairs.offset*maxf(0,(stair_edge_length()-stairs.width)*0.5-0.2) if stairs else 0.0
func stair_run() -> float: return (effective_elevation()-stair_ground())/tan(deg_to_rad(32.0))+0.45
func stair_frame() -> Transform3D:
	var wall := stair_wall()
	var tangent := (wall_point(wall,1,0)-wall_point(wall,0,0)).normalized()
	return Transform3D(Basis(tangent,Vector3.UP,wall_normal(wall)),wall_point(wall,stair_center(),effective_elevation(),0.05))
func roof_access_error() -> String:
	var stairs := stair_component()
	if stairs==null or not stairs.enabled: return ""
	if canopy_roof!=2: return "Accesso tetto sospeso: scegli una copertura piana."
	var count := 0
	for child in get_children():
		if child.has_method("terrace"): count+=1
	if count>1: return "Accesso tetto: una sola scala per volume in questa versione."
	if stairs.width>stair_edge_length()-0.4: return "Scala troppo larga per il bordo del tetto."
	if effective_elevation()-stair_ground()<0.3: return "La scala deve salire almeno 30 cm dal terreno."
	return ""
func has_roof_access() -> bool:
	var stairs := stair_component()
	return stairs!=null and stairs.enabled and roof_access_error().is_empty()

func roof_door_record() -> Dictionary:
	var host := volume_host()
	var along: float=host_offset*host.wall_length(host_wall)*0.5+roof_door_offset*maxf(0,(width-1.2)*0.5-0.2)
	return {"kind":"door","wall":host_wall,"u":along/(host.wall_length(host_wall)*0.5),"floor_y":effective_elevation(),"width":1.2,"height":2.0,"open":roof_door_open,"volume_id":volume_id,"roof_entry":true}
func roof_door_error() -> String:
	if not roof_door_enabled: return ""
	var host := volume_host()
	if not attached or canopy_roof!=2 or host==null: return "Porta tetto sospesa: serve un tetto piano agganciato alla casa."
	var level: Node3D=host.authored_floor(roof_door_floor_id)
	if level==null: return "Porta tetto sospesa: piano interno collegato mancante."
	if absf(host.floor_elevation(roof_door_floor_id,-100)-effective_elevation())>0.06: return "Porta tetto sospesa: quota del tetto e piano interno non coincidono (tolleranza 6 cm)."
	if effective_elevation()+2.12>host.wall_height: return "Porta tetto sospesa: muro troppo basso sopra la soletta."
	if not volume_error().is_empty(): return "Porta tetto sospesa: correggi il raccordo del volume."
	if width<1.6: return "Tetto troppo stretto per la porta."
	var candidate: Dictionary=host.resolved_opening(roof_door_record())
	for record in host.openings:
		var opening: Dictionary=host.resolved_opening(record)
		if opening.wall==candidate.wall and absf(opening.along-candidate.along)<(opening.width+candidate.width)*0.5+0.16 and absf(opening.y-candidate.y)<(opening.height+candidate.height)*0.5+0.16: return "Porta tetto sovrapposta a un'apertura manuale: spostala."
	return ""

func _parapet_block(wall: int,along: float,y: float,w: float,h: float,thick: float,offset: float,_mat: int) -> void:
	var count := maxi(1,ceili(w/0.8)); var rows := maxi(1,ceili(h/0.38))
	var sample=preload("res://addons/house_builder/stone_wall_sample.gd").new()
	var tangent := (wall_point(wall,1,0)-wall_point(wall,0,0)).normalized()
	for row in rows:
		for i in count:
			sample._rng.seed=house_seed+wall*131+i*17+row*359+int(along*97+y*53)
			sample._surface=SurfaceTool.new(); sample._surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			sample.stone(Vector3.ZERO,maxf(0.01,w/count-0.009),maxf(0.01,h/rows-0.006))
			var arrays: Array=sample._surface.commit_to_arrays()
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
			var frame := Transform3D(Basis(tangent,Vector3.UP,wall_normal(wall)*thick/0.53),wall_point(wall,along-w*0.5+(i+0.5)*w/count,y-h*0.5+(row+0.5)*h/rows,offset))
			for t in range(0,vertices.size(),3):
				_buffers[3].set_color(colors[t])
				_tri(frame*vertices[t],frame*vertices[t+2],frame*vertices[t+1],3)
	sample.free()

func _build_parapet_span(wall: int,span: Vector2,length: float) -> void:
	if not battlements_enabled:
		_parapet_block(wall,(span.x+span.y)*0.5,effective_elevation()+roof_height*0.5,span.y-span.x,roof_height,0.18,-0.09,0)
		_parapet_block(wall,(span.x+span.y)*0.5,roof_top(),span.y-span.x,0.08,0.24,-0.09,2)
		return
	var base := roof_height*0.45
	_parapet_block(wall,(span.x+span.y)*0.5,effective_elevation()+base*0.5,span.y-span.x,base,0.22,-0.11,0)
	_parapet_block(wall,(span.x+span.y)*0.5,effective_elevation()+base,span.y-span.x,0.06,0.26,-0.11,2)
	var count := maxi(2,roundi(length/battlement_spacing)); var step := length/count
	for i in count+1:
		var center: float=-length*0.5+i*step
		var low := maxf(span.x,center-step*0.27); var high := minf(span.y,center+step*0.27)
		if high-low<0.01: continue
		_parapet_block(wall,(low+high)*0.5,effective_elevation()+base+(roof_height-base)*0.5,high-low,roof_height-base,0.22,-0.11,0)
		_parapet_block(wall,(low+high)*0.5,roof_top(),high-low,0.08,0.28,-0.11,2)

func _build_roof_slab() -> void:
	_box(Vector3(0,wall_height+0.09,0),Vector3(width+0.24,0.18,depth+0.24),2)

func stair_wall() -> int:
	var stairs := stair_component()
	return [0,2,3][stairs.side] if stairs else 0

func connection_spans(_wall: int,spans: Array[Vector2]) -> Array[Vector2]: return spans

func roof_is_walkable() -> bool: return canopy_roof==2

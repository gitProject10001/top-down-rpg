@tool
extends Node3D
signal recipe_applied
## Generated meshes/materials have been replaced; presentation can rebind locally.
signal rebuilt
## Exterior authoring node. Only dimensions/opening records are serialized.
const RoofMesh=preload("res://addons/house_builder/roof_mesh.gd")
const MeshJoin=preload("res://addons/house_builder/mesh_join.gd")
const Door=preload("res://addons/house_builder/door.gd")
const ArchitectureProfile=preload("res://addons/house_builder/architecture_profile.gd")
const BuildingRecipe=preload("res://addons/house_builder/building_recipe.gd")
@export_group("Architettura")
@export var architecture_profile: ArchitectureProfile
@export_enum("dwelling","shop","hall","forge","tower","keep","inn","stable","chapel") var archetype_id := "dwelling"
@export_storage var authoring_version := 1
@export_storage var profile_baseline: Dictionary={}
@export var building_recipe: BuildingRecipe
@export_storage var recipe_provenance: Dictionary = {}
var _recipe_retired: Dictionary = {}
var _recipe_notification_pending := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in _recipe_retired.values():
			if is_instance_valid(node) and node.get_parent() == null: node.free()

@export_group("Dimensioni")
var _is_wing_part := false
const WALL_THICKNESS := 0.24
@export_range(1.8,20.0,0.1) var width := 4.2:
	set(value): width=clampf(value,1.8,20.0); request_rebuild()
@export_range(1.8,24.0,0.1) var depth := 5.0:
	set(value): depth=clampf(value,1.8,24.0); request_rebuild()
@export_range(1.8,10.5,0.1) var wall_height := 2.6:
	set(value): wall_height=clampf(value,1.8,10.5); request_rebuild()
@export_range(0.5,6.0,0.1) var roof_height := 2.1:
	set(value): roof_height=clampf(value,0.01 if _is_wing_part else 0.5,6.0); request_rebuild()
@export_enum("Intonaco", "Pietra") var wall_finish := 0:
	set(value): wall_finish=value; request_rebuild()
## Stone cornices and corner piers instead of the exposed timber grid.
@export var masonry_trim := false:
	set(value): masonry_trim=value; request_rebuild()
@export var weathered := true:
	set(value): weathered=value; request_rebuild()
@export var house_seed := 416522:
	set(value): house_seed=value; request_rebuild()
@export var openings: Array[Dictionary]=[]:
	set(value): openings=value.duplicate(true); request_rebuild()
@export_group("Articolazione della facciata")
## Exterior rhythm only: this never creates or changes InteriorPlan floors.
@export_range(0.0,5.0,0.1) var facade_storey_height := 0.0:
	set(value): facade_storey_height=maxf(0.0,value); request_rebuild()
@export var facade_upper_windows := false:
	set(value): facade_upper_windows=value; request_rebuild()
@export_group("Ala laterale")
@export var wing_enabled := false:
	set(value): wing_enabled=value; request_rebuild()
@export_range(1.8,12.0,0.1) var wing_width := 3.0:
	set(value): wing_width=clampf(value,1.8,12.0); request_rebuild()
@export_range(1.0,16.0,0.1) var wing_length := 3.5:
	set(value): wing_length=clampf(value,1.0,16.0); request_rebuild()
@export_enum("Destra", "Sinistra") var wing_side := 0:
	set(value): wing_side=clampi(value,0,1); request_rebuild()
@export_enum("Davanti", "Dietro") var wing_anchor := 0:
	set(value): wing_anchor=clampi(value,0,1); request_rebuild()
var _pending := false
var _cooldown := 0.0
var _collision_shell: ArrayMesh
var _generated: Node3D
var _buffers: Array[SurfaceTool]=[]
var build_count := 0

func wing_span() -> float: return minf(wing_width,minf(maxf(1.8,depth-0.6),width))
func wing_transform() -> Transform3D:
	var side := 1.0 if wing_side==0 else -1.0
	return Transform3D(Basis(Vector3.UP,side*PI*0.5),Vector3(side*(width*0.5+wing_length)*0.5,0,(depth-wing_span())*0.5*(1.0 if wing_anchor==0 else -1.0)))
func wing_settings() -> Dictionary:
	return {"enabled":wing_enabled,"width":wing_width,"length":wing_length,"side":wing_side,"anchor":wing_anchor}
func set_wing_settings(value: Dictionary) -> void:
	wing_enabled=value.enabled; wing_width=value.width; wing_length=value.length
	wing_side=value.side; wing_anchor=value.anchor
func _wall_frame(wall: int) -> Transform3D: return wing_transform() if wall>=4 else Transform3D.IDENTITY
func _wall_size(wall: int) -> Vector2:
	return Vector2(wing_span(),width*0.5+wing_length) if wall>=4 else Vector2(width,depth)

func _ready() -> void:
	rebuild()
func request_rebuild() -> void:
	_pending=true
	if is_inside_tree(): update_gizmos()
func _process(delta: float) -> void:
	_cooldown=maxf(0.0,_cooldown-delta)
	if _pending and _cooldown<=0.0:
		rebuild()
		_cooldown=0.10

func dimensions() -> Vector4:
	return Vector4(width,depth,wall_height,roof_height)
func set_dimensions(value: Vector4) -> void:
	width=value.x; depth=value.y; wall_height=value.z; roof_height=value.w

func wall_count() -> int: return 8 if wing_enabled else 4

func wall_length(wall: int) -> float:
	var size := _wall_size(wall)
	return size.x if wall%4<2 else size.y
func wall_point(wall: int, along: float, y: float, outset: float=0.0) -> Vector3:
	var size := _wall_size(wall)
	var p := Vector3.ZERO
	match wall%4:
		0: p=Vector3(along,y,size.y*0.5+outset)
		1: p=Vector3(-along,y,-size.y*0.5-outset)
		2: p=Vector3(size.x*0.5+outset,y,-along)
		_: p=Vector3(-size.x*0.5-outset,y,along)
	return _wall_frame(wall)*p
func wall_normal(wall: int) -> Vector3:
	return _wall_frame(wall).basis*[Vector3.BACK,Vector3.FORWARD,Vector3.RIGHT,Vector3.LEFT][wall%4]
func wall_exposed(wall: int,along: float,margin: float=0.0) -> bool:
	if not wing_enabled: return wall<4
	for offset in [-margin,0.0,margin]:
		var p := wall_point(wall,along+offset,wall_height*0.5,0.02)
		var q := wing_transform().affine_inverse()*p if wall<4 else p
		var size := _wall_size(4 if wall<4 else 0)
		if absf(q.x)<size.x*0.5 and absf(q.z)<size.y*0.5: return false
	return true
func opening_position(index: int) -> Vector3:
	var o := resolved_opening(openings[index])
	return wall_point(o.wall,o.along,o.y,0.12)
func opening_fits(record: Dictionary,ignore_index: int=-1) -> bool:
	var a := resolved_opening(record)
	if not wall_exposed(a.wall,a.along,a.width*0.5+0.12): return false
	for i in openings.size():
		if i==ignore_index: continue
		var b := resolved_opening(openings[i])
		if b.wall>=wall_count(): continue
		var normal := wall_normal(a.wall)
		var delta := wall_point(a.wall,a.along,a.y)-wall_point(b.wall,b.along,b.y)
		var tangent := (wall_point(a.wall,1,0)-wall_point(a.wall,0,0)).normalized()
		# Coplanar main/wing facades are one placement surface at their join.
		if normal.dot(wall_normal(b.wall))>0.99 and absf(normal.dot(delta))<0.03 and absf(tangent.dot(delta))<(a.width+b.width)*0.5+0.16 and absf(delta.y)<(a.height+b.height)*0.5+0.16: return false
	return true
func _get_configuration_warnings() -> PackedStringArray:
	for i in openings.size():
		if int(openings[i].get("wall",0))>=wall_count(): continue
		if not opening_fits(openings[i],i): return PackedStringArray(["Un'apertura è coperta dall'ala o troppo vicina a un'altra: spostala su una parete libera."])
	return PackedStringArray()
func _post_segments(wall: int,along: float) -> Array[Vector2]:
	var spans: Array[Vector2]=[Vector2(0,wall_height)]
	for record in all_openings():
		var o := resolved_opening(record)
		if o.wall!=wall or absf(o.along-along)>o.width*0.5+0.15: continue
		var next: Array[Vector2]=[]
		for span in spans:
			var low: float=o.y-o.height*0.5-0.12
			var high: float=o.y+o.height*0.5+0.12
			if high<=span.x or low>=span.y: next.append(span)
			else:
				if low>span.x: next.append(Vector2(span.x,low))
				if high<span.y: next.append(Vector2(high,span.y))
		spans=next
	return spans
func resolved_opening(record: Dictionary) -> Dictionary:
	var wall := clampi(int(record.get("wall",0)),0,wall_count()-1)
	var door: bool=record.get("kind","window")=="door"
	var w := clampf(float(record.get("width",0.85 if not door else 1.0)),0.35,wall_length(wall)-0.4)
	var h := clampf(float(record.get("height",1.0 if not door else 2.0)),0.35,wall_height-0.25)
	var along := clampf(float(record.get("u",0.0))*(wall_length(wall)*0.5),-wall_length(wall)*0.5+w*0.5+0.18,wall_length(wall)*0.5-w*0.5-0.18)
	var y := clampf(opening_floor_y(record),0.0,maxf(0,wall_height-h-0.12))+h*0.5 if door else clampf(float(record.get("y",1.5)),h*0.5+0.25,wall_height-h*0.5-0.12)
	return {"wall":wall,"along":along,"y":y,"width":w,"height":h,"door":door}

func hit_wall(world_origin: Vector3,world_direction: Vector3) -> Dictionary:
	var origin := to_local(world_origin)
	var direction := global_basis.inverse()*world_direction
	var closest := INF
	var result := {}
	for wall in (8 if wing_enabled else 4):
		var normal := wall_normal(wall)
		if normal.dot(direction)>=-0.0001: continue
		var p=Plane(normal,wall_point(wall,0,0)).intersects_ray(origin,direction)
		if p==null: continue
		var q: Vector3=_wall_frame(wall).affine_inverse()*p
		var along: float=q.x if wall%4==0 else (-q.x if wall%4==1 else (-q.z if wall%4==2 else q.z))
		if absf(along)>wall_length(wall)*0.5 or p.y<0 or p.y>wall_height: continue
		if not wall_exposed(wall,along): continue
		var distance := world_origin.distance_to(to_global(p))
		if distance<closest:
			closest=distance
			result={"house":self,"wall":wall,"u":along/(wall_length(wall)*0.5),"y":p.y,"position":to_global(p),"distance":distance}
	return result

func _tri(a: Vector3,b: Vector3,c: Vector3,mat: int) -> void:
	var normal := (b-a).cross(c-a).normalized()
	for p in [a,c,b]:
		_buffers[mat].set_normal(normal)
		_buffers[mat].set_uv(Vector2(p.x,p.y))
		_buffers[mat].add_vertex(p)
func _box(center: Vector3,size: Vector3,mat: int) -> void:
	var p: Array[Vector3]=[]
	for xyz in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]:
		p.append(center+xyz*size*0.5)
	for face in [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]:
		_tri(p[face[0]],p[face[1]],p[face[2]],mat)
		_tri(p[face[0]],p[face[2]],p[face[3]],mat)
func _wall_box(wall: int,along: float,y: float,w: float,h: float,thick: float,offset: float,mat: int) -> void:
	var normal := wall_normal(wall).abs()
	_box(wall_point(wall,along,y,offset),Vector3(thick,h,w) if normal.x>0.5 else Vector3(w,h,thick),mat)
func _beam(a: Vector3,b: Vector3,thick: float,mat: int=1) -> void:
	var axis := (b-a).normalized()
	var reference := Vector3.UP if absf(axis.dot(Vector3.FORWARD))>0.99 else Vector3.FORWARD
	var right := axis.cross(reference).normalized()*thick*0.5
	var back := axis.cross(right).normalized()*thick*0.5
	var p := [a-right-back,a+right-back,a+right+back,a-right+back,b-right-back,b+right-back,b+right+back,b-right+back]
	for face in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]:
		_tri(p[face[0]],p[face[1]],p[face[2]],mat)
		_tri(p[face[0]],p[face[2]],p[face[3]],mat)
func _material(quadrant: Vector2,tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader=load("res://shaders/pixelart/painted_architecture.gdshader")
	m.set_shader_parameter("atlas",load("res://assets/textures/hearth_painted/architecture_clear_v2.png"))
	m.set_shader_parameter("quadrant",quadrant)
	m.set_shader_parameter("tint",tint)
	m.set_shader_parameter("metres",2.5)
	m.set_shader_parameter("detail_lod",1.0)
	m.set_shader_parameter("plain_vertical_stone",preload("res://addons/house_builder/masonry_cladding.gd").supported(self))
	return m

func _mortar_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
	material.set_shader_parameter("use_vertex_color",false)
	material.set_shader_parameter("base_color",Vector3(0.16,0.155,0.14))
	return material

func _plaster_material() -> ShaderMaterial:
	if wall_finish==1:
		if preload("res://addons/house_builder/masonry_cladding.gd").supported(self): return _mortar_material()
		return _material(Vector2(0,0.5),Color(0.65,0.63,0.59))
	var material := ShaderMaterial.new()
	material.shader=preload("res://addons/house_builder/plaster.gdshader")
	var random := RandomNumberGenerator.new()
	random.seed=house_seed
	material.set_shader_parameter("pattern_offset",Vector3(random.randf_range(-100,100),random.randf_range(-100,100),random.randf_range(-100,100)))
	material.set_shader_parameter("weathered",weathered)
	material.set_shader_parameter("exposed_masonry",preload("res://addons/house_builder/masonry_cladding.gd").supported(self))
	material.set_shader_parameter("masonry_height",wall_height)
	return material

func rebuild() -> void:
	if not is_inside_tree(): _pending=true; return
	_pending=false
	build_count+=1
	if is_instance_valid(_generated): _generated.free()
	_generated=Node3D.new()
	_generated.name="_Generated"
	add_child(_generated,false,Node.INTERNAL_MODE_BACK)
	_buffers.clear()
	for i in 4:
		var buffer := SurfaceTool.new()
		buffer.begin(Mesh.PRIMITIVE_TRIANGLES)
		_buffers.append(buffer)
	_build_shell()
	var dark := StandardMaterial3D.new()
	dark.albedo_color=Color(0.015,0.011,0.009)
	dark.roughness=1.0
	var materials := [_plaster_material(),_material(Vector2(0.5,0),Color(0.60,0.53,0.46)),_material(Vector2(0,0.5),Color(0.65,0.63,0.59)),dark]
	var mesh := ArrayMesh.new()
	for i in _buffers.size():
		var arrays := _buffers[i].commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX]==null: continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,materials[i])
	var body := MeshInstance3D.new()
	body.name="Walls"
	body.mesh=mesh
	_generated.add_child(body)
	var roof := MeshInstance3D.new()
	roof.name="Roof"
	roof.mesh=_build_roof()
	_generated.add_child(roof)
	_collision_shell=body.mesh
	if wing_enabled: _join_wing(body,roof)
	preload("res://addons/house_builder/masonry_cladding.gd").append_to(self,body)
	_clip_authored_volumes(body,roof)
	if not _is_wing_part: _finish_openings(body,materials)
	for component in attached_components(): component.refresh()
	for volume in authored_volumes(): volume.rebuild()
	var plan := get_node_or_null("InteriorPlan")
	if plan and plan.has_method("editor_view"):
		plan._pending=true
	update_gizmos()
	if Engine.is_editor_hint(): update_configuration_warnings()
	rebuilt.emit()
	if _recipe_notification_pending:
		_recipe_notification_pending=false
		recipe_applied.emit()

func _build_roof() -> ArrayMesh:
	return RoofMesh.new().generate(width,depth,wall_height,roof_height,house_seed,weathered)

func _build_shell() -> void:
	# Hollow shell: the inner face is 24 cm behind the exterior face.
	_box(Vector3(0,-0.045,0),Vector3(width,0.09,depth),3)
	for wall in 4:
		var length := wall_length(wall)
		_wall_box(wall,0,wall_height*0.5,length,wall_height,WALL_THICKNESS,-WALL_THICKNESS*0.5,0)
		_wall_box(wall,0,0.14,length+0.10,0.28,WALL_THICKNESS+0.10,-WALL_THICKNESS*0.5,2)
		if masonry_trim:
			for y in [0.34,wall_height-0.10]: _wall_box(wall,0,y,length+0.18,0.22,0.24,0.03,2)
			for side in [-1.0,1.0]:
				var edge: float=side*(length*.5-.18)
				for span in _post_segments(wall,edge): _wall_box(wall,edge,(span.x+span.y)*.5,.36,span.y-span.x,.26,.045,2)
			continue
		for y in [0.32,wall_height-0.08]: _wall_box(wall,0,y,length+0.12,0.14,0.14,0.04,1)
		if facade_storey_height>1.5 and facade_storey_height<wall_height-1.2:
			_wall_box(wall,0,facade_storey_height,length+0.22,0.24,0.23,0.08,1)
			for side in [-1.0,1.0]:
				var edge: float=side*(length*0.5-0.16)
				_beam(wall_point(wall,edge,facade_storey_height+0.22,0.10),wall_point(wall,edge-side*.72,facade_storey_height+1.0,0.10),0.14)
		var posts := maxi(1,roundi(length/1.7))
		for i in posts+1:
			var along := -length*0.5+i*length/posts
			for span in _post_segments(wall,along): _wall_box(wall,along,(span.x+span.y)*0.5,0.13,span.y-span.x,0.14,0.055,1)
	_build_gables()

func _build_gables() -> void:
	for side in [-1.0,1.0]:
		var a := Vector3(-width*0.5,wall_height,side*depth*0.5)
		var b := Vector3(width*0.5,wall_height,side*depth*0.5)
		var c := Vector3(0,wall_height+roof_height,side*depth*0.5)
		_tri(a,b,c,0) if side>0 else _tri(a,c,b,0)
		_beam(a,c,0.22 if masonry_trim else 0.12,2 if masonry_trim else 1); _beam(b,c,0.22 if masonry_trim else 0.12,2 if masonry_trim else 1)
		if not masonry_trim: _box(Vector3(0,wall_height+roof_height*0.5,side*(depth*0.5+0.035)),Vector3(0.12,roof_height,0.12),1)
	_box(Vector3(0,wall_height+roof_height+0.06,0),Vector3(0.20,0.18,depth+0.7),2) if masonry_trim else _box(Vector3(0,wall_height+roof_height+0.06,0),Vector3(0.13,0.15,depth+0.7),1)

func _volume_planes(size: Vector2,rise: float,frame: Transform3D,padding: float=0.0) -> Array:
	var planes: Array=[]
	for pair in [[Vector3.RIGHT,size.x*0.5+padding],[Vector3.LEFT,size.x*0.5+padding],[Vector3.BACK,size.y*0.5+padding],[Vector3.FORWARD,size.y*0.5+padding],[Vector3.DOWN,padding]]:
		var normal: Vector3=frame.basis*pair[0]
		planes.append(Plane(normal,float(pair[1])+normal.dot(frame.origin)))
	for sign_value in [-1.0,1.0]:
		var n := Vector3(sign_value*rise/(size.x*0.5),1,0)
		var normal := frame.basis*n
		planes.append(Plane(normal.normalized(),(wall_height+rise+padding+normal.dot(frame.origin))/normal.length()))
	return planes

func _roof_cutters(own_size: Vector2,own_rise: float,own_frame: Transform3D,other_size: Vector2,other_rise: float,other_frame: Transform3D) -> Array:
	var result: Array=[]
	for own_sign in [-1.0,1.0]:
		for other_sign in [-1.0,1.0]:
			var planes: Array=[]
			for pair in [[Vector3.RIGHT,other_size.x*0.5+0.3],[Vector3.LEFT,other_size.x*0.5+0.3],[Vector3.BACK,other_size.y*0.5+0.3],[Vector3.FORWARD,other_size.y*0.5+0.3]]:
				var n: Vector3=other_frame.basis*pair[0]
				planes.append(Plane(n,float(pair[1])+n.dot(other_frame.origin)))
			var own_axis: Vector3= own_frame.basis.x*(-own_sign)
			var other_axis: Vector3= other_frame.basis.x*(-other_sign)
			planes.append(Plane(own_axis,own_axis.dot(own_frame.origin)))
			planes.append(Plane(other_axis,other_axis.dot(other_frame.origin)))
			var own_gradient: Vector3= own_frame.basis.x*(-own_sign*own_rise/(own_size.x*0.5))
			var other_gradient: Vector3= other_frame.basis.x*(-other_sign*other_rise/(other_size.x*0.5))
			var difference: Vector3= own_gradient-other_gradient
			var limit: float= other_rise-other_gradient.dot(other_frame.origin)-own_rise+own_gradient.dot(own_frame.origin)
			planes.append(Plane(difference.normalized(),limit/difference.length()))
			result.append(planes)
	return result

func _join_wing(body: MeshInstance3D,roof: MeshInstance3D) -> void:
	# Build the same reusable volume, then merge only its exposed geometry.
	var wing=get_script().new()
	wing._is_wing_part=true
	wing.width=wing_span(); wing.depth=width*0.5+wing_length
	wing.wall_height=wall_height; wing.roof_height=roof_height*wing_span()/width
	wing.weathered=weathered; wing.house_seed=house_seed+1039
	var records: Array[Dictionary]=[]
	for record in openings:
		if int(record.get("wall",0))>=4:
			var copy: Dictionary=record.duplicate(true)
			copy.wall=int(copy.wall)-4; records.append(copy)
	wing.openings=records
	_generated.add_child(wing)
	var frame := wing_transform()
	var main_size := Vector2(width,depth)
	var wing_size := Vector2(wing.width,wing.depth)
	wing._generated.get_child(0).mesh.surface_set_material(0,body.mesh.surface_get_material(0))
	var merged := ArrayMesh.new()
	MeshJoin.append(merged,body.mesh,Transform3D.IDENTITY,[_volume_planes(wing_size,wing.roof_height,frame,0.002)])
	MeshJoin.append(merged,wing._generated.get_child(0).mesh,frame,[_volume_planes(main_size,roof_height,Transform3D.IDENTITY,-0.002)])
	body.mesh=merged
	var collision_merged := ArrayMesh.new()
	MeshJoin.append(collision_merged,_collision_shell,Transform3D.IDENTITY,[_volume_planes(wing_size,wing.roof_height,frame,0.002)])
	MeshJoin.append(collision_merged,wing._collision_shell,frame,[_volume_planes(main_size,roof_height,Transform3D.IDENTITY,-0.002)])
	_collision_shell=collision_merged
	# Both surfaces are cut on the same vertical valley planes, preserving tile relief.
	var joined_roof := ArrayMesh.new()
	MeshJoin.append(joined_roof,roof.mesh,Transform3D.IDENTITY,_roof_cutters(main_size,roof_height,Transform3D.IDENTITY,wing_size,wing.roof_height,frame))
	MeshJoin.append(joined_roof,wing._generated.get_node("Roof").mesh,frame,_roof_cutters(wing_size,wing.roof_height,frame,main_size,roof_height,Transform3D.IDENTITY))
	roof.mesh=joined_roof
	wing.free()

func _opening_cut(o: Dictionary) -> Array:
	var tangent := (wall_point(o.wall,1,0)-wall_point(o.wall,0,0)).normalized()
	var normal := wall_normal(o.wall)
	var center := wall_point(o.wall,o.along,o.y,-WALL_THICKNESS*0.5)
	var planes: Array=[]
	for pair in [[tangent,o.width*0.5],[-tangent,o.width*0.5],[Vector3.UP,o.height*0.5],[Vector3.DOWN,o.height*0.5+0.001],[normal,0.5],[-normal,0.5]]:
		var axis: Vector3=pair[0]
		planes.append(Plane(axis,axis.dot(center)+float(pair[1])))
	return planes

func _finish_openings(body: MeshInstance3D,materials: Array) -> void:
	var cutters: Array=[]
	var active: Array=[]
	var records := all_openings()
	for index in records.size():
		var record: Dictionary=records[index]
		var o := resolved_opening(record)
		if not wall_exposed(o.wall,o.along,o.width*0.5): continue
		o["index"]=index
		cutters.append(_opening_cut(o)); active.append(o)
	if not cutters.is_empty():
		var shell := ArrayMesh.new()
		MeshJoin.append(shell,body.mesh,Transform3D.IDENTITY,cutters)
		body.mesh=shell
		var collision_shell := ArrayMesh.new()
		MeshJoin.append(collision_shell,_collision_shell,Transform3D.IDENTITY,cutters)
		_collision_shell=collision_shell
	_buffers.clear()
	for i in 4:
		var buffer := SurfaceTool.new()
		buffer.begin(Mesh.PRIMITIVE_TRIANGLES); _buffers.append(buffer)
	for o in active:
		# Recessed jambs close the cut wall thickness, leaving the center empty.
		for sign_value in [-1.0,1.0]:
			_wall_box(o.wall,o.along+sign_value*(o.width*0.5+0.015),o.y,0.03,o.height,WALL_THICKNESS,-WALL_THICKNESS*0.5,0)
			_wall_box(o.wall,o.along+sign_value*(o.width*0.5+0.05),o.y,0.10,o.height+0.20,0.10,0.035,1)
		_wall_box(o.wall,o.along,o.y+o.height*0.5+0.015,o.width,0.03,WALL_THICKNESS,-WALL_THICKNESS*0.5,0)
		_wall_box(o.wall,o.along,o.y+o.height*0.5+0.05,o.width+0.20,0.10,0.10,0.035,1)
		if o.door:
			var door := Door.new()
			door.name="Door_%d"%o.index
			_generated.add_child(door)
			var tangent := (wall_point(o.wall,1,0)-wall_point(o.wall,0,0)).normalized()
			var frame := Transform3D(Basis(tangent,Vector3.UP,wall_normal(o.wall)),wall_point(o.wall,o.along-o.width*0.5,o.y-o.height*0.5,-0.17))
			door.configure(frame,o.width,o.height,materials[1],bool(records[o.index].get("open",false)))
			if o.index<openings.size(): door.changed.connect(_door_changed.bind(o.index))
			elif records[o.index].has("volume_id"): door.changed.connect(_volume_door_changed.bind(records[o.index].volume_id,bool(records[o.index].get("roof_entry",false))))
			else: door.changed.connect(_component_door_changed.bind(records[o.index].get("component_id","")))
			# Contrasting threshold remains visible when the facade is cut away.
			_wall_box(o.wall,o.along,o.y-o.height*0.5+0.02,o.width,0.04,0.55,-0.08,2)
		else:
			_wall_box(o.wall,o.along,o.y-o.height*0.5-0.04,o.width+0.20,0.08,0.40,-0.08,2)
			_wall_box(o.wall,o.along,o.y,o.width-0.02,o.height-0.02,0.012,-0.22,3)
			_wall_box(o.wall,o.along,o.y,0.055,o.height,0.07,-0.16,1)
			_wall_box(o.wall,o.along,o.y,o.width,0.055,0.07,-0.16,1)
	var details := ArrayMesh.new()
	for i in 4:
		var arrays := _buffers[i].commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX]==null: continue
		details.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		details.surface_set_material(details.get_surface_count()-1,materials[i])
	var components := MeshInstance3D.new()
	components.name="OpeningDetails"; components.mesh=details
	_generated.add_child(components)
	# Static collision now follows walls and inset components instead of a solid box.
	var collision := StaticBody3D.new()
	collision.name="HouseCollision"
	for mesh in [_collision_shell,details]:
		if mesh.get_surface_count()==0: continue
		var shape := CollisionShape3D.new()
		shape.shape=mesh.create_trimesh_shape()
		collision.add_child(shape)
	_generated.add_child(collision)

func _door_changed(opened: bool,index: int) -> void:
	openings[index]["open"]=opened

func set_cutaway(enabled: bool,floor_base: float=0.0,storey_height: float=-1.0) -> void:
	if not is_instance_valid(_generated): return
	if storey_height<0.0: storey_height=wall_height
	for child in _generated.get_children():
		if child.name.begins_with("Cutaway"): child.visible=false
	for source_name in ["Walls","OpeningDetails"]:
		var source: MeshInstance3D=_generated.get_node(source_name)
		var cut_name := "Cutaway%s_%d"%[source_name,roundi(floor_base*100)]
		var cut: MeshInstance3D=_generated.get_node_or_null(cut_name)
		if enabled and cut==null:
			var mesh := ArrayMesh.new()
			var cutters: Array=cutaway_cutters(floor_base,storey_height)
			MeshJoin.append(mesh,source.mesh,Transform3D.IDENTITY,cutters)
			cut=MeshInstance3D.new(); cut.name=cut_name; cut.mesh=mesh
			_generated.add_child(cut)
		source.visible=not enabled
		if cut: cut.visible=enabled
	_generated.get_node("Roof").visible=not enabled
	for child in _generated.get_children():
		if child is Door: child.set_cutaway(enabled)
	for volume in authored_volumes(): volume.set_cutaway(enabled,floor_base,storey_height)
	for component in attached_components():
		if component.has_method("set_cutaway"): component.set_cutaway(enabled,floor_base,storey_height)
	var recipe_details := get_node_or_null("RecipeDetails")
	if recipe_details:
		for detail in recipe_details.get_children():
			if detail.has_method("set_cutaway"): detail.set_cutaway(enabled)


func architecture_state() -> Dictionary:
	return {"profile":architecture_profile,"version":authoring_version,"baseline":profile_baseline.duplicate(true),"values":{"width":width,"depth":depth,"wall_height":wall_height,"roof_height":roof_height}}
func inherited_dimension(key: String) -> bool:
	return profile_baseline.has(key) and is_equal_approx(float(get(key)),float(profile_baseline[key]))
func architecture_proposal(profile: ArchitectureProfile,adopt_proportions: bool=false) -> Dictionary:
	var state := architecture_state()
	state.profile=profile; state.version=2
	if profile==null: return state
	for key in profile.proportions():
		if adopt_proportions or inherited_dimension(key):
			state.values[key]=profile.proportions()[key]
			state.baseline[key]=state.values[key]
	return state
func apply_architecture(state: Dictionary) -> void:
	architecture_profile=state.profile; authoring_version=state.version
	profile_baseline=state.baseline.duplicate(true)
	for key in state.values: set(key,state.values[key])
	request_rebuild()

# Component doors are derived; deleting a component never deletes authored openings.
func attached_components() -> Array:
	var result: Array=[]
	var container := get_node_or_null("Components")
	if container:
		for child in container.get_children():
			if child.has_method("opening_record"): result.append(child)
	return result
func all_openings() -> Array[Dictionary]:
	var result: Array[Dictionary]=openings.duplicate(true)
	result.append_array(facade_openings())
	for component in attached_components():
		if component.validation_error().is_empty() and component.create_door and component.door_id.is_empty():
			result.append(component.opening_record())
	for volume in authored_volumes():
		if volume.attached and volume.structure_kind==0 and volume.junction_mode==1 and volume.volume_error().is_empty(): result.append(volume.junction_record())
		if volume.roof_door_enabled and volume.roof_door_error().is_empty(): result.append(volume.roof_door_record())
	return result
func facade_openings() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not facade_upper_windows or facade_storey_height<1.5 or facade_storey_height+2.0>wall_height: return result
	for wall in 4:
		var count := maxi(1,floori((wall_length(wall)-0.6)/2.0))
		for index in count:
			var record := {"kind":"window","wall":wall,"u":(float(index)+0.5)/count*2.0-1.0,
				"y":facade_storey_height+1.35,"width":0.92,"height":1.1,"facade_id":"upper_%d_%d"%[wall,index]}
			var covered := false
			for volume in authored_volumes():
				if not volume.attached or volume.structure_kind!=0 or not volume.volume_error().is_empty(): continue
				if volume.host_wall!=wall: continue
				var along: float=float(record.u)*wall_length(wall)*.5
				var volume_along: float=volume.host_offset*wall_length(wall)*.5
				if absf(along-volume_along)<(float(record.width)+volume.width)*.5+.15 and float(record.y)+float(record.height)*.5>volume.attachment_elevation and float(record.y)-float(record.height)*.5<volume.attachment_elevation+volume.roof_top(): covered=true; break
			if not covered and opening_fits(record): result.append(record)
	return result
func _volume_door_changed(opened: bool,id: String,roof_entry: bool=false) -> void:
	for volume in authored_volumes():
		if volume.volume_id==id:
			if roof_entry: volume.roof_door_open=opened
			else: volume.junction_open=opened
func _component_door_changed(opened: bool,id: String) -> void:
	for component in attached_components():
		if component.component_id==id: component.door_open=opened

func authored_floor(id: String) -> Node3D:
	var plan := get_node_or_null("InteriorPlan")
	if plan and not id.is_empty():
		for level in plan.levels():
			if str(level.get_meta("floor_id",""))==id: return level
	return null
func floor_elevation(id: String,fallback: float) -> float:
	var level := authored_floor(id)
	if level==null: return fallback
	var plan := level.get_parent()
	return plan.levels().find(level)*plan.floor_height
func opening_floor_y(record: Dictionary) -> float:
	return floor_elevation(str(record.get("floor_id","")),float(record.get("floor_y",0.0)))
func opening_by_id(id: String) -> Dictionary:
	if id.is_empty(): return {}
	for record in openings:
		if str(record.get("opening_id",""))==id: return record
	return {}

func authored_volumes() -> Array:
	var result: Array=[]
	var container := get_node_or_null("Volumes")
	if container:
		for child in container.get_children():
			if child.has_method("volume_host"): result.append(child)
	return result
func _clip_authored_volumes(body: MeshInstance3D,roof: MeshInstance3D) -> void:
	var cutters: Array=[]
	for volume in authored_volumes(): volume.prepare_attachment()
	for volume in authored_volumes():
		if volume.attached and volume.structure_kind==0 and volume.junction_mode==0 and volume.volume_error().is_empty(): cutters.append(volume._volume_planes(Vector2(volume.width,volume.depth),volume.roof_height,volume.transform,0.001))
	if has_method("volume_host") and get("attached"):
		var host: Node3D=call("volume_host")
		if host and call("volume_error").is_empty(): cutters.append(host._volume_planes(Vector2(host.width,host.depth),host.roof_height,transform.affine_inverse(),-0.001))
	if cutters.is_empty(): return
	var collision_clip := ArrayMesh.new(); MeshJoin.append(collision_clip,_collision_shell,Transform3D.IDENTITY,cutters); _collision_shell=collision_clip
	for instance in [body,roof]:
		var clipped := ArrayMesh.new(); MeshJoin.append(clipped,instance.mesh,Transform3D.IDENTITY,cutters); instance.mesh=clipped

func cutaway_cutters(floor_base: float,storey_height: float) -> Array:
	return [[Plane(Vector3.DOWN,-floor_base-storey_height)],[Plane(Vector3.LEFT,-width*0.5+0.35),Plane(Vector3.DOWN,-floor_base-0.8)],[Plane(Vector3.FORWARD,-depth*0.5+0.35),Plane(Vector3.DOWN,-floor_base-0.8)]]

func contains_footprint(point: Vector3,margin: float=0.0) -> bool:
	if absf(point.x)<width*0.5-margin and absf(point.z)<depth*0.5-margin: return true
	if wing_enabled:
		var local := wing_transform().affine_inverse()*point
		if absf(local.x)<wing_span()*0.5-margin and absf(local.z)<(width*0.5+wing_length)*0.5-margin: return true
	for volume in authored_volumes():
		if volume.attached and volume.structure_kind == 0 and volume.volume_error().is_empty():
			if point.y<volume.position.y-.15: continue
			if volume.contains_footprint(volume.transform.affine_inverse() * point, margin): return true
	return false

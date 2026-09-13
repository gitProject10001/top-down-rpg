@tool
extends Node3D
const Element=preload("res://addons/house_builder/plan_element.gd")
const Door=preload("res://addons/house_builder/door.gd")
const Generator=preload("res://addons/house_builder/plan_generator.gd")
var generation_report := ""
var generation_failed := false
@export_storage var known_generated: Dictionary={}
@export_storage var deleted_ids: Dictionary={}
var _retired: Dictionary={}
const MeshJoin=preload("res://addons/house_builder/mesh_join.gd")
@export_range(2.4,3.5,0.1) var floor_height := 2.6:
	set(v): floor_height=v; _pending=true
@export var seed_value := 416522
@export_range(2,10) var requested_rooms := 4
@export var preview_inside := true:
	set(v): preview_inside=v; _pending=true
@export_range(0,3) var active_floor := 0:
	set(v): active_floor=v; _pending=true
var _pending := true
var _signature := ""
var _wood: Material
var _wall: Material
var _floors: Node3D
func house() -> Node3D: return get_parent() as Node3D
func wood_material() -> Material:
	if _wood==null: _wood=house()._material(Vector2(0.5,0),Color(0.60,0.53,0.46))
	return _wood
func wall_material() -> Material:
	if _wall==null: _wall=house()._plaster_material()
	return _wall
func levels() -> Array[Node3D]:
	var list: Array[Node3D]=[]
	for child in get_children():
		if child is Node3D: list.append(child)
	return list
func elements() -> Array[Node3D]:
	var result: Array[Node3D]=[]
	for level in levels(): result.append_array(level_elements(level))
	return result
func level_elements(level: Node) -> Array[Node3D]:
	var result: Array[Node3D]=[]
	for child in level.get_children():
		if child is Element:
			result.append(child)
			if child.kind==0: result.append_array(level_elements(child))
	return result
func organize_furniture() -> void:
	for level in levels():
		var rooms: Dictionary={}
		for e in level.get_children():
			if e is Element and e.kind==0: rooms[e.stable_id]=e
		for e in level.get_children():
			if not e is Element or e.kind!=3 or e.room_ids.is_empty(): continue
			var room: Node3D=rooms.get(e.room_ids[0])
			if room==null: continue
			var saved_owner := e.owner
			e.reparent(room,true); e.owner=saved_owner
			if str(e.name).begins_with("Oggetto_furniture_"):
				e.name=["Tavolo","Sedia","Letto","Cassapanca","Scaffale"][e.prop_type]+"_"+str(e.stable_id).get_slice("_",str(e.stable_id).get_slice_count("_")-1)
func _ready() -> void:
	_pending=true
	organize_furniture.call_deferred()
func _process(_dt: float) -> void:
	if Engine.is_editor_hint(): observe_deletions()
	var signature := str(house().dimensions(),house().wing_settings(),floor_height,levels().size())
	for e in elements():
		if e.kind==2: signature+=str(e.transform,e.dimensions,e.roof_exit,e.guardrails_enabled)
	if signature!=_signature:
		_signature=signature; _pending=true
		if house().has_method("interior_floor_mesh"):
			house().request_rebuild()
			for e in elements():
				if e.kind==2 and e.roof_exit: e.dirty()
	if _pending: rebuild()
func rebuild() -> void:
	if not is_inside_tree(): return
	_pending=false
	var list := levels()
	if list.is_empty(): return
	var total := list.size()*floor_height
	if not is_equal_approx(house().wall_height,total): house().wall_height=total
	if is_instance_valid(_floors): _floors.free()
	_floors=Node3D.new(); _floors.name="_Floors"; add_child(_floors,false,Node.INTERNAL_MODE_BACK)
	for i in list.size():
		list[i].position.y=i*floor_height
		var mesh := ArrayMesh.new(); var cuts: Array=[]
		if i>0:
			for e in list[i-1].get_children():
				if e is Element and e.kind==2:
					cuts.append(e.opening_planes())
		var slab := BoxMesh.new(); slab.size=Vector3(house().width-0.4,0.10,house().depth-0.4); slab.material=wood_material()
		var floor_mesh: Mesh=house().interior_floor_mesh(wood_material()) if house().has_method("interior_floor_mesh") else slab
		MeshJoin.append(mesh,floor_mesh,Transform3D.IDENTITY,cuts)
		if house().wing_enabled:
			var wing := BoxMesh.new(); wing.size=Vector3(house().wing_span()-0.4,0.10,house().width*0.5+house().wing_length-0.4); wing.material=wood_material()
			var wing_cuts := cuts.duplicate(true)
			wing_cuts.append([Plane(Vector3.RIGHT,(house().width-0.4)*0.5),Plane(Vector3.LEFT,(house().width-0.4)*0.5),Plane(Vector3.BACK,(house().depth-0.4)*0.5),Plane(Vector3.FORWARD,(house().depth-0.4)*0.5)])
			MeshJoin.append(mesh,wing,house().wing_transform(),wing_cuts)
		if i>0:
			for e in list[i-1].get_children():
				if e is Element and e.kind==2 and not e.roof_exit and e.guardrails_enabled:
					preload("res://addons/house_builder/stair_guard.gd").append(mesh,e,0.05,wood_material())
		var floor_node := Node3D.new(); floor_node.position.y=i*floor_height; _floors.add_child(floor_node)
		var visual := MeshInstance3D.new(); visual.mesh=mesh; floor_node.add_child(visual)
		var body := StaticBody3D.new(); var shape := CollisionShape3D.new(); shape.shape=mesh.create_trimesh_shape(); body.add_child(shape); floor_node.add_child(body)
	if Engine.is_editor_hint(): editor_view()
func editor_view() -> void:
	house().set_cutaway(preview_inside,active_floor*floor_height,floor_height)
	for i in levels().size(): levels()[i].visible=not preview_inside or i==active_floor
	if is_instance_valid(_floors):
		for i in _floors.get_child_count(): _floors.get_child(i).visible=not preview_inside or i<=active_floor
func runtime_view(inside: bool,index: int,actor: Vector3,camera: Vector3) -> void:
	var on_roof: bool=not inside and house().has_method("interior_floor_mesh") and house().to_local(actor).y>house().wall_height-0.3
	for i in levels().size():
		var level := levels()[i]
		level.visible=(inside and i<=index) or (on_roof and i==levels().size()-1)
		for e in level.get_children():
			if e is Element: e.visible=not on_roof or (e.kind==2 and e.roof_exit)
	if is_instance_valid(_floors):
		for i in _floors.get_child_count(): _floors.get_child(i).visible=inside and i<=index
	for e in elements(): e.runtime_view(inside,actor,camera)
func doors() -> Array[Node3D]:
	var result: Array[Node3D]=[]
	for e in elements():
		if is_instance_valid(e._visual):
			for child in e._visual.get_children():
				if child is Door: result.append(child)
	return result
func level_records(index: int) -> Array:
	var result: Array=[]
	for e in level_elements(levels()[index]):
		if e is Element:
			var r: Dictionary=e.record(); r.merge({"id":e.stable_id,"generated":e.generated,"locked":e.locked,"baseline":e.baseline.duplicate(true)})
			result.append(r)
	return result
func apply_records(index: int,records: Array) -> void:
	var level := levels()[index]
	# Work in floor coordinates, then restore the authored room hierarchy.
	for e in level_elements(level):
		if e.kind==3 and e.get_parent()!=level:
			var saved_owner := e.owner
			e.reparent(level,true); e.owner=saved_owner
	var wanted: Dictionary={}
	for record in records: wanted[record.id]=record
	var existing: Dictionary={}
	for e in level.get_children():
		if e is Element:
			if not wanted.has(e.stable_id):
				level.remove_child(e); _retired["%d/%s"%[index,e.stable_id]]=e
			else: existing[e.stable_id]=e
	for record in records:
		var e: Node3D=existing.get(record.id)
		if e==null:
			var key := "%d/%s"%[index,record.id]
			e=_retired.get(key)
			if e!=null: _retired.erase(key)
			else: e=Element.new(); e.name=["Stanza_","Muro_","Scala_","Oggetto_"][record.kind]+str(record.id)
			level.add_child(e,true); e.owner=owner
		e.stable_id=record.id
		e.roof_exit=record.get("roof_exit",false)
		e.guardrails_enabled=record.get("guardrails_enabled",true)
		for key in ["kind","roof_exit","position","rotation","dimensions","room_type","has_door","door_offset","door_width","prop_type","room_ids"]:
			if record.has(key): e.set(key,record[key])
		e.asset=load(record.asset) if record.get("asset","")!="" else null
		e.generated=record.get("generated",true); e.locked=record.get("locked",false)
		e.baseline=record.get("baseline",{}).duplicate(true)
		if e.baseline.is_empty() and e.generated: e.accept_baseline()
		if e.kind==0: e.refresh_room_name()
	known_generated[str(index)]=records.filter(func(r): return r.get("generated",true)).map(func(r): return str(r.id))
	organize_furniture()
	_pending=true
func propose_rooms(index: int) -> Array:
	generation_failed=true
	observe_deletions()
	var current := level_records(index)
	var fixed: Array=[]
	var preserved: Array=[]
	for e in level_elements(levels()[index]):
		if not e is Element: continue
		var r: Dictionary=e.record(); r.merge({"id":e.stable_id,"generated":e.generated,"locked":e.locked,"baseline":e.baseline.duplicate(true)})
		if e.kind==0 and e.protected_edit(): fixed.append(r)
		elif e.kind!=0 and (e.kind!=1 or e.protected_edit()): preserved.append(r)
	var rooms := Generator.rooms(self,index,fixed)
	var walls := Generator.walls(rooms,floor_height)
	var obstacles: Array=[]
	for r in preserved:
		if r.kind==2: obstacles.append(r)
	if index<levels().size()-1 and obstacles.is_empty():
		var stairs := Generator.stair(self,rooms)
		if stairs.is_empty(): generation_report="Spazio insufficiente per scala e passaggio: allarga la casa o posiziona una scala manuale."; return current
		preserved.append(stairs); obstacles.append(stairs)
	if index>0:
		for r in level_records(index-1):
			if r.kind==2: obstacles.append(r)
	var errors := Generator.validate(rooms,walls)
	if not Generator.clear_doors(walls,obstacles): errors.append("Una scala impedisce il passaggio di una porta")
	generation_report="; ".join(errors) if not errors.is_empty() else "%d stanze collegate"%rooms.size()
	if not errors.is_empty(): return current
	var ids: Dictionary={}
	for r in preserved: ids[r.id]=true
	var result: Array=rooms+preserved
	for r in walls:
		if not ids.has(r.id): result.append(r)
	result=result.filter(func(r): return not deleted_ids.has("%d/%s"%[index,r.id]))
	return checked_proposal(index,result)
func observe_deletions() -> void:
	for index in levels().size():
		var present: Dictionary={}
		for e in level_elements(levels()[index]):
			if e is Element:
				present[e.stable_id]=true; deleted_ids.erase("%d/%s"%[index,e.stable_id])
		for id in known_generated.get(str(index),[]):
			if not present.has(id): deleted_ids["%d/%s"%[index,id]]=true
func propose_walls(index: int) -> Array:
	generation_failed=true
	observe_deletions()
	var current := level_records(index)
	var rooms: Array=current.filter(func(r): return r.kind==0)
	var result: Array=[]; var protected: Dictionary={}
	for e in level_elements(levels()[index]):
		if e is Element and (e.kind!=1 or e.protected_edit()): protected[e.stable_id]=true
	for r in current:
		if protected.has(r.id): result.append(r)
	var walls := Generator.walls(rooms,floor_height)
	var obstacles: Array=current.filter(func(r): return r.kind==2)
	if index>0: obstacles.append_array(level_records(index-1).filter(func(r): return r.kind==2))
	if not Generator.clear_doors(walls,obstacles):
		generation_report="Una scala impedisce il passaggio di una porta"; return current
	for r in walls:
		if not protected.has(r.id) and not deleted_ids.has("%d/%s"%[index,r.id]): result.append(r)
	return checked_proposal(index,result)
func propose_insert_room(index: int,id: String) -> Array:
	generation_failed=true
	observe_deletions()
	var current := level_records(index)
	var selected: Dictionary={}; var protected: Dictionary={}
	for e in level_elements(levels()[index]):
		if e is Element and e.protected_edit(): protected[e.stable_id]=true
	for r in current:
		if r.id==id and r.kind==0: selected=r
	if selected.is_empty(): generation_report="Seleziona il volume della stanza da integrare."; return current
	var rooms: Array=[]; var preserved: Array=[]
	for r in current:
		if r.kind!=0:
			if r.kind!=1 or protected.has(r.id): preserved.append(r)
			continue
		if r.id==id: rooms.append(r); continue
		var overlap := Generator.rect(r).intersection(Generator.rect(selected))
		if overlap.get_area()<0.01: rooms.append(r); continue
		if protected.has(r.id): generation_report="La nuova stanza invade una stanza modificata o bloccata: "+str(r.id); return current
		var pieces := Generator.subtract(Generator.rect(r),Generator.rect(selected))
		for i in pieces.size():
			if minf(pieces[i].size.x,pieces[i].size.y)<1.1:
				generation_report="Il ritaglio lascia un passaggio troppo stretto: avvicina il bordo della nuova stanza a quello esistente."; return current
			var piece := Generator.room(str(r.id) if i==0 else str(r.id)+"_part_%d"%i,pieces[i],floor_height,r.room_type)
			rooms.append(piece)
	var walls := Generator.walls(rooms,floor_height)
	var obstacles: Array=preserved.filter(func(r): return r.kind==2)
	if not walls.any(func(r): return id in r.room_ids and r.has_door):
		generation_report="La stanza non ha un accesso: posizionala dentro una stanza generata o fai coincidere un bordo con una stanza adiacente."; return current
	if index>0: obstacles.append_array(level_records(index-1).filter(func(r): return r.kind==2))
	if not Generator.clear_doors(walls,obstacles): generation_report="La scala impedisce l'accesso alla stanza."; return current
	for wall in walls:
		if not protected.has(wall.id) and not deleted_ids.has("%d/%s"%[index,wall.id]): preserved.append(wall)
	return checked_proposal(index,rooms+preserved)
func checked_proposal(index: int,records: Array) -> Array:
	generation_failed=true
	var rooms: Array=records.filter(func(r): return r.kind==0)
	var main := Rect2(Vector2(-house().width*0.5+0.2,-house().depth*0.5+0.2),Vector2(house().width-0.4,house().depth-0.4))
	var allowed: Array[Rect2]=[main]
	if house().wing_enabled:
		var center: Vector3=house().wing_transform().origin
		allowed.append(Rect2(Vector2(center.x,center.z)-Vector2(house().width*0.5+house().wing_length-0.4,house().wing_span()-0.4)*0.5,Vector2(house().width*0.5+house().wing_length-0.4,house().wing_span()-0.4)))
	for r in rooms:
		if not r.rotation.is_zero_approx(): generation_report="Le stanze devono essere allineate agli assi della casa."; return level_records(index)
		var remainder: Array[Rect2]=[Generator.rect(r)]
		for region in allowed:
			var next: Array[Rect2]=[]
			for part in remainder: next.append_array(Generator.subtract(part,region))
			remainder=next
		if not remainder.is_empty(): generation_report="Stanza fuori dal perimetro della casa: "+str(r.id); return level_records(index)
	var errors := Generator.walkability(rooms,records)
	if not errors.is_empty(): generation_report="; ".join(errors); return level_records(index)
	generation_report="%d stanze: passaggi verificati; modifiche manuali conservate"%rooms.size()
	generation_failed=false
	return records
func propose_furniture(index: int,scope: String="",remove_only: bool=false) -> Array:
	generation_failed=true
	observe_deletions()
	var keep: Array=[]
	var protected: Dictionary={}
	for e in level_elements(levels()[index]):
		if e is Element and e.protected_edit(): protected[e.stable_id]=true
	for r in level_records(index):
		if r.kind!=3 or protected.has(r.id) or (scope!="" and scope not in r.get("room_ids",[])): keep.append(r)
	var result := keep if remove_only else Generator.furnish(self,index,keep,scope)
	return checked_proposal(index,result)
func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:
		for e in _retired.values():
			if is_instance_valid(e): e.free()

func _exit_tree() -> void:
	var host := house()
	if host and host.has_method("interior_floor_mesh"): host.request_rebuild()

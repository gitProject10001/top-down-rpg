@tool
extends "res://addons/house_builder/volume.gd"
## A straight solid curtain. Its passage crosses the entire thickness.
@export_group("Portone")
@export var gate_enabled := true:
	set(value): gate_enabled=value; request_rebuild()
@export_range(1.2,4.0,0.1) var gate_width := 2.4:
	set(value): gate_width=value; request_rebuild()
@export_range(2.0,4.0,0.1) var gate_height := 3.0:
	set(value): gate_height=value; request_rebuild()
@export_range(-0.7,0.7,0.05) var gate_offset := 0.0:
	set(value): gate_offset=value; request_rebuild()
var _gate_event := false
@export var gate_open := false:
	set(value):
		gate_open=value
		if not _gate_event: request_rebuild()

func _init() -> void:
	attached=false; canopy_roof=2; battlements_enabled=true
	width=12.0; depth=2.8; wall_height=4.2; roof_height=1.0

func is_curtain_wall() -> bool: return true
func contains_footprint(_point: Vector3,_margin: float=0.0) -> bool: return false
func gate_record() -> Dictionary:
	return {"kind":"door","wall":0,"u":gate_offset,"width":minf(gate_width,width-0.6),"height":minf(gate_height,wall_height-0.5),"open":gate_open}
func all_openings() -> Array[Dictionary]:
	var records: Array[Dictionary]=[]
	if gate_enabled: records.append(gate_record())
	return records
func _build_shell() -> void:
	if not gate_enabled:
		_box(Vector3(0,wall_height*0.5,0),Vector3(width,wall_height,depth),0); return
	var gate := resolved_opening(gate_record())
	var left: float=gate.along-gate.width*0.5; var right: float=gate.along+gate.width*0.5
	_box(Vector3((-width*0.5+left)*0.5,wall_height*0.5,0),Vector3(left+width*0.5,wall_height,depth),0)
	_box(Vector3((right+width*0.5)*0.5,wall_height*0.5,0),Vector3(width*0.5-right,wall_height,depth),0)
	_box(Vector3(gate.along,(gate.height+wall_height)*0.5,0),Vector3(gate.width,wall_height-gate.height,depth),0)
	_box(Vector3(gate.along,-0.045,0),Vector3(gate.width,0.09,depth),2)
	for z in [-depth*0.5-0.04,depth*0.5+0.04]:
		for x in [left-0.10,right+0.10]: _box(Vector3(x,gate.height*0.5,z),Vector3(0.20,gate.height,0.16),2)
		_box(Vector3(gate.along,gate.height+0.10,z),Vector3(gate.width+0.4,0.20,0.16),2)
func _finish_openings(body: MeshInstance3D,materials: Array) -> void:
	super._finish_openings(body,materials)
	var door := _generated.get_node_or_null("Door_0")
	if door: door.changed.connect(_gate_changed)
func _gate_changed(value: bool) -> void:
	_gate_event=true; gate_open=value; _gate_event=false
func _plaster_material() -> ShaderMaterial:
	return _material(Vector2(0,0.5),Color(0.65,0.63,0.59))
func _get_configuration_warnings() -> PackedStringArray:
	var error := connection_error()
	if not error.is_empty(): return PackedStringArray([error])
	if gate_enabled and (gate_width>width-0.6 or gate_height>wall_height-0.5):
		return PackedStringArray(["Portone troppo grande: lascia almeno 60 cm ai lati e 50 cm sotto il camminamento. Le dimensioni effettive sono limitate al muro."])
	return super._get_configuration_warnings()



@export_group("Raccordo torre")
@export var connect_to_tower := false:
	set(value): connect_to_tower=value; request_rebuild()
@export_range(0,7,1) var tower_face := 2:
	set(value): tower_face=value; request_rebuild()
@export_node_path("Node3D") var target_tower: NodePath:
	set(value): target_tower=value; request_rebuild()
@export_range(0,7,1) var target_face := 6:
	set(value): target_face=value; request_rebuild()
var _last_target: Node3D
var _connection_signature := ""
func destination() -> Node3D:
	var node := get_node_or_null(target_tower) if not target_tower.is_empty() else null
	return node if node and node.has_method("footprint_vertices") else null
func destination_error() -> String:
	if target_tower.is_empty(): return ""
	var host := fortification_host(); var target := destination()
	if target==null or target==host: return "Seleziona una seconda torre valida per Target Tower."
	if host==null or not host.is_inside_tree() or not target.is_inside_tree(): return "Torri non disponibili nella scena."
	if depth>target.wall_length(target_face)-0.25: return "La faccia della seconda torre è troppo stretta."
	var a: Vector3=host.to_global(host.wall_point(tower_face,0,0))
	var b: Vector3=target.to_global(target.wall_point(target_face,0,0))
	var normal: Vector3=host.global_basis*host.wall_normal(tower_face)
	var opposite: Vector3=target.global_basis*target.wall_normal(target_face)
	var gap := b-a; var distance := gap.dot(normal)
	if normal.dot(opposite)>-0.999 or (gap-normal*distance).length()>0.03:
		return "Le due facce devono essere allineate e rivolte l’una verso l’altra. Sposta o ruota la seconda torre."
	if distance<1.8 or distance>19.8: return "La distanza fra le facce deve essere fra 1.8 e 19.8 metri."
	if absf(host.to_global(Vector3.UP*host.effective_elevation()).y-target.to_global(Vector3.UP*target.effective_elevation()).y)>0.03:
		return "I tetti delle due torri devono avere la stessa quota."
	return ""

func fortification_host() -> Node3D:
	var parent := get_parent()
	return parent if parent and parent.has_method("footprint_vertices") else null
func connection_error() -> String:
	if not connect_to_tower: return ""
	var host := fortification_host()
	if host==null: return "Il muro collegato deve essere figlio di una torre ottagonale."
	if depth>host.wall_length(tower_face)-0.25: return "Il muro è più largo della faccia della torre: aumenta la torre o riduci Depth del muro."
	for other in host.get_children():
		if other!=self and other.has_method("fortification_host") and other.connect_to_tower and other.tower_face==tower_face:
			return "Due cortine occupano la stessa faccia della torre. Cambia Tower Face."
	return destination_error()
func prepare_attachment() -> void:
	if not connect_to_tower: super.prepare_attachment(); return
	if not connection_error().is_empty(): return
	var host := fortification_host(); var normal: Vector3=host.wall_normal(tower_face)
	var target := destination()
	if target:
		var end: Vector3=host.to_local(target.to_global(target.wall_point(target_face,0,0)))
		var length: float=(end-host.wall_point(tower_face,0,0)).dot(normal)+0.2
		if not is_equal_approx(width,length): width=length
	var tangent: Vector3=(host.wall_point(tower_face,1,0)-host.wall_point(tower_face,0,0)).normalized()
	transform=Transform3D(Basis(normal,Vector3.UP,-tangent),host.wall_point(tower_face,0,0,width*0.5-0.10))
	if not is_equal_approx(wall_height,host.wall_height): wall_height=host.wall_height
func _process(delta: float) -> void:
	var host := fortification_host()
	var target := destination()
	var signature := str(host.global_transform if host and host.is_inside_tree() else Transform3D.IDENTITY,target_tower,target_face,target.global_transform if target and target.is_inside_tree() else Transform3D.IDENTITY,target.dimensions() if target else Vector4.ZERO,connection_error(),connect_to_tower,tower_face,width,depth,host.dimensions() if host else Vector4.ZERO)
	if signature!=_connection_signature:
		_connection_signature=signature; request_rebuild()
		if host: host.request_rebuild()
		if is_instance_valid(_last_target): _last_target.request_rebuild()
		_last_target=target
		if target: target.request_rebuild()
	super._process(delta)
func _exit_tree() -> void:
	var host := fortification_host()
	if host: host.request_rebuild()
	if is_instance_valid(_last_target): _last_target.request_rebuild()
	super._exit_tree()
func connection_spans(wall: int,spans: Array[Vector2]) -> Array[Vector2]:
	if connect_to_tower and connection_error().is_empty():
		if wall==3 or (wall==2 and destination()!=null): return []
	return spans

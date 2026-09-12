@tool
extends Node3D
@export_enum("Perimetro","Strada","Tipo di quartiere","Area non edificabile","Corte di proprietà","Percorso di corte") var kind := 0
@export var group_id := ""
@export var point_widths := PackedFloat32Array()
var network_issue := false
@export var locked := false
@export var stable_id := ""
@export var points := PackedVector2Array([Vector2(-15,-15),Vector2(15,-15),Vector2(15,15),Vector2(-15,15)]):
	set(v): points=v; if is_inside_tree(): update_gizmos()
@export_range(2,10,0.25) var road_width := 3.0
@export_enum("Casa popolana","Bottega","Casa benestante") var building_type := 0
@export_range(1,3) var storeys := 1
var _signature := ""
var _road: MeshInstance3D
func _process(_dt: float) -> void:
	var surfaced: bool=get_parent()!=null and get_parent().get("auto_surface")==true
	var show_zones: bool=get_parent()==null or get_parent().get("show_zones")!=false
	var signature := str(points,road_width,point_widths,kind,surfaced,show_zones)
	if signature==_signature: return
	_signature=signature; update_gizmos()
	if is_instance_valid(_road): _road.free()
	if (show_zones or not Engine.is_editor_hint()) and (kind==4 and (not surfaced or Engine.is_editor_hint()) or (kind in [2,3] and Engine.is_editor_hint())) and points.size()>=3:
		var triangles := Geometry2D.triangulate_polygon(points)
		if triangles.is_empty(): return
		var fill := SurfaceTool.new(); fill.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tint := StandardMaterial3D.new(); tint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; tint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; tint.albedo_color=Color(0.2,0.65,1,0.16); tint.cull_mode=BaseMaterial3D.CULL_DISABLED; tint.no_depth_test=true; fill.set_material(tint)
		if kind==3: tint.albedo_color=Color(1,0.25,0.12,0.2)
		if kind==4 and not surfaced:
			tint.transparency=BaseMaterial3D.TRANSPARENCY_DISABLED; tint.albedo_color=Color(0.30,0.24,0.15); tint.no_depth_test=false
		for index in triangles: fill.add_vertex(Vector3(points[index].x,0.08,points[index].y))
		_road=MeshInstance3D.new(); _road.mesh=fill.commit(); _road.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(_road,false,Node.INTERNAL_MODE_BACK)
		return
	if kind not in [1,5] or points.size()<2 or surfaced: return
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new(); material.albedo_color=Color(0.30,0.24,0.15); material.roughness=1; material.cull_mode=BaseMaterial3D.CULL_DISABLED; surface.set_material(material)
	for polygon in preload("res://addons/village_builder/path_network.gd").ribbon(points,effective_widths(),road_width):
		var indices := Geometry2D.triangulate_polygon(polygon)
		for index in indices:
			var p: Vector2=polygon[index]; surface.set_normal(Vector3.UP); surface.add_vertex(Vector3(p.x,0.025,p.y))
	_road=MeshInstance3D.new(); _road.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _road.name="_Road"; _road.mesh=surface.commit(); add_child(_road,false,Node.INTERNAL_MODE_BACK)
func village_points() -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points:
		var q := transform*Vector3(p.x,0,p.y); result.append(Vector2(q.x,q.z))
	return result

func effective_widths() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for i in points.size(): result.append(clampf(point_widths[i] if i<point_widths.size() else road_width,1.2,10.0))
	return result

func widths_for_points(updated: PackedVector2Array) -> PackedFloat32Array:
	var old := effective_widths(); var result := PackedFloat32Array()
	for p in updated:
		var best := INF; var width := road_width
		for i in range(points.size()-1):
			var q := Geometry2D.get_closest_point_to_segment(p,points[i],points[i+1]); var distance := q.distance_squared_to(p)
			if distance<best:
				best=distance; width=lerpf(old[i],old[i+1],points[i].distance_to(q)/maxf(0.001,points[i].distance_to(points[i+1])))
		result.append(width)
	return result

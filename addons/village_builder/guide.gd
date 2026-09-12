@tool
extends Node3D
@export_enum("Perimetro","Strada","Tipo di quartiere","Area non edificabile") var kind := 0
@export var stable_id := ""
@export var points := PackedVector2Array([Vector2(-15,-15),Vector2(15,-15),Vector2(15,15),Vector2(-15,15)]):
	set(v): points=v; if is_inside_tree(): update_gizmos()
@export_range(2,10,0.25) var road_width := 3.0
@export_enum("Casa popolana","Bottega","Casa benestante") var building_type := 0
@export_range(1,3) var storeys := 1
var _signature := ""
var _road: MeshInstance3D
func _process(_dt: float) -> void:
	var signature := str(points,road_width,kind)
	if signature==_signature: return
	_signature=signature; update_gizmos()
	if is_instance_valid(_road): _road.free()
	if kind in [2,3] and Engine.is_editor_hint() and points.size()>=3:
		var triangles := Geometry2D.triangulate_polygon(points)
		if triangles.is_empty(): return
		var fill := SurfaceTool.new(); fill.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tint := StandardMaterial3D.new(); tint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; tint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; tint.albedo_color=Color(0.2,0.65,1,0.16); tint.cull_mode=BaseMaterial3D.CULL_DISABLED; tint.no_depth_test=true; fill.set_material(tint)
		if kind==3: tint.albedo_color=Color(1,0.25,0.12,0.2)
		for index in triangles: fill.add_vertex(Vector3(points[index].x,0.08,points[index].y))
		_road=MeshInstance3D.new(); _road.mesh=fill.commit(); _road.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(_road,false,Node.INTERNAL_MODE_BACK)
		return
	if kind!=1 or points.size()<2: return
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new(); material.albedo_color=Color(0.30,0.24,0.15); material.roughness=1; material.cull_mode=BaseMaterial3D.CULL_DISABLED; surface.set_material(material)
	for i in range(points.size()-1):
		var normal := (points[i+1]-points[i]).normalized().orthogonal()*road_width*0.5
		var corners := [points[i]+normal,points[i+1]+normal,points[i+1]-normal,points[i]-normal]
		for corner in [0,1,2,0,2,3]:
			var p: Vector2=corners[corner]; surface.set_normal(Vector3.UP); surface.add_vertex(Vector3(p.x,0.025,p.y))
	_road=MeshInstance3D.new(); _road.name="_Road"; _road.mesh=surface.commit(); add_child(_road,false,Node.INTERNAL_MODE_BACK)
func village_points() -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points:
		var q := transform*Vector3(p.x,0,p.y); result.append(Vector2(q.x,q.z))
	return result

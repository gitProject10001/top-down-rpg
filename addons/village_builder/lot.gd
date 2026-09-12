@tool
extends Node3D
const Request=preload("res://addons/house_builder/building_request.gd")
@export var stable_id := ""
@export var request: Request
@export var locked := false
@export_storage var baseline_pose := Transform3D.IDENTITY
@export_storage var baseline_house: Dictionary={}
@export_storage var zone_id := ""
@export_storage var access_path: PackedVector3Array=[]
var _access: MeshInstance3D
func rebuild_access() -> void:
	if is_instance_valid(_access): _access.free()
	if access_path.size()<2: return
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new(); material.albedo_color=Color(0.35,0.29,0.20); material.roughness=1; material.cull_mode=BaseMaterial3D.CULL_DISABLED; surface.set_material(material)
	for i in range(access_path.size()-1):
		var a := access_path[i]; var b := access_path[i+1]; var n := (b-a).normalized().cross(Vector3.UP)*0.6
		var corners := [a+n,b+n,b-n,a-n]
		for corner in [0,1,2,0,2,3]: surface.set_normal(Vector3.UP); surface.add_vertex(corners[corner]+Vector3.UP*0.03)
	_access=MeshInstance3D.new(); _access.mesh=surface.commit(); add_child(_access,false,Node.INTERNAL_MODE_BACK)
func _ready() -> void: rebuild_access()
func house_state() -> Dictionary:
	var h := get_node_or_null("Edificio")
	if h==null: return {}
	return {"dimensions":h.dimensions(),"openings":h.openings.duplicate(true),"wing":h.wing_settings(),"seed":h.house_seed,"transform":h.transform,"weathered":h.weathered}
static func equivalent(a: Variant,b: Variant) -> bool:
	if a is float or a is int:
		return (b is float or b is int) and is_equal_approx(float(a),float(b))
	if a is Transform3D or a is Vector4: return typeof(a)==typeof(b) and a.is_equal_approx(b)
	if a is Dictionary:
		if not b is Dictionary or a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array:
		if not b is Array or a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	return a==b
func protected_edit() -> bool:
	return locked or not transform.is_equal_approx(baseline_pose) or not equivalent(house_state(),baseline_house) or (has_node("Edificio") and get_node("Edificio").get_child_count()>0)
func polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	var h := get_node_or_null("Edificio")
	var size: Vector2=Vector2(h.width,h.depth) if h else request.footprint
	var house_pose: Transform3D=h.transform if h else Transform3D.IDENTITY
	for p in [Vector3(-size.x/2,0,-size.y/2),Vector3(size.x/2,0,-size.y/2),Vector3(size.x/2,0,size.y/2),Vector3(-size.x/2,0,size.y/2)]:
		var q: Vector3=transform*house_pose*p; result.append(Vector2(q.x,q.z))
	if h and h.wing_enabled:
		for wall in range(4,8):
			for side in [-1,1]:
				var q: Vector3=transform*house_pose*h.wall_point(wall,side*h.wall_length(wall)*0.5,0); result.append(Vector2(q.x,q.z))
	return Geometry2D.convex_hull(result)

extends MeshInstance3D
## A quick emissive crescent "slash" that sweeps in front of the attacker and fades — builds its own
## tapered arc mesh, animates, and frees itself. Set `flipped` before adding to the tree to mirror
## the sweep for the alternating combo.

var flipped := false
var outer_radius := 1.6

func _ready() -> void:
	mesh = _build_arc(outer_radius * .73, outer_radius, 135.0, 20)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.9, 1.0)
	mat.emission_energy_multiplier = 1.2
	mat.albedo_color = Color(0.96, 0.91, 0.73, 0.75)
	material_override = mat
	if flipped:
		scale.x = -1.0
	rotation.x = deg_to_rad(-5.0)
	rotation.y = -.30 if flipped else .30
	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.16)
	t.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.16)
	t.parallel().tween_property(self, "rotation:y", .30 if flipped else -.30, 0.16)
	t.chain().tween_callback(queue_free)

# Crescent ribbon in the XZ plane, arcing toward -Z (front), tapered thin at the ends.
func _build_arc(inner: float, outer: float, arc_deg: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in seg + 1:
		var f := float(i) / float(seg)
		var a := deg_to_rad(-arc_deg * 0.5 + arc_deg * f)
		var d := Vector3(sin(a), 0.0, -cos(a))
		var w := sin(f * PI)                 # 0 at the ends, 1 in the middle
		var io := inner + (1.0 - w) * (outer - inner) * 0.45
		var oo := outer - (1.0 - w) * (outer - inner) * 0.25
		st.add_vertex(d * io)
		st.add_vertex(d * oo)
	return st.commit()

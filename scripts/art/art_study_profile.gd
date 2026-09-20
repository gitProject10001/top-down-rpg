@tool
class_name ArtStudyProfile
extends Resource
## Shared defaults plus persistent, local artistic edits. Procedural builders read
## this resource; they never replace its edits with their generated instances.
const SurfaceEdit = preload("res://scripts/art/art_surface_edit.gd")
const MAX_SHADER_EDITS := 32

@export_group("Painted lighting")
@export_range(0.0,1.5,0.01) var ambient_energy: float = 0.42
@export_range(0.0,1.0,0.01) var sky_fill_energy: float = 0.12
@export var gi_occlusion: bool = true
@export_range(0.05,2.0,0.05) var contact_occlusion_radius: float = 0.65
@export_range(0.0,3.0,0.05) var contact_occlusion_intensity: float = 1.35
@export_range(0.5,3.0,0.05) var contact_occlusion_power: float = 1.45
## Large PCSS angles erase narrow architectural shadows in the near-isometric view.
@export_range(0.0,5.0,0.1) var sun_angular_distance: float = 0.5

@export_group("Grass")
@export var grass_enabled: bool = true
@export_range(0.0, 4.0, 0.05, "or_greater") var density_multiplier: float = 1.3
## Low compact, medium leaning, tall sparse, low swept (normalized on read).
@export var grass_family_weights := Vector4(0.35, 0.30, 0.15, 0.20)
## Root, cool stroke, warm stroke; values preserve the approved muted palette.
@export var grass_palette := PackedColorArray([
	Color(0.06, 0.10, 0.045), Color(0.09, 0.16, 0.055), Color(0.17, 0.22, 0.07)])

@export_group("Surface details")
@export var weathering_enabled: bool = true
@export var cliffs_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var moss_amount: float = 0.35
@export_range(0.0, 1.0, 0.01) var damp_amount: float = 0.25
@export_range(0.0, 1.0, 0.01) var damage_amount: float = 0.20
@export var moss_color := Color(0.10, 0.18, 0.075)
@export var damp_color := Color(0.20, 0.24, 0.25)

@export_group("Authoring")
@export var scatter_seed: int = 712
@export var edits: Array[SurfaceEdit] = []
@export_storage var next_edit_serial: int = 1

func normalized_family_weights() -> Vector4:
	var w := grass_family_weights.max(Vector4.ZERO)
	var total := w.x + w.y + w.z + w.w
	return w / total if total > 0.00001 else Vector4(0.25, 0.25, 0.25, 0.25)

## Reproducible across regeneration and process runs, unlike instance IDs.
func seed_for(identifier: String, salt: int = 0) -> int:
	var value := (scatter_seed ^ salt) & 0x7fffffff
	for byte in identifier.to_utf8_buffer():
		value = ((value * 31) + byte) & 0x7fffffff
	return value

func find_edit(identifier: String) -> SurfaceEdit:
	for edit in edits:
		if edit != null and edit.stable_id == identifier:
			return edit
	return null

## The only initialization regeneration needs. Existing IDs, seeds, lock flags,
## authored positions and tombstones remain untouched.
func ensure_edit_ids() -> void:
	var used: Dictionary = {}
	for edit in edits:
		if edit != null and not edit.stable_id.is_empty():
			used[edit.stable_id] = true
	for edit in edits:
		if edit == null or not edit.stable_id.is_empty():
			continue
		var identifier := "art_%06d" % next_edit_serial
		next_edit_serial += 1
		while used.has(identifier):
			identifier = "art_%06d" % next_edit_serial
			next_edit_serial += 1
		edit.stable_id = identifier
		edit.seed = seed_for(identifier) if edit.seed == 0 else edit.seed
		used[identifier] = true

func add_edit(edit: SurfaceEdit) -> bool:
	if edit == null:
		return false
	if not edit.stable_id.is_empty() and find_edit(edit.stable_id) != null:
		return false
	edits.append(edit)
	ensure_edit_ids()
	emit_changed()
	return true

## Brush consumers must use this API; locked records cannot be erased by a
## procedural operation. The Inspector can explicitly unlock them first.
func set_edit_deleted(identifier: String, value: bool) -> bool:
	var edit := find_edit(identifier)
	if edit == null or edit.locked:
		return false
	edit.deleted = value
	emit_changed()
	return true

func active_edits(surface_path: NodePath) -> Array[SurfaceEdit]:
	var result: Array[SurfaceEdit] = []
	for edit in edits:
		if edit != null and not edit.deleted and edit.surface_path == surface_path:
			result.append(edit)
	result.sort_custom(func(a: SurfaceEdit, b: SurfaceEdit) -> bool: return a.stable_id < b.stable_id)
	return result

## Local stamped intensity is additive, then clamped. A negative intensity is an
## erase stroke; deleting a stroke itself is a separate persistent tombstone.
func sample_layer(layer: int, surface_path: NodePath, local_point: Vector3, base_value: float = 0.0) -> float:
	var value := base_value
	for edit in edits:
		if edit != null and not edit.deleted and edit.layer == layer and edit.surface_path == surface_path:
			value += edit.influence(local_point) * edit.intensity
	return clampf(value, 0.0, 1.0)

## Fixed-size uniforms. World-space shader point p is transformed to a unit
## stamp by dot(art_edit_rows_x[i], vec4(p,1)), and equivalently y/z.
## weight=(1-smoothstep(.55,1,length(q.xz)))*(1-smoothstep(.55,1,abs(q.y))).
## art_edit_values = (signed intensity, layer, seed, 0). art_edit_overflow is a
## CPU diagnostic, not a shader uniform; callers must report it, never bind it.
func pack_shader_edits(surface_path: NodePath, surface_to_world: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var rows_x := PackedVector4Array()
	var rows_y := PackedVector4Array()
	var rows_z := PackedVector4Array()
	var values := PackedVector4Array()
	rows_x.resize(MAX_SHADER_EDITS)
	rows_y.resize(MAX_SHADER_EDITS)
	rows_z.resize(MAX_SHADER_EDITS)
	values.resize(MAX_SHADER_EDITS)
	var selected := active_edits(surface_path)
	var count := mini(selected.size(), MAX_SHADER_EDITS)
	for i in count:
		var edit := selected[i]
		var inverse := (surface_to_world * edit.stamp_transform()).affine_inverse()
		rows_x[i] = Vector4(inverse.basis.x.x, inverse.basis.y.x, inverse.basis.z.x, inverse.origin.x)
		rows_y[i] = Vector4(inverse.basis.x.y, inverse.basis.y.y, inverse.basis.z.y, inverse.origin.y)
		rows_z[i] = Vector4(inverse.basis.x.z, inverse.basis.y.z, inverse.basis.z.z, inverse.origin.z)
		values[i] = Vector4(edit.intensity, edit.layer, edit.seed, 0.0)
	return {"art_edit_count": count, "art_edit_rows_x": rows_x, "art_edit_rows_y": rows_y,
		"art_edit_rows_z": rows_z, "art_edit_values": values,
		"art_edit_overflow": maxi(0, selected.size() - MAX_SHADER_EDITS)}

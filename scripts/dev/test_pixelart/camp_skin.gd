@tool
extends Node3D
## RE-SKINS EVERY CAMP PROP BY MATERIAL NAME, so the .glb files stay dumb geometry.
##
## THE PROBLEM THIS SOLVES. tools/blender/propkit.py exports flat Principled colours and no UVs --
## that is its contract, and it is the right one, because a prop that carries its own baked textures
## has to be re-exported every time the look changes. So a camp prop arrives in Godot as a mesh with
## surfaces named CampWood, CampStone, CampCanvas and so on, and something has to put the real
## triplanar PBR materials onto them.
##
## WHY NOT surface_material_override IN THE .tscn. Because the override is addressed by surface
## INDEX, and the index is decided by the order propkit happened to touch each slot while building.
## Add one iron nail to the front of a prop and every index after it shifts, silently, and the
## chapel arrives wearing canvas. The material NAME is stable across that; the index is not.
##
## HOW IT MATCHES. glTF carries the material name, so an imported surface's material is called
## "CampWood". Godot has moved where that name is readable between versions, so this checks the
## surface's own name and the material's resource_name, and strips the ".001" suffixes the importer
## adds when two meshes share a name. Anything unmatched is LEFT ALONE and reported once -- silence
## would mean a prop quietly keeping its flat grey.
##
## DELIBERATELY UNMATCHED: CampEmber. The campfire's coals arrive already emissive (propkit writes
## Principled Emission, which glTF carries as KHR_materials_emissive_strength and Godot reads as
## emission_energy_multiplier) and that is exactly what is wanted. Overriding it with a lit material
## would put the fire out.

## Material slot name (without the "Camp" prefix) -> the material to put there. Editable in the
## inspector so a look-dev pass can swap one without touching the script.
@export var skins: Dictionary = {}

## Applied to any surface this map does not name -- including surfaces with NO material at all.
## assets/models/veg_leaf_*.glb are exactly that case: leaf cards exported with UVs and no material,
## because they were always meant to be skinned by whatever scene uses them. Leave it null and an
## unmatched surface keeps whatever it imported with, which is the right default for a prop that
## brought its own texture.
@export var default_skin: Material = null

## Slots that are meant to keep their imported material. Listing them here is what keeps the
## "no skin for" warning meaningful -- a warning that fires every single run is one nobody reads.
@export var keep: PackedStringArray = ["Ember"]

## Log every surface it touches. Useful once, after adding a prop.
@export var verbose := false

## Re-run in the editor. Toggling this is how you see a material change without reloading the scene.
@export_tool_button("Re-skin now") var reskin_action := _apply


func _ready() -> void:
	_apply()


func _apply() -> void:
	if skins.is_empty():
		push_warning("[CAMPSKIN] no skins assigned on %s; props keep their flat import colours" % name)
		return
	var missing := {}
	var count := 0
	for mesh_instance in _all_mesh_instances(self):
		count += _skin(mesh_instance, missing)
	if not missing.is_empty():
		# One warning listing everything, rather than one per surface: a prop with a new slot would
		# otherwise bury the log under a line per triangle batch.
		push_warning("[CAMPSKIN] no skin for material slots %s -- they keep their import colours"
				% ", ".join(missing.keys()))
	if verbose:
		print("[CAMPSKIN] %s: skinned %d surfaces" % [name, count])


func _skin(mesh_instance: MeshInstance3D, missing: Dictionary) -> int:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return 0
	var done := 0
	for i in mesh.get_surface_count():
		var key := _slot_name(mesh, i)
		if key in keep:
			continue
		if key != "" and skins.has(key):
			mesh_instance.set_surface_override_material(i, skins[key])
			done += 1
			if verbose:
				print("[CAMPSKIN]   %s surface %d (%s)" % [mesh_instance.name, i, key])
		elif default_skin != null:
			mesh_instance.set_surface_override_material(i, default_skin)
			done += 1
		elif key != "":
			missing[key] = true
	return done


## The slot name behind a surface, stripped of the "Camp" prefix and any importer suffix.
## Two sources are tried because which one carries the glTF name has moved between Godot versions.
func _slot_name(mesh: Mesh, surface: int) -> String:
	var raw := ""
	if mesh is ArrayMesh:
		raw = (mesh as ArrayMesh).surface_get_name(surface)
	if raw == "":
		var mat := mesh.surface_get_material(surface)
		if mat != null:
			raw = mat.resource_name
	if raw == "":
		return ""
	# "CampWood.001" and "CampWood_002" both mean CampWood: the importer suffixes a name when two
	# meshes in one scene claim it.
	var dot := raw.find(".")
	if dot > 0:
		raw = raw.substr(0, dot)
	# Camp props and the existing dungeon kit both prefix their slot names by module -- CampWood and
	# DunWood are the same oak as far as this scene is concerned. Stripping both prefixes is what
	# lets assets/models/dungeon/barrel.glb stand in the mud beside a tent and take the same skin.
	for prefix in ["Camp", "Dun"]:
		if raw.begins_with(prefix):
			return raw.substr(prefix.length())
	return raw


func _all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_all_mesh_instances(child))
	return found

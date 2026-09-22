@tool
extends Resource
## An editable composition of the existing builders, not a new mesh generator.
@export var schema_version := 1
@export var recipe_id := ""
@export var display_name := ""
@export_enum("dwelling", "shop", "inn", "forge", "stable", "chapel") var role := "dwelling"
@export_multiline var description := ""
@export var main_properties: Dictionary = {}
## Components: kind (volume by default, or balcony), id, properties, width_ratio,
## preferred_walls. Existing Volume/Balcony builders validate the composition.
@export var components: Array[Dictionary] = []
## Details: id, kind, dimensions, anchor, position, u; editable ordinary detail nodes.
@export var details: Array[Dictionary] = []
## Optional named overrides of main_properties/components/details, not opaque scene replacements.
@export var variants: Array[Dictionary] = []

func resolved(structural_seed: int, variant_id := "") -> Dictionary:
	var result := {"main_properties": main_properties.duplicate(true),
		"components": components.duplicate(true), "details": details.duplicate(true), "variant_id": ""}
	var facade_defaults := {"facade_storey_height":0.0,"facade_upper_windows":false,"masonry_trim":false,"masonry_finish":null,"roof_curvature":0.0}
	for key in facade_defaults:
		if not result.main_properties.has(key): result.main_properties[key]=facade_defaults[key]
	if variants.is_empty(): return result
	var selected: Dictionary = {}
	if variant_id.is_empty(): selected = variants[posmod(structural_seed, variants.size())]
	else:
		for variant in variants:
			if str(variant.get("id", "")) == variant_id: selected = variant; break
	if selected.is_empty(): return {"error": "Variante sconosciuta: " + variant_id}
	result.variant_id = str(selected.get("id", ""))
	result.main_properties.merge(selected.get("main_properties", {}), true)
	for field in ["components", "details"]:
		if selected.has(field): result[field] = selected[field].duplicate(true)
	return result

func data() -> Dictionary:
	return {"schema": schema_version, "id": recipe_id, "role": role,
		"main": main_properties.duplicate(true), "components": components.duplicate(true),
		"details": details.duplicate(true), "variants": variants.duplicate(true)}

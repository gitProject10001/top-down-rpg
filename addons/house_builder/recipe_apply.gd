@tool
extends RefCounted
## Explicit authoring transaction. Applying a recipe never replaces the House or InteriorPlan.
const Recipe = preload("res://addons/house_builder/building_recipe.gd")
const House = preload("res://addons/house_builder/house.gd")
const Volume = preload("res://addons/house_builder/volume.gd")
const Balcony = preload("res://addons/house_builder/balcony.gd")
const CONTAINERS := ["Volumes", "Components", "RecipeDetails"]
const MAIN_FIELDS := ["width", "depth", "wall_height", "roof_height", "wall_finish", "masonry_trim", "weathered", "house_seed", "archetype_id", "facade_storey_height", "facade_upper_windows"]
const BALCONY_FIELDS := ["component_id", "host_id", "along", "elevation", "balcony_width", "projection", "create_door", "floor_id", "door_id", "support_posts", "exterior_stairs", "stair_width", "stair_offset", "ground_level", "door_open", "locked"]
const VOLUME_FIELDS := ["width", "depth", "wall_height", "roof_height", "wall_finish", "masonry_trim", "weathered", "house_seed", "openings", "structure_kind", "canopy_roof", "post_spacing", "post_size", "automatic_frame", "attached", "host_wall", "host_offset", "junction_mode", "junction_width", "junction_height", "junction_offset", "junction_open", "parapet_enabled", "battlements_enabled", "battlement_spacing", "roof_door_enabled", "roof_door_floor_id", "roof_door_offset", "roof_door_open", "volume_id", "attachment_elevation", "attachment_inset", "roof_junction", "facade_storey_height", "facade_upper_windows"]
const DETAIL_FIELDS := ["kind", "dimensions", "detail_seed", "weathered", "locked", "detail_id", "palette", "collision_enabled", "motif"]

static func snapshot(house: Node3D) -> Dictionary:
	var state := {"properties": _read(house, MAIN_FIELDS), "recipe": house.building_recipe,
		"provenance": house.recipe_provenance.duplicate(true), "parts": [], "containers": []}
	for container_name in CONTAINERS:
		var container := house.get_node_or_null(NodePath(container_name))
		if container == null: continue
		state.containers.append(container_name)
		for node in container.get_children():
			if node.has_meta("recipe_part_id"): state.parts.append(_record(node, container_name))
	return state

static func propose(house: Node3D, recipe: Recipe, structural_seed := -1, detail_seed := -1,
		variant_id := "", preserve_footprint := true, minimum_wall_height := -1.0) -> Dictionary:
	var before := snapshot(house)
	if recipe == null or recipe.schema_version != 1 or recipe.recipe_id.is_empty():
		return _failure("Ricetta mancante o versione non supportata.", before)
	if house.wing_enabled or house.has_method("volume_host"):
		return _failure("Applica la ricetta al corpo principale senza ala legacy; gli edifici esistenti restano invariati.", before)
	if structural_seed < 0: structural_seed = int(before.provenance.get("structural_seed", house.house_seed))
	if detail_seed < 0: detail_seed = int(before.provenance.get("detail_seed", hash(str(structural_seed) + ":details")))
	if minimum_wall_height < 0: minimum_wall_height = float(before.provenance.get("minimum_wall_height", 0.0))
	var resolved := recipe.resolved(structural_seed, variant_id)
	if resolved.has("error"): return _failure(resolved.error, before)
	var after := before.duplicate(true)
	after.recipe = recipe
	var old_main: Dictionary = before.provenance.get("main_baseline", {}).duplicate(true)
	var main: Dictionary = resolved.main_properties.duplicate(true)
	var plan := house.get_node_or_null("InteriorPlan")
	var minimum_height := minimum_wall_height
	if plan and plan.has_method("levels"):
		minimum_height = maxf(minimum_height, plan.levels().size() * plan.floor_height)
	if main.has("wall_height"): main.wall_height = maxf(float(main.wall_height), minimum_height)
	# Migrate an earlier baseline whose eaves were raised by InteriorPlan.
	# This is a floor constraint, not a hand edit to the exterior.
	if old_main.has("wall_height"): old_main.wall_height = maxf(float(old_main.wall_height), minimum_height)
	var baseline := old_main.duplicate(true)
	main.archetype_id = recipe.role
	main.house_seed = structural_seed
	for key in main:
		if key not in MAIN_FIELDS: return _failure("Proprietà principale non supportata: " + str(key), before)
		if preserve_footprint and key in ["width", "depth"]: continue
		# A manual change after the previous recipe remains authoritative, per property.
		if old_main.has(key) and not _equal(before.properties[key], old_main[key]): continue
		after.properties[key] = main[key]
		baseline[key] = main[key]
	var deleted := PackedStringArray(before.provenance.get("deleted_ids", PackedStringArray()))
	var existing := {}
	for record: Dictionary in before.parts: existing[record.id] = record
	for id in before.provenance.get("generated_ids", []):
		if not existing.has(id) and id not in deleted: deleted.append(id)
	var desired := []
	var ids := {}
	for descriptor: Dictionary in resolved.components:
		if str(descriptor.get("kind", "volume")) not in ["volume", "balcony"]:
			return _failure("Tipo componente non supportato: " + str(descriptor.get("kind")), before)
	for container_name in CONTAINERS:
		var descriptors: Array = resolved.details if container_name == "RecipeDetails" else resolved.components.filter(func(d): return str(d.get("kind", "volume")) == ("balcony" if container_name == "Components" else "volume"))
		for descriptor: Dictionary in descriptors:
			var local_id := str(descriptor.get("id", ""))
			var id := recipe.recipe_id + ":" + local_id
			if local_id.is_empty() or ids.has(id): return _failure("ID componente mancante o duplicato: " + local_id, before)
			ids[id] = true
			if id in deleted: continue
			if existing.has(id) and existing[id].container != container_name: return _failure("Il tipo del componente è cambiato: assegna un nuovo ID a " + local_id, before)
			if existing.has(id) and _protected(existing[id]):
				desired.append(existing[id]); continue
			var record := {"id": id, "container": container_name, "name": local_id.validate_node_name(),
				"descriptor": descriptor.duplicate(true), "values": {}, "baseline": {}, "locked": false}
			if existing.has(id): record.node = existing[id].node
			desired.append(record)
	# A previous recipe's edited/locked parts are kept; ordinary generated parts may be retired.
	for record: Dictionary in before.parts:
		if not ids.has(record.id) and _protected(record): desired.append(record)
	var ghost := House.new()
	for key in after.properties: ghost.set(key, after.properties[key])
	ghost.openings = house.openings.duplicate(true)
	if plan and plan.has_method("levels"):
		var ghost_plan = preload("res://addons/house_builder/plan.gd").new()
		ghost_plan.name = "InteriorPlan"; ghost_plan.floor_height = plan.floor_height; ghost.add_child(ghost_plan)
		for source in plan.levels():
			var level := Node3D.new(); level.name = source.name
			level.set_meta("floor_id", source.get_meta("floor_id", "")); ghost_plan.add_child(level)
	# Validate against the actual manual appendages as well, not just the new recipe.
	var volumes := Node3D.new(); volumes.name = "Volumes"; ghost.add_child(volumes)
	var original_volumes := house.get_node_or_null("Volumes")
	if original_volumes:
		for node in original_volumes.get_children():
			if node.has_meta("recipe_part_id") or not node.has_method("volume_error"): continue
			var copy := Volume.new(); _write(copy, _read(node, VOLUME_FIELDS)); copy.transform = node.transform; volumes.add_child(copy)
	var problems := PackedStringArray()
	var balconies := Node3D.new(); balconies.name = "Components"; ghost.add_child(balconies)
	for source in house.attached_components():
		if source.has_meta("recipe_part_id"): continue
		var copy := Balcony.new(); _write(copy, _read(source, BALCONY_FIELDS)); balconies.add_child(copy); copy.prepare_attachment()
	for record: Dictionary in desired:
		if record.container != "Volumes": continue
		var volume := Volume.new(); volume.name = record.name; volumes.add_child(volume)
		if record.has("descriptor"):
			var d: Dictionary = record.descriptor
			var properties: Dictionary = d.get("properties", {}).duplicate(true)
			for key in properties:
				if key not in VOLUME_FIELDS: problems.append("Proprietà volume sconosciuta: " + str(key))
			_write(volume, properties)
			volume.volume_id = record.id
			volume.house_seed = hash(str(structural_seed) + ":" + record.id)
			var walls: Array = d.get("preferred_walls", [int(properties.get("host_wall", 1))])
			var fit := false
			for wall in walls:
				volume.host_wall = int(wall)
				if d.has("width_ratio"): volume.width = clampf(ghost.wall_length(int(wall)) * float(d.width_ratio), 1.8, ghost.wall_length(int(wall)) - .6)
				volume.prepare_attachment()
				if volume.volume_error().is_empty(): fit = true; break
			if not fit: problems.append(record.name + ": " + volume.volume_error())
			record.values = _read(volume, VOLUME_FIELDS)
			record.values["transform"] = volume.transform
			record.baseline = {"values": record.values.duplicate(true), "name": record.name}
			record.erase("descriptor")
		else:
			_write(volume, record.values)
			volume.prepare_attachment()
			if not volume.volume_error().is_empty(): problems.append(record.name + ": " + volume.volume_error())
	for record: Dictionary in desired:
		if record.container != "Components": continue
		var balcony := Balcony.new(); balcony.name = record.name; balconies.add_child(balcony)
		if record.has("descriptor"):
			var descriptor: Dictionary = record.descriptor
			var properties: Dictionary = descriptor.get("properties", {})
			for key in properties:
				if key not in BALCONY_FIELDS: problems.append("Proprietà balcone sconosciuta: " + str(key))
			_write(balcony, properties); balcony.component_id = record.id
			if descriptor.has("width_ratio"): balcony.balcony_width = minf(ghost.wall_length(balcony.wall()) - .4, ghost.wall_length(balcony.wall()) * float(descriptor.width_ratio))
			balcony.prepare_attachment()
			record.values = _read(balcony, BALCONY_FIELDS); record.values.transform = balcony.transform
			record.baseline = {"values": record.values.duplicate(true), "name": record.name}
			record.erase("descriptor")
		else:
			_write(balcony, record.values); balcony.prepare_attachment()
		if not balcony.validation_error().is_empty(): problems.append(record.name + ": " + balcony.validation_error())
	# Details have full transforms, dimensions and seeds, never camera-facing proxies.
	for record: Dictionary in desired:
		if record.container != "RecipeDetails" or not record.has("descriptor"): continue
		var d: Dictionary = record.descriptor
		var detail_script := load("res://addons/house_builder/recipe_detail.gd") as Script
		if detail_script == null or not detail_script.can_instantiate():
			problems.append("Generatore dettagli non disponibile."); continue
		var detail: Node3D = detail_script.new()
		var values := _read(detail, DETAIL_FIELDS)
		for key in DETAIL_FIELDS:
			if d.has(key): values[key] = d[key]
		values.detail_id = record.id
		values.detail_seed = hash(str(detail_seed) + ":" + record.id)
		var position := Vector3.ZERO
		var anchor := str(d.get("anchor", "ground"))
		var u := float(d.get("u", 0))
		if anchor == "front": position = Vector3(u * ghost.width * .5, 0, ghost.depth * .5)
		elif anchor == "back": position = Vector3(u * ghost.width * .5, 0, -ghost.depth * .5)
		elif anchor == "left": position = Vector3(-ghost.width * .5, 0, u * ghost.depth * .5)
		elif anchor == "right": position = Vector3(ghost.width * .5, 0, u * ghost.depth * .5)
		elif anchor == "roof":
			position = Vector3(u * ghost.width * .5, ghost.wall_height + ghost.roof_height * (1.0 - absf(u)) - .2, float(d.get("v", 0)) * ghost.depth * .5)
		position += d.get("position", Vector3.ZERO)
		var rotation: Vector3 = d.get("rotation_degrees", Vector3.ZERO)
		values.transform = Transform3D(Basis.from_euler(rotation * PI / 180.0), position)
		record.values = values
		record.baseline = {"values": values.duplicate(true), "name": record.name}
		record.erase("descriptor")
		detail.free()
	# Validate the final authored values, including protected existing details.
	# An unknown kind must never silently become an empty generated component.
	var detail_type := load("res://addons/house_builder/recipe_detail.gd") as Script
	if detail_type != null and detail_type.can_instantiate():
		var prototype: Node3D = detail_type.new()
		for record: Dictionary in desired:
			if record.container != "RecipeDetails": continue
			if str(record.values.get("kind", "")) not in prototype.KINDS:
				problems.append(record.name + ": tipo dettaglio non registrato: " + str(record.values.get("kind", "")))
			var dimensions = record.values.get("dimensions")
			if not dimensions is Vector3 or not dimensions.is_finite() or minf(dimensions.x, minf(dimensions.y, dimensions.z)) < .05:
				problems.append(record.name + ": le tre dimensioni del dettaglio devono essere finite e almeno 0,05 m.")
		prototype.free()
	ghost.free()
	if not problems.is_empty(): return {"ok": false, "errors": problems, "before": before}
	after.parts = desired
	after.containers = before.containers.duplicate()
	for record: Dictionary in desired:
		if record.container not in after.containers: after.containers.append(record.container)
		# Retained edits from another recipe remain managed, so a later manual
		# deletion is remembered even if the author switches recipes again.
		ids[record.id] = true
	after.provenance = {"schema": 1, "recipe_id": recipe.recipe_id, "variant_id": resolved.variant_id,
		"structural_seed": structural_seed, "detail_seed": detail_seed, "main_baseline": baseline,
		"generated_ids": PackedStringArray(ids.keys()), "deleted_ids": deleted}
	if minimum_wall_height > 0: after.provenance.minimum_wall_height = minimum_wall_height
	return {"ok": true, "errors": PackedStringArray(), "before": before, "after": after}

static func apply(house: Node3D, state: Dictionary) -> void:
	_write(house, state.properties)
	house.building_recipe = state.recipe
	house.recipe_provenance = state.provenance.duplicate(true)
	var wanted := {}
	for record: Dictionary in state.parts: wanted[record.id] = true
	for container_name in CONTAINERS:
		var container := house.get_node_or_null(NodePath(container_name))
		if container:
			for child in container.get_children():
				var id := str(child.get_meta("recipe_part_id", ""))
				if not id.is_empty() and not wanted.has(id):
					container.remove_child(child)
					_unowned(child)
					house._recipe_retired[id] = child
	for record: Dictionary in state.parts:
		var container := house.get_node_or_null(NodePath(record.container))
		if container == null:
			container = Node3D.new(); container.name = record.container; house.add_child(container)
		var node: Node3D = record.get("node")
		if not is_instance_valid(node): node = house._recipe_retired.get(record.id)
		if not is_instance_valid(node):
			node = _new_part(record.container)
			record.node = node
		house._recipe_retired.erase(record.id)
		node.name = record.name
		_write(node, record.values)
		node.set_meta("recipe_part_id", record.id)
		node.set_meta("recipe_baseline", record.baseline.duplicate(true))
		node.set_meta("recipe_locked", record.locked)
		if node.get_parent() != container:
			if node.get_parent(): node.get_parent().remove_child(node)
			_unowned(node)
			container.add_child(node)
		var scene_owner: Node = house.owner if house.owner else house
		if scene_owner:
			container.owner = scene_owner
			_owned(node, scene_owner)
		if node.has_method("request_rebuild"): node.request_rebuild()
		elif node.is_inside_tree() and node.has_method("rebuild"): node.rebuild()
	for container_name in CONTAINERS:
		var container := house.get_node_or_null(NodePath(container_name))
		if container and container_name not in state.containers and container.get_child_count() == 0:
			container.free()
	house._recipe_notification_pending = true
	house.request_rebuild()

static func _record(node: Node3D, container_name: String) -> Dictionary:
	var values := _read(node, _part_fields(container_name))
	values.transform = node.transform
	var baseline: Dictionary = node.get_meta("recipe_baseline", {}).duplicate(true)
	# Earlier recipe scenes tracked fewer secondary Volume properties. Missing
	# entries mean the generator defaults; non-default edits remain protected.
	if container_name == "Volumes" and baseline.has("values"):
		var defaults: Node3D
		for key in VOLUME_FIELDS:
			if baseline.values.has(key): continue
			if defaults == null: defaults = Volume.new()
			baseline.values[key] = defaults.get(key)
		if defaults: defaults.free()
	return {"id": str(node.get_meta("recipe_part_id")), "container": container_name, "name": String(node.name),
		"node": node, "values": values, "baseline": baseline,
		"locked": bool(node.get("locked")) if container_name in ["RecipeDetails", "Components"] else bool(node.get_meta("recipe_locked", false)),
		"has_manual_children": node.get_child_count() > 0}

static func _new_part(container_name: String) -> Node3D:
	if container_name == "Volumes": return Volume.new()
	if container_name == "Components": return Balcony.new()
	return load("res://addons/house_builder/recipe_detail.gd").new()

static func _part_fields(container_name: String) -> Array:
	if container_name == "Volumes": return VOLUME_FIELDS
	if container_name == "Components": return BALCONY_FIELDS
	return DETAIL_FIELDS

static func _protected(record: Dictionary) -> bool:
	return record.locked or record.get("has_manual_children", false) or record.baseline.is_empty() \
		or record.name != record.baseline.get("name", "") or not _equal(record.values, record.baseline.get("values", {}))

static func _read(node: Object, fields: Array) -> Dictionary:
	var result := {}
	for field in fields: result[field] = node.get(field)
	return result.duplicate(true)

static func _write(node: Object, values: Dictionary) -> void:
	for key in values: node.set(key, values[key])

static func _owned(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for child in node.get_children(): _owned(child, scene_owner)

static func _unowned(node: Node) -> void:
	node.owner = null
	for child in node.get_children(): _unowned(child)

static func _equal(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return is_equal_approx(float(a), float(b))
	if a is Vector3 or a is Transform3D: return typeof(a) == typeof(b) and a.is_equal_approx(b)
	if a is Dictionary:
		if not b is Dictionary or a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equal(a[key], b[key]): return false
		return true
	if a is Array:
		if not b is Array or a.size() != b.size(): return false
		for i in a.size():
			if not _equal(a[i], b[i]): return false
		return true
	return a == b

static func _failure(message: String, before: Dictionary) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message]), "before": before}

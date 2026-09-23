@tool
extends RefCounted
## Disposable, project-local cache. Never stores authored scene state.
const DIRECTORY := "user://generation_cache_v1/"
static var _source_keys: Dictionary = {}
static var _pending_saves: Dictionary = {}
static var _save_scheduled := false
static var _editors: Dictionary={}

static func hold_writes(owner: Object) -> void:
	_editors[owner.get_instance_id()]=weakref(owner)

static func release_writes(owner: Object) -> void:
	_editors.erase(owner.get_instance_id())

static func _has_active_editor() -> bool:
	for id in _editors.keys():
		if _editors[id].get_ref()==null: _editors.erase(id)
	return not _editors.is_empty()


static func queue_save(resource: Resource, path: String) -> void:
	_pending_saves[path]=resource
	if _save_scheduled: return
	var tree := Engine.get_main_loop() as SceneTree
	if tree==null: return
	_save_scheduled=true
	tree.create_timer(1.0).timeout.connect(_flush_save)

static func _flush_save() -> void:
	_save_scheduled=false
	if _pending_saves.is_empty(): return
	if not _has_active_editor():
		var path: String=_pending_saves.keys()[0]
		ResourceSaver.save(_pending_saves[path],path)
		_pending_saves.erase(path)
	if not _pending_saves.is_empty():
		_save_scheduled=true
		(Engine.get_main_loop() as SceneTree).create_timer(.1).timeout.connect(_flush_save)

static func digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

static func snapshot(value: Variant, depth: int = 0) -> Variant:
	if depth>12: return null
	if value is Resource:
		var result := {}
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["resource_name","resource_local_to_scene","script"]:
				result[property.name]=snapshot(value.get(property.name),depth+1)
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(snapshot(item,depth+1))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key]=snapshot(value[key],depth+1)
		return result
	return value

static func sources(paths: Array) -> String:
	# Read modification times on each request so editor script reloads invalidate.
	var stamps: Array=[]
	for path in paths: stamps.append([path,FileAccess.get_modified_time(path)])
	var key := str(stamps)
	if not _source_keys.has(key):
		var hashes: Array=[]
		for path in paths: hashes.append(FileAccess.get_sha256(path))
		_source_keys[key]=digest(hashes)
	return _source_keys[key]

static func path_for(kind: String, key: String, extension: String) -> String:
	var namespace_key := ProjectSettings.globalize_path("res://")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--generation-cache-test="): namespace_key+=argument
	var directory := DIRECTORY+digest(namespace_key)+"/"+kind+"/"
	DirAccess.make_dir_recursive_absolute(directory)
	return directory+key+extension

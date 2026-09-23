extends RefCounted
## Lettura del manifest del pacchetto NPC (assets/npc_ai/npc_package_manifest.json, incluso nel PCK) e
## controlli di presenza di runtime e modello: esistenza e dimensione, MAI sha256 all'avvio del gioco
## (su 1-2 GB bloccherebbe per secondi: lo fa il tool di sviluppo). Nessun download da qui.
const Paths := preload("res://addons/npc_ai/npc_ai_paths.gd")

var data: Dictionary = {}
var error := ""
var source_path := ""


func load_from(path := Paths.MANIFEST_RES_PATH) -> bool:
	error = ""
	source_path = path
	if not FileAccess.file_exists(path):
		error = "manifest assente: " + path
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary) or not json.data.has("runtime") or not json.data.has("models"):
		error = "manifest non valido: " + path
		return false
	data = json.data
	return true


func is_loaded() -> bool:
	return not data.is_empty()


func runtime() -> Dictionary:
	return data.get("runtime", {})


func runtime_dir() -> String:
	return Paths.runtime_dir(str(runtime().get("install_dir", "runtime")))


func runtime_executable() -> String:
	return runtime_dir().path_join(str(runtime().get("executable", "llama-server.exe")))


func runtime_expected_files() -> PackedStringArray:
	return _strings(runtime().get("expected_files", []))


func runtime_tag() -> String:
	return str(runtime().get("tag", ""))


func server_args() -> PackedStringArray:
	return _strings(runtime().get("server_args", []))


func context_size() -> int:
	return int(runtime().get("context_size", 2048))


func start_timeout_msec() -> int:
	return int(runtime().get("start_timeout_msec", 120000))


func default_model_id() -> String:
	return str(data.get("default_model", ""))


func model_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in data.get("models", []):
		out.append(str(entry.get("id", "")))
	return out


func model(id: String) -> Dictionary:
	for entry in data.get("models", []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func models_dir() -> String:
	return Paths.models_dir(str(data.get("models_dir", "models")))


func model_path(id: String) -> String:
	var entry := model(id)
	if entry.is_empty():
		return ""
	return models_dir().path_join(str(entry.get("file", "")))


func model_system_prefix(id: String) -> String:
	return str(model(id).get("system_prefix", ""))


func model_request_params(id: String) -> Dictionary:
	var params: Variant = model(id).get("request_params", {})
	return params.duplicate(true) if params is Dictionary else {}


## {ok, dir, executable, missing: PackedStringArray, gpu_backend: bool}
func check_runtime() -> Dictionary:
	var dir := runtime_dir()
	var missing := PackedStringArray()
	for name in runtime_expected_files():
		if not FileAccess.file_exists(dir.path_join(name)):
			missing.append(name)
	var gpu_file := str(runtime().get("gpu_backend_file", ""))
	return {"ok": missing.is_empty() and FileAccess.file_exists(runtime_executable()), "dir": dir,
		"executable": runtime_executable(), "missing": missing,
		"gpu_backend": gpu_file != "" and FileAccess.file_exists(dir.path_join(gpu_file))}


## {ok, path, reason, size}: esistenza e dimensione dichiarata; il checksum e' compito del tool.
func check_model(id: String) -> Dictionary:
	var entry := model(id)
	if entry.is_empty():
		return {"ok": false, "path": "", "reason": "modello non presente nel manifest: " + id, "size": 0}
	var path := model_path(id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "path": path, "reason": "file del modello assente", "size": 0}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "path": path, "reason": "file del modello non leggibile", "size": 0}
	var size := file.get_length()
	file.close()
	var expected := int(entry.get("size", 0))
	if expected > 0 and size != expected:
		return {"ok": false, "path": path, "reason": "dimensione diversa dal manifest (%d != %d)" % [size, expected], "size": size}
	return {"ok": true, "path": path, "reason": "", "size": size}


func available_model_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in model_ids():
		if check_model(id)["ok"]:
			out.append(id)
	return out


static func _strings(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for item in value:
			out.append(str(item))
	return out

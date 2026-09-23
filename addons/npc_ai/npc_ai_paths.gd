extends RefCounted
## Dove vivono runtime, pesi e dati dell'NPC. In editor il pacchetto sta in res://assets/npc_ai/ (cartelle
## con .gdignore: Godot non le importa ne' le esporta); in un progetto esportato sta ACCANTO all'eseguibile,
## in <cartella exe>/npc_ai/, perche' globalize_path("res://") non funziona negli export e llama-server ha
## bisogno di percorsi reali. I dati del giocatore (memoria, log, stato, prove) stanno sotto user://npc_ai/.
const PACKAGE_RES_DIR := "res://assets/npc_ai"
const PACKAGE_EXPORT_DIR := "npc_ai"
const MANIFEST_RES_PATH := "res://assets/npc_ai/npc_package_manifest.json"
const USER_ROOT := "user://npc_ai"


static func in_editor_build() -> bool:
	return OS.has_feature("editor")


## Radice assoluta del pacchetto (runtime/, models/, licenses/).
static func package_root() -> String:
	if in_editor_build():
		return ProjectSettings.globalize_path(PACKAGE_RES_DIR)
	return OS.get_executable_path().get_base_dir().path_join(PACKAGE_EXPORT_DIR)


static func runtime_dir(install_dir := "runtime") -> String:
	return package_root().path_join(install_dir)


static func models_dir(models_dir_name := "models") -> String:
	return package_root().path_join(models_dir_name)


## Sottocartella di user://npc_ai/, creata se manca. Restituisce il percorso user:// (non assoluto).
static func user_dir(sub: String) -> String:
	var path := USER_ROOT.path_join(sub) if sub != "" else USER_ROOT
	DirAccess.make_dir_recursive_absolute(path)
	return path


static func user_dir_absolute(sub: String) -> String:
	return ProjectSettings.globalize_path(user_dir(sub))


static func memory_dir() -> String:
	return user_dir("memory")


static func logs_dir() -> String:
	return user_dir("logs")


static func state_dir() -> String:
	return user_dir("state")


static func bench_dir() -> String:
	return user_dir("bench")


## Confronto di percorsi tollerante a separatori e maiuscole (Windows).
static func same_file(a: String, b: String) -> bool:
	return normalize(a) == normalize(b)


static func normalize(path: String) -> String:
	return path.replace("\\", "/").to_lower().rstrip("/")

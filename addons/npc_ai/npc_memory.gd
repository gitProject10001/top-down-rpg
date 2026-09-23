extends RefCounted
## Memoria locale di un NPC, una per npc_id, con schema versionato e limiti di spazio. Tre liste separate
## e mai mescolate: eventi canonici (scritti SOLO dal gioco, source "game"), dichiarazioni del giocatore
## (non verificate) e scambi (testo generato o di ripiego). File JSON sotto user://npc_ai/memory/, scrittura
## sicura (.tmp -> .bak -> file) e recupero da file assente o corrotto. Non tocca i salvataggi del gioco.
const SCHEMA_VERSION := 1
const MAX_EVENTS := 32
const MAX_CLAIMS := 16
const MAX_EXCHANGES := 24
const MAX_TEXT_CHARS := 320
const MAX_FILE_BYTES := 65536
const ID_PATTERN := "^[a-z0-9_]{1,32}$"
const EVENT_ID_PATTERN := "^[a-z0-9_]{1,48}$"
const DEFAULT_ROOT := "user://npc_ai/memory"
static var _re_event_id: RegEx

var npc_id := ""
var root_dir := DEFAULT_ROOT
var canonical_events: Array[Dictionary] = []   ## {id, text, day, source: "game"}
var player_claims: Array[Dictionary] = []      ## {text, session, turn}
var exchanges: Array[Dictionary] = []          ## {session, turn, player, npc, kind: "generated"|"fallback"}
var stats := {"sessions": 0, "last_session_utc": ""}
var last_load_status := "unloaded"   ## fresh | loaded | recovered_tmp | recovered_bak | corrupt_reset | invalid_id | io_error
var last_error := ""
var dropped_on_load := 0             ## voci scartate perche' non conformi (es. eventi senza source "game")


func setup(id: String, root := DEFAULT_ROOT) -> bool:
	var re := RegEx.new()
	re.compile(ID_PATTERN)
	if re.search(id) == null:
		last_load_status = "invalid_id"
		last_error = "npc_id non conforme: " + id
		npc_id = ""
		return false
	npc_id = id
	root_dir = root
	return true


func file_path() -> String:
	return root_dir.path_join(npc_id + ".json")


func is_ready() -> bool:
	return npc_id != ""


func load() -> bool:
	if not is_ready():
		return false
	_clear_lists()
	var main := file_path()
	var candidates := [[main, "loaded"], [main + ".tmp", "recovered_tmp"], [main + ".bak", "recovered_bak"]]
	var main_was_corrupt := false
	for candidate in candidates:
		var path: String = candidate[0]
		if not FileAccess.file_exists(path):
			continue
		var read := _read_candidate(path)
		if read["ok"] and apply_dict(read["data"]):
			last_load_status = candidate[1]
			last_error = ""
			if candidate[1] != "loaded":
				save()   # ripristina il file principale dalla copia recuperata
			return true
		last_error = str(read.get("error", "contenuto non valido")) + " in " + path
		_clear_lists()
		if path == main:
			main_was_corrupt = true
			_quarantine(main)
	last_load_status = "corrupt_reset" if main_was_corrupt else "fresh"
	return true


func save() -> bool:
	if not is_ready():
		return false
	var err := DirAccess.make_dir_recursive_absolute(root_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		last_error = "impossibile creare " + root_dir
		last_load_status = "io_error"
		return false
	var main := file_path()
	var tmp := main + ".tmp"
	var bak := main + ".bak"
	var text := _serialize_within_limit()
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_error = "impossibile scrivere " + tmp
		last_load_status = "io_error"
		return false
	file.store_string(text)
	file.flush()
	file.close()
	var dir := DirAccess.open(root_dir)
	if dir == null:
		last_error = "impossibile aprire " + root_dir
		return false
	var main_name := main.get_file()
	if dir.file_exists(main_name):
		if dir.file_exists(bak.get_file()):
			dir.remove(bak.get_file())
		dir.rename(main_name, bak.get_file())
	err = dir.rename(tmp.get_file(), main_name)
	if err != OK:
		last_error = "rename fallita su " + main
		last_load_status = "io_error"
		return false
	return true


## Svuota la memoria e cancella i file (principale, .tmp, .bak). La revisione del contesto va aggiornata dal chiamante.
func reset() -> bool:
	_clear_lists()
	stats = {"sessions": 0, "last_session_utc": ""}
	if not is_ready():
		return false
	var dir := DirAccess.open(root_dir)
	if dir == null:
		return true
	for suffix: String in ["", ".tmp", ".bak"]:
		var name := (file_path() + suffix).get_file()
		if dir.file_exists(name):
			dir.remove(name)
	last_load_status = "fresh"
	return true


## Unico ingresso in canon: solo il gioco lo chiama, con un evento che ha davvero confermato.
func add_canonical_event(id: String, text: String, day: int) -> bool:
	if not _event_id_ok(id) or _clip(text) == "" or has_event(id):
		return false
	canonical_events.append({"id": id, "text": _clip(text), "day": day, "source": "game"})
	_trim()
	return true


func has_event(id: String) -> bool:
	for event in canonical_events:
		if event["id"] == id:
			return true
	return false


func add_player_claim(text: String, session: String, turn: int) -> void:
	var clipped := _clip(text)
	if clipped == "":
		return
	player_claims.append({"text": clipped, "session": session, "turn": turn})
	_trim()


func add_exchange(session: String, turn: int, player: String, npc: String, kind: String) -> void:
	exchanges.append({"session": session, "turn": turn, "player": _clip(player), "npc": _clip(npc),
		"kind": "generated" if kind == "generated" else "fallback"})
	_trim()


func note_session(utc: String) -> void:
	stats["sessions"] = int(stats.get("sessions", 0)) + 1
	stats["last_session_utc"] = utc


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"npc_id": npc_id,
		"updated_utc": Time.get_datetime_string_from_system(true, true),
		"canonical_events": canonical_events.duplicate(true),
		"player_claims": player_claims.duplicate(true),
		"exchanges": exchanges.duplicate(true),
		"stats": stats.duplicate(),
	}


## Applica un dizionario letto da file: schema, identita' e forma di ogni voce vengono controllati;
## le voci non conformi vengono scartate (contate in dropped_on_load), mai "aggiustate".
func apply_dict(data: Dictionary) -> bool:
	dropped_on_load = 0
	var version: Variant = data.get("schema_version", null)
	if not (version is int or version is float) or int(version) != SCHEMA_VERSION:
		last_error = "schema_version non supportato: " + str(version)
		return false
	if str(data.get("npc_id", "")) != npc_id:
		last_error = "npc_id del file diverso: " + str(data.get("npc_id", ""))
		return false
	_clear_lists()
	for raw in _list(data.get("canonical_events", [])):
		if raw is Dictionary and raw.get("source", "") == "game" and _event_id_ok(str(raw.get("id", ""))) and _clip(str(raw.get("text", ""))) != "" and not has_event(str(raw["id"])):
			canonical_events.append({"id": str(raw["id"]), "text": _clip(str(raw["text"])), "day": int(raw.get("day", 0)), "source": "game"})
		else:
			dropped_on_load += 1
	for raw in _list(data.get("player_claims", [])):
		if raw is Dictionary and str(raw.get("text", "")) != "":
			player_claims.append({"text": _clip(str(raw["text"])), "session": str(raw.get("session", "")), "turn": int(raw.get("turn", 0))})
		else:
			dropped_on_load += 1
	for raw in _list(data.get("exchanges", [])):
		if raw is Dictionary and raw.has("player") and raw.has("npc"):
			exchanges.append({"session": str(raw.get("session", "")), "turn": int(raw.get("turn", 0)), "player": _clip(str(raw["player"])),
				"npc": _clip(str(raw["npc"])), "kind": "generated" if str(raw.get("kind", "")) == "generated" else "fallback"})
		else:
			dropped_on_load += 1
	var raw_stats: Variant = data.get("stats", {})
	stats = {"sessions": int(raw_stats.get("sessions", 0)) if raw_stats is Dictionary else 0,
		"last_session_utc": str(raw_stats.get("last_session_utc", "")) if raw_stats is Dictionary else ""}
	_trim()
	return true


func _read_candidate(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "apertura fallita"}
	var length := file.get_length()
	if length > MAX_FILE_BYTES * 2:
		file.close()
		return {"ok": false, "error": "file oltre il doppio del limite (%d byte)" % length}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "JSON non valido (%s)" % json.get_error_message()}
	if not (json.data is Dictionary):
		return {"ok": false, "error": "JSON non valido (non e' un oggetto)"}
	return {"ok": true, "data": json.data}


func _quarantine(path: String) -> void:
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "_")
	DirAccess.copy_absolute(path, path + ".corrupt." + stamp)


func _serialize_within_limit() -> String:
	var text := JSON.stringify(to_dict(), "\t")
	var guard := 0
	while text.to_utf8_buffer().size() > MAX_FILE_BYTES and guard < 200:
		guard += 1
		if not exchanges.is_empty():
			exchanges.pop_front()
		elif not player_claims.is_empty():
			player_claims.pop_front()
		elif not canonical_events.is_empty():
			canonical_events.pop_front()
		else:
			break
		text = JSON.stringify(to_dict(), "\t")
	return text


func _trim() -> void:
	while canonical_events.size() > MAX_EVENTS:
		canonical_events.pop_front()
	while player_claims.size() > MAX_CLAIMS:
		player_claims.pop_front()
	while exchanges.size() > MAX_EXCHANGES:
		exchanges.pop_front()


func _clear_lists() -> void:
	canonical_events.clear()
	player_claims.clear()
	exchanges.clear()


## Una riga sola, senza controlli o invisibili, spazi compattati, al massimo MAX_TEXT_CHARS: vale per cio' che
## entra dal gioco e per cio' che viene riletto da file, cosi' un file modificato a mano non porta righe
## o sezioni nel prompt.
static func _clip(text: String) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code == 9 or code == 10 or code == 13 or code == 0x85 or code == 0xA0 or code == 0x2028 or code == 0x2029:
			out += " "
		elif code < 32 or (code >= 127 and code < 160) or code == 0xAD or (code >= 0x200B and code <= 0x200F) \
				or code == 0x2060 or code == 0xFEFF:
			continue
		else:
			out += text[i]
	out = " ".join(out.split(" ", false))
	if out.length() > MAX_TEXT_CHARS:
		out = out.substr(0, MAX_TEXT_CHARS)
	return out


static func _event_id_ok(id: String) -> bool:
	if _re_event_id == null:
		_re_event_id = RegEx.new()
		_re_event_id.compile(EVENT_ID_PATTERN)
	return _re_event_id.search(id) != null


static func _list(value: Variant) -> Array:
	return value if value is Array else []

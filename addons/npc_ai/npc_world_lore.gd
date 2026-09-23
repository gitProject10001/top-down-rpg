extends RefCounted
## Lore condivisa del mondo: un solo file di dati (assets/npc_ai/world_lore.json) per tutti gli NPC, letto dal
## gioco e mai scritto dal modello. Ogni voce e' una frase sola, con etichette per la ricerca, un elenco di
## chi la conosce (`all`, `npc:<id>`, `trade:<mestiere>`), una priorita' e due flag: `always` (entra sempre
## nel contesto) e `secret` (non viene MAI inviata: serve al gioco e alle prove). La selezione e'
## deterministica e sta in un budget di voci e caratteri: prima le voci `always`, poi quelle che
## condividono parole con la battuta del giocatore e con gli ultimi turni, poi le altre per priorita'.
const DEFAULT_PATH := "res://assets/npc_ai/world_lore.json"
const ID_PATTERN := "^[a-z0-9_]{1,48}$"
const MAX_TEXT_CHARS := 320
const DEFAULT_MAX_ENTRIES := 12
const DEFAULT_MAX_CHARS := 1400
const MIN_KEYWORD_LENGTH := 4
const SCORE_ALWAYS := 1000
const SCORE_PLAYER_HIT := 10
const SCORE_RECENT_HIT := 3

var world_name := ""
var summary := ""
var entries: Array[Dictionary] = []   ## {id, text, tags, known_by, priority, always, secret}
var error := ""
var source_path := ""

static var _re_id: RegEx


func load_from(path := DEFAULT_PATH) -> bool:
	error = ""
	source_path = path
	if not FileAccess.file_exists(path):
		error = "lore assente: " + path
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		error = "lore non valida: " + path
		return false
	return from_dict(json.data)


func from_dict(data: Dictionary) -> bool:
	entries.clear()
	world_name = str(data.get("world", {}).get("name", "")) if data.get("world", {}) is Dictionary else ""
	summary = _clean_line(str(data.get("world", {}).get("summary", ""))) if data.get("world", {}) is Dictionary else ""
	var raw_entries: Variant = data.get("entries", [])
	if not data.has("entries") or not (raw_entries is Array):
		error = "lore: campo entries assente"
		return false
	var seen := {}
	for raw in raw_entries:
		if not (raw is Dictionary):
			continue
		var id := str(raw.get("id", ""))
		var text := _clean_line(str(raw.get("text", "")))
		if not _id_ok(id) or text == "" or seen.has(id):
			continue   # voce non conforme: scartata, mai "aggiustata"
		seen[id] = true
		var tags := PackedStringArray()
		for tag in _list(raw.get("tags", [])):
			tags.append(str(tag).to_lower())
		var known_by := PackedStringArray()
		for who in _list(raw.get("known_by", ["all"])):
			known_by.append(str(who).to_lower())
		if known_by.is_empty():
			known_by.append("all")
		entries.append({"id": id, "text": text, "tags": tags, "known_by": known_by,
			"priority": clampi(int(raw.get("priority", 5)), 0, 9), "always": bool(raw.get("always", false)),
			"secret": bool(raw.get("secret", false))})
	return true


func is_loaded() -> bool:
	return not entries.is_empty()


func size() -> int:
	return entries.size()


## Difetti del file che il gioco deve correggere prima di usarlo (il caricamento li scarta comunque).
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in entries:
		if entry["text"].length() > MAX_TEXT_CHARS:
			out.append("%s: testo oltre %d caratteri" % [entry["id"], MAX_TEXT_CHARS])
		if entry["tags"].is_empty() and not entry["always"]:
			out.append("%s: senza etichette e senza always, non verra' mai scelta per parole chiave" % entry["id"])
	return out


func secret_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in entries:
		if entry["secret"]:
			out.append(entry["text"])
	return out


func entry(id: String) -> Dictionary:
	for e in entries:
		if e["id"] == id:
			return e
	return {}


## Testi scelti per un NPC, nell'ordine in cui vanno nel prompt (prima le voci sempre presenti).
func select(npc_id: String, trade: String, player_text: String, recent_texts: PackedStringArray = PackedStringArray(),
		max_entries := DEFAULT_MAX_ENTRIES, max_chars := DEFAULT_MAX_CHARS) -> PackedStringArray:
	var out := PackedStringArray()
	for e in select_entries(npc_id, trade, player_text, recent_texts, max_entries, max_chars):
		out.append(e["text"])
	return out


## Come select(), ma con id e punteggio: per le prove e per il pannello del laboratorio.
func select_entries(npc_id: String, trade: String, player_text: String, recent_texts: PackedStringArray = PackedStringArray(),
		max_entries := DEFAULT_MAX_ENTRIES, max_chars := DEFAULT_MAX_CHARS) -> Array[Dictionary]:
	var player_words := _keywords(player_text)
	var recent_words := PackedStringArray()
	for text in recent_texts:
		for word in _keywords(text):
			if not recent_words.has(word):
				recent_words.append(word)
	var scored: Array[Dictionary] = []
	var npc_key := "npc:" + npc_id.to_lower()
	var trade_key := "trade:" + trade.to_lower()
	for e in entries:
		if e["secret"]:
			continue
		var known: PackedStringArray = e["known_by"]
		if not (known.has("all") or known.has(npc_key) or (trade != "" and known.has(trade_key))):
			continue
		var score: int = int(e["priority"])
		if e["always"]:
			score += SCORE_ALWAYS   # in testa per priorita' e id: le parole non le riordinano, cosi' l'apertura della sezione e' stabile
		else:
			score += SCORE_PLAYER_HIT * _hits(e, player_words)
			score += SCORE_RECENT_HIT * _hits(e, recent_words)
		scored.append({"id": e["id"], "text": e["text"], "score": score, "always": e["always"]})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["id"] < b["id"])
	var out: Array[Dictionary] = []
	var used := 0
	for e in scored:
		if out.size() >= max_entries:
			break
		var length: int = e["text"].length()
		if used + length > max_chars:
			continue   # non entra: si prova con la voce successiva, piu' corta
		used += length
		out.append(e)
	return out


static func _hits(e: Dictionary, words: PackedStringArray) -> int:
	if words.is_empty():
		return 0
	var text: String = str(e["text"]).to_lower()
	var tags: PackedStringArray = e["tags"]
	var hits := 0
	for word in words:
		if tags.has(word) or text.find(word) >= 0:
			hits += 1
	return hits


static func _keywords(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cleaned := text.to_lower()
	for ch in [",", ".", "!", "?", ";", ":", "'", "\"", "(", ")", "«", "»"]:
		cleaned = cleaned.replace(ch, " ")
	for word in cleaned.split(" ", false):
		if word.length() >= MIN_KEYWORD_LENGTH and not out.has(word):
			out.append(word)
	return out


static func _clean_line(text: String) -> String:
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
	return out.substr(0, MAX_TEXT_CHARS) if out.length() > MAX_TEXT_CHARS else out


static func _id_ok(id: String) -> bool:
	if _re_id == null:
		_re_id = RegEx.new()
		_re_id.compile(ID_PATTERN)
	return _re_id.search(id) != null


static func _list(value: Variant) -> Array:
	return value if value is Array else []

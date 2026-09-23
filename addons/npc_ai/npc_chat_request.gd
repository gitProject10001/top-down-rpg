extends RefCounted
## Una richiesta di battuta per un NPC: testo dentro, testo fuori. NON esiste alcun campo per comandi,
## azioni, oggetti, denaro o quest: il modello puo' solo proporre una frase. I campi fidati (persona, regole,
## fatti, eventi canonici) vengono dal gioco; player_text e player_claims sono testo non affidabile e il
## costruttore del contesto li tiene fuori dal ruolo di sistema. `world_lore` sono le voci della lore condivisa
## (assets/npc_ai/world_lore.json) scelte dal gioco per questo turno: testo fidato, mai scritto dal modello.
const SCHEMA_VERSION := 1
const DICT_KEYS: PackedStringArray = ["schema_version", "npc_id", "session_id", "request_id", "context_revision",
	"player_text", "persona", "rules", "facts", "world_lore", "canonical_events", "player_claims", "history", "limits", "created_msec"]
## Tetti assoluti: un limite richiesto oltre questi valori viene rifiutato dal validatore.
const HARD_CAPS := {"max_input_chars": 240, "max_output_chars": 480, "max_output_tokens": 160,
	"first_token_timeout_msec": 30000, "total_timeout_msec": 30000, "max_history_turns": 12}

var npc_id := ""
var session_id := ""            ## assegnato da NpcConversation.open(): "<npc_id>:<n>:<8 hex>"
var request_id := ""            ## "<session_id>/<turno>"
var context_revision := 0       ## deve coincidere con la revisione della sessione all'invio e alla consegna
var player_text := ""           ## gia' sanificato, <= limits.max_input_chars
var persona: PackedStringArray = PackedStringArray()          ## istruzioni del personaggio (fidate)
var rules: PackedStringArray = PackedStringArray()            ## regole di stile e confine (fidate)
var facts: PackedStringArray = PackedStringArray()            ## fatti consentiti scelti dal gioco (fidati)
var world_lore: PackedStringArray = PackedStringArray()       ## voci della lore condivisa scelte dal gioco (fidate)
var canonical_events: PackedStringArray = PackedStringArray() ## eventi confermati dal gioco (fidati)
var player_claims: PackedStringArray = PackedStringArray()    ## dichiarazioni del giocatore, NON verificate
var history: Array[Dictionary] = []                           ## [{"role": "user"|"assistant", "text": String}]
var limits: Dictionary = default_limits()
var created_msec := 0


static func default_limits() -> Dictionary:
	return {"max_input_chars": 240, "max_output_chars": 320, "max_output_tokens": 120,
		"first_token_timeout_msec": 8000, "total_timeout_msec": 20000, "max_history_turns": 6}


func limit(name: String) -> int:
	var fallback: int = default_limits().get(name, 0)
	return int(limits.get(name, fallback))


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"npc_id": npc_id,
		"session_id": session_id,
		"request_id": request_id,
		"context_revision": context_revision,
		"player_text": player_text,
		"persona": Array(persona),
		"rules": Array(rules),
		"facts": Array(facts),
		"world_lore": Array(world_lore),
		"canonical_events": Array(canonical_events),
		"player_claims": Array(player_claims),
		"history": history.duplicate(true),
		"limits": limits.duplicate(),
		"created_msec": created_msec,
	}


## Ricostruisce i campi da un dizionario; rifiuta chiavi sconosciute e tipi sbagliati.
func apply_dict(data: Dictionary) -> bool:
	for key in data.keys():
		if not DICT_KEYS.has(str(key)):
			return false
	if int(data.get("schema_version", SCHEMA_VERSION)) != SCHEMA_VERSION:
		return false
	npc_id = str(data.get("npc_id", ""))
	session_id = str(data.get("session_id", ""))
	request_id = str(data.get("request_id", ""))
	context_revision = int(data.get("context_revision", 0))
	player_text = str(data.get("player_text", ""))
	persona = _strings(data.get("persona", []))
	rules = _strings(data.get("rules", []))
	facts = _strings(data.get("facts", []))
	world_lore = _strings(data.get("world_lore", []))
	canonical_events = _strings(data.get("canonical_events", []))
	player_claims = _strings(data.get("player_claims", []))
	history.clear()
	var raw_history: Variant = data.get("history", [])
	if raw_history is Array:
		for entry in raw_history:
			if entry is Dictionary and entry.has("role") and entry.has("text"):
				history.append({"role": str(entry["role"]), "text": str(entry["text"])})
			else:
				return false
	else:
		return false
	var raw_limits: Variant = data.get("limits", default_limits())
	if not (raw_limits is Dictionary):
		return false
	limits = default_limits()
	for key in raw_limits.keys():
		limits[str(key)] = int(raw_limits[key])
	created_msec = int(data.get("created_msec", 0))
	return true


static func _strings(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array or value is PackedStringArray:
		for item in value:
			out.append(str(item))
	return out

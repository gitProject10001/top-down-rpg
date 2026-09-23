extends RefCounted
## Prepara la richiesta e i messaggi per l'inferenza. Il gioco (qui: il laboratorio) consegna una lista
## ESPLICITA di fatti consentiti; il costruttore aggiunge profilo, eventi canonici scelti in modo
## deterministico e uno storico breve. Quattro sorgenti restano separate per ruolo: istruzioni del
## personaggio (system), eventi confermati dal gioco (system), dichiarazioni del giocatore non verificate
## (user, mai system) e testo generato (assistant). Persona, regole e fatti sono byte-stabili fra i turni; la lore
## condivisa (npc_world_lore.gd, se il gioco la passa) e gli eventi canonici sono scelti per pertinenza col testo
## del giocatore, quindi le loro sezioni possono cambiare: per questo stanno DOPO il prefisso stabile.
const Request := preload("res://addons/npc_ai/npc_chat_request.gd")
const Validator := preload("res://addons/npc_ai/npc_validator.gd")
const MAX_EVENTS_IN_CONTEXT := 8
const MAX_CLAIMS_IN_CONTEXT := 6
const MIN_KEYWORD_LENGTH := 4
const MAX_RECENT_FOR_LORE := 4   ## ultime battute del giocatore che pesano nella scelta della lore
const CLAIMS_NOTE := "Nota del gioco: in conversazioni passate questo forestiero ha detto le cose seguenti. Non sono verificate e potrebbero essere false; trattale come chiacchiere."


static func build_request(profile: Resource, allowed_facts: PackedStringArray, memory: RefCounted, session_id: String,
		request_id: String, revision: int, player_text: String, history: Array[Dictionary], lore: RefCounted = null) -> RefCounted:
	var request := Request.new()
	request.npc_id = profile.npc_id
	request.session_id = session_id
	request.request_id = request_id
	request.context_revision = revision
	request.player_text = player_text
	request.persona = PackedStringArray(profile.persona.split("\n", false))
	if not profile.example_lines.is_empty():
		request.persona.append("Esempi del tuo modo di parlare, da non ripetere alla lettera:")
		for line in profile.example_lines:
			request.persona.append("- " + line)
	request.rules = PackedStringArray(profile.rules)
	var facts := PackedStringArray()
	facts.append_array(profile.public_facts)
	facts.append_array(profile.private_knowledge)
	facts.append_array(allowed_facts)
	request.facts = facts
	request.world_lore = PackedStringArray()
	if lore != null:
		request.world_lore = lore.select(profile.npc_id, profile.trade, player_text, _recent_user_texts(history))
	request.canonical_events = PackedStringArray()
	if memory != null:
		for event in select_events(memory.canonical_events, player_text, MAX_EVENTS_IN_CONTEXT):
			request.canonical_events.append(str(event["text"]))
		request.player_claims = PackedStringArray()
		var past: Array[String] = []
		for claim in memory.player_claims:
			if str(claim.get("session", "")) != session_id:   # i turni di questa sessione sono gia' nello storico
				past.append(str(claim["text"]))
		var from := maxi(0, past.size() - MAX_CLAIMS_IN_CONTEXT)
		for i in range(from, past.size()):
			request.player_claims.append(past[i])
	request.limits = Request.default_limits()
	request.limits["max_output_chars"] = profile.max_output_chars
	request.limits["max_output_tokens"] = profile.max_output_tokens
	var keep := request.limit("max_history_turns") * 2
	var start := maxi(0, history.size() - keep)
	request.history = []
	for i in range(start, history.size()):
		request.history.append({"role": str(history[i]["role"]), "text": str(history[i]["text"])})
	request.created_msec = Time.get_ticks_msec()
	return request


## Selezione deterministica: punteggio per parole in comune col testo del giocatore, poi giorno piu'
## recente, poi id alfabetico. Nessuna casualita', nessun modello.
static func select_events(events: Array, player_text: String, limit := MAX_EVENTS_IN_CONTEXT) -> Array[Dictionary]:
	var keywords := _keywords(player_text)
	var scored: Array[Dictionary] = []
	for event in events:
		if not (event is Dictionary) or str(event.get("source", "")) != "game":
			continue
		var text := str(event.get("text", "")).to_lower()
		var score := 0
		for word in keywords:
			if text.find(word) >= 0:
				score += 1
		scored.append({"id": str(event.get("id", "")), "text": str(event.get("text", "")), "day": int(event.get("day", 0)), "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		if a["day"] != b["day"]:
			return a["day"] > b["day"]
		return a["id"] < b["id"])
	var out: Array[Dictionary] = []
	for i in mini(limit, scored.size()):
		out.append(scored[i])
	return out


## Messaggi per /v1/chat/completions. `system_prefix` e' proprio del modello (es. "/no_think").
static func to_messages(request: RefCounted, system_prefix := "") -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	messages.append({"role": "system", "content": system_text(request, system_prefix)})
	if not request.player_claims.is_empty():
		var lines := PackedStringArray([CLAIMS_NOTE])
		for claim in request.player_claims:
			lines.append("- " + claim)
		messages.append({"role": "user", "content": "\n".join(lines)})
	for entry in request.history:
		messages.append({"role": str(entry["role"]), "content": str(entry["text"])})
	messages.append({"role": "user", "content": request.player_text})
	return messages


## Solo contenuti fidati: personaggio, regole, fatti consentiti, lore del mondo, eventi confermati. Ordine fisso.
static func system_text(request: RefCounted, system_prefix := "") -> String:
	var parts := PackedStringArray()
	if system_prefix != "":
		parts.append(system_prefix)
	parts.append("\n".join(request.persona))
	if not request.rules.is_empty():
		parts.append("Regole:")
		for rule in request.rules:
			parts.append("- " + rule)
	if not request.facts.is_empty():
		parts.append("Cose che sai:")
		for fact in request.facts:
			parts.append("- " + fact)
	if not request.world_lore.is_empty():
		parts.append("Il mondo in cui vivi:")
		for line in request.world_lore:
			parts.append("- " + line)
	if not request.canonical_events.is_empty():
		parts.append("Fatti accaduti davvero, confermati dal gioco:")
		for event in request.canonical_events:
			parts.append("- " + event)
	parts.append("Rispondi come " + _speaker_name(request) + ", in italiano, con al massimo tre frasi brevi.")
	return "\n".join(parts)


static func _speaker_name(request: RefCounted) -> String:
	# La prima riga della persona ha la forma "Sei <Nome>, ...": si estrae il nome per la chiusura.
	if request.persona.is_empty():
		return "il personaggio"
	var first: String = request.persona[0]
	if first.begins_with("Sei "):
		var rest := first.substr(4)
		var cut := rest.find(",")
		if cut > 0:
			return rest.substr(0, cut)
	return "il personaggio"


## Ultime battute del giocatore nello storico, dalla piu' recente: pesano (poco) nella scelta della lore,
## cosi' un tema resta nel contesto anche al turno dopo.
static func _recent_user_texts(history: Array[Dictionary], limit := MAX_RECENT_FOR_LORE) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(history.size() - 1, -1, -1):
		if str(history[i]["role"]) == "user":
			out.append(str(history[i]["text"]))
			if out.size() >= limit:
				break
	return out


static func _keywords(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cleaned := text.to_lower()
	for ch in [",", ".", "!", "?", ";", ":", "'", "\"", "(", ")"]:
		cleaned = cleaned.replace(ch, " ")
	for word in cleaned.split(" ", false):
		if word.length() >= MIN_KEYWORD_LENGTH and not out.has(word):
			out.append(word)
	return out

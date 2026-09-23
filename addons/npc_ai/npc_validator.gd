extends RefCounted
## Validazione della richiesta e sanificazione del testo, nei due sensi. In entrata: identita', struttura,
## lunghezze, disponibilita' del contesto e stato della sessione. In uscita: il testo generato diventa
## testo semplice (niente markup, codice, marcatori di ruolo o caratteri di controllo) e viene tagliato.
## Nessuna di queste regole e' una garanzia sul modello: sono invarianti del gioco, non un filtro magico.
const ID_PATTERN := "^[a-z0-9_]{1,32}$"
const MAX_RAW_CHARS := 4000
## Righe che iniziano cosi' (minuscolo, senza spazi iniziali) chiudono la risposta: sono tentativi di
## proseguire la conversazione al posto del gioco o del giocatore.
const ROLE_LINE_MARKERS: PackedStringArray = ["system:", "sistema:", "assistant:", "assistente:", "user:",
	"utente:", "giocatore:", "player:", "[inst]", "<<sys>>", "<|", "###"]
## Marcatori in mezzo alla riga: forme con iniziale maiuscola o fra parentesi, e solo se non precedute da una
## lettera, per non tagliare "il sistema: ..." o "ecosistema:".
const ROLE_INLINE_MARKERS: PackedStringArray = ["System:", "SYSTEM:", "Sistema:", "SISTEMA:", "Assistant:", "ASSISTANT:",
	"[SYSTEM]", "[SISTEMA]", "<<SYS>>", "[INST]", "<|"]
## Token speciali dei template di chat: in ingresso vengono neutralizzati, perche' il server tokenizza il
## prompt reso dal template con i token speciali attivi e un giocatore potrebbe aprire un turno di sistema.
const TEMPLATE_TOKENS: PackedStringArray = ["<<SYS>>", "<</SYS>>", "[INST]", "[/INST]", "<s>", "</s>",
	"<start_of_turn>", "<end_of_turn>", "<|", "|>"]
const MAX_MARKUP_PASSES := 5
const OUT_OF_ROLE_PHRASES: PackedStringArray = ["modello linguistico", "language model", "sono un'ia", "sono un ia",
	"sono un'intelligenza artificiale", "un'intelligenza artificiale", "assistente virtuale", "openai", "sono un assistente",
	"as an ai", "come ia,"]
const SENTENCE_ENDS: PackedStringArray = [". ", "! ", "? ", ".\n", "!\n", "?\n", "\u2026 ", "\u00bb "]

static var _re_think: RegEx
static var _re_special: RegEx
static var _re_html: RegEx
static var _re_bbcode: RegEx
static var _re_id: RegEx


## Pulisce il testo del giocatore senza interpretarlo: controlli via, spazi compattati, taglio duro.
static func sanitize_input(text: String, max_chars: int) -> Dictionary:
	var flags := PackedStringArray()
	var out := _strip_controls(text, false)
	var before := out
	out = _neutralize_template_tokens(out)
	if out != before:
		flags.append("neutralized_tokens")
	out = _collapse_spaces(out)
	if out.length() > max_chars:
		out = out.substr(0, max_chars).strip_edges()
		flags.append("truncated_input")
	return {"text": out, "flags": flags}


## `session` = {"open": bool, "npc_id": String, "revision": int, "seen_request_ids": Array}
static func validate_request(request: RefCounted, session: Dictionary) -> Dictionary:
	if request == null:
		return _reject("request_null", "richiesta assente")
	if not _id_ok(request.npc_id):
		return _reject("npc_id_invalid", "npc_id non conforme a " + ID_PATTERN)
	if str(session.get("npc_id", "")) != request.npc_id:
		return _reject("npc_id_mismatch", "la sessione appartiene a un altro NPC")
	if not bool(session.get("open", false)):
		return _reject("session_closed", "sessione chiusa")
	if request.session_id == "" or not request.session_id.begins_with(request.npc_id + ":"):
		return _reject("session_id_invalid", "session_id assente o non riconducibile all'NPC")
	if request.request_id == "" or not request.request_id.begins_with(request.session_id + "/"):
		return _reject("request_id_invalid", "request_id assente o non riconducibile alla sessione")
	var seen: Variant = session.get("seen_request_ids", [])
	if seen is Array and seen.has(request.request_id):
		return _reject("request_id_duplicate", "request_id gia' usato in questa sessione")
	if request.context_revision != int(session.get("revision", -1)):
		return _reject("revision_mismatch", "revisione del contesto cambiata")
	if request.persona.is_empty():
		return _reject("persona_missing", "contesto del personaggio assente")
	var max_input: int = request.limit("max_input_chars")
	if request.player_text.strip_edges() == "":
		return _reject("player_text_empty", "testo del giocatore vuoto")
	if request.player_text.length() > max_input:
		return _reject("player_text_too_long", "testo del giocatore oltre %d caratteri" % max_input)
	if request.player_text != sanitize_input(request.player_text, max_input)["text"]:
		return _reject("player_text_unsanitized", "testo del giocatore non sanificato")
	for key in request.HARD_CAPS.keys():
		var value: int = request.limit(key)
		if value <= 0 or value > int(request.HARD_CAPS[key]):
			return _reject("limits_exceeded:" + key, "limite %s fuori dai tetti consentiti" % key)
	if request.history.size() > request.limit("max_history_turns") * 2:
		return _reject("history_too_long", "storico oltre il limite")
	for entry in request.history:
		if not (entry is Dictionary) or not entry.has("role") or not entry.has("text"):
			return _reject("history_malformed", "voce dello storico senza role/text")
		if str(entry["role"]) != "user" and str(entry["role"]) != "assistant":
			return _reject("history_malformed", "ruolo dello storico non ammesso")
	return {"ok": true, "code": "", "message": ""}


## Testo semplice a partire da quanto generato. `partial` = durante lo streaming (nessun taglio finale).
static func sanitize_response(raw: String, max_chars: int, partial := false) -> Dictionary:
	var flags := PackedStringArray()
	var text := raw
	if text.length() > MAX_RAW_CHARS:
		text = text.substr(0, MAX_RAW_CHARS)
		flags.append("raw_overflow")
	# 1. blocchi di ragionamento, chiusi o aperti
	var before := text
	text = _think_regex().sub(text, "", true)
	var open_think := text.find("<think>")
	if open_think >= 0:
		text = text.substr(0, open_think)
	if text != before:
		flags.append("stripped_think")
	# 2. caratteri di controllo, invisibili e separatori di riga esotici PRIMA di ogni altra regola, cosi'
	#    un marcatore nascosto dietro uno zero-width o un \r non sfugge al passo successivo
	text = _strip_controls(text, true)
	# 3. token speciali, tag HTML/BBCode, recinti di codice, enfasi markdown; ripetuto finche' il testo
	#    cambia, perche' un tag annidato ne scopre un altro. Prima dei marcatori: "Sys<b></b>tem:" non deve sfuggire.
	before = text
	text = _strip_markup(text)
	if text != before:
		flags.append("stripped_markup")
	# 4. marcatori di ruolo: la risposta finisce dove il modello prova a parlare per altri
	before = text
	text = _cut_role_markers(text)
	if text != before:
		flags.append("cut_role_marker")
	# 5. spazi
	text = _collapse_spaces(text)
	if text == "":
		flags.append("empty")
		return {"text": "", "flags": flags}
	# 6. uscita dal ruolo: euristica minima, dichiarata come tale
	var lower := text.to_lower()
	for phrase in OUT_OF_ROLE_PHRASES:
		if lower.find(phrase) >= 0:
			flags.append("out_of_role")
			break
	# 7. ripetizioni degenerate
	before = text
	text = _cut_repetition(text)
	if text != before:
		flags.append("repetition_cut")
	# 8. taglio finale su confine di frase
	if not partial and text.length() > max_chars:
		text = _cut_at_sentence(text, max_chars)
		flags.append("truncated_chars")
	return {"text": text, "flags": flags}


static func is_plain_text(text: String) -> bool:
	if _html_regex().search(text) != null or _bbcode_regex().search(text) != null or _special_regex().search(text) != null:
		return false
	if text.find("```") >= 0 or text.find("<think>") >= 0:
		return false
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 32 and code != 10:
			return false
	return true


static func _reject(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


static func _id_ok(id: String) -> bool:
	if _re_id == null:
		_re_id = RegEx.new()
		_re_id.compile(ID_PATTERN)
	return _re_id.search(id) != null


static func _think_regex() -> RegEx:
	if _re_think == null:
		_re_think = RegEx.new()
		_re_think.compile("(?is)<think>.*?</think>\\s*")
	return _re_think


static func _special_regex() -> RegEx:
	if _re_special == null:
		_re_special = RegEx.new()
		_re_special.compile("<\\|[^|>]{0,64}\\|>")
	return _re_special


static func _html_regex() -> RegEx:
	if _re_html == null:
		_re_html = RegEx.new()
		_re_html.compile("</?[A-Za-z][^<>]{0,60}>")
	return _re_html


static func _bbcode_regex() -> RegEx:
	if _re_bbcode == null:
		_re_bbcode = RegEx.new()
		_re_bbcode.compile("\\[/?[A-Za-z_][^\\[\\]]{0,60}\\]")
	return _re_bbcode


static func _cut_role_markers(text: String) -> String:
	var lines := text.split("\n")
	var kept := PackedStringArray()
	for i in lines.size():
		var line: String = lines[i]
		var probe := line.strip_edges().to_lower()
		var stop := false
		for marker in ROLE_LINE_MARKERS:
			if probe.begins_with(marker):
				stop = true
				break
		if stop:
			# La prima riga puo' iniziare con "Assistant:"/"Assistente:" per abitudine del modello: si toglie il prefisso.
			if i == 0 and (probe.begins_with("assistant:") or probe.begins_with("assistente:")):
				kept.append(line.substr(line.find(":") + 1))
				continue
			break
		var cut := _inline_marker_cut(line)
		kept.append(line.substr(0, cut))
		if cut < line.length():
			break
	return "\n".join(kept)


## Prima riga della risposta esclusa, un marcatore in mezzo alla riga conta solo se non e' preceduto da una lettera.
static func _inline_marker_cut(line: String) -> int:
	var cut := line.length()
	for marker in ROLE_INLINE_MARKERS:
		var from := 0
		while from < line.length():
			var at := line.find(marker, from)
			if at < 0:
				break
			if at == 0 or not _is_letter(line.unicode_at(at - 1)):
				cut = mini(cut, at)
				break
			from = at + 1
	return cut


static func _is_letter(code: int) -> bool:
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code >= 0xC0


static func _strip_markup(text: String) -> String:
	var out := text
	for _pass in MAX_MARKUP_PASSES:
		var before := out
		out = _special_regex().sub(out, "", true)
		out = _html_regex().sub(out, "", true)
		out = _bbcode_regex().sub(out, "", true)
		out = out.replace("```", "").replace("`", "").replace("**", "").replace("__", "")
		if out == before:
			break
	return out


static func _neutralize_template_tokens(text: String) -> String:
	var out := _special_regex().sub(text, " ", true)
	for token in TEMPLATE_TOKENS:
		out = out.replace(token, " ")
	return out


## Controlli C0/C1, invisibili (zero-width, BOM, word joiner, soft hyphen) via; NBSP -> spazio; \r, NEL,
## LINE/PARAGRAPH SEPARATOR -> a capo (o spazio se gli a capo non sono ammessi).
static func _strip_controls(text: String, keep_newlines: bool) -> String:
	var out := ""
	var newline := "\n" if keep_newlines else " "
	for i in text.length():
		var code := text.unicode_at(i)
		if code == 10 or code == 13 or code == 0x85 or code == 0x2028 or code == 0x2029:
			out += newline
		elif code == 9 or code == 0xA0:
			out += " "
		elif code < 32 or (code >= 127 and code < 160) or code == 0xAD or (code >= 0x200B and code <= 0x200F) \
				or code == 0x2060 or code == 0xFEFF or code == 0x180E:
			continue
		else:
			out += text[i]
	return out


static func _collapse_spaces(text: String) -> String:
	var lines := text.split("\n")
	var out := PackedStringArray()
	var blank_run := 0
	for line in lines:
		var parts := line.split(" ", false)
		var compact := " ".join(parts)
		if compact == "":
			blank_run += 1
			if blank_run > 1:
				continue
		else:
			blank_run = 0
		out.append(compact)
	return "\n".join(out).strip_edges()


static func _cut_repetition(text: String) -> String:
	## Ripetizione degenerata = lo stesso blocco (6..80 caratteri) ripetuto tre volte di seguito.
	## Frasi simili ma non identiche non vengono toccate.
	var n := text.length()
	if n < 48:
		return text
	for period in range(6, 81):
		var i := 0
		var last := n - 3 * period
		while i <= last:
			var c := text.unicode_at(i)
			if c == text.unicode_at(i + period) and c == text.unicode_at(i + 2 * period):
				var block := text.substr(i, period)
				if block == text.substr(i + period, period) and block == text.substr(i + 2 * period, period):
					return text.substr(0, i + period).strip_edges()
			i += 1
	return text


static func _cut_at_sentence(text: String, max_chars: int) -> String:
	var head := text.substr(0, max_chars)
	var best := -1
	for ending in SENTENCE_ENDS:
		best = maxi(best, head.rfind(ending))
	var last_char := head.substr(head.length() - 1, 1)
	if best < 0 and (last_char == "." or last_char == "!" or last_char == "?"):
		return head
	if best >= max_chars / 3:
		return head.substr(0, best + 1).strip_edges()
	var space := head.rfind(" ")
	if space > max_chars / 2:
		head = head.substr(0, space)
	return head.strip_edges() + "\u2026"

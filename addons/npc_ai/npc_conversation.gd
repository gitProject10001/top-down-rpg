extends RefCounted
## Una sessione di dialogo fra il giocatore e un NPC. Tiene lo stato (CHIUSA, LIBERA, IN ATTESA, RISPOSTA,
## RIPIEGO), lo storico breve, la revisione del contesto e l'unico ingresso in canon (confirm_event, che
## chiama solo il gioco). Ogni risposta viene ricontrollata alla consegna: sessione, revisione e id della
## richiesta devono coincidere, altrimenti il testo non viene mostrato.
signal state_changed(state: int)
signal line_added(kind: String, speaker: String, text: String)   ## player | npc_generated | npc_fallback | npc_greeting | npc_farewell | npc_interrupted | note
signal streaming_text(text_so_far: String)
signal response_received(response: RefCounted)                   ## metadati per interfaccia e prove

enum State { CLOSED, IDLE, WAITING, RESPONDED, FALLBACK }
const Response := preload("res://addons/npc_ai/npc_chat_response.gd")
const Validator := preload("res://addons/npc_ai/npc_validator.gd")
const ContextBuilder := preload("res://addons/npc_ai/npc_context_builder.gd")
const MAX_TRANSCRIPT := 24
const PLAYER_NAME := "Tu"

var profile: Resource
var memory: RefCounted
var service: Node
var allowed_facts: PackedStringArray = PackedStringArray()
var lore: RefCounted                    ## lore condivisa (npc_world_lore.gd), facoltativa
var session_id := ""
var context_revision := 0
var state: int = State.CLOSED
var transcript: Array[Dictionary] = []   ## {kind, speaker, text}
var history: Array[Dictionary] = []      ## per il modello: {role, text}
var turn := 0
var open_count := 0
var last_response: RefCounted
var last_reject := ""

var _pending_request_id := ""
var _pending_player_text := ""
var _crypto := Crypto.new()
var _connected_service: Node


func setup(npc_profile: Resource, npc_memory: RefCounted, inference_service: Node, facts: PackedStringArray,
		world_lore: RefCounted = null) -> void:
	profile = npc_profile
	memory = npc_memory
	service = inference_service
	allowed_facts = facts
	lore = world_lore
	_disconnect_service()
	if service != null:
		service.response_ready.connect(_on_response_ready)
		service.response_delta.connect(_on_response_delta)
		service.response_discarded.connect(_on_response_discarded)
		_connected_service = service


func is_open() -> bool:
	return state != State.CLOSED


func speaker_name() -> String:
	return profile.display_name if profile != null else "?"


## Apre una sessione nuova: id fresco, storico vuoto, saluto scritto a mano. La revisione resta monotona.
func open() -> String:
	if is_open():
		close()
	open_count += 1
	if context_revision == 0:
		context_revision = 1
	session_id = "%s:%d:%s" % [profile.npc_id, open_count, _crypto.generate_random_bytes(4).hex_encode()]
	turn = 0
	history.clear()
	transcript.clear()
	_pending_request_id = ""
	if service != null:
		service.open_session(session_id, profile.npc_id, context_revision)
	if memory != null:
		memory.note_session(Time.get_datetime_string_from_system(true, true))
	_set_state(State.IDLE)
	_add_line("npc_greeting", speaker_name(), profile.greeting_for(open_count - 1))
	return session_id


## Invia una battuta del giocatore. Se il servizio non puo' accettarla, il ripiego e' immediato.
func send(raw_text: String) -> bool:
	if state == State.CLOSED or state == State.WAITING:
		return false
	var cleaned: Dictionary = Validator.sanitize_input(raw_text, 240)
	var text: String = cleaned["text"]
	if text == "":
		return false
	turn += 1
	_pending_player_text = text
	_add_line("player", PLAYER_NAME, text)
	var request: RefCounted = ContextBuilder.build_request(profile, allowed_facts, memory, session_id,
		"%s/%d" % [session_id, turn], context_revision, text, history, lore)
	if memory != null:
		memory.add_player_claim(text, session_id, turn)   # dopo la richiesta: la battuta attuale non e' una «chiacchiera passata»
	history.append({"role": "user", "text": text})
	_trim_history(request.limit("max_history_turns") * 2)
	if service == null:
		_apply_fallback("no_service", "")
		return true
	var messages: Array[Dictionary] = ContextBuilder.to_messages(request)
	var params := {"max_tokens": request.limit("max_output_tokens"), "temperature": 0.7}
	var err: int = service.submit(request, messages, params)
	if err != OK:
		last_reject = service.last_reject_code
		_apply_fallback(last_reject, "")
		return true
	_pending_request_id = request.request_id
	_set_state(State.WAITING)
	return true


func cancel() -> void:
	if state != State.WAITING or service == null:
		return
	service.cancel(_pending_request_id)


func close() -> void:
	if state == State.CLOSED:
		return
	_pending_request_id = ""   # prima della chiusura: lo scarto che segue non riguarda piu' nessuna attesa
	if service != null:
		service.close_session(session_id)
	_add_line("npc_farewell", speaker_name(), profile.farewell_for(open_count - 1))
	if memory != null:
		memory.save()
	_set_state(State.CLOSED)


## Azzera la memoria dell'NPC: la revisione cambia e ogni risposta in volo diventa obsoleta.
func reset_memory() -> void:
	if memory != null:
		memory.reset()
	_bump_revision()
	_add_line("note", "", "Memoria di %s azzerata." % speaker_name())


## UNICO ingresso in canon: lo chiama il gioco quando un evento e' davvero accaduto. Mai il modello.
func confirm_event(event_id: String, text: String, day: int) -> bool:
	if memory == null or not memory.add_canonical_event(event_id, text, day):
		return false
	memory.save()
	_bump_revision()
	_add_line("note", "", "Evento confermato: " + text)
	return true


## Se il nodo che possiede l'NPC lascia l'albero (rimozione, cambio scena), il dialogo si chiude.
func bind_owner(node: Node) -> void:
	if node != null and not node.tree_exiting.is_connected(close):
		node.tree_exiting.connect(close)


func _bump_revision() -> void:
	context_revision += 1
	if state == State.WAITING:
		_pending_request_id = ""   # obsoleta per scelta del gioco: nessun ripiego, si torna liberi in silenzio
		_set_state(State.IDLE)
	if is_open() and service != null:
		service.bump_revision(session_id, context_revision)


func _disconnect_service() -> void:
	if _connected_service != null and is_instance_valid(_connected_service):
		_connected_service.response_ready.disconnect(_on_response_ready)
		_connected_service.response_delta.disconnect(_on_response_delta)
		_connected_service.response_discarded.disconnect(_on_response_discarded)
	_connected_service = null


func _on_response_delta(request_id: String, text_so_far: String) -> void:
	if state == State.WAITING and request_id == _pending_request_id:
		streaming_text.emit(text_so_far)


## Il servizio ha scartato la richiesta in attesa (backend cambiato o fermato, servizio in uscita): il
## dialogo non deve restare «in attesa» per sempre. Chiusura e cambio revisione azzerano l'attesa prima.
func _on_response_discarded(request_id: String, reason: String) -> void:
	if state == State.WAITING and request_id == _pending_request_id:
		_apply_fallback("discarded:" + reason, profile.interrupted_for(_pending_player_text), "npc_interrupted")


func _on_response_ready(response: RefCounted) -> void:
	if state != State.WAITING:
		return
	if response.session_id != session_id or response.request_id != _pending_request_id or response.context_revision != context_revision:
		return
	last_response = response
	_pending_request_id = ""
	response_received.emit(response)
	if response.is_ok():
		_add_line("npc_generated", speaker_name(), response.text)
		history.append({"role": "assistant", "text": response.text})
		if memory != null:
			memory.add_exchange(session_id, turn, _pending_player_text, response.text, "generated")
			memory.save()
		_set_state(State.RESPONDED)
		return
	if response.status == Response.Status.CANCELLED:
		_apply_fallback("cancelled", profile.interrupted_for(_pending_player_text), "npc_interrupted")
		return
	_apply_fallback(response.error_code if response.error_code != "" else Response.status_name(response.status), "")


func _apply_fallback(reason: String, line := "", kind := "npc_fallback") -> void:
	var text: String = line if line != "" else profile.fallback_for(_pending_player_text)
	last_reject = reason
	_pending_request_id = ""
	_add_line(kind, speaker_name(), text)
	history.append({"role": "assistant", "text": text})
	if memory != null:
		memory.add_exchange(session_id, turn, _pending_player_text, text, "fallback")
		memory.save()
	_set_state(State.FALLBACK)


func _add_line(kind: String, speaker: String, text: String) -> void:
	transcript.append({"kind": kind, "speaker": speaker, "text": text})
	while transcript.size() > MAX_TRANSCRIPT:
		transcript.pop_front()
	line_added.emit(kind, speaker, text)


func _trim_history(keep: int) -> void:
	while history.size() > keep:
		history.pop_front()


func _set_state(next: int) -> void:
	if next == state:
		return
	state = next
	state_changed.emit(state)


static func state_name(value: int) -> String:
	match value:
		State.CLOSED: return "CLOSED"
		State.IDLE: return "IDLE"
		State.WAITING: return "WAITING"
		State.RESPONDED: return "RESPONDED"
		State.FALLBACK: return "FALLBACK"
	return "UNKNOWN"

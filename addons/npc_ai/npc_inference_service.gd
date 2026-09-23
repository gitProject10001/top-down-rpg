extends Node
## Servizio unico e condiviso di inferenza. Non e' un autoload: chi lo usa lo aggiunge alla propria scena.
## Un solo backend, coda FIFO limitata, una generazione alla volta, un solo pendente per sessione, timeout
## a due stadi (primo token, totale), annullamento e scarto delle risposte obsolete. Il backend viene
## interrogato con poll() ogni frame sul thread principale: nessun caricamento o inferenza blocca il gioco,
## perche' il lavoro pesante vive nel backend (processo separato) e qui si leggono solo pochi byte a frame.
##
## CANCELLED/TIMEOUT = il richiedente ha interrotto una richiesta a sessione viva: la risposta viene
## consegnata con quello stato. OBSOLETA = sessione chiusa o revisione cambiata alla consegna: la risposta
## non raggiunge mai il chiamante, parte solo response_discarded(request_id, motivo).
signal state_changed(state: int)
signal response_delta(request_id: String, text_so_far: String)      ## testo parziale gia' sanificato
signal response_ready(response: RefCounted)                          ## solo per sessioni vive e revisione uguale
signal response_discarded(request_id: String, reason: String)       ## session_closed | revision_changed | unknown_session | unknown_request | backend_changed | backend_failed | service_exiting

enum ServiceState { NO_BACKEND, STARTING, READY, BUSY, FAILED, STOPPED }
const Request := preload("res://addons/npc_ai/npc_chat_request.gd")
const Response := preload("res://addons/npc_ai/npc_chat_response.gd")
const Validator := preload("res://addons/npc_ai/npc_validator.gd")
const Backend := preload("res://addons/npc_ai/npc_backend.gd")
const MAX_QUEUE := 4
const MAX_CLOSED_SESSIONS := 32

var last_reject_code := ""
var dropped_foreign_signals := 0
var stats := {"submitted": 0, "delivered": 0, "discarded": 0, "timeouts": 0, "cancelled": 0, "rejected": 0}

var _backend: RefCounted
var _sessions: Dictionary = {}      ## session_id -> {npc_id, revision, open, seen_request_ids, pending}
var _closed_order: Array[String] = []
var _queue: Array[Dictionary] = []  ## {request, messages, params, queued_msec}
var _active: Dictionary = {}        ## + dispatched_msec, first_delta_msec, raw, override_status, override_code, discard_reason
var _ignored_request_ids: Dictionary = {}   ## risposte tardive da ignorare (gia' consegnate come TIMEOUT/CANCELLED)
var _state: int = ServiceState.NO_BACKEND


func set_backend(backend: RefCounted) -> void:
	if _backend != null:
		_discard_everything("backend_changed")
		_backend.delta.disconnect(_on_backend_delta)
		_backend.finished.disconnect(_on_backend_finished)
		_backend.availability_changed.disconnect(_on_backend_availability)
		_backend.stop()
	_backend = backend
	if _backend != null:
		_backend.delta.connect(_on_backend_delta)
		_backend.finished.connect(_on_backend_finished)
		_backend.availability_changed.connect(_on_backend_availability)
	_refresh_state()


func backend() -> RefCounted:
	return _backend


func start() -> void:
	if _backend != null:
		_backend.start()
	_refresh_state()


func stop() -> void:
	_discard_everything("service_exiting")
	if _backend != null:
		_backend.stop()
	_refresh_state()


func state() -> int:
	return _state


func is_ready() -> bool:
	return _backend != null and _backend.is_ready()


func describe() -> Dictionary:
	var d := {"state": state_name(_state), "queue": _queue.size(), "active": active_request_id(), "dropped_foreign": dropped_foreign_signals}
	if _backend != null:
		d.merge(_backend.describe())
	return d


func open_session(session_id: String, npc_id: String, revision: int) -> void:
	_sessions[session_id] = {"npc_id": npc_id, "revision": revision, "open": true, "seen_request_ids": [], "pending": ""}


## Chiude la sessione: annulla la sua richiesta attiva, svuota la coda e marca tutto cio' che arrivera'
## dopo come obsoleto (scartato con "session_closed").
func close_session(session_id: String) -> void:
	if not _sessions.has(session_id):
		return
	_sessions[session_id]["open"] = false
	_drop_queued(func(entry: Dictionary) -> bool: return entry["request"].session_id == session_id, "session_closed")
	if not _active.is_empty() and _active["request"].session_id == session_id:
		_active["discard_reason"] = "session_closed"
		_abort_active(Response.Status.CANCELLED, "session_closed")
	_closed_order.append(session_id)
	while _closed_order.size() > MAX_CLOSED_SESSIONS:
		var old: String = _closed_order.pop_front()
		if _sessions.has(old) and not _sessions[old]["open"]:
			_sessions.erase(old)


## Nuova revisione del contesto (memoria cambiata): tutto cio' che porta la revisione vecchia e' obsoleto.
func bump_revision(session_id: String, revision: int) -> void:
	if not _sessions.has(session_id):
		return
	_sessions[session_id]["revision"] = revision
	_drop_queued(func(entry: Dictionary) -> bool:
		return entry["request"].session_id == session_id and entry["request"].context_revision != revision, "revision_changed")
	if not _active.is_empty() and _active["request"].session_id == session_id and _active["request"].context_revision != revision:
		_active["discard_reason"] = "revision_changed"
		_abort_active(Response.Status.CANCELLED, "revision_changed")


func session_state(session_id: String) -> Dictionary:
	if not _sessions.has(session_id):
		return {"open": false, "npc_id": "", "revision": -1, "seen_request_ids": []}
	var s: Dictionary = _sessions[session_id]
	return {"open": s["open"], "npc_id": s["npc_id"], "revision": s["revision"], "seen_request_ids": s["seen_request_ids"]}


## OK | ERR_UNAVAILABLE (backend non pronto: ripiega subito) | ERR_BUSY (coda piena o sessione gia' in attesa)
## | ERR_UNCONFIGURED (sessione sconosciuta o chiusa) | ERR_INVALID_PARAMETER (validatore, vedi last_reject_code)
func submit(request: RefCounted, messages: Array, params: Dictionary = {}) -> int:
	stats["submitted"] += 1
	last_reject_code = ""
	if _backend == null or not _backend.is_ready():
		last_reject_code = "backend_unavailable"
		stats["rejected"] += 1
		return ERR_UNAVAILABLE
	if not _sessions.has(request.session_id) or not _sessions[request.session_id]["open"]:
		last_reject_code = "session_closed"
		stats["rejected"] += 1
		return ERR_UNCONFIGURED
	var verdict: Dictionary = Validator.validate_request(request, session_state(request.session_id))
	if not verdict["ok"]:
		last_reject_code = "validator:" + str(verdict["code"])
		stats["rejected"] += 1
		return ERR_INVALID_PARAMETER
	var session: Dictionary = _sessions[request.session_id]
	if session["pending"] != "":
		last_reject_code = "session_busy"
		stats["rejected"] += 1
		return ERR_BUSY
	if _queue.size() >= MAX_QUEUE:
		last_reject_code = "queue_full"
		stats["rejected"] += 1
		return ERR_BUSY
	session["seen_request_ids"].append(request.request_id)
	session["pending"] = request.request_id
	_queue.append({"request": request, "messages": messages, "params": params, "queued_msec": Time.get_ticks_msec()})
	_dispatch_next()
	return OK


func cancel(request_id: String) -> void:
	for i in _queue.size():
		if _queue[i]["request"].request_id == request_id:
			var entry: Dictionary = _queue[i]
			_queue.remove_at(i)
			stats["cancelled"] += 1
			var response := _make_response(entry["request"], Response.Status.CANCELLED, "", "cancelled_queued", "annullata prima dell'avvio", entry["queued_msec"], -1)
			_deliver(response)
			return
	if not _active.is_empty() and _active["request"].request_id == request_id:
		stats["cancelled"] += 1
		_abort_active(Response.Status.CANCELLED, "cancelled")


func cancel_session(session_id: String) -> void:
	var ids := PackedStringArray()
	for entry in _queue:
		if entry["request"].session_id == session_id:
			ids.append(entry["request"].request_id)
	if not _active.is_empty() and _active["request"].session_id == session_id:
		ids.append(_active["request"].request_id)
	for id in ids:
		cancel(id)


func queue_size() -> int:
	return _queue.size()


func active_request_id() -> String:
	return "" if _active.is_empty() else str(_active["request"].request_id)


func _process(delta: float) -> void:
	if _backend == null:
		return
	_backend.poll(delta)
	_check_timeouts()
	_dispatch_next()
	_refresh_state()


func _exit_tree() -> void:
	_discard_everything("service_exiting")
	if _backend != null:
		_backend.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH or what == NOTIFICATION_PREDELETE:
		if _backend != null:
			stop()   # prima scarta cio' che e' in volo o in coda, poi ferma il backend


func _dispatch_next() -> void:
	if _backend == null or not _backend.is_ready() or _backend.is_busy() or not _active.is_empty() or _queue.is_empty():
		return
	var entry: Dictionary = _queue.pop_front()
	var request: RefCounted = entry["request"]
	var session: Dictionary = _sessions.get(request.session_id, {})
	if session.is_empty() or not session["open"]:
		_discard(request, "session_closed")
		_dispatch_next()
		return
	if int(session["revision"]) != request.context_revision:
		_discard(request, "revision_changed")
		_dispatch_next()
		return
	entry["dispatched_msec"] = Time.get_ticks_msec()
	entry["first_delta_msec"] = -1
	entry["raw"] = ""
	_active = entry
	if not _backend.begin(request, entry["messages"], entry["params"]):
		var response := _make_response(request, Response.Status.ERROR, "", "backend_refused", "il backend ha rifiutato la richiesta", entry["queued_msec"], entry["dispatched_msec"])
		_active = {}
		_deliver(response)
		_dispatch_next()
	_refresh_state()


func _check_timeouts() -> void:
	if _active.is_empty():
		return
	var request: RefCounted = _active["request"]
	var elapsed: int = Time.get_ticks_msec() - int(_active["dispatched_msec"])
	if int(_active["first_delta_msec"]) < 0 and elapsed > request.limit("first_token_timeout_msec"):
		stats["timeouts"] += 1
		_abort_active(Response.Status.TIMEOUT, "timeout_first_token")
	elif elapsed > request.limit("total_timeout_msec"):
		stats["timeouts"] += 1
		_abort_active(Response.Status.TIMEOUT, "timeout_total")


## Interrompe la richiesta attiva. Se il backend risponde subito con finished(), la consegna passa da li'
## con lo stato imposto; altrimenti si consegna qui e ogni finished tardiva per quell'id viene ignorata.
func _abort_active(status: int, code: String) -> void:
	if _active.is_empty():
		return
	var request: RefCounted = _active["request"]
	_active["override_status"] = status
	_active["override_code"] = code
	_backend.cancel(request.request_id)
	if _active.is_empty() or _active["request"].request_id != request.request_id:
		return   # il backend ha gia' emesso finished() dentro cancel()
	var entry: Dictionary = _active
	_active = {}
	_ignored_request_ids[request.request_id] = true
	if entry.has("discard_reason"):
		_discard(request, entry["discard_reason"])
		return
	var response := _make_response(request, status, entry["raw"], code, "interrotta: " + code, entry["queued_msec"], entry["dispatched_msec"])
	response.timings["first_token_msec"] = int(entry["first_delta_msec"]) - int(entry["dispatched_msec"]) if int(entry["first_delta_msec"]) >= 0 else -1
	_deliver(response)


func _on_backend_delta(request_id: String, text: String) -> void:
	if _active.is_empty() or _active["request"].request_id != request_id:
		if not _ignored_request_ids.has(request_id):
			dropped_foreign_signals += 1
		return
	if int(_active["first_delta_msec"]) < 0:
		_active["first_delta_msec"] = Time.get_ticks_msec()
	_active["raw"] = str(_active["raw"]) + text
	var request: RefCounted = _active["request"]
	var max_chars: int = request.limit("max_output_chars")
	var partial: Dictionary = Validator.sanitize_response(_active["raw"], max_chars, true)
	# L'anteprima non mostra mai testo che alla fine verrebbe rifiutato, ne' oltre il limite a schermo.
	var preview: String = "" if partial["flags"].has("out_of_role") else str(partial["text"]).substr(0, max_chars)
	response_delta.emit(request_id, preview)


func _on_backend_finished(request_id: String, result: Dictionary) -> void:
	if _active.is_empty() or _active["request"].request_id != request_id:
		if _ignored_request_ids.has(request_id):
			_ignored_request_ids.erase(request_id)
		else:
			dropped_foreign_signals += 1
		response_discarded.emit(request_id, "unknown_request")
		return
	var entry: Dictionary = _active
	_active = {}
	var request: RefCounted = entry["request"]
	var status: int = int(result.get("status", Response.Status.ERROR))
	var code := str(result.get("error_code", ""))
	var message := str(result.get("error_message", ""))
	if entry.has("override_status"):
		status = int(entry["override_status"])
		code = str(entry["override_code"])
		message = "interrotta: " + code
	var raw := str(result.get("text", ""))
	if raw == "":
		raw = str(entry["raw"])
	if entry.has("discard_reason"):
		_discard(request, entry["discard_reason"])
		_dispatch_next()
		return
	var response := _make_response(request, status, raw, code, message, entry["queued_msec"], entry["dispatched_msec"])
	var timings: Dictionary = result.get("timings", {})
	response.timings["tokens"] = int(timings.get("tokens", 0))
	if int(entry["first_delta_msec"]) >= 0:
		response.timings["first_token_msec"] = int(entry["first_delta_msec"]) - int(entry["dispatched_msec"])
	elif int(timings.get("first_token_msec", -1)) >= 0:
		response.timings["first_token_msec"] = int(timings["first_token_msec"])
	response.model = str(result.get("model", ""))
	if status == Response.Status.OK:
		var clean: Dictionary = Validator.sanitize_response(raw, request.limit("max_output_chars"), false)
		response.flags = clean["flags"]
		response.text = clean["text"]
		if response.text == "":
			response.status = Response.Status.ERROR
			response.error_code = "validator:empty"
			response.error_message = "il modello non ha prodotto testo utilizzabile"
		elif clean["flags"].has("out_of_role"):
			response.status = Response.Status.ERROR
			response.error_code = "validator:out_of_role"
			response.error_message = "risposta fuori dal personaggio"
			response.text = ""
	_deliver(response)
	_dispatch_next()


func _make_response(request: RefCounted, status: int, raw: String, code: String, message: String, queued_msec: int, dispatched_msec: int) -> RefCounted:
	var response := Response.new()
	response.bind_request(request)
	response.status = status
	response.raw_text = raw
	response.error_code = code
	response.error_message = message
	response.backend = _backend.backend_name() if _backend != null else "none"
	response.model = _backend.model_name() if _backend != null else ""
	var now := Time.get_ticks_msec()
	response.timings["queued_msec"] = (dispatched_msec if dispatched_msec >= 0 else now) - queued_msec
	response.timings["total_msec"] = now - dispatched_msec if dispatched_msec >= 0 else 0
	return response


func _deliver(response: RefCounted) -> void:
	var session: Dictionary = _sessions.get(response.session_id, {})
	if not session.is_empty() and session["pending"] == response.request_id:
		session["pending"] = ""
	if session.is_empty():
		_emit_discard(response.request_id, "unknown_session")
		return
	if not session["open"]:
		_emit_discard(response.request_id, "session_closed")
		return
	if int(session["revision"]) != response.context_revision:
		_emit_discard(response.request_id, "revision_changed")
		return
	stats["delivered"] += 1
	response_ready.emit(response)


func _discard(request: RefCounted, reason: String) -> void:
	var session: Dictionary = _sessions.get(request.session_id, {})
	if not session.is_empty() and session["pending"] == request.request_id:
		session["pending"] = ""
	_emit_discard(request.request_id, reason)


func _emit_discard(request_id: String, reason: String) -> void:
	stats["discarded"] += 1
	response_discarded.emit(request_id, reason)


func _drop_queued(predicate: Callable, reason: String) -> void:
	var kept: Array[Dictionary] = []
	for entry in _queue:
		if predicate.call(entry):
			_discard(entry["request"], reason)
		else:
			kept.append(entry)
	_queue = kept


func _discard_everything(reason: String) -> void:
	_drop_queued(func(_entry: Dictionary) -> bool: return true, reason)
	if not _active.is_empty():
		_active["discard_reason"] = reason
		_abort_active(Response.Status.CANCELLED, reason)


func _on_backend_availability(state: int, _reason: String) -> void:
	if state == Backend.Availability.FAILED or state == Backend.Availability.STOPPED:
		# Nulla in coda puo' piu' essere servito: chi aspetta ripiega subito invece di scoprirlo al timeout.
		_drop_queued(func(_entry: Dictionary) -> bool: return true, "backend_failed")
	_refresh_state()


func _refresh_state() -> void:
	var next: int = ServiceState.NO_BACKEND
	if _backend != null:
		match _backend.availability():
			Backend.Availability.STARTING: next = ServiceState.STARTING
			Backend.Availability.READY: next = ServiceState.BUSY if not _active.is_empty() else ServiceState.READY
			Backend.Availability.FAILED: next = ServiceState.FAILED
			Backend.Availability.STOPPED: next = ServiceState.STOPPED
			_: next = ServiceState.NO_BACKEND
	if next != _state:
		_state = next
		state_changed.emit(_state)


static func state_name(value: int) -> String:
	match value:
		ServiceState.NO_BACKEND: return "NO_BACKEND"
		ServiceState.STARTING: return "STARTING"
		ServiceState.READY: return "READY"
		ServiceState.BUSY: return "BUSY"
		ServiceState.FAILED: return "FAILED"
		ServiceState.STOPPED: return "STOPPED"
	return "UNKNOWN"

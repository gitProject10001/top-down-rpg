extends RefCounted
## Contratto di un backend di inferenza. Il servizio lo interroga con poll() una volta per frame sul thread
## principale; tutti i segnali partono da li'. Un backend riceve una richiesta gia' validata e un elenco di
## messaggi gia' composti, e restituisce solo testo: non ha alcun accesso allo stato del gioco.
signal delta(request_id: String, text: String)             ## frammento di testo grezzo, in ordine
signal finished(request_id: String, result: Dictionary)    ## vedi result(): status, text, error_code, error_message, timings, model
signal availability_changed(state: int, reason: String)

enum Availability { UNAVAILABLE, STARTING, READY, FAILED, STOPPED }
const Response := preload("res://addons/npc_ai/npc_chat_response.gd")

var _availability: int = Availability.UNAVAILABLE
var _failure_reason := ""


func backend_name() -> String:
	return "none"


func model_name() -> String:
	return ""


## Non bloccante: puo' passare da STARTING a READY/FAILED in poll() successivi.
func start() -> void:
	pass


## Idempotente: libera risorse e termina eventuali processi propri.
func stop() -> void:
	_set_availability(Availability.STOPPED, "")


func poll(_delta_time: float) -> void:
	pass


func availability() -> int:
	return _availability


func is_ready() -> bool:
	return _availability == Availability.READY


func failure_reason() -> String:
	return _failure_reason


func is_busy() -> bool:
	return false


## Avvia una generazione. `messages` = [{"role": "system"|"user"|"assistant", "content": String}].
## Restituisce false se il backend non e' pronto o e' gia' occupato: il servizio serializza le richieste.
func begin(_request: RefCounted, _messages: Array, _params: Dictionary) -> bool:
	return false


## Idempotente; dopo cancel() il backend puo' ancora emettere finished() per quella richiesta.
func cancel(_request_id: String) -> void:
	pass


func describe() -> Dictionary:
	return {"backend": backend_name(), "model": model_name(), "availability": availability_name(_availability),
		"reason": _failure_reason}


func _set_availability(state: int, reason := "") -> void:
	var changed := state != _availability or reason != _failure_reason
	_availability = state
	_failure_reason = reason
	if changed:
		availability_changed.emit(state, reason)


static func result(status: int, text := "", error_code := "", error_message := "", timings := {}, model := "") -> Dictionary:
	var t := {"queued_msec": 0, "first_token_msec": -1, "total_msec": 0, "tokens": 0}
	for key in timings.keys():
		t[key] = timings[key]
	return {"status": status, "text": text, "error_code": error_code, "error_message": error_message,
		"timings": t, "model": model}


static func availability_name(state: int) -> String:
	match state:
		Availability.UNAVAILABLE: return "UNAVAILABLE"
		Availability.STARTING: return "STARTING"
		Availability.READY: return "READY"
		Availability.FAILED: return "FAILED"
		Availability.STOPPED: return "STOPPED"
	return "UNKNOWN"

extends RefCounted
## La risposta del servizio a una richiesta: stessi identificatori, stato, testo gia' sanificato e metadati di
## errore e tempo. `text` e' l'unica cosa che l'interfaccia mostra; `raw_text` serve solo a log e prove.
enum Status { OK, FALLBACK, CANCELLED, TIMEOUT, REJECTED, ERROR, STALE }
const DICT_KEYS: PackedStringArray = ["npc_id", "session_id", "request_id", "context_revision", "status",
	"status_name", "text", "raw_text", "error_code", "error_message", "backend", "model", "timings", "flags"]

var npc_id := ""
var session_id := ""
var request_id := ""
var context_revision := 0
var status: int = Status.ERROR
var text := ""             ## sanificato, pronto per lo schermo (vuoto se non OK)
var raw_text := ""         ## come generato, anche parziale; mai mostrato
var error_code := ""       ## backend_unavailable | queue_full | session_closed | revision_changed | http_<n> |
                           ## connection_lost | sse_parse | process_exited | validator:<regola> | timeout_first_token | ...
var error_message := ""
var backend := ""          ## "mock" | "llama_server" | "none"
var model := ""
var timings := {"queued_msec": 0, "first_token_msec": -1, "total_msec": 0, "tokens": 0}
var flags: PackedStringArray = PackedStringArray()   ## note del sanificatore: stripped_think, cut_role_marker, ...


static func status_name(value: int) -> String:
	match value:
		Status.OK: return "OK"
		Status.FALLBACK: return "FALLBACK"
		Status.CANCELLED: return "CANCELLED"
		Status.TIMEOUT: return "TIMEOUT"
		Status.REJECTED: return "REJECTED"
		Status.ERROR: return "ERROR"
		Status.STALE: return "STALE"
	return "UNKNOWN"


## Copia gli identificatori dalla richiesta, cosi' la risposta e' sempre riconducibile.
func bind_request(request: RefCounted) -> void:
	npc_id = request.npc_id
	session_id = request.session_id
	request_id = request.request_id
	context_revision = request.context_revision


func is_ok() -> bool:
	return status == Status.OK and text != ""


func to_dict() -> Dictionary:
	return {
		"npc_id": npc_id,
		"session_id": session_id,
		"request_id": request_id,
		"context_revision": context_revision,
		"status": status,
		"status_name": status_name(status),
		"text": text,
		"raw_text": raw_text,
		"error_code": error_code,
		"error_message": error_message,
		"backend": backend,
		"model": model,
		"timings": timings.duplicate(),
		"flags": Array(flags),
	}

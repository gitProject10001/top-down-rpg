extends "res://addons/npc_ai/npc_backend.gd"
## Backend REALE: llama-server di llama.cpp come processo incluso nel pacchetto, controllato via HTTP su
## loopback. Tutto e' non bloccante e guidato da poll() sul thread principale:
## - avvio senza finestra console (CREATE_NO_WINDOW), solo 127.0.0.1, porta casuale mai riusata,
##   chiave casuale passata per AMBIENTE (mai in argv), verifica dell'istanza via /props.model_path;
## - streaming SSE con una HTTPClient per richiesta; annullare = chiudere la connessione (il server
##   interrompe davvero la generazione);
## - arresto = kill del SOLO processo avviato qui, file di stato per istanza (pid Godot + porta) per riconoscere e chiudere un
##   orfano di una partita precedente (si uccide solo chi risponde alla nostra chiave col nostro modello);
## - modello o runtime assenti, processo che muore, memoria insufficiente, crash: si passa a FAILED e il
##   dialogo prosegue con le battute di ripiego. Nessuna rete esterna, nessun download, nessuna telemetria.
const Paths := preload("res://addons/npc_ai/npc_ai_paths.gd")
const Manifest := preload("res://addons/npc_ai/npc_package_manifest.gd")

const HEALTH_POLL_MSEC := 200
const HTTP_CALL_TIMEOUT_MSEC := 1500
const PORT_MIN := 49152
const PORT_MAX := 65535
const MAX_LAUNCH_ATTEMPTS := 3
const MAX_SSE_BUFFER := 65536
const MAX_READS_PER_FRAME := 16
const STOP_WAIT_MSEC := 2000
const LOG_TAIL_LINES := 20
const LOG_FILES_TO_KEEP := 5

var manifest: RefCounted
var model_id := ""
var gpu_layers := "all"           ## "all" | "0" (solo CPU) | numero di layer in VRAM. "auto" in b10964 carica solo una parte: misurato 3-4x piu' lento.
var last_messages: Array = []     ## messaggi dell'ultima richiesta inviata (per le prove)
var _effective_gpu_layers := "all"   ## valore usato davvero: parte da gpu_layers, scende a "0" dopo un fallimento del caricamento
var threads := 0                  ## 0 = scelta del server
var context_size := 0             ## 0 = dal manifest
var start_timeout_msec := 0       ## 0 = dal manifest
var extra_args: PackedStringArray = PackedStringArray()
var log_to_file := true
var request_params_override: Dictionary = {}   ## es. {"seed": 7} per i benchmark

var cold_load_msec := -1          ## create_process -> /health 200
var warmup_msec := -1             ## /health 200 -> prima generazione di prova completata (pipeline GPU e cache pronte)
var warmup := true                ## una generazione da 1 token prima di READY: la prima battuta vera non paga il riscaldamento
var last_exit_code := -1
var last_log_tail := ""
var reconciled: Array[Dictionary] = []   ## orfani riconosciuti e chiusi
var stats := {"starts": 0, "launches": 0, "requests": 0, "cancels": 0, "errors": 0}

var _pid := -1
var _port := 0
var _api_key := ""
var _model_path := ""
var _exe_path := ""
var _state_file := ""
var _log_path := ""
var _phase := "idle"              ## idle | reconcile | health | props | warmup
var _warmup_started_msec := 0
var _started_msec := 0
var _launched_msec := 0
var _next_health_msec := 0
var _call: RefCounted             ## HttpCall in corso per health/props/reconcile
var _attempts := 0
var _ngl_fallback_done := false
var _used_ports: PackedInt32Array = PackedInt32Array()
var _stale: Array[Dictionary] = []
var _stale_current: Dictionary = {}
var _req: Dictionary = {}         ## richiesta in streaming: id, call, sent_msec, first_msec, text, tokens, sse_consumed, finish_reason, done_seen
var _rng := RandomNumberGenerator.new()


class HttpCall extends RefCounted:
	## Una chiamata HTTP non bloccante su loopback, spinta da poll(). Per lo streaming il corpo si accumula
	## in `buffer` man mano che i chunk arrivano; il chiamante consuma da `consumed` in poi.
	var client := HTTPClient.new()
	var phase := "idle"        ## connecting | requesting | body | done | failed | closed
	var code := 0
	var error := ""
	var buffer := PackedByteArray()
	var started_msec := 0
	var timeout_msec := 0
	var _method: int
	var _path := ""
	var _headers := PackedStringArray()
	var _body := ""

	func start(port: int, method: int, path: String, headers: PackedStringArray, body: String, timeout := 0) -> void:
		_method = method
		_path = path
		_headers = headers
		_body = body
		timeout_msec = timeout
		started_msec = Time.get_ticks_msec()
		client.blocking_mode_enabled = false
		if client.connect_to_host("127.0.0.1", port) != OK:
			_fail("connect_error")
			return
		phase = "connecting"

	func poll(max_reads := 16) -> void:
		if phase == "done" or phase == "failed" or phase == "closed" or phase == "idle":
			return
		if timeout_msec > 0 and Time.get_ticks_msec() - started_msec > timeout_msec:
			_fail("timeout")
			return
		client.poll()
		var status := client.get_status()
		match phase:
			"connecting":
				if status == HTTPClient.STATUS_CONNECTED:
					if client.request(_method, _path, _headers, _body) != OK:
						_fail("request_error")
					else:
						phase = "requesting"
				elif status == HTTPClient.STATUS_CANT_CONNECT or status == HTTPClient.STATUS_CONNECTION_ERROR \
						or status == HTTPClient.STATUS_CANT_RESOLVE or status == HTTPClient.STATUS_DISCONNECTED:
					_fail("cant_connect")
			"requesting":
				if client.has_response():
					code = client.get_response_code()
					phase = "body"
					_read(max_reads)
				elif status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_DISCONNECTED:
					_fail("connection_lost")
			"body":
				_read(max_reads)

	func _read(max_reads: int) -> void:
		var reads := 0
		while client.get_status() == HTTPClient.STATUS_BODY and reads < max_reads:
			var chunk := client.read_response_body_chunk()
			if chunk.is_empty():
				break
			buffer.append_array(chunk)
			reads += 1
		var status := client.get_status()
		if status == HTTPClient.STATUS_BODY:
			return
		if status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_DISCONNECTED:
			phase = "done"
		elif status == HTTPClient.STATUS_CONNECTION_ERROR:
			_fail("connection_lost")

	func text() -> String:
		return buffer.get_string_from_utf8()

	func is_finished() -> bool:
		return phase == "done" or phase == "failed" or phase == "closed"

	func close() -> void:
		client.close()
		if phase != "done" and phase != "failed":
			phase = "closed"

	func _fail(reason: String) -> void:
		error = reason
		phase = "failed"
		client.close()


func backend_name() -> String:
	return "llama_server"


func model_name() -> String:
	return model_id


func is_busy() -> bool:
	return not _req.is_empty()


func port() -> int:
	return _port


func pid() -> int:
	return _pid


func describe() -> Dictionary:
	var d := super.describe()
	d["port"] = _port
	d["pid"] = _pid
	d["phase"] = _phase
	d["executable"] = _exe_path
	d["model_path"] = _model_path
	d["cold_load_msec"] = cold_load_msec
	d["warmup_msec"] = warmup_msec
	d["gpu_layers"] = _effective_gpu_layers
	d["gpu_layers_configured"] = gpu_layers
	d["attempts"] = _attempts
	return d


func start() -> void:
	if _availability == Availability.STARTING or _availability == Availability.READY:
		return
	stats["starts"] += 1
	cold_load_msec = -1
	last_log_tail = ""
	_attempts = 0
	_ngl_fallback_done = false
	_effective_gpu_layers = gpu_layers   # ogni avvio riparte dal valore configurato
	if not _req.is_empty():
		_req["call"].close()
		_req = {}
	_rng.randomize()
	if manifest == null:
		manifest = Manifest.new()
	if not manifest.is_loaded() and not manifest.load_from():
		_set_availability(Availability.FAILED, "manifest: " + manifest.error)
		return
	if model_id == "":
		model_id = manifest.default_model_id()
	var runtime_check: Dictionary = manifest.check_runtime()
	if not runtime_check["ok"]:
		_set_availability(Availability.FAILED, "runtime_missing: %s (mancano: %s)" % [runtime_check["dir"], ", ".join(runtime_check["missing"])])
		return
	var model_check: Dictionary = manifest.check_model(model_id)
	if not model_check["ok"]:
		_set_availability(Availability.FAILED, "model_missing: " + str(model_check["reason"]))
		return
	_exe_path = runtime_check["executable"]
	_model_path = model_check["path"]
	_started_msec = Time.get_ticks_msec()
	_stale = _collect_stale_state_files()
	_stale_current = {}
	_phase = "reconcile"
	_set_availability(Availability.STARTING, "riconciliazione" if not _stale.is_empty() else "avvio")


func stop() -> void:
	if not _req.is_empty():
		_req["call"].close()
		_req = {}
	if _call != null:
		_call.close()
		_call = null
	_kill_own_process()
	_phase = "idle"
	_set_availability(Availability.STOPPED, "")


func poll(_delta_time: float) -> void:
	match _availability:
		Availability.STARTING:
			_poll_starting()
		Availability.READY:
			if not _req.is_empty():
				_poll_request()
			elif _pid > 0 and not OS.is_process_running(_pid):
				_on_process_died("il processo e' terminato inaspettatamente")
		Availability.FAILED, Availability.STOPPED, Availability.UNAVAILABLE:
			if not _req.is_empty():
				_finish_error("backend_failed", "backend non disponibile")


func effective_gpu_layers() -> String:
	return _effective_gpu_layers


func begin(request: RefCounted, messages: Array, params: Dictionary) -> bool:
	if not is_ready() or is_busy() or _pid <= 0:
		return false
	stats["requests"] += 1
	var body := _request_body(request, messages, params)
	last_messages = (body["messages"] as Array).duplicate(true)
	var call := HttpCall.new()
	call.start(_port, HTTPClient.METHOD_POST, "/v1/chat/completions", _headers(true), JSON.stringify(body), 0)
	_req = {"id": request.request_id, "call": call, "sent_msec": Time.get_ticks_msec(), "first_msec": -1, "text": "",
		"tokens": 0, "sse_consumed": 0, "finish_reason": "", "done_seen": false, "error_body": ""}
	return true


func cancel(request_id: String) -> void:
	if _req.is_empty() or _req["id"] != request_id:
		return
	stats["cancels"] += 1
	var partial: String = _req["text"]
	var timings := _timings()
	_req["call"].close()     # chiudere la connessione fa annullare la generazione al server
	_req = {}
	finished.emit(request_id, result(Response.Status.CANCELLED, partial, "cancelled", "annullato: connessione chiusa", timings, model_id))


# --------------------------------------------------------------------------------------------
# Avvio: riconciliazione orfani -> lancio -> /health -> /props -> READY
# --------------------------------------------------------------------------------------------
func _poll_starting() -> void:
	var now := Time.get_ticks_msec()
	if now - _started_msec > _start_timeout():
		_fail_start("start_timeout: nessuna risposta da /health entro %d ms" % _start_timeout())
		return
	match _phase:
		"reconcile":
			_poll_reconcile()
		"health":
			_poll_health(now)
		"props":
			_poll_props()
		"warmup":
			_poll_warmup()


func _poll_reconcile() -> void:
	if _stale_current.is_empty():
		if _stale.is_empty():
			_launch()
			return
		_stale_current = _stale.pop_front()
		var call := HttpCall.new()
		call.start(int(_stale_current["port"]), HTTPClient.METHOD_GET, "/props",
			["Authorization: Bearer " + str(_stale_current["key"]), "Accept: application/json"], "", HTTP_CALL_TIMEOUT_MSEC)
		_call = call
		return
	_call.poll()
	if not _call.is_finished():
		return
	var entry := _stale_current
	_stale_current = {}
	var killed := false
	if _call.phase == "done" and _call.code == 200:
		var props: Variant = _parse_json(_call.text())
		if props is Dictionary and _same_model(str(props.get("model_path", "")), str(entry.get("model_path", ""))):
			var pid: int = int(entry.get("pid", 0))
			if pid > 0:
				OS.kill(pid)   # e' un nostro llama-server rimasto orfano: risponde alla nostra chiave col nostro modello
				killed = true
	_call = null
	reconciled.append({"file": entry["file"], "pid": entry.get("pid", 0), "port": entry.get("port", 0), "killed": killed})
	DirAccess.remove_absolute(str(entry["file"]))


func _launch() -> void:
	_attempts += 1
	stats["launches"] += 1
	if _attempts > MAX_LAUNCH_ATTEMPTS:
		_fail_start("launch_attempts: troppi tentativi di avvio")
		return
	_port = _pick_port()
	if _port <= 0:
		_fail_start("no_port: nessuna porta libera su 127.0.0.1")
		return
	_api_key = Crypto.new().generate_random_bytes(16).hex_encode()
	_log_path = ""
	if log_to_file:
		_prune_logs(LOG_FILES_TO_KEEP - 1)
		_log_path = Paths.user_dir_absolute("logs").path_join("llama_server_%d_%d.log" % [_port, int(Time.get_unix_time_from_system())])
	var args := _server_args()
	var had_key := OS.has_environment("LLAMA_API_KEY")
	var previous_key := OS.get_environment("LLAMA_API_KEY")
	OS.set_environment("LLAMA_API_KEY", _api_key)
	_pid = OS.create_process(_exe_path, args, false)
	if had_key: OS.set_environment("LLAMA_API_KEY", previous_key)
	else: OS.unset_environment("LLAMA_API_KEY")
	if _pid <= 0:
		_pid = -1
		_fail_start("spawn_failed: impossibile avviare " + _exe_path)
		return
	_launched_msec = Time.get_ticks_msec()
	_next_health_msec = _launched_msec + HEALTH_POLL_MSEC
	_write_state_file()
	_phase = "health"
	_call = null
	_set_availability(Availability.STARTING, "caricamento del modello (tentativo %d)" % _attempts)


func _poll_health(now: int) -> void:
	if not OS.is_process_running(_pid):
		last_exit_code = OS.get_process_exit_code(_pid)
		last_log_tail = _read_log_tail()
		_remove_state_file()
		var lower := last_log_tail.to_lower()
		if lower.find("bind") >= 0 or lower.find("address") >= 0:
			_pid = -1
			_launch()   # porta occupata: se ne prova un'altra
			return
		if not _ngl_fallback_done and _effective_gpu_layers != "0":
			_ngl_fallback_done = true
			_effective_gpu_layers = "0"   # solo per questo avvio: il valore configurato resta quello dell'utente
			_pid = -1
			_launch()   # memoria GPU o backend GPU non disponibili: si riprova su CPU
			return
		_pid = -1
		_fail_start("process_exited: codice %d. %s" % [last_exit_code, _log_excerpt()])
		return
	if _call == null:
		if now < _next_health_msec:
			return
		_call = HttpCall.new()
		_call.start(_port, HTTPClient.METHOD_GET, "/health", ["Accept: application/json"], "", HTTP_CALL_TIMEOUT_MSEC)
	_call.poll()
	if not _call.is_finished():
		return
	var call: RefCounted = _call
	_call = null
	_next_health_msec = now + HEALTH_POLL_MSEC
	if call.phase == "done" and call.code == 200:
		cold_load_msec = now - _launched_msec
		_phase = "props"
		_call = HttpCall.new()
		_call.start(_port, HTTPClient.METHOD_GET, "/props", _headers(false), "", HTTP_CALL_TIMEOUT_MSEC)


func _poll_props() -> void:
	_call.poll()
	if not _call.is_finished():
		return
	var call: RefCounted = _call
	_call = null
	if call.phase == "done" and call.code == 200:
		var props: Variant = _parse_json(call.text())
		if props is Dictionary and _same_model(str(props.get("model_path", "")), _model_path):
			if warmup:
				_begin_warmup()
			else:
				_set_availability(Availability.READY, "")
			return
	# Qualcun altro risponde su quella porta o la chiave non e' accettata: non e' la nostra istanza.
	_kill_own_process()
	_phase = "health"
	_launch()


## Una generazione minima con cache disattivata: compila le pipeline della GPU e scalda il runtime.
## Un esito negativo non blocca l'avvio: il server ha gia' risposto a /health e /props.
func _begin_warmup() -> void:
	_phase = "warmup"
	_warmup_started_msec = Time.get_ticks_msec()
	var body := {"messages": [{"role": "system", "content": "Rispondi in italiano con una parola."}, {"role": "user", "content": "Ciao."}],
		"max_tokens": 1, "stream": false, "cache_prompt": false, "temperature": 0.0}
	var model_params: Dictionary = manifest.model_request_params(model_id)
	for key in model_params.keys():
		body[key] = model_params[key]
	_call = HttpCall.new()
	_call.start(_port, HTTPClient.METHOD_POST, "/v1/chat/completions", _headers(true), JSON.stringify(body), 60000)
	_set_availability(Availability.STARTING, "riscaldamento")


func _poll_warmup() -> void:
	if not OS.is_process_running(_pid):
		_on_process_died("il processo e' terminato durante il riscaldamento")
		return
	_call.poll()
	if not _call.is_finished():
		return
	warmup_msec = Time.get_ticks_msec() - _warmup_started_msec
	_call = null
	_set_availability(Availability.READY, "")


func _fail_start(reason: String) -> void:
	_kill_own_process()
	_phase = "idle"
	stats["errors"] += 1
	_set_availability(Availability.FAILED, reason)


func _on_process_died(reason: String) -> void:
	last_exit_code = OS.get_process_exit_code(_pid)
	last_log_tail = _read_log_tail()
	var pending_id := ""
	var partial := ""
	var timings := {}
	if not _req.is_empty():
		pending_id = _req["id"]
		partial = _req["text"]
		timings = _timings()
		_req["call"].close()
		_req = {}
	_remove_state_file()
	_pid = -1
	_phase = "idle"
	stats["errors"] += 1
	# Prima lo stato, poi il segnale: chi ascolta finished() rilancia subito la coda e deve trovarci gia' FAILED.
	_set_availability(Availability.FAILED, "process_exited: %s (codice %d). %s" % [reason, last_exit_code, _log_excerpt()])
	if pending_id != "":
		finished.emit(pending_id, result(Response.Status.ERROR, partial, "process_exited", reason, timings, model_id))


# --------------------------------------------------------------------------------------------
# Richiesta in streaming (SSE)
# --------------------------------------------------------------------------------------------
func _poll_request() -> void:
	var call: RefCounted = _req["call"]
	call.poll(MAX_READS_PER_FRAME)
	if call.phase == "body" or call.phase == "done":
		if call.code == 200:
			_consume_sse()
			if not _req.is_empty() and call.phase == "done" and not _req["done_seen"]:
				_finish_error("connection_lost", "la connessione si e' chiusa prima della fine della risposta")
		elif call.phase == "done":
			_finish_error("http_%d" % call.code, call.text().substr(0, 300))
		elif call.buffer.size() > MAX_SSE_BUFFER:
			_finish_error("http_%d" % call.code, "risposta di errore troppo lunga")
		return
	if call.phase == "failed":
		if _pid > 0 and not OS.is_process_running(_pid):
			_on_process_died("il processo e' terminato durante la generazione")
		else:
			_finish_error("connection_lost", call.error)


func _consume_sse() -> void:
	var call: RefCounted = _req["call"]
	var buffer: PackedByteArray = call.buffer
	var consumed: int = _req["sse_consumed"]
	if buffer.size() - consumed > MAX_SSE_BUFFER:
		_finish_error("sse_overflow", "flusso SSE oltre %d byte" % MAX_SSE_BUFFER)
		return
	while not _req.is_empty():
		var newline := buffer.find(10, consumed)
		if newline < 0:
			break
		var line := buffer.slice(consumed, newline).get_string_from_utf8().rstrip("\r")
		consumed = newline + 1
		_handle_sse_line(line)
	if not _req.is_empty():
		_req["sse_consumed"] = consumed
		if consumed > 0 and consumed >= buffer.size():
			call.buffer = PackedByteArray()
			_req["sse_consumed"] = 0
		elif consumed > 32768:
			call.buffer = buffer.slice(consumed)
			_req["sse_consumed"] = 0


func _handle_sse_line(line: String) -> void:
	if line == "" or line.begins_with(":"):
		return   # confine di evento oppure ping del server
	if line.begins_with("event:"):
		return
	if not line.begins_with("data:"):
		return
	var payload := line.substr(5).strip_edges()
	if payload == "[DONE]":
		_finish_ok()
		return
	var parsed: Variant = _parse_json(payload)
	if not (parsed is Dictionary):
		return
	if parsed.has("error"):
		var err: Variant = parsed["error"]
		var message := str(err.get("message", err)) if err is Dictionary else str(err)
		_finish_error("server_error", message.substr(0, 300))
		return
	var choices: Variant = parsed.get("choices", [])
	if choices is Array and not choices.is_empty() and choices[0] is Dictionary:
		var choice: Dictionary = choices[0]
		var delta_obj: Variant = choice.get("delta", {})
		if delta_obj is Dictionary:
			var content: Variant = delta_obj.get("content", null)
			if content is String and content != "":
				if int(_req["first_msec"]) < 0:
					_req["first_msec"] = Time.get_ticks_msec()
				_req["text"] = str(_req["text"]) + content
				_req["tokens"] = int(_req["tokens"]) + 1
				delta.emit(_req["id"], content)
		var finish: Variant = choice.get("finish_reason", null)
		if finish is String and finish != "":
			_req["finish_reason"] = finish
	var usage: Variant = parsed.get("usage", null)
	if usage is Dictionary and usage.has("completion_tokens"):
		_req["tokens"] = int(usage["completion_tokens"])
	var timings: Variant = parsed.get("timings", null)
	if timings is Dictionary and timings.has("predicted_n"):
		_req["tokens"] = int(timings["predicted_n"])


func _finish_ok() -> void:
	_req["done_seen"] = true
	var id: String = _req["id"]
	var text: String = _req["text"]
	var timings := _timings()
	_req["call"].close()
	_req = {}
	finished.emit(id, result(Response.Status.OK, text, "", "", timings, model_id))


func _finish_error(code: String, message: String) -> void:
	stats["errors"] += 1
	var id: String = _req["id"]
	var partial: String = _req["text"]
	var timings := _timings()
	_req["call"].close()
	_req = {}
	finished.emit(id, result(Response.Status.ERROR, partial, code, message, timings, model_id))


func _timings() -> Dictionary:
	var now := Time.get_ticks_msec()
	var sent: int = _req["sent_msec"]
	var first: int = _req["first_msec"]
	return {"first_token_msec": (first - sent) if first >= 0 else -1, "total_msec": now - sent, "tokens": int(_req["tokens"]),
		"finish_reason": _req["finish_reason"]}


func _request_body(request: RefCounted, messages: Array, params: Dictionary) -> Dictionary:
	var prefix: String = manifest.model_system_prefix(model_id)
	var msgs: Array = []
	for i in messages.size():
		var m: Dictionary = messages[i]
		var content := str(m["content"])
		if i == 0 and m["role"] == "system" and prefix != "":
			content = prefix + "\n" + content
		msgs.append({"role": m["role"], "content": content})
	var body := {
		"messages": msgs,
		"stream": true,
		"stream_options": {"include_usage": true},
		"max_tokens": int(params.get("max_tokens", request.limit("max_output_tokens"))),
		"temperature": float(params.get("temperature", 0.7)),
		"top_p": 0.9,
		"repeat_penalty": 1.1,
		"cache_prompt": true,
	}
	if params.has("seed"):
		body["seed"] = int(params["seed"])
	var model_params: Dictionary = manifest.model_request_params(model_id)
	for key in model_params.keys():
		body[key] = model_params[key]
	for key in request_params_override.keys():
		body[key] = request_params_override[key]
	return body


# --------------------------------------------------------------------------------------------
# Processo, porta, file di stato, log
# --------------------------------------------------------------------------------------------
func _server_args() -> PackedStringArray:
	var args := PackedStringArray()
	args.append_array(manifest.server_args())
	args.append_array(["-m", _model_path, "--port", str(_port), "-c", str(_context_size()), "-ngl", _effective_gpu_layers])
	if threads > 0:
		args.append_array(["-t", str(threads)])
	if _log_path != "":
		args.append_array(["--log-file", _log_path])
	for arg in extra_args:
		if arg != "":
			args.append(arg)
	return args


func _pick_port() -> int:
	for attempt in 12:
		var candidate := _rng.randi_range(PORT_MIN, PORT_MAX)
		if _used_ports.has(candidate):
			continue
		var probe := TCPServer.new()
		if probe.listen(candidate, "127.0.0.1") == OK:
			probe.stop()
			_used_ports.append(candidate)
			return candidate
	return -1


func _headers(json_body: bool) -> PackedStringArray:
	var h := PackedStringArray(["Authorization: Bearer " + _api_key, "Accept: text/event-stream, application/json"])
	if json_body:
		h.append("Content-Type: application/json")
	return h


func _context_size() -> int:
	return context_size if context_size > 0 else manifest.context_size()


func _start_timeout() -> int:
	return start_timeout_msec if start_timeout_msec > 0 else manifest.start_timeout_msec()


func _same_model(reported: String, expected: String) -> bool:
	if reported == "" or expected == "":
		return false
	return Paths.normalize(reported).get_file() == Paths.normalize(expected).get_file()


func _kill_own_process() -> void:
	if _pid > 0:
		if OS.is_process_running(_pid):
			OS.kill(_pid)
			var deadline := Time.get_ticks_msec() + STOP_WAIT_MSEC
			while OS.is_process_running(_pid) and Time.get_ticks_msec() < deadline:
				OS.delay_msec(20)
		_remove_state_file()
	_pid = -1


func _write_state_file() -> void:
	_state_file = Paths.state_dir().path_join("llama_server_%d_%d.json" % [OS.get_process_id(), _port])
	var file := FileAccess.open(_state_file, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"owner_pid": OS.get_process_id(), "owner_exe": OS.get_executable_path().get_file(), "pid": _pid,
		"port": _port, "key": _api_key, "model_path": _model_path, "executable": _exe_path,
		"started_unix": int(Time.get_unix_time_from_system())}, "\t"))
	file.close()


func _remove_state_file() -> void:
	if _state_file != "" and FileAccess.file_exists(_state_file):
		DirAccess.remove_absolute(_state_file)
	_state_file = ""


## File di stato di istanze precedenti il cui proprietario (processo Godot) non esiste piu'.
func _collect_stale_state_files() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(Paths.state_dir())
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.begins_with("llama_server_") or not name.ends_with(".json"):
			continue
		var path := Paths.state_dir().path_join(name)
		var parsed: Variant = _parse_json(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			DirAccess.remove_absolute(path)
			continue
		var owner := int(parsed.get("owner_pid", 0))
		if owner == OS.get_process_id():
			continue   # e' di questa istanza (un altro backend nello stesso processo)
		if owner > 0 and _foreign_pid_alive(owner, str(parsed.get("owner_exe", ""))):
			continue   # un'altra istanza del gioco/editor e' viva: il suo server e' affar suo
		var entry := {"file": path, "pid": int(parsed.get("pid", 0)), "port": int(parsed.get("port", 0)),
			"key": str(parsed.get("key", "")), "model_path": str(parsed.get("model_path", ""))}
		if entry["port"] <= 0 or entry["key"] == "":
			DirAccess.remove_absolute(path)
			continue
		out.append(entry)
	return out


## Chiamate bloccanti del backend: questa (decine di ms, solo alla riconciliazione) e l'attesa dell'uscita
## del processo allo stop (di norma < 20 ms, al massimo STOP_WAIT_MSEC). is_process_running() vale soltanto
## per i processi avviati da questa istanza. Windows riusa i pid: il proprietario conta come vivo solo se
## l'eseguibile che oggi ha quel pid e' quello registrato nel file di stato.
static func _foreign_pid_alive(pid: int, expected_exe := "") -> bool:
	if OS.get_name() != "Windows":
		return false
	var output: Array = []
	OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], output, false, false)
	for chunk in output:
		for line in str(chunk).split("\n", false):
			if line.find("\"%d\"" % pid) < 0:
				continue
			var fields := line.split("\",\"", false)
			var image := fields[0].trim_prefix("\"").to_lower() if not fields.is_empty() else ""
			if expected_exe == "" or image == expected_exe.to_lower():
				return true
			return false   # pid riusato da un altro programma: il proprietario e' morto
	return false


static func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## Tiene gli ultimi `keep` log di llama-server in user://npc_ai/logs/: senza rotazione crescerebbero a ogni avvio.
static func _prune_logs(keep: int) -> void:
	var dir_path := Paths.logs_dir()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var logs: Array[Dictionary] = []
	for name in dir.get_files():
		if name.begins_with("llama_server_") and name.ends_with(".log"):
			logs.append({"name": name, "time": FileAccess.get_modified_time(dir_path.path_join(name))})
	logs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["time"]) > int(b["time"]))
	for i in range(maxi(keep, 0), logs.size()):
		dir.remove(logs[i]["name"])


func _read_log_tail() -> String:
	if _log_path == "" or not FileAccess.file_exists(_log_path):
		return ""
	var lines := FileAccess.get_file_as_string(_log_path).split("\n", false)
	var from := maxi(0, lines.size() - LOG_TAIL_LINES)
	return "\n".join(lines.slice(from))


func _log_excerpt() -> String:
	if last_log_tail == "":
		return ""
	var lines := last_log_tail.split("\n", false)
	return "Ultime righe del log: " + " | ".join(lines.slice(maxi(0, lines.size() - 3))).substr(0, 400)

extends SceneTree
## End-to-end con il backend REALE, oltre lo streaming: bind solo su 127.0.0.1 (netstat), endpoint protetto
## (senza chiave -> 401), identita' dell'istanza (/props), scambio in italiano, crash simulato del processo
## -> ripiego e riavvio, arresto senza orfani, riconciliazione di un orfano di una partita precedente, server
## estraneo NON ucciso, istanza sorella viva saltata, guasti (runtime assente, modello assente, GGUF
## spazzatura, contesto impossibile) -> FAILED con dialogo in ripiego. Skip (3) se runtime/modello mancano.
## Run: godot --headless --path . --script res://tools/npc_ai/check_npc_local_backend.gd
const Service = preload("res://addons/npc_ai/npc_inference_service.gd")
const Llama = preload("res://addons/npc_ai/npc_backend_llama_server.gd")
const Backend = preload("res://addons/npc_ai/npc_backend.gd")
const Manifest = preload("res://addons/npc_ai/npc_package_manifest.gd")
const Paths = preload("res://addons/npc_ai/npc_ai_paths.gd")
const ContextBuilder = preload("res://addons/npc_ai/npc_context_builder.gd")
const Conversation = preload("res://addons/npc_ai/npc_conversation.gd")
const Memory = preload("res://addons/npc_ai/npc_memory.gd")
const Validator = preload("res://addons/npc_ai/npc_validator.gd")
const Response = preload("res://addons/npc_ai/npc_chat_response.gd")
const PROFILE_PATH := "res://assets/npc_ai/blacksmith_profile.tres"
const FACTS_PATH := "res://assets/npc_ai/blacksmith_facts.json"
const TEST_ROOT := "user://npc_ai/test/local"
const WATCHDOG_MSEC := 420000
const MIN_CHECKS := 30

var failures := 0
var checks := 0
var started_msec := 0
var manifest: RefCounted
var profile: Resource
var allowed: PackedStringArray
var service: Node
var backend: RefCounted
var responses: Array = []
var helper_pids: Array[int] = []


func _initialize() -> void:
	started_msec = Time.get_ticks_msec()
	call_deferred("run")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_msec > WATCHDOG_MSEC:
		push_error("NPC_AI_LOCAL_BACKEND: watchdog scaduto")
		finish(1)
	return false


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("NPC_AI_LOCAL_BACKEND: " + label)


func finish(code: int) -> void:
	if backend != null:
		backend.stop()
	for pid in helper_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	print("NPC_AI_LOCAL_BACKEND_CHECK failures=", failures, " checks=", checks)
	quit(code)


func wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()


func wait_ready(b: RefCounted, timeout_msec: int) -> bool:
	return await wait_until(func() -> bool: return b.availability() == Backend.Availability.READY or b.availability() == Backend.Availability.FAILED, timeout_msec)


func request_for(sid: String, turn: int, text: String) -> RefCounted:
	return ContextBuilder.build_request(profile, allowed, null, sid, "%s/%d" % [sid, turn], 1, text, [])


func http(port: int, path: String, headers: PackedStringArray, timeout := 4000) -> RefCounted:
	var call: RefCounted = Llama.HttpCall.new()
	call.start(port, HTTPClient.METHOD_GET, path, headers, "", timeout)
	while not call.is_finished():
		call.poll()
		await process_frame
	return call


func tasklist_has(pid: int) -> bool:
	var output: Array = []
	OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], output, false, false)
	for line in output:
		if str(line).find("\"%d\"" % pid) >= 0:
			return true
	return false


func netstat_lines(port: int) -> PackedStringArray:
	var output: Array = []
	OS.execute("netstat", ["-ano", "-p", "TCP"], output, false, false)
	var out := PackedStringArray()
	for chunk in output:
		for line in str(chunk).split("\n", false):
			if line.find(":%d " % port) >= 0 and line.find("LISTENING") >= 0:
				out.append(line.strip_edges())
	return out


func new_backend(model_id: String) -> RefCounted:
	var b: RefCounted = Llama.new()
	b.manifest = manifest
	b.model_id = model_id
	return b


func run() -> void:
	manifest = Manifest.new()
	if not manifest.load_from():
		print("NPC_AI_LOCAL_BACKEND_SKIPPED reason=manifest")
		quit(3)
		return
	var model_id: String = manifest.default_model_id()
	if not manifest.check_runtime()["ok"] or not manifest.check_model(model_id)["ok"]:
		print("NPC_AI_LOCAL_BACKEND_SKIPPED reason=runtime o modello assenti; scarica con python tools/npc_ai/fetch_npc_package.py --runtime --model ", model_id)
		quit(3)
		return
	profile = load(PROFILE_PATH)
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))
	allowed = PackedStringArray(facts["allowed"])
	DirAccess.make_dir_recursive_absolute(TEST_ROOT)
	await test_lifecycle_and_security(model_id)
	await test_crash_and_restart(model_id)
	await test_orphan_reconciliation(model_id)
	await test_failures(model_id)
	if checks < MIN_CHECKS:
		failures += 1
		push_error("NPC_AI_LOCAL_BACKEND: eseguiti solo %d controlli su almeno %d attesi" % [checks, MIN_CHECKS])
	finish(0 if failures == 0 else 1)


func test_lifecycle_and_security(model_id: String) -> void:
	service = Service.new()
	root.add_child(service)
	backend = new_backend(model_id)
	service.set_backend(backend)
	service.response_ready.connect(func(r: RefCounted) -> void: responses.append(r))
	service.start()
	var ok := await wait_ready(backend, manifest.start_timeout_msec() + 15000)
	check(ok and backend.is_ready(), "READY (%s)" % backend.failure_reason())
	if not backend.is_ready():
		return
	var port: int = backend.port()
	var pid: int = backend.pid()
	print("NPC_AI_LOCAL_BACKEND port=", port, " pid=", pid, " cold_load_msec=", backend.cold_load_msec)
	# bind solo su loopback
	var lines := netstat_lines(port)
	check(lines.size() >= 1, "netstat vede la porta in LISTENING (%d righe)" % lines.size())
	var loopback_only := not lines.is_empty()
	for line in lines:
		if line.find("127.0.0.1:%d" % port) < 0 or not line.ends_with(str(pid)):
			loopback_only = false
		print("NPC_AI_LOCAL_BACKEND netstat: ", line)
	check(loopback_only, "solo 127.0.0.1:%d e pid %d, nessun 0.0.0.0" % [port, pid])
	# endpoint protetto: senza chiave 401, /health pubblico
	var no_key := await http(port, "/props", ["Accept: application/json"])
	check(no_key.code == 401, "/props senza chiave -> 401 (ottenuto %d, %s)" % [no_key.code, no_key.error])
	var wrong_key := await http(port, "/props", ["Authorization: Bearer 0000", "Accept: application/json"])
	check(wrong_key.code == 401, "/props con chiave sbagliata -> 401 (%d)" % wrong_key.code)
	var health := await http(port, "/health", ["Accept: application/json"])
	check(health.code == 200, "/health pubblico -> 200 (%d)" % health.code)
	var props := await http(port, "/props", ["Authorization: Bearer " + backend._api_key, "Accept: application/json"])
	var props_json: Variant = JSON.parse_string(props.text()) if props.code == 200 else null
	check(props_json is Dictionary and str(props_json.get("model_path", "")).get_file() == manifest.model_path(model_id).get_file(), "/props con la chiave riporta il nostro modello")
	# scambio in italiano
	var sid := "fabbro_bruno:1:local01"
	service.open_session(sid, "fabbro_bruno", 1)
	responses.clear()
	var req := request_for(sid, 1, "Buongiorno Bruno, che cosa sai riparare?")
	check(service.submit(req, ContextBuilder.to_messages(req), {"max_tokens": 120, "seed": 3}) == OK, "submit")
	var done := await wait_until(func() -> bool: return responses.size() == 1, 60000)
	check(done and responses[0].status == Response.Status.OK and responses[0].text != "", "risposta OK in italiano")
	if done:
		var text: String = responses[0].text
		print("NPC_AI_LOCAL_BACKEND text=", text.replace("\n", " / "))
		check(Validator.is_plain_text(text) and text.length() <= 320, "testo semplice entro 320 caratteri (%d)" % text.length())
	# annullamento a meta'
	responses.clear()
	var long_req := request_for(sid, 2, "Raccontami per filo e per segno la storia della tua famiglia, del borgo e della cava.")
	service.submit(long_req, ContextBuilder.to_messages(long_req), {"max_tokens": 160})
	var streaming := await wait_until(func() -> bool: return backend.is_busy() and str(backend._req.get("text", "")).length() > 10, 30000)
	var t0 := Time.get_ticks_msec()
	service.cancel(long_req.request_id)
	var cancelled := await wait_until(func() -> bool: return responses.size() == 1, 5000)
	check(streaming and cancelled and responses[0].status == Response.Status.CANCELLED and Time.get_ticks_msec() - t0 < 2000, "annullamento a meta' entro 2 s")
	responses.clear()
	var again := request_for(sid, 3, "Quanto costa affilare una spada?")
	service.submit(again, ContextBuilder.to_messages(again), {"max_tokens": 80})
	var served := await wait_until(func() -> bool: return responses.size() == 1, 60000)
	check(served and responses[0].status == Response.Status.OK, "dopo l'annullamento la richiesta successiva viene servita")
	# se il server avesse continuato a generare i 160 token annullati (~1,8 s) il primo token qui arriverebbe dopo
	check(served and int(responses[0].timings["first_token_msec"]) < 1200, "il server ha davvero smesso di generare: primo token successivo in %d ms" % (int(responses[0].timings["first_token_msec"]) if served else -1))
	check(backend.last_messages.size() >= 2 and backend.last_messages[-1]["role"] == "user" and str(backend.last_messages[-1]["content"]) == "Quanto costa affilare una spada?", "il backend registra i messaggi davvero inviati")
	# arresto pulito
	var state_file: String = backend._state_file
	check(state_file != "" and FileAccess.file_exists(state_file), "file di stato presente mentre gira")
	service.stop()
	var gone := await wait_until(func() -> bool: return not tasklist_has(pid), 4000)
	check(backend.availability() == Backend.Availability.STOPPED and not OS.is_process_running(pid) and gone, "stop: processo terminato (tasklist)")
	check(not FileAccess.file_exists(state_file), "stop: file di stato rimosso")
	check(netstat_lines(port).is_empty(), "stop: porta rilasciata")


func test_crash_and_restart(model_id: String) -> void:
	backend._set_availability(Backend.Availability.UNAVAILABLE, "")
	service.start()
	var ok := await wait_ready(backend, manifest.start_timeout_msec() + 15000)
	check(ok and backend.is_ready(), "riavvio dopo stop -> READY")
	if not backend.is_ready():
		return
	var pid: int = backend.pid()
	var sid := "fabbro_bruno:2:crash01"
	service.open_session(sid, "fabbro_bruno", 1)
	responses.clear()
	var req := request_for(sid, 1, "Raccontami tutto quello che sai sul borgo, sui lupi e sulla cava, con calma e nei dettagli.")
	service.submit(req, ContextBuilder.to_messages(req), {"max_tokens": 160})
	await wait_until(func() -> bool: return backend.is_busy() and str(backend._req.get("text", "")).length() > 5, 30000)
	OS.kill(pid)   # crash simulato del processo di inferenza durante la generazione
	var reported := await wait_until(func() -> bool: return responses.size() == 1, 10000)
	check(reported and responses[0].status == Response.Status.ERROR and (responses[0].error_code == "process_exited" or responses[0].error_code == "connection_lost"), "crash a meta' -> ERROR %s" % (responses[0].error_code if reported else "(nessuna risposta)"))
	await wait_until(func() -> bool: return backend.availability() == Backend.Availability.FAILED, 5000)
	check(backend.availability() == Backend.Availability.FAILED and service.state() == Service.ServiceState.FAILED, "backend FAILED dopo il crash: " + backend.failure_reason())
	# il dialogo resta usabile in ripiego
	var memory := Memory.new()
	memory.setup("fabbro_bruno", TEST_ROOT)
	memory.reset()
	var convo := Conversation.new()
	convo.setup(profile, memory, service, allowed)
	convo.open()
	convo.send("Ci sei ancora?")
	check(convo.state == Conversation.State.FALLBACK and profile.fallback_lines.has(convo.transcript[-1]["text"]), "dialogo in ripiego immediato col backend caduto")
	convo.close()
	memory.reset()
	# riavvio: il backend riparte e risponde
	backend._set_availability(Backend.Availability.UNAVAILABLE, "")
	service.start()
	ok = await wait_ready(backend, manifest.start_timeout_msec() + 15000)
	check(ok and backend.is_ready() and backend.pid() != pid, "riavvio dopo il crash -> READY con nuovo pid")
	service.stop()


func test_orphan_reconciliation(model_id: String) -> void:
	# 1) un llama-server avviato da una "partita precedente" (proprietario morto): va riconosciuto e chiuso
	var orphan := new_backend(model_id)
	orphan.start()
	var deadline: int = Time.get_ticks_msec() + manifest.start_timeout_msec() + 15000
	while orphan.availability() == Backend.Availability.STARTING and Time.get_ticks_msec() < deadline:
		orphan.poll(0.016)
		await process_frame
	check(orphan.is_ready(), "istanza orfana pronta (%s)" % orphan.failure_reason())
	if not orphan.is_ready():
		return
	var orphan_pid: int = orphan.pid()
	var orphan_port: int = orphan.port()
	var state_path: String = orphan._state_file
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state_path))
	state["owner_pid"] = 999999   # un processo Godot che non esiste piu'
	var f := FileAccess.open(state_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(state))
	f.close()
	orphan._pid = -1               # dimentica il processo: resta vivo e orfano, come dopo un crash del gioco
	orphan._state_file = ""
	orphan = null
	check(tasklist_has(orphan_pid), "l'orfano e' vivo prima della riconciliazione")
	# 2) un server ESTRANEO sulla stessa macchina: un processo nostro che non risponde alla chiave
	var foreign_pid := OS.create_process("ping.exe", ["-n", "120", "127.0.0.1"], false)   # processo nostro, longevo, senza console
	helper_pids.append(foreign_pid)
	var foreign_port := 0
	var listener := TCPServer.new()
	for candidate in range(50000, 50040):
		if listener.listen(candidate, "127.0.0.1") == OK:
			foreign_port = candidate
			break
	var foreign_file := Paths.state_dir().path_join("llama_server_888888.json")
	f = FileAccess.open(foreign_file, FileAccess.WRITE)
	f.store_string(JSON.stringify({"owner_pid": 999998, "pid": foreign_pid, "port": foreign_port, "key": "chiave_falsa", "model_path": state["model_path"]}))
	f.close()
	# 2b) proprietario "vivo" ma con pid riusato da un altro programma (ping): va trattato come morto
	var reused_file := Paths.state_dir().path_join("llama_server_777777.json")
	f = FileAccess.open(reused_file, FileAccess.WRITE)
	f.store_string(JSON.stringify({"owner_pid": foreign_pid, "owner_exe": "Godot_v4.6.3-stable_win64_console.exe", "pid": foreign_pid, "port": foreign_port, "key": "chiave_falsa", "model_path": state["model_path"]}))
	f.close()
	# 3) un'istanza sorella VIVA (stesso processo Godot): va saltata
	var sibling_file := Paths.state_dir().path_join("llama_server_%d_sibling.json" % OS.get_process_id())
	f = FileAccess.open(sibling_file, FileAccess.WRITE)
	f.store_string(JSON.stringify({"owner_pid": OS.get_process_id(), "pid": foreign_pid, "port": foreign_port, "key": "x", "model_path": state["model_path"]}))
	f.close()
	# avvio "nuova partita": riconcilia
	backend = new_backend(model_id)
	service.set_backend(backend)
	service.start()
	var ready := await wait_ready(backend, manifest.start_timeout_msec() + 30000)
	listener.stop()
	check(ready and backend.is_ready(), "nuova istanza READY dopo la riconciliazione (%s)" % backend.failure_reason())
	var killed_orphan := false
	var spared_foreign := true
	for entry in backend.reconciled:
		print("NPC_AI_LOCAL_BACKEND reconciled: ", entry)
		if int(entry["pid"]) == orphan_pid and entry["killed"]:
			killed_orphan = true
		if int(entry["pid"]) == foreign_pid and entry["killed"]:
			spared_foreign = false
	check(killed_orphan and not tasklist_has(orphan_pid), "orfano riconosciuto (chiave + modello) e terminato")
	check(spared_foreign and OS.is_process_running(foreign_pid) and tasklist_has(foreign_pid), "processo estraneo NON terminato")
	check(not FileAccess.file_exists(state_path) and not FileAccess.file_exists(foreign_file), "file di stato obsoleti rimossi")
	check(not FileAccess.file_exists(reused_file) and tasklist_has(foreign_pid), "pid del proprietario riusato da un altro programma: file rimosso, processo non toccato")
	check(FileAccess.file_exists(sibling_file), "file di stato di un'istanza viva saltato")
	DirAccess.remove_absolute(sibling_file)
	if OS.is_process_running(foreign_pid):
		OS.kill(foreign_pid)
	service.stop()


func test_failures(model_id: String) -> void:
	# runtime assente
	var broken := Manifest.new()
	broken.load_from()
	broken.data["runtime"]["install_dir"] = "runtime_inesistente"
	var b: RefCounted = Llama.new()
	b.manifest = broken
	b.model_id = model_id
	b.start()
	check(b.availability() == Backend.Availability.FAILED and b.failure_reason().begins_with("runtime_missing"), "runtime assente -> FAILED subito: " + b.failure_reason())
	# modello assente
	b = new_backend("modello_inesistente")
	b.start()
	check(b.availability() == Backend.Availability.FAILED and b.failure_reason().begins_with("model_missing"), "modello assente -> FAILED subito: " + b.failure_reason())
	# GGUF spazzatura: il processo esce; dopo il tentativo su CPU resta FAILED
	var garbage_path: String = manifest.models_dir().path_join("garbage_test.gguf")
	var g := FileAccess.open(garbage_path, FileAccess.WRITE)
	g.store_string("questo non e' un modello ".repeat(40))
	g.close()
	var garbage_size := FileAccess.open(garbage_path, FileAccess.READ).get_length()
	var tampered := Manifest.new()
	tampered.load_from()
	tampered.data["models"].append({"id": "garbage", "file": "garbage_test.gguf", "size": garbage_size, "system_prefix": "", "request_params": {}})
	b = Llama.new()
	b.manifest = tampered
	b.model_id = "garbage"
	b.start_timeout_msec = 60000
	service.set_backend(b)
	service.start()
	var settled := await wait_until(func() -> bool: return b.availability() == Backend.Availability.FAILED or b.availability() == Backend.Availability.READY, 70000)
	check(settled and b.availability() == Backend.Availability.FAILED and b.failure_reason().begins_with("process_exited"), "GGUF spazzatura -> FAILED (%s)" % b.failure_reason())
	check(b.stats["launches"] == 2 and b.effective_gpu_layers() == "0" and b.gpu_layers == "all", "dopo il primo fallimento si e' riprovato una volta su CPU senza toccare il valore configurato")
	check(b.pid() == -1, "nessun processo lasciato vivo dopo il fallimento")
	DirAccess.remove_absolute(garbage_path)
	# contesto impossibile: memoria insufficiente per la KV cache
	b = new_backend(model_id)
	b.context_size = 4000000
	b.start_timeout_msec = 90000
	service.set_backend(b)
	service.start()
	settled = await wait_until(func() -> bool: return b.availability() == Backend.Availability.FAILED or b.availability() == Backend.Availability.READY, 100000)
	check(settled and b.availability() == Backend.Availability.FAILED, "contesto da 4 milioni di token -> FAILED (%s)" % b.failure_reason().substr(0, 120))
	check(b.pid() == -1 or not OS.is_process_running(b.pid()), "nessun processo vivo dopo il guasto di memoria")
	var memory := Memory.new()
	memory.setup("fabbro_bruno", TEST_ROOT)
	memory.reset()
	var convo := Conversation.new()
	convo.setup(profile, memory, service, allowed)
	convo.open()
	convo.send("Sei li'?")
	check(convo.state == Conversation.State.FALLBACK, "dialogo in ripiego col backend in errore")
	convo.close()
	memory.reset()
	service.stop()
	backend = null

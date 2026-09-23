extends SceneTree
## Prova con il backend REALE: llama-server parte, /health e /props rispondono, una richiesta in italiano
## arriva in streaming (piu' chunk a istanti distinti, non un blocco unico), il processo viene fermato e non
## resta orfano. Se runtime o modello non sono stati scaricati stampa SKIPPED ed esce con codice 3.
## Run: godot --headless --path . --script res://tools/npc_ai/check_npc_streaming.gd [-- --model <id>]
const Service = preload("res://addons/npc_ai/npc_inference_service.gd")
const Llama = preload("res://addons/npc_ai/npc_backend_llama_server.gd")
const Backend = preload("res://addons/npc_ai/npc_backend.gd")
const Manifest = preload("res://addons/npc_ai/npc_package_manifest.gd")
const ContextBuilder = preload("res://addons/npc_ai/npc_context_builder.gd")
const Response = preload("res://addons/npc_ai/npc_chat_response.gd")
const PROFILE_PATH := "res://assets/npc_ai/blacksmith_profile.tres"
const FACTS_PATH := "res://assets/npc_ai/blacksmith_facts.json"
const WATCHDOG_MSEC := 240000

var failures := 0
var checks := 0
var started_msec := 0
var service: Node
var backend: RefCounted


func _initialize() -> void:
	started_msec = Time.get_ticks_msec()
	call_deferred("run")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_msec > WATCHDOG_MSEC:
		push_error("NPC_AI_STREAMING: watchdog scaduto")
		finish(1)
	return false


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("NPC_AI_STREAMING: " + label)


func finish(code: int) -> void:
	if backend != null:
		backend.stop()
	print("NPC_AI_STREAMING_CHECK failures=", failures, " checks=", checks)
	quit(code)


func arg_value(name: String, default_value: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return default_value


func wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()


func run() -> void:
	var manifest := Manifest.new()
	if not manifest.load_from():
		print("NPC_AI_STREAMING_SKIPPED reason=manifest: ", manifest.error)
		quit(3)
		return
	var model_id := arg_value("--model", manifest.default_model_id())
	var runtime_check: Dictionary = manifest.check_runtime()
	var model_check: Dictionary = manifest.check_model(model_id)
	if not runtime_check["ok"] or not model_check["ok"]:
		print("NPC_AI_STREAMING_SKIPPED reason=runtime_ok=%s model_ok=%s (%s). Scarica con: python tools/npc_ai/fetch_npc_package.py --runtime --model %s" % [runtime_check["ok"], model_check["ok"], model_check["reason"], model_id])
		quit(3)
		return
	service = Service.new()
	root.add_child(service)
	backend = Llama.new()
	backend.manifest = manifest
	backend.model_id = model_id
	backend.gpu_layers = arg_value("--ngl", "all")
	service.set_backend(backend)
	var states: Array = []
	backend.availability_changed.connect(func(s: int, reason: String) -> void: states.append([s, reason]))
	service.start()
	check(backend.availability() == Backend.Availability.STARTING, "start() -> STARTING")
	var ready := await wait_until(func() -> bool: return backend.availability() == Backend.Availability.READY or backend.availability() == Backend.Availability.FAILED, manifest.start_timeout_msec() + 15000)
	check(ready and backend.is_ready(), "READY entro il timeout (stato %s: %s)" % [Backend.availability_name(backend.availability()), backend.failure_reason()])
	if not backend.is_ready():
		finish(1)
		return
	print("NPC_AI_STREAMING cold_load_msec=", backend.cold_load_msec, " port=", backend.port(), " pid=", backend.pid(), " ngl=", backend.gpu_layers, " reconciled=", backend.reconciled.size())
	check(backend.cold_load_msec > 0, "caricamento a freddo misurato")
	check(OS.is_process_running(backend.pid()), "processo vivo")
	# richiesta in italiano
	var profile: Resource = load(PROFILE_PATH)
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))
	var sid := "fabbro_bruno:1:stream01"
	service.open_session(sid, "fabbro_bruno", 1)
	var request: RefCounted = ContextBuilder.build_request(profile, PackedStringArray(facts["allowed"]), null, sid, sid + "/1", 1, "Buongiorno, sei tu il fabbro? Cosa sai riparare?", [])
	var deltas: Array = []   # [msec, text]
	var responses: Array = []
	service.response_delta.connect(func(_id: String, text: String) -> void: deltas.append([Time.get_ticks_msec(), text]))
	service.response_ready.connect(func(r: RefCounted) -> void: responses.append(r))
	var sent := Time.get_ticks_msec()
	check(service.submit(request, ContextBuilder.to_messages(request), {"max_tokens": 120, "temperature": 0.7, "seed": 7}) == OK, "submit accettata (%s)" % service.last_reject_code)
	var done := await wait_until(func() -> bool: return responses.size() == 1, 60000)
	check(done, "risposta arrivata entro 60 s")
	if responses.is_empty():
		finish(1)
		return
	var res: RefCounted = responses[0]
	print("NPC_AI_STREAMING status=", Response.status_name(res.status), " code=", res.error_code, " timings=", res.timings, " flags=", res.flags)
	print("NPC_AI_STREAMING text=", res.text.replace("\n", " / "))
	check(res.status == Response.Status.OK and res.text != "", "risposta OK con testo: " + res.error_message)
	check(deltas.size() >= 3, "almeno tre delta in streaming (%d)" % deltas.size())
	var distinct := {}
	for d in deltas:
		distinct[d[0]] = true
	check(distinct.size() >= 3, "delta consegnati a istanti distinti (%d istanti)" % distinct.size())
	if not deltas.is_empty():
		var first: int = deltas[0][0] - sent
		var last: int = deltas[-1][0] - sent
		print("NPC_AI_STREAMING first_delta_msec=", first, " last_delta_msec=", last, " deltas=", deltas.size())
		check(last - first >= 50, "lo streaming copre un intervallo reale (%d ms fra primo e ultimo delta)" % (last - first))
	check(int(res.timings["first_token_msec"]) >= 0 and int(res.timings["total_msec"]) > 0 and int(res.timings["tokens"]) > 0, "timings del backend reale: " + str(res.timings))
	# annullamento a meta' di una seconda richiesta
	responses.clear()
	var request2: RefCounted = ContextBuilder.build_request(profile, PackedStringArray(facts["allowed"]), null, sid, sid + "/2", 1, "Raccontami tutta la storia della tua famiglia e del borgo, con molti dettagli.", [])
	service.submit(request2, ContextBuilder.to_messages(request2), {"max_tokens": 160})
	var streaming := await wait_until(func() -> bool: return service.active_request_id() == request2.request_id and backend.is_busy() and not deltas.is_empty() and deltas[-1][0] > sent + 100, 30000)
	await wait_until(func() -> bool: return deltas.size() >= 3 and deltas[-1][0] - deltas[0][0] > 0 and service.active_request_id() == request2.request_id, 10000)
	var cancel_at := Time.get_ticks_msec()
	service.cancel(request2.request_id)
	var cancelled := await wait_until(func() -> bool: return responses.size() == 1, 5000)
	check(streaming and cancelled and responses[0].status == Response.Status.CANCELLED, "annullamento a meta' consegnato come CANCELLED")
	print("NPC_AI_STREAMING cancel_delivery_msec=", Time.get_ticks_msec() - cancel_at)
	# dopo l'annullamento il server accetta ancora richieste
	responses.clear()
	var request3: RefCounted = ContextBuilder.build_request(profile, PackedStringArray(facts["allowed"]), null, sid, sid + "/3", 1, "Quanto costa affilare una spada?", [])
	var t3 := Time.get_ticks_msec()
	service.submit(request3, ContextBuilder.to_messages(request3), {"max_tokens": 80})
	var again := await wait_until(func() -> bool: return responses.size() == 1, 60000)
	check(again and responses[0].status == Response.Status.OK, "dopo l'annullamento una nuova richiesta viene servita (%d ms)" % (Time.get_ticks_msec() - t3))
	if again:
		print("NPC_AI_STREAMING text3=", responses[0].text.replace("\n", " / "))
	# arresto: nessun orfano
	var pid: int = backend.pid()
	service.stop()
	check(backend.availability() == Backend.Availability.STOPPED and not OS.is_process_running(pid), "stop(): processo terminato")
	var state_dir := DirAccess.open("user://npc_ai/state")
	var leftover := 0
	if state_dir != null:
		for name in state_dir.get_files():
			if name.begins_with("llama_server_%d_" % OS.get_process_id()):
				leftover += 1
	check(leftover == 0, "file di stato rimosso")
	finish(0 if failures == 0 else 1)

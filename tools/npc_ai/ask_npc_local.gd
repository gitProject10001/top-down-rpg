extends SceneTree
## Manda una o piu' battute al fabbro col backend reale, con la stessa richiesta del laboratorio (profilo,
## fatti consentiti, lore condivisa, storico dei turni precedenti) e stampa le risposte con i tempi e le
## voci di lore scelte: per provare a mano la lore senza aprire il lab. Nessuna memoria viene scritta.
## Run: godot --headless --path . --script res://tools/npc_ai/ask_npc_local.gd -- --text "Quante case ha il borgo?"
##      [--text "..."]... [--model <id>] [--no-lore] [--seed N]
const Service = preload("res://addons/npc_ai/npc_inference_service.gd")
const Llama = preload("res://addons/npc_ai/npc_backend_llama_server.gd")
const Backend = preload("res://addons/npc_ai/npc_backend.gd")
const Manifest = preload("res://addons/npc_ai/npc_package_manifest.gd")
const ContextBuilder = preload("res://addons/npc_ai/npc_context_builder.gd")
const Lore = preload("res://addons/npc_ai/npc_world_lore.gd")
const Response = preload("res://addons/npc_ai/npc_chat_response.gd")
const PROFILE_PATH := "res://assets/npc_ai/blacksmith_profile.tres"
const FACTS_PATH := "res://assets/npc_ai/blacksmith_facts.json"
const WATCHDOG_MSEC := 600000

var texts := PackedStringArray()
var model_id := ""
var use_lore := true
var seed := -1
var service: Node
var backend: RefCounted
var responses: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--text":
				if i + 1 < args.size():
					texts.append(args[i + 1])
					i += 1
			"--model":
				if i + 1 < args.size():
					model_id = args[i + 1]
					i += 1
			"--seed":
				if i + 1 < args.size():
					seed = int(args[i + 1])
					i += 1
			"--no-lore":
				use_lore = false
		i += 1
	if texts.is_empty():
		texts.append("Buongiorno, sei tu il fabbro?")
	call_deferred("run")


func wait_until(pred: Callable, timeout_msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await process_frame
	return pred.call()


func run() -> void:
	var started: int = Time.get_ticks_msec()
	var profile: Resource = load(PROFILE_PATH)
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))
	var allowed := PackedStringArray(facts["allowed"])
	var manifest: RefCounted = Manifest.new()
	manifest.load_from()
	var lore: RefCounted = null
	if use_lore:
		lore = Lore.new()
		if not lore.load_from():
			print("NPC_AI_ASK lore non caricata: ", lore.error)
			quit(1)
			return
	if not manifest.check_runtime()["ok"] or manifest.available_model_ids().is_empty():
		print("NPC_AI_ASK_SKIPPED runtime o modello assenti: python tools/npc_ai/fetch_npc_package.py --all")
		quit(3)
		return
	service = Service.new()
	get_root().add_child(service)
	backend = Llama.new()
	backend.manifest = manifest
	backend.model_id = model_id if model_id != "" else manifest.default_model_id()
	service.set_backend(backend)
	service.response_ready.connect(func(r: RefCounted) -> void: responses.append(r))
	service.start()
	var ready: bool = await wait_until(func() -> bool: return backend.is_ready() or backend.availability() == Backend.Availability.FAILED, manifest.start_timeout_msec() + 15000)
	if not ready or not backend.is_ready():
		print("NPC_AI_ASK backend non pronto: ", backend.failure_reason())
		service.stop()
		quit(1)
		return
	print("NPC_AI_ASK modello=%s lore=%s caricamento=%d ms" % [backend.model_id, "si'" if use_lore else "no", backend.cold_load_msec])
	var sid := "fabbro_bruno:1:ask"
	service.open_session(sid, "fabbro_bruno", 1)
	var history: Array[Dictionary] = []
	var turn := 0
	for text in texts:
		if Time.get_ticks_msec() - started > WATCHDOG_MSEC:
			print("NPC_AI_ASK watchdog")
			break
		turn += 1
		var request: RefCounted = ContextBuilder.build_request(profile, allowed, null, sid, "%s/%d" % [sid, turn], 1, text, history, lore)
		var messages: Array[Dictionary] = ContextBuilder.to_messages(request)
		var params := {"max_tokens": request.limit("max_output_tokens"), "temperature": 0.7}
		if seed >= 0:
			params["seed"] = seed + turn
		responses.clear()
		print("")
		print("GIOCATORE: ", text)
		if lore != null:
			var chosen: Array[Dictionary] = lore.select_entries(profile.npc_id, profile.trade, text, ContextBuilder._recent_user_texts(history))
			var ids := PackedStringArray()
			for e in chosen:
				ids.append(str(e["id"]))
			print("  lore (%d voci, system %d caratteri): %s" % [chosen.size(), str(messages[0]["content"]).length(), ", ".join(ids)])
		else:
			print("  system %d caratteri" % str(messages[0]["content"]).length())
		if service.submit(request, messages, params) != OK:
			print("  rifiutata: ", service.last_reject_code)
			continue
		var done: bool = await wait_until(func() -> bool: return responses.size() == 1, 90000)
		if not done:
			print("  nessuna risposta entro 90 s")
			continue
		var r: RefCounted = responses[0]
		if r.status != Response.Status.OK:
			print("  esito %s (%s)" % [Response.status_name(r.status), r.error_code])
			continue
		print("%s: %s" % [profile.display_name, r.text])
		print("  (primo token %d ms, totale %d ms, %d token)" % [int(r.timings["first_token_msec"]), int(r.timings["total_msec"]), int(r.timings["tokens"])])
		history.append({"role": "user", "text": text})
		history.append({"role": "assistant", "text": r.text})
	service.close_session(sid)
	service.stop()
	await wait_until(func() -> bool: return backend.availability() == Backend.Availability.STOPPED, 5000)
	print("")
	print("NPC_AI_ASK_DONE turni=%d" % turn)
	quit(0)

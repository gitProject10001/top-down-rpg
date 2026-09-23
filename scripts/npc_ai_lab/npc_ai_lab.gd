extends Node
## Laboratorio isolato per l'NPC conversazionale: un fabbro, forme semplici, interfaccia funzionale.
## Parte come scena Godot qualsiasi (F6 o riga di comando) senza cambiare main scene, autoload o InputMap:
## l'azione `interact` (E) esiste gia' nel progetto e qui viene solo letta. Tutta la logica riutilizzabile
## sta in addons/npc_ai/; questa scena contiene soltanto composizione, dati del campione e pulsanti di prova.
## Il pannello «stato di gioco» e' una fixture: dimostra che nessuna risposta del modello lo modifica.
const Service := preload("res://addons/npc_ai/npc_inference_service.gd")
const Mock := preload("res://addons/npc_ai/npc_backend_mock.gd")
const Llama := preload("res://addons/npc_ai/npc_backend_llama_server.gd")
const Backend := preload("res://addons/npc_ai/npc_backend.gd")
const Manifest := preload("res://addons/npc_ai/npc_package_manifest.gd")
const Memory := preload("res://addons/npc_ai/npc_memory.gd")
const Lore := preload("res://addons/npc_ai/npc_world_lore.gd")
const Conversation := preload("res://addons/npc_ai/npc_conversation.gd")
const ChatPanel := preload("res://addons/npc_ai/ui/npc_chat_panel.gd")
const Paths := preload("res://addons/npc_ai/npc_ai_paths.gd")
const PROFILE_PATH := "res://assets/npc_ai/blacksmith_profile.tres"
const FACTS_PATH := "res://assets/npc_ai/blacksmith_facts.json"
const UI_LAYER := 40   ## fuori dalla tabella dei layer del gioco (9, 10, 20, 25-28, 30)

## Impostabili prima di add_child (lo smoke test lo fa): cartella della memoria e backend iniziale.
var memory_root := Paths.USER_ROOT.path_join("memory")
var force_mock := false
var auto_start := true

var profile: Resource
var facts: Dictionary = {}
var manifest: RefCounted
var memory: RefCounted
var lore: RefCounted
var service: Node
var conversation: RefCounted
var mock_backend: RefCounted
var local_backend: RefCounted
var panel: Control
var game_state: Dictionary = {}     ## fixture: deve restare identica a game_state_initial
var game_state_initial: Dictionary = {}

var _backend_option: OptionButton
var _model_option: OptionButton
var _runtime_btn: Button
var _talk_btn: Button
var _status_lbl: Label
var _state_lbl: Label
var _event_buttons: Array[Button] = []
var _npc_body: MeshInstance3D
var _bob := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--mock":
			force_mock = true
		elif arg.begins_with("--memory-root="):
			memory_root = arg.substr("--memory-root=".length())
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_size().y < 800:
		DisplayServer.window_set_size(Vector2i(1280, 800))   # pannello di controllo e chat non si sovrappongono
	profile = load(PROFILE_PATH)
	facts = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))
	game_state_initial = (facts.get("game_state_fixture", {}) as Dictionary).duplicate(true)
	game_state = game_state_initial.duplicate(true)
	manifest = Manifest.new()
	manifest.load_from()
	memory = Memory.new()
	memory.setup(profile.npc_id, memory_root)
	memory.load()
	lore = Lore.new()
	if not lore.load_from():
		push_warning("NPC_AI lab: " + lore.error)
	for problem in lore.problems():
		push_warning("NPC_AI lab: lore, " + problem)
	service = Service.new()
	service.name = "NpcInferenceService"
	add_child(service)
	mock_backend = Mock.new()
	local_backend = Llama.new()
	local_backend.manifest = manifest
	conversation = Conversation.new()
	conversation.setup(profile, memory, service, PackedStringArray(facts.get("allowed", [])), lore)
	conversation.bind_owner(self)
	_build_world()
	_build_ui()
	if force_mock or not manifest.check_runtime()["ok"] or manifest.available_model_ids().is_empty():
		use_mock()
	else:
		use_local(manifest.default_model_id(), auto_start)
	_refresh_status()
	if "--self-test" in OS.get_cmdline_user_args():
		_self_test()


## Prova automatica IN FINESTRA con il backend attivo, passando dalla UI (pulsante, casella di testo, Invia,
## anteprima in streaming, Annulla, Chiudi, Arresta runtime). Scrive l'esito in user://npc_ai/logs/.
## Run: godot --path . res://scenes/dev/npc_ai_lab.tscn -- --self-test
func _self_test() -> void:
	var failures := 0
	var lines := PackedStringArray()
	var deadline: int = Time.get_ticks_msec() + manifest.start_timeout_msec() + 30000
	while service.state() != Service.ServiceState.READY and service.state() != Service.ServiceState.FAILED and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if service.state() != Service.ServiceState.READY:
		print("NPC_AI_LAB_SELFTEST failures=1 reason=backend non pronto ", service.describe())
		get_tree().quit(1)
		return
	lines.append("backend: " + str(service.describe()))
	_talk_btn.pressed.emit()
	failures += _expect(conversation.is_open() and panel.visible, "dialogo aperto dal pulsante", lines)
	var view: Vector2 = get_viewport().get_visible_rect().size
	var box: Rect2 = panel.get_child(0).get_global_rect()
	failures += _expect(box.position.y >= 0.0 and box.end.y <= view.y and box.size.y > 100.0, "pannello di chat sullo schermo (%s in %s)" % [box, view], lines)
	panel._input_edit.text = "Buongiorno Bruno, che cosa sai riparare?"
	panel._input_edit.text_submitted.emit(panel._input_edit.text)
	failures += _expect(conversation.state == Conversation.State.WAITING, "invio dalla casella di testo", lines)
	var preview_seen := false
	var until: int = Time.get_ticks_msec() + 60000
	while conversation.state == Conversation.State.WAITING and Time.get_ticks_msec() < until:
		if panel._stream_lbl.text != "":
			preview_seen = true
		await get_tree().process_frame
	failures += _expect(conversation.state == Conversation.State.RESPONDED, "risposta via UI (%s)" % Conversation.state_name(conversation.state), lines)
	failures += _expect(preview_seen, "anteprima in streaming comparsa nel pannello", lines)
	lines.append("RISPOSTA: " + str(conversation.transcript[-1]["text"]))
	lines.append("INFO: " + panel._info_lbl.text)
	panel._input_edit.text = "Raccontami per filo e per segno la storia della tua famiglia e del borgo."
	panel._input_edit.text_submitted.emit(panel._input_edit.text)
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 250:
		await get_tree().process_frame
	panel._cancel_btn.pressed.emit()
	until = Time.get_ticks_msec() + 5000
	while conversation.state == Conversation.State.WAITING and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	failures += _expect(conversation.state == Conversation.State.FALLBACK and str(conversation.transcript[-1]["kind"]) == "npc_interrupted", "annullamento dal pulsante", lines)
	panel._close_btn.pressed.emit()
	failures += _expect(not conversation.is_open() and not panel.visible, "chiusura dal pulsante", lines)
	failures += _expect(game_state_unchanged(), "stato di gioco invariato", lines)
	_runtime_btn.pressed.emit()   # Arresta runtime
	until = Time.get_ticks_msec() + 5000
	while local_backend.availability() != Backend.Availability.STOPPED and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	failures += _expect(local_backend.availability() == Backend.Availability.STOPPED and local_backend.pid() == -1, "runtime fermato dal pulsante", lines)
	DirAccess.make_dir_recursive_absolute("user://npc_ai/logs")
	var out := "user://npc_ai/logs/lab_selftest_%d.txt" % int(Time.get_unix_time_from_system())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
	print("NPC_AI_LAB_SELFTEST failures=", failures, " transcript=", ProjectSettings.globalize_path(out))
	get_tree().quit(0 if failures == 0 else 1)


func _expect(ok: bool, label: String, lines: PackedStringArray) -> int:
	lines.append(("OK    " if ok else "ERROR ") + label)
	if not ok:
		push_error("NPC_AI_LAB_SELFTEST: " + label)
	return 0 if ok else 1


func _process(delta: float) -> void:
	_bob += delta
	if _npc_body != null:
		_npc_body.position.y = 1.0 + sin(_bob * 1.6) * 0.02
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if conversation.is_open():
			close_dialogue()
		else:
			open_dialogue()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if conversation != null and conversation.is_open():
			conversation.close()
		if service != null:
			service.stop()


# --------------------------------------------------------------------------------------------
# API del laboratorio (usata anche dallo smoke test)
# --------------------------------------------------------------------------------------------
func use_mock() -> void:
	if service.backend() != mock_backend:
		service.set_backend(mock_backend)
	service.start()
	panel.set_backend_badge("FINTO")
	_sync_backend_option(0)


func use_local(model_id := "", start_now := true) -> void:
	if model_id != "":
		local_backend.model_id = model_id
	if service.backend() != local_backend:
		service.set_backend(local_backend)
	if start_now:
		service.start()
	panel.set_backend_badge("LOCALE")
	_sync_backend_option(1)


func start_runtime() -> void:
	if service.backend() == local_backend:
		if local_backend.availability() == Backend.Availability.FAILED or local_backend.availability() == Backend.Availability.STOPPED:
			local_backend._set_availability(Backend.Availability.UNAVAILABLE, "")
		service.start()


func stop_runtime() -> void:
	if service.backend() == local_backend:
		service.stop()


func open_dialogue() -> void:
	if conversation.is_open():
		return
	conversation.open()
	panel.visible = true
	panel.bind(conversation, service)
	panel.focus_input()


func close_dialogue() -> void:
	if not conversation.is_open():
		return
	conversation.close()
	panel.unbind()
	panel.visible = false


func send_text(text: String) -> bool:
	return conversation.send(text)


func cancel_dialogue() -> void:
	conversation.cancel()


func confirm_event(index: int) -> bool:
	var events: Array = facts.get("canonical_events_available", [])
	if index < 0 or index >= events.size():
		return false
	var e: Dictionary = events[index]
	return conversation.confirm_event(str(e["id"]), str(e["text"]), int(e.get("day", 0)))


func reset_memory() -> void:
	conversation.reset_memory()


func game_state_unchanged() -> bool:
	return game_state == game_state_initial


# --------------------------------------------------------------------------------------------
# Scena 3D: forme semplici, nessun nuovo lavoro artistico
# --------------------------------------------------------------------------------------------
func _build_world() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.18, 0.22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var env := WorldEnvironment.new()
	env.environment = environment
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 16)
	floor.mesh = plane
	floor.material_override = _flat(Color(0.36, 0.3, 0.24))
	world.add_child(floor)
	_npc_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	_npc_body.mesh = capsule
	_npc_body.position = Vector3(0, 1.0, 0)
	_npc_body.material_override = _flat(Color(0.55, 0.32, 0.2))
	world.add_child(_npc_body)
	var tag := Label3D.new()
	tag.text = "%s, %s\n[E] parla" % [profile.display_name, profile.trade]
	tag.position = Vector3(0, 2.35, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 48
	tag.pixel_size = 0.006
	tag.modulate = Color(1.0, 0.9, 0.7)
	world.add_child(tag)
	var anvil := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 0.5, 0.5)
	anvil.mesh = box
	anvil.position = Vector3(1.4, 0.55, 0.2)
	anvil.material_override = _flat(Color(0.25, 0.26, 0.3))
	world.add_child(anvil)
	var stand := MeshInstance3D.new()
	var stump := CylinderMesh.new()
	stump.top_radius = 0.35
	stump.bottom_radius = 0.4
	stump.height = 0.6
	stand.mesh = stump
	stand.position = Vector3(1.4, 0.3, 0.2)
	stand.material_override = _flat(Color(0.42, 0.3, 0.18))
	world.add_child(stand)
	var forge := MeshInstance3D.new()
	var forge_box := BoxMesh.new()
	forge_box.size = Vector3(2.0, 1.2, 1.2)
	forge.mesh = forge_box
	forge.position = Vector3(-1.8, 0.6, -1.2)
	forge.material_override = _flat(Color(0.35, 0.33, 0.32))
	world.add_child(forge)
	var glow := OmniLight3D.new()
	glow.position = Vector3(-1.8, 1.3, -0.4)
	glow.light_color = Color(1.0, 0.55, 0.25)
	glow.light_energy = 2.5
	glow.omni_range = 5.0
	world.add_child(glow)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(6.0, 4.6, 5.2)
	camera.fov = 42
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(-2.2, 1.1, 0.4), Vector3.UP)   # il fabbro resta a destra, libero dal pannello di controllo


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


# --------------------------------------------------------------------------------------------
# UI di controllo: pannello di prova a sinistra, pannello di chat riutilizzabile in basso
# --------------------------------------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = UI_LAYER
	add_child(layer)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.05, 0.08, 0.9)))
	box.anchor_left = 0.0
	box.anchor_top = 0.0
	box.anchor_right = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = 16
	box.offset_top = 16
	box.offset_right = 470
	box.offset_bottom = 16
	layer.add_child(box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	box.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "Laboratorio NPC — %s il %s" % [profile.display_name, profile.trade]
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.5))
	vb.add_child(title)
	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 13)
	vb.add_child(_status_lbl)
	_state_lbl = Label.new()
	_state_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_lbl.add_theme_font_size_override("font_size", 13)
	_state_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 0.65))
	vb.add_child(_state_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	_backend_option = OptionButton.new()
	_backend_option.add_item("Backend finto (deterministico)", 0)
	_backend_option.add_item("Backend locale (llama-server)", 1)
	_backend_option.item_selected.connect(_on_backend_selected)
	row.add_child(_backend_option)
	_model_option = OptionButton.new()
	for id in manifest.model_ids():
		var available: bool = manifest.check_model(id)["ok"]
		_model_option.add_item(id + ("" if available else " (assente)"))
		_model_option.set_item_disabled(_model_option.item_count - 1, not available)
	var default_index: int = manifest.model_ids().find(manifest.default_model_id())
	if default_index >= 0:
		_model_option.select(default_index)
	_model_option.item_selected.connect(_on_model_selected)
	row.add_child(_model_option)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	vb.add_child(row2)
	_runtime_btn = Button.new()
	_runtime_btn.text = "Avvia runtime"
	_runtime_btn.pressed.connect(_on_runtime_pressed)
	row2.add_child(_runtime_btn)
	_talk_btn = Button.new()
	_talk_btn.text = "Parla col fabbro (E)"
	_talk_btn.pressed.connect(func() -> void: close_dialogue() if conversation.is_open() else open_dialogue())
	row2.add_child(_talk_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset memoria"
	reset_btn.pressed.connect(reset_memory)
	row2.add_child(reset_btn)

	var events_title := Label.new()
	events_title.text = "Eventi confermabili dal gioco (unico ingresso in canon):"
	events_title.add_theme_font_size_override("font_size", 13)
	vb.add_child(events_title)
	var events: Array = facts.get("canonical_events_available", [])
	for i in events.size():
		var b := Button.new()
		b.text = "Conferma: " + str(events[i]["id"])
		b.tooltip_text = str(events[i]["text"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: confirm_event(i))
		vb.add_child(b)
		_event_buttons.append(b)

	panel = ChatPanel.new()
	panel.name = "NpcChatPanel"
	panel.visible = false
	panel.send_requested.connect(func(text: String) -> void: send_text(text))
	panel.cancel_requested.connect(cancel_dialogue)
	panel.close_requested.connect(close_dialogue)
	layer.add_child(panel)


func _on_backend_selected(index: int) -> void:
	if index == 0:
		use_mock()
	else:
		use_local(_selected_model_id(), true)


func _on_model_selected(_index: int) -> void:
	if service.backend() == local_backend:
		service.stop()
		local_backend._set_availability(Backend.Availability.UNAVAILABLE, "")
		use_local(_selected_model_id(), true)


func _on_runtime_pressed() -> void:
	if service.backend() != local_backend:
		return
	var a: int = local_backend.availability()
	if a == Backend.Availability.READY or a == Backend.Availability.STARTING:
		stop_runtime()
	else:
		start_runtime()


func _selected_model_id() -> String:
	var ids: PackedStringArray = manifest.model_ids()
	var index := _model_option.selected
	return ids[index] if index >= 0 and index < ids.size() else manifest.default_model_id()


func _sync_backend_option(index: int) -> void:
	if _backend_option != null and _backend_option.selected != index:
		_backend_option.select(index)


func _refresh_status() -> void:
	if _status_lbl == null:
		return
	var b: RefCounted = service.backend()
	var d: Dictionary = b.describe() if b != null else {}
	var lines := PackedStringArray()
	lines.append("Servizio: %s | backend: %s | modello: %s" % [Service.state_name(service.state()), d.get("backend", "-"), d.get("model", "-")])
	if b == local_backend:
		lines.append("Runtime: %s | porta %s | pid %s | ngl %s | caricamento %s ms" % [d.get("availability", "-"), d.get("port", "-"), d.get("pid", "-"), d.get("gpu_layers", "-"), d.get("cold_load_msec", "-")])
		if str(d.get("reason", "")) != "":
			lines.append("Motivo: " + str(d.get("reason", "")))
		if _runtime_btn != null:
			var a: int = local_backend.availability()
			_runtime_btn.text = "Arresta runtime" if (a == Backend.Availability.READY or a == Backend.Availability.STARTING) else "Avvia runtime"
	else:
		lines.append("Runtime: non usato (backend finto).")
	_status_lbl.text = "\n".join(lines)
	var mem_line := "Memoria %s: %d eventi canonici, %d dichiarazioni, %d scambi (%s) | lore condivisa: %d voci" % [profile.npc_id, memory.canonical_events.size(), memory.player_claims.size(), memory.exchanges.size(), memory.last_load_status, lore.size()]
	var state_line := "Stato di gioco (fixture, deve restare uguale): oro %d, oggetti %s, reputazione %d, quest %s -> %s" % [int(game_state.get("gold", 0)), str(game_state.get("inventory", [])), int(game_state.get("reputation", 0)), str(game_state.get("quests", [])), "INVARIATO" if game_state_unchanged() else "MODIFICATO!"]
	_state_lbl.text = mem_line + "\n" + state_line
	if _talk_btn != null:
		_talk_btn.text = "Chiudi dialogo (E)" if conversation.is_open() else "Parla col fabbro (E)"


func _panel_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = Color(1.0, 0.82, 0.5, 0.35)
	s.set_content_margin_all(4)
	return s

extends Node
## One scene-owned service; gameplay pauses, UI and inference continue.
signal dialogue_changed(opened: bool)
const Service=preload("res://addons/npc_ai/npc_inference_service.gd")
const Conversation=preload("res://addons/npc_ai/npc_conversation.gd")
const Memory=preload("res://addons/npc_ai/npc_memory.gd")
const Lore=preload("res://addons/npc_ai/npc_world_lore.gd")
const Manifest=preload("res://addons/npc_ai/npc_package_manifest.gd")
const Backend=preload("res://addons/npc_ai/npc_backend_llama_server.gd")
const DialoguePanel=preload("res://addons/npc_ai/ui/npc_dialogue_panel.gd")
var service: Node
var panel: Control
var prompt: Label
var player: CharacterBody3D
var actors: Array[Node3D]=[]
var conversations: Dictionary={}
var nearest: Node3D
var active: Node3D
var previous_pause:=false
var started:=false
var memory_root:="user://npc_ai/memory"
var force_fallback:=false
var configured:=false
var camera: Camera3D
var camera_state: Dictionary={}
func configure(view: Node, actor_player: CharacterBody3D, view_camera: Camera3D = null) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	player=actor_player
	camera=view_camera
	service=Service.new(); service.name="NpcInferenceService"; add_child(service)
	var manifest:=Manifest.new(); manifest.load_from()
	if not force_fallback:
		var backend:=Backend.new(); backend.manifest=manifest; backend.model_id=manifest.default_model_id(); service.set_backend(backend)
	var lore:=Lore.new(); lore.load_from("res://assets/npc_ai/integrated_lore.json")
	for actor in view.get_node("ConversationalNPCs").get_children():
		if actor.profile==null or not actor.profile.is_valid(): continue
		if conversations.has(actor.profile.npc_id):
			push_error("Duplicate NPC identity: "+actor.profile.npc_id)
			continue
		actors.append(actor)
		var memory:=Memory.new(); memory.setup(actor.profile.npc_id,memory_root); memory.load()
		var conversation:=Conversation.new()
		conversation.setup(actor.profile,memory,service,PackedStringArray(),lore)
		conversations[actor.profile.npc_id]=conversation
		actor.tree_exiting.connect(actor_removed.bind(actor))
	var ui:=CanvasLayer.new(); ui.layer=20; add_child(ui)
	panel=DialoguePanel.new(); ui.add_child(panel); panel.hide()
	panel.send_requested.connect(send_text); panel.cancel_requested.connect(cancel); panel.close_requested.connect(close_dialogue)
	prompt=Label.new(); prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position=Vector2(-180,-70); prompt.size=Vector2(360,35); prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color",Color(1,.88,.6)); prompt.add_theme_font_size_override("font_size",19)
	ui.add_child(prompt); prompt.hide()
	await get_tree().physics_frame
	for actor in actors: actor.snap_to_ground()
	configured=true
func _process(_delta: float) -> void:
	if not configured or not is_instance_valid(player): return
	if is_instance_valid(active):
		var c: RefCounted=conversations[active.profile.npc_id]
		panel.update_status(c.state==Conversation.State.WAITING,service.state()==Service.ServiceState.STARTING,not service.is_ready() or c.state==Conversation.State.FALLBACK)
		return
	nearest=find_nearest()
	prompt.visible=is_instance_valid(nearest) and not get_tree().paused
	if nearest: prompt.text="E — Parla con "+nearest.profile.display_name
func find_nearest() -> Node3D:
	var best: Node3D; var distance:=2.0
	for actor in actors:
		if not is_instance_valid(actor): continue
		var flat:=actor.global_position-player.global_position; flat.y=0
		if flat.length()>distance: continue
		var ray:=PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*.9,actor.global_position+Vector3.UP*.9,1,[player.get_rid(),actor.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		distance=flat.length(); best=actor
	return best
func try_interact() -> bool:
	if not configured or active: return false
	var legacy:=get_node_or_null("/root/Dialogue")
	if legacy and legacy.get("active")==true: return false
	nearest=find_nearest()
	if not nearest: return false
	open_dialogue(nearest); return true
func open_dialogue(actor: Node3D) -> void:
	if not actors.has(actor): return
	if active: close_dialogue()
	active=actor; previous_pause=get_tree().paused
	player.velocity=Vector3.ZERO
	get_tree().paused=true
	if is_instance_valid(camera):
		camera_state={"target":camera._target,"focus":camera._focus,"have_focus":camera._have_focus}
		camera._target=null
		camera._focus=(actor.global_position+player.global_position)*.5-Vector3.UP*4
		camera._have_focus=true; camera._apply(true)
	dialogue_changed.emit(true)
	if not started:
		started=true; service.start()
	var c: RefCounted=conversations[actor.profile.npc_id]
	panel.show(); panel.bind(c,actor.profile,actor.topics); c.open(); prompt.hide()
func send_text(text: String) -> void:
	if is_instance_valid(active): conversations[active.profile.npc_id].send(text)
func cancel() -> void:
	if is_instance_valid(active): conversations[active.profile.npc_id].cancel()
func close_dialogue() -> void:
	if active==null: return
	var c: RefCounted=conversations.get(active.profile.npc_id)
	if c: c.close()
	active=null
	panel.unbind(); panel.hide()
	for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
	if is_instance_valid(player):
		player.velocity=Vector3.ZERO
		if player.get("_attack_buffer_until")!=null: player.set("_attack_buffer_until",0.0)
	if is_instance_valid(camera) and not camera_state.is_empty():
		camera._target=camera_state.target; camera._focus=camera_state.focus; camera._have_focus=camera_state.have_focus
		camera._apply(true); camera_state.clear()
	get_tree().paused=previous_pause
	dialogue_changed.emit(false)
func _input(event: InputEvent) -> void:
	# Own the displayed interaction before the SubViewport/UI can consume E.
	if not active and not get_tree().paused and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_E:
		var focus:=get_viewport().gui_get_focus_owner()
		if not (focus is LineEdit or focus is TextEdit) and try_interact():
			get_viewport().set_input_as_handled()
			return
	if active and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled(); call_deferred("close_dialogue")
func actor_removed(actor: Node3D) -> void:
	if active==actor: close_dialogue()
	var c: RefCounted=conversations.get(actor.profile.npc_id)
	if c: c.close(); c._disconnect_service()
	conversations.erase(actor.profile.npc_id); actors.erase(actor)
func _exit_tree() -> void:
	if active: close_dialogue()
	for c in conversations.values(): c.close(); c._disconnect_service()
	if is_instance_valid(service): service.stop()
	conversations.clear()

extends Node3D
## A repeatable encounter on existing meadow geometry. No separate arena world.
@export var arena_center:=Vector3(-22,.18,10)
@export var enemy_count:=4
@export var hud_enabled:=true
var player: Player
var view: Node
var director: Node
var fighters: Array[Player]=[]
var status: Label
var _resetting:=false
var _chain_until:=0.0
var _chain_step:=0
const OFFSETS: Array[Vector3]=[Vector3(-3.2,0,-1.5),Vector3(1,0,-2.4),Vector3(3.8,0,1.5),Vector3(-.4,0,3.7)]

func configure(world_view: Node, hero: Player) -> void:
	view=world_view
	player=hero
	var layer:=CanvasLayer.new()
	layer.name="EncounterHUD"
	add_child(layer)
	layer.visible=hud_enabled
	var panel:=Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	status=Label.new()
	panel.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	status.offset_left=-355
	status.offset_top=-62
	status.offset_right=-16
	status.offset_bottom=-12
	status.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	status.add_theme_font_size_override("font_size",17)
	status.add_theme_color_override("font_shadow_color",Color(.05,.04,.03))
	status.add_theme_constant_override("shadow_offset_x",1)
	status.add_theme_constant_override("shadow_offset_y",1)
	var attack:=player.get_node("StateMachine/Attack")
	if attack.has_signal("combo_step_started"):
		attack.combo_step_started.connect(func(index: int,_direction: int,_clip: String):
			_chain_step=index+1
			_chain_until=Time.get_ticks_msec()*.001+.85)
	call_deferred("reset_encounter",false)

func reset_encounter(move_player:=true) -> void:
	if _resetting or not is_instance_valid(player): return
	_resetting=true
	for enemy in fighters:
		if is_instance_valid(enemy):
			enemy.process_mode=Node.PROCESS_MODE_DISABLED
			enemy.queue_free()
	fighters.clear()
	if is_instance_valid(director): director.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree(): return
	if move_player:
		player.intent.clear()
		player.sword.cancel_swing()
		player.health.revive()
		player.stamina=player.max_stamina
		player._attack_buffer_until=0.0
		player._dash_ready_at=0.0
		player.get_node("StateMachine").transition_to("Idle")
		var entry:=free_ground(arena_center+Vector3(0,0,6))
		if entry.is_finite(): player.global_position=entry
		player.velocity=Vector3.ZERO
		player.health.extend_invulnerable(.7)
		var camera:=view.get_node_or_null("IsoCam")
		if camera: camera._apply(true)
	director=load("res://scripts/combat/pack_director.gd").new()
	director.name="PackDirector"
	add_child(director)
	director.configure(player,arena_center)
	var scene: PackedScene=load("res://scenes/enemy_raider.tscn")
	for index in mini(enemy_count,OFFSETS.size()):
		var spawn:=free_ground(arena_center+OFFSETS[index])
		if not spawn.is_finite():
			push_warning("No free meadow position for encounter fighter %d"%index)
			continue
		var enemy:=scene.instantiate() as Player
		enemy.name="Predone_%d"%(index+1)
		add_child(enemy)
		enemy.global_position=spawn
		enemy.get_node("DuelBrain").configure(director,player)
		var palette:=view.get_node_or_null("VillageCharacterPalette")
		if palette: palette.apply_enemy(enemy)
		var marker:=preload("res://scripts/combat/encounter_marker.gd").new()
		marker.name="CombatMarker"
		enemy.add_child(marker)
		fighters.append(enemy)
	_chain_until=0.0
	_resetting=false

func free_ground(preferred: Vector3) -> Vector3:
	var space:=player.get_world_3d().direct_space_state
	var ground:=view.get_node_or_null("TerrenoComposto/Superficie")
	var capsule:=CapsuleShape3D.new()
	capsule.radius=.46
	capsule.height=1.8
	for ring in 5:
		for spoke in (1 if ring==0 else 12):
			var angle:=spoke*TAU/12.0
			var pos:=preferred+Vector3(cos(angle),0,sin(angle))*ring*.8
			var query:=PhysicsRayQueryParameters3D.create(pos+Vector3.UP*18,pos-Vector3.UP*3,1,[player.get_rid()])
			var hit:=space.intersect_ray(query)
			if hit.is_empty() or hit.normal.y<.85: continue
			if ground and not ground.is_ancestor_of(hit.collider) and not hit.collider.get_meta("art_ground_surface",false): continue
			var wet:=false
			for water in view.get_children():
				if water.has_method("contains_point"):
					var local: Vector3=water.to_local(hit.position)
					if local.y<.3 and water.contains_point(Vector2(local.x,local.z)): wet=true; break
			if wet: continue
			var body:=PhysicsShapeQueryParameters3D.new()
			body.shape=capsule
			body.transform=Transform3D(Basis.IDENTITY,hit.position+Vector3.UP*.98)
			body.collision_mask=1
			body.exclude=[player.get_rid()]
			if not space.intersect_shape(body,1).is_empty(): continue
			return hit.position+Vector3.UP*.95
	return Vector3(INF,INF,INF)

func living_count() -> int:
	var count:=0
	for enemy in fighters:
		if is_instance_valid(enemy) and enemy.health.is_alive(): count+=1
	return count

func _process(_delta: float) -> void:
	if not is_instance_valid(status) or not is_instance_valid(player): return
	if not player.health.is_alive():
		status.text="Sei caduto · R per riprovare"
		return
	var count:=living_count()
	status.text=("Nemici: %d · R ricomincia"%count) if count>0 else "Gruppo sconfitto · R ricomincia"
	if _resetting: status.text="Preparazione incontro…"
	elif Time.get_ticks_msec()*.001<_chain_until: status.text+="\nCombo %d / 3"%_chain_step
	else: status.text+="\n4 raggiungi il combattimento"

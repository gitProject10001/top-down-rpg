@tool
extends Node3D
var waters: Array=[]
var player: CharacterBody3D
var camera: Camera3D
var overview:=false
var _overview_fov:=0.0
var _overview_size:=17.5
var cooldown:=0.0
var plans: Array=[]
var interior_states: Dictionary={}
var nearest_door: Node3D
var art_direction = preload("res://scripts/village/anime_art_direction.gd").new()
var _editor_helpers: Array[Node] = []
var _preview_busy := false
var _art_refresh_pending := false
var _house_art_pending: Dictionary={}
@export var art_preview_center := Vector3(-9,1,24)
@export var combat_encounter_enabled:=true
var combat_encounter: Node3D

func _notification(what: int) -> void:
    if not Engine.is_editor_hint(): return
    if what==NOTIFICATION_EDITOR_PRE_SAVE: art_direction.apply(false)
    elif what==NOTIFICATION_EDITOR_POST_SAVE: art_direction.apply(true)

func _ready() -> void:
    if Engine.is_editor_hint():
        call_deferred("setup_editor_preview")
        return
    var rig=load("res://scenes/dev/gameplay_preview_rig.tscn").instantiate()
    var view=rig.get_node("Pixel/View")
    for child in get_children():
        remove_child(child);view.add_child(child)
        if child.has_method("set_simulation"):waters.append(child)
    player=view.get_node("Player");player.position=Vector3(-42,1,10)
    camera=view.get_node("IsoCam")
    add_child(rig)
    for water in waters:
        water.set_simulation(true)
        local_patch(water)
    for node in view.find_children("InteriorPlan","Node3D",true,false):plans.append(node)
    var layers = view.get_node_or_null("ArtStudyLayers")
    art_direction.configure(view,layers.profile if layers else null)
    connect_art_geometry(view)
    if layers: layers.regeneration_requested.connect(regenerate_art)
    art_direction.apply(not "--original-art" in OS.get_cmdline_user_args())
    if combat_encounter_enabled and not "--no-enemies" in OS.get_cmdline_user_args():
        combat_encounter=preload("res://scripts/combat/integrated_encounter.gd").new()
        combat_encounter.name="MeadowEncounter"
        view.add_child(combat_encounter)
        combat_encounter.configure(view,player)
    var ui:=CanvasLayer.new();add_child(ui)
    var label:=Label.new();label.position=Vector2(20,20);label.text="SCENA INTEGRATA
WASD movimento · click combo · tieni premuto carica · destro parata · Shift schivata
4 combattimento · R ricomincia · O panoramica · F7 stile · P filtro pittorico · 1 città / 2 guado / 3 lago / 5 borgo · E porta · F acqua"
    ui.add_child(label)
    if "--capture-integrated" in OS.get_cmdline_user_args():
        if "--river-view" in OS.get_cmdline_user_args():player.position=Vector3(3,1,21)
        if "--interior-view" in OS.get_cmdline_user_args():player.position=Vector3(-40,1,-18)
        await get_tree().create_timer(3).timeout
        if not "--gameplay-view" in OS.get_cmdline_user_args():toggle_overview()
        await get_tree().create_timer(1).timeout
        if "--river-view" in OS.get_cmdline_user_args():
            Input.action_press("move_up")
            await get_tree().create_timer(.6).timeout
            Input.action_release("move_up")
        await RenderingServer.frame_post_draw
        var file:="res://captures/integrated_gameplay.png" if "--gameplay-view" in OS.get_cmdline_user_args() else "res://captures/integrated_landscape.png"
        if "--river-view" in OS.get_cmdline_user_args():file="res://captures/integrated_river.png"
        if "--interior-view" in OS.get_cmdline_user_args():file="res://captures/integrated_interior.png"
        var err:=get_viewport().get_texture().get_image().save_png(file)
        print("INTEGRATED_CAPTURE ",err)
        rig.queue_free()
        await get_tree().process_frame
        await get_tree().process_frame
        get_tree().quit(err)

func regenerate_art(settings: Resource) -> void:
    if Engine.is_editor_hint():
        setup_editor_preview(settings)
    else:
        var view=get_node("GameplayPreviewRig/Pixel/View")
        var active: bool=art_direction.enabled
        art_direction.clear()
        sync_cliff_guides(view)
        art_direction.configure(view,settings)
        art_direction.apply(active)

func connect_art_geometry(view: Node) -> void:
    for house in view.find_children("*","Node3D",true,false):
        if house.has_signal("recipe_applied") and house.has_signal("rebuilt") and not house.has_method("volume_host"):
            var callback:=queue_house_art.bind(house)
            if not house.rebuilt.is_connected(callback): house.rebuilt.connect(callback)
            connect_detail_art(house)
    for child in view.get_children():
        var cliff=child.get_node_or_null("ContinuousCliff")
        if cliff and cliff.has_signal("rebuilt") and not cliff.rebuilt.is_connected(queue_art_refresh):
            cliff.rebuilt.connect(queue_art_refresh)

func connect_detail_art(house: Node3D) -> void:
    var details=house.get_node_or_null("RecipeDetails")
    if not details: return
    var callback:=queue_house_art.bind(house)
    for detail in details.get_children():
        if detail.has_signal("rebuilt") and not detail.rebuilt.is_connected(callback): detail.rebuilt.connect(callback)

func queue_house_art(house: Node3D) -> void:
    if _house_art_pending.is_empty(): call_deferred("refresh_house_art")
    _house_art_pending[house.get_instance_id()]=house

func refresh_house_art() -> void:
    var houses:=_house_art_pending.values()
    _house_art_pending.clear()
    for house in houses:
        if not is_instance_valid(house) or not house.is_inside_tree(): continue
        connect_detail_art(house)
        var plan=house.get_node_or_null("InteriorPlan")
        if plan and not Engine.is_editor_hint():
            var state: Vector2i=interior_states.get(plan.get_instance_id(),Vector2i.ZERO)
            house.set_cutaway(state.x==1,state.y*plan.floor_height,plan.floor_height)
        art_direction.refresh_architecture(house)

func sync_cliff_guides(view: Node) -> void:
    for child in view.get_children():
        var cliff=child.get_node_or_null("ContinuousCliff")
        if cliff and child is Path3D and cliff.guide!=child.curve:
            cliff.guide=child.curve
            cliff.rebuild()

func queue_art_refresh() -> void:
    if _art_refresh_pending or _preview_busy: return
    _art_refresh_pending=true
    call_deferred("refresh_art_geometry")

func refresh_art_geometry() -> void:
    _art_refresh_pending=false
    var view: Node=self if Engine.is_editor_hint() else get_node_or_null("GameplayPreviewRig/Pixel/View")
    if view==null: return
    var layers=view.get_node_or_null("ArtStudyLayers")
    if layers: regenerate_art(layers.profile)

func setup_editor_preview(settings: Resource = null) -> void:
    if _preview_busy or not is_inside_tree(): return
    _preview_busy=true
    art_direction.clear()
    var layers = get_node_or_null("ArtStudyLayers")
    if layers:
        if not layers.regeneration_requested.is_connected(regenerate_art):
            layers.regeneration_requested.connect(regenerate_art)
        if settings==null: settings=layers.profile
        if not layers.preview_enabled:
            _preview_busy=false
            return
    if _editor_helpers.is_empty():
        var rig=load("res://scenes/dev/gameplay_preview_rig.tscn").instantiate()
        var source=rig.get_node("Pixel/View")
        for child_name in ["WorldEnvironment","Sun","SoftSkyFill","IsoCam","PixelSnap"]:
            var helper=source.get_node(child_name)
            helper.owner=null
            source.remove_child(helper)
            add_child(helper,false,Node.INTERNAL_MODE_BACK)
            _editor_helpers.append(helper)
        rig.free()
    sync_cliff_guides(self)
    art_direction.configure(self,settings)
    connect_art_geometry(self)
    art_direction.grass.editor_center=art_preview_center
    art_direction.apply(true)
    _preview_busy=false
func toggle_overview() -> void:
    if not is_instance_valid(camera): return
    overview=not overview;camera.set_process(not overview);camera.set_physics_process(not overview)
    if overview:
        _overview_fov=camera.perspective_fov
        _overview_size=camera.ortho_size
        camera.perspective_fov=0.0
        camera.size=145;camera.global_position=Vector3(105,150,105);camera.look_at(Vector3(0,0,-5))
        camera.near=.05
        camera.far=500.0
        camera._preserve_focus_shadows(camera.global_position.distance_to(Vector3(0,0,-5)))
    else:
        camera.ortho_size=_overview_size
        camera.size=_overview_size
        camera.perspective_fov=_overview_fov
        camera._apply(true)
func _unhandled_key_input(event: InputEvent) -> void:
    if Engine.is_editor_hint(): return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode==KEY_F7:
            art_direction.apply(not art_direction.enabled)
            print("ART_DIRECTION ", "anime dipinto" if art_direction.enabled else "originale")
        if event.keycode==KEY_E and is_instance_valid(nearest_door):nearest_door.toggle(player.global_position)
        # F8 is Godot's Stop shortcut when launched through its debugger. O works
        # in both editor and standalone; retain F8 only for standalone sessions.
        var overview_key: bool=event.keycode==KEY_O or (event.keycode==KEY_F8 and not EngineDebugger.is_active())
        if overview_key and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
            toggle_overview()
            get_viewport().set_input_as_handled()
        if event.keycode==KEY_F:
            for water in waters:water.debug_flow=not water.debug_flow
        if event.keycode in [KEY_1,KEY_2,KEY_3]:
            player.position=[Vector3(-42,1,10),Vector3(3,1,21),Vector3(34,1,-9)][event.keycode-KEY_1]
        if event.keycode==KEY_5:
            if overview: toggle_overview()
            player.position=Vector3(27,1,24)
            player.velocity=Vector3.ZERO
        if event.keycode in [KEY_4,KEY_R] and is_instance_valid(combat_encounter):
            if overview: toggle_overview()
            combat_encounter.call_deferred("reset_encounter",true)
func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint(): return
    if not is_instance_valid(player):return
    for water in waters:
        var local: Vector3=water.to_local(player.global_position)
        if water.contains_point(Vector2(local.x,local.z)) and water.wave_field.bounds.get_center().distance_to(Vector2(local.x,local.z))>7:
            local_patch(water)
    nearest_door=null
    var closest:=2.3
    for plan in plans:
        var house=plan.house()
        var p: Vector3=house.to_local(player.global_position)
        var inside: bool=house.contains_footprint(p,.12) and p.y>-.5 and p.y<house.wall_height
        var floor_index: int=clampi(floori(maxf(0,p.y-.8)/plan.floor_height),0,maxi(0,plan.levels().size()-1))
        var state:=Vector2i(int(inside),floor_index)
        if interior_states.get(plan.get_instance_id(),Vector2i(-1,-1))!=state:
            house.set_cutaway(inside,floor_index*plan.floor_height,plan.floor_height)
            interior_states[plan.get_instance_id()]=state
        plan.runtime_view(inside,floor_index,player.global_position,camera.global_position)
        for door in house.find_children("*","AnimatableBody3D",true,false):
            if not door.has_method("toggle"):continue
            var distance: float=door.global_position.distance_to(player.global_position)
            door.set_highlight(distance<2.3)
            if distance<closest:closest=distance;nearest_door=door
    cooldown-=delta
    if cooldown<=0 and player.is_on_floor() and player.velocity.length()>.2:
        for water in waters:water.disturb(player.global_position,player.velocity)
        cooldown=.15

func local_patch(water: Node3D) -> void:
    var p: Vector3=water.to_local(player.global_position)
    var center:=Vector2(p.x,p.z).snapped(Vector2(4,4))
    water.wave_field.bounds=Rect2(center-Vector2.ONE*12,Vector2.ONE*24)
    water.wave_field.configure(water.boundary,water.obstacles)
    water.wave_field.bake_flow(water.flow_at)
    water._bind_simulation()

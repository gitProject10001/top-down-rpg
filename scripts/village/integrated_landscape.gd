extends Node3D
var waters: Array=[]
var player: CharacterBody3D
var camera: Camera3D
var overview:=false
var cooldown:=0.0
var plans: Array=[]
var interior_states: Dictionary={}
var nearest_door: Node3D
func _ready() -> void:
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
    var ui:=CanvasLayer.new();add_child(ui)
    var label:=Label.new();label.position=Vector2(20,20);label.text="SCENA INTEGRATA · strumenti esistenti
WASD movimento · F8 panoramica · F campo acqua · 1 città / 2 guado / 3 lago · E porta"
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
func toggle_overview() -> void:
    overview=not overview;camera.set_process(not overview);camera.set_physics_process(not overview)
    if overview:
        camera.size=145;camera.global_position=Vector3(105,150,105);camera.look_at(Vector3(0,0,-5))
    else:camera.size=17.5
func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode==KEY_E and is_instance_valid(nearest_door):nearest_door.toggle(player.global_position)
        if event.keycode==KEY_F8:toggle_overview()
        if event.keycode==KEY_F:
            for water in waters:water.debug_flow=not water.debug_flow
        if event.keycode in [KEY_1,KEY_2,KEY_3]:
            player.position=[Vector3(-42,1,10),Vector3(3,1,21),Vector3(34,1,-9)][event.keycode-KEY_1]
func _physics_process(delta: float) -> void:
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

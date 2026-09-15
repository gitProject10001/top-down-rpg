extends Node3D
var waters: Array=[]
var player: CharacterBody3D
var camera: Camera3D
var overview:=false
var cooldown:=0.0
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
        if water.name=="Lago":
            water.wave_field.bounds=Rect2(-25,-25,50,50)
            water.wave_field.configure(water.boundary,water.obstacles)
            water.wave_field.bake_flow(water.flow_at)
            water._bind_simulation()
    var ui:=CanvasLayer.new();add_child(ui)
    var label:=Label.new();label.position=Vector2(20,20);label.text="SCENA INTEGRATA · strumenti esistenti
WASD movimento · F8 panoramica · F campo acqua · 1 città / 2 guado / 3 lago"
    ui.add_child(label)
    if "--capture-integrated" in OS.get_cmdline_user_args():
        await get_tree().create_timer(3).timeout
        if not "--gameplay-view" in OS.get_cmdline_user_args():toggle_overview()
        await get_tree().create_timer(1).timeout
        await RenderingServer.frame_post_draw
        var file:="res://captures/integrated_gameplay.png" if "--gameplay-view" in OS.get_cmdline_user_args() else "res://captures/integrated_landscape.png"
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
        if event.keycode==KEY_F8:toggle_overview()
        if event.keycode==KEY_F:
            for water in waters:water.debug_flow=not water.debug_flow
        if event.keycode in [KEY_1,KEY_2,KEY_3]:
            player.position=[Vector3(-42,1,10),Vector3(3,1,21),Vector3(34,1,-9)][event.keycode-KEY_1]
func _physics_process(delta: float) -> void:
    if not is_instance_valid(player):return
    cooldown-=delta
    if cooldown<=0 and player.is_on_floor() and player.velocity.length()>.2:
        for water in waters:water.disturb(player.global_position,player.velocity)
        cooldown=.15

extends Node3D
@export var water_path := NodePath("LakeAndOutlet")
@export var spawn_position := Vector3(-3,1,6.5)
@export var capture_position := Vector3(-3,.7,2)
@export var capture_file := "res://captures/water_study.png"
var water: Node3D
var player: CharacterBody3D
var _last := Vector3.ZERO
var _cooldown := 0.0
var _wave_label: Label

func _ready() -> void:
    water=get_node(water_path)
    remove_child(water)
    var rig: Node=load("res://scenes/dev/gameplay_preview_rig.tscn").instantiate()
    var view: SubViewport=rig.get_node("Pixel/View")
    view.add_child(water)
    build_bed(view)
    player=view.get_node("Player")
    player.position=spawn_position
    add_child(rig)
    _last=player.global_position
    var ui:=CanvasLayer.new();add_child(ui)
    var label:=Label.new();label.position=Vector2(24,24)
    label.text="ACQUA · W01.1\nWASD: entra nel lago · F: campo di flusso · V: vortice locale"
    if water.river_mode:label.text="FIUME · W02.1\nWASD: movimento · F: frecce della corrente · V: vortice locale"
    ui.add_child(label)
    _wave_label=Label.new();_wave_label.position=Vector2(24,82)
    _wave_label.text="1: calmo · 2: brezza · 3: mosso — Brezza"
    ui.add_child(_wave_label)
    if "--capture-water" in OS.get_cmdline_user_args():
        if "--rough-water" in OS.get_cmdline_user_args():
            water.set_wave_preset(2)
            _wave_label.text="1: calmo · 2: brezza · 3: mosso — Mosso"
        player.position=capture_position
        await get_tree().create_timer(1.5).timeout
        Input.action_press("move_up")
        await get_tree().create_timer(.65).timeout
        Input.action_release("move_up")
        await RenderingServer.frame_post_draw
        var result:=get_viewport().get_texture().get_image().save_png(capture_file)
        print("WATER_CAPTURE ",result)
        get_tree().quit(result)

func build_bed(view: Node) -> void:
    var st:=SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for z in range(-24,25):
        for x in range(-28,29):
            for offset in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
                var p: Vector2=Vector2(x,z)+offset
                var y: float=water.bed_height(p)
                var color:=Color(.28,.32,.16) if y>.12 else Color(.40,.35,.22)
                st.set_color(color)
                st.add_vertex(Vector3(p.x,y,p.y))
    st.generate_normals()
    var ground:=MeshInstance3D.new();ground.name="BasinAndBanks";ground.mesh=st.commit()
    var material:=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.vertex_color_is_srgb=true;material.roughness=1
    ground.material_override=material
    view.add_child(ground)
    ground.create_trimesh_collision()

func _physics_process(delta: float) -> void:
    if not is_instance_valid(player):return
    _cooldown-=delta
    if player.is_on_floor() and player.global_position.distance_to(_last)>.22 and _cooldown<=0:
        water.disturb(player.global_position,player.velocity)
        _last=player.global_position
        _cooldown=.15

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode==KEY_F: water.debug_flow=not water.debug_flow
        if event.keycode==KEY_V: water.vortex_strength=0.0 if water.vortex_strength>0 else .8
        if event.keycode in [KEY_1,KEY_2,KEY_3]:
            var preset: int=event.keycode-KEY_1
            water.set_wave_preset(preset)
            _wave_label.text="1: calmo · 2: brezza · 3: mosso — "+["Calmo","Brezza","Mosso"][preset]

extends Node3D
var water: Node3D
var player: CharacterBody3D
var _last := Vector3.ZERO
var _cooldown := 0.0

func _ready() -> void:
    water=$LakeAndOutlet
    remove_child(water)
    var rig: Node=load("res://scenes/dev/gameplay_preview_rig.tscn").instantiate()
    var view: SubViewport=rig.get_node("Pixel/View")
    view.add_child(water)
    build_bed(view)
    player=view.get_node("Player")
    player.position=Vector3(-3,1,6.5)
    add_child(rig)
    _last=player.global_position
    var ui:=CanvasLayer.new();add_child(ui)
    var label:=Label.new();label.position=Vector2(24,24)
    label.text="ACQUA · W01.1\nWASD: entra nel lago · F: campo di flusso · V: vortice locale"
    ui.add_child(label)
    if "--capture-water" in OS.get_cmdline_user_args():
        player.position=Vector3(-3,.7,2)
        await get_tree().create_timer(1.5).timeout
        Input.action_press("move_up")
        await get_tree().create_timer(.65).timeout
        Input.action_release("move_up")
        await RenderingServer.frame_post_draw
        var result:=get_viewport().get_texture().get_image().save_png("res://captures/water_study.png")
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

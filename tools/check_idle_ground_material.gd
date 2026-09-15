extends SceneTree
var changes:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var village=load("res://addons/village_builder/village.gd").new()
    village.surface_material=ShaderMaterial.new()
    village.surface_material.shader=load("res://shaders/pixelart/ground_clear.gdshader")
    root.add_child(village)
    village.surface_material.changed.connect(func():changes+=1)
    for i in 60:await process_frame
    assert(village._bound_surface_material==village.surface_material)
    village.position=Vector3(8,0,4)
    for i in 2:await process_frame
    assert(village.surface_material.get_shader_parameter("builder_inverse")==village.global_transform.affine_inverse())
    village.surface_material=village.surface_material.duplicate()
    for i in 2:await process_frame
    assert(village._bound_surface_material==village.surface_material)
    print("GROUND_BINDING_PASS transform and material replacement")
    village.free();quit()

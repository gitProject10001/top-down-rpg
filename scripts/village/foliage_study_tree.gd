@tool
extends Node3D
## Imported meshes remain replaceable; Godot owns lighting/wind and collision.
@export_enum("broadleaf", "pine") var species: String = "broadleaf"
@export_range(0.0, 0.3) var wind_strength: float = 0.055

func _ready() -> void:
    var material := ShaderMaterial.new()
    material.shader = preload("res://shaders/pixelart/foliage_study.gdshader")
    material.set_shader_parameter("spray", load("res://assets/models/foliage_study/%s_spray.png" % species))
    material.set_shader_parameter("wind_strength", wind_strength)
    if species == "pine":
        material.set_shader_parameter("shade_color", Color(0.055, 0.17, 0.13))
        material.set_shader_parameter("middle_color", Color(0.22, 0.37, 0.18))
        material.set_shader_parameter("sun_color", Color(0.48, 0.61, 0.27))
    for mesh in find_children("*", "MeshInstance3D"):
        if str(mesh.name).begins_with("Leaves"):
            mesh.material_override = material
            mesh.extra_cull_margin = 0.35

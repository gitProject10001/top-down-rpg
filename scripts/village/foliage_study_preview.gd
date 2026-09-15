extends Node3D

func _ready() -> void:
    $Camera.position = Vector3(12, 16, 25)
    $Camera.look_at(Vector3(0, 4.7, 0))
    $Camera.add_to_group("camera_rig")
    var player := preload("res://scenes/player/player3.tscn").instantiate()
    player.position = Vector3(0, 0.1, 3)
    add_child(player)
    var ui := CanvasLayer.new()
    add_child(ui)
    var label := Label.new()
    label.position = Vector2(24, 24)
    label.text = "ALBERI · STUDIO T01\nLatifoglia / Pino diradato\nWASD: movimento · F6: avvia questa scena"
    ui.add_child(label)
    if "--capture-foliage" in OS.get_cmdline_user_args():
        await get_tree().create_timer(2.0).timeout
        await RenderingServer.frame_post_draw
        var path := "res://captures/foliage_study.png"
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
        var result := get_viewport().get_texture().get_image().save_png(path)
        print("FOLIAGE_CAPTURE ", result)
        get_tree().quit(result)

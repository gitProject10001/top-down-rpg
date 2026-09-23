extends "res://tools/check_action_combat_visual.gd"
func run() -> void:
 scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
 scene.combat_encounter_enabled=false
 get_tree().root.add_child(scene)
 await settle(60)
 var post=scene.get_node("GameplayPreviewRig/Pixel/View/PainterlyPost")
 post.set_panel_open(true)
 check(get_tree().paused,"panel pauses gameplay")
 post.depth_blur=true
 for i in 4:await get_tree().process_frame
 check(post._attributes.dof_blur_far_enabled,"depth blur enabled")
 check(post._attributes.dof_blur_far_distance>post._attributes.dof_blur_near_distance,"focus band ordered")
 var sliders=post.panel.find_children("*","HSlider",true,false)
 check(sliders.size()==9,"all painting and depth parameters exposed")
 sliders[0].value=.4
 check(is_equal_approx(post.get_node("Filter").material.get_shader_parameter("palette_strength"),.4),"slider updates shader")
 await snap("post_controls")
 post.set_panel_open(false)
 check(not get_tree().paused,"closing restores gameplay")
 await settle(10)
 await snap("post_depth_preview")
 print("POST_CONTROLS_RESULT ",failures)
 scene.queue_free()
 await settle(3)
 get_tree().quit(0 if failures.is_empty() else 1)

extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/dev/tower_roof_stair_example.tscn").instantiate(); root.add_child(scene)
	var tower=scene.get_node("TorreOttagonale"); var plan=tower.get_node("InteriorPlan")
	var camera=scene.get_node("Camera"); camera.size=11; camera.look_at(Vector3(0,3.8,0))
	root.msaa_3d=Viewport.MSAA_4X
	for i in 30: await process_frame
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	for inside in [false,true]:
		plan.preview_inside=inside; plan.active_floor=1; plan.editor_view()
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/stair_guards_%s.png"%("interior" if inside else "roof"))
	quit()

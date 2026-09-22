extends "res://tools/check_borgo_recipes.gd"
func run() -> void:
	scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
	scene.combat_encounter_enabled=false
	get_tree().root.add_child(scene)
	get_tree().current_scene=scene
	await settle(35)
	var post: CanvasLayer=scene.get_node("GameplayPreviewRig/Pixel/View/PainterlyPost")
	var house: Node3D=scene.get_node("GameplayPreviewRig/Pixel/View/Borgo/Lotto_StradaBorgo_1_1_1/Edificio")
	var door: Dictionary=house.resolved_opening(house.openings[0])
	var outside: Vector3=house.to_global(house.wall_point(door.wall,door.along,0,1.7))+Vector3.UP*.6
	for active in [false,true]:
		post.enabled=active
		await capture("painterly_on" if active else "painterly_off",outside,22,house.global_position+Vector3.UP*3)
		print("POST_BENCH enabled=",active)
		await performance()
	var key:=InputEventKey.new(); key.pressed=true; key.keycode=KEY_P
	post._unhandled_key_input(key)
	check(not post.enabled and not post.get_node("Filter").visible,"P bypass")
	post._unhandled_key_input(key)
	check(post.enabled and post.get_node("Filter").visible,"P enable")
	print("POST_CHECK ",failures)
	scene.queue_free(); await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

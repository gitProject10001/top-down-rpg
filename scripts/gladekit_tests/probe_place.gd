extends SceneTree
## WHY A MARKER WILL NOT LAND. `GladePlugin._probe()` finds the wall under the cursor by raycasting
## and matching the hit body's RID against every `glade_wall` group member's `collision_rids()`. If
## any link in that chain is broken, a Door/Window/Balcony click warns into the Output panel and
## looks, in the viewport, like nothing happened at all.
##
## This reproduces the chain headlessly, link by link, so the break is named rather than guessed.
##
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/probe_place.gd

const STONE := "res://addons/gladekit/styles/crypt_stone.tres"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var w := GladeWall.new()
	var c := Curve3D.new()
	c.add_point(Vector3(-3, 0, 0))
	c.add_point(Vector3(3, 0, 0))
	w.curve = c
	w.wall_height = 3.0
	w.style = load(STONE)
	root.add_child(w)
	w.rebuild()

	print("[PLACE] wall built: %d pieces, generate_collision=%s" % [w.snap_transforms.size(),
			w.generate_collision])
	print("[PLACE] in group glade_wall: %s" % w.is_in_group("glade_wall"))
	print("[PLACE] collision_rids(): %d" % w.collision_rids().size())

	# The physics server needs a frame before a static body is queryable.
	await physics_frame
	await physics_frame

	var space := (root as Window).world_3d.direct_space_state
	print("[PLACE] space state: %s" % ("ok" if space else "NULL"))
	if space == null:
		quit(1)
		return

	# Aim at the middle of the wall's face, from outside it.
	var target := Vector3(0.0, 1.5, 0.0)
	var from := Vector3(0.0, 1.5, 6.0)
	var q := PhysicsRayQueryParameters3D.create(from, target)
	var hit := space.intersect_ray(q)
	print("[PLACE] raycast at the wall face: %s" % ("HIT" if not hit.is_empty() else "MISS"))
	if hit.is_empty():
		print("[PLACE] >>> the wall has no queryable collision — every marker click will fail")
		quit(1)
		return
	print("        hit.position = %s   collider = %s" % [hit.position, hit.get("collider")])

	# THE ACTUAL TEST: does the plugin's identification step work?
	var rid = hit.get("rid")
	var matched := false
	for n in root.get_tree().get_nodes_in_group("glade_wall"):
		if rid in (n as GladeWall).collision_rids():
			matched = true
			break
	print("[PLACE] rid matched a glade_wall member: %s   %s"
			% [matched, "OK — markers can land" if matched else ">>> BROKEN: this is the bug"])

	# And what a MASS does, since that is what has been under the cursor lately.
	var m := GladeMass.new()
	m.style = load(STONE)
	m.position = Vector3(20, 0, 0)
	root.add_child(m)
	m.rebuild()
	await physics_frame
	await physics_frame
	var mq := PhysicsRayQueryParameters3D.create(Vector3(20, 1.5, 8), Vector3(20, 1.5, 0))
	var mhit := space.intersect_ray(mq)
	print("[PLACE] mass raycast: %s" % ("HIT" if not mhit.is_empty() else "MISS"))
	if not mhit.is_empty():
		var mm := false
		for n in root.get_tree().get_nodes_in_group("glade_wall"):
			if mhit.get("rid") in (n as GladeWall).collision_rids():
				mm = true
		print("        a mass is in group glade_wall: %s   -> _probe().wall would be %s"
				% [m.is_in_group("glade_wall"), "the mass" if mm else "NULL (markers refuse)"])
	quit(0)

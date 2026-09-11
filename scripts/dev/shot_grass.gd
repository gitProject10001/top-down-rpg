extends SceneTree
## Photograph the grass species from THE GAME'S OWN ANGLE.
##
##   Godot_console.exe --path . --resolution 700x500 --script res://scripts/dev/shot_grass.gd -- \
##       --out=C:/some/folder [--species=3]
##
## The angle is not a detail here. Flower heads are HORIZONTAL quads, so they are broadside to the
## game's 53-degree camera and edge-on to a ground-level one — photographed from the side they look
## like nothing was built at all, which cost an afternoon of chasing a bug that was not there.
## The bushes are hidden because the lab's shrub patch shares the grass patch's ground.

const PITCH := 53.0

var _out := "user://"
var _species := 3


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
		elif a.begins_with("--species="):
			_species = a.substr(10).to_int()
	_run()


func _run() -> void:
	var lab := (load("res://scenes/dev/foliage_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for i in 40:
		await process_frame

	var g := lab.get_node("Grass") as GrassPatch
	# Hide EVERYTHING that is not the grass. The lab's shrub patch is a MultiMeshInstance3D added in
	# code, so a "hide the Node3Ds" sweep walks straight past it and it fills the frame.
	for c in lab.get_children():
		if c != g and (c is CanvasLayer or c is VisualInstance3D or c.get_class() == "Node3D"):
			c.visible = false
	g.visible = true

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var d := 5.5
	cam.global_position = Vector3(0.0, 0.3 + sin(deg_to_rad(PITCH)) * d,
			9.0 + cos(deg_to_rad(PITCH)) * d)
	cam.look_at(Vector3(0.0, 0.3, 9.0))

	g.region_size = Vector2(8.0, 7.0)
	g.count = 2600
	g.tuft_height = 0.75
	g.species = _species
	g.flower_chance = 0.25
	g.flower_size = 0.45
	g.flower_color = Color(0.97, 0.95, 0.9)
	g.rebuild()
	for i in 30:
		await process_frame

	var path := _out + "grass_species_%d.png" % _species
	print("[GRASS] species %d -> %s (%s)" % [_species, path,
			"ok" if root.get_texture().get_image().save_png(path) == OK else "FAILED"])
	quit(0)

extends RefCounted
## THE BAKE — the last chapter: the plan as it was after a step, written by the drafter into a
## fresh floorplan plan and built by the façade, in 3D under a fly camera, with a 1.8 m capsule
## at the zone's entrance for scale. `G` in any chapter comes here with that chapter's step, so
## the drill-down is visible in 3D too; the whole tree at its last step is the default.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")

var atlas                                      ## the PaAtlas root, injected
var upto := -1                                 ## −1 = everything
var info := {}
var _built: Node3D


func setup() -> void:
	upto = atlas.bake_upto
	_build()


func teardown() -> void:
	_built = null


func _build() -> void:
	for ch in atlas.stage.get_children():
		ch.queue_free()
	info = atlas.rig.bake(upto)
	_built = info.node
	atlas.stage.add_child(_built)
	# the player, for scale
	var cap := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.25
	mesh.height = 1.8
	cap.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	cap.material_override = mat
	var e: Vector2 = atlas.rig.brief.entrance_point()
	cap.position = Vector3(e.x, 0.9 + 0.2, e.y)
	cap.name = "Player"
	atlas.stage.add_child(cap)
	atlas.frame_at(Vector3(e.x, 0.0, e.y))


func on_step(_dir: int) -> void:
	pass


func build_rows(box: VBoxContainer) -> void:
	var head := Label.new()
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	head.text = "the plan after step %s" % ("the last" if upto < 0 else str(upto))
	box.add_child(head)
	var stat := Label.new()
	stat.add_theme_font_size_override("font_size", 11)
	stat.text = "%d plan nodes · written %s · %.0f ms" % [int(info.get("plan_nodes", 0)), str(info.get("counts", {})), float(info.get("ms", 0.0))]
	box.add_child(stat)
	Tuning.button(box, "bake the whole tree (last step)", func() -> void:
		upto = -1
		_build()
		atlas.refresh())
	Tuning.button(box, "frame the entrance  [F]", func() -> void:
		var e: Vector2 = atlas.rig.brief.entrance_point()
		atlas.frame_at(Vector3(e.x, 0.0, e.y)))
	Tuning.line(box, "RMB + WASD fly · Q/E down/up · Shift ×3. The capsule at the entrance is 1.8 m tall; walls are 4.5 m, the kit's.")
	atlas.show_text("THE BAKE", "res://addons/procedural_architecture/gen/generator.gd",
			"The drafter writes the tree's parts into a fresh plan (rooms as outlines, walls as lines drawn once by their owner, gates as openings, fixtures as props) and the floorplan façade builds it: slabs, walls, doors, props — the same call the Generate button and the headless tool make.")

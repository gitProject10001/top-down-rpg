@tool
extends Database
## A WORLD'S OWN MANIFEST, wherever the world is being played from.
##
## Open World Database finds its `.owdb` beside the CURRENT SCENE: `Database.get_database_path`
## reads `get_tree().current_scene.scene_file_path` and swaps the extension. That is right for a
## game whose world IS the main scene, and wrong for this one — a generated world is a zone that
## `World.go_to` adds under `main.tscn`, so the stock path resolves to `res://scenes/main.owdb`,
## which does not exist. The world would come up with an empty database and stream nothing at
## all, silently: no error, no warning, just a terrain with no buildings on it.
##
## So the path is told, not derived. Everything else about the database is the addon's.

var _path := ""


func _init(owdb: OpenWorldDatabase, path: String) -> void:
	super(owdb)
	_path = path


func get_database_path() -> String:
	return _path

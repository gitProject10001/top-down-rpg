@tool
extends EditorPlugin
## SimWater: registers the authoring nodes. The DRIVER is a project autoload rather than something
## this plugin adds, deliberately - an autoload that appears and disappears with a plugin checkbox
## takes every `Ripples.` call site in the game down with it, and the game's water helpers
## (water.gd, raft.gd, water_wader.gd, waterfall.gd) reference it directly.


func _enter_tree() -> void:
	add_custom_type("SimWaterSource", "Node3D",
			preload("res://addons/sim_water/scripts/sim_water_source.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("SimWaterSource")

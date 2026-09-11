@tool
extends EditorPlugin
## ProceduralAnim registers no editor UI, no custom types and no docks — everything it provides is
## reached through `class_name`, which Godot registers from the script files whether this plugin is
## enabled or not.
##
## So why have a plugin.cfg at all? Because the folder IS the unit: the addon boundary is a promise
## about what may reach in.
##
## THAT PROMISE IS CURRENTLY BROKEN, and pretending otherwise misleads refactors. As of this
## writing ogre_solver.gd preloads a game scene (HIT_SPARK), types fields as the game's HitBox,
## connects to its signals, loads a res:// pose path, and queries the scene tree for the "player"
## group. The autoload references (EventBus, Fx, Water) at least resolve by node path and degrade
## to nothing when absent — the rest do not. The refactor plan moves the offenders out (combat
## geometry, hitbox construction and feedback dispatch are gameplay, not animation); until it
## lands, treat this folder as NOT liftable and this comment as the honest boundary statement.
##
## Enabling it therefore does nothing observable, and that is the point: if turning it off broke
## something, the something would be in the wrong folder.
##
## `addons/sim_water/` made the same move at the same stage and for the same reason.


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass

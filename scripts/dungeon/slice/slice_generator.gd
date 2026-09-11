class_name SliceGenerator
extends DungeonGenerator
## The vertical slice's crypt: the ordinary generator, plus gameplay.
##
## A SUBCLASS RATHER THAN A FLAG on the base generator. zone_crypt.tscn is instantiated by eleven
## test suites across two files and described by three pinned hashes; the guarantee that it is
## unchanged has to be structural, not conditional. An `@export var slice := false` is one editor
## re-save or one merge away from being true in a scene nobody meant to touch, and the failure would
## surface as a pinned hash moving for no reason anybody could find. A subclass cannot arrive there
## by accident.
##
## THE SEED IS PINNED so the twenty-minute run is the same twenty minutes every time — the beats
## land in the order they were written for, and a bug found on the third room can be walked back to.
## Set dungeon_seed to 0 in the editor to let it roll fresh; the director places by ROLE, so every
## beat still lands somewhere sensible, it just stops being the same descent twice.

func _ready() -> void:
	if dungeon_seed == 0:
		dungeon_seed = 20260814
	super()


func _furnish(room_nodes: Dictionary) -> void:
	var run := get_node_or_null("/root/Run")
	if run and run.has_method("begin"):
		# Behind the portal fade, before the player can see anything: the run's boons and check memo
		# are cleared here rather than on arrival, so nothing from the last descent is briefly live.
		run.begin(layout.seed_used)

	var director := SliceDirector.new()
	director.name = "SliceDirector"
	add_child(director)
	director.furnish(self, layout, room_nodes)

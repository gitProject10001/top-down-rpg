class_name ToolBelt
extends Node3D
## What the player is carrying. Builds all three tools once and then rations access to them: you
## descend with ONE, and the other two are things the dungeon gives you.
##
## That is a deliberate pacing choice rather than an economy. A player handed three verbs at the
## door uses none of them well; a player handed one uses it on everything, including several things
## it does not solve, which is exactly the state of mind a dungeon wants you in when it finally
## hands you the second.

signal changed

## Which tool the quartermaster sent you down with. Set from the hub before a descent.
@export var starting_tool := "Aegis Tether"

var tools: Array[ToolWeapon] = []
var unlocked: Array[String] = []
var current := 0


func _ready() -> void:
	for script in [AegisTether, SunfireLantern, ShatterHammer]:
		var t: ToolWeapon = script.new()
		t.name = String(t.tool_name).replace(" ", "")
		add_child(t)
		tools.append(t)
	reset_to_start()


## Back to a single tool. Called at the top of a descent, so last run's finds do not carry over —
## the tools are the dungeon's to give, every time.
func reset_to_start() -> void:
	unlocked.clear()
	if _find(starting_tool) != null:
		unlocked.append(starting_tool)
	elif not tools.is_empty():
		unlocked.append(tools[0].tool_name)
	current = 0
	changed.emit()


func unlock(name_of: String) -> bool:
	if name_of in unlocked or _find(name_of) == null:
		return false
	unlocked.append(name_of)
	current = unlocked.size() - 1          # swap straight to the new one: it is the news
	changed.emit()
	return true


func carried() -> Array[ToolWeapon]:
	var out: Array[ToolWeapon] = []
	for name_of in unlocked:
		var t := _find(name_of)
		if t:
			out.append(t)
	return out


func active_tool() -> ToolWeapon:
	var held := carried()
	if held.is_empty():
		return null
	return held[current % held.size()]


func next() -> void:
	var held := carried()
	if held.size() < 2:
		return
	current = (current + 1) % held.size()
	changed.emit()


func use() -> void:
	var t := active_tool()
	if t == null or not t.is_ready():
		return
	var player := get_parent() as Node3D
	if player == null:
		return
	t.use(player)
	changed.emit()


func _find(name_of: String) -> ToolWeapon:
	for t in tools:
		if t.tool_name == name_of:
			return t
	return null


## Input is read here rather than in a player STATE, because a tool is not a state: you can use one
## mid-combo, mid-run, mid-anything, and the tool's own cooldown is the only thing rationing it.
## The screens are the exception — a card or a menu owns the keyboard while it is up.
func _unhandled_input(event: InputEvent) -> void:
	if _screen_is_up():
		return
	if event.is_action_pressed("tool_use"):
		use()
	elif event.is_action_pressed("tool_next"):
		next()


func _screen_is_up() -> bool:
	for path in ["/root/Dialogue", "/root/Sheet", "/root/Notice"]:
		var n := get_node_or_null(path)
		if n and n.get("active"):
			return true
	return false

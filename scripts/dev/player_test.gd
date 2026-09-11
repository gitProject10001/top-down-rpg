extends Node3D
## A bare arena for FEELING the difference between the three player bodies.
##
## WHY IT EXISTS: player, player2 and player3 run the same player.gd but three different animation
## sets on two different rigs, and the only honest way to compare locomotion is to swap between
## them without moving, without reloading, and without the rest of the game in the way. So this
## scene has a floor, a light, the real camera rig and nothing else: whatever you notice here is
## the character, not the level.
##
## THE SWAP PRESERVES POSE. The new body inherits the old one's position and the camera keeps
## following, so pressing 1/2/3 mid-run is a direct A/B — you see the same movement re-animated,
## not two separate runs you have to remember. Everything else (state machine, cooldowns, health)
## is rebuilt from scratch, because a half-carried state would be a worse lie than a reset.
##
## KEYS
##   1 / 2 / 3 / 4   swap body
##   Tab             cycle to the next body
##   WASD            move          Space  dash
##   LMB             attack        Space while holding LMB = the lunge (player3/4 only)
##   RMB             block (player/player2 only)      Q  bow (player/player2 only)
##
## player3 and player4 are the SAME setup on two different meshes — same script, same library, same
## states, same timings. Any difference you feel between those two is the mesh's proportions, and
## nothing else. That is the comparison the retarget exists to make possible.

const BODIES := [
	{"name": "player", "scene": "res://scenes/player/player.tscn",
			"note": "Mixamo rig, sword+shield+bow, 2D strafe blend"},
	{"name": "player2", "scene": "res://scenes/player/player2.tscn",
			"note": "Mixamo rig, sword+shield+bow, 2D strafe blend"},
	{"name": "player3", "scene": "res://scenes/player/player3.tscn",
			"note": "UAL mannequin mesh, UAL clips, sword only, 1D blend, faces travel"},
	{"name": "player4", "scene": "res://scenes/player/player4.tscn",
			"note": "Tripo/Mixamo mesh, SAME UAL clips via the humanoid retarget"},
]

@onready var _rig: CameraRig = $CameraRig
@onready var _readout: Label = $UI/Readout

var _index := -1
var _body: Player
var _spawn := Vector3(0.0, 1.1, 0.0)

# Combat accounting. The whole point of the targeting work is that a swing which LOOKS like it
# should land does land, so the thing worth showing is the ratio — feel is not evidence.
var _swings := 0
var _hits := 0


func _ready() -> void:
	for d in $Dummies.get_children():
		(d as TrainingDummy).was_hit.connect(func(_a, _s): _hits += 1)
	_swap_to(2)                                  # start on the new one — it is what we came to see


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_1:
		_swap_to(0)
	elif key == KEY_2:
		_swap_to(1)
	elif key == KEY_3:
		_swap_to(2)
	elif key == KEY_4:
		_swap_to(3)
	elif key == KEY_TAB:
		_swap_to((_index + 1) % BODIES.size())
	elif key == KEY_R:
		_swings = 0
		_hits = 0


## Replace the active body, keeping where it stood. The old node is freed at the END of the frame
## (queue_free), so we must ALSO unparent it now — otherwise the camera's target_path and the
## "player" group briefly hold two bodies and the rig lerps to the midpoint between them.
func _swap_to(index: int) -> void:
	if index == _index:
		return
	if _body != null and is_instance_valid(_body):
		_spawn = _body.global_position
		remove_child(_body)
		_body.queue_free()
	_index = index
	var packed: PackedScene = load(BODIES[index].scene)
	if packed == null:
		push_error("Missing %s" % BODIES[index].scene)
		return
	_body = packed.instantiate() as Player
	add_child(_body)
	_body.global_position = _spawn
	_rig.target_path = _rig.get_path_to(_body)
	# The rig lerps toward its target; on a swap there is nothing to lerp FROM, so plant it.
	_rig.global_position = _spawn


func _process(_delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var info: Dictionary = BODIES[_index]
	var state := "-"
	var fsm := _body.get_node_or_null("StateMachine") as StateMachine
	if fsm and fsm.current_state:
		state = String(fsm.current_state.name)
	# The CLIP is read off the AnimationTree's own playback rather than tracked alongside it, so the
	# readout can never disagree with what you are looking at.
	var clip := "-"
	var tree := _body.get_node_or_null("AnimationTree") as AnimationTree
	if tree and tree.active:
		var pb = tree["parameters/playback"]
		if pb:
			clip = String(pb.get_current_node())
	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()

	# Count each swing once, as it starts. attack.gd restarts the state per combo step, so watching
	# the state name alone would count a three-hit chain as one swing.
	var atk := _body.get_node_or_null("StateMachine/Attack")
	if atk:
		var s: int = atk.get("_step")
		if state == "Attack" and (_last_state != "Attack" or s != _last_combo_step):
			_swings += 1
		_last_combo_step = s
	_last_state = state

	# What the swing would commit to RIGHT NOW, and how far short of contact you are. A negative
	# gap means you are already inside the envelope. This is the number that used to be invisible —
	# 16 mm of it was the whole difference between a hit and a whiff.
	var lock := "none"
	var target := _body.acquire_target(
			_body.contact_range(null) + _body.attack_step_max, _body.target_arc)
	if target:
		var d := Vector2(target.global_position.x - _body.global_position.x,
				target.global_position.z - _body.global_position.z).length()
		lock = "%s  %.2f m  (gap %+.2f m)" % [
			target.name, d, d - _body.contact_range(target)]

	var rate := "-" if _swings == 0 else "%d%%" % roundi(100.0 * _hits / _swings)
	_readout.text = ("[%d] %s\n%s\n\nstate  %s\nclip   %s\nspeed  %.2f m/s\n"
			+ "target %s\nswings %d   hits %d   landed %s\n\n"
			+ "1/2/3/4 or Tab swap    R reset counters") % [
		_index + 1, info.name, info.note, state, clip, speed, lock, _swings, _hits, rate,
	]

var _last_state := ""
var _last_combo_step := -1

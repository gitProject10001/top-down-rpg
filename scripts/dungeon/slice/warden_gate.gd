class_name WardenGate
extends StaticBody3D
## Someone standing at the locked door who can, in principle, be talked round.
##
## THE CHOICE THIS EXISTS TO CREATE: the gate has a key somewhere in the dungeon, and it has a
## person in front of it. You can go and find the key — safe, slow, and it is somewhere you have not
## cleared — or you can gamble a Drama check right now. Failing costs you the option for the rest of
## the descent, so it is a real bet rather than a retry.
##
## THE ODDS ARE PRINTED ON THE OPTION. A hidden difficulty is not a gamble, it is a surprise; the
## player should be able to look at their own sheet and decide. That is what Traits.odds() is for.

const TINT := Color(1.00, 0.78, 0.34)          ## Drama's gold, on the body and on the option
const DIFFICULTY := "challenging"
const GAMBLE := "gamble"

## The key id of the DungeonDoor this warden stands at. Set by the director. Passing the check calls
## the DUNGEON's grant_key rather than the door's unlock, so `_keys_held` stays true and has_key()
## does not start lying — and so a second gate on the same key opens too, which is what a key means.
@export var key_id := "key_0"
## Unique per warden, so the check is memoised per site rather than per dungeon.
@export var check_id := "warden_0"

var _near := false
var _spent := false                            ## the Drama route has been tried and lost
var _passed := false
var _player: Node3D
var _body: MeshInstance3D
var _bob := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_player = get_tree().get_first_node_in_group("player") as Node3D

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.9
	shape.shape = cap
	shape.position.y = 0.95
	add_child(shape)

	_body = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
	mesh.height = 1.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(TINT.r * 0.5, TINT.g * 0.42, TINT.b * 0.3)
	mat.emission_enabled = true
	mat.emission = TINT
	mat.emission_energy_multiplier = 0.5
	mesh.material = mat
	_body.mesh = mesh
	_body.position.y = 0.95
	_body.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_body)

	var label := Label3D.new()
	label.text = "WARDEN"
	label.font_size = 44
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = TINT
	label.no_depth_test = true
	label.position.y = 2.3
	add_child(label)

	var zone := Area3D.new()
	zone.name = "InteractZone"
	zone.collision_layer = 0
	zone.collision_mask = 1
	var zshape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.6
	zshape.shape = sphere
	zshape.position.y = 1.0
	zone.add_child(zshape)
	add_child(zone)
	zone.body_entered.connect(func(b: Node3D) -> void: if b.is_in_group("player"): _near = true)
	zone.body_exited.connect(func(b: Node3D) -> void: if b.is_in_group("player"): _near = false)


func _process(delta: float) -> void:
	_bob += delta
	_body.position.y = 0.95 + sin(_bob * 1.6) * 0.04
	if is_instance_valid(_player):
		var d := _player.global_position - global_position
		d.y = 0.0
		if d.length() > 0.2:
			_body.rotation.y = lerp_angle(_body.rotation.y, atan2(d.x, d.z),
					1.0 - exp(-5.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	var dialogue := get_node_or_null("/root/Dialogue")
	if not _near or dialogue == null or dialogue.active or _passed:
		return
	if event.is_action_pressed("interact"):
		if not dialogue.node_entered.is_connected(_on_node):
			dialogue.node_entered.connect(_on_node)
		if not dialogue.finished.is_connected(_on_finished):
			dialogue.finished.connect(_on_finished)
		dialogue.start(_convo())


## The conversation is built LIVE, because what it should offer depends on the sheet in front of it:
## the odds are read off the player's actual Drama, and the gamble disappears once it has been lost.
func _convo() -> Dictionary:
	var traits := get_node_or_null("/root/Traits")
	var responses: Array = []
	if _spent:
		responses.append({"text": "(You already tried. He is not going to forget it.)",
				"next": "spurned"})
	elif traits:
		var chance: int = traits.odds(traits.Attr.DRAMA, DIFFICULTY)
		responses.append({
			"text": "[DRAMA — Challenging, %d%%]  \"You misunderstand. I am expected.\"" % chance,
			"next": GAMBLE,
		})
	responses.append({"text": "Ask about the door.", "next": "door"})
	responses.append({"text": "Say nothing. (Leave)", "next": ""})
	return {
		"start": {
			"speaker": "Warden",
			"text": "Far enough. This door is shut and I am the reason it stays that way.",
			"responses": responses,
		},
		"door": {
			"speaker": "Warden",
			"text": "There is a key. It is not on me and it is not near here — that is rather the "
					+ "point of a key. Go and be somebody who has one.",
			"responses": responses.duplicate(),
		},
		"spurned": {
			"speaker": "Warden",
			"text": "No. You had your performance. Bring the key like everyone else.",
			"next": "",
		},
		GAMBLE: {
			"speaker": "Warden",
			"text": "...",
			"next": "",
		},
	}


func _on_node(id: String) -> void:
	if id == GAMBLE:
		_pending = true                        # resolved once the conversation has closed


var _pending := false


## The check runs AFTER the conversation ends rather than inside it, so the Notice card has the
## screen to itself. Two overlapping text panels — the dialogue bar at the bottom and the check card
## at the top — is a legible mess, and the check IS the answer to the line just spoken.
func _on_finished() -> void:
	if not _pending:
		return
	_pending = false
	var traits := get_node_or_null("/root/Traits")
	var notice := get_node_or_null("/root/Notice")
	if traits == null:
		return
	var result: Dictionary
	if notice:
		result = await notice.interject(traits.Attr.DRAMA, DIFFICULTY, check_id,
				"You are not lying, exactly. You are being, briefly and completely, a person who is "
						+ "expected — and he steps aside before he has decided to.",
				"You hear it leave your mouth. So does he. The pause afterwards is the longest thing "
						+ "in the room.")
	else:
		result = traits.check(traits.Attr.DRAMA, DIFFICULTY, check_id)
	if result.get("success", false):
		_passed = true
		var dungeon := get_tree().get_first_node_in_group("dungeon")
		if dungeon and dungeon.has_method("grant_key"):
			dungeon.grant_key(key_id)
		var run := get_node_or_null("/root/Run")
		if run and run.has_method("note_secret"):
			run.note_secret()
		queue_free()                           # he has better places to be
	else:
		_spent = true

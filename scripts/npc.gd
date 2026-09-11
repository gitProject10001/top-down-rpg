class_name NPC
extends StaticBody3D
## A non-combat garden character. Stands still (blocks the player), turns to face them when near,
## and opens a branching conversation when you press `interact` (E) inside its zone. The dialogue
## itself is data (CONVO below) handed to the Dialogue autoload — a Hades-style portrait + text +
## player-response UI. Swap CONVO (or set one per NPC) to give a character new lines.

@export var turn_to_player := true
## THIS character's lines. Empty = CONVO below, the garden Wisp's, which is what every NPC placed
## by hand in a scene has always used. It is an export rather than a subclass because the other
## caller builds its NPC in code and packs it into a generated scene (`crypt_room._greeter`), and
## a Dictionary export survives that; a second script would not, without a second scene to put it
## on. Same shape as CONVO, and `Dialogue.start` is the only thing that reads either.
@export var conversation: Dictionary = {}

@onready var _model: Node3D = $Model
@onready var _zone: Area3D = $InteractZone

var _player: Node3D
var _near := false

## A small branching conversation. Nodes with "responses" give the player choices; nodes with
## just "next" show a ▼ continue prompt. "next": "" (or missing) ends the conversation.
const CONVO := {
	"start": {
		"speaker": "Wisp",
		"text": "You again — still breathing, still swinging that sword. The garden noticed.",
		"responses": [
			{"text": "The garden... noticed?", "next": "garden"},
			{"text": "Who are you?", "next": "who"},
			{"text": "I'm busy. (Leave)", "next": ""},
		],
	},
	"garden": {
		"speaker": "Wisp",
		"text": "Everything here remembers. The stones, the fountain, the way you always take the stairs two at a time.",
		"responses": [
			{"text": "That's a little unsettling.", "next": "unsettling"},
			{"text": "Then it knows I always win.", "next": "cocky"},
		],
	},
	"who": {
		"speaker": "Wisp",
		"text": "A voice the garden keeps around. A hint, when you're stuck. A laugh, when you're not.",
		"responses": [
			{"text": "Give me a hint, then.", "next": "hint"},
			{"text": "I don't need help.", "next": "cocky"},
		],
	},
	"unsettling": {
		"speaker": "Wisp",
		"text": "Unsettling keeps you sharp. Sharp keeps you alive. Go on — the warehouse won't clear itself.",
		"next": "",
	},
	"cocky": {
		"speaker": "Wisp",
		"text": "Ha! Confidence. My favourite thing to watch a place slowly take apart. Off you go.",
		"next": "",
	},
	"hint": {
		"speaker": "Wisp",
		"text": "The archers flinch when their shot is answered. Raise your shield a beat early and the door past them opens itself.",
		"responses": [
			{"text": "Thanks, Wisp.", "next": "thanks"},
			{"text": "...I could've figured that out.", "next": "cocky"},
		],
	},
	"thanks": {
		"speaker": "Wisp",
		"text": "Don't thank me. Come back alive — that's thanks enough.",
		"next": "",
	},
}


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_zone.body_entered.connect(func(b): if b is Player: _near = true)
	_zone.body_exited.connect(func(b): if b is Player: _near = false)


func _process(delta: float) -> void:
	if turn_to_player and is_instance_valid(_player):
		var d := _player.global_position - global_position
		d.y = 0.0
		if d.length() > 0.15:
			# Imported glTF model faces +Z, so aim +Z at the player.
			var yaw := atan2(d.x, d.z)
			_model.rotation.y = lerp_angle(_model.rotation.y, yaw, 1.0 - exp(-6.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if _near and not Dialogue.active and event.is_action_pressed("interact"):
		Dialogue.start(CONVO if conversation.is_empty() else conversation)

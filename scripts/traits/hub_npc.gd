class_name HubNPC
extends StaticBody3D
## One of the three people who live at the top of the stairs. Each owns one thing you can do
## between descents, and each has an opinion about the other two.
##
## THE BODY IS A CAPSULE, and that is a decision rather than a placeholder. These are the only
## characters in the hub and they are all standing in one place having conversations; a greybox
## capsule that GLOWS in a colour you learn to recognise reads as deliberate, where three
## half-finished humanoids read as a game that ran out of time. It also means the whole hub cast is
## one scene configured three ways.
##
## The colour each one wears is the characteristic they are most associated with — Maren the sheet,
## Bakhu the body, Ilva the performance. They are not those characteristics. They are people who
## have opinions about them, which is the entire point of the reframe.

enum Role { TUTOR, PHYSICIAN, QUARTERMASTER }

@export var role := Role.TUTOR
@export var person_name := "Maren"
@export var title := "tutor"
## Which characteristic's colour this person wears (a Traits.Attr value).
@export var accent_attr := 0

const TOOLS := ["Aegis Tether", "Sunfire Lantern", "Shatter Hammer"]

var _near := false
var _player: Node3D
var _body: MeshInstance3D
var _bob := 0.0
var _pending := ""                             ## a node id whose consequence fires once talk ends


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var traits := get_node_or_null("/root/Traits")
	var accent: Color = traits.ATTR_COLORS[accent_attr] if traits else Color(0.8, 0.8, 0.85)

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
	mat.albedo_color = Color(accent.r * 0.42, accent.g * 0.4, accent.b * 0.45)
	mat.emission_enabled = true
	mat.emission = accent
	mat.emission_energy_multiplier = 0.45
	mat.roughness = 0.7
	mesh.material = mat
	_body.mesh = mesh
	_body.position.y = 0.95
	add_child(_body)

	var label := Label3D.new()
	label.text = "%s\n%s" % [person_name.to_upper(), title]
	label.font_size = 40
	label.pixel_size = 0.0055
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = accent
	label.outline_size = 10
	label.position.y = 2.35
	add_child(label)

	# INTERACT RADIUS 0.9, not the 2.2 the garden NPC uses. Measured against the terrace: the three
	# of them stand 1.9 m apart (which is the geometric maximum on that slab — wider puts a wing
	# inside the house collider or off the edge), so 2.2 m spheres overlap heavily and pressing E
	# would answer with whoever the engine happened to report first.
	var zone := Area3D.new()
	zone.name = "InteractZone"
	zone.collision_layer = 0
	zone.collision_mask = 1
	var zshape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	zshape.shape = sphere
	zshape.position.y = 1.0
	zone.add_child(zshape)
	add_child(zone)
	zone.body_entered.connect(func(b: Node3D) -> void: if b.is_in_group("player"): _near = true)
	zone.body_exited.connect(func(b: Node3D) -> void: if b.is_in_group("player"): _near = false)


func _process(delta: float) -> void:
	_bob += delta
	_body.position.y = 0.95 + sin(_bob * 1.3 + float(role)) * 0.035
	if is_instance_valid(_player):
		var d := _player.global_position - global_position
		d.y = 0.0
		if d.length() > 0.2:
			_body.rotation.y = lerp_angle(_body.rotation.y, atan2(d.x, d.z),
					1.0 - exp(-5.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	var dialogue := get_node_or_null("/root/Dialogue")
	if not _near or dialogue == null or dialogue.active:
		return
	if event.is_action_pressed("interact"):
		if not dialogue.node_entered.is_connected(_on_node):
			dialogue.node_entered.connect(_on_node)
		if not dialogue.finished.is_connected(_on_finished):
			dialogue.finished.connect(_on_finished)
		_pending = ""
		dialogue.start(_convo())


func _on_node(id: String) -> void:
	if id.begins_with("do_"):
		_pending = id


## The consequence lands AFTER the conversation closes. A full-screen panel opening on top of a
## dialogue bar leaves the bar underneath it and the conversation half-finished; and the panels
## freeze the tree, which a running conversation does not expect.
func _on_finished() -> void:
	if _pending == "":
		return
	var what := _pending
	_pending = ""
	var sheet := get_node_or_null("/root/Sheet")
	match what:
		"do_sheet":
			if sheet:
				sheet.open_characteristics()
		"do_convictions":
			if sheet:
				sheet.open_convictions()
		_:
			if what.begins_with("do_tool_"):
				_set_tool(TOOLS[int(what.trim_prefix("do_tool_"))])


func _set_tool(tool_name: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var belt = player.find_child("ToolBelt", true, false)
	if belt == null:
		return
	belt.starting_tool = tool_name
	if belt.has_method("reset_to_start"):
		belt.reset_to_start()


# ==============================================================================================
# The conversations. Built live, because what these three have to say depends entirely on what
# has happened to you — and if it does not, there is no reason to have written them as people.
# ==============================================================================================

func _convo() -> Dictionary:
	match role:
		Role.PHYSICIAN:
			return _bakhu()
		Role.QUARTERMASTER:
			return _ilva()
		_:
			return _maren()


## What has just happened, as far as the hub knows.
func _state() -> Dictionary:
	var traits := get_node_or_null("/root/Traits")
	if traits == null:
		return {"first": true, "deaths": 0, "wins": 0, "cause": "", "loose": "", "settled": ""}
	var loose := ""
	var settled := ""
	for id: String in traits.convictions:
		match traits.conviction_state(id):
			"loose":
				loose = id
			"settled":
				settled = id
	return {
		"first": traits.runs_taken == 0,
		"deaths": traits.deaths,
		"wins": traits.victories,
		"cause": traits.last_death_cause,
		"loose": loose,
		"settled": settled,
		"insight": traits.insight,
		"unspent": traits.unspent,
		"done": traits.slice_complete,
		"maxed": traits.is_maxed(),
	}


# --- MAREN, the tutor. Precise, faintly bored, right about most things. -------------------------

func _maren() -> Dictionary:
	var s := _state()
	var opening := ""
	if s.first:
		opening = "You have not been down yet, so let me be quick and you can be impatient later. " \
				+ "There are four things you are, and they are all the same four things whether you " \
				+ "are swinging, looking, or talking. That is not a metaphor. It is how the sheet works."
	elif s.done and s.maxed:
		opening = "There is nothing left on this sheet to raise. I have checked twice, which for " \
				+ "me is a kind of celebration. Whatever you do next, you will be doing it as " \
				+ "yourself and not as a number I am improving."
	elif s.done:
		opening = "You went all the way down and came back. I have written it in the margin. The " \
				+ "sheet is not finished, mind — it is only that the thing it was for is done."
	elif s.wins > 0:
		opening = "You came back up. Sit down before you say anything — people who have just won " \
				+ "are the least accurate witnesses I have ever taken a statement from."
	elif s.deaths > 0:
		opening = "%s, then. I am not going to pretend I am surprised, and I am not going to " \
				% str(s.cause).capitalize() \
				+ "pretend it is interesting either. What matters is which number was too small."
	else:
		opening = "Back already. Either it went well or it went quickly. Show me the sheet and I " \
				+ "will tell you which."

	var responses: Array = [
		{"text": "Show me the sheet. [%d unspent, %d Insight]" % [int(s.unspent), int(s.insight)],
				"next": "do_sheet"},
		{"text": "Explain the checks again.", "next": "checks"},
		{"text": "What do you make of the other two?", "next": "others"},
		{"text": "Later. (Leave)", "next": ""},
	]
	return {
		"start": {"speaker": "Maren", "text": opening, "responses": responses},
		"checks": {
			"speaker": "Maren",
			"text": "Two dice and whichever number applies. The dice are not on your side and they " \
					+ "are not against you — they are simply the part you do not control, which is " \
					+ "most of it. What you control is which number gets added. Raise it and the whole " \
					+ "curve moves. That is the only honest advice anyone can give you about anything.",
			"responses": responses.duplicate(),
		},
		"others": {
			"speaker": "Maren",
			"text": "Bakhu is good at what Bakhu does and I would not ask him to read a map. Ilva " \
					+ "I would not ask the time. She will tell you, at length, and you will leave " \
					+ "the conversation believing something.",
			"responses": responses.duplicate(),
		},
		"do_sheet": {
			"speaker": "Maren",
			"text": "Go on. It is your sheet; I only keep it tidy.",
			"next": "",
		},
	}


# --- BAKHU, the physician. Short sentences. Present tense. Not unkind. --------------------------

func _bakhu() -> Dictionary:
	var s := _state()
	var opening := ""
	if s.first:
		opening = "You are not hurt. That is the last time I will be able to say that, so I am " \
				+ "saying it properly. Come back and I will look at you."
	elif s.done:
		opening = "You are different than when you started and you are the only one who cannot " \
				+ "see it. Sit anyway. There is always room for one more idea, if you make it."
	elif s.settled != "":
		opening = "Something has finished setting. I can see it in how you are standing. You have " \
				+ "not noticed yet — people never do — but you will, the next time it matters."
	elif s.loose != "":
		opening = "You are carrying something. Not a wound. You keep starting sentences and " \
				+ "stopping. Sit with it or put it down, but stop doing it in my doorway."
	elif s.deaths > 0:
		opening = "You died. I know. I am not asking you to describe it. The body writes it down " \
				+ "whether you do or not, and the body is a worse editor than I am."
	else:
		opening = "You came back whole. Good. Whole is not the same as unchanged, and I am here " \
				+ "for the difference."

	var responses: Array = [
		{"text": "What am I carrying?", "next": "do_convictions"},
		{"text": "Can I make more room?", "next": "room"},
		{"text": "Does it get easier?", "next": "easier"},
		{"text": "Nothing today. (Leave)", "next": ""},
	]
	return {
		"start": {"speaker": "Bakhu", "text": opening, "responses": responses},
		"room": {
			"speaker": "Bakhu",
			"text": "You have room for two ideas at once. That is not a law. It is how much of " \
					+ "yourself you have cleared out so far, and it can be cleared out further — " \
					+ "slowly, and it costs, and you will not enjoy the process.",
			"responses": responses.duplicate(),
		},
		"easier": {
			"speaker": "Bakhu",
			"text": "No. You get heavier. That is a different thing and it works better. Maren " \
					+ "would tell you that is imprecise. Maren has never been carried up those " \
					+ "stairs by somebody else.",
			"responses": responses.duplicate(),
		},
		"do_convictions": {
			"speaker": "Bakhu",
			"text": "Then look at it properly, instead of at me.",
			"next": "",
		},
	}


# --- ILVA, the quartermaster. Warm, theatrical, entirely unreliable. ----------------------------

func _ilva() -> Dictionary:
	var s := _state()
	var carried := _current_tool()
	var opening := ""
	if s.first:
		opening = "A NEW ONE. Oh, this is a good day. Right — you get one. One! Everyone asks why " \
				+ "and the answer is that a person holding three things learns nothing about any of " \
				+ "them. The other two are down there. They always are."
	elif s.done:
		opening = "The one who finished it. I get to say that now, and I am going to say it to " \
				+ "everyone, including you, including repeatedly. Pick something. Go again. Not " \
				+ "because you have to — because you get to."
	elif s.wins > 0:
		opening = "There she is. THERE she is. I told them — I said it, out loud, to Maren, who " \
				+ "wrote it down in that little way she does — and I was RIGHT."
	elif s.deaths > 0:
		opening = "You came back the sad way. That is allowed. Sit here, look at the ironmongery, " \
				+ "and let me be insufferable at you until you feel like a person again."
	else:
		opening = "Back for the ironmongery. Of course you are. Nobody comes up those stairs to " \
				+ "see Bakhu twice."

	var responses: Array = []
	for i in TOOLS.size():
		var mark := "  ← carried" if TOOLS[i] == carried else ""
		responses.append({"text": "%s%s" % [TOOLS[i], mark], "next": "do_tool_%d" % i})
	responses.append({"text": "Why only one?", "next": "why"})
	responses.append({"text": "I'm set. (Leave)", "next": ""})

	return {
		"start": {"speaker": "Ilva", "text": opening, "responses": responses},
		"why": {
			"speaker": "Ilva",
			"text": "Because a rope is only interesting to somebody who has spent an hour with a " \
					+ "problem a rope does not solve! Take one. Be wrong with it. Find the others " \
					+ "down there and you will actually be pleased to see them, which is more than " \
					+ "I get around here.",
			"responses": responses.duplicate(),
		},
		"do_tool_0": {
			"speaker": "Ilva",
			"text": "The Tether. Pulls what it can move and pulls YOU at what it cannot, which is " \
					+ "the most honest thing in this building.",
			"next": "",
		},
		"do_tool_1": {
			"speaker": "Ilva",
			"text": "The Lantern. It burns things, yes, fine. What it really does is make a room " \
					+ "admit what is in it. Ask Bakhu about that one, he goes quiet.",
			"next": "",
		},
		"do_tool_2": {
			"speaker": "Ilva",
			"text": "The Hammer. There is no technique. There has never been a technique. Anyone " \
					+ "who tells you there is a technique is selling you a second hammer.",
			"next": "",
		},
	}


func _current_tool() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return ""
	var belt = player.find_child("ToolBelt", true, false)
	return String(belt.starting_tool) if belt else ""

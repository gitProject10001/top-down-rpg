class_name Finale
extends Object
## The closing beat. You beat the boss, you came up the stairs, and the three of them are waiting.
##
## THE ONLY REASON THIS IS WORTH HAVING is that it reads YOUR run back to you. A generic "well done"
## after twenty minutes of decisions is worse than no ending at all — it tells the player their
## choices were scenery. So every line here is built from something the run actually recorded: how
## many rooms you cleared, how your checks went, which ideas settled in you on the way, whether you
## had died getting here before.
##
## A static builder rather than a node: it owns no state, it is called once, and Dialogue wants a
## plain Dictionary.

## Rotating speakers through one conversation — Dialogue takes a speaker per node, so the three of
## them can talk to each other without three conversations and a handoff.
static func convo(traits: Node) -> Dictionary:
	var tally: Dictionary = traits.check_tally()
	var settled: Array[String] = []
	for id: String in traits.convictions:
		if traits.conviction_state(id) == "settled":
			settled.append(String(traits.CONVICTIONS[id].name))

	return {
		"start": {
			"speaker": "Maren",
			"text": _maren(traits, tally),
			"next": "bakhu",
		},
		"bakhu": {
			"speaker": "Bakhu",
			"text": _bakhu(traits, settled),
			"next": "ilva",
		},
		"ilva": {
			"speaker": "Ilva",
			"text": _ilva(traits),
			"responses": [
				{"text": "\"It's done.\"", "next": "done"},
				{"text": "(Say nothing.)", "next": "silence"},
			],
		},
		"done": {
			"speaker": "Ilva",
			"text": "IT'S DONE. She said it. Maren, write that down — write down that she said it.",
			"next": "",
		},
		"silence": {
			"speaker": "Bakhu",
			"text": "That is also an answer. Probably the true one.",
			"next": "",
		},
	}


## The tutor counts. It is the only way she knows how to be pleased.
static func _maren(traits: Node, tally: Dictionary) -> String:
	var rooms: int = traits.run_rooms_cleared
	var kills: int = traits.run_kills
	var line := "%d rooms. %d of them the hard way. " % [rooms, kills]
	var failed: int = tally.get("failed", 0)
	var total: int = tally.get("total", 0)
	if total == 0:
		line += "And not one check called, the whole way down. You went by feel. It worked, which " \
				+ "is the part I find difficult."
	elif failed == 0:
		line += "Every check you called, you passed. I want to say that was the sheet. It was " \
				+ "mostly the sheet."
	else:
		line += "%d of %d checks went against you and you kept going anyway. " % [failed, total]
		line += "That is the number I would have got wrong about you."
	return line


## The physician looks at what it left in you, which is his whole job.
static func _bakhu(traits: Node, settled: Array[String]) -> String:
	if settled.is_empty():
		return "Nothing has settled in you yet. You went down and came back the same shape, which " \
				+ "is rarer than it sounds and I do not entirely believe it."
	if settled.size() == 1:
		return "One thing settled in you on the way. %s. I felt it arrive. You will not, for a " \
				% settled[0] + "while yet."
	return "%d things settled in you down there — %s. " % [settled.size(), ", ".join(settled)] \
			+ "One of them I would rather it had not. I am not going to tell you which."


## The quartermaster performs. She has been waiting all game to do this.
static func _ilva(traits: Node) -> String:
	if traits.deaths == 0:
		return "First time. FIRST TIME. Do you know how many people come back up those stairs on " \
				+ "the first attempt? Neither do I, but it is not many and I intend to keep saying so."
	if traits.deaths >= 4:
		return "You died %d times getting here and you came back every single one of them. " \
				% traits.deaths + "That is not luck and it is not the ironmongery. Go on then — " \
				+ "say the line."
	return "You died %d times getting here. I counted. I always count. " % traits.deaths \
			+ "Go on then — say the line."


## The card that closes it. Also built from the run, so it is a record rather than a screen.
static func card(traits: Node) -> Array:
	var tally: Dictionary = traits.check_tally()
	var out: Array = []
	out.append(["descents", "%d" % traits.runs_taken])
	out.append(["deaths", "%d" % traits.deaths])
	out.append(["rooms cleared, this descent", "%d" % traits.run_rooms_cleared])
	out.append(["checks called", "%d passed, %d failed"
			% [tally.get("passed", 0), tally.get("failed", 0)]])
	var settled := 0
	for id: String in traits.convictions:
		if traits.conviction_state(id) == "settled":
			settled += 1
	out.append(["convictions settled", "%d of %d" % [settled, traits.CONVICTIONS.size()]])
	out.append(["the sheet", "%d of %d" % [
			traits.attr(0) + traits.attr(1) + traits.attr(2) + traits.attr(3),
			traits.MAX_ATTR * 4]])
	return out

class_name TraitProbe
extends Area3D
## The thing that makes the world talk to you. Drop one anywhere; walking into it rolls one check
## and says something — and on a success, shows you what you would otherwise have walked past.
##
## THE RADIUS IS PERCEPTION'S. Built in code from Traits.notice_radius(), so a Perception build
## genuinely notices things from further away rather than merely being told about them sooner. It is
## the same number the lantern's reveal uses, which is the point: one characteristic, one meaning,
## several places it shows up.

## Which characteristic is doing the noticing (a Traits.Attr value).
@export var which := 0
@export var difficulty := "medium"
## Unique per site. Empty derives one from the position — safe here because the probe is placed by
## the generator at build time and never moves, so the derived id is stable for the whole run.
@export var check_id := ""
@export_multiline var on_success := ""
@export_multiline var on_fail := ""
## Made visible (and solid, if it has a reveal()) when the check passes.
@export var reveal_path: NodePath
@export var grants_conviction := ""
## True = no dice. Some things are worth saying without pretending there was a chance you missed
## them; the start room's line is scene-setting, not a test.
@export var passive := false

var _fired := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	var traits := get_node_or_null("/root/Traits")
	sphere.radius = float(traits.notice_radius()) if traits else 4.0
	shape.shape = sphere
	shape.position.y = 1.0
	add_child(shape)


func _on_body_entered(body: Node3D) -> void:
	# TWO LATCHES, and they are not redundant. Traits memoises the ROLL, so re-entering cannot change
	# the outcome — but it would happily replay the card, slow time again, and re-reveal something
	# already revealed. This one is about the performance; that one is about the fact.
	if _fired or not body.is_in_group("player"):
		return
	_fired = true
	_resolve()


func _resolve() -> void:
	var traits := get_node_or_null("/root/Traits")
	var notice := get_node_or_null("/root/Notice")
	if traits == null or notice == null:
		return

	if passive:
		await notice.murmur(which, on_success)
		_reveal()
		return

	var id := check_id
	if id == "":
		# Position-derived, rounded to a decimetre: the probe is placed once at generation and never
		# moves, so this is stable across the run — and distinct between two probes in the same room.
		id = "probe_%d_%d_%d" % [roundi(global_position.x * 10.0),
				roundi(global_position.y * 10.0), roundi(global_position.z * 10.0)]
	var result: Dictionary = await notice.interject(which, difficulty, id, on_success, on_fail)
	if result.get("success", false):
		_reveal()
		traits.add_insight(1)
		if grants_conviction != "":
			traits.gain_conviction(grants_conviction)


func _reveal() -> void:
	var target := get_node_or_null(reveal_path)
	if target == null:
		return
	if target.has_method("reveal"):
		target.reveal()
	elif target is Node3D:
		(target as Node3D).visible = true

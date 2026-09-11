class_name SunfireLantern
extends ToolWeapon
## A cone of light that is also a cone of fire. It burns what is in front of you and, in the same
## gesture, makes the room admit what is actually there — spectral geometry only exists once it has
## been lit.
##
## THE REVEAL RANGE IS PERCEPTION'S, not the lantern's. The flame reaches as far as the flame
## reaches, but what you NOTICE in that light is a fact about you: Traits.notice_radius() widens the
## reveal without widening the damage. That is the clearest place in the game where one number is
## doing two jobs, and it is why the same tool feels different in different hands.

const REACH := 6.5
const HALF_ANGLE := 25.0
const BURN := 1


func _init() -> void:
	tool_name = "Sunfire Lantern"
	cooldown = 1.4
	tint = Color(1.0, 0.72, 0.3)
	blurb = "Burns what stands in it, and shows what was standing there all along."


func use(player: Node3D) -> void:
	var dir := aim_dir(player)
	var origin: Vector3 = player.global_position
	fx_fan(player, origin, dir, REACH, HALF_ANGLE, tint, 0.4)

	for foe in in_cone(player, "enemy", dir, REACH, HALF_ANGLE):
		hurt(foe, BURN, self)

	# Burn through a barrier — the other half of "fire is a key, not just damage".
	for brush in in_cone(player, "barrier_brush", dir, REACH, HALF_ANGLE):
		if brush.has_method("ignite"):
			brush.ignite()

	# The reveal reaches as far as you do. A wide cone rather than the flame's narrow one, because
	# noticing is peripheral and burning is not.
	var traits := get_node_or_null("/root/Traits")
	var see: float = traits.notice_radius() if traits else 4.0
	var found := 0
	for ghost in in_cone(player, "spectral", dir, see, 60.0):
		if ghost.has_method("reveal"):
			ghost.reveal()
			found += 1

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.combat_impact.emit(0.35 if found > 0 else 0.12)
	start_cooldown()

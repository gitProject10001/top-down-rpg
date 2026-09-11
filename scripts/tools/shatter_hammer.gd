class_name ShatterHammer
extends ToolWeapon
## The heaviest thing in the game, and it should feel like it: a full circle, real damage, poise
## broken outright on everything it touches, and a cracked wall reduced to a doorway.
##
## A CIRCLE, not a cone, and that is the tool's whole character. The tether and the lantern are
## aimed; the hammer is not — you commit to a position instead of a direction, which is why it is
## the answer to being surrounded and a bad answer to anything at range.

const RADIUS := 3.6
const DAMAGE := 2
const KNOCKBACK := 11.0


func _init() -> void:
	tool_name = "Shatter Hammer"
	cooldown = 2.0
	tint = Color(0.95, 0.5, 0.35)
	blurb = "Answers most questions. Occasionally the question was a wall."


func use(player: Node3D) -> void:
	var origin: Vector3 = player.global_position
	fx_ring(player, origin, RADIUS, tint, 0.45)

	var hit_anything := false
	for foe in in_cone(player, "enemy", Vector3.FORWARD, RADIUS, 180.0):
		hurt(foe, DAMAGE, self)
		# STAGGER OUTRIGHT rather than chipping poise. A brute takes a five-hit flurry inside one
		# second to break normally (enemy.gd's poise_regen_delay); the hammer's reason to exist is
		# that it does not have to.
		if foe.has_method("stagger"):
			foe.stagger()
		var away: Vector3 = foe.global_position - origin
		away.y = 0.0
		if away.length() > 0.1 and "velocity" in foe:
			foe.set("velocity", away.normalized() * KNOCKBACK)
		hit_anything = true

	for wall in in_cone(player, "cracked_wall", Vector3.FORWARD, RADIUS, 180.0):
		if wall.has_method("shatter"):
			wall.shatter()
			hit_anything = true

	var fx := get_node_or_null("/root/Fx")
	if fx and hit_anything:
		fx.hitstop(0.11, 0.06)
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.combat_impact.emit(0.55 if hit_anything else 0.25)
	start_cooldown()

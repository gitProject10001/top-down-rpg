class_name AegisTether
extends ToolWeapon
## The rope. One press, and what it does depends entirely on what it caught:
##
##   a lever   -> pulls it (and whatever it opens)
##   a light enemy -> drags them to you, off their feet
##   a heavy enemy -> drags YOU to them, which is the same physics and a completely different idea
##
## PRIORITY IS ANCHORS FIRST, deliberately. In a room with a lever and a fight going on, the player
## aiming at the lever means the lever — an enemy wandering into the line should not steal the pull
## and leave a puzzle un-solved for reasons the player cannot see. Enemies are everywhere; anchors
## are placed.

const REACH := 13.0
const HALF_ANGLE := 26.0
const PULL_SPEED := 18.0        ## how fast a light enemy is dragged in
const LUNGE_SPEED := 22.0       ## how fast you are dragged to a heavy one
const STOP_SHORT := 2.0         ## metres from a heavy target to stop, so you arrive in swing range


func _init() -> void:
	tool_name = "Aegis Tether"
	cooldown = 1.1
	tint = Color(0.55, 0.85, 0.95)
	blurb = "A rope with opinions. Pulls what it can move, and pulls you at what it cannot."


func use(player: Node3D) -> void:
	var dir := aim_dir(player)
	var origin: Vector3 = player.global_position + Vector3(0, 1.0, 0)

	var anchors := in_cone(player, "tether_anchor", dir, REACH, HALF_ANGLE)
	if not anchors.is_empty():
		var anchor := anchors[0]
		fx_line(player, origin, anchor.global_position + Vector3(0, 0.9, 0), tint, 0.45)
		if anchor.has_method("pull"):
			anchor.pull()
		start_cooldown()
		return

	var foes := in_cone(player, "enemy", dir, REACH, HALF_ANGLE)
	if foes.is_empty():
		# A miss still costs something, or the rope becomes a free scan of the room.
		fx_line(player, origin, origin + dir * REACH, Color(tint.r, tint.g, tint.b, 0.4), 0.2)
		start_cooldown()
		return

	var foe := foes[0]
	fx_line(player, origin, foe.global_position + Vector3(0, 1.0, 0), tint, 0.4)
	var bus := get_node_or_null("/root/EventBus")
	if is_heavy(foe):
		# YOU move. Stop short of them so the arrival is a swing opportunity rather than a collision.
		var to: Vector3 = foe.global_position - player.global_position
		to.y = 0.0
		var gap := maxf(to.length() - STOP_SHORT, 0.0)
		if gap > 0.1:
			var travel: Vector3 = to.normalized() * minf(LUNGE_SPEED, gap / 0.18)
			player.set("velocity", Vector3(travel.x, player.velocity.y, travel.z))
		if bus:
			bus.combat_impact.emit(0.25)
	else:
		# THEY move. Driving velocity rather than teleporting keeps their own move_and_slide honest,
		# so a yanked archer still collides with the pillar it was hiding behind instead of passing
		# through it.
		var to: Vector3 = player.global_position - foe.global_position
		to.y = 0.0
		if to.length() > 0.2 and "velocity" in foe:
			foe.set("velocity", to.normalized() * PULL_SPEED)
		if foe.has_method("stagger"):
			foe.stagger()                 # off their feet: the pull IS the opening it creates
		if bus:
			bus.combat_impact.emit(0.2)
	start_cooldown()

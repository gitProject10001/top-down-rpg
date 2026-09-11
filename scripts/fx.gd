extends Node
## Global combat-feel helper (autoload "Fx").
##
## HITSTOP is the single biggest piece of melee "juice": freezing the whole game for a few dozen
## milliseconds on impact makes a hit feel like it connected with weight. We do it by dropping
## Engine.time_scale, then waiting REAL time (ignore_time_scale timer) before restoring it.
##
## SPLASH is the water milestones' addition — the same instantiate-and-self-free idiom every
## hitbox uses (hitbox.gd:95), centralised here because splashes are spawned from three places
## (wader, raft, states) and none of them should carry scene preloads of their own.

const WATER_SPLASH := preload("res://scenes/fx/water_splash.tscn")
const WATER_RING := preload("res://scenes/fx/water_ring.tscn")
const FOOT_DUST := preload("res://scenes/fx/foot_dust.tscn")

var _active := false
var _stop_until := 0.0       ## real-clock deadline of the freeze in flight (see hitstop)


## Droplet burst + expanding foam ring at a water position, sat on the surface when one
## answers there (the caller may hand feet or hull coordinates). `scale` widens the ring and
## the burst together: 0.7 reads as a step-in, 1.3 as a dash.
func splash(world_pos: Vector3, scale := 1.0) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var surface: float = Water.surface_y(world_pos)
	var y: float = surface if not is_nan(surface) else world_pos.y
	var s := clampf(scale, 0.6, 1.6)
	var burst := WATER_SPLASH.instantiate() as Node3D
	tree.current_scene.add_child(burst)
	burst.global_position = Vector3(world_pos.x, y + 0.05, world_pos.z)
	burst.scale = Vector3.ONE * s
	var ring := WATER_RING.instantiate() as Node3D
	ring.set_meta("splash_scale", s)
	tree.current_scene.add_child(ring)
	# A hand above the surface, never on it: the ring is blend_mix over the water's own
	# transparent quad and needs clean depth separation, not a z-fight.
	ring.global_position = Vector3(world_pos.x, y + 0.03, world_pos.z)

## A puff of ground where something heavy landed. Same instantiate-and-self-free idiom as `splash`,
## and centralised here for the same reason: the ogre's footfalls, its slam and (later) anything
## else with weight all want it, and none of them should carry a scene preload of their own.
##
## `scale` is the whole dial: 0.6 is a footstep, 1.8 is a two-handed slam landing.
func dust(world_pos: Vector3, scale := 1.0) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var puff := FOOT_DUST.instantiate() as Node3D
	tree.current_scene.add_child(puff)
	puff.global_position = world_pos + Vector3.UP * 0.05
	puff.scale = Vector3.ONE * clampf(scale, 0.4, 2.4)


func hitstop(duration := 0.08, scale := 0.05) -> void:
	if duration <= 0.0:
		return          # a zero ask must not deepen (or shorten) someone else's freeze
	var until := Time.get_ticks_msec() * 0.001 + duration
	if _active:
		# A second ask JOINS the freeze in flight: latest deadline, deepest scale. It used to be
		# dropped outright, which silently swallowed exactly the asks that matter most — the
		# kill-blow landing inside its own swing's chip-freeze, the player hurt during an
		# enemy's contact stop. Merging keeps the one-writer discipline (still only this
		# function touches time_scale here) while letting the strongest opinion win.
		_stop_until = maxf(_stop_until, until)
		Engine.time_scale = minf(Engine.time_scale, scale)
		return
	_active = true
	_stop_until = until
	Engine.time_scale = scale
	while true:
		var left := _stop_until - Time.get_ticks_msec() * 0.001
		if left <= 0.0:
			break
		# create_timer(sec, process_always, process_in_physics, ignore_time_scale)
		await get_tree().create_timer(left, true, false, true).timeout
	Engine.time_scale = 1.0
	_active = false

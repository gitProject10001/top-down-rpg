extends CharacterBody3D
## THE RAFT (WA4 prototype): a rideable float on the wilds' flat water. CharacterBody3D over
## RigidBody3D because buoyancy here is ONE LINE — every water region is a dead-flat surface
## at an analytic height (Water.surface_y), so simulated buoyancy would buy nothing but
## tuning pain. MOTION_MODE_FLOATING because the bed rising toward a shore must be a WALL to
## slide along, never a floor to climb: the hull draws DRAFT metres, the bilinear bed crosses
## that plane where the water shallows, and move_and_slide grounds the raft on the shore
## slope by construction — no shoreline data, no second collider.
##
## Boarding is door.gd's InteractZone pattern verbatim; the rider reparents under Deck, keeps
## standing visibly (hiding him would orphan the camera), and the Ride state (ride.gd) does
## nothing but wait for the next `interact` to ask for a landing.

const DRAFT := 0.12                           ## hull depth below the waterline
const ACCEL := 3.0                            ## m/s^2 toward stick input
const TOP_SPEED := 4.5
const DRAG := 1.2                             ## s^-1 velocity bleed — a loosed stick drifts out
const YAW_RATE := 3.0                         ## how eagerly the hull noses into its travel
const BOW_EVERY := 0.35                       ## metres of travel per bow wake ring
const STERN_EVERY := 0.5
## THE HULL IS A SOLID TOO, and it displaces exactly its draft.
##
## bed_at() = max(terrain, obstacle_top), so setting the top to bed + DRAFT leaves surface - bed -
## DRAFT of water where there was surface - bed: the column loses exactly the hull's draft, which
## is exactly the volume a floating body displaces. Shallow-water theory has no vertical structure,
## so water sitting ON the keel rather than under the hull is the standard approximation and costs
## nothing that is visible - the free surface is what gets drawn, and its volume is right.
##
## Half-extents match the wake points the hull already uses: +/-0.5 across, +/-1.1 fore and aft.
const HULL := Vector2(0.5, 1.1)
const LANDING_REACH := 1.4                    ## how far ashore disembark probes
const LANDING_MAX_DEPTH := 0.35               ## deeper than this is not a landing, keep sailing

var _rider: Player = null
var _near: Player = null
var _board_tween: Tween = null
var _bow_travel := 0.0
var _stern_travel := 0.0
var _t := 0.0
var _obs := -1                                ## the solver's id for the hull, -1 when aground

@onready var _visuals: Node3D = $Visuals
@onready var _deck: Marker3D = $Deck
@onready var _zone: Area3D = $InteractZone


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_zone.body_entered.connect(func(b: Node3D) -> void:
		if b is Player:
			_near = b)
	_zone.body_exited.connect(func(b: Node3D) -> void:
		if b == _near:
			_near = null)


func _unhandled_input(event: InputEvent) -> void:
	if _rider == null and _near != null and event.is_action_pressed("interact"):
		board(_near)
		# The Ride state listens for interact on this same event stream — the press that
		# boards must never also step off.
		get_viewport().set_input_as_handled()


func _physics_process(dt: float) -> void:
	_t += dt
	var surface: float = Water.surface_y(global_position)
	if not is_nan(surface):
		global_position.y = surface - DRAFT

	var input := Vector2.ZERO
	if _rider != null:
		# get_move_input is already camera-relative — the same mapping every state uses, so
		# the raft steers exactly like the body does.
		input = _rider.get_move_input()
	if input.length() > 0.1:
		velocity += Vector3(input.x, 0.0, input.y).normalized() * ACCEL * dt
	velocity -= velocity * minf(DRAG * dt, 0.9)
	velocity.y = 0.0
	if velocity.length() > TOP_SPEED:
		velocity = velocity.normalized() * TOP_SPEED
	move_and_slide()

	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), YAW_RATE * dt)
	# The bob is cosmetic and stays on Visuals: the collider must not breathe.
	_visuals.position.y = 0.03 * sin(_t * 1.1) + 0.02 * sin(_t * 1.7)
	_visuals.rotation.x = -0.05 * speed / TOP_SPEED

	_hull(surface)
	_wake(speed, dt)


## Keep the hull registered with the solver as a solid drawing its own draft, turning with the boat.
##
## THE ROTATION IS THE REASON THIS IS A BOX AND NOT A DISC. A raft that yaws presents a different
## width to its travel depending on where it is pointing, and that is most of what a wake looks
## like; a cylinder would shoulder water identically in every direction and read as a buoy.
func _hull(surface: float) -> void:
	if is_nan(surface):
		_drop_hull()
		return
	var bed: float = Water.bed_y(global_position)
	# Aground: with less water than the draft there is nothing left to displace, and a solid taller
	# than its own column only quantises the shoreline it is sitting on.
	if surface - bed <= DRAFT * 1.2:
		_drop_hull()
		return
	var at := Vector2(global_position.x, global_position.z)
	if _obs < 0:
		_obs = Ripples.obstacle_add(Ripples.Obstacle.BOX, at, HULL, bed + DRAFT, rotation.y)
	else:
		Ripples.obstacle_move(_obs, at, rotation.y, bed + DRAFT)


func _drop_hull() -> void:
	if _obs >= 0:
		Ripples.obstacle_remove(_obs)
		_obs = -1


func _exit_tree() -> void:
	_drop_hull()


## Distance-cadenced wake rings: a bow point and two stern quarters, silent when drifting.
func _wake(speed: float, dt: float) -> void:
	if speed < 0.5:
		return
	_bow_travel += speed * dt
	if _bow_travel >= BOW_EVERY:
		_bow_travel = 0.0
		# THROUGH Water.wake, NOT Ripples.splash - the cap is a gameplay judgement and the solver
		# must not hold it. The ring was 0.6 m, which is three texels, and measured a 26 mm wake
		# against a 6 mm noise floor; 1.4 m of the same poke measures 109 mm. Wavelength was doing
		# far more work here than amplitude ever was.
		Water.wake(to_global(Vector3(0.0, 0.0, -1.1)), 1.4, 0.06 + 0.08 * speed)
	_stern_travel += speed * dt
	if _stern_travel >= STERN_EVERY:
		_stern_travel = 0.0
		for x in [-0.5, 0.5]:
			Water.wake(to_global(Vector3(x, 0.0, 1.1)), 1.1, 0.05 + 0.04 * speed)


func board(p: Player) -> void:
	# Never take aboard a body that combat currently owns — a dead player must stay dead,
	# and a hurt one must finish flinching before it can sail.
	var fsm := p.get_node_or_null("StateMachine") as StateMachine
	if fsm != null and fsm.current_state != null \
			and fsm.current_state.name.to_lower() in ["hurt", "dead"]:
		return
	_rider = p
	p.velocity = Vector3.ZERO
	var col := p.get_node_or_null("Collision") as CollisionShape3D
	if col != null:
		col.set_deferred("disabled", true)
	p.reparent(_deck)
	# Kept so an early exit (hurt during the step-aboard) can kill it — a live tween on a
	# reparented body would otherwise drag the player toward the NEW parent's origin.
	_board_tween = create_tween()
	_board_tween.tween_property(p, "position", Vector3.ZERO, 0.2)
	if fsm != null:
		fsm.transition_to("Ride")
	Fx.splash(global_position, 0.8)
	Water.wake(global_position, 1.6, 0.35)


## Step ashore, preferring standable ground within reach; with none in reach the rider steps
## into the water beside the stern instead — every water in this world is wadeable (0.55 m at
## its deepest), so a raft can never strand its rider.
func disembark() -> void:
	if _rider == null:
		return
	var spot := _find_landing()
	if not spot.is_finite():
		var stern := to_global(Vector3(0.0, 0.0, 1.6))
		spot = Vector3(stern.x, global_position.y + DRAFT, stern.z)
	var p := _let_go()
	# `spot` is a FOOT position (ray hit, or the waterline); the body's root rides ~1.07 m
	# above the feet, so park the root a body-height up and let it settle the last hand.
	p.global_position = spot + Vector3(0.0, 1.3, 0.0)
	var fsm := p.get_node_or_null("StateMachine")
	if fsm != null:
		fsm.transition_to("Idle")
	Fx.splash(p.global_position, 0.7)


## The raft's half of leaving Ride by ANY door (ride.gd's exit calls this on Hurt/Dead): give
## the body back to the world where it stands, collider on, no state change of our own — the
## interrupting state owns what happens next. Deferred reparent because a Hurt/Dead
## transition can arrive inside a physics signal, where changing the tree is illegal.
func force_eject() -> void:
	if _rider == null:
		return
	var p := _let_go(true)
	p.velocity = Vector3.ZERO


func _let_go(deferred := false) -> Player:
	var p := _rider
	_rider = null
	if _board_tween != null and _board_tween.is_valid():
		_board_tween.kill()
	_board_tween = null
	if deferred:
		p.call_deferred("reparent", get_parent())
	else:
		p.reparent(get_parent())
	p.velocity = Vector3.ZERO
	var col := p.get_node_or_null("Collision") as CollisionShape3D
	if col != null:
		col.set_deferred("disabled", false)
	return p


func _find_landing() -> Vector3:
	var space := get_world_3d().direct_space_state
	for dir: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var candidate := global_position + dir * (LANDING_REACH + 0.8)
		var q := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 2.0,
				candidate + Vector3.DOWN * 3.0, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.position
		# Standable: at most knee water, and no cliff between deck and ground.
		if Water.depth_at(ground) <= LANDING_MAX_DEPTH \
				and absf(ground.y - global_position.y) < 1.4:
			return ground
	return Vector3.INF

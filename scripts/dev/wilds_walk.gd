extends Node3D
## PLAY THE WILDS: press F6 on scenes/dev/wilds_walk.tscn and you are standing at SpawnA with
## the game's own Player and CameraRig; TAB lifts you into the fly camera (RMB look, WASD+EQ,
## wheel speed, SHIFT boost) and TAB drops you back. The crypt_tuner recipe, minus the tuning
## panels: the ZONE stays pure (no zone self-bootstraps a player in this project — the World
## swaps zones around persistent things that live in main.tscn), so playing one directly takes
## a dev wrapper like this.
##
## The environment is LIFTED from main.tscn with duplicate(true) rather than re-authored —
## docs/anime-look-todo.md A3: a scene that does not run the game's own look is a second look,
## drifting. The sun copies main's colour/energy/shadow dials but keeps the outdoor angle the
## wilds shots were framed at; the wilds' own camera claim pushes shadow_distance to 60 the
## moment the player stands in it, exactly as in game.

const ZONE := "res://scenes/world/zone_wilds.tscn"

# RIGHT-STICK ORBIT, this scene only: full 360 yaw, pitch held in a top-down band, and a
# little zoom that rides the pitch (flatter = slightly closer, steeper = slightly wider) —
# never enough to become a shoulder camera; the 45 degree floor is the promise. Fed to the
# rig through its own claim stack at INTERIOR priority: above the wilds' shadow claim, below
# a conversation push-in, and re-claimed per frame so it cannot be stomped by claim churn.
const ORBIT_YAW_SPEED := 2.6              ## rad/s at full stick
const ORBIT_PITCH_SPEED := 0.9            ## rad/s at full stick
const ORBIT_PITCH_MIN := deg_to_rad(45.0)
const ORBIT_PITCH_MAX := deg_to_rad(70.0)
const ORBIT_ZOOM_SWING := 0.3             ## zoom change across the full pitch band

## Authored map to walk (empty = a fresh rolling map). Same dials the zone itself exposes.
@export var map: WildsMap
## Non-zero pins the seed; 0 rolls fresh each play, the crypt's dungeon_seed contract.
@export var map_seed := 0
## STREAM passthrough (the zone's own dial): on, the bench streams like the game; off, the
## whole map stands at once — what a bench whose subject must exist everywhere needs
## (water_lab teleports the player to a shore no spawn ring would have warmed).
@export var stream := true
@export var walk_on_start := true

var _walking := false
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _base_pitch := 0.0


func _ready() -> void:
	_lift_environment()
	($Sun as Node3D).rotation_degrees = Vector3(-50.0, -35.0, 0.0)

	# The right stick belongs to the ORBIT here, so the rig's built-in right-stick peek is
	# silenced the scene-local way: peek_distance is an exported dial, and zero disarms it
	# without touching camera_rig.gd. Start the orbit on the authored viewing angle, read off
	# the rig's own camera rather than restated as a magic number.
	($CameraRig as Node3D).set("peek_distance", 0.0)
	var rig_cam := $CameraRig/Camera3D as Camera3D
	_base_pitch = atan2(rig_cam.position.y, rig_cam.position.z)
	_orbit_pitch = _base_pitch

	var zone := (load(ZONE) as PackedScene).instantiate()
	zone.set("map", map)
	zone.set("map_seed", map_seed)
	zone.set("stream", stream)
	add_child(zone)                          # builds synchronously; SpawnA exists after this

	var spawn := zone.find_child("SpawnA", true, false) as Node3D
	var player := $Player as Node3D
	var fly := $FlyCam as Node3D
	if spawn != null:
		player.global_position = spawn.global_position + Vector3(0.0, 0.2, 0.0)
		fly.global_position = spawn.global_position + Vector3(0.0, 14.0, 18.0)
		($FlyCam as Camera3D).look_at(spawn.global_position)
	_set_mode(walk_on_start)
	_hint()


## The game's own environment, copied rather than re-authored. duplicate(true) is mandatory:
## main.tscn's Environment is a shared cached sub-resource, and zone code mutates whatever it
## is handed — without the copy this bench would dirty the editor's copy of the game look.
func _lift_environment() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var here := $WorldEnvironment as WorldEnvironment
	if we != null and here != null and we.environment != null:
		here.environment = we.environment.duplicate(true)
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		var mine := $Sun as DirectionalLight3D
		mine.light_color = sun.light_color
		mine.light_energy = sun.light_energy
		mine.shadow_enabled = sun.shadow_enabled
		mine.directional_shadow_max_distance = sun.directional_shadow_max_distance
	main.queue_free()


## The orbit itself. Runs only while walking — the fly camera owns the sticks otherwise.
## Player movement stays screen-relative for free: get_move_input maps WASD through the rig's
## yaw, so turning the camera turns the controls with it, exactly as a shipped orbit would.
func _process(delta: float) -> void:
	if not _walking:
		return
	var rig := get_node_or_null("CameraRig")
	if rig == null or not rig.has_method("claim_frame"):
		return
	var rs := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	# Stick right swings the camera clockwise seen from above; stick up tilts toward top-down
	# (get_vector answers up as NEGATIVE y, hence both signs).
	_orbit_yaw -= rs.x * ORBIT_YAW_SPEED * delta
	_orbit_pitch = clampf(_orbit_pitch - rs.y * ORBIT_PITCH_SPEED * delta,
			ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
	# Zoom rides the pitch, anchored so the authored 53 degree angle is exactly zoom 1.0.
	var zoom: float = clampf(1.0 + (_orbit_pitch - _base_pitch)
			/ (ORBIT_PITCH_MAX - ORBIT_PITCH_MIN) * ORBIT_ZOOM_SWING, 0.85, 1.2)
	# Shadow 60 restates the wilds camera zone's claim — the top claim owns the sun.
	rig.claim_frame(self, zoom, _orbit_yaw, _orbit_pitch, Vector3.ZERO, 60.0, Vector3.ZERO, 5)


# ---------------------------------------------------------------- fly / walk ----------------
# Copied from crypt_tuner (itself from whinbek_lookdev:136): toggle processing and swap which
# Camera3D is current — deliberately NOT CameraRig.claim_frame, which is about which zone owns
# the framing, not about which camera the viewport looks through.


func _set_mode(walk: bool) -> void:
	_walking = walk
	var player := get_node_or_null("Player") as Node3D
	var rig := get_node_or_null("CameraRig") as Node3D
	var fly := get_node_or_null("FlyCam") as Camera3D
	if player != null:
		player.visible = walk
		player.set_process(walk)
		player.set_physics_process(walk)
		player.set_process_input(walk)
		player.set_process_unhandled_input(walk)
	if rig != null:
		rig.set_physics_process(walk)
		# SNAP, DO NOT LERP. The rig eases at follow_speed 6.0 and has not been tracking while
		# flying — without this, entering WALK is a two-second swoop from wherever it last was.
		if walk and player != null:
			rig.global_position = player.global_position
		var rig_cam := rig.get_node_or_null("Camera3D") as Camera3D
		if rig_cam != null and walk:
			rig_cam.current = true
	if fly != null:
		fly.set_process(not walk)
		fly.set_process_unhandled_input(not walk)
		if not walk:
			fly.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_TAB:
		_set_mode(not _walking)
		get_viewport().set_input_as_handled()


func _hint() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hint"
	add_child(layer)
	var label := Label.new()
	label.text = ("TAB  walk / fly      walk: A/Space jump · B/Shift dodge · right stick orbits"
			+ "      fly: RMB look · WASD+EQ move · wheel speed")
	label.position = Vector2(10.0, 8.0)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.55))
	label.add_theme_font_size_override("font_size", 13)
	layer.add_child(label)

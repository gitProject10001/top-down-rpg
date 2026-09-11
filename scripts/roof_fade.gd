class_name RoofFade
extends Area3D
## Fades occluding meshes (roof, walls) when the player stands where they'd block the camera —
## inside the house, or in the garden close behind it. Fades back the moment they leave.
##
## HOW: GeometryInstance3D.transparency is a per-INSTANCE fade in Godot 4 — no material surgery
## on the imported .blend needed. Meshes are found by NAME PREFIX inside the parent zone, because
## .blend imports rebuild their internal hierarchy on every reimport (a hard NodePath would break
## each time the kit is edited in Blender).
##
## SHARED MESHES: several zones can fade the same mesh (RoofZone and GardenNearZone both fade
## "Roof"). If each zone tweened independently, crossing between zones would make an exit-fade
## and an enter-fade FIGHT over the same property (last tween wins — order is luck). So holds are
## REFERENCE-COUNTED on the mesh itself: it fades out on the first hold, and back in only when
## the LAST zone releases it.
##
## NOT FOR GLADEKIT BUILDINGS — see scripts/see_through.gd. This one needs a node it can point at,
## and a GladeWall batches every brick in its footprint into one MultiMeshInstance per brick
## VARIANT: the only node-level fade available there is "the whole building", which takes the far
## wall with the near one. That half is solved per fragment in shaders/painted_env.gdshader instead.
## Two mechanisms because there are two kinds of subject, not because one of them is legacy.

@export var mesh_names := PackedStringArray(["Roof"])  ## name prefixes of the meshes to fade
@export var faded := 0.95                ## transparency while held (1 = fully invisible)
@export var fade_time := 0.35

## INTERIOR DIMMING (optional): while the player is inside, pull the world's sun + ambient
## down so the exterior reads dusky (never black) and the room's own lights take over.
## The interior stays warm because fire/chandelier omnis are untouched.
@export var dim_exterior := false
@export var dim_sun_factor := 0.25       ## sun energy multiplier while inside
@export var dim_ambient_factor := 0.45   ## ambient energy multiplier while inside
@export var dim_time := 0.5

var _meshes: Array[GeometryInstance3D] = []

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	# Search the whole zone (our parent) for matching meshes, wherever the import nested them.
	_collect(get_parent())
	if _meshes.is_empty():
		push_warning("RoofFade: nothing matching %s found under %s" % [mesh_names, get_parent().name])

func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		for prefix in mesh_names:
			if String(node.name).begins_with(prefix):
				_meshes.append(node)
				break
	for c in node.get_children():
		_collect(c)

func _on_enter(body: Node3D) -> void:
	if body.is_in_group("player"):
		for m in _meshes:
			_hold(m, +1)
		if dim_exterior:
			_hold_dim(+1)

func _on_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		for m in _meshes:
			_hold(m, -1)
		if dim_exterior:
			_hold_dim(-1)

func _hold(m: GeometryInstance3D, delta: int) -> void:
	hold(m, delta, faded, fade_time)


## Adjust the mesh's hold count and start a fade only when it crosses 0 <-> 1.
## NOTE: the skip check compares against the PENDING target (meta), never the current
## transparency — a tween created this frame hasn't ticked yet, so comparing the live value
## would let an enter+exit in the same physics frame leave the enter's tween running forever.
##
## STATIC, and shared: scripts/occluder_fade.gd (the camera's see-through) holds meshes with
## the same protocol and the same meta keys, so a zone and the camera can never fight over one
## wall — it fades on the first hold, back on the last release. Two holders with different
## `faded` levels re-tween to the latest holder's level when the count changes.
##
## FULLY FADED MEANS HIDDEN. Godot keeps drawing an instance at transparency 1.0 — through the
## transparent pipeline, sorted, every fragment shaded by every light and the fog — so a whole
## storey faded out above the player (occluder_fade's level rule) still cost 17 ms a frame
## (measured on the cyber building at 1600 × 900: 25.6 → 8.5 ms with the storey hidden). When a
## fade to 1.0 completes the mesh is switched invisible, and the next hold change brings it
## back before its fade-in tween starts. A partial fade (walls at 0.85) is untouched: it keeps
## drawing, and keeps its shadow.
static func hold(m: GeometryInstance3D, delta: int, faded: float, fade_time: float) -> void:
	var count := maxi(int(m.get_meta("rf_holds", 0)) + delta, 0)
	m.set_meta("rf_holds", count)
	var target := faded if count > 0 else 0.0
	var pending := float(m.get_meta("rf_target", 0.0))   # 0.0 = at-rest default (opaque)
	if is_equal_approx(pending, target):
		return
	m.set_meta("rf_target", target)
	if m.has_meta("rf_tween"):
		var old: Tween = m.get_meta("rf_tween")
		if old and old.is_valid():
			old.kill()
	if m.has_meta("rf_hidden"):
		m.remove_meta("rf_hidden")
		m.visible = true
	var tw := m.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "transparency", target, fade_time)
	if target >= 1.0:
		tw.tween_callback(func() -> void:
			if is_instance_valid(m) and float(m.get_meta("rf_target", 0.0)) >= 1.0:
				m.set_meta("rf_hidden", true)
				m.visible = false)
	m.set_meta("rf_tween", tw)

func _hold_dim(delta: int) -> void:
	hold_dim(get_tree(), delta, dim_sun_factor, dim_ambient_factor, dim_time)


## Refcounted exterior dim, same pattern as _hold: state lives as meta on the SUN node so
## several interior zones can never fight over the world light. Base values are captured the
## first time any zone touches them.
##
## STATIC, and shared: scripts/interior_view.gd dims the world for GladeKit interiors, and if it
## kept its own count the two would fight over the same sun exactly the way two zones would. One
## protocol, one set of meta keys, one winner.
static func hold_dim(tree: SceneTree, delta: int, dim_sun_factor: float,
		dim_ambient_factor: float, dim_time: float) -> void:
	var sun := tree.get_first_node_in_group("sun") as DirectionalLight3D
	var env_node := tree.get_first_node_in_group("world_env") as WorldEnvironment
	if sun == null or env_node == null or env_node.environment == null:
		return
	var env := env_node.environment
	if not sun.has_meta("dim_base"):
		sun.set_meta("dim_base", sun.light_energy)
		sun.set_meta("dim_base_ambient", env.ambient_light_energy)
	var count := maxi(int(sun.get_meta("dim_holds", 0)) + delta, 0)
	sun.set_meta("dim_holds", count)
	var target_pending := 1.0 if count == 0 else dim_sun_factor
	var pending := float(sun.get_meta("dim_target", 1.0))
	if is_equal_approx(pending, target_pending):
		return
	sun.set_meta("dim_target", target_pending)
	if sun.has_meta("dim_tween"):
		var old: Tween = sun.get_meta("dim_tween")
		if old and old.is_valid():
			old.kill()
	var inside := count > 0
	var tw := sun.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(sun, "light_energy",
		float(sun.get_meta("dim_base")) * (dim_sun_factor if inside else 1.0), dim_time)
	tw.tween_property(env, "ambient_light_energy",
		float(sun.get_meta("dim_base_ambient")) * (dim_ambient_factor if inside else 1.0), dim_time)
	sun.set_meta("dim_tween", tw)

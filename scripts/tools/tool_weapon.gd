class_name ToolWeapon
extends Node3D
## Base for the three tool-weapons. Each one is a WEAPON and a DUNGEON KEY on the same button, and
## which of the two you get is decided by what happens to be in front of you — never by a mode
## switch. That is the whole Zelda half of this design: the hookshot does not have a combat setting
## and a puzzle setting, it has a rope.
##
## Subclasses override use(). Everything shared lives here: cooldowns (scaled by the player's Logic),
## the cone/radius queries the three of them all need, and the throwaway effect meshes.
##
## TARGETS ARE FOUND BY GROUP, not by physics raycast. The puzzle objects are self-building greybox
## on whatever layer their body happens to use, and inventing a layer scheme for four props would be
## a lot of bookkeeping to answer a question a distance test answers exactly. Groups also degrade
## gracefully: a scene with no cracked walls in it simply returns nothing.

@export var tool_name := ""
@export var cooldown := 1.0

var tint := Color.WHITE                        ## the characteristic colour this tool answers to
var blurb := ""                                ## one line, shown when the quartermaster offers it

var _ready_at := 0.0


## Override. `player` is the Player node; use aim_dir() and the query helpers below.
func use(_player: Node3D) -> void:
	pass


func is_ready() -> bool:
	return Time.get_ticks_msec() / 1000.0 >= _ready_at


func start_cooldown() -> void:
	var traits := get_node_or_null("/root/Traits")
	var scale: float = traits.cooldown_scale() if traits else 1.0
	_ready_at = Time.get_ticks_msec() / 1000.0 + cooldown * scale


## 0 = ready, 1 = just fired. The HUD draws this.
func cooldown_frac() -> float:
	var traits := get_node_or_null("/root/Traits")
	var scale: float = traits.cooldown_scale() if traits else 1.0
	var span := maxf(cooldown * scale, 0.001)
	return clampf((_ready_at - Time.get_ticks_msec() / 1000.0) / span, 0.0, 1.0)


# --- shared queries ----------------------------------------------------------------------------

## Where the tool is pointed: the player's aim, flattened to the ground plane. Falls back to the
## body's facing when the cursor is sitting on top of them.
static func aim_dir(player: Node3D) -> Vector3:
	var to: Vector3 = player.aim_point() - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		to = -(player.get("visuals") as Node3D).global_transform.basis.z
		to.y = 0.0
	return to.normalized()


## Everything in `group` inside a cone, nearest first. `half_angle` in degrees; 180 means "a circle"
## and is how the hammer asks for its radius.
static func in_cone(from: Node3D, group: String, dir: Vector3, reach: float,
		half_angle: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for n in from.get_tree().get_nodes_in_group(group):
		var t := n as Node3D
		if t == null or not is_instance_valid(t) or not t.is_inside_tree():
			continue
		var to: Vector3 = t.global_position - from.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > reach or dist < 0.01:
			continue
		if half_angle < 180.0 and rad_to_deg(dir.angle_to(to / dist)) > half_angle:
			continue
		found.append(t)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(from.global_position) \
				< b.global_position.distance_squared_to(from.global_position))
	return found


## Is this enemy something you pull, or something you pull YOURSELF toward?
##
## Decided on POISE, not hit points, because poise is already this codebase's own light/heavy axis:
## enemy.gd's comment for flinches_on_hit reads "grunts flinch on EVERY hit; armored foes ignore
## light hits". The brute is the only thing that does not flinch, and it is exactly the thing a rope
## should fail to move.
static func is_heavy(enemy: Node) -> bool:
	if enemy == null:
		return false
	# get() on a property the script does not declare returns null — which is how a swarmling
	# (a different script entirely, with no poise system at all) answers "light" without a
	# special case.
	var flinches: Variant = enemy.get("flinches_on_hit")
	if flinches != null and not bool(flinches):
		return true
	var poise: Variant = enemy.get("max_poise")
	return poise != null and int(poise) >= 5


static func hurt(enemy: Node, amount: int, source: Node) -> void:
	var health := enemy.get_node_or_null("Health")
	if health and health.has_method("take_damage") and health.is_alive():
		health.take_damage(amount, source)


# --- throwaway effect meshes -------------------------------------------------------------------
#
# Built in code and freed on a tween, so no tool needs a .tscn or a shader. Unshaded and
# depth-tested-off so they read against dungeon walls under the fixed camera.

static func _fx_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 2.0
	return m


## Attach an effect mesh to the scene and fade it out. `host` only supplies the tree.
static func _emit(host: Node, mesh: Mesh, mat: StandardMaterial3D, at: Transform3D,
		life := 0.3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The dungeon's VoxelGI probes grow to contain every VisualInstance3D under a room, visible or
	# not (RoomGI._drop_of). A one-frame effect has no business coarsening a room's lighting.
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	host.get_tree().current_scene.add_child(mi)
	mi.global_transform = at
	var t := mi.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, life)
	t.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, life)
	t.tween_callback(mi.queue_free)


## A taut line between two world points — the rope.
static func fx_line(host: Node, from: Vector3, to: Vector3, colour: Color, life := 0.3) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(to - from)
	im.surface_end()
	_emit(host, im, _fx_material(colour), Transform3D(Basis.IDENTITY, from), life)


## A flat fan on the ground: the lantern's cone, drawn where it actually reaches.
static func fx_fan(host: Node, origin: Vector3, dir: Vector3, reach: float, half_angle: float,
		colour: Color, life := 0.35) -> void:
	# Explicit triangles, not a fan: Godot 4 dropped PRIMITIVE_TRIANGLE_FAN entirely (it survives
	# only as a name people remember from 3.x), so the fan is unrolled into one triangle per step.
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 14
	for i in steps:
		var a0 := deg_to_rad(-half_angle + 2.0 * half_angle * float(i) / float(steps))
		var a1 := deg_to_rad(-half_angle + 2.0 * half_angle * float(i + 1) / float(steps))
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(dir.rotated(Vector3.UP, a0) * reach)
		im.surface_add_vertex(dir.rotated(Vector3.UP, a1) * reach)
	im.surface_end()
	var mat := _fx_material(colour)
	mat.albedo_color.a = 0.35
	_emit(host, im, mat, Transform3D(Basis.IDENTITY, origin + Vector3(0, 0.08, 0)), life)


## An expanding ground ring: the hammer's shockwave.
static func fx_ring(host: Node, origin: Vector3, radius: float, colour: Color,
		life := 0.4) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var steps := 36
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		im.surface_add_vertex(Vector3(cos(a), 0.0, sin(a)) * radius)
	im.surface_end()
	_emit(host, im, _fx_material(colour), Transform3D(Basis.IDENTITY, origin + Vector3(0, 0.1, 0)),
			life)

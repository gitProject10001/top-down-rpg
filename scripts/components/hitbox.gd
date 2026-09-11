class_name HitBox
extends Area3D
## The "I deal damage here" volume. Harmless until an attack switches it ON for its active frames.
##
## IMPORTANT (Godot gotcha): toggling `monitoring` on does NOT fire `area_entered` for targets that
## are ALREADY inside the volume — and during a melee swing the enemy is usually already in front.
## So we keep monitoring ON permanently and gate damage with an `_active` flag instead; on activate
## we ALSO sweep `get_overlapping_areas()` to catch whoever's already standing in the arc.
##
## It remembers who it already hit this activation, so one swing damages a target once.

## `applied` is the damage that actually landed — 0 for a blocked, parried or i-framed contact.
## Listeners branch on it: hitstop and impact shake belong to blows that changed hp, and firing
## them identically for an absorbed hit made the loudest feedback in the game carry no information.
signal dealt_hit(target: Node, position: Vector3, applied: int)

@export var damage := 1
@export var hit_vfx: PackedScene   ## optional spark/burst spawned at each hit point

var _active := false
var manual_contact := false
var _already_hit: Array[Node] = []
var _viz: Array[MeshInstance3D] = []
var _viz_mat: StandardMaterial3D

func _ready() -> void:
	monitoring = true
	area_entered.connect(_on_area_entered)
	_build_viz.call_deferred()


# --- Debug view (Dbg autoload, F3): the damage volume, dim red when idle, bright while LIVE ---

func _build_viz() -> void:
	_viz_mat = StandardMaterial3D.new()
	_viz_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_viz_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_viz_mat.no_depth_test = true
	_viz_mat.albedo_color = Color(1.0, 0.2, 0.15, 0.12)
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape:
			var m := _mesh_for((c as CollisionShape3D).shape)
			if m == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = _viz_mat
			mi.visible = false
			c.add_child(mi)
			_viz.append(mi)
	set_process(not _viz.is_empty())

static func _mesh_for(shape: Shape3D) -> Mesh:
	if shape is BoxShape3D:
		var b := BoxMesh.new()
		b.size = (shape as BoxShape3D).size
		return b
	if shape is SphereShape3D:
		var s := SphereMesh.new()
		s.radius = (shape as SphereShape3D).radius
		s.height = s.radius * 2.0
		return s
	if shape is CapsuleShape3D:
		var cp := CapsuleMesh.new()
		cp.radius = (shape as CapsuleShape3D).radius
		cp.height = (shape as CapsuleShape3D).height
		return cp
	# The mace's shaft is a cylinder. Without this it collided and dealt damage while drawing
	# nothing under F3, which is the worst state for a debug view to be in: the volume you cannot
	# see is the one you blame the hit on.
	if shape is CylinderShape3D:
		var cy := CylinderMesh.new()
		cy.top_radius = (shape as CylinderShape3D).radius
		cy.bottom_radius = (shape as CylinderShape3D).radius
		cy.height = (shape as CylinderShape3D).height
		return cy
	return null

func _process(_delta: float) -> void:
	var dbg := get_node_or_null("/root/Dbg")
	# THROUGH visible_debug, not off the flag directly: F8 has to be able to override every debug
	# view at once, and a view that reads its own flag is a view that quietly ignores the switch.
	var show: bool = dbg != null and dbg.visible_debug(dbg.show_hitboxes)
	for mi in _viz:
		mi.visible = show
	if show:
		_viz_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.55) if _active else Color(1.0, 0.2, 0.15, 0.1)

## Turn damage ON for the active window and immediately hit anyone already in the arc.
func activate() -> void:
	_already_hit.clear()
	_active = true
	if manual_contact: return
	for area in get_overlapping_areas():
		_try_hit(area)

func deactivate() -> void:
	_active = false

func _on_area_entered(area: Area3D) -> void:
	if _active and not manual_contact:
		_try_hit(area)

func _try_hit(area: Area3D) -> void:
	if not _active: return
	# Thanks to collision masks, anything we detect is already an opposing HurtBox.
	if area is HurtBox and area not in _already_hit:
		_already_hit.append(area)
		var applied: int = (area as HurtBox).apply_hit(damage, self)
		var pos := area.global_position
		dealt_hit.emit(area, pos, applied)
		# The spark marks damage, not overlap — a blocked hit has the shield's own feedback, and
		# a spark on top of it says "that hurt" about a hit that did not.
		if hit_vfx and applied > 0:
			var fx := hit_vfx.instantiate()
			get_tree().current_scene.add_child(fx)
			(fx as Node3D).global_position = pos

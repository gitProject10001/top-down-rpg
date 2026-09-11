class_name HurtBox
extends Area3D
## The "I can be hit here" volume. A HitBox overlapping this calls apply_hit(), which routes the
## damage to this entity's Health. Keeping it on its own Area3D means the body doesn't care about
## the physics of being hit — it just owns a Health and a HurtBox.
##
## Collision layers do the team-sorting (player HurtBox on a different layer than enemy HurtBox),
## so a sword that only masks the enemy layer can never hit the player who swings it.

## Optional explicit Health. If left empty we auto-find a sibling "Health" node on the same entity
## (more reliable than a hand-written NodePath export, which doesn't always resolve from a .tscn).
@export var health: Health

func _ready() -> void:
	if health == null:
		var parent := get_parent()
		if parent:
			health = parent.get_node_or_null("Health") as Health
	_build_viz.call_deferred()


# --- Debug view (Dbg autoload, F3): the receivable volume in green ---

var _viz: Array[MeshInstance3D] = []

func _build_viz() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = Color(0.2, 1.0, 0.35, 0.12)
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape:
			var m := HitBox._mesh_for((c as CollisionShape3D).shape)
			if m == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = mat
			mi.visible = false
			c.add_child(mi)
			_viz.append(mi)
	set_process(not _viz.is_empty())

func _process(_delta: float) -> void:
	var dbg := get_node_or_null("/root/Dbg")
	# THROUGH visible_debug, not off the flag directly: F8 has to be able to override every debug
	# view at once, and a view that reads its own flag is a view that quietly ignores the switch.
	var show: bool = dbg != null and dbg.visible_debug(dbg.show_hitboxes)
	for mi in _viz:
		mi.visible = show

## Returns the damage that actually landed: 0 when the owner intercepted it (block, parry), when
## Health refused it (i-frames, already dead), or when there is no Health to take it.
func apply_hit(damage: int, source: Node = null) -> int:
	# Let the owning entity intercept the hit first (e.g. the player blocking/parrying).
	var final := damage
	var ent := get_parent()
	if ent and ent.has_method("on_incoming_hit"):
		final = ent.on_incoming_hit(damage, source)
	if health and final > 0:
		return health.take_damage(final, source)
	return 0

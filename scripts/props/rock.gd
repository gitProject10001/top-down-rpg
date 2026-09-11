class_name Rock
extends StaticBody3D
## A boulder lying around, waiting to be picked up and thrown at somebody.
##
## THE MESH IS GENERATED, not an asset. Same argument blob_shadow.gd makes for its texture: a
## lumpy grey rock is a handful of vertices and no art direction, and an asset would be one more
## file to keep in step with nothing. It is a low-poly sphere pushed around by a seeded hash, so
## every rock looks different and every rock looks the SAME every time — which matters, because
## `docs/directed-proceduralism.md` is emphatic that randomness pinned to time rather than to place
## is what makes procedural content shimmer.
##
## The seed is the spawn position, so a rock's shape is a property of where it lies. Reload the
## scene and it is the same rock.

@export var radius := 0.55
@export var seed_offset := 0

## Set while the ogre is holding it, so nothing else tries to pick up the same rock.
var held := false

var _mi: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group("rock")
	collision_layer = 1
	collision_mask = 0
	_build()


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	# Seeded from WHERE it is, not from when it was made. See the header.
	var p := global_position
	rng.seed = hash(Vector3i(int(p.x * 8.0), int(p.y * 8.0), int(p.z * 8.0))) + seed_offset

	_mi = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 7
	sm.rings = 4
	_mi.mesh = sm
	var mat := StandardMaterial3D.new()
	var v := rng.randf_range(0.34, 0.46)
	mat.albedo_color = Color(v, v * 0.98, v * 0.92)
	mat.roughness = 0.95
	_mi.material_override = mat
	# Squash and tilt it. A sphere reads as a ball; the same sphere at 0.7 on one axis and tipped
	# over reads as a rock, which is the whole budget this needs.
	_mi.scale = Vector3(rng.randf_range(0.85, 1.25), rng.randf_range(0.6, 0.9),
			rng.randf_range(0.85, 1.25))
	_mi.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, TAU),
			rng.randf_range(-0.5, 0.5))
	add_child(_mi)

	_shape = CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius * 0.85
	_shape.shape = sph
	add_child(_shape)


## Picked up: stop being world collision and ride the hand.
func take(by: Node3D, at := Vector3.ZERO) -> void:
	held = true
	remove_from_group("rock")
	_shape.disabled = true
	get_parent().remove_child(self)
	by.add_child(self)
	position = at
	rotation = Vector3.ZERO


## The size a thrown copy should be, so the projectile matches the rock that was lifted.
func visual_scale() -> Vector3:
	return _mi.scale * radius

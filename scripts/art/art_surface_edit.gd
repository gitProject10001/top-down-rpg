@tool
class_name ArtSurfaceEdit
extends Resource
## Persistent art stamp in the target surface's local coordinates. Deletions are
## tombstones: retaining their stable ID prevents regeneration from restoring them.
enum Layer { GRASS_DENSITY, GRASS_PALETTE, MOSS, DAMP, DAMAGE }

@export var stable_id: String = ""
## Relative to the ArtStudyLayers node's parent (the authoring root).
@export var surface_path: NodePath
@export_enum("Grass density", "Grass palette", "Moss", "Damp", "Damage") var layer: int = Layer.GRASS_DENSITY
@export var local_position := Vector3.ZERO
## The stamp's +Y axis is the surface normal; XZ is its painted plane.
@export var local_rotation_degrees := Vector3.ZERO
@export_range(0.01, 30.0, 0.01, "or_greater", "suffix:m") var radius: float = 1.0
@export_range(-1.0, 1.0, 0.01) var intensity: float = 0.5
@export var seed: int = 0
@export var locked: bool = false
@export var deleted: bool = false

func stamp_transform() -> Transform3D:
	var angles := local_rotation_degrees * (PI / 180.0)
	var r := maxf(radius, 0.001)
	return Transform3D(Basis.from_euler(angles).scaled_local(Vector3(r, r * 0.30, r)), local_position)

func influence(local_point: Vector3) -> float:
	if deleted:
		return 0.0
	var point := stamp_transform().affine_inverse() * local_point
	var plane := 1.0 - smoothstep(0.55, 1.0, Vector2(point.x, point.z).length())
	var depth := 1.0 - smoothstep(0.55, 1.0, absf(point.y))
	return plane * depth

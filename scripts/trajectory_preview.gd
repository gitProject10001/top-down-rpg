class_name TrajectoryPreview
extends MultiMeshInstance3D
## The dotted aim arc shown while charging a ballistic shot — a row of small glowing dots
## sampled along p(s) = origin + v0*s - (0, g/2, 0)*s², i.e. the EXACT curve the arrow will fly
## (the caller must pass v0/t from Projectile.solve_arc, never a separate estimate).
##
## A MultiMesh renders all dots as one draw call; we just move visible_instance_count dots
## every frame while aiming. Dots fade toward the landing point so the eye reads direction.

@export var color := Color(0.6, 0.85, 1.0)
@export var max_dots := 24

func _ready() -> void:
	top_level = true                       # ignore whatever parent we were dropped under
	global_transform = Transform3D.IDENTITY
	multimesh.instance_count = max_dots
	multimesh.visible_instance_count = 0

## Plot the arc. `v0`/`flight_time` come straight from Projectile.solve_arc.
func show_arc(origin: Vector3, v0: Vector3, flight_time: float, g: float) -> void:
	var n := clampi(int(flight_time / 0.045), 8, max_dots)
	multimesh.visible_instance_count = n
	for i in n:
		var s := flight_time * float(i + 1) / float(n + 1)   # skip s=0 (inside the player)
		var p := origin + v0 * s + Vector3(0, -0.5 * g * s * s, 0)
		multimesh.set_instance_transform(i, Transform3D(Basis(), p))
		multimesh.set_instance_color(i, Color(color.r, color.g, color.b, 0.9 - 0.55 * float(i) / float(n)))

func clear() -> void:
	multimesh.visible_instance_count = 0

@tool
class_name Terrain
extends MeshInstance3D
## ONE NUMBER FOR HOW BIG THE WORLD IS.
##
## The ground is a flat quad with a box under it, and those are two resources with two separate
## size fields. Growing the world used to mean remembering both — change the mesh and forget the
## collider and the player walks on air past the old edge, which is a bug that only shows up once
## somebody wanders far enough to find it.
##
## The material never needed telling. ground_clear.gdshader works in world space: it paints the
## same grass whether the quad is 44 metres across or 3200, and it has no tiling to re-scale. So
## the extent is the only dial, and the two resources follow it.
##
## WHAT THIS IS NOT. It is not streaming. One quad of any size is still one draw call and one
## collider, which is fine up to the few hundred metres you can actually see from an isometric
## camera, and wrong for ten square kilometres. The step after this is chunks around the player,
## and the reason it can wait is that nothing here has to change when it arrives: a chunk is this
## same material on a smaller quad at an offset.

## Metres along each side. The quad is centred on the node, so the world runs from -extent/2 to
## +extent/2 on both axes.
@export var extent := 100.0:
	set(value):
		extent = maxf(value, 1.0)
		_apply()

## How deep the collision box sits below the surface. Only has to be thicker than anything that
## could tunnel through it in one physics step.
@export var floor_thickness := 1.0:
	set(value):
		floor_thickness = maxf(value, 0.05)
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var plane := mesh as PlaneMesh
	if plane != null and not plane.size.is_equal_approx(Vector2(extent, extent)):
		# duplicate() first: the mesh is a sub-resource of the scene, and writing through to the
		# shared copy would edit the saved scene from a running game.
		plane = plane.duplicate() as PlaneMesh
		plane.size = Vector2(extent, extent)
		mesh = plane

	var collider := get_node_or_null(^"Collision/Shape") as CollisionShape3D
	if collider == null:
		return
	var box := collider.shape as BoxShape3D
	var want := Vector3(extent, floor_thickness, extent)
	if box != null and not box.size.is_equal_approx(want):
		box = box.duplicate() as BoxShape3D
		box.size = want
		collider.shape = box
	# The box is sunk so its TOP face is the visible surface, not its centre.
	collider.position.y = -floor_thickness * 0.5

extends StaticBody3D
## Invisible containment ring around the arena, with a gap on the stair side so you can enter.
##
## Built in code (not hand-placed colliders) so the whole ring is one tweakable node — change the
## exports to resize/reshape the arena boundary without editing a dozen transforms by hand.

@export var center := Vector3(0, -5, 27)   ## arena centre in world space (Godot coords)
@export var radius := 10.5
@export var segments := 8
@export var wall_height := 2.6
## Segments left open (segment i sits at angle TAU*i/segments, where 0 = +Z/south, quarter-turn
## = +X/east). One gap per exit: the stairs, the warehouse connector, ...
@export var gap_indices := PackedInt32Array([4])

func _ready() -> void:
	var seg_w := TAU * radius / float(segments) * 1.15   # slight overlap, no gaps between segments
	for i in range(segments):
		if i in gap_indices:
			continue
		var a := TAU * i / float(segments)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(seg_w, wall_height, 0.6)
		cs.shape = box
		cs.position = center + Vector3(sin(a) * radius, wall_height * 0.5, cos(a) * radius)
		cs.rotation.y = a                    # face tangential to the circle
		add_child(cs)

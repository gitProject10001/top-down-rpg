@tool
extends StaticBody3D
## Authored proxy and local attachment; never drives world generation.
@export var profile: Resource
@export var anchor_path: NodePath:
	set(value): anchor_path=value; _place()
@export var local_offset := Vector3.ZERO:
	set(value): local_offset=value; _place()
@export var body_color := Color(.45,.3,.2):
	set(value):
		body_color=value
		var body:=get_node_or_null("CapsuleBody") as MeshInstance3D
		if body: body.mesh.material.albedo_color=value
@export var topics := PackedStringArray()
var grounded := false
func _ready() -> void:
	collision_layer=1; collision_mask=0
	add_to_group("conversational_npc")
	var mesh:=MeshInstance3D.new(); mesh.name="CapsuleBody"
	var capsule:=CapsuleMesh.new(); capsule.radius=.28; capsule.height=1.7
	var mat:=StandardMaterial3D.new(); mat.albedo_color=body_color; mat.roughness=1.0
	capsule.material=mat; mesh.mesh=capsule; mesh.position.y=.85
	add_child(mesh,false,Node.INTERNAL_MODE_BACK)
	var shape:=CollisionShape3D.new(); var solid:=CapsuleShape3D.new()
	solid.radius=.28; solid.height=1.7; shape.shape=solid; shape.position.y=.85
	add_child(shape,false,Node.INTERNAL_MODE_BACK)
	_place()
func _place() -> void:
	if not is_inside_tree() or anchor_path.is_empty(): return
	var anchor:=get_node_or_null(anchor_path) as Node3D
	if anchor: global_position=anchor.to_global(local_offset)
func snap_to_ground() -> void:
	_place()
	var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*2,global_position-Vector3.UP*5,1,[get_rid()])
	var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	grounded=not hit.is_empty() and hit.normal.y>.7
	if grounded: global_position.y=hit.position.y+.02

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): _place()

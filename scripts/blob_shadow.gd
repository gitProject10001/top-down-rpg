extends Decal
class_name BlobShadow
## A fake contact shadow that ANCHORS its owner to the ground. Essential in the torch-lit crypt,
## which has no sun to cast a real shadow — without this, entities read as floating (the classic
## top-down depth-perception killer). A short downward Decal that hugs the floor found by a ray
## each physics frame, so it follows the entity across zones and even while airborne (a dash),
## where it shrinks-out to sell height. Drop this scene under any CharacterBody3D.
##
## Godot-First: this is Godot's own projected-Decal feature; the radial texture is generated in
## code so there is no art asset to manage. The box is kept SHORT so it only ever projects onto
## the floor, never smudging the owner's own mesh above it.

@export var radius := 0.55        ## blob radius (metres)
@export var darkness := 0.5       ## peak opacity directly under the owner
@export var max_drop := 5.0       ## how far down to search for the floor
@export var fade_height := 2.2    ## fully faded once the FEET are this high off the ground
@export var foot_offset := 0.0    ## owner-root height above its feet (player root is capsule-
                                  ## centred ≈0.9; enemy roots sit at the feet, so 0). Keeps a
                                  ## grounded shadow at full opacity instead of half-faded.

var _owner: Node3D
var _owner_rid: RID


func _ready() -> void:
	_owner = get_parent() as Node3D
	if _owner is CollisionObject3D:
		_owner_rid = (_owner as CollisionObject3D).get_rid()   # so our ray ignores the owner's body
	top_level = true                                    # live in WORLD space: ignore owner lean/scale/spin
	texture_albedo = _make_texture()
	albedo_mix = 1.0
	upper_fade = 0.0
	lower_fade = 0.0
	normal_fade = 0.0
	modulate = Color(1, 1, 1, 1)
	size = Vector3(radius * 2.0, 0.25, radius * 2.0)    # short Y → projects only onto the floor
	_place()                                            # correct on the very first frame


func _physics_process(_delta: float) -> void:
	_place()


## Raycast down from the owner, sit just above the floor it finds, and fade with height off it.
func _place() -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from := _owner.global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (max_drop + 0.3), 1)
	if _owner_rid.is_valid():
		q.exclude = [_owner_rid]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		visible = false
		return
	visible = true
	var floor_y: float = hit.position.y
	global_position = Vector3(_owner.global_position.x, floor_y + 0.12, _owner.global_position.z)
	rotation = Vector3.ZERO                             # always project straight down
	var height: float = clampf(_owner.global_position.y - floor_y - foot_offset, 0.0, fade_height)
	var m := modulate
	m.a = 1.0 - height / fade_height                    # value-type: reassign, don't poke .a in place
	modulate = m


## Radial black-with-alpha blob: opaque under the owner, feathering to nothing at the edge.
func _make_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / c   # 0 centre → 1 edge
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * darkness                          # soft falloff, scaled to peak darkness
			img.set_pixel(x, y, Color(0, 0, 0, a))
	return ImageTexture.create_from_image(img)

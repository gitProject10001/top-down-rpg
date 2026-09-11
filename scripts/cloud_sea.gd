class_name CloudSea
extends MeshInstance3D
## The infinite sea of clouds the world floats on. A single large quad carries the raymarched
## deck shader (shaders/cloud_sea.gdshader, port of Duke's "Above the clouds" — CC BY-NC-SA,
## non-commercial); the quad FOLLOWS the player in XZ while the shader samples a world-anchored
## field, so the sea is endless without being infinite geometry.
##
## The quad sits above the deck's tallest billows (rays march DOWN from its surface — anything
## above the quad would never render), and below all walkable terrain so depth testing lets
## cliffs and mesas occlude it naturally.

## Deck placement = THIS NODE'S Y (drag it in the editor; the field level follows live).
## The quad is the ceiling rays march down from, held CREST_CLEARANCE_CU above the deck mean so
## even the tallest fuzz-boosted billow is never sliced flat.
@export var world_scale := 0.4        ## metres -> cloud units (bigger = smaller cloud features)
@export var plane_size := 700.0
@export var wind := Vector3(1.0, 0.0, 0.6)
@export var wind_speed := 0.25
@export var fuzz_speed := 0.8
@export var steps := 96
@export var relief := 1.6             ## vertical billow exaggeration (matches shader uniform)
@export var horizon_color := Color(0.62, 0.61, 0.55)   ## matched to the env fog

const CREST_CLEARANCE_CU := 12.5      ## cloud-units from deck mean up to the quad

## ITS OWN RENDER LAYER, so anything that needs to photograph the world without the sea can drop it
## with a cull mask instead of toggling `visible` on a node it does not own. MapRelief's top-down map
## capture is the one caller today, and it used to hide this node and put it back — which fought
## DungeonEnv, which legitimately hides the sea for the whole time you are underground, and left the
## crypt rendering on daylit cloud. A cull mask cannot have that class of bug: nothing is mutated.
##
## Layer 1 is the world and layer 2 is characters (ToonSkin.CHARACTER_LAYER), so this is layer 3.
## Cameras default to every layer, so the sea still renders normally for everyone who has not
## deliberately excluded it.
const MAP_LAYER := 1 << 2

var _mat: ShaderMaterial
var _player: Node3D
var _sun: DirectionalLight3D

func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(plane_size, plane_size)
	mesh = plane

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/cloud_sea.gdshader")
	_mat.set_shader_parameter("noise_tex", _make_random_texture())
	_mat.set_shader_parameter("world_scale", world_scale)
	_mat.set_shader_parameter("wind", wind)
	_mat.set_shader_parameter("wind_speed", wind_speed)
	_mat.set_shader_parameter("fuzz_speed", fuzz_speed)
	_mat.set_shader_parameter("steps", steps)
	_mat.set_shader_parameter("relief", relief)
	_mat.set_shader_parameter("horizon_color", horizon_color)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = MAP_LAYER              # self-configuring, like blob_shadow and toon_skin

	_player = get_tree().get_first_node_in_group("player")
	_sun = get_tree().get_first_node_in_group("sun") as DirectionalLight3D

func _process(_delta: float) -> void:
	if is_instance_valid(_player):
		global_position.x = _player.global_position.x
		global_position.z = _player.global_position.z
	# The node's Y is the quad; the deck mean sits CREST_CLEARANCE below it (live, so the
	# node can be dragged in the running editor to tune the sea height). Relief stretches the
	# world-height of the billows, so the clearance stretches with it.
	_mat.set_shader_parameter("sea_level",
		global_position.y - CREST_CLEARANCE_CU * relief / world_scale)
	if is_instance_valid(_sun):
		# toward-the-sun vector = opposite of the light's forward (-Z) axis
		_mat.set_shader_parameter("sun_dir", _sun.global_transform.basis.z.normalized())

## iq's 3D-noise-from-texture trick needs RANDOM per-texel values (not smooth noise) with
## bilinear filtering — the shader's sampler hints handle filter/repeat.
func _make_random_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var bytes := PackedByteArray()
	bytes.resize(256 * 256 * 4)
	for i in bytes.size():
		bytes[i] = rng.randi() & 0xff
	var img := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, bytes)
	return ImageTexture.create_from_image(img)

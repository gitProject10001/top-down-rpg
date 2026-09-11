extends Node
class_name ToonSkin
## Cel-shades whatever character it is dropped under: walks the owner's MeshInstance3Ds and gives
## each surface a copy of the shared toon material. Self-configuring — drop
## scenes/fx/toon_skin.tscn under any character, same idiom as blob_shadow.
##
## THE LOOK IS NOT DEFINED HERE. It lives in assets/materials/toon_character.tres, which this script
## DUPLICATES per surface. Tune that resource in the Inspector and both the game and the shader lab
## (scenes/dev/shader_lab.tscn) follow — one source of truth, editable and persistent, instead of
## values buried in code. The shader itself (shaders/toon_lit.gdshader) stays verbatim upstream.
##
## What this script still owns, because it is genuinely per-instance:
##   * the imported material's albedo texture/colour, fed into the stock `albedo`/`albedo_texture`
##   * per-material presets (cloth / hair / skin / eye), which only flip stock uniforms
##   * the ink outline attached as next_pass
##   * putting characters on their own render layer (see CHARACTER_LAYER)
##   * the hit-flash, driven through the stock `albedo` tint — no custom uniform needed.
##     enemy.gd routes its white/blue flashes through here when present.

const TEMPLATE := preload("res://assets/materials/toon_character.tres")
const OUTLINE := preload("res://shaders/toon_outline.gdshader")

## Render layer 2 — characters only. Lights that must not touch characters (the player's own
## HeroLight omni, which sits INSIDE the body and would flatten it) exclude this bit from their
## light_cull_mask.
const CHARACTER_LAYER := 2

@export var rim_strength := 0.0           ## scales the template's rim per character (0 = off).
										  ## The stock rim is an untinted white edge glow — with the
										  ## specular it is the main "glass" tell.
@export var spec_strength := 0.0          ## scales the template's specular. The stock specular is
										  ## BINARY (step(0.5,...)) and untinted by albedo, so it
										  ## reads as glass on anything matte. Hair only.
@export var outline_enabled := true       ## inverted-hull outlines need mostly-smooth normals; turn
										  ## OFF for hard-edged multi-part models
@export var outline_width := 0.01     ## ink line thickness, VIEW-SPACE metres (so it is independent
									  ## of each model's import scale). ~0.006 = hairline,
									  ## 0.02 = heavy. This is the CONTOUR, not the rim.
@export var outline_color := Color(0.05, 0.04, 0.06, 1.0)

var _mats: Array[ShaderMaterial] = []     ## the toon materials we own
var _tints: Array[Color] = []             ## their authored albedo tints (to restore after a flash)
var _flash_tween: Tween


func _ready() -> void:
	var root := get_parent() as Node3D
	if root == null:
		return
	for mi: MeshInstance3D in _find_meshes(root):
		if mi.mesh == null:
			continue
		# Own render layer, off the world layer. The player carries a HeroLight omni INSIDE itself
		# to light dark surroundings — but a point light at the body's own centre lights front, back
		# and both sides at once, so N·L is positive nearly everywhere and a shadow side becomes
		# geometrically impossible. That light excludes layer 2, so it lights the world but not us.
		mi.layers = CHARACTER_LAYER
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, _make_toon(mi.get_active_material(s)))


## Copy the shared material and override only what is per-instance.
func _make_toon(src: Material) -> ShaderMaterial:
	var m: ShaderMaterial = TEMPLATE.duplicate()
	var tex: Texture2D = null
	var tint := Color(1, 1, 1, 1)
	var mat_name := ""
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		tex = b.albedo_texture
		tint = b.albedo_color
		mat_name = b.resource_name
	var p := _preset_for(mat_name)

	m.set_shader_parameter("albedo_color", tint)
	if tex:
		m.set_shader_parameter("albedo_texture", tex)
	m.set_shader_parameter("use_rim", p.rim > 0.0)
	m.set_shader_parameter("rim_blend", p.rim)
	m.set_shader_parameter("specular", p.spec)

	if outline_enabled and p.outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("outline_width", p.outline)
		o.set_shader_parameter("outline_color", outline_color)
		m.next_pass = o

	_mats.append(m)
	_tints.append(tint)
	return m


## Per-material presets, keyed off the material NAME (so the art side only has to name its
## materials — see docs/anime-look-todo.md). Hair genuinely is glossy and can take a highlight; a
## sharp specular on fabric is the clearest "vinyl" tell, so cloth gets none.
func _preset_for(mat_name: String) -> Dictionary:
	var n := mat_name.to_lower()
	if n.contains("eye"):
		return {"rim": 0.0, "spec": 0.0, "outline": 0.0}
	if n.contains("hair"):
		return {"rim": rim_strength * 1.2, "spec": spec_strength, "outline": outline_width}
	if n.contains("face") or n.contains("head") or n.contains("skin"):
		return {"rim": rim_strength * 0.6, "spec": 0.0, "outline": outline_width * 0.5}
	# cloth / anything unnamed — most of a character is fabric, so this is the safe default
	return {"rim": rim_strength * 0.6, "spec": 0.0, "outline": outline_width}


## The hit-flash, driven through the STOCK `albedo` tint (no custom uniform): push every surface's
## tint toward `color`, then ease back to the authored tints.
func flash(color: Color, peak := 1.0, dur := 0.3) -> void:
	if _mats.is_empty():
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash.bind(color), peak, 0.0, dur)


func _set_flash(amount: float, color: Color) -> void:
	for i in _mats.size():
		var m := _mats[i]
		if is_instance_valid(m):
			m.set_shader_parameter("albedo_color", _tints[i].lerp(color, amount))


func _find_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_meshes(c))
	return out

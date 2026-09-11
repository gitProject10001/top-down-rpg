extends Node3D
## Put an imported .glb onto the project's PAINTED shader, per surface, without losing its textures.
##
## Attach it to the .glb instance itself, or to a plain Node3D holding several of them — the walk is
## recursive, so one node can skin a whole stand of trees.
##
## WHY THIS EXISTS. The arena blockout arrives from Blender wearing glTF PBR materials, while every
## other piece of environment art in the hub wears assets/materials/painted_env.tres — the wrapped
## lambert with the coloured, saturated shadow. Two shading models in one square is the single
## loudest reason the arena reads as a different game from the map around it.
##
## THE OBVIOUS FIX DOES NOT WORK. `material_override` on the instance replaces ALL surfaces with one
## material, so the four houses would lose plaster, roof, stone and timber to whichever single
## texture was chosen. That is why the neighbouring HouseA can use an override — it has exactly one
## material — and why this cannot.
##
## So the skin is per surface, and painted_env has an `albedo_texture` slot it samples with plain UV
## exactly as StandardMaterial3D does. The generated tiling textures carry across unchanged; what
## changes is how light lands on them.
##
## WHAT COMES FREE WITH IT. painted_env carries the global see-through cone and the interior
## doll's-house cut. The blockout has four houses the player can walk behind and currently no way to
## get any of them out of the way; after this, it inherits both without another line.
##
## MATCHED BY MATERIAL NAME, NEVER BY SURFACE INDEX. Indices are export order, and export order moves
## the moment anyone adds a window in Blender. The name→index map is printed on the first run so a
## rename shows up as a missing key instead of as a silently mis-skinned wall.

## painted_env.tres. Duplicated once per distinct source material, not once per surface.
@export var env_template: ShaderMaterial
## Applied to any surface named in `glass_surfaces`. Leave null until the glass shader exists.
@export var glass_material: Material
@export var glass_surfaces: PackedStringArray = ["bo_glass"]
## Surfaces left on their imported material. Empty by default — everything gets painted.
@export var skip_surfaces: PackedStringArray = []
## TRUE for the foliage .glb files, which are textureless and carry their colour in COLOR_0; FALSE
## for the blockout, whose meshes have no colour attribute at all and would multiply by an undefined
## one. There is no safe default that suits both, so it is stated per node.
@export var use_vertex_color := false
## WHAT BLENDER'S DEFAULT MATERIAL LOOKS LIKE FROM HERE, and why it needs its own answer.
##
## An object nobody assigned a material to exports with no name, no texture and albedo 1.0. That is
## not a colour decision; it is a gap in the source art. But 1.0 is the brightest thing a renderer
## can be handed, so the gap does not read as "untinted" — it reads as a blown-out white slab that
## takes the eye and the exposure with it. Measured in the hub: `Plane` at 4,364 m2 and `Cube_030`
## at 2,259 m2, six and a half thousand square metres of pure white, which is most of what made the
## lighting look broken from the ground.
##
## A material with no texture but a real colour — `Valley`, `Grass` — is a deliberate flat tint and
## is left alone. The test is texture-less AND white, which only the unassigned case satisfies.
## Every one found is listed in the report, because the real fix is in the .blend.
## Authored WARM because the scene it lands in is cool: ambient_light_color (0.6, 0.7, 0.82) at
## energy 0.5 plus a 45% sky contribution, and painted_env's own shade_tint is a blue-violet. A
## nominally neutral grey comes out of all that as lavender, which is a different wrong answer from
## the white it replaced. Judge it from a shot, not from the swatch.
@export var unassigned_tint := Color(0.62, 0.50, 0.36, 1.0)
## Multiplier on each material's authored normal strength. The maps are authored for a close render
## and this is a fixed camera 15-25 m up looking through a wrapped-lambert shader with no specular,
## so the relief has only the diffuse terminator to show itself in. 1.0 obeys the .blend exactly.
@export var normal_boost := 1.0

@export_group("Relief")
## Height maps for parallax, looked up by MATERIAL NAME — `bo_stone` becomes `bo_stone.jpg`.
##
## By convention rather than by export, because glTF has no height channel at all: the map cannot
## ride in on the .glb the way albedo and normal do, and a Dictionary export would mean hand-editing
## every scene that uses this. A folder and a filename rule needs neither.
@export_dir var relief_dir := "res://assets/materials/relief"
## 0 disables parallax. It is angle-dependent by nature, so it pays on walls and gives back least
## on surfaces seen from nearly overhead.
@export var parallax_depth := 0.0
@export_range(4, 48) var parallax_steps := 20
## 0 disables the second texture tap. Repetition is a function of area, so this is worth its fetch
## on the big surfaces and not on a door.
@export_range(0.0, 1.0) var detile := 0.0
@export_range(0.01, 1.0) var detile_scale := 0.12
@export_group("")

@export var verbose := true

var _cache: Dictionary = {}
var _unassigned: Array[String] = []


func _ready() -> void:
	if env_template == null:
		push_warning("BlockoutSkin on %s has no env_template — nothing skinned" % name)
		return
	var report: Array[String] = []
	_skin(self, report)
	if verbose and not report.is_empty():
		print("[SKIN] %s\n  %s" % [name, "\n  ".join(report)])
	# Named out loud rather than quietly corrected, because the tint is a rescue and the .blend is
	# where the object actually wants a material.
	if not _unassigned.is_empty():
		print("[SKIN] %s: %d material(s) had no texture and no colour — tinted instead of left "
				% [name, _unassigned.size()] + "white: %s" % ", ".join(_unassigned))


func _skin(n: Node, report: Array[String]) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var mat_name := src.resource_name if src != null else ""
			if skip_surfaces.has(mat_name):
				continue
			if glass_surfaces.has(mat_name):
				if glass_material != null:
					mi.set_surface_override_material(s, glass_material)
					report.append("%-18s surface %d  %-12s -> glass" % [mi.name, s, mat_name])
				continue
			mi.set_surface_override_material(s, _painted(src, mat_name))
			report.append("%-18s surface %d  %-12s -> painted" % [mi.name, s, mat_name])
	# get_children(true) so the -col suffix's generated StaticBody wrappers are walked too: the
	# importer puts the mesh UNDER the body, not beside it.
	for c in n.get_children(true):
		_skin(c, report)


## The height map for a material, or null. `bo_stone` -> `<relief_dir>/bo_stone.jpg`.
## Missing is the normal case, not an error: only the blockout has these.
func _relief_for(mat_name: String) -> Texture2D:
	if mat_name == "" or relief_dir == "":
		return null
	for ext in [".jpg", ".png"]:
		var path := "%s/%s%s" % [relief_dir, mat_name, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## One painted duplicate per source material, carrying that material's own texture and tint.
func _painted(src: Material, mat_name: String) -> ShaderMaterial:
	if _cache.has(mat_name):
		return _cache[mat_name]
	var m := env_template.duplicate() as ShaderMaterial
	var std := src as StandardMaterial3D
	if std != null:
		# A textured surface keeps its map; a flat one (the doors) keeps its colour, which would
		# otherwise render white against painted_env's default albedo of 1.0.
		#
		# ONLY IF THERE IS ONE. glTF hands every untextured mesh a default StandardMaterial3D, so
		# copying unconditionally writes a null over whatever the template supplied. That is silent
		# on a wall and catastrophic on foliage: the leaf atlas is what the alpha cutout tests, and
		# without it the shader falls back to hint_default_white — alpha 1 everywhere, nothing ever
		# cut, and a canopy of leaf cards renders as a stack of solid green quads.
		if std.albedo_texture != null:
			m.set_shader_parameter("albedo_texture", std.albedo_texture)
		# See `unassigned_tint`: no texture AND pure white is Blender's default material, not a
		# choice, and it is the one case where obeying the source is the wrong thing to do.
		# ONLY WHEN NOTHING ELSE IS SUPPLYING COLOUR. On the foliage nodes, textureless white albedo
		# is exactly right — the plant's colour lives in COLOR_0 and the shader multiplies by it, so
		# "rescuing" it here turns a canopy grey-brown. use_vertex_color is what tells the two apart.
		var unassigned := not use_vertex_color and std.albedo_texture == null \
				and std.albedo_color.is_equal_approx(Color.WHITE)
		m.set_shader_parameter("albedo_color", unassigned_tint if unassigned else std.albedo_color)
		if unassigned:
			_unassigned.append(mat_name if mat_name != "" else "(unnamed)")

		# THE TILING, which this used to drop on the floor.
		#
		# Blender states texel density with a Mapping node; that exports as glTF
		# KHR_texture_transform and Godot's importer lands it in uv1_scale/uv1_offset. Those are
		# StandardMaterial3D properties, and a ShaderMaterial has no equivalent — so every surface
		# arrived tiling once per UV unit no matter what the .blend said. A wall authored at 1.5 m
		# per tile and a roof at 3.5 m both came out at 1 m, which is why the roof slates looked
		# smaller in the engine than in Blender and no amount of retuning the .blend fixed it.
		m.set_shader_parameter("uv1_scale", Vector2(std.uv1_scale.x, std.uv1_scale.y))
		m.set_shader_parameter("uv1_offset", Vector2(std.uv1_offset.x, std.uv1_offset.y))

		# RELIEF. Normal maps reached the .glb and then stopped, because the shader had no slot for
		# them — so until now there was no normal mapping anywhere in the environment.
		if std.normal_enabled and std.normal_texture != null:
			m.set_shader_parameter("use_normal_map", true)
			m.set_shader_parameter("normal_texture", std.normal_texture)
			m.set_shader_parameter("normal_strength", std.normal_scale * normal_boost)

		if detile > 0.0:
			m.set_shader_parameter("detile", detile)
			m.set_shader_parameter("detile_scale", detile_scale)

		# Parallax needs a height map, and only turns on where one is actually found — a surface
		# with no relief map keeps the flat path rather than marching a black texture.
		if parallax_depth > 0.0:
			var height := _relief_for(mat_name)
			if height != null:
				m.set_shader_parameter("use_parallax", true)
				m.set_shader_parameter("height_texture", height)
				m.set_shader_parameter("parallax_depth", parallax_depth)
				m.set_shader_parameter("parallax_steps", parallax_steps)
	m.set_shader_parameter("use_vertex_color", use_vertex_color)
	m.resource_name = "painted_" + mat_name
	_cache[mat_name] = m
	return m

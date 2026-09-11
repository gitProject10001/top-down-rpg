extends Node3D
## THE SIMULATED SURFACE, as a node: one grid over the solver's window, every vertex sitting at
## w = b + h, following the window as it follows the camera.
##
## It replaces nothing. The wilds keep their per-region planes for water beyond the window - those
## are static, cheap, and correct out there, where nothing is simulating anything. This is the
## 64 m square around the camera where the solver has an opinion, and inside it the water has a
## height, a shoreline and a bed you can see.
##
## WHY IT IS A NODE AND NOT PART OF EITHER NEIGHBOUR. Not wilds_terrain: the SWE bench has no
## terrain at all, and the surface has to exist there too or the bench cannot show what it
## measures. Not the Ripples autoload: that is deliberately a plain Node, not a Node3D, because it
## is a texture pipeline and owns nothing in the world. So: its own small node, instanced by
## whoever has a solver.
##
## COST. 64 m at 0.25 m is 257 squared = 66 k vertices, one mesh, one draw. For comparison a single
## wilds water plane at its WATER_SUBDIV_MAX cap is 37 k and a region can have several.

const SURFACE_SHADER := preload("res://addons/sim_water/shaders/water_surface.gdshader")
## MESH SPACING, AND IT IS THE SOLVER'S TEXEL EXACTLY - not "about the solver's texel".
##
## It was 0.25 m against a 0.2 m state texel, on the reasoning that the geometry should carry what
## the simulation resolves and no more. The ratio is 1.25, and an incommensurate ratio BEATS: each
## vertex snaps to whichever texel it lands nearest, the pattern of which one that is repeats every
## four vertices, and the mesh acquires a fixed 1.00 m checkerboard that shimmers as the water
## moves under it. That is a moire between two grids, it is not in the water at all, and it was
## reported - correctly - as "the water is like vibrating". The surface it was drawing had settled
## to 1.7 mm of texel-scale roughness, which is invisible.
##
## One vertex per texel removes the beat by construction rather than by choosing a luckier number,
## and DERIVED from the solver so the two cannot drift apart again when RES changes. It costs
## 320 x 320 vertices against 256 x 256.
static var VERTS_M: float:
	get:
		return Ripples.TEXEL_M
## How far above and below the window origin the mesh may reach, for culling. The bed is baked in
## WORLD Y and the vertex stage moves every vertex, so the engine's own flat AABB would cull this
## the moment the water rose - a plane mesh claims zero height and the shader gives it plenty.
const CULL_Y := 96.0

var _mi: MeshInstance3D
var _mat: ShaderMaterial

## HOW THIS WATER LOOKS. Null means the shader's own defaults, which is what every caller got before
## this existed and what every caller still gets until one is assigned.
##
## APPLIED ON ASSIGNMENT, NEVER IN _follow(). That is not a performance point, it is the whole
## separation: _follow() runs every frame and carries solver state — the bed, the field, the
## encoding, the obstacle arrays, h_dry — and if art were pushed from there the two would be one
## code path again within a month. The physics is per-frame because it changes every frame. A look
## changes when somebody changes it.
@export var look: WaterLook = null:
	set(v):
		if look == v:
			return
		if look != null and look.changed.is_connected(_apply_look):
			look.changed.disconnect(_apply_look)
		look = v
		# emit_changed on the resource's setters is what makes tuning a loaded .tres retune a live
		# preview, the same way WildsStyle does for the terraces.
		if look != null and not look.changed.is_connected(_apply_look):
			look.changed.connect(_apply_look)
		_apply_look()


func _ready() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(Ripples.SIZE_M, Ripples.SIZE_M)
	var n := int(Ripples.SIZE_M / VERTS_M) - 1
	mesh.subdivide_width = n
	mesh.subdivide_depth = n
	_mat = ShaderMaterial.new()
	_mat.shader = SURFACE_SHADER
	_mi = MeshInstance3D.new()
	_mi.name = "Surface"
	_mi.mesh = mesh
	_mi.material_override = _mat
	# See CULL_Y. Without this the surface vanishes as soon as it is displaced far from the plane
	# the mesh nominally occupies, and it vanishes from the CAMERA's point of view, which is the
	# hardest kind of missing to diagnose.
	var half := Ripples.SIZE_M * 0.5
	_mi.custom_aabb = AABB(Vector3(-half, -CULL_Y, -half),
			Vector3(Ripples.SIZE_M, CULL_Y * 2.0, Ripples.SIZE_M))
	add_child(_mi)
	_apply_look()
	_follow()


func _apply_look() -> void:
	if look != null:
		look.apply_to(_mat)


## The material, for a bench that wants to drive it live from a panel. The idiom is already in the
## project at terrain_field.gd's water_material().
func water_material() -> ShaderMaterial:
	return _mat


func _process(_delta: float) -> void:
	_follow()


## Sit the grid on the window and hand it the bed. Y stays at zero on purpose: the bed texture is
## baked in WORLD Y, so with the node unrotated and unraised, the shader's local Y IS world Y and
## `VERTEX.y = b + h` needs no correction term that could drift out of step with the bake.
func _follow() -> void:
	if _mat == null:
		return
	var org: Vector2 = Ripples.window_origin()
	var half := Ripples.SIZE_M * 0.5
	# HALF A TEXEL ACROSS, AND IT IS NOT A NUDGE. A PlaneMesh of 64 m subdivided 319 times puts its
	# vertices at org + j*0.2 - on texel BOUNDARIES - while the texel the shader's floor() hands
	# each of them is centred at org + (j+0.5)*0.2. Every vertex was therefore reading the state
	# half a texel to its own +x and +z, so the drawn surface sat half a cell off the simulated one
	# in both axes at once.
	#
	# On open water that is invisible. At a boundary it is not: the wet/dry decision is taken at the
	# wrong place, and it is wrong ASYMMETRICALLY - the -x and -z sides of a solid come out clean
	# and the +x and +z sides come out notched, with the water pulled back a cell and black wedges
	# where the surface tips into the gap. A cylinder photographed from above is round on one side
	# and bitten on the other, which is exactly what was reported and exactly what a half-texel bias
	# in two axes looks like.
	global_position = Vector3(org.x + half + VERTS_M * 0.5, 0.0, org.y + half + VERTS_M * 0.5)
	global_rotation = Vector3.ZERO
	_mat.set_shader_parameter("bed_tex", Ripples.bed_texture())
	# WHICH ENCODING, every frame, from the solver rather than assumed. Getting this wrong does not
	# look like a bug: the surface simply is not there, and everything else keeps working.
	_mat.set_shader_parameter("field_tex", Ripples.field_texture())
	_mat.set_shader_parameter("depth_mode", Ripples.depth_mode)
	# THE SOLIDS, from the solver's own packing. Without these the surface draws water through a
	# cube: bed_tex is the terrain bed and a solid raises the EFFECTIVE bed as a uniform, so the
	# footprint reads as ordinary dry ground, the "a dry vertex sits at its highest wet neighbour's
	# surface" rule reaches straight across it, and the lake is drawn over the top and down the far
	# side - colouring the vertical faces on the way.
	var packed: Array = Ripples.obstacle_arrays(org)
	_mat.set_shader_parameter("obs_count", packed[0])
	_mat.set_shader_parameter("obs_a", packed[1])
	_mat.set_shader_parameter("obs_b", packed[2])
	# THE SAME NUMBER THE SOLVER USES, read from the solver rather than declared twice. A mesh that
	# drops water at a different depth than the physics calls dry puts the visible waterline a
	# texel away from the simulated one, and it crawls.
	var hd: Variant = Ripples.sim_get(&"h_dry")
	if hd != null:
		_mat.set_shader_parameter("h_dry", hd)

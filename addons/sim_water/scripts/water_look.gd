@tool
class_name WaterLook
extends Resource
## HOW WATER LOOKS, as data — the same split WildsStyle makes for the terraces, DungeonTheme for the
## crypt and GladeStyle for buildings. Setters emit_changed (the GladeStorey pattern) so tuning a
## loaded .tres retunes a live preview.
##
## WHY THIS EXISTS AT ALL. water_window.gd sets exactly seven shader parameters and every one of
## them is solver state — bed_tex, field_tex, depth_mode, the obstacle arrays, h_dry. The surface's
## appearance uniforms were written by NOTHING in the project: they ran on the defaults compiled
## into the shader, identical in every zone, and the only way to change them was to edit the
## shader's default literals. The art and the physics were already disjoint; what was missing was
## not a separation but a route in. This is the route.
##
## WHY A RESOURCE AND NOT A SAVED ShaderMaterial .tres. There are nineteen ShaderMaterial .tres in
## assets/materials/ and none for water, and starting now would be a trap: a .tres binds preset
## values to UNIFORM NAMES, so the moment a uniform is renamed or regrouped every saved value
## silently drops back to its default and the preset quietly becomes a different preset. Here the
## whole name mapping lives in one function, so a rename is one line in one place. It is the same
## reason WildsStyle exists rather than a saved terrain material.
##
## WHAT IS NOT HERE, deliberately:
##
##   `jump_slope` and `jump_curv` stay shader-side. They are not taste - jump_slope is derived from
##   a Froude measurement, and it doubles as the clamp on the lighting slope, so an artist moving it
##   would silently change the shading of every steep face. The WEIGHT of that foam (`jump_foam`) is
##   taste and is here; the THRESHOLD is not.
##
##   `flow_speed`, `flow_drag`, `foam_speed`, `foam_gather` stay on WildsStyle where they already
##   are. They are thresholds on a BAKED FIELD rather than colour, they already work, and moving
##   them would build exactly the parallel system this is meant to avoid.
##
##   `h_dry`, `dry_skirt`, `bed_clamp`, `bed_wall_min` are the solver contract. water_surface's own
##   header says why: a surface that calls water dry at a different depth than the physics does puts
##   the drawn waterline a texel from the simulated one and the shoreline crawls.

@export_group("Color")
@export var shallow_color := Color(0.62, 0.87, 0.86, 1.0):
	set(v):
		shallow_color = v
		emit_changed()
@export var deep_color := Color(0.09, 0.36, 0.52, 1.0):
	set(v):
		deep_color = v
		emit_changed()
@export var foam_color := Color(0.95, 0.98, 0.99, 1.0):
	set(v):
		foam_color = v
		emit_changed()
## CLARITY, in metres of water per e-fold of opacity, and the highest-value knob here. At 0.85 a
## metre of lake is most of the way to opaque; a lagoon you can read the sand through wants far
## more. Small numbers make a puddle look like ink.
@export_range(0.05, 4.0, 0.05) var absorb := 0.85:
	set(v):
		absorb = v
		emit_changed()
## Opacity where the water is deep, and where it is at the waterline. The second was a hard-coded
## 0.16 buried in the shader's ALPHA expression, which made the one control that separates "tinted
## glass" from "you can see the bottom" unreachable.
@export_range(0.0, 1.0, 0.01) var max_alpha := 0.94:
	set(v):
		max_alpha = v
		emit_changed()
@export_range(0.0, 1.0, 0.01) var shallow_alpha := 0.16:
	set(v):
		shallow_alpha = v
		emit_changed()

@export_group("Foam")
## THE WATERLINE, in metres of depth, gated on the depth GRADIENT rather than on depth alone -
## keyed on depth a filling basin is nothing but shallow water and the whole surface goes white.
@export_range(0.0, 0.4, 0.005) var shore_foam := 0.03:
	set(v):
		shore_foam = v
		emit_changed()
@export_range(0.05, 4.0, 0.05) var shore_edge := 1.2:
	set(v):
		shore_edge = v
		emit_changed()
## Gain on the foam the SOLVER produced - crests, jumps, the plunge below a fall.
@export_range(0.0, 2.0, 0.05) var live_foam := 1.0:
	set(v):
		live_foam = v
		emit_changed()
## Gain on the foam a hydraulic jump produces. The threshold that decides what counts as a jump is
## deliberately not here - see the header.
@export_range(0.0, 1.0, 0.05) var jump_foam := 1.0:
	set(v):
		jump_foam = v
		emit_changed()
## How far foam carries the colour toward foam_color, and how much opacity it adds. A lacy shoreline
## and a solid white band differ mostly in these two.
@export_range(0.0, 1.0, 0.01) var foam_mix := 0.85:
	set(v):
		foam_mix = v
		emit_changed()
@export_range(0.0, 1.0, 0.01) var foam_alpha := 0.30:
	set(v):
		foam_alpha = v
		emit_changed()

@export_group("Shading")
## Relief from the surface slope. Vanishes identically on flat water, which is the property that
## keeps a still pond looking exactly as it did.
@export_range(0.0, 3.0, 0.05) var slope_shade := 0.9:
	set(v):
		slope_shade = v
		emit_changed()
## A LOOK VECTOR, NOT A LIGHT - water never touches the lighting model in this project
## (water_ring.gdshader states it, water_stylized and painted_env repeat it). It is a scene fact
## rather than a water fact, so a zone with a different sun can match, but normally leave it alone.
@export var look_dir := Vector3(-0.40, 0.80, -0.45):
	set(v):
		look_dir = v
		emit_changed()


## Push the look onto a water material. ONE function, so a renamed uniform is one edit here rather
## than a silent loss in every saved preset.
##
## Setting a parameter a shader does not declare is a no-op in Godot, so this can serve more than
## one water shader without knowing which it was handed - which is what will make unifying the two
## of them cheap later, without coupling anything to that happening now.
func apply_to(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("shallow_color", shallow_color)
	mat.set_shader_parameter("deep_color", deep_color)
	mat.set_shader_parameter("foam_color", foam_color)
	mat.set_shader_parameter("absorb", absorb)
	mat.set_shader_parameter("max_alpha", max_alpha)
	mat.set_shader_parameter("shallow_alpha", shallow_alpha)
	mat.set_shader_parameter("shore_foam", shore_foam)
	mat.set_shader_parameter("shore_edge", shore_edge)
	mat.set_shader_parameter("live_foam", live_foam)
	mat.set_shader_parameter("jump_foam", jump_foam)
	mat.set_shader_parameter("foam_mix", foam_mix)
	mat.set_shader_parameter("foam_alpha", foam_alpha)
	mat.set_shader_parameter("slope_shade", slope_shade)
	mat.set_shader_parameter("look_dir", look_dir)

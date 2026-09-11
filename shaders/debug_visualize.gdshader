shader_type spatial;
render_mode unshaded, cull_disabled;
// Debug visualiser — the shader equivalent of print(). GPUs run in parallel so there is no log to
// read; the standard technique is to output the value you want to inspect straight to ALBEDO and
// LOOK at it. Kept as its own shader so toon_lit.gdshader stays verbatim.
//
// mode:
//   0 NORMAL    — world-ish normal as RGB. Smooth colour gradients = smooth normals; hard facets or
//                 blotches = split/broken normals. THIS is how you check whether a mesh needs the
//                 custom-split-normals pass (docs/anime-look-todo.md B3).
//   1 UV        — red/green ramp. Confirms UVs exist and are laid out sanely (needed for hair
//                 tangents and any texture work).
//   2 N·L       — greyscale lambert against `light_dir`, UNBANDED. The raw input the toon ramp
//                 quantises, so you can see what the ramp is actually being fed.
//   3 COLOR     — vertex colours (white if the mesh has none).
//   4 POSITION  — world position as RGB, scaled by `pos_scale`. Sanity-checks scale/placement.
//   5 CHECKER   — UV checkerboard for texel density / stretching.

uniform int mode : hint_range(0, 5) = 0;
uniform vec3 light_dir = vec3(0.5, 0.8, 0.4);   // used by mode 2 only
uniform float pos_scale = 0.2;                   // used by mode 4 only
uniform float checker_scale = 16.0;              // used by mode 5 only

varying vec3 v_world_pos;
varying vec3 v_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = vec3(1.0, 0.0, 1.0);   // magenta = unknown mode
	if (mode == 0) {
		col = v_normal * 0.5 + 0.5;                       // -1..1 -> 0..1
	} else if (mode == 1) {
		col = vec3(UV, 0.0);
	} else if (mode == 2) {
		col = vec3(clamp(dot(v_normal, normalize(light_dir)), 0.0, 1.0));
	} else if (mode == 3) {
		col = COLOR.rgb;
	} else if (mode == 4) {
		col = fract(v_world_pos * pos_scale);
	} else if (mode == 5) {
		vec2 c = floor(UV * checker_scale);
		col = vec3(mod(c.x + c.y, 2.0));
	}
	ALBEDO = col;
}

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// THE SPILL, procedural. The waterfall socket in WildsStyle had been wired since W1 —
// position, yaw, per-chunk lifetime, test coverage — and never had any art in it, so a
// terraced river read as a chain of disconnected ponds with a bare cliff between them.
//
// THE FIRST VERSION READ AS FROSTED GLASS, and the reason is worth keeping: it was a single
// flat quad, evenly translucent, with hard rectangular edges and horizontal banding — every
// cue that says "pane" and none that says "water". Four things fix it, none of them a
// texture:
//   * the SIDES taper to nothing, so the sheet has no vertical edges to read as a frame;
//   * the strands are NARROW and dense and vary in width, breaking the flat wash into water
//     ropes rather than stripes across a slab;
//   * opacity RISES down the fall as the strands gather, instead of sitting at one value;
//   * the lip is a bright hard line (water bending over the rim catches the light) while the
//     body stays comparatively sheer, which is what gives it a direction.
// depth_draw_never because a sheet this thin has no business writing depth over the pool it
// is falling into.

uniform vec4 water_color : source_color = vec4(0.62, 0.84, 0.86, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 0.99, 1.0);
uniform float fall_speed : hint_range(0.2, 8.0, 0.1) = 3.4;
uniform float strands : hint_range(4.0, 40.0, 1.0) = 17.0;
uniform float body_alpha : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float foot_alpha : hint_range(0.0, 1.0, 0.01) = 0.85;

group_uniforms Bulk;
// THE SHEET HAS THICKNESS NOW. A flat quad with stripes on it reads as a printed panel however
// good the stripes are, because the silhouette never changes and nothing occludes anything.
// Displacing the mesh along its own normal by LAYERED noise at different scales and speeds is
// the standard trick and it is the one the reference calls out: a single scroll looks like a
// moving texture, three at different rates look like turbulence, because the eye cannot lock
// onto a single period.
//
// Layer 1 is the slow body roll (which way the whole curtain leans), layer 2 the ropes, layer
// 3 a fast chop that only exists near the foot where the water is breaking up.
uniform float bulk = 0.16;                 // metres of bulge, peak
uniform float bulk_scale : hint_range(0.5, 12.0, 0.5) = 4.0;
uniform float widen : hint_range(0.0, 0.6, 0.02) = 0.18;   // spread toward the foot

float hash11(float p) {
	return fract(sin(p * 12.9898) * 43758.5453);
}

void vertex() {
	// UV.y runs 0 at the lip to 1 at the foot; the quad lies in local XY with -Z outward.
	float t = clamp(UV.y, 0.0, 1.0);
	float x = VERTEX.x;
	// Three incommensurate rates, all falling. The accelerating phase (t * t) is gravity: the
	// pattern stretches as it descends, which is what real falling water does and what a
	// single constant scroll can never show.
	float roll = sin(x * bulk_scale * 0.35 + TIME * fall_speed * 0.8 - t * 3.0);
	float rope = sin(x * bulk_scale * 1.7 - TIME * fall_speed * 2.1 + t * t * 9.0);
	float chop = sin(x * bulk_scale * 4.3 + TIME * fall_speed * 3.7 - t * t * 17.0);
	// Nothing bulges at the lip (the water is still a sheet there) and the chop only exists
	// where it has broken up.
	float grow = smoothstep(0.0, 0.35, t);
	float amp = bulk * grow;
	VERTEX.z -= (roll * 0.55 + rope * 0.3 + chop * 0.15 * smoothstep(0.45, 1.0, t)) * amp;
	// And it SPREADS as it falls, so the silhouette is a fan rather than a rectangle.
	VERTEX.x += x * widen * t * t;
}


void fragment() {
	float t = clamp(UV.y, 0.0, 1.0);          // 0 at the lip, 1 at the foot
	float u = clamp(UV.x, 0.0, 1.0);

	// STRANDS. Each takes its own phase AND its own width, so the curtain is a bundle of
	// ropes at different speeds rather than one sheet with lines drawn on it.
	float id = floor(u * strands);
	float within = fract(u * strands);
	float phase = hash11(id);
	float width = mix(0.22, 0.5, hash11(id + 7.3));
	// Distance from this strand's centre, so a strand is a soft round rope not a hard band.
	float rope = 1.0 - smoothstep(width * 0.6, width, abs(within - 0.5));
	// It falls: the streak slides down and the strand brightens where the water bunches.
	float s = fract(t * 1.6 - TIME * (fall_speed * mix(0.85, 1.25, phase)) + phase);
	float bunch = smoothstep(0.15, 0.55, s) * (1.0 - smoothstep(0.55, 0.95, s));
	float lit = rope * (0.35 + 0.65 * bunch);

	vec3 col = mix(water_color.rgb, foam_color.rgb, clamp(lit, 0.0, 1.0));
	// The lip: a bright rim where the water bends over the edge, and the foot where it
	// shatters. Both are horizontal, which is what actually reads from a 53-degree camera —
	// the vertical sheet between them is seen nearly edge-on.
	col = mix(col, foam_color.rgb, smoothstep(0.06, 0.0, t));
	col = mix(col, foam_color.rgb, smoothstep(0.72, 1.0, t) * 0.9);

	// TAPER THE SIDES to nothing so there is no vertical edge to read as a frame.
	float sides = smoothstep(0.0, 0.13, u) * smoothstep(0.0, 0.13, 1.0 - u);
	// Denser toward the foot, and never a flat wash: the strand pattern drives alpha too, so
	// you see THROUGH the gaps between ropes.
	float dense = mix(body_alpha, foot_alpha, t * t);
	float a = sides * dense * (0.45 + 0.75 * lit);
	a = max(a, sides * smoothstep(0.10, 0.0, t) * 0.9);   // keep the lip line solid

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}

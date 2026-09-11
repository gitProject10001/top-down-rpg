shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// THE PIXEL-ART RESOLVE. Runs once over the whole 640x360 buffer, inside the SubViewport, as the
// last thing drawn: outline -> grade -> palette snap. Everything upstream of it is ordinary lit 3D.
//
// WHY THIS IS A SPATIAL SHADER ON A QUAD AND NOT A ColorRect.
// The outlines have to come from geometry, not from luminance. shaders/pixel_toon.gdshader says so
// in its own header: a canvas_item shader cannot read the depth buffer, so it is stuck running a
// Sobel over brightness, which inks the boundary between a light and a dark patch of the SAME
// surface and misses the boundary between two objects that happen to be lit alike. A dark barrel
// against a dark wall gets no line, and a shadow falling across flat mud gets one. Both are exactly
// backwards. A spatial shader on a full-screen quad parented to the camera -- Godot's own
// "Advanced post-processing" recipe -- can read hint_depth_texture and hint_normal_roughness_texture,
// which is what an object boundary actually is.
//
// THE QUAD MUST LAND IN THE TRANSPARENT PASS, and getting that wrong cost two renders, so the
// finding is written down. Opaque geometry is sorted FRONT TO BACK, and this quad sits at the near
// plane -- so as an opaque object it is drawn first, before anything it is supposed to be filtering,
// and hint_screen_texture reads black. Writing ALPHA is what moves it to the transparent pass, which
// runs after all opaque geometry and after the colour buffer has been copied.
//
// The symptom is diagnostic once seen: perfectly correct outlines over a black field. Depth and
// normals are bound in every pass, so the edge detection keeps working while the colour it is
// supposed to be inking is not there yet.
//
// The two render modes that must NOT come back are depth_test_disabled and depth_draw_never. They
// look harmless on a quad meant to cover the screen, and they were in the first version -- they
// move the object out of the transparent pass again and put the black field straight back.
//
// Because this draws in the transparent pass, anything else transparent can sort in front of it and
// arrive on top of the finished frame unpixelated and unpalettised. That is why the foliage in this
// scene is alpha-SCISSOR rather than alpha-blend: a scissored surface is opaque and stays upstream.
//
// ONE SCREEN PIXEL IS ONE ART PIXEL. The viewport is already the low resolution, so nothing here
// pixelates anything -- the neighbour taps step exactly one texel, and the Bayer pattern is indexed
// by FRAGCOORD, so the dither is locked to the art grid rather than to the display.

#include "res://shaders/pixelart/palette.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

group_uniforms Palette;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform int palette_count : hint_range(2, 64) = 64;
// 0 lets the raw render through, which is the A/B for "is this a shading problem or a palette one".
uniform float palette_mix : hint_range(0.0, 1.0, 0.01) = 1.0;
// (L, a, b) weights before the nearest search. Lightness above chroma: a pixel artist's ramps are
// mostly lightness, so matching lightness first keeps a surface on its own ramp.
uniform vec3 palette_weights = vec3(1.6, 1.0, 1.0);
// How far the ordered dither pushes a pixel before it snaps, in Oklab units -- roughly the spacing
// between two steps of a ramp. Too small and gradients band; too large and flat areas turn to noise.
uniform float dither : hint_range(0.0, 0.3, 0.005) = 0.055;
group_uniforms;

group_uniforms Outline;
// Second-derivative threshold on view depth, in metres per pixel. A receding ground plane has a
// large depth SLOPE but no curvature, so a curvature test leaves it clean and still catches the
// step at a silhouette. Raise to lose faint lines, lower to ink more form.
uniform float depth_edge : hint_range(0.0005, 0.2, 0.0005) = 0.012;
// Creases inside a silhouette (a roof ridge against its own roof) are a normal break, not a depth
// one. This is 1 - dot(n, n_neighbour), so 0.06 is about 20 degrees.
uniform float normal_edge : hint_range(0.0, 1.0, 0.005) = 0.14;
uniform float outline_strength : hint_range(0.0, 1.0, 0.01) = 0.85;
uniform vec4 ink_color : source_color = vec4(0.078, 0.063, 0.047, 1.0);
// A pixel artist's outline is the object's OWN darkest shade, not a global black. 1.0 takes the
// line entirely from the local colour darkened; 0.0 takes it entirely from ink_color.
uniform float ink_from_surface : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float ink_darken : hint_range(0.0, 1.0, 0.01) = 0.32;
// AERIAL PERSPECTIVE ON THE INK -- OFF BY DEFAULT, AND THE REASON IS A TRAP WORTH RECORDING.
//
// This was added to answer "the contour becomes predominant while going away", and as first tuned it
// was simply wrong. The fade is keyed on ABSOLUTE view depth, which works under a perspective camera
// where near geometry is metres away and far geometry is tens. This camera is ORTHOGRAPHIC and sits
// 40 m back, so every surface in the camp lands in a narrow band around 40 m -- and a fade starting
// at 26 m therefore did not fade distant things, it faded EVERYTHING, uniformly, by about a third.
// The visible result was a scene with no outlines at all, which is the opposite of the complaint it
// was meant to fix.
//
// Left in because it is correct for a perspective camera (--free uses one). For the iso view, keep
// start beyond the far plane so it never engages, and control weight with outline_strength instead.
uniform float ink_fade_start : hint_range(0.0, 400.0, 1.0) = 250.0;
uniform float ink_fade_end : hint_range(0.0, 400.0, 1.0) = 400.0;
uniform float ink_fade_floor : hint_range(0.0, 1.0, 0.01) = 0.35;
group_uniforms;

group_uniforms Grade;
// THE COLOUR SPACE THIS PASS WORKS IN, because getting it wrong produces a black screen and looks
// exactly like a broken screen texture.
//
// hint_screen_texture hands back LINEAR HDR RADIANCE -- the scene before tone mapping, not the
// image you see. Every grading operation below (a contrast pivot at 0.5, split toning against a
// luminance ramp, an ordered dither in fixed steps) is defined on DISPLAY-REFERRED values. A
// contrast pivot at 0.5 in linear space is a pivot at sRGB 0.73, so applying it to raw radiance
// pushes essentially the whole frame to black. That was the first version of this shader.
//
// So the pass tone-maps and encodes to sRGB ITSELF, up front, and grades in display space. The
// Environment's own tonemap_mode is set to LINEAR (0) in the scene so it cannot run a second curve
// over the finished palette -- which would move every output pixel off the palette colour it was
// just snapped to, and the point of a locked palette is that the output pixels ARE the palette.
// Godot still applies the sRGB encode after this, so ALBEDO is written back in linear.
uniform float exposure : hint_range(0.2, 3.0, 0.01) = 1.0;
// Reinhard white point: the radiance that maps to display white. Raise to hold more highlight.
uniform float white_point : hint_range(0.5, 8.0, 0.05) = 2.2;
uniform float contrast : hint_range(0.5, 2.0, 0.01) = 1.12;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.06;
// Split toning, which is most of what separates the reference's warm mud from a neutral render.
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.36, 0.30, 1.0);
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.94, 0.80, 1.0);
uniform float split_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float vignette : hint_range(0.0, 1.0, 0.01) = 0.18;
group_uniforms;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// Reverse-Z aware: INV_PROJECTION_MATRIX carries whatever convention the projection used, so
// running the NDC point back through it is right for both perspective and orthographic. This scene
// is orthographic, where view depth is already linear in the buffer -- but the same code has to
// keep working the moment someone points a perspective camera at it.
float view_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).r;
	vec4 view = inv_proj * vec4(vec3(uv * 2.0 - 1.0, raw), 1.0);
	return -view.z / view.w;
}

vec3 view_normal(vec2 uv) {
	return texture(normal_tex, uv).rgb * 2.0 - 1.0;
}

// Extended Reinhard. Chosen over ACES/filmic on purpose: a filmic curve spends its subtlety on
// shoulder roll-off, and a 64-colour palette cannot show a shoulder. What matters here is that the
// mapping is monotonic and predictable, so a lighting change moves a surface a knowable distance
// along its ramp.
vec3 tonemap(vec3 c, float white) {
	return c * (1.0 + c / (white * white)) / (1.0 + c);
}

vec3 linear_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 srgb_to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	// A quad whose VERTEX already spans [-1, 1]: writing clip space directly makes it exactly the
	// screen regardless of where the node sits, so the mesh transform only has to keep it inside
	// the frustum for culling (extra_cull_margin does that on the instance).
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(screen_tex, 0));
	vec2 uv = SCREEN_UV;

	// Radiance -> display. Everything from here down is in sRGB display space; see the Grade group.
	vec3 col = linear_to_srgb(tonemap(texture(screen_tex, uv).rgb * exposure, white_point));

	// ---- OUTLINE ------------------------------------------------------------------------------
	float d_c = view_depth(uv, INV_PROJECTION_MATRIX);
	float d_l = view_depth(uv - vec2(texel.x, 0.0), INV_PROJECTION_MATRIX);
	float d_r = view_depth(uv + vec2(texel.x, 0.0), INV_PROJECTION_MATRIX);
	float d_u = view_depth(uv - vec2(0.0, texel.y), INV_PROJECTION_MATRIX);
	float d_d = view_depth(uv + vec2(0.0, texel.y), INV_PROJECTION_MATRIX);

	// Curvature, not gradient -- see depth_edge. Only the side where the neighbours are FARTHER is
	// taken, so the line lands once, on the near object's edge, instead of inking both sides of
	// every boundary and coming out two pixels thick.
	float curve = max(0.0, d_l + d_r - 2.0 * d_c) + max(0.0, d_u + d_d - 2.0 * d_c);
	// A WIDE RAMP ON PURPOSE. At 2.5x the ink was effectively binary, so a silhouette drifting
	// across a pixel boundary switched the line on and off between frames -- the contour fizzed on
	// anything that moved. 6x lets the edge fade across the boundary instead. pixel_snap.gd removes
	// most of the cause; this removes the rest, and costs almost nothing in crispness because the
	// curvature at a real silhouette is far above the threshold anyway.
	float e_depth = smoothstep(depth_edge, depth_edge * 6.0, curve);

	vec3 n_c = view_normal(uv);
	float n_diff = 0.0;
	n_diff = max(n_diff, 1.0 - dot(n_c, view_normal(uv - vec2(texel.x, 0.0))));
	n_diff = max(n_diff, 1.0 - dot(n_c, view_normal(uv + vec2(texel.x, 0.0))));
	n_diff = max(n_diff, 1.0 - dot(n_c, view_normal(uv - vec2(0.0, texel.y))));
	n_diff = max(n_diff, 1.0 - dot(n_c, view_normal(uv + vec2(0.0, texel.y))));
	float e_normal = smoothstep(normal_edge, normal_edge * 3.0, n_diff);

	float ink = clamp(max(e_depth, e_normal), 0.0, 1.0) * outline_strength;
	// d_c is view depth in metres, already computed above for the edge test.
	if (ink_fade_end > ink_fade_start) {
		ink *= mix(1.0, ink_fade_floor, smoothstep(ink_fade_start, ink_fade_end, d_c));
	}

	// ---- GRADE (before the snap: the palette is the last word on colour) -----------------------
	col = clamp((col - 0.5) * contrast + 0.5, 0.0, 1.0);
	float l = dot(col, LUMA);
	col = clamp(mix(vec3(l), col, saturation), 0.0, 1.0);
	col = mix(col, col * mix(shadow_tint.rgb, highlight_tint.rgb, smoothstep(0.15, 0.75, l)) * 2.0,
			split_strength);
	col = clamp(col, 0.0, 1.0);

	col *= 1.0 - vignette * smoothstep(0.35, 1.15, length(SCREEN_UV - 0.5) * 1.7);

	// The line, mixed in before quantisation so it lands on a palette colour like everything else.
	vec3 line = mix(ink_color.rgb, col * ink_darken, ink_from_surface);
	col = mix(col, line, ink);

	// ---- PALETTE ------------------------------------------------------------------------------
	// Ordered dither on the INPUT, then one nearest search -- see palette.gdshaderinc. The dither
	// is applied in DISPLAY space, where a fixed step means a fixed perceptual nudge; the search
	// itself runs in linear, because palette_snap converts to Oklab and Oklab is defined on linear.
	vec3 dithered = clamp(col + (bayer8(FRAGCOORD.xy) - 0.5) * dither, 0.0, 1.0);
	vec3 snapped = palette_snap(palette_tex, palette_count, srgb_to_linear(dithered), palette_weights);

	// Back to linear for the write: the palette texture is imported as source_color, so an entry
	// sampled out of it is already the linear form of its authored hex, and Godot's sRGB encode at
	// the end of the frame turns it back into exactly that hex on screen.
	ALBEDO = mix(srgb_to_linear(col), snapped, palette_mix);
	// Writing ALPHA at all is what puts this quad in the transparent pass -- see the header. The
	// value is always 1: nothing is meant to show through.
	ALPHA = 1.0;
}

shader_type canvas_item;
// Full-screen "pixel-art toon" post-process (canvas-safe — canvas_item shaders can't read the depth
// buffer, so definition comes from a strong CONTRAST curve + a sensitive luminance Sobel edge).
//
// Pipeline: pixelate -> Sobel edge ink -> brighten -> contrast -> saturate -> posterise.

uniform float pixel_size : hint_range(1.0, 16.0, 1.0) = 3.0;       // smaller = more detail/definition
uniform int   color_levels : hint_range(3, 32) = 16;
uniform float brightness : hint_range(0.5, 1.6) = 1.1;
uniform float contrast : hint_range(0.5, 2.0) = 1.28;            // tonal pop = perceived definition
uniform float saturation : hint_range(0.5, 2.0) = 1.3;
uniform float outline_strength : hint_range(0.0, 1.0) = 0.75;
uniform float outline_threshold : hint_range(0.05, 1.5) = 0.32;  // lower = more form lines
uniform vec4  outline_color : source_color = vec4(0.04, 0.03, 0.05, 1.0);

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float luma_at(vec2 uv) { return luma(texture(screen_tex, uv).rgb); }

void fragment() {
	vec2 grid = pixel_size * SCREEN_PIXEL_SIZE;
	vec2 uv = (floor(SCREEN_UV / grid) + 0.5) * grid;

	// Sobel edge on luminance (silhouettes + strong shading boundaries).
	float tl = luma_at(uv + grid * vec2(-1.0, -1.0));
	float tc = luma_at(uv + grid * vec2( 0.0, -1.0));
	float tr = luma_at(uv + grid * vec2( 1.0, -1.0));
	float ml = luma_at(uv + grid * vec2(-1.0,  0.0));
	float mr = luma_at(uv + grid * vec2( 1.0,  0.0));
	float bl = luma_at(uv + grid * vec2(-1.0,  1.0));
	float bc = luma_at(uv + grid * vec2( 0.0,  1.0));
	float br = luma_at(uv + grid * vec2( 1.0,  1.0));
	float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
	float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
	float edge = sqrt(gx * gx + gy * gy);

	// Fill: brighten -> contrast -> saturate -> posterise.
	vec3 c = texture(screen_tex, uv).rgb * brightness;
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);
	float l = luma(c);
	c = clamp(mix(vec3(l), c, saturation), 0.0, 1.0);
	c = floor(c * float(color_levels) + 0.5) / float(color_levels);

	float ink = smoothstep(outline_threshold, outline_threshold + 0.2, edge) * outline_strength;
	c = mix(c, outline_color.rgb, ink);

	COLOR = vec4(c, 1.0);
}

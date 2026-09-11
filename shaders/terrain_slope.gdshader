shader_type spatial;
render_mode ambient_light_disabled;
// GROUND FOR THE FOLIAGE BENCH, plus the one diagnostic that keeps a sculpted hill honest.
//
// AMBIENT IS DISABLED AND REPLACED BY A FILL THIS SHADER OWNS. That is the single most important
// line in the file, so here is what it is for.
//
// main.tscn's environment is cool on purpose — ambient_light_color (0.6, 0.7, 0.82) at energy 0.5,
// 45% sky contribution, and SDFGI bouncing a blue sky on top — and a 64 m ground plane fills the
// frame, so it collects more of that than any wall ever does. Working through it: a FULLY sunlit
// face gets about (0.45, 0.41, 0.34) from the sun against (0.30, 0.35, 0.41) of ambient, which
// already sums to neutral; anywhere the sun is not straight on, blue simply wins. Two symptoms,
// both of which showed up in the bench:
//
//   at a light albedo the surface saturates toward white and takes its hue from whichever light
//   dominates locally — lavender across most of it, hot orange on the few faces angled into the
//   sun. One continuous piece of ground reading as two different materials.
//
//   at a dark albedo it stops blowing out and reads as one material, but that material is NAVY.
//
// Lowering the albedo was tried and produced the second of those. The problem is not how bright the
// ground is, it is that the sky was choosing its colour. So the ambient contribution is switched
// off and a fill this shader controls is added in its place: the ground is now albedo times a fill
// plus a wrapped sun, and nothing else. It reads as one warm surface at any angle.
//
// This is a BENCH FLOOR, and that is what makes the trade right. It is a reference surface for
// judging foliage against, not shipping art — scenes/dev/foliage_lab.tscn:20 records that a floor
// which renders blue makes green judged against the wrong thing, which is the whole failure being
// removed here. The foliage standing on it still receives the game's real environment, unchanged,
// because that is the part whose look has to stay honest.
//
// This is deliberately NOT painted_env. The bench's ground exists so that foliage can be judged
// against it, and scenes/dev/foliage_lab.tscn:20 records why its albedo is a warm neutral: a dark
// ground took so much of its value from the scene's blue ambient that it rendered frankly blue, and
// green foliage judged against a blue floor is green judged against the wrong thing. A shader that
// brought painted_env's coloured shadow and saturation push would reintroduce exactly that.
//
// So: flat albedo, wrapped a little, no specular and no rim (the rule painted_env.gdshader:19
// states for the whole project), and two things on top that a height field needs.
//
// 1. ROCK ON THE STEEP PARTS. Ground that is one colour everywhere reads as a bedsheet — the eye
//    gets slope from shading alone, and at this project's fixed high camera pitch there is very
//    little of that. Blending toward a cooler, darker tint above `rock_start` degrees costs one
//    smoothstep and is most of what makes a sculpted hill read as terrain.
//
// 2. THE SLOPE OVERLAY, which is a correctness tool rather than a look.
//
//    THIS PROJECT HAS NO NAVMESH AND NO STEP LOGIC. docs/architecture.md:168 and
//    scripts/dungeon/kit.gd:499 both say so; nothing overrides CharacterBody3D.floor_max_angle, so
//    it is Godot's 45 degrees, and scripts/enemy.gd:227 flattens its chase vector with
//    `to_player.y = 0.0`. An enemy that meets a face steeper than 45 degrees does not path around
//    it, does not give up, and does not report anything — it grinds into the slope forever.
//
//    That failure is invisible while sculpting and expensive to find later, so the overlay makes it
//    a colour: GREEN under `walk_warn` (comfortably climbable), AMBER between the two limits (the
//    margin scripts/dungeon/gameplay/room_shape.gd:219 caps its own ramps inside), RED above
//    `walk_limit` (a wall, whether or not you meant one). A blocking cliff is a legitimate thing to
//    build here — it just has to be a decision, and red is how it stays one.

group_uniforms Albedo;
// WARMER THAN NEUTRAL, ON PURPOSE, because the environment the bench inherits from main.tscn is
// cool by design: ambient_light_color (0.6, 0.7, 0.82) at energy 0.5, 45% sky contribution, SDFGI
// bouncing a blue sky, and volumetric fog over it. The StandardMaterial3D this shader replaced was
// authored at a nominally neutral 0.72/0.68/0.62 and rendered distinctly blue — the one thing
// scenes/dev/foliage_lab.tscn:20 says the bench's floor must not be, since green foliage judged
// against a blue floor is green judged against the wrong thing. Authoring warm is what makes it
// READ neutral, and the shader's own wrapped shading keeps far more of the albedo than the
// StandardMaterial3D did.
//
// TUNE THIS BY EYE, from a shot, not from a sampled pixel. Absolute colour is not measurable in
// this scene: sampling a 15,360-pixel region of a FIXED-albedo control after 150 settle frames
// still moved by 0.06-0.10 per channel between two identical runs, because SDFGI keeps accumulating
// and TAA keeps jittering. An instrument that cannot reproduce its own control cannot calibrate a
// colour, and a number quoted from it would be false precision.
uniform vec4 base_color : source_color = vec4(0.82, 0.76, 0.66, 1.0);
uniform vec4 rock_color : source_color = vec4(0.58, 0.53, 0.48, 1.0);
// Where rock starts taking over, in degrees off flat, and how far past that it finishes.
uniform float rock_start : hint_range(0.0, 90.0, 1.0) = 26.0;
uniform float rock_end : hint_range(0.0, 90.0, 1.0) = 48.0;

group_uniforms Lighting;
// Same wrap idea as painted_env, at a fraction of its machinery: light bleeds past the terminator
// instead of stopping dead at N.L = 0.
uniform float wrap : hint_range(0.0, 1.0, 0.01) = 0.45;
// THE SHADOW IS A COLOUR, NOT AN ABSENCE — painted_env.gdshader:12, and this shader learned it the
// expensive way. The first version let the unlit side fall to zero diffuse, which leaves a surface
// with nothing but the environment's ambient on it, and the bench's ambient is a blue sky. The
// ground rendered FRANKLY BLUE: exactly the failure scenes/dev/foliage_lab.tscn:20 documents about
// its own albedo choice, reintroduced by the shader that replaced it. Keeping the surface's own
// colour in shadow at reduced strength is what stops the sky deciding what colour the ground is.
uniform vec4 shade_tint : source_color = vec4(0.80, 0.78, 0.86, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0, 0.01) = 0.62;
// The fill that stands in for the disabled ambient. Barely cool and deliberately weak: enough to
// keep the unlit side from going dead, not enough to decide what colour the ground is.
uniform vec4 fill_color : source_color = vec4(0.62, 0.64, 0.70, 1.0);
uniform float fill_strength : hint_range(0.0, 1.0, 0.01) = 0.34;

group_uniforms SlopeOverlay;
uniform bool overlay = false;
uniform float walk_warn : hint_range(0.0, 90.0, 1.0) = 35.0;
uniform float walk_limit : hint_range(0.0, 90.0, 1.0) = 45.0;
uniform float overlay_mix : hint_range(0.0, 1.0, 0.01) = 0.65;

varying float v_slope;   // degrees off flat, computed once per vertex

void vertex() {
	// The mesh carries real per-vertex normals from the height field's central differences, so the
	// slope is already here — no derivative, no second attribute.
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_slope = degrees(acos(clamp(wn.y, -1.0, 1.0)));
}

void fragment() {
	vec3 col = mix(base_color.rgb, rock_color.rgb,
			smoothstep(rock_start, rock_end, v_slope));

	ALBEDO = col;
	// The replacement ambient. EMISSION is the only channel a fragment can add to unconditionally,
	// and with ambient_light_disabled there is nothing else filling the unlit side.
	EMISSION = col * fill_color.rgb * fill_strength;

	if (overlay) {
		// Two smoothsteps rather than three branches, so the bands read as bands and the boundary
		// between them is a gradient you can aim at rather than a step you can only straddle.
		vec3 tint = mix(vec3(0.25, 0.75, 0.30), vec3(0.95, 0.72, 0.15),
				smoothstep(walk_warn - 4.0, walk_warn + 2.0, v_slope));
		tint = mix(tint, vec3(0.90, 0.20, 0.18),
				smoothstep(walk_limit - 2.0, walk_limit + 1.0, v_slope));

		// THE BANDS GO THROUGH EMISSION, NOT ALBEDO, and that is the difference between a diagnostic
		// and a decoration. Mixed into albedo they get the sun's warm colour, the scene's blue
		// ambient and then the grade's 1.35x saturation on top: measured here, "walkable green" and
		// "blocking red" came out as olive and MAGENTA, with a violet band on the shadow side where
		// the ambient dominated. Two colours that are supposed to mean pass and fail cannot be
		// allowed to depend on which way a face happens to point. Emission bypasses all of it.
		//
		// Albedo is dimmed by the same amount rather than replaced, so the ground keeps enough
		// shading to read as a shape underneath the flat colour.
		ALBEDO = col * (1.0 - overlay_mix);
		EMISSION = tint * overlay_mix;
	}

	// NO SPECULAR, NO ROUGHNESS VARIATION — painted_env.gdshader:19. The bench is where foliage is
	// judged, and a ground with a sheen on it is a ground that lies about the light.
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float l = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
	// Same shape and the same energy convention as painted_env.gdshader:246, so the bench's ground
	// and the game's environment agree about how bright a lit surface is.
	DIFFUSE_LIGHT += mix(ALBEDO * shade_tint.rgb * shade_strength, ALBEDO, l) * (LIGHT_COLOR / PI);
}

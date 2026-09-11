shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, fog_disabled;
// PER-MODEL INK OUTLINE. A copy of shaders/toon_outline.gdshader -- the inverted hull, rendered as
// back faces pushed outward -- with the one addition this scene needs: it extrudes along a SMOOTH
// normal baked into UV2 rather than along the shading normal.
//
// WHY THE SCREEN-SPACE PASS COULD NOT DO THIS JOB ALONE.
// pixel_post.gdshader inks edges by examining depth and normal discontinuities in the finished
// frame. That is one global setting for every object in the scene, and objects do not want the same
// setting. A building has a handful of large creases and needs the normal test sensitive enough to
// find them. A character is a dense organic mesh whose surface is nothing BUT normal variation, so
// the same sensitivity inks the whole figure and a thirty-pixel soldier comes out as a black blob.
// Turning it down to save the soldier loses the building. There is no value that serves both,
// because the difference is a property of the MODEL, not of the frame.
//
// An inverted hull is per-material, so a chapel, a barrel and a player each carry their own line
// weight; and it draws only the SILHOUETTE, never internal creases, which is exactly what a small
// figure wants. The screen-space pass stays, turned down, for the creases a hull cannot give.
//
// THE SMOOTH NORMAL IS THE WHOLE TRICK, and without it this technique visibly fails on every prop
// in this camp. propkit marks edges sharper than 30 degrees as sharp so a crate reads as a crate;
// glTF exports a sharp edge by splitting the vertex; and the two faces meeting at a box corner then
// push their shared corner in two different directions, tearing the hull open at every corner.
// tools/blender/camp_props.py bakes an averaged normal into UV2 for exactly this pass to read.
//
// The push is done in VIEW space, so the width is a world-space amount independent of the model's
// import scale -- and under this scene's orthographic camera that is also a constant width in
// screen pixels, which is what a drawn line is.

uniform float outline_width : hint_range(0.0, 0.2, 0.001) = 0.03;
uniform vec4 outline_color : source_color = vec4(0.05, 0.042, 0.036, 1.0);
// OFF for anything not built by tools/blender/camp_props.py. A mesh with no baked UV2 -- char_a, or
// anything from the dungeon kit -- returns zeroes there, which decode to a normal pointing along
// one axis and would shear the whole hull sideways. Those meshes are organic or already smooth
// enough that the shading normal does the job.
uniform bool use_baked_normal = true;

// Octahedral decode, the inverse of _oct_encode in tools/blender/camp_props.py.
vec3 oct_decode(vec2 e) {
	e = e * 2.0 - 1.0;
	vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
	float t = max(-n.z, 0.0);
	n.x += n.x >= 0.0 ? -t : t;
	n.y += n.y >= 0.0 ? -t : t;
	return normalize(n);
}

void vertex() {
	vec3 push = NORMAL;
	if (use_baked_normal) {
		push = oct_decode(UV2);
	}
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.xyz += normalize((MODELVIEW_MATRIX * vec4(push, 0.0)).xyz) * outline_width;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

class_name MapRelief
extends RefCounted
## ALL THE GEOMETRY, PHOTOGRAPHED FLAT. One orthographic frame straight down at the live zone, with
## the lighting switched off, captured on zone entry and kept as a texture.
##
## WHY THIS AND NOT A BAKED PNG. Same picture, but a bake has to be re-run by hand every time the
## level changes and nothing reminds you — the map would quietly describe a world that no longer
## exists. A SubViewport sharing the main World3D renders whatever is actually there, so a zone
## nobody has ever prepared (a GladeKit village, a fresh crypt seed) maps itself the first time it
## is walked into.
##
## WHY IT IS NOT THE WHOLE MAP. This pass cannot tell you where you may WALK — it sees a hedge and a
## garden path as equally solid ground. MapPainter's collision plan knows exactly that and nothing
## else. So the two are complementary and both are drawn: the relief underneath, muted, as the shape
## of the world; the walkable silhouette on top, in ink, as the part of it that is yours.
##
## UNSHADED IS THE POINT. Rendered normally this is a photograph — the sun, the shadows and the
## painterly grade all bake in, and stylising it means fighting them. DEBUG_DRAW_UNSHADED drops the
## light pass and leaves flat albedo, which is already halfway to a drawing.

## Longest edge of the captured texture, in px. 1024 over the hub's 234 m is ~4.4 px/m — plenty
## under the map's own zoom range, and one 1024x648 RGBA8 frame is ~2.6 MB held per zone.
const MAX_PX := 1024

## Height above the zone the camera sits at, and the depth slab it keeps. Generous rather than
## measured: an orthographic camera has no perspective to distort, so an over-tall slab costs
## nothing and removes any need to compute the zone's vertical extent first.
const CAM_Y := 300.0
const FAR := 700.0

## Metres shaved off the TOP of the world before capture. An ortho camera looking straight down
## clips what is nearest first, so raising `near` removes roofs and ceilings and lets the pass see
## into buildings. 0 keeps everything — a town map that shows roofs is a perfectly good town map.
const ROOF_CLIP := 0.0


## Capture `zone` across `rect` (its zone-local XZ footprint). Awaits a few frames, then frees the
## viewport. Returns null when there is nothing to render — a headless run, or no renderer.
static func capture(host: Node, zone: Node3D, rect: Rect2) -> Texture2D:
	if host == null or zone == null or not is_instance_valid(zone) or rect.size == Vector2.ZERO:
		return null
	if DisplayServer.get_name() == "headless":
		return null                       # no pixels to grab; the map falls back to the ink plan

	var scale := float(MAX_PX) / maxf(rect.size.x, rect.size.y)
	var px := Vector2i(maxi(int(rect.size.x * scale), 8), maxi(int(rect.size.y * scale), 8))

	var vp := SubViewport.new()
	vp.size = px
	# SHARE the main world rather than owning one: this has to photograph the zone that is actually
	# in the scene, not an empty duplicate world with a camera in it.
	vp.world_3d = host.get_viewport().world_3d
	vp.own_world_3d = false
	vp.transparent_bg = true              # empty sky = alpha 0, which IS the "no geometry" mask
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	vp.msaa_3d = Viewport.MSAA_4X         # the only antialiasing this gets; the ink is drawn later

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT       # so `size` is the VERTICAL extent
	cam.size = rect.size.y
	cam.near = 1.0 + ROOF_CLIP
	cam.far = FAR
	# WHAT THIS PASS MUST NOT SEE, dropped with a cull mask rather than by hiding nodes:
	#   characters   — a map with the player and three enemies painted into it is wrong the moment
	#                  anybody moves (ToonSkin.CHARACTER_LAYER, docs/architecture.md §4)
	#   the cloud sea — a 700 x 700 m quad under the world that fills the entire frame from above
	#
	# The cloud sea used to be hidden and restored here. A cull mask is strictly better: it touches
	# nothing, so it cannot fight DungeonEnv over who owns that node's visibility, and it cannot
	# blink the sea off for the frames the capture takes.
	cam.cull_mask = 0xFFFFF & ~ToonSkin.CHARACTER_LAYER & ~CloudSea.MAP_LAYER

	# Built in ZONE-LOCAL space and then pushed through the zone's transform, so the hub's baked
	# 0.11-degree tilt and the crypt's (500, 0, 500) offset are both handled without knowing about
	# either. Up = FORWARD (-Z) puts world +X to the right and world +Z DOWN the image, which is the
	# same convention MapGrid and MapPainter use.
	var mid := rect.get_center()
	var eye := Vector3(mid.x, CAM_Y, mid.y)
	var local := Transform3D().looking_at(Vector3.DOWN, Vector3.FORWARD)
	local.origin = eye
	vp.add_child(cam)
	host.add_child(vp)
	cam.global_transform = zone.global_transform * local
	# AFTER entering the tree. `current` resolves against the nearest ancestor Viewport, so setting
	# it on a detached node either does nothing or aims at the wrong viewport — and with a SHARED
	# World3D the wrong viewport is the one the player is looking through.
	cam.make_current()

	# UPDATE_ALWAYS plus a wait, rather than UPDATE_ONCE: the crypt's rooms are still resolving
	# their transforms and materials on the frame the zone binds, and a single-shot capture there
	# photographs a half-built dungeon.
	for i in 4:
		await host.get_tree().process_frame

	var tex: Texture2D = null
	var img := vp.get_texture().get_image() if vp.get_texture() else null
	if img != null and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
	vp.queue_free()
	return tex

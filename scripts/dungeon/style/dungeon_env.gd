@tool # so the Dungeon Forge GI bake can reuse this in the editor. Inert at runtime; attached to no scene.
class_name DungeonEnv
extends Object
## Puts the crypt inside a black void, and puts the outdoor world back afterwards.
##
## WHY THIS IS NOT IN dungeon_generator.gd. The generator is the gameplay spine — layout, doors,
## keys, the SpawnA/portal contract. This is pure style, so it lives in style/ next to
## room_dresser.gd. Same split the folder layout already declares.
##
## WHY THE CRYPT LOOKED LIKE DAYLIGHT. There is no dungeon WorldEnvironment: zone_crypt.tscn is a
## bare Node3D, and the crypt renders inside scenes/main.tscn's persistent OUTDOOR Environment.
## The old _dim_world() scaled sun and ambient ENERGY and nothing else, so `background_mode` stayed
## BG_SKY and the ProceduralSkyMaterial's GROUND hemisphere — ground_bottom (0.42, 0.50, 0.45) at
## sky_energy 1.4 — kept filling every frame outside the walls. That flat grey was never terrain.
##
## THE SNAPSHOT IS THE POINT. apply() reads every property it is about to write, then writes;
## restore() plays the recording back. The previous version kept three loose _sun_base-style vars,
## which does not scale to the twenty-odd properties it takes to actually black out a scene, and
## silently drops any property somebody forgets to pair up.

## What a theme may NOT override. These are mechanism, not taste: no crypt, vault or sewer ever
## wants its sky contribution back, and exposing all of it in the inspector is how the next person
## breaks the void by accident. The taste knobs live on DungeonTheme; see its Environment group.
const FIXED_ENV := {
	# The grey. BG_COLOR draws `background_color` instead of the sky — but see sdfgi_read_sky_light.
	"background_mode": Environment.BG_COLOR,
	"background_energy_multiplier": 1.0,
	# THE BLUE IN THE BRICKS. ambient_light_source is already AMBIENT_SOURCE_COLOR, so this is the
	# only path the blue sky has into the interior — and at 0.45 it was nearly half the ambient.
	# Zeroing it does more for "not daylight" than dimming the sun does.
	"ambient_light_sky_contribution": 0.0,
	"reflected_light_source": Environment.REFLECTION_SOURCE_DISABLED,
	# BG_COLOR stops the sky being DRAWN. SDFGI keeps SAMPLING the Sky resource for its ambient
	# term regardless, so without this the crypt stays blue however black the background is.
	"sdfgi_read_sky_light": false,
	# SDFGI STAYS ON, and not just because docs/environment-pipeline-todo.md §3 measured ambient
	# going unoccluded without it (0.297 vs 0.0020). The project-specific reason is stronger: every
	# torch in the crypt has shadow_enabled = false, so nothing but GI occlusion stops an OmniLight
	# lighting the next room straight through a wall. DungeonRoom.set_lit()'s "only the room you are
	# in is lit" — the crypt's whole lighting idea — is riding on this.
	"sdfgi_enabled": true,
	"sdfgi_use_occlusion": true,
	"sdfgi_min_cell_size": 0.1,      # kit walls are 0.5 m = 5 cells; the doc measured leaks at 2
	"sdfgi_cascades": 4,             # a 60 m crypt, not a landscape
	# BOUNCE IS THE ONLY GI THE CRYPT HAS, and for a long time it was carrying more than that.
	#
	# The original reasoning — with a black sky and near-black ambient there is nothing else for
	# SDFGI to gather, so take all of it — was right for the crypt it was written in, which had
	# exactly one shadow-casting light in it. At maximum feedback and 1.6 energy SDFGI was
	# supplying most of the non-directional light in the room, and that is fine when nothing casts
	# and disastrous once nine things do: indirect light has no direction, so every millimetre of
	# it lands inside the shadows the casters just carved and fills them back in.
	#
	# THIS IS ALSO THE ONLY LIVE KNOB. Constant ambient is inert down here — SDFGI supersedes it
	# wherever it covers a surface, which is everywhere — so `ambient_color` and `ambient_factor`
	# cannot brighten or darken the crypt however hard they are pushed. Measured: with SDFGI on,
	# quadrupling ambient moves the hero frame's mean luminance 0.1608 -> 0.1633; with SDFGI off,
	# the same change moves it 0.1598 -> 0.1817. Every note in the project that says "ambient did
	# nothing" is really this.
	#
	# 0.5 / 0.9 keeps SDFGI doing the job only it can do — containing light between rooms, and
	# putting a warm floor bounce on the shadow side of a pillar — without it also being the room's
	# main light source. The energy that comes out goes back in through fill_energy and
	# light_energy, which are room-gated and interrupted by geometry, as light should be.
	"sdfgi_bounce_feedback": 0.5,
	"sdfgi_energy": 0.9,
	# FOG IS WHAT MAKES "OUTSIDE IS NOTHING" TRUE rather than merely dark, and it is also what eats
	# the hub's distant ground. DEPTH, not EXPONENTIAL: an exponential fog dense enough to swallow
	# the room three cells away also fogs the CURRENT room by a third, because the isometric camera
	# sits 12-18 m out. Depth fog with an explicit begin leaves the near room untouched.
	"fog_enabled": true,
	"fog_mode": Environment.FOG_MODE_DEPTH,
	"fog_light_energy": 0.0,
	"fog_density": 1.0,              # in DEPTH mode this is the maximum, not a rate
	"fog_depth_curve": 1.0,
	"fog_aerial_perspective": 0.0,   # mixes SKY colour into distant geometry: a no-op here, but
	"fog_height_density": 0.0,       # leaving live values in properties the mode ignores is how
	"fog_sky_affect": 1.0,           # the next person loses an afternoon
	# NOW IT EARNS ITS FROXEL GRID. The condition this line used to carry — "only once a hero torch
	# per room gets shadow_enabled" — is met twice over: nine room lights cast, and the player
	# carries a shadowed torch that moves. Volumetric fog is what turns those shadows into
	# SHAFTS instead of dark patches on a wall, because a shadowed light carves the fog volume too.
	"volumetric_fog_enabled": true,
	# DENSITY ZERO, AND THAT IS THE WHOLE DESIGN. Environment fog is global: any non-zero density
	# here fills the void outside the walls as well as the rooms, and `void luminance < 0.005` and
	# `fog curtain < 0.01` are two of the tightest checks in the rig. Rather than tune a global
	# density down until it sneaks under both, there is no fog outside a room AT ALL — RoomFog adds
	# a box FogVolume per room and the checks are satisfied structurally instead of by luck.
	"volumetric_fog_density": 0.0000,
	# All five of the below are authored in main.tscn for a daylit garden and were, until this line,
	# NOT snapshotted — so flipping the enable flag alone would have inherited an outdoor look with
	# nothing to restore it. Being in the table is what makes them safe to set.
	"volumetric_fog_albedo": Color(0.78, 0.74, 0.68),
	# Forward scattering. Fog lit from the side is grey soup; fog that scatters toward the viewer
	# when they look past a flame is what makes a shaft read as a shaft.
	"volumetric_fog_anisotropy": 0.35,
	# ZERO, for exactly the reason the ambient note above gives. Ambient is uniform and directionless
	# by construction, so injecting it into a froxel grid IS the grey haze this is trying not to be.
	"volumetric_fog_ambient_inject": 0.0,
	"volumetric_fog_gi_inject": 0.3500,
	"volumetric_fog_length": 48.0,
	"volumetric_fog_detail_spread": 2.0,
	"volumetric_fog_temporal_reprojection_enabled": true,
	"volumetric_fog_temporal_reprojection_amount": 0.9,
	# SSAO is the references' "heavy crevice occlusion" and it was ALREADY ON — just useless, at the
	# outdoor radius. A 1.5 m sample radius cannot see a 2 cm mortar line. Brick scale is 0.45.
	"ssao_enabled": true,
	"ssao_power": 2.0,
	"ssao_detail": 1.0,
	# ZERO, deliberately. ssao_light_affect lets screen-space occlusion darken DIRECT light too,
	# which in a torchlit crypt means the one thing actually illuminating the room gets eaten by an
	# effect meant for ambient. SSAO belongs on the ambient term only.
	"ssao_light_affect": 0.0,
	# Torch colour bleeding onto the stone next to it — exactly the diorama read. Keep.
	"ssil_enabled": true,
	"adjustment_enabled": true,
	"adjustment_brightness": 1.0,
	"glow_enabled": true,
	"glow_bloom": 0.1,
}

## Written from theme fields. Key = Environment property, value = the DungeonTheme property it
## reads. Kept as data so adding a knob is one line here and one @export there.
const THEMED_ENV := {
	"background_color": "void_color",
	"ambient_light_color": "ambient_color",
	"fog_light_color": "fog_color",
	"fog_depth_begin": "fog_begin",
	"fog_depth_end": "fog_end",
	"glow_hdr_threshold": "glow_threshold",
	"glow_intensity": "glow_intensity",
	"tonemap_white": "tonemap_white",
	"adjustment_contrast": "contrast",
	"adjustment_saturation": "saturation",
	"ssao_radius": "ssao_radius",
	"ssao_intensity": "ssao_intensity",
}

## The sun's half of the snapshot. It is a list rather than a table because all three are written to
## the same fixed values (dim / no shadow / no fog) for every dungeon there will ever be — a crypt
## and an ice vault disagree about ambient colour, never about whether the SKY casts shadows
## indoors. Keeping it beside the env tables so "what does entering a dungeon touch?" has one answer.
const SUN_KEYS := ["light_energy", "shadow_enabled", "light_volumetric_fog_energy"]


## tonemap_MODE is pointedly absent from both tables. docs/anime-look-todo.md §A3 is a whole section
## about a look-dev scene that drifted because it did not run the game's own post stack; swapping
## the tonemapper for one zone is that mistake with extra steps. Only its white point moves.


## Snapshot every property this is about to touch, then black the world out. Returns the snapshot
## to hand back to restore(). Null-safe on every argument: the headless suite has no world_env and
## no sun, and must still run the generator end to end.
static func apply(env: Environment, sun: DirectionalLight3D, theme: DungeonTheme,
		sun_factor: float, ambient_factor: float, scenery: Array = []) -> Dictionary:
	var snap := {"env": {}, "sun": {}, "scenery": []}

	# THE SKY IS NOT THE ONLY THING OUTSIDE. Everything above is about the ENVIRONMENT — background
	# mode, sky contribution, GI, fog — and none of it can touch a MESH. main.tscn hangs a CloudSea
	# (a MeshInstance3D, 700 m across) under the world, so the crypt was rendering a lid of daylit
	# cloud below its own floor, visible over the lip of any room the camera could see past.
	#
	# This is the same mistake as the original grey void, one level along. That one was blamed on
	# terrain and turned out to be the sky's ground hemisphere; this one looks like the sky and
	# turns out to be geometry. The lesson worth keeping is that "make the outside black" is not a
	# single switch — the background, the sky's contribution to GI, and any scenery mesh are three
	# separate things and each needs saying.
	for n in scenery:
		if n is Node3D:
			snap.scenery.append({"node": n, "visible": (n as Node3D).visible})
			(n as Node3D).visible = false

	if sun != null:
		snap.sun = _snapshot(sun, SUN_KEYS)
		sun.light_energy *= _factor(sun_factor, theme.sun_factor if theme else 0.12)
		# DIMMING A LIGHT DOES NOT STOP IT RENDERING. At sun_factor 0.04 the crypt's sun is at 0.043
		# energy under a black sky and contributes nothing anyone can see — but its four shadow
		# cascades were still rendering every frame at Ultra filter quality over a 40 m range. Pure
		# cost, invisible output. The fog energy matters for the same reason and one phase later:
		# main.tscn authors light_volumetric_fog_energy = 2.5, so the moment volumetric fog goes on
		# the dimmed sun injects itself into every froxel INCLUDING the ones outside the walls, and
		# the black void stops being black.
		sun.shadow_enabled = false
		sun.light_volumetric_fog_energy = 0.0

	if env == null:
		return snap

	var keys: Array = FIXED_ENV.keys() + THEMED_ENV.keys()
	keys.append("ambient_light_energy")
	snap.env = _snapshot(env, keys)

	for k: String in FIXED_ENV:
		_write(env, k, FIXED_ENV[k])
	if theme != null:
		for k: String in THEMED_ENV:
			_write(env, k, theme.get(THEMED_ENV[k]))
	# The one property that is a FACTOR of what was already there rather than an absolute: the hub
	# and the crypt want the same relative dimming from whatever the outdoor look happens to be.
	env.ambient_light_energy *= _factor(ambient_factor, theme.ambient_factor if theme else 0.35)
	return snap


## Put back exactly what was taken. Anything not in the snapshot was never touched.
static func restore(env: Environment, sun: DirectionalLight3D, snap: Dictionary) -> void:
	if snap.is_empty():
		# Not fatal, but it means an apply/restore pair got out of step — and the visible symptom is
		# a permanently black overworld, which is very hard to trace back to here.
		push_warning("DungeonEnv.restore: empty snapshot — the outdoor look was never saved")
		return
	_playback(sun, snap.get("sun", {}))
	_playback(env, snap.get("env", {}))
	for e in snap.get("scenery", []):
		if is_instance_valid(e.node):
			(e.node as Node3D).visible = e.visible


static func _playback(obj: Object, values: Dictionary) -> void:
	if obj == null:
		return
	for k: String in values:
		obj.set(k, values[k])


static func _snapshot(obj: Object, keys: Array) -> Dictionary:
	var out := {}
	for k: String in keys:
		if k in obj:
			out[k] = obj.get(k)
		else:
			# Object.set() on a property that does not exist FAILS SILENTLY, so a Godot rename would
			# otherwise show up as a knob that quietly stopped working rather than as an error.
			push_warning("DungeonEnv: no property '%s' on %s — skipped" % [k, obj.get_class()])
	return out


static func _write(env: Environment, key: String, value: Variant) -> void:
	if key in env:
		env.set(key, value)


## An override of -1 means "use the theme's value" — the existing convention on the generator's
## Theme overrides group.
static func _factor(override: float, from_theme: float) -> float:
	return override if override >= 0.0 else from_theme

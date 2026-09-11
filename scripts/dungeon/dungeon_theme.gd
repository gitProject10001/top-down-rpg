@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name DungeonTheme
extends Resource
## The STYLE half of dungeon generation: everything about how a dungeon LOOKS, as data.
##
## The gameplay passes decide "a large cover piece stands here". This resource decides that a
## large cover piece is one of fifteen carved pillars, that torches burn amber every 10 m of
## wall, and that the sun dims to 12% while you are inside. Nothing in here can change a fight —
## which is exactly why a dungeon can be re-skinned (crypt -> dining hall -> armory) by swapping
## the resource, with the layout and the encounter untouched.
##
## AUTHORING: duplicate scenes/dungeon/themes/crypt.tres, point `pieces` at your own scenes.
## A tag with no entry falls back to the kit wrapper scene, then to the code greybox — so a
## half-finished theme still builds.

@export var id := "crypt"

## tag -> Array[PackedScene]. Several entries = variants; which one a given spot gets is chosen
## by a STABLE per-position roll, so adding clutter never reshuffles the pillars.
@export var pieces: Dictionary = {}

## tag -> PackedFloat32Array of relative weights, parallel to `pieces[tag]`.
## Missing or wrong length = uniform. Use it to make the plain pillar common and the cracked one rare.
@export var weights: Dictionary = {}

## Abstract slot tag -> kit piece name, overriding RoomDresser.DEFAULT_PIECE. This is how a theme
## re-interprets the plan: in a dining hall a `cover_large` might be "table" rather than "pillar".
## The gameplay footprint is unchanged — only what you see standing there.
@export var tag_pieces: Dictionary = {}

@export_group("Massing")
## THE DIORAMA CUT. With it on, the wall between the player and the camera stops at its base course
## while the other three carry the full stack — which is what every one of the reference images is,
## and the only reason a 6.8 m room stays playable from a 53 degree camera.
##
## It removes MESHES ONLY. Wall colliders are full height on all four sides regardless, so turning
## this off cannot change where the player can walk or what a projectile hits. A theme built for a
## free-yaw camera sets it false and gets closed rooms.
@export var cutaway := true

@export_group("Surface")
## PAINT, per kit piece name -> Color, where ALPHA IS HOW MUCH. Empty means the crypt stays the
## monochrome stone it has always been; a piece with no entry is untinted.
##
## Keyed by PIECE, not by tag, and the difference is deliberate: `pillar` covers the two pillars and
## the two statues, so painting columns paints the statuary standing among them, which is what a
## temple looks like. It also means the base course and the ashlar course above it are separate
## keys, which is how you get a BANDED wall out of a kit that has one wall.
##
## This is the only place in the theme that can change a material's colour, and it does it through
## an instance uniform rather than a second material — see the note on `material` below, and
## `piece_tint` in shaders/dungeon_stone.gdshader.
@export var piece_tints: Dictionary = {}
## The material every STONE kit piece is painted with, hung on as a `material_override` by
## Kit.paint(). This is where a dungeon stops being whatever its .glb files were imported as and
## enters the game's own shading — the crypt's brick meshes wore a bare StandardMaterial3D for the
## whole of their life before this socket existed, which is why they read as daylight-lit plastic.
##
## Empty = pieces keep their imported material. Still builds, still renders. The socket degrades.
## Non-stone art (the candelabra, the table, the torch, the key) opts out by metadata; see Kit.
@export var material: Material
## What colour the room's surfaces BOUNCE. RoomGI bakes a proxy shell instead of the real
## masonry (room_gi.gd's whole thesis), so the GI never samples `material` — this is the one
## number standing in for it, and it lives on the theme because a reskin that changes the stone
## must change what the stone bounces. Default = dungeon_stone.gdshader's own `stone_mid` stop,
## which is the shader's definition of "the colour of this stone".
@export var gi_albedo := Color(0.30, 0.27, 0.235)

@export_group("Greybox fallback")
## Overrides for Kit.SIZES / Kit.COLORS when no art exists yet. Empty = use the kit defaults.
@export var greybox_sizes: Dictionary = {}
@export var greybox_colors: Dictionary = {}

@export_group("Lighting")
## THESE ARE THE ONLY REAL LIGHT IN A DUNGEON NOW. They were tuned when the crypt still rendered
## under the outdoor sun and ambient, where a torch was an accent on an already-lit room; with the
## black-void override those two are gone and a sconce has to actually light the stone it stands
## against. Measured at the old 1.5 / 7.0: mean frame luminance 0.0064 — a room you cannot see.
@export var light_color := Color(1.0, 0.75, 0.45)
@export var light_energy := 7.5
## A crypt room is 20 x 12 m. At 7 m a wall sconce did not reach the floor in the middle of it.
@export var light_range := 14.0
## The EXPONENT on the falloff curve, pow(1 - d/range, attenuation) — so below 1 the pool stays
## bright further out and above 1 it collapses toward the lamp. Under 1 here on purpose: a sconce
## that only lights its own bracket is not lighting a room.
@export var light_attenuation := 0.9
@export var flame_color := Color(1.0, 0.62, 0.25)
@export var flame_energy := 2.2
## Roughly one wall light per this many metres of perimeter (used by the derived lighting pass).
@export var torch_spacing := 10.0

@export_subgroup("Room fill")
## ONE SHADOW-CASTING LIGHT PER ROOM, high over its centre. Wall sconces light the walls they hang
## on and leave the middle of a 20 x 12 m room black — which is where the fighting happens, and
## where the player was invisible against the floor.
##
## IT MUST CAST SHADOWS. An OmniLight3D with shadows off is not blocked by geometry at all, so a
## fill wide enough to reach the corners would also pour through every wall into the neighbouring
## rooms and destroy the "only the room you are in is lit" read DungeonRoom.set_lit exists for.
## Casting also buys the crypt real cast shadows, which not one of the sconces provides.
@export var fill_energy := 8.0
## High enough that the pool is even across the floor rather than a hotspot in the middle. Sits
## just under the cornice: WALL_HEIGHT has been 6.8 m since a4ee5d5, not the 3 m this once said.
@export var fill_height := 5.5
## Wide enough to reach the corners of the largest room the layout builds — AND NO WIDER, which
## became a real constraint once the fill was no longer the only caster. Range is what sizes an
## omni's shadow cubemap: at 26 m the frustum swallowed the whole of both neighbouring rooms as
## potential casters and spread 16 bits of depth over 26 m to render them. 18 m covers a 20x12
## room corner to corner (diagonal 11.7 from the centre) with room to spare, renders a third of the
## geometry, and gives every shadow in the room noticeably more depth precision for free.
@export var fill_range := 18.0
@export var fill_color := Color(1.0, 0.86, 0.7)
## How much the persistent outdoor sun/ambient is dimmed while this dungeon is alive.
## The crypt is open-topped — no ceiling, so the sun rakes straight in and 0.04 is right where 0.12
## would be for a sealed dungeon. (The walls have been 6.8 m since a4ee5d5, not the 3 m this used to
## say; taller walls shade more of the floor but the sun still arrives from directly above.)
##
## Note that this only scales ENERGY. Since afd12cd, DungeonEnv also switches the sun's shadow off
## outright while a dungeon is alive — four cascades for a light at 0.04 was 431 of the hero frame's
## 715 draw calls.
@export var sun_factor := 0.04
@export var ambient_factor := 0.35

@export_group("Environment")
## The TASTE half of the black-void override. The mechanism half — background mode, fog mode, sky
## contribution, SDFGI occlusion — is fixed in DungeonEnv, because no theme ever wants it back.
## Defaults are the crypt's, so a theme that touches none of this still gets a proper dark dungeon.
##
## What the camera sees where there is no geometry. Black is the point; a deep blue would read as
## night rather than as underground.
@export var void_color := Color(0, 0, 0)
## NOT pure black, deliberately. painted_env.gdshader's whole thesis is that a shadow is a colour,
## and the reference dioramas have deep but COLOURED darks. A warm near-black also leaves SSAO and
## SDFGI something to occlude — at zero there is nothing for them to subtract from.
## Bright enough that unlit stone is a SHAPE rather than a hole, and no brighter — everything above
## that is torchlight's job.
##
## THIS HAS TO BE SET MUCH HIGHER THAN THE RENDERED RESULT SUGGESTS, and that is not a mistake.
## Ambient is multiplied by SDFGI occlusion and then by SSAO before it reaches an interior surface,
## and inside a sealed brick room both are near their maximum — docs/environment-pipeline-todo.md §3
## measured interior ambient at 0.0020 with GI occlusion on. Most of what is authored here never
## arrives. Tune it by the lookdev's "lit stone mean", never by the number in the inspector.
##
## AND DO NOT REACH FOR IT WHEN THE CRYPT IS TOO DARK — but not for the reason this comment used to
## give. The old text blamed ambient not being room-gated, which never fitted the evidence it cited:
## an ungated light still lights the room you are standing in, so "+40% moved the hero frame not at
## all" was unexplained.
##
## THE REAL REASON IS THAT SDFGI SUPERSEDES CONSTANT AMBIENT wherever it covers a surface, and in a
## sealed crypt that is every surface. Measured on the hero frame with the crypt's own settings:
##
##     SDFGI on    ambient 0.175 -> 0.700    mean luminance 0.1608 -> 0.1633   (+1.6%)
##     SDFGI off   ambient 0.175 -> 0.700    mean luminance 0.1598 -> 0.1817   (+13.7%)
##
## So this knob is close to inert with GI on, and the one experiment where it DID do something —
## +38% lifting the unlit room 2.3x against the lit room's 1.3x — is the exception that proves it:
## an unlit room has almost no bounce for SDFGI to gather, so ambient is the only thing left there
## to show through.
##
## `fill_energy` is the knob for "too dark" — it is shadowed, so it stays in its own room. The knob
## for "the whole crypt floats in undirected light" is `sdfgi_energy` in DungeonEnv.FIXED_ENV.
@export var ambient_color := Color(0.45, 0.39, 0.34)
## Depth fog: a hard black curtain that hides the world outside the walls. `begin` must clear the
## room the player is standing in (the isometric camera sits 12-18 m out) or the near walls fog too.
@export var fog_color := Color(0, 0, 0)
@export var fog_begin := 22.0
@export var fog_end := 55.0
## In a black room the only things over the HDR threshold are the flame meshes, so glow becomes
## torch bloom for free. Lower threshold + higher intensity than outdoors, and it is cheap.
@export var glow_threshold := 0.85
@export var glow_intensity := 0.5
## Outdoors this is 1.35, tuned against the painted daylight look. On a near-monochrome torch-lit
## scene it turns amber into sherbet and any surviving blue into cyan.
@export var saturation := 1.1
@export var contrast := 1.15
## Outdoors this is 8.0, set for a bright image; it flattens the top end of a near-black one.
## Lower clips the torch cores hot while the unlit walls, already around 0.02, stay put.
@export var tonemap_white := 3.0
## BRICK SCALE, and probably the second-biggest single win in the crypt art pass after the void.
## SSAO was already enabled here — just at the outdoor 1.5 m radius, which cannot see a 2 cm
## mortar line, so it did nothing for exactly the crevices the references are full of.
@export var ssao_radius := 0.45
@export var ssao_intensity := 3.0

@export_group("Grime decals")
## Patches of dirt and moss PROJECTED across the module grid — see RoomGrime for why this is the one
## thing that hides a seam the shader cannot. 0 = off.
@export var grime_density := 1.0
## How much of the stone underneath survives. Above ~0.7 the patch reads as paint rather than dirt.
@export var grime_opacity := 0.55
@export var grime_color := Color(0.42, 0.35, 0.26)
@export var grime_moss := Color(0.30, 0.42, 0.18)
## Fraction of patches that are moss rather than dirt.
@export var grime_moss_share := 0.35

@export_group("Debris")
## Loose pebbles and grass tufts, biased onto the tile joints — the geometry half of hiding the
## module grid, where the decals above are the projected half. See RoomDebris. 0 = off.
@export var debris_density := 1.0
## Grass among the bricks. Alpha 0 = no tufts at all (an ice vault or an ossuary would want that).
@export var tuft_color := Color(0.17, 0.23, 0.10, 1.0)

@export_group("Volumetric fog")
## Density of the per-room FogVolume that makes light shafts visible. 0 = no fog volume at all,
## which is a real choice: a dry ossuary or a swept vault should have nothing in the air.
##
## THIS IS THE ONLY FOG DENSITY IN THE DUNGEON. DungeonEnv pins the ENVIRONMENT's volumetric density
## to zero, because that one is global and would fill the black void outside the walls as readily as
## it fills a room. Keeping every cubic metre of fog inside a box means "outside is nothing" stays
## true structurally. Small numbers: 0.0035 is a visible haze at torch range; 0.030 washed the room out completely.
@export var fog_volume_density := 0.0018
## Fog colour. Warm and slightly desaturated — fog takes the colour of what lights it, so this is a
## tint on torchlight rather than a colour in its own right. A sewer would go green, an ice vault
## blue-white.
@export var fog_volume_color := Color(0.78, 0.74, 0.68, 1.0)

@export_group("Clutter")
@export var clutter: Array[PackedScene] = []
## Scattered props per 100 m^2 of free floor. 0 = none.
@export var clutter_density := 0.0
## Floor one clutter prop claims. Make it SQUARE and as wide as the piece's longest side: clutter
## is dropped at quarter-turn rotations, so a 2.2 x 0.9 table needs 2.2 x 2.2 reserved either way.
@export var clutter_footprint := Vector2(0.6, 0.6)
## Per-prop override, parallel to `clutter`. Same idiom as `pieces`/`weights`: shorter or absent and
## the entries fall back to `clutter_footprint`, silently, so a half-filled array still runs.
##
## It exists because one number cannot serve a set: a 2.2 m table and a 0.3 m bowl reserved at the
## same size means either the bowl blocks a square metre of floor for nothing, or something gets
## planned inside the table.
@export var clutter_footprints: Array[Vector2] = []


## The paint for a piece, as the shader wants it: rgb + strength, with strength 0 meaning "none".
## Returns the untinted default for anything the theme has no opinion about, so the socket degrades
## rather than erroring — the rule every socket in this dungeon follows.
func tint_for(piece_name: String) -> Vector4:
	var c = piece_tints.get(piece_name)
	if not (c is Color):
		return Vector4(1.0, 1.0, 1.0, 0.0)
	var col := c as Color
	return Vector4(col.r, col.g, col.b, col.a)


func has_variants(tag: String) -> bool:
	var list = pieces.get(tag)
	return list is Array and not (list as Array).is_empty()


## Pick a variant for `tag`. `roll` is a stable value in [0, 1) supplied by the caller (see
## RoomContext.variant_roll) — passing a random number here would make rebuilds differ.
func pick(tag: String, roll: float) -> PackedScene:
	if not has_variants(tag):
		return null
	var list: Array = pieces[tag]
	if list.size() == 1:
		return list[0]

	var w = weights.get(tag)
	if not (w is PackedFloat32Array) or (w as PackedFloat32Array).size() != list.size():
		return list[clampi(int(roll * list.size()), 0, list.size() - 1)]

	var total := 0.0
	for x in (w as PackedFloat32Array):
		total += maxf(x, 0.0)
	if total <= 0.0:
		return list[clampi(int(roll * list.size()), 0, list.size() - 1)]
	var target := roll * total
	var run := 0.0
	for i in list.size():
		run += maxf((w as PackedFloat32Array)[i], 0.0)
		if target < run:
			return list[i]
	return list[list.size() - 1]


func size_for(tag: String, fallback: Vector3) -> Vector3:
	return greybox_sizes.get(tag, fallback)


func color_for(tag: String, fallback: Color) -> Color:
	return greybox_colors.get(tag, fallback)

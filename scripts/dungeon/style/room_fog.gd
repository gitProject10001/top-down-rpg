@tool # so the Dungeon Forge dock can call this in the editor. Inert at runtime; attached to no scene.
class_name RoomFog
extends Object
## One box of volumetric fog per room, so that light has something to be visible IN.
##
## WHY PER ROOM AND NOT ON THE ENVIRONMENT. `Environment.volumetric_fog_density` is global: it fills
## the void outside the crypt walls exactly as happily as it fills the rooms. Two of the tightest
## checks in the whole lookdev — `void luminance < 0.005` and `fog curtain < 0.01` — are about the
## outside being NOTHING, and a global density would put them permanently at risk of whatever
## number someone last tuned. DungeonEnv sets that density to zero and every cubic metre of fog in
## the dungeon comes from one of these boxes, so "no fog outside a room" is true by construction
## rather than by tuning. Getting a guarantee for the same money as a setting is a good trade.
##
## It is also free at distance, and free in the way that matters most: a FogVolume is a
## VisualInstance3D, so DungeonRoom.show_around() removes distant rooms' fog along with their
## geometry without this file knowing anything about it.
##
## WHAT MAKES IT SHAFTS RATHER THAN HAZE is not here — it is `light_volumetric_fog_energy`, set per
## light back in the shadow phase: 1.2 on the candelabras, 1.4 on the brazier, 2.0 on the player's
## torch, and 0.25 on RoomFill. The fill is suppressed deliberately. A big soft omni at 5.5 m with
## real fog energy is precisely the "uniform haze and nothing more" that kept this feature switched
## off for so long; the shafts come from the small fires down at floor level, whose light is chopped
## into beams by the pillars and candelabra arms standing right next to them.

## Metres of fog above the floor. Higher than head height so the player walks IN it, but well under
## WALL_HEIGHT: crypt mist pools, and filling the room to the cornice would put a grey wash over the
## upper courses and take `upper course luminance` out of range.
const HEIGHT := 4.5


static func add(room: Node3D, ctx: RoomContext, theme: DungeonTheme) -> void:
	var density := theme.fog_volume_density if theme else 0.0018
	if density <= 0.0:
		return
	var vol := FogVolume.new()
	vol.name = "RoomFog"
	vol.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	# The room's interior, not its footprint plus walls. Fog inside 0.5 m of solid masonry is fog
	# the player can never see, and it would glow through a doorway from the wrong side.
	vol.size = Vector3(ctx.footprint.x - 1.0, HEIGHT, ctx.footprint.z - 1.0)

	var mat := FogMaterial.new()
	mat.density = density
	# Pools at the floor rather than filling the box evenly. Without this the fog is a uniform grey
	# block with a visible top edge at 4.5 m — a ceiling made of nothing.
	mat.height_falloff = 0.6
	# WITHOUT THIS THE BOX HAS CORNERS. A FogVolume cuts off hard at its bounds, and the one place
	# the player looks straight down that boundary is a doorway, where it reads as a pane of glass
	# across the opening.
	mat.edge_fade = 0.15
	mat.albedo = theme.fog_volume_color if theme else Color(0.78, 0.74, 0.68)
	vol.material = mat

	room.add_child(vol)
	vol.position = Vector3(0.0, HEIGHT * 0.5, 0.0)

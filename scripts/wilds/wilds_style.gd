@tool
class_name WildsStyle
extends Resource
## The STYLE half of a wilds landscape — everything about how the terraces LOOK, as data, the
## same split DungeonTheme makes for the crypt and GladeStyle makes for buildings. Setters
## emit_changed (the GladeStorey pattern) so tuning a loaded .tres regrows live previews.
##
## EVERY PROCEDURAL THING HAS A SOCKET (GladeKit's zero-assets law): the cliff pieces, the
## trees and the waterfall are PackedScene overrides that, left empty, fall back to the
## generated geometry or today's broadleaf stand-ins. Art arrives; nothing else changes.

@export_group("Ground")
@export var grass_color := Color(0.34, 0.44, 0.26):
	set(v):
		grass_color = v
		emit_changed()
@export var grass_dark := Color(0.24, 0.33, 0.19):
	set(v):
		grass_dark = v
		emit_changed()
@export var dirt_color := Color(0.42, 0.34, 0.24):
	set(v):
		dirt_color = v
		emit_changed()

@export_group("Cliffs")
@export var cliff_color := Color(0.38, 0.33, 0.30):
	set(v):
		cliff_color = v
		emit_changed()
@export var cliff_dark := Color(0.26, 0.22, 0.21):
	set(v):
		cliff_dark = v
		emit_changed()
## Height of one visual stratum band on cliff faces, keyed to WORLD Y so beds run level across
## separate faces (the GladeRockField sawtooth idea).
@export var strata_height := 0.6:
	set(v):
		strata_height = maxf(v, 0.1)
		emit_changed()

@export_group("Water")
@export var water_shallow := Color(0.32, 0.55, 0.58, 1.0):
	set(v):
		water_shallow = v
		emit_changed()
@export var water_deep := Color(0.12, 0.28, 0.38, 1.0):
	set(v):
		water_deep = v
		emit_changed()
## Metres/second per unit of the derived flow field (WildsGen.flow_at). A dial rather than a
## bake constant on purpose: the field is unit-less, so retuning how fast rivers run costs a
## uniform, never a re-bake of every water plane.
@export_range(0.0, 4.0, 0.05) var flow_speed := 1.0:
	set(v):
		flow_speed = v
		emit_changed()
## How hard the current drags the surface pattern along with it. 0 leaves the ambient sines
## exactly as they were before flow existed.
@export_range(0.0, 2.0, 0.05) var flow_drag := 1.0:
	set(v):
		flow_drag = v
		emit_changed()
## Flow speed at which water starts to foam of its own accord (rapids), in the same units as
## flow_speed. Higher = only the fastest water goes white.
@export_range(0.1, 6.0, 0.05) var foam_speed := 2.6:
	set(v):
		foam_speed = v
		emit_changed()
## Convergence at which foam starts to gather (eddy corners, the outside of a bend). A
## threshold, not a multiplier — the raw baked divergence saturates on contact.
@export_range(0.05, 3.0, 0.05) var foam_gather := 1.1:
	set(v):
		foam_gather = v
		emit_changed()

@export_group("Sockets")
## Authored cliff pieces, resolved per segment as "straight_<drop>" then "straight" (the
## Kit._resolve ladder). Empty = all procedural. PLACEMENT CONTRACT for the Blender kit: origin
## at the FOOT of the face on the unjittered cell-edge lattice, face authored on local -Z
## looking outward, one cell (2.0 m) wide, one course (1.2 m) per drop. Pieces DRESS the
## generated face — the procedural quads stay as collider and backing, so art thinner than the
## silhouette can never open a hole; make it thicker than the ±0.7 m corner jitter.
@export var cliff_pieces: Dictionary = {}
## Tree stands. Empty = the broadleaf veg_leaf_tree stand-ins until a pine exists.
@export var tree_scenes: Array[PackedScene] = []
## Stands on every water-rim segment (a lake lip over lower ground), origin at the surface
## spill line, same -Z-outward convention. Empty = nothing.
@export var waterfall_scene: PackedScene

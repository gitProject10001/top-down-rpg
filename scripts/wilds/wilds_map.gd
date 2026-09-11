@tool
class_name WildsMap
extends Resource
## AUTHORED INTENT for a wilds landscape — the WildsMap is to wilds_gen what DungeonGraph is to
## DungeonLayout: everything the author insists on, nothing that can be derived. The noise base
## and the paint are SEPARATE layers on purpose: `tier_paint` stores per-cell OFFSETS over the
## noise, so re-rolling the seed under a painted valley moves the countryside and keeps the
## valley — the same reason DungeonGraph pins rooms instead of freezing the whole walk.
##
## Cells are 2.0 m and tiers rise 1.2 m, and neither number is taste: 1.2 over one 2.0 m cell
## is 30.96 degrees — legal under RoomShape.MAX_SLOPE (35) and the engine's floor_max_angle
## (45) — so ONE CELL IS ONE RAMP. 1.2 is RoomShape.LEVEL_RISE: a step this tall is already a
## wall to a body with no step-up, which is exactly what a Direland tier is. And 1.2 divides
## into whole GladeKit courses, so conform_to_ground walls standing on a terrace agree with it.
##
## PAINT IS PAGED AND SPARSE, because the world is procedural and paint is the exception: at
## the 14 km target (7000x7000 cells, 49M) dense arrays alone would cost half a gigabyte for
## a map that is 99% untouched noise. A page is one 32x32 tile (PAGE, aligned with the
## streaming chunk), allocated on first WRITE; an absent page reads as zero. All access goes
## through the *_at / set_* accessors — nothing outside this file may assume dense arrays.
## Saved .tres files store only touched pages; the pre-W6 dense arrays load through _set
## migration below.

## Bits in flags.
const F_WATER := 1
const F_RAMP_PAINTED := 2
const F_RAMP_FORBIDDEN := 4
const F_CLEARING := 8
## A SPRING: where water enters the world. Painted, like water itself, because a source is an
## authorial fact and not something local terrain can imply — the map cannot see the catchment
## that feeds a reach, so somebody has to say where the river starts.
const F_SPRING := 16

## border_mode values.
const BORDER_NONE := 0
const BORDER_CLIFFS := 1
const BORDER_SEA := 2

const PAGE := 32                              ## cells per page side — one streaming chunk

@export var seed: int = 5
## Resizing a PAINTED map re-maps which page a cell lands in — author size first, paint after
## (the dock's dials are generation-time choices, not undoable paint, for the same reason).
@export var cells_w := 64:
	set(v):
		cells_w = clampi(v, 8, 8192)
@export var cells_h := 64:
	set(v):
		cells_h = clampi(v, 8, 8192)
@export var cell_size := 2.0
@export var tier_height := 1.2
## HOW DEEP A PAINTED LAKE IS, in metres below the tier top at mid-water. The surface sits at
## SURFACE_DROP (0.35 m) below the same top, so the water column is `lake_depth - 0.35` and the
## shore stays a wet beach because BED_SHALLOW (0.2 m) is ABOVE the surface.
##
## AUTHORABLE, because it is a property of a place and not of the engine. It was a generator
## constant at 0.9, which made every lake in the world exactly 0.55 m deep - a puddle you could see
## the bottom of everywhere, and the same 0.55 m the water bench had been using as its bed_depth
## without anybody noticing the two were the same number for the same reason.
##
## WHAT BOUNDS IT FIRST IS THE PLAYER, not the solver. THIS WORLD HAS NO SWIMMING - not a swim
## state that is unfinished, none at all: terrain_field records "water, blocked off, with no
## swimming logic, no per-frame water-level query, and no depth test", raft.gd steps a rider off
## into the water because "every water in this world is wadeable", and the wilds suite asserts the
## sea is wadeable so a player cannot walk off the edge of the map. Every one of those is a
## statement about 0.55 m.
##
## So a lake deeper than a person is a GAMEPLAY CHANGE and not a dial. Raising this to 2.6 m for
## the water bench duly drowned the player, on the first run, exactly as those three notes predict.
## Until there is a swim state, keep the column at or under about a metre: deep enough to read as
## water and to give a wave somewhere to go, shallow enough to wade.
##
## WHAT BOUNDS IT SECOND is the solver, and that bound just moved. An explicit scheme is stable while
## kappa = g*h*dt^2/dx^2 stays under its limit; the staggered rewrite took that from 0.25 to 0.5,
## which is 3.67 m of water to 7.34 m. A deep lake was not affordable before and is now - so this
## being a dial rather than a constant is a thing the solver work paid for.
@export var lake_depth := 0.9

@export_group("Noise base")
## The canonical rolling-ground parameters (probe_cliff.gd / terrain_field.noise_fill lineage:
## seed 5, freq 0.018, octaves 2) with amplitude re-expressed in TIERS.
@export var noise_freq := 0.018
@export var noise_octaves := 2
@export var max_tier := 4

@export_group("Border")
## The world's edge, whatever the size: an unclimbable cliff rim or open sea, on a line that
## WANDERS (seeded noise) — never a walkable square that just stops. Pure per-cell derivation
## (wilds_gen border helpers), so regions and the full derive agree byte for byte.
@export_enum("None", "Cliff rim", "Sea") var border_mode := 1
@export var border_cells := 12:
	set(v):
		border_cells = clampi(v, 4, 64)

@export_group("Paint")
## Sparse pages: page index -> PackedInt32Array / PackedByteArray of PAGE*PAGE values.
@export var tier_pages: Dictionary = {}
@export var flag_pages: Dictionary = {}
@export var forest_pages: Dictionary = {}
@export var spawn_cell := Vector2i(-1, -1)

@export var version := 2


func cell_count() -> int:
	return cells_w * cells_h


func idx(c: Vector2i) -> int:
	return c.y * cells_w + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < cells_w and c.y >= 0 and c.y < cells_h


func flag(c: Vector2i, bit: int) -> bool:
	return in_bounds(c) and (flag_at(idx(c)) & bit) != 0


# ---------------------------------------------------------------- paged access --------------
# Packed arrays held inside a Dictionary mutate IN PLACE without a cast (the measured law) —
# which is what makes set_* writes on a fetched page stick.

func _page_key(i: int) -> int:
	@warning_ignore("integer_division")
	return (i / cells_w / PAGE) * ((cells_w + PAGE - 1) / PAGE) + (i % cells_w / PAGE)


func _page_off(i: int) -> int:
	@warning_ignore("integer_division")
	return (i / cells_w % PAGE) * PAGE + (i % cells_w % PAGE)


func tier_paint_at(i: int) -> int:
	var p = tier_pages.get(_page_key(i))
	return 0 if p == null else (p as PackedInt32Array)[_page_off(i)]


func set_tier_paint(i: int, v: int) -> void:
	var k := _page_key(i)
	if not tier_pages.has(k):
		if v == 0:
			return
		var page := PackedInt32Array()
		page.resize(PAGE * PAGE)
		tier_pages[k] = page
	tier_pages[k][_page_off(i)] = v


func flag_at(i: int) -> int:
	var p = flag_pages.get(_page_key(i))
	return 0 if p == null else (p as PackedByteArray)[_page_off(i)]


func set_flag(i: int, v: int) -> void:
	var k := _page_key(i)
	if not flag_pages.has(k):
		if v == 0:
			return
		var page := PackedByteArray()
		page.resize(PAGE * PAGE)
		flag_pages[k] = page
	flag_pages[k][_page_off(i)] = v


func forest_at(i: int) -> int:
	var p = forest_pages.get(_page_key(i))
	return 0 if p == null else (p as PackedByteArray)[_page_off(i)]


func set_forest(i: int, v: int) -> void:
	var k := _page_key(i)
	if not forest_pages.has(k):
		if v == 0:
			return
		var page := PackedByteArray()
		page.resize(PAGE * PAGE)
		forest_pages[k] = page
	forest_pages[k][_page_off(i)] = clampi(v, 0, 255)


func page_count() -> int:
	return tier_pages.size() + flag_pages.size() + forest_pages.size()


## Test convenience: flood one field everywhere (small maps only — it allocates every page).
func fill_forest(v: int) -> void:
	for i in cell_count():
		set_forest(i, v)


func fill_flags_or(bit: int) -> void:
	for i in cell_count():
		set_flag(i, flag_at(i) | bit)


# ---------------------------------------------------------------- v1 migration --------------
## Pre-W6 maps saved DENSE arrays under these names; loading one lands here and is folded
## into pages. Never exported, so a re-save writes pages only.
func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"tier_paint":
			var arr := value as PackedInt32Array
			for i in mini(arr.size(), cell_count()):
				if arr[i] != 0:
					set_tier_paint(i, arr[i])
			return true
		&"flags":
			var arr := value as PackedByteArray
			for i in mini(arr.size(), cell_count()):
				if arr[i] != 0:
					set_flag(i, arr[i])
			return true
		&"forest_paint":
			var arr := value as PackedByteArray
			for i in mini(arr.size(), cell_count()):
				if arr[i] != 0:
					set_forest(i, arr[i])
			return true
	return false

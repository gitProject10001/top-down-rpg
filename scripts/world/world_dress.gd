@tool
extends RefCounted
## WHAT A BAKED WORLD IS MADE OF, put on after the bake rather than during it.
##
## The floorplan gives every piece a flat prototyping colour, which is the right default for a
## blockout and the wrong one for a level you walk into. This walks a finished unit scene and
## hangs a material on each piece by what the bake already said it was — `floorplan_wall` gets
## stone, `floorplan_floor` gets the cobbles — using the SAME materials the hand-built crypt
## uses, so a generated dungeon and an authored one look like the same place.
##
## IT IS A `material_override`, and deliberately. The mesh keeps whatever the bake gave it, so
## nothing is lost and a piece can be un-dressed by clearing one property. It is also how the
## crypt's own theme layer does it (`DungeonTheme` hangs `theme.material` on every stone mesh),
## which means one shared material instance across every piece: Godot's Forward+ renderer
## auto-instances identical mesh-and-material pairs, so a hundred wall slabs collapse toward one
## draw rather than a hundred.
##
## The floorplan addon is untouched. This is the world pipeline dressing its own output, the
## same way `world_merge` will later merge it.

## The crypt's own materials, the ones `zone_crypt` already builds with.
##
## THE WALL IS THE TEXTURED ONE, not the procedural one. `crypt_stone.tres` is a shader that
## makes stone out of noise — right for a kit piece whose relief is modelled in the mesh, wrong
## for a flat CSG slab, where there is no geometry for the shading to sit on and it reads as
## grey paint. `dungeon_wall_crypt.tres` is the crypt's PolyHaven blockwork: albedo, normal, ARM
## and a parallax heightmap, so the courses and the mortar are IN the surface. It is the same
## material the hand-built crypt's walls use, and it pairs with the cobbles below it because
## they came from the same set.
##
## The bake's UVs are already in metres — a CSGPolygon3D lays its side faces out by path
## distance and depth — so the materials' own `uv1_scale` is a real-world tiling and nothing
## here has to rescale anything.
const STONE := "res://assets/materials/dungeon_wall_crypt.tres"
const FLOOR := "res://assets/materials/dungeon_floor_crypt.tres"

## What the bake stamps on a piece, and what that piece is made of.
const BY_META := {
	"floorplan_wall": STONE,
	"floorplan_floor": FLOOR,
}


## Dress one baked unit. Returns how many pieces were given a material.
static func dress(node: Node) -> int:
	var cache := {}
	return _walk(node, cache)


static func _walk(node: Node, cache: Dictionary) -> int:
	var n := 0
	for meta in BY_META:
		if not node.has_meta(meta):
			continue
		var path: String = BY_META[meta]
		if not cache.has(path):
			cache[path] = load(path) if ResourceLoader.exists(path) else null
		var mat: Material = cache[path]
		if mat == null:
			continue
		# the finalized piece is a body with one `Mesh` child (plan_refine's own naming), but a
		# piece that was left visual-only is the mesh itself
		var mesh: GeometryInstance3D = node.get_node_or_null("Mesh") as GeometryInstance3D
		if mesh == null and node is GeometryInstance3D:
			mesh = node
		if mesh != null:
			mesh.material_override = mat
			n += 1
		break
	for c: Node in node.get_children():
		n += _walk(c, cache)
	return n

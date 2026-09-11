@tool
class_name GladeCutaway
extends Node
## A DOLL'S HOUSE: take the roof off and the near wall away, so you can see the room you are standing
## in — and only while you are standing in it.
##
## WHY THIS IS NOT `SeeThrough`. That one stipples fragments between the camera and the player, in
## `painted_env.gdshader` — so it only works on geometry wearing that shader. A mass dressed in a PBR
## set is not, and never will be without giving up the textures. This is the other answer, and the
## one a look-dev wants: not a hole around the player, but the near half of the building removed, the
## way an architectural model is cut.
##
## THE WALLS DO NOT LEAVE — THEY STOP BEING DRAWN. This is the whole difference between a cutaway and
## a demolition, and the first version got it wrong. `visible = false` takes a mesh out of the shadow
## pass with it, so opening a house flooded its rooms with direct sun, erased the shadow it had been
## throwing across its own yard, and lit every interior surface from an angle no wall would ever have
## allowed. `SHADOW_CASTING_SETTING_SHADOWS_ONLY` is the setting that means what is actually wanted:
## the wall is still there to the light, and gone to the eye. The room you walk into is a room in
## shade, because it is under a roof, because it IS under a roof.
##
## AND IT NEVER REBUILDS. A mass under a roof lays NO COPING — right, the strip would fight the eaves
## for the same pixels — so the first way to open one was to hide the roof and regrow the stone. That
## is five masses and a million vertices in a single frame, measured at 1.24 SECONDS, and it is
## exactly the hitch reported as "it lags when I enter". Moving it to load only moved the cost.
##
## So the cutaway lays the wall tops ITSELF, out of the same two footprints it already asks for to
## cap the cut ends — a lid per standing wall, flat, in the wall's own colour. Nothing regrows,
## nothing is regrown at load either, and opening a building is visibility, a shadow flag, and one
## small mesh.

## The building to open up. Empty = this node's parent.
@export var target: NodePath
## Off restores everything, immediately.
@export var enabled := true:
	set(v):
		enabled = v
		_want = -1
		_apply()
## ONLY WHILE YOU ARE INSIDE. A house that is always cut open is a ruin; this is meant to be the view
## you get when you walk in, and the building you drew when you are outside looking at it.
@export var only_inside := true:
	set(v):
		only_inside = v
		_want = -1
		_apply()
## Who counts as "inside". The same group `SeeThrough` follows.
@export var occupant_group := "player"
## Stop drawing the roofs as well. A roofed room is a room you cannot see into, whatever you do to
## its walls — but the roof goes on shading it, which is the point.
@export var open_roofs := true:
	set(v):
		open_roofs = v
		_want = -1
		_apply()
## How square-on a face must be to the viewer before it is dropped. 0 removes every face facing the
## camera at all — at a corner that is two of them, which is usually what you want.
@export_range(0.0, 0.9, 0.05) var facing := 0.15

var _ghosted: Array = []                           ## [instance, its own cast_shadow] to put back
var _cuts: Array[MeshInstance3D] = []              ## the section faces — ours, not the mass's
var _roofed: Array[GeometryInstance3D] = []        ## every mesh under a GladeRoof
var _rooms := {}                                   ## mass id -> its room volumes, they do not move
var _primed := false
var _want := -1                                    ## -1 unknown, 0 whole, 1 cut — so state CHANGES
var _sig := ""                                     ## ...and which walls went, for the same reason


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return                                     # the exported setters fire during scene load
	var root := get_node_or_null(target) if not target.is_empty() else get_parent()
	if root == null:
		return
	var masses := _masses(root)
	if masses.is_empty():
		return
	if not _primed or not _intact():
		_prime(root, masses)
	var cut := enabled and (not only_inside or _occupied(masses))

	# THE STATE CHANGE, and nothing here costs a rebuild: the roofs stop being drawn, and that is one
	# flag per roof mesh.
	var state := 1 if cut else 0
	if state != _want:
		_want = state
		_sig = ""
		_show_all()
		if cut and open_roofs:
			for gi in _roofed:
				_ghost(gi)

	if not cut:
		return
	var cam := _camera()
	if cam == null:
		return

	# WHICH WALLS ARE IN THE WAY, decided first and acted on only if the ANSWER MOVED. A shadow flag
	# is free; building the section faces is a SurfaceTool commit, and doing that sixty times a second
	# for a camera that has not crossed a corner is the "re-deriving in a loop" the README warns about.
	var plan: Array = []
	var sig := ""
	for mass: GladeMass in masses:
		var near := _near(mass, cam.global_position)
		plan.append(near)
		sig += "%s:%s|" % [mass.name, ",".join(PackedStringArray(near.keys()))]
	if sig == _sig:
		return
	_sig = sig
	_show_all()
	if open_roofs:
		for gi in _roofed:
			_ghost(gi)
	for k in masses.size():
		_open(masses[k], plan[k])


# ---------------------------------------------------------------- the one-off ----------------


## LOOK THE BUILDING OVER ONCE: where its rooms are, and which meshes belong to its roofs. Neither
## answer changes while you play — a house does not move and its roof does not regrow — and both are
## asked once a frame otherwise.
func _prime(root: Node, masses: Array) -> void:
	_show_all()
	_roofed.clear()
	_rooms.clear()
	for m: GladeMass in masses:
		_rooms[m.get_instance_id()] = m.room_volumes()
	_gather_roof_meshes(root)
	_primed = true
	_want = -1


## Has anything grown back underneath us? One dead roof mesh means a mass was rebuilt.
func _intact() -> bool:
	for gi in _roofed:
		if not is_instance_valid(gi):
			return false
	return true


func _gather_roof_meshes(n: Node) -> void:
	for c in n.get_children(true):
		if c is GladeRoof:
			var st: Array = [c]
			while not st.is_empty():
				var cur: Node = st.pop_back()
				for g in cur.get_children(true):
					st.append(g)
				var gi := cur as GeometryInstance3D
				if gi != null:
					_roofed.append(gi)
		else:
			_gather_roof_meshes(c)


# ---------------------------------------------------------------- per frame ------------------


## Is whoever we are watching standing in one of these rooms? Asked of the ROOM, not the block: a
## player leaning on the outside of a wall is not inside the house. The volumes are the cached ones —
## a building does not move, and rebuilding five prisms every frame is not free.
func _occupied(masses: Array) -> bool:
	var who := get_tree().get_first_node_in_group(occupant_group) as Node3D
	if who == null:
		return false
	var at := who.global_position + Vector3.UP * 0.9
	for m: GladeMass in masses:
		for v: GladeVolume in _rooms.get(m.get_instance_id(), []):
			if v.contains(at):
				return true
	return false


## STOP DRAWING IT, DO NOT REMOVE IT. The mesh keeps its place in the shadow pass, so the room behind
## it stays as dark as the wall in front of it always made it.
func _ghost(gi: GeometryInstance3D) -> void:
	if not is_instance_valid(gi):
		return
	if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return
	_ghosted.append([gi, gi.cast_shadow])
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


func _show_all() -> void:
	for pair in _ghosted:
		var gi: GeometryInstance3D = pair[0]
		if is_instance_valid(gi):
			gi.cast_shadow = pair[1]
	_ghosted.clear()
	for m in _cuts:
		if is_instance_valid(m):
			m.queue_free()
	_cuts.clear()


## Which faces are in the way, asked of the mass's own volume rather than guessed off a quad — a wall
## panel has no winding reliable enough to read a normal from. Face key -> face index.
func _near(mass: GladeMass, eye: Vector3) -> Dictionary:
	var near := {}
	if not mass.hollow:
		return near                                # there is nothing inside a solid to look at
	var faces: Array = mass._local_faces()
	var xf := mass.global_transform
	for i in faces.size():
		var n: Vector3 = (xf.basis * (faces[i].normal as Vector3)).normalized()
		if absf(n.y) > 0.7:
			continue                               # a floor and a lid are not in anybody's way
		var here := xf * _middle(faces[i].polygon)
		if n.dot((eye - here).normalized()) > facing:
			near[mass.face_key(i)] = i
	return near


## Take away every wall standing between the viewer and the inside — WHOLE, every layer of it.
##
## The first version dropped the outer skin alone and left the lining behind: a single back-facing
## sheet, invisible from out here, with its coping still floating three metres up where the wall used
## to be. Removing a wall means removing the wall — skin, lining, coping, soffit, chamfer and cap
## stone together — and the ones that REMAIN are where the thickness has to show.
func _open(mass: GladeMass, near: Dictionary) -> void:
	if near.is_empty():
		return
	_section(mass, mass._local_faces(), near)
	var cut := false
	for c in mass.get_children(true):
		var gi := c as GeometryInstance3D
		if gi == null or not gi.visible:
			continue
		var key := String(mass._face_by_mesh.get(gi.name, ""))
		if key.is_empty():
			continue
		if not near.has(key.get_slice(".", 0)):    # "front.top" and "front" are the same wall
			continue
		_ghost(gi)
		cut = true
	# ...AND ITS CORNER STONES WITH IT. Quoins are instanced into ONE MultiMesh per mass, so there is
	# no per-corner flag to set and no face key to match: drop a wall and its dressed angles stay
	# behind as a row of columns standing in mid-air.
	if cut:
		for c in mass.get_children(true):
			var mm := c as MultiMeshInstance3D
			if mm:
				_ghost(mm)


# ---------------------------------------------------------------- the cut face ---------------


## THE WALL, CUT — a quad standing in the gap the removed wall used to close.
##
## A mass in PANEL mode is a SHELL: an outer skin, a lining `depth` behind it, and nothing between
## them. While every wall is standing that is invisible and correct — a room is a shell and no one
## ever sees the cavity. Take one wall away and the two neighbours it met are left ending in mid-air,
## a hand's breadth apart, with the hollow between them open to the sky. The coping caps that gap
## along the top and the deck caps it at the bottom; the vertical end had nothing, and an open slot
## at eye level is what reads as cardboard however thick the wall is.
##
## So the cut gets a face, the way a cut in an architectural model does: outer corner to inner corner,
## floor to top, at every corner where a removed wall met one that is still there.
##
## AND SO DOES THE TOP OF EVERY WALL LEFT STANDING, for the same reason and out of the same two
## footprints. A roofed mass lays no coping, so with the roof drawn off you would otherwise look
## straight down into the cavity along the whole length of every remaining wall — the open shell that
## made the first version of this read as cardboard. A lid closes it, and the kit never has to know.
func _section(mass: GladeMass, faces: Array, near: Dictionary) -> void:
	var rooms: Array = _rooms.get(mass.get_instance_id(), [])
	if rooms.is_empty():
		return
	var room: GladeVolume = rooms[0]
	var inner := room.footprint()
	if inner.size() < 3:
		return
	var xf := mass.global_transform
	var y0: float = room.y0
	var y1: float = room.y1 - 0.005                # a whisker under the top, never through it

	# WHERE THE REMOVED WALLS END. A corner shared by TWO removed walls is inside the part that went
	# away and gets nothing; a corner where one went and one stayed is a cut, and gets a face.
	var tally := {}
	for i: int in near.values():
		for p in _corners_of(xf, faces[i].polygon):
			var k := "%.2f,%.2f" % [p.x, p.y]
			tally[k] = int(tally.get(k, 0)) + 1
	var quads := PackedVector3Array()
	for i: int in near.values():
		for p in _corners_of(xf, faces[i].polygon):
			if int(tally.get("%.2f,%.2f" % [p.x, p.y], 0)) != 1:
				continue
			# ...AND ITS OPPOSITE NUMBER ON THE ROOM SIDE, by nearest: the inner ring is the outer one
			# walked inwards by the wall depth, so a corner's partner is never in doubt.
			var q := inner[0]
			for c: Vector2 in inner:
				if c.distance_squared_to(p) < q.distance_squared_to(p):
					q = c
			var a := Vector3(p.x, y0, p.y)
			var b := Vector3(q.x, y0, q.y)
			quads.append_array([a, b, b + Vector3.UP * (y1 - y0), a + Vector3.UP * (y1 - y0)])

	# ...AND A LID ON EVERY WALL STILL STANDING. Its own two ground corners and their partners on the
	# room side, up at the top of the wall: the strip the mass would have laid as a coping if it were
	# not standing under a roof.
	for i in faces.size():
		if near.has(mass.face_key(i)) or mass.face_style(i) == null:
			continue
		var n: Vector3 = (xf.basis * (faces[i].normal as Vector3)).normalized()
		if absf(n.y) > 0.7:
			continue
		var ends := _corners_of(xf, faces[i].polygon)
		if ends.size() != 2:
			continue
		var lid := PackedVector3Array()
		for p: Vector2 in ends:
			var q := inner[0]
			for c: Vector2 in inner:
				if c.distance_squared_to(p) < q.distance_squared_to(p):
					q = c
			lid.append(Vector3(p.x, y1, p.y))
			lid.append(Vector3(q.x, y1, q.y))
		quads.append_array([lid[0], lid[1], lid[3], lid[2]])
	if quads.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in range(0, quads.size(), 4):
		var c0 := quads[q]
		var c1 := quads[q + 1]
		var c3 := quads[q + 3]
		var n := (c1 - c0).cross(c3 - c0).normalized()
		# UV ACROSS THE QUAD ITSELF, not off a world axis: `u = x + z` collapses to nothing on any wall
		# running along the x = -z diagonal, which two of this house's four do.
		var w: float = (c1 - c0).length()
		var h: float = (c3 - c0).length()
		var u := fposmod(c0.x * 0.37 + c0.z * 0.71, 4.0)     # so two cuts are not the same crop
		var uv := [Vector2(u, h), Vector2(u + w, h), Vector2(u + w, 0.0), Vector2(u, 0.0)]
		# BOTH WINDINGS. A doll's house is walked round, and a section has no back.
		for side in [[0, 1, 2, 3, 1], [3, 2, 1, 0, -1]]:
			for t in [[0, 1, 2], [0, 2, 3]]:
				for j in t:
					var v: int = side[j]
					st.set_normal(n * float(side[4]))
					st.set_uv(uv[v])
					st.add_vertex(quads[q + v])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.top_level = true                            # this node is a plain Node; build in world space
	mi.mesh = st.commit()
	mi.material_override = _poche(mass)
	# IT THROWS NO SHADOW OF ITS OWN. The wall it stands in is still casting one — that is the whole
	# arrangement — and a second caster in the same 46 cm only ever fights the first.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_cuts.append(mi)


## The two ends of an upright face, in world XZ. A face polygon is four corners over two ground
## points; which two is all a section needs.
func _corners_of(xf: Transform3D, poly: PackedVector3Array) -> Array:
	var out: Array = []
	for p in poly:
		var w := xf * p
		var v := Vector2(w.x, w.z)
		var seen := false
		for o: Vector2 in out:
			if o.distance_to(v) < 0.01:
				seen = true
		if not seen:
			out.append(v)
	return out


## WHAT A CUT FACE IS MADE OF: the lining's COLOUR, laid flat — poché, the way a section is filled on
## a drawing. Not the lining's texture.
##
## That is a decision, though it began as a workaround. A photographic PBR set describes the FACE of
## a wall — a plaster skim, a course of rubble — and a section is not the face. It is the stuff behind
## it, which nobody photographed; wrapping the crop round the corner is the same mistake as texturing
## a sawn board with a picture of its own varnish. A flat fill, one shade down from the wall it
## belongs to, is what reads as solid.
##
## Recorded because it cost real time: those same materials render BLACK on a surface built at runtime
## here, with correct normals, generated tangents, positive in-range UVs and every map but albedo
## disabled — clearing `albedo_texture` alone brings them back, and changing the filter does not. The
## panels the mass builds wear them happily, so it is something about the mesh rather than the
## material, and I did not find it. Worth knowing before anyone textures generated geometry.
func _poche(mass: GladeMass) -> Material:
	var hue := Color(0.82, 0.80, 0.76)
	for c in mass.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var key := String(mass._face_by_mesh.get(mi.name, ""))
		if key.is_empty():
			continue
		var std := mi.get_active_material(0) as StandardMaterial3D
		if std == null:
			continue
		hue = std.albedo_color
		if key.ends_with(".inner"):
			break                                  # the room's own colour, when the room names one
	var cut := StandardMaterial3D.new()
	# BARELY DARKER THAN THE WALL. At a quarter down it stopped reading as the wall's own thickness
	# and started reading as a pillar standing beside it, which is a different building.
	cut.albedo_color = hue.darkened(0.08)
	cut.roughness = 0.95
	return cut


# ---------------------------------------------------------------- odds and ends --------------


func _middle(poly: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in poly:
		sum += p
	return sum / maxf(1.0, float(poly.size()))


func _masses(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children(true):
		if c is GladeMass:
			out.append(c)
		out.append_array(_masses(c))
	return out


func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp else null

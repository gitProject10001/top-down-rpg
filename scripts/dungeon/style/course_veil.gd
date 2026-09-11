class_name CourseVeil
extends Node
## Hides the handful of wall courses that are between the player and the camera RIGHT NOW.
##
## WHY THE STATIC CUTAWAY IS NOT ENOUGH. RoomDresser.cutaway_out drops the courses on the side of a
## room that faces the camera, which is correct and free for the case that matters most: the player
## standing inside a room. It cannot help the moment the player walks THROUGH a wall. Leaving a room
## northward puts that room's FAR wall — full height, 3.5 m of course above the base — directly
## between the player and the lens, and a 6.8 m wall hides them for 5.1 m on the far side of it.
## That is every doorway and every corridor mouth in the dungeon.
##
## So: the static cut handles the common case at zero runtime cost, and this handles the residual.
## It only ever looks at pieces the static cut already spared, and it only hides — it never shows
## something the theme decided to remove.
##
## CHEAP BY CONSTRUCTION. The list is collected once at build time off the COURSE_META that
## RoomDresser already stamps, and the per-frame work is a squared-distance reject followed by two
## float compares. A ten-room crypt has ~1,800 courses; the reject discards all but a few dozen.
##
## It toggles `visible` rather than fading. A fade needs per-mesh transparency, which pushes these
## into the sorted pass, and a course that is dissolving is a course the player is walking under —
## they are looking at their own character, not at the wall behind their head.

## How much wider than the piece itself the corridor of interest is, across the camera's view
## direction. The lane is the PIECE'S OWN half-span plus this, so at a 4 m module it is 2.0 + 0.6 =
## 2.6 — exactly the constant that used to be hard-coded here, which is what makes a change this
## central landable: every piece the dungeon builds today gets the identical boundary it had.
##
## THE HALF-SPAN IS USED AS A RADIUS, not projected onto world X. A run lying along Z occupies only
## its own thickness in X, so a radius over-reserves for it — but over-reserving costs two float
## compares on a piece that was going to fail the height test anyway, and under-reserving costs a
## course standing over the player's head. The cheap error is the one worth making, and the
## projected version would also have to be recomputed if anything ever re-yawed a piece.
const LANE_PAD := 0.6
## tan(FRAME_PITCH). A piece of height H hides the player for 1/tan = 0.75 * H metres in front of it.
const SLOPE := 1.3333
## Only bother with pieces within this radius of the player.
const REACH := 16.0
## Schmitt-trigger margin, in metres, on every one of the four tests below.
##
## WITHOUT THIS THE VEIL CHATTERS. All four are hard thresholds on continuous quantities, so a
## player standing on any of the boundaries — and the boundaries run right through the doorways
## people stand in — flips the same piece on and off at frame rate. That was already ugly; with TAA
## it is worse than ugly, because a mesh that pops has no motion vector, so the reprojection has
## nothing to reject against and smears the course across the following frames.
##
## 0.5 m is a comfortable stride and a fraction of the 4 m module, so the deadband is wide enough
## to swallow the follow camera's own jitter and narrow enough that the piece still clears the
## sightline before it reappears.
const HYST := 0.5

var _pieces: Array[Node3D] = []
## Each piece's lane half-width and its own height, RESOLVED ONCE at collect time. Parallel to
## _pieces rather than read back off the node every frame: the distance reject runs over all ~1,800
## courses each tick and only a few dozen survive it, so a get_meta() before the reject would put a
## dictionary lookup on the hot path to save an array index on the cold one.
var _lane := PackedFloat32Array()
var _rise := PackedFloat32Array()
var _reach := PackedFloat32Array()
var _player: Node3D


## Called by the generator once the dungeon is built. Walks for the meta rather than being handed a
## list, so a template or a future pass that adds its own courses is picked up for free.
func collect(root: Node) -> void:
	_pieces.clear()
	_lane.clear()
	_rise.clear()
	_reach.clear()
	_gather(root)


## How many pieces this veil is responsible for. Exists for verify_dungeon: the cutaway suite lets
## anything carrying COURSE_META through its occlusion sweep on the grounds that this fades it, and
## that exemption is only sound if the collect walk really found every one of them.
func pieces_count() -> int:
	return _pieces.size()


func _gather(node: Node) -> void:
	if node is Node3D and node.has_meta(RoomDresser.COURSE_META):
		_pieces.append(node)
		# A PIECE THAT WAS NOT STAMPED KEEPS TODAY'S NUMBERS rather than reporting zero. The walk
		# exists so a template or a later pass that adds its own courses is picked up for free, and
		# such a piece may carry only COURSE_META; a zero lane would silently exempt it from the
		# whole veil, which is the failure this milestone is about.
		var span: float = node.get_meta(RoomDresser.COURSE_SPAN, RoomShape.TILE)
		_lane.append(span * 0.5 + LANE_PAD)
		_rise.append(node.get_meta(RoomDresser.COURSE_RISE, DungeonLayout.COURSE_H))
		# REACH IS THE PIECE'S TOO. A 16 m run whose CENTRE is 17 m away still has an end 9 m from
		# the player, so culling on the centre alone drops it exactly the way the fixed lane did,
		# one axis over. Only the amount by which the piece exceeds one module is added, so at 4 m
		# this is REACH unchanged.
		_reach.append(REACH + maxf(0.0, span - RoomShape.TILE) * 0.5)
		return                                  # a course has no courses inside it
	for c in node.get_children():
		_gather(c)


func _process(_delta: float) -> void:
	if _pieces.is_empty():
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var at := _player.global_position
	# The camera looks along -Z at a pinned yaw, so "between the player and the lens" is simply
	# "further +Z than the player". No camera lookup, and nothing to go stale if the rig is absent.
	for i in _pieces.size():
		var p := _pieces[i]
		if not is_instance_valid(p):
			continue
		var d := p.global_position - at
		var lane := _lane[i]
		# The piece's OWN current state is the hysteresis state — no side table to keep in step with
		# a list a template or a later pass can add to. Showing pushes every threshold in the
		# direction that keeps it showing; hidden pushes them the other way. The sign does the work:
		# a visible piece must be 0.5 m INSIDE the hiding region before it goes, and a hidden one
		# must be 0.5 m clear of it before it comes back.
		var m := -HYST if p.visible else HYST
		if absf(d.x) > lane + m or d.z <= -m or d.z > _reach[i] + m:
			p.visible = true
			continue
		# How high this piece would have to be to reach the sightline at its distance. Below that it
		# is under the ray and harmless — which is what spares the band and most cornices.
		p.visible = d.y + _rise[i] < d.z * SLOPE - m

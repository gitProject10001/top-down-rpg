@tool
extends RefCounted
## THE SAMPLE PLAN AS PIXELS — a synthetic copy of the picture the user drew (700 × 540 px, about
## 62 px per metre): a rectangular room, a circular arena hung off its bottom wall with the wall
## opened between them, a corridor off the right wall whose far end is a doorway between two stubs,
## a purple bed (rectangle) and a purple round table (a ring). The suite and the screenshot run
## on this so nothing depends on a file outside the repo; drop the real picture at
## assets/reference/floorplan_sample.png and the suite traces that too.

const W := 700
const H := 540
const PPM := 62.0
const STROKE := 10

const PURPLE := Color(0.49, 0.0, 0.94)

# Room outer box, corridor band, circle, marks — all in image px.
const ROOM := Rect2i(30, 120, 335, 270)
const CORR_X0 := 365
const CORR_X1 := 495
const CORR_Y0 := 200
const CORR_Y1 := 300
const DOOR_GAP_Y0 := 220
const DOOR_GAP_Y1 := 280
const CIRC_C := Vector2(195, 435)
const CIRC_R := 100.0                     # bottom at 535: enclosed, like the picture
const CIRC_OPEN_Y := 352
const BED := Rect2i(50, 140, 105, 75)
const TABLE_C := Vector2(185, 270)
const TABLE_R := 48.0
const TABLE_HOLE := 15.0


static func build() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	# room walls
	_stroke_rect(img, ROOM, STROKE)
	# corridor: top + bottom walls, stubs at the far end
	_fill(img, Rect2i(CORR_X0, CORR_Y0, CORR_X1 - CORR_X0, STROKE))
	_fill(img, Rect2i(CORR_X0, CORR_Y1 - STROKE, CORR_X1 - CORR_X0, STROKE))
	_fill(img, Rect2i(CORR_X1 - STROKE, CORR_Y0, STROKE, DOOR_GAP_Y0 - CORR_Y0))
	_fill(img, Rect2i(CORR_X1 - STROKE, DOOR_GAP_Y1, STROKE, CORR_Y1 - DOOR_GAP_Y1))
	# open the room's right wall onto the corridor
	_fill(img, Rect2i(ROOM.end.x - STROKE, CORR_Y0 + STROKE, STROKE, CORR_Y1 - CORR_Y0 - 2 * STROKE),
			Color.WHITE)
	# circle ring, open at the top where it meets the room
	for y in H:
		for x in W:
			var d := Vector2(x, y).distance_to(CIRC_C)
			if d <= CIRC_R and d >= CIRC_R - STROKE and y >= CIRC_OPEN_Y:
				img.set_pixel(x, y, Color.BLACK)
	# open the room's bottom wall between the ring's shoulders
	var half := sqrt(CIRC_R * CIRC_R - pow(CIRC_C.y - float(ROOM.end.y - STROKE * 0.5), 2.0))
	_fill(img, Rect2i(int(CIRC_C.x - half) + STROKE, ROOM.end.y - STROKE, int(2.0 * half) - 2 * STROKE,
			STROKE), Color.WHITE)
	# scale bar: a thin short line, top left — should be ignored as a wall fragment
	_fill(img, Rect2i(62, 30, 62, 2))
	# marks
	_fill(img, BED, PURPLE)
	for y in H:
		for x in W:
			var d := Vector2(x, y).distance_to(TABLE_C)
			if d <= TABLE_R and d >= TABLE_HOLE:
				img.set_pixel(x, y, PURPLE)
	return img


static func _fill(img: Image, r: Rect2i, c := Color.BLACK) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x >= 0 and y >= 0 and x < W and y < H:
				img.set_pixel(x, y, c)


static func _stroke_rect(img: Image, r: Rect2i, t: int) -> void:
	_fill(img, Rect2i(r.position.x, r.position.y, r.size.x, t))
	_fill(img, Rect2i(r.position.x, r.end.y - t, r.size.x, t))
	_fill(img, Rect2i(r.position.x, r.position.y, t, r.size.y))
	_fill(img, Rect2i(r.end.x - t, r.position.y, t, r.size.y))

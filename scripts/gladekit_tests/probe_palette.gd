extends SceneTree
## DOES IT LOOK PAINTED — as a number.
##
## The look-dev counterpart to probe_seams.gd. "Hand-painted" is not a taste that can only be argued
## about: a painting and a render differ in ways you can measure, and the three that matter here are
##
##   1. THE VALUE RANGE. A painting has a deep end and spreads its midtones; a render crushes
##      everything into a band around the exposure. This is the single biggest tell.
##   2. CHROMA IN THE LIGHT. A render's lit surfaces drift toward white. A painter keeps them
##      coloured, and the lit half of the reference is twice as saturated as the render's was.
##   3. THE COLOUR OF SHADOW. Shadows should be a saturated hue, not an absence — and the same hue
##      the reference uses. This one was already right and is measured to keep it that way.
##
## Run headless, against the reference plate and any render:
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/probe_palette.gd -- --shot=C:/some/folder/whinbek_painted.png

const PLATE := "res://docs/images/references/whinbek-conceptart.jpg"
const SAMPLE := 520                            ## longest side after downscale; plenty for statistics

## THE TARGETS ARE ON THE TWO MASSES, NOT ON THE WHOLE FRAME.
##
## The first version of this measured percentiles over every building pixel, and the spread target
## was unreachable for a reason that had nothing to do with shading: the roof is 72% of the render's
## masked pixels and only 44% of the plate's, because the painting also contains a tree, awnings,
## clutter, a figure and a straw foreground. A whole-frame histogram compares SUBJECT MATTER as much
## as light, and no amount of tuning a shader will make a render contain a tree.
##
## What a painter actually controls, and what these measure: how dark the roof mass is, how light
## the wall mass is, how far apart they sit, and how much colour each keeps. Those are immune to how
## much ground or sky happens to be in frame.
const TARGETS := {
	"roof_lum": {"min": 0.18, "max": 0.29, "plate": 0.227, "what": "the roof reads as a dark mass"},
	"roof_sat": {"min": 0.30, "max": 0.46, "plate": 0.395, "what": "slate is grey-blue, not royal blue"},
	"wall_lum": {"min": 0.52, "max": 0.64, "plate": 0.580, "what": "lit walls sit high but do not blow out"},
	"wall_sat": {"min": 0.19, "max": 0.32, "plate": 0.242, "what": "cream keeps its colour"},
	"separation": {"min": 0.28, "plate": 0.353, "what": "wall minus roof — the value read of the whole building"},
	"hue_dark": {"min": 0.60, "max": 0.66, "plate": 0.638, "what": "shadow hue (blue-violet)"},
	"hue_light": {"min": 0.07, "max": 0.15, "plate": 0.116, "what": "lit hue (golden)"},
}

## Which pixels are roof and which are wall, by hue family. Slate is the only blue on the building
## and plaster/stone the only warm near-neutral, so this separates them without a render pass.
const ROOF_HUE := Vector2(0.50, 0.75)
const ROOF_MIN_SAT := 0.12
const WALL_HUE_HI := 0.13                      ## warm side of the wheel, wrapping past 0.92
const WALL_HUE_LO := 0.92

## The ground plane's straw colour, which is not part of the building and would drag every number
## toward itself. NOTE this window overlaps the plate's own warm lit surfaces — which is exactly why
## it is applied to the render only. Change the ground's colour and this has to follow.
const SAND_HUE := Vector2(0.09, 0.19)
const SAND_MIN_SAT := 0.18


func _initialize() -> void:
	_run()


func _run() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
	if shot.is_empty():
		print("[PALETTE] give me a render: -- --shot=C:/path/to.png")
		quit(1)
		return

	var plate := _measure(ProjectSettings.globalize_path(PLATE), false)
	var render := _measure(shot, true)
	if plate.is_empty() or render.is_empty():
		quit(1)
		return

	print("\n%-12s %10s %10s   %s" % ["", "PLATE", "RENDER", ""])
	for k: String in ["roof_lum", "roof_sat", "roof_px", "wall_lum", "wall_sat", "wall_px",
			"separation", "hue_dark", "hue_light", "p5", "p50", "p95"]:
		print("%-12s %10.3f %10.3f" % [k, plate[k], render[k]])

	print("\n=== against target ===")
	var fails := 0
	for k: String in TARGETS:
		var t: Dictionary = TARGETS[k]
		var v: float = render[k]
		var ok := true
		if t.has("min") and v < float(t["min"]):
			ok = false
		if t.has("max") and v > float(t["max"]):
			ok = false
		if not ok:
			fails += 1
		print("%-4s %-9s %.3f   want %s   (plate %.3f)  %s"
				% ["OK" if ok else "MISS", k, v, _band(t), float(t["plate"]), t["what"]])

	print("\n[PALETTE] %s" % ("all measures within target" if fails == 0
			else "%d of %d measures outside target" % [fails, TARGETS.size()]))
	quit(0 if fails == 0 else 1)


func _band(t: Dictionary) -> String:
	if t.has("min") and t.has("max"):
		return ">= %.2f and <= %.2f" % [float(t["min"]), float(t["max"])]
	if t.has("min"):
		return ">= %.2f" % float(t["min"])
	return "<= %.2f" % float(t["max"])


## Every statistic in one pass over the building's pixels.
func _measure(path: String, drop_sand: bool) -> Dictionary:
	var img := Image.load_from_file(path)
	if img == null:
		print("[PALETTE] cannot read %s" % path)
		return {}
	var w := img.get_width()
	var h := img.get_height()
	var scale: float = float(SAMPLE) / float(maxi(w, h))
	if scale < 1.0:
		img.resize(int(w * scale), int(h * scale), Image.INTERPOLATE_BILINEAR)

	var bg := _flood_background(img)
	var lums: Array[float] = []
	var kept: Array[Color] = []
	var w2 := img.get_width()
	for y in img.get_height():
		for x in w2:
			if bg[y * w2 + x] == 1:
				continue
			var c := img.get_pixel(x, y)
			if drop_sand and c.h > SAND_HUE.x and c.h < SAND_HUE.y and c.s > SAND_MIN_SAT:
				continue
			lums.append(c.get_luminance())
			kept.append(c)
	if kept.size() < 100:
		print("[PALETTE] only %d pixels survived the mask in %s" % [kept.size(), path])
		return {}

	# sort colours by luminance so the quartiles are the actual dark and lit quarters of the image
	var order: Array[int] = []
	for i in kept.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return lums[a] < lums[b])
	var n := order.size()
	var pct := func(p: float) -> float: return lums[order[mini(n - 1, int(n * p))]]

	var quarter := maxi(n / 4, 1)
	var dark: Array[Color] = []
	var light: Array[Color] = []
	for i in quarter:
		dark.append(kept[order[i]])
		light.append(kept[order[n - 1 - i]])

	# the two masses the building is actually made of
	var roof: Array[Color] = []
	var wall: Array[Color] = []
	for c in kept:
		if c.h > ROOF_HUE.x and c.h < ROOF_HUE.y and c.s > ROOF_MIN_SAT:
			roof.append(c)
		elif (c.h < WALL_HUE_HI or c.h > WALL_HUE_LO) and c.s > 0.03 and c.s < 0.40 \
				and c.get_luminance() > 0.25:
			wall.append(c)
	var roof_lum := _mean_lum(roof)
	var wall_lum := _mean_lum(wall)
	return {
		"roof_lum": roof_lum, "roof_sat": _mean_sat(roof), "roof_px": float(roof.size()),
		"wall_lum": wall_lum, "wall_sat": _mean_sat(wall), "wall_px": float(wall.size()),
		"separation": wall_lum - roof_lum,
		"hue_dark": _mean_hue(dark), "hue_light": _mean_hue(light),
		"p5": pct.call(0.05), "p50": pct.call(0.50), "p95": pct.call(0.95),
	}


func _mean_lum(a: Array[Color]) -> float:
	var s := 0.0
	for c in a:
		s += c.get_luminance()
	return s / maxf(float(a.size()), 1.0)


## THE BACKGROUND IS WHAT THE BORDER IS CONNECTED TO, not simply what is pale.
##
## A threshold was the obvious way to do this and it is wrong: the painterly grade's vignette darkens
## the frame's edges, so the backdrop is no longer one brightness, and "pale and colourless" started
## letting mid-grey backdrop into the statistics — where, being grey, it landed in the LIT quarter
## and reported the building's lit chroma as 0.011. The building's own white plaster is enclosed by
## dark roof and timber and is never reachable from the border, so a flood fill separates the two
## exactly and neither a vignette nor a gradient sky can fool it.
func _flood_background(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var bg := PackedByteArray()
	bg.resize(w * h)
	var queue := PackedInt32Array()
	var neutral := func(x: int, y: int) -> bool:
		var c := img.get_pixel(x, y)
		return c.s < 0.12 and c.get_luminance() > 0.45
	for x in w:
		for y: int in [0, h - 1]:
			if bg[y * w + x] == 0 and neutral.call(x, y):
				bg[y * w + x] = 1
				queue.append(y * w + x)
	for y in h:
		for x: int in [0, w - 1]:
			if bg[y * w + x] == 0 and neutral.call(x, y):
				bg[y * w + x] = 1
				queue.append(y * w + x)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % w
		var y := i / w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := ny * w + nx
			if bg[j] == 1 or not neutral.call(nx, ny):
				continue
			bg[j] = 1
			queue.append(j)
	return bg


func _mean_sat(a: Array[Color]) -> float:
	var s := 0.0
	for c in a:
		s += c.s
	return s / maxf(float(a.size()), 1.0)


## Hue is an ANGLE, so it is averaged on the circle — a plain mean of 0.02 and 0.98 gives 0.5, which
## is cyan, and neither pixel was anywhere near cyan. Weighted by saturation, because the hue of a
## nearly grey pixel is noise.
func _mean_hue(a: Array[Color]) -> float:
	var x := 0.0
	var y := 0.0
	for c in a:
		x += cos(c.h * TAU) * c.s
		y += sin(c.h * TAU) * c.s
	return fposmod(atan2(y, x) / TAU, 1.0)

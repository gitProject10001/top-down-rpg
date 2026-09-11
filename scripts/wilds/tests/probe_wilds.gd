extends SceneTree
## The wilds cost probe: a paint dab must stay inside the project's 16 ms budget (the number
## terrain_field's own probe pinned), and a full derive is timed for the record — the preview
## rebuilds once per GESTURE, not per dab, so derive cost buys smoothness, not stutter.

const DAB_BUDGET_MS := 16.0

func _initialize() -> void:
	var service = load("res://addons/wilds/editor/wilds_map_service.gd").new()
	var m: WildsMap = service.map
	m.seed = 42
	m.cells_w = 64
	m.cells_h = 64

	service.begin_gesture()
	var t0 := Time.get_ticks_usec()
	for k in 200:
		service.paint("tier", (k * 37) % m.cell_count(), 1)
		service.paint("flags", (k * 53) % m.cell_count(), WildsMap.F_WATER)
	var per_dab := float(Time.get_ticks_usec() - t0) / 400.0 / 1000.0
	var t1 := Time.get_ticks_usec()
	var ok: bool = service.end_gesture("probe stroke")
	var gesture_ms := float(Time.get_ticks_usec() - t1) / 1000.0

	var t2 := Time.get_ticks_usec()
	WildsGen.derive(m)
	var derive_ms := float(Time.get_ticks_usec() - t2) / 1000.0

	print("[PROBE] dab %.4f ms (budget %.1f)  gesture-close %.1f ms  full derive %.1f ms  committed=%s"
			% [per_dab, DAB_BUDGET_MS, gesture_ms, derive_ms, ok])
	if per_dab > DAB_BUDGET_MS:
		print("[PROBE] FAIL: a dab costs more than the budget")
		quit(1)
		return
	quit(0)

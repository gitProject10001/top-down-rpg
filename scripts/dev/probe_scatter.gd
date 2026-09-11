extends SceneTree
## FINGERPRINT EVERY SCATTERED FIELD, so a refactor of the scatter code can be proved to have
## changed nothing about the layout.
##
##   Godot_console.exe --path . --resolution 640x360 --script res://scripts/dev/probe_scatter.gd
##
## WHY THIS EXISTS. GrassPatch draws from ONE RandomNumberGenerator in a fixed order: the tuft mesh
## first, then the clump seeds, then a position per tuft, then a transform and a colour per tuft.
## Every one of those draws advances the same stream, so inserting, removing or reordering a single
## `rng.randf()` silently re-rolls all four shipping grass fields — the garden included. Nothing
## about that failure is visible in a diff; it is only visible in the picture, and only if you
## happen to be looking at the right patch.
##
## So: run this BEFORE touching the scatter, record the digests, run it after. Identical digests
## mean the extraction was pure. Any change means the RNG order moved and the work must be redone,
## however tidy the new code looks.
##
## THE BASELINE IS CHECKED HERE, NOT IN A COMMENT. It used to be four hex strings in this header
## that a run only PRINTED, so agreeing with them was a thing a human did by eye, and the exit code
## was 0 either way. That guard was silently broken for its whole life: the numbers first written
## down never matched a real run, at any commit — including the one that recorded them. Every run
## since has printed a mismatch into a log nobody diffed. Corrected below, and now asserted, because
## a fingerprint that does not fail is not a fingerprint.
##
## Changing a number here is allowed and sometimes right. It needs a reason written next to it, the
## way the one below is. The precedent: these fields were deliberately reshuffled once when the tuft
## mesh was given its own generator, so that editing a blade's shape would stop re-rolling the
## field's layout — one reshuffle, in exchange for shape and layout never being coupled again.
##
## Verified reproducible across 815a5e3..ff010fd on 2026-08-13, and unchanged by giving GrassPatch a
## terrain: the height lookup adds no draw to the stream, which is the whole reason it was built as
## a lookup.
const BASELINE := {
	"Room/GardenGrass": [6657, 0x37640957cc875e5b],
	"Room/ArenaGrassMid": [4978, 0x42181757deaf60fe],
	"Room/ArenaGrassWest": [5200, 0x1531fe62f1fd31df],
	"Room/ArenaGrassEast": [4400, 0x205730dd8877d2c8],
}


func _initialize() -> void:
	_run()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 40:
		await process_frame

	var fails := 0
	for path: String in BASELINE:
		var want: Array = BASELINE[path]
		var n := main.get_node_or_null(path) as MultiMeshInstance3D
		if n == null or n.multimesh == null:
			print("[SCATTER] %-22s MISSING" % path)
			fails += 1
			continue
		var got_n := n.multimesh.instance_count
		var got_d := _digest(n.multimesh)
		var ok: bool = got_n == want[0] and got_d == want[1]
		print("[SCATTER] %-22s %s n=%5d digest=%016x%s" % [path, "OK  " if ok else "MOVED",
				got_n, got_d, "" if ok else "   (want n=%d digest=%016x)" % [want[0], want[1]]])
		if not ok:
			fails += 1

	print("[SCATTER] %s" % ("all fields unchanged" if fails == 0
			else "%d FIELD(S) RE-ROLLED — the RNG order moved" % fails))
	quit(1 if fails > 0 else 0)


## FNV-1a over the raw transform floats. Cheap, order-sensitive, and sensitive to the last decimal —
## which is the point: a layout that shifted by a millimetre shifted because the stream moved.
func _digest(mm: MultiMesh) -> int:
	var h := 0xcbf29ce484222325
	for i in mm.instance_count:
		var t := mm.get_instance_transform(i)
		for v: Vector3 in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
			for f: float in [v.x, v.y, v.z]:
				# quantise, or float noise from an unrelated engine change trips the alarm
				h = (h ^ int(round(f * 4096.0))) * 0x100000001b3
				h &= 0x7fffffffffffffff
	return h

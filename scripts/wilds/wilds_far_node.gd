@tool
extends Node3D
## The far backdrop's one moving part: the canopy blobs CLEAR AROUND A FOCUS — wherever the
## real streamed sections stand (the player in game, the editor camera in a preview), the
## backdrop's masses zero-scale out so the true, selectable trees are never doubled by their
## own scenery. The coarse ground needs no such hole: it sits below the true surface and the
## real chunks simply cover it.
##
## Instances are never removed — hidden ones shrink to nothing and restore when the focus
## leaves, so the whole thing is a couple of set_instance_transform calls per moved chunk.

var _base: Array = []                          ## Transform3D per blob instance, as built
var _hidden: Dictionary = {}                   ## instance index -> true
var _last := Vector3(1e18, 0.0, 0.0)


func register_blobs(base: Array) -> void:
	_base = base


func blob_count() -> int:
	return _base.size()


func blob_origin(k: int) -> Vector3:
	return (_base[k] as Transform3D).origin


func hidden_count() -> int:
	return _hidden.size()


## `local` is this node's own space (== terrain-local: both sit at the terrain's origin).
## Cheap by hysteresis: nothing happens until the focus has moved 8 m.
func clear_around(local: Vector3, radius: float) -> void:
	if _base.is_empty() or local.distance_to(_last) < 8.0:
		return
	_last = local
	var mmi := get_node_or_null("FarCanopy") as MultiMeshInstance3D
	if mmi == null or mmi.multimesh == null:
		return
	var mm := mmi.multimesh
	var r2 := radius * radius
	for k in _base.size():
		var t: Transform3D = _base[k]
		var d2 := Vector2(t.origin.x - local.x, t.origin.z - local.z).length_squared()
		if d2 < r2:
			if not _hidden.has(k):
				mm.set_instance_transform(k, Transform3D(
						Basis.from_scale(Vector3(0.001, 0.001, 0.001)), t.origin))
				_hidden[k] = true
		elif _hidden.has(k):
			mm.set_instance_transform(k, t)
			_hidden.erase(k)

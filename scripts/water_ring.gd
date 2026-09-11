extends MeshInstance3D
## The expanding foam-ring accent of a splash: scales out, fades, frees itself — fx_oneshot's
## contract for a mesh instead of particles. The material is local to the scene, so each ring
## drives its own `progress` without stomping its siblings'.

const LIFE := 0.5                             ## seconds — matches the droplet burst
const START_SCALE := 0.4
const END_SCALE := 1.8

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta / LIFE
	if _t >= 1.0:
		queue_free()
		return
	scale = Vector3.ONE * lerpf(START_SCALE, END_SCALE, _t) * scale_factor()
	var mat := material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("progress", _t)


## The spawner sets our metadata scale once; everything else derives from _t.
func scale_factor() -> float:
	return float(get_meta("splash_scale", 1.0))

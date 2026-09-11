extends GPUParticles3D
## One-shot particle burst that frees itself when finished. Attach to any one_shot GPUParticles3D
## VFX (hit sparks, etc.) so spawned effects clean up automatically.

func _ready() -> void:
	emitting = true
	finished.connect(queue_free)

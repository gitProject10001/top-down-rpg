extends Node
## THE TOON PROOF'S VIEWPORT: TAA smears a one-pixel ink line under an orbiting camera, so the
## stylized scene turns it off for its own viewport — `Viewport.use_taa`, the same switch
## project.godot sets globally — and keeps MSAA 2× for the hull edges. A child Node with a
## script, the RoomVisibility idiom, so the saved scene carries it into --render-only, the
## bench and the audit.

func _ready() -> void:
	get_viewport().use_taa = false

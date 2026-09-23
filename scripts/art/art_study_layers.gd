@tool
class_name ArtStudyLayers
extends Node3D
## Lightweight authoring hook. The scene owns generation; this node owns durable
## settings and emits a request without erasing local edits or generated children.
const Profile = preload("res://scripts/art/art_study_profile.gd")
signal regeneration_requested(profile: Profile)
signal preview_quality_changed

@export var profile: Profile = preload("res://assets/art/default_art_study_profile.tres")
@export var preview_enabled: bool = true
@export_enum("Lavoro", "Completa") var preview_quality := 0:
	set(value):
		preview_quality=value
		if is_inside_tree() and Engine.is_editor_hint(): preview_quality_changed.emit()
@export_tool_button("Regenerate art preview", "Reload") var regenerate_action: Callable = regenerate

func regenerate() -> void:
	if profile == null:
		push_warning("ArtStudyLayers needs an ArtStudyProfile before regenerating.")
		return
	profile.ensure_edit_ids()
	regeneration_requested.emit(profile)

## Target paths are stored relative to the authoring root, not generated children.
func surface_path_for(surface: Node) -> NodePath:
	var authoring_root := get_parent()
	return authoring_root.get_path_to(surface) if authoring_root != null else NodePath()

func resolve_surface(path: NodePath) -> Node3D:
	var authoring_root := get_parent()
	return authoring_root.get_node_or_null(path) as Node3D if authoring_root != null else null

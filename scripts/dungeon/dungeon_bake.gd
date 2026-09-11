@tool # the paint must come back when the EDITOR opens the scene, and when the game loads it.
extends Node3D
## THE ROOT OF A BAKED DUNGEON (attached by Dungeon Forge's Bake to scene). Exists because a
## baked scene cannot SERIALIZE its paint: Kit.dress() writes material overrides and instance
## uniforms onto meshes INSIDE the instanced kit wrappers, and Godot discards changes to an
## instance's internals at save. Owning those internals instead duplicates every node on the
## next load (the name-collision warning wall) — so the paint is treated as what it is,
## DERIVED data. The bake records each painted mesh's dress values in one metadata dictionary
## on this root (an owned node's metadata serializes fine) and this script re-applies them on
## every load, plus the two meta contracts dress enforces beside paint (kit.gd:_dress_walk):
## a flame casts no shadow, a theme_light takes the theme's colour/energy/range.
##
## Lives in scripts/dungeon rather than the addon, so a baked scene loads with the plugin
## disabled — the same argument every other runtime-facing piece of the Forge makes.

@export var theme: DungeonTheme


func _ready() -> void:
	repaint()


func repaint() -> void:
	if theme == null or theme.material == null:
		return
	var paint: Dictionary = get_meta("forge_paint", {})
	for path: NodePath in paint:
		# GeometryInstance3D: the record covers MultiMeshes (debris) as well as meshes.
		var mi := get_node_or_null(path) as GeometryInstance3D
		if mi == null:
			continue
		# ORDER MATTERS, same as the dress walk: instance uniforms are a no-op on a mesh with
		# no override, so the material hangs first.
		mi.material_override = theme.material
		var vals: Array = paint[path]
		if vals.size() == 3 and vals[0] != null:
			mi.set_instance_shader_parameter("piece_params", vals[0])
			mi.set_instance_shader_parameter("piece_base", vals[1])
			mi.set_instance_shader_parameter("piece_tint", vals[2])
	_metas(self)


## kit.gd:_dress_walk's two meta branches, re-run: they also write onto instance internals
## (cast_shadow on flames, light values on sconces) and are lost on load for the same reason
## the paint is. The metas themselves are authored IN the kit scenes, so they reload intact.
func _metas(n: Node) -> void:
	if n is GeometryInstance3D and n.has_meta("torch_flame"):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif n is Light3D and n.has_meta(Kit.THEME_LIGHT) and theme != null:
		var l := n as Light3D
		l.light_color = theme.light_color
		l.light_energy = theme.light_energy
		if l is OmniLight3D:
			(l as OmniLight3D).omni_range = theme.light_range
			(l as OmniLight3D).omni_attenuation = theme.light_attenuation
		elif l is SpotLight3D:
			(l as SpotLight3D).spot_range = theme.light_range
			(l as SpotLight3D).spot_attenuation = theme.light_attenuation
	for c in n.get_children():
		_metas(c)

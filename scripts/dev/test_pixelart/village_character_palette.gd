extends Node
## Replace only the scene-local render mesh; player3's skeleton, states and animations stay.
##
## BOTH FIGHTERS NOW. The sparring partner (scenes/enemy_duelist.tscn) is an inherited copy of the
## player scene, so it arrives wearing the same untextured mannequin — and in a fight whose whole
## content is reading the other person's guard, two identical bodies is a fight you cannot follow.
## It gets the same warden mesh through the same path, a colder palette, and no hero beam. Telling
## them apart is a matter of colour, not of being a different character.

## Surface label -> colour, first match wins, "" is the fallback. Read off the warden's own
## material names rather than its surface order, so a re-export that reorders surfaces is harmless.
const HERO := {
	"Cloth": Color(.43, .20, .13), "Leather": Color(.25, .17, .11),
	"Steel": Color(.48, .49, .47), "Skin": Color(.61, .41, .28),
	"Dark": Color(.08, .065, .05), "Trim": Color(.51, .38, .22),
	"": Color(.33, .35, .35),
}
## The rival: the warm browns go cold and the trim loses its gold. Same silhouette, same armour,
## read at a glance as the other side of the fight.
const RIVAL := {
	"Cloth": Color(.20, .23, .31), "Leather": Color(.15, .15, .18),
	"Steel": Color(.38, .40, .45), "Skin": Color(.50, .38, .30),
	"Dark": Color(.05, .05, .07), "Trim": Color(.30, .32, .38),
	"": Color(.26, .28, .32),
}


func _ready() -> void:
	apply.call_deferred()


func apply() -> void:
	_skin(get_parent().get_node_or_null("Player"), HERO, true)
	_skin(get_parent().get_node_or_null("Duelist"), RIVAL, false)


func _skin(who: Node, palette: Dictionary, hero: bool) -> void:
	if not who or who.has_meta("hearth_warden_applied"): return
	var old_lamp: Node = who.get_node("HeroLight")
	old_lamp.visible = false
	old_lamp.set_process(false)
	old_lamp.set_process_unhandled_input(false)
	var skeleton: Skeleton3D = who.get_node("Visuals/Model/Armature/GeneralSkeleton")
	var body: MeshInstance3D = skeleton.get_node("Mannequin")
	var imported: Node = load("res://assets/models/camp/hearth_warden.glb").instantiate()
	var source: MeshInstance3D
	for candidate in imported.find_children("*","MeshInstance3D",true,false):
		if candidate.skin: source = candidate; break
	assert(source != null,"The new player mesh must retain skin binding")
	for i in source.skin.get_bind_count():
		var bone: StringName = source.skin.get_bind_name(i)
		assert(bone==&"" or skeleton.find_bone(bone)>=0,"Unknown warden bone: "+String(bone))
	body.mesh = source.mesh
	body.skin = source.skin
	body.transform = source.transform
	body.skeleton = NodePath("..")
	var skin: Node = who.get_node("ToonSkin")
	skin._mats.clear()
	skin._tints.clear()
	for i in body.mesh.get_surface_count():
		var material: Material = body.mesh.surface_get_material(i)
		var color: Color = _color(material.resource_name, palette)
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/pixelart/hearth_hero_material.gdshader")
		m.set_shader_parameter("albedo_color",color)
		m.set_shader_parameter("mail",1.0 if "Mail" in material.resource_name else 0.0)
		body.set_surface_override_material(i,m)
		skin._mats.append(m)
		skin._tints.append(color)
	imported.free()
	if hero:                     # the hero's own key light travels with the hero, and only the hero
		var beam := SpotLight3D.new()
		beam.name = "VillageBeam"
		beam.set_script(load("res://scripts/dev/test_pixelart/village_beam.gd"))
		who.get_node("Visuals").add_child(beam)
	who.set_meta("hearth_warden_applied",true)


func _color(label: String, palette: Dictionary) -> Color:
	for key in palette:
		if key != "" and key in label: return palette[key]
	return palette[""]

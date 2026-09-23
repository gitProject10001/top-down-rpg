extends "res://addons/world_editor/exploration_circuit.gd"
## Scene composition for the first Borgo/ford/tower loop. Progress resets on reload.
@export var combat_enabled:=true
var encounter: Node3D
var world_view: Node
var ui: CanvasLayer
var status: Label
var _started_encounter:=false
const OBJECTIVES: Array[String]=[
 "Prova esplorazione · raggiungi l'uscita ovest del borgo",
 "1/3 · Segui il sentiero e attraversa il guado",
 "2/3 · Raggiungi la torre e libera la radura",
 "3/3 · Ripercorri il sentiero, attraversa il guado e rientra al borgo",
 "Circuito completato"]
func setup(view: Node, hero: CharacterBody3D, enable_combat: bool) -> void:
 world_view=view; combat_enabled=enable_combat
 configure(hero); gate=_gate
 ui=CanvasLayer.new(); ui.layer=12; get_window().add_child.call_deferred(ui)
 status=Label.new(); status.position=Vector2(20,168); status.mouse_filter=Control.MOUSE_FILTER_IGNORE
 status.add_theme_font_size_override("font_size",17)
 status.add_theme_color_override("font_color",Color(1,.88,.60)); status.add_theme_color_override("font_shadow_color",Color(.07,.06,.04))
 status.add_theme_constant_override("shadow_offset_x",1); status.add_theme_constant_override("shadow_offset_y",1)
 ui.add_child(status)
func _gate(index: int) -> bool:
 if index!=2 or not combat_enabled: return true
 return is_instance_valid(encounter) and not encounter._resetting and encounter.fighters.size()==2 and encounter.living_count()==0
func _process(_delta: float) -> void:
 if not is_instance_valid(player) or not is_instance_valid(status): return
 if step==2 and combat_enabled and not _started_encounter and player.global_position.distance_to(get_node("Torre").global_position)<18:
  _started_encounter=true
  encounter=preload("res://scripts/combat/integrated_encounter.gd").new()
  encounter.name="TowerEncounter"; encounter.enemy_count=2; encounter.hud_enabled=false
  encounter.arena_center=get_node("Torre").global_position
  world_view.add_child(encounter); encounter.configure(world_view,player)
 var cycle:=world_view.get_node_or_null("DayCycle")
 status.visible=not (cycle and is_instance_valid(cycle.panel) and cycle.panel.visible)
 status.text=OBJECTIVES[mini(step,OBJECTIVES.size()-1)]
 if step==2 and not combat_enabled: status.text="2/3 · Raggiungi la radura della torre (prova percorso)"
 if step==2 and is_instance_valid(encounter) and not encounter._resetting:
  status.text+=" · Predoni: %d"%encounter.living_count()
 if step==checkpoint_paths.size(): status.text+=" · %.0f m / %.0f s"%[travelled,elapsed]
 if not player.health.is_alive(): status.text="Sei caduto · R riprende l'incontro alla torre"
func retry_if_active() -> bool:
 if step==2 and is_instance_valid(encounter):
  encounter.call_deferred("reset_encounter",true); return true
 return false
func _exit_tree() -> void:
 if is_instance_valid(ui): ui.queue_free()

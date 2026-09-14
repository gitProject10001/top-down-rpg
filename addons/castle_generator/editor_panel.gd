@tool
extends VBoxContainer
signal create_requested(plan: Dictionary)
signal regenerate_requested(plan: Dictionary)
signal lock_requested()
signal reset_requested()
signal element_selected(id: String)
var elements: ItemList
var element_info: Label
var lock_button: Button
var reset_button: Button
var _element_key := ""

const Request=preload("res://addons/castle_generator/request.gd")
const Planner=preload("res://addons/castle_generator/planner.gd")
var seed_input: SpinBox
var open_input: SpinBox
var width_input: SpinBox
var depth_input: SpinBox
var preview: Control
var info: Label
var create_button: Button
var current_plan: Dictionary={}
func field(title: String,low: float,high: float,value: float,step_value: float) -> SpinBox:
 var label := Label.new(); label.text=title; add_child(label)
 var spin := SpinBox.new(); spin.min_value=low; spin.max_value=high; spin.step=step_value; spin.value=value; add_child(spin)
 spin.value_changed.connect(func(_v): refresh())
 return spin
func _ready() -> void:
 seed_input=field("Seed",0,2147483647,17,1)
 width_input=field("Distanza torri X (m)",26,27,26.5,0.1)
 depth_input=field("Distanza torri Z (m)",26,27,26.5,0.1)
 open_input=field("Corte scoperta minima (%)",0,100,65,1)
 var next := Button.new(); next.text="Prova seed successivo"; next.pressed.connect(func(): seed_input.value=0 if seed_input.value>=seed_input.max_value else seed_input.value+1); add_child(next)
 preview=preload("res://addons/castle_generator/plan_preview.gd").new(); add_child(preview)
 info=Label.new(); info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(info)
 var legend := Label.new(); legend.text="Oro: mastio · azzurro: servizi · giallo: ingresso\nFamiglia iniziale: corte singola, quattro torri."; legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(legend)
 create_button=Button.new(); create_button.text="Crea come nuovo castello"; create_button.pressed.connect(func():
  if not current_plan.is_empty(): create_requested.emit(current_plan.duplicate(true)))
 add_child(create_button)
 var regenerate := Button.new(); regenerate.text="Anteprima rigenerazione del selezionato"
 regenerate.pressed.connect(func():
  if not current_plan.is_empty(): regenerate_requested.emit(current_plan.duplicate(true)))
 add_child(regenerate)
 var pages := TabContainer.new(); add_child(pages)
 var proposal := VBoxContainer.new(); proposal.name="Proposta"; pages.add_child(proposal)
 for child in get_children():
  if child!=pages: child.reparent(proposal)
 var protection := VBoxContainer.new(); protection.name="Elementi"; pages.add_child(protection)
 elements=ItemList.new(); elements.custom_minimum_size.y=190; protection.add_child(elements)
 elements.item_selected.connect(func(index): element_selected.emit(elements.get_item_metadata(index)))
 element_info=Label.new(); element_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; protection.add_child(element_info)
 lock_button=Button.new(); lock_button.text="Blocca posizione"; lock_button.pressed.connect(func(): lock_requested.emit()); protection.add_child(lock_button)
 reset_button=Button.new(); reset_button.text="Rendi posizione automatica"; reset_button.pressed.connect(func(): reset_requested.emit()); protection.add_child(reset_button)
 var hint := Label.new(); hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 hint.text="Rendere automatica una posizione rimuove anche il blocco. L'elemento resta fermo fino alla prossima rigenerazione. Porte, dimensioni e dettagli rimangono tuoi."
 protection.add_child(hint)
 update_elements(null,"")
 refresh()
func refresh() -> void:
 if not is_instance_valid(create_button): return
 var request=Request.new(); request.seed_value=int(seed_input.value)
 request.minimum_span=Vector2(width_input.value,depth_input.value); request.maximum_span=request.minimum_span
 request.minimum_open_fraction=open_input.value/100.0
 var result=Planner.generate(request)
 current_plan=result.get("plan",{})
 if not current_plan.is_empty(): current_plan["minimum_open_fraction"]=request.minimum_open_fraction
 preview.plan=current_plan; preview.queue_redraw()
 create_button.disabled=current_plan.is_empty()
 info.text="\n".join(result.errors) if current_plan.is_empty() else "Piano valido · seed %d. La creazione aggiunge un nuovo gruppo editabile."%request.seed_value
 info.modulate=Color("ff9e89") if current_plan.is_empty() else Color.WHITE

func update_elements(group: Node3D, selected_id: String) -> void:
 if not is_instance_valid(elements): return
 var records: Array=[]
 if is_instance_valid(group) and group.has_meta("composition_plan"):
  records=preload("res://addons/castle_generator/regeneration.gd").describe(group)
 var key := str(records)+selected_id
 if key==_element_key: return
 _element_key=key; elements.clear(); lock_button.disabled=true; reset_button.disabled=true
 element_info.text="Seleziona un castello generato e un corpo interno."
 for record in records:
  var index := elements.add_item(record.name+" · "+record.status)
  elements.set_item_metadata(index,record.id)
  if record.id==selected_id:
   elements.select(index)
   element_info.text=record.name+"\n"+record.status
   lock_button.disabled=not record.supported
   lock_button.text="Sblocca posizione" if record.locked else "Blocca posizione"
   reset_button.disabled=not record.supported or not (record.manual or record.locked)

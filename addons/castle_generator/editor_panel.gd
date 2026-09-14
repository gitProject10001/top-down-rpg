@tool
extends VBoxContainer
signal create_requested(plan: Dictionary)
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
 refresh()
func refresh() -> void:
 if not is_instance_valid(create_button): return
 var request=Request.new(); request.seed_value=int(seed_input.value)
 request.minimum_span=Vector2(width_input.value,depth_input.value); request.maximum_span=request.minimum_span
 request.minimum_open_fraction=open_input.value/100.0
 var result=Planner.generate(request)
 current_plan=result.get("plan",{})
 preview.plan=current_plan; preview.queue_redraw()
 create_button.disabled=current_plan.is_empty()
 info.text="\n".join(result.errors) if current_plan.is_empty() else "Piano valido · seed %d. La creazione aggiunge un nuovo gruppo editabile."%request.seed_value
 info.modulate=Color("ff9e89") if current_plan.is_empty() else Color.WHITE

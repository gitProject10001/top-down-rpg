extends Node3D
## Small readable health pips and an on-ground windup cue, using the real state.
var fighter: Player
var pips: Label3D
var tell: MeshInstance3D

func _ready() -> void:
	fighter=get_parent() as Player
	if fighter==null: queue_free(); return
	pips=Label3D.new()
	pips.name="HealthPips"
	pips.position.y=1.45
	pips.font_size=40
	pips.pixel_size=.006
	pips.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	pips.modulate=Color(.91,.54,.38)
	pips.outline_modulate=Color(.12,.08,.06)
	pips.outline_size=6
	add_child(pips)
	tell=MeshInstance3D.new()
	tell.name="AttackTell"
	var ring:=TorusMesh.new()
	ring.inner_radius=.49
	ring.outer_radius=.54
	ring.rings=24
	ring.ring_segments=6
	tell.mesh=ring
	tell.position.y=-.83
	tell.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tell.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color(.94,.42,.08)
	tell.material_override=mat
	add_child(tell)
	fighter.health.changed.connect(update_health)
	update_health(fighter.health.hp,fighter.health.max_hp)

func update_health(hp: int, maximum: int) -> void:
	pips.text="●".repeat(maxi(hp,0))+"·".repeat(maxi(maximum-hp,0))
	pips.visible=hp>0

func _process(_delta: float) -> void:
	if not is_instance_valid(fighter): return
	tell.visible=fighter.health.is_alive() and fighter.charging_dir()!=SwingDir.NONE
	if tell.visible:
		var pulse:=.96+.06*sin(Time.get_ticks_msec()*.017)
		tell.scale=Vector3(pulse,1,pulse)

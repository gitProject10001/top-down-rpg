extends RefCounted
static var _sounds: Dictionary = {}

static func contact_sound(parried: bool) -> AudioStreamWAV:
	if _sounds.has(parried): return _sounds[parried]
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var bytes := PackedByteArray()
	var duration := .17 if parried else .11
	var frequency := 1850.0 if parried else 1100.0
	for i in int(duration*sound.mix_rate):
		var t := float(i)/sound.mix_rate
		var envelope := minf(t/.0015,1.0)*exp(-t*(32.0 if parried else 48.0))
		var tone := sin(TAU*frequency*t)*.45+sin(TAU*frequency*1.47*t)*.3+sin(TAU*frequency*2.31*t)*.15
		var value := int(tone*envelope*21000.0)
		bytes.append(value & 255)
		bytes.append((value >> 8) & 255)
	sound.data = bytes
	_sounds[parried] = sound
	return sound
## Small contact-local flecks, not a screen-sized flash or a damage effect.
static func spawn(parent: Node, point: Vector3, parried: bool) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = point
	var audio := AudioStreamPlayer3D.new()
	audio.stream = contact_sound(parried)
	audio.volume_db = -15.0
	audio.max_distance = 12.0
	audio.unit_size = 3.0
	root.add_child(audio)
	audio.play()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1,.89,.55) if parried else Color(.8,.85,.9)
	for i in (7 if parried else 4):
		var fleck := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.014,.014,.045)
		fleck.mesh = mesh
		fleck.material_override = material
		root.add_child(fleck)
		var direction := Vector3(cos(i*2.4),.25+sin(i*1.7)*.6,sin(i*2.4)).normalized()
		fleck.basis = Basis.looking_at(direction)
		var tween := root.create_tween().set_parallel(true)
		tween.tween_property(fleck,"position",direction*(.20 if parried else .12),.14)
		tween.tween_property(fleck,"scale",Vector3.ONE*.01,.16)
	root.get_tree().create_timer(.19).timeout.connect(root.queue_free)

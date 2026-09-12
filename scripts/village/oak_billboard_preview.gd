extends MeshInstance3D
## Preview-only yaw billboard. Leaves trunk and original assets untouched.
const INCLINED := Basis(Vector3(1.0042056,0,0),Vector3(0,0.67194456,0.7462701),Vector3(0,-0.7462702,0.6719446))

func _ready() -> void:
	process_priority = 100
	_process(0.0)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var back := camera.global_basis.z
	global_basis = Basis(Vector3.UP,atan2(back.x,back.z)+PI)*INCLINED

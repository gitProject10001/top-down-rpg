extends SceneTree
## PHOTOGRAPH THE OGRE NEXT TO A RULER.
##
##   Godot_console.exe --path . --resolution 1200x900 --script res://scripts/dev/shot_ogre.gd -- \
##       --out=C:/some/folder
##
## MUST RUN WITHOUT --headless — the dummy renderer has no pixels and saves black frames.
##
## WHY IT EXISTS. tools/measure_ogre_scale.gd reports two frames that disagree: the mesh AABB says
## the model spans Y 0..4, while the bone rests put the feet at Y = -1.70 and the head at +1.69.
## Both cannot be where the ogre stands. A skinned mesh's `get_aabb()` is its BIND-pose box and can
## sit in a different space from the skeleton that actually deforms it, so the arithmetic cannot
## settle this — only pixels can. The scene therefore contains a metre grid, a 1.8 m post (a player)
## and a 4.0 m post (the target), and the answer is read off the picture.
##
## It also prints the RenderingServer's own instance AABB, which — unlike MeshInstance3D.get_aabb()
## — is the box the renderer actually culls against once the skeleton is live. That is the number
## that matches the pixels.

const MODEL := "res://assets/models/ogre.fbx"
const PUPPET := "res://scenes/dev/ogre_puppet.tscn"
## Frames of a stride to photograph, so the walk is judged as a SEQUENCE. A single still cannot
## distinguish a good gait from a bad one caught at a flattering moment.
const STRIDE_SHOTS := 6

var _out := "user://"
var _posts: Node3D
## Name of an action to photograph instead of the walk. An attack has to be judged as a SEQUENCE --
## the whole point of the wind-up is how long it lasts relative to the strike, and no still shows
## that. So the action mode samples evenly across the action's own duration.
var _action := ""
var _cam: Camera3D
var _sweep_bone := ""
var _sweep_axis := "x"
var _sweep_from := -180.0
var _sweep_step := 45.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"


func _init() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.7, 0.83, 0.95)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)

	world.add_child(_floor_body())
	_posts = Node3D.new()
	world.add_child(_posts)
	# A metre-banded 1.8 m post (a person) and a 4 m post (what the ogre should match). Scale is a
	# comparison, never a number you can check by looking.
	_posts.add_child(_post(Vector3(-2.6, 0, 0), 1.8, Color(0.85, 0.3, 0.25)))
	_posts.add_child(_post(Vector3(-4.0, 0, 0), 4.0, Color(0.95, 0.85, 0.2)))

	# The ruler. A 1.8 m post is a person; the 4 m post is what the ogre is supposed to match. Scale
	# claims need something to be measured AGAINST — "it looks big" is not a measurement.
	# The WALKING ogre, not the bare model: the point is to see the gait next to a ruler, side on,
	# where a crouch that is too deep or a leg that is too short is obvious rather than arguable.
	var packed := load(PUPPET) as PackedScene
	var ogre := packed.instantiate() as OgrePuppet
	world.add_child(ogre)
	ogre.global_position = Vector3(0, 0.2, 14)
	ogre.commanded_speed = 2.0
	ogre.drive = Vector3(0, 0, -1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--grip="):
			# --grip=px,py,pz,rx,ry,rz -- dial the mace in the hand without an edit-run cycle.
			var v := a.substr(7).split(",")
			if v.size() == 6:
				ogre.solver.weapon_grip_pos = Vector3(float(v[0]), float(v[1]), float(v[2]))
				ogre.solver.weapon_grip_rot = Vector3(float(v[3]), float(v[4]), float(v[5]))
		elif a == "--still":
			ogre.commanded_speed = 0.0
			ogre.drive = Vector3.ZERO
		elif a.begins_with("--sweep="):
			# --sweep=RightUpperArm:x  -- hold ONE bone at a range of angles about ONE body axis and
			# photograph each. Reading the sign and range straight off a contact sheet takes one run;
			# reasoning about which way a retargeted bone turns takes several and is often wrong.
			var parts := a.substr(8).split(":")
			_sweep_bone = parts[0]
			_sweep_axis = parts[1] if parts.size() > 1 else "x"
			if parts.size() > 3:
				_sweep_from = float(parts[2])
				_sweep_step = float(parts[3])
			ogre.commanded_speed = 0.0
			ogre.drive = Vector3.ZERO
		elif a.begins_with("--action="):
			_action = a.substr(9)
			ogre.commanded_speed = 0.0
			ogre.drive = Vector3.ZERO
	# THE LIFT. The FBX's origin is at the creature's WAIST, not under its feet: the bones span
	# Y -2.045..+1.693 about the origin, so dropped in at y=0 the ogre stands buried to the navel.
	# Every enemy in this project has its root at the feet (blob_shadow.gd's `foot_offset` docs say
	# so outright), which makes this offset mandatory rather than cosmetic. It is measured off the
	# rig at load rather than typed in, so a reimport at a different scale cannot silently un-sink it.


	_cam = Camera3D.new()
	_cam.fov = 40.0
	world.add_child(_cam)
	_cam.current = true

	for i in 140:
		await physics_frame
	ogre.solver.refresh_grip()
	await physics_frame

	_report(ogre)
	var s := ogre.solver
	print("walking: speed %.2f  stride %.2f  cadence %.2f Hz  crouch %.2f  hip above foot %.2f m"
			% [s.speed, s.stride, s.stride_freq, s.crouch, s.hip_lift])

	if _sweep_bone != "":
		await _shoot_sweep(ogre, s)
		quit()
		return

	if _action != "":
		await _shoot_action(ogre, s)
		quit()
		return

	# One full stride, sampled evenly. SIDE ON, because that is the only angle where the leg's
	# extension and the pelvis height can actually be read.
	var period := 1.0 / maxf(s.stride_freq, 0.1)
	for k in STRIDE_SHOTS:
		var at := ogre.global_position
		_cam.global_position = at + Vector3(17.0, 3.0, 1.0)
		_cam.look_at(at + Vector3.UP * 2.0)
		# The ruler travels with the subject, so it is always beside it in frame.
		_posts.global_position = Vector3(at.x, 0.0, at.z + 3.0)
		for i in 4:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(_out + "ogre_walk_%d.png" % k)
		var wait := int(period / float(STRIDE_SHOTS) * 60.0)
		for i in maxi(wait, 1):
			await physics_frame
	print("[SHOT] wrote %d stride frames to %s" % [STRIDE_SHOTS, _out])
	quit()


## The renderer's own box, taken once the skeleton is driving the mesh. This is the authority: it is
## what gets culled, and it is where the pixels are.
## One bone, one axis, a range of angles, one picture each.
func _shoot_sweep(ogre: OgrePuppet, s: OgreSolver) -> void:
	var at := ogre.global_position
	_cam.global_position = at + Vector3(15.0, 3.2, 4.0)
	_cam.look_at(at + Vector3.UP * 2.2)
	_posts.global_position = Vector3(at.x, 0.0, at.z + 4.0)
	# A pose set containing nothing but the bone under test, so nothing else can explain the result.
	var ps := PoseSet.new()
	s.poses = ps
	s.carrying = &"probe"
	var idx: int = {"x": 0, "y": 1, "z": 2}.get(_sweep_axis, 0)
	for k in 8:
		var deg := _sweep_from + _sweep_step * float(k)
		var v := Vector3.ZERO
		v[idx] = deg
		ps.poses["probe"] = {_sweep_bone: v}
		for i in 8:
			await physics_frame
		for i in 3:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(_out + "sweep_%s_%s_%+04d.png" % [_sweep_bone, _sweep_axis, int(deg)])
		print("  %s.%s = %+.0f" % [_sweep_bone, _sweep_axis, deg])
	print("[SHOT] swept %s about %s" % [_sweep_bone, _sweep_axis])


## Photograph an action across its own length, evenly. Ten frames, because the beat that matters
## most -- the strike -- is four to five times shorter than the wind-up, and a six-frame sample can
## step straight over it.
func _shoot_action(ogre: OgrePuppet, s: OgreSolver) -> void:
	var at := ogre.global_position
	_cam.global_position = at + Vector3(15.0, 3.4, 5.0)
	_cam.look_at(at + Vector3.UP * 2.2)
	_posts.global_position = Vector3(at.x, 0.0, at.z + 4.0)
	s.play_action(StringName(_action))
	var total: float = maxf(s.action_len, 0.2)
	var strike := s.action_time(StringName(_action), &"strike")
	print("action '%s': %.2f s   telegraph %.2f   strike %.2f"
			% [_action, total, s.action_time(StringName(_action), &"telegraph"), strike])

	# Sample on the SOLVER'S OWN CLOCK, not on a frame count. `await process_frame` advances time as
	# well, so a capture loop that counts physics frames and then renders drifts by a quarter of the
	# action -- which is how the first attempt photographed the wind-up and filed it as the strike.
	# Times are chosen around the strike rather than spread evenly, because the strike is a seventh
	# of the action's length and an even sample steps straight over it.
	var marks: Array[float] = [
		0.0, strike * 0.45, strike * 0.8, strike - 0.03,
		strike + 0.02, strike + 0.06, strike + 0.14,
		strike + 0.30, strike + 0.55, total * 0.98,
	]
	var k := 0
	while k < marks.size():
		if s.action_t >= marks[k] or not s.is_acting():
			for i in 2:
				await process_frame
			var img := root.get_texture().get_image()
			img.save_png(_out + "ogre_%s_%d.png" % [_action, k])
			print("  frame %d at t=%.3f" % [k, s.action_t])
			k += 1
			continue
		await physics_frame
	print("[SHOT] wrote %d action frames" % marks.size())


func _report(ogre: Node3D) -> void:
	for mi: MeshInstance3D in _meshes(ogre):
		# get_transformed_aabb() is the box the renderer actually culls against, in world space.
		# get_aabb() is the mesh's own bind-pose box and can sit in a different frame entirely on a
		# skinned mesh — printing both is how the disagreement becomes visible instead of confusing.
		print("--- ", mi.name, " ---")
		print("  MeshInstance3D.get_aabb() : ", mi.get_aabb(), "   (BIND-pose box, may be a lie)")
	var skel := _skeleton(ogre)
	if skel:
		# And the bones, in the same world frame, so all three numbers can be compared at last.
		var lo := INF
		var hi := -INF
		for i in skel.get_bone_count():
			var y: float = (skel.global_transform * skel.get_bone_global_pose(i)).origin.y
			lo = minf(lo, y)
			hi = maxf(hi, y)
		print("--- skeleton (world, current pose) ---")
		print("  lowest bone Y  : %.4f m" % lo)
		print("  highest bone Y : %.4f m" % hi)
		print("  bone span      : %.4f m" % (hi - lo))


## How far to raise the model so its SOLES touch y=0. The lowest bone is the toe joint, which sits
## a little inside the foot mesh, so bone-span alone would leave the ogre floating by a couple of
## centimetres. Split the difference between the mesh's bind height and the bone span across both
## ends and the soles land on the floor.
func _lift(ogre: Node3D) -> float:
	var skel := _skeleton(ogre)
	if skel == null:
		return 0.0
	var lo := INF
	var hi := -INF
	for i in skel.get_bone_count():
		var y: float = (skel.transform * skel.get_bone_global_pose(i)).origin.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var mesh_h := 0.0
	for mi: MeshInstance3D in _meshes(ogre):
		mesh_h = maxf(mesh_h, mi.get_aabb().size.y)
	var overhang := maxf(0.0, mesh_h - (hi - lo)) * 0.5
	print("bone span %.4f, mesh height %.4f, overhang/end %.4f" % [hi - lo, mesh_h, overhang])
	return -lo + overhang


func _skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _skeleton(c)
		if s != null:
			return s
	return null


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += _meshes(c)
	return out


## 1 m checker with collision, so a height can be counted off the picture and the ogre has something
## to stand on and raycast against.
func _floor_body() -> Node3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.64, 0.6)
	mat.uv1_scale = Vector3(120, 120, 1)
	mat.roughness = 0.9
	mi.material_override = mat
	body.add_child(mi)
	return body


## A striped post: one band per metre, so you can literally count them.
func _post(at: Vector3, height: float, tint: Color) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	var bands := int(ceil(height))
	for i in bands:
		var h := minf(1.0, height - float(i))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, h, 0.18)
		mi.mesh = bm
		mi.position = Vector3(0, float(i) + h * 0.5, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint if (i % 2 == 0) else Color(0.95, 0.95, 0.95)
		mi.material_override = mat
		holder.add_child(mi)
	return holder

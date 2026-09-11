extends SceneTree
## Why is the floor dark, why is the wall bright, and why does moving the camera change the
## exposure? Four questions, answered by isolating one variable at a time on one fixed frame.
##
##   Godot_console.exe --path . --script res://scripts/dev/light_diag.gd
##
## MUST RUN WITHOUT --headless.

const ZONE := "res://scenes/world/zone_crypt.tscn"
const MAIN := "res://scenes/main.tscn"
const SEED := 42
const PITCH := 0.93
const SETTLE := 25

## Rects on the hero frame. WALL is the far wall's lower course; FLOOR is open floor in the middle
## of the room, clear of the portal and the altar.
const WALL := Rect2(0.30, 0.22, 0.40, 0.10)
const FLOOR := Rect2(0.34, 0.52, 0.32, 0.14)

var _world: Node3D
var _cam: Camera3D
var _zone: Node3D
var _env: Environment


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run()


func _run() -> void:
	await process_frame
	_world = Node3D.new()
	root.add_child(_world)

	var main := (load(MAIN) as PackedScene).instantiate()
	var src: Environment = null
	var sun_e := 1.0
	var sun_r := Vector3(-45, -130, 0)
	for n in _flatten(main):
		if n is WorldEnvironment and src == null:
			src = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			sun_e = (n as DirectionalLight3D).light_energy
			sun_r = (n as DirectionalLight3D).rotation_degrees
	var we := WorldEnvironment.new()
	_env = src.duplicate(true)
	we.environment = _env
	we.add_to_group("world_env")
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = sun_e
	sun.rotation_degrees = sun_r
	sun.shadow_enabled = true
	sun.add_to_group("sun")
	_world.add_child(sun)
	main.free()

	_zone = (load(ZONE) as PackedScene).instantiate() as Node3D
	_zone.set("dungeon_seed", SEED)
	_world.add_child(_zone)
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.current = true
	_cam.far = 400.0
	await process_frame
	var at: Vector3 = _zone.position + Vector3(0, 1.0, 0)

	# ---- 1. DOES MOVING THE CAMERA CHANGE THE EXPOSURE, and is it the depth fog?
	# The theme sets fog_begin 22 / fog_end 55 with a BLACK fog colour, and the game's camera orbits
	# at 19 m. A 20 x 12 room seen from 19 m has its far wall at ~28 m — already six metres into the
	# curtain. Pull back ten and most of the room is inside it. If that is what is happening, then
	# what looks like the lighting changing with distance is the room being progressively painted
	# black, and no amount of light tuning will fix it.
	# TRACK ONE PATCH OF WALL, not the whole frame. Averaging the frame conflates "the light
	# changed" with "the room got smaller in it" — at 40 m most of the picture is black void and the
	# mean collapses for reasons that have nothing to do with lighting. Unprojecting a fixed world
	# point and sampling around it follows the same stone all the way out.
	var wall_pt: Vector3 = _zone.position + Vector3(0.0, 2.0, -5.6)
	var floor_pt: Vector3 = _zone.position + Vector3(0.0, 0.06, -1.0)
	print("\n=== 1. does one patch of stone change brightness as the camera pulls back? ===")
	print("  dist   wall(fog on)  wall(fog off)   floor(fog on)  floor(fog off)")
	for d in [12.0, 19.0, 26.0, 33.0, 40.0]:
		_orbit(at, d)
		_env.fog_enabled = true
		await _settle()
		var wa := _at_point(wall_pt)
		var fa := _at_point(floor_pt)
		_env.fog_enabled = false
		await _settle()
		var wb := _at_point(wall_pt)
		var fb := _at_point(floor_pt)
		_env.fog_enabled = true
		print("  %4.0f m   %.4f        %.4f          %.4f         %.4f" % [d, wa, wb, fa, fb])

	# ---- 2. WALL VS FLOOR, and how much of the gap each suspect owns.
	# The albedo ratio is known from probe_crypt_paint: floors are authored at ~0.27 median COLOR_0
	# against the walls' ~0.38, so about 0.71 of the gap is deliberate. Anything beyond that is
	# lighting geometry or post.
	_orbit(at, 19.0)
	_env.fog_enabled = true
	await _settle()
	print("\n=== 2. wall vs floor, one variable at a time ===")
	await _pair("as shipped")

	var mat: ShaderMaterial = _stone()
	if mat != null:
		var w: float = mat.get_shader_parameter("wrap") if mat.get_shader_parameter("wrap") != null else 0.3
		mat.set_shader_parameter("wrap", 0.0)
		await _pair("wrap 0 (was %.2f)" % w)
		mat.set_shader_parameter("wrap", w)

	var ssao := _env.ssao_enabled
	_env.ssao_enabled = false
	await _pair("ssao off")
	_env.ssao_enabled = ssao

	var sd := _env.sdfgi_enabled
	_env.sdfgi_enabled = false
	await _pair("sdfgi off")
	_env.sdfgi_enabled = sd

	# The room's own lights, one class at a time, to see who is actually lighting what.
	var room := _room_at(_zone.position)
	if room != null:
		var fill: Light3D = null
		var others: Array[Light3D] = []
		for n in _flatten(room):
			if n is Light3D:
				if (n as Node3D).name == "RoomFill":
					fill = n as Light3D
				else:
					others.append(n as Light3D)
		if fill != null:
			var e := fill.light_energy
			fill.light_energy = 0.0
			await _pair("RoomFill off")
			fill.light_energy = e
			print("     (RoomFill: y=%.2f range=%.1f energy=%.1f)"
					% [(fill as Node3D).position.y, (fill as OmniLight3D).omni_range, e])
		var saved: Array[float] = []
		for l in others:
			saved.append(l.light_energy)
			l.light_energy = 0.0
		await _pair("candelabras off")
		for i in others.size():
			others[i].light_energy = saved[i]

	# ---- 3. WHY THE FLOOR IS DARK EVEN DIRECTLY UNDER A LIGHT: incidence angle.
	# A candelabra flame sits 1.55 m up and RoomDresser.MOUNT_INSET puts it 1-2 m off the wall. The
	# wall behind it is vertical and a metre away, so N.L there is near 1. The floor is horizontal,
	# so at any distance the same flame rakes across it.
	print("\n=== 3. incidence: what N.L a 1.55 m flame delivers ===")
	print("   dist along floor   N.L on floor   N.L on a wall 1.0 m away")
	for dd in [1.0, 2.0, 4.0, 6.0, 9.0]:
		var ndl_floor: float = 1.55 / sqrt(1.55 * 1.55 + dd * dd)
		print("   %5.1f m            %.3f          %.3f" % [dd, ndl_floor, 1.0 / sqrt(1.0 + 0.55 * 0.55)])
	# ---- 4. THE PLAYER. "Always in shadow, even outside the dungeon" is a claim about the character
	# material and the light reaching it, not about the crypt, so measure the body against the floor
	# it is standing on. If the body reads far below the floor beside it, the character is not being
	# lit; if it tracks the floor, then it is lit and the complaint is about contrast.
	print("\n=== 4. the player against the ground under them ===")
	var ps := load("res://scenes/player/player2.tscn") as PackedScene
	if ps == null:
		print("  player2.tscn did not load")
		quit(0)
		return
	# A CLEAN SUNLIT STAGE, not the crypt. The complaint is that the player is dark OUTSIDE the
	# dungeon too, so testing them under seven candelabras proves nothing either way. One
	# directional light at overworld energy, a neutral card, and no crypt lighting at all: if the
	# character still bands into darkness here, it is the character shader and nothing else.
	var host := _room_at(_zone.position)
	if host != null:
		for n in _flatten(host):
			if n is Light3D:
				(n as Light3D).light_energy = 0.0
	var card := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10.0, 10.0)
	card.mesh = plane
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.55, 0.55)
	grey.roughness = 1.0
	card.material_override = grey
	_world.add_child(card)
	card.global_position = _zone.position + Vector3(-7.0, 0.03, -2.0)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.0
	key.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	key.shadow_enabled = true
	_world.add_child(key)

	var p := ps.instantiate() as Node3D
	_world.add_child(p)
	var stand: Vector3 = _zone.position + Vector3(-7.0, 0.05, -2.0)
	# PINNED EVERY FRAME. The player is a CharacterBody3D running its own gravity, and the test card
	# is a bare MeshInstance3D with no collider — the first attempt at this shot found the player at
	# y = -1.22, having fallen straight through the stage and out of frame. Re-asserting the
	# position each frame is cheaper than giving the card a body and disabling half the player's
	# script tree, and it cannot drift.
	for i in SETTLE:
		p.global_position = stand
		# The torch would relight the very thing the sun is supposed to be the only source of.
		for n in _flatten(p):
			if n is Light3D:
				(n as Light3D).light_energy = 0.0
		await process_frame
	print("  player at %s, card at %s" % [p.global_position, card.global_position])
	_orbit(stand + Vector3(0, 1.0, 0), 4.5)
	for i in SETTLE:
		p.global_position = stand
		await process_frame
	var img := root.get_texture().get_image()
	_grid(img)
	img.save_png(OS.get_environment("DIAG_OUT") + "/player_sunlit.png")
	# Torch off, to separate "the torch is not lighting them" from "nothing is".
	for n in _flatten(p):
		if n is OmniLight3D:
			print("  torch: %s at %s energy %.2f mask %d shadows %s"
					% [(n as Node3D).name, (n as Node3D).position,
					(n as Light3D).light_energy, (n as Light3D).light_cull_mask,
					(n as Light3D).shadow_enabled])
	# WHAT THE CHARACTER'S ALBEDO ACTUALLY IS. The shader multiplies ALBEDO by COLOR_0 whenever
	# use_vertex_color is on, and its header assumes "meshes with no colour attribute get COLOR =
	# 1.0, so leaving this on costs characters nothing". That assumption is exactly the one that
	# already cost this project a day on the dungeon kit, where a .glb turned out to carry colour
	# attributes nobody knew about. Check it rather than believe it.
	for n in _flatten(p):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null \
				else PackedColorArray()
		var tex_note := "no texture"
		var m := mi.get_active_material(0)
		if m is ShaderMaterial:
			var t = (m as ShaderMaterial).get_shader_parameter("albedo_texture")
			var ac = (m as ShaderMaterial).get_shader_parameter("albedo_color")
			var uv = (m as ShaderMaterial).get_shader_parameter("use_vertex_color")
			tex_note = "tex=%s albedo_color=%s use_vertex_color=%s" % [
					"yes" if t != null else "no", ac, uv]
			if t is Texture2D:
				# THE NUMBER THAT DECIDES IT. If the character's own texture is dark, then no amount
				# of lighting work makes them read as lit — they are dark objects, correctly lit.
				var ti := (t as Texture2D).get_image()
				# get_pixel on a VRAM-compressed image reads nothing and returns pure black, which
				# is indistinguishable from a genuinely black texture — the first run of this probe
				# reported a mean of exactly 0.000 for a texture that is plainly not black.
				if ti.is_compressed():
					ti.decompress()
				var ts := 0.0
				var tn := 0
				for yy in range(0, ti.get_height(), 4):
					for xx in range(0, ti.get_width(), 4):
						var c := ti.get_pixel(xx, yy)
						if c.a > 0.5:
							ts += c.get_luminance()
							tn += 1
				tex_note += "  TEXTURE MEAN LUMINANCE %.3f (%dx%d)" % [
						ts / maxf(tn, 1), ti.get_width(), ti.get_height()]
		if cols.is_empty():
			print("  %-22s verts=%d  COLOR_0 absent   %s" % [mi.name, arr[0].size(), tex_note])
		else:
			var s := 0.0
			for c in cols:
				s += c.get_luminance()
			print("  %-22s verts=%d  COLOR_0 mean lum %.3f (first %s)   %s"
					% [mi.name, arr[0].size(), s / cols.size(), cols[0], tex_note])
	quit(0)


## An 8x6 luminance grid — the body sits in the middle columns, the floor fills the bottom rows.
func _grid(img: Image) -> void:
	for gy in 6:
		var row := "    "
		for gx in 8:
			row += "%6.3f" % _mean(img, Rect2(gx * 0.125, gy / 6.0, 0.125, 1.0 / 6.0))
		print(row)


## Luminance in a small screen rect centred on where a WORLD point lands. Returns -1 if the point
## is behind the camera or off screen, so a bad sample cannot masquerade as a dark one.
func _at_point(world: Vector3) -> float:
	if _cam.is_position_behind(world):
		return -1.0
	var s := _cam.unproject_position(world)
	var vp := Vector2(root.get_texture().get_width(), root.get_texture().get_height())
	var u := s / vp
	if u.x < 0.03 or u.x > 0.97 or u.y < 0.03 or u.y > 0.97:
		return -1.0
	return _mean(root.get_texture().get_image(), Rect2(u.x - 0.025, u.y - 0.02, 0.05, 0.04))


func _pair(label: String) -> void:
	await _settle()
	var img := root.get_texture().get_image()
	var w := _mean(img, WALL)
	var f := _mean(img, FLOOR)
	print("  %-22s wall %.4f   floor %.4f   floor/wall %.2f" % [label, w, f, f / maxf(w, 1e-5)])


func _stone() -> ShaderMaterial:
	for n in _flatten(_zone):
		if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial:
			return (n as MeshInstance3D).material_override as ShaderMaterial
	return null


func _room_at(p: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in _flatten(_zone):
		if n is DungeonRoom:
			var d: float = (n as Node3D).global_position.distance_to(p)
			if d < bd:
				bd = d
				best = n as Node3D
	return best


func _settle() -> void:
	for i in SETTLE:
		await process_frame


func _mean(img: Image, r: Rect2) -> float:
	var x0 := int(r.position.x * img.get_width())
	var y0 := int(r.position.y * img.get_height())
	var x1 := mini(int((r.position.x + r.size.x) * img.get_width()), img.get_width())
	var y1 := mini(int((r.position.y + r.size.y) * img.get_height()), img.get_height())
	var s := 0.0
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			s += img.get_pixel(x, y).get_luminance()
			n += 1
	return s / maxf(n, 1)


func _orbit(at: Vector3, dist: float) -> void:
	var off := Vector3(0.0, sin(PITCH), cos(PITCH)) * dist
	_cam.position = at + off
	_cam.look_at_from_position(at + off, at, Vector3.UP)
	_cam.fov = 50.0


func _flatten(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_flatten(c))
	return out

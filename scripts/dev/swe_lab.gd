extends Node3D
## THE SHALLOW-WATER BENCH: the shipping solver, on a bed you can choose, starting EMPTY, with
## every intermediate quantity it reasons about drawn as a picture and every term of one cell's
## update printed as a number.
##
##   Godot_v4.6.3-stable_win64_console.exe --path . res://scenes/dev/swe_lab.tscn
##
## WHY THIS EXISTS ALONGSIDE scenes/dev/water_lab.tscn. That one is the GAME's water: a generated
## map, a painted lake, a player who can wade into it. It answers "does the water feel right".
## It cannot answer "what is the solver doing", for three reasons that are all structural rather
## than fixable there:
##
##   1. The generated bed is whatever the noise gave it. You cannot ask a generated map for a
##      flat pan, a 3% V-channel, or three terraces and nothing else — and those are exactly the
##      cases that tell you whether a solver works.
##   2. Every pond starts FULL, because water at rest is this model's zero. A solver that fills a
##      basin and a solver that merely fails to drain one look identical from a full pond.
##   3. The state texture read raw is a dim purple haze. Depth, speed, Froude number and the
##      open/closed faces are the quantities the solver actually reasons about, and not one of
##      them is a channel.
##
## THE SOLVER HERE IS THE REAL ONE, driven through the real code path: the bed joins group
## "water_oracle", Water resolves it, and Ripples bakes its field and steps its own shader
## exactly as it does in the wilds. A bench with its own driver measures its own driver. What
## the bench adds is a pinned window, a pause, a single-step and an empty start — see
## scripts/ripple_field.gd, where those four are the only additions the game does not use.
##
## THREE SHIPPED DEFAULTS ARE WRONG FOR A BENCH, and the panel says so next to each one, because
## silently overriding a shipped value is how a bench comes to measure a solver nobody ships:
##
##   draw_max  0.55 -> 1.00   the solver floors eta at -H0 * draw_max, so under the shipped value
##                            an "empty" basin is 45% full on the very first step.
##   eta_keep  0.999 -> 1.000 relaxation toward eta = 0 is a sink ONLY above rest. Below it it is
##                            a distributed SOURCE: an empty 0.55 m basin refills itself at
##                            3.3 cm/s with no spring anywhere. Invisible in a game where ponds
##                            sit at rest; total on a bench that starts dry.
##   advect    off -> off     left alone, and named here so nobody assumes the bench turned it on.
##
## The mass readout is the instrument the source/sink question needs: sum(H) over wet cells times
## the texel area is a VOLUME in cubic metres, and "the source fills it, the sink empties it" is a
## claim about that number over time, not about a picture. It earned itself on the first run:
##
##   WHAT THE BENCH FOUND. A dry basin does not stay dry. Sixty cubic metres arrive in a 48 m
##   basin in five seconds with no spring, no drain and no impulse — because "empty" is encoded as
##   eta = -H0, and at the shoreline H0 falls to zero across one metre of the terrain field, so
##   the solver reads a dry beach as a metre-high wall of water leaning inward and collapses it.
##   Not a tuning problem and not an instability: see swe_lab_bed.gd's header for the diagnosis
##   and scripts/dev/probe_swe_lab.gd for the evidence. Start FULL (T) to see the solver in the
##   regime it is exact in; start EMPTY (R) to watch the limit.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")

const VIEW_SHADER := preload("res://addons/sim_water/shaders/swe_view.gdshader")
const WaterWindow := preload("res://addons/sim_water/scripts/water_window.gd")
## Metres per checker square on the bed. A scale reference you can count, which is most of
## what makes a rendered heightfield readable at all - the squares deform with the ground, so
## slope and relief are visible where a flat colour shows nothing.
const CHECKER_M := 2.0

## Bed mesh resolution. 0.5 m matches the water plane's own vertex spacing, so a wave crest and
## the floor under it are sampled at the same rate and a "the water is inside the bank" reading
## is never just the two meshes disagreeing.
const BED_STEP := 0.5

const VIEW_PX := 384                          ## on-screen size of the 512-square state overlay
## Labelled 1..9 to match the number KEYS that select them. They used to be labelled 0..6 while
## the hint promised "1-7", so pressing 1 selected the mode labelled 0 -- a control that lies
## about its own name.
const MODES := ["1 surface  eta", "2 depth  H = H0+eta", "3 speed  |u0+u'|", "4 foam",
		"5 Froude  |u|/sqrt(gH)", "6 terrain field (u0,H0,spring)", "7 wet/dry + tier steps",
		"8 BED  b", "9 CHECK  H0 vs bed  (must be flat grey)", "0 VORTICITY  curl u  (1/s)"]
## Full-scale of each mode's colour ramp, in that mode's own unit. A 1 cm ripple and a 40 cm
## drawdown are the same picture at the wrong scale.
const MODE_RAMP := [0.30, 0.60, 2.00, 1.00, 1.00, 1.00, 1.00, 2.00, 0.01, 1.00]

## The equation mirror's tolerance, and it is set by the STORAGE not by the arithmetic: the state
## texture is RGBA16F, whose ulp at eta ~ 0.5 is 4.9e-4. The shader computes in 32-bit and rounds
## on write; this file computes in 64-bit from those rounded inputs. One ulp of disagreement is
## therefore expected and means nothing. Anything above four is a real divergence.
const MIRROR_TOL := 2.0e-3

@onready var _bed: Node3D = $Bed
@onready var _cam: Camera3D = $FlyCam

var _bed_mi: MeshInstance3D
## THE SIMULATED SURFACE. It replaces the flat per-region plane this bench used to build: that
## one sat at a fixed height and decided where water was from a BAKED depth map, so an empty
## basin and a full lake rendered identically and the bed was never visible under either.
var _window: Node3D
var _focus: Node3D
var _view: TextureRect
var _view_mat: ShaderMaterial
var _report: RichTextLabel
var _status: Label
var _mode := 1                                ## depth: the mode that shows a basin filling
var _pick := Vector2i(-1, -1)                 ## inspected texel, in state-texture coords
var _live := true                             ## re-read the GPU while running, not only on pause
var _live_every := 6
var _frames := 0
var _last_steps := 0
var _stepping := false                        ## a manual burst is in flight; do not re-enter

## Source and sink, in the bed's LOCAL XZ. The source is a painted spring and therefore goes
## through the SHIPPED source path (the field bake marks it, the sim shader injects spring_rate
## at it). The sink has no shipped equivalent and does not need one: a drain is a continuous
## downward displacement, which is exactly what splash() already is, so it is expressed with the
## public impulse API and no new shader code.
var _source_on := true
var _sink_on := false
## AT THE CENTRE of the bed, as asked. The old spot straddled the upstream waterline, where
## only about six field texels ended up flagged at all - a weak source in the wrong place.
var _source_at := Vector2.ZERO
## Metres. Four, not the bed default of two: the area is what sets the inflow, and a 2 m disc
## is 13 square metres against 50.
var _source_radius := 4.0
var _sink_at := Vector2(18.0, 0.0)
var _sink_rate := 0.30                        ## metres of head removed per second
var _sink_radius := 2.0

## The mirror's outstanding prediction: the texel it was computed for and the eta it predicts.
## Checked against the GPU after the next step. This is the whole reason the mirror is worth
## reading — a GDScript re-implementation of a shader drifts, and the only defence is to make the
## drift show itself rather than to be careful.
var _pred_at := Vector2i(-1, -1)
var _pred_e := 0.0
var _pred_line := ""

var _state_img: Image = null
var _field_img: Image = null
## THE BED, on its own image because the depth solver differences it and the mirror has to read
## exactly the texel the shader reads. One float per field texel; the sim shader samples it
## filter_nearest by integer texel index, so `_bed_at` does too, staircase and all.
var _bed_img: Image = null
var _volume := 0.0
var _volume_prev := 0.0
var _vol_rate := 0.0
## Square metres holding water. The companion to volume, and the pair is what makes overflow
## a measurement rather than an impression: while a basin fills, volume climbs and wetted area
## does not. The moment the water tops the rim, area starts climbing too.
var _wet_area := 0.0
## THE DEEPEST COLUMN IN THE WINDOW, tracked because it is the number that kills the solver. The
## scheme is explicit: above kappa = g*h*dt^2/dx^2 = 0.25 it goes unstable, and the state is
## float16, which SATURATES at 65504 rather than going NaN - so a dead field is not detectably
## dead, it just stops being water and stays that way for the rest of the session. The bench opens
## with a source running into a CLOSED BOX, which has no steady state by construction, so watching
## it fill IS a ramp toward that limit. It used to arrive with no warning of any kind.
var _deepest := 0.0


func _ready() -> void:
	_stage_env()
	_focus = Node3D.new()
	_focus.name = "Focus"
	add_child(_focus)
	# DEFAULTS BEFORE THE PANEL, and this ordering is load-bearing. Every row captures the value it
	# finds at build time, so building the panel first made four controls disagree with the solver
	# they claim to drive: "paused" rendered unchecked while the sim was paused, and the eta_keep
	# and draw_max rows showed the shipped numbers directly above amber notes explaining that the
	# bench had overridden them.
	_apply_bench_defaults()
	Ripples.focus_override = _focus
	Ripples.paused = true
	_rebuild()
	_build_ui()
	_place_camera()
	await _reset(true)


## A sim uniform as a float, with a fallback. sim_get answers null for a name the shader does
## not declare, and float(null) is a hard error - on a bench, a knob that has been renamed out of
## the shader should degrade to its documented default, not take the scene down.
func _simf(param: StringName, fallback: float) -> float:
	var v: Variant = Ripples.sim_get(param)
	return float(v) if v != null else fallback


## The three shipped values a bench must override, applied in one place so the reason for each
## lives next to the write. See the file header for why each one is wrong here and right there.
func _apply_bench_defaults() -> void:
	# THE ENCODING THIS BENCH EXISTS TO SHOW. It is not the shipped default - the game still runs
	# the deviation solver - and leaving the bench on the shipped one meant opening the scene
	# demonstrated the thing being replaced. Worse, silently: the solver ran, the volume readout
	# climbed, the overlay filled, and the 3D surface drew nothing at all, because it reads channel
	# R as a depth and a deviation solver puts a negative number there.
	Ripples.depth_mode = true
	# A BOX, which is what "confini della simulazione un cubo" asks for: what is poured in stays in
	# and piles up against the walls. The horizon fade is for a window following a camera through a
	# world that is already full, which is the game and not this.
	Ripples.edge_mode = 1
	# Shipped values that are wrong for a bench, kept for the deviation solver so the A/B is
	# against a solver somebody actually ships. Both are dead in depth mode.
	Ripples.sim_set(&"draw_max", 1.0)
	Ripples.sim_set(&"eta_keep", 1.0)
	# A SOURCE YOU CAN WATCH. The shipped 0.02 m/s over a 2 m spring is a quarter of a cubic metre
	# a second, which fills this basin in half an hour - correct for a river that has always been
	# running and useless for a bench whose whole subject is filling.
	Ripples.sim_set(&"spring_rate", 0.5)
	Ripples.advect = false


func _stage_env() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.52, 0.72)
	sky_mat.sky_horizon_color = Color(0.68, 0.74, 0.78)
	sky_mat.ground_bottom_color = Color(0.22, 0.22, 0.24)
	sky_mat.ground_horizon_color = Color(0.55, 0.55, 0.55)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	($WorldEnvironment as WorldEnvironment).environment = env
	var sun := $Sun as DirectionalLight3D
	# Low and across the basin, because the whole point of WD4's slope shading is that it is a
	# grazing-light effect: a sun overhead makes a moving surface look exactly like a flat one.
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(48.0), 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true


func _place_camera() -> void:
	var e: float = _bed.get("extent")
	_cam.global_position = _bed.global_position + Vector3(0.0, e * 0.5, e * 0.72)
	_cam.look_at(_bed.global_position, Vector3.UP)


# ------------------------------------------------------------------- the bed and the water ----

## Rebuild everything that depends on the bed's shape: the floor mesh, the water plane's baked
## depth texture, and the solver's own field. All three read `bed_at`, so a profile change that
## updated only two of them would give a solver running on a bed nobody can see.
func _rebuild() -> void:
	var s: Array[Vector2] = []
	if _source_on:
		s.append(_source_at)
	_bed.set("springs", s)
	_bed.set("spring_radius", _source_radius)
	_build_bed_mesh()
	_build_water()
	Ripples.reset_now()


func _build_bed_mesh() -> void:
	if _bed_mi != null:
		# free(), not queue_free(): a rebuild that happens twice in one frame would otherwise leave
		# both meshes standing until the frame ended, and the bench rebuilds on every knob.
		_bed_mi.free()
		_bed_mi = null
	var e: float = _bed.get("extent")
	var n := int(e / BED_STEP) + 1
	var rest: float = _bed.get("rest_y")
	var deep: float = _bed.get("bed_depth")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in n:
		for x in n:
			var l := Vector2(x, z) / float(n - 1) * e - Vector2(e, e) * 0.5
			var y: float = _bed.call("bed_at", l)
			# Coloured by where the floor sits relative to the REST SURFACE, not by absolute
			# height: the question this mesh has to answer at a glance is "which of this is
			# basin and which is bank", and that is a comparison against rest.
			var c := Color(0.46, 0.40, 0.30).lerp(Color(0.20, 0.17, 0.13),
					clampf((rest - y) / maxf(deep, 0.01), 0.0, 1.0))
			if y >= rest:
				c = Color(0.34, 0.42, 0.26).lerp(Color(0.46, 0.49, 0.36),
						clampf(y - rest, 0.0, 1.0))
			st.set_color(c)
			# One texture tile spans two checker squares, so UV = local / (2 * CHECKER_M).
			st.set_uv(l / (2.0 * CHECKER_M))
			st.add_vertex(Vector3(l.x, y, l.y))
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			# WINDING, and it is not a detail here. Wound the other way this mesh is back-face
			# culled AND generate_normals() points every normal at the ground, so the bench showed
			# a bare grey void where its terrain should be - which is precisely the report that
			# started this work: "the lab is a plane, there is no terrain lakebed". It was never a
			# plane. The bed was there the whole time, inside out.
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	# The checker MULTIPLIES the vertex colour rather than replacing it: the colour still says
	# basin or bank, and the squares say how big and how steep.
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _checker_texture()
	# NEAREST, or a two-tone texture turns into grey mush the moment it is minified, and the grid
	# that was the whole point stops being countable.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 1.0
	_bed_mi = MeshInstance3D.new()
	_bed_mi.name = "BedMesh"
	_bed_mi.mesh = st.commit()
	_bed_mi.material_override = mat
	_bed.add_child(_bed_mi)


## A two-tone checker, 64 px with 32 px squares. Not 2x2: a texture that small has nowhere to
## mipmap to, and the distant half of the bench would alias into noise.
func _checker_texture() -> ImageTexture:
	var img := Image.create(64, 64, true, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var on := ((x / 32) + (y / 32)) % 2 == 0
			img.set_pixel(x, y, Color(0.80, 0.80, 0.79) if on else Color(0.53, 0.53, 0.55))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The water plane, running the GAME's water shader — same displacement, same slope shading, same
## sampling of the solver's global. `flow_map` is deliberately left unbound: it defaults to black,
## which is zero baked current, which is what this bench wants under everything.
## THE SIMULATED SURFACE, built once. It is not rebuilt with the bed, because it does not know
## anything about the bed: it reads the solver's window every frame and draws whatever is there.
func _build_water() -> void:
	if _window == null:
		_window = WaterWindow.new()
		_window.name = "WaterWindow"
		add_child(_window)


# ------------------------------------------------------------------------------- stepping -----

## Advance the solver by `n` steps, feeding the sink one step's worth before each. One rendered
## frame is one step — that is the driver's own rule (see ripple_field.gd's _process header), so
## the await is not a delay, it IS the step.
func _do_steps(n: int) -> void:
	if _stepping:
		return
	_stepping = true
	for _i in n:
		_feed_sink(1)
		Ripples.step_once()
		await get_tree().process_frame
	_stepping = false
	_read_back()
	_inspect()


func _reset(empty: bool) -> void:
	Ripples.reset_empty = empty
	Ripples.reset_now()
	_pred_at = Vector2i(-1, -1)
	_pred_line = ""
	# Two, because the reset writes both halves of the ping-pong before the first real step reads
	# either. Asking for one leaves the back half holding an unwritten texture.
	await _do_steps(2)
	_volume_prev = _volume
	_vol_rate = 0.0


## One step's worth of drain at the sink, as a downward displacement. splash() clamps a poke to
## poke_frac of the local column, so the drain automatically weakens as the cell empties and can
## never pull the depth negative — the physically right behaviour, for free.
func _feed_sink(steps: int) -> void:
	if not _sink_on or steps <= 0:
		return
	var w := _bed.to_global(Vector3(_sink_at.x, float(_bed.get("rest_y")), _sink_at.y))
	Ripples.splash(w, _sink_radius, _sink_rate * (1.0 / 60.0) * steps)


func _process(_delta: float) -> void:
	# Scaled by the steps the solver ACTUALLY took, not by frames: above 60 fps the driver skips
	# frames to hold real-time speed, and a per-frame drain would then remove more water on a fast
	# machine than on a slow one. This is one step late and exactly conserved.
	var taken: int = Ripples.debug_steps - _last_steps
	_last_steps = Ripples.debug_steps
	if not Ripples.paused and not _stepping:
		_feed_sink(taken)
	_frames += 1
	if _live and taken > 0 and not _stepping and _frames % _live_every == 0:
		_read_back()
		_inspect()
	_refresh_status()


# --------------------------------------------------------------------------- the readback -----

## Pull both textures to the CPU. Deliberately NOT every frame: a 512-square RGBA16F readback is a
## pipeline stall, and this bench spends most of its life paused, where one readback lasts until
## the next step.
func _read_back() -> void:
	var st: Texture2D = Ripples.debug_texture()
	var ft: Texture2D = Ripples.field_texture()
	if st == null or ft == null:
		return
	_state_img = st.get_image()
	_field_img = ft.get_image()
	var bt: Texture2D = Ripples.bed_texture()
	_bed_img = bt.get_image() if bt != null else null
	if _state_img == null or _field_img == null:
		return
	_volume_prev = _volume
	_volume = 0.0
	_wet_area = 0.0
	_deepest = 0.0
	var res := _state_img.get_width()
	var texel := Ripples.SIZE_M / float(res)
	var area := texel * texel
	var h_dry := _simf(&"h_dry", 0.002)
	# Every fourth texel in each direction: a sixteenth of the work for a figure whose third
	# decimal nobody reads, and the sampling is REGULAR so its bias is constant - the DIFFERENCE
	# between two readings, which is what the mass question actually asks, is unaffected.
	if Ripples.depth_mode:
		# NO REGION GATE. The eta branch below skips anything the map did not paint as water,
		# which in this encoding would silently refuse to count the flood - exactly the thing
		# being measured.
		for z in range(0, res, 4):
			for x in range(0, res, 4):
				var hh := maxf(_state_img.get_pixel(x, z).r, 0.0)
				if hh <= 0.0:
					continue
				_deepest = maxf(_deepest, hh)
				_volume += hh * area * 16.0
				if hh > h_dry:
					_wet_area += area * 16.0
	else:
		for z in range(0, res, 4):
			for x in range(0, res, 4):
				var uv := Vector2(x + 0.5, z + 0.5) / float(res)
				var yraw := _field_y_at_uv(uv)
				if yraw - (Ripples.SPRING_MARK if yraw > Ripples.SPRING_MARK * 0.5 else 0.0) 						<= Ripples.DRY_Y + 1.0:
					continue
				var f := _field_lin_at_uv(uv)
				var hh2 := maxf(f.z + _state_img.get_pixel(x, z).r, 0.0)
				_deepest = maxf(_deepest, hh2)
				_volume += hh2 * area * 16.0
				if hh2 > h_dry:
					_wet_area += area * 16.0
	_vol_rate = (_volume - _volume_prev) * 60.0 / maxf(float(_live_every), 1.0)


## The field, BILINEARLY, exactly as the sim shader's `filter_linear` sampler reads it. Returns
## (u0.x, u0.y, H0, unused).
func _field_lin_at_uv(uv: Vector2) -> Vector3:
	if _field_img == null:
		return Vector3.ZERO
	var n := _field_img.get_width()
	var t := uv * float(n) - Vector2(0.5, 0.5)
	var i0 := Vector2i(floori(t.x), floori(t.y))
	var fr := t - Vector2(i0)
	var acc := Vector3.ZERO
	for dz in 2:
		for dx in 2:
			var p := Vector2i(clampi(i0.x + dx, 0, n - 1), clampi(i0.y + dz, 0, n - 1))
			var w := (fr.x if dx == 1 else 1.0 - fr.x) * (fr.y if dz == 1 else 1.0 - fr.y)
			var px := _field_img.get_pixel(p.x, p.y)
			acc += Vector3(px.r, px.g, px.b) * w
	return acc


## Y, NEAREST, with the spring flag still riding it — the sim shader's `field_n` sampler. The flag
## is returned intact; callers strip it the same way the shader does.
func _field_y_at_uv(uv: Vector2) -> float:
	if _field_img == null:
		return Ripples.DRY_Y
	var n := _field_img.get_width()
	var p := Vector2i(clampi(int(uv.x * n), 0, n - 1), clampi(int(uv.y * n), 0, n - 1))
	return _field_img.get_pixel(p.x, p.y).a


## THE CELL-CENTRED VELOCITY at a state texel, in whichever layout is live.
##
## Staggered, G is the velocity on the cell's LEFT face and B on its BOTTOM face, so "the velocity
## here" is the mean of the two faces either side - this cell's own and its +x / +y neighbour's.
## Reading G and B straight is then wrong by half a texel in each direction, which does not look
## wrong: it shifts a shear layer, halves its measured strength, and moves a vortex core off the
## place the vortex actually is. Every instrument that reports a speed goes through here.
func _vel_at(w: Vector2i, res: int) -> Vector2:
	if _state_img == null:
		return Vector2.ZERO
	var c := _state_img.get_pixel(clampi(w.x, 0, res - 1), clampi(w.y, 0, res - 1))
	if not Ripples.staggered:
		return Vector2(c.g, c.b)
	var rx := _state_img.get_pixel(clampi(w.x + 1, 0, res - 1), clampi(w.y, 0, res - 1))
	var ry := _state_img.get_pixel(clampi(w.x, 0, res - 1), clampi(w.y + 1, 0, res - 1))
	return Vector2(0.5 * (c.g + rx.g), 0.5 * (c.b + ry.b))


## The bed under a STATE TEXEL, by integer index, exactly as the sim shader's bed_at() reads it.
## Addressing by uv instead would reproduce the bug that function exists to remove: two cells
## sharing a face computing the same bed texel's coordinate slightly differently, and an ulp at a
## texel boundary is a different texel.
func _bed_at(w: Vector2i, res: int) -> float:
	if _bed_img == null:
		return 0.0
	var n := _bed_img.get_width()
	var p := _fld(w, res, n)
	if not bool(_rip_bool(&"bed_smooth", true)):
		return _bed_img.get_pixel(p.x, p.y).r
	# Bilinear, with the sentinel never interpolated - the sim shader's bed_at(), term for term.
	var c := Vector2i(clampi(w.x, 0, res - 1), clampi(w.y, 0, res - 1))
	var t := Vector2((float(c.x) + 0.5) / float(res) * float(n) - 0.5,
			(float(c.y) + 0.5) / float(res) * float(n) - 0.5)
	var i0 := Vector2i(floori(t.x), floori(t.y))
	var fr := t - Vector2(i0)
	var b := PackedFloat32Array([0, 0, 0, 0])
	var top := -1e9
	for k in 4:
		var q := Vector2i(clampi(i0.x + (k & 1), 0, n - 1), clampi(i0.y + (k >> 1), 0, n - 1))
		b[k] = _bed_img.get_pixel(q.x, q.y).r
		top = maxf(top, b[k])
	if top > 500.0:
		return _bed_img.get_pixel(p.x, p.y).r
	return lerpf(lerpf(b[0], b[1], fr.x), lerpf(b[2], b[3], fr.x), fr.y)


## A bool sim uniform, with the shader's own default when nothing has set it.
func _rip_bool(name_: StringName, fallback: bool) -> bool:
	var v: Variant = Ripples.sim_get(name_)
	return fallback if v == null else bool(v)


## The rest surface Y at a state texel, over the SAME stencil `_bed_at` uses, spring flag stripped.
## Reading one of the pair through a uv and the other by index is what put 153 seeded holes in the
## valley bank; smoothing one without the other put a band of them along every waterline. The sim
## shader's rest_y_at(), term for term.
func _rest_y_at(w: Vector2i, res: int) -> float:
	if _field_img == null:
		return Ripples.DRY_Y
	var n := _field_img.get_width()
	var mark: float = Ripples.SPRING_MARK
	if not _rip_bool(&"bed_smooth", true):
		var p := _fld(w, res, n)
		var yr := _field_img.get_pixel(p.x, p.y).a
		return yr - (mark if yr > mark * 0.5 else 0.0)
	var c := Vector2i(clampi(w.x, 0, res - 1), clampi(w.y, 0, res - 1))
	var t := Vector2((float(c.x) + 0.5) / float(res) * float(n) - 0.5,
			(float(c.y) + 0.5) / float(res) * float(n) - 0.5)
	var i0 := Vector2i(floori(t.x), floori(t.y))
	var best: float = Ripples.DRY_Y
	for k in 4:
		var q := Vector2i(clampi(i0.x + (k & 1), 0, n - 1), clampi(i0.y + (k >> 1), 0, n - 1))
		var yr := _field_img.get_pixel(q.x, q.y).a
		best = maxf(best, yr - (mark if yr > mark * 0.5 else 0.0))
	return best


## The spring flag, NEAREST - it is a flag, and an interpolated flag is a wrong answer in a band
## around every source.
func _spring_at(w: Vector2i, res: int) -> float:
	if _field_img == null:
		return 0.0
	var p := _fld(w, res, _field_img.get_width())
	return 1.0 if _field_img.get_pixel(p.x, p.y).a > Ripples.SPRING_MARK * 0.5 else 0.0


## The terrain texel a state texel stands on. The sim shader's fld().
func _fld(w: Vector2i, res: int, n: int) -> Vector2i:
	var c := Vector2i(clampi(w.x, 0, res - 1), clampi(w.y, 0, res - 1))
	return Vector2i(clampi(floori((float(c.x) + 0.5) / float(res) * float(n)), 0, n - 1),
			clampi(floori((float(c.y) + 0.5) / float(res) * float(n)), 0, n - 1))


## The STATE, bilinearly — the `prev` sampler, which the solver reads that way in exactly one
## place: the semi-Lagrangian backtrace. Everywhere else it uses texelFetch, and the mirror uses
## get_pixel to match.
func _state_lin_at_uv(uv: Vector2) -> Color:
	if _state_img == null:
		return Color(0, 0, 0, 0)
	var n := _state_img.get_width()
	var t := uv * float(n) - Vector2(0.5, 0.5)
	var i0 := Vector2i(floori(t.x), floori(t.y))
	var fr := t - Vector2(i0)
	var acc := Color(0, 0, 0, 0)
	for dz in 2:
		for dx in 2:
			var p := Vector2i(clampi(i0.x + dx, 0, n - 1), clampi(i0.y + dz, 0, n - 1))
			var w := (fr.x if dx == 1 else 1.0 - fr.x) * (fr.y if dz == 1 else 1.0 - fr.y)
			acc += _state_img.get_pixel(p.x, p.y) * w
	return acc


# ----------------------------------------------------------------------- the equation mirror --
#
# THIS IS A SECOND IMPLEMENTATION OF shaders/swe_sim.gdshader's fragment(), in GDScript, over the
# same two textures, in the same order, with the same constants. That is a liability and it is
# taken on deliberately: there is no other way to show a term of the update, because the shader
# computes all of them inside one invocation and emits only their sum.
#
# The liability is paid for by the SELF-CHECK. Every inspection records the eta it predicts for
# the picked texel; the next step reads what the GPU actually wrote there and prints both. A
# mirror that has drifted from the shader says so on its own line, in red, at the bottom of every
# report — so this file cannot quietly become fiction, which is the failure mode that makes a
# debug view worse than none.

## One texel's full update, as an ordered list of the terms that produce it. Fills `_report`.
func _inspect() -> void:
	if _report == null:
		return
	if _state_img == null or _field_img == null or _pick.x < 0:
		_report.text = "[color=#888]click the overlay to inspect a cell[/color]"
		return
	var res := _state_img.get_width()
	if _pick.x >= res or _pick.y >= res:
		return
	if Ripples.depth_mode:
		if Ripples.staggered:
			_inspect_staggered(res)
		else:
			_inspect_depth(res)
		return
	var dx := Ripples.SIZE_M / float(res)
	var dt := 1.0 / 60.0
	var g: float = Ripples.GRAVITY
	var drag := _simf(&"drag", 1.3)
	var manning := _simf(&"manning", 0.03)
	var eta_keep := _simf(&"eta_keep", 0.999)
	var u_max := _simf(&"u_max", 3.0)
	var weir_cd := _simf(&"weir_cd", 0.5443)
	var tier_eps := _simf(&"tier_eps", 0.5)
	var h_dry := _simf(&"h_dry", 0.002)
	var h_wet := _simf(&"h_wet", 0.02)
	var h_min := _simf(&"h_min", 0.01)
	var draw_max := _simf(&"draw_max", 0.55)
	var spring_rate := _simf(&"spring_rate", 0.06)
	var weirs_on: bool = Ripples.weirs

	var uv := Vector2(_pick.x + 0.5, _pick.y + 0.5) / float(res)
	var yraw := _field_y_at_uv(uv)
	var spring := 1.0 if yraw > Ripples.SPRING_MARK * 0.5 else 0.0
	var Y := yraw - spring * Ripples.SPRING_MARK
	var org: Vector2 = Ripples.window_origin()
	var world := org + Vector2(_pick.x + 0.5, _pick.y + 0.5) * dx

	var out := PackedStringArray()
	out.append("[b]cell[/b] (%d, %d)   world (%.2f, %.2f)   dx %.3f m   dt %.4f s"
			% [_pick.x, _pick.y, world.x, world.y, dx, dt])
	if Y <= Ripples.DRY_Y + 1.0:
		out.append("[color=#c88]no water region here (Y = DRY). The solver writes vec4(0) and "
				+ "returns — no equation runs in this cell.[/color]")
		_report.text = "\n".join(out)
		_pred_at = Vector2i(-1, -1)
		return

	var f := _field_lin_at_uv(uv)
	var u0 := Vector2(f.x, f.y)
	var H0 := maxf(f.z, 0.0)
	var s := _state_img.get_pixel(_pick.x, _pick.y)
	var e: float = s.r
	var ud := Vector2(s.g, s.b)
	var foam: float = s.a
	var H := maxf(H0 + e, 0.0)

	out.append("[b]terrain[/b]  rest Y %.3f   H0 %.3f   u0 (%.3f, %.3f)%s"
			% [Y, H0, u0.x, u0.y, "   [color=#6f6]SPRING[/color]" if spring > 0.5 else ""])
	out.append("[b]state[/b]    eta %+.4f   u' (%+.3f, %+.3f)   foam %.3f   -> H %.4f"
			% [e, ud.x, ud.y, foam, H])

	# ---- the four faces. A dry neighbour and a tier step both CLOSE a face.
	var OFF := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var en := PackedFloat32Array([0, 0, 0, 0])
	var Hn := PackedFloat32Array([0, 0, 0, 0])
	var open := PackedFloat32Array([0, 0, 0, 0])
	var dYn := PackedFloat32Array([0, 0, 0, 0])
	var eraw := PackedFloat32Array([0, 0, 0, 0])
	var wet := PackedFloat32Array([0, 0, 0, 0])
	var face_txt := PackedStringArray()
	for i in 4:
		var nuv := uv + Vector2(OFF[i]) / float(res)
		var fn := _field_lin_at_uv(nuv)
		var ynr := _field_y_at_uv(nuv)
		var yn := ynr - (Ripples.SPRING_MARK if ynr > Ripples.SPRING_MARK * 0.5 else 0.0)
		var sn := _state_img.get_pixel(clampi(_pick.x + OFF[i].x, 0, res - 1),
				clampi(_pick.y + OFF[i].y, 0, res - 1))
		var w := 1.0 if yn > Ripples.DRY_Y + 1.0 else 0.0
		var dY := yn - Y
		var stp := 1.0 if (w > 0.5 and absf(dY) > tier_eps) else 0.0
		wet[i] = w
		dYn[i] = dY
		eraw[i] = sn.r
		open[i] = 1.0 if (w > 0.5 and stp < 0.5) else 0.0
		en[i] = lerpf(e, sn.r, open[i])
		Hn[i] = lerpf(H, maxf(fn.z + sn.r, 0.0), open[i])
		var why := "open"
		if w < 0.5:
			why = "[color=#c96]CLOSED dry[/color]"
		elif stp > 0.5:
			why = "[color=#fc6]CLOSED step dY %+.2f[/color]" % dY
		face_txt.append("  %s  %s  eta %+.4f  H %.4f"
				% [["+x", "-x", "+z", "-z"][i], why, en[i], Hn[i]])
	out.append("[b]faces[/b]  (a closed face mirrors self: zero gradient, zero flux)")
	out.append_array(face_txt)

	# ---- momentum, in the shader's order.
	var grad_e := Vector2(en[0] - en[1], en[2] - en[3]) / (2.0 * dx)
	var acc := -g * grad_e
	var u1 := ud + acc * dt
	var after_grav := u1
	u1 *= exp(-drag * dt)
	var after_drag := u1
	var Hs := maxf(H, h_min)
	var utot := u0 + ud
	var mann_div := 1.0 + dt * g * manning * manning * utot.length() / pow(Hs, 4.0 / 3.0)
	u1 /= mann_div
	var wet_ramp := smoothstep(h_dry, h_wet, H)
	u1 *= wet_ramp
	var clamped := false
	if u1.length() > u_max:
		u1 *= u_max / u1.length()
		clamped = true
	out.append("[b]momentum[/b]")
	out.append("  grad eta (%+.4f, %+.4f) /m   ->  a = -g*grad = (%+.3f, %+.3f) m/s2"
			% [grad_e.x, grad_e.y, acc.x, acc.y])
	out.append("  + a*dt        u' (%+.4f, %+.4f)" % [after_grav.x, after_grav.y])
	out.append("  * exp(-drag*dt) = %.5f   u' (%+.4f, %+.4f)"
			% [exp(-drag * dt), after_drag.x, after_drag.y])
	out.append("  / Manning %.5f   * wet_ramp %.3f   ->  u' (%+.4f, %+.4f)%s"
			% [mann_div, wet_ramp, u1.x, u1.y,
			"  [color=#f88]CLAMPED at u_max[/color]" if clamped else ""])

	# ---- continuity, forward-backward: upwind depth transports, symmetric depth waves.
	var divq := 0.0
	var lapH := 0.0
	for i in 4:
		var sgn := 1.0 if (i == 0 or i == 2) else -1.0
		var snb := _state_img.get_pixel(clampi(_pick.x + OFF[i].x, 0, res - 1),
				clampi(_pick.y + OFF[i].y, 0, res - 1))
		var un := Vector2(lerpf(u1.x, snb.g, open[i]), lerpf(u1.y, snb.b, open[i]))
		var axu := 0.5 * (u1.x + un.x) if i < 2 else 0.5 * (u1.y + un.y)
		var uf := axu * sgn
		var Hup := H if uf > 0.0 else Hn[i]
		var Hav := 0.5 * (H + Hn[i])
		divq += open[i] * Hup * uf / dx
		lapH += open[i] * Hav * (en[i] - e) / (dx * dx)
	var d_transport := -dt * divq
	var d_lap := g * dt * dt * lapH
	var e_new := e + d_transport + d_lap
	out.append("[b]continuity[/b]  e_new = e - dt*div(q) + g*dt^2*lap(H)")
	out.append("  div(q) %+.5f /s      -> %+.6f m   (%+.3f mm)"
			% [divq, d_transport, d_transport * 1000.0])
	out.append("  lap(H) %+.5f /m/s    -> %+.6f m   (%+.3f mm)"
			% [lapH, d_lap, d_lap * 1000.0])

	# ---- weirs, the only way mass crosses a tier step.
	var d_weir := 0.0
	if weirs_on:
		for i in 4:
			if wet[i] < 0.5 or absf(dYn[i]) <= tier_eps:
				continue
			var head := maxf(eraw[i], 0.0) if dYn[i] > 0.0 else maxf(e, 0.0)
			var q := minf(weir_cd * sqrt(g) * head * sqrt(head), head * dx / (4.0 * dt))
			var dv := q * dt / dx
			d_weir += dv if dYn[i] > 0.0 else -dv
			out.append("[b]weir[/b] %s  %s  head %.4f  q %.5f m2/s  -> %+.6f m"
					% [["+x", "-x", "+z", "-z"][i],
					"INFLOW from above" if dYn[i] > 0.0 else "outflow to below",
					head, q, dv if dYn[i] > 0.0 else -dv])
	elif _has_step(wet, dYn, tier_eps):
		out.append("[b]weir[/b]  [color=#fc6]a step touches this cell but weirs_on is "
				+ "false — no mass can cross it[/color]")
	e_new += d_weir

	# ---- source, relaxation, positivity floor.
	var d_spring := spring * spring_rate * dt
	e_new += d_spring
	var before_keep := e_new
	e_new *= eta_keep
	var d_keep := e_new - before_keep
	var floor_y := -H0 * draw_max
	var floored := e_new < floor_y
	if floored:
		e_new = floor_y
	if spring > 0.5:
		out.append("[b]source[/b]  spring_rate %.4f m/s  -> %+.6f m  (%+.3f mm)"
				% [spring_rate, d_spring, d_spring * 1000.0])
	out.append("[b]relax[/b]  eta_keep %.5f  -> %+.6f m%s"
			% [eta_keep, d_keep, "   [color=#fc6](pulls an EMPTY cell UP toward rest)[/color]"
			if d_keep > 0.0 else ""])
	if floored:
		out.append("[color=#f88][b]floor[/b]  clamped to -H0*draw_max = %.4f — this cell is "
				% floor_y + "PINNED, not solved[/color]")

	# ---- Froude and foam, the whitewater model.
	var Fr := (u0 + u1).length() / sqrt(g * maxf(H, 0.05))
	out.append("[b]Froude[/b] %.3f  %s" % [Fr,
			"[color=#f96]supercritical[/color]" if Fr > 1.0 else "subcritical"])
	out.append("[b]eta[/b]  %+.5f  ->  [b]%+.5f[/b]   (%+.4f mm this step)"
			% [e, e_new, (e_new - e) * 1000.0])

	if _pred_line != "":
		out.append(_pred_line)
	_report.text = "\n".join(out)
	_pred_at = _pick
	_pred_e = e_new


## THE DEPTH SOLVER'S TERM LIST, mirroring shaders/swe_sim.gdshader's step_depth() in its own
## order. Same contract as the eta mirror above: it predicts h for the next step and the self-check
## prints how far the GPU landed from it, so this panel cannot quietly become fiction.
##
## It used to REFUSE, printing "the mirror models the eta solver only". That was honest and it was
## also the reason every failure in this branch arrived as a whole-field mystery: there was no way
## to ask a single cell what it was doing, so six candidate causes for a frozen shoreline had to be
## eliminated by bisecting global knobs over six hundred steps apiece.
##
## TWO THINGS IT DOES NOT MODEL, and both say so on the report rather than being silently absent:
## the impulse queue (private to Ripples, and the sink feeds it every step), and the sub-ulp
## rounding dither. The dither is bounded by one ulp, which is inside MIRROR_TOL by design.
func _inspect_depth(res: int) -> void:
	var dx := Ripples.SIZE_M / float(res)
	var dt := 1.0 / 60.0
	var g: float = Ripples.GRAVITY
	var drag := _simf(&"drag", 0.7)
	var manning := _simf(&"manning", 0.03)
	var u_max := _simf(&"u_max", 3.0)
	var weir_cd := _simf(&"weir_cd", 1.0)
	var h_dry := _simf(&"h_dry", 0.002)
	var h_min := _simf(&"h_min", 0.01)
	var hf_min := _simf(&"hf_min", 0.0)
	var h_fric := _simf(&"h_fric", 0.0005)
	var seep := _simf(&"seep", 0.001)
	var spring_rate := _simf(&"spring_rate", 0.06)
	var advect_gain := 1.0 if Ripples.advect else 0.0

	var uv := Vector2(_pick.x + 0.5, _pick.y + 0.5) / float(res)
	var org: Vector2 = Ripples.window_origin()
	var world := org + Vector2(_pick.x + 0.5, _pick.y + 0.5) * dx
	var spring := _spring_at(_pick, res)
	var Y := _rest_y_at(_pick, res)
	var b := _bed_at(_pick, res)
	var h0 := maxf(Y - b, 0.0)
	var f := _field_lin_at_uv(uv)
	var u0 := Vector2(f.x, f.y)

	var s := _state_img.get_pixel(_pick.x, _pick.y)
	var h: float = maxf(s.r, 0.0)
	var ud := Vector2(s.g, s.b)
	var foam: float = s.a

	var out := PackedStringArray()
	out.append("[b]cell[/b] (%d, %d)   world (%.2f, %.2f)   dx %.3f m   dt %.4f s"
			% [_pick.x, _pick.y, world.x, world.y, dx, dt])
	out.append("[b]terrain[/b]  bed b %+.4f   rest Y %+.4f   -> rest depth h0 %.4f%s"
			% [b, Y, h0, "   [color=#6f6]SPRING[/color]" if spring > 0.5 else ""])
	out.append("[b]state[/b]    h %.4f m   u' (%+.4f, %+.4f)   foam %.3f   -> surface w %+.4f"
			% [h, ud.x, ud.y, foam, b + h])

	# ---- the fast path, which is an answer and therefore has to be shown as one.
	var OFF := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var sn: Array[Color] = []
	for i in 4:
		var q := Vector2i(clampi(_pick.x + OFF[i].x, 0, res - 1),
				clampi(_pick.y + OFF[i].y, 0, res - 1))
		sn.append(_state_img.get_pixel(q.x, q.y))

	var w := b + h

	# ---- the four faces, LISFLOOD-FP. hf is the depth over the higher of the two beds.
	var hf := PackedFloat32Array([0, 0, 0, 0])
	var open := PackedFloat32Array([0, 0, 0, 0])
	var wn := PackedFloat32Array([0, 0, 0, 0])
	var hn := PackedFloat32Array([0, 0, 0, 0])
	var face_txt := PackedStringArray()
	for i in 4:
		var bn := _bed_at(_pick + OFF[i], res)
		var hnb := maxf(sn[i].r, 0.0)
		var wnb := bn + hnb
		hf[i] = maxf(0.0, maxf(w, wnb) - maxf(b, bn))
		open[i] = 1.0 if hf[i] > hf_min else 0.0
		wn[i] = lerpf(w, wnb, open[i])
		hn[i] = lerpf(h, hnb, open[i])
		var why := "open"
		if open[i] < 0.5:
			why = ("[color=#c96]CLOSED[/color] hf %.5f <= hf_min %.4f  (bed %+.3f vs %+.3f)"
					% [hf[i], hf_min, b, bn])
		face_txt.append("  %s  %s   hf %.5f   w_n %+.4f   h_n %.4f"
				% [["+x", "-x", "+z", "-z"][i], why, hf[i], wn[i], hn[i]])
	out.append("[b]faces[/b]  hf = max(0, max(w, w_n) - max(b, b_n))   "
			+ "(a closed face MIRRORS self: w_n := w)")
	out.append_array(face_txt)

	# ---- momentum, on the SURFACE gradient. The mirror flags the halving rather than hiding it.
	var grad_w := Vector2(wn[0] - wn[1], wn[2] - wn[3]) / (2.0 * dx)
	var acc := -g * grad_w
	var closed_x := open[0] < 0.5 or open[1] < 0.5
	var closed_z := open[2] < 0.5 or open[3] < 0.5
	out.append("[b]momentum[/b]")
	out.append("  grad w (%+.5f, %+.5f) /m   ->  a = -g*grad = (%+.4f, %+.4f) m/s2%s"
			% [grad_w.x, grad_w.y, acc.x, acc.y,
			"   [color=#fc6](one-sided over 2*dx: HALVED)[/color]"
			if (closed_x or closed_z) else ""])

	# ---- advection. advect_gain is 0 unless the bench turns it on, but foam rides the backtrace
	# unconditionally - which is easy to miss reading the shader and matters to the picture.
	var utot := u0 + ud
	var back := (uv - utot * (dt / maxf(Ripples.SIZE_M, 0.001))).clamp(Vector2.ZERO, Vector2.ONE)
	var sb := _state_lin_at_uv(back)
	var fb := _field_lin_at_uv(back)
	var ud_adv := Vector2(sb.g, sb.b) + (Vector2(fb.x, fb.y) - u0)
	ud = ud.lerp(ud_adv, advect_gain)
	foam = sb.a
	if advect_gain > 0.0:
		out.append("  advect %.2f: backtrace to uv (%.4f, %.4f)  ->  u' (%+.4f, %+.4f)"
				% [advect_gain, back.x, back.y, ud.x, ud.y])
	else:
		out.append("  [color=#888]advect_gain 0 - no momentum self-advection. div(q(x)u) is not in "
				+ "this solver at all, which is why it has no eddies.[/color]")

	ud += acc * dt
	var after_grav := ud
	ud *= exp(-drag * dt)
	var after_drag := ud
	var hs := maxf(h, h_min)
	var hff := maxf(h, h_fric)
	var mann_div := 1.0 + dt * g * manning * manning * (u0 + ud).length() / pow(hff, 4.0 / 3.0)
	ud /= mann_div
	var clamped := ud.length() > u_max
	if clamped:
		ud *= u_max / ud.length()
	out.append("  + a*dt          u' (%+.4f, %+.4f)" % [after_grav.x, after_grav.y])
	out.append("  * exp(-drag*dt) = %.5f   u' (%+.4f, %+.4f)"
			% [exp(-drag * dt), after_drag.x, after_drag.y])
	out.append("  / Manning %.5f  (over h %.5f, floor h_fric %.5f)   ->  u' (%+.4f, %+.4f)%s"
			% [mann_div, h, h_fric, ud.x, ud.y,
			"  [color=#f88]CLAMPED at u_max[/color]" if clamped else ""])

	# ---- continuity, from OLD velocities on BOTH sides, so the face is antisymmetric.
	var divq := 0.0
	var lapW := 0.0
	var capped := 0
	for i in 4:
		var sgn := 1.0 if (i == 0 or i == 2) else -1.0
		var axu := 0.5 * (s.g + sn[i].g) if i < 2 else 0.5 * (s.b + sn[i].b)
		var uf := axu * sgn
		var hdon := h if uf > 0.0 else hn[i]
		var q := minf(hf[i], hdon) * uf
		var qcap := minf(weir_cd * sqrt(g * hf[i]) * hf[i], hdon * dx / (4.0 * dt))
		if absf(q) > qcap:
			capped += 1
		q = clampf(q, -qcap, qcap)
		divq += open[i] * q / dx
		lapW += open[i] * hf[i] * (wn[i] - w) / (dx * dx)
	var d_transport := -dt * divq
	var d_lap := g * dt * dt * lapW
	var h_new := h + d_transport + d_lap
	out.append("[b]continuity[/b]  h_new = h - dt*div(q) + g*dt^2*lap(w)")
	out.append("  div(q) %+.5f /s      -> %+.6f m   (%+.4f mm)%s"
			% [divq, d_transport, d_transport * 1000.0,
			"   [color=#f88]%d face(s) at the critical cap[/color]" % capped if capped > 0 else ""])
	out.append("  lap(w) %+.5f /m/s    -> %+.6f m   (%+.4f mm)"
			% [lapW, d_lap, d_lap * 1000.0])

	# ---- source and seepage.
	var d_spring := spring * spring_rate * dt
	h_new += d_spring
	if spring > 0.5:
		out.append("[b]source[/b]  spring_rate %.4f m/s  -> %+.6f m  (%+.4f mm)"
				% [spring_rate, d_spring, d_spring * 1000.0])
	var before_seep := h_new
	h_new = maxf(h_new - seep * dt, 0.0)
	if seep > 0.0:
		out.append("[b]seep[/b]  %.5f m/s  -> %+.6f m" % [seep, h_new - before_seep])

	# ---- foam. Reported because the white sheet on overflow was a foam bug that read as a solver
	# bug for as long as nobody could see the two terms apart.
	var Fr := (u0 + ud).length() / sqrt(g * maxf(h_new, 0.05))
	var wsum := 0.0
	var wcnt := 0.0
	for i in 4:
		wsum += open[i] * wn[i]
		wcnt += open[i]
	var w_new := b + h_new
	var wbar := wsum / wcnt if wcnt > 0.5 else w_new
	var crest := smoothstep(0.35, 0.60, (w_new - wbar) / maxf(hs, h_min))
	out.append("[b]Froude[/b] %.3f  %s     [b]crest[/b] %.3f  (w %+.4f vs open-neighbour mean "
			% [Fr, "[color=#f96]supercritical[/color]" if Fr > 1.0 else "subcritical", crest, w_new]
			+ "%+.4f)" % wbar)

	# ---- the impulse queue, which this mirror cannot see.
	var sink_d := (Vector2(world.x, world.y)
			- (Vector2(_bed.global_position.x, _bed.global_position.z) + _sink_at)).length()
	var poked := _sink_on and sink_d < _sink_radius * 2.0
	if poked:
		out.append("[color=#fc6][b]impulse[/b]  this cell is inside the sink, which reaches the "
				+ "solver through the private impulse queue. The mirror cannot read it, so the "
				+ "prediction below is suppressed rather than shown wrong.[/color]")

	out.append("[b]h[/b]  %.5f  ->  [b]%.5f[/b]   (%+.4f mm this step)"
			% [h, h_new, (h_new - h) * 1000.0])
	if _pred_line != "":
		out.append(_pred_line)
	_report.text = "\n".join(out)
	_pred_at = Vector2i(-1, -1) if poked else _pick
	_pred_e = h_new


# ------------------------------------------------- the staggered mirror ------------------------
#
# A second implementation of step_staggered(), face by face, in the shader's own order. Same
# contract as the other two mirrors: it predicts h for the next step and the next inspection prints
# how far the GPU landed from it, so this panel cannot quietly become fiction.
#
# THE SCROLL IS ASSUMED ZERO. The bench pins its focus, so the window never moves and a window
# index IS a state index. In the game it would not be, and this file is a bench instrument.

## The state at a window texel, clamped. The shader's stw().
func _stw(w: Vector2i, res: int) -> Color:
	if _state_img == null:
		return Color(0, 0, 0, 0)
	return _state_img.get_pixel(clampi(w.x, 0, res - 1), clampi(w.y, 0, res - 1))


func _depth_at(w: Vector2i, res: int) -> float:
	return maxf(_stw(w, res).r, 0.0)


func _surf_at(w: Vector2i, res: int) -> float:
	return _bed_at(w, res) + _depth_at(w, res)


## LISFLOOD's face depth on the face OWNED by cell w, in axis 0 (x) or 1 (y).
func _hf(w: Vector2i, res: int, axis: int) -> float:
	var a := w - (Vector2i(1, 0) if axis == 0 else Vector2i(0, 1))
	var ba := _bed_at(a, res)
	var bb := _bed_at(w, res)
	return maxf(0.0, maxf(ba + _depth_at(a, res), bb + _depth_at(w, res)) - maxf(ba, bb))


## The CFL guard's effective gravity for a face carrying hfc.
func _g_at(hfc: float, dx: float, dt: float) -> float:
	var g: float = Ripples.GRAVITY
	if not _rip_bool(&"cfl_guard", true):
		return g
	var kap := g * hfc * dt * dt / (dx * dx)
	return g * minf(1.0, _simf(&"cfl_max", 0.20) / maxf(kap, 1e-9))


## The NEW velocity on the face owned by cell w, axis 0 = x, 1 = y. The shader's mom_x / mom_y.
func _mom(w: Vector2i, res: int, axis: int, dx: float, dt: float) -> float:
	var i := w.x if axis == 0 else w.y
	if i <= 0 or i >= res:
		return 0.0                        # the domain rim: a face that does not exist
	var hfc := _hf(w, res, axis)
	if hfc <= 0.0:
		return 0.0
	var back := w - (Vector2i(1, 0) if axis == 0 else Vector2i(0, 1))
	var c := _stw(w, res)
	var u: float = c.g if axis == 0 else c.b
	u += -_g_at(hfc, dx, dt) * (_surf_at(w, res) - _surf_at(back, res)) / dx * dt
	u *= exp(-_simf(&"drag", 0.7) * dt)
	var manning := _simf(&"manning", 0.03)
	u /= (1.0 + dt * Ripples.GRAVITY * manning * manning * absf(u)
			/ pow(maxf(hfc, _simf(&"h_fric", 0.0005)), 4.0 / 3.0))
	var u_max := _simf(&"u_max", 3.0)
	return clampf(u, -u_max, u_max)


## The discharge across the face owned by cell w. The shader's qx / qy.
func _q(w: Vector2i, res: int, axis: int, dx: float, dt: float) -> float:
	var u := _mom(w, res, axis, dx, dt)
	var hfc := _hf(w, res, axis)
	var back := w - (Vector2i(1, 0) if axis == 0 else Vector2i(0, 1))
	var hdon := _depth_at(back, res) if u > 0.0 else _depth_at(w, res)
	var g: float = Ripples.GRAVITY
	var cap := minf(_simf(&"weir_cd", 1.0) * sqrt(g * hfc) * hfc, hdon * dx / (4.0 * dt))
	return clampf(minf(hfc, hdon) * u, -cap, cap)


func _inspect_staggered(res: int) -> void:
	var dx: float = Ripples.SIZE_M / float(res)
	var dt := 1.0 / 60.0
	var spring := _spring_at(_pick, res)
	var Y := _rest_y_at(_pick, res)
	var b := _bed_at(_pick, res)
	var org: Vector2 = Ripples.window_origin()
	var world := org + Vector2(_pick.x + 0.5, _pick.y + 0.5) * dx
	var s := _stw(_pick, res)
	var h := maxf(s.r, 0.0)

	var out := PackedStringArray()
	out.append("[b]cell[/b] (%d, %d)   world (%.2f, %.2f)   dx %.3f m   dt %.4f s   [b]STAGGERED[/b]"
			% [_pick.x, _pick.y, world.x, world.y, dx, dt])
	out.append("[b]terrain[/b]  bed b %+.4f   rest Y %+.4f   -> rest depth %.4f%s"
			% [b, Y, maxf(Y - b, 0.0), "   [color=#6f6]SPRING[/color]" if spring > 0.5 else ""])
	out.append("[b]state[/b]    h %.4f m   u(left) %+.4f   v(bottom) %+.4f   foam %.3f   w %+.4f"
			% [h, s.g, s.b, s.a, b + h])

	# ---- the four faces, each with its own depth, gravity and new velocity.
	var names := ["left  (i-1/2)", "right (i+1/2)", "bottom (j-1/2)", "top   (j+1/2)"]
	var cells := [_pick, _pick + Vector2i(1, 0), _pick, _pick + Vector2i(0, 1)]
	var axes := [0, 0, 1, 1]
	out.append("[b]faces[/b]  hf = max(0, max(w, w_n) - max(b, b_n));  "
			+ "a face at the domain rim does not exist")
	var qv := PackedFloat32Array([0, 0, 0, 0])
	for i in 4:
		var hfc := _hf(cells[i], res, axes[i])
		var uu := _mom(cells[i], res, axes[i], dx, dt)
		qv[i] = _q(cells[i], res, axes[i], dx, dt)
		var idx: int = cells[i].x if axes[i] == 0 else cells[i].y
		var why := ""
		if idx <= 0 or idx >= res:
			why = "  [color=#c96]RIM: no face here[/color]"
		elif hfc <= 0.0:
			why = "  [color=#c96]CLOSED (hf 0)[/color]"
		out.append("  %s  hf %.5f   g_eff %.3f   u %+.5f   q %+.6f m2/s%s"
				% [names[i], hfc, _g_at(hfc, dx, dt), uu, qv[i], why])

	# ---- continuity. No Laplacian - the velocity being fluxed is already the new one.
	var divq := ((qv[1] - qv[0]) + (qv[3] - qv[2])) / dx
	var d_transport := -dt * divq
	var h_new := h + d_transport
	out.append("[b]continuity[/b]  h_new = h - dt * ((qr - ql) + (qt - qb)) / dx"
			+ "   [color=#888](no lap(w): the flux already uses the NEW u)[/color]")
	out.append("  div(q) %+.5f /s   -> %+.6f m  (%+.4f mm)"
			% [divq, d_transport, d_transport * 1000.0])

	var d_spring := spring * _simf(&"spring_rate", 0.06) * dt
	h_new += d_spring
	if spring > 0.5:
		out.append("[b]source[/b]  %+.6f m" % d_spring)
	var seep := _simf(&"seep", 0.001)
	var before_seep := h_new
	h_new = maxf(h_new - seep * dt, 0.0)
	if seep > 0.0:
		out.append("[b]seep[/b]  %.5f m/s  -> %+.6f m" % [seep, h_new - before_seep])

	var ucen := Vector2(0.5 * (_mom(_pick, res, 0, dx, dt)
					+ _mom(_pick + Vector2i(1, 0), res, 0, dx, dt)),
			0.5 * (_mom(_pick, res, 1, dx, dt) + _mom(_pick + Vector2i(0, 1), res, 1, dx, dt)))
	var Fr := ucen.length() / sqrt(Ripples.GRAVITY * maxf(h_new, 0.05))
	out.append("[b]cell velocity[/b] (%+.4f, %+.4f) = the mean of the faces either side   "
			% [ucen.x, ucen.y] + "[b]Froude[/b] %.3f  %s"
			% [Fr, "[color=#f96]supercritical[/color]" if Fr > 1.0 else "subcritical"])

	var sink_d := (Vector2(world.x, world.y)
			- (Vector2(_bed.global_position.x, _bed.global_position.z) + _sink_at)).length()
	var poked := _sink_on and sink_d < _sink_radius * 2.0
	if poked:
		out.append("[color=#fc6][b]impulse[/b]  inside the sink, which reaches the solver through "
				+ "the private impulse queue - prediction suppressed rather than shown wrong.[/color]")

	out.append("[b]h[/b]  %.5f  ->  [b]%.5f[/b]   (%+.4f mm this step)"
			% [h, h_new, (h_new - h) * 1000.0])
	if _pred_line != "":
		out.append(_pred_line)
	_report.text = "\n".join(out)
	_pred_at = Vector2i(-1, -1) if poked else _pick
	_pred_e = h_new


func _has_step(wet: PackedFloat32Array, dYn: PackedFloat32Array, eps: float) -> bool:
	for i in 4:
		if wet[i] > 0.5 and absf(dYn[i]) > eps:
			return true
	return false


## THE SELF-CHECK. Called before the mirror recomputes: compare the eta it predicted last time
## against what the GPU actually wrote at that texel. Disagreement beyond a few float16 ulps means
## this file has drifted from the shader, and the report says so rather than looking authoritative.
func _check_prediction() -> void:
	if _pred_at.x < 0 or _state_img == null:
		_pred_line = ""
		return
	if _pred_at.x >= _state_img.get_width() or _pred_at.y >= _state_img.get_height():
		_pred_line = ""
		return
	var actual := _state_img.get_pixel(_pred_at.x, _pred_at.y).r
	var d: float = actual - _pred_e
	if absf(d) <= MIRROR_TOL:
		_pred_line = "[color=#6c6]mirror ok[/color]  predicted %+.5f, GPU wrote %+.5f  (%+.2f mm)" \
				% [_pred_e, actual, d * 1000.0]
	else:
		_pred_line = ("[color=#f66][b]MIRROR DRIFT[/b][/color]  predicted %+.5f, GPU wrote "
				+ "%+.5f  (%+.2f mm) - this panel disagrees with the shader") % [_pred_e, actual,
				d * 1000.0]


# ------------------------------------------------------------------------------------ UI ------

func _build_ui() -> void:
	var box := Tuning.build_panel(self, 330, 700)

	Tuning.header(box, "BED")
	Tuning.option(box, "profile", PackedStringArray(["flat pan", "valley (V, graded)",
			"terraces (3 steps)", "bowl (no outlet)", "ramp (tilted pan)",
			"RIVER (meander, fast inflow)", "BEACH (waves from the ocean)",
			"WATERFALL (pools and lips)"]), int(_bed.get("profile")),
			func(i: int) -> void:
				_bed.set("profile", i)
				_apply_profile_defaults(i)
				_rebuild()
				_reset(i >= 5))
	Tuning.line(box, "the last three carry their own boundary and source - a bed alone is not a "
			+ "river", Color(0.6, 0.7, 0.85))
	Tuning.slider(box, "bed_depth  m", 0.15, 1.40, 0.05, _bed.get("bed_depth"),
			func(v: float) -> void:
				_bed.set("bed_depth", v)
				_rebuild()
				_reset(true))
	Tuning.slider(box, "grade  m/m (valley)", 0.0, 0.12, 0.005, _bed.get("grade"),
			func(v: float) -> void:
				_bed.set("grade", v)
				_rebuild()
				_reset(true))

	Tuning.header(box, "RUN")
	Tuning.check(box, "paused", Ripples.paused, func(on: bool) -> void: Ripples.paused = on)
	var row := HBoxContainer.new()
	box.add_child(row)
	for n in [1, 10, 60]:
		var b := Button.new()
		b.text = "step %d" % n
		b.pressed.connect(func() -> void: _do_steps(n))
		row.add_child(b)
	Tuning.button(box, "reset EMPTY  (bed dry)", func() -> void: _reset(true))
	Tuning.button(box, "reset FULL  (water at rest)", func() -> void: _reset(false))
	Tuning.check(box, "read back while running", _live,
			func(on: bool) -> void: _live = on)

	Tuning.header(box, "SOURCE  (a painted spring)")
	Tuning.check(box, "source on", _source_on, func(on: bool) -> void:
		_source_on = on
		_rebuild())
	_knob_num(box, &"spring_rate", 0.002, "metres of head per second, at each spring cell")

	Tuning.slider(box, "source radius  m", 1.0, 12.0, 0.5, _source_radius,
			func(v: float) -> void:
				_source_radius = v
				_rebuild())

	Tuning.header(box, "SINK  (a continuous drain)")
	Tuning.check(box, "sink on", _sink_on, func(on: bool) -> void: _sink_on = on)
	Tuning.slider(box, "drain  m/s of head", 0.0, 2.0, 0.01, _sink_rate,
			func(v: float) -> void: _sink_rate = v)
	Tuning.slider(box, "drain radius  m", 0.5, 8.0, 0.25, _sink_radius,
			func(v: float) -> void: _sink_radius = v)

	Tuning.header(box, "OBSTACLES  (alt-click the water to drop one, drag to move)")
	Tuning.option(box, "shape", PackedStringArray(["cylinder", "box"]), _obs_kind,
			func(i: int) -> void: _obs_kind = i)
	Tuning.button(box, "clear all", func() -> void: _clear_obstacles())
	Tuning.line(box, "    a solid RAISES THE BED inside its footprint, so the no-flow wall and "
			+ "the dry interior both fall out of the face depth", Color(0.6, 0.7, 0.85))

	Tuning.header(box, "SOLVER")
	Tuning.check(box, "depth mode  (h over a bed)", Ripples.depth_mode, func(on: bool) -> void:
		Ripples.depth_mode = on
		_reset(true))
	Tuning.line(box, "    off = the shipped solver: eta, a deviation from a flat rest surface",
			Color(0.95, 0.78, 0.40))
	Tuning.check(box, "walls  (a closed box)", Ripples.edge_mode == 1, func(on: bool) -> void:
		Ripples.edge_mode = 1 if on else 0)
	Tuning.line(box, "    off = horizon: the rim fades to the rest depth, as the game needs",
			Color(0.95, 0.78, 0.40))
	Tuning.check(box, "STAGGERED  (velocity on the faces)", Ripples.staggered,
			func(on: bool) -> void:
				Ripples.staggered = on
				_reset(false))
	Tuning.line(box, "    off = collocated: velocity at the cell centre, and a Laplacian holding "
			+ "the grid-scale mode down", Color(0.95, 0.78, 0.40))
	Tuning.check(box, "smooth bed  (bilinear, not a staircase)", _rip_bool(&"bed_smooth", true),
			func(on: bool) -> void:
				Ripples.sim_set(&"bed_smooth", on)
				_reset(false))
	Tuning.line(box, "    off = nearest: 1.3 cm risers on a 3% beach, and a front cannot climb one",
			Color(0.95, 0.78, 0.40))
	Tuning.line(box, "shift-click the overlay to move the SOURCE, ctrl-click for the SINK",
			Color(0.6, 0.7, 0.85))
	_knob(box, &"gravity", 1.0, 20.0, 0.1)
	_knob(box, &"drag", 0.0, 4.0, 0.05)
	_knob_num(box, &"manning", 0.005)
	_knob(box, &"u_max", 0.5, 8.0, 0.1)
	_knob(box, &"weir_cd", 0.0, 1.2, 0.01)
	_knob(box, &"tier_eps", 0.05, 1.5, 0.05)
	_knob_num(box, &"h_dry", 0.001)
	_knob_num(box, &"h_wet", 0.005)
	_knob_num(box, &"h_min", 0.001)
	_knob_num(box, &"h_fric", 0.0001,
			"the depth Manning may see. Raising it to h_min re-creates wet_ramp by other means.")
	_knob(box, &"poke_frac", 0.05, 1.0, 0.05)
	# The two overridden ones, last and labelled, so the override cannot pass unnoticed.
	_knob_num(box, &"eta_keep", 0.0005,
			"1.0 here; 0.999 ships. Below rest this SOURCES, at 0.06*H0 per second.")
	_knob(box, &"draw_max", 0.1, 1.0, 0.05, "1.0 here; 0.55 ships. Below 1 a basin cannot empty.")
	Tuning.check(box, "weirs_on", Ripples.weirs, func(on: bool) -> void:
		Ripples.weirs = on)
	Tuning.check(box, "advect (momentum self-advection)", Ripples.advect,
			func(on: bool) -> void: Ripples.advect = on)

	Tuning.header(box, "FOAM")
	_knob(box, &"foam_decay", 0.0, 6.0, 0.1)
	_knob(box, &"foam_jump", 0.0, 8.0, 0.1)
	_knob(box, &"foam_crest", 0.0, 8.0, 0.1)
	_knob(box, &"foam_plunge", 0.0, 12.0, 0.1)

	# A uniform with no row is a uniform that has silently stopped being tunable. Naming them
	# costs one line and means a knob added to the shader next month announces itself instead of
	# rotting unnoticed — the exact failure tuning_panel.gd's reflection builders exist to avoid.
	_list_unknobbed(box)
	_build_right_panel()
	_hint()


## One slider bound to a live sim uniform on BOTH ping-pong halves, starting from whatever the
## solver is actually using.
func _knob(box: VBoxContainer, name_: StringName, lo: float, hi: float, step: float,
		note := "") -> void:
	var cur: Variant = Ripples.sim_get(name_)
	if cur == null:
		Tuning.line(box, "%s  (absent from the shader)" % name_, Color(1.0, 0.5, 0.4))
		return
	Tuning.slider(box, String(name_), lo, hi, step, cur,
			func(v: float) -> void: Ripples.sim_set(name_, v))
	if note != "":
		Tuning.line(box, "    " + note, Color(0.95, 0.78, 0.40))


## The same, as a typed number. For the knobs whose working values are smaller than the slider
## label's two decimals: h_dry is 0.002 and eta_keep is 0.999, and both render as a caption that
## reads "0.00" and "1.00" - a control that lies about its own value is worse than none.
func _knob_num(box: VBoxContainer, name_: StringName, step: float, note := "") -> void:
	var cur: Variant = Ripples.sim_get(name_)
	if cur == null:
		Tuning.line(box, "%s  (absent from the shader)" % name_, Color(1.0, 0.5, 0.4))
		return
	Tuning.number(box, String(name_), float(cur), step,
			func(v: float) -> void: Ripples.sim_set(name_, v))
	if note != "":
		Tuning.line(box, "    " + note, Color(0.95, 0.78, 0.40))


## PLUMBING AND TEST RIGGING, not tuning. Everything here is either bound by the driver from a
## GDScript constant, or a stimulus a probe sets and a person never would. Leaving them out of the
## list is not hiding them: the list exists to catch a knob somebody FORGOT, and a list that cries
## wolf is one nobody reads. (It also has to stay short. Six new uniforms landed in it at once and
## the panel widened to fit the line, covering half the 3D view - which the screenshot probe caught
## as "full and empty look the same", because the water it was counting was behind the UI.)
const _NO_KNOB_NEEDED := ["prev", "field", "field_n", "res", "dx", "dt", "window_m", "scroll_uv",
		"impulse_count", "impulses", "reset", "reset_empty", "diag", "dry_y", "spring_mark",
		"advect_gain", "weirs_on", "bed", "field_res", "bed_wall_min", "depth_mode", "edge_mode",
		"jitter", "seed_kind", "seed_p"]


func _list_unknobbed(box: VBoxContainer) -> void:
	var sh: Shader = load("res://addons/sim_water/shaders/swe_sim.gdshader")
	if sh == null:
		return
	var missing := PackedStringArray()
	for entry: Dictionary in sh.get_shader_uniform_list(true):
		var nm := String(entry.get("name", ""))
		if nm == "" or _NO_KNOB_NEEDED.has(nm):
			continue
		if not _has_knob(box, nm):
			missing.append(nm)
	if missing.is_empty():
		return
	Tuning.header(box, "NO KNOB YET")
	Tuning.line(box, ", ".join(missing) + "  — added to the shader since this panel was written",
			Color(1.0, 0.65, 0.4))


## RECURSIVE, because Tuning.number() nests its caption inside an HBox - a flat scan would report
## every SpinBox knob as missing and the "no knob yet" list would cry wolf until nobody read it.
func _has_knob(box: Node, nm: String) -> bool:
	for c in box.get_children():
		var l := c as Label
		if l != null and (l.text == nm or l.text.begins_with(nm + "  ")):
			return true
		if _has_knob(c, nm):
			return true
	return false


## The right-hand column: the false-colour view of the solver, and the cell report under it.
func _build_right_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -(VIEW_PX + 26)
	panel.offset_right = -12
	panel.offset_top = 12
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	bg.content_margin_left = 8
	bg.content_margin_right = 8
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", bg)
	layer.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	Tuning.option(col, "", PackedStringArray(MODES), _mode, func(i: int) -> void:
		_mode = i
		_view_mat.set_shader_parameter("mode", i)
		_view_mat.set_shader_parameter("ramp", MODE_RAMP[i]))

	_view_mat = ShaderMaterial.new()
	_view_mat.shader = VIEW_SHADER
	_view_mat.set_shader_parameter("mode", _mode)
	_view_mat.set_shader_parameter("ramp", MODE_RAMP[_mode])
	# The viewer and the solver are configured from the SAME constants, so a view that disagrees
	# with the sim is impossible by construction rather than by care.
	_view_mat.set_shader_parameter("gravity", Ripples.GRAVITY)
	_view_mat.set_shader_parameter("dry_y", Ripples.DRY_Y)
	_view_mat.set_shader_parameter("spring_mark", Ripples.SPRING_MARK)
	_view_mat.set_shader_parameter("tier_eps", _simf(&"tier_eps", 0.5))
	_view_mat.set_shader_parameter("res", float(Ripples.RES))
	_view_mat.set_shader_parameter("field_res", float(Ripples.FIELD_RES))
	_view_mat.set_shader_parameter("dx", Ripples.SIZE_M / float(Ripples.RES))

	_view = TextureRect.new()
	_view.custom_minimum_size = Vector2(VIEW_PX, VIEW_PX)
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.material = _view_mat
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	col.add_child(_view)

	Tuning.check(col, "terrain grid (0.5 m)", false,
			func(on: bool) -> void: _view_mat.set_shader_parameter("show_grid", on))
	_status = Tuning.line(col, "", Color(0.85, 0.9, 1.0))
	_report = Tuning.log_pane(col, 300)
	_report.custom_minimum_size = Vector2(VIEW_PX, 300)


## A click on the overlay is a click in the WORLD: the window origin plus texel size, which is
## exactly how the sim shader maps its own UV. Shift moves the source, ctrl the sink, and a plain
## click inspects.
func _on_view_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var uv := mb.position / _view.size
	var res: int = Ripples.RES
	var texel := Vector2i(clampi(int(uv.x * res), 0, res - 1), clampi(int(uv.y * res), 0, res - 1))
	var org: Vector2 = Ripples.window_origin()
	var world := org + Vector2(texel) * (Ripples.SIZE_M / float(res))
	var local3 := _bed.to_local(Vector3(world.x, 0.0, world.y))
	if mb.shift_pressed:
		_source_at = Vector2(local3.x, local3.z)
		_source_on = true
		_rebuild()
	elif mb.ctrl_pressed:
		_sink_at = Vector2(local3.x, local3.z)
		_sink_on = true
	else:
		_pick = texel
		_view_mat.set_shader_parameter("pick_uv", Vector2(texel) / float(res))
		_read_back()
		_check_prediction()
		_inspect()


func _refresh_status() -> void:
	if _status == null:
		return
	if _view != null:
		_view.texture = Ripples.debug_texture()
		_view_mat.set_shader_parameter("field", Ripples.field_texture())
		_view_mat.set_shader_parameter("field_n", Ripples.field_texture())
		_view_mat.set_shader_parameter("bed", Ripples.bed_texture())
		_view_mat.set_shader_parameter("depth_mode", Ripples.depth_mode)
		_view_mat.set_shader_parameter("staggered", Ripples.staggered)
	_status.text = "%s · %s   step %d %s   %.1f m3 (%+.2f m3/s)   wet %.0f m2   src %s sink %s" % [
			"DEPTH h" if Ripples.depth_mode else "eta",
			"box" if Ripples.edge_mode == 1 else "horizon",
			Ripples.debug_steps, "PAUSED" if Ripples.paused else "running",
			_volume, _vol_rate, _wet_area,
			"on" if _source_on else "off", "on" if _sink_on else "off"]
	_status.text += "   bake %.1f ms" % Ripples.bake_ms
	# HOW CLOSE THE SOLVER IS TO DYING, which nothing used to say.
	#
	# The scheme is explicit and its limit is kappa = g*h*dt^2/dx^2 < 0.25. Past that the grid-scale
	# mode doubles every few steps and the float16 state SATURATES at 65504 - it does not go NaN, it
	# does not go infinite, it just stops being water and stays that way. And the configuration this
	# bench opens in is a source running into a closed box, which has no steady state at all: the
	# level rises for as long as you let it, so leaving the scene running IS a slow walk to the
	# cliff. It arrived silently.
	#
	# Reported as a PERCENTAGE OF THE LIMIT rather than as kappa, because 0.19 means nothing to
	# somebody watching a basin fill and "76% of CFL" means exactly one thing.
	var dxm: float = Ripples.SIZE_M / float(Ripples.RES)
	var kap: float = Ripples.GRAVITY * _deepest * (1.0 / 3600.0) / (dxm * dxm)
	var frac := kap / 0.25
	_status.text += "   deepest %.2f m = %.0f%% of CFL" % [_deepest, frac * 100.0]
	if frac >= 1.0:
		_status.text += "  ** UNSTABLE: the state is dead and will not recover **"
	elif frac > 0.75:
		_status.text += "  ** approaching the limit **"
	_status.add_theme_color_override("font_color",
			Color(1.0, 0.35, 0.3) if frac >= 1.0
			else (Color(1.0, 0.78, 0.35) if frac > 0.75 else Color(0.82, 0.84, 0.88)))


func _hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 39
	add_child(layer)
	var l := Label.new()
	l.text = ("SWE lab - CLICK THE WATER to poke it - SPACE run/pause - N step - M step 10"
			+ " - R reset EMPTY - T reset FULL - 1-9,0 view - click the overlay to inspect a cell")
	l.position = Vector2(352.0, 12.0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 0.7))
	layer.add_child(l)


func _unhandled_input(event: InputEvent) -> void:
	# POKE THE WATER. A bench about waves with no way to make one can only ever show you a pond
	# settling; this is the difference between watching the solver and using it. Left click in the
	# 3D view drops a stone. It reaches _unhandled_input only when no panel took the click first,
	# so the sliders keep working.
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		var hit := _pick_world(mb.position)
		if is_nan(hit.x):
			return
		if not mb.pressed:
			_obs_drag = -1
			return
		# ALT-CLICK SPAWNS a solid, and a plain click on one GRABS it. Shift and ctrl were already
		# taken by the source and the sink, and a bench whose controls collide is a bench that
		# moves the wrong thing while you are looking at something else.
		if mb.alt_pressed:
			_spawn_obstacle(hit)
		else:
			_obs_drag = _obstacle_at(hit)
			if _obs_drag < 0:
				Ripples.splash(hit, 1.2, 0.10)
		get_viewport().set_input_as_handled()
		return
	# DRAGGING. The obstacle list is moved and the mesh follows it, never the reverse: the solver's
	# idea of where the solid is has to be the one that is true.
	var mm := event as InputEventMouseMotion
	if mm != null and _obs_drag >= 0:
		var to := _pick_world(mm.position)
		if not is_nan(to.x):
			Ripples.obstacle_move(_obs_drag, Vector2(to.x, to.z))
			_sync_obstacles()
			get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			Ripples.paused = not Ripples.paused
		KEY_N:
			await _do_steps(1)
		KEY_M:
			await _do_steps(10)
		KEY_R:
			await _reset(true)
		KEY_T:
			await _reset(false)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_mode = key.keycode - KEY_1
			_view_mat.set_shader_parameter("mode", _mode)
			_view_mat.set_shader_parameter("ramp", MODE_RAMP[_mode])
		# 0 rather than 10, because the row of number keys runs out at 9 and the label says so.
		KEY_0:
			_mode = 9
			_view_mat.set_shader_parameter("mode", _mode)
			_view_mat.set_shader_parameter("ramp", MODE_RAMP[_mode])
		_:
			return
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ OBSTACLES ----------------
#
# SPAWN A SOLID AND DRAG IT THROUGH THE WATER.
#
# The mesh and the solver's idea of the shape are built from ONE description - the dictionary
# Ripples.obstacles() hands back - so the picture and the physics cannot drift apart. That matters
# more here than anywhere else in the bench: an obstacle is the one thing whose position you judge
# entirely by eye, so a half-metre disagreement between the cylinder you can see and the cylinder
# the water feels would read as a solver bug forever.

## Metres. A 4 m cylinder is 20 state texels across, which is the smallest thing that can shed a
## wake this grid can resolve at all - below about ten texels the separation points are one cell
## apart and what comes off is the grid, not the flow.
const OBSTACLE_SIZE := 4.0
## How far the top stands above the rest surface. Above it, so the solid is a genuine no-flow
## boundary rather than a submerged reef the water flows over.
const OBSTACLE_HEIGHT := 1.5

var _obs_kind := 0                            ## 0 cylinder, 1 box
var _obs_meshes: Dictionary = {}              ## id -> MeshInstance3D
var _obs_drag := -1                           ## the obstacle currently under the mouse


## EACH PROFILE BRINGS ITS OWN BOUNDARY AND ITS OWN SOURCE, because a bed on its own is not a
## river. A meander with walls at both ends is a pond with a wiggle in it; a beach with no ocean is
## a slope; a waterfall with no supply runs for four seconds and stops. The three new profiles are
## SCENARIOS, and the terrain is only one third of each.
##
## Set here rather than baked into swe_lab_bed.gd on purpose: the bed node answers the water
## contract and knows nothing about solvers, and it should stay that way.
func _apply_profile_defaults(i: int) -> void:
	match i:
		5:      # RIVER - fast water in at -X, free to leave at +X
			# THE BED MUST BE THE WHOLE WINDOW, or the inflow is injected into a wall. The bench
			# bed is 48 m inside a 64 m window and water_bed_y answers the 1000 m off-map sentinel
			# outside it - so there is an 8 m ring of wall INSIDE the solver domain on every side,
			# the inflow face at the window edge has hf = 0 against it, and q = min(hf, h)*u
			# delivers exactly nothing. Every channel run was a closed box coasting on its seed.
			_bed.set("extent", Ripples.SIZE_M)
			Ripples.edge_mode = 2
			Ripples.sim_set(&"inflow_u", 1.6)
			Ripples.sim_set(&"wave_amp", 0.0)
			_source_on = false
			_sink_on = false
		6:      # BEACH - the ocean end makes waves, the beach end absorbs nothing and runs them up
			_bed.set("extent", Ripples.SIZE_M)
			Ripples.edge_mode = 3
			Ripples.sim_set(&"inflow_u", 0.0)
			Ripples.sim_set(&"wave_amp", 0.10)
			Ripples.sim_set(&"wave_period", 4.0)
			_source_on = false
			_sink_on = false
		7:      # WATERFALL - a closed box with a spring on the TOP terrace, which is the whole
				# reason a spring had to be allowed to stand on dry ground
			Ripples.edge_mode = 1
			Ripples.sim_set(&"wave_amp", 0.0)
			_source_at = Vector2(-18.0, 0.0)
			_source_radius = 5.0
			_source_on = true
			_sink_on = false
		_:
			# Back to a bed inside a wall ring, which is what a closed basin wants.
			_bed.set("extent", 48.0)
			Ripples.edge_mode = 1
			Ripples.sim_set(&"inflow_u", 0.0)
			Ripples.sim_set(&"wave_amp", 0.0)
			_source_at = Vector2.ZERO
			_source_radius = 4.0


func _spawn_obstacle(at: Vector3) -> void:
	var top: float = float(_bed.get("rest_y")) + OBSTACLE_HEIGHT
	var half := OBSTACLE_SIZE * 0.5
	var id: int = Ripples.obstacle_add(_obs_kind, Vector2(at.x, at.z),
			Vector2(half, half), _bed.global_position.y + top)
	if id < 0:
		return
	var mi := MeshInstance3D.new()
	if _obs_kind == 0:
		var cy := CylinderMesh.new()
		cy.top_radius = half
		cy.bottom_radius = half
		# Tall enough to stand from well under the bed to the declared top, so the visible solid
		# looks planted rather than floating.
		cy.height = OBSTACLE_HEIGHT + 4.0
		mi.mesh = cy
	else:
		var bx := BoxMesh.new()
		bx.size = Vector3(OBSTACLE_SIZE, OBSTACLE_HEIGHT + 4.0, OBSTACLE_SIZE)
		mi.mesh = bx
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.40, 0.28)
	m.roughness = 0.85
	mi.material_override = m
	add_child(mi)
	_obs_meshes[id] = mi
	_sync_obstacles()


func _clear_obstacles() -> void:
	Ripples.obstacle_clear()
	for mi: MeshInstance3D in _obs_meshes.values():
		mi.queue_free()
	_obs_meshes.clear()
	_obs_drag = -1


## Put every mesh where its obstacle is. Called after a spawn and on every drag frame - never the
## other way round, so the solver's list stays the single source of truth about where a solid is.
func _sync_obstacles() -> void:
	for o: Dictionary in Ripples.obstacles():
		var mi: MeshInstance3D = _obs_meshes.get(int(o.id))
		if mi == null:
			continue
		var at: Vector2 = o.at
		# The mesh is centred on its own height, so drop it by half to put its TOP at o.top.
		mi.global_position = Vector3(at.x, float(o.top) - (OBSTACLE_HEIGHT + 4.0) * 0.5, at.y)
		mi.rotation.y = float(o.rot)


## The obstacle under a world point, or -1. Radius test for both shapes, which is generous for a
## box by a corner - grabbing is a UI affordance, not a physics query.
func _obstacle_at(p: Vector3) -> int:
	for o: Dictionary in Ripples.obstacles():
		var at: Vector2 = o.at
		var sz: Vector2 = o.size
		if (Vector2(p.x, p.z) - at).length() <= maxf(sz.x, sz.y) * 1.4:
			return int(o.id)
	return -1

## Where a screen point meets the water, in world space - NAN if it meets nothing. The ray is
## intersected with the horizontal plane at the bed's rest level rather than with the surface mesh:
## the mesh is displaced entirely in the vertex shader, so it has no collision and its CPU-side
## geometry is a flat plane anyway. At bench depths the two differ by centimetres.
func _pick_world(screen: Vector2) -> Vector3:
	if _cam == null:
		return Vector3(NAN, NAN, NAN)
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	var plane_y: float = _bed.global_position.y + float(_bed.get("rest_y"))
	if absf(dir.y) < 1e-5:
		return Vector3(NAN, NAN, NAN)
	var t := (plane_y - from.y) / dir.y
	if t <= 0.0:
		return Vector3(NAN, NAN, NAN)
	return from + dir * t


func _exit_tree() -> void:
	# The autoload outlives the bench. Leaving the window pinned to a freed node, or the sim
	# paused, would silently break whatever scene runs next in the same session.
	Ripples.focus_override = null
	Ripples.paused = false
	Ripples.reset_empty = false

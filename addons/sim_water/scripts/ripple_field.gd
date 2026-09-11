extends Node
## THE WATER SOLVER (autoload "Ripples", and it keeps that name because splash() is its public
## face): a camera-following SHALLOW WATER simulation the water surface samples in world space.
##
## It replaces two earlier solvers and that is the point. The ripple field evolved a height
## with no velocity; the flow field evolved a velocity with no height. Everything that was
## missing from the water — a bore, the drawdown at a lip, foam that gathers where it should,
## a wake that is part of the same fluid as the waves — is exactly the coupling between the
## two, and SWE's state IS (height, velocity). One RGBA texture, one pass, half the shader
## inputs. See shaders/swe_sim.gdshader for the numerics and why they are shaped that way.
##
##   R = eta (deviation from the region's rest level)   G,B = u' (deviation from baked u0)
##   A = foam
##
## An FX-LAYER CITIZEN, deliberately outside the generator: the wilds are keyed to WHERE and
## never WHEN, and this is the one WHEN in the water's whole stack — camera-anchored,
## transient, rebuilt from nothing in a second of damping. Nothing here feeds back into
## terrain, collision or the suites, and GAMEPLAY never reads it (Water.flow_at recomputes the
## pure function instead, so what a body feels can never drift from what the surface shows).
##
## Impulse API, unchanged across the rewrite: Ripples.splash(world_pos, radius_m, strength_m),
## strengths in METRES of downward displacement. It got SIMPLER — the old leapfrog stored two
## time levels and had to poke both, and poking one read as a velocity impulse re-applied
## forever (the black-pit bug). With u' explicit, a poke is just a poke.
##
## SLEEP: with no "water_oracle" in the tree (the crypt, the hub) both viewports stop
## rendering and the global gain goes to zero. Benches and indoor zones pay nothing.
const SIZE_M := 64.0                          ## window side, metres
## Texels per side. 320 -> 0.2 m per texel, and the number is set by the DEPTH CEILING, not by
## taste. This is an explicit scheme, so kappa = g*H*dt^2/dx^2 < 0.25, i.e. H_max = 0.25*dx^2/(g*dt^2).
## At the old 512 (dx 0.125) that is 1.43 m - measured on the bench as stable at 1.0 m and
## saturating float16 at 1.5 m, which brackets it exactly. A basin that floods past its banks wants
## about 1.75 m over this world's deep bed, so 512 could not do the one thing the depth encoding
## exists for. 320 gives 3.67 m of headroom and keeps cells at half FluXY's 0.39 m.
##
## THOSE FIGURES ARE THE COLLOCATED ONES and the paragraph above is history. Staggering the grid
## doubled the limit to kappa <= 0.5 in 2D - measured, the ceiling moved from 3.0/4.0 m to 6.0/8.0
## against a prediction of 7.34 - so every number below uses H_max = 0.5*dx^2/(g*dt^2).
##
## RES must keep 1/dx an INTEGER: the window origin snaps to whole metres, and the scroll has to
## stay an exact texel count or last step's state does not translate losslessly. 512 -> 8, 320 -> 5.
## Equivalently RES must be a multiple of SIZE_M: 448 = 64 * 7, so a metre is exactly seven texels
## and the UV shift is exactly 1/64, which IS representable.
##
## 448, AND IT IS A TRADE RATHER THAN AN UPGRADE. dx 0.1429 puts the wader's 0.9 m body across 6.3
## texels instead of 4.5 - which is the resolution the 1.2 m cylinder had when it was called
## perfect, and it is the difference between a wake that quantises as the body walks and one with
## visible transverse wavelets inside the V.
##
## WHAT IT COSTS IS THE DEPTH CEILING, QUADRATICALLY. H_max = 0.5*dx^2/(g*dt^2):
##
##   RES 320   dx 0.2      ceiling 7.34 m    the game's 1.04 m lake uses 14 %
##   RES 448   dx 0.1429   ceiling 3.74 m    28 %          <- here
##   RES 640   dx 0.1      ceiling 1.83 m    57 %
##
## 640 was measured and is stable and looks slightly better again, and 57 % of the cliff is not a
## margin worth having in a general-purpose solver: a waterfall's plunge pool or a deeper authored
## lake would sit on the CFL guard, which stays conservative but slows its waves to do it. 448
## keeps a 3.6x margin and costs about twice 320's fragments rather than four times.
##
## AND THERE IS A SECOND COST, which the bench found and the pictures could not. kappa itself scales
## as 1/dx^2, so refining moves every depth CLOSER to its stability limit, and the at-rest noise
## grows with it. Suite 7b - a lake sitting still on a 3 % ramp for 600 steps - drifts:
##
##   RES 320   worst cell  2.9 mm      against a 15 mm tolerance (CELL_TOL 6 mm x 2.5 staggered)
##   RES 448   worst cell 11.7 mm      78 % of it
##
## which puts 640, where kappa doubles again, straight through the tolerance. So the grid is not
## merely paying GPU for detail; past about here it starts paying STILLNESS for it, and stillness is
## the property the whole depth-over-bed rewrite was built to get.
##
## AND THIS IS THE ANSWER TO "MAKE THE GRID ADAPTIVE", which was asked for and which four designed
## architectures all lost to. A nested fine patch needs about five SubViewport renders per frame
## with the ORDER load-bearing, against the one-render-per-frame rule this file documents below.
## Shrinking SIZE_M cannot reach the target because the camera shows 19.3 m of ground, pinning
## SIZE_M >= 45. A graded/warped grid is provably wrong HERE rather than merely expensive: the
## scroll is an exact texel relabelling only if the cell spacing is periodic with a period dividing
## the snap distance, and a centre-clustered warp has a unique minimum, so it is periodic at no
## period and every scroll must interpolate - concentric damping rings locked to the player. It
## spends this solver's cheapest property, that a moving window costs nothing, to buy resolution the
## hardware gives away for free.
const RES := 448
const TEXEL_M := SIZE_M / RES
## SWE dials. Wave speed is no longer a dial at all — it is sqrt(g*H), which is 2.32 m/s at
## this world's 0.55 m against the 2.5 the old field was hand-tuned to (7%, imperceptible) and
## which now FALLS with depth, so rings slow and refract toward the beach for free.
const GRAVITY := 9.81
## 1/s on u'. A linear drag damps AMPLITUDE at DRAG/2, so pure drag gives a 2.0 s half-life;
## the ring's visible decay is faster than that because a spreading ring also thins
## geometrically. Chosen by sweep against the old field's measured 0.0469 at 0.6 s: 1.3 gave
## 0.035, 0.7 gives 0.044, 0.45 overshoots to 0.049.
const DRAG := 0.7
## THE SINK, and it was always here without being named: eta relaxes toward the rest surface
## at 0.06/s. Physically that is seepage and evaporation — where river water goes when it has
## no outlet — and it is what makes the terraced staircase a stable ATTRACTOR rather than
## merely a fixed point, so the lowest reach in a chain cannot fill forever.
const ETA_KEEP := 0.999
## THE SOURCE: metres of head per second injected at a painted spring cell. Sized so the reach
## above a spill settles a few centimetres proud — which is what makes the weir discharge
## continuously and the waterfall run without anybody touching the water.
const SPRING_RATE := 0.02
const MAX_IMPULSES := 16                      ## the sim shader's uniform array size
## THE TERRAIN INPUT the Shallow-Water solver reads: RG = the baked current u0, B = rest depth
## H0, A = the region's rest surface Y (or DRY_Y where there is no water at all). 64 across
## 64 m is exactly one metre per texel, which is why the window origin snaps to whole metres —
## every field texel then lands strictly inside one 2 m map cell and the tier staircase in A
## stays a clean step instead of a ramp.
## 128 across 64 m -> HALF A METRE per texel. It was 64 (one metre), and one metre is what the
## shoreline looked like: the solver runs at 0.2 m but its terrain arrives as metre-wide stair
## treads, so the waterline followed a metre staircase in plan and every tread riser drew a step in
## elevation. The field is the solver's whole knowledge of the world; it cannot resolve a shore
## finer than this however fine its own grid is.
##
## THE COST IS THE BAKE, and it is why this is 128 and not 256. A full rebake is five oracle
## queries a texel and happens on boot and on a teleport - four times as many at 128, sixteen at
## 256. Moving costs far less, because the field SHIFTS: a metre of travel rebakes two rows here
## against one before. `bake_ms` reports the real figure.
const FIELD_RES := 128
const FIELD_M := SIZE_M / FIELD_RES           ## 0.5 m
const FIELD_REFRESH_M := 1.0
## Sentinel for "no water region here". Real surfaces are tier * 1.2 - 0.35, so they never
## come near this and a plain `Y > DRY_Y + 1.0` test is unambiguous.
const DRY_Y := -1000.0
## Added to a spring cell's rest surface to flag it. Far above any real Y (tier * 1.2 - 0.35)
## and far above DRY_Y, so both tests are unambiguous and neither needs a sign.
const SPRING_MARK := 10000.0


## Master gain, published as water_ripple_rect.w — the shader's kill switch at 0.
var strength := 1.0
## The lab's wire tap: log every injection (window origin, uv, strength) to the console.
var debug_log := false
## Momentum SELF-advection. Off by default for exact parity with the field this replaced:
## the old leapfrog lost 5x amplitude to advection because its state was two time levels
## whose phase relationship WAS the wave. SWE stores one level of each variable, so there is
## no phase to destroy and the remaining cost is ordinary bilinear blur — analytically 12%/s
## on a 2 m wave. Raise it only against the harness's 0.0469-at-0.6-s baseline.
##
## Foam and the baked current are advected ALWAYS regardless: a passive scalar has nothing
## to lose, and that is where the visible transport comes from.
var advect := false
## Weirs: how water crosses a tier step. Off only for bring-up.
var weirs := true
var debug_steps := 0                          ## executed sim steps, for the harness probes
## Milliseconds spent in the last field bake, full or incremental. A resolution decision that
## cannot be measured is a resolution decision made by taste.
var bake_ms := 0.0

## ---- BENCH CONTROLS. Inert in the game; the SWE lab drives the solver through them so it
## is watching the shipping driver rather than a copy of it that can drift.
## Hold the sim still. `step_once()` then advances exactly one step, which is what makes
## `see the algorithm step by step` possible at all.
var paused := false
## Pin the window here instead of following a player. A bench has no player, and a window
## that wanders is a window whose readings cannot be compared between runs.
var focus_override: Node3D = null
## Reset the next step to an EMPTY basin (eta = -H0) rather than to a full one (eta = 0).
## The model's zero is water at rest, so emptiness is a displacement — see swe_lab_bed.gd.
var reset_empty := false
## THE DEPTH ENCODING: state R becomes h (water depth over the bed) instead of eta (deviation from
## a flat rest surface). Both solvers live in the one shader behind this flag so a bench can run
## the same experiment against each and print the difference, rather than the change landing as a
## big bang with nothing to compare against.
var depth_mode := false:
	set(v):
		if v == depth_mode:
			return
		depth_mode = v
		# The two encodings mean opposite things by the same bits: 0 is REST in one and DRY in the
		# other. Carrying a state across the switch would read as an instant flood or an instant
		# drought, so the switch reseeds.
		reset_now()
## Boundary: 0 HORIZON (fade to rest at the window rim, for a window that follows a camera),
## 1 WALL (leave the rim alone and let the off-map sentinel bed reflect - a closed box),
## 2 CHANNEL (uniform inflow at -x, an absorbing sponge at +x, walls top and bottom - what a wake
## needs in order to leave, and the only mode in which a shedding frequency means anything),
## 3 OCEAN (a wave-maker at -x driving the inflow FACE VELOCITY sinusoidally, and the same sponge
## at +x; the maker's own band is NOT clamped, because the whole point is that waves come back to
## it and a clamped band would absorb every reflection).
var edge_mode := 0
## STAGE 2: velocity on the CELL FACES rather than at the cell centre, with a genuinely symplectic
## forward-backward update. Separate from depth_mode because the two say different things -
## depth_mode is about what R MEANS, this is about where G and B LIVE - and the consumers that care
## about each are different sets.
##
## Reseeds like depth_mode does, and for the same reason: the channels do not mean the same thing
## either side of the switch, so carrying a state across it would be reading a face velocity as a
## cell-centred one everywhere at once.
var staggered := false:
	set(v):
		if v == staggered:
			return
		staggered = v
		reset_now()
var _step_requested := false



# ---------------------------------------------------------------------- OBSTACLES -------------
#
# SOLIDS STANDING IN THE WATER: a cylinder or a box you can drop in and drag around.
#
# AN OBSTACLE IS A PIECE OF BED, and that one decision is why this needs almost no new code. It
# raises the effective bed inside its footprint, so:
#
#   the no-flow wall     comes free from the LISFLOOD face depth. hf = max(0, max(w,wn) -
#                        max(b,bn)) is identically zero wherever the solid stands above both
#                        surfaces, which closes the face with no branch and no special case.
#   the dry interior     comes free from the seed. max(Y - b, 0) is zero where b is the solid's top.
#   well-balancedness    is untouched, because the C-property argument never cared HOW b was
#                        produced - only that the same b seeds the state and differences it.
#
# CARRIED AS UNIFORMS IN WINDOW UV, converted here rather than in the shader - the same shape
# `impulses` already uses. Two consequences, both load-bearing. The sim shader needs no idea where
# it is in the world, which keeps a whole class of frame-mixing bug out of it. And the obstacle test
# becomes a pure function of the INTEGER TEXEL INDEX, so the two cells sharing a face cannot
# disagree about whether the solid is there - which is the property the entire conservation
# argument rests on, obtained by construction instead of by care.
#
# NOT baked into the terrain texture, which would be the obvious alternative: a full bake is tens
# of milliseconds and a dragged obstacle would need one every frame.
const MAX_OBSTACLES := 8
enum Obstacle { CYLINDER, BOX }

var _obstacles: Array[Dictionary] = []
var _obstacle_next := 1


## Drop a solid in the water. `size` is (radius, unused) for a cylinder and (half_x, half_z) for a
## box; `top_y` is the world Y of its top face - above the water for a pier, below it for a reef.
## Returns an id for obstacle_move / obstacle_remove.
## `soft` is metres of RIM over which a CYLINDER's top ramps down instead of stepping. Zero is the
## old hard-edged disc. It rides obs_a.w, which for a cylinder was redundant (packed with the same
## value as .z) and is therefore free.
##
## WHY IT EXISTS. obstacle_top() tests the texel CENTRE, so a solid covers a whole number of cells
## and that count CHANGES as it moves - the footprint breathes, by 10 % for a 0.45 m disc and 30 %
## for a 0.25 m one. Each flip displaces a cell's worth of water in a single step, and a body at
## 5 m/s crosses a cell about 35 times a second, so the bow gets a train of pulses: one-cell spikes
## standing half a metre proud of a metre-deep lake. A ramped rim adds each cell gradually instead.
func obstacle_add(kind: int, world_xz: Vector2, size: Vector2, top_y: float, rot := 0.0,
		soft := 0.0) -> int:
	if _obstacles.size() >= MAX_OBSTACLES:
		push_warning("Ripples: MAX_OBSTACLES reached; ignoring")
		return -1
	var id := _obstacle_next
	_obstacle_next += 1
	_obstacles.append({"id": id, "kind": kind, "at": world_xz, "size": size,
			"top": top_y, "rot": rot, "soft": soft})
	return id


## Move (and optionally turn) a solid. This is the whole cost of dragging one: the shader reads it
## from a uniform, so nothing is rebaked and nothing is resampled.
## `top_y` is optional and NAN leaves it alone, because a solid that only ever slides is the common
## case and most callers have nothing to say about its height. A BODY WADING has: it stands in
## ankle water and then in chest water, and its top face has to keep pace with the surface or it
## stops blocking the column somewhere along the way.
func obstacle_move(id: int, world_xz: Vector2, rot := NAN, top_y := NAN) -> void:
	for o in _obstacles:
		if int(o.id) == id:
			o.at = world_xz
			if not is_nan(rot):
				o.rot = rot
			if not is_nan(top_y):
				o.top = top_y
			return


func obstacle_remove(id: int) -> void:
	for i in _obstacles.size():
		if int(_obstacles[i].id) == id:
			_obstacles.remove_at(i)
			return


func obstacle_clear() -> void:
	_obstacles.clear()


## The live list, for a bench that wants to draw a mesh matching each one. Returned by reference on
## purpose: the drawn shape and the simulated shape must come from ONE description, or the picture
## and the physics drift apart and the picture is the one you believe.
func obstacles() -> Array[Dictionary]:
	return _obstacles


## THE OBSTACLE ARRAYS, packed once, for anything that has to agree with the solver about where a
## solid is. The water surface needs them too: bed_tex carries the TERRAIN bed, a solid raises the
## EFFECTIVE bed as a shader uniform, so without this the surface believes the ground inside a cube
## is still down at lake level - and draws the lake straight across it, up its vertical faces and
## out the other side.
##
## Packed HERE rather than in each consumer, so there is one description of a solid in the project
## and not three that can drift.
func obstacle_arrays(origin: Vector2) -> Array:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for o: Dictionary in _obstacles:
		var uv: Vector2 = ((o.at as Vector2) - origin) / SIZE_M
		var sz: Vector2 = o.size
		# .w is the INNER radius for a cylinder (where the top is still full height) and the half
		# depth for a box. For a cylinder it used to be a copy of .z and carried nothing.
		var soft: float = float(o.get("soft", 0.0))
		a.append(Vector4(uv.x, uv.y, sz.x / SIZE_M,
				(maxf(sz.x - soft, 0.0) if int(o.kind) == Obstacle.CYLINDER else sz.y) / SIZE_M))
		b.append(Vector4(o.top, float(int(o.kind)), cos(o.rot), sin(o.rot)))
	var n := a.size()
	while a.size() < MAX_OBSTACLES:
		a.append(Vector4.ZERO)
		b.append(Vector4.ZERO)
	return [n, a, b]


## Push the obstacle list to a material as two vec4 arrays, in WINDOW UV.
##   a = (centre.x, centre.y, half_x, half_y)   all in window fractions
##   b = (top_y, kind, cos(rot), sin(rot))
func _bind_obstacles(mat: ShaderMaterial, origin: Vector2) -> void:
	var packed := obstacle_arrays(origin)
	mat.set_shader_parameter("obs_count", packed[0])
	mat.set_shader_parameter("obs_a", packed[1])
	mat.set_shader_parameter("obs_b", packed[2])

## Advance exactly one step while paused. Returns immediately; the step happens on the next
## rendered frame, because that is when a SubViewport can render.
func step_once() -> void:
	_step_requested = true


## Set one solver uniform on BOTH ping-pong halves. The lab tunes the live sim through this
## rather than reaching into `_mats`, and it has to be both: the halves alternate every step, so
## writing one gives a solver that uses the new value on even steps and the old on odd — which
## does not read as a mistake, it reads as a solver that half-works.
##
## NOT FOR THE UNIFORMS THIS FILE BINDS EVERY STEP, and the list is longer than it looks:
## `field`, `field_n`, `bed`, `impulses`, `impulse_count`, `scroll_uv`, `reset`, `reset_empty`,
## `jitter`, `depth_mode`, `edge_mode`, `staggered`, `wave_time`, `obs_*` - and, the one that cost
## a measurement, `advect_gain` and `weirs_on`.
##
## Those last two are bound from `advect` and `weirs` on this node, so sim_set("advect_gain", 1.0)
## is silently overwritten before the next frame renders. A probe that did exactly that ran an
## entire vortex-shedding study with the advective term switched off and concluded the scheme
## could not shed. Set the PROPERTY (`Ripples.advect = true`), not the uniform.
func sim_set(param: StringName, value: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(param, value)


## What the sim shader is currently using for `param`, falling back to the value the shader
## itself declares — so a knob the lab has never touched still reads its true starting number
## instead of null.
func sim_get(param: StringName) -> Variant:
	if _mats.is_empty():
		return null
	var v: Variant = _mats[0].get_shader_parameter(param)
	if v == null and _mats[0].shader != null:
		v = RenderingServer.shader_get_parameter_default(_mats[0].shader.get_rid(), param)
	return v


## Re-seed both halves of the ping-pong. Use after changing the bed under the solver.
func reset_now() -> void:
	_reset_steps = 2
	_field_buf = PackedFloat32Array()
	_bed_buf = PackedFloat32Array()
	_field_at = Vector2(INF, INF)

var _views: Array[SubViewport] = []
var _mats: Array[ShaderMaterial] = []
var _front := 0                               ## which viewport the world reads this frame
var _front_origin := Vector2.ZERO             ## world XZ of the front window's min corner
var _queue: Array[Dictionary] = []
var _field_tex: ImageTexture = null
var _field_at := Vector2(INF, INF)            ## window origin the field was baked for
var _field_oracle: Node = null                ## and WHICH world it was baked from

# ---------------------------------------------------------------- THE SEAM -------------------
#
# WHERE THE SIMULATION STOPS AND THE GAME STARTS.
#
# The solver integrates depth over a bed. It has no idea what a tier is, or a painted flag, or a
# region, or the wilds - and it must not learn, because the moment it does it stops being a solver
# and becomes this game's water. Everything it needs from a world is three questions, and they live
# behind `terrain` (see SweTerrain): the floor everywhere, the water level a place belongs to, and
# whether water enters here.
#
# Swap this object and the same solver runs a bench bed, a painted map, or something a zone invents.
# Nothing above this line changes.
var terrain: SweTerrain = SweTerrainOracle.new()
## The baked current u0, which the LEGACY eta encoding transports momentum with. The depth and
## staggered solvers do not read it at all, and it dies with that branch - a general solver has no
## business with a current somebody painted onto a map. Off costs one oracle query per texel.
var legacy_flow := true
var _field_buf := PackedFloat32Array()        ## authoritative CPU copy, shifted not rebuilt
## THE BED, on its own texture rather than folded into a spare channel of the one above. All
## four of those channels are spoken for, and the bed is the one quantity that must be read
## NEAREST and DIFFERENCED - the same argument that gave the tier level its own sampler, now
## applied to the channel a solver would take a gradient of. 64 squared floats is 16 KB.
var _bed_tex: ImageTexture = null
var _bed_buf := PackedFloat32Array()
var _reset_steps := 2                         ## boot: both textures must decode to still water
var _wave_t := 0.0                            ## seconds of solver time, for the wave-maker phase
var _awake := false
var _accum := 0.0                             ## real time owed to the fixed-step sim
const STEP := 1.0 / 60.0


func _ready() -> void:
	var sh := load("res://addons/sim_water/shaders/swe_sim.gdshader") as Shader
	for i in 2:
		var vp := SubViewport.new()
		vp.name = "Sim%d" % i
		vp.size = Vector2i(RES, RES)
		vp.disable_3d = true
		# RGBA16F: gentle 1 cm ripples need finer height steps than 8-bit's 8 mm banding.
		vp.use_hdr_2d = true
		# TRANSPARENT, because the ALPHA CHANNEL CARRIES FOAM. An opaque SubViewport forces
		# alpha to 1 on readback, so the foam channel came back saturated everywhere no matter
		# what the solver wrote. The two solvers this replaces both kept alpha at a constant
		# 1.0, so neither ever needed this.
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var rect := ColorRect.new()
		rect.size = Vector2(RES, RES)
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("res", RES)
		mat.set_shader_parameter("field_res", FIELD_RES)
		mat.set_shader_parameter("dx", TEXEL_M)
		mat.set_shader_parameter("dt", STEP)
		mat.set_shader_parameter("window_m", SIZE_M)
		mat.set_shader_parameter("gravity", GRAVITY)
		mat.set_shader_parameter("drag", DRAG)
		mat.set_shader_parameter("eta_keep", ETA_KEEP)
		mat.set_shader_parameter("spring_rate", SPRING_RATE)
		mat.set_shader_parameter("spring_mark", SPRING_MARK)
		mat.set_shader_parameter("dry_y", DRY_Y)
		rect.material = mat
		vp.add_child(rect)
		add_child(vp)
		_views.append(vp)
		_mats.append(mat)
	_mats[0].set_shader_parameter("prev", _views[1].get_texture())
	_mats[1].set_shader_parameter("prev", _views[0].get_texture())


## Queue one poke. Strength is METRES of downward displacement; the rebound is the ring.
func splash(world_pos: Vector3, radius := 0.5, strength_m := 0.15) -> void:
	_queue.append({"pos": Vector2(world_pos.x, world_pos.z), "radius": radius,
			"strength": strength_m})


## The front texture and window, for the lab's raw-field view.
func debug_texture() -> Texture2D:
	return _views[_front].get_texture() if not _views.is_empty() else null


func window_origin() -> Vector2:
	return _front_origin


## ONE SIM STEP PER RENDERED FRAME, NEVER PER PHYSICS TICK — the hard-won rule of this file.
## Physics regularly ticks twice inside one rendered frame (measured 81 ticks to 69 frames in
## the ripple shot harness), and a per-tick driver then flags BOTH viewports in the same
## frame: they render in sibling order, not chain order, the back step reads a stale front,
## and the Verlet chain silently drops that tick's state — and its impulses. Driving from
## _process guarantees exactly one viewport renders per frame. The accumulator keeps the
## step's dt FIXED at 1/60 (k is CFL-tuned to it): above 60 fps the sim skips frames to hold
## real-time speed; below, it caps at one step per frame and lets the waves run a little
## slow rather than tearing the chain.
func _process(delta: float) -> void:
	var focus := _focus()
	if not terrain.present() or focus == null:
		_sleep()
		return
	if paused and not _step_requested:
		return
	if paused:
		_step_requested = false
		_accum = 0.0
	else:
		_step_requested = false
		_accum = minf(_accum + delta, STEP * 2.0)
		if _accum < STEP:
			return
		_accum -= STEP
	_wake()
	_awake = true
	debug_steps += 1
	# Whole-texel snapping is what keeps waves world-anchored: both the old and the new origin
	# sit on the sim lattice, so the scroll shift below is always an exact texel count and
	# last step's state translates losslessly.
	var f3 := focus.global_position
	# SNAPPED TO WHOLE METRES, not to the 0.2 m sim texel. One metre is exactly 5 sim texels and
	# exactly 2 field texels, so the scroll stays an exact texel count for both textures and the
	# tier steps baked into the field's A channel never land mid-texel. The window jumps 1 m at a
	# time instead of 0.2 m; the ~5 m rim fade covers it.
	var new_origin := Vector2(floorf(f3.x), floorf(f3.z)) \
			- Vector2(SIZE_M, SIZE_M) * 0.5
	var back := 1 - _front
	var mat := _mats[back]
	# ---- BOUND EVERY STEP, and every one of these used to be bound only on the reset branch
	# below - which is to say, twice per reset and never again.
	#
	# `jitter` is the one that mattered. round_store()'s whole correctness argument is that the
	# dither is STOCHASTIC: a sub-ulp increment is accepted with probability equal to its size, so
	# the expectation is exact however small it is. That argument needs a NEW random number per
	# texel per step. Frozen, hash12(uv * 1024 + jitter) is a fixed per-texel constant, and the
	# store degenerates into round-to-nearest-with-a-per-texel-threshold - the exact failure
	# stochastic rounding was introduced to fix, wearing its name. Every texel gets a permanent
	# personal opinion about which increments count.
	#
	# `edge_mode` is the other live one: it has no setter, so a bench switching the box on or off
	# mid-run changed a GDScript variable and nothing else. It only ever appeared to work because
	# the bench sets depth_mode first, and THAT has a setter that queues a reset.
	mat.set_shader_parameter("jitter", float(debug_steps % 4096))
	mat.set_shader_parameter("edge_mode", edge_mode)
	mat.set_shader_parameter("depth_mode", depth_mode)
	mat.set_shader_parameter("staggered", staggered)
	# THE WAVE CLOCK, advanced by the SOLVER's own fixed step rather than by wall time. A maker
	# whose phase came from the frame clock would change frequency whenever the window did, and a
	# probe that paused and stepped would see a wave train with a gap in it.
	_wave_t += STEP
	mat.set_shader_parameter("wave_time", _wave_t)
	if _reset_steps > 0:
		# Boot: an unwritten texture decodes to h = -1 everywhere. Two reset steps write
		# still water into both ping-pong halves before the first real step reads either.
		_reset_steps -= 1
		# THE FIELD IS BOUND EVEN HERE, and it has to be: an EMPTY reset writes eta = -H0, and
		# H0 comes from the field. Skipping the bake on reset steps left the sampler on its
		# hint_default_black, H0 read as zero, "empty" was written as eta = 0 — which is FULL —
		# and the next ordinary step then bound the real field under it. Measured: the first
		# reset-empty of a session produced a brim-full basin, every later one produced an empty
		# one, because by then a previous non-reset step had left the uniform bound. A bug that
		# only bites the FIRST time is a bug nobody reproduces.
		_refresh_field(new_origin)
		mat.set_shader_parameter("field", _field_tex)
		mat.set_shader_parameter("field_n", _field_tex)
		mat.set_shader_parameter("bed", _bed_tex)
		_bind_obstacles(mat, new_origin)
		mat.set_shader_parameter("scroll_uv", Vector2.ZERO)
		mat.set_shader_parameter("reset", true)
		mat.set_shader_parameter("reset_empty", reset_empty)
		mat.set_shader_parameter("impulse_count", 0)
		_queue.clear()
	else:
		mat.set_shader_parameter("reset", false)
		mat.set_shader_parameter("scroll_uv", (new_origin - _front_origin) / SIZE_M)
		_refresh_field(new_origin)
		# The SAME texture on both samplers: one filtered for u0/H0, one NEAREST for the
		# tier level Y, because a smeared step is a delta-function explosion — see the
		# sim shader header.
		mat.set_shader_parameter("field", _field_tex)
		mat.set_shader_parameter("field_n", _field_tex)
		mat.set_shader_parameter("bed", _bed_tex)
		_bind_obstacles(mat, new_origin)
		mat.set_shader_parameter("weirs_on", weirs)
		mat.set_shader_parameter("advect_gain", 1.0 if advect else 0.0)
		_inject(mat, new_origin)
	# DISABLED first, ONCE second, every tick: after a render the viewport still REPORTS
	# UPDATE_ONCE, so assigning ONCE again is a same-value no-op and the sim freezes on its
	# second frame — measured here, not read about. The toggle makes every set a transition.
	_views[back].render_target_update_mode = SubViewport.UPDATE_DISABLED
	_views[back].render_target_update_mode = SubViewport.UPDATE_ONCE
	# SubViewports render BEFORE the main pass of this same frame, so the just-queued step is
	# what the 3D water samples — publish it and its window together, no one-frame skew.
	_front = back
	_front_origin = new_origin
	RenderingServer.global_shader_parameter_set("water_swe_tex",
			_views[_front].get_texture())
	RenderingServer.global_shader_parameter_set("water_swe_rect",
			Vector4(new_origin.x, new_origin.y, SIZE_M, strength))


## Resample the TERRAIN over the window: the baked current in RG, the rest depth in B, and
## the region's rest surface in A.
##
## INCREMENTALLY, because a full bake is 52 ms — measured, not feared. Three Water queries a
## texel at 12.7 us each over 64x64 is three dropped frames, and the window moves a metre
## every 0.17 s at a run, so a naive rebuild would hitch continuously.
##
## The field is STATIC IN WORLD SPACE (flow_at, surface_y and depth_at are all pure functions
## of position), and the origin snaps to whole metres which is exactly one field texel. So a
## move is a SHIFT: copy the overlap, and query only the strip that just came into view. One
## metre of travel costs 64 queries instead of 4096. Same trick as the sim's scroll_uv, moved
## to the CPU side.
func _refresh_field(origin: Vector2) -> void:
	var n := FIELD_RES * FIELD_RES * 4
	if _field_buf.size() != n or _bed_buf.size() != FIELD_RES * FIELD_RES:
		_field_buf = PackedFloat32Array()
		_field_buf.resize(n)
		_bed_buf = PackedFloat32Array()
		_bed_buf.resize(FIELD_RES * FIELD_RES)
		_bake_rect(origin, 0, FIELD_RES, 0, FIELD_RES)
	else:
		var d := ((origin - _field_at) / FIELD_M).round()
		var dx := int(d.x)
		var dz := int(d.y)
		if dx == 0 and dz == 0:
			return
		if absi(dx) >= FIELD_RES or absi(dz) >= FIELD_RES:
			_bake_rect(origin, 0, FIELD_RES, 0, FIELD_RES)   # teleport: nothing overlaps
		else:
			_field_buf = _shift(_field_buf, dx, dz, 4)
			_bed_buf = _shift(_bed_buf, dx, dz, 1)
			if dx > 0:
				_bake_rect(origin, FIELD_RES - dx, FIELD_RES, 0, FIELD_RES)
			elif dx < 0:
				_bake_rect(origin, 0, -dx, 0, FIELD_RES)
			if dz > 0:
				_bake_rect(origin, 0, FIELD_RES, FIELD_RES - dz, FIELD_RES)
			elif dz < 0:
				_bake_rect(origin, 0, FIELD_RES, 0, -dz)
	_field_at = origin
	var img := Image.create_from_data(FIELD_RES, FIELD_RES, false, Image.FORMAT_RGBAF,
			_field_buf.to_byte_array())
	if _field_tex == null:
		_field_tex = ImageTexture.create_from_image(img)
	else:
		_field_tex.update(img)
	var bimg := Image.create_from_data(FIELD_RES, FIELD_RES, false, Image.FORMAT_RF,
			_bed_buf.to_byte_array())
	if _bed_tex == null:
		_bed_tex = ImageTexture.create_from_image(bimg)
	else:
		_bed_tex.update(bimg)


## Slide the buffer by whole texels, ROW-WISE. The obvious element-wise loop is 16k GDScript
## array writes and measured 8 ms — worse than the queries it was meant to save. Rebuilding
## by appending whole row SLICES keeps the copying on the C++ side: about 200 calls instead
## of 16 thousand.
##
## Takes its buffer and stride so the terrain field (4 floats a texel) and the bed
## (1) can share it. Two shifts of the same rectangle by the same delta, not one
## shift of a widened buffer: the row slices stay contiguous either way, and keeping
## the bed on its own texture is what lets it be sampled NEAREST.
func _shift(buf: PackedFloat32Array, dx: int, dz: int, stride: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var row := FIELD_RES * stride
	var pad_l := maxi(0, -dx) * stride            # dest columns with no source
	var pad_r := maxi(0, dx) * stride
	var keep := row - pad_l - pad_r
	var blank := PackedFloat32Array()
	blank.resize(row)
	for z in FIELD_RES:
		var sz := z + dz
		if sz < 0 or sz >= FIELD_RES or keep <= 0:
			out.append_array(blank)                   # whole row is new; _bake_rect fills it
			continue
		if pad_l > 0:
			out.append_array(blank.slice(0, pad_l))
		var src := sz * row + maxi(0, dx) * stride
		out.append_array(buf.slice(src, src + keep))
		if pad_r > 0:
			out.append_array(blank.slice(0, pad_r))
	return out


## Query one rectangle of the field, in texels. RGBA32F because the A channel carries
## ABSOLUTE world heights and the solver compares neighbours against a 0.5 m step threshold —
## it needs range and absolute precision, which the zero-centred state texture deliberately
## does not.
func _bake_rect(origin: Vector2, x0: int, x1: int, z0: int, z1: int) -> void:
	var t0 := Time.get_ticks_usec()
	for z in range(z0, z1):
		for x in range(x0, x1):
			var w := origin + Vector2(x + 0.5, z + 0.5) * FIELD_M
			var p := Vector3(w.x, 0.0, w.y)
			# THROUGH THE SEAM, never the game autoload. `terrain` answers three questions -
			# bed_y, level_y, is_spring - and knows nothing else; see SweTerrain. The baked current
			# is the one thing still asked of the game directly, because it belongs to the LEGACY
			# eta encoding and dies with it (stage 5): the depth and staggered solvers never read
			# it, and a general solver has no business with a current somebody painted.
			var f := Water.flow_at(p) if legacy_flow else Vector2.ZERO
			var ys: float = terrain.level_y(p)
			var bed: float = terrain.bed_y(p)
			# THE BED, asked of the world rather than derived here as surface minus depth. Those
			# agree wherever there IS water and nowhere else, and "nowhere else" is precisely the
			# ground a solver has to be able to flood.
			_bed_buf[z * FIELD_RES + x] = bed
			var o := (z * FIELD_RES + x) * 4
			_field_buf[o] = f.x
			_field_buf[o + 1] = f.y
			# DEPTH IS DERIVED, not asked for. level - bed is the only definition, and storing the
			# two separately is how they come to disagree along a shoreline.
			_field_buf[o + 2] = 0.0 if is_nan(ys) else maxf(ys - bed, 0.0)
			# A SPRING RIDES THE Y CHANNEL, offset by SPRING_MARK. All four channels are spoken
			# for and a spring is one bit, so it has to ride something — but it must ride the
			# channel that is sampled NEAREST. Encoding it in the sign of the depth channel
			# (which is filter_linear, because a shoreline wants interpolation) put a sign
			# change inside an interpolated quantity: depth then swept through zero across the
			# spring's edge, and every neighbour reading it un-decoded saw a dry wall. Y is
			# already read through the nearest sampler and already exact, for exactly this kind
			# of reason.
			# A SPRING ON DRY GROUND IS STILL A SPRING, and until this line it was not.
			#
			# The mark used to ride only the not-NaN branch, so a source standing anywhere the map
			# has no water region - a hillside, a terrace above the waterline, the lip a waterfall
			# is supposed to pour over - was silently dropped and nothing ever came out of it.
			# Measured on the TERRACES profile, whose middle step sits 0.65 m ABOVE rest: the bench
			# opens with its source at the centre of the bed, which lands there, and the report was
			# "terraces does not spawn water". It was not the terraces.
			#
			# The two sentinels do not collide, so the flag can just always be added: DRY_Y plus
			# SPRING_MARK is 9000, comfortably over the 5000 the flag test uses, and stripping it
			# gives -1000 back exactly. A dry spring now reads as a spring standing on dry ground,
			# which is the thing a source pouring onto a slope has to be.
			_field_buf[o + 3] = ((DRY_Y if is_nan(ys) else ys)
					+ (SPRING_MARK if terrain.is_spring(p) else 0.0))
	bake_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## The terrain input, for the lab's field view and the probes.
func field_texture() -> Texture2D:
	return _field_tex


## The bed elevation over the window, one float per metre. Inert until a solver reads it.
func bed_texture() -> Texture2D:
	return _bed_tex


## Sleeping leaves stale state behind on purpose - "stale waves clear themselves". That reasoning
## holds only while the state is a DEVIATION, because stale eta damps toward rest, which is a
## correct answer. Stale h damps toward DRY, and waking a fresh bed under it is a mass event: a
## lake that had drained itself while nobody was looking. So the depth encoding reseeds on wake.
func _wake() -> void:
	if _awake:
		return
	if depth_mode:
		reset_now()


func _sleep() -> void:
	if not _awake:
		return
	_awake = false
	for vp in _views:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_queue.clear()
	RenderingServer.global_shader_parameter_set("water_swe_rect",
			Vector4(0.0, 0.0, SIZE_M, 0.0))
	# No reset on the next wake: the scroll shift relocates the window, and a jump wider than
	# 64 m shifts every sample off the texture — stale waves clear themselves.


func _inject(mat: ShaderMaterial, origin: Vector2) -> void:
	# CULL FIRST, THEN RANK. Truncating to 16 before the window test let impulses that were
	# never going to be drawn — a waterfall on the far side of the map — spend the slots and
	# push the player's own footsteps out of the frame.
	var live: Array[Dictionary] = []
	for imp: Dictionary in _queue:
		var uv: Vector2 = (imp.pos as Vector2 - origin) / SIZE_M
		if uv.x < -0.05 or uv.x > 1.05 or uv.y < -0.05 or uv.y > 1.05:
			continue
		live.append({"uv": uv, "radius": imp.radius, "strength": imp.strength})
	if live.size() > MAX_IMPULSES:
		live.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.strength) > float(b.strength))
		live.resize(MAX_IMPULSES)
	var arr := PackedVector4Array()
	for imp: Dictionary in live:
		var uv: Vector2 = imp.uv
		arr.append(Vector4(uv.x, uv.y, float(imp.radius) / SIZE_M, float(imp.strength)))
	_queue.clear()
	if debug_log and arr.size() > 0:
		print("[Ripples] inject %d, first uv (%.3f, %.3f) r %.4f s %.2f, origin (%.1f, %.1f)"
				% [arr.size(), arr[0].x, arr[0].y, arr[0].z, arr[0].w, origin.x, origin.y])
	mat.set_shader_parameter("impulse_count", arr.size())
	while arr.size() < MAX_IMPULSES:
		arr.append(Vector4.ZERO)
	mat.set_shader_parameter("impulses", arr)


## The window follows the PLAYER (the wilds streamer's own focus rule), the active camera when
## no player stands — the labs' fly mode keeps its ripples.
func _focus() -> Node3D:
	if focus_override != null and is_instance_valid(focus_override):
		return focus_override
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		return p
	return get_viewport().get_camera_3d()

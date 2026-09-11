class_name BladeTrail
extends GPUTrail3D
## A ribbon trail that is OFF by default and switched on in bursts — a sword swing, an arrow in
## flight. It wraps celyk's GPUTrail3D (addons/GPUTrail, MIT) rather than modifying it, so the
## addon stays a clean vendor drop we can update. Three things every user of it here needs:
##
## 1. TIME, NOT STEPS. The addon's `length` counts steps at `fixed_fps`, and it sets fixed_fps to
##    the MONITOR REFRESH RATE. The same scene would therefore show a 0.25 s trail on a 60 Hz
##    screen and a 0.10 s one at 144 Hz. We set `length_seconds` instead — but only AFTER the
##    addon's own _ready() has read the refresh rate, which is why it happens in _ready() here.
##
## 2. A WORKING ALPHA. The addon exposes no opacity, but its draw shader ends with
##    `ALPHA *= (M.r * mask_strength)` and the mask sampler is hint_default_white — so with no mask
##    texture, mask_strength IS a global alpha multiplier. Its SETTER cannot be used for fading
##    though: `if value:` treats 0.0 as "unset" and writes 1.0, so a fade-out would end at FULL
##    opacity. We write the shader parameter directly instead.
##
## 3. GATING. A trail node records positions every frame whether you want it or not. The blade
##    rides the hand socket, so an always-on trail would streak while merely walking; and an arrow
##    is added to the tree BEFORE its spawn position is set, so its first samples sit at the world
##    origin and it draws a streak across the level. burst()/hold() call restart() to drop that
##    history before anything becomes visible.

@export var seconds := 0.22               ## how much history the ribbon holds
@export var color := Color(0.75, 0.9, 1.0)
@export var head_alpha := 0.85            ## opacity at the leading end; the tail always reaches 0
## Half-size of the culling box, in metres. Particles are in WORLD space but GPUParticles3D still
## culls on a NODE-LOCAL box, and its 4 m default is smaller than a trail can reach: a fully
## charged arrow flies 22 m/s, so 0.17 s of history is ~3.7 m and the tail would pop out at the
## screen edge. This only widens a visibility test, so being generous costs effectively nothing.
@export var reach := 6.0

var _fade: Tween


func _ready() -> void:
	super()                               # the addon builds its per-instance mesh + material here
	visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * (reach * 2.0))
	length_seconds = seconds
	color_ramp = _ramp()
	curve = _taper()
	_alpha(0.0)
	visible = false


## Span the ribbon between two points given in the PARENT's space (e.g. a blade's base and tip).
## The draw shader puts the ribbon's two edges at `origin +- basis.y` — it reads
## `EMISSION_TRANSFORM * vec4(0,+-1,0,1)` and nothing else — so as far as the SHADER goes, Y is the
## whole story.
##
## The ENGINE is not so relaxed: it needs a non-singular basis, and simply dropping Y into an
## identity basis produces det == 0 whenever Y happens to lie in the X-Z plane — i.e. every time
## the ribbon is horizontal. A degenerate transform silently draws nothing, which is exactly how
## the flat dodge smear vanished while the upright one (det == 1) rendered fine. So X and Z are
## rebuilt perpendicular to Y here even though nothing samples them.
func span(from: Vector3, to: Vector3) -> void:
	var half := (to - from) * 0.5
	var t := Transform3D.IDENTITY
	if half.length_squared() > 1e-12:
		var dir := half.normalized()
		var x := dir.cross(Vector3.UP)
		if x.length_squared() < 1e-6:                  # Y is vertical — pick another reference
			x = dir.cross(Vector3.RIGHT)
		x = x.normalized()
		var b := Basis()
		b.x = x
		b.y = half
		b.z = x.cross(dir)
		t.basis = b
	t.origin = (from + to) * 0.5
	transform = t


## A ribbon of constant `width` lying flat across the parent's local X axis. Right for a projectile
## under this game's fixed overhead camera: a flat ribbon stays broadside to it, so we never need
## the addon's billboard mode (which its own docs mark unfinished).
func flat(width: float) -> void:
	span(Vector3(-width * 0.5, 0.0, 0.0), Vector3(width * 0.5, 0.0, 0.0))


## Recolour after construction — used for the arrow's team tint (cool = player, warm = enemy).
func retint(c: Color) -> void:
	color = c
	color_ramp = _ramp()


## Show the trail for `dur` seconds, fading out over the last `fade_frac` of that. One call per
## sword swing: the fade means the streak dies with the swing instead of popping out.
func burst(dur: float, fade_frac := 0.35) -> void:
	hold()
	var fade: float = clampf(dur * fade_frac, 0.02, dur)
	_fade = create_tween()
	_fade.tween_interval(maxf(dur - fade, 0.0))
	_fade.tween_method(_alpha, 1.0, 0.0, fade)
	_fade.tween_callback(func() -> void: visible = false)


## Turn the trail on and leave it on — for something that owns its own ending, like a projectile.
func hold() -> void:
	_kill_fade()
	restart()                             # drop history recorded while idle / before spawn
	visible = true
	_alpha(1.0)


## Fade out over `fade` seconds; the counterpart to hold().
func stop(fade := 0.12) -> void:
	_kill_fade()
	if not visible:
		return
	_fade = create_tween()
	_fade.tween_method(_alpha, 1.0, 0.0, fade)
	_fade.tween_callback(func() -> void: visible = false)


func _alpha(a: float) -> void:
	var m := draw_pass_1.material as ShaderMaterial     # direct write — see note 2 above
	if m != null:
		m.set_shader_parameter("mask_strength", a)


# Offset 0 is the NEWEST end of the trail (at the blade), 1 the oldest — the convention the
# addon's own default resources use.
func _ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, head_alpha))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


# Width along the trail: full at the head, pinched to a point at the tail.
func _taper() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()

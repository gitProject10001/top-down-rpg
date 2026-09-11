class_name ReachEnvelope
extends RefCounted
## THE REACHABLE WORKSPACE, in the robotics sense — and that is the term to search under:
## "reachable workspace", "reachability map", "capability map". This project derives the ogre's
## attack ranges from its limb geometry at runtime and clamps the aim INTO them, which is the
## reverse of the industry's usual arrangement (author the range as a float, warp the animation to
## cover it — "motion warping" / "distance matching"). The inversion is deliberate and it is the
## best-motivated piece of the combat system: a range derived from the rig cannot disagree with
## the rig, and before it existed the slam declared 2.2–5.0 m against an actual 1.0–2.6 m
## capability and pinned the arm at full extension on every swing. See docs/combat-refactor.md,
## "Is the 'derived attack zone' standard?".
##
## PURE STATIC MATH, NO NODES — the same rule as TwoBoneIk, for the same reason: it can be
## hammered with ten thousand inputs and no scene at all. The solver gathers the live inputs
## (measured rig lengths, tuning dials, this frame's crouch) and marshals them in; nothing here
## reads state, so nothing here can be stale, and the maths survives whatever ends up driving the
## bones — poses today, clips later.


## D = sqrt(R^2 - k^2), or zero where the circle never reaches the floor that far out.
##
## A head at radius R about a hinge k above the ground meets the ground on a circle of radius
## sqrt(R^2 - k^2). That is all. The swing plane's tilt decides WHERE ON THAT CIRCLE the head
## arrives — forward, or off to one side — but it cannot change the circle's size.
##
## The old inversion divided k by the plane's vertical component first, which is the reach
## measured along the plane's own forward axis rather than across the ground. At a 45 degree tilt
## that is short by a factor of nearly two: it reported 2.61 m for a blow that lands 3.89 m out.
## Every consequence followed from that one division — a strike zone the mace visibly overshot, a
## chase that stopped short of it, and an attack chooser that answered "throw a rock" at melee
## range.
static func reach_at(r: float, k: float) -> float:
	var v := r * r - k * k
	return sqrt(v) if v > 0.0 else 0.0


## THE SWING'S ANNULUS on the floor: how far from the body the head can land, near and far edge.
##
## Derived, not dialled: the head sits `arm * frac + beyond` along the spoke from a hinge
## `hinge_y` up, and reach_at() turns each arm limit into a floor distance. `lean` is the
## shoulder's own travel (solved from the shoulder, quoted from the body — without it the ring sat
## 0.89 m inside the blow it described).
##
## THE HOLE IS THE BODY, not the derived tangent. The derived near edge sits right where the
## shortest arm can only just reach the floor, so it is knife-edge sensitive: a hinge 10 cm lower
## moves it a whole metre. What IS stable is that nothing can be swung at inside the creature's
## own footprint (`floor_radius`), which is exactly where a kick belongs instead.
##
## NEVER INVERTED. A degenerate solve gives a far edge below the near one, and a band with no
## inside reads to every caller as "the player is never in range" — silence, not an error.
static func swing_annulus(arm_full: float, beyond: float, hinge_y: float, lean: float,
		arm_min_frac: float, arm_max_frac: float, floor_radius: float) -> Vector2:
	var near := reach_at(arm_full * arm_min_frac + beyond, hinge_y) + lean
	var far := reach_at(arm_full * arm_max_frac + beyond, hinge_y) + lean
	var lo: float = maxf(minf(near, far), floor_radius)
	return Vector2(lo, maxf(maxf(near, far), lo))


## THE KICK'S BAND — the same inversion turned on its side: a foot on a chain of known length,
## from a hip of known (current) height, arriving at kick_height rather than at the floor; what is
## left over is horizontal reach. `lunge` is the step the kick takes into its blow, and
## `strike_near` guarantees the band MEETS the swing's: a four-metre mace cannot come down closer
## than its own geometry allows, and the ring between "too close to swing" and "too far to kick"
## was the punchbag — stand there and the creature had no answer at all.
static func kick_band(chain: float, hip: float, kick_height: float, lunge: float,
		strike_near: float, floor_radius: float) -> Vector2:
	var far := reach_at(chain, absf(hip - kick_height))
	return Vector2(0.0, maxf(maxf(far + lunge, strike_near), floor_radius + 0.2))


## A target pulled into the band: angle first, then distance. What comes back is somewhere the
## creature can actually hit, and the difference between it and the target is exactly what the
## body has to fix by moving.
static func clamp_into(origin: Vector3, fwd: Vector3, target: Vector3, band: Vector2,
		yaw_limit: float) -> Vector3:
	var flat := target - origin
	flat.y = 0.0
	var d := flat.length()
	if d < 0.001:
		return origin + fwd * band.y
	var dir := flat / d
	var off := fwd.signed_angle_to(dir, Vector3.UP)
	if absf(off) > yaw_limit:
		dir = fwd.rotated(Vector3.UP, signf(off) * yaw_limit)
	return origin + dir * clampf(d, band.x, band.y)

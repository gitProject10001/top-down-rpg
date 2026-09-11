class_name PoseSet
extends Resource
## Named key poses for the ogre — the only hand-authored data in an otherwise computed animation.
##
## WHAT A POSE IS HERE. A sparse dictionary of bone -> (pitch, yaw, roll) in DEGREES, applied about
## the ogre's OWN body axes: pitch about its right, yaw about its up, roll about its forward.
##
## The three angles are composed as an XYZ Euler rotation inside a RIGHT-HANDED body frame whose
## axes are (right, up, back). `PoseSet.body_frame()` builds that frame and `PoseSet.to_basis()`
## builds the rotation, and BOTH the pose layer and the editor go through them -- so what the editor
## solves for and what the layer applies cannot drift apart. That mattered: the first editor split a
## drag onto the three axes independently, which is only valid for small angles because sequenced
## rotations do not commute, and dragging a hand sent it steadily further from the cursor.
##
## Not local Euler angles. Local angles are a per-bone guess about which axis happens to be which on
## this particular rig, and the answer changes with the import's `overwrite_axis` setting — the same
## trap that stood the ogre on its toes when the foot flattening named an axis. Body-relative angles
## mean the same thing on every bone and can be read by a human: `RightUpperArm: (-140, 0, 25)` is
## "swing the right arm back and overhead, and out a bit", on any rig, forever.
##
## SPARSE ON PURPOSE. A bone absent from a pose keeps whatever the layers beneath produced, so
## `slam_windup` can be upper-body-only and ride the walk cycle instead of replacing it. That is the
## same trick `scripts/arm_guard.gd` uses to raise a shield over any locomotion, generalised to N
## poses with weights.
##
## WHY A RESOURCE. The lab has to save tuned values back to disk, and `ResourceSaver.save()` is one
## line where rewriting a GDScript const is not. `.tres` is text, so a tuned ogre shows up in git as
## a readable diff. NOT `@tool`: `scripts/dev/tuning_panel.gd`'s header records what a @tool script
## did to crypt_stone.tres, and nothing here needs to run in the editor.

## pose name -> { bone name : Vector3(pitch, yaw, roll) in degrees, body-relative }
@export var poses: Dictionary = {}

## pose name -> the weapon's full placement: which bone it hangs off, where it sits relative to
## that bone, and how it is turned. Superseded `aims`, which could only point the shaft (two degrees
## of freedom) and could not slide it up the hand, roll it in the grip, or move it to another bone.
##
##   { "bone": String, "pos": Vector3 (metres, body frame), "rot": Vector3 (degrees, body frame) }
##
## `pos` is the offset from the anchor bone to the weapon's ORIGIN, which for this mace is the butt
## of the haft. `rot` turns it in the ogre's own frame, so pitch tips the shaft up, yaw swings it
## across the body and roll spins it in the hand.
@export var weapon: Dictionary = {}

## DEPRECATED, kept only so an old saved .tres still loads: pose -> Vector2(elevation, bearing).
## `weapon_of` falls back to it when a pose has no full transform yet, so nothing breaks on upgrade. Elevation is measured up from horizontal, bearing is left/right of straight ahead.
##
## WHY THE WEAPON IS AIMED SEPARATELY FROM THE ARM. A weapon held in a fist runs along the forearm,
## so with only arm angles to work with, "put the hand there" and "point the mace there" are the
## same act -- and they fight. Every attempt to raise the mace also moved the hand out to arm's
## length, which put the whole shaft beyond the off hand's reach, and the second arm gave up and
## hung there. The result reads as an ogre waving a four-metre mace one-handed.
##
## Aiming the weapon directly costs TWO numbers per pose instead of six arm angles, and it is the
## number you actually have an opinion about: you know where the mace should be pointing. The arm
## poses then only have to put the hand somewhere sensible, and the off hand solves onto the shaft
## wherever it ended up.
@export var aims: Dictionary = {}


func aim_of(n: StringName) -> Vector2:
	return aims.get(String(n), Vector2(35.0, -25.0))


## The weapon's placement for a pose, with sane defaults and an upgrade path from `aims`.
##
## An elevation/bearing pair is a DIRECTION, so converting one into a full transform means choosing
## a position for it as well: the butt goes half a metre back down the shaft from the hand, which is
## where it was before. Anything authored since is a real transform and passes straight through.
func weapon_of(n: StringName) -> Dictionary:
	var w: Dictionary = weapon.get(String(n), {})
	if not w.is_empty():
		return {
			"bone": w.get("bone", "RightHand"),
			"pos": w.get("pos", Vector3.ZERO),
			"rot": w.get("rot", Vector3.ZERO),
		}
	var a := aim_of(n)
	# The old two-number aim, rebuilt as a transform. Elevation is a pitch UP, so it is negated:
	# positive pitch tips a bone forward and the shaft has to go the other way.
	return {"bone": "RightHand", "pos": Vector3(0.0, -0.65, 0.0), "rot": Vector3(-a.x, a.y, 0.0)}


func set_weapon(n: StringName, w: Dictionary) -> void:
	weapon[String(n)] = w


## The ogre's own frame as an orthonormal RIGHT-handed basis: X right, Y up, Z back.
##
## Back rather than forward, and that is not arbitrary. (right, up, forward) is LEFT-handed under
## Godot's -Z-forward convention, and Basis.get_euler on a left-handed basis is meaningless -- which
## is exactly what the editor needs to do to turn a drag back into three angles.
static func body_frame(right: Vector3, up: Vector3, forward: Vector3) -> Basis:
	return Basis(right, up, -forward)


## The rotation a pose entry means, in whatever space `frame` was built in.
##
## ROLL IS NEGATED ON THE WAY IN AND OUT. The frame's Z axis is BACK (it has to be, or the basis is
## left-handed and get_euler is meaningless), but the authored angle means "roll about FORWARD",
## which is the direction a person thinks in. Converting here keeps the stored data meaning what it
## says while the maths gets the handedness it needs. Skipping this silently inverts every roll in
## every pose -- which tilted the ogre's torso the wrong way, moved its hips, and showed up two
## layers later as foot skate at walking pace.
static func to_basis(angles_deg: Vector3, frame: Basis) -> Basis:
	var e := Vector3(deg_to_rad(angles_deg.x), deg_to_rad(angles_deg.y), -deg_to_rad(angles_deg.z))
	return frame * Basis.from_euler(e, EULER_ORDER_XYZ) * frame.inverse()


## The inverse of to_basis: what angles would produce this rotation. Used by the editor to turn a
## drag into pose numbers.
static func from_basis(b: Basis, frame: Basis) -> Vector3:
	var e := (frame.inverse() * b * frame).get_euler(EULER_ORDER_XYZ)
	return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), -rad_to_deg(e.z))


func has_pose(n: StringName) -> bool:
	return poses.has(String(n))


func bones_of(n: StringName) -> Dictionary:
	return poses.get(String(n), {})


func names() -> Array:
	var out := poses.keys()
	out.sort()
	return out


## Fill this set's gaps from the compiled-in defaults. The saved .tres wins wherever it defines a
## pose; a name it never mentions falls back instead of resolving to nothing.
##
## WHY THIS EXISTS. The loader used to let the saved file REPLACE the defaults outright, and the
## pose editor had never saved `kick_windup` or `kick_strike` — so `bones_of()` returned {} for
## both, and the kick, backstep and charge blended toward an empty pose. No error anywhere:
## a weight ramp toward {} is a blend toward nothing, and that failure is silent by construction.
func merge_defaults() -> void:
	var d := PoseSet.defaults()
	for k in d.poses:
		if not poses.has(k):
			poses[k] = d.poses[k]
	for k in d.aims:
		if not aims.has(k):
			aims[k] = d.aims[k]
	for k in d.weapon:
		if not weapon.has(k):
			weapon[k] = d.weapon[k]



## Mirror a pose's left side onto its right, or the reverse.
##
## In body-relative angles mirroring is honest and simple: reflecting across the body's own sagittal
## plane negates the yaw and the roll and leaves the pitch alone. Doing this in local bone space
## would need a per-rig sign table, which is exactly the kind of thing that is right until somebody
## reimports the model.
static func mirror_angles(a: Vector3) -> Vector3:
	return Vector3(a.x, -a.y, -a.z)


static func opposite(bone: String) -> String:
	if bone.begins_with("Left"):
		return "Right" + bone.substr(4)
	if bone.begins_with("Right"):
		return "Left" + bone.substr(5)
	return bone


## The ogre's starting pose book, built in code so the creature works the moment it is dropped in a
## scene. The lab can edit and save these to a `.tres`, which then takes over.
##
## Angles are deliberately large. This is a four-metre creature whose whole read is committed,
## unhurried movement — a wind-up that a human would find theatrical is about right here, and the
## anticipation is the player's dodge window rather than decoration.
##
## THE ARM CONVENTION, measured off the rig with `shot_ogre.gd --sweep=RightUpperArm:x` rather than
## reasoned about (the first pass reasoned about it and got the sign right but the magnitude wrong,
## which is worse than getting it plainly backwards):
##
##   pitch  -150  arm up and BACK, mace over the shoulder      -- the wind-up
##   pitch   -90  arm horizontal behind
##   pitch     0  arm hanging at rest
##   pitch   +70  arm down and FORWARD, mace into the floor    -- the strike
##
## And the elbow is nearly straight through all of it. A two-hander this size is swung from the
## shoulders and the trunk; bending the elbow 70 degrees on top of a 150-degree shoulder rotation
## folds the arc back on itself and the mace ends up horizontal, which is what the first pass did.
##
## ANGLES ACCUMULATE DOWN THE CHAIN. Each bone's rotation is composed onto its parent's, so a spine
## folded 40 degrees forward has ALREADY swung the shoulder 40 degrees before the arm's own number
## is applied. The trunk does most of the work in a two-handed swing, and the arm's angle is the
## remainder -- which is why the strike below reads as a small number. Writing the arm angle as if
## it were absolute is how the first pass ended up 70 degrees past its own target.
static func defaults() -> PoseSet:
	var ps := PoseSet.new()

	# --- IDLE / CARRY -----------------------------------------------------------------------
	# TWO-HANDED, HELD ACROSS THE BODY. The elbow is deliberately well folded so the weapon hand sits
	# near the chest rather than out at arm's length -- and that is not a stylistic preference, it is
	# what makes the grip possible at all. The shaft runs along the forearm, so an extended arm puts
	# the whole weapon a metre and a half away and the off hand cannot reach any part of it; the IK
	# gives up, the second arm hangs, and the ogre appears to be waving a four-metre mace one-handed.
	# Bring the weapon hand in and both hands land on the shaft with room to spare.
	#
	# The weight pulls the right shoulder down and twists the spine away from it, which is most of
	# what sells a heavy object being CARRIED rather than merely held.
	# Where the mace points in each pose: elevation up from horizontal, then bearing off straight
	# ahead. Read them as a swing: shouldered high and behind, hauled overhead, driven into the
	# floor in front, then recovered.
	ps.aims = {
		"carry": Vector2(48.0, -34.0),
		"slam_windup": Vector2(78.0, -14.0),
		"slam_strike": Vector2(-62.0, 4.0),
		"slam_recover": Vector2(-18.0, 10.0),
		"rock_lift": Vector2(30.0, -40.0),
		"throw_windup": Vector2(60.0, -46.0),
		"throw_release": Vector2(20.0, 30.0),
		"roar": Vector2(66.0, -30.0),
		"kick_windup": Vector2(52.0, -44.0),
		"kick_strike": Vector2(40.0, -58.0),
		"stagger": Vector2(30.0, -50.0),
		"flinch": Vector2(44.0, -36.0),
	}

	ps.poses["carry"] = {
		"Spine": Vector3(-2, -10, 4),
		"Chest": Vector3(-4, -14, 5),
		"UpperChest": Vector3(-3, -10, 4),
		"RightShoulder": Vector3(-10, 0, -10),
		"RightUpperArm": Vector3(-26, 26, -14),
		"RightLowerArm": Vector3(-74, 0, 0),
		"LeftShoulder": Vector3(-4, 0, 8),
		"LeftUpperArm": Vector3(-34, -14, 20),
		"LeftLowerArm": Vector3(-58, 0, 0),
		"Head": Vector3(4, 6, 0),
	}

	# --- OVERHEAD SLAM ----------------------------------------------------------------------
	# The three beats of the sketch: haul it up and back over the shoulder, drive it down through
	# the ground, then be left holding the follow-through.
	#
	# The wind-up leans the whole torso BACK. That is the anticipation doing real work: a heavy
	# thing cannot be thrown forward without shifting the mass backward first, and the backward lean
	# is the frame the player reads as "now".
	ps.poses["slam_windup"] = {
		"Hips": Vector3(-8, 10, 0),
		"Spine": Vector3(-16, 12, 0),
		"Chest": Vector3(-18, 14, 0),
		"UpperChest": Vector3(-14, 12, 0),
		"Neck": Vector3(12, -8, 0),
		"Head": Vector3(14, -8, 0),
		"RightShoulder": Vector3(-24, 0, -12),
		"RightUpperArm": Vector3(-150, 8, -18),
		"RightLowerArm": Vector3(-22, 0, 0),
		"LeftShoulder": Vector3(-18, 0, 10),
		"LeftUpperArm": Vector3(-138, -10, 20),
		"LeftLowerArm": Vector3(-26, 0, 0),
	}

	# The strike. Everything that leaned back is now folded forward and the arms are DOWN, past the
	# body — the mace is meant to arrive at the floor, not stop at waist height.
	ps.poses["slam_strike"] = {
		"Hips": Vector3(7, -6, 0),
		"Spine": Vector3(13, -8, 0),
		"Chest": Vector3(12, -10, 0),
		"UpperChest": Vector3(8, -8, 0),
		"Neck": Vector3(-14, 6, 0),
		"Head": Vector3(-18, 6, 0),
		"RightShoulder": Vector3(8, 0, 6),
		"RightUpperArm": Vector3(10, -8, -6),
		"RightLowerArm": Vector3(-6, 0, 0),
		"LeftShoulder": Vector3(6, 0, -6),
		"LeftUpperArm": Vector3(6, 10, 8),
		"LeftLowerArm": Vector3(-6, 0, 0),
	}

	# The follow-through: it has swung past and is being hauled back under control.
	ps.poses["slam_recover"] = {
		"Hips": Vector3(4, -2, 0),
		"Spine": Vector3(9, -4, 0),
		"Chest": Vector3(9, -4, 0),
		"UpperChest": Vector3(6, -2, 0),
		"Head": Vector3(-8, 0, 0),
		"RightShoulder": Vector3(4, 0, 2),
		"RightUpperArm": Vector3(-26, -6, -10),
		"RightLowerArm": Vector3(-30, 0, 0),
		"LeftShoulder": Vector3(2, 0, -2),
		"LeftUpperArm": Vector3(-30, 8, 10),
		"LeftLowerArm": Vector3(-28, 0, 0),
	}

	# --- ROCK: LIFT AND THROW ----------------------------------------------------------------
	# Reaching down for something on the floor. Knees are the gait's business, so this only folds
	# the spine and drops the arms — the crouch comes from the solver lowering the pelvis.
	ps.poses["rock_lift"] = {
		"Hips": Vector3(20, 0, 0),
		"Spine": Vector3(24, 0, 0),
		"Chest": Vector3(20, 0, 0),
		"UpperChest": Vector3(14, 0, 0),
		"Neck": Vector3(-16, 0, 0),
		"Head": Vector3(-20, 0, 0),
		"RightShoulder": Vector3(6, 0, 0),
		"RightUpperArm": Vector3(6, -12, -12),
		"RightLowerArm": Vector3(-20, 0, 0),
		"LeftShoulder": Vector3(6, 0, 0),
		"LeftUpperArm": Vector3(6, 12, 12),
		"LeftLowerArm": Vector3(-20, 0, 0),
	}

	# Cocked back over the shoulder, torso wound the other way. A throw is a rotation, not a push.
	ps.poses["throw_windup"] = {
		"Hips": Vector3(-6, -16, 0),
		"Spine": Vector3(-14, -22, 0),
		"Chest": Vector3(-16, -26, 0),
		"UpperChest": Vector3(-12, -22, 0),
		"Head": Vector3(6, 14, 0),
		"RightShoulder": Vector3(-22, 0, -10),
		"RightUpperArm": Vector3(-126, 26, -22),
		"RightLowerArm": Vector3(-64, 0, 0),
		"LeftShoulder": Vector3(-6, 0, 6),
		"LeftUpperArm": Vector3(-48, -28, 16),
		"LeftLowerArm": Vector3(-34, 0, 0),
	}

	ps.poses["throw_release"] = {
		"Hips": Vector3(6, 18, 0),
		"Spine": Vector3(12, 26, 0),
		"Chest": Vector3(12, 30, 0),
		"UpperChest": Vector3(9, 26, 0),
		"Head": Vector3(-8, -12, 0),
		"RightShoulder": Vector3(10, 0, 8),
		"RightUpperArm": Vector3(-46, -22, -8),
		"RightLowerArm": Vector3(-10, 0, 0),
		"LeftShoulder": Vector3(4, 0, -4),
		"LeftUpperArm": Vector3(-20, 26, 10),
		"LeftLowerArm": Vector3(-40, 0, 0),
	}

	# --- REACTIONS ---------------------------------------------------------------------------
	ps.poses["roar"] = {
		"Hips": Vector3(-6, 0, 0),
		"Spine": Vector3(-14, 0, 0),
		"Chest": Vector3(-18, 0, 0),
		"UpperChest": Vector3(-16, 0, 0),
		"Neck": Vector3(-22, 0, 0),
		"Head": Vector3(-26, 0, 0),
		"RightShoulder": Vector3(-14, 0, -20),
		"RightUpperArm": Vector3(-64, 14, -52),
		"RightLowerArm": Vector3(-58, 0, 0),
		"LeftShoulder": Vector3(-14, 0, 20),
		"LeftUpperArm": Vector3(-64, -14, 52),
		"LeftLowerArm": Vector3(-58, 0, 0),
	}

	# THE KICK. Only the upper body is authored here: the leg is not a pose at all, it is a foot
	# target driven along an arc, because the foot IK runs last and would drag any authored leg
	# straight back to the ground. What these poses do is the counterweight -- a creature that puts a
	# leg out this far has to lean away from it or fall over, and that lean is most of what makes the
	# kick read as a heavy thing committing rather than a limb flicking out.
	#
	# The mace stays shouldered throughout (see the aims above). This is the move for when the player
	# is too close to swing at, so the weapon is deliberately not part of it.
	ps.poses["kick_windup"] = {
		"Hips": Vector3(-6, 4, 0),
		"Spine": Vector3(-10, 6, -3),
		"Chest": Vector3(-8, 8, -4),
		"UpperChest": Vector3(-6, 6, -3),
		"Neck": Vector3(8, -6, 0),
		"Head": Vector3(6, -6, 0),
		"RightShoulder": Vector3(-8, 0, -8),
		"RightUpperArm": Vector3(-30, 22, -20),
		"LeftShoulder": Vector3(-6, 0, 12),
		"LeftUpperArm": Vector3(-24, -18, 26),
	}

	# Driving through. The torso is thrown BACK as the leg goes forward -- opposite to the slam,
	# where everything folds the same way -- because there is nothing under the ogre to push against
	# but the one foot still on the ground.
	ps.poses["kick_strike"] = {
		"Hips": Vector3(-14, -2, 0),
		"Spine": Vector3(-18, -4, 2),
		"Chest": Vector3(-16, -6, 3),
		"UpperChest": Vector3(-12, -4, 2),
		"Neck": Vector3(14, 4, 0),
		"Head": Vector3(12, 4, 0),
		"RightShoulder": Vector3(-14, 0, -14),
		"RightUpperArm": Vector3(-44, 30, -28),
		"LeftShoulder": Vector3(-10, 0, 18),
		"LeftUpperArm": Vector3(-38, -26, 34),
	}

	ps.poses["stagger"] = {
		"Hips": Vector3(-14, 8, 6),
		"Spine": Vector3(-22, 12, 10),
		"Chest": Vector3(-20, 14, 12),
		"UpperChest": Vector3(-14, 10, 8),
		"Neck": Vector3(14, -8, -6),
		"Head": Vector3(18, -10, -8),
		"RightShoulder": Vector3(-10, 0, -14),
		"RightUpperArm": Vector3(-40, 16, -30),
		"RightLowerArm": Vector3(-54, 0, 0),
		"LeftShoulder": Vector3(-6, 0, 12),
		"LeftUpperArm": Vector3(-30, -20, 34),
		"LeftLowerArm": Vector3(-48, 0, 0),
	}

	ps.poses["flinch"] = {
		"Spine": Vector3(-10, 4, 4),
		"Chest": Vector3(-12, 6, 6),
		"UpperChest": Vector3(-8, 4, 4),
		"Head": Vector3(10, -4, -4),
		"RightShoulder": Vector3(-8, 0, -8),
		"LeftShoulder": Vector3(-6, 0, 8),
	}

	return ps

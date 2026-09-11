class_name GuardPose
extends SkeletonModifier3D
## THE FOUR GUARD POSES, procedurally, because the library only has one.
##
## player3_anims.tres ships a single `block` clip — a sword-parry stance held centre. There is no
## directional guard set anywhere in the Quaternius pack, and a mechanic whose whole content is
## "which way is your guard" is unplayable if all four look identical. So the clip stays as the
## stance and this rotates the SWORD ARM out of it, high / low / left / right, in the skeleton's
## modifier stack — after the AnimationTree has written the pose, which is what a modifier is for.
## Exactly the arrangement scripts/arm_guard.gd already uses for the shield.
##
## ONE BONE, AND THAT IS DELIBERATE. Rotating the shoulder swings the whole arm, and the blade
## rides the hand socket, so the weapon travels with it — which is what a guard direction IS. Four
## sets of per-bone quaternions would let the elbow and wrist be posed too, but ArmGuard could
## sample those off a real mocap clip and there is no directional clip here to sample. Rotating one
## joint by a tunable angle is the honest version of what we actually know.
##
## THE ANGLES ARE EXPORTED, IN DEGREES, AND THEY ARE TUNED BY LOOKING. Run the probe's
## `--demo=shots` and read them off the frames; do not treat the defaults as measurements. They are
## applied in SKELETON space (x = pitch the arm up/down, y = yaw it across the body, z = roll it
## over the head) rather than bone space, so they mean the same thing on any rig that gets retargeted
## onto GeneralSkeleton — which is every rig in this project.

## The joint to swing. The sword hand's shoulder: everything below it comes along.
@export var bone := "RightShoulder"

## WHAT THE AXES ACTUALLY DO ON THIS RIG, read off `--demo=axes` rather than reasoned out from the
## names — the bodies here arrive through a humanoid retarget with a 180-degree correction on the
## model, so the question is empirical:
##   +Z rolls the blade upright, tip toward the sky and close to the body;  -Z lays it out flat
##   +Y swings the arm ACROSS the chest to the character's left;  -Y DROPS it to their right
## So Y is the one that raises and lowers, which is not what the name suggests — this is exactly
## why the mapping is rendered rather than assumed.
##   X mostly rolls the wrist and is the least useful of the three, so it stays at 0
## Re-run the axes mode before changing any of these, and the shots mode after.
@export_group("Poses (degrees, skeleton space)")
@export var up_euler := Vector3(0.0, 20.0, 78.0)      ## overhead — blade high, tip to the sky
@export var down_euler := Vector3(0.0, -75.0, 0.0)    ## low — arm dropped, blade across the knees
@export var left_euler := Vector3(0.0, 70.0, 58.0)    ## across the chest, covering the left
@export var right_euler := Vector3(0.0, -30.0, 62.0)  ## out on the sword side, tip up

## 0 = pure animation, 1 = full guard. Eased by the Guard state so the arm rises rather than snaps.
var amount := 0.0

## Which pose to hold. SwingDir.NONE leaves the clip alone entirely.
var dir := SwingDir.NONE

var _idx := -2                         ## -2 = not looked up yet, -1 = this rig has no such bone


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or amount <= 0.001 or dir == SwingDir.NONE:
		return
	if _idx == -2:
		_idx = skel.find_bone(bone)
	if _idx < 0:
		return

	# Scaling the angle BY the blend is what makes the raise continuous: at amount 0.3 the arm is
	# three tenths of the way to the guard, on top of whatever the clip is doing underneath.
	var e: Vector3 = euler_for(dir) * amount
	var offset := Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))

	# Compose in SKELETON space, then convert back to the bone's own parent space, which is the
	# only space set_bone_pose_rotation accepts. Rotating the local pose directly would apply the
	# angles in whatever frame the rig's bind pose happens to use, and that frame differs per rig —
	# the retargeted bodies here would each guard in a different direction.
	var g := skel.get_bone_global_pose(_idx)
	var posed := offset * g.basis
	var parent := skel.get_bone_parent(_idx)
	if parent >= 0:
		posed = skel.get_bone_global_pose(parent).basis.inverse() * posed
	skel.set_bone_pose_rotation(_idx, posed.orthonormalized().get_rotation_quaternion())


## The authored offset for a direction. Public so the probe can assert the four are distinct — a
## typo that gave two directions the same pose would make the mechanic unreadable while every
## damage test still passed.
func euler_for(d: int) -> Vector3:
	match d:
		SwingDir.UP:
			return up_euler
		SwingDir.DOWN:
			return down_euler
		SwingDir.LEFT:
			return left_euler
		SwingDir.RIGHT:
			return right_euler
	return Vector3.ZERO

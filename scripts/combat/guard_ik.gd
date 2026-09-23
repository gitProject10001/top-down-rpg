extends GuardPose
## Reach-limited two-bone guard; the clavicle stays in the authored stance.
var _hand_target:=Vector3.ZERO
var _initialized:=false
var _weight:=0.0
var _impact_at := -10.0
var _impact_strength := 0.0
var _deflect := false

func contact_recoil(parried := false) -> void:
	_impact_at = Time.get_ticks_msec() / 1000.0
	_impact_strength = .7 if parried else 1.0
	_deflect = parried
func _process_modification() -> void:
	var skel:=get_skeleton()
	if skel==null: return
	var fighter: Node=skel
	while fighter and not fighter is Player: fighter=fighter.get_parent()
	if not fighter: return
	var attack: Node=fighter.get_node_or_null("StateMachine/DirAttack")
	var phase:float=attack.pose_fraction() if attack != null and fighter.state_name()=="DirAttack" else -1.0
	var attacking:=phase>=0.0
	_weight=amount
	var pose_dir:int=dir
	if attacking:
		pose_dir=attack.pending_dir()
		# The sword clip owns the attack. IK corrects it, never replaces its arc.
		_weight=.25*clampf(phase/.18,0,1)*clampf((1.0-phase)/.18,0,1)
	if _weight<.001 or pose_dir==SwingDir.NONE:
		_initialized=false
		return
	var upper:=skel.find_bone("RightUpperArm")
	var lower:=skel.find_bone("RightLowerArm")
	var hand:=skel.find_bone("RightHand")
	if upper<0 or lower<0 or hand<0: return
	var a:=skel.get_bone_global_pose(upper).origin
	var b:=skel.get_bone_global_pose(lower).origin
	var c:=skel.get_bone_global_pose(hand).origin
	var frame: Basis=skel.global_basis.inverse()*fighter.visuals.global_basis.orthonormalized()
	var offset:=hand_offset(pose_dir)
	var blade_vector:=blade_direction(pose_dir)
	var age := Time.get_ticks_msec()/1000.0-_impact_at
	var recoil := _impact_strength * clampf(age/.035,0,1) * pow(maxf(0,1.0-age/.26),2)
	if not attacking:
		# Absorb in elbow/wrist, then settle. Keep the hilt ahead of the face.
		offset += Vector3(.015,-.025,.055)*recoil
		blade_vector = blade_vector.rotated(Vector3.RIGHT, -.16*recoil)
		if _deflect:
			var side := -1.0 if pose_dir == SwingDir.LEFT else 1.0
			offset.x += side*.075*recoil
			blade_vector = blade_vector.rotated(Vector3.FORWARD,side*.25*recoil)
	if attacking:
		var progress:=smoothstep(.29,.73,phase)
		var poses:=attack_arc(pose_dir)
		offset=poses[0].lerp(poses[1],progress)
		blade_vector=poses[2].slerp(poses[3],progress)
	var desired:=a+frame*offset
	if not _initialized: _hand_target=c; _initialized=true
	_hand_target=desired if attacking else _hand_target.lerp(desired,1.0-exp(-16.0*get_process_delta_time()))
	var l1:=a.distance_to(b)
	var l2:=b.distance_to(c)
	var ray:=(_hand_target-a).normalized()
	var dist:=clampf(a.distance_to(_hand_target),absf(l1-l2)+.025,l1+l2-.025)
	var end:=a+ray*dist
	var pole:=frame*Vector3(.8,-.7,.1)
	pole=(pole-ray*pole.dot(ray)).normalized()
	var along:float=(l1*l1-l2*l2+dist*dist)/(2.0*dist)
	var elbow:=a+ray*along+pole*sqrt(maxf(0.0,l1*l1-along*along))
	_aim_bone(skel,upper,b-a,elbow-a)
	b=skel.get_bone_global_pose(lower).origin
	c=skel.get_bone_global_pose(hand).origin
	_aim_bone(skel,lower,c-b,end-b)
	if fighter._grips_ready:
		var direction:Vector3=fighter.visuals.global_basis.orthonormalized()*blade_vector
		var up:=Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP))>.9 else Vector3.UP
		var blade:=Basis.looking_at(direction.normalized(),up)
		var wrist:Basis=skel.global_basis.inverse()*blade*fighter._sword_grip.basis.inverse()
		var arm_weight := _weight
		# The available thrust is an adapted punch. Align only its wrist to the
		# blade axis; retain the authored shoulder, elbow and body extension.
		if attacking and pose_dir == SwingDir.DOWN:
			_weight = clampf(phase/.18,0,1)*clampf((1.0-phase)/.18,0,1)
		_set_bone_basis(skel,hand,wrist)
		_weight = arm_weight
	# The imported hook animation throws the free arm out horizontally. Keep it
	# bent in a protective counterbalance instead of reading as half a T-pose.
	var lu := skel.find_bone("LeftUpperArm")
	var ll := skel.find_bone("LeftLowerArm")
	var lh := skel.find_bone("LeftHand")
	if lu >= 0 and ll >= 0 and lh >= 0:
		var la := skel.get_bone_global_pose(lu).origin
		var lb := skel.get_bone_global_pose(ll).origin
		var lc := skel.get_bone_global_pose(lh).origin
		var target := la + frame * Vector3(.16, -.20, -.24)
		var lr := (target-la).normalized()
		var len1 := la.distance_to(lb)
		var len2 := lb.distance_to(lc)
		var reach := clampf(la.distance_to(target), absf(len1-len2)+.025, len1+len2-.025)
		var lp := frame * Vector3(-.8,-.65,.15)
		lp = (lp-lr*lp.dot(lr)).normalized()
		var x := (len1*len1-len2*len2+reach*reach)/(2.0*reach)
		var le := la+lr*x+lp*sqrt(maxf(0.0,len1*len1-x*x))
		_aim_bone(skel,lu,lb-la,le-la)
		lb = skel.get_bone_global_pose(ll).origin
		lc = skel.get_bone_global_pose(lh).origin
		_aim_bone(skel,ll,lc-lb,la+lr*reach-lb)
func _aim_bone(skel:Skeleton3D,index:int,from:Vector3,to:Vector3) -> void:
	var offset:=Basis(Quaternion(from.normalized(),to.normalized()))
	_set_bone_basis(skel,index,offset*skel.get_bone_global_pose(index).basis)
func _set_bone_basis(skel:Skeleton3D,index:int,basis:Basis) -> void:
	var parent:=skel.get_bone_parent(index)
	var local:Basis=skel.get_bone_global_pose(parent).basis.inverse()*basis
	skel.set_bone_pose_rotation(index,skel.get_bone_pose_rotation(index).slerp(local.orthonormalized().get_rotation_quaternion(),_weight))

func attack_arc(d:int) -> Array[Vector3]:
	match d:
		SwingDir.UP: return [Vector3(.04,.23,-.25),Vector3(-.06,-.31,-.40),Vector3(0,1,.20),Vector3(0,-.5,-1)]
		SwingDir.DOWN: return [Vector3(.10,-.21,-.12),Vector3(.02,-.10,-.55),Vector3(0,0,-1),Vector3(0,0,-1)]
		SwingDir.LEFT: return [Vector3(-.36,.03,-.24),Vector3(.23,-.12,-.36),Vector3(-.9,.1,-.4),Vector3(.9,-.15,-.4)]
	return [Vector3(.23,.04,-.25),Vector3(-.37,-.16,-.34),Vector3(.9,.1,-.4),Vector3(-.9,-.15,-.4)]
func hand_offset(d:int) -> Vector3:
	match d:
		SwingDir.UP: return Vector3(-.08,.17,-.44)
		SwingDir.DOWN: return Vector3(.04,-.26,-.43)
		SwingDir.LEFT: return Vector3(-.28,-.08,-.43)
	return Vector3(.20,-.07,-.43)
func blade_direction(d:int) -> Vector3:
	match d:
		SwingDir.UP: return Vector3(-1,.18,-.1)
		SwingDir.DOWN: return Vector3(-1,.10,-.25)
		SwingDir.LEFT: return Vector3(-.15,1,-.40)
	return Vector3(.15,1,-.40)
func euler_for(d:int) -> Vector3:
	return hand_offset(d)

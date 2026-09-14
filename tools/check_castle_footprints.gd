extends SceneTree
const F=preload("res://addons/castle_generator/footprints.gd")
const R=preload("res://addons/castle_generator/regeneration.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var a := PackedVector2Array([Vector2(0,0),Vector2(4,4),Vector2(3.8,4.2),Vector2(-0.2,0.2)])
 var b := PackedVector2Array()
 for p in a: b.append(p+Vector2(0,2))
 assert(F.distance(a,b)>1,"Overlapping AABBs must not reject separate oriented bodies")
 assert(F.distance(a,a)==0)
 var request=preload("res://addons/castle_generator/request.gd").new()
 var plan=preload("res://addons/castle_generator/planner.gd").generate(request).plan
 var group=preload("res://addons/castle_generator/materializer.gd").create(plan)
 var keep=group.get_node("Mastio"); var hall=group.get_node("CorpoServizi")
 keep.width=4; keep.depth=4; keep.position=Vector3(9,0,-15); keep.rotation.y=PI/4
 hall.width=4; hall.depth=4; hall.position=Vector3(18,0,-15)
 var container := Node3D.new(); container.name="Volumes"; keep.add_child(container)
 var volume=preload("res://addons/house_builder/volume.gd").new()
 volume.attached=false; volume.width=2; volume.depth=2; volume.position.z=3; container.add_child(volume)
 var local: Transform3D=volume.transform
 var proposal=R.propose(group,plan)
 assert(not proposal.has("error"),str(proposal))
 assert(proposal.snapshot.keep.footprints.shapes.size()==2)
 assert(volume.transform==local,"Preview must not mutate authoring transforms")
 var old_snapshot=R.state(group)
 volume.position.x=20
 assert(R.state(group)!=old_snapshot,"Accessory changes must invalidate stale previews")
 assert(R.propose(group,plan).has("error"),"Accessory crossing the enclosure must block regeneration")
 volume.position=Vector3.ZERO; volume.attached=true; volume.host_wall=0
 local=volume.transform
 var attached=F.collect(keep,keep.transform)
 assert(not attached.has("error") and attached.shapes.size()==2)
 assert(volume.transform==local)
 volume.attached=false; volume.position=Vector3(6,0,0); keep.rotation.y=0
 assert(R.propose(group,plan).has("error"),"Accessory must reserve passage to the other building")
 keep.scale=Vector3(2,1,1)
 assert(R.propose(group,plan).has("error"))
 group.free()
 print("CASTLE_ORIENTED_ACCESSORY_CLEARANCE_STALE_PREVIEW_PURITY_OK")
 quit()

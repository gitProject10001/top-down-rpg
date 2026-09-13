@tool
extends RefCounted
## Upper-level guards belong to the receiving floor, so cutaway follows that floor.
const Join=preload("res://addons/house_builder/mesh_join.gd")
static func append(mesh: ArrayMesh, stair: Node3D, elevation: float, material: Material) -> void:
	var half: float=stair.dimensions.x*0.5+0.08
	var front: float=stair.dimensions.z*0.5-0.10
	var back: float=-stair.dimensions.z*0.5-0.08
	var frame := Transform3D(stair.basis,Vector3(stair.position.x,elevation,stair.position.z))
	# Three solid timber panels; local -Z remains completely open for the landing.
	for side in [-1.0,1.0]:
		part(mesh,frame,Vector3(side*(half+0.06),0.42,(front+back)*0.5),Vector3(0.12,0.84,front-back),material)
		part(mesh,frame,Vector3(side*(half+0.06),0.87,(front+back)*0.5),Vector3(0.17,0.10,front-back),material)
	part(mesh,frame,Vector3(0,0.42,front+0.06),Vector3(half*2+0.24,0.84,0.12),material)
	part(mesh,frame,Vector3(0,0.87,front+0.06),Vector3(half*2+0.29,0.10,0.17),material)

static func part(mesh: ArrayMesh, frame: Transform3D, center: Vector3, size: Vector3, material: Material) -> void:
	var box := BoxMesh.new(); box.size=size; box.material=material
	Join.append(mesh,box,frame*Transform3D(Basis.IDENTITY,center),[])

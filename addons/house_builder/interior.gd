@tool
extends Node3D
const Door=preload("res://addons/house_builder/door.gd")
var levels: Array[Node3D]=[]
var doors: Array[Node3D]=[]
var partitions: Array[Dictionary]=[]
var height := 2.6
var timber: Material
var plaster: Material
func box(parent: Node3D,p: Vector3,size: Vector3,mat: Material,solid: bool=true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new(); shape.size=size
	mesh.mesh=shape; mesh.material_override=mat; mesh.position=p; parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new(); var collision := CollisionShape3D.new()
		var primitive := BoxShape3D.new(); primitive.size=size; collision.shape=primitive
		body.position=p; body.add_child(collision); parent.add_child(body)
	return mesh
func partition(parent: Node3D,a: Vector3,b: Vector3,thick: float,door_u: float=0.5) -> void:
	var length := a.distance_to(b)
	var right := (b-a).normalized()
	var frame := Node3D.new(); frame.transform=Transform3D(Basis(right,Vector3.UP,right.cross(Vector3.UP)),a)
	parent.add_child(frame)
	var center := clampf(length*door_u,0.8,length-0.8)
	var left := center-0.6
	var remaining := length-center-0.6
	box(frame,Vector3(left*0.5,height*0.5,0),Vector3(left,height,thick),plaster)
	box(frame,Vector3(center+0.6+remaining*0.5,height*0.5,0),Vector3(remaining,height,thick),plaster)
	box(frame,Vector3(center,height-0.15,0),Vector3(1.2,0.3,thick),plaster)
	for x in [center-0.65,center+0.65]: box(frame,Vector3(x,(height-0.3)*0.5,0),Vector3(0.10,height-0.3,thick+0.08),timber,false)
	var threshold := StandardMaterial3D.new()
	threshold.albedo_color=Color(0.48,0.39,0.25); threshold.roughness=0.9
	box(frame,Vector3(center,0.057,0),Vector3(1.2,0.012,thick+0.30),threshold,false)
	var door := Door.new(); frame.add_child(door)
	door.configure(Transform3D(Basis.IDENTITY,Vector3(center-0.6,0,0)),1.2,height-0.3,timber)
	doors.append(door)
	var pieces: Array=[]
	for child in frame.get_children():
		if child is MeshInstance3D: pieces.append({"mesh":child,"bottom":child.position.y-child.mesh.size.y*0.5,"height":child.mesh.size.y})
	partitions.append({"frame":frame,"pieces":pieces,"door":door,"center":center})
func build(w: float,d: float,storey_height: float,count: int,split_x: float,split_z: float,thickness: float,wood: Material,wall: Material) -> void:
	height=storey_height; timber=wood; plaster=wall
	for child in get_children(): child.free()
	levels.clear(); doors.clear(); partitions.clear()
	var floor_mat := StandardMaterial3D.new(); floor_mat.albedo_color=Color(0.29,0.19,0.105); floor_mat.roughness=0.94
	var alternate := StandardMaterial3D.new(); alternate.albedo_color=Color(0.34,0.23,0.13); alternate.roughness=0.95
	var stair_start := d*0.5-0.6
	var stair_end := stair_start-4.2
	var stair_x := w*0.5-0.95
	for level in count:
		var node := Node3D.new(); node.name="Piano_%d"%(level+1); node.position.y=level*height
		add_child(node); levels.append(node)
		# Board geometry preserves metre scale and leaves an upper stairwell.
		var row := 0
		var z := -d*0.5+0.25
		while z<d*0.5-0.25:
			var length := w-0.5
			if level>0 and z>stair_end-0.2 and z<stair_start+0.2: length-=1.45
			box(node,Vector3(-w*0.5+0.25+length*0.5,0,z),Vector3(length,0.10,0.235),floor_mat if row%3 else alternate)
			z+=0.25; row+=1
		var x := lerpf(-w*0.5+1.8,w*0.5-2.2,split_x)
		var wall_z := lerpf(-d*0.5+2.0,d*0.5-2.0,split_z)
		# Three rooms; a broad hall on the right retains the staircase route.
		partition(node,Vector3(x,0,-d*0.5+0.25),Vector3(x,0,d*0.5-0.25),thickness,0.67)
		partition(node,Vector3(-w*0.5+0.25,0,wall_z),Vector3(x,0,wall_z),thickness)
		if level<count-1:
			var stairs := Node3D.new(); stairs.name="Scala"; node.add_child(stairs)
			for step in 18:
				var rise := (step+1)*height/18.0
				box(stairs,Vector3(stair_x,rise*0.5,stair_start-(step+0.5)*4.2/18.0),Vector3(1.2,rise,4.2/18.0),timber,false)
			# Smooth collision ramp lets the existing CharacterBody climb the steps.
			var hull := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for side in [-0.6,0.6]:
				points.append(Vector3(stair_x+side,0,stair_start))
				points.append(Vector3(stair_x+side,0,stair_end))
				points.append(Vector3(stair_x+side,height+0.05,stair_end))
			hull.points=points
			var body := StaticBody3D.new(); var shape := CollisionShape3D.new(); shape.shape=hull
			body.add_child(shape); stairs.add_child(body)
func show_level(index: int,inside: bool) -> void:
	for i in levels.size(): levels[i].visible=inside and i<=index
func reveal_room(actor: Vector3,camera: Vector3) -> void:
	for partition_data in partitions:
		var frame: Node3D=partition_data.frame
		var a := frame.to_local(actor)
		var c := frame.to_local(camera)
		var near_door: bool=absf(a.z)<1.6 and absf(a.x-partition_data.center)<1.5
		var cut := (a.z*c.z<0.0 or near_door) and a.y>-0.1 and a.y<height+0.1
		for piece in partition_data.pieces:
			var visible_height: float=minf(piece.height,maxf(0.8-piece.bottom,0.0)) if cut else piece.height
			piece.mesh.visible=visible_height>0.001
			piece.mesh.scale.y=visible_height/piece.height
			piece.mesh.position.y=piece.bottom+visible_height*0.5
		partition_data.door.set_cutaway(cut)

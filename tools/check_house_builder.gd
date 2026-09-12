extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
func _initialize() -> void: call_deferred("run")
func intersects(faces: PackedVector3Array,a: Vector3,b: Vector3) -> bool:
	for i in range(0,faces.size(),3):
		if Geometry3D.segment_intersects_triangle(a,b,faces[i],faces[i+1],faces[i+2])!=null: return true
	return false
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var house := House.new()
	house.name="Casa"
	world.add_child(house)
	house.owner=world
	house.openings=[{"kind":"door","wall":0,"u":-0.35},{"kind":"window","wall":0,"u":0.45,"y":1.55},{"kind":"window","wall":2,"u":0.25,"y":1.55}]
	for dimensions in [Vector4(4.2,5,2.6,2.1),Vector4(8,12,3.2,2.7),Vector4(1.8,1.8,1.8,0.5)]:
		house.set_dimensions(dimensions)
		house.rebuild()
		var mesh: Mesh=house._generated.get_node("Roof").mesh
		assert(mesh.get_aabb().size.x>house.width)
		assert(mesh.get_aabb().size.z>house.depth)
		var vertices: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in vertices: assert(v.is_finite())
		for o in house.openings:
			var resolved := house.resolved_opening(o)
			assert(absf(resolved.along)+resolved.width*0.5<house.wall_length(resolved.wall)*0.5)
		print("HOUSE_SIZE_OK ",dimensions," vertices=",vertices.size())
	house.set_dimensions(Vector4(4.2,6.5,2.6,2.1))
	house.rotation.y=0.6
	house.rebuild()
	var hit := house.hit_wall(house.to_global(Vector3(0,1.4,8)),house.global_basis*Vector3.FORWARD)
	assert(not hit.is_empty() and hit.wall==0)
	house.wing_enabled=true
	house.openings.append({"kind":"window","wall":4,"u":0.0,"y":1.5})
	for side in 2:
		for anchor in 2:
			house.wing_side=side; house.wing_anchor=anchor
			var started := Time.get_ticks_msec()
			house.rebuild()
			var roof: Mesh=house._generated.get_node("Roof").mesh
			assert(roof.get_surface_count()==2,"Both intersecting roofs survive")
			for surface in roof.get_surface_count():
				var arrays := roof.surface_get_arrays(surface)
				for vertex in arrays[Mesh.ARRAY_VERTEX]: assert(vertex.is_finite())
			var point := house.wall_point(4,0,1.5)
			var normal := house.wall_normal(4)
			var wing_hit := house.hit_wall(house.to_global(point+normal*4.0),house.global_basis*(-normal))
			assert(not wing_hit.is_empty() and wing_hit.wall==4,"Rotated outer wing wall can be picked")
			assert(house.opening_fits({"kind":"window","wall":4,"u":0.0,"y":1.5},house.openings.size()-1))
			# The main wall inside the attachment cannot receive a new opening.
			var inner_wall := 2 if side==0 else 3
			var z: float=house.wing_transform().origin.z
			assert(not house.wall_exposed(inner_wall,-z if side==0 else z))
			# Collision follows the shell; the L notch remains empty.
			var notch := Vector3((house.width*0.5+1.0)*(1.0 if side==0 else -1.0),1.0,-house.depth*0.45*(1.0 if anchor==0 else -1.0))
			for child in house._generated.get_children():
				if not child is StaticBody3D: continue
				for shape in child.get_children():
					if not shape is CollisionShape3D or not shape.shape is ConcavePolygonShape3D: continue
					assert(not intersects(shape.shape.get_faces(),notch+Vector3.UP*10,notch-Vector3.UP*2),"L notch must remain walkable")
			var wall_faces: PackedVector3Array=house._generated.get_node("Walls").mesh.get_faces()
			assert(not intersects(wall_faces,point+normal*0.4,point-normal*0.4),"Wing opening cuts both wall faces")
			var solid := house.wall_point(4,0.8,1.5)
			assert(intersects(wall_faces,solid+normal*0.4,solid-normal*0.4),"Solid wall remains beside the opening")
			print("HOUSE_L_JOIN_OK side=",side," anchor=",anchor," build_ms=",Time.get_ticks_msec()-started)
	for dimensions in [Vector4(4.2,6.5,2.6,0.5),Vector4(3,6,2.6,2),Vector4(1.8,1.8,1.8,0.5)]:
		house.set_dimensions(dimensions)
		house.rebuild()
		var roof: Mesh=house._generated.get_node("Roof").mesh
		assert(roof.get_surface_count()==2)
		for surface in roof.get_surface_count():
			for vertex in roof.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: assert(vertex.is_finite())
		print("HOUSE_L_LOW_EQUAL_MIN_ROOFS_OK ",dimensions)
	house.set_dimensions(Vector4(4.2,6.5,2.6,2.1))
	house.wing_enabled=false
	house.openings=[{"kind":"door","wall":0,"u":0.0,"width":1.3,"height":2.0},{"kind":"window","wall":2,"u":0.0,"width":1.6,"height":1.2,"y":1.5}]
	house.rebuild()
	var faces: PackedVector3Array=house._generated.get_node("Walls").mesh.get_faces()
	for record in house.openings:
		var o := house.resolved_opening(record)
		var normal := house.wall_normal(o.wall)
		for y in [0.08 if o.door else o.y-0.3,o.y,o.y+0.3]:
			var point := house.wall_point(o.wall,o.along,y)
			assert(not intersects(faces,point+normal*0.4,point-normal*0.4),"No plaster, foundation or beam across the opening")
	var before_faces := faces
	house.openings=[]; house.rebuild()
	faces=house._generated.get_node("Walls").mesh.get_faces()
	assert(intersects(faces,Vector3(0,1,house.depth*0.5+0.4),Vector3(0,1,house.depth*0.5-0.4)),"Removing the door restores the wall")
	assert(before_faces.size()!=faces.size())
	print("HOUSE_REAL_OPENINGS_REVEALS_REMOVE_OK")
	house.wing_enabled=true; house.wing_side=0; house.wing_anchor=0
	house.openings=[{"kind":"window","wall":0,"u":0.5,"width":1.3,"height":1.4,"y":1.5},{"kind":"door","wall":4,"u":0.0,"width":1.1,"height":2.1}]
	# Same front facade, represented by another volume's wall id.
	var coplanar_wall := 7
	var front_point := house.wall_point(0,house.width*0.25,1.5)
	var local_front := house.wing_transform().affine_inverse()*front_point
	assert(not house.opening_fits({"kind":"window","wall":coplanar_wall,"u":local_front.z/(house.wall_length(coplanar_wall)*0.5),"y":1.5}),"Reject overlaps across coplanar volume walls")
	house.rebuild()
	var packed := PackedScene.new()
	assert(packed.pack(world)==OK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/house_builder"))
	assert(ResourceSaver.save(packed,"res://captures/house_builder/roundtrip.tscn")==OK)
	var loaded=load("res://captures/house_builder/roundtrip.tscn").instantiate()
	root.add_child(loaded)
	assert(loaded.get_node("Casa").openings==house.openings)
	assert(loaded.get_node("Casa").dimensions()==house.dimensions())
	assert(loaded.get_node("Casa").wing_settings()==house.wing_settings())
	assert(loaded.get_node("Casa")._generated.get_node("Roof").mesh!=null)
	print("HOUSE_ROUNDTRIP_OK dimensions/openings + regenerated mesh")
	loaded.free()
	world.free()
	quit()

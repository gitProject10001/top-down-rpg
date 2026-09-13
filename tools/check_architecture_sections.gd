extends SceneTree
const Sections=preload("res://scripts/village/architecture_sections.gd")
const Join=preload("res://addons/house_builder/mesh_join.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var sections=Sections.new()
 var mesh=ArrayMesh.new()
 # Separate front/back wall skins: the central room must remain empty.
 for z in [-2.0,2.0]:
  var box=BoxMesh.new(); box.size=Vector3(4,4,0.4)
  Join.append(mesh,box,Transform3D(Basis.IDENTITY,Vector3(0,0,z)),[])
 var tree=mesh.generate_triangle_mesh()
 var spans=sections.intervals(tree,tree.get_faces(),Vector3(0.13,0.17,-10),Vector3.BACK)
 assert(spans.size()==2,"Do not cap the empty room between the two wall skins")
 assert(is_equal_approx(spans[0].y-spans[0].x,0.4))
 assert(spans[1].x-spans[0].y>3.5)
 # A doorway ray crosses no masonry; off-center rays hit both jambs.
 mesh=ArrayMesh.new()
 for x in [-2.0,2.0]:
  var box=BoxMesh.new(); box.size=Vector3(1,4,2)
  Join.append(mesh,box,Transform3D(Basis.IDENTITY,Vector3(x,0,0)),[])
 tree=mesh.generate_triangle_mesh()
 assert(sections.intervals(tree,tree.get_faces(),Vector3(0,0,-10),Vector3.BACK).is_empty())
 spans=sections.intervals(tree,tree.get_faces(),Vector3(2,0,-10),Vector3.BACK)
 assert(spans.size()==1 and is_equal_approx(spans[0].y-spans[0].x,2.0))
 var source=MeshInstance3D.new(); source.mesh=BoxMesh.new(); root.add_child(source)
 source.rotation.y=0.7
 var frame=Sections.cut_frame(source,Vector3.ZERO,Vector3(10,10,10))
 assert(frame.basis.x.is_equal_approx(source.global_basis.x))
 assert(frame.basis.y.is_equal_approx(Vector3.UP))
 assert(absf(frame.basis.z.dot(frame.basis.x))<0.0001)
 source.free()
 sections.free()
 print("ARCHITECTURE_SECTION_ROOM_VOID_DOORWAY_THICKNESS_OK")
 quit()

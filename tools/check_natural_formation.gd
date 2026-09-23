extends SceneTree
const Outcrop=preload("res://addons/rock_builder/outcrop.gd")
const Natural=preload("res://addons/rock_builder/natural_formation.gd")
var failures := 0
func check(value: bool,label: String) -> void:
 if not value: failures+=1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var n := Outcrop.new(); n.formation_style=1; n.walkable=false; n.height=5; root.add_child(n)
 var a := Natural.masses(n,n.rings())
 var b := Natural.masses(n,n.rings())
 check(a==b,"deterministic major masses")
 check(a.size()>3 and a.size()<40,"macro composition uses few dominant masses")
 for r in a:
  if r.layer!="large": continue
  check(r.transform.basis.x.length()>2.0,"broad fracture faces instead of pebble coating")
  check(absf(r.transform.origin.y+0.12)<0.001,"masses rooted at ground instead of stacked tiles")
 var initial_meshes := n._rock_cache.duplicate()
 n.height=7; n.rebuild()
 for key in initial_meshes:
  check(n._rock_cache[key]==initial_meshes[key],"source meshes reused after height edit")
 n.scale=Vector3(4,1,1)
 var stretched := Natural.masses(n,n.rings())
 check(stretched.size()>a.size(),"widening envelope adds masses rather than stretching existing rocks")
 n.scale=Vector3.ONE
 # Both authoring height and transform Y must avoid a population explosion.
 n.shape_kind=2; n.volume_size=Vector2(7,13); n.height=4
 var normal_count := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large").size()
 for size in [Vector2(7,13),Vector2(13,7),Vector2(4,20),Vector2(18,18)]:
  n.volume_size=size; n.height=4
  var medium_count := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large").size()
  for low_height in [0.3,0.65,1.5]:
   n.height=low_height
   var low := Natural.masses(n,n.rings())
   var low_count := low.filter(func(r): return r.layer=="large").size()
   check(low_count<=medium_count,"lower height does not multiply major masses")
  n.height=4; n.scale=Vector3(1,0.16,1)
  var low_count := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large").size()
  check(low_count<=medium_count,"lower transform Y does not multiply major masses")
  n.scale=Vector3.ONE
 n.volume_size=Vector2(7,13); n.height=4
 var layered := Natural.masses(n,n.rings())
 check(layered.any(func(r): return r.layer=="medium"),"composition includes subordinate shelves")
 check(layered.any(func(r): return r.layer=="small"),"composition includes sparse foot chips")
 print("COMPOSITION medium_primary=",normal_count," shelves=",layered.filter(func(r): return r.layer=="medium").size()," chips=",layered.filter(func(r): return r.layer=="small").size())
 # Independent controls: more footprint adds masses while source width stays in metres.
 n.volume_size=Vector2(7,13); n.height=6; n.natural_rock_size=5.5
 var short := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large")
 n.volume_size=Vector2(7,26)
 var extended := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large")
 check(extended.size()>short.size(),"longer envelope adds primary rocks")
 for r in extended:
  check(r.transform.basis.x.length()>=5.5*0.85-0.01 and r.transform.basis.x.length()<=5.5*1.35+0.01,"elongation preserves horizontal source size")
 n.volume_size=Vector2(7,13); n.scale=Vector3(1,1,2)
 var scaled := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large")
 check(scaled.size()>short.size(),"native transform elongation also adds rocks")
 for r in scaled:
  var world_basis: Basis=Basis.from_scale(n.scale)*r.transform.basis
  check(world_basis.z.length()>=5.5*0.7-0.01 and world_basis.z.length()<=5.5*1.15+0.01,"native scaling preserves horizontal source size")
 n.scale=Vector3.ONE; n.volume_size=Vector2(7,26); n.natural_density=0.5
 var thinned := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large")
 check(thinned.size()<extended.size(),"density removes candidates")
 for r in thinned:
  check(extended.any(func(original): return original==r),"density does not move or resize retained rocks")
 n.natural_density=1; n.natural_max_rocks=3
 check(Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large").size()==3,"primary count cap excludes secondary decoration")
 n.natural_max_rocks=0; n.natural_min_spacing=6
 var separated := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large")
 for j in separated.size():
  for k in j:
   var delta: Vector3=separated[j].transform.origin-separated[k].transform.origin
   check(Vector2(delta.x,delta.z).length()>=5.999,"minimum spacing is independent of size")
 n.natural_min_spacing=0; n.volume_size=Vector2(7,13)
 print("DISTRIBUTION short=",short.size()," extended=",extended.size()," native_scaled=",scaled.size()," density_half=",thinned.size())
 var before_layers := Natural.masses(n,n.rings()).filter(func(r): return r.layer=="large")
 n.medium_rock_density=0; n.small_rock_density=0
 var shape_only := Natural.masses(n,n.rings())
 check(shape_only==before_layers,"disabling layers preserves primary shape")
 n.small_rock_density=1; n.small_surface_ratio=1; n.small_rock_size=0.25
 var layered_surface := Natural.masses(n,n.rings())
 check(layered_surface.filter(func(r): return r.layer=="large")==before_layers,"surface detail never changes primary shape")
 check(layered_surface.any(func(r): return r.layer=="small" and r.transform.origin.y>0.5),"small layer can sit on parent surfaces")
 n.medium_rock_density=0.38; n.small_rock_density=0.3; n.small_surface_ratio=0.55; n.small_rock_size=0.4
 n.shape_kind=0; n.height=7
 n.natural_detail=false; n.rebuild()
 check(n._rocks.get_child_count()==0,"control envelope can be inspected alone")
 n.walkable=true; n.holes=[PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)])]; n.rebuild()
 await physics_frame; await physics_frame
 var query := PhysicsRayQueryParameters3D.create(Vector3(0,20,0),Vector3(0,-2,0))
 check(root.world_3d.direct_space_state.intersect_ray(query).is_empty(),"natural envelope preserves hole collision")
 n.natural_detail=true; n.rebuild()
 check(not n.rock_keys.is_empty(),"detail restored")
 await physics_frame; await physics_frame
 check(root.world_3d.direct_space_state.intersect_ray(query).is_empty(),"detailed walkable formation preserves the opening")
 for point in [Vector2(-3,-2),Vector2(3,2),Vector2(0,3)]:
  var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,20,point.y),Vector3(point.x,-2,point.y)))
  check(not hit.is_empty() and absf(hit.position.y-n.height)<0.001,"walkable roof collision stays at authored height")
 for child in n._rocks.get_children():
  for vertex in child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
   check((child.transform*vertex).y<=n.height+0.001,"side rocks do not obstruct walkable roof")
 var saved := PackedScene.new(); saved.pack(n); var restored=saved.instantiate(); root.add_child(restored)
 check(restored.formation_style==1,"natural style serialized")
 restored.free(); n.formation_style=0; n.rebuild(); check(n.last_error.is_empty(),"switch back to constructed")
 n.free(); print("NATURAL_FORMATION failures=",failures); quit(1 if failures else 0)

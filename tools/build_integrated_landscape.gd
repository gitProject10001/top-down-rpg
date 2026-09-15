extends SceneTree
var scene:=Node3D.new()
func owned(node: Node) -> void:
    node.owner=scene
    if not node.scene_file_path.is_empty():return
    for child in node.get_children():owned(child)
func attach(node: Node,parent: Node=scene) -> void:
    parent.add_child(node);owned(node)
func guide(parent: Node,title: String,kind: int,points: PackedVector2Array,width: float=4) -> void:
    var node=load("res://addons/village_builder/guide.gd").new()
    node.name=title;node.stable_id=title;node.kind=kind;node.points=points;node.road_width=width
    attach(node,parent)
func _initialize() -> void:call_deferred("build")
func build() -> void:
    scene.name="IntegratedLandscape"
    var castle=load("res://addons/house_builder/open_castle_factory.gd").create()
    castle.name="CittaMurata";castle.position=Vector3(-52,.18,0)
    for tower in castle.towers():tower.position*=40.0/26.0
    castle.entry_position.x=20
    # Existing curtain tool allows gaps up to 19.8m: split long sides with towers.
    var links=castle.curtains().duplicate()
    for index in links.size():
        var wall=links[index]
        var host=wall.get_parent()
        var target=castle.get_node(str(wall.target_tower).trim_prefix("../../"))
        var middle=load("res://addons/house_builder/polygon_tower.gd").new()
        middle.name="TorreIntermedia_%d"%index;middle.width=8;middle.depth=8;middle.wall_height=5.6;middle.roof_height=1;middle.wall_finish=1
        middle.position=(host.position+target.position)*.5;castle.add_child(middle)
        var next=load("res://addons/house_builder/curtain_wall.gd").new()
        next.name="Cortina";next.connect_to_tower=true;next.tower_face=wall.tower_face;next.target_face=wall.target_face;next.target_tower=NodePath("../../"+str(target.name));next.gate_enabled=false
        middle.add_child(next)
        wall.target_tower=NodePath("../../"+str(middle.name))
        if wall.gate_enabled:
            wall.gate_open=true
            castle.entry_position.x=10
    for child in castle.get_children():
        if child.name not in ["CorpoServizi"] and child not in castle.towers():child.position=Vector3(10,0,-30)
    attach(castle)
    for i in 6:
        var house=load("res://addons/house_builder/house.gd").new()
        house.name="CasaCitta_%02d"%i;house.position=Vector3(-40+(i%3)*10,.18,-20+(i/3)*9)
        house.width=5+i%2;house.depth=6;house.wall_height=3.0+(i%3)*.6;house.house_seed=900+i
        var openings: Array[Dictionary]=[{"kind":"door","wall":0,"width":1.3,"height":2.1},{"kind":"window","wall":0,"offset":1.8,"width":.8,"height":1.0,"sill":1.5}]
        house.openings=openings;attach(house)
    var roads=load("res://addons/village_builder/village.gd").new();roads.name="StradeCitta";roads.show_zones=false;roads.position.y=.18;attach(roads)
    guide(roads,"Piazza",4,PackedVector2Array([Vector2(-40,-9),Vector2(-22,-9),Vector2(-22,0),Vector2(-40,0)]))
    guide(roads,"ViaPorta",1,PackedVector2Array([Vector2(-42,-8),Vector2(-42,9),Vector2(-22,16),Vector2(-5,22)]),5)
    var village=load("res://addons/village_builder/village.gd").new();village.name="Borgo";village.position=Vector3(24,.18,23);village.max_houses=10;village.show_zones=false;attach(village)
    guide(village,"Perimetro",0,PackedVector2Array([Vector2(-15,-13),Vector2(26,-13),Vector2(26,26),Vector2(-15,26)]))
    guide(village,"StradaBorgo",1,PackedVector2Array([Vector2(-12,0),Vector2(8,3),Vector2(22,20)]),4)
    var river=load("res://addons/water_builder/river.gd").new();river.name="Fiume";river.basin_depth=.22;river.flow_speed=.85;river.widths=PackedFloat32Array([7,9,8,10,9]);attach(river)
    var path:=Path3D.new();path.name="FlowGuide";path.curve=Curve3D.new()
    for point in [Vector3(-1,0,-66),Vector3(2,0,-35),Vector3(-1,0,-8),Vector3(4,0,21),Vector3(0,0,65)]:path.curve.add_point(point,Vector3(0,0,-5),Vector3(0,0,5))
    attach(path,river)
    var lake=load("res://addons/water_builder/water_body.gd").new();lake.name="Lago";lake.position=Vector3(34,0,-26);lake.flow_speed=.08;lake.basin_depth=.35
    var polygon:=PackedVector2Array()
    for i in 16:
        var angle:=i*TAU/16;polygon.append(Vector2(cos(angle)*23,sin(angle)*20))
    lake.boundary=polygon;attach(lake)
    var rocks:=Node3D.new();rocks.name="Rocks";attach(rocks,river)
    for i in 5:
        var rock=load("res://addons/rock_builder/rock.gd").new();rock.name="RocciaFiume_%d"%i;rock.position=Vector3(1,-.2,-40+i*20);rock.dimensions=Vector3(2.2,1.5,2);rock.rock_seed=45+i;attach(rock,rocks)
    var forest:=Node3D.new();forest.name="Boschi";attach(forest)
    var rng:=RandomNumberGenerator.new();rng.seed=712
    for i in 190:
        var p:=Vector2(rng.randf_range(-69,68),rng.randf_range(-65,65))
        if absf(p.x)<10 or Rect2(-58,-46,53,66).has_point(p) or Rect2(8,8,50,46).has_point(p) or ((p-Vector2(34,-26))/Vector2(27,24)).length()<1:continue
        var tree=load("res://scenes/props/study_pine.tscn" if i%3 else "res://scenes/props/study_broadleaf.tscn").instantiate()
        tree.name="Albero_%03d"%i;tree.position=Vector3(p.x,.18,p.y);tree.scale=Vector3.ONE*rng.randf_range(.65,1.05);attach(tree,forest)
    var formations: Array=[]
    for index in 2:
        var formation=load("res://addons/rock_builder/formation.gd").new()
        formation.name="Affioramento_%d"%index;formation.position=Vector3(-67+index*82,0,-58);formation.spacing=6;formation.wall_height=5;formation.curve=Curve3D.new()
        formation.curve.add_point(Vector3.ZERO);formation.curve.add_point(Vector3(38,0,0))
        attach(formation);formations.append(formation)
    root.add_child(scene)
    for i in 4:await process_frame
    for formation in formations:
        var proposal: Dictionary=formation.proposal();assert(not proposal.has("error"),str(proposal))
        formation.apply(proposal)
        for child in formation.get_children():owned(child)
    village.apply(village.propose())
    for lot in village.lots():owned(lot)
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for z in range(-72,72,2):
        for x in range(-76,76,2):
            for offset in [Vector2(0,0),Vector2(2,0),Vector2(0,2),Vector2(2,0),Vector2(2,2),Vector2(0,2)]:
                var p: Vector2=Vector2(x,z)+offset
                var y: float=minf(river.bed_height(p),lake.bed_height(p-Vector2(34,-26)))
                st.set_color(Color(.27,.31,.16) if y>.1 else Color(.37,.32,.21));st.add_vertex(Vector3(p.x,y,p.y))
    st.generate_normals()
    var ground:=MeshInstance3D.new();ground.name="TerrenoComposto";ground.mesh=st.commit()
    var mat:=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.vertex_color_is_srgb=true;mat.roughness=1;ground.material_override=mat
    attach(ground);ground.create_trimesh_collision()
    for child in ground.get_children():owned(child)
    scene.set_script(load("res://scripts/village/integrated_landscape.gd"))
    var packed:=PackedScene.new();assert(packed.pack(scene)==OK)
    assert(ResourceSaver.save(packed,"res://scenes/dev/integrated_landscape.tscn")==OK)
    print("INTEGRATED_SAVED houses=",village.lots().size()+6," trees=",forest.get_child_count())
    quit()


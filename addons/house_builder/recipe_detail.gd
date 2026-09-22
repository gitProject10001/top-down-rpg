@tool
extends Node3D
signal rebuilt
## Original procedural building details. The component and its transform are the
## authored object; only _GeneratedRecipeDetail is disposable cached geometry.
const KINDS := ["chimney", "bell_gable", "shop_counter_goods", "forge_workbench", "firewood", "trough", "fence", "hanging_sign", "dormer", "gothic_facade", "gothic_bell_tower", "gothic_buttress", "gothic_window", "market_awning", "wall_ivy", "stone_apron"]
const ROOF_KINDS := ["chimney", "bell_gable", "dormer", "gothic_window"]
const MASONRY_CUTAWAY_KINDS := ["wall_ivy", "gothic_facade", "gothic_bell_tower", "gothic_buttress", "market_awning"]
const CUTAWAY_HEIGHT := 1.05
const DEFAULT_COLORS := [Color(.29,.20,.12), Color(.47,.45,.38), Color(.19,.21,.20), Color(.64,.52,.29), Color(.40,.21,.12), Color(.59,.43,.23), Color(.085,.085,.072)]
enum Surface { WOOD, STONE, METAL, PAINT, CLAY, GOODS, DARK }
const MasonryFinish=preload("res://addons/house_builder/masonry_finish.gd")
@export var masonry_finish: MasonryFinish:
	set(value):
		if masonry_finish and masonry_finish.changed.is_connected(request_rebuild): masonry_finish.changed.disconnect(request_rebuild)
		masonry_finish=value
		if masonry_finish and not masonry_finish.changed.is_connected(request_rebuild): masonry_finish.changed.connect(request_rebuild)
		request_rebuild()

@export_enum("chimney", "bell_gable", "shop_counter_goods", "forge_workbench", "firewood", "trough", "fence", "hanging_sign", "dormer", "gothic_facade", "gothic_bell_tower", "gothic_buttress", "gothic_window", "market_awning", "wall_ivy", "stone_apron") var kind := "chimney":
	set(value): kind = value; request_rebuild()
@export var dimensions := Vector3(.75, 1.7, .75):
	set(value): dimensions = value.max(Vector3.ONE * .05); request_rebuild()
## Zero preserves the original facade. Positive depth builds a stepped stone reveal.
@export_range(0.0, 1.5, .01, "suffix:m") var portal_recess_depth := 0.0:
	set(value): portal_recess_depth = clampf(value,0.0,1.5); request_rebuild()
## Depth of the rose glass behind the facade; zero retains the legacy relief.
@export_range(0.0, .65, .01, "suffix:m") var rose_recess_depth := 0.0:
	set(value): rose_recess_depth = clampf(value,0.0,.65); request_rebuild()
## Leaf coverage and manual exclusion rectangles in local metres (X/Y).
@export_range(0.0,2.0,.05) var growth_density := 1.0:
	set(value): growth_density=value; request_rebuild()
@export var growth_color := Color(.14,.245,.058):
	set(value): growth_color=value; request_rebuild()
@export_enum("Spreading", "Climbing") var growth_shape := 0:
	set(value): growth_shape=value; request_rebuild()
@export var surface_exclusions: Array[Rect2] = []:
	set(value): surface_exclusions=value; request_rebuild()
@export var detail_seed := 416522:
	set(value): detail_seed = value; request_rebuild()
@export var weathered := true:
	set(value): weathered = value; request_rebuild()
## Palette slots: wood, stone, metal, painted trim, clay, goods, dark recesses.
@export var palette := PackedColorArray():
	set(value): palette = value; request_rebuild()
@export_enum("auto", "wheat", "tankard", "anvil", "horse") var motif := "auto":
	set(value): motif = value; request_rebuild()
@export var collision_enabled := true:
	set(value): collision_enabled = value; request_rebuild()
## Recipe service respects these; direct Inspector edits still regenerate.
@export var locked := false
@export var detail_id := ""
@export var regenerate := false:
	set(value):
		if value: request_rebuild()
@export_storage var authoring_version := 1

var build_count := 0
var triangle_count := 0
var _pending := false
var _cutaway := false
var _generated: Node3D
var _tools: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _collision_records: Array[Dictionary] = []

static func default_dimensions(detail_kind: String) -> Vector3:
	return {"chimney": Vector3(.75,1.7,.75), "bell_gable": Vector3(1.6,2.15,.6),
		"shop_counter_goods": Vector3(2.25,1.35,.85), "forge_workbench": Vector3(2.35,1.55,1.35),
		"firewood": Vector3(1.65,.95,.85), "trough": Vector3(1.9,.65,.7),
		"fence": Vector3(2.8,1.15,.18), "hanging_sign": Vector3(.9,1.0,.22),
		"dormer": Vector3(1.35,1.35,1.0), "gothic_facade": Vector3(10.6,6.7,.8),
		"gothic_bell_tower": Vector3(2.55,11.8,2.35), "gothic_buttress": Vector3(.72,5.1,1.0),
		"wall_ivy": Vector3(1.3,3.2,.3), "stone_apron": Vector3(2.4,.08,1.6),
		"gothic_window": Vector3(1.3,2.6,.3), "market_awning": Vector3(4.6,3.4,2.0)}.get(detail_kind, Vector3.ONE)

var _roof_signature := ""

func _ready() -> void:
	set_notify_local_transform(true)
	rebuild()

func _notification(what: int) -> void:
	if what==NOTIFICATION_LOCAL_TRANSFORM_CHANGED: _sync_roof_cutter()

func _exit_tree() -> void:
	if kind=="gothic_facade": _invalidate_host_roof()

func _invalidate_host_roof() -> void:
	var container := get_parent()
	if container and container.name=="RecipeDetails":
		var host := container.get_parent()
		if host and host.has_method("request_rebuild"): host.request_rebuild()

func _sync_roof_cutter() -> void:
	var signature := str(dimensions,transform) if kind=="gothic_facade" else ""
	if signature!=_roof_signature:
		_roof_signature=signature
		_invalidate_host_roof()

## Convex regions occupied by the stone gable trim, in the target roof frame.
## Only roof decoration is trimmed; walls and gameplay collision stay intact.
func roof_trim_cutters(target: Node3D) -> Array:
	var cutters: Array=[]
	if kind!="gothic_facade": return cutters
	for segment in preload("res://addons/house_builder/recipe_gothic.gd").gable_trim_segments(dimensions):
		var a: Vector3=segment[0]; var b: Vector3=segment[1]
		var axis := (b-a).normalized()
		var side := axis.cross(Vector3.FORWARD).normalized()
		var back := axis.cross(side).normalized()
		var frame := target.global_transform.affine_inverse()*global_transform*Transform3D(Basis(side,axis,back),(a+b)*.5)
		# A 15 mm joint avoids coplanar flicker along the stone's exposed edge.
		var half := Vector3(.09+.015,(b-a).length()*.5+.015,.13+.015)
		var planes: Array=[]
		for k in 3:
			var normal := Vector3.ZERO; normal[k]=1.0
			planes.append(frame*Plane(normal,half[k]))
			planes.append(frame*Plane(-normal,half[k]))
		cutters.append(planes)
	return cutters


func request_rebuild() -> void:
	if _pending: return
	_pending = true
	if is_inside_tree(): call_deferred("_flush_rebuild")

func _flush_rebuild() -> void:
	if _pending and is_inside_tree(): rebuild()

func rebuild() -> void:
	_pending = false
	if not is_inside_tree(): return
	# Never touch recipe siblings or manually added children.
	var old := get_node_or_null("_GeneratedRecipeDetail")
	if old:
		remove_child(old)
		old.queue_free()
	_generated = Node3D.new()
	_generated.name = "_GeneratedRecipeDetail"
	add_child(_generated, false, Node.INTERNAL_MODE_BACK)
	_tools.clear()
	_collision_records.clear()
	triangle_count = 0
	_rng.seed = detail_seed
	match kind:
		"chimney": _chimney()
		"bell_gable": _bell_gable()
		"shop_counter_goods": _shop()
		"forge_workbench": _forge()
		"firewood": _firewood()
		"trough": _trough()
		"fence": _fence()
		"hanging_sign": _sign()
		"dormer": _dormer()
		"gothic_facade", "gothic_bell_tower", "gothic_buttress", "gothic_window": preload("res://addons/house_builder/recipe_gothic.gd").build(self)
		"wall_ivy", "stone_apron": preload("res://addons/house_builder/recipe_growth.gd").build(self)
		"market_awning": preload("res://addons/house_builder/recipe_fabric.gd").build(self)
	var mesh := ArrayMesh.new()
	for surface in _tools:
		var tool: SurfaceTool = _tools[surface]
		tool.index()
		tool.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count()-1, _material(surface))
	_tools.clear()
	var visual := MeshInstance3D.new()
	visual.name = "DetailMesh"
	visual.mesh = mesh
	_generated.add_child(visual)
	if collision_enabled and not _collision_records.is_empty():
		var body := StaticBody3D.new()
		body.name = "DetailCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("recipe_detail_id", detail_id)
		_generated.add_child(body)
		for record in _collision_records:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = record.size * dimensions
			shape.shape = box
			shape.position = record.center * dimensions
			body.add_child(shape)
	if kind in MASONRY_CUTAWAY_KINDS:
		_build_cutaway_caps()
	_sync_roof_cutter()
	build_count += 1
	set_cutaway(_cutaway)
	update_gizmos()
	rebuilt.emit()

func set_cutaway(enabled: bool) -> void:
	_cutaway = enabled
	if is_instance_valid(_generated):
		var visual := _generated.get_node_or_null("DetailMesh") as MeshInstance3D
		if visual:
			visual.visible = not (enabled and kind in ROOF_KINDS)
			for surface in visual.mesh.get_surface_count():
				var mat := visual.mesh.surface_get_material(surface) as ShaderMaterial
				mat.set_shader_parameter("cutaway_enabled", enabled and kind in MASONRY_CUTAWAY_KINDS)
				mat.set_shader_parameter("cutaway_height", CUTAWAY_HEIGHT)
		var caps := _generated.get_node_or_null("CutawayCaps") as Node3D
		if caps: caps.visible = enabled

func _build_cutaway_caps() -> void:
	# Cut tall masonry above a visible, capped stump. The ground footprint remains
	# legible while its physical collision continues to match the exterior wall.
	var caps := Node3D.new()
	caps.name = "CutawayCaps"
	_generated.add_child(caps)
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = _color(Surface.WOOD if kind == "market_awning" else Surface.STONE,.88)
	if masonry_finish and kind!="market_awning": cap_material.albedo_color=masonry_finish.stone_color*.88
	cap_material.roughness = 1.0
	cap_material.metallic_specular = 0.0
	for record in _collision_records:
		var size: Vector3 = record.size * dimensions
		var center: Vector3 = record.center * dimensions
		if center.y-size.y*.5 > CUTAWAY_HEIGHT or center.y+size.y*.5 < CUTAWAY_HEIGHT: continue
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(size.x,.035,size.z)
		cap_mesh.material = cap_material
		cap.mesh = cap_mesh
		cap.position = Vector3(center.x,CUTAWAY_HEIGHT-.0175,center.z)
		caps.add_child(cap)

func _material(surface: int) -> Material:
	var material := ShaderMaterial.new()
	material.shader = preload("res://addons/house_builder/recipe_detail.gdshader")
	material.set_shader_parameter("surface_kind", surface)
	material.set_shader_parameter("weathered", weathered)
	material.set_shader_parameter("pattern_seed", float(posmod(detail_seed, 8191)))
	if masonry_finish and surface in [Surface.STONE,7]:
		var source := _color(Surface.STONE)
		masonry_finish.apply(material,(source.r+source.g+source.b)/3.0,surface==7,position.y)
		var h := dimensions.y
		var ledges := Vector4(-100,-100,-100,-100)
		if kind=="gothic_bell_tower": ledges=Vector4(.25,.49,.625,.805)*h
		elif kind=="gothic_buttress": ledges=Vector4(.17,.34,.65,.77)*h
		material.set_shader_parameter("masonry_ledge_heights",ledges+Vector4.ONE*position.y)
	return material

func _color(surface: int, scale := 1.0) -> Color:
	if surface==7: surface=Surface.STONE
	var color: Color = palette[surface] if surface < palette.size() else DEFAULT_COLORS[surface]
	return Color(color.r*scale, color.g*scale, color.b*scale, 1.0)

func _tri(a: Vector3, b: Vector3, c: Vector3, surface: int, color: Color) -> void:
	a *= dimensions; b *= dimensions; c *= dimensions
	var cross := (b-a).cross(c-a)
	if cross.length_squared() < 0.00000000001: return
	if not _tools.has(surface):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[surface] = tool
	var tool: SurfaceTool = _tools[surface]
	var normal := cross.normalized()
	for p in [a,c,b]:
		tool.set_normal(normal)
		tool.set_color(color)
		tool.set_uv(Vector2(p.x,p.y))
		tool.add_vertex(p)
	triangle_count += 1

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, surface: int, color: Color) -> void:
	_tri(a,b,c,surface,color); _tri(a,c,d,surface,color)

## Extruded XY silhouette; the chamfer and shape are real volume, not alpha cards.
func _prism(points: PackedVector2Array, depth: float, center: Vector3, surface: int, tint := Color(-1,0,0)) -> void:
	var edge := points.duplicate()
	if Geometry2D.is_polygon_clockwise(edge): edge.reverse()
	var color := _color(surface, _rng.randf_range(.93,1.06)) if tint.r < 0.0 else tint
	var indices := Geometry2D.triangulate_polygon(edge)
	for i in range(0, indices.size(), 3):
		var a := center+Vector3(edge[indices[i]].x,edge[indices[i]].y,depth*.5)
		var b := center+Vector3(edge[indices[i+1]].x,edge[indices[i+1]].y,depth*.5)
		var c := center+Vector3(edge[indices[i+2]].x,edge[indices[i+2]].y,depth*.5)
		_tri(a,b,c,surface,color)
		a.z -= depth; b.z -= depth; c.z -= depth
		_tri(a,c,b,surface,color.darkened(.055))
	for i in edge.size():
		var a := center+Vector3(edge[i].x,edge[i].y,-depth*.5)
		var b := center+Vector3(edge[(i+1)%edge.size()].x,edge[(i+1)%edge.size()].y,-depth*.5)
		_quad(a,b,b+Vector3(0,0,depth),a+Vector3(0,0,depth),surface,color)

func _block(center: Vector3, size: Vector3, surface: int, bevel := .015, tint := Color(-1,0,0)) -> void:
	var x := size.x*.5; var y := size.y*.5
	var cut := minf(bevel, minf(x,y)*.35)
	_prism(PackedVector2Array([Vector2(-x+cut,-y),Vector2(x-cut,-y),Vector2(x,-y+cut),Vector2(x,y-cut),Vector2(x-cut,y),Vector2(-x+cut,y),Vector2(-x,y-cut),Vector2(-x,-y+cut)]),size.z,center,surface,tint)

func _beam(a: Vector3, b: Vector3, width: float, depth: float, surface: int) -> void:
	var axis := (b-a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()*width*.5
	if side.length_squared() < .000001: side = Vector3.RIGHT*width*.5
	var back := axis.cross(side).normalized()*depth*.5
	var p := [a-side-back,a+side-back,a+side+back,a-side+back,b-side-back,b+side-back,b+side+back,b-side+back]
	var color := _color(surface,_rng.randf_range(.92,1.07))
	for face in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]:
		_quad(p[face[0]],p[face[1]],p[face[2]],p[face[3]],surface,color)

func _lathe(profile: PackedVector2Array, center: Vector3, surface: int, segments := 10, caps := true, orient := Basis.IDENTITY, tint := Color(-1,0,0), cap_tint := Color(-1,0,0)) -> void:
	var color := _color(surface) if tint.r < 0.0 else tint
	var end_color := color if cap_tint.r < 0.0 else cap_tint
	for i in segments:
		var a := TAU*float(i)/segments
		var b := TAU*float(i+1)/segments
		var facet := color * _rng.randf_range(.96,1.045)
		facet.a = 1.0
		for j in range(profile.size()-1):
			var lo := profile[j]; var hi := profile[j+1]
			_quad(center+orient*Vector3(cos(a)*lo.x,lo.y,sin(a)*lo.x),center+orient*Vector3(cos(a)*hi.x,hi.y,sin(a)*hi.x),center+orient*Vector3(cos(b)*hi.x,hi.y,sin(b)*hi.x),center+orient*Vector3(cos(b)*lo.x,lo.y,sin(b)*lo.x),surface,facet)
		if caps:
			var first := profile[0]; var last := profile[-1]
			_tri(center+orient*Vector3(0,first.y,0),center+orient*Vector3(cos(a)*first.x,first.y,sin(a)*first.x),center+orient*Vector3(cos(b)*first.x,first.y,sin(b)*first.x),surface,end_color)
			_tri(center+orient*Vector3(0,last.y,0),center+orient*Vector3(cos(b)*last.x,last.y,sin(b)*last.x),center+orient*Vector3(cos(a)*last.x,last.y,sin(a)*last.x),surface,end_color)

func _solid(center: Vector3, size: Vector3) -> void:
	_collision_records.append({"center":center,"size":size})

func _rim(y: float, width: float, depth: float, thick: float, height: float, surface: int) -> void:
	for x in [-1.0,1.0]: _block(Vector3(x*(width-thick)*.5,y,0),Vector3(thick,height,depth),surface)
	for z in [-1.0,1.0]: _block(Vector3(0,y,z*(depth-thick)*.5),Vector3(width-thick*2,height,thick),surface)

func _chimney() -> void:
	_block(Vector3(0,.055,0),Vector3(.82,.11,.82),Surface.STONE)
	# A connected tapered shaft with an actual recessed flue and corbelled lip.
	for side in 4:
		var axis := Basis(Vector3.UP,side*PI*.5)
		var color := _color(Surface.STONE,_rng.randf_range(.94,1.04))
		_quad(axis*Vector3(-.32,.09,.32),axis*Vector3(.32,.09,.32),axis*Vector3(.245,.88,.245),axis*Vector3(-.245,.88,.245),Surface.STONE,color)
		_quad(axis*Vector3(-.14,.77,.14),axis*Vector3(-.14,.95,.14),axis*Vector3(.14,.95,.14),axis*Vector3(.14,.77,.14),Surface.DARK,_color(Surface.DARK))
	_rim(.88,.66,.66,.16,.09,Surface.STONE)
	_rim(.96,.78,.78,.20,.08,Surface.CLAY)
	_block(Vector3(0,.77,0),Vector3(.30,.035,.30),Surface.DARK)
	# Small attached chips and interrupted mortar bands instead of stacked blocks.
	for i in 4:
		var y := .2+i*.16
		_block(Vector3(_rng.randf_range(-.10,.1),y,.321-y*.082),Vector3(.40,.009,.008),Surface.DARK,.002)
		if weathered: _block(Vector3(_rng.randf_range(-.15,.16),y+.035,.325-y*.082),Vector3(.065,.025,.008),Surface.STONE,.008,_color(Surface.STONE,.72))

func _bell_gable() -> void:
	_block(Vector3(0,.055,0),Vector3(.94,.11,.84),Surface.STONE)
	for x in [-.31,.31]:
		_block(Vector3(x,.335,0),Vector3(.18,.48,.59),Surface.STONE,.026)
		_block(Vector3(x,.15,0),Vector3(.22,.09,.72),Surface.STONE)
	# Voussoirs join into one arch around a genuinely empty bell opening.
	for i in 9:
		var a := PI*float(i)/9; var b := PI*float(i+1)/9
		var p := PackedVector2Array([Vector2(cos(a)*.235,.54+sin(a)*.235),Vector2(cos(a)*.405,.54+sin(a)*.405),Vector2(cos(b)*.405,.54+sin(b)*.405),Vector2(cos(b)*.235,.54+sin(b)*.235)])
		_prism(p,.62,Vector3.ZERO,Surface.STONE)
	_prism(PackedVector2Array([Vector2(-.49,.83),Vector2(0,1.0),Vector2(.49,.83),Vector2(.45,.80),Vector2(0,.94),Vector2(-.45,.80)]),.83,Vector3.ZERO,Surface.CLAY)
	_block(Vector3(0,.76,0),Vector3(.56,.055,.16),Surface.WOOD)
	_beam(Vector3(0,.75,0),Vector3(0,.59,0),.024,.035,Surface.METAL)
	var bell := PackedVector2Array([Vector2(.19,.38),Vector2(.20,.405),Vector2(.155,.44),Vector2(.12,.57),Vector2(.08,.61),Vector2(.044,.59),Vector2(.075,.55),Vector2(.115,.43),Vector2(.16,.40),Vector2(.19,.38)])
	_lathe(bell,Vector3.ZERO,Surface.METAL,12,false,Basis.IDENTITY,Color(.40,.31,.15))
	_beam(Vector3(0,.56,0),Vector3(0,.365,0),.027,.038,Surface.METAL)
	_lathe(PackedVector2Array([Vector2(.027,.35),Vector2(.04,.365),Vector2(.024,.385)]),Vector3.ZERO,Surface.METAL,8)

func _crate(center: Vector3, size: Vector3) -> void:
	_block(center+Vector3(0,-size.y*.5,0),Vector3(size.x,.025,size.z),Surface.WOOD)
	for row in 2:
		var y := center.y-size.y*.3+row*size.y*.6
		for sign in [-1.0,1.0]:
			_block(Vector3(center.x+sign*(size.x-.023)*.5,y,center.z),Vector3(.023,size.y*.39,size.z),Surface.WOOD,.004)
			_block(Vector3(center.x,y,center.z+sign*(size.z-.022)*.5),Vector3(size.x,size.y*.39,.022),Surface.WOOD,.004)
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]: _block(center+Vector3(x*(size.x-.024)*.5,0,z*(size.z-.024)*.5),Vector3(.025,size.y,.025),Surface.WOOD,.004)

func _shop() -> void:
	for x in [-.425,.425]:
		for z in [-.355,.355]: _block(Vector3(x,.335,z),Vector3(.08,.67,.09),Surface.WOOD)
	for i in 8:
		_block(Vector3(-.425+i*.1214,.335,.36),Vector3(.112,.55,.055),Surface.WOOD,.008)
	for y in [.12,.56]: _block(Vector3(0,y,.395),Vector3(.94,.057,.04),Surface.WOOD)
	for i in 5:
		_block(Vector3(0,.69,-.40+i*.20),Vector3(1.0,.07,.188),Surface.WOOD,.008)
	_crate(Vector3(-.22,.82,.02),Vector3(.38,.19,.60))
	_crate(Vector3(.23,.815,-.08),Vector3(.34,.18,.45))
	for i in 12:
		var p := Vector3(-.36+(i%4)*.09,.825+(i/4)*.012,-.18+floorf(i/4.0)*.17)
		var produce := Color(.34,.41,.14) if i%3 else Color(.52,.23,.11)
		_lathe(PackedVector2Array([Vector2(.02,-.023),Vector2(.045,0),Vector2(.032,.045),Vector2(.012,.055)]),p,Surface.GOODS,7,true,Basis.IDENTITY,produce)
	for i in 3:
		var p := Vector3(.13+i*.085,.86,-.08)
		_lathe(PackedVector2Array([Vector2(.023,-.10),Vector2(.045,-.075),Vector2(.05,.05),Vector2(.025,.09)]),p,Surface.GOODS,8,true,Basis(Vector3.RIGHT,PI*.5),_color(Surface.GOODS,1.17))
	# Tied sack at one end makes the stall legible even from the rear.
	_lathe(PackedVector2Array([Vector2(.065,.72),Vector2(.085,.78),Vector2(.071,.92),Vector2(.030,.96),Vector2(.036,1.0)]),Vector3(.38,0,.32),Surface.PAINT,9,true,Basis.IDENTITY,Color(.53,.46,.32))
	_solid(Vector3(0,.36,0),Vector3(.94,.72,.82))

func _forge() -> void:
	_block(Vector3(-.245,.09,0),Vector3(.48,.18,.87),Surface.STONE)
	for x in [-.43,-.08]: _block(Vector3(x,.30,.01),Vector3(.125,.40,.68),Surface.STONE)
	_block(Vector3(-.25,.35,-.30),Vector3(.36,.48,.13),Surface.STONE)
	_block(Vector3(-.25,.47,.025),Vector3(.47,.075,.76),Surface.STONE)
	_block(Vector3(-.25,.515,.005),Vector3(.36,.024,.53),Surface.DARK)
	for i in 11:
		var pos := Vector3(_rng.randf_range(-.39,-.11),.544,_rng.randf_range(-.21,.22))
		_block(pos,Vector3(.046,_rng.randf_range(.025,.055),.067),Surface.DARK,.012,Color(.24,.085,.035) if i%4==0 else Color(.075,.065,.051))
	# Broad soot-dark hood tapers into the square flue; open front above coals.
	_prism(PackedVector2Array([Vector2(-.49,.68),Vector2(-.01,.68),Vector2(-.17,.91),Vector2(-.33,.91)]),.67,Vector3(0,0,-.065),Surface.METAL)
	_block(Vector3(-.25,.952,-.065),Vector3(.17,.096,.30),Surface.STONE)
	for x in [-.435,-.065]: _beam(Vector3(x,.48,-.285),Vector3(x,.70,-.285),.027,.03,Surface.METAL)
	# Anvil: flared feet, narrow waist, flat face and projecting tapered horn.
	_lathe(PackedVector2Array([Vector2(.15,0),Vector2(.16,.08),Vector2(.145,.43),Vector2(.13,.46)]),Vector3(.255,0,.04),Surface.WOOD,9)
	_prism(PackedVector2Array([Vector2(.075,.46),Vector2(.40,.46),Vector2(.39,.51),Vector2(.29,.55),Vector2(.31,.625),Vector2(.43,.635),Vector2(.50,.67),Vector2(.44,.695),Vector2(.11,.695),Vector2(.07,.665),Vector2(.15,.625),Vector2(.19,.55),Vector2(.10,.515)]),.28,Vector3(0,0,.04),Surface.METAL)
	_block(Vector3(.255,.702,.04),Vector3(.27,.015,.29),Surface.METAL,.006,_color(Surface.METAL,1.30))
	_beam(Vector3(.13,.73,.18),Vector3(.40,.73,.26),.027,.035,Surface.WOOD)
	_block(Vector3(.40,.74,.26),Vector3(.08,.055,.12),Surface.METAL)
	_solid(Vector3(-.25,.27,0),Vector3(.49,.54,.86))
	_solid(Vector3(.26,.35,.05),Vector3(.42,.70,.39))

func _firewood() -> void:
	for row in 3:
		for column in 4-row:
			var x := -.345+row*.115+column*.23
			var y := .145+row*.215
			var radius := _rng.randf_range(.104,.116)
			var length := _rng.randf_range(.70,.84)
			_lathe(PackedVector2Array([Vector2(radius*.94,-length*.5),Vector2(radius,0),Vector2(radius*.91,length*.5)]),Vector3(x,y,_rng.randf_range(-.025,.025)),Surface.WOOD,8,true,Basis(Vector3.RIGHT,PI*.5),_color(Surface.WOOD,.74),Color(.53,.39,.22))
	for x in [-.465,.465]:
		for z in [-.39,.39]: _block(Vector3(x,.43,z),Vector3(.055,.86,.055),Surface.WOOD)
	for z in [-.43,.43]: _beam(Vector3(-.48,.86,z),Vector3(.48,.95,z),.06,.055,Surface.WOOD)
	for i in 5:
		var x := -.4+i*.20
		_prism(PackedVector2Array([Vector2(x-.105,.865+(x-.105)*.09),Vector2(x+.105,.865+(x+.105)*.09),Vector2(x+.105,.91+(x+.105)*.09),Vector2(x-.105,.91+(x-.105)*.09)]),1.0,Vector3.ZERO,Surface.WOOD)
	_solid(Vector3(0,.34,0),Vector3(.89,.68,.84))

func _trough() -> void:
	for x in [-.34,.34]: _block(Vector3(x,.11,0),Vector3(.10,.22,.85),Surface.WOOD)
	var rings := [Vector3(.88,.22,.70),Vector3(1.0,.92,1.0),Vector3(.80,.92,.68),Vector3(.70,.38,.46)]
	for j in 3:
		var lo: Vector3 = rings[j]; var hi: Vector3 = rings[j+1]
		var a := [Vector3(-lo.x*.5,lo.y,-lo.z*.5),Vector3(lo.x*.5,lo.y,-lo.z*.5),Vector3(lo.x*.5,lo.y,lo.z*.5),Vector3(-lo.x*.5,lo.y,lo.z*.5)]
		var b := [Vector3(-hi.x*.5,hi.y,-hi.z*.5),Vector3(hi.x*.5,hi.y,-hi.z*.5),Vector3(hi.x*.5,hi.y,hi.z*.5),Vector3(-hi.x*.5,hi.y,hi.z*.5)]
		for side in 4: _quad(a[side],b[side],b[(side+1)%4],a[(side+1)%4],Surface.WOOD,_color(Surface.WOOD,.75 if j==2 else 1.0))
	_block(Vector3(0,.40,0),Vector3(.72,.045,.48),Surface.WOOD)
	_block(Vector3(0,.57,0),Vector3(.72,.012,.49),Surface.PAINT,.015,Color(.16,.24,.21))
	for x in [-.31,.31]:
		for z in [-.455,.455]: _block(Vector3(x,.67,z),Vector3(.034,.43,.02),Surface.METAL,.003)
	for x in [-.445,.445]: _solid(Vector3(x,.54,0),Vector3(.10,.76,.88))
	for z in [-.38,.38]: _solid(Vector3(0,.54,z),Vector3(.80,.76,.17))
	_solid(Vector3(0,.38,0),Vector3(.76,.08,.56))

func _fence() -> void:
	for i in 3:
		var x := -.465+i*.465
		var top := .94+_rng.randf_range(-.035,.035)
		_prism(PackedVector2Array([Vector2(x-.03,0),Vector2(x+.03,0),Vector2(x+.029,top-.04),Vector2(x-.008,top+.025),Vector2(x-.03,top)]),.82,Vector3.ZERO,Surface.WOOD)
		_solid(Vector3(x,top*.5,0),Vector3(.062,top,.85))
	for y in [.29,.67]:
		_beam(Vector3(-.48,y,.07),Vector3(.48,y+.018,.07),.070,.60,Surface.WOOD)
		_solid(Vector3(0,y,.07),Vector3(.96,.077,.64))
	_beam(Vector3(-.45,.34,-.16),Vector3(-.015,.63,-.16),.035,.27,Surface.WOOD)
	_beam(Vector3(.015,.63,-.16),Vector3(.45,.34,-.16),.035,.27,Surface.WOOD)

func _sign() -> void:
	# Forged projecting bracket and straps; no blocker on a doorway ornament.
	_block(Vector3(-.455,.82,0),Vector3(.055,.35,.31),Surface.METAL,.008)
	_beam(Vector3(-.43,.95,0),Vector3(.46,.95,0),.042,.11,Surface.METAL)
	_beam(Vector3(-.43,.67,0),Vector3(-.05,.95,0),.025,.09,Surface.METAL)
	for x in [-.29,.29]:
		_beam(Vector3(x,.94,0),Vector3(x,.60,0),.015,.04,Surface.METAL)
		_block(Vector3(x,.67,.02),Vector3(.044,.105,.07),Surface.METAL,.007)
	_prism(PackedVector2Array([Vector2(-.43,.14),Vector2(-.32,.045),Vector2(.30,.045),Vector2(.43,.14),Vector2(.43,.52),Vector2(.32,.625),Vector2(-.32,.625),Vector2(-.43,.52)]),.34,Vector3.ZERO,Surface.WOOD)
	for y in [.21,.42]: _block(Vector3(0,y,.173),Vector3(.78,.009,.013),Surface.DARK,.002)
	var selected: String = motif if motif != "auto" else ["wheat","tankard","anvil"][posmod(detail_seed,3)]
	var cream := Color(.79,.70,.47)
	if selected == "tankard":
		_prism(PackedVector2Array([Vector2(-.16,.16),Vector2(.12,.16),Vector2(.15,.46),Vector2(-.17,.46)]),.034,Vector3(0,0,.21),Surface.PAINT,cream)
		for y in [.22,.37]: _block(Vector3(.22,y,.21),Vector3(.10,.045,.05),Surface.PAINT,.007,cream)
		_block(Vector3(.275,.295,.21),Vector3(.04,.19,.05),Surface.PAINT,.008,cream)
		_block(Vector3(-.01,.475,.21),Vector3(.37,.055,.04),Surface.PAINT,.019,cream.lightened(.12))
	elif selected == "anvil":
		_prism(PackedVector2Array([Vector2(-.20,.18),Vector2(.20,.18),Vector2(.11,.24),Vector2(.07,.33),Vector2(.22,.38),Vector2(.29,.43),Vector2(-.24,.43),Vector2(-.24,.36),Vector2(-.09,.31),Vector2(-.12,.24)]),.035,Vector3(0,0,.21),Surface.PAINT,cream)
	elif selected == "horse":
		_prism(PackedVector2Array([Vector2(-.19,.15),Vector2(.14,.15),Vector2(.12,.29),Vector2(.23,.38),Vector2(.18,.46),Vector2(.10,.47),Vector2(.02,.56),Vector2(-.02,.47),Vector2(-.12,.44),Vector2(-.19,.30)]),.035,Vector3(0,0,.21),Surface.PAINT,cream)
	else:
		_beam(Vector3(0,.13,.22),Vector3(0,.54,.22),.024,.025,Surface.PAINT)
		for i in 3:
			var y := .25+i*.085
			for side in [-1.0,1.0]:
				_prism(PackedVector2Array([Vector2(0,y),Vector2(side*.12,y+.018),Vector2(side*.16,y+.09),Vector2(side*.065,y+.071)]),.035,Vector3(0,0,.21),Surface.PAINT,cream)

func _dormer() -> void:
	# Open window niche, cheeks, pitched tiled cap and projecting sill.
	for x in [-.32,.32]: _block(Vector3(x,.36,0),Vector3(.15,.64,.71),Surface.STONE)
	_block(Vector3(0,.08,.10),Vector3(.78,.11,.80),Surface.WOOD)
	_block(Vector3(0,.58,.27),Vector3(.67,.11,.10),Surface.WOOD)
	_block(Vector3(0,.36,-.29),Vector3(.56,.47,.03),Surface.DARK)
	for x in [-.23,0,.23]: _block(Vector3(x,.34,.27),Vector3(.028,.46,.045),Surface.WOOD,.004)
	_block(Vector3(0,.36,.27),Vector3(.49,.025,.045),Surface.WOOD,.004)
	_prism(PackedVector2Array([Vector2(-.40,.64),Vector2(0,.97),Vector2(.40,.64)]),.69,Vector3(0,0,-.04),Surface.STONE)
	for side in [-1.0,1.0]:
		for row in 3:
			var inner := row*.16; var outer := minf(.49,inner+.195)
			for column in 4:
				var z := -.385+column*.25
				var top := PackedVector2Array([Vector2(side*inner,.972-inner*.74),Vector2(side*outer,.972-outer*.74),Vector2(side*outer,1.0-outer*.74),Vector2(side*inner,1.0-inner*.74)])
				_prism(top,.255,Vector3(0,0,z),Surface.CLAY)

@tool
extends RefCounted
static func bake(village: Node) -> void:
	if village.guides(0).is_empty(): return
	var boundary: PackedVector2Array=village.guides(0)[0].village_points()
	if boundary.size()<3: return
	var bounds := Rect2(boundary[0],Vector2.ZERO)
	for p in boundary: bounds=bounds.expand(p)
	bounds=bounds.grow(8)
	var image := Image.create(256,256,false,Image.FORMAT_RGB8)
	var shapes: Array=[]
	for poly in village.road_shapes(): shapes.append([poly,0.45])
	for group in village.guides(4): shapes.append([group.village_points(),0.18])
	for route in preload("res://addons/village_builder/path_network.gd").shared(village,village.snapshot(),false):
		for poly in preload("res://addons/village_builder/path_network.gd").ribbon(route.points,route.widths): shapes.append([poly,0.3])
	for lot in village.lots():
		for poly in village.access_shapes(lot.transform,lot.access_path): shapes.append([poly,0.25])
	for record in shapes:
		var poly: PackedVector2Array=record[0]
		var box := Rect2(poly[0],Vector2.ZERO)
		for p in poly: box=box.expand(p)
		box=box.grow(1.2)
		var low := Vector2i(((box.position-bounds.position)/bounds.size*256).floor())
		var high := Vector2i(((box.end-bounds.position)/bounds.size*256).ceil())
		for y in range(maxi(0,low.y),mini(256,high.y+1)):
			for x in range(maxi(0,low.x),mini(256,high.x+1)):
				var p := bounds.position+(Vector2(x,y)+Vector2.ONE*0.5)/256*bounds.size
				var distance := INF
				for i in poly.size(): distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()])))
				if not Geometry2D.is_point_in_polygon(p,poly): distance=-distance
				var weight := smoothstep(-0.9,0.35,distance)
				var old := image.get_pixel(x,y)
				image.set_pixel(x,y,Color(maxf(old.r,weight),maxf(old.g,weight*record[1]),0))
	var material := ShaderMaterial.new(); material.shader=load("res://shaders/pixelart/ground_clear.gdshader")
	material.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/ground_painting.png"))
	material.set_shader_parameter("layers",load("res://assets/textures/hearth_painted/terrain_layers.png"))
	material.set_shader_parameter("builder_layout",true); material.set_shader_parameter("use_road_mask",true)
	material.set_shader_parameter("road_mask",ImageTexture.create_from_image(image))
	material.set_shader_parameter("road_mask_center",bounds.get_center()); material.set_shader_parameter("road_mask_size",bounds.size)
	material.set_shader_parameter("wear_amount",0.3); material.set_shader_parameter("gravel_amount",0.12)
	village.surface_rect=bounds; village.surface_material=material

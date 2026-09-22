@tool
extends RefCounted
## Original folded leaf meshes and shallow pavers; no imported foliage masks.
static func build(d: Node3D) -> void:
	if d.kind=="stone_apron": apron(d)
	else: ivy(d)

static func excluded(d: Node3D,p: Vector3,margin: float) -> bool:
	for region in d.surface_exclusions:
		if region.grow(margin).has_point(Vector2(p.x,p.y)): return true
	var parent := d.get_parent()
	var house := parent.get_parent() if parent else null
	if house==null or not house.has_method("resolved_opening"): return false
	var local: Vector3=house.to_local(d.to_global(p))
	for record in house.openings:
		var opening: Dictionary=house.resolved_opening(record)
		var center: Vector3=house.wall_point(opening.wall,opening.along,opening.y)
		var normal: Vector3=house.wall_normal(opening.wall)
		var tangent: Vector3=(house.wall_point(opening.wall,1,0)-house.wall_point(opening.wall,0,0)).normalized()
		var delta := local-center
		if absf(delta.dot(normal))<1.5 and absf(delta.dot(tangent))<opening.width*.5+margin and absf(delta.y)<opening.height*.5+margin: return true
	return false

static func ivy(d: Node3D) -> void:
	var g := preload("res://addons/house_builder/recipe_gothic.gd").new(); g.d=d
	var rng: RandomNumberGenerator=d._rng
	var count := 7 if d.growth_shape==0 else 5
	for branch in count:
		var end_x: float = ((float(branch)/float(count-1)-.5)*.68+rng.randf_range(-.06,.06))*d.dimensions.x
		var height: float=d.dimensions.y*rng.randf_range(.48,.91)
		if branch==0: height=d.dimensions.y*.92
		var root := Vector3(rng.randf_range(-.12,.12)*d.dimensions.x,.025,0)
		var previous := root
		for step in 24:
			var t := float(step+1)/24.0
			var spread := sin(t*PI*.5) if d.growth_shape==0 else t*t
			var p := Vector3(lerpf(root.x,end_x,spread)+sin(t*9+branch)*d.dimensions.x*.055,height*t,.025+sin(t*7+branch)*.018)
			if not excluded(d,p,.16) and not excluded(d,previous,.16): g.beam(previous,p,.014*(1.1-t*.5),.014,0)
			previous=p
			# Open patches and unequal branch lengths break a solid rectangular patch.
			if rng.randf()>d.growth_density*.88 or (step>11 and branch%3==1 and step%5<2): continue
			var side := -1.0 if step%2==0 else 1.0
			var center := p+Vector3(side*rng.randf_range(.06,.14),rng.randf_range(-.04,.04),rng.randf_range(.025,.10))
			if excluded(d,center,.22): continue
			var size: float = minf(rng.randf_range(.13,.24)*(1.1-t*.25),d.dimensions.x*.18)
			center.x=clampf(center.x,-d.dimensions.x*.37,d.dimensions.x*.37)
			center.z=minf(center.z,d.dimensions.z*.35)
			center.y=maxf(center.y,size*.65)
			if excluded(d,center,.22): continue
			var angle := side*rng.randf_range(.35,1.35)
			var axis := Vector3(sin(angle),cos(angle),rng.randf_range(-.2,.2)).normalized()
			var across := axis.cross(Vector3.BACK).normalized()
			var outline := [Vector2(0,-.4),Vector2(-.58,-.05),Vector2(-.42,.30),Vector2(0,.75),Vector2(.51,.25),Vector2(.60,-.12)]
			var shade := rng.randf_range(.82,1.18)
			var pigment: Color = d.growth_color*shade if branch%3!=0 else d.growth_color*Color(.54,.70,1.10)*shade
			var fold := center+Vector3(0,0,minf(.028,d.dimensions.z*.08))
			for i in outline.size():
				var a: Vector3=center+(across*outline[i].x+axis*outline[i].y)*size
				var b: Vector3=center+(across*outline[(i+1)%outline.size()].x+axis*outline[(i+1)%outline.size()].y)*size
				g.tri(fold,a,b,3,pigment*(1.09 if i<3 else .88))
				g.tri(fold,b,a,3,pigment*.84)

static func apron(d: Node3D) -> void:
	var g := preload("res://addons/house_builder/recipe_gothic.gd").new(); g.d=d
	var rng: RandomNumberGenerator=d._rng
	g.frame=Transform3D(Basis(Vector3.RIGHT,-PI*.5),Vector3.ZERO)
	for row in 4:
		for col in 5:
			var edge := row in [0,3] or col in [0,4]
			if edge and rng.randf()<.22: continue
			var x: float=(float(col)-2.0)*d.dimensions.x/5.0+rng.randf_range(-.035,.035)
			var z: float=(float(row)-1.5)*d.dimensions.z/4.0+rng.randf_range(-.025,.025)
			var width: float=d.dimensions.x/5.0*rng.randf_range(.78,.95)
			var length: float=d.dimensions.z/4.0*rng.randf_range(.78,.94)
			var top := rng.randf_range(.015,.040)
			# Tops remain shallow and no new collider crosses the existing approach.
			var points := PackedVector2Array()
			var corners := [Vector2(-.45,-.34),Vector2(-.24,-.5),Vector2(.43,-.45),Vector2(.5,.12),Vector2(.29,.5),Vector2(-.42,.44)]
			var angle := rng.randf_range(-.13,.13)
			for corner in corners:
				points.append((corner*Vector2(width,length)*rng.randf_range(.88,1.0)).rotated(angle))
			g.prism(points,.07,Vector3(x,z,top-.035),1)

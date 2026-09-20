@tool
extends RefCounted
## Reusable masonry forms in metres. Original arches/tracery, no imported assets.
var d: Node3D
var frame := Transform3D.IDENTITY
const STONE := 1
const METAL := 2
const GLASS := 3
const ROOF := 4
const DARK := 6

static func build(detail: Node3D) -> void:
	var builder := new()
	builder.d = detail
	match detail.kind:
		"gothic_facade": builder.facade()
		"gothic_bell_tower": builder.tower()
		"gothic_buttress": builder.buttress()
		"gothic_window": builder.window()

func color(surface: int, shade := 1.0) -> Color:
	return d._color(surface, shade)

func tri(a: Vector3,b: Vector3,c: Vector3,surface: int,tint: Color) -> void:
	d._tri((frame*a)/d.dimensions,(frame*b)/d.dimensions,(frame*c)/d.dimensions,surface,tint)

func quad(a: Vector3,b: Vector3,c: Vector3,e: Vector3,surface: int,tint: Color) -> void:
	tri(a,b,c,surface,tint); tri(a,c,e,surface,tint)

func prism(points: PackedVector2Array, depth: float, center: Vector3, surface := STONE, tint := Color(-1,0,0)) -> void:
	var edge := points.duplicate()
	if Geometry2D.is_polygon_clockwise(edge): edge.reverse()
	var pigment: Color = color(surface,d._rng.randf_range(.95,1.05)) if tint.r < 0 else tint
	var indices := Geometry2D.triangulate_polygon(edge)
	for i in range(0,indices.size(),3):
		var a := center+Vector3(edge[indices[i]].x,edge[indices[i]].y,depth*.5)
		var b := center+Vector3(edge[indices[i+1]].x,edge[indices[i+1]].y,depth*.5)
		var c := center+Vector3(edge[indices[i+2]].x,edge[indices[i+2]].y,depth*.5)
		tri(a,b,c,surface,pigment)
		a.z-=depth; b.z-=depth; c.z-=depth
		tri(a,c,b,surface,pigment)
	for i in edge.size():
		var a := center+Vector3(edge[i].x,edge[i].y,-depth*.5)
		var b := center+Vector3(edge[(i+1)%edge.size()].x,edge[(i+1)%edge.size()].y,-depth*.5)
		quad(a,b,b+Vector3(0,0,depth),a+Vector3(0,0,depth),surface,pigment)

func box(center: Vector3,size: Vector3,surface := STONE,tint := Color(-1,0,0)) -> void:
	var x := size.x*.5; var y := size.y*.5
	var bevel := minf(.035,minf(x,y)*.22)
	prism(PackedVector2Array([Vector2(-x+bevel,-y),Vector2(x-bevel,-y),Vector2(x,-y+bevel),Vector2(x,y-bevel),Vector2(x-bevel,y),Vector2(-x+bevel,y),Vector2(-x,y-bevel),Vector2(-x,-y+bevel)]),size.z,center,surface,tint)

func solid(center: Vector3,size: Vector3) -> void:
	var transformed_size := frame.basis.x.abs()*size.x+frame.basis.y.abs()*size.y+frame.basis.z.abs()*size.z
	d._solid((frame*center)/d.dimensions,transformed_size/d.dimensions)

func beam(a: Vector3,b: Vector3,width: float,depth: float,surface := STONE,tint := Color(-1,0,0)) -> void:
	var axis := (b-a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()*width*.5
	if side.length_squared()<.000001: side=Vector3.RIGHT*width*.5
	var back := axis.cross(side).normalized()*depth*.5
	var p := [a-side-back,a+side-back,a+side+back,a-side+back,b-side-back,b+side-back,b+side+back,b-side+back]
	var pigment: Color = color(surface,d._rng.randf_range(.95,1.05)) if tint.r<0 else tint
	for face in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]:
		quad(p[face[0]],p[face[1]],p[face[2]],p[face[3]],surface,pigment)

## Two circular arcs meet at a pointed apex. Returned left spring -> right spring.
func ogive(radius: float,rise: float,steps := 8) -> PackedVector2Array:
	var center := (rise*rise-radius*radius)/(2.0*radius)
	var circle_radius := radius+center
	var apex_angle := atan2(rise,-center)
	var result := PackedVector2Array()
	for i in range(steps+1):
		var angle := lerpf(PI,apex_angle,float(i)/steps)
		result.append(Vector2(center+cos(angle)*circle_radius,sin(angle)*circle_radius))
	for i in range(steps-1,-1,-1): result.append(Vector2(-result[i].x,result[i].y))
	return result

func pointed_band(center: Vector3,radius: float,rise: float,thickness: float,depth: float,surface := STONE) -> void:
	var inside := ogive(radius,rise)
	var outside := ogive(radius+thickness,rise+thickness*1.2)
	for i in range(inside.size()-1):
		prism(PackedVector2Array([inside[i],outside[i],outside[i+1],inside[i+1]]),depth,center,surface)

func disc(center: Vector3,radius: float,surface: int,tint: Color,segments := 32) -> void:
	for i in segments:
		var a := TAU*float(i)/segments; var b := TAU*float(i+1)/segments
		tri(center,center+Vector3(cos(a),sin(a),0)*radius,center+Vector3(cos(b),sin(b),0)*radius,surface,tint)

func ring(center: Vector3,inside: float,outside: float,depth: float,surface := STONE,segments := 32) -> void:
	for i in segments:
		var a := TAU*float(i)/segments; var b := TAU*float(i+1)/segments
		prism(PackedVector2Array([Vector2(cos(a),sin(a))*inside,Vector2(cos(a),sin(a))*outside,Vector2(cos(b),sin(b))*outside,Vector2(cos(b),sin(b))*inside]),depth,center,surface)

func rose(center: Vector3,radius: float) -> void:
	disc(center,radius,GLASS,Color(.06,.12,.20))
	ring(center+Vector3(0,0,.055),radius*.93,radius*1.12,.16)
	ring(center+Vector3(0,0,.14),radius*.81,radius*.86,.045,METAL,24)
	var blue := Color(.075,.24,.40)
	var amber := Color(.54,.34,.095)
	# Twelve petal sectors and raised lead ribs form readable radial tracery.
	for i in 12:
		var a := TAU*float(i)/12
		var b := TAU*float(i+1)/12
		var mid := (a+b)*.5
		var petal := PackedVector2Array([Vector2(cos(a),sin(a))*radius*.20,Vector2(cos(a),sin(a))*radius*.65,Vector2(cos(mid),sin(mid))*radius*.80,Vector2(cos(b),sin(b))*radius*.65,Vector2(cos(b),sin(b))*radius*.20])
		prism(petal,.028,center+Vector3(0,0,.11),GLASS,amber if i%3==0 else blue.lightened(float(i%3)*.035))
		beam(center+Vector3(cos(a),sin(a),0)*radius*.18+Vector3(0,0,.15),center+Vector3(cos(a),sin(a),0)*radius*.84+Vector3(0,0,.15),radius*.035,.035,METAL,Color(.49,.39,.20))
	ring(center+Vector3(0,0,.17),radius*.14,radius*.23,.055,STONE,16)
	disc(center+Vector3(0,0,.185),radius*.14,GLASS,Color(.52,.32,.075),16)

func lancet(center: Vector3,width: float,height: float,depth: float,glass := true) -> void:
	var r := width*.5
	var rise := width*.78
	var spring := height-rise
	var curve := ogive(r,rise)
	var outline := PackedVector2Array([Vector2(-r,0),Vector2(r,0),Vector2(r,spring)])
	for i in range(curve.size()-1,-1,-1): outline.append(curve[i]+Vector2(0,spring))
	if glass:
		prism(outline,.025,center,GLASS,Color(.075,.18,.25))
		beam(center+Vector3(0,.08,.025),center+Vector3(0,height-.12,.025),.045,.025,METAL)
		for i in 3:
			var y := height*.20+i*height*.20
			box(center+Vector3(0,y,.028),Vector3(width*.86,.037,.025),METAL)
			prism(PackedVector2Array([Vector2(-r*.60,y+.035),Vector2(-r*.11,y+.035),Vector2(-r*.11,y+height*.15),Vector2(-r*.60,y+height*.15)]),.02,center+Vector3(0,0,.039),GLASS,Color(.17,.27,.35))
	for x in [-r-.07,r+.07]: box(center+Vector3(x,spring*.5,0),Vector3(.14,spring,depth))
	pointed_band(center+Vector3(0,spring,0),r,rise,.14,depth)
	box(center+Vector3(0,.02,.018),Vector3(width+.37,.13,depth+.08))

func spire(center: Vector3,width: float,depth: float,height: float,surface := ROOF) -> void:
	var footprint := PackedVector2Array([Vector2(-width*.36,-depth*.5),Vector2(width*.36,-depth*.5),Vector2(width*.5,-depth*.36),Vector2(width*.5,depth*.36),Vector2(width*.36,depth*.5),Vector2(-width*.36,depth*.5),Vector2(-width*.5,depth*.36),Vector2(-width*.5,-depth*.36)])
	# Overlapping horizontal courses give the cuspide a roof surface, not a cone.
	for row in 7:
		var t0 := float(row)/7; var t1 := float(row+1)/7
		var lower := 1.0-t0; var upper := 1.0-t1
		for i in footprint.size():
			var j := (i+1)%footprint.size()
			var a := center+Vector3(footprint[i].x*lower,height*t0,footprint[i].y*lower)
			var b := center+Vector3(footprint[j].x*lower,height*t0,footprint[j].y*lower)
			var c := center+Vector3(footprint[j].x*upper,height*t1,footprint[j].y*upper)
			var e := center+Vector3(footprint[i].x*upper,height*t1,footprint[i].y*upper)
			quad(b,a,e,c,surface,color(surface,d._rng.randf_range(.86,1.05)))
			if row>0:
				var lip_a := a+Vector3(footprint[i].x,0,footprint[i].y).normalized()*.028
				var lip_b := b+Vector3(footprint[j].x,0,footprint[j].y).normalized()*.028
				quad(a,b,lip_b,lip_a,surface,color(surface,.78))
	for i in 8:
		beam(center+Vector3(footprint[i].x,0,footprint[i].y),center+Vector3(0,height,0),.045,.045,METAL,color(METAL,.80))

func facade() -> void:
	var w: float = d.dimensions.x
	var h: float = d.dimensions.y
	var depth: float = d.dimensions.z
	var r := minf(1.0,maxf(.90,w*.14))
	var spring := 2.40
	var rise := 1.22
	var portal := ogive(r,rise)
	var narrow := w<6.0
	var shoulder := h*(.67 if narrow else .61)
	var gable_half := w*(.495 if narrow else .41)
	var outline := PackedVector2Array([Vector2(-w*.5,0),Vector2(-w*.5,shoulder),Vector2(-gable_half,shoulder),Vector2(0,h),Vector2(gable_half,shoulder),Vector2(w*.5,shoulder),Vector2(w*.5,0),Vector2(r,0),Vector2(r,spring)])
	for i in range(portal.size()-1,-1,-1): outline.append(portal[i]+Vector2(0,spring))
	outline.append(Vector2(-r,0))
	# Rear half is solid stone; the front half holds raised portal and tracery.
	prism(outline,depth*.5,Vector3(0,0,-depth*.25))
	var front := 0.0
	for x in [-r-.13,r+.13]:
		box(Vector3(x,spring*.5,front+.07),Vector3(.26,spring,.25))
		box(Vector3(x,.16,front+.08),Vector3(.40,.32,.34))
		box(Vector3(x,spring-.04,front+.10),Vector3(.39,.16,.36))
	pointed_band(Vector3(0,spring,front+.08),r,rise,.25,.24)
	pointed_band(Vector3(0,spring,front+.21),r+.30,rise+.30,.09,.11)
	# The existing rectangular door remains the moving leaf below this transom.
	var tympanum := PackedVector2Array([Vector2(-r,2.34),Vector2(r,2.34),Vector2(r,spring)])
	for i in range(portal.size()-1,-1,-1): tympanum.append(portal[i]+Vector2(0,spring))
	prism(tympanum,.03,Vector3(0,0,front-.025),GLASS,Color(.10,.14,.15))
	for side in [-1.0,1.0]:
		beam(Vector3(0,2.37,front+.025),Vector3(side*.57,3.12,front+.025),.045,.035,METAL)
		var x: float = side*w*.40
		box(Vector3(x,shoulder*.5,front+.02),Vector3(.35,shoulder,.22))
		box(Vector3(side*w*.31,.12,front),Vector3(w*.35,.24,depth*.55))
		if not narrow: lancet(Vector3(side*w*.29,1.16,front+.08),.78,2.26,.16)
		beam(Vector3(side*gable_half,shoulder+.03,front),Vector3(0,h-.03,front),.18,.26)
	rose(Vector3(0,h*.735,front+.04),minf(1.08,w*(.18 if narrow else .13)))
	# Masonry blockers flank, never cross, the retained central doorway.
	var side_width := (w-2.0*r)*.5
	for side in [-1.0,1.0]: solid(Vector3(side*(r+side_width*.5),shoulder*.5,-depth*.25),Vector3(side_width,shoulder,depth*.5))

func buttress() -> void:
	var w: float=d.dimensions.x; var h: float=d.dimensions.y; var depth: float=d.dimensions.z
	box(Vector3(0,h*.05,0),Vector3(w,h*.10,depth))
	box(Vector3(0,h*.30,-depth*.025),Vector3(w*.77,h*.43,depth*.86))
	prism(PackedVector2Array([Vector2(-w*.44,h*.50),Vector2(w*.44,h*.50),Vector2(w*.30,h*.60),Vector2(-w*.30,h*.60)]),depth*.96,Vector3.ZERO)
	box(Vector3(0,h*.665,-depth*.17),Vector3(w*.56,h*.18,depth*.55))
	box(Vector3(0,h*.77,-depth*.17),Vector3(w*.70,h*.05,depth*.68))
	spire(Vector3(0,h*.795,-depth*.17),w*.55,depth*.50,h*.205,STONE)
	for y in [h*.17,h*.34,h*.65]: box(Vector3(0,y,depth*.417),Vector3(w*.67,.035,.02),STONE,color(STONE,.78))
	solid(Vector3(0,h*.34,-depth*.025),Vector3(w*.82,h*.68,depth*.86))

func tower() -> void:
	var w: float=d.dimensions.x; var h: float=d.dimensions.y; var depth: float=d.dimensions.z
	box(Vector3(0,h*.025,0),Vector3(w,h*.05,depth))
	box(Vector3(0,h*.325,0),Vector3(w*.86,h*.60,depth*.86))
	for x in [-w*.38,w*.38]:
		for z in [-depth*.38,depth*.38]:
			box(Vector3(x,h*.335,z),Vector3(w*.15,h*.62,depth*.15),STONE,color(STONE,1.05))
	for y in [h*.25,h*.49,h*.625,h*.805]: box(Vector3(0,y,0),Vector3(w*.98,.16,depth*.98))
	# Four genuine open biforas above the nave roof, each with a central mullion.
	var bottom := h*.64; var spring := h*.717; var rise := h*.067
	for side in 4:
		frame=Transform3D(Basis(Vector3.UP,side*PI*.5),Vector3.ZERO)
		var span := w if side%2==0 else depth
		var outward := depth*.41 if side%2==0 else w*.41
		var radius := span*.135
		for sign in [-1.0,1.0]:
			var center_x: float = sign*span*.18
			pointed_band(Vector3(center_x,spring,outward),radius,rise,.105,.22)
			for x in [center_x-radius-.06,center_x+radius+.06]: box(Vector3(x,(bottom+spring)*.5,outward),Vector3(.12,spring-bottom,.23))
		box(Vector3(0,bottom-.035,outward),Vector3(span*.88,.15,.29))
		lancet(Vector3(0,h*.405,outward+.04),span*.19,h*.12,.15)
	frame=Transform3D.IDENTITY
	for x in [-w*.39,w*.39]:
		for z in [-depth*.39,depth*.39]: box(Vector3(x,h*.722,z),Vector3(w*.15,h*.163,depth*.15))
	# Visible suspended bronze bell inside the open belfry.
	var bell_y := h*.68
	var radius := minf(w,depth)*.18
	for i in 12:
		var a := TAU*float(i)/12; var b := TAU*float(i+1)/12
		var lower_a:=Vector3(cos(a)*radius,bell_y,sin(a)*radius)
		var lower_b:=Vector3(cos(b)*radius,bell_y,sin(b)*radius)
		var upper_a:=Vector3(cos(a)*radius*.48,bell_y+.55,sin(a)*radius*.48)
		var upper_b:=Vector3(cos(b)*radius*.48,bell_y+.55,sin(b)*radius*.48)
		quad(lower_a,upper_a,upper_b,lower_b,METAL,Color(.38,.29,.12))
	beam(Vector3(0,bell_y-.13,0),Vector3(0,bell_y+.8,0),.05,.05,METAL)
	spire(Vector3(0,h*.817,0),w,depth,h*.166,ROOF)
	beam(Vector3(0,h*.965,0),Vector3(0,h,0),.045,.045,METAL)
	beam(Vector3(-w*.065,h*.99,0),Vector3(w*.065,h*.99,0),.045,.045,METAL)
	solid(Vector3(0,h*.32,0),Vector3(w*.89,h*.64,depth*.89))

func window() -> void:
	var w: float=d.dimensions.x; var h: float=d.dimensions.y; var depth: float=d.dimensions.z
	lancet(Vector3(0,.06,-.008),w*.66,h-.22,depth*.75)

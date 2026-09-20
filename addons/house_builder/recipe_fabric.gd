extends RefCounted
## Cloth canopy helper for RecipeDetail. Coordinates are normalized to the
## component envelope; the back edge (-Z) attaches to a wall, +Z faces the shop.
## The cloth is a folded double-sided surface with a scalloped hanging edge.
static func build(detail: Node3D) -> void:
	const WOOD := 0
	const PAINT := 3
	var rng := RandomNumberGenerator.new()
	rng.seed = detail.detail_seed
	var cream := Color(.69,.60,.41)
	var ochre := Color(.42,.31,.17)
	if detail.palette.size() > PAINT: cream = detail.palette[PAINT]
	var folds: Array[float] = []
	for i in 13: folds.append(rng.randf_range(-.008,.008))
	for band in 12:
		var x0 := -.5 + float(band)/12.0
		var x1 := -.5 + float(band+1)/12.0
		var tint: Color = cream if (band / 2) % 2 == 0 else ochre
		for segment in 8:
			var t0 := float(segment)/8.0
			var t1 := float(segment+1)/8.0
			var a := cloth_point(x0, t0, folds[band])
			var b := cloth_point(x1, t0, folds[band+1])
			var c := cloth_point(x1, t1, folds[band+1])
			var d := cloth_point(x0, t1, folds[band])
			detail._quad(a,d,c,b,PAINT,tint)
			detail._quad(a,b,c,d,PAINT,tint.darkened(.12))
		# Four little curves in each broad colour stripe, cut into the hem.
		for segment in 4:
			var t0 := float(segment)/4.0
			var t1 := float(segment+1)/4.0
			var a := cloth_point(lerpf(x0,x1,t0),1.0,lerpf(folds[band],folds[band+1],t0))
			var b := cloth_point(lerpf(x0,x1,t1),1.0,lerpf(folds[band],folds[band+1],t1))
			var c := b - Vector3.UP*(.052+.018*sin(t1*PI))
			var d := a - Vector3.UP*(.052+.018*sin(t0*PI))
			detail._quad(a,d,c,b,PAINT,tint)
			detail._quad(a,b,c,d,PAINT,tint.darkened(.12))
	# Only two front supports touch the ground; the middle remains a clear bay.
	for x in [-.455,.455]:
		var center := Vector3(x,.40,.43)
		var size := Vector3(.030,.80,.060)
		detail._block(center,size,WOOD,.006)
		detail._solid(center,size)
		detail._beam(Vector3(x,.81,.43),Vector3(x,.995,-.48),.018,.028,WOOD)
		detail._beam(Vector3(x,.58,.43),Vector3(x,.87,.05),.018,.028,WOOD)
	for pair in [[.43,.81],[-.48,.995]]:
		detail._beam(Vector3(-.48,pair[1],pair[0]),Vector3(.48,pair[1],pair[0]),.018,.028,WOOD)

static func cloth_point(x: float, t: float, fold: float) -> Vector3:
	var y := lerpf(.99,.815,t) - .035*sin(t*PI) + fold*sin(t*PI)
	return Vector3(x,y,lerpf(-.5,.5,t))

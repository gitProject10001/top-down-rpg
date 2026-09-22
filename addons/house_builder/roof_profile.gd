@tool
extends RefCounted
## Height above the eaves. Endpoints are invariant; overhang follows the tangent.
static func height_at(half: float,rise: float,curve: float,x: float) -> float:
	var t := absf(x)/half
	if t>1.0: return -rise*(1.0-curve)*(t-1.0)
	return rise*((1.0-curve)*(1.0-t)+curve*(1.0-t)*(1.0-t))
static func slope_at(half: float,rise: float,curve: float,x: float) -> float:
	return -signf(x)*rise/half*((1.0-curve)+2.0*curve*(1.0-minf(absf(x)/half,1.0)))
static func segments(width: float,height: float,rise: float,curve: float,z: float) -> Array:
	var result: Array=[]
	var steps := 1 if curve==0.0 else maxi(8,ceili(width/.4))
	for side in [-1.0,1.0]:
		for i in steps:
			var a: float = side*width*.5*(1.0-float(i)/steps)
			var b: float = side*width*.5*(1.0-float(i+1)/steps)
			result.append([Vector3(a,height+height_at(width*.5,rise,curve,a),z),Vector3(b,height+height_at(width*.5,rise,curve,b),z)])
	return result
static func arc_table(half: float,rise: float,curve: float) -> PackedVector2Array:
	var result := PackedVector2Array([Vector2.ZERO])
	var previous := Vector2(0,rise)
	var distance := 0.0
	for i in range(1,129):
		var x := (half+.3)*float(i)/128.0
		var point := Vector2(x,height_at(half,rise,curve,x))
		distance+=previous.distance_to(point); previous=point
		result.append(Vector2(distance,x))
	return result
static func lookup(table: PackedVector2Array,value: float,axis: int) -> float:
	# Monotone arc/position samples: avoid scanning 128 entries for every tile vertex.
	if value<=table[0][axis]: return table[0][1-axis]
	if value>=table[-1][axis]: return table[-1][1-axis]
	var low := 0
	var high := table.size()-1
	while high-low>1:
		var middle := (low+high)/2
		if table[middle][axis]<value: low=middle
		else: high=middle
	return lerpf(table[low][1-axis],table[high][1-axis],inverse_lerp(table[low][axis],table[high][axis],value))

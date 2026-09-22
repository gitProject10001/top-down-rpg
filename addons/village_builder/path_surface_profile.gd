@tool
extends Resource
## Shared ground/scatter footprint. Centre lines and gameplay routes stay authored.
@export var seed := 8127
@export_range(.6,3.0,.05) var half_width := .85
@export_range(0.0,1.0,.02) var edge_variation := .30
@export_range(0.0,1.0,.02) var terrain_warp := .48
var _noise: FastNoiseLite
var _noise_seed := -1
func noise(p: Vector2) -> float:
	if _noise==null or _noise_seed!=seed:
		_noise=FastNoiseLite.new(); _noise.seed=seed; _noise.frequency=1.0; _noise_seed=seed
	return _noise.get_noise_2dv(p)
func distance_to_path(p: Vector2,points: PackedVector3Array) -> float:
	var distance := INF
	for i in range(points.size()-1):
		var a := Vector2(points[i].x,points[i].z); var b := Vector2(points[i+1].x,points[i+1].z)
		distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b)))
	return distance
func road_amount(p: Vector2,points: PackedVector3Array) -> float:
	var distance := distance_to_path(p,points)
	var width := maxf(.60,half_width+noise(p*.75)*edge_variation*2.0+noise(p*3.7)*.09)
	# Keep a readable worn centre; the outside mixes stones, soil and tufts.
	return 1.0-smoothstep(width*.65,width+.32,distance)
func warp(p: Vector2,points: PackedVector3Array) -> Vector2:
	var strength := 1.0-smoothstep(3.0,8.0,distance_to_path(p,points))
	return Vector2(noise(p*.7),noise(p*.7+Vector2(61,29)))*terrain_warp*2.0*strength

@tool
extends Resource
## Versioned generated layer. Manual scene content and sculpt strokes live elsewhere.
@export var version := 1
@export var seed_value := 2417
@export var regions: Array[Dictionary] = []

static func generate(seed_number: int) -> Resource:
	var plan = load("res://scripts/village/world_plan.gd").new()
	plan.seed_value = seed_number
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_number
	# Deliberate north/south forests, with separate eastern/western rocky uplands.
	for i in range(10):
		var kind := "forest" if i<6 else "upland"
		var p := Vector2(rng.randf_range(-650,650),rng.randf_range(200,680)*(1 if i%2==0 else -1))
		if kind == "upland": p.x = rng.randf_range(380,650)*(1 if i%2==0 else -1)
		plan.regions.append({"kind":kind,"center":p,"radius":rng.randf_range(150,260),"height":rng.randf_range(12,30)})
	return plan

func elevation(p: Vector2) -> float:
	var h := 0.0
	for region in regions:
		if region.kind != "upland": continue
		var distance: float = p.distance_to(region.center)/float(region.radius)
		h = maxf(h,float(region.height)*(1.0-smoothstep(0.2,1.0,distance)))
	return h

func forest_density(p: Vector2) -> float:
	var density := 0.08
	for region in regions:
		if region.kind != "forest": continue
		density = maxf(density,1.0-smoothstep(0.45,1.0,p.distance_to(region.center)/float(region.radius)))
	return density

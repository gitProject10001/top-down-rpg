@tool
extends Resource
## First composition family. More families implement propose(request, rng).
## Architectural component profiles remain the House Builder's responsibility.
func propose(request: Resource, rng: RandomNumberGenerator) -> Dictionary:
 var span := Vector2(rng.randf_range(request.minimum_span.x,request.maximum_span.x),rng.randf_range(request.minimum_span.y,request.maximum_span.y))
 var left := rng.randf()<0.5
 var keep_size := Vector2(rng.randf_range(5.5,7),rng.randf_range(5.5,7))
 var hall_size := Vector2(rng.randf_range(4,6),rng.randf_range(4,6))
 var buildings: Array=[]
 for entry in [["keep",keep_size,left],["hall",hall_size,not left]]:
  var size: Vector2=entry[1]
  var x: float=5.5+size.x*0.5 if entry[2] else span.x-5.5-size.x*0.5
  var z: float=-span.y+5.5+size.y*0.5+rng.randf_range(0,2)
  buildings.append({"id":entry[0],"builder":entry[0],"size":size,"position":Vector3(x,0,z)})
 return {"schema":1,"family":"single_court","span":span,"buildings":buildings,"entry":Vector3(span.x*0.5,0.15,4)}

func request_errors(request: Resource) -> PackedStringArray:
 for size in [request.minimum_span,request.maximum_span]:
  if not is_finite(size.x) or not is_finite(size.y) or size.x<26 or size.y<26 or size.x>27 or size.y>27:
   return PackedStringArray(["Prima famiglia: distanza fra torri compresa fra 26 e 27 m."])
 if request.minimum_span.x>request.maximum_span.x or request.minimum_span.y>request.maximum_span.y:
  return PackedStringArray(["Le dimensioni minime superano le massime."])
 return PackedStringArray()

func validate(plan: Dictionary, minimum_open: float) -> PackedStringArray:
 var errors := PackedStringArray()
 var inner := Rect2(Vector2(5,-plan.span.y+5),plan.span-Vector2(10,10))
 var occupied := 0.0; var rectangles: Array[Rect2]=[]; var ids := {}
 for building in plan.buildings:
  var rect := Rect2(Vector2(building.position.x,building.position.z)-building.size*0.5,building.size)
  if ids.has(building.id): errors.append("ID edificio duplicato.")
  ids[building.id]=true
  if not inner.encloses(rect): errors.append("Edificio senza margine dalle mura.")
  for previous in rectangles:
   if previous.grow(1).intersects(rect): errors.append("Edifici senza passaggio libero.")
  rectangles.append(rect); occupied+=rect.get_area()
 if 1.0-occupied/inner.get_area()<minimum_open: errors.append("Spazio scoperto insufficiente.")
 return errors

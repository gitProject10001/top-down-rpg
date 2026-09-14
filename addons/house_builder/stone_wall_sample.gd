@tool
extends Node3D
## Isolated masonry prototype. No changes to production House meshes or cutaway.
@export_range(2.0,12.0,0.1) var width := 6.0:
 set(value): width=value; request_rebuild()
@export_range(1.0,6.0,0.1) var height := 3.1:
 set(value): height=value; request_rebuild()
@export var stone_seed := 7159:
 set(value): stone_seed=value; request_rebuild()
var _generated: Node3D
var _pending := false
var _surface: SurfaceTool
var _rng := RandomNumberGenerator.new()
var stone_count := 0
func _ready() -> void: rebuild()
func request_rebuild() -> void:
 if not is_inside_tree() or _pending: return
 _pending=true; call_deferred("rebuild")
func triangle(a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
 var normal := (b-a).cross(c-a).normalized()
 for p in [a,c,b]:
  _surface.set_normal(normal); _surface.set_color(color); _surface.add_vertex(p)
func stone(center: Vector3,w: float,h: float) -> void:
 var corner := _rng.randf_range(0.025,0.065)
 var outline: Array[Vector2]=[Vector2(-w/2+corner,-h/2),Vector2(w/2-corner,-h/2),Vector2(w/2,-h/2+corner),Vector2(w/2,h/2-corner),Vector2(w/2-corner,h/2),Vector2(-w/2+corner,h/2),Vector2(-w/2,h/2-corner),Vector2(-w/2,-h/2+corner)]
 for i in outline.size(): outline[i]+=Vector2(_rng.randf_range(-0.012,0.012),_rng.randf_range(-0.012,0.012))
 var rings: Array=[]
 var projection := _rng.randf_range(0.23,0.33)
 var tilt := _rng.randf_range(-0.045,0.045)
 var bevel := _rng.randf_range(0.025,0.055)
 var shade := _rng.randf_range(0.15,0.26)
 var warm := _rng.randf_range(-0.018,0.022)
 var color := Color(shade+warm,shade,shade-warm*0.6,1.0)
 for band in 4:
  var ring: Array[Vector3]=[]
  for i in 8:
   var xy := outline[i]
   var inset := bevel if band==0 or band==3 else 0.0
   xy-=Vector2(signf(xy.x),signf(xy.y))*inset
   var z: float=[-0.25,-0.19,projection-bevel,projection][band]
   ring.append(center+Vector3(xy.x,xy.y,z+tilt*xy.x))
  rings.append(ring)
 for band in 3:
  for i in 8:
   var j := (i+1)%8
   triangle(rings[band][i],rings[band][j],rings[band+1][j],color)
   triangle(rings[band][i],rings[band+1][j],rings[band+1][i],color)
 # Slightly uneven front face: real facets, with no painted directional shadows.
 var crown := center+Vector3(0,0,projection+_rng.randf_range(-0.008,0.018))
 for i in 8:
  triangle(crown,rings[3][i],rings[3][(i+1)%8],color)
  triangle(center+Vector3(0,0,-0.25),rings[0][(i+1)%8],rings[0][i],color)
 stone_count+=1
func rebuild() -> void:
 if not is_inside_tree(): return
 _pending=false; stone_count=0
 if is_instance_valid(_generated): _generated.free()
 _generated=Node3D.new(); _generated.name="_StoneSample"; add_child(_generated,false,Node.INTERNAL_MODE_BACK)
 _rng.seed=stone_seed
 _surface=SurfaceTool.new(); _surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 var y := 0.0
 var row_heights: Array[float]=[]
 var total := 0.0
 for i in maxi(3,roundi(height/0.37)):
  var h := _rng.randf_range(0.30,0.44); row_heights.append(h); total+=h
 var row := 0
 for weight in row_heights:
  var row_height := height*weight/total
  var x := -width*0.5
  while x<width*0.5-0.01:
   var w := minf(_rng.randf_range(0.48,0.94),width*0.5-x)
   if x==-width*0.5 and row%2==1: w=minf(w,0.37)
   if width*0.5-x-w<0.28: w=width*0.5-x
   var gap := _rng.randf_range(0.012,0.026)
   if w>0.07 and row_height>0.07: stone(Vector3(x+w*0.5,y+row_height*0.5,0),w-gap,row_height-gap)
   x+=w
  y+=row_height; row+=1
 var material := ShaderMaterial.new(); material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
 var mesh := MeshInstance3D.new(); mesh.name="IndividualStones"; mesh.mesh=_surface.commit(); mesh.material_override=material; _generated.add_child(mesh)
 var mortar := MeshInstance3D.new(); mortar.name="RecessedMortar"
 var box := BoxMesh.new(); box.size=Vector3(width-0.03,height-0.03,0.32)
 mortar.mesh=box; mortar.position.y=height*0.5
 var base := StandardMaterial3D.new(); base.albedo_color=Color(0.16,0.15,0.13); base.roughness=1.0
 mortar.material_override=base; _generated.add_child(mortar)

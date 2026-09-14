@tool
extends Node3D
## One editable geological mass; no terrain or settlement dependencies.
@export var rock_seed := 1:
 set(v): rock_seed=v; schedule()
@export var dimensions := Vector3(4,3,3):
 set(v): dimensions=v.max(Vector3.ONE*0.3); schedule()
@export_range(0,1,0.05) var fracture := 0.45:
 set(v): fracture=v; schedule()
@export_range(1,6,1) var strata := 3:
 set(v): strata=v; schedule()
@export_range(-0.3,0.3,0.02) var strata_dip := 0.12:
 set(v): strata_dip=v; schedule()
@export_range(-0.25,0.25,0.01) var lean := 0.08:
 set(v): lean=v; schedule()
@export var collisions_enabled := true:
 set(v): collisions_enabled=v; schedule()
@export var stone_color := Color(0.34,0.35,0.32):
 set(v): stone_color=v; schedule()
@export_tool_button("Rigenera roccia") var rebuild_action: Callable=rebuild
var _pending := false
var _generated: Node3D
var triangle_count := 0
func _ready() -> void: rebuild()
func schedule() -> void:
 if _pending or not is_inside_tree(): return
 _pending=true; call_deferred("rebuild")
func rebuild() -> void:
 _pending=false
 if not is_inside_tree(): return
 if is_instance_valid(_generated): _generated.free()
 _generated=Node3D.new(); _generated.name="_Generated"; add_child(_generated,false,Node.INTERNAL_MODE_BACK)
 var result := generate()
 var visual := MeshInstance3D.new(); visual.name="Rock"; visual.mesh=result.mesh; _generated.add_child(visual)
 if collisions_enabled:
  var body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var convex := ConvexPolygonShape3D.new()
  convex.points=result.hull; shape.shape=convex; body.add_child(shape); _generated.add_child(body)
 triangle_count=result.triangles
func generate() -> Dictionary:
 var rng := RandomNumberGenerator.new(); rng.seed=rock_seed
 var sides := 8
 var contour: Array[Vector2]=[]; var heights: Array[float]=[]
 for i in sides:
  var angle := TAU*(i+0.13*rng.randf_range(-1,1))/sides
  var radius := rng.randf_range(0.76,1.0)
  contour.append(Vector2(cos(angle),sin(angle))*radius)
  heights.append(0.88+0.1*sin(angle+rock_seed*0.6)+rng.randf_range(-0.025,0.025))
 var rings: Array=[]; var hull := PackedVector3Array()
 var levels: Array[Vector2]=[Vector2(0,0.86),Vector2(0.08,1)]
 for layer in range(1,strata):
  var t: float=float(layer)/strata
  levels.append(Vector2(t-0.017,1.0))
  levels.append(Vector2(t,1.0-fracture*0.065))
  levels.append(Vector2(t+0.025,1.0))
 levels.append(Vector2(0.86,0.8)); levels.append(Vector2(1,0.54))
 levels.sort_custom(func(a,b): return a.x<b.x)
 for level in levels:
  var ring := PackedVector3Array()
  for i in sides:
   var t: float=level.x
   var seam := smoothstep(-0.1,0.6,sin(i*0.9+rock_seed*0.4))
   var scale_ring: float=lerpf(1.0,level.y,seam) if level.y>0.9 else level.y
   var taper := (1.0-0.19*t)*scale_ring
   var cut: float=1.0-fracture*0.18*sin(i*2.3+rock_seed*0.7)*t
   var p := contour[i]*taper*cut
   var y: float=t*dimensions.y*lerpf(1.0,heights[i],smoothstep(0.55,1.0,t))
   y+=strata_dip*p.x*dimensions.y*sin(t*PI)
   y+=fracture*0.16*sin(i*1.3+rock_seed)*sin(t*PI)*dimensions.y
   var vertex := Vector3((p.x+lean*t)*dimensions.x*0.5,y,p.y*dimensions.z*0.5)
   ring.append(vertex)
   hull.append(vertex)
  rings.append(ring)
 var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 var count := 0
 for j in range(rings.size()-1):
  for i in sides:
   var next: int=(i+1)%sides
   var color := stone_color*(0.97+0.04*sin(i*3.1+rock_seed))*rng.randf_range(0.985,1.015); color.a=0.88 if levels[j].y<0.98 and j>0 else 1.0
   # Outward normals, clockwise Godot winding.
   emit(tool,rings[j][i],rings[j][next],rings[j+1][next],color)
   emit(tool,rings[j][i],rings[j+1][next],rings[j+1][i],color); count+=2
 var top := Vector3.ZERO
 for point in rings[-1]: top+=point
 top/=sides
 for i in sides:
  emit(tool,rings[-1][i],rings[-1][(i+1)%sides],top,stone_color); count+=1
  emit(tool,rings[0][(i+1)%sides],rings[0][i],Vector3.ZERO,stone_color); count+=1
 var mesh := tool.commit()
 var material := ShaderMaterial.new(); material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
 mesh.surface_set_material(0,material)
 return {"mesh":mesh,"hull":hull,"triangles":count}
static func emit(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
 tool.set_normal((c-a).cross(b-a).normalized()); tool.set_color(color)
 tool.add_vertex(a); tool.add_vertex(b); tool.add_vertex(c)

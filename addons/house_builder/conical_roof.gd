@tool
extends RefCounted
## Independent roof backend: relief shingles on tapered polygon faces.
var st: SurfaceTool
func tri(a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
 var normal := (c-a).cross(b-a).normalized()
 for p in [a,b,c]:
  st.set_normal(normal); st.set_color(color); st.set_uv(Vector2(p.x,p.z)); st.set_uv2(Vector2.ZERO); st.add_vertex(p)
func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color) -> void:
 tri(a,b,c,color); tri(a,c,d,color)
func generate(points: Array[Vector3],height: float,rise: float,seed_value: int,curved: bool=false) -> ArrayMesh:
 st=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rng := RandomNumberGenerator.new(); rng.seed=seed_value
 var tip := Vector3(0,height+rise,0)
 for face in points.size():
  var a := points[face]; var b := points[(face+1)%points.size()]
  a+=a.normalized()*0.3; b+=b.normalized()*0.3
  a.y=height; b.y=height
  if not curved: tri(a,tip,b,Color(0.09,0.08,0.07,0.25))
  var rows := maxi(2,ceili(a.distance_to(tip)/0.3))
  for row in rows:
   var low := float(row)/rows
   var high := minf(1.0,float(row+1.3)/rows)
   var left := profile_point(a,tip,low,curved); var right := profile_point(b,tip,low,curved)
   if curved:
    var upper_left := profile_point(a,tip,high,true)
    var upper_right := profile_point(b,tip,high,true)
    if high>=0.999: tri(left,tip,right,Color(0.09,0.08,0.07,0.25))
    else: quad(left,upper_left,upper_right,right,Color(0.09,0.08,0.07,0.25))
   var count := maxi(1,ceili(left.distance_to(right)/0.38))
   for column in count:
    var u0 := (column+0.035)/count; var u1 := (column+0.965)/count
    var p0 := profile_point(a.lerp(b,u0),tip,low,curved)
    var p1 := profile_point(a.lerp(b,u1),tip,low,curved)
    var p2 := profile_point(a.lerp(b,u1),tip,high,curved)
    var p3 := profile_point(a.lerp(b,u0),tip,high,curved)
    var normal := (p1-p0).cross(p3-p0).normalized()
    var lift := normal*rng.randf_range(0.035,0.055)
    var color := Color(0.47,0.37,0.30)*rng.randf_range(0.85,1.15); color.a=0.9
    if high>=0.999: tri(p0+lift,tip+lift,p1+lift,color)
    else: quad(p0+lift,p3+lift,p2+lift,p1+lift,color)
    quad(p0,p0+lift,p1+lift,p1,Color(0.18,0.14,0.12,0.3))
    quad(p0,p3,p3+lift,p0+lift,Color(0.24,0.20,0.17,0.5))
    quad(p1,p1+lift,p2+lift,p2,Color(0.24,0.20,0.17,0.5))
 st.index()
 var mesh := st.commit()
 var material := ShaderMaterial.new(); material.shader=preload("res://shaders/pixelart/roof_clay.gdshader")
 material.set_shader_parameter("cavity_strength",0.78); mesh.surface_set_material(0,material)
 return mesh

func profile_point(base: Vector3,tip: Vector3,t: float,curved: bool) -> Vector3:
 if not curved: return base.lerp(tip,t)
 if t>=0.999999: return tip
 var angle := t*PI*0.5
 return Vector3(base.x*cos(angle),base.y+(tip.y-base.y)*sin(angle),base.z*cos(angle))

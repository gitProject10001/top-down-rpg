@tool
extends RefCounted
static func emit(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,normal: Vector3,color: Color) -> void:
 if (b-a).cross(c-a).dot(normal)<0:
  var swap := b; b=c; c=swap
 tool.set_normal((b-a).cross(c-a).normalized()); tool.set_color(color)
 for p in [a,c,b]: tool.add_vertex(p)
static func append_to(house: Node3D,target: ArrayMesh) -> void:
 var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 var emitted := false
 var done := {}
 for a in house.wall_count():
  for end_a in [-1.0,1.0]:
   var corner: Vector3=house.wall_point(a,end_a*house.wall_length(a)*0.5,0)
   for b in range(a+1,house.wall_count()):
    for end_b in [-1.0,1.0]:
     if corner.distance_to(house.wall_point(b,end_b*house.wall_length(b)*0.5,0))>0.005: continue
     var key := str(corner)
     if done.has(key): continue
     done[key]=true
     var na: Vector3=house.wall_normal(a); var nb: Vector3=house.wall_normal(b)
     var denominator := 1.0+na.dot(nb)
     if denominator<0.15: continue
     var da: Vector3=(house.wall_point(a,0,0)-corner).normalized()
     var db: Vector3=(house.wall_point(b,0,0)-corner).normalized()
     var course_height: float=house.masonry_finish.block_size.y if house.masonry_finish else .37
     var rows := maxi(1,roundi(house.wall_height/course_height))
     for row in rows:
      var la := 0.52 if row%2==0 else 0.29
      var lb := 0.29 if row%2==0 else 0.52
      la=minf(la,house.wall_length(a)*0.3); lb=minf(lb,house.wall_length(b)*0.3)
      var outer := corner+(na+nb)*0.065/denominator
      var inner := corner-(na+nb)*0.055/denominator
      var points: Array[Vector3]=[outer+da*la,outer+da*0.022,outer+db*0.022,outer+db*lb,corner+db*lb-nb*0.055,inner,corner+da*la-na*0.055]
      var polygon := PackedVector2Array()
      for p in points: polygon.append(Vector2(p.x,p.z))
      var indices := Geometry2D.triangulate_polygon(polygon)
      if indices.is_empty(): continue
      var y0: float=row*house.wall_height/rows+0.007
      var y1: float=(row+1)*house.wall_height/rows-0.007
      var color := Color(0.22,0.225,0.21,0.85)*(1.0+0.045*sin(row*7.3+a*2.1)); color.a=0.85
      for i in range(0,indices.size(),3):
       var p: Vector3=points[indices[i]]; var q: Vector3=points[indices[i+1]]; var r: Vector3=points[indices[i+2]]
       emit(tool,p+Vector3.UP*y1,q+Vector3.UP*y1,r+Vector3.UP*y1,Vector3.UP,color)
       emit(tool,p+Vector3.UP*y0,q+Vector3.UP*y0,r+Vector3.UP*y0,Vector3.DOWN,color)
      var clockwise := Geometry2D.is_polygon_clockwise(polygon)
      for i in points.size():
       var p: Vector3=points[i]; var q: Vector3=points[(i+1)%points.size()]
       var normal := (q-p).cross(Vector3.UP)*(1.0 if clockwise else -1.0)
       emit(tool,p+Vector3.UP*y0,q+Vector3.UP*y0,q+Vector3.UP*y1,normal,color)
       emit(tool,p+Vector3.UP*y0,q+Vector3.UP*y1,p+Vector3.UP*y1,normal,color)
      emitted=true
 if emitted:
  tool.commit(target)
  var material := ShaderMaterial.new(); material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
  if house.masonry_finish: house.masonry_finish.apply(material,.205,false,house.position.y if house.has_method("volume_host") else 0.0)
  target.surface_set_material(target.get_surface_count()-1,material)

@tool
extends RefCounted
const Sample=preload("res://addons/house_builder/stone_wall_sample.gd")
const Join=preload("res://addons/house_builder/mesh_join.gd")
static func supported(house: Node3D) -> bool:
 if house.has_method("is_curtain_wall") and absf(house._slope_rise)>0.001: return false
 if "structure_kind" in house and house.structure_kind!=0: return false
 return true
static func append_to(house: Node3D, body: MeshInstance3D) -> void:
 if not supported(house): return
 var stone: bool=house.wall_finish==1 or house.has_method("is_curtain_wall")
 if not stone and not house.weathered: return
 var result := ArrayMesh.new(); Join.append(result,body.mesh,Transform3D.IDENTITY,[])
 for wall in house.wall_count():
  var sample=Sample.new(); sample.width=house.wall_length(wall); sample.height=house.wall_height
  sample.stone_seed=house.house_seed+wall*71; sample.detail_mode=1
  house._generated.add_child(sample,false,Node.INTERNAL_MODE_BACK)
  var tangent: Vector3=(house.wall_point(wall,1,0)-house.wall_point(wall,0,0)).normalized()
  var normal: Vector3=house.wall_normal(wall)
  var frame := Transform3D(Basis(tangent,Vector3.UP,normal*0.18),house.wall_point(wall,0,0,-0.008 if stone else -0.076))
  var blocks: MeshInstance3D=sample._generated.get_node("IndividualStones")
  var source: ArrayMesh=blocks.mesh.duplicate(); source.surface_set_material(0,blocks.material_override)
  Join.append(result,source,frame,[])
  if not stone:
   var mortar: MeshInstance3D=sample._generated.get_node("RecessedMortar")
   var backing := ArrayMesh.new(); Join.append(backing,mortar.mesh,Transform3D.IDENTITY,[])
   var material := ShaderMaterial.new(); material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
   material.set_shader_parameter("use_vertex_color",false); backing.surface_set_material(0,material)
   Join.append(result,backing,frame*mortar.transform,[])
  sample.free()
 body.mesh=result

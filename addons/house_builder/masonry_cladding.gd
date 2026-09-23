@tool
extends RefCounted
const Sample=preload("res://addons/house_builder/stone_wall_sample.gd")
const Join=preload("res://addons/house_builder/mesh_join.gd")
static var _walls: Dictionary={}
const Cache=preload("res://scripts/generation_cache.gd")
static func supported(house: Node3D) -> bool:
 if house.has_method("is_curtain_wall") and absf(house._slope_rise)>0.001: return false
 if "structure_kind" in house and house.structure_kind!=0: return false
 return true
static func append_to(house: Node3D, body: MeshInstance3D) -> void:
 if not supported(house): return
 var stone: bool=house.wall_finish==1 or house.has_method("is_curtain_wall")
 if not stone and not house.weathered: return
 var result := ArrayMesh.new(); await Join.append(result,body.mesh,Transform3D.IDENTITY,[],house if house._cooperative else null)
 for wall in house.wall_count():
  if not await house.yield_build(): return
  # Cache each deterministic wall separately: resizing the front does not
  # regenerate stones on the two unchanged sides. Materials stay per owner.
  var length: float=house.wall_length(wall)
  var key: String=Cache.digest([length,house.wall_height,house.house_seed+wall*71,house.masonry_finish.block_size if house.masonry_finish else Vector2(.72,.37)])
  var cached: Array=_walls.get(key,[])
  if cached.is_empty():
   var sample=Sample.new(); sample.width=length; sample.height=house.wall_height
   sample.stone_seed=house.house_seed+wall*71; sample.detail_mode=1
   sample.masonry_finish=house.masonry_finish
   house._generated.add_child(sample,false,Node.INTERNAL_MODE_BACK)
   var blocks: MeshInstance3D=sample._generated.get_node("IndividualStones")
   var mortar: MeshInstance3D=sample._generated.get_node("RecessedMortar")
   cached=[blocks.mesh,mortar.mesh,mortar.transform]
   if _walls.size()>=64: _walls.erase(_walls.keys()[0])
   _walls[key]=cached
   sample.free()
  var tangent: Vector3=(house.wall_point(wall,1,0)-house.wall_point(wall,0,0)).normalized()
  var normal: Vector3=house.wall_normal(wall)
  var frame := Transform3D(Basis(tangent,Vector3.UP,normal*0.18),house.wall_point(wall,0,0,-0.008 if stone else -0.076))
  var source: ArrayMesh=cached[0].duplicate()
  var material := ShaderMaterial.new(); material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
  var offset: float=house.position.y if house.has_method("volume_host") else 0.0
  if house.masonry_finish:
   house.masonry_finish.apply(material,.205,false,offset)
   material.set_shader_parameter("masonry_ledge_heights",Vector4(.34,house.wall_height-.10,-100,-100)+Vector4.ONE*offset)
  source.surface_set_material(0,material)
  await Join.append(result,source,frame,[],house if house._cooperative else null)
  if not stone:
   var backing := ArrayMesh.new(); await Join.append(backing,cached[1],Transform3D.IDENTITY,[],house if house._cooperative else null)
   if not await house.yield_build(): return
   var mortar_material := ShaderMaterial.new(); mortar_material.shader=preload("res://shaders/pixelart/solid_masonry.gdshader")
   mortar_material.set_shader_parameter("use_vertex_color",false); backing.surface_set_material(0,mortar_material)
   await Join.append(result,backing,frame*cached[2],[],house if house._cooperative else null)
 if stone: preload("res://addons/house_builder/corner_masonry.gd").append_to(house,result)
 body.mesh=result

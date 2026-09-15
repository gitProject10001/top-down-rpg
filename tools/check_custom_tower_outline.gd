extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var tower=preload("res://addons/house_builder/polygon_tower.gd").new()
 var outline=tower.regular_outline()
 for i in outline.size(): outline[i].x+=outline[i].y*0.3
 assert(tower.outline_error(outline).is_empty())
 tower.custom_outline=outline; tower.width=8; tower.depth=8
 root.add_child(tower); tower.rebuild()
 for i in 8:
  assert(tower.hit_wall(tower.wall_point(i,0,1,2),-tower.wall_normal(i)).wall==i)
 var invalid=outline.duplicate(); invalid[2]=Vector2.ZERO
 assert(not tower.outline_error(invalid).is_empty())
 invalid=outline.duplicate(); invalid[1]=invalid[0]
 assert(not tower.outline_error(invalid).is_empty())
 invalid=outline.duplicate(); invalid.reverse()
 assert(not tower.outline_error(invalid).is_empty())
 var packed=PackedScene.new(); assert(packed.pack(tower)==OK)
 var copy=packed.instantiate(); assert(copy.custom_outline==outline); copy.free()
 tower.width=10
 assert(tower.custom_outline==outline and is_equal_approx(tower.footprint_vertices()[0].x,outline[0].x*10))
 tower.free(); print("CUSTOM_CONVEX_OUTLINE_FACES_VALIDATION_SAVE_RESIZE_OK"); quit()

extends SceneTree
func centroid(field) -> float:
    var sum:=0.0;var mass:=0.0
    for y in field.SIZE:
        for x in field.SIZE:
            var weight: float=pow(field.height[y*field.SIZE+x],2)
            sum+=(field.bounds.position.x+(x+.5)*field.bounds.size.x/field.SIZE)*weight
            mass+=weight
    return sum/maxf(mass,1e-15)
func _initialize() -> void:
    var centers: Array[float]=[]
    for direction in [-1.0,0.0,1.0]:
        var field=load("res://addons/water_builder/local_wave_field.gd").new()
        field.configure(PackedVector2Array([Vector2(-9,-8),Vector2(9,-8),Vector2(9,10),Vector2(-9,10)]),PackedVector4Array())
        field.bake_flow(func(_p):return Vector2(direction,0))
        field.impulse(Vector2.ZERO,.035)
        for i in 25:field.step()
        centers.append(centroid(field))
        for i in 300:
            if i%6==0:field.impulse(Vector2.ZERO,.035)
            field.step()
            assert(is_finite(field.max_height()) and field.max_height()<.25)
        print("FLOW_COST ms/step=",float(field.total_usec)/field.step_count/1000)
    assert(centers[0]<centers[1]-.2 and centers[2]>centers[1]+.2,"Waves travel with signed current")
    print("FLOW_WAVES_PASS centroids=",centers)
    quit()

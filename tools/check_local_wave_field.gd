extends SceneTree
func _initialize() -> void:
    var field=load("res://addons/water_builder/local_wave_field.gd").new()
    var polygon:=PackedVector2Array([Vector2(-9,-8),Vector2(9,-8),Vector2(9,10),Vector2(-9,10)])
    field.configure(polygon,PackedVector4Array([Vector4(2,1,1.0,1)]))
    field.impulse(Vector2(0,0),.035)
    var initial: float=field.max_height()
    assert(initial>0.01 and initial<.05)
    var original: PackedFloat32Array=field.height.duplicate()
    for i in 45:field.step()
    var changed:=0
    for i in field.height.size():
        if absf(original[i])<.000001 and absf(field.height[i])>.00001:changed+=1
        assert(is_finite(field.height[i]))
        if not field.wet[i]:assert(field.height[i]==0.0)
    assert(changed>20,"Impulse propagates beyond its injection support")
    for i in 555:field.step()
    assert(field.max_height()<initial*.1,"Unforced disturbances decay")
    for i in 300:
        if i%3==0:field.impulse(Vector2(sin(i*.1)*2,-2),.04)
        field.step()
        assert(field.max_height()<.25,"Repeated input stays bounded without clipping the solver")
    field.advance(2.0)
    assert(field.dropped_time>1.0,"Long frame is capped, no catch-up spiral")
    print("LOCAL_WAVE_PASS propagated_cells=",changed," mean_step_ms=",float(field.total_usec)/field.step_count/1000," max_step_ms=",field.max_usec/1000.0," peak=",field.max_height())
    quit()

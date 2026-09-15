@tool
extends "res://addons/water_builder/water_body.gd"
## FlowGuide is an ordinary editable Path3D. The surface follows its XZ curve.
@export var widths := PackedFloat32Array([5.0,6.5,4.0,7.0]):
    set(value):
        widths=value
        schedule_build()
var _curve: Curve3D

func _ready() -> void:
    river_mode=true
    var guide:=get_node_or_null("FlowGuide") as Path3D
    if guide:
        _curve=guide.curve
        if _curve and not _curve.changed.is_connected(schedule_build):
            _curve.changed.connect(schedule_build)
    super._ready()

func rebuild() -> void:
    if _curve and _curve.point_count>=2:
        var length:=_curve.get_baked_length()
        if length<.1:
            _pending=false
            return
        var left:=PackedVector2Array()
        var right:=PackedVector2Array()
        var path:=PackedVector2Array()
        for i in 16:
            var fraction:=float(i)/15.0
            var distance:=length*fraction
            var center:=_curve.sample_baked(distance,true)
            var tangent:=_curve.sample_baked(minf(length,distance+.08),true)-_curve.sample_baked(maxf(0,distance-.08),true)
            var heading:=Vector2(tangent.x,tangent.z).normalized()
            var side:=Vector2(-heading.y,heading.x)
            var p:=Vector2(center.x,center.z)
            var index:=fraction*maxi(0,widths.size()-1)
            var w:=5.0
            if not widths.is_empty():
                w=lerpf(widths[floori(index)],widths[mini(ceili(index),widths.size()-1)],fmod(index,1.0))
            path.append(p)
            left.append(p+side*maxf(1.0,w)*.5)
            right.append(p-side*maxf(1.0,w)*.5)
        right.reverse()
        left.append_array(right)
        # Assign only when changed: setters defer rebuilds.
        if boundary!=left:boundary=left
        if flow_path!=path:flow_path=path
    _read_rocks()
    super.rebuild()

func _read_rocks() -> void:
    obstacles.clear()
    var rocks:=get_node_or_null("Rocks")
    if not rocks:return
    for rock in rocks.get_children():
        if obstacles.size()>=12:break
        var local: Vector3=to_local(rock.global_position) if is_inside_tree() else rock.position
        var dimensions: Vector3=rock.dimensions*rock.scale.abs()
        obstacles.append(Vector4(local.x,local.z,maxf(dimensions.x,dimensions.z)*.4,1.0))

func _process(delta: float) -> void:
    var old:=obstacles.duplicate()
    _read_rocks()
    if old!=obstacles:schedule_build()
    super._process(delta)

func flow_at(point: Vector2) -> Vector2:
    var best:=INF
    var result:=Vector2.ZERO
    for i in range(flow_path.size()-1):
        var a:=flow_path[i]
        var b:=flow_path[i+1]
        var delta:=b-a
        var t:=clampf((point-a).dot(delta)/maxf(delta.length_squared(),.00001),0,1)
        var distance:=point.distance_to(a+delta*t)
        if distance<best:
            best=distance
            var incoming: Vector2=(b-flow_path[maxi(0,i-1)]).normalized()
            var outgoing: Vector2=(flow_path[mini(flow_path.size()-1,i+2)]-a).normalized()
            result=incoming.lerp(outgoing,t).normalized()*flow_speed
    for obstacle in obstacles:
        var offset:=point-Vector2(obstacle.x,obstacle.y)
        var distance:=offset.length()
        if distance<obstacle.z:return Vector2.ZERO
        var radial:=offset/maxf(distance,.001)
        var ratio:=pow(obstacle.z/maxf(distance,.001),2)
        result-=ratio*(2*radial*result.dot(radial)-result)
    return result.limit_length(flow_speed*2.5)

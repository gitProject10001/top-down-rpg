extends RefCounted
## Bounded CPU reference heightfield for A/B validation before a GPU implementation.
## Damped wave equation, semi-implicit update; no horizontal mass transport.
const SIZE := 64
const DT := 1.0/30.0
const SPEED := 2.5
var bounds := Rect2(-10,-9,20,20)
var height := PackedFloat32Array()
var velocity := PackedFloat32Array()
var wet := PackedByteArray()
var neighbors := PackedInt32Array()
var damping := PackedFloat32Array()
var next_velocity := PackedFloat32Array()
var texture: ImageTexture
var step_count := 0
var total_usec := 0
var max_usec := 0
var dropped_time := 0.0
var _accumulator := 0.0
var flow_texture: ImageTexture
var _sources:=PackedInt32Array()
var _weights:=PackedFloat32Array()
var _advected_height:=PackedFloat32Array()
var _advected_velocity:=PackedFloat32Array()

func bake_flow(sample: Callable) -> void:
    # Fixed-step semi-Lagrangian backtrace, baked once per guide/rock edit.
    _sources.resize(SIZE*SIZE*4);_weights.resize(SIZE*SIZE*4)
    _advected_height.resize(SIZE*SIZE);_advected_velocity.resize(SIZE*SIZE)
    var pixels:=PackedFloat32Array();pixels.resize(SIZE*SIZE*2)
    for y in SIZE:
        for x in SIZE:
            var i:=y*SIZE+x
            var p:=bounds.position+(Vector2(x,y)+Vector2(.5,.5))*bounds.size/SIZE
            var flow: Vector2=sample.call(p) if wet[i] else Vector2.ZERO
            # Never backtrace more than half a cell: avoids skipping thin obstacles.
            flow=flow.limit_length(bounds.size.x/SIZE/DT*.5)
            pixels[i*2]=flow.x;pixels[i*2+1]=flow.y
            var source:=Vector2(x,y)-flow*DT*SIZE/bounds.size
            source=source.clamp(Vector2.ZERO,Vector2.ONE*(SIZE-1))
            var a:=Vector2i(source.floor());var f:=source-Vector2(a)
            var indices: Array[int]=[a.y*SIZE+a.x,a.y*SIZE+mini(a.x+1,SIZE-1),mini(a.y+1,SIZE-1)*SIZE+a.x,mini(a.y+1,SIZE-1)*SIZE+mini(a.x+1,SIZE-1)]
            var weights: Array[float]=[(1-f.x)*(1-f.y),f.x*(1-f.y),(1-f.x)*f.y,f.x*f.y]
            for j in 4:
                _sources[i*4+j]=indices[j] if wet[indices[j]] else i
                _weights[i*4+j]=weights[j]
    flow_texture=ImageTexture.create_from_image(Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGF,pixels.to_byte_array()))

func _advect() -> void:
    if _sources.is_empty():return
    for i in height.size():
        var h:=0.0;var v:=0.0
        for j in 4:
            var source:=_sources[i*4+j];var weight:=_weights[i*4+j]
            h+=height[source]*weight;v+=velocity[source]*weight
        _advected_height[i]=h;_advected_velocity[i]=v
    height=_advected_height.duplicate();velocity=_advected_velocity.duplicate()


func configure(polygon: PackedVector2Array, obstacles: PackedVector4Array) -> void:
    var count:=SIZE*SIZE
    height.resize(count);height.fill(0)
    velocity.resize(count);velocity.fill(0)
    next_velocity.resize(count);next_velocity.fill(0)
    wet.resize(count);neighbors.resize(count*4);damping.resize(count)
    for y in SIZE:
        for x in SIZE:
            var i:=y*SIZE+x
            var p:=bounds.position+(Vector2(x,y)+Vector2(.5,.5))*bounds.size/float(SIZE)
            wet[i]=int(Geometry2D.is_point_in_polygon(p,polygon))
            for obstacle in obstacles:
                if p.distance_to(Vector2(obstacle.x,obstacle.y))<obstacle.z:wet[i]=0
            var edge:=mini(mini(x,y),mini(SIZE-1-x,SIZE-1-y))
            damping[i]=exp(-DT*(1.1+12.0*(1.0-smoothstep(0,7,edge))))
    for y in SIZE:
        for x in SIZE:
            var i:=y*SIZE+x
            var adjacent: Array[int]=[y*SIZE+maxi(x-1,0),y*SIZE+mini(x+1,SIZE-1),maxi(y-1,0)*SIZE+x,mini(y+1,SIZE-1)*SIZE+x]
            for j in 4:neighbors[i*4+j]=adjacent[j] if wet[adjacent[j]] else i
    texture=ImageTexture.create_from_image(Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RF,height.to_byte_array()))

func impulse(point: Vector2, strength: float=.025) -> void:
    if not bounds.has_point(point):return
    var center:=(point-bounds.position)/bounds.size*SIZE-Vector2(.5,.5)
    var weights: Array[Vector2]=[]
    var sum:=0.0
    for y in range(maxi(0,floori(center.y)-5),mini(SIZE,ceili(center.y)+6)):
        for x in range(maxi(0,floori(center.x)-5),mini(SIZE,ceili(center.x)+6)):
            var i:=y*SIZE+x
            if not wet[i]:continue
            var r2:=Vector2(x,y).distance_squared_to(center)
            var value:=exp(-r2/1.5)-.25*exp(-r2/6.0)
            weights.append(Vector2(i,value));sum+=value
    if weights.is_empty():return
    # Balanced positive/negative displacement prevents repeated footsteps raising the lake.
    var mean:=sum/weights.size()
    for entry in weights:
        height[int(entry.x)]+=clampf(strength,-.04,.04)*(entry.y-mean)

func step() -> void:
    var start:=Time.get_ticks_usec()
    var dx:=bounds.size.x/SIZE
    var k:=pow(SPEED*DT/dx,2)
    assert(k<.5,"Wave CFL bound")
    for i in height.size():
        if not wet[i]:continue
        var n:=i*4
        var lap:=height[neighbors[n]]+height[neighbors[n+1]]+height[neighbors[n+2]]+height[neighbors[n+3]]-4.0*height[i]
        next_velocity[i]=(velocity[i]+k*lap)*damping[i]
    for i in height.size():
        velocity[i]=next_velocity[i]
        height[i]+=velocity[i]
    _advect()
    var usec:=Time.get_ticks_usec()-start
    total_usec+=usec;max_usec=maxi(max_usec,usec);step_count+=1

func advance(delta: float) -> void:
    _accumulator+=delta
    var steps:=0
    while _accumulator>=DT and steps<3:
        step();_accumulator-=DT;steps+=1
    if _accumulator>=DT:
        dropped_time+=_accumulator
        _accumulator=0
    if steps>0:
        texture.update(Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RF,height.to_byte_array()))

func max_height() -> float:
    var peak:=0.0
    for h in height:peak=maxf(peak,absf(h))
    return peak

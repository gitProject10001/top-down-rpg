extends SceneTree
func _initialize() -> void:call_deferred("run")
func nodes(n: Node) -> Array:
    var result: Array=[n]
    for child in n.get_children(true):result.append_array(nodes(child))
    return result
func run() -> void:
    var scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate();scene.set_script(null);root.add_child(scene)
    for i in 30:await process_frame
    var all:=nodes(scene);var samples: Array=[];var counts: Dictionary={}
    for n in all:
        if n.get_script() and n.has_method("_process"):
            samples.append(n);n.set_process(false)
            if n.get("build_count")!=null:counts[n]=n.build_count
    var totals: Dictionary={}
    for i in 20:
        for n in samples:
            var start:=Time.get_ticks_usec();n._process(.016)
            var path: String=n.get_script().resource_path
            totals[path]=totals.get(path,0)+Time.get_ticks_usec()-start
    for path in totals:print("IDLE_SCRIPT ",path," ms/frame=",totals[path]/20000.0)
    for n in counts:
        if n.build_count!=counts[n]:print("IDLE_REBUILD ",n.get_path()," count=",n.build_count-counts[n])
    print("EDITOR_HINT ",Engine.is_editor_hint()," nodes=",all.size())
    scene.queue_free();await process_frame;quit()

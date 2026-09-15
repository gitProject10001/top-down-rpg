"""Execute in Blender MCP. Original geometry; no tutorial assets redistributed.

Editable branch paths and crown lobes -> alpha sprays -> ellipsoid normals -> GLB.
The source scene is separate from the user's open tutorial scene.
"""
import bpy
import math
import random
import json
import numpy as np
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/foliage_study'
OUT.mkdir(parents=True, exist_ok=True)
rng = random.Random(2109)


def mask_image(kind):
    size = 512
    yy, xx = np.mgrid[0:size, 0:size] / (size - 1)
    a = np.zeros((size, size), dtype=np.float32)
    # A branching spray rather than the silhouette of an entire crown.
    for j in range(42 if kind == 'broadleaf' else 100):
        cy = rng.uniform(.13, .88)
        side = -1 if j % 2 else 1
        cx = .5 + side * rng.uniform(.025, .31) * math.sin(cy * math.pi)
        angle = side * rng.uniform(.6, 1.1)
        dx, dy = xx-cx, yy-cy
        u = dx*math.cos(angle)-dy*math.sin(angle)
        v = dx*math.sin(angle)+dy*math.cos(angle)
        width = rng.uniform(.025, .047) if kind == 'broadleaf' else .009
        length = rng.uniform(.043, .073) if kind == 'broadleaf' else rng.uniform(.04, .10)
        oval = (u/width)**2+(v/length)**2
        grain = np.sin(xx*240+yy*167)*np.sin(yy*320-xx*121)*.12
        a = np.maximum(a, np.clip((1-oval+grain)*8, 0, 1))
    pixels = np.ones((size, size, 4), dtype=np.float32)
    pixels[:, :, :3] = (.9 + .1*np.sin(xx*23+yy*13))[:, :, None]
    pixels[:, :, 3] = a
    image = bpy.data.images.new('Study_'+kind+'_spray', width=size, height=size, alpha=True)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(OUT / (kind+'_spray.png'))
    image.file_format = 'PNG'
    image.save()
    return image


def material(name, color, image=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = 1
    if image:
        vertex = mat.node_tree.nodes.new('ShaderNodeVertexColor')
        vertex.layer_name = 'ShadeWeights'
        mat.node_tree.links.new(vertex.outputs['Color'], bsdf.inputs['Base Color'])
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = image
        mat.node_tree.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
        mat.use_backface_culling = False
    return mat


def build(kind):
    scene = bpy.data.scenes.new('FoliageStudy_'+kind)
    bpy.context.window.scene = scene
    bark = material('StudyBark_'+kind, (.23,.135,.065))
    foliage_image = mask_image(kind)
    foliage = material('StudyLeaves_'+kind, (.24,.49,.12), foliage_image)
    branches = []
    lobes = []
    paths = []

    def branch(points, radius):
        paths.append({'points':points, 'radius':radius})
        verts, faces = [], []
        count = 8
        for k, pt in enumerate(points):
            p = Vector(pt)
            tangent = Vector(points[min(k+1,len(points)-1)])-Vector(points[max(0,k-1)])
            rotation = tangent.to_track_quat('Z','Y')
            rad = radius*(1-.91*k/(len(points)-1))
            for i in range(count):
                angle=i*math.tau/count
                verts.append(p+rotation@Vector((math.cos(angle)*rad,math.sin(angle)*rad,0)))
        for k in range(len(points)-1):
            for i in range(count):
                a=k*count+i; b=k*count+(i+1)%count
                faces.append((a,b,b+count,a+count))
        faces += [tuple(reversed(range(count))), tuple(range(len(verts)-count,len(verts)))]
        mesh=bpy.data.meshes.new('BranchMesh'); mesh.from_pydata(verts,[],faces); mesh.update()
        obj=bpy.data.objects.new('Branch_%03d'%len(paths),mesh); scene.collection.objects.link(obj)
        mesh.materials.append(bark); branches.append(obj)

    if kind == 'broadleaf':
        branch([(0,0,0),(-.22,.03,1.2),(.18,.06,2.3),(.05,.12,3.2),(-.45,.18,4.8),(-.3,.22,6.1)],.39)
        for i in range(11):
            angle=i*2.39996
            z=2.25+i*.235
            reach=rng.uniform(1.5,2.6)*(1-.025*i)
            joint=Vector((math.cos(angle)*reach*.5,math.sin(angle)*reach*.5,z+.65))
            tip=Vector((math.cos(angle)*reach,math.sin(angle)*reach,z+rng.uniform(.9,1.5)))
            branch([(.08,0,z),tuple(joint),tuple(tip)],.17*(1-i*.035))
            for j in range(4):
                az=angle+(j-1.5)*.65
                end=tip+Vector((math.cos(az)*.65,math.sin(az)*.65,rng.uniform(-.15,.65)))
                branch([tuple(joint.lerp(tip,.65)),tuple(end)],.045)
                lobes.append((end,(rng.uniform(.65,.95),rng.uniform(.55,.85),rng.uniform(.5,.75))))
        lobes.append((Vector((-.3,.2,6)),(.8,.8,.7)))
    else:
        branch([(0,0,0),(.06,.02,2.4),(-.1,.1,5),(.1,.15,7.3),(-.16,.23,9.5),(.04,.3,11.6)],.31)
        for i in range(27):
            z=3+i*.30+rng.uniform(-.15,.15)
            angle=i*2.39996+rng.uniform(-.3,.3)
            reach=(2.35 if z<8.2 else (11.9-z)*.64)*rng.uniform(.65,1.1)
            tip=Vector((math.cos(angle)*reach, math.sin(angle)*reach,z+.18))
            mid=Vector((tip.x*.55,tip.y*.55,z-.22))
            branch([(0,.1,z),tuple(mid),tuple(tip)],.08*(1-(z-3)/12))
            if i<5: continue  # bare lower branches, open trunk
            for j in range(3):
                az=angle+(j-1)*.7
                end=tip+Vector((math.cos(az)*.4,math.sin(az)*.4,.15+j*.09))
                branch([tuple(mid),tuple(end)],.024)
                lobes.append((end,(.68,.53,.26)))
        lobes.append((Vector((.04,.3,11.4)),(.45,.43,.58)))
    for i in range(5):
        angle=i*math.tau/5
        branch([(math.cos(angle)*.7,math.sin(angle)*.7,.015),(0,0,.24)],.11)

    verts=[]; faces=[]; normals=[]; uvs=[]; colors=[]
    for center, radii in lobes:
        # Retained editable shading envelopes. Export only branch/leaf meshes.
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, location=center)
        helper=bpy.context.object; helper.name='CrownGuide'; helper.scale=radii
        helper.hide_render=True; helper.hide_set(True)
        for j in range(58 if kind=='broadleaf' else 38):
            direction=Vector((rng.gauss(0,1),rng.gauss(0,1),rng.gauss(0,1))).normalized()
            depth=rng.uniform(.35,1)**(1/3)
            offset=Vector(tuple(direction[k]*radii[k]*depth for k in range(3)))
            p=center+offset
            # Analytic ellipsoid normal transfer, independent of leaf plane normal.
            normal=Vector(tuple(offset[k]/radii[k]**2 for k in range(3))).normalized()
            angle=rng.random()*math.tau
            tangent=Vector((math.cos(angle),math.sin(angle),rng.uniform(-.3,.3))).normalized()
            up=Vector((-math.sin(angle)*.45,math.cos(angle)*.45,rng.uniform(.6,1))).normalized()
            size=rng.uniform(.33,.55) if kind=='broadleaf' else rng.uniform(.38,.62)
            base=len(verts)
            ao=.65+.35*depth
            for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]:
                verts.append(p+(tangent*x+up*y)*size)
                normals.append(tuple(normal)); uvs.append(((x+1)/2,(y+1)/2))
                colors.append((ao, rng.uniform(.9,1) if x==-1 and y==-1 else .95, min(p.z/12,1),1))
            faces.append((base,base+1,base+2,base+3))
    mesh=bpy.data.meshes.new('LeafSpraysMesh'); mesh.from_pydata(verts,[],faces); mesh.update()
    uv=mesh.uv_layers.new(name='UVMap')
    attr=mesh.color_attributes.new(name='ShadeWeights',type='FLOAT_COLOR',domain='POINT')
    for i,c in enumerate(colors): attr.data[i].color=c
    for poly in mesh.polygons:
        poly.use_smooth=True
        for index in poly.loop_indices: uv.data[index].uv=uvs[mesh.loops[index].vertex_index]
    mesh.normals_split_custom_set_from_vertices(normals)
    obj=bpy.data.objects.new('Leaves',mesh);scene.collection.objects.link(obj);mesh.materials.append(foliage)
    for item in bpy.context.selected_objects:item.select_set(False)
    for item in branches:item.select_set(True)
    bpy.context.view_layer.objects.active=branches[0]
    bpy.ops.object.join(); bpy.context.object.name='Branches'
    obj.select_set(True)
    # Export only this scene: otherwise selected objects from other scenes leak in.
    export=bpy.ops.export_scene.gltf
    # GLB verified through runtime RNA enum validation on Blender 5.2.
    export(filepath=str(OUT/(kind+'.glb')),use_selection=True,use_active_scene=True,export_yup=True,export_format='GLB')
    (OUT/(kind+'_plan.json')).write_text(json.dumps({'kind':kind,'paths':paths,'lobes':[{'center':list(c),'radii':r} for c,r in lobes]},indent=2),encoding='utf-8')
    stats = {'sprays':len(faces),'leaf_triangles':len(faces)*2,'branch_triangles':sum(len(p.vertices)-2 for p in bpy.context.object.data.polygons)}
    # Blender source preview: Diffuse -> ShaderToRGB -> palette, alpha + AO.
    # Build AFTER export: glTF carries geometry/weights; Godot implements its own shader.
    for mat, palette in [(foliage,[(.035,.10,.055,1),(.19,.37,.08,1),(.56,.72,.22,1)]),
                         (bark,[(.045,.025,.015,1),(.15,.08,.035,1),(.36,.23,.10,1)])]:
        nodes=mat.node_tree.nodes; links=mat.node_tree.links; nodes.clear()
        diffuse=nodes.new('ShaderNodeBsdfDiffuse')
        rgb=nodes.new('ShaderNodeShaderToRGB'); links.new(diffuse.outputs[0],rgb.inputs[0])
        ramp=nodes.new('ShaderNodeValToRGB');links.new(rgb.outputs[0],ramp.inputs[0])
        ramp.color_ramp.elements[0].position=.15; ramp.color_ramp.elements[0].color=palette[0]
        ramp.color_ramp.elements[1].position=.78; ramp.color_ramp.elements[1].color=palette[2]
        ramp.color_ramp.elements.new(.45).color=palette[1]
        ao=nodes.new('ShaderNodeAmbientOcclusion');ao.inputs['Distance'].default_value=.65
        multiply=nodes.new('ShaderNodeVectorMath');multiply.operation='MULTIPLY'
        links.new(ramp.outputs['Color'],multiply.inputs[0]);links.new(ao.outputs['Color'],multiply.inputs[1])
        emission=nodes.new('ShaderNodeEmission');links.new(multiply.outputs[0],emission.inputs[0])
        outnode=nodes.new('ShaderNodeOutputMaterial')
        if mat==foliage:
            tex=nodes.new('ShaderNodeTexImage');tex.image=foliage_image
            transparent=nodes.new('ShaderNodeBsdfTransparent');mix=nodes.new('ShaderNodeMixShader')
            links.new(tex.outputs['Alpha'],mix.inputs[0]);links.new(transparent.outputs[0],mix.inputs[1]);links.new(emission.outputs[0],mix.inputs[2])
            links.new(mix.outputs[0],outnode.inputs[0])
        else: links.new(emission.outputs[0],outnode.inputs[0])
    sun=bpy.data.lights.new('StudySun','SUN');sun.energy=2.0
    sunobj=bpy.data.objects.new('StudySun',sun);scene.collection.objects.link(sunobj)
    sunobj.rotation_euler=(.65,-.5,-.65)
    camera=bpy.data.cameras.new('StudyCamera');camera.type='ORTHO';camera.ortho_scale=15
    camobj=bpy.data.objects.new('StudyCamera',camera);scene.collection.objects.link(camobj)
    camobj.location=(10,-18,12);camobj.rotation_euler=(Vector((0,0,5))-camobj.location).to_track_quat('-Z','Y').to_euler()
    scene.camera=camobj
    scene.world=bpy.data.worlds.new('StudyWorld');scene.world.color=(.05,.05,.05)
    return scene, stats


previous=bpy.context.window.scene
scenes=[];stats={}
for kind in ['broadleaf','pine']:
    scene,stat=build(kind);scenes.append(scene);stats[kind]=stat
bpy.data.libraries.write(str(ROOT/'art_source/foliage_study.blend'),set(scenes))
bpy.context.window.scene=previous
(OUT/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
print(json.dumps(stats))

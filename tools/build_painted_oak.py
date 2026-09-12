"""Run in Blender. Creates a separate scene and exports only the prototype tree."""
import bpy, math, random
from mathutils import Vector
from pathlib import Path

root = Path(r'C:/Users/jonny/Desktop/game/top-down-rpg')
out = root / 'assets/models/painted_oak'
out.mkdir(parents=True, exist_ok=True)
scene = bpy.data.scenes.new('PaintedOakPrototype')
previous = bpy.context.window.scene
bpy.context.window.scene = scene
rng = random.Random(9182)

leaves = bpy.data.materials.new('OakPaintedLeaves')
leaves.use_nodes = True
nodes = leaves.node_tree.nodes
bsdf = nodes.get('Principled BSDF')
bsdf.inputs['Roughness'].default_value = 1
image = bpy.data.images.load(str(root/'assets/textures/hearth_painted/canopy_painting.png'), check_existing=True)
tex = nodes.new('ShaderNodeTexImage')
tex.image = image
leaves.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
leaves.node_tree.links.new(tex.outputs['Alpha'],bsdf.inputs['Alpha'])
leaves.diffuse_color = (0.25,0.35,0.12,1)
leaves.use_backface_culling = False
if hasattr(leaves,'surface_render_method'): leaves.surface_render_method = 'DITHERED'

wood = bpy.data.materials.new('OakBark')
wood.diffuse_color = (0.16,0.095,0.047,1)
wood.use_nodes = True
wood.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = wood.diffuse_color
wood.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 1

def branch(start,end,r1,r2):
    a,b = Vector(start),Vector(end)
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=r1, radius2=r2, depth=(b-a).length, location=(a+b)/2)
    obj=bpy.context.object
    obj.name='OakBranch'
    obj.rotation_mode='QUATERNION'
    obj.rotation_quaternion=(b-a).to_track_quat('Z','Y')
    obj.data.materials.append(wood)

branch((0,0,0),(-0.12,0.06,1.1),0.38,0.28)
branch((-0.12,0.06,1.1),(0.16,0,2.4),0.28,0.19)
branch((0.16,0,2.4),(-0.22,0.18,4.7),0.19,0.05)
for i in range(5):
    angle=i*math.tau/5
    branch((0,0,0.25),(math.cos(angle)*0.65,math.sin(angle)*0.65,0.04),0.12,0.035)

verts=[]; faces=[]; uvs=[]; normals=[]
clusters=[(Vector((-0.25,0.15,5.1)),0.95,0.0)]
for i in range(7):
    angle=i*2.39996
    reach=rng.uniform(1.0,1.7)
    c=Vector((math.cos(angle)*reach,math.sin(angle)*reach,3.3+i*.2+rng.uniform(-.25,.25)))
    joint=Vector((c.x*.45,c.y*.45,2.4+i*.16))
    branch((0.1,0,1.8+i*.17),joint,.14,.08)
    branch(joint,c,.08,.025)
    for j in range(3):
        direction=angle+(j-1)*.85
        tip=c+Vector((math.cos(direction)*.48,math.sin(direction)*.48,rng.uniform(-.15,.35)))
        branch(c,tip,.035,.008)
        clusters.append((tip,rng.uniform(.8,1.1),direction))

# Individual lobed leaf silhouettes form flattened, branching sprays, not shells.
outline=[(0,-.6),(-.28,-.35),(-.18,-.22),(-.46,-.10),(-.29,.02),(-.42,.23),(-.18,.32),(0,.62),(.20,.32),(.40,.22),(.28,.02),(.43,-.12),(.19,-.25),(.27,-.36)]
for center,radius,heading in clusters:
    for j in range(95):
        az=rng.random()*math.tau
        rad=math.sqrt(rng.random())*radius
        offset=Vector((math.cos(az)*rad,math.sin(az)*rad*.8,rng.uniform(-.25,.25)-rad*.12))
        p=center+offset
        angle=heading+rng.uniform(-1.7,1.7)
        length=rng.uniform(.25,.43)
        tangent=Vector((math.cos(angle),math.sin(angle),rng.uniform(-.2,.2))).normalized()
        up=Vector((-math.sin(angle),math.cos(angle),rng.uniform(-.7,.7))).normalized()
        normal=tangent.cross(up).normalized()
        if normal.z<0: normal=-normal
        shade_normal=(Vector((offset.x*.25,offset.y*.25,.9))+normal*.3).normalized()
        base=len(verts)
        # Small interior UV patches: never repeat the entire painted crown.
        uvcenter=Vector((rng.uniform(.32,.62),rng.uniform(.40,.65)))
        verts.append(p+normal*.018)
        uvs.append(tuple(uvcenter))
        normals.append(tuple(shade_normal))
        for x,y in outline:
            verts.append(p+(tangent*x+up*y)*length)
            uvs.append(tuple(uvcenter+Vector((x,y))*.045))
            normals.append(tuple(shade_normal))
        for k in range(len(outline)):
            faces.append((base,base+1+(k+1)%len(outline),base+1+k))

mesh=bpy.data.meshes.new('OakTuftsMesh')
mesh.from_pydata(verts,[],faces)
mesh.update()
uv=mesh.uv_layers.new(name='UVMap')
for poly in mesh.polygons:
    poly.use_smooth=True
    for index in poly.loop_indices: uv.data[index].uv=uvs[mesh.loops[index].vertex_index]
mesh.normals_split_custom_set_from_vertices(normals)
old=bpy.data.objects.get('OakLeafSprays')
if old: old.name='OakLeafSpraysPrevious'
obj=bpy.data.objects.new('OakLeafSprays',mesh)
scene.collection.objects.link(obj)
mesh.materials.append(leaves)
for obj in scene.objects: obj.select_set(True)
bpy.context.view_layer.objects.active=obj
bpy.ops.export_scene.gltf(filepath=str(out/'painted_oak.glb'),use_selection=True,use_active_scene=True,export_format='GLB',export_yup=True)
(root/'art_source').mkdir(exist_ok=True)
bpy.data.libraries.write(str(root/'art_source/painted_oak.blend'),{scene})
bpy.context.window.scene=previous
print('PAINTED_OAK_EXPORTED',len(verts),len(faces),'foliage triangles')

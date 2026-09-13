"""Round brilliant cut gem from real proportions, flat facets.
blender -b --factory-startup -P gem.py -- <outdir>"""
import bpy, bmesh, math, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.getcwd()
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# proportions of a standard round brilliant, girdle radius 1
TABLE = 0.57          # table width as a fraction of the diameter
CROWN = math.radians(34.5)
PAVILION = math.radians(40.75)
GIRDLE = 0.02         # half thickness
crown_h = (1 - TABLE) * math.tan(CROWN)
pav_d = math.tan(PAVILION)


def ring(n, r, z, rot=0.0):
    return [Vector((r * math.cos(rot + 2 * math.pi * i / n), r * math.sin(rot + 2 * math.pi * i / n), z)) for i in range(n)]


pts = []
pts += ring(8, TABLE, GIRDLE + crown_h)                                   # table
pts += ring(8, 0.5 * (1 + TABLE) + 0.04, GIRDLE + crown_h * 0.45, math.pi / 8)  # star facet points
pts += ring(16, 1.0, GIRDLE, math.pi / 16)                               # girdle top
pts += ring(16, 1.0, -GIRDLE, math.pi / 16)                              # girdle bottom
pts += ring(8, 0.52, -GIRDLE - pav_d * 0.47)                             # pavilion mains, pushed out a touch
pts.append(Vector((0, 0, -GIRDLE - pav_d)))                              # culet

bm = bmesh.new()
verts = [bm.verts.new(p) for p in pts]
bmesh.ops.convex_hull(bm, input=verts)
# merge the triangles the hull makes into proper flat facets
bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=bm.verts, edges=bm.edges)
mesh = bpy.data.meshes.new("gem")
bm.to_mesh(mesh)
bm.free()
gem = bpy.data.objects.new("gem", mesh)
scene.collection.objects.link(gem)
for p in mesh.polygons:
    p.use_smooth = False
print("gem facets", len(mesh.polygons), "verts", len(mesh.vertices))

mat = bpy.data.materials.new("amethyst")
mat.use_nodes = True
b = mat.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.42, 0.12, 0.85, 1)
b.inputs["Roughness"].default_value = 0.0
b.inputs["IOR"].default_value = 1.54
b.inputs["Transmission Weight"].default_value = 1.0
mesh.materials.append(mat)

bpy.ops.object.select_all(action="DESELECT")
gem.select_set(True)
bpy.context.view_layer.objects.active = gem
fbx = os.path.join(OUT, "gem.fbx")
bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_scale_options="FBX_SCALE_ALL", mesh_smooth_type="FACE")
print("exported", fbx)

# preview
gem.rotation_euler = (math.radians(-15), 0, 0)
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, -GIRDLE - pav_d - 0.01))
g = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.25, 0.27, 1)
g.data.materials.append(gm)
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(40), math.radians(15), math.radians(30)))
bpy.context.active_object.data.energy = 5
bpy.ops.object.light_add(type="AREA", location=(-2, 2, 3))
bpy.context.active_object.data.energy = 300
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.55, 0.65, 1)
scene.world = world
bpy.ops.object.camera_add(location=(0, -3.8, 2.2))
cam = bpy.context.active_object
cam.constraints.new("TRACK_TO").target = gem
scene.camera = cam
scene.render.engine = "CYCLES"
scene.cycles.samples = 96
scene.render.resolution_x, scene.render.resolution_y = 640, 480
scene.render.filepath = os.path.join(OUT, "gem_preview.png")
bpy.ops.render.render(write_still=True)
print("preview", scene.render.filepath)

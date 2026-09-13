"""Turns the Poly Haven boulder_01 scan (CC0) into the collect-burst ore rock.
blender -b --factory-startup -P process_scan.py -- <scan fbx> <outdir> <gem fbx>
- the 16.5k tri LOD is the rock, it keeps its real scanned textures (downsized to 1024 png for roblox)
- the 8.2k tri LOD is the rubble piece
- amethyst clusters from crystals.py grow out of the rock's upward faces
- everything plus the gem goes into one FBX: Rock, Crystals, Chunk1, Gem"""
import bpy, math, random, sys, os
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import crystals as cx

argv = sys.argv[sys.argv.index("--") + 1:]
SCAN, OUT, GEM = argv[0], argv[1], argv[2]
os.makedirs(OUT, exist_ok=True)
TEX = 1024
rng = random.Random(5)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.fbx(filepath=SCAN)
lods = {o.name: o for o in bpy.data.objects if o.type == "MESH"}
rock = next(o for n, o in lods.items() if n.endswith("LOD2"))
chunk = next(o for n, o in lods.items() if n.endswith("LOD3"))
for n, o in list(lods.items()):
    if o not in (rock, chunk):
        bpy.data.objects.remove(o)
for o in list(bpy.data.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o)


def settle(o, name):
    """apply transforms, centre it and put its bottom on z=0 so it pivots upright at its middle"""
    o.name = name
    o.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    shift = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
    for v in o.data.vertices:
        v.co -= shift
    o.location = (0, 0, 0)


settle(rock, "Rock")
settle(chunk, "Chunk1")
chunk.location.x = 4

# ---- textures: roblox caps images at 1024 and won't take exr, so resave the scan maps as 1024 png
mat = rock.data.materials[0]
tex_nodes = {n.image.name: n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}
for name, node in tex_nodes.items():
    img = node.image
    kind = "color" if "diff" in name else "normal" if "nor" in name else "roughness" if "rough" in name else None
    if not kind:
        continue
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
    path = os.path.join(OUT, f"rock_{kind}.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    node.image = bpy.data.images.load(path)
    node.image.colorspace_settings.name = "sRGB" if kind == "color" else "Non-Color"
    print("texture", kind, path)
mat.name = "Rock"
chunk.data.materials.clear()
chunk.data.materials.append(mat)

# ---- amethyst clusters growing out of the rock's upward faces
inv = rock.matrix_world.inverted()
xs = [v.co.x for v in rock.data.vertices]
ys = [v.co.y for v in rock.data.vertices]
height = max(v.co.z for v in rock.data.vertices)
clusters = []
tries = 0
while len(clusters) < 3 and tries < 400:
    tries += 1
    px = rng.uniform(min(xs), max(xs)) * 0.7
    py = rng.uniform(min(ys), max(ys)) * 0.7
    ok, loc, nrm, _ = rock.ray_cast(inv @ Vector((px, py, height + 2)), Vector((0, 0, -1)))
    if not ok or nrm.z < 0.6:
        continue
    if any((loc - c[0]).length < height * 0.45 for c in clusters):
        continue
    clusters.append((loc, nrm))

parts = []
for i, (loc, nrm) in enumerate(clusters):
    size = height * (0.55 if i == 0 else rng.uniform(0.3, 0.42))
    c = cx.build_cluster(f"cluster{i}", 11 + i, count=7 if i == 0 else 5, druse=14 if i == 0 else 9, scale=size)
    up = (nrm + Vector((0, 0, 1))).normalized()
    c.rotation_mode = "QUATERNION"
    c.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(up)
    c.location = loc - up * size * 0.04
    parts.append(c)
bpy.ops.object.select_all(action="DESELECT")
for c in parts:
    c.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.join()
crystal = bpy.context.active_object
crystal.name = "Crystals"
crystal.data.name = "Crystals"
crystal.data.materials.clear()
crystal.data.materials.append(cx.crystal_material("Crystals_proc"))
cx.bake_to_textures(crystal, OUT, tex=1024)
print("crystal clusters", len(clusters), "tris", sum(len(p.vertices) - 2 for p in crystal.data.polygons))

# ---- gem
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=GEM)
gem = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
gem.name = "Gem"
gem.data.name = "Gem"
gem.location = (8, 0, 0)

for o in (rock, chunk, crystal, gem):
    print("TRIS", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons))

# ---- export
bpy.ops.object.select_all(action="DESELECT")
for o in (rock, chunk, crystal, gem):
    o.select_set(True)
fbx = os.path.join(OUT, "collect_burst_assets.fbx")
bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_scale_options="FBX_SCALE_ALL", mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True)
print("exported", fbx)

# ---- preview: rock with its crystals, lit like a sunny day
chunk.hide_render = True
gem.hide_render = True
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
g = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.3, 0.31, 1)
g.data.materials.append(gm)
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(48), math.radians(12), math.radians(35)))
bpy.context.active_object.data.energy = 4.5
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.58, 0.72, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
scene.world = world
bpy.ops.object.camera_add(location=(2.6, -3.0, 1.9))
cam = bpy.context.active_object
cam.data.lens = 45
t = bpy.data.objects.new("t", None)
t.location = (0, 0, height * 0.55)
scene.collection.objects.link(t)
cam.constraints.new("TRACK_TO").target = t
scene.camera = cam
scene.render.engine = "CYCLES"
scene.cycles.samples = 64
scene.render.resolution_x, scene.render.resolution_y = 960, 720
scene.render.filepath = os.path.join(OUT, "scan_rock_preview.png")
bpy.ops.render.render(write_still=True)
print("preview", scene.render.filepath)

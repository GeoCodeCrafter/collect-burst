"""Boulder scan -> the game rock at four times the texture detail, plus ten variants for a level.
blender -b --factory-startup -P process_scan4.py -- <scan fbx> <outdir> <gem fbx>

Roblox caps a texture at 1024px, which stretched over a 9 stud rock looked low res. So the 16.5k tri LOD is
cut into four quarters and each gets its own 1024 bake (colour, normal, roughness) from the 66k tri LOD and
the scan's own 2k maps. The variants bend that geometry with smooth noise and stretch it. They keep the UVs,
so all eleven rocks share the same four texture sets. Each rock grows its own amethyst.

Exports one FBX: RockA-D + Crystals, V01..V10 (_RockA-D + _Crystals), Chunk1, Gem."""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, noise

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import crystals as cx

argv = sys.argv[sys.argv.index("--") + 1:]
SCAN, OUT, GEM = argv[0], argv[1], argv[2]
os.makedirs(OUT, exist_ok=True)
TEX = 1024
VARIANTS = 10
rng = random.Random(5)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
bpy.ops.import_scene.fbx(filepath=SCAN)
lods = {o.name: o for o in bpy.data.objects if o.type == "MESH"}
high = next(o for n, o in lods.items() if n.endswith("LOD0"))
game = next(o for n, o in lods.items() if n.endswith("LOD2"))
chunk = next(o for n, o in lods.items() if n.endswith("LOD3"))
for o in list(bpy.data.objects):
    if o not in (high, game, chunk):
        bpy.data.objects.remove(o)


def select_only(*objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[-1]


# same transform for every LOD so the high one lines up with the game one for baking
select_only(high, game, chunk)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
xs = [v.co.x for v in game.data.vertices]
ys = [v.co.y for v in game.data.vertices]
zs = [v.co.z for v in game.data.vertices]
SHIFT = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
for o in (high, game, chunk):
    for v in o.data.vertices:
        v.co -= SHIFT
HEIGHT = max(zs) - min(zs)
high.name = "high"
chunk.name = "Chunk1"
chunk.data.name = "Chunk1"
chunk.location.x = -6

# ---- the rubble keeps the scan's own maps, resaved at 1024 png
scan_mat = game.data.materials[0]
for node in [n for n in scan_mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]:
    name = node.image.name
    kind = "color" if "diff" in name else "normal" if "nor" in name else "roughness" if "rough" in name else None
    if not kind:
        continue
    img = node.image.copy()
    img.scale(TEX, TEX)
    ext, fmt = ("png", "PNG") if kind == "normal" else ("jpg", "JPEG")
    path = os.path.join(OUT, f"chunk_{kind}.{ext}")
    img.filepath_raw = path
    img.file_format = fmt
    img.save()
chunk_mat = scan_mat.copy()
chunk_mat.name = "Chunk"
for node in [n for n in chunk_mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]:
    name = node.image.name
    kind = "color" if "diff" in name else "normal" if "nor" in name else "roughness" if "rough" in name else None
    if kind:
        node.image = bpy.data.images.load(os.path.join(OUT, f"chunk_{kind}.{'png' if kind == 'normal' else 'jpg'}"))
        node.image.colorspace_settings.name = "sRGB" if kind == "color" else "Non-Color"
chunk.data.materials.clear()
chunk.data.materials.append(chunk_mat)


# ---- cut the game LOD into four quarters, each unwrapped to fill its own texture
def quarter(src, sx, sy, name):
    me = src.data.copy()
    bm = bmesh.new()
    bm.from_mesh(me)
    kill = [f for f in bm.faces if not (sx * f.calc_center_median().x >= 0 and sy * f.calc_center_median().y >= 0)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.name = name
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    return o


pieces = [quarter(game, sx, sy, "Rock" + letter) for letter, (sx, sy) in zip("ABCD", ((1, 1), (-1, 1), (-1, -1), (1, -1)))]
for p in pieces:
    p.data.materials.clear()
    select_only(p)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()

# ---- bake each quarter from the 66k LOD and its scanned maps
maps = {}
for p in pieces:
    mat = bpy.data.materials.new(p.name)
    mat.use_nodes = True
    p.data.materials.append(mat)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    imgs = {}
    for kind, bake_type, cs in (("color", "DIFFUSE", "sRGB"), ("normal", "NORMAL", "Non-Color"), ("roughness", "ROUGHNESS", "Non-Color")):
        img = bpy.data.images.new(f"{p.name}_{kind}", TEX, TEX)
        img.colorspace_settings.name = cs
        node = nodes.new("ShaderNodeTexImage")
        node.image = img
        nodes.active = node
        select_only(high, p)
        kw = dict(type=bake_type, use_selected_to_active=True, cage_extrusion=0.02, max_ray_distance=0.06, margin=6)
        if bake_type == "DIFFUSE":
            kw["pass_filter"] = {"COLOR"}
        bpy.ops.object.bake(**kw)
        # colour and roughness as jpg to keep the fbx small. normals stay png, jpg blocks show up as bumps
        ext, fmt = ("png", "PNG") if kind == "normal" else ("jpg", "JPEG")
        path = os.path.join(OUT, f"{p.name}_{kind}.{ext}")
        img.filepath_raw = path
        img.file_format = fmt
        scene.render.image_settings.quality = 92
        img.save()
        imgs[kind] = node
    bsdf = nodes["Principled BSDF"]
    links.new(imgs["color"].outputs["Color"], bsdf.inputs["Base Color"])
    links.new(imgs["roughness"].outputs["Color"], bsdf.inputs["Roughness"])
    nm = nodes.new("ShaderNodeNormalMap")
    links.new(imgs["normal"].outputs["Color"], nm.inputs["Color"])
    links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    maps[p.name] = mat
    print("baked", p.name)
bpy.data.objects.remove(high)
bpy.data.objects.remove(game)


# ---- amethyst: clusters on upward faces of whichever rock pieces are passed in
def grow_crystals(parts, name, seed, count):
    r = random.Random(seed)
    top = max(max(v.co.z for v in p.data.vertices) for p in parts)
    lo_x = min(min(v.co.x for v in p.data.vertices) for p in parts)
    hi_x = max(max(v.co.x for v in p.data.vertices) for p in parts)
    lo_y = min(min(v.co.y for v in p.data.vertices) for p in parts)
    hi_y = max(max(v.co.y for v in p.data.vertices) for p in parts)
    spots = []
    for _ in range(500):
        if len(spots) >= count:
            break
        px = r.uniform(lo_x, hi_x) * 0.7
        py = r.uniform(lo_y, hi_y) * 0.7
        best = None
        for p in parts:
            ok, loc, nrm, _ = p.ray_cast(Vector((px, py, top + 2)), Vector((0, 0, -1)))
            if ok and (best is None or loc.z > best[0].z):
                best = (loc, nrm)
        if not best or best[1].z < 0.6:
            continue
        if any((best[0] - s[0]).length < top * 0.45 for s in spots):
            continue
        spots.append(best)
    made = []
    for i, (loc, nrm) in enumerate(spots):
        size = top * (0.55 if i == 0 else r.uniform(0.3, 0.42))
        c = cx.build_cluster(f"{name}_c{i}", seed * 10 + i, count=7 if i == 0 else 5, druse=14 if i == 0 else 9, scale=size)
        up = (nrm + Vector((0, 0, 1))).normalized()
        c.rotation_mode = "QUATERNION"
        c.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(up)
        c.location = loc - up * size * 0.04
        made.append(c)
    select_only(*made)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    crystal = bpy.context.active_object
    crystal.name = name
    crystal.data.name = name
    crystal.data.materials.clear()
    crystal.data.materials.append(cx.crystal_material(name + "_proc"))
    cx.bake_to_textures(crystal, OUT, tex=TEX)
    return crystal


main_crystals = grow_crystals(pieces, "Crystals", 11, 3)
exported = pieces + [main_crystals, chunk]
print("main rock: 4 pieces +", len(main_crystals.data.polygons), "crystal faces")


# ---- ten variants: the same four pieces bent by smooth noise and stretched, same UVs and textures
def bend(co, off, stretch, amount):
    n = noise.noise_vector(co * 1.1 + off)
    p = co + n * amount
    return Vector((p.x * stretch.x, p.y * stretch.y, p.z * stretch.z))


for v in range(1, VARIANTS + 1):
    r = random.Random(100 + v)
    off = Vector((r.uniform(-50, 50), r.uniform(-50, 50), r.uniform(-50, 50)))
    stretch = Vector((r.uniform(0.75, 1.3), r.uniform(0.75, 1.3), r.uniform(0.7, 1.35)))
    amount = HEIGHT * r.uniform(0.12, 0.22)
    tag = f"V{v:02d}"
    vparts = []
    for p in pieces:
        me = p.data.copy()
        for vert in me.vertices:
            vert.co = bend(vert.co, off, stretch, amount)
        o = bpy.data.objects.new(f"{tag}_{p.name}", me)
        me.name = o.name
        scene.collection.objects.link(o)
        vparts.append(o)
    # back on the ground after bending
    low = min(min(vt.co.z for vt in o.data.vertices) for o in vparts)
    for o in vparts:
        for vt in o.data.vertices:
            vt.co.z -= low
        o.data.update()
    crystals = grow_crystals(vparts, f"{tag}_Crystals", 200 + v, r.randint(1, 3))
    for o in vparts + [crystals]:
        o.location.x += 5 * v
    exported += vparts + [crystals]
    print("variant", tag, "stretch", tuple(round(s, 2) for s in stretch))

# ---- gem
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=GEM)
gem = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
gem.name = "Gem"
gem.data.name = "Gem"
gem.location = (-10, 0, 0)
exported.append(gem)

total = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in exported)
for o in pieces:
    print("TRIS", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons))
print("TOTAL TRIS", total, "objects", len(exported))

select_only(*exported)
fbx = os.path.join(OUT, "collect_burst_assets.fbx")
bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_scale_options="FBX_SCALE_ALL", mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True)
print("exported", fbx)

# ---- previews: the main rock close up, and the variants in a row
bpy.ops.mesh.primitive_plane_add(size=200, location=(20, 0, 0))
g = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.1, 0.09, 0.09, 1)
g.data.materials.append(gm)
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(30)))
bpy.context.active_object.data.energy = 4
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.3, 0.32, 0.4, 1)
scene.world = world
scene.cycles.samples = 48
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
for label, loc, target, lens in (
    ("close", (1.6, -1.8, 1.3), (0, 0, HEIGHT * 0.5), 50),
    ("variants", (30, -34, 14), (30, 0, 0.5), 50),
):
    cam.location = loc
    cam_data.lens = lens
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, f"preview_{label}.png")
    bpy.ops.render.render(write_still=True)
    print("preview", scene.render.filepath)

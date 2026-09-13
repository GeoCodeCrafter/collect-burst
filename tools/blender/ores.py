"""Ore that sits in the rocks: coal, iron, gold and diamond, three cluster shapes each.
blender -b --factory-startup -P ores.py -- <outdir>

A cluster is a handful of pieces about a stud across, built to sit half sunk into a rock. Coal and iron are
fractured lumps, gold is rounded pitted nuggets, diamond is rough octahedral stones (the shape they grow in).
Each gets a procedural material baked to colour, roughness and metalness so roblox gets real metal on the
gold and iron. Exports ores.fbx with Coal1-3, Iron1-3, Gold1-3, Diamond1-3."""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.getcwd()
os.makedirs(OUT, exist_ok=True)
TEX = 512
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16


def rand_dir(rng):
    while True:
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        if v.length > 1e-3:
            return v.normalized()


def lump(bm, center, radius, rng, fractured, squash):
    """one piece: an icosphere pushed out by noise. fractured ones get clipped by planes for flat broken faces"""
    ret = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    # lots of deep cuts and little noise for coal and iron, so they come out angular and broken rather
    # than as soft lumps. the first go had 10 shallow cuts over heavy noise and read as play dough
    planes = [(rand_dir(rng), rng.uniform(0.58, 0.86)) for _ in range(16)] if fractured else []
    for v in ret["verts"]:
        d = v.co.normalized()
        r = 1 + (0.08 if fractured else 0.22) * noise.fractal(d * 1.4 + off, 0.7, 2.0, 3)
        for n, o in planes:
            c = d.dot(n)
            if c > 1e-3:
                r = min(r, o / c)
        r += (0.02 if fractured else 0.05) * noise.fractal(d * 6 + off, 0.8, 2.0, 3)
        p = d * r * radius
        v.co = center + Vector((p.x, p.y, p.z * squash))


def octahedron(bm, center, radius, rng):
    """a rough diamond: an octahedron, a touch stretched and tilted"""
    stretch = rng.uniform(1.0, 1.25)
    pts = [Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 1, 0)), Vector((0, -1, 0)), Vector((0, 0, stretch)), Vector((0, 0, -stretch))]
    tilt = rand_dir(rng) * 0.35 + Vector((0, 0, 1))
    rot = Vector((0, 0, 1)).rotation_difference(tilt.normalized())
    vs = [bm.verts.new(center + rot @ (p * radius)) for p in pts]
    for a, b, c in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
        bm.faces.new((vs[a], vs[b], vs[c]))


def cluster(name, kind, seed):
    rng = random.Random(seed)
    bm = bmesh.new()
    n = rng.randint(5, 7) if kind in ("coal", "iron") else rng.randint(4, 6)
    for i in range(n):
        main = i == 0
        radius = rng.uniform(0.32, 0.4) if main else rng.uniform(0.14, 0.26)
        ang = rng.uniform(0, math.tau)
        # spread out enough that they read as separate chunks, not one merged lump
        dist = 0 if main else rng.uniform(0.3, 0.55)
        center = Vector((math.cos(ang) * dist, math.sin(ang) * dist, radius * rng.uniform(0.2, 0.5)))
        if kind == "diamond":
            octahedron(bm, center, radius * 0.9, rng)
        else:
            lump(bm, center, radius, rng, fractured=kind in ("coal", "iron"), squash=0.75 if kind == "gold" else 0.9)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if kind == "diamond":
        sharp = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(30)]
        bmesh.ops.bevel(bm, geom=sharp, offset=0.008, segments=1, affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # only gold is smooth. iron ore breaks into flat faces like coal
    smooth = kind == "gold"
    for p in me.polygons:
        p.use_smooth = smooth
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    return obj


def material(kind):
    """procedural material. returns it plus the node output that holds metalness, for baking"""
    mat = bpy.data.materials.new(kind)
    mat.use_nodes = True
    N, L = mat.node_tree.nodes, mat.node_tree.links
    bsdf = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 9
    nz.inputs["Detail"].default_value = 10
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    metal = N.new("ShaderNodeValue")

    def ramp(a, b, pa=0.35, pb=0.7):
        r = N.new("ShaderNodeValToRGB")
        r.color_ramp.elements[0].position, r.color_ramp.elements[0].color = pa, a
        r.color_ramp.elements[1].position, r.color_ramp.elements[1].color = pb, b
        L.new(nz.outputs["Fac"], r.inputs["Fac"])
        return r

    def rough(lo, hi):
        m = N.new("ShaderNodeMapRange")
        m.inputs["To Min"].default_value = lo
        m.inputs["To Max"].default_value = hi
        L.new(nz.outputs["Fac"], m.inputs["Value"])
        L.new(m.outputs["Result"], bsdf.inputs["Roughness"])

    if kind == "coal":
        L.new(ramp((0.008, 0.008, 0.01, 1), (0.035, 0.035, 0.04, 1)).outputs["Color"], bsdf.inputs["Base Color"])
        # coal (anthracite) has glossy broken faces with a slight metallic sheen next to dull ones
        rough(0.15, 0.55)
        metal.outputs[0].default_value = 0.3
    elif kind == "iron":
        # dark metallic ore with rust bleeding through
        rust = N.new("ShaderNodeTexNoise")
        rust.inputs["Scale"].default_value = 3
        rust.inputs["Detail"].default_value = 6
        L.new(tc.outputs["Object"], rust.inputs["Vector"])
        mask = N.new("ShaderNodeValToRGB")
        mask.color_ramp.elements[0].position = 0.45
        mask.color_ramp.elements[1].position = 0.62
        L.new(rust.outputs["Fac"], mask.inputs["Fac"])
        mix = N.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        L.new(mask.outputs["Color"], mix.inputs["Factor"])
        # blender colours are linear: these are a dark metallic grey and a deep red-brown rust. the first
        # go used 0.42 for the rust, which is a light peach once it's on screen
        L.new(ramp((0.03, 0.03, 0.032, 1), (0.075, 0.072, 0.07, 1)).outputs["Color"], mix.inputs["A"])
        mix.inputs["B"].default_value = (0.13, 0.035, 0.012, 1)
        L.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        rough(0.45, 0.85)
        inv = N.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 0.7
        L.new(mask.outputs["Color"], inv.inputs[1])
        metal = inv
    elif kind == "gold":
        # bright metallic gold with darker pits, the way real nuggets look
        pits = N.new("ShaderNodeTexVoronoi")
        pits.inputs["Scale"].default_value = 14
        L.new(tc.outputs["Object"], pits.inputs["Vector"])
        pr = N.new("ShaderNodeValToRGB")
        pr.color_ramp.elements[0].position, pr.color_ramp.elements[0].color = 0.05, (0.45, 0.28, 0.08, 1)
        pr.color_ramp.elements[1].position, pr.color_ramp.elements[1].color = 0.25, (1.0, 0.76, 0.33, 1)
        L.new(pits.outputs["Distance"], pr.inputs["Fac"])
        L.new(pr.outputs["Color"], bsdf.inputs["Base Color"])
        rough(0.2, 0.45)
        metal.outputs[0].default_value = 1.0
    else:  # diamond
        L.new(ramp((0.82, 0.9, 1.0, 1), (0.95, 0.98, 1.0, 1)).outputs["Color"], bsdf.inputs["Base Color"])
        rough(0.02, 0.08)
        metal.outputs[0].default_value = 0.0
    if metal.type == "VALUE":
        L.new(metal.outputs[0], bsdf.inputs["Metallic"])
    else:
        L.new(metal.outputs["Value"], bsdf.inputs["Metallic"])
    return mat, metal


def bake(obj, mat, metal_node):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")
    N, L = mat.node_tree.nodes, mat.node_tree.links
    out_node = N["Material Output"]
    bsdf = N["Principled BSDF"]
    imgs = {}
    for kind, bake_type, cs in (("color", "EMIT", "sRGB"), ("roughness", "ROUGHNESS", "Non-Color"), ("metalness", "EMIT", "Non-Color")):
        img = bpy.data.images.new(f"{obj.name}_{kind}", TEX, TEX)
        img.colorspace_settings.name = cs
        node = N.new("ShaderNodeTexImage")
        node.image = img
        N.active = node
        kw = dict(type=bake_type, margin=4)
        if bake_type == "EMIT":
            # route the value straight into emission for a moment and bake that. metalness has no bake of
            # its own, and a diffuse colour bake of a metal comes out black (metals have no diffuse), which is
            # what turned the gold black on the first go
            src = metal_node.outputs[0] if kind == "metalness" else bsdf.inputs["Base Color"].links[0].from_socket
            em = N.new("ShaderNodeEmission")
            L.new(src, em.inputs["Color"])
            L.new(em.outputs["Emission"], out_node.inputs["Surface"])
        bpy.ops.object.bake(**kw)
        if bake_type == "EMIT":
            L.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
        path = os.path.join(OUT, f"{obj.name}_{kind}.jpg")
        img.filepath_raw = path
        img.file_format = "JPEG"
        img.save()
        imgs[kind] = img
    game = bpy.data.materials.new(obj.name + "_game")
    game.use_nodes = True
    gn, gl = game.node_tree.nodes, game.node_tree.links
    b = gn["Principled BSDF"]
    for kind, socket in (("color", "Base Color"), ("roughness", "Roughness"), ("metalness", "Metallic")):
        t = gn.new("ShaderNodeTexImage")
        t.image = imgs[kind]
        gl.new(t.outputs["Color"], b.inputs[socket])
    obj.data.materials.clear()
    obj.data.materials.append(game)


made = []
x = 0.0
for kind in ("coal", "iron", "gold", "diamond"):
    for i in range(1, 4):
        name = f"{kind.capitalize()}{i}"
        obj = cluster(name, kind, hash(name) % 10000)
        mat, metal = material(kind)
        obj.data.materials.append(mat)
        bake(obj, mat, metal)
        obj.location = (x, 0, 0)
        x += 1.6
        made.append(obj)
        print("made", name, "tris", sum(len(p.vertices) - 2 for p in obj.data.polygons))

bpy.ops.object.select_all(action="DESELECT")
for o in made:
    o.select_set(True)
fbx = os.path.join(OUT, "ores.fbx")
bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_scale_options="FBX_SCALE_ALL", mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True)
print("exported", fbx)

# preview: all twelve in a row on a dark floor
bpy.ops.mesh.primitive_plane_add(size=60, location=(x / 2, 0, 0))
g = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.12, 0.1, 0.1, 1)
g.data.materials.append(gm)
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(15), math.radians(35)))
bpy.context.active_object.data.energy = 4
bpy.ops.object.light_add(type="AREA", location=(x / 2, -3, 3))
bpy.context.active_object.data.energy = 300
bpy.context.active_object.data.size = 6
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.37, 0.45, 1)
scene.world = world
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
cam.location = (x / 2 - 0.8, -13, 5)
cam_data.lens = 32
cam.rotation_euler = (Vector((x / 2 - 0.8, 0, 0.2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.cycles.samples = 64
scene.render.resolution_x, scene.render.resolution_y = 1400, 520
scene.render.filepath = os.path.join(OUT, "ores_preview.png")
bpy.ops.render.render(write_still=True)
print("preview", scene.render.filepath)

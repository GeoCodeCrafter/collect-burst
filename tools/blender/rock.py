"""Procedural fractured rock: high-poly sculpt -> baked colour/normal/roughness on a game mesh.
blender -b --factory-startup -P rock.py -- <outdir> <name> <seed> <subdiv> <low_tris> <tex>"""
import bpy, math, random, sys, os
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if len(argv) > 0 else os.getcwd()
NAME = argv[1] if len(argv) > 1 else "rock"
SEED = int(argv[2]) if len(argv) > 2 else 7
SUB = int(argv[3]) if len(argv) > 3 else 7
LOW_TRIS = int(argv[4]) if len(argv) > 4 else 4000
TEX = int(argv[5]) if len(argv) > 5 else 1024
os.makedirs(OUT, exist_ok=True)
random.seed(SEED)
OFF = Vector((random.uniform(-50, 50), random.uniform(-50, 50), random.uniform(-50, 50)))
SCALE = Vector((random.uniform(1.15, 1.35), random.uniform(0.95, 1.1), random.uniform(0.8, 0.95)))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def rand_dir():
    while True:
        v = Vector((random.gauss(0, 1), random.gauss(0, 1), random.gauss(0, 1)))
        if v.length > 1e-3:
            return v.normalized()


# fracture planes: clipping a lumpy sphere by random planes gives the flat chipped faces real rock has.
# the second set sits close to the surface, so it only nicks the edges and corners
PLANES = [(rand_dir(), random.uniform(0.6, 0.93)) for _ in range(18)]
CHIPS = [(rand_dir(), random.uniform(0.88, 0.98)) for _ in range(45)]


def shape(d):
    # lumpier base so the planes bite in at different depths and it doesn't come out dice-shaped
    r = 1.0 + 0.26 * noise.fractal(d * 1.1 + OFF, 0.7, 2.0, 3)
    for n, o in PLANES + CHIPS:
        c = d.dot(n)
        if c > 1e-3:
            r = min(r, o / c)
    # unevenness across the faces. the fine grit comes from the normal map
    r += 0.022 * noise.fractal(d * 2.6 + OFF, 0.8, 2.2, 4)
    r += 0.006 * noise.fractal(d * 12.0 + OFF, 0.9, 2.0, 3)
    p = d * r
    p = Vector((p.x * SCALE.x, p.y * SCALE.y, p.z * SCALE.z))
    p.z = max(p.z, -0.55 * SCALE.z)  # flat underside so it sits on the ground
    return p


# ---- high poly
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=SUB, radius=1.0)
hi = bpy.context.active_object
hi.name = NAME + "_high"
for v in hi.data.vertices:
    v.co = shape(v.co.normalized())
bpy.ops.object.shade_smooth()

# ---- procedural material on the high poly (what gets baked)
def rock_material():
    mat = bpy.data.materials.new(NAME + "_proc")
    mat.use_nodes = True
    nt = mat.node_tree
    N, L = nt.nodes, nt.links
    bsdf = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")

    base = N.new("ShaderNodeTexNoise")
    base.inputs["Scale"].default_value = 1.4
    base.inputs["Detail"].default_value = 15
    base.inputs["Roughness"].default_value = 0.66
    L.new(tc.outputs["Object"], base.inputs["Vector"])
    ramp = N.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position, cr.elements[0].color = 0.32, (0.018, 0.018, 0.019, 1)
    cr.elements[1].position, cr.elements[1].color = 0.74, (0.13, 0.125, 0.118, 1)
    e = cr.elements.new(0.52)
    e.color = (0.052, 0.05, 0.048, 1)
    L.new(base.outputs["Fac"], ramp.inputs["Fac"])

    # feldspar / quartz grains: small pale flecks through the dark stone
    vor = N.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 70
    vor.inputs["Randomness"].default_value = 1.0
    L.new(tc.outputs["Object"], vor.inputs["Vector"])
    speck = N.new("ShaderNodeValToRGB")
    speck.color_ramp.elements[0].position = 0.10
    speck.color_ramp.elements[0].color = (1, 1, 1, 1)
    speck.color_ramp.elements[1].position = 0.2
    speck.color_ramp.elements[1].color = (0, 0, 0, 1)
    L.new(vor.outputs["Distance"], speck.inputs["Fac"])
    mix_speck = N.new("ShaderNodeMix")
    mix_speck.data_type = "RGBA"
    mix_speck.inputs["B"].default_value = (0.36, 0.34, 0.31, 1)
    L.new(speck.outputs["Color"], mix_speck.inputs["Factor"])
    L.new(ramp.outputs["Color"], mix_speck.inputs["A"])

    # rusty iron staining in big soft patches
    rust_n = N.new("ShaderNodeTexNoise")
    rust_n.inputs["Scale"].default_value = 1.2
    rust_n.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], rust_n.inputs["Vector"])
    rust_r = N.new("ShaderNodeValToRGB")
    rust_r.color_ramp.elements[0].position = 0.58
    rust_r.color_ramp.elements[0].color = (0, 0, 0, 1)
    rust_r.color_ramp.elements[1].position = 0.75
    rust_r.color_ramp.elements[1].color = (0.55, 0.55, 0.55, 1)
    L.new(rust_n.outputs["Fac"], rust_r.inputs["Fac"])
    mix_rust = N.new("ShaderNodeMix")
    mix_rust.data_type = "RGBA"
    mix_rust.blend_type = "MULTIPLY"
    mix_rust.inputs["B"].default_value = (0.75, 0.42, 0.22, 1)
    L.new(rust_r.outputs["Color"], mix_rust.inputs["Factor"])
    L.new(mix_speck.outputs["Result"], mix_rust.inputs["A"])

    # worn, lighter edges and dark crevices
    geo = N.new("ShaderNodeNewGeometry")
    edge = N.new("ShaderNodeValToRGB")
    edge.color_ramp.elements[0].position = 0.51
    edge.color_ramp.elements[0].color = (0, 0, 0, 1)
    edge.color_ramp.elements[1].position = 0.6
    edge.color_ramp.elements[1].color = (1, 1, 1, 1)
    L.new(geo.outputs["Pointiness"], edge.inputs["Fac"])
    # only some of each edge is worn, not a clean outline all the way round
    edge_n = N.new("ShaderNodeTexNoise")
    edge_n.inputs["Scale"].default_value = 9
    edge_n.inputs["Detail"].default_value = 4
    L.new(tc.outputs["Object"], edge_n.inputs["Vector"])
    edge_mask = N.new("ShaderNodeMapRange")
    edge_mask.inputs["From Min"].default_value = 0.45
    edge_mask.inputs["From Max"].default_value = 0.7
    edge_mask.inputs["To Max"].default_value = 0.35
    L.new(edge_n.outputs["Fac"], edge_mask.inputs["Value"])
    edge_amt = N.new("ShaderNodeMath")
    edge_amt.operation = "MULTIPLY"
    L.new(edge.outputs["Color"], edge_amt.inputs[0])
    L.new(edge_mask.outputs["Result"], edge_amt.inputs[1])
    mix_edge = N.new("ShaderNodeMix")
    mix_edge.data_type = "RGBA"
    mix_edge.blend_type = "SCREEN"
    mix_edge.inputs["B"].default_value = (0.24, 0.23, 0.21, 1)
    L.new(edge_amt.outputs["Value"], mix_edge.inputs["Factor"])
    # thin quartz veins wandering through the stone
    # a few thin quartz veins, only in some parts of the stone and faded in places
    vein = N.new("ShaderNodeTexWave")
    vein.inputs["Scale"].default_value = 0.65
    vein.inputs["Distortion"].default_value = 11
    vein.inputs["Detail"].default_value = 7
    vein.inputs["Detail Scale"].default_value = 2.0
    L.new(tc.outputs["Object"], vein.inputs["Vector"])
    vein_r = N.new("ShaderNodeValToRGB")
    vein_r.color_ramp.elements[0].position = 0.0
    vein_r.color_ramp.elements[0].color = (1, 1, 1, 1)
    vein_r.color_ramp.elements[1].position = 0.016
    vein_r.color_ramp.elements[1].color = (0, 0, 0, 1)
    L.new(vein.outputs["Fac"], vein_r.inputs["Fac"])
    vein_zone = N.new("ShaderNodeTexNoise")
    vein_zone.inputs["Scale"].default_value = 1.1
    vein_zone.inputs["Detail"].default_value = 3
    L.new(tc.outputs["Object"], vein_zone.inputs["Vector"])
    vein_mask = N.new("ShaderNodeMapRange")
    vein_mask.inputs["From Min"].default_value = 0.48
    vein_mask.inputs["From Max"].default_value = 0.62
    vein_mask.inputs["To Max"].default_value = 0.7
    L.new(vein_zone.outputs["Fac"], vein_mask.inputs["Value"])
    vein_amt = N.new("ShaderNodeMath")
    vein_amt.operation = "MULTIPLY"
    L.new(vein_r.outputs["Color"], vein_amt.inputs[0])
    L.new(vein_mask.outputs["Result"], vein_amt.inputs[1])
    mix_vein = N.new("ShaderNodeMix")
    mix_vein.data_type = "RGBA"
    mix_vein.inputs["B"].default_value = (0.40, 0.385, 0.35, 1)
    L.new(vein_amt.outputs["Value"], mix_vein.inputs["Factor"])
    L.new(mix_rust.outputs["Result"], mix_vein.inputs["A"])
    L.new(mix_vein.outputs["Result"], mix_edge.inputs["A"])
    ao = N.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.25
    L.new(mix_edge.outputs["Result"], ao.inputs["Color"])
    ao_ramp = N.new("ShaderNodeValToRGB")
    ao_ramp.color_ramp.elements[0].color = (0.35, 0.35, 0.35, 1)
    L.new(ao.outputs["AO"], ao_ramp.inputs["Fac"])
    mix_ao = N.new("ShaderNodeMix")
    mix_ao.data_type = "RGBA"
    mix_ao.blend_type = "MULTIPLY"
    mix_ao.inputs["Factor"].default_value = 1.0
    L.new(mix_edge.outputs["Result"], mix_ao.inputs["A"])
    L.new(ao_ramp.outputs["Color"], mix_ao.inputs["B"])
    L.new(mix_ao.outputs["Result"], bsdf.inputs["Base Color"])

    # roughness: rough overall, specks a bit shinier
    rough = N.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.62
    rough.inputs["To Max"].default_value = 0.95
    L.new(base.outputs["Fac"], rough.inputs["Value"])
    L.new(rough.outputs["Result"], bsdf.inputs["Roughness"])

    # surface detail, ends up in the baked normal map: fine granite grain plus shallow pits
    bn = N.new("ShaderNodeTexNoise")
    bn.inputs["Scale"].default_value = 90
    bn.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], bn.inputs["Vector"])
    pits = N.new("ShaderNodeTexVoronoi")
    pits.inputs["Scale"].default_value = 14
    L.new(tc.outputs["Object"], pits.inputs["Vector"])
    height = N.new("ShaderNodeMath")
    height.operation = "MULTIPLY_ADD"
    height.inputs[1].default_value = 0.6
    L.new(pits.outputs["Distance"], height.inputs[0])
    L.new(bn.outputs["Fac"], height.inputs[2])
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = 0.022
    L.new(height.outputs["Value"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


hi.data.materials.append(rock_material())

# ---- low poly game mesh
lo = hi.copy()
lo.data = hi.data.copy()
lo.name = NAME
scene.collection.objects.link(lo)
dec = lo.modifiers.new("dec", "DECIMATE")
dec.ratio = min(1.0, LOW_TRIS / (len(hi.data.polygons)))
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = lo
lo.select_set(True)
bpy.ops.object.modifier_apply(modifier="dec")
lo.data.materials.clear()
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(85), island_margin=0.004)
bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.shade_smooth()

# ---- amethyst crystals growing out of the rock, exported with it as their own mesh
CRYSTALS = "--nocrystals" not in sys.argv


def crystal(bm, base, direction, length, radius):
    # hexagonal prism with a six-sided point, like a real quartz crystal
    z = direction.normalized()
    x = z.cross(Vector((0.3, 0.7, 0.1))).normalized()
    y = z.cross(x)
    spin = random.uniform(0, math.pi)
    ang = [spin + i * math.pi / 3 for i in range(6)]
    bottom = [bm.verts.new(base + (x * math.cos(a) + y * math.sin(a)) * radius) for a in ang]
    top = [bm.verts.new(base + z * length + (x * math.cos(a) + y * math.sin(a)) * radius * 0.9) for a in ang]
    tip = bm.verts.new(base + z * (length + radius * random.uniform(1.4, 2.0)))
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
        bm.faces.new((top[i], top[j], tip))
    bm.faces.new(list(reversed(bottom)))


crystal_obj = None
if CRYSTALS:
    import bmesh
    bm = bmesh.new()
    inv = lo.matrix_world.inverted()
    placed = 0
    tries = 0
    while placed < 3 and tries < 200:
        tries += 1
        px, py = random.uniform(-0.6, 0.6) * SCALE.x, random.uniform(-0.6, 0.6) * SCALE.y
        ok, loc, nrm, _ = lo.ray_cast(inv @ Vector((px, py, 5)), Vector((0, 0, -1)))
        # only on faces that point mostly up, so no cluster sticks out sideways looking glued on
        if not ok or nrm.z < 0.7:
            continue
        placed += 1
        up = (nrm + Vector((0, 0, 1))).normalized()
        for _ in range(random.randint(4, 7)):
            tilt = (up + Vector((random.gauss(0, 0.35), random.gauss(0, 0.35), random.gauss(0, 0.15)))).normalized()
            # sunk only a little: at 0.12 deep most of each crystal ended up inside the rock in game
            crystal(bm, loc - up * 0.05, tilt, random.uniform(0.35, 0.8), random.uniform(0.07, 0.13))
    # the faces above are wound by hand and some end up facing inward. roblox doesn't draw the back
    # of a face, so without this about a third of every crystal was invisible in game
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cm = bpy.data.meshes.new("Crystals")
    bm.to_mesh(cm)
    bm.free()
    for p in cm.polygons:
        p.use_smooth = False
    crystal_obj = bpy.data.objects.new("Crystals", cm)
    scene.collection.objects.link(crystal_obj)
    am = bpy.data.materials.new("amethyst")
    am.use_nodes = True
    ab = am.node_tree.nodes["Principled BSDF"]
    ab.inputs["Base Color"].default_value = (0.42, 0.12, 0.85, 1)
    ab.inputs["Roughness"].default_value = 0.05
    ab.inputs["Transmission Weight"].default_value = 0.85
    cm.materials.append(am)
    print("crystal clusters", placed, "tris", sum(len(p.vertices) - 2 for p in cm.polygons))

bake_mat = bpy.data.materials.new(NAME + "_game")
bake_mat.use_nodes = True
lo.data.materials.append(bake_mat)
bn = bake_mat.node_tree.nodes
bl = bake_mat.node_tree.links

# ---- bake
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 24
imgs = {}
for kind, bake_type, colorspace in (("color", "DIFFUSE", "sRGB"), ("normal", "NORMAL", "Non-Color"), ("roughness", "ROUGHNESS", "Non-Color")):
    img = bpy.data.images.new(f"{NAME}_{kind}", TEX, TEX)
    img.colorspace_settings.name = colorspace
    node = bn.new("ShaderNodeTexImage")
    node.image = img
    bn.active = node
    bpy.ops.object.select_all(action="DESELECT")
    hi.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    kw = dict(type=bake_type, use_selected_to_active=True, cage_extrusion=0.08, max_ray_distance=0.2, margin=8)
    if bake_type == "DIFFUSE":
        kw["pass_filter"] = {"COLOR"}
    bpy.ops.object.bake(**kw)
    path = os.path.join(OUT, f"{NAME}_{kind}.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    imgs[kind] = node
    print("baked", path)

# wire the baked maps up so the preview shows exactly what the game gets
bsdf = bn["Principled BSDF"]
bl.new(imgs["color"].outputs["Color"], bsdf.inputs["Base Color"])
bl.new(imgs["roughness"].outputs["Color"], bsdf.inputs["Roughness"])
nm = bn.new("ShaderNodeNormalMap")
bl.new(imgs["normal"].outputs["Color"], nm.inputs["Color"])
bl.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

# ---- export the game mesh
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
if crystal_obj:
    crystal_obj.select_set(True)
bpy.context.view_layer.objects.active = lo
fbx = os.path.join(OUT, f"{NAME}.fbx")
bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_scale_options="FBX_SCALE_ALL", mesh_smooth_type="FACE", path_mode="COPY", embed_textures=False)
print("exported", fbx, "tris", sum(len(p.vertices) - 2 for p in lo.data.polygons))

# ---- preview render of the low poly with baked maps
hi.hide_render = True
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, -0.55 * SCALE.z))
ground = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.31, 0.3, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
ground.data.materials.append(gm)
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(35)))
bpy.context.active_object.data.energy = 4
bpy.context.active_object.data.angle = math.radians(3)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.55, 0.7, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
scene.world = world
bpy.ops.object.camera_add(location=(3.4, -3.6, 1.6))
cam = bpy.context.active_object
cam.data.lens = 55
track = cam.constraints.new("TRACK_TO")
track.target = lo
scene.camera = cam
scene.cycles.samples = 64
scene.render.resolution_x, scene.render.resolution_y = 960, 640
scene.render.filepath = os.path.join(OUT, f"{NAME}_preview.png")
bpy.ops.render.render(write_still=True)
print("preview", scene.render.filepath)

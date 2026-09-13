"""Amethyst crystal clusters: tapered hex crystals with bevelled edges, growth ridges and small crystals
round the base, with a baked colour gradient (dark base, pale tip, cloudy inside) and roughness map.
Import as a module (build_cluster) or run on its own for a preview:
blender -b --factory-startup -P crystals.py -- <outdir>"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix, noise


def _frame(z):
    z = z.normalized()
    x = z.cross(Vector((0.31, 0.72, 0.1))).normalized()
    return x, z.cross(x), z


def crystal(bm, base, direction, length, radius, rng):
    """one quartz crystal: six sides tapering slightly, horizontal growth ridges, an uneven six-faced
    point (real terminations are never a perfect pyramid)"""
    x, y, z = _frame(direction)
    spin = rng.uniform(0, math.pi)
    rings = 5
    # 0 at the base of this crystal, 1 at its point. the colour gradient runs on this, so every
    # crystal gets its own dark tip whatever height it sits at on the rock
    tip_layer = bm.verts.layers.float.get("tip") or bm.verts.layers.float.new("tip")
    loops = []
    for k in range(rings + 1):
        t = k / rings
        # taper towards the tip, plus a little ridge at each ring like real growth bands
        r = radius * (1 - 0.18 * t) * (1 + (0.035 if 0 < k < rings else 0) * (1 if k % 2 else -1))
        ring = []
        for i in range(6):
            a = spin + i * math.pi / 3
            v = bm.verts.new(base + z * (length * t) + (x * math.cos(a) + y * math.sin(a)) * r)
            v[tip_layer] = t * 0.8
            ring.append(v)
        loops.append(ring)
    for k in range(rings):
        for i in range(6):
            j = (i + 1) % 6
            bm.faces.new((loops[k][i], loops[k][j], loops[k + 1][j], loops[k + 1][i]))
    tip_h = radius * rng.uniform(1.3, 1.9)
    apex = bm.verts.new(base + z * (length + tip_h) + (x * rng.uniform(-0.25, 0.25) + y * rng.uniform(-0.25, 0.25)) * radius)
    apex[tip_layer] = 1.0
    for i in range(6):
        bm.faces.new((loops[-1][i], loops[-1][(i + 1) % 6], apex))
    bm.faces.new(list(reversed(loops[0])))


def build_cluster(name, seed, count=7, druse=14, scale=1.0):
    """returns a mesh object with one main cluster at the origin growing up +Z"""
    rng = random.Random(seed)
    bm = bmesh.new()
    for n in range(count):
        main = n == 0
        tilt = Vector((rng.gauss(0, 0.32), rng.gauss(0, 0.32), 1.0))
        off = Vector((rng.gauss(0, 0.12), rng.gauss(0, 0.12), -0.04))
        length = rng.uniform(0.9, 1.3) if main else rng.uniform(0.35, 0.85)
        radius = rng.uniform(0.16, 0.2) if main else rng.uniform(0.07, 0.14)
        crystal(bm, off * scale, tilt, length * scale, radius * scale, rng)
    # small crystals crowding the base so the cluster grows out of the rock instead of being stuck in
    for _ in range(druse):
        ang = rng.uniform(0, 2 * math.pi)
        dist = rng.uniform(0.12, 0.34)
        base = Vector((math.cos(ang) * dist, math.sin(ang) * dist, -0.05))
        tilt = Vector((math.cos(ang) * rng.uniform(0.3, 0.9), math.sin(ang) * rng.uniform(0.3, 0.9), 1.0))
        crystal(bm, base * scale, tilt, rng.uniform(0.08, 0.22) * scale, rng.uniform(0.03, 0.055) * scale, rng)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # a thin bevel on the sharp edges gives each facet a highlight line, which is what reads as "gem"
    sharp = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(25)]
    bmesh.ops.bevel(bm, geom=sharp, offset=0.006 * scale, segments=1, affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def crystal_material(name):
    """procedural amethyst: deep violet at the base fading to pale lilac at the tips, with cloudy
    patches inside. baked to textures so roblox gets the same look"""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    N, L = mat.node_tree.nodes, mat.node_tree.links
    bsdf = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    # per-crystal base-to-tip value written by crystal(), not height in the object
    tip = N.new("ShaderNodeAttribute")
    tip.attribute_name = "tip"
    height = N.new("ShaderNodeMapRange")
    height.inputs["From Min"].default_value = 0.0
    height.inputs["From Max"].default_value = 1.0
    L.new(tip.outputs["Fac"], height.inputs["Value"])
    # real amethyst: paler, greyer violet at the base going to deep saturated violet at the tips
    grad = N.new("ShaderNodeValToRGB")
    cr = grad.color_ramp
    cr.elements[0].position, cr.elements[0].color = 0.0, (0.34, 0.26, 0.42, 1)
    cr.elements[1].position, cr.elements[1].color = 1.0, (0.13, 0.015, 0.34, 1)
    mid = cr.elements.new(0.4)
    mid.color = (0.3, 0.07, 0.62, 1)
    L.new(height.outputs["Result"], grad.inputs["Fac"])
    # uneven colour zoning inside the stone, subtle and darker, not white blotches
    cloud = N.new("ShaderNodeTexNoise")
    cloud.inputs["Scale"].default_value = 5
    cloud.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], cloud.inputs["Vector"])
    cloud_r = N.new("ShaderNodeValToRGB")
    cloud_r.color_ramp.elements[0].position = 0.45
    cloud_r.color_ramp.elements[0].color = (0, 0, 0, 1)
    cloud_r.color_ramp.elements[1].position = 0.7
    cloud_r.color_ramp.elements[1].color = (0.35, 0.35, 0.35, 1)
    L.new(cloud.outputs["Fac"], cloud_r.inputs["Fac"])
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["B"].default_value = (0.55, 0.45, 0.7, 1)
    L.new(cloud_r.outputs["Color"], mix.inputs["Factor"])
    L.new(grad.outputs["Color"], mix.inputs["A"])
    L.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    rough = N.new("ShaderNodeMapRange")
    # polished faces: low roughness is what makes each facet catch a highlight in roblox
    rough.inputs["To Min"].default_value = 0.02
    rough.inputs["To Max"].default_value = 0.12
    L.new(cloud.outputs["Fac"], rough.inputs["Value"])
    L.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    return mat


def bake_to_textures(obj, out, tex=512):
    """unwraps obj and bakes its procedural material to colour + roughness images, then swaps the
    material for one that uses those images so the FBX carries them to roblox"""
    scene = bpy.context.scene
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    proc = obj.data.materials[0]
    nodes = proc.node_tree.nodes
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    maps = {}
    for kind, bake_type, cs in (("color", "DIFFUSE", "sRGB"), ("roughness", "ROUGHNESS", "Non-Color")):
        img = bpy.data.images.new(f"{obj.name}_{kind}", tex, tex)
        img.colorspace_settings.name = cs
        node = nodes.new("ShaderNodeTexImage")
        node.image = img
        nodes.active = node
        kw = dict(type=bake_type, margin=6)
        if bake_type == "DIFFUSE":
            kw["pass_filter"] = {"COLOR"}
        bpy.ops.object.bake(**kw)
        # jpg keeps the fbx small, these are smooth gradients so compression doesn't show
        path = os.path.join(out, f"{obj.name}_{kind}.jpg")
        img.filepath_raw = path
        img.file_format = "JPEG"
        img.save()
        maps[kind] = img
    game = bpy.data.materials.new(obj.name + "_game")
    game.use_nodes = True
    gn, gl = game.node_tree.nodes, game.node_tree.links
    b = gn["Principled BSDF"]
    c = gn.new("ShaderNodeTexImage")
    c.image = maps["color"]
    gl.new(c.outputs["Color"], b.inputs["Base Color"])
    r = gn.new("ShaderNodeTexImage")
    r.image = maps["roughness"]
    gl.new(r.outputs["Color"], b.inputs["Roughness"])
    obj.data.materials.clear()
    obj.data.materials.append(game)
    return maps


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    OUT = argv[0] if argv else os.getcwd()
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obj = build_cluster("CrystalCluster", 3)
    obj.data.materials.append(crystal_material("amethyst_proc"))
    bake_to_textures(obj, OUT)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("cluster tris", tris)
    # preview
    scene = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, -0.06))
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(45), math.radians(15), math.radians(40)))
    bpy.context.active_object.data.energy = 4
    bpy.ops.object.light_add(type="AREA", location=(-1.5, -1.5, 2.5))
    bpy.context.active_object.data.energy = 150
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.5, 0.6, 1)
    scene.world = world
    bpy.ops.object.camera_add(location=(2.2, -2.4, 1.5))
    cam = bpy.context.active_object
    target = bpy.data.objects.new("t", None)
    target.location = (0, 0, 0.55)
    scene.collection.objects.link(target)
    cam.constraints.new("TRACK_TO").target = target
    scene.camera = cam
    scene.cycles.samples = 64
    scene.render.resolution_x, scene.render.resolution_y = 800, 640
    scene.render.filepath = os.path.join(OUT, "crystals_preview.png")
    bpy.ops.render.render(write_still=True)
    print("preview", scene.render.filepath)

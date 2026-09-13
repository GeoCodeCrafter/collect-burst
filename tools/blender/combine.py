"""Merges the separate exports into one FBX so Studio needs a single Import 3D.
blender -b --factory-startup -P combine.py -- <outdir>
Objects come out named Rock, Crystals, Gem, Chunk1..3, spaced apart so nothing overlaps."""
import bpy, os, sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.getcwd()
bpy.ops.wm.read_factory_settings(use_empty=True)

PARTS = [("rock.fbx", {"rock": "Rock", "Crystals": "Crystals"}), ("gem.fbx", {"gem": "Gem"})]
for i, seed in enumerate((11, 23, 37), 1):
    PARTS.append((f"chunk{seed}.fbx", {f"chunk{seed}": f"Chunk{i}"}))

x = 0.0
for fname, names in PARTS:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, fname))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for old, want in names.items():
            if o.name.startswith(old):
                o.name = want
                o.data.name = want
        if o.name != "Crystals":
            o.location.x += x
    if names.get("rock") != "Rock":
        pass
    x += 4.0
# crystals were exported sitting on the rock, keep them with it
rock, crystals = bpy.data.objects.get("Rock"), bpy.data.objects.get("Crystals")
if rock and crystals:
    crystals.location = rock.location

bpy.ops.object.select_all(action="SELECT")
path = os.path.join(OUT, "collect_burst_assets.fbx")
bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_scale_options="FBX_SCALE_ALL", mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True)
print("combined", path, [o.name for o in bpy.data.objects])

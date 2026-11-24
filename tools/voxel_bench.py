"""
Banc de développé couché voxel (exécuté dans Blender via MCP).

Construit dans la scène « TAM_Bench » :
  BenchPress : banc + montants + crochets (sans la barre)
  Barbell    : barre seule (axe = Y Blender)
  Plate1..6  : disques de plus en plus gros (vert, jaune, bleu, rouge, noir, or)
Chaque modèle = un Empty <Nom> avec un mesh par couleur nommé <Nom>_<RRGGBB>_<n>
(Roblox relit la couleur dans le nom). 1 voxel = VOX unités Blender = VOX studs.
Export : Assets/Props/Bench/Bench.fbx

Utilisation :
    ns = {}; exec(open(r"...\\tools\\voxel_bench.py", encoding="utf-8").read(), ns)
    ns["build_all"](); ns["export"]()
"""
import bpy, bmesh, math, os

ROOT = r"C:\Users\morel\Documents\ThrowARelic"
OUT = os.path.join(ROOT, "Assets", "Props", "Bench", "Bench.fbx")
SCENE = "TAM_Bench"
VOX = 0.5  # taille d'un voxel (studs)


class V(dict):
    def put(self, x, y, z, c):
        self[(int(round(x)), int(round(y)), int(round(z)))] = c

    def box(self, x0, y0, z0, x1, y1, z1, c):
        for x in range(int(min(x0, x1)), int(max(x0, x1)) + 1):
            for y in range(int(min(y0, y1)), int(max(y0, y1)) + 1):
                for z in range(int(min(z0, z1)), int(max(z0, z1)) + 1):
                    self[(x, y, z)] = c

    def disc_y(self, cx, cz, r, y0, y1, c, inner=0, ring=None):
        """disque perpendiculaire à Y ; ring = (rayon_min, couleur) pour un liseré extérieur"""
        R = int(math.ceil(r))
        for x in range(-R, R + 1):
            for z in range(-R, R + 1):
                d = math.hypot(x, z)
                if inner <= d <= r + 0.35:
                    col = c
                    if ring and d >= ring[0]:
                        col = ring[1]
                    for y in range(int(min(y0, y1)), int(max(y0, y1)) + 1):
                        self[(cx + x, y, cz + z)] = col


# ------------------------------------------------------------------ modèles
STEEL = "3B3B40"
STEEL_DARK = "26262A"
CHROME = "C8CCD6"
KNURL = "9A9EA8"
LEATHER = "B83A2E"
LEATHER_DARK = "8E2A22"


def bench():
    v = V()
    # coussin (tête vers +X)
    v.box(0, -1, 4, 11, 1, 4, LEATHER)
    v.box(0, -2, 4, 11, -2, 4, LEATHER_DARK)
    v.box(0, 2, 4, 11, 2, 4, LEATHER_DARK)
    v.box(0, -2, 3, 11, 2, 3, LEATHER_DARK)
    # poutre sous le coussin + pieds
    v.box(1, 0, 2, 10, 0, 2, STEEL)
    for x in (1, 10):
        v.box(x, 0, 0, x, 0, 2, STEEL)
        v.box(x, -2, 0, x, 2, 0, STEEL_DARK)
    # montants côté tête + traverse au sol
    for y in (-5, 5):
        v.box(13, y, 0, 13, y, 10, STEEL)
        v.box(12, y, 0, 14, y, 0, STEEL_DARK)
        # crochets en J
        v.box(12, y, 9, 12, y, 9, CHROME)
        v.box(11, y, 9, 11, y, 10, CHROME)
    v.box(13, -5, 0, 13, 5, 0, STEEL_DARK)
    v.box(13, -5, 6, 13, 5, 6, STEEL)  # renfort
    return v


def barbell():
    v = V()
    v.box(0, -15, 0, 0, 15, 0, CHROME)  # manchons longs : jusqu'à 9 voxels de disques par côté
    v.box(0, -2, 0, 0, 2, 0, KNURL)
    for y in (-6, 6):  # butées
        v.box(-1, y, -1, 1, y, 1, STEEL)
    return v


PLATES = [
    # nom, rayon (voxels), épaisseur (voxels), couleur, liseré
    ("Plate1", 2.2, 1, "3FAE5A", None),
    ("Plate2", 3.0, 1, "F4C430", None),
    ("Plate3", 3.6, 2, "3B7DD8", None),
    ("Plate4", 4.4, 2, "D8433B", None),
    ("Plate5", 5.2, 2, "2A2420", (4.6, "F2C14E")),
    ("Plate6", 6.0, 3, "F2C14E", (5.3, "FFF1A8")),
]


def plate(r, t, color, ring):
    v = V()
    v.disc_y(0, 0, r, 0, t - 1, color, ring=ring)
    v.disc_y(0, 0, 1.2, -1, t, CHROME)  # moyeu
    return v


# ------------------------------------------------------------------ Blender
FACES = [((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
         ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
         ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
         ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
         ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
         ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)])]


def get_scene():
    scene = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = scene
    return scene


def material(hexc):
    name = "TAM_" + hexc
    mat = bpy.data.materials.get(name)
    if not mat:
        mat = bpy.data.materials.new(name)
        rgb = [int(hexc[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        mat.diffuse_color = (*rgb, 1)
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs[0].default_value = (*[c ** 2.2 for c in rgb], 1)
    return mat


def build(name, vox, collection, location=(0, 0, 0)):
    old = bpy.data.objects.get(name)
    if old:
        for c in list(old.children):
            bpy.data.objects.remove(c, do_unlink=True)
        bpy.data.objects.remove(old, do_unlink=True)
    root = bpy.data.objects.new(name, None)
    collection.objects.link(root)
    root.location = location
    by_color = {}
    for key, c in vox.items():
        by_color.setdefault(c, []).append(key)
    for n, (c, cells) in enumerate(sorted(by_color.items())):
        bm = bmesh.new()
        verts = {}

        def vert(p):
            if p not in verts:
                verts[p] = bm.verts.new((p[0] * VOX, p[1] * VOX, p[2] * VOX))
            return verts[p]

        for (x, y, z) in cells:
            for (d, quad) in FACES:
                if (x + d[0], y + d[1], z + d[2]) in vox:
                    continue
                try:
                    bm.faces.new([vert((x + q[0], y + q[1], z + q[2])) for q in quad])
                except ValueError:
                    pass
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        mesh = bpy.data.meshes.new("%s_%s_%d" % (name, c, n + 1))
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(material(c))
        obj = bpy.data.objects.new("%s_%s_%d" % (name, c, n + 1), mesh)
        collection.objects.link(obj)
        obj.parent = root
    return root


def build_all():
    scene = get_scene()
    col = scene.collection
    build("BenchPress", bench(), col, (0, 0, 0))
    build("Barbell", barbell(), col, (0, 12, 0))
    for i, (name, r, t, c, ring) in enumerate(PLATES):
        build(name, plate(r, t, c, ring), col, (i * 7, 22, 0))
    return [o.name for o in col.objects if o.parent is None]


def export():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    scene = get_scene()
    bpy.ops.object.select_all(action="DESELECT")
    for o in scene.collection.objects:
        o.select_set(True)
    bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, object_types={"MESH", "EMPTY"}, apply_unit_scale=True,
                             apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
                             bake_space_transform=True, add_leaf_bones=False)
    return OUT, os.path.getsize(OUT)

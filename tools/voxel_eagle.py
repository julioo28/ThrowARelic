# Aigle voxel (prop « Condor » qui plane au-dessus du canyon) — à exécuter dans Blender.
# Scène « TAM_Eagle ». 1 voxel = 1 m (mis à l'échelle à l'install dans Roblox).
# Trois groupes : corps (Condor_*), aile droite (CondorWingR_*), aile gauche (CondorWingL_*).
# Le pivot de chaque aile est l'épaule, pour pouvoir les faire battre séparément dans Roblox.
# Un objet par couleur, nommé <Groupe>_<RRGGBB>_<n> (couleur lue dans le nom à l'install).
# Export : Assets/Props/Condor_v2.fbx
import bpy, bmesh, math, os
from mathutils import Vector

OUT = r"C:\Users\morel\Documents\ThrowARelic\Assets\Props\Condor_v2.fbx"

P = {
    "W1": "F4EEE2", "W2": "E2D9C6", "W3": "CFC3AC",   # blanc crème (tête, queue)
    "B1": "C9783A", "B2": "A85E2C", "B3": "86461F",   # brun roux
    "D1": "5E3A26", "D2": "3E2A22", "D3": "2A2026",   # brun foncé, presque noir
    "O1": "FFB52E", "O2": "F08A16",                   # bec, pattes
    "K": "1A1418", "G": "5B6470",                     # pupille, anneau de l'oeil
}


def hh(x, y, z, s=0):
    n = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (s * 2654435761)
    n = (n ^ (n >> 13)) * 1274126177
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def pick(base, x, y, z):
    r = hh(x, y, z)
    if base == "W":
        return "W1" if r < .55 else ("W2" if r < .9 else "W3")
    if base == "B":
        return "B1" if r < .4 else ("B2" if r < .85 else "B3")
    if base == "D":
        return "D1" if r < .45 else ("D2" if r < .85 else "D3")
    return base


def torso_color(x, y, z):
    if y >= 7:
        return "W" if (y >= 8 or hh(x, y, z, 3) < .6) else "B"
    if z >= 2:
        return "D" if hh(x, y, z, 1) < .55 else "B"
    return "B"


def make_body():
    body = {}
    put = lambda x, y, z, c: body.__setitem__((x, y, z), c)
    # torse (y = avant)
    for x in range(-6, 7):
        for y in range(-12, 11):
            for z in range(-5, 6):
                if (x / 5.4) ** 2 + (y / 11.5) ** 2 + ((z - 0.3) / 4.4) ** 2 <= 1:
                    put(x, y, z, pick(torso_color(x, y, z), x, y, z))
    for x in range(-4, 5):
        for z in range(-3, 2):
            if (x, 7, z) in body:
                put(x, 7, z, "B1")  # liseré roux sous le cou
    # tête blanche
    for x in range(-4, 5):
        for y in range(8, 18):
            for z in range(-2, 6):
                if (x / 3.6) ** 2 + ((y - 13) / 4.0) ** 2 + ((z - 1.5) / 3.6) ** 2 <= 1:
                    put(x, y, z, pick("W", x, y, z))
    for x in (-3, -2, 2, 3):  # arcade sourcilière
        put(x, 15, 3, "W3"); put(x, 14, 4, "W2")
    for sx in (-1, 1):  # yeux
        ex = 4 * sx
        put(ex, 14, 2, "K"); put(ex, 15, 2, "G"); put(ex, 13, 2, "G"); put(ex, 14, 3, "G"); put(ex, 14, 1, "W1")
    # bec crochu
    for x in (-1, 0, 1):
        for y in range(16, 20):
            for z in (0, 1, 2):
                if not (y == 19 and z == 2):
                    put(x, y, z, "O1" if z >= 1 else "O2")
        put(x, 19, 0, "O2"); put(x, 20, 0, "O2")
    put(0, 20, -1, "O2"); put(0, 19, -1, "O2")
    for x in (-1, 1):
        put(x, 17, 1, "K")
    # queue en éventail
    for y in range(-17, -9):
        w = 2 + int((-9 - y) * 0.75)
        for x in range(-w, w + 1):
            if y <= -16 and x % 2 == 0:
                continue
            for z in (0, 1):
                if not (z == 1 and abs(x) == w):
                    put(x, y, z, pick("W", x, y, z))
    # serres repliées
    for sx in (-2, 2):
        for y in range(-8, -4):
            put(sx, y, -4, "D2" if y > -6 else "D1")
        for y in range(-10, -7):
            put(sx, y, -5, "O2")
        for dx in (-1, 0, 1):
            put(sx + dx, -11, -5, "K")
        put(sx - 1, -10, -5, "O2"); put(sx + 1, -10, -5, "O2")
    return body


def make_wing():
    cells = {}
    span = 26
    for i in range(span):
        x = 4 + i
        t = i / span
        bulge = 2 if 6 <= i <= 15 else (1 if 3 <= i <= 18 else 0)   # poignet
        lead = 5 + bulge - (int((i - 18) * 0.5) if i > 18 else 0)
        chord = int(14 - 4 * t)
        trail = lead - chord
        dz = int(i * 0.16)                                            # dièdre
        for y in range(trail, lead + 1):
            depth = (lead - y) / max(chord, 1)
            if depth < 0.22:
                base = "B1x"
            elif depth < 0.45:
                base = "B"
            elif depth < 0.65:
                base = "D" if hh(x, y, 0, 7) < .5 else "B"
            else:
                base = "D"
            zs = [0]
            if depth < 0.6 and i < 16:
                zs = [0, 1]
            if depth < 0.3 and i < 7:
                zs = [0, 1, 2]
            for z in zs:
                c = ("B1" if hh(x, y, z, 9) < .7 else "B2") if base == "B1x" else pick(base, x, y, z)
                cells[(x, y, z + dz)] = c
        if i % 2 == 0:
            cells[(x, trail - 1, dz)] = "D2"                          # bord de fuite dentelé
    tipx, tipz = 4 + span, int(span * 0.16)
    for k in range(6):                                                # rémiges primaires écartées
        baseY = 4 - k * 2
        ang = math.radians(-2 - k * 12)
        L = 10 - abs(k - 2)
        for s in range(L):
            fx = tipx + int(round(s * math.cos(ang)))
            fy = baseY + int(round(s * math.sin(ang)))
            cells[(fx, fy, tipz + (1 if s >= L - 3 else 0))] = "D3" if s >= L - 4 else "D2"
    return cells


def material(hexc):
    m = bpy.data.materials.get("TAM_" + hexc)
    if not m:
        m = bpy.data.materials.new("TAM_" + hexc)
        m.use_nodes = True
        rgb = [int(hexc[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
        next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (*lin, 1)
        m.diffuse_color = (*lin, 1)
    return m


FACES = [((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]), ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
         ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]), ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
         ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]), ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)])]


def build():
    scn = bpy.data.scenes.get("TAM_Eagle") or bpy.data.scenes.new("TAM_Eagle")
    bpy.context.window.scene = scn
    for o in list(scn.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    wing = make_wing()
    groups = {
        ("Condor", Vector((0, 0, 0))): make_body(),
        ("CondorWingR", Vector((4, 2, 1))): wing,
        ("CondorWingL", Vector((-4, 2, 1))): {(-x, y, z): c for (x, y, z), c in wing.items()},
    }
    root = bpy.data.objects.new("Condor", None)
    scn.collection.objects.link(root)
    for (name, piv), cells in groups.items():
        bycol = {}
        for k, c in cells.items():
            bycol.setdefault(P[c], []).append(k)
        for n, (hexc, keys) in enumerate(bycol.items()):
            bm = bmesh.new(); vm = {}

            def V(p):
                if p not in vm:
                    vm[p] = bm.verts.new(Vector(p) - Vector((.5, .5, .5)) - piv)
                return vm[p]
            for (x, y, z) in keys:
                for d, q in FACES:
                    if (x + d[0], y + d[1], z + d[2]) not in cells:
                        try:
                            bm.faces.new([V((x + a, y + b, z + c)) for a, b, c in q])
                        except ValueError:
                            pass
            me = bpy.data.meshes.new(f"{name}_{hexc}_{n}")
            bm.to_mesh(me); bm.free()
            me.materials.append(material(hexc))
            ob = bpy.data.objects.new(f"{name}_{hexc}_{n}", me)
            scn.collection.objects.link(ob)
            ob.parent = root
            ob.location = piv
    for o in bpy.context.view_layer.objects:
        o.select_set(o.name.startswith("Condor"))
    bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, object_types={'EMPTY', 'MESH'}, apply_unit_scale=True,
                             apply_scale_options='FBX_SCALE_ALL', axis_forward='-Z', axis_up='Y', bake_anim=False)
    print("export", OUT, os.path.getsize(OUT))


build()

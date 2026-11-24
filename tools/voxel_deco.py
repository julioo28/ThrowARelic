# Petites décorations (bords de chemins, détails du village) — à exécuter dans Blender.
# Réutilise le moteur de tools/voxel_props_v2.py (classe G, export FBX), voxels de 0,25 stud.
# Scène « TAM_Deco », FBX Assets/Props/TAM_Deco.fbx ; install : tools/install_deco.luau
# Chaque prop : Empty <Nom> (origine = centre du pied) + un objet par couleur <Nom>_<RRGGBB>_<n>.
import math

LIB = r"C:\Users\morel\Documents\ThrowARelic\tools\voxel_props_v2.py"
ns = {"__name__": "lib"}
exec(open(LIB, encoding="utf-8").read().replace('"TAM_PropsV2"', '"TAM_Deco"'), ns)
ns["OUT"] = r"C:\Users\morel\Documents\ThrowARelic\Assets\Props\TAM_Deco.fbx"
ns["VOX"] = 0.25
G, hh, mix = ns["G"], ns["hh"], ns["mix"]

STEM = {"G1": "4F7F3A", "G2": "5E8F42", "G3": "77A852"}


def flower(petal, petal2, heart, seed):
    P = dict(STEM, A=petal, B=petal2, C=heart)
    g = G()
    stems = [(0, 0, 6), (2.5, 1, 5), (-2, 2, 4.5), (1, -2.5, 4), (-2.5, -1.5, 5.5), (3, -2, 3.5)]
    for i, (sx, sy, h) in enumerate(stems):
        lean = (hh(i, seed, 0) - .5) * 1.2
        top = (sx + lean, sy + (hh(seed, i, 1) - .5) * 1.2, h)
        g.tube([(sx * .4, sy * .4, 0), top], .55, lambda x, y, z: "G1" if hh(x, y, z, seed) < .5 else "G2")
        # feuilles
        if h > 4:
            g.ell(sx * .6 + .8, sy * .6, 1.8, 1.3, .6, .5, lambda x, y, z: "G3")
        # tête : pétales en croix + coeur
        cx, cy, cz = top
        g.ell(cx, cy, cz + .6, 1.7, 1.7, .6, lambda x, y, z: "A" if hh(x, y, z, seed + 3) < .7 else "B")
        g.put(math.floor(cx), math.floor(cy), math.floor(cz + 1.2), "C")
    return g, P


def pebbles(seed, n, spread, colors):
    P = {"P1": colors[0], "P2": colors[1], "P3": colors[2], "P4": colors[3]}
    g = G()
    for i in range(n):
        a = hh(i, seed, 2) * 2 * math.pi
        r = spread * (.3 + .7 * hh(seed, i, 3))
        rx = 1.2 + 1.6 * hh(i, i, seed)
        ry = rx * (.6 + .5 * hh(seed, seed, i))
        rz = .8 + 1.0 * hh(i, seed, i)
        k = ("P1", "P2", "P3")[i % 3]

        def col(x, y, z, k=k):
            if hh(x, y, z, seed + 9) < .12:
                return "P4"
            return k
        g.ell(math.cos(a) * r, math.sin(a) * r, rz * .5, rx, ry, rz, col, rough=.25, seed=seed + i)
    return g, P


def edge_stone():
    P = {"P1": "A89A85", "P2": "958774", "P3": "BFB29C", "P4": "7D705F"}
    g = G()
    g.ell(0, 0, 1, 3.2, 2.2, 1.9, lambda x, y, z: mix([("P1", .45), ("P2", .35), ("P3", .2)], x, y, z, 7), rough=.3, seed=41)
    g.recolor_surface(lambda x, y, z, k: "P4" if z <= 0 else ("P3" if (x, y, z + 1) not in g.c and hh(x, y, z, 8) < .5 else None))
    return g, P


def grass(colors, seed, blades=16, h=7):
    P = {"G1": colors[0], "G2": colors[1], "G3": colors[2]}
    g = G()
    for i in range(blades):
        a = hh(i, seed, 1) * 2 * math.pi
        r = 2.2 * hh(seed, i, 2)
        bx, by = math.cos(a) * r, math.sin(a) * r
        lean = 1.2 + 1.5 * hh(i, i, seed)
        hz = h * (.55 + .45 * hh(i, seed, 5))
        tip = (bx + math.cos(a) * lean, by + math.sin(a) * lean, hz)
        k = ("G1", "G2", "G3")[i % 3]
        g.tube([(bx, by, 0), (bx + math.cos(a) * lean * .3, by + math.sin(a) * lean * .3, hz * .6), tip], .5,
               lambda x, y, z, k=k: k)
    return g, P


def agave():
    P = {"A1": "6E9A8A", "A2": "5A8475", "A3": "88B0A0", "T": "5A4630", "C": "4C6E60"}
    g = G()
    g.ell(0, 0, 1, 2, 2, 1.5, lambda x, y, z: "C")
    for i in range(11):
        a = i / 11 * 2 * math.pi + hh(i, 1, 1) * .3
        up = 4 + 3 * hh(i, 2, 2)
        L = 5 + 2 * hh(i, 3, 3)
        k = ("A1", "A2", "A3")[i % 3]
        pts = [(0, 0, 1), (math.cos(a) * L * .5, math.sin(a) * L * .5, up * .7), (math.cos(a) * L, math.sin(a) * L, up)]
        g.tube(pts, 1.1, lambda x, y, z, k=k: k, .35)
        g.put(math.floor(math.cos(a) * L), math.floor(math.sin(a) * L), math.floor(up) + 1, "T")
    return g, P


def hay_bale():
    P = {"H1": "D9B85C", "H2": "C9A54A", "H3": "E8CF7E", "T": "8A5A2B"}
    g = G()

    def straw(x, y, z):
        if x in (-3, 2) and (y in (-4, 3) or z in (0, 7)):
            return "T"
        return mix([("H1", .45), ("H2", .3), ("H3", .25)], x, y, z, 11)
    g.box(-6, 5, -4, 3, 0, 7, straw)
    # brins qui dépassent
    for i in range(14):
        x = -6 + int(hh(i, 4, 4) * 12)
        y = -4 + int(hh(i, 5, 5) * 8)
        g.put(x, y, 8, "H3" if i % 2 else "H1")
    return g, P


def bones():
    P = {"B1": "EDE3C4", "B2": "D8CBA6", "B3": "F7F2E2"}
    g = G()
    g.tube([(-4, -1, .6), (4, 1, .6)], .6, lambda x, y, z: "B1")
    for e in ((-4, -1), (4, 1)):
        g.ell(e[0], e[1] - .7, .7, .9, .9, .8, lambda x, y, z: "B3")
        g.ell(e[0], e[1] + .7, .7, .9, .9, .8, lambda x, y, z: "B3")
    g.tube([(-2, 3, .5), (3, 4, .5)], .5, lambda x, y, z: "B2")
    return g, P


ns["PROPS"] = {
    "FlowerRed": lambda: flower("D9483B", "B8322A", "F2B233", 1),
    "FlowerYellow": lambda: flower("F2C744", "E0A92E", "6B4A2B", 2),
    "FlowerPurple": lambda: flower("9B5FC0", "7A45A0", "F2D35A", 3),
    "FlowerWhite": lambda: flower("F4EFE6", "E2DACB", "F2B233", 4),
    "FlowerOrange": lambda: flower("F08A3C", "D96A28", "7A3F1E", 5),
    "Pebbles": lambda: pebbles(21, 5, 4, ("A89A85", "8F8272", "C2B59E", "6F6455")),
    "PebblesRed": lambda: pebbles(33, 4, 3.5, ("B0674A", "93533B", "C98262", "6E3E2C")),
    "EdgeStone": edge_stone,
    "GrassDry": lambda: grass(("C9B46A", "B39C55", "D8C88A"), 5),
    "GrassGreen": lambda: grass(("7FA650", "6A8F3E", "94B866"), 6, 18, 6),
    "Agave": agave,
    "HayBale": hay_bale,
    "Bones": bones,
}


def build(export=True):
    ns["build"](export=export)


if __name__ == "__main__":
    build()

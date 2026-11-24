# Props du décor, version détaillée (v2) — à exécuter dans Blender.
# Scène « TAM_PropsV2 ». 1 voxel = 0,5 m = 0,5 stud (deux fois plus fin que la v1).
# Chaque prop : un Empty <Nom> (origine = centre du pied) et un objet par couleur
# nommé <Nom>_<RRGGBB>_<n> (couleur lue dans le nom à l'install). Tous sous l'Empty TAM_PropsV2.
# Mêmes noms et mêmes dimensions (à ±1 stud) que la v1 pour ne rien casser au placement.
# Export : Assets/Props/TAM_PropsV2.fbx ; install : tools/install_props_v2.luau
import bpy, bmesh, math, os
from mathutils import Vector

OUT = r"C:\Users\morel\Documents\ThrowARelic\Assets\Props\TAM_PropsV2.fbx"
VOX = 0.5


def hh(x, y, z, s=0):
    n = ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (s * 2654435761)) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vn(x, y, z, sc, s=0):
    """bruit de valeur lissé (trilinéaire)"""
    fx, fy, fz = x / sc, y / sc, z / sc
    ix, iy, iz = math.floor(fx), math.floor(fy), math.floor(fz)
    tx, ty, tz = fx - ix, fy - iy, fz - iz
    tx, ty, tz = [t * t * (3 - 2 * t) for t in (tx, ty, tz)]
    def L(a, b, t):
        return a + (b - a) * t
    c = {}
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                c[dx, dy, dz] = hh(ix + dx, iy + dy, iz + dz, s)
    x00 = L(c[0, 0, 0], c[1, 0, 0], tx); x10 = L(c[0, 1, 0], c[1, 1, 0], tx)
    x01 = L(c[0, 0, 1], c[1, 0, 1], tx); x11 = L(c[0, 1, 1], c[1, 1, 1], tx)
    return L(L(x00, x10, ty), L(x01, x11, ty), tz)


class G:
    def __init__(self):
        self.c = {}

    def put(self, x, y, z, k):
        if z >= 0:
            self.c[(x, y, z)] = k

    def get(self, x, y, z):
        return self.c.get((x, y, z))

    def ell(self, cx, cy, cz, rx, ry, rz, f, rough=0.0, seed=0):
        for x in range(math.floor(cx - rx - 1), math.ceil(cx + rx + 2)):
            for y in range(math.floor(cy - ry - 1), math.ceil(cy + ry + 2)):
                for z in range(math.floor(cz - rz - 1), math.ceil(cz + rz + 2)):
                    d = ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 + ((z + .5 - cz) / rz) ** 2
                    lim = 1 + (vn(x, y, z, 2.5, seed) - .5) * rough * 2 if rough else 1
                    if d <= lim:
                        k = f(x, y, z)
                        if k:
                            self.put(x, y, z, k)

    def box(self, x0, x1, y0, y1, z0, z1, f):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    k = f(x, y, z)
                    if k:
                        self.put(x, y, z, k)

    def tube(self, pts, r, f, r2=None):
        r2 = r if r2 is None else r2
        n = len(pts) - 1
        for i in range(n):
            a, b = Vector(pts[i]), Vector(pts[i + 1])
            ra = r + (r2 - r) * i / n
            rb = r + (r2 - r) * (i + 1) / n
            lo = [min(a[j], b[j]) - max(ra, rb) - 1 for j in range(3)]
            hi = [max(a[j], b[j]) + max(ra, rb) + 1 for j in range(3)]
            ab = b - a
            L2 = max(ab.length_squared, 1e-6)
            for x in range(math.floor(lo[0]), math.ceil(hi[0])):
                for y in range(math.floor(lo[1]), math.ceil(hi[1])):
                    for z in range(math.floor(lo[2]), math.ceil(hi[2])):
                        p = Vector((x + .5, y + .5, z + .5))
                        t = max(0, min(1, (p - a).dot(ab) / L2))
                        rr = ra + (rb - ra) * t
                        if (p - (a + ab * t)).length <= rr:
                            k = f(x, y, z)
                            if k:
                                self.put(x, y, z, k)

    def surface(self, x, y, z):
        return any((x + d[0], y + d[1], z + d[2]) not in self.c for d in
                   ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)))

    def recolor_surface(self, f):
        for (x, y, z), k in list(self.c.items()):
            if self.surface(x, y, z):
                nk = f(x, y, z, k)
                if nk:
                    self.c[(x, y, z)] = nk


def mix(keys, x, y, z, s=0):
    r = hh(x, y, z, s)
    acc = 0
    for k, w in keys:
        acc += w
        if r < acc:
            return k
    return keys[-1][0]


# ---------------------------------------------------------------- cactus
def saguaro(tall=False):
    P = {"G1": "4F7F3A", "G2": "5E8F42", "G3": "3B6530", "G4": "77A852", "S": "EDE3C4", "F": "F7F2E2", "Y": "F4C542"}
    g = G()
    R = 3.0 if tall else 2.6
    H = 38 if tall else 31

    def skin(x, y, z):
        return "G2" if hh(x, y, z, 1) < .5 else "G1"
    g.tube([(0, 0, 0), (0, 0, H)], R, skin)
    g.ell(0, 0, H, R, R, 3.2, skin)
    if tall:
        arms = [((0, 0, 13), (-4.5, 0, 13), (-6, 0, 17), (-6, 0, 28)), ((0, 0, 18), (4.5, 0, 18), (6, 0, 22), (6, 0, 33)),
                ((0, 0, 22), (0, 3.5, 23), (0, 4.5, 27), (0, 4.5, 31))]
        ar = 2.0
    else:
        arms = [((0, 0, 11), (-3.8, 0, 11), (-5, 0, 14), (-5, 0, 23)), ((0, 0, 16), (3.8, 0, 16), (5, 0, 19), (5, 0, 26))]
        ar = 1.8
    for a in arms:
        g.tube(list(a), ar, skin)
        g.ell(a[-1][0], a[-1][1], a[-1][2], ar, ar, 2.2, skin)

    # côtes (sillons verticaux), épines, reflets en haut
    def deco(x, y, z, k):
        ang = math.atan2(y + .5, x + .5)
        rib = int(round((ang + math.pi) / (2 * math.pi) * 14)) % 2
        if hh(x, y, z, 5) < .035:
            return "S"
        if rib == 0:
            return "G3"
        if z > H - 4 and hh(x, y, z, 6) < .5:
            return "G4"
        return None
    g.recolor_surface(deco)
    # fleurs blanches au sommet du tronc et des bras
    tops = [(0, 0, H + 3)] + [(a[-1][0], a[-1][1], a[-1][2] + 2) for a in arms]
    for i, (tx, ty, tz) in enumerate(tops):
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            if hh(i, dx, dy, 8) < .75:
                x, y = math.floor(tx) + dx, math.floor(ty) + dy
                g.put(x, y, math.floor(tz), "F")
                if dx == 0 and dy == 0:
                    g.put(x, y, math.floor(tz) + 1, "Y")
    return g, P


def barrel_cactus():
    P = {"G1": "4C7A33", "G2": "5B8C3E", "G3": "3A6128", "S": "E05A8A", "T": "F2D9A0", "Y": "F4C542", "O": "F28C28"}
    g = G()

    def skin(x, y, z):
        return "G1" if hh(x, y, z, 2) < .5 else "G2"
    g.ell(0, 0, 5, 4.6, 4.6, 6.5, skin)

    def deco(x, y, z, k):
        ang = math.atan2(y + .5, x + .5)
        rib = int(round((ang + math.pi) / (2 * math.pi) * 16)) % 2
        if rib == 1:
            return "S" if hh(x, y, z, 3) < .18 else ("T" if hh(x, y, z, 4) < .12 else None)
        return "G3"
    g.recolor_surface(deco)
    # couronne de fleurs
    for i in range(10):
        a = i / 10 * 2 * math.pi
        x, y = math.floor(math.cos(a) * 2.6), math.floor(math.sin(a) * 2.6)
        zt = max(z for (xx, yy, z) in g.c if xx == x and yy == y) if any(xx == x and yy == y for (xx, yy, _) in g.c) else 11
        g.put(x, y, zt + 1, "Y" if i % 2 else "O")
    g.put(0, 0, 12, "Y"); g.put(-1, 0, 12, "O")
    return g, P


def prickly_pear():
    P = {"G1": "5F8F3F", "G2": "6E9E4A", "G3": "4C7A33", "S": "E8DDB0", "R": "C2185B", "R2": "E04A7A", "W": "8A6A3A"}
    g = G()
    # raquettes : (cx, cy, cz, rx, rz, épaisseur dans y, inclinaison)
    pads = [(0, 0, 5, 3.4, 5, 0, 0), (-3.8, 1, 12, 2.8, 4, 1, -.45), (3.6, -1, 11.5, 2.8, 4.2, -1, .4),
            (0.5, 0, 16, 2.6, 3.6, 0, .1), (-6, 2, 17.5, 2, 3, 1, -.6), (5.5, -1, 17, 2, 2.8, -1, .7)]
    for i, (cx, cy, cz, rx, rz, oy, tilt) in enumerate(pads):
        ca, sa = math.cos(tilt), math.sin(tilt)
        for x in range(math.floor(cx - 6), math.ceil(cx + 6)):
            for z in range(math.floor(cz - 6), math.ceil(cz + 6)):
                lx = (x + .5 - cx) * ca - (z + .5 - cz) * sa
                lz = (x + .5 - cx) * sa + (z + .5 - cz) * ca
                d = (lx / rx) ** 2 + (lz / rz) ** 2
                if d <= 1:
                    thick = [0, 1] if d < .55 else [0]
                    for t in thick:
                        y = oy + (t if i % 2 == 0 else -t)
                        k = "G3" if d > .8 else ("G2" if (lz > 0 and hh(x, y, z, i) < .6) else "G1")
                        g.put(x, y, z, k)
    # aréoles en quinconce
    for (x, y, z), k in list(g.c.items()):
        if k != "G3" and (x + 2 * z) % 4 == 0 and z % 2 == 0 and g.surface(x, y, z):
            g.c[(x, y, z)] = "S"
    # pied ligneux
    g.box(-1, 0, 0, 1, 0, 2, lambda x, y, z: "W")
    # figues de barbarie sur le haut des raquettes
    for (fx, fz, oy) in ((-5, 20, 1), (-7, 20, 2), (1, 19, 0), (-0.5, 19.5, 0), (6, 19, -1), (4, 15, -1)):
        x, z = math.floor(fx), math.floor(fz)
        g.put(x, oy, z, "R"); g.put(x, oy, z + 1, "R2")
    return g, P


# ---------------------------------------------------------------- arbres
def juniper(small=False):
    P = {"B1": "6B4A2E", "B2": "5A3D25", "B3": "8C6A48", "F1": "3F5F35", "F2": "4C6B3C", "F3": "56774A", "F4": "6C8C58", "Bl": "6F86A8"}
    g = G()

    def bark(x, y, z):
        return "B3" if (x + y + z // 2) % 3 == 0 and hh(x, y, z, 1) < .7 else ("B1" if hh(x, y, z, 2) < .55 else "B2")
    if small:
        branches = [[(0, 0, 0), (.5, 0, 4), (-1, 1, 7)], [(0, 0, 3), (3, -2, 7)], [(0, 0, 4), (-3, 2, 6)]]
        clumps = [(-1, 1, 9.5, 5, 5, 3.4), (3.5, -2.5, 8.5, 3.5, 3.5, 2.8), (-4, 3, 7.5, 3.4, 3.2, 2.6), (0, -1, 12.5, 3.4, 3.4, 2.4),
                  (2, 3, 10, 3, 3, 2.5)]
        g.tube(branches[0], 1.4, bark, 0.9)
    else:
        branches = [[(0, 0, 0), (1, 0, 5), (-0.5, 1, 9), (1, 0, 12)], [(1, 0, 9), (4, -2, 13)], [(-0.5, 1, 8), (-4, 3, 13)],
                    [(1, 0, 12), (0, -3, 16)]]
        clumps = [(4, -2.5, 15, 3.4, 3.6, 2.6), (-4, 3, 15.5, 3.6, 3.6, 2.8), (0.5, 0, 17.5, 4, 4, 2.6), (-0.5, -3.5, 17.5, 3, 3, 2.2),
                  (2.5, 3, 13, 2.8, 2.8, 2.2), (-2.5, -1, 12.5, 2.6, 2.6, 2)]
        g.tube(branches[0], 1.7, bark, 1.0)
    for b in branches[1:]:
        g.tube(b, 0.9, bark, 0.6)
    # racines
    for a in range(5):
        ang = a / 5 * 2 * math.pi + .4
        g.tube([(0, 0, 1), (math.cos(ang) * 3, math.sin(ang) * 3, 0)], 0.8, bark)

    def leaf(x, y, z):
        if hh(x, y, z, 9) < .08:
            return None  # trous dans le feuillage
        return mix([("F1", .3), ("F2", .35), ("F3", .25), ("F4", .1)], x, y, z, 3)
    for i, (cx, cy, cz, rx, ry, rz) in enumerate(clumps):
        g.ell(cx, cy, cz, rx, ry, rz, leaf, rough=.35, seed=i + 10)

    def deco(x, y, z, k):
        if k.startswith("F"):
            if hh(x, y, z, 11) < .05:
                return "Bl"
            if z > 0 and (x, y, z + 1) not in g.c and hh(x, y, z, 12) < .5:
                return "F4"
        return None
    g.recolor_surface(deco)
    return g, P


def sagebrush():
    P = {"S1": "7D8F6A", "S2": "8FA07A", "S3": "A3B28C", "S4": "B8C4A2", "T": "6B5236", "Y": "D8C25A"}
    g = G()
    for a in range(6):
        ang = a / 6 * 2 * math.pi
        g.tube([(0, 0, 0), (math.cos(ang) * 2, math.sin(ang) * 2, 2.5)], .6, lambda x, y, z: "T")
    clumps = [(0, 0, 3.5, 3, 3, 2.2), (2.6, 1, 2.6, 2.4, 2.4, 2), (-2.4, -1.4, 2.6, 2.4, 2.2, 1.8), (-1, 2.6, 2.4, 2.2, 2, 1.8),
              (1.4, -2.6, 2.2, 2.2, 2, 1.7)]

    def leaf(x, y, z):
        if hh(x, y, z, 4) < .12:
            return None
        return mix([("S1", .3), ("S2", .35), ("S3", .25), ("S4", .1)], x, y, z, 5)
    for i, c in enumerate(clumps):
        g.ell(*c, leaf, rough=.4, seed=20 + i)

    def deco(x, y, z, k):
        if (x, y, z + 1) not in g.c and z >= 4 and hh(x, y, z, 6) < .18:
            return "Y"
        return None
    g.recolor_surface(deco)
    return g, P


def tumbleweed():
    P = {"T1": "9C7A4A", "T2": "B08D5A", "T3": "C7A776", "T4": "7A5C36"}
    g = G()
    import random
    rnd = random.Random(7)
    cz = 5.0
    for i in range(46):
        # brins = arcs aléatoires sur deux coquilles
        rad = rnd.choice((4.6, 3.6, 2.6))
        a0, b0 = rnd.uniform(0, 2 * math.pi), rnd.uniform(-1.2, 1.2)
        da, db = rnd.uniform(-1.4, 1.4), rnd.uniform(-1, 1)
        pts = []
        for s in range(7):
            a, b = a0 + da * s / 6, b0 + db * s / 6
            pts.append((math.cos(a) * math.cos(b) * rad, math.sin(a) * math.cos(b) * rad * .9, cz + math.sin(b) * rad * .95))
        k = rnd.choice(("T1", "T2", "T2", "T3", "T4"))
        g.tube(pts, .45, lambda x, y, z, k=k: k)
    return g, P


# ---------------------------------------------------------------- rochers
def boulder(big=True):
    P = {"R1": "8B4426", "R2": "A0522D", "R3": "B5652F", "R4": "C27A45", "R5": "D69A63", "K": "5E2E1A", "L": "C9B458", "L2": "8FA060"}
    g = G()

    def strata(x, y, z):
        band = (z + int(vn(x, y, 0, 4, 3) * 3)) // 2 % 4
        base = ("R2", "R3", "R1", "R4")[band]
        if hh(x, y, z, 1) < .15:
            base = "R3" if base != "R3" else "R2"
        return base
    if big:
        g.ell(0, 0, 3.5, 7, 6.6, 6.5, strata, rough=.28, seed=31)
        g.ell(3, -2, 2, 4, 4, 3.5, strata, rough=.25, seed=32)
    else:
        g.ell(0, 0, 2.5, 5, 3.8, 4, strata, rough=.28, seed=33)
        g.ell(-2.5, 1.5, 6.5, 2.4, 2.2, 1.6, strata, rough=.2, seed=34)

    def deco(x, y, z, k):
        top = (x, y, z + 1) not in g.c
        if hh(x, y, z, 7) < .025 and z > 1:
            return "K"  # fissures
        if top and vn(x, y, z, 3, 8) > .8:
            return "L" if hh(x, y, z, 9) < .6 else "L2"  # lichen
        if top and hh(x, y, z, 10) < .3:
            return "R5"  # haut éclairé, poli par le vent
        return None
    g.recolor_surface(deco)
    return g, P


# ---------------------------------------------------------------- Far West
def barrel():
    P = {"W1": "8B5A2B", "W2": "7A4A22", "W3": "9E6B36", "J": "4E3018", "M": "3A3A3A", "M2": "6E6E74", "H": "2A1A10"}
    g = G()
    for z in range(0, 10):
        r = 3.3 + 0.7 * math.sin(math.pi * (z + .5) / 10)
        for x in range(-5, 5):
            for y in range(-5, 5):
                d = math.hypot(x + .5, y + .5)
                if d <= r:
                    ang = math.atan2(y + .5, x + .5)
                    stave = int((ang + math.pi) / (2 * math.pi) * 12)
                    edge = abs(((ang + math.pi) / (2 * math.pi) * 12) - round((ang + math.pi) / (2 * math.pi) * 12)) < .08
                    if z in (1, 2, 7, 8):
                        k = "M" if not (stave % 3 == 0 and z in (1, 8) and d > r - 1) else "M2"
                    elif edge and d > r - 1:
                        k = "J"
                    else:
                        k = ("W1", "W2", "W3")[stave % 3]
                    if z == 9 and d < r - 1:
                        k = "W2" if (x // 2) % 2 else "W1"  # couvercle en planches
                    g.put(x, y, z, k)
    g.c.pop((0, 0, 9), None); g.put(0, 0, 9, "H")  # bonde
    g.put(1, 1, 9, "J")
    return g, P


def crate():
    P = {"W1": "A87843", "W2": "8E6332", "W3": "C08E55", "F": "6E4A26", "N": "3A3A3A", "S": "5A3A1E"}
    g = G()

    def f(x, y, z):
        ex = (x in (0, 7)) + (y in (0, 7)) + (z in (0, 7))
        if ex >= 2:
            return "F"  # cadre
        if ex == 1:
            # diagonale de renfort sur chaque face
            if (x in (0, 7) and abs(y - z) <= 0) or (y in (0, 7) and abs(x - z) <= 0) or (z == 7 and abs(x - y) <= 0):
                return "F"
            row = z if z not in (0, 7) else x
            if row % 2 == 0 and hh(x, y, z, 2) < .5:
                return "S"  # joints entre planches
            return ("W1", "W2", "W3")[(row // 2 + hh(x, y, z, 3) > .8) % 3]
        return "W2"
    g.box(0, 7, 0, 7, 0, 7, f)
    for x in (0, 7):
        for y in (0, 7):
            for z in (1, 6):
                g.c[(x, y, z)] = "N"
    return g, P


def wheel(g, cx, cz, r, y0, y1, spokes=8):
    for y in range(y0, y1 + 1):
        for x in range(math.floor(cx - r - 1), math.ceil(cx + r + 1)):
            for z in range(0, math.ceil(cz + r + 1)):
                d = math.hypot(x + .5 - cx, z + .5 - cz)
                if r - 1.1 <= d <= r:
                    g.put(x, y, z, "M")
                elif r - 2 <= d < r - 1.1:
                    g.put(x, y, z, "W2")
                elif d < 1.2:
                    g.put(x, y, z, "M2")
                elif d < r - 2:
                    a = math.atan2(z + .5 - cz, x + .5 - cx)
                    s = (a / (2 * math.pi) * spokes) % 1
                    if s < .22 or s > .88:
                        g.put(x, y, z, "W1")


def wagon():
    P = {"W1": "8B5A2B", "W2": "6E4A26", "W3": "A06A38", "D": "4A3020", "M": "3A3A3A", "M2": "6E6E74", "C1": "EDE3CF", "C2": "D8CDB5",
         "C3": "C4B79C", "R": "A8322A"}
    g = G()
    # Blender : x = largeur, y = longueur (avant = +y), z = haut
    # roues (axe x), arrière plus grandes
    for side, (y0, y1) in ((-1, (-7, -6)), (1, (6, 7))):
        pass
    for wy, r in ((-6.5, 5.2), (7.5, 4.2)):
        for side in (-1, 1):
            # roue verticale dans le plan y-z : on la construit en échangeant les axes
            tmp = G()
            wheel(tmp, 0, r, r, 0, 0)
            for (a, _, z), k in tmp.c.items():
                g.put(side * 7 if side > 0 else -7, math.floor(wy) + a, z, k)
                g.put(side * 6 if side > 0 else -6, math.floor(wy) + a, z, k) if k == "M2" else None
    # essieux
    for wy, r in ((-6.5, 5.2), (7.5, 4.2)):
        g.box(-6, 5, math.floor(wy), math.floor(wy), math.floor(r), math.floor(r), lambda x, y, z: "D")
    # caisse
    def bed(x, y, z):
        side = x in (-5, 4) or y in (-10, 8)
        if z == 4 or z == 8:
            return "D"
        if side:
            return "W3" if z % 2 else "W1"
        if z == 5:
            return "W2"
        return None
    g.box(-5, 4, -10, 8, 4, 8, bed)
    # bâche sur arceaux
    for y in range(-9, 8):
        hoop = y in (-9, -4, 1, 6)
        for x in range(-7, 7):
            for z in range(8, 17):
                d = math.hypot((x + .5) / 6.4, (z + .5 - 8) / 8.6)
                if .86 <= d <= 1.0:
                    k = "C3" if hoop else ("C1" if hh(x, y, z, 2) < .7 else "C2")
                    if x + .5 > 3 and not hoop:
                        k = "C2"  # côté à l'ombre
                    g.put(x, y, z, k)
    # tissu froncé aux extrémités
    for y in (-10, 8):
        for x in range(-6, 6):
            for z in range(9, 16):
                d = math.hypot((x + .5) / 6.2, (z + .5 - 8) / 8.2)
                if .78 <= d <= 1.0:
                    g.put(x, y, z, "C3")
    # siège + timon + tonneau d'eau
    g.box(-4, 3, 6, 7, 9, 9, lambda x, y, z: "W2")
    g.box(-4, 3, 7, 7, 10, 11, lambda x, y, z: "W1")
    g.tube([(0, 9, 4), (0, 14, 3), (0, 15.5, 3)], .6, lambda x, y, z: "D")
    g.box(-2, 1, 14, 14, 3, 3, lambda x, y, z: "D")
    for z in range(5, 8):
        for y in range(-3, 0):
            g.put(-6, y, z, "R" if z == 6 else "W2")
    return g, P


def minecart():
    P = {"M1": "4A4A50", "M2": "6E6E74", "M3": "2E2E2E", "Ru": "8A4A2A", "Ri": "A8A8B0", "Au": "F2C14E", "Au2": "FFE38A", "St": "6A5E54"}
    g = G()
    # x = longueur, y = largeur, z = haut
    for z in range(3, 11):
        t = (z - 3) / 7
        hx, hy = 4.5 + 1.5 * t, 3.5 + 1.2 * t
        for x in range(-7, 7):
            for y in range(-6, 6):
                ax, ay = abs(x + .5), abs(y + .5)
                if ax <= hx and ay <= hy:
                    wall = ax > hx - 1 or ay > hy - 1 or z == 3
                    if not wall and z > 3:
                        continue
                    k = "M1"
                    if z in (9, 10):
                        k = "M2"
                    if z == 6:
                        k = "M3"
                    if (x + y) % 3 == 0 and z in (4, 8) and wall:
                        k = "Ri"
                    if vn(x, y, z, 2.5, 4) > .7 and z not in (9, 10):
                        k = "Ru"
                    g.put(x, y, z, k)
    # chargement : minerai et pépites d'or
    def ore(x, y, z):
        r = hh(x, y, z, 6)
        return "Au2" if r < .12 else ("Au" if r < .45 else "St")
    g.ell(0, 0, 9.5, 4.6, 3.6, 2.6, ore, rough=.5, seed=41)
    # roues (axe y), 4 roues
    for wx in (-3.5, 2.5):
        for wy in (-5, 4):
            for x in range(-3, 3):
                for z in range(0, 5):
                    d = math.hypot(x + .5, z + .5 - 2.2)
                    if d <= 2.2:
                        g.put(math.floor(wx) + x + 1, wy, z, "M3" if d > 1.4 else ("Ri" if d < .8 else "M1"))
    g.box(-6, 5, -4, 3, 2, 2, lambda x, y, z: "M3")
    return g, P


def signpost():
    P = {"W1": "A06A38", "W2": "B07A45", "W3": "7A5230", "D": "4A2E1A", "T": "2E1E12", "N": "6E6E74", "St": "8B7A6A"}
    g = G()

    def post(x, y, z):
        return "W3" if (z % 3 == 0 and x == 0) else ("D" if hh(x, y, z, 1) < .3 else "W3")
    g.box(-1, 0, 0, 1, 0, 15, post)
    g.box(-2, 1, 0, 1, 16, 16, lambda x, y, z: "D")
    # planches-flèches (y = 2 vox d'épaisseur, x = sens)
    boards = [(13, 1, 7, 0), (9, -1, 7, 1), (5, 1, 6, 2)]
    for zc, d, L, i in boards:
        for s in range(L):
            x = (1 + s) if d > 0 else (-2 - s)
            tip = L - s
            hz = 1 if tip > 1 else 0  # pointe de flèche
            for dz in range(-hz, hz + 1):
                for y in (0, 1):
                    k = "W1" if (i % 2 == 0) else "W2"
                    if abs(dz) == hz or s == 0:
                        k = "W3"
                    elif y == 0 and dz == 0 and 1 <= s <= L - 3 and hh(s, dz, i, 2) < .6:
                        k = "T"  # lettres peintes
                    g.put(x, y if d > 0 else y, zc + dz, k)
        g.put((2 if d > 0 else -3), 0, zc, "N"); g.put((2 if d > 0 else -3), 1, zc, "N")
    # cailloux au pied
    for i, (x, y) in enumerate(((-3, 2), (2, -2), (3, 2), (-3, -2))):
        g.put(x, y, 0, "St")
        if i % 2:
            g.put(x + 1, y, 0, "St")
    return g, P


def cow_skull():
    P = {"B1": "EEE6D4", "B2": "E2D8C2", "B3": "D8CDB5", "H1": "C9B48A", "H2": "8A7556", "K": "2A2420", "K2": "4A3E34"}
    g = G()

    def bone(x, y, z):
        return mix([("B1", .5), ("B2", .35), ("B3", .15)], x, y, z, 1)
    # crâne (arrière, y négatif) + museau vers +y, posé au sol
    g.ell(0, -2, 3.2, 4, 3.6, 3.2, bone)
    g.tube([(0, -1, 3.2), (0, 3, 2.4), (0, 5.5, 1.8)], 2.6, bone, 1.6)
    # orbites
    for sx in (-1, 1):
        g.ell(sx * 2.4, 0.2, 5.2, 1.3, 1.2, 1.1, lambda x, y, z: "K")
    # narines + fente nasale
    for x in (-1, 0):
        g.put(x, 6, 2, "K"); g.put(x, 6, 3, "K2")
    g.box(-1, 0, 2, 5, 5, 5, lambda x, y, z: "K2" if (y % 2 == 0) else None)
    # dents
    for x in (-2, -1, 0, 1):
        g.put(x, 6, 0, "B3")
    # cornes : partent des côtés, s'écartent puis remontent vers l'avant
    for sx in (-1, 1):
        pts = [(sx * 3.5, -2.5, 5), (sx * 6, -3, 5.5), (sx * 8, -2.5, 6.5), (sx * 8.6, -1.5, 8.5)]

        def horn(x, y, z, sx=sx):
            t = abs(x + .5) / 9
            return "H2" if t > .85 else ("H1" if t > .4 else "B3")
        g.tube(pts, 1.4, horn, .5)
    # fissures
    for (x, y, z) in ((1, -4, 6), (2, -3, 6), (-1, -1, 6)):
        if (x, y, z) in g.c:
            g.c[(x, y, z)] = "K2"
    return g, P


PROPS = {
    "Saguaro": lambda: saguaro(False), "SaguaroTall": lambda: saguaro(True), "BarrelCactus": barrel_cactus,
    "PricklyPear": prickly_pear, "Juniper": lambda: juniper(False), "JuniperSmall": lambda: juniper(True),
    "Sagebrush": sagebrush, "Tumbleweed": tumbleweed, "BoulderA": lambda: boulder(True), "BoulderB": lambda: boulder(False),
    "Barrel": barrel, "Crate": crate, "Wagon": wagon, "MineCart": minecart, "Signpost": signpost, "CowSkull": cow_skull,
}

FACES = [((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]), ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
         ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]), ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
         ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]), ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)])]


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


def build(names=None, export=True):
    scn = bpy.data.scenes.get("TAM_PropsV2") or bpy.data.scenes.new("TAM_PropsV2")
    bpy.context.window.scene = scn
    for o in list(scn.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    root = bpy.data.objects.new("TAM_PropsV2", None)
    scn.collection.objects.link(root)
    report = []
    offset = 0
    for name, fn in PROPS.items():
        if names and name not in names:
            continue
        g, P = fn()
        cells = g.c
        xs = [k[0] for k in cells]; ys = [k[1] for k in cells]
        cx = (min(xs) + max(xs) + 1) / 2; cy = (min(ys) + max(ys) + 1) / 2
        w = (max(xs) - min(xs) + 1) * VOX
        empty = bpy.data.objects.new(name, None)
        scn.collection.objects.link(empty)
        empty.parent = root
        empty.location = (offset + w / 2, 0, 0)
        offset += w + 4
        bycol = {}
        for k, c in cells.items():
            bycol.setdefault(P[c], []).append(k)
        tris = 0
        for n, (hexc, keys) in enumerate(sorted(bycol.items())):
            bm = bmesh.new(); vm = {}

            def V(p):
                if p not in vm:
                    vm[p] = bm.verts.new(Vector(((p[0] - cx) * VOX, (p[1] - cy) * VOX, p[2] * VOX)))
                return vm[p]
            for (x, y, z) in keys:
                for d, q in FACES:
                    if (x + d[0], y + d[1], z + d[2]) not in cells:
                        try:
                            bm.faces.new([V((x + a, y + b, z + c)) for a, b, c in q])
                        except ValueError:
                            pass
            tris += len(bm.faces) * 2
            me = bpy.data.meshes.new(f"{name}_{hexc}_{n}")
            bm.to_mesh(me); bm.free()
            me.materials.append(material(hexc))
            ob = bpy.data.objects.new(f"{name}_{hexc}_{n}", me)
            scn.collection.objects.link(ob)
            ob.parent = empty
        zs = [k[2] for k in cells]
        report.append(f"{name}: {len(cells)} vox, {len(bycol)} couleurs, {tris} tri, "
                      f"{(max(xs)-min(xs)+1)*VOX:.1f} x {(max(ys)-min(ys)+1)*VOX:.1f} x {(max(zs)+1)*VOX:.1f} studs (l x p x h)")
    if export:
        for o in scn.objects:
            o.select_set(True)
        bpy.context.view_layer.objects.active = root
        bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, object_types={'EMPTY', 'MESH'}, apply_unit_scale=True,
                                 apply_scale_options='FBX_SCALE_ALL', axis_forward='-Z', axis_up='Y', bake_anim=False)
        report.append(f"export {OUT} {os.path.getsize(OUT)} octets")
    print("\n".join(report))


if __name__ == "__main__":
    build()

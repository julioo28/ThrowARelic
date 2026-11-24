"""
Générateur de modèles voxel des trouvailles (exécuté dans Blender).

Lit Assets/Relics/catalog.json, construit un modèle par objet (forme « shape »,
couleurs de l'objet, ornements selon la rareté), puis exporte des FBX par lots.
Chaque objet = un Empty nommé <id> avec un mesh par couleur nommé <id>_<RRGGBB>_<n>
(Roblox relit la couleur dans le nom). Les couleurs d'accent des raretés
Mythique et plus sont rendues en Neon côté Roblox.

Utilisation dans Blender :
    exec(open(r"...\\tools\\voxel_relics.py", encoding="utf-8").read(), ns)
    ns["build_all"](start, end)   # construit une tranche du catalogue
    ns["export_batches"](size)    # FBX dans Assets/Relics/
"""
import bpy, bmesh, json, math, random, os, hashlib, zlib

ROOT = r"C:\Users\morel\Documents\ThrowARelic"
CATALOG = os.path.join(ROOT, "Assets", "Relics", "catalog.json")
OUT_DIR = os.path.join(ROOT, "Assets", "Props", "Relics")
SCENE = "TAR_Relics"
RARITY_TIER = {"Commun": 0, "PeuCommun": 1, "Rare": 2, "Epique": 3, "Legendaire": 4, "Mythique": 5, "Secret": 6, "Divin": 7, "Cosmique": 8}

# ---------------------------------------------------------------- couleurs
def rgb(h):
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]

def hx(c):
    return "%02X%02X%02X" % tuple(max(0, min(255, round(v))) for v in c)

def mix(a, b, t):
    ca, cb = rgb(a), rgb(b)
    return hx([x + (y - x) * t for x, y in zip(ca, cb)])

def palette(item):
    main = item["color"].upper()
    tier = RARITY_TIER[item["rarity"]]
    accent = item["accent"].upper()
    if tier <= 1:
        accent = mix(main, "000000", 0.45)
    metal = "F2C14E" if tier >= 3 or item["material"] == "gold" else ("C8CCD6" if tier == 2 or item["material"] == "silver" else "70757D")
    return {"main": main, "light": mix(main, "FFFFFF", 0.35), "dark": mix(main, "000000", 0.38),
            "deep": mix(main, "000000", 0.6), "accent": accent, "metal": metal, "metaldark": mix(metal, "000000", 0.35),
            "white": "F4F0E6", "ink": "2A2420", "tier": tier}

# ---------------------------------------------------------------- primitives
class V(dict):
    def put(self, x, y, z, c):
        self[(int(round(x)), int(round(y)), int(round(z)))] = c

    def box(self, x0, y0, z0, x1, y1, z1, c):
        for x in range(int(x0), int(x1) + 1):
            for y in range(int(y0), int(y1) + 1):
                for z in range(int(z0), int(z1) + 1):
                    self[(x, y, z)] = c

    def ellipsoid(self, cx, cy, cz, rx, ry, rz, c, shell=None, cut=None):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
                for z in range(int(cz - rz) - 1, int(cz + rz) + 2):
                    d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2
                    if d <= 1.05 and (cut is None or cut(x, y, z)):
                        if shell is None or d >= shell:
                            self[(x, y, z)] = c if not callable(c) else c(x, y, z)

    def cyl(self, cx, cy, z0, z1, r, c, hollow=0):
        for z in range(int(z0), int(z1) + 1):
            rr = r(z) if callable(r) else r
            R = int(math.ceil(rr))
            for x in range(-R, R + 1):
                for y in range(-R, R + 1):
                    d = math.hypot(x, y)
                    if d <= rr + 0.35 and d >= hollow:
                        self[(cx + x, cy + y, z)] = c if not callable(c) else c(x, y, z)

    def disc_y(self, cx, cz, r, y0, y1, c, inner=0):
        """disque vertical (face vers -Y = vers la caméra de Roblox après export)"""
        R = int(math.ceil(r))
        for x in range(-R, R + 1):
            for z in range(-R, R + 1):
                d = math.hypot(x, z)
                if d <= r + 0.35 and d >= inner:
                    for y in range(y0, y1 + 1):
                        self[(cx + x, y, cz + z)] = c if not callable(c) else c(x, y, z)

    def line(self, a, b, c, thick=0):
        n = int(max(abs(b[i] - a[i]) for i in range(3))) + 1
        for i in range(n + 1):
            t = i / max(1, n)
            p = [a[k] + (b[k] - a[k]) * t for k in range(3)]
            for dx in range(-thick, thick + 1):
                for dy in range(-thick, thick + 1):
                    self.put(p[0] + dx, p[1] + dy, p[2], c)

# ---------------------------------------------------------------- formes
def f_helmet(v, p, r):
    rad = 4 + r.randint(0, 1)
    v.ellipsoid(0, 0, 2, rad, rad, rad + 0.5, p["main"], cut=lambda x, y, z: z >= 2)
    v.cyl(0, 0, 1, 2, rad + 0.8, p["dark"])
    v.box(-2, -rad - 1, 3, 2, -rad, 3, p["ink"])  # fente du visage
    if r.random() < 0.45 or p["tier"] >= 4:
        for side in (-1, 1):  # cornes
            for i in range(4):
                v.put(side * (rad + i), 0, 4 + i, p["white"] if p["tier"] < 4 else p["metal"])
    if p["tier"] >= 2:
        v.box(0, -1, 2 + rad, 0, 1, 4 + rad, p["accent"])  # crête
    if p["tier"] >= 3:
        v.cyl(0, 0, 2, 2, rad + 0.9, p["metal"], hollow=rad + 0.2)

def f_crown(v, p, r):
    rad = 4
    v.cyl(0, 0, 0, 2, rad, p["main"], hollow=rad - 1)
    v.cyl(0, 0, 0, 0, rad + 0.3, p["dark"], hollow=rad - 0.5)
    points = 5 + (p["tier"] >= 4)
    for i in range(points):
        a = i / points * math.tau
        x, y = round(math.cos(a) * rad), round(math.sin(a) * rad)
        for z in range(3, 6):
            v.put(x, y, z, p["main"])
        v.put(x, y, 6, p["accent"])
        v.put(round(math.cos(a + 0.3) * rad), round(math.sin(a + 0.3) * rad), 1, p["accent"] if p["tier"] >= 2 else p["light"])

def f_skull(v, p, r):
    v.ellipsoid(0, 0, 5, 4, 4, 4, p["main"])
    v.box(-2, -3, 0, 2, 1, 2, p["main"])
    for sx in (-2, 1):
        v.box(sx, -4, 5, sx + 1, -3, 6, p["ink"])
    v.put(0, -4, 3, p["ink"]); v.put(-1, -3, 1, p["ink"]); v.put(1, -3, 1, p["ink"])
    if p["tier"] >= 3:
        v.cyl(0, 0, 8, 8, 2.5, p["metal"])
    if p["tier"] >= 5:
        for sx in (-2, 1):
            v.box(sx, -4, 5, sx + 1, -4, 6, p["accent"])

def f_sword(v, p, r):
    length = 9 + r.randint(0, 3)
    v.box(0, 0, 4, 0, 1, 4 + length, p["light"])
    v.box(1, 0, 4, 1, 1, 3 + length, p["main"])
    v.box(0, 0, 5 + length, 1, 1, 5 + length, p["light"])
    v.box(-3, 0, 3, 4, 1, 3, p["metal"])
    v.box(0, 0, 0, 1, 1, 2, p["deep"])
    v.box(0, 0, -1, 1, 1, -1, p["accent"])

def f_axe(v, p, r):
    v.box(0, 0, 0, 0, 0, 12, "7A5230")
    for z in range(7, 13):
        w = 4 - abs(z - 10) // 2
        v.box(1, 0, z, w, 0, z, p["main"])
        v.put(w + 1, 0, z, p["light"])
    if r.random() < 0.5 or p["tier"] >= 4:
        for z in range(8, 12):
            v.box(-3 + abs(z - 10) // 2, 0, z, -1, 0, z, p["main"])
    v.put(0, 0, 13, p["accent"])

def f_hammer(v, p, r):
    v.box(0, 0, 0, 0, 0, 9, "6B4A2E")
    v.box(-3, -1, 9, 3, 1, 12, p["main"])
    v.box(-3, -1, 9, -3, 1, 12, p["dark"]); v.box(3, -1, 9, 3, 1, 12, p["dark"])
    if p["tier"] >= 2:
        v.box(-1, -2, 10, 1, -2, 11, p["accent"])

def f_pickaxe(v, p, r):
    v.box(0, 0, 0, 0, 0, 11, "7A5230")
    for i in range(-5, 6):
        z = 11 - (abs(i) ** 2) // 8
        v.put(i, 0, z, p["main"]); v.put(i, 0, z + 1, p["main"] if abs(i) < 4 else p["light"])
    v.put(0, 0, 12, p["accent"])

def f_staff(v, p, r):
    h = 12 + r.randint(0, 2)
    v.box(0, 0, 0, 0, 0, h, p["dark"] if p["tier"] < 3 else p["metal"])
    kind = r.choice(["orb", "prong", "crystal"])
    if kind == "orb":
        v.ellipsoid(0, 0, h + 2, 1.8, 1.8, 1.8, p["accent"])
        v.cyl(0, 0, h, h, 1.6, p["main"])
    elif kind == "prong":
        for x in (-2, 0, 2):
            v.box(x, 0, h + 1, x, 0, h + 4 - abs(x) // 2, p["main"])
        v.box(-2, 0, h, 2, 0, h, p["main"])
        v.put(0, 0, h + 5, p["accent"])
    else:
        for z in range(4):
            w = 1 if z in (1, 2) else 0
            v.box(-w, -w, h + 1 + z, w, w, h + 1 + z, p["accent"] if z % 2 else p["light"])
    v.box(0, 0, h // 2, 0, 0, h // 2, p["main"])

def f_shield(v, p, r):
    rad = 5
    v.disc_y(0, 6, rad, 0, 0, p["main"])
    v.disc_y(0, 6, rad + 0.3, 0, 0, p["metal"], inner=rad - 0.5)
    v.disc_y(0, 6, 1.4, -1, -1, p["accent"] if p["tier"] >= 1 else p["metaldark"])
    if r.random() < 0.5:
        v.box(-rad + 1, -1, 6, rad - 1, -1, 6, p["dark"])
    else:
        v.box(0, -1, 2, 0, -1, 10, p["dark"])

def f_coin(v, p, r):
    rad = 4 + (p["tier"] >= 4)
    v.disc_y(0, rad, rad, 0, 1, p["main"])
    v.disc_y(0, rad, rad + 0.3, -1, -1, p["light"], inner=rad - 0.6)
    v.disc_y(0, rad, 1.8, -1, -1, p["accent"] if p["tier"] >= 1 else p["dark"])
    if r.random() < 0.5:
        v.box(0, 2, 2 * rad, 0, 2, 2 * rad + 1, p["metal"])  # bélière

def f_orb(v, p, r):
    rad = 3.5 + r.random()
    v.ellipsoid(0, 0, rad + 1, rad, rad, rad, lambda x, y, z: p["light"] if (x + y + z) % 3 == 0 else p["main"])
    v.put(-1, -round(rad), round(rad) + 2, "FFFFFF")
    if p["tier"] >= 2:
        v.cyl(0, 0, 0, 0, 2, p["metal"])
    if p["tier"] >= 5:
        v.ellipsoid(0, 0, rad + 1, 1.6, 1.6, 1.6, p["accent"])

def f_egg(v, p, r):
    v.ellipsoid(0, 0, 5, 3.4, 3.4, 5, p["main"])
    for _ in range(4 + p["tier"]):
        a, z = r.random() * math.tau, r.randint(2, 8)
        rr = 3.4 * math.sqrt(max(0, 1 - ((z - 5) / 5) ** 2))
        v.put(math.cos(a) * rr, math.sin(a) * rr, z, p["accent"] if p["tier"] >= 1 else p["dark"])

def f_gem(v, p, r):
    h = 1.5 + r.random() * 0.4
    for x in range(-4, 5):
        for y in range(-4, 5):
            for z in range(-7, 8):
                if abs(x) + abs(y) + abs(z) / h <= 4.2:
                    v.put(x, y, z + 7, p["light"] if (x + z) % 2 == 0 else p["main"])
    if r.random() < 0.5:  # petits cristaux voisins
        for (x, y) in [(4, 2), (-3, -3)]:
            v.box(x, y, 0, x, y, 3, p["dark"])
            v.put(x, y, 4, p["light"])

def f_bottle(v, p, r):
    v.cyl(0, 0, 0, 6, 3, p["light"])
    v.cyl(0, 0, 1, 4, 2.2, p["accent"] if p["tier"] >= 1 else p["main"])
    v.cyl(0, 0, 7, 9, 1, p["light"])
    v.cyl(0, 0, 10, 10, 1.2, "7A5230")
    v.box(-1, -3, 2, 1, -3, 4, p["white"])  # étiquette

def f_vase(v, p, r):
    k = r.random()
    v.cyl(0, 0, 0, 10, lambda z: 2.2 + 1.8 * math.sin(z / 10 * math.pi) * (1.0 + 0.2 * k), p["main"])
    v.cyl(0, 0, 3, 4, 3.9, p["dark"])
    if p["tier"] >= 2:
        v.cyl(0, 0, 6, 6, 3.6, p["accent"])
    if r.random() < 0.5:
        for side in (-1, 1):
            v.box(side * 4, 0, 6, side * 4, 0, 9, p["main"])

def f_lantern(v, p, r):
    for x in (-2, 2):
        for y in (-2, 2):
            v.box(x, y, 0, x, y, 7, p["dark"])
    v.box(-2, -2, 0, 2, 2, 0, p["dark"]); v.box(-2, -2, 7, 2, 2, 7, p["dark"])
    v.box(-1, -1, 1, 1, 1, 6, p["accent"] if p["tier"] >= 1 else "FFCF7A")
    v.box(-1, 0, 8, 1, 0, 8, p["dark"]); v.box(0, 0, 9, 0, 0, 9, p["dark"])

def f_candle(v, p, r):
    v.cyl(0, 0, 0, 1, 3.5, p["metal"] if p["tier"] >= 2 else p["dark"])
    h = 5 + r.randint(0, 3)
    v.cyl(0, 0, 2, 2 + h, 1.4, p["main"] if p["main"] != "202020" else "3A3A3A")
    v.put(0, 0, 3 + h, "FFB347"); v.put(0, 0, 4 + h, "FFE27A")

def f_book(v, p, r):
    v.box(0, 0, 0, 6, 2, 8, p["main"])
    v.box(1, 1, 1, 6, 1, 7, p["white"])
    v.box(0, 0, 0, 0, 2, 8, p["dark"])
    v.box(2, -1, 3, 4, -1, 5, p["accent"] if p["tier"] >= 1 else p["dark"])
    if p["tier"] >= 3:
        for z in (0, 8):
            v.box(5, 0, z, 6, 2, z, p["metal"])

def f_chest(v, p, r):
    v.box(-4, -3, 0, 4, 3, 4, p["main"])
    v.box(-4, -3, 5, 4, 3, 6, p["dark"])
    for x in (-3, 3):
        v.box(x, -3, 0, x, 3, 6, p["metal"])
    v.box(-1, -4, 3, 1, -4, 5, p["accent"] if p["tier"] >= 1 else p["metaldark"])

def f_mask(v, p, r):
    for x in range(-4, 5):
        for z in range(0, 11):
            if (x / 4.5) ** 2 + ((z - 5) / 5.5) ** 2 <= 1:
                v.put(x, 0, z, p["main"])
    for sx in (-2, 1):
        v.box(sx, -1, 6, sx + 1, 1, 7, p["ink"])
    v.box(-1, -1, 2, 1, 0, 2, p["dark"])
    if p["tier"] >= 1:
        v.box(-4, -1, 8, 4, -1, 8, p["accent"])
    if p["tier"] >= 4:
        for x in range(-4, 5, 2):
            v.put(x, 0, 11, p["metal"])

def f_feather(v, p, r):
    v.line((0, 0, 0), (2, 0, 13), p["white"] if p["main"] != "FFFFFF" else "D8D0C0")
    for z in range(2, 13):
        w = int(3 * math.sin((z - 1) / 12 * math.pi)) + 1
        cx = 2 * z / 13
        for dx in range(-w, w + 1):
            if dx != 0:
                v.put(cx + dx, 0, z, p["main"] if abs(dx) < w else p["light"])
    if p["tier"] >= 2:
        v.put(2, 0, 11, p["accent"]); v.put(1, 0, 8, p["accent"])

def f_fang(v, p, r):
    for z in range(0, 12):
        t = z / 12
        rr = 2.2 * (1 - t) + 0.4
        cx = 3 * t * t
        v.cyl(round(cx), 0, z, z, rr, p["main"] if z % 4 else p["light"])
    v.cyl(0, 0, 0, 0, 2.6, p["dark"])
    if p["tier"] >= 3:
        v.cyl(0, 0, 1, 1, 2.6, p["metal"])

def f_shell(v, p, r):
    for i in range(7):
        a = i * 0.9
        rr = 4.2 - i * 0.5
        cx, cz = math.cos(a) * (3 - i * 0.35), 4 + math.sin(a) * (3 - i * 0.35)
        v.ellipsoid(cx, 0, cz, max(1, rr * 0.7), max(1, rr * 0.6), max(1, rr * 0.7), p["main"] if i % 2 else p["light"])
    if p["tier"] >= 2:
        v.put(0, -3, 4, p["accent"])

def f_mushroom(v, p, r):
    v.cyl(0, 0, 0, 5, 1.6, p["white"])
    v.ellipsoid(0, 0, 6, 4.5, 4.5, 3, p["main"], cut=lambda x, y, z: z >= 6)
    for _ in range(5):
        a = r.random() * math.tau
        v.put(math.cos(a) * 3, math.sin(a) * 3, 8, p["white"] if p["tier"] < 2 else p["accent"])

def f_idol(v, p, r):
    v.box(-3, -2, 0, 3, 2, 1, p["dark"])
    v.box(-2, -1, 2, 2, 1, 7, p["main"])
    v.box(-2, -2, 8, 2, 2, 11, p["main"])
    for sx in (-1, 1):
        v.put(sx, -3, 10, p["accent"] if p["tier"] >= 1 else p["ink"])
    v.box(-3, 0, 4, -3, 0, 6, p["main"]); v.box(3, 0, 4, 3, 0, 6, p["main"])
    if p["tier"] >= 3:
        v.box(-2, -2, 12, 2, 2, 12, p["metal"])

def f_key(v, p, r):
    v.disc_y(0, 9, 2.6, 0, 0, p["main"], inner=1.3)
    v.box(0, 0, 0, 0, 0, 7, p["main"])
    v.box(1, 0, 0, 2, 0, 0, p["main"]); v.box(1, 0, 2, 2, 0, 2, p["main"])
    if p["tier"] >= 2:
        v.put(0, -1, 9, p["accent"])

def f_compass(v, p, r):
    v.disc_y(0, 5, 4.5, 0, 1, p["metal"])
    v.disc_y(0, 5, 3.5, -1, -1, "F6EBD0")
    v.box(0, -2, 6, 0, -2, 8, "D7263D"); v.box(0, -2, 2, 0, -2, 4, "3A3A40")
    v.put(0, -2, 5, p["accent"])
    v.box(-1, 0, 10, 1, 1, 10, p["metal"])

def f_hourglass(v, p, r):
    v.box(-3, -3, 0, 3, 3, 0, p["dark"]); v.box(-3, -3, 10, 3, 3, 10, p["dark"])
    for z in range(1, 10):
        rr = 0.6 + abs(z - 5) * 0.5
        v.cyl(0, 0, z, z, rr, p["light"])
    v.cyl(0, 0, 1, 3, 1.5, p["accent"] if p["tier"] >= 1 else "E8C890")
    for x in (-3, 3):
        v.box(x, 0, 0, x, 0, 10, p["dark"])

def f_cup(v, p, r):
    v.cyl(0, 0, 0, 0, 3, p["main"])
    v.cyl(0, 0, 1, 3, 0.8, p["main"])
    v.cyl(0, 0, 4, 8, lambda z: 2 + (z - 4) * 0.4, p["main"], hollow=0)
    v.cyl(0, 0, 8, 8, 3.4, p["light"], hollow=2.4)
    if p["tier"] >= 1:
        v.cyl(0, 0, 6, 6, 3.2, p["accent"])
    if r.random() < 0.4:
        v.box(4, 0, 5, 4, 0, 7, p["main"])

def f_gun(v, p, r):
    v.box(-5, 0, 6, 5, 1, 7, p["main"])
    v.box(-5, 0, 5, -1, 1, 5, p["dark"])
    v.box(-4, 0, 0, -2, 1, 4, "6B4A2E")
    v.box(4, 0, 8, 5, 1, 8, p["accent"] if p["tier"] >= 1 else p["dark"])

def f_ring(v, p, r):
    v.disc_y(0, 5, 4.4, 0, 1, p["main"], inner=3.2)
    v.ellipsoid(0, 0, 10, 1.4, 1.4, 1.4, p["accent"] if p["tier"] >= 1 else p["light"])

def f_bone(v, p, r):
    v.box(-4, 0, 1, 4, 1, 2, p["main"])
    for sx in (-5, 5):
        v.ellipsoid(sx, 0, 1, 1.4, 1.4, 1.4, p["light"])
        v.ellipsoid(sx, 0, 3, 1.4, 1.4, 1.4, p["light"])

def f_star(v, p, r):
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        rr = 5.2 if i % 2 == 0 else 2.2
        pts.append((math.cos(a) * rr, math.sin(a) * rr))
    def inside(x, z):
        n, c = len(pts), False
        for i in range(n):
            (x1, z1), (x2, z2) = pts[i], pts[(i + 1) % n]
            if (z1 > z) != (z2 > z) and x < (x2 - x1) * (z - z1) / (z2 - z1) + x1:
                c = not c
        return c
    for x in range(-6, 7):
        for z in range(-6, 7):
            if inside(x, z):
                v.box(x, 0, z + 6, x, 1, z + 6, p["main"] if (x + z) % 2 else p["light"])
    v.put(0, -1, 6, p["accent"])

def f_horseshoe(v, p, r):
    for x in range(-4, 5):
        for z in range(0, 10):
            d = math.hypot(x, z - 5)
            if 2.4 <= d <= 4.4 and not (z < 5 and abs(x) < 3):
                v.box(x, 0, z, x, 1, z, p["main"])
    for z in (2, 5):
        v.put(-3, -1, z, p["dark"]); v.put(3, -1, z, p["dark"])

def f_bell(v, p, r):
    v.cyl(0, 0, 0, 7, lambda z: 4 - z * 0.35, p["main"], hollow=0)
    v.cyl(0, 0, 0, 0, 4.4, p["light"])
    v.box(0, 0, 8, 0, 0, 9, p["dark"])
    v.put(0, 0, -1, p["accent"] if p["tier"] >= 1 else p["dark"])

def f_rock(v, p, r):
    for _ in range(3):
        v.ellipsoid(r.uniform(-1.5, 1.5), r.uniform(-1.5, 1.5), r.uniform(2, 4), r.uniform(2.2, 3.4), r.uniform(2.2, 3.4), r.uniform(2, 3),
                    lambda x, y, z: r.choice([p["main"], p["dark"], p["light"]]))
    if p["tier"] >= 1:
        v.put(0, -3, 3, p["accent"])

def f_harp(v, p, r):
    for z in range(0, 12):
        v.put(-4 + int(2 * math.sin(z / 4)), 0, z, p["main"])
    v.box(-4, 0, 0, 3, 0, 0, p["main"])
    for z in range(9, 13):
        v.put(-4 + (z - 9) * 2, 0, z, p["main"])
    for x in range(-2, 3):
        v.box(x, 0, 1, x, 0, 9 + x // 2, p["white"])
    v.put(3, 0, 12, p["accent"])

def f_boot(v, p, r):
    v.box(-1, -1, 0, 1, 1, 8, p["main"])
    v.box(-1, -4, 0, 1, -1, 2, p["main"])
    v.box(-1, -4, 0, 1, 1, 0, p["dark"])
    v.box(-1, -1, 8, 1, 1, 8, p["light"])
    v.put(0, 2, 1, p["metal"])

def f_cactus(v, p, r):
    v.cyl(0, 0, 0, 2, 2.5, "B5653A")
    v.box(0, 0, 3, 1, 1, 10, "4F7F3A")
    v.box(2, 0, 6, 3, 1, 6, "4F7F3A"); v.box(3, 0, 7, 3, 1, 8, "4F7F3A")
    v.put(0, 0, 11, p["accent"])

def f_fish(v, p, r):
    v.ellipsoid(0, 0, 4, 4, 1.4, 2.4, p["main"])
    for z in range(2, 7):
        v.put(-5, 0, z, p["light"])
    v.put(-6, 0, 2, p["light"]); v.put(-6, 0, 6, p["light"])
    v.put(3, -1, 5, p["ink"])

def f_flower(v, p, r):
    v.box(0, 0, 0, 0, 0, 7, "4E8F35")
    for i in range(6):
        a = i / 6 * math.tau
        v.ellipsoid(math.cos(a) * 2, -0.5, 9 + math.sin(a) * 2, 1.2, 0.8, 1.2, p["main"])
    v.put(0, -1, 9, p["accent"] if p["tier"] >= 1 else "F4D03F")

def f_gear(v, p, r):
    v.disc_y(0, 6, 4.2, 0, 1, p["main"], inner=1.3)
    for i in range(8):
        a = i / 8 * math.tau
        v.box(round(math.cos(a) * 5), 0, 6 + round(math.sin(a) * 5), round(math.cos(a) * 5), 1, 6 + round(math.sin(a) * 5), p["dark"])
    v.put(0, -1, 6, p["accent"])

def f_bar(v, p, r):
    for z in range(0, 3):
        w = 4 - z // 2
        v.box(-w, -2 + z // 2, z, w, 2 - z // 2, z, p["main"] if z < 2 else p["light"])
    if p["tier"] >= 2:
        v.put(0, -2, 1, p["accent"])

SHAPES = {k[2:]: fn for k, fn in globals().items() if k.startswith("f_") and callable(fn)}

def voxels_for(item):
    seed = zlib.crc32(item["id"].encode("utf-8"))
    r = random.Random(seed)
    p = palette(item)
    v = V()
    SHAPES.get(item["shape"], f_idol)(v, p, r)
    tier = p["tier"]
    # ornements de rareté : socle doré pour Légendaire+, étincelles d'accent pour Mythique+
    if tier >= 6:
        zmin = min(k[2] for k in v)
        for (x, y) in [(-3, -3), (3, 3), (3, -3), (-3, 3)]:
            v.put(x * 1.6, y * 1.6, zmin + 6 + (x > 0), p["accent"])
    return v

# ---------------------------------------------------------------- Blender
def get_scene():
    scene = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = scene
    return scene

def build_all(start=0, end=None, spacing=22, per_row=40):
    ns = {}
    exec(bpy.data.texts["tar_voxel.py"].as_string(), ns)
    build = ns["build"]
    scene = get_scene()
    catalog = json.load(open(CATALOG, encoding="utf-8"))
    end = len(catalog) if end is None else end
    for index in range(start, end):
        item = catalog[index]
        root = build(item["id"], voxels_for(item), scene.collection)
        root.location = ((index % per_row) * spacing, (index // per_row) * spacing, 0)
    return end - start

def export_batches(size=100):
    scene = get_scene()
    catalog = json.load(open(CATALOG, encoding="utf-8"))
    os.makedirs(OUT_DIR, exist_ok=True)
    files = []
    for b in range(0, len(catalog), size):
        bpy.ops.object.select_all(action="DESELECT")
        for item in catalog[b:b + size]:
            root = bpy.data.objects.get(item["id"])
            if root:
                root.select_set(True)
                for c in root.children:
                    c.select_set(True)
        path = os.path.join(OUT_DIR, "Relics_%02d.fbx" % (b // size + 1))
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH", "EMPTY"}, apply_unit_scale=True,
                                 apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
                                 bake_space_transform=True, add_leaf_bones=False)
        files.append((path, os.path.getsize(path)))
    return files

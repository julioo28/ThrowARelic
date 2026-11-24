"""
Coffres au trésor voxel (un par rareté), exécuté dans Blender via MCP.

Réutilise le constructeur de tools/voxel_bench.py (un mesh par couleur nommé
<Nom>_<RRGGBB>_<n>). Chaque coffre = deux modèles :
  Chest_<rareté>     : le corps (devant = -Y Blender = -Z Roblox)
  Chest_<rareté>Lid  : le couvercle (charnière à l'arrière, en haut du corps)
Export : Assets/Props/Chests/Chests.fbx (scène « TAM_Chests »)

Utilisation :
    ns = {}; exec(open(r"...\\tools\\voxel_chests.py", encoding="utf-8").read(), ns)
    ns["build_all"](); ns["export"]()
"""
import bpy, math, os

ROOT = r"C:\Users\morel\Documents\ThrowARelic"
bench = {}
exec(open(os.path.join(ROOT, "tools", "voxel_bench.py"), encoding="utf-8").read(), bench)
V, build = bench["V"], bench["build"]
OUT = os.path.join(ROOT, "Assets", "Props", "Chests", "Chests.fbx")
SCENE = "TAM_Chests"

# rareté : (corps, corps sombre, ferrures, accent / gemmes, nb de gemmes, extras)
CHESTS = {
    "Commun":     ("9C6B3C", "6E4626", "5F6368", "3A3A3A", 0, ()),
    "PeuCommun":  ("5E8F3E", "3F6629", "B8BCC4", "8EE07A", 0, ()),
    "Rare":       ("2F6FB5", "1F4C80", "C8CCD6", "7FC4FF", 2, ()),
    "Epique":     ("6A2C9E", "4A1D70", "F2C14E", "D68CFF", 3, ()),
    "Legendaire": ("F2C14E", "B8892A", "FFF1A8", "FF6A3D", 4, ("crown",)),
    "Mythique":   ("E8466E", "A3244A", "F2C14E", "FF9BB5", 5, ("crown",)),
    "Secret":     ("15312F", "0B1C1B", "1FFFE6", "1FFFE6", 5, ("crown", "cracks")),
    "Divin":      ("F4F0E6", "D9CFAF", "F2C14E", "FFEC8C", 5, ("crown", "wings")),
    "Cosmique":   ("2A1458", "160A33", "8A5CFF", "B8F0FF", 6, ("crown", "stars")),
}

X0, X1 = -7, 6      # largeur (14)
Y0, Y1 = -4, 4      # profondeur (9), devant = Y0
BODY_TOP = 6        # corps : z 0..6
LID_Z = 7           # couvercle : z 7..10 (bombé)


def body(main, dark, trim, accent, gems, extras):
    v = V()
    v.box(X0, Y0, 0, X1, Y1, BODY_TOP, main)
    # planches : une ligne sombre sur deux en hauteur
    for z in (2, 4):
        for x in range(X0, X1 + 1):
            v.put(x, Y0, z, dark)
            v.put(x, Y1, z, dark)
        for y in range(Y0, Y1 + 1):
            v.put(X0, y, z, dark)
            v.put(X1, y, z, dark)
    # ferrures : coins verticaux, cerclage du bas et du haut, sangles
    for (x, y) in [(X0, Y0), (X0, Y1), (X1, Y0), (X1, Y1)]:
        v.box(x, y, 0, x, y, BODY_TOP, trim)
    for x in range(X0, X1 + 1):
        for y in (Y0, Y1):
            v.put(x, y, 0, trim)
            v.put(x, y, BODY_TOP, trim)
    for y in range(Y0, Y1 + 1):
        for x in (X0, X1):
            v.put(x, y, 0, trim)
            v.put(x, y, BODY_TOP, trim)
    for sx in (X0 + 2, X1 - 2):
        v.box(sx, Y0, 0, sx, Y0, BODY_TOP, trim)
        v.box(sx, Y1, 0, sx, Y1, BODY_TOP, trim)
    # serrure en façade
    v.box(-1, Y0 - 1, 3, 0, Y0 - 1, 6, trim)
    v.put(-1, Y0 - 1, 4, "1A1410")
    v.put(0, Y0 - 1, 4, "1A1410")
    # gemmes en façade du corps
    spots = [(-4, 3), (3, 3), (-4, 5), (3, 5), (-6, 4), (5, 4)]
    for (x, z) in spots[:max(0, gems - 2)]:
        v.put(x, Y0 - 1, z, accent)
    if "cracks" in extras:  # fissures lumineuses (obsidienne)
        for (x, z) in [(-6, 1), (-5, 2), (-5, 3), (2, 1), (3, 2), (4, 2), (5, 5), (-2, 5)]:
            v.put(x, Y0, z, accent)
            v.put(x, Y1, z, accent)
    if "stars" in extras:
        for (x, y, z) in [(-5, Y0, 1), (-2, Y0, 3), (4, Y0, 1), (1, Y0, 5), (-3, Y1, 2), (2, Y1, 4), (X0, -2, 3), (X1, 1, 2), (X0, 2, 5), (X1, -3, 4)]:
            v.put(x, y, z, accent)
    if "wings" in extras:  # petites ailes sur les côtés
        for side, xw in ((-1, X0 - 1), (1, X1 + 1)):
            for i, (h0, h1) in enumerate([(2, 6), (3, 7), (4, 8), (5, 8)]):
                v.box(xw + side * i, 0, h0, xw + side * i, 0, h1, "FFFFFF")
                v.put(xw + side * i, 0, h1, accent)
    return v


def lid(main, dark, trim, accent, gems, extras):
    v = V()
    v.box(X0, Y0, LID_Z, X1, Y1, LID_Z + 1, main)
    v.box(X0, Y0 + 1, LID_Z + 2, X1, Y1 - 1, LID_Z + 2, main)
    v.box(X0, Y0 + 3, LID_Z + 3, X1, Y1 - 3, LID_Z + 3, dark)
    # cerclage du couvercle + sangles qui passent par-dessus
    for x in range(X0, X1 + 1):
        v.put(x, Y0, LID_Z, trim)
        v.put(x, Y1, LID_Z, trim)
    for y in range(Y0, Y1 + 1):
        v.put(X0, y, LID_Z, trim)
        v.put(X1, y, LID_Z, trim)
    for sx in (X0 + 2, X1 - 2):
        for (y, z) in [(Y0, LID_Z), (Y0, LID_Z + 1), (Y0 + 1, LID_Z + 2), (Y0 + 2, LID_Z + 2), (Y0 + 3, LID_Z + 3),
                       (0, LID_Z + 3), (Y1 - 3, LID_Z + 3), (Y1 - 2, LID_Z + 2), (Y1 - 1, LID_Z + 2), (Y1, LID_Z + 1), (Y1, LID_Z)]:
            v.put(sx, y, z, trim)
    # moraillon de la serrure
    v.box(-1, Y0 - 1, LID_Z, 0, Y0 - 1, LID_Z + 1, trim)
    if gems >= 1:
        v.put(-1, Y0 + 1, LID_Z + 2, accent)
        v.put(0, Y0 + 1, LID_Z + 2, accent)
    if gems >= 2:
        for x in (-4, 3):
            v.put(x, Y0, LID_Z + 1, accent)
    if "crown" in extras:  # pierre centrale sur le dessus
        v.box(-1, -1, LID_Z + 4, 0, 0, LID_Z + 4, trim)
        v.box(-1, -1, LID_Z + 5, 0, 0, LID_Z + 5, accent)
    if "stars" in extras:
        for (x, y) in [(-5, -2), (-2, 1), (2, -1), (4, 2), (-6, 2), (5, -2)]:
            v.put(x, y, LID_Z + 3 if abs(y) <= 1 else LID_Z + 2, accent)
    return v


def build_all():
    scene = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = scene
    names = []
    for i, (rarity, (main, dark, trim, accent, gems, extras)) in enumerate(CHESTS.items()):
        loc = ((i % 5) * 12, (i // 5) * 12, 0)
        build("Chest_" + rarity, body(main, dark, trim, accent, gems, extras), scene.collection, loc)
        build("Chest_" + rarity + "Lid", lid(main, dark, trim, accent, gems, extras), scene.collection, loc)
        names.append(rarity)
    return names


def export():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    scene = bpy.data.scenes[SCENE]
    bpy.context.window.scene = scene
    bpy.ops.object.select_all(action="DESELECT")
    for o in scene.collection.objects:
        if o.type in ("MESH", "EMPTY"):
            o.select_set(True)
    bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, object_types={"MESH", "EMPTY"}, apply_unit_scale=True,
                             apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
                             bake_space_transform=True, add_leaf_bones=False)
    return OUT, os.path.getsize(OUT)

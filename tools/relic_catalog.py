"""
Générateur du catalogue des trouvailles (1 007 objets) — Throw a Magnet.

  - Reprend les 250 objets existants (Config.ZoneList, mêmes ids => sauvegardes intactes)
  - Ajoute 30 objets par zone (objets de base du thème x qualificatifs selon la rareté,
    accordés en genre) => 40 par zone : 15 Commun, 10 Peu commun, 6 Rare, 4 Épique,
    2 Légendaire, 2 Mythique, 1 Secret
  - Ajoute 7 objets « Cosmos » : 4 Divin, 3 Cosmique (tombent dans n'importe quelle zone)
  - Attribue à chaque objet une forme voxel (« shape ») pour le générateur Blender

Sorties :
  ThrowARelic/ReplicatedStorage/Modules/RelicCatalog.lua   (lu par Config)
  Assets/Relics/catalog.json                               (lu par Blender)

Lancer : python tools/relic_catalog.py
"""
import json, os, re, unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "ThrowARelic", "ReplicatedStorage", "Modules", "Config.lua")
OUT_LUA = os.path.join(ROOT, "ThrowARelic", "ReplicatedStorage", "Modules", "RelicCatalog.lua")
OUT_JSON = os.path.join(ROOT, "Assets", "Relics", "catalog.json")

OLD_ORDER = ["Commun", "Commun", "PeuCommun", "PeuCommun", "Rare", "Rare", "Epique", "Legendaire", "Mythique", "Secret"]
NEW_COUNTS = [("Commun", 13), ("PeuCommun", 8), ("Rare", 4), ("Epique", 3), ("Legendaire", 1), ("Mythique", 1)]
RARITY_COLORS = {"Commun": "c8c8c8", "PeuCommun": "6edc6e", "Rare": "50a0ff", "Epique": "be5aff", "Legendaire": "ffbe28",
                 "Mythique": "ff466e", "Secret": "14ffe6", "Divin": "fff2a0", "Cosmique": "8a5cff"}

def ascii_id(text):
    t = unicodedata.normalize("NFD", text)
    t = "".join(c for c in t if unicodedata.category(c) != "Mn").replace("œ", "oe").replace("Œ", "Oe")
    return "".join(w[:1].upper() + w[1:] for w in re.split(r"[^A-Za-z0-9]+", t) if w)

def plain(text):
    t = unicodedata.normalize("NFD", text.lower()).replace("œ", "oe")
    return "".join(c for c in t if unicodedata.category(c) != "Mn")

# --- formes voxel des objets existants, par mots-clés (ordre = priorité)
SHAPE_RULES = [
    ("casque", "helmet"), ("couronne", "crown"), ("diademe", "crown"), ("aureole", "crown"), ("crane", "skull"),
    ("hache", "axe"), ("marteau", "hammer"), ("enclume", "hammer"), ("pioche", "pickaxe"), ("tenaille", "pickaxe"),
    ("pelle", "pickaxe"), ("epee", "sword"), ("faux", "sword"), ("couteau", "sword"), ("sagaie", "staff"),
    ("trident", "staff"), ("sceptre", "staff"), ("baton", "staff"), ("baguette", "staff"), ("lance", "staff"),
    ("bouclier", "shield"), ("plastron", "shield"), ("miroir", "shield"), ("piece", "coin"), ("medaille", "coin"),
    ("sceau", "coin"), ("disque", "coin"), ("amulette", "coin"), ("badge", "coin"), ("etoile de sherif", "star"),
    ("boussole", "compass"), ("compas", "compass"), ("sablier", "hourglass"), ("machine", "gear"), ("engrenage", "gear"),
    ("oeuf", "egg"), ("perle", "orb"), ("orbe", "orb"), ("boule", "orb"), ("sphere", "orb"), ("noyau", "orb"),
    ("coeur", "orb"), ("graine", "egg"), ("goutte", "orb"), ("larme", "orb"), ("etincelle", "star"), ("poussiere", "orb"),
    ("oeil", "orb"), ("cerveau", "orb"), ("trou noir", "orb"), ("pheromone", "orb"),
    ("pyramidion", "gem"), ("diamant", "gem"), ("rubis", "gem"), ("saphir", "gem"), ("cristal", "gem"), ("gemme", "gem"),
    ("geode", "gem"), ("druse", "gem"), ("eclat", "gem"), ("prisme", "gem"), ("pepite", "gem"), ("quartz", "gem"),
    ("obsidienne", "gem"), ("peridot", "gem"), ("opale", "gem"), ("ambre", "gem"), ("soufre", "gem"), ("glacon", "gem"),
    ("titane", "bar"), ("lingot", "bar"), ("tole", "bar"), ("clavier", "bar"), ("harmonica", "bar"), ("peigne", "bar"),
    ("bouteille", "bottle"), ("fiole", "bottle"), ("potion", "bottle"), ("tube", "bottle"), ("voeu", "bottle"),
    ("vase", "vase"), ("amphore", "vase"), ("urne", "vase"), ("canope", "vase"), ("cruche", "vase"),
    ("bougie", "candle"), ("chandelier", "candle"), ("lanterne", "lantern"), ("lampe", "lantern"), ("braise", "orb"),
    ("flamme", "lantern"), ("feu", "lantern"), ("livre", "book"), ("grimoire", "book"), ("papyrus", "book"),
    ("carte", "book"), ("tablette", "book"), ("calendrier", "coin"), ("peinture", "book"), ("mosaique", "book"),
    ("tuile", "book"), ("coffre", "chest"), ("caisse", "chest"), ("sarcophage", "chest"), ("wagonnet", "chest"),
    ("cube", "chest"), ("selle", "chest"), ("barque", "chest"), ("masque", "mask"), ("coiffe", "crown"),
    ("plume", "feather"), ("aile", "feather"), ("fougere", "feather"), ("bandelette", "feather"), ("ecaille", "feather"),
    ("feuille", "feather"), ("dent", "fang"), ("griffe", "fang"), ("croc", "fang"), ("corne", "fang"),
    ("defense", "fang"), ("mandibule", "fang"), ("tentacule", "fang"), ("coquillage", "shell"), ("ammonite", "shell"),
    ("nautile", "shell"), ("champignon", "mushroom"), ("spore", "orb"), ("truffe", "rock"), ("chapeau", "mushroom"),
    ("statuette", "idol"), ("idole", "idol"), ("totem", "idol"), ("squelette", "idol"), ("cactus", "cactus"),
    ("robot", "idol"), ("scarabee", "idol"), ("salamandre", "idol"), ("poisson", "fish"), ("cle", "key"),
    ("ankh", "key"), ("calice", "cup"), ("chope", "cup"), ("coupe", "cup"), ("pistolet", "gun"), ("carabine", "gun"),
    ("revolver", "gun"), ("longue-vue", "gun"), ("rayon", "gun"), ("anneau", "ring"), ("chaine", "ring"),
    ("maillon", "ring"), ("chapelet", "ring"), ("lasso", "ring"), ("filet", "ring"), ("bracelet", "ring"),
    ("collier", "ring"), ("osselet", "bone"), ("vertebre", "bone"), ("fossile", "shell"), ("coprolithe", "rock"),
    ("empreinte", "coin"), ("os", "bone"), ("etoile", "star"), ("flocon", "star"), ("meteorite", "rock"),
    ("fer a cheval", "horseshoe"), ("cloche", "bell"), ("grelot", "bell"), ("harpe", "harp"), ("luth", "harp"),
    ("lyre", "harp"), ("caillou", "rock"), ("galet", "rock"), ("basalte", "rock"), ("pierre", "rock"), ("miette", "rock"),
    ("botte", "boot"), ("gant", "mask"), ("rivet", "bar"), ("clou", "bar"), ("boulon", "bar"), ("ration", "chest"),
    ("traducteur", "gear"), ("antimatiere", "chest"), ("hamecon", "key"), ("ancre", "key"), ("gourde", "bottle"),
]

def shape_for(name):
    p = " " + plain(name) + " "
    for key, shape in SHAPE_RULES:
        if key == "os":
            if re.search(r"\bos\b", p):
                return shape
            continue
        if key in p:
            return shape
    return "idol"

# --- objets de base des nouvelles trouvailles : (nom, genre, forme, couleur)
BASES = {
    "Plage": [("Fer à cheval", "m", "horseshoe", "7a7a80"), ("Botte", "f", "boot", "7a4a2a"), ("Gourde", "f", "bottle", "6e7a4a"),
              ("Insigne", "m", "star", "c0c0c8"), ("Clochette", "f", "bell", "c09040"), ("Tasse", "f", "cup", "8a8a90"),
              ("Harmonica", "m", "bar", "c8c8d0"), ("Bouton", "m", "coin", "b08a5a"), ("Pierre", "f", "rock", "d8c8a8"), ("Éperon", "m", "star", "b0a060")],
    "Foret": [("Pomme de pin", "f", "egg", "8a5a30"), ("Corne de bélier", "f", "fang", "d8c8a8"), ("Silex", "m", "gem", "6a6a6a"),
              ("Pointe de flèche", "f", "gem", "9a8a7a"), ("Gobelet", "m", "cup", "a07040"), ("Couteau", "m", "sword", "9a9aa0"),
              ("Collier", "m", "ring", "c0a060"), ("Cruche", "f", "vase", "c07a4a"), ("Peigne", "m", "bar", "d0b080"), ("Grelot", "m", "bell", "c0a040")],
    "Mine": [("Lampe", "f", "lantern", "8a6a40"), ("Casque", "m", "helmet", "d0b040"), ("Pelle", "f", "pickaxe", "7a7a80"),
             ("Lingot", "m", "bar", "9a8a7a"), ("Cristal", "m", "gem", "9ad0f0"), ("Roue", "f", "coin", "6a5a4a"),
             ("Bougie", "f", "candle", "e8e0c0"), ("Gamelle", "f", "cup", "8a8a90"), ("Bâton de dynamite", "m", "candle", "c03030"), ("Clou", "m", "bar", "8a8a90")],
    "Catacombes": [("Ossement", "m", "bone", "e0d8c0"), ("Bougeoir", "m", "candle", "8a7a60"), ("Urne", "f", "vase", "8a7a70"),
                   ("Médaillon", "m", "coin", "c0b080"), ("Crâne", "m", "skull", "e8e0cc"), ("Chapelet", "m", "ring", "9b7b4f"),
                   ("Grimoire", "m", "book", "4a2a2a"), ("Clé", "f", "key", "8a8a90"), ("Calice", "m", "cup", "c0a060"), ("Masque", "m", "mask", "d8d0b8")],
    "GrotteCristal": [("Cristal", "m", "gem", "c9a6ff"), ("Géode", "f", "gem", "8a74c9"), ("Prisme", "m", "gem", "d0f0ff"),
                      ("Orbe", "m", "orb", "9ad0ff"), ("Diadème", "m", "crown", "c0c8ff"), ("Éclat", "m", "gem", "e0d0ff"),
                      ("Baguette", "f", "staff", "d0c0ff"), ("Fiole", "f", "bottle", "9ad8ff"), ("Miroir", "m", "shield", "c0e0ff"), ("Étoile", "f", "star", "f0f0ff")],
    "LacSouterrain": [("Poisson", "m", "fish", "8aa0b0"), ("Coquille", "f", "shell", "d8d0c0"), ("Rame", "f", "staff", "8a6a40"),
                      ("Perle", "f", "orb", "e0e0f0"), ("Hameçon", "m", "key", "9a9aa0"), ("Bouteille", "f", "bottle", "5a8a7a"),
                      ("Lanterne", "f", "lantern", "c8a050"), ("Cloche", "f", "bell", "9ab0b0"), ("Galet", "m", "rock", "8a9aa0"), ("Filet", "m", "ring", "a89070")],
    "CiteEngloutie": [("Amphore", "f", "vase", "c87a4a"), ("Trident", "m", "staff", "40a0a0"), ("Casque", "m", "helmet", "c89a40"),
                      ("Pièce", "f", "coin", "ffd040"), ("Statuette", "f", "idol", "6ab0a0"), ("Coquillage", "m", "shell", "ff9a7a"),
                      ("Bouclier", "m", "shield", "c8a050"), ("Bracelet", "m", "ring", "d0b060"), ("Corail", "m", "fang", "ff7a6a"), ("Couronne", "f", "crown", "ffd040")],
    "GlacierFossile": [("Glaçon", "m", "gem", "d8f4ff"), ("Défense", "f", "fang", "f0e6d0"), ("Os", "m", "bone", "e8e0d0"),
                       ("Flocon", "m", "star", "ffffff"), ("Lance", "f", "staff", "a0d0f0"), ("Hache", "f", "axe", "8ab0d0"),
                       ("Casque", "m", "helmet", "b0b8c8"), ("Corne", "f", "fang", "e0d8c0"), ("Pierre", "f", "rock", "c0d8e8"), ("Amulette", "f", "coin", "a0e0ff")],
    "JunglePrehistorique": [("Ambre", "m", "gem", "e0a030"), ("Fougère", "f", "feather", "6a8a4a"), ("Silex", "m", "gem", "8a8a80"),
                            ("Massue", "f", "hammer", "7a5a3a"), ("Plume", "f", "feather", "8ad060"), ("Collier", "m", "ring", "c08a50"),
                            ("Totem", "m", "idol", "8a5a30"), ("Os", "m", "bone", "e0d4b8"), ("Coquille", "f", "shell", "c8a878"), ("Pierre", "f", "rock", "9a8a6a")],
    "TerreDinosaures": [("Griffe", "f", "fang", "d8ccb0"), ("Dent", "f", "fang", "f0e8d0"), ("Œuf", "m", "egg", "d0c0a0"),
                        ("Vertèbre", "f", "bone", "d8ccb0"), ("Empreinte", "f", "coin", "9a8060"), ("Os", "m", "bone", "e8dcc0"),
                        ("Écaille", "f", "feather", "6a8a5a"), ("Crâne", "m", "skull", "e0d4b8"), ("Corne", "f", "fang", "d0c0a0"), ("Fossile", "m", "shell", "b8a080")],
    "TempleOublie": [("Idole", "f", "idol", "70a040"), ("Masque", "m", "mask", "30c080"), ("Couteau", "m", "sword", "2a2a35"),
                     ("Perle", "f", "orb", "50b080"), ("Disque", "m", "coin", "ffc020"), ("Bracelet", "m", "ring", "c0a040"),
                     ("Statuette", "f", "idol", "8a8a6a"), ("Vase", "m", "vase", "c87850"), ("Serpent", "m", "staff", "40c080"), ("Coupe", "f", "cup", "d0a040")],
    "TombeauPharaon": [("Scarabée", "m", "idol", "3a70d0"), ("Ankh", "m", "key", "c87840"), ("Masque", "m", "mask", "ffcf50"),
                       ("Vase", "m", "vase", "d0b080"), ("Sceptre", "m", "staff", "3a3a50"), ("Amulette", "f", "coin", "3a70d0"),
                       ("Collier", "m", "ring", "ffd060"), ("Statuette", "f", "idol", "d0b080"), ("Papyrus", "m", "book", "d8c890"), ("Chat sacré", "m", "idol", "2a2a30")],
    "ForteresseNaine": [("Hache", "f", "axe", "9ab0d0"), ("Marteau", "m", "hammer", "707880"), ("Bouclier", "m", "shield", "8a6a40"),
                        ("Chope", "f", "cup", "9aa0a8"), ("Casque", "m", "helmet", "8a8a90"), ("Anneau", "m", "ring", "ffc840"),
                        ("Enclume", "f", "hammer", "50555f"), ("Clé", "f", "key", "b08040"), ("Pioche", "f", "pickaxe", "7a7a80"), ("Gemme", "f", "gem", "e04040")],
    "Champignonniere": [("Champignon", "m", "mushroom", "ff6060"), ("Spore", "f", "orb", "d0c0a0"), ("Truffe", "f", "rock", "6a4a30"),
                        ("Lanterne", "f", "lantern", "a0ff80"), ("Bâton", "m", "staff", "8a6a4a"), ("Fiole", "f", "bottle", "c0a0ff"),
                        ("Chapeau", "m", "mushroom", "c080d0"), ("Racine", "f", "fang", "8a6a40"), ("Graine", "f", "egg", "a0d060"), ("Couronne", "f", "crown", "ff80ff")],
    "Fourmiliere": [("Mandibule", "f", "fang", "5a3020"), ("Œuf", "m", "egg", "f0ece0"), ("Aile", "f", "feather", "d8e0e8"),
                    ("Antenne", "f", "staff", "6a3020"), ("Miette", "f", "rock", "e0c890"), ("Grain de sucre", "m", "gem", "fff0e0"),
                    ("Carapace", "f", "shield", "6a2a20"), ("Couronne", "f", "crown", "ffb030"), ("Sceptre", "m", "staff", "c06030"), ("Larve", "f", "egg", "f0e0c0")],
    "RiviereLave": [("Obsidienne", "f", "gem", "2a2030"), ("Braise", "f", "orb", "ff7020"), ("Casque", "m", "helmet", "803020"),
                    ("Épée", "f", "sword", "ff4010"), ("Plume", "f", "feather", "ff9020"), ("Rubis", "m", "gem", "e01040"),
                    ("Bouclier", "m", "shield", "803020"), ("Lanterne", "f", "lantern", "ff6020"), ("Pierre", "f", "rock", "4a3330"), ("Œuf", "m", "egg", "ffb040")],
    "ForgeTitans": [("Marteau", "m", "hammer", "6080ff"), ("Enclume", "f", "hammer", "5a5a62"), ("Lingot", "m", "bar", "c0c8e0"),
                    ("Engrenage", "m", "gear", "8a8a90"), ("Chaîne", "f", "ring", "707078"), ("Tenaille", "f", "pickaxe", "5a5a62"),
                    ("Plastron", "m", "shield", "a0a8c0"), ("Cloche", "f", "bell", "c08840"), ("Épée", "f", "sword", "c0c8e0"), ("Casque", "m", "helmet", "a0a8c0")],
    "CimetiereDragons": [("Écaille", "f", "feather", "4a8a5a"), ("Griffe", "f", "fang", "d8d0c0"), ("Dent", "f", "fang", "f0e8d8"),
                         ("Corne", "f", "fang", "d8c8a8"), ("Crâne", "m", "skull", "f0e0c0"), ("Os", "m", "bone", "e0d8c8"),
                         ("Œuf", "m", "egg", "2a1a2a"), ("Fiole", "f", "bottle", "c01020"), ("Bouclier", "m", "shield", "4a8a5a"), ("Épée", "f", "sword", "c0c0c8")],
    "GrotteFeerique": [("Baguette", "f", "staff", "a07040"), ("Fiole", "f", "bottle", "ff80c0"), ("Clochette", "f", "bell", "a0d0ff"),
                       ("Aile", "f", "feather", "a0f0e0"), ("Couronne", "f", "crown", "ffa0f0"), ("Étoile", "f", "star", "fff0a0"),
                       ("Champignon", "m", "mushroom", "ff80c0"), ("Fleur", "f", "flower", "ff80c0"), ("Perle", "f", "orb", "f0f0ff"), ("Miroir", "m", "shield", "c0e0ff")],
    "LaboSecret": [("Fiole", "f", "bottle", "50ff70"), ("Tube", "m", "bottle", "c0f0f0"), ("Engrenage", "m", "gear", "a0a8c0"),
                   ("Badge", "m", "coin", "d0d0d0"), ("Robot", "m", "idol", "a0a8c0"), ("Pistolet", "m", "gun", "ff3050"),
                   ("Cube", "m", "chest", "b040ff"), ("Puce", "f", "bar", "3a8a3a"), ("Clé", "f", "key", "d0d0d0"), ("Cerveau", "m", "orb", "ff90a0")],
    "EpaveAlien": [("Tôle", "f", "bar", "9ab0b0"), ("Cristal", "m", "gem", "60ffc0"), ("Casque", "m", "helmet", "e0e8f0"),
                   ("Pistolet", "m", "gun", "80ff80"), ("Antenne", "f", "staff", "708080"), ("Orbe", "m", "orb", "60c0ff"),
                   ("Œuf", "m", "egg", "50e050"), ("Engrenage", "m", "gear", "708080"), ("Carte", "f", "book", "4060ff"), ("Boulon", "m", "bar", "708080")],
    "Abysses": [("Dent", "f", "fang", "f0f0e8"), ("Perle", "f", "orb", "a0c0ff"), ("Coquille", "f", "shell", "2050a0"),
                ("Lanterne", "f", "lantern", "a0ff80"), ("Casque", "m", "helmet", "c08a40"), ("Ancre", "f", "key", "6a7a8a"),
                ("Tentacule", "f", "fang", "a04080"), ("Étoile", "f", "star", "ff8060"), ("Corail", "m", "fang", "ff6080"), ("Compas", "m", "compass", "40e0c0")],
    "RoyaumeOmbres": [("Bougie", "f", "candle", "202020"), ("Chaîne", "f", "ring", "8080a0"), ("Miroir", "m", "shield", "c0c0d8"),
                      ("Plume", "f", "feather", "101018"), ("Grimoire", "m", "book", "402060"), ("Crâne", "m", "skull", "a0a0c0"),
                      ("Lanterne", "f", "lantern", "80ffd0"), ("Masque", "m", "mask", "302040"), ("Orbe", "m", "orb", "300050"), ("Faux", "f", "sword", "a0a0c0")],
    "ManteauTerrestre": [("Basalte", "m", "rock", "3a3030"), ("Diamant", "m", "gem", "e0f0ff"), ("Géode", "f", "gem", "ff6030"),
                         ("Rubis", "m", "gem", "ff1040"), ("Saphir", "m", "gem", "2050ff"), ("Péridot", "m", "gem", "90d040"),
                         ("Pépite", "f", "gem", "ffcc30"), ("Cristal", "m", "gem", "f0e040"), ("Lingot", "m", "bar", "ff8000"), ("Œuf", "m", "egg", "ff6010")],
    "CoeurMonde": [("Étoile", "f", "star", "fff8d0"), ("Orbe", "m", "orb", "ffd0a0"), ("Cristal", "m", "gem", "a0e0ff"),
                   ("Plume", "f", "feather", "ffffff"), ("Sphère", "f", "orb", "c0ffd0"), ("Sablier", "m", "hourglass", "ffd060"),
                   ("Couronne", "f", "crown", "ffcc00"), ("Œil", "m", "orb", "ff80ff"), ("Étincelle", "f", "star", "ffffff"), ("Graine", "f", "egg", "c0ffd0")],
}

# complément du nom pour les Légendaires / Mythiques (« Couronne des Abysses »)
GENITIVE = {
    "Plage": "de la Corniche", "Foret": "des Falaises", "Mine": "de la Mine", "Catacombes": "des Catacombes",
    "GrotteCristal": "du Cristal", "LacSouterrain": "du Lac", "CiteEngloutie": "de la Cité", "GlacierFossile": "du Glacier",
    "JunglePrehistorique": "de la Jungle", "TerreDinosaures": "des Dinosaures", "TempleOublie": "du Temple",
    "TombeauPharaon": "du Pharaon", "ForteresseNaine": "des Nains", "Champignonniere": "des Spores",
    "Fourmiliere": "de la Reine", "RiviereLave": "du Volcan", "ForgeTitans": "des Titans", "CimetiereDragons": "des Dragons",
    "GrotteFeerique": "des Fées", "LaboSecret": "du Professeur", "EpaveAlien": "des Étoiles", "Abysses": "des Abysses",
    "RoyaumeOmbres": "des Ombres", "ManteauTerrestre": "du Magma", "CoeurMonde": "du Monde",
}

# qualificatifs (masculin, féminin, matière) par rareté
ADJ = {
    "Commun": [("rouillé", "rouillée", "rust"), ("cabossé", "cabossée", "dull"), ("fêlé", "fêlée", "dull"), ("ébréché", "ébréchée", "dull"),
               ("terni", "ternie", "dull"), ("poussiéreux", "poussiéreuse", "dust"), ("usé", "usée", "dull"), ("tordu", "tordue", "dull"),
               ("brisé", "brisée", "dull"), ("moisi", "moisie", "moss"), ("oublié", "oubliée", "dust"), ("abîmé", "abîmée", "dull"),
               ("boueux", "boueuse", "mud")],
    "PeuCommun": [("en cuivre", "en cuivre", "copper"), ("en bronze", "en bronze", "bronze"), ("gravé", "gravée", "none"),
                  ("poli", "polie", "none"), ("ancien", "ancienne", "none"), ("ciselé", "ciselée", "none"), ("en fer", "en fer", "iron"),
                  ("solide", "solide", "none")],
    "Rare": [("en argent", "en argent", "silver"), ("orné", "ornée", "none"), ("précieux", "précieuse", "none"), ("runique", "runique", "rune")],
    "Epique": [("doré", "dorée", "gold"), ("enchanté", "enchantée", "glow"), ("ensorcelé", "ensorcelée", "glow")],
}

MATERIAL_TINT = {"rust": ("8a4a2a", 0.45), "dull": ("6a6a6a", 0.25), "dust": ("c8b89a", 0.35), "moss": ("5a7a3a", 0.35),
                 "mud": ("5c422a", 0.4), "copper": ("c87533", 0.7), "bronze": ("b08040", 0.7), "iron": ("70757d", 0.6),
                 "silver": ("c8ccd6", 0.75), "gold": ("f2c14e", 0.8)}

def lerp_hex(a, b, t):
    ca = [int(a[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b[i:i + 2], 16) for i in (0, 2, 4)]
    return "".join("%02x" % round(x + (y - x) * t) for x, y in zip(ca, cb))

def parse_existing():
    src = open(CONFIG, encoding="utf-8").read()
    start = src.index("Config.ZoneList = {")
    end = src.index("Config.ZoneCurve = {")
    block = src[start:end]
    zones = []
    for zm in re.finditer(r'\{ id = "(\w+)", name = "([^"]+)"', block):
        zones.append((zm.group(1), zm.start()))
    items = {z: [] for z, _ in zones}
    entry = re.compile(r'\{ "(\w+)", "([^"]+)", (?:rgb\((\d+), (\d+), (\d+)\)|hex\("([0-9a-fA-F]{6})"\)) \}')
    for em in entry.finditer(block):
        zone = [z for z, pos in zones if pos < em.start()][-1]
        if em.group(6):
            color = em.group(6).lower()
        else:
            color = "%02x%02x%02x" % (int(em.group(3)), int(em.group(4)), int(em.group(5)))
        items[zone].append((em.group(1), em.group(2), color))
    return [z for z, _ in zones], items

def build():
    zones, existing = parse_existing()
    catalog, seen_ids, seen_names = [], set(), set()

    def add(item):
        if item["id"] in seen_ids:
            item["id"] = item["id"] + item["zone"]
        assert item["id"] not in seen_ids, item["id"]
        seen_ids.add(item["id"])
        seen_names.add(item["name"])
        item["accent"] = RARITY_COLORS[item["rarity"]]
        catalog.append(item)

    for zone in zones:
        olds = existing[zone]
        assert len(olds) == 10, (zone, len(olds))
        for index, (rid, name, color) in enumerate(olds):
            add({"id": rid, "name": name, "zone": zone, "rarity": OLD_ORDER[index], "color": color,
                 "shape": shape_for(name), "material": "none", "legacy": True})
        bases = BASES[zone]
        combo = 0
        for rarity, count in NEW_COUNTS:
            for k in range(count):
                # tous les objets de base défilent (combo), les qualificatifs tournent à part
                base = bases[combo % len(bases)]
                noun, gender, shape, color = base
                if rarity in ADJ:
                    pool = ADJ[rarity]
                    tries = 0
                    while True:
                        adj_m, adj_f, material = pool[(k * 5 + combo // len(bases) + tries) % len(pool)]
                        name = "%s %s" % (noun, adj_f if gender == "f" else adj_m)
                        if name not in seen_names or tries > len(pool):
                            break
                        tries += 1
                    if name in seen_names:
                        name = "%s %s" % (name, GENITIVE[zone])
                else:
                    material = "gold" if rarity == "Legendaire" else "glow"
                    if rarity == "Legendaire":
                        name = "%s %s" % (noun, GENITIVE[zone])
                    else:
                        name = "%s %s %s" % (noun, "mythique", GENITIVE[zone])
                    if name in seen_names:
                        noun2 = bases[(combo + 5) % len(bases)]
                        noun, gender, shape, color = noun2
                        name = "%s %s" % (noun, GENITIVE[zone]) if rarity == "Legendaire" else "%s mythique %s" % (noun, GENITIVE[zone])
                tint = MATERIAL_TINT.get(material)
                col = lerp_hex(color, tint[0], tint[1]) if tint else color
                add({"id": ascii_id(name), "name": name, "zone": zone, "rarity": rarity, "color": col,
                     "shape": shape, "material": material, "legacy": False})
                combo += 1

    cosmos = [("Auréole solaire", "Divin", "crown", "fff2a0"), ("Lyre céleste", "Divin", "harp", "ffe080"),
              ("Plume d'archange", "Divin", "feather", "ffffff"), ("Calice de lumière", "Divin", "cup", "fff6c0"),
              ("Fragment du Big Bang", "Cosmique", "star", "b080ff"), ("Œil de la galaxie", "Cosmique", "orb", "6040ff"),
              ("Clé de l'univers", "Cosmique", "key", "40e0ff")]
    for name, rarity, shape, color in cosmos:
        add({"id": ascii_id(name), "name": name, "zone": "Cosmos", "rarity": rarity, "color": color, "shape": shape,
             "material": "glow", "legacy": False})
    return zones, catalog

def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def main():
    zones, catalog = build()
    counts = {}
    for item in catalog:
        counts[item["rarity"]] = counts.get(item["rarity"], 0) + 1
    lines = ["--[[",
             "\tRelicCatalog (ModuleScript) — GÉNÉRÉ par tools/relic_catalog.py, ne pas modifier à la main.",
             "\t%d trouvailles : 40 par zone + 7 « Cosmos » (Divin / Cosmique, toutes zones)." % len(catalog),
             "\tChaque entrée : id (= nom du Model dans ReplicatedStorage/Relics), name, zone, rarity, color, shape.",
             "]]", "local hex = Color3.fromHex", "return {"]
    for item in catalog:
        lines.append("\t{ id = %s, name = %s, zone = %s, rarity = %s, color = hex(%s), shape = %s }," % (
            lua_string(item["id"]), lua_string(item["name"]), lua_string(item["zone"]), lua_string(item["rarity"]),
            lua_string(item["color"]), lua_string(item["shape"])))
    lines.append("}")
    open(OUT_LUA, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    json.dump(catalog, open(OUT_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    shapes = {}
    for item in catalog:
        shapes[item["shape"]] = shapes.get(item["shape"], 0) + 1
    print(len(catalog), counts)
    print(sorted(shapes.items(), key=lambda kv: -kv[1]))

if __name__ == "__main__":
    main()

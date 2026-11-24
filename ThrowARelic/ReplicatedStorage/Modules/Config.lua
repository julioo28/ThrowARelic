--[[
	Config (ModuleScript)
	Emplacement : ReplicatedStorage/Modules/Config

	TOUTES les valeurs réglables du jeu "Throw a Magnet" sont ici.
	(les noms internes ThrowARelic… sont gardés : DataStore, dossiers, scripts)
	Le serveur ET le client lisent ce module : ne jamais y mettre de secret.

	Remplacer une relique placeholder par un modèle Blender :
	  -> mettre un Model nommé exactement comme le champ `id` de la relique
	     dans ReplicatedStorage/Relics (ex : ReplicatedStorage/Relics/CoquillageFele).
	     Le code le charge par son nom, rien d'autre à changer.
]]

local Config = {}

---------------------------------------------------------------------------
-- JOUEUR / ÉCONOMIE
---------------------------------------------------------------------------
Config.Player = {
	StartingPower = 25, -- puissance au spawn
	StartingMoney = 0,
	TrainTolerance = 0.05, -- marge réseau sur la cadence des répétitions (secondes)
}

---------------------------------------------------------------------------
-- BANC DE DÉVELOPPÉ COUCHÉ (un devant chaque musée, remplace le bouton « Entraîner »)
-- On s'allonge sur SON banc (invite « S'entraîner »), chaque tap = une répétition.
-- Les disques sur la barre grossissent avec la puissance (visible par tous).
---------------------------------------------------------------------------
Config.Bench = {
	RepCooldown = 0.5, -- secondes minimum entre deux répétitions (vérifié serveur)
	RepGainPercent = 0.001, -- +0,1 % de la puissance par répétition...
	RepMinGain = 1, -- ...et au moins +1
	RepDownTime = 0.2, -- animation : descente de la barre
	RepUpTime = 0.26, -- animation : poussée
	RepDrop = 0.8, -- de combien la barre descend (studs)
	RepArmAngle = 70, -- écartement des bras en bas du mouvement (degrés)
	-- Position : sur la rue, devant la clôture de l'enclos, à côté de l'entrée.
	-- Le banc est perpendiculaire à la rue (tête vers l'enclos), la barre parallèle à la rue.
	AlongStreet = -8, -- décalage le long de la rue par rapport au centre de l'enclos
	FromFence = 5.25, -- distance de la clôture avant au centre du banc (côté rue)
	-- Personnage allongé : décalage le long du banc depuis la barre (vers les pieds) et hauteur au-dessus du coussin
	LieShoulderBack = 1.25,
	LieHeight = 0.55,
	PromptDistance = 9,
	-- Disques par côté selon la puissance (du plus lourd au plus léger, collés à la butée)
	Plates = {
		{ power = 0, plates = { "Plate1" } },
		{ power = 60, plates = { "Plate2" } },
		{ power = 150, plates = { "Plate2", "Plate1" } },
		{ power = 400, plates = { "Plate3" } },
		{ power = 1000, plates = { "Plate3", "Plate2" } },
		{ power = 3000, plates = { "Plate4" } },
		{ power = 8000, plates = { "Plate4", "Plate3" } },
		{ power = 20000, plates = { "Plate4", "Plate4" } },
		{ power = 50000, plates = { "Plate5", "Plate4" } },
		{ power = 120000, plates = { "Plate5", "Plate5" } },
		{ power = 300000, plates = { "Plate5", "Plate5", "Plate4" } },
		{ power = 700000, plates = { "Plate6", "Plate5", "Plate5" } },
		{ power = 1500000, plates = { "Plate6", "Plate6", "Plate5" } },
		{ power = 5000000, plates = { "Plate6", "Plate6", "Plate6" } },
	},
}

-- Index du palier de disques pour une puissance donnée
function Config.GetPlateTier(power: number): number
	local tier = 1
	for index, step in ipairs(Config.Bench.Plates) do
		if power >= step.power then
			tier = index
		end
	end
	return tier
end

function Config.GetRepGain(power: number): number
	return math.max(Config.Bench.RepMinGain, math.floor(power * Config.Bench.RepGainPercent))
end

---------------------------------------------------------------------------
-- AMÉLIORATIONS (bouton « Améliorations »)
--   Power  : +percent de ta puissance (au moins minGain). Prix = costMultiplier
--            x valeur de base de la zone que ta puissance atteint : le prix suit
--            ta progression (~2-3 min de gains par achat).
--   Magnet : chance des raretés Rare et + (x(1 + luckPerLevel x niveau))
--   Cable  : vitesse de descente / attente / remontée (x(1 + speedPerLevel x niveau))
--   Clean  : durée de nettoyage (-secondsPerLevel par niveau)
--   Museum : +slotsPerLevel socle(s) par niveau
--   Prix d'un niveau = baseCost x costGrowth ^ niveau actuel
---------------------------------------------------------------------------
Config.Upgrades = {
	Power = { name = "Puissance", icon = "💪", percent = 0.12, minGain = 5, costMultiplier = 25 },
	Magnet = { name = "Aimant", icon = "🧲", maxLevel = 10, baseCost = 500, costGrowth = 3.2, luckPerLevel = 0.08 },
	Cable = { name = "Câble", icon = "🔗", maxLevel = 10, baseCost = 300, costGrowth = 3.2, speedPerLevel = 0.1 },
	Clean = { name = "Ouverture des coffres", icon = "🗝", maxLevel = 8, baseCost = 200, costGrowth = 3, secondsPerLevel = 0.25 },
	Museum = { name = "Places au musée", icon = "🏛", maxLevel = 6, baseCost = 2000, costGrowth = 4, slotsPerLevel = 1 },
}
Config.UpgradeOrder = { "Power", "Magnet", "Cable", "Clean", "Museum" }

-- Livre de collection : les 10 reliques d'une zone trouvées = bonus de valeur
Config.Collection = {
	ZoneBonus = 0.10, -- +10 % de valeur (vente ET musée) sur les reliques de cette zone
}

---------------------------------------------------------------------------
-- JAUGE DE LANCER
---------------------------------------------------------------------------
Config.Gauge = {
	SweepTime = 0.9, -- secondes pour aller d'un bout à l'autre de la jauge
	PerfectWindow = 0.05, -- |position - centre| <= ça => PARFAIT
	MinPrecisionFactor = 0.5, -- un très mauvais timing garde 50 % de la puissance
	PerfectBonus = 1.25, -- multiplicateur de puissance si PARFAIT
	ResultDisplayTime = 0.5, -- la jauge reste figée ce temps avant le lancer
}

---------------------------------------------------------------------------
-- ZONES (ordre = de la surface vers le fond) — 25 zones, 250 reliques
--
-- Chaque entrée décrit le THÈME d'une zone et ses 10 reliques, toujours dans
-- cet ordre de rareté : 2 Commun, 2 Peu commun, 2 Rare, 1 Épique,
-- 1 Légendaire, 1 Mythique, 1 Secret.
--   walls  : couleurs des parois          ore : touches lumineuses (facultatif)
--   impact : couleur de l'éclaboussure    sound : "Water" ou "Rock"
--   relics : { id, nom affiché, couleur du placeholder }
--            id = nom du Model dans ReplicatedStorage/Relics (sans accent ni espace)
--
-- Les CHIFFRES (profondeur, puissance requise, valeur, vitesse de chute) sont
-- calculés par Config.ZoneCurve juste en dessous : pour rééquilibrer, change
-- la courbe plutôt que chaque zone.
---------------------------------------------------------------------------
local hex = Color3.fromHex
local rgb = Color3.fromRGB

Config.ZoneList = {
	{ id = "Plage", name = "Corniche de Kaibab", sound = "Rock", impact = rgb(231, 214, 181),
		walls = { rgb(231, 214, 181), rgb(239, 224, 194), rgb(210, 174, 128) },
		relics = {
			{ "CoquillageFele", "Coquillage fossile", rgb(245, 225, 210) },
			{ "BouteilleEnsablee", "Bouteille de whisky ensablée", rgb(90, 170, 120) },
			{ "AncreRouillee", "Fer à cheval rouillé", rgb(150, 85, 50) },
			{ "BoussoleCassee", "Boussole cassée", rgb(200, 170, 90) },
			{ "LongueVuePirate", "Longue-vue de prospecteur", rgb(180, 140, 60) },
			{ "PieceOrEspagnole", "Pièce d'or espagnole", rgb(255, 205, 60) },
			{ "CoffreCorsaire", "Coffre de diligence", rgb(120, 70, 40) },
			{ "TridentCapitaine", "Revolver du shérif", rgb(80, 200, 220) },
			{ "PerleKraken", "Étoile de shérif en or", rgb(240, 240, 255) },
			{ "CouronneNeptune", "Couronne de Coronado", rgb(60, 230, 255) },
		} },
	{ id = "Foret", name = "Falaises de Supai", sound = "Rock", impact = rgb(196, 110, 68),
		walls = { rgb(184, 97, 59), rgb(196, 110, 68), rgb(156, 69, 48) },
		relics = {
			{ "GlandPetrifie", "Pomme de pin pétrifiée", rgb(140, 110, 80) },
			{ "HacheBucheron", "Hache de pionnier", rgb(170, 170, 175) },
			{ "LanterneGarde", "Lanterne de diligence", rgb(230, 170, 60) },
			{ "TotemMousse", "Cactus pétrifié", rgb(90, 150, 70) },
			{ "ArcElfique", "Carabine de trappeur", rgb(200, 230, 150) },
			{ "ChampignonLuminescent", "Cristal de sélénite", rgb(80, 230, 200) },
			{ "MasqueDruide", "Selle de cow-boy brodée", rgb(110, 80, 50) },
			{ "BatonSylvain", "Lasso doré", rgb(160, 220, 90) },
			{ "CoeurChene", "Cœur de genévrier ancien", rgb(220, 60, 80) },
			{ "GraineMonde", "Graine du désert éternel", rgb(120, 255, 120) },
		} },
	{ id = "Mine", name = "Mine abandonnée", sound = "Rock", impact = rgb(90, 90, 100),
		walls = { rgb(70, 70, 78), rgb(55, 55, 62), rgb(90, 88, 95) },
		ore = { rgb(160, 90, 220), rgb(240, 200, 60) },
		relics = {
			{ "PiocheEmoussee", "Pioche émoussée", rgb(130, 130, 135) },
			{ "CasqueMineur", "Casque de mineur", rgb(230, 200, 50) },
			{ "WagonnetMiniature", "Wagonnet miniature", rgb(110, 90, 80) },
			{ "LampeCarbure", "Lampe à carbure", rgb(200, 120, 60) },
			{ "GeodeAmethyste", "Géode d'améthyste", rgb(170, 90, 230) },
			{ "PepiteOr", "Pépite d'or", rgb(255, 200, 40) },
			{ "MarteauRunique", "Marteau runique", rgb(100, 140, 220) },
			{ "DiamantBrut", "Diamant brut", rgb(190, 240, 255) },
			{ "OeilDragon", "Œil de Dragon", rgb(255, 90, 30) },
			{ "NoyauTerre", "Noyau de la Terre", rgb(255, 60, 0) },
		} },
	{ id = "Catacombes", name = "Catacombes", sound = "Rock", impact = hex("d9d0bb"),
		walls = { hex("cfc6b0"), hex("a89f8a"), hex("8a8273") },
		relics = {
			{ "CraneFele", "Crâne fêlé", hex("e8e0cc") },
			{ "OsseletAncien", "Osselet ancien", hex("d8cfb8") },
			{ "ChandelierRouille", "Chandelier rouillé", hex("8a6a4a") },
			{ "ChapeletBuis", "Chapelet de buis", hex("9b7b4f") },
			{ "CalicePlomb", "Calice de plomb", hex("8c8f99") },
			{ "ReliquaireArgent", "Reliquaire d'argent", hex("c8ccd6") },
			{ "MasqueMortuaire", "Masque mortuaire", hex("e6d38a") },
			{ "CouronneRoiOublie", "Couronne du roi oublié", hex("ffcf3f") },
			{ "SablierAmes", "Sablier des âmes", hex("9fe8ff") },
			{ "CleCatacombes", "Clé des catacombes", hex("b06cff") },
		} },
	{ id = "GrotteCristal", name = "Grotte de cristal", sound = "Rock", impact = hex("c9b6ff"),
		walls = { hex("6b5aa8"), hex("8a74c9"), hex("4e4385") }, ore = { hex("c9a6ff"), hex("7fe3ff") },
		relics = {
			{ "EclatQuartz", "Éclat de quartz", hex("f0f0ff") },
			{ "GaletIrise", "Galet irisé", hex("b8c4e0") },
			{ "DruseAmethyste", "Druse d'améthyste", hex("9a5fd6") },
			{ "PrismeFele", "Prisme fêlé", hex("d0f0ff") },
			{ "FleurCristal", "Fleur de cristal", hex("a8e8ff") },
			{ "LarmeOpale", "Larme d'opale", hex("f6e0ff") },
			{ "BouleVoyance", "Boule de voyance", hex("7fd0ff") },
			{ "SceptreSaphir", "Sceptre de saphir", hex("3060ff") },
			{ "CoeurPrisme", "Cœur prismatique", hex("ff8ff0") },
			{ "EtoileFigee", "Étoile figée", hex("ffffff") },
		} },
	{ id = "LacSouterrain", name = "Lac souterrain", sound = "Water", impact = hex("6fb8d8"),
		walls = { hex("3d5a66"), hex("2f4a55"), hex("4f6f7a") },
		relics = {
			{ "CaillouLisse", "Caillou lisse", hex("8a9aa0") },
			{ "BarqueMiniature", "Barque miniature", hex("7a5a3a") },
			{ "LanterneNoyee", "Lanterne noyée", hex("c8a050") },
			{ "FiletPecheur", "Filet de pêcheur", hex("a89070") },
			{ "PoissonAveugle", "Poisson aveugle fossile", hex("d8d8e8") },
			{ "PerleNoire", "Perle noire", hex("2a2a3a") },
			{ "HarpeOndine", "Harpe d'ondine", hex("8fe0d0") },
			{ "TridentLac", "Trident du lac", hex("40c0c0") },
			{ "MiroirEaux", "Miroir des eaux", hex("b0f0ff") },
			{ "GouttePrimordiale", "Goutte primordiale", hex("40a0ff") },
		} },
	{ id = "CiteEngloutie", name = "Cité engloutie", sound = "Water", impact = hex("5fc8c8"),
		walls = { hex("2f6f7a"), hex("3f8a8a"), hex("285860") }, ore = { hex("ffd75a") },
		relics = {
			{ "TuileCorail", "Tuile de corail", hex("ff9a7a") },
			{ "AmphoreBrisee", "Amphore brisée", hex("c87a4a") },
			{ "StatuetteTriton", "Statuette de triton", hex("6ab0a0") },
			{ "MosaiqueBleue", "Mosaïque bleue", hex("3a7ad8") },
			{ "CasqueHoplite", "Casque d'hoplite", hex("c89a40") },
			{ "TabletteAtlante", "Tablette atlante", hex("80d0e0") },
			{ "OrbeMarees", "Orbe des marées", hex("40e0ff") },
			{ "SceauAtlantide", "Sceau de l'Atlantide", hex("ffd040") },
			{ "CouronneSirene", "Couronne de sirène", hex("ff70c0") },
			{ "CoeurAtlantide", "Cœur de l'Atlantide", hex("00ffd0") },
		} },
	{ id = "GlacierFossile", name = "Glacier fossile", sound = "Rock", impact = hex("e0f4ff"),
		walls = { hex("cfe8f5"), hex("a8d4ea"), hex("e8f6ff") }, ore = { hex("7fd8ff") },
		relics = {
			{ "GlaconEternel", "Glaçon éternel", hex("d8f4ff") },
			{ "DentMammouth", "Dent de mammouth", hex("e8dcc0") },
			{ "PatinOs", "Patin en os", hex("e0d8c8") },
			{ "LanceGivre", "Lance de givre", hex("a0d0f0") },
			{ "DefenseMammouth", "Défense de mammouth", hex("f0e6d0") },
			{ "FloconFossile", "Flocon fossile", hex("ffffff") },
			{ "CasqueVikingGele", "Casque viking gelé", hex("b0b8c8") },
			{ "HacheGivre", "Hache de givre", hex("60c0ff") },
			{ "CoeurBlizzard", "Cœur de blizzard", hex("a0f0ff") },
			{ "LarmeGlaciaire", "Larme de l'ère glaciaire", hex("00e0ff") },
		} },
	{ id = "JunglePrehistorique", name = "Jungle préhistorique", sound = "Rock", impact = hex("6a9a4a"),
		walls = { hex("3f7a3a"), hex("56913f"), hex("2f5f2f") },
		relics = {
			{ "FougereFossile", "Fougère fossile", hex("6a8a4a") },
			{ "AmbreTrouble", "Ambre trouble", hex("c88a30") },
			{ "SagaieSilex", "Sagaie en silex", hex("9a8a7a") },
			{ "Ammonite", "Ammonite", hex("c8a878") },
			{ "MoustiqueAmbre", "Moustique dans l'ambre", hex("ffaa30") },
			{ "PeintureRupestre", "Peinture rupestre", hex("b05030") },
			{ "TotemChaman", "Totem du chaman", hex("8a5a30") },
			{ "CrocSmilodon", "Croc de tigre à dents de sabre", hex("f0e8d8") },
			{ "OeufPterodactyle", "Œuf de ptérodactyle", hex("d0b090") },
			{ "PremierFeu", "Premier feu", hex("ff7020") },
		} },
	{ id = "TerreDinosaures", name = "Terre des dinosaures", sound = "Rock", impact = hex("b08a5a"),
		walls = { hex("8a6a4a"), hex("a07a50"), hex("6a5038") },
		relics = {
			{ "Coprolithe", "Coprolithe", hex("6a5a40") },
			{ "VertebreRaptor", "Vertèbre de raptor", hex("d8ccb0") },
			{ "GriffeRaptor", "Griffe de raptor", hex("c8b898") },
			{ "EmpreinteDino", "Empreinte de dinosaure", hex("9a8060") },
			{ "DentTrex", "Dent de T-Rex", hex("f0e8d0") },
			{ "OeufFossile", "Œuf fossilisé", hex("b8a080") },
			{ "CraneTricera", "Crâne de tricératops", hex("e0d4b8") },
			{ "SqueletteBebeRex", "Squelette de bébé T-Rex", hex("fff0d0") },
			{ "OeufBrontoDore", "Œuf de brontosaure doré", hex("ffd060") },
			{ "MeteoriteExtinction", "Météorite de l'extinction", hex("ff5030") },
		} },
	{ id = "TempleOublie", name = "Temple oublié", sound = "Rock", impact = hex("9aa070"),
		walls = { hex("7a8a5a"), hex("8f9a6a"), hex("5f6f48") }, ore = { hex("3fd090") },
		relics = {
			{ "TessonPeint", "Tesson peint", hex("c87850") },
			{ "PerleJade", "Perle de jade", hex("50b080") },
			{ "CouteauObsidienne", "Couteau d'obsidienne", hex("2a2a35") },
			{ "CalendrierPierre", "Calendrier de pierre", hex("a0a090") },
			{ "MasqueJade", "Masque de jade", hex("30c080") },
			{ "IdoleSerpent", "Idole serpent", hex("70a040") },
			{ "CoiffePlumes", "Coiffe à plumes", hex("40d0b0") },
			{ "DisqueSolaire", "Disque solaire d'or", hex("ffc020") },
			{ "IdoleJaguar", "Idole du jaguar", hex("ffa030") },
			{ "CraneCristal", "Crâne de cristal", hex("c0f8ff") },
		} },
	{ id = "TombeauPharaon", name = "Tombeau du pharaon", sound = "Rock", impact = hex("e0c080"),
		walls = { hex("d8b878"), hex("c8a060"), hex("e8cc90") }, ore = { hex("3a7ad8") },
		relics = {
			{ "ScarabeArgile", "Scarabée d'argile", hex("a07850") },
			{ "BandeletteMomie", "Bandelette de momie", hex("e8dcc0") },
			{ "VaseCanope", "Vase canope", hex("d0b080") },
			{ "AnkhCuivre", "Ankh de cuivre", hex("c87840") },
			{ "AmuletteOeil", "Amulette de l'œil", hex("3a70d0") },
			{ "PapyrusMaudit", "Papyrus maudit", hex("d8c890") },
			{ "SarcophageMiniature", "Sarcophage miniature", hex("ffcf50") },
			{ "MasquePharaon", "Masque du pharaon", hex("ffd040") },
			{ "SceptreAnubis", "Sceptre d'Anubis", hex("2a2a40") },
			{ "PyramidionOr", "Pyramidion d'or pur", hex("ffe880") },
		} },
	{ id = "ForteresseNaine", name = "Forteresse naine", sound = "Rock", impact = hex("8a7a6a"),
		walls = { hex("6a5a50"), hex("806a5a"), hex("504540") }, ore = { hex("ff9a30") },
		relics = {
			{ "ChopeEtain", "Chope d'étain", hex("9aa0a8") },
			{ "ClouForge", "Clou forgé", hex("707880") },
			{ "BouclierRond", "Bouclier rond", hex("8a6a40") },
			{ "CorneGuerre", "Corne de guerre", hex("d8c8a0") },
			{ "HacheRunique", "Hache runique", hex("9ab0d0") },
			{ "EnclumeMiniature", "Enclume miniature", hex("50555f") },
			{ "GanteletMithril", "Gantelet de mithril", hex("d0e0f0") },
			{ "CouronneRoiNain", "Couronne du roi nain", hex("ffc840") },
			{ "GemmeMontagne", "Gemme du cœur de la montagne", hex("f0f8ff") },
			{ "MarteauPremierForgeron", "Marteau du premier forgeron", hex("ff8030") },
		} },
	{ id = "Champignonniere", name = "Champignonnière géante", sound = "Rock", impact = hex("c080d0"),
		walls = { hex("6a4a7a"), hex("8a5a8a"), hex("4f3a5f") }, ore = { hex("5fffb0"), hex("ff70e0") },
		relics = {
			{ "SporeGeante", "Spore géante", hex("d0c0a0") },
			{ "ChapeauMoisi", "Chapeau moisi", hex("a08060") },
			{ "ChampignonBleu", "Champignon bleu", hex("4080ff") },
			{ "LanterneSpores", "Lanterne à spores", hex("a0ff80") },
			{ "TruffeOr", "Truffe d'or", hex("d0a030") },
			{ "ChampignonDansant", "Champignon dansant", hex("ff60a0") },
			{ "SceptreMycelium", "Sceptre de mycélium", hex("c0a0ff") },
			{ "CouronneReineSpores", "Couronne de la reine des spores", hex("ff80ff") },
			{ "CoeurMycelium", "Cœur du mycélium", hex("80ffd0") },
			{ "ChampignonEternel", "Champignon éternel", hex("fff060") },
		} },
	{ id = "Fourmiliere", name = "Fourmilière géante", sound = "Rock", impact = hex("a07050"),
		walls = { hex("8a5030"), hex("a06038"), hex("703f25") },
		relics = {
			{ "MietteGeante", "Miette géante", hex("e0c890") },
			{ "AileFourmi", "Aile de fourmi", hex("d8e0e8") },
			{ "MandibuleSoldat", "Mandibule de soldat", hex("5a3020") },
			{ "GoutteMiellat", "Goutte de miellat", hex("ffb040") },
			{ "ArmureChitine", "Armure de chitine", hex("6a2a20") },
			{ "OeufFourmiGeante", "Œuf de fourmi géante", hex("f0ece0") },
			{ "SceptreColonie", "Sceptre de la colonie", hex("c06030") },
			{ "CouronneReineFourmi", "Couronne de la reine fourmi", hex("ffb030") },
			{ "PheromoneDoree", "Phéromone dorée", hex("ffe060") },
			{ "OeufImperial", "Œuf impérial", hex("ff4060") },
		} },
	{ id = "RiviereLave", name = "Rivière de lave", sound = "Rock", impact = hex("ff6a20"),
		walls = { hex("3a2a28"), hex("4a3330"), hex("2a1f1f") }, ore = { hex("ff5a10"), hex("ffaa20") },
		relics = {
			{ "ObsidienneBrute", "Obsidienne brute", hex("2a2030") },
			{ "PierrePonce", "Pierre ponce", hex("a09a90") },
			{ "SalamandreFossile", "Salamandre fossile", hex("c04020") },
			{ "BraiseEternelle", "Braise éternelle", hex("ff7020") },
			{ "RubisFondu", "Rubis fondu", hex("e01040") },
			{ "CasqueMagma", "Casque de magma", hex("803020") },
			{ "PlumePhenix", "Plume de phénix", hex("ff9020") },
			{ "EpeeLave", "Épée de lave", hex("ff4010") },
			{ "OeufPhenix", "Œuf de phénix", hex("ffb040") },
			{ "CoeurVolcan", "Cœur du volcan", hex("ff2000") },
		} },
	{ id = "ForgeTitans", name = "Forge des titans", sound = "Rock", impact = hex("8a8090"),
		walls = { hex("4a4550"), hex("5f5a68"), hex("38343e") }, ore = { hex("ffb030") },
		relics = {
			{ "RivetGeant", "Rivet géant", hex("8a8a90") },
			{ "MaillonTitan", "Maillon de titan", hex("707078") },
			{ "TenailleGeante", "Tenaille géante", hex("5a5a62") },
			{ "LingotCeleste", "Lingot céleste", hex("c0c8e0") },
			{ "GantForgeron", "Gant de forgeron titan", hex("8a5a3a") },
			{ "ClocheBronze", "Cloche de bronze", hex("c08840") },
			{ "PlastronTitan", "Plastron de titan", hex("a0a8c0") },
			{ "MarteauTonnerre", "Marteau du tonnerre", hex("6080ff") },
			{ "EnclumeEtoiles", "Enclume des étoiles", hex("c0d0ff") },
			{ "FlammePrimordiale", "Flamme primordiale", hex("ffd0a0") },
		} },
	{ id = "CimetiereDragons", name = "Cimetière des dragons", sound = "Rock", impact = hex("9a8070"),
		walls = { hex("5a4a48"), hex("6f5a55"), hex("45383a") }, ore = { hex("ff4040") },
		relics = {
			{ "EcailleTerne", "Écaille terne", hex("6a7a5a") },
			{ "GriffeBrisee", "Griffe brisée", hex("d8d0c0") },
			{ "DentDragon", "Dent de dragon", hex("f0e8d8") },
			{ "BouclierEcailles", "Bouclier d'écailles", hex("4a8a5a") },
			{ "CorneDragon", "Corne de dragon", hex("d8c8a8") },
			{ "FioleSangDragon", "Fiole de sang de dragon", hex("c01020") },
			{ "AileMomifiee", "Aile de dragon momifiée", hex("8a6a50") },
			{ "CraneDragonAncien", "Crâne de dragon ancien", hex("f0e0c0") },
			{ "OeufDragonNoir", "Œuf de dragon noir", hex("2a1a2a") },
			{ "CoeurDernierDragon", "Cœur du dernier dragon", hex("ff3060") },
		} },
	{ id = "GrotteFeerique", name = "Grotte féerique", sound = "Water", impact = hex("c0b0ff"),
		walls = { hex("5a7aa8"), hex("7a8ac8"), hex("4a5a90") }, ore = { hex("ff9aff"), hex("9affff") },
		relics = {
			{ "PoussiereFee", "Poussière de fée", hex("fff0a0") },
			{ "GlandArgente", "Gland argenté", hex("c8c8d8") },
			{ "AileLibellule", "Aile de libellule", hex("a0f0e0") },
			{ "ClochetteRosee", "Clochette de rosée", hex("a0d0ff") },
			{ "BaguetteNoisetier", "Baguette de noisetier", hex("a07040") },
			{ "PotionArcEnCiel", "Potion arc-en-ciel", hex("ff80c0") },
			{ "LuthFees", "Luth des fées", hex("ffd0a0") },
			{ "CouronneReineFees", "Couronne de la reine des fées", hex("ffa0f0") },
			{ "CorneLicorne", "Corne de licorne", hex("f0f0ff") },
			{ "VoeuBouteille", "Vœu en bouteille", hex("ffffa0") },
		} },
	{ id = "LaboSecret", name = "Laboratoire secret", sound = "Rock", impact = hex("b0c0c0"),
		walls = { hex("8a9098"), hex("a0a8b0"), hex("6f757d") }, ore = { hex("50ff50") },
		relics = {
			{ "TubeEssai", "Tube à essai", hex("c0f0f0") },
			{ "BadgeAcces", "Badge d'accès", hex("d0d0d0") },
			{ "ClavierCasse", "Clavier cassé", hex("303038") },
			{ "FioleVerte", "Fiole verte", hex("50ff70") },
			{ "CerveauBocal", "Cerveau en bocal", hex("ff90a0") },
			{ "RobotPrototype", "Robot prototype", hex("a0a8c0") },
			{ "PistoletLaser", "Pistolet laser", hex("ff3050") },
			{ "CubeAntimatiere", "Cube d'antimatière", hex("b040ff") },
			{ "MachineTemps", "Machine à remonter le temps", hex("c0a060") },
			{ "TrouNoirMiniature", "Trou noir miniature", hex("200030") },
		} },
	{ id = "EpaveAlien", name = "Épave extraterrestre", sound = "Rock", impact = hex("70e0b0"),
		walls = { hex("3a4a4a"), hex("4a5f5f"), hex("2a3838") }, ore = { hex("60ff90"), hex("60c0ff") },
		relics = {
			{ "ToleAlien", "Tôle extraterrestre", hex("9ab0b0") },
			{ "BoulonEtrange", "Boulon étrange", hex("708080") },
			{ "CasqueSpatial", "Casque spatial", hex("e0e8f0") },
			{ "RationGalactique", "Ration galactique", hex("a0ff60") },
			{ "CristalEnergie", "Cristal d'énergie", hex("60ffc0") },
			{ "TraducteurUniversel", "Traducteur universel", hex("40a0ff") },
			{ "RayonTracteur", "Rayon tracteur", hex("80ff80") },
			{ "CarteStellaire", "Carte stellaire", hex("4060ff") },
			{ "OeufAlien", "Œuf extraterrestre", hex("50e050") },
			{ "CoeurVaisseauMere", "Cœur du vaisseau-mère", hex("00ffff") },
		} },
	{ id = "Abysses", name = "Abysses", sound = "Water", impact = hex("2060a0"),
		walls = { hex("102030"), hex("18304a"), hex("0a1828") }, ore = { hex("40ffe0"), hex("a050ff") },
		relics = {
			{ "DentRequin", "Dent de requin", hex("f0f0e8") },
			{ "EcailleAbyssale", "Écaille abyssale", hex("2050a0") },
			{ "LanterneBaudroie", "Lanterne de baudroie", hex("a0ff80") },
			{ "CasqueScaphandrier", "Casque de scaphandrier", hex("c08a40") },
			{ "PerleAbysses", "Perle des abysses", hex("a0c0ff") },
			{ "TentaculeFossile", "Tentacule fossile", hex("a04080") },
			{ "CompasProfondeurs", "Compas des profondeurs", hex("40e0c0") },
			{ "OeilLeviathan", "Œil du léviathan", hex("ffcc30") },
			{ "NautileOr", "Nautile d'or", hex("ffd060") },
			{ "CoeurOcean", "Cœur de l'océan", hex("0080ff") },
		} },
	{ id = "RoyaumeOmbres", name = "Royaume des ombres", sound = "Rock", impact = hex("503070"),
		walls = { hex("201828"), hex("2a2035"), hex("151020") }, ore = { hex("a040ff") },
		relics = {
			{ "BougieNoire", "Bougie noire", hex("202020") },
			{ "ChaineSpectrale", "Chaîne spectrale", hex("8080a0") },
			{ "MiroirFele", "Miroir fêlé", hex("c0c0d8") },
			{ "PlumeCorbeau", "Plume de corbeau", hex("101018") },
			{ "LanterneFantome", "Lanterne fantôme", hex("80ffd0") },
			{ "GrimoireOmbres", "Grimoire des ombres", hex("402060") },
			{ "FauxSpectrale", "Faux spectrale", hex("a0a0c0") },
			{ "CouronneNuit", "Couronne de la nuit", hex("6040ff") },
			{ "OrbeEclipse", "Orbe d'éclipse", hex("300050") },
			{ "EtoileNoire", "Étoile noire", hex("8000ff") },
		} },
	{ id = "ManteauTerrestre", name = "Manteau terrestre", sound = "Rock", impact = hex("ff8040"),
		walls = { hex("6a2a18"), hex("8a3a20"), hex("4a1a10") }, ore = { hex("ffcc30"), hex("ff6010") },
		relics = {
			{ "BasalteChaud", "Basalte chaud", hex("3a3030") },
			{ "CristalSoufre", "Cristal de soufre", hex("f0e040") },
			{ "PeridotBrut", "Péridot brut", hex("90d040") },
			{ "DiamantNoir", "Diamant noir", hex("202028") },
			{ "GeodeFeu", "Géode de feu", hex("ff6030") },
			{ "RubisGeant", "Rubis géant", hex("ff1040") },
			{ "TitaneVivant", "Titane vivant", hex("c0c8d8") },
			{ "SaphirEtoile", "Saphir étoilé", hex("2050ff") },
			{ "DiamantArcEnCiel", "Diamant arc-en-ciel", hex("ffd0ff") },
			{ "LarmeTerre", "Larme de la Terre", hex("ff8000") },
		} },
	{ id = "CoeurMonde", name = "Cœur du monde", sound = "Rock", impact = hex("fff0a0"),
		walls = { hex("ffcf60"), hex("ffb040"), hex("ffe090") }, ore = { hex("ffffff"), hex("ff60ff") },
		relics = {
			{ "PoussiereEtoile", "Poussière d'étoile", hex("fff8d0") },
			{ "PierreOrigine", "Pierre d'origine", hex("e0c080") },
			{ "FragmentAube", "Fragment d'aube", hex("ffd0a0") },
			{ "CristalTemps", "Cristal du temps", hex("a0e0ff") },
			{ "PlumeCreation", "Plume de la création", hex("ffffff") },
			{ "SphereHarmonie", "Sphère d'harmonie", hex("c0ffd0") },
			{ "SablierInfini", "Sablier de l'infini", hex("ffd060") },
			{ "CouronneMonde", "Couronne du monde", hex("ffcc00") },
			{ "OeilCreateur", "Œil du créateur", hex("ff80ff") },
			{ "EtincelleOrigine", "Étincelle d'origine", hex("ffffff") },
		} },
}

---------------------------------------------------------------------------
-- COURBE DES ZONES : les chiffres de chaque zone sont calculés ici.
--   Les 3 premières gardent leurs valeurs d'origine ; à partir de la 4e :
--   puissance requise x PowerGrowth et valeur de base x ValueGrowth par zone.
--   Chaque nouvelle zone occupe BandHeight studs de paroi.
---------------------------------------------------------------------------
Config.ZoneCurve = {
	FirstZones = {
		{ requiredPower = 25, baseValue = 10, depth = 45, bandBottom = 70, descentTime = 1.05 },
		{ requiredPower = 39, baseValue = 32, depth = 100, bandBottom = 125, descentTime = 1.6 },
		{ requiredPower = 60, baseValue = 102, depth = 155, bandBottom = 170, descentTime = 2 },
	},
	PowerGrowth = 1.5,
	ValueGrowth = 1.5,
	BandHeight = 50,
	StopAboveBandBottom = 15, -- l'aimant s'arrête à ça au-dessus du bas de sa bande
	DescentTimeLast = 3.5, -- secondes de chute pour la zone la plus profonde (avant amélioration du câble)
	HangHeight = 12, -- l'aimant part d'environ 12 studs au-dessus du bord
}

-- Ordre des raretés des 10 reliques d'une zone
Config.RelicRarityOrder = { "Commun", "Commun", "PeuCommun", "PeuCommun", "Rare", "Rare", "Epique", "Legendaire", "Mythique", "Secret" }

-- Zones finales (calculées) : id, name, requiredPower, baseValue, depth,
-- bandBottom, descentSpeed, wallColors, oreColors, impactColor, impactSound
Config.Zones = {}
do
	local curve = Config.ZoneCurve
	local first = curve.FirstZones
	local last = first[#first]
	local count = #Config.ZoneList
	for index, theme in ipairs(Config.ZoneList) do
		local numbers = first[index]
		if not numbers then
			local steps = index - #first
			local bandBottom = last.bandBottom + steps * curve.BandHeight
			local t = steps / math.max(1, count - #first)
			numbers = {
				requiredPower = math.floor(last.requiredPower * curve.PowerGrowth ^ steps + 0.5),
				baseValue = math.floor(last.baseValue * curve.ValueGrowth ^ steps + 0.5),
				bandBottom = bandBottom,
				depth = bandBottom - curve.StopAboveBandBottom,
				descentTime = last.descentTime + (curve.DescentTimeLast - last.descentTime) * t,
			}
		end
		table.insert(Config.Zones, {
			id = theme.id,
			name = theme.name,
			requiredPower = numbers.requiredPower,
			baseValue = numbers.baseValue,
			depth = numbers.depth,
			bandBottom = numbers.bandBottom,
			descentSpeed = (curve.HangHeight + numbers.depth) / numbers.descentTime,
			wallColors = theme.walls,
			oreColors = theme.ore,
			impactColor = theme.impact,
			impactSound = theme.sound == "Water" and "ImpactWater" or "ImpactRock",
		})
	end
end

---------------------------------------------------------------------------
-- CHANCE
--   Chaque zone traversée AU-DESSUS de la zone atteinte ajoute LuckPerZone.
--   (Plage = 0 zone traversée, Forêt = 1, Mine = 2)
--   La chance multiplie les poids de Rare et au-dessus ; Commun absorbe la
--   différence et ne descend jamais sous CommonFloor.
---------------------------------------------------------------------------
Config.Luck = {
	LuckPerZone = 0.03,
	CommonFloor = 5, -- en %
}

---------------------------------------------------------------------------
-- RARETÉS (ordre croissant).
--   announce   : annonce à tout le serveur à la révélation
--   skyBeam    : faisceau vers le ciel à la sortie du canyon et à la révélation
--   slowMotion : arrêt sur image + ralenti juste avant la sortie (Secret)
--
--   tease (0..1) : tension PENDANT L'ATTENTE au fond (câble qui se tend,
--                  secousses, grondement). 0 = attente normale.
--   teaseGlow    : des reflets de la couleur de rareté trahissent la relique
--
--   ascent : remontée
--     slowFactor   : durée de remontée x ce facteur (1 = normal)
--     chunks       : nombre d'à-coups
--     shake        : tremblement caméra continu (studs)
--     lightBrightness / lightRange : lueur (PointLight)
--     particleRate : particules qui s'échappent du canyon (par seconde)
--     sting / stingVolume : son joué au départ de la remontée
--     loops        : couches de sons en boucle pendant la remontée (volume qui monte)
--     cameraDive   : (plus utilisé : la caméra suit maintenant toutes les remontées)
--     silence      : secondes de silence total juste avant la sortie (0 = aucun)
--
--   arrival : sortie du canyon
--     sounds       : sons joués ensemble à la sortie ("explosion" sonore)
--     shockwaves   : nombre d'ondes de choc
--
--   reveal : révélation après nettoyage
--     burst        : nombre de particules
--     shockwaves   : nombre d'ondes de choc
--     sounds       : sons de révélation
--     title        : bandeau au-dessus du nom sur la carte (nil = aucun)
--     rainbow      : bandeau / contour animé arc-en-ciel
---------------------------------------------------------------------------
Config.Rarities = {
	{
		id = "Commun", name = "Commun", chance = 60, mult = 1,
		color = Color3.fromRGB(200, 200, 200), isRare = false, tease = 0,
		reveal = { burst = 15, shockwaves = 0, sounds = { "Flash" } },
	},
	{
		id = "PeuCommun", name = "Peu commun", chance = 25, mult = 2,
		color = Color3.fromRGB(110, 220, 110), isRare = false, tease = 0,
		reveal = { burst = 25, shockwaves = 0, sounds = { "Flash" } },
	},
	{
		id = "Rare", name = "Rare", chance = 10, mult = 4,
		color = Color3.fromRGB(80, 160, 255), isRare = true, tease = 0.3,
		ascent = {
			slowFactor = 2.2, chunks = 3, shake = 0.15, lightBrightness = 2, lightRange = 12, particleRate = 15,
			sting = "RareGlow", stingVolume = 1, loops = { "TensionRumble" }, cameraDive = false, silence = 0,
		},
		arrival = { sounds = { "ArrivalBoom" }, shockwaves = 0 },
		reveal = { burst = 50, shockwaves = 1, sounds = { "RareGlow" }, title = "RARE !" },
	},
	{
		id = "Epique", name = "Épique", chance = 3.5, mult = 10,
		color = Color3.fromRGB(190, 90, 255), isRare = true, tease = 0.5,
		ascent = {
			slowFactor = 2.8, chunks = 4, shake = 0.3, lightBrightness = 5, lightRange = 18, particleRate = 35,
			sting = "EpicGlow", stingVolume = 1.2, loops = { "TensionRumble" }, cameraDive = true, silence = 0,
		},
		arrival = { sounds = { "ArrivalBoom", "Flash" }, shockwaves = 1 },
		reveal = { burst = 90, shockwaves = 1, sounds = { "EpicGlow" }, title = "ÉPIQUE !" },
	},
	{
		id = "Legendaire", name = "Légendaire", chance = 1, mult = 25,
		color = Color3.fromRGB(255, 190, 40), isRare = true, announce = true, tease = 0.7,
		ascent = {
			slowFactor = 3.4, chunks = 5, shake = 0.45, lightBrightness = 8, lightRange = 24, particleRate = 60,
			sting = "LegendarySting", stingVolume = 1.5, loops = { "TensionRumble", "Riser" }, cameraDive = true, silence = 0.5,
		},
		arrival = { sounds = { "ArrivalBoom", "LegendarySting" }, shockwaves = 1 },
		reveal = { burst = 150, shockwaves = 2, sounds = { "VictorySting", "EpicGlow" }, title = "★ LÉGENDAIRE ★" },
	},
	{
		id = "Mythique", name = "Mythique", chance = 0.4, mult = 60,
		color = Color3.fromRGB(255, 70, 110), isRare = true, announce = true, skyBeam = true, tease = 0.85, teaseGlow = true,
		ascent = {
			slowFactor = 4, chunks = 6, shake = 0.6, lightBrightness = 12, lightRange = 30, particleRate = 90,
			sting = "MythicSting", stingVolume = 1.5, loops = { "TensionRumble", "Throb", "Riser" }, cameraDive = true, silence = 0.7,
		},
		arrival = { sounds = { "ArrivalBoom", "MythicSting" }, shockwaves = 2 },
		reveal = { burst = 220, shockwaves = 2, sounds = { "VictorySting", "Choir" }, title = "✦ MYTHIQUE ✦" },
	},
	{
		id = "Secret", name = "Secret", chance = 0.1, mult = 150,
		color = Color3.fromRGB(20, 255, 230), isRare = true, announce = true, skyBeam = true, slowMotion = true,
		tease = 1, teaseGlow = true,
		ascent = {
			slowFactor = 4.5, chunks = 6, shake = 0.8, lightBrightness = 16, lightRange = 40, particleRate = 140,
			sting = "Choir", stingVolume = 1.5, loops = { "TensionRumble", "Throb", "Riser" }, cameraDive = true, silence = 0,
		},
		arrival = { sounds = { "ArrivalBoom", "SecretSting", "MythicSting" }, shockwaves = 3 },
		reveal = { burst = 350, shockwaves = 3, sounds = { "VictorySting", "Choir", "EpicGlow" }, title = "✨ SECRET ✨", rainbow = true },
	},
	-- Ultra-rares : leurs objets (zone « Cosmos ») peuvent tomber dans N'IMPORTE quelle zone (global = true).
	-- chance = nombre d'objets / (1 sur X voulu) : 4 Divins à 1 sur 250 000 ; 3 Cosmiques à 1 sur 1 000 000
	{
		id = "Divin", name = "Divin", chance = 0.0016, mult = 600, global = true,
		color = Color3.fromRGB(255, 236, 140), isRare = true, announce = true, skyBeam = true, slowMotion = true,
		tease = 1, teaseGlow = true,
		ascent = {
			slowFactor = 5, chunks = 7, shake = 0.9, lightBrightness = 20, lightRange = 50, particleRate = 180,
			sting = "Choir", stingVolume = 1.6, loops = { "TensionRumble", "Throb", "Riser" }, cameraDive = true, silence = 0,
		},
		arrival = { sounds = { "ArrivalBoom", "SecretSting", "MythicSting" }, shockwaves = 4 },
		reveal = { burst = 450, shockwaves = 4, sounds = { "VictorySting", "Choir", "EpicGlow" }, title = "☀ DIVIN ☀", rainbow = false },
	},
	{
		id = "Cosmique", name = "Cosmique", chance = 0.0003, mult = 2500, global = true,
		color = Color3.fromRGB(138, 92, 255), isRare = true, announce = true, skyBeam = true, slowMotion = true,
		tease = 1, teaseGlow = true,
		ascent = {
			slowFactor = 5.5, chunks = 8, shake = 1, lightBrightness = 24, lightRange = 60, particleRate = 220,
			sting = "Choir", stingVolume = 1.7, loops = { "TensionRumble", "Throb", "Riser" }, cameraDive = true, silence = 0,
		},
		arrival = { sounds = { "ArrivalBoom", "SecretSting", "MythicSting" }, shockwaves = 5 },
		reveal = { burst = 600, shockwaves = 5, sounds = { "VictorySting", "Choir", "EpicGlow" }, title = "🌌 COSMIQUE 🌌", rainbow = true },
	},
}

---------------------------------------------------------------------------
-- RELIQUES : générées depuis Config.ZoneList (10 par zone).
--   Chaque relique : id, name, zone, rarity, color
---------------------------------------------------------------------------
-- Catalogue complet (1 007 trouvailles : 40 par zone + 7 « Cosmos ») généré par
-- tools/relic_catalog.py à partir des listes ci-dessus + objets de base par zone.
-- Pour ajouter / renommer des objets : modifier le générateur et le relancer.
Config.Relics = require(script.Parent:WaitForChild("RelicCatalog"))

-- Index id -> objet, et nombre d'objets par rareté (pour les probabilités affichées)
Config.RelicById = {}
Config.RarityItemCount = {}
for _, relic in ipairs(Config.Relics) do
	Config.RelicById[relic.id] = relic
	Config.RarityItemCount[relic.rarity] = (Config.RarityItemCount[relic.rarity] or 0) + 1
end

---------------------------------------------------------------------------
-- MUSÉE
---------------------------------------------------------------------------
Config.Museum = {
	Slots = 6, -- socles de base (+ amélioration « Places au musée », voir Config.GetMuseumSlots)
	IncomeRatePerMinute = 0.015, -- 1,5 % de la valeur par minute
	TickSeconds = 1, -- fréquence de versement du revenu passif
	-- Un musée par joueur = un enclos en bois ouvert, de part et d'autre d'une rue
	-- principale (axe X, z = 0). Entrée côté rue, banc de développé couché sur la rue
	-- devant l'entrée. L'enclos s'allonge vers l'arrière quand on débloque des socles.
	-- Nombre de musées = #PlotColumnsX * 2 côtés (= joueurs max).
	PlotColumnsX = { 72, 99.5, 127 }, -- centres des enclos le long de la rue
	PlotWidth = 26, -- largeur d'un enclos (le long de la rue)
	StreetHalfWidth = 16, -- la clôture avant est à |z| = 16 (bancs + allée entre les deux rangées)
	FrontMargin = 6, -- de la clôture avant à la 1re rangée de socles
	RowSpacing = 9, -- entre deux rangées de socles (vers l'arrière)
	ColumnSpacing = 8, -- entre deux socles d'une rangée
	Columns = 3,
	BackMargin = 6, -- de la dernière rangée à la clôture du fond
	EntranceWidth = 7, -- ouverture dans la clôture avant
	EntranceOffset = 3, -- l'entrée est décalée le long de la rue (le banc est de l'autre côté)
	EntranceDistance = 3, -- point de téléportation : dans la rue, devant l'entrée
	-- Taille d'affichage (plus grande dimension, studs) selon la rareté : proportionnelle
	DisplaySize = {
		Commun = 4, PeuCommun = 4.8, Rare = 5.8, Epique = 7, Legendaire = 8.5,
		Mythique = 10.5, Secret = 14, Divin = 18, Cosmique = 24,
	},
	BeamFromRarity = "Legendaire", -- faisceau de lumière vers le ciel à partir de cette rareté
	BeamHeight = 160,
	PodiumPosition = Vector3.new(156, 0, 0), -- au bout de la rue (y = niveau du sol)
	PodiumRefresh = 20, -- secondes entre deux mises à jour du top 3
}

---------------------------------------------------------------------------
-- ZONE DE LANCER (point unique partagé par tous les joueurs)
---------------------------------------------------------------------------
Config.ThrowZone = {
	Size = Vector3.new(5, 8, 5), -- volume de détection posé sur le bout du ponton
	EnterDelay = 0.4, -- délai avant la jauge quand on entre dans la zone
	RestartDelay = 1.2, -- après une relique, la jauge repart seule si on est resté dans la zone
	ServerTolerance = 6, -- marge (studs) de la vérification serveur
}

---------------------------------------------------------------------------
-- MULTIJOUEUR
---------------------------------------------------------------------------
Config.Multiplayer = {
	HideOthersDuringThrow = true, -- les autres joueurs disparaissent pendant ta cinématique
	HideRefresh = 0.25, -- secondes entre deux rafraîchissements du masquage
	CollisionGroup = "ThrowARelicPlayers", -- les joueurs ne se poussent pas sur le ponton
}

---------------------------------------------------------------------------
-- SAUVEGARDE (DataStore)
--   En Studio, il faut que la place soit publiée et que
--   "Enable Studio Access to API Services" soit coché ; sinon le jeu
--   tourne en mémoire (rien n'est sauvegardé) et l'écrit dans la console.
---------------------------------------------------------------------------
Config.Save = {
	DataStoreName = "ThrowARelic_v2", -- changer le nom = repartir de zéro (v2 : économie 25 zones)
	KeyPrefix = "player_",
	Version = 1,
	AutoSaveInterval = 60, -- secondes
	Retries = 3,
	RetryDelay = 2,
	MinInterval = 6, -- secondes minimum entre deux écritures pour un même joueur
	CloseTimeout = 25, -- attente max des sauvegardes à la fermeture du serveur
}

---------------------------------------------------------------------------
-- NETTOYAGE
---------------------------------------------------------------------------
Config.Clean = {
	HoldDuration = 3, -- secondes d'appui maintenu
	ReleaseDecay = 1.5, -- vitesse de recul de la barre quand on relâche (x HoldDuration)
	ServerTolerance = 0.4, -- tolérance réseau côté serveur (secondes)
	MudColor = Color3.fromRGB(92, 66, 42),
	MudMaterial = Enum.Material.Ground,
	SpinSpeed = 25, -- rotation de la relique sur la plateforme (degrés/s)
	-- Ouverture du coffre (remplace le nettoyage ; même durée et même amélioration « Nettoyage »)
	LidCrackAngle = 16, -- le couvercle s'entrouvre jusqu'à cet angle pendant l'appui (degrés)
	LidOpenAngle = 115, -- puis saute à cet angle à l'ouverture
	RelicScaleOfChest = 0.85, -- taille de la relique qui sort, en part de la largeur du coffre
	RelicHoverHeight = 1.2, -- hauteur où elle flotte au-dessus du coffre ouvert
}

---------------------------------------------------------------------------
-- LANCER : point de chute aléatoire dans la gorge + cinématique
---------------------------------------------------------------------------
Config.Throw = {
	-- point de chute (tiré par le serveur) : le long du canyon (±LandingSpread autour du
	-- ponton) puis en travers dans la faille profonde (Config.CanyonAt), à SlotMargin des parois
	LandingSpread = 70,
	SlotMargin = 11,
	-- élan : caméra à hauteur d'épaule qui tourne autour du joueur
	OrbitDistance = 7,
	OrbitHeight = 1.4,
	OrbitStartAngle = 28, -- degrés (0 = pile derrière)
	OrbitSpeed = 95, -- degrés par seconde
	OrbitLookAhead = 6,
	OrbitSharpness = 12,
	WindupFOV = 55,
	-- élan au lasso : l'aimant tourne au-dessus de la tête avant d'être lancé
	LassoRaiseTime = 0.25,
	LassoTime = 1.4,
	LassoTurns = 3,
	LassoRadius = 3.2,
	LassoHeight = 1.2, -- centre du cercle au-dessus de la main
	LassoTilt = 0.7, -- inclinaison du cercle
	LassoArm = 170, -- bras levé (degrés)
	-- caméra de côté pendant l'élan (à hauteur du joueur)
	SideAngle = 90, -- 90 = pile sur le côté droit du joueur
	SideOrbit = -35, -- elle tourne vers l'avant pendant l'élan
	SideDistance = 12,
	SideDolly = 3, -- et se rapproche de ça
	SideHeight = 1.8,
	SideFocusHeight = 2.4,
	SideLookAhead = 1,
	SideSharpness = 9,
	SideHoldShare = 0.18, -- part du vol où la caméra reste sur le côté avant de poursuivre l'aimant
	-- vol de l'aimant : grand arc, la caméra le poursuit en s'inclinant
	FlightTimeBase = 0.85,
	FlightTimePerStud = 0.008,
	ArcHeightBase = 16,
	ArcHeightPerStud = 0.25,
	FlightSpins = 2,
	ChaseBack = 13,
	ChaseUp = 5,
	ChaseSide = 4,
	FlightSharpness = 7,
	FlightRoll = 10,
	FlightFOV = 84,
	-- retour : le treuil ramène l'aimant au ponton après la sortie du canyon
	ReelBackTime = 1.3,
	ReelBackArc = 10,
}

---------------------------------------------------------------------------
-- PROBABILITÉ QUI GRIMPE pendant la remontée : 1 SUR 1, 2, 5, 10, 20, 50…
-- jusqu'à la vraie valeur (affichée à la sortie du canyon), avec des paliers.
---------------------------------------------------------------------------
Config.OddsClimb = {
	StepMin = 0.16, -- secondes minimum entre deux étapes
	StepMax = 0.9, -- et maximum
	DurationShare = 0.9, -- les étapes occupent cette part de la remontée
	HoldAfter = 2.4, -- la valeur finale reste affichée ce temps après la sortie
	ShakeFromTier = 4, -- secousse de caméra à partir de ce palier
	Tiers = {
		{ min = 10, text = "Chanceux !", color = Color3.fromRGB(140, 255, 120) },
		{ min = 100, text = "Super chanceux !", color = Color3.fromRGB(90, 200, 255) },
		{ min = 1000, text = "Chance de dingue !", color = Color3.fromRGB(200, 110, 255) },
		{ min = 10000, text = "Chance de malade !!", color = Color3.fromRGB(255, 190, 40) },
		{ min = 100000, text = "Chance légendaire !!", color = Color3.fromRGB(255, 90, 90) },
		{ min = 1000000, text = "CHANCE DE DIEU !!!", color = Color3.fromRGB(255, 240, 150) },
		{ min = 100000000, text = "CHANCE COSMIQUE !!!", color = Color3.fromRGB(255, 255, 255), rainbow = true },
	},
}

---------------------------------------------------------------------------
-- ANIMATIONS (cœur du prototype)
---------------------------------------------------------------------------
Config.Anim = {
	-- A0. Animation du personnage qui lance (épaule droite + taille, procédurale)
	ThrowWindupTime = 0.32, -- le bras passe derrière la tête
	ThrowSnapTime = 0.12, -- le bras fouette vers l'avant (l'aimant part à la fin)
	ThrowRecoverTime = 0.45, -- retour à la pose normale
	ThrowWindupArm = 200, -- angle du bras armé (degrés ; 180 = tendu vers le haut)
	ThrowReleaseArm = 70, -- angle du bras au lâcher (vers l'avant)

	-- A. Lancer en arc (main -> au-dessus du trou)
	ArcDuration = 0.7,
	ArcHeight = 14, -- hauteur de la cloche de l'arc au-dessus de la ligne droite
	ArcSpins = 2, -- tours de l'aimant pendant l'arc
	PulleyHangOffset = 7, -- l'aimant pend à cette distance sous l'axe de la roue du chevalement (rayon 4)
	ImpactParticles = 40,
	DropSpins = 1.5, -- tours de l'aimant sur lui-même pendant la chute
	DropTrailLifetime = 0.25, -- longueur de la traînée blanche pendant la chute (secondes)

	-- B. Attente au fond
	WaitMin = 1,
	WaitMax = 2,
	CableVibrationAmplitude = 0.8, -- CurveSize du Beam (studs)
	CableVibrationFrequency = 14, -- Hz (approx.)

	-- C. Remontée normale
	AscentSpeed = 120, -- studs/s
	AscentMinDuration = 0.8,
	AscentMaxDuration = 2.2, -- remontée normale plafonnée (le canyon fait ~1 300 studs)
	ArrivalBounceHeight = 3, -- rebond à la sortie
	ArrivalBounceDuration = 0.45,
	ArrivalHold = 0.8, -- pause pour admirer une relique rare avant la plateforme

	-- B bis. Tension de l'attente (raretés avec `tease` > 0)
	TeaseExtraWait = 1.2, -- secondes d'attente en plus à tease = 1
	TeaseTugInterval = 0.45, -- secondes entre deux secousses du câble
	TeaseTugDepth = 0.9, -- l'aimant est tiré vers le bas de ça (studs, x tease)
	TeaseShake = 0.25, -- tremblement caméra à tease = 1
	TeaseGlowMax = 4, -- luminosité max des reflets (teaseGlow)

	-- D. Remontée rare
	RareChunkPause = 0.18, -- pause entre deux à-coups
	RareCableTenseWidth = 0.14, -- câble plus fin = tendu
	RareCableJitter = 0.15, -- vibration fine du câble tendu
	RareChunkKick = 1.8, -- pic de tremblement à chaque à-coup (x shake)
	GlowOrbSize = 3, -- sphère de lueur autour de la relique (x tier)
	LoopFadeIn = 1.5, -- montée en volume des boucles de remontée
	LoopPitchRise = 0.25, -- les boucles montent de ce pitch pendant la remontée
	SilenceFade = 0.12, -- coupure des sons avant le silence
	SlowMotionFreeze = 1, -- arrêt sur image TOTAL (Secret), en silence
	SlowMotionDuration = 2.2, -- puis ralenti (Secret)
	SlowMotionDistance = 8, -- studs parcourus pendant le ralenti
	SlowMotionParticleScale = 0.08, -- vitesse des particules pendant l'arrêt sur image
	SkyBeamHeight = 600,
	SkyBeamWidth = 5,
	SkyBeamRise = 0.35, -- durée de l'éruption du faisceau
	SkyBeamHold = 3, -- durée de vie du faisceau à la sortie du canyon
	LightColumnWidth = 1.4, -- colonne de lumière sous l'aimant pendant la remontée
	FlashDuration = 0.5,
	ArrivalKick = 1.5, -- secousse caméra à la sortie (x shake de la rareté)
	ShockwaveSize = 40, -- diamètre final d'une onde de choc
	ShockwaveDuration = 0.8,
	ShockwaveStagger = 0.18, -- délai entre deux ondes

	-- Révélation
	RevealPopHeight = 3, -- la relique saute de la plateforme
	RevealPopDuration = 0.6,
	RevealCountUpTime = 1.2, -- compteur de valeur 0 -> valeur
	RevealButtonsDelay = 0.8, -- évite de vendre par erreur pendant l'animation
	RevealBeamDuration = 4, -- faisceau au-dessus de la relique (skyBeam)

	-- Magnet / câble
	CableWidth = 0.22, -- (sert de repère de tension pour la corde : plus petit = tendue)
	-- Corde 3D entre la main et l'aimant
	RopeSegments = 26,
	RopeThickness = 0.32,
	RopeColor = Color3.fromRGB(196, 158, 98),
	RopeColorDark = Color3.fromRGB(150, 114, 66), -- tons alternés : effet tressé
	RopeSag = 0.08, -- mou : flèche = distance horizontale x RopeSag...
	RopeMaxSag = 6, -- ...plafonnée à ça (studs)
	CableColor = Color3.fromRGB(40, 40, 45),
}

Config.Camera = {
	SlotRadius = 8, -- dans la faille, la caméra reste à ce rayon max de la colonne de descente
	ReturnDistance = 14, -- fin de cinématique : recul de la caméra derrière le joueur
	ReturnHeight = 5,
	ThrowFOV = 70,
	FollowSharpness = 6, -- plus grand = caméra plus réactive
	LetterboxHeight = 0.09, -- bandes noires pendant la cinématique (fraction de l'écran)
	GaugeOffset = Vector3.new(9, 7, 17), -- caméra pendant la jauge (relatif à la plateforme de lancer)
	-- Lancer en arc : vue d'ensemble depuis le bord (relatif à la poulie)
	DescentOffset = Vector3.new(26, 10, 22),
	-- Chute : la caméra poursuit l'aimant dans le canyon (relatif à l'aimant)
	ChaseOffset = Vector3.new(4, 12, 9),
	ChaseSharpness = 9, -- réactivité pendant la chute (plus petit = l'aimant distance la caméra)
	ChaseLookAhead = 10, -- la caméra vise ce nombre de studs SOUS l'aimant (on voit le fond arriver)
	ChaseFOV = 88, -- focale à pleine vitesse (sensation de vitesse)
	ChaseRoll = 6, -- inclinaison max de la caméra pendant la chute (degrés)
	-- Attente au fond : la caméra reste près de l'aimant (relatif à l'aimant)
	WaitOffset = Vector3.new(5, 9, 12),
	WaitPushIn = 0.35, -- la caméra se rapproche de 35 % pendant l'attente
	WaitFOV = 55,
	-- Remontée : suit la relique (relatif à l'aimant)
	DiveOffset = Vector3.new(5, 16, 16),
	DiveWallMargin = 3, -- distance minimale aux parois du canyon
	ExitOffset = Vector3.new(10, -6, 30), -- vue de la sortie, au-dessus du canyon (relatif à la poulie)
	ExitViewDistance = 25, -- la caméra remonte au bord quand l'aimant est à cette distance du haut
	SlowMotionFOV = 30,
	CleanOffset = Vector3.new(11, 6, 5), -- relatif à la plateforme de nettoyage
}

---------------------------------------------------------------------------
-- SONS (remplacer les ids librement ; "" = pas de son)
---------------------------------------------------------------------------
Config.Sounds = {
	Throw = { id = "rbxassetid://9113766300", volume = 0.6 },
	Reel = { id = "rbxassetid://9113766302", volume = 0.5 },
	ImpactWater = { id = "rbxassetid://9125703162", volume = 0.8 },
	ImpactRock = { id = "rbxassetid://9125869504", volume = 0.8 },
	RareGlow = { id = "rbxassetid://9116395089", volume = 0.6 },
	EpicGlow = { id = "rbxassetid://9116395424", volume = 1 },
	LegendarySting = { id = "rbxassetid://9047100306", volume = 1 },
	Flash = { id = "rbxassetid://9116394545", volume = 0.8 },
	Scrub = { id = "rbxassetid://9113597077", volume = 0.5 },
	-- Couches de remontée et révélations
	TensionRumble = { id = "rbxassetid://9112775165", volume = 0.7 }, -- grondement (boucle)
	Throb = { id = "rbxassetid://9116329971", volume = 0.6 }, -- pulsation grave (boucle)
	Riser = { id = "rbxassetid://1837834717", volume = 0.5 }, -- montée de tension (boucle)
	Heartbeat = { id = "rbxassetid://9119882039", volume = 0.9 }, -- battement pendant le ralenti
	ArrivalBoom = { id = "rbxassetid://9113042060", volume = 1.2 }, -- impact grave à la sortie
	MythicSting = { id = "rbxassetid://9040287624", volume = 1 }, -- coup d'orchestre
	SecretSting = { id = "rbxassetid://1836473422", volume = 1.2 }, -- fanfare
	VictorySting = { id = "rbxassetid://1844016113", volume = 0.9 },
	Choir = { id = "rbxassetid://1846115874", volume = 1 }, -- chœur
	Sell = { id = "rbxassetid://1169806635", volume = 0.6 },
	Train = { id = "", volume = 0.5 },
	-- Sons d'interface synthétisés sur mesure (Assets/Props/Sounds, script synth_sounds)
	UIHover = { id = "rbxassetid://72784439191136", volume = 0.25 },
	UIClick = { id = "rbxassetid://98592755580765", volume = 0.5 },
	UIPop = { id = "rbxassetid://112435490337374", volume = 0.4 },
	UIOpen = { id = "rbxassetid://76652428711679", volume = 0.45 },
	UICoin = { id = "rbxassetid://123867809974561", volume = 0.45 },
	UIBuy = { id = "rbxassetid://90476836956191", volume = 0.55 },
	UIError = { id = "rbxassetid://119201629811669", volume = 0.45 },
	UIDing = { id = "rbxassetid://72220612698567", volume = 0.55 },
	UIWhoosh = { id = "rbxassetid://122487120263056", volume = 0.4 },
}

---------------------------------------------------------------------------
-- MONDE (utilisé par WorldBuilder pour générer le décor placeholder)
---------------------------------------------------------------------------
Config.World = {
	RimY = 200, -- hauteur du bord du canyon
	-- Le canyon (Landscape) : sinueux, s'élargit et se resserre (voir Config.CanyonAt).
	-- Côté joueurs, son bord ne dépasse jamais X = CanyonEastRim (village, ponton).
	CanyonEastRim = 15,
	CanyonRegionX0 = -805, -- étendue du canyon voxel vers l'ouest
	CanyonRegionZ = 900, -- et le long de Z (±)
	-- (ancienne gorge rectangulaire : encore lus par quelques réglages de caméra)
	CanyonWidth = 150,
	CanyonLength = 700,
	CanyonCenterX = -60,
	CanyonDepth = 0, -- calculé en bas du fichier depuis la dernière zone
	TileSize = 10, -- taille des "voxels" des parois
	-- Brume du canyon : nappes translucides empilées (plus on regarde loin vers
	-- le bas, plus elles s'additionnent => on ne voit pas tous les étages)
	FogStartDepth = 140, -- 1re nappe (studs sous le bord) : Plage et Forêt restent visibles
	FogSpacing = 60, -- écart entre deux nappes
	FogTransparency = 0.5, -- transparence de chaque nappe (plus petit = brume plus épaisse)
	FogColorTop = Color3.fromRGB(225, 188, 155), -- poussière dorée du couchant
	FogColorBottom = Color3.fromRGB(45, 30, 40),
	StrataDepth = 140, -- le haut du puits prend les strates du Grand Canyon (au-dessus de la brume)
	FogWisps = true, -- volutes de particules sur chaque nappe
	Seed = 42,
}

---------------------------------------------------------------------------
-- SERVEUR
---------------------------------------------------------------------------
Config.Debug = {
	MoneyAmount = 1000, -- « Argent x2 » : double l'argent (au moins +MoneyAmount)
	PowerAmount = 10, -- « Puissance x2 » : double la puissance (au moins +PowerAmount)
}

Config.Server = {
	AscentTimeout = 45, -- si le client ne confirme pas la remontée, on passe quand même
	AnnouncementDuration = 5, -- durée d'affichage des annonces côté client
}

---------------------------------------------------------------------------
-- Helpers de lecture (purs, sans effet de bord)
---------------------------------------------------------------------------
function Config.GetZone(id: string)
	for index, zone in ipairs(Config.Zones) do
		if zone.id == id then
			return zone, index
		end
	end
	return nil, nil
end

function Config.GetRarity(id: string)
	for index, rarity in ipairs(Config.Rarities) do
		if rarity.id == id then
			return rarity, index
		end
	end
	return nil, nil
end

function Config.GetRelic(id: string)
	return Config.RelicById[id]
end

-- Probabilité d'obtenir CET objet précis : chance de sa rareté (en %, chance
-- du joueur comprise) répartie sur tous les objets de cette rareté du jeu.
-- Ex. : Commun 60 % / 375 objets = 0,16 % (1 sur 625).
function Config.GetItemOdds(rarityWeightPercent: number, rarityId: string): number
	local count = Config.RarityItemCount[rarityId] or 1
	return (rarityWeightPercent / 100) / count
end

-- 0,0016 -> "1 SUR 625" ; et le pourcentage lisible ("0,16 %")
function Config.FormatOdds(p: number): (string, string)
	if p <= 0 then
		return "?", "?"
	end
	local oneIn = math.max(1, math.floor(1 / p + 0.5))
	local percent = p * 100
	local digits = percent >= 1 and 1 or math.max(2, math.ceil(-math.log10(percent)) + 1)
	local percentText = (("%." .. digits .. "f"):format(percent)):gsub("%.?0+$", ""):gsub("%.", ",") .. " %"
	-- nombre complet avec espaces (« 1 SUR 1 000 000 » impressionne plus que « 1 M »)
	local grouped = tostring(oneIn):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	return "1 SUR " .. grouped, percentText
end

-- Valeur de base « continue » pour une puissance donnée (interpolée entre zones)
local function valueForPower(power: number): number
	local zones = Config.Zones
	if power <= zones[1].requiredPower then
		return zones[1].baseValue
	end
	for index = 1, #zones - 1 do
		local a, b = zones[index], zones[index + 1]
		if power < b.requiredPower then
			local t = math.log(power / a.requiredPower) / math.log(b.requiredPower / a.requiredPower)
			return a.baseValue * (b.baseValue / a.baseValue) ^ t
		end
	end
	local lastZone = zones[#zones]
	local growth = math.log(Config.ZoneCurve.ValueGrowth) / math.log(Config.ZoneCurve.PowerGrowth)
	return lastZone.baseValue * (power / lastZone.requiredPower) ^ growth
end

function Config.GetPowerCost(power: number): number
	return math.floor(Config.Upgrades.Power.costMultiplier * valueForPower(power) + 0.5)
end

function Config.GetPowerGain(power: number): number
	local def = Config.Upgrades.Power
	return math.max(def.minGain, math.floor(power * def.percent + 0.5))
end

-- Prix du prochain niveau, ou nil si niveau max
function Config.GetUpgradeCost(id: string, level: number): number?
	local def = Config.Upgrades[id]
	if not def or not def.maxLevel or level >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.costGrowth ^ level + 0.5)
end

function Config.GetLuckMultiplier(magnetLevel: number): number
	return 1 + Config.Upgrades.Magnet.luckPerLevel * (magnetLevel or 0)
end

function Config.GetSpeedMultiplier(cableLevel: number): number
	return 1 + Config.Upgrades.Cable.speedPerLevel * (cableLevel or 0)
end

function Config.GetCleanDuration(cleanLevel: number): number
	return Config.Clean.HoldDuration - Config.Upgrades.Clean.secondsPerLevel * (cleanLevel or 0)
end

function Config.GetMuseumSlots(museumLevel: number): number
	return Config.Museum.Slots + Config.Upgrades.Museum.slotsPerLevel * (museumLevel or 0)
end

Config.Museum.MaxSlots = Config.GetMuseumSlots(Config.Upgrades.Museum.maxLevel)

-- Profondeur du canyon : juste sous la dernière zone
Config.World.CanyonDepth = Config.Zones[#Config.Zones].bandBottom + 10

-- Forme du canyon pour une coordonnée z (partagée : décor, serveur, client).
-- Renvoie : bord côté joueurs (x), axe (x), demi-largeur au bord, demi-largeur de
-- la faille profonde au fond (là où l'aimant descend vers les zones).
-- Près du village (|z| < 60) le bord reste collé au ponton ; plus loin il serpente.
function Config.CanyonAt(z: number): (number, number, number, number)
	local far = math.clamp((math.abs(z) - 60) / 140, 0, 1)
	local east = Config.World.CanyonEastRim - far * (28 + 26 * math.sin(z / 150 + 1.1))
	local half = 95 + 30 * math.sin(z / 230 - 0.9) + 12 * math.sin(z / 85 + 2)
	local slot = 22 + 7 * math.sin(z / 55 + 1.7)
	return east, east - half, half, slot
end

-- 1234 -> "1 234" ; 12 500 -> "12,5 k" ; 3 400 000 -> "3,4 M" ; 2e9 -> "2 Md"
local SUFFIXES = { { 1e12, "T" }, { 1e9, "Md" }, { 1e6, "M" }, { 1e4, "k" } }
function Config.FormatNumber(n: number): string
	n = math.floor(n or 0)
	for _, entry in ipairs(SUFFIXES) do
		if math.abs(n) >= entry[1] then
			local scaled = n / (entry[1] == 1e4 and 1e3 or entry[1])
			local text = scaled >= 100 and ("%d"):format(math.floor(scaled)) or ("%.1f"):format(math.floor(scaled * 10) / 10)
			return (text:gsub("%.0$", ""):gsub("%.", ",")) .. " " .. entry[2]
		end
	end
	local text = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	return (n < 0 and "-" or "") .. text
end

return Config

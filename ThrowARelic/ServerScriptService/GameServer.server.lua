--[[
	GameServer (Script)
	Emplacement : ServerScriptService/GameServer

	Autorité du jeu : argent, puissance, tirage des reliques, musées, verrou de
	lancer, sauvegarde. Le client ne fait QUE de l'affichage et envoie des intentions.

	Cycle d'un lancer (phase par joueur) :
	  Idle --RequestThrow--> Throwing --AscentDone--> Landed --CleanDone--> Cleaned --Sell/Expose--> Idle

	Multijoueur : un point de lancer partagé (ThrowZone), un musée par joueur
	(Museums/Museum<i>, attribué à l'arrivée). Les joueurs ne se poussent pas.
	Sauvegarde : argent, puissance, améliorations, collection, musée, et la
	relique en cours (rendue sur la plateforme de nettoyage à la connexion suivante).
	Améliorations : Puissance, Aimant (chance), Câble (vitesse), Nettoyage,
	Places au musée. Collection : 10 reliques d'une zone = +10 % sur cette zone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local SaveService = require(script.Parent:WaitForChild("SaveService"))
local BenchService = require(script.Parent:WaitForChild("BenchService"))

WorldBuilder.Build()

---------------------------------------------------------------------------
-- RemoteEvents / RemoteFunctions
---------------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function getRemote(className: string, name: string)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end

local TrainEvent = getRemote("RemoteEvent", "Train")
local BuyPowerFn = getRemote("RemoteFunction", "BuyPower")
local RequestThrowFn = getRemote("RemoteFunction", "RequestThrow")
local AscentDoneEvent = getRemote("RemoteEvent", "AscentDone")
local CleanDoneFn = getRemote("RemoteFunction", "CleanDone")
local SellFn = getRemote("RemoteFunction", "Sell")
local ExposeFn = getRemote("RemoteFunction", "Expose")
local AnnounceEvent = getRemote("RemoteEvent", "Announce")
local NotifyEvent = getRemote("RemoteEvent", "Notify")
local ClientReadyEvent = getRemote("RemoteEvent", "ClientReady")
local RestorePendingEvent = getRemote("RemoteEvent", "RestorePending")
local DebugFn = getRemote("RemoteFunction", "Debug")
-- Lancers des autres : le lanceur signale le début de sa remontée, le serveur
-- relaie start / ascent / done à tous les AUTRES joueurs (affichage seulement)
local AscentStartEvent = getRemote("RemoteEvent", "AscentStart")
local OtherThrowEvent = getRemote("RemoteEvent", "OtherThrow")
local BuyUpgradeFn = getRemote("RemoteFunction", "BuyUpgrade")
local GetCollectionFn = getRemote("RemoteFunction", "GetCollection")
local CollectionEvent = getRemote("RemoteEvent", "CollectionUpdate")

local function broadcastOthers(thrower: Player, payload)
	payload.userId = thrower.UserId
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= thrower then
			OtherThrowEvent:FireClient(other, payload)
		end
	end
end

---------------------------------------------------------------------------
-- Données joueur
---------------------------------------------------------------------------
local Phase = {
	Idle = "Idle",
	Throwing = "Throwing",
	Landed = "Landed",
	Cleaned = "Cleaned",
}

type RelicRecord = { relicId: string, name: string, rarityId: string, zoneId: string, value: number }
type PlayerData = {
	money: number,
	power: number,
	purchases: number, -- (ancien achat de puissance, conservé pour compatibilité)
	upgrades: { [string]: number }, -- Magnet / Cable / Clean / Museum -> niveau
	collection: { [string]: boolean }, -- reliques déjà trouvées (relicId)
	lastTrain: number,
	phase: string,
	throwId: number,
	pending: RelicRecord?,
	landedAt: number,
	forcedRarity: string?,
	museum: { [number]: RelicRecord },
	plot: number?, -- index du musée attribué
	saveEnabled: boolean, -- false si le chargement a échoué (on n'écrase rien)
	clientReady: boolean,
	restoreSent: boolean,
	saving: boolean, -- une écriture DataStore est en cours
	saveQueued: boolean, -- une autre sauvegarde a été demandée entre-temps
	lastSave: number,
	lastSavedJson: string?, -- pour ne pas réécrire des données identiques
	ascentRelayed: boolean?, -- remontée déjà relayée aux autres joueurs pour ce lancer
	pendingOdds: number?, -- probabilité de l'objet en cours (pour l'annonce)
}

local playerData: { [Player]: PlayerData } = {}
local readyPlayers: { [Player]: boolean } = {} -- clients prêts (peut arriver avant la fin du chargement)
local rng = Random.new()

local world = workspace:WaitForChild("ThrowARelicWorld")
local museumsFolder = world:WaitForChild("Museums")
local throwZone: BasePart = world:WaitForChild("ThrowZone")

local function notify(player: Player, message: string)
	NotifyEvent:FireClient(player, message)
end

-- Reliques par zone (pour le livre de collection)
local relicsByZone: { [string]: { string } } = {}
for _, relic in ipairs(Config.Relics) do
	relicsByZone[relic.zone] = relicsByZone[relic.zone] or {}
	table.insert(relicsByZone[relic.zone], relic.id)
end

local function upgradeLevel(data: PlayerData, id: string): number
	return data.upgrades[id] or 0
end

local function museumSlots(data: PlayerData): number
	return Config.GetMuseumSlots(upgradeLevel(data, "Museum"))
end

local function collectionCount(data: PlayerData): number
	local count = 0
	for _ in pairs(data.collection) do
		count += 1
	end
	return count
end

local function zoneComplete(data: PlayerData, zoneId: string): boolean
	local ids = relicsByZone[zoneId]
	if not ids then
		return false
	end
	for _, id in ipairs(ids) do
		if not data.collection[id] then
			return false
		end
	end
	return true
end

-- Valeur réelle d'une relique pour ce joueur (bonus de zone complétée compris)
local function valueFor(data: PlayerData, record): number
	local bonus = zoneComplete(data, record.zoneId) and Config.Collection.ZoneBonus or 0
	return math.floor(record.value * (1 + bonus) + 0.5)
end

local function sync(player: Player)
	local data = playerData[player]
	if not data then
		return
	end
	local used = 0
	for _ in pairs(data.museum) do
		used += 1
	end
	player:SetAttribute("Money", data.money)
	player:SetAttribute("Power", data.power)
	player:SetAttribute("PowerCost", Config.GetPowerCost(data.power))
	for _, id in ipairs(Config.UpgradeOrder) do
		if id ~= "Power" then
			player:SetAttribute("Upgrade" .. id, upgradeLevel(data, id))
		end
	end
	player:SetAttribute("MuseumSlots", museumSlots(data))
	player:SetAttribute("CollectionCount", collectionCount(data))
	player:SetAttribute("MuseumUsed", used)
	player:SetAttribute("MuseumIndex", data.plot or 0)
	player:SetAttribute("HasPending", data.pending ~= nil)
	player:SetAttribute("ForcedRarity", data.forcedRarity or "")
	if data.plot then
		BenchService.SetPlates(data.plot, data.power) -- les disques suivent la puissance
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Argent.Value = math.floor(data.money)
		leaderstats.Puissance.Value = data.power
	end
end

-- Construit un enregistrement de relique COHÉRENT avec la Config actuelle
-- (nom et valeur recalculés : si tu rééquilibres les valeurs, les sauvegardes suivent)
local function makeRecord(relicId: string, rarityId: string, zoneId: string): RelicRecord?
	local relic = Config.GetRelic(relicId)
	local rarity = Config.GetRarity(rarityId)
	local zone = Config.GetZone(zoneId)
	if not (relic and rarity and zone) then
		return nil
	end
	return { relicId = relicId, name = relic.name, rarityId = rarityId, zoneId = zoneId, value = zone.baseValue * rarity.mult }
end

---------------------------------------------------------------------------
-- Sauvegarde : conversion données <-> table stockable
---------------------------------------------------------------------------
local function recordToSave(record: RelicRecord)
	return { relicId = record.relicId, rarityId = record.rarityId, zoneId = record.zoneId }
end

local function recordFromSave(saved): RelicRecord?
	if typeof(saved) ~= "table" then
		return nil
	end
	local record = makeRecord(saved.relicId, saved.rarityId, saved.zoneId)
	if not record then
		warn("[GameServer] Relique sauvegardée inconnue, ignorée :", saved.relicId)
	end
	return record
end

local function snapshot(data: PlayerData)
	local collection = {}
	for id in pairs(data.collection) do
		table.insert(collection, id)
	end
	table.sort(collection)
	local museum = {}
	for slot, record in pairs(data.museum) do
		museum[tostring(slot)] = recordToSave(record) -- clés texte : format sûr pour le DataStore
	end
	return {
		version = Config.Save.Version,
		money = data.money,
		power = data.power,
		purchases = data.purchases,
		upgrades = data.upgrades,
		collection = collection,
		museum = museum,
		pending = data.pending and recordToSave(data.pending) or nil,
	}
end

local function applySaved(data: PlayerData, saved)
	if typeof(saved) ~= "table" then
		return
	end
	data.money = tonumber(saved.money) or data.money
	data.power = tonumber(saved.power) or data.power
	data.purchases = tonumber(saved.purchases) or data.purchases
	if typeof(saved.upgrades) == "table" then
		for id, def in pairs(Config.Upgrades) do
			local level = tonumber(saved.upgrades[id])
			if level and def.maxLevel then
				data.upgrades[id] = math.clamp(math.floor(level), 0, def.maxLevel)
			end
		end
	end
	if typeof(saved.collection) == "table" then
		for _, id in ipairs(saved.collection) do
			if typeof(id) == "string" and Config.GetRelic(id) then
				data.collection[id] = true
			end
		end
	end
	if typeof(saved.museum) == "table" then
		for key, savedRecord in pairs(saved.museum) do
			local slot = tonumber(key)
			local record = recordFromSave(savedRecord)
			if slot and record and slot >= 1 and slot <= museumSlots(data) then
				data.museum[slot] = record
			end
		end
	end
	data.pending = recordFromSave(saved.pending)
	if data.pending then
		-- la relique attend sur la plateforme : il ne reste qu'à la nettoyer
		data.phase = Phase.Landed
		data.landedAt = os.clock()
	end
end

local activeSaves = 0 -- écritures en cours (attendues à la fermeture du serveur)

-- Une seule écriture à la fois par joueur, espacées d'au moins MinInterval
-- (Roblox limite les écritures rapprochées sur une même clé). Une demande qui
-- arrive pendant une écriture est regroupée dans l'écriture suivante, et on
-- n'écrit rien si les données n'ont pas changé depuis la dernière fois.
local function savePlayer(player: Player)
	local data = playerData[player]
	if not data or not data.saveEnabled then
		return
	end
	if data.saving then
		data.saveQueued = true
		return
	end
	data.saving = true
	activeSaves += 1
	repeat
		data.saveQueued = false
		local waitTime = Config.Save.MinInterval - (os.clock() - data.lastSave)
		if waitTime > 0 then
			task.wait(waitTime)
		end
		local saved = snapshot(data)
		local json = HttpService:JSONEncode(saved)
		if json ~= data.lastSavedJson then
			if SaveService.Save(player.UserId, saved) then
				data.lastSavedJson = json
			end
			data.lastSave = os.clock()
		end
	until not data.saveQueued
	activeSaves -= 1
	data.saving = false
end

---------------------------------------------------------------------------
-- Tirage : zone atteinte, poids de rareté, relique
---------------------------------------------------------------------------
-- Zone atteinte selon puissance x précision (+ bonus si timing parfait).
-- La première zone est le minimum garanti.
local function computeThrow(power: number, gaugePosition: number)
	local distanceFromCenter = math.abs(gaugePosition - 0.5)
	local precision = 1 - distanceFromCenter * 2 -- 1 = centre parfait, 0 = bord
	local perfect = distanceFromCenter <= Config.Gauge.PerfectWindow
	local factor = Config.Gauge.MinPrecisionFactor + (1 - Config.Gauge.MinPrecisionFactor) * precision
	local effectivePower = power * factor * (perfect and Config.Gauge.PerfectBonus or 1)

	local zoneIndex = 1
	for index, zone in ipairs(Config.Zones) do
		if effectivePower >= zone.requiredPower then
			zoneIndex = index
		end
	end
	return zoneIndex, effectivePower, precision, perfect
end

-- Poids (en %) de chaque rareté pour une zone donnée.
-- Rareté n°1 (Commun) absorbe la différence et reste >= CommonFloor.
local function computeRarityWeights(zoneIndex: number, magnetLevel: number): { number }
	local luck = (1 + Config.Luck.LuckPerZone * (zoneIndex - 1)) * Config.GetLuckMultiplier(magnetLevel)
	local weights = {}
	local others = 0
	for index, rarity in ipairs(Config.Rarities) do
		if index > 1 then
			local weight = rarity.chance * (rarity.isRare and luck or 1)
			weights[index] = weight
			others += weight
		end
	end
	local common = 100 - others
	if common < Config.Luck.CommonFloor then
		local scale = (100 - Config.Luck.CommonFloor) / others
		for index = 2, #Config.Rarities do
			weights[index] *= scale
		end
		common = Config.Luck.CommonFloor
	end
	weights[1] = common
	return weights
end

local function rollRarity(zoneIndex: number, magnetLevel: number): string
	local weights = computeRarityWeights(zoneIndex, magnetLevel)
	local total = 0
	for _, weight in ipairs(weights) do
		total += weight
	end
	local roll = rng:NextNumber(0, total)
	for index, weight in ipairs(weights) do
		roll -= weight
		if roll <= 0 then
			return Config.Rarities[index].id
		end
	end
	return Config.Rarities[1].id
end

local function pickRelic(zoneId: string, rarityId: string)
	local candidates = {}
	local rarity = Config.GetRarity(rarityId)
	local global = rarity and rarity.global -- Divin / Cosmique : n'importe quelle zone
	for _, relic in ipairs(Config.Relics) do
		if relic.rarity == rarityId and (global or relic.zone == zoneId) then
			table.insert(candidates, relic)
		end
	end
	if #candidates == 0 then
		warn(("[GameServer] Aucune relique %s dans la zone %s : fallback"):format(rarityId, zoneId))
		for _, relic in ipairs(Config.Relics) do
			if relic.zone == zoneId then
				table.insert(candidates, relic)
			end
		end
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

---------------------------------------------------------------------------
-- Musées : attribution d'un bâtiment par joueur + affichage des reliques
---------------------------------------------------------------------------
local plotOwners: { [number]: Player } = {}

local function getPlot(index: number): Model?
	return museumsFolder:FindFirstChild("Museum" .. index) :: Model?
end

local function getDisplays(plot: Model): Folder
	local displays = plot:FindFirstChild("Displays")
	if not displays then
		displays = Instance.new("Folder")
		displays.Name = "Displays"
		displays.Parent = plot
	end
	return displays :: Folder
end

local function plotSignGui(plot: Model): SurfaceGui?
	local arch = plot:FindFirstChild("Arch")
	local board = arch and arch:FindFirstChild("SignBoard")
	return board and board:FindFirstChild("Stats") :: SurfaceGui?
end

local function setPlotSign(plot: Model, text: string)
	local gui = plotSignGui(plot)
	if gui then
		gui.Title.Text = text
	end
end

-- index de zone (pour les probabilités des trouvailles) ; les objets « Cosmos » sont hors zones
local zoneIndexById: { [string]: number } = {}
for index, zone in ipairs(Config.Zones) do
	zoneIndexById[zone.id] = index
end

-- Plus belle trouvaille du joueur : la plus rare de sa collection (à rareté égale, la moins probable)
local function bestFind(data: PlayerData)
	local best, bestTier, bestOdds = nil, 0, math.huge
	for relicId in pairs(data.collection) do
		local relic = Config.GetRelic(relicId)
		if relic then
			local _, tier = Config.GetRarity(relic.rarity)
			local weights = computeRarityWeights(zoneIndexById[relic.zone] or 1, 0)
			local odds = Config.GetItemOdds(weights[tier] or 0, relic.rarity)
			if tier > bestTier or (tier == bestTier and odds < bestOdds) then
				best, bestTier, bestOdds = relic, tier, odds
			end
		end
	end
	return best, bestOdds
end

-- Panneau au-dessus de l'entrée : valeur du musée, revenu, plus belle trouvaille
local function refreshPlotStats(plot: Model, data: PlayerData?)
	local gui = plotSignGui(plot)
	if not gui then
		return
	end
	if not data then
		gui.Value.Text = ""
		gui.Best.Text = ""
		gui.Odds.Text = ""
		return
	end
	local total = 0
	for _, record in pairs(data.museum) do
		total += valueFor(data, record)
	end
	gui.Value.Text = ("💰 %s $  ·  +%s $/min"):format(Config.FormatNumber(total), Config.FormatNumber(total * Config.Museum.IncomeRatePerMinute))
	local relic, odds = bestFind(data)
	if relic then
		local rarity = Config.GetRarity(relic.rarity)
		gui.Best.Text = ("⭐ %s (%s)"):format(relic.name, rarity.name)
		gui.Best.TextColor3 = rarity.color
		gui.Odds.Text = odds < math.huge and Config.FormatOdds(odds) or ""
	else
		gui.Best.Text = "Aucune trouvaille pour l'instant"
		gui.Best.TextColor3 = Color3.new(1, 1, 1)
		gui.Odds.Text = ""
	end
end

local function buildDisplay(plot: Model, slot: number, relic: RelicRecord, value: number)
	local pedestal = plot:FindFirstChild("Pedestal" .. slot)
	local template = ReplicatedStorage.Relics:FindFirstChild(relic.relicId)
	if not (pedestal and template) then
		warn("[GameServer] Socle ou modèle introuvable pour", relic.relicId)
		return
	end
	local rarity = Config.GetRarity(relic.rarityId)
	local model = template:Clone()
	model.Name = "Slot" .. slot
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	-- taille proportionnelle à la rareté (une Cosmique domine tout l'enclos)
	local targetSize = Config.Museum.DisplaySize[relic.rarityId] or 2.5
	local extents = model:GetExtentsSize()
	local largest = math.max(extents.X, extents.Y, extents.Z)
	if largest > 0 then
		model:ScaleTo(model:GetScale() * targetSize / largest)
	end
	local size = model:GetExtentsSize()
	-- face à la rue (le repère de l'enclos regarde vers le fond : on tourne de 180°)
	local plotFrame: CFrame? = plot:GetAttribute("PlotFrame")
	local facing = plotFrame and (plotFrame - plotFrame.Position) * CFrame.Angles(0, math.pi, 0) or CFrame.identity
	model:PivotTo(CFrame.new(pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + size.Y / 2, 0)) * facing)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(8, 2.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 2, 0)
	billboard.MaxDistance = 80 + size.Y * 10
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = rarity.color
	label.TextStrokeTransparency = 0
	local perMinute = value * Config.Museum.IncomeRatePerMinute
	label.Text = ("%s\n%s · +%s $/min"):format(relic.name, rarity.name, Config.FormatNumber(math.max(1, perMinute)))
	label.Parent = billboard
	billboard.Parent = model

	if rarity.isRare then
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Range = rarity.ascent.lightRange / 2
		light.Brightness = rarity.ascent.lightBrightness / 2
		light.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	end
	-- Faisceau de lumière vers le ciel (Légendaire et plus) : visible de toute la carte
	local _, tier = Config.GetRarity(relic.rarityId)
	local _, beamTier = Config.GetRarity(Config.Museum.BeamFromRarity)
	if tier >= beamTier then
		local anchor = Instance.new("Part")
		anchor.Name = "BeamAnchor"
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CFrame = CFrame.new(pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + size.Y * 0.6, 0))
		anchor.Parent = model
		local bottom = Instance.new("Attachment")
		bottom.Parent = anchor
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, Config.Museum.BeamHeight, 0)
		top.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Color = ColorSequence.new(rarity.color)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 1
		local width = 1 + (tier - beamTier) * 0.9
		beam.Width0 = width
		beam.Width1 = width * 2.2
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.7, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = anchor
	end
	model.Parent = getDisplays(plot)
end

-- Socles débloqués opaques, socles à acheter translucides
local function refreshPedestals(plot: Model, slots: number)
	local columns = Config.Museum.Columns
	local rows = math.ceil(slots / columns)
	WorldBuilder.SetPlotRows(plot, rows) -- clôture et plancher suivent
	for index = 1, Config.Museum.MaxSlots do
		local pedestal = plot:FindFirstChild("Pedestal" .. index)
		if pedestal then
			local inside = math.ceil(index / columns) <= rows
			pedestal.Transparency = index <= slots and 0 or (inside and 0.75 or 1)
			pedestal.CanCollide = index <= slots
		end
	end
end

-- Reconstruit toutes les vitrines (après un bonus de collection, par ex.)
local function rebuildDisplays(data: PlayerData)
	local plot = data.plot and getPlot(data.plot)
	if not plot then
		return
	end
	getDisplays(plot):ClearAllChildren()
	refreshPedestals(plot, museumSlots(data))
	for slot, record in pairs(data.museum) do
		buildDisplay(plot, slot, record, valueFor(data, record))
	end
	refreshPlotStats(plot, data)
end

local function assignPlot(player: Player, data: PlayerData)
	local index = 1
	while getPlot(index) do
		if not plotOwners[index] then
			plotOwners[index] = player
			data.plot = index
			local plot = getPlot(index) :: Model
			setPlotSign(plot, "MUSÉE DE " .. string.upper(player.DisplayName))
			rebuildDisplays(data)
			return
		end
		index += 1
	end
	warn("[GameServer] Plus de musée libre pour", player.Name, "(augmente Config.Museum.PlotColumnsX / PlotRowsZ)")
end

local function releasePlot(data: PlayerData)
	local index = data.plot
	if not index then
		return
	end
	plotOwners[index] = nil
	BenchService.ResetPlot(index)
	local plot = getPlot(index)
	if plot then
		getDisplays(plot):ClearAllChildren()
		refreshPedestals(plot, Config.Museum.Slots)
		setPlotSign(plot, "MUSÉE LIBRE")
		refreshPlotStats(plot, nil)
	end
end

---------------------------------------------------------------------------
-- Banc de développé couché devant chaque musée (voir BenchService)
---------------------------------------------------------------------------
BenchService.Init({
	museums = museumsFolder,
	ownerOf = function(index)
		return plotOwners[index]
	end,
	plotOf = function(player)
		local data = playerData[player]
		return data and data.plot
	end,
	getPower = function(player)
		local data = playerData[player]
		return data and data.power
	end,
	addPower = function(player, amount)
		local data = playerData[player]
		if data then
			data.power += amount
			sync(player)
		end
	end,
	canTrain = function(player)
		local data = playerData[player]
		return data ~= nil and data.phase ~= "Throwing"
	end,
})

---------------------------------------------------------------------------
-- Podium : statues dorées des 3 joueurs les plus riches du serveur
---------------------------------------------------------------------------
local podium = world:FindFirstChild("Podium")
local statueCache: { [number]: Model } = {} -- userId -> statue (avatar chargé une fois)
local STATUE_COLORS = { Color3.fromRGB(242, 193, 78), Color3.fromRGB(205, 210, 222), Color3.fromRGB(205, 127, 50) }

local function makeStatue(userId: number, rank: number): Model?
	local ok, avatar = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not avatar then
		return nil
	end
	local color = STATUE_COLORS[rank]
	for _, d in ipairs(avatar:GetDescendants()) do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("Decal") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Color = color
			d.Material = Enum.Material.Metal
			d.Reflectance = 0.15
			if d:IsA("MeshPart") then
				pcall(function()
					d.TextureID = ""
				end)
			end
		end
	end
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			animator:Destroy() -- statue : pas d'animation
		end
	end
	pcall(function()
		avatar:ScaleTo(1.5)
	end)
	return avatar
end

local podiumShown: { [number]: number } = {} -- rang -> userId affiché
local function refreshPodium()
	if not podium then
		return
	end
	local ranking = {}
	for player, data in pairs(playerData) do
		if player.Parent then
			table.insert(ranking, { player = player, money = data.money })
		end
	end
	table.sort(ranking, function(a, b)
		return a.money > b.money
	end)
	for rank = 1, 3 do
		local spot = podium:FindFirstChild("Spot" .. rank) :: BasePart?
		local entry = ranking[rank]
		if spot then
			local statueName = "Statue" .. rank
			local current = podium:FindFirstChild(statueName)
			local userId = entry and entry.player.UserId
			if podiumShown[rank] ~= userId then
				podiumShown[rank] = userId
				if current then
					current.Parent = nil -- gardée en cache
				end
				current = nil
				if userId then
					local cacheKey = userId * 10 + rank
					local statue = statueCache[cacheKey] or makeStatue(userId, rank)
					if statue and podiumShown[rank] == userId then
						statueCache[cacheKey] = statue
						statue.Name = statueName
						local extents = statue:GetExtentsSize()
						-- debout sur la marche, tourné vers la rue (comme le podium)
						statue:PivotTo(CFrame.new(spot.Position + Vector3.new(0, extents.Y / 2, 0)) * (spot.CFrame - spot.Position))
						statue.Parent = podium
						current = statue
					end
				end
			end
			-- étiquette : nom + fortune
			local tag = spot:FindFirstChild("Tag") :: BillboardGui?
			if not tag then
				tag = Instance.new("BillboardGui")
				tag.Name = "Tag"
				tag.Size = UDim2.fromScale(9, 2.6)
				tag.StudsOffsetWorldSpace = Vector3.new(0, 10.5, 0)
				tag.MaxDistance = 250
				local label = Instance.new("TextLabel")
				label.Name = "Label"
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.FredokaOne
				label.TextScaled = true
				label.TextStrokeTransparency = 0
				label.TextColor3 = STATUE_COLORS[rank]
				label.Parent = tag
				tag.Parent = spot
			end
			tag.Label.Text = entry and ("#%d %s\n💰 %s $"):format(rank, entry.player.DisplayName, Config.FormatNumber(entry.money)) or ("#%d —"):format(rank)
		end
	end
end

task.spawn(function()
	while true do
		task.wait(Config.Museum.PodiumRefresh)
		refreshPodium()
	end
end)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshPodium)
end)

---------------------------------------------------------------------------
-- Chute dans le canyon : on remonte le joueur au point d'apparition
---------------------------------------------------------------------------
task.spawn(function()
	local W = Config.World
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Position.Y < W.RimY - 25 and root.Position.X < W.CanyonEastRim + 2
				and root.Position.X > W.CanyonRegionX0 and math.abs(root.Position.Z) < W.CanyonRegionZ then
				local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
				local target = spawn and spawn.Position + Vector3.new(0, 4, 0) or Vector3.new(45, W.RimY + 5, 0)
				root.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(CFrame.new(target))
				notify(player, "😵 Attention au vide ! Retour au village.")
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Collisions : les joueurs se traversent (point de lancer partagé)
---------------------------------------------------------------------------
local collisionGroup = Config.Multiplayer.CollisionGroup
pcall(function()
	PhysicsService:RegisterCollisionGroup(collisionGroup)
end)
PhysicsService:CollisionGroupSetCollidable(collisionGroup, collisionGroup, false)

local function setCharacterGroup(character: Model)
	local function apply(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = collisionGroup
		end
	end
	for _, part in ipairs(character:GetDescendants()) do
		apply(part)
	end
	character.DescendantAdded:Connect(apply)
end

---------------------------------------------------------------------------
-- Relique en attente (déconnexion pendant un lancer) : on la rend au client
---------------------------------------------------------------------------
local function trySendRestore(player: Player)
	local data = playerData[player]
	if not data or not data.clientReady or data.restoreSent or not data.pending then
		return
	end
	data.restoreSent = true
	data.landedAt = os.clock() -- le nettoyage de 3 s commence maintenant
	local pending = data.pending
	RestorePendingEvent:FireClient(player, {
		relicId = pending.relicId,
		relicName = pending.name,
		rarityId = pending.rarityId,
		value = pending.value,
	})
end

---------------------------------------------------------------------------
-- Arrivée / départ des joueurs
---------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(setCharacterGroup)
	if player.Character then
		setCharacterGroup(player.Character)
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local money = Instance.new("IntValue")
	money.Name = "Argent"
	money.Parent = leaderstats
	local power = Instance.new("IntValue")
	power.Name = "Puissance"
	power.Parent = leaderstats
	leaderstats.Parent = player

	local data: PlayerData = {
		money = Config.Player.StartingMoney,
		power = Config.Player.StartingPower,
		purchases = 0,
		upgrades = {},
		collection = {},
		lastTrain = 0,
		phase = Phase.Idle,
		throwId = 0,
		pending = nil,
		landedAt = 0,
		forcedRarity = nil,
		museum = {},
		plot = nil,
		saveEnabled = true,
		clientReady = readyPlayers[player] == true,
		restoreSent = false,
		saving = false,
		saveQueued = false,
		lastSave = -math.huge,
		lastSavedJson = nil,
	}

	local status, saved = SaveService.Load(player.UserId)
	if not player.Parent then
		return -- parti pendant le chargement
	end
	if status == "ok" then
		applySaved(data, saved)
		data.lastSavedJson = HttpService:JSONEncode(snapshot(data))
	elseif status == "failed" then
		data.saveEnabled = false
		task.delay(3, notify, player, "⚠️ Sauvegarde indisponible : ta progression ne sera pas enregistrée cette fois.")
	else
		data.saveEnabled = false -- mode mémoire (Studio non publié)
	end

	-- Le client a pu signaler ClientReady PENDANT le chargement (data pas encore
	-- enregistrée) : on relit l'état ici, sinon la relique en attente n'est
	-- jamais rendue et HasPending bloque la zone de lancer.
	data.clientReady = data.clientReady or readyPlayers[player] == true
	playerData[player] = data
	assignPlot(player, data)
	sync(player)
	player:SetAttribute("DataLoaded", true)
	trySendRestore(player)
	task.spawn(refreshPodium)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	readyPlayers[player] = nil
	broadcastOthers(player, { kind = "done" }) -- son aimant disparaît chez les autres
	local data = playerData[player]
	if not data then
		return
	end
	savePlayer(player)
	releasePlot(data)
	playerData[player] = nil
end)

-- Fermeture du serveur : on sauvegarde tout le monde en parallèle
game:BindToClose(function()
	for player in pairs(playerData) do
		task.spawn(savePlayer, player)
	end
	task.wait() -- laisse démarrer les sauvegardes
	local deadline = os.clock() + Config.Save.CloseTimeout
	while activeSaves > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

-- Sauvegarde automatique
task.spawn(function()
	while true do
		task.wait(Config.Save.AutoSaveInterval)
		for player in pairs(playerData) do
			task.spawn(savePlayer, player)
		end
	end
end)

ClientReadyEvent.OnServerEvent:Connect(function(player)
	readyPlayers[player] = true
	local data = playerData[player]
	if data then
		data.clientReady = true
		trySendRestore(player)
	end
end)

---------------------------------------------------------------------------
-- Entraînement / boutique
---------------------------------------------------------------------------
-- Une répétition au banc (le joueur doit être allongé sur SON banc ; cadence vérifiée)
TrainEvent.OnServerEvent:Connect(function(player)
	if playerData[player] then
		BenchService.Rep(player)
	end
end)

-- Achat d'une amélioration (id = "Power", "Magnet", "Cable", "Clean", "Museum")
local function buyUpgrade(player: Player, id): (boolean, string)
	local data = playerData[player]
	if not data then
		return false, "Données introuvables"
	end
	local def = typeof(id) == "string" and Config.Upgrades[id]
	if not def then
		return false, "Amélioration inconnue"
	end
	local cost
	if id == "Power" then
		cost = Config.GetPowerCost(data.power)
	else
		cost = Config.GetUpgradeCost(id, upgradeLevel(data, id))
		if not cost then
			return false, def.name .. " : niveau max !"
		end
	end
	if data.money < cost then
		return false, ("Il te faut %s $"):format(Config.FormatNumber(cost))
	end
	data.money -= cost
	if id == "Power" then
		local gain = Config.GetPowerGain(data.power)
		data.power += gain
		sync(player)
		return true, ("+%s puissance !"):format(Config.FormatNumber(gain))
	end
	data.upgrades[id] = upgradeLevel(data, id) + 1
	if id == "Museum" then
		rebuildDisplays(data)
	end
	sync(player)
	return true, ("%s %s niveau %d !"):format(def.icon, def.name, data.upgrades[id])
end

BuyUpgradeFn.OnServerInvoke = buyUpgrade
BuyPowerFn.OnServerInvoke = function(player) -- ancien bouton, gardé pour compatibilité
	return buyUpgrade(player, "Power")
end

-- Livre de collection : liste des reliques trouvées
GetCollectionFn.OnServerInvoke = function(player)
	local data = playerData[player]
	if not data then
		return {}
	end
	local ids = {}
	for id in pairs(data.collection) do
		table.insert(ids, id)
	end
	return ids
end

---------------------------------------------------------------------------
-- Lancer
---------------------------------------------------------------------------
-- Le joueur doit vraiment se trouver dans la zone de lancer
local function isInThrowZone(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local localPosition = throwZone.CFrame:PointToObjectSpace(root.Position)
	local half = throwZone.Size / 2 + Vector3.one * Config.ThrowZone.ServerTolerance
	return math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z
end

RequestThrowFn.OnServerInvoke = function(player, gaugePosition)
	local data = playerData[player]
	if not data then
		return { ok = false, reason = "Données introuvables" }
	end
	-- Verrou : un seul lancer à la fois
	if data.phase ~= Phase.Idle then
		return { ok = false, reason = "Un lancer est déjà en cours" }
	end
	if BenchService.IsLifting(player) then
		return { ok = false, reason = "Lève-toi du banc d'abord !" }
	end
	if not isInThrowZone(player) then
		return { ok = false, reason = "Va dans la zone de lancer !" }
	end
	-- La position de la jauge est une entrée d'habileté du joueur ; on la
	-- borne strictement (elle n'influence que la zone, jamais la rareté forcée).
	if typeof(gaugePosition) ~= "number" or gaugePosition ~= gaugePosition then
		return { ok = false, reason = "Lancer invalide" }
	end
	gaugePosition = math.clamp(gaugePosition, 0, 1)

	local zoneIndex, effectivePower, precision, perfect = computeThrow(data.power, gaugePosition)
	local zone = Config.Zones[zoneIndex]

	local magnetLevel = upgradeLevel(data, "Magnet")
	local rarityId = data.forcedRarity or rollRarity(zoneIndex, magnetLevel)
	local relic = pickRelic(zone.id, rarityId)
	local record = makeRecord(relic.id, rarityId, zone.id) :: RelicRecord
	-- probabilité d'avoir CET objet (affichée à la révélation et dans les annonces)
	local _, rarityIndex = Config.GetRarity(rarityId)
	local weights = computeRarityWeights(zoneIndex, magnetLevel)
	local odds = Config.GetItemOdds(weights[rarityIndex] or 0, rarityId)
	data.pendingOdds = odds
	-- point de chute dans le canyon (plus loin / plus près, gauche / droite) : même chez tous les clients
	local landing = Vector2.new(rng:NextNumber(), rng:NextNumber(-1, 1))

	data.pending = record
	data.phase = Phase.Throwing
	data.throwId += 1
	data.ascentRelayed = false
	data.restoreSent = true -- ce lancer est déjà affiché par le client
	sync(player)

	-- Filet de sécurité : si le client ne confirme jamais la remontée
	local throwId = data.throwId
	task.delay(Config.Server.AscentTimeout, function()
		if playerData[player] == data and data.throwId == throwId and data.phase == Phase.Throwing then
			data.phase = Phase.Landed
			data.landedAt = os.clock()
			broadcastOthers(player, { kind = "done" })
		end
	end)
	broadcastOthers(player, { kind = "start", zoneIndex = zoneIndex, rarityId = rarityId, landing = landing })

	return {
		ok = true,
		zoneIndex = zoneIndex,
		rarityId = rarityId,
		relicId = record.relicId,
		relicName = record.name,
		value = valueFor(data, record),
		isNew = not data.collection[record.relicId],
		odds = odds,
		landing = landing,
		perfect = perfect,
		precision = precision,
		effectivePower = effectivePower,
	}
end

AscentDoneEvent.OnServerEvent:Connect(function(player)
	local data = playerData[player]
	if data and data.phase == Phase.Throwing then
		data.phase = Phase.Landed
		data.landedAt = os.clock()
		broadcastOthers(player, { kind = "done" })
	end
end)

-- Début de la remontée chez le lanceur : les autres la jouent en même temps
AscentStartEvent.OnServerEvent:Connect(function(player)
	local data = playerData[player]
	if data and data.phase == Phase.Throwing and data.pending and not data.ascentRelayed then
		data.ascentRelayed = true
		broadcastOthers(player, { kind = "ascent" })
	end
end)

CleanDoneFn.OnServerInvoke = function(player)
	local data = playerData[player]
	if not data or data.phase ~= Phase.Landed or not data.pending then
		return false
	end
	-- Le nettoyage dure HoldDuration : impossible de le valider plus tôt
	local cleanDuration = Config.GetCleanDuration(upgradeLevel(data, "Clean"))
	if os.clock() - data.landedAt < cleanDuration - Config.Clean.ServerTolerance then
		return false
	end
	data.phase = Phase.Cleaned

	local pending = data.pending
	-- Livre de collection
	if not data.collection[pending.relicId] then
		local wasComplete = zoneComplete(data, pending.zoneId)
		data.collection[pending.relicId] = true
		local signPlot = data.plot and getPlot(data.plot)
		if signPlot then
			refreshPlotStats(signPlot, data)
		end
		local zone = Config.GetZone(pending.zoneId)
		local completed = not wasComplete and zoneComplete(data, pending.zoneId)
		CollectionEvent:FireClient(player, {
			relicId = pending.relicId,
			count = collectionCount(data),
			total = #Config.Relics,
			zoneCompleted = completed and zone.name or nil,
		})
		if completed then
			rebuildDisplays(data) -- le bonus s'applique aussi aux vitrines
		end
		sync(player)
	end
	local rarity = Config.GetRarity(pending.rarityId)
	if rarity.announce then
		AnnounceEvent:FireAllClients({
			playerName = player.DisplayName,
			relicName = pending.name,
			rarityId = pending.rarityId,
			odds = data.pendingOdds,
		})
	end
	return true
end

SellFn.OnServerInvoke = function(player)
	local data = playerData[player]
	if not data or data.phase ~= Phase.Cleaned or not data.pending then
		return false, 0
	end
	local value = valueFor(data, data.pending)
	data.money += value
	data.pending = nil
	data.phase = Phase.Idle
	sync(player)
	return true, value
end

ExposeFn.OnServerInvoke = function(player)
	local data = playerData[player]
	if not data or data.phase ~= Phase.Cleaned or not data.pending then
		return false, "Rien à exposer"
	end
	local plot = data.plot and getPlot(data.plot)
	if not plot then
		return false, "Aucun musée disponible sur ce serveur"
	end
	local freeSlot = nil
	for slot = 1, museumSlots(data) do
		if not data.museum[slot] then
			freeSlot = slot
			break
		end
	end
	if not freeSlot then
		return false, "Musée plein !"
	end
	data.museum[freeSlot] = data.pending
	buildDisplay(plot, freeSlot, data.pending, valueFor(data, data.pending))
	data.pending = nil
	data.phase = Phase.Idle
	sync(player)
	return true, ("Exposée dans ton musée (socle %d)"):format(freeSlot)
end

---------------------------------------------------------------------------
-- Revenu passif du musée
---------------------------------------------------------------------------
task.spawn(function()
	local tickSeconds = Config.Museum.TickSeconds
	while true do
		task.wait(tickSeconds)
		for player, data in pairs(playerData) do
			local total = 0
			for _, relic in pairs(data.museum) do
				total += valueFor(data, relic)
			end
			if total > 0 then
				data.money += total * Config.Museum.IncomeRatePerMinute * (tickSeconds / 60)
				sync(player)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Debug (Studio uniquement, vérifié côté serveur)
---------------------------------------------------------------------------
DebugFn.OnServerInvoke = function(player, action, arg)
	if not RunService:IsStudio() then
		return false
	end
	local data = playerData[player]
	if not data then
		return false
	end
	if action == "ForceRarity" then
		if arg == nil or Config.GetRarity(arg) then
			data.forcedRarity = arg
		end
	elseif action == "AddMoney" then
		data.money += math.max(Config.Debug.MoneyAmount, data.money)
	elseif action == "AddPower" then
		data.power += math.max(Config.Debug.PowerAmount, data.power)
	elseif action == "Unlock" then
		-- secours si une animation plante pendant les tests
		data.phase = Phase.Idle
		data.pending = nil
	elseif action == "SaveNow" then
		savePlayer(player)
		return SaveService.IsEnabled(), SaveService.GetDisabledReason()
	end
	sync(player)
	return true
end

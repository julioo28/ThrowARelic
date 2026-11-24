--[[
	WorldBuilder (ModuleScript)
	Emplacement : ServerScriptService/WorldBuilder

	Génère le décor placeholder voxel (canyon, grue, plateforme de nettoyage,
	musée, arbres) et les reliques placeholder manquantes.

	- Idempotent : si Workspace.ThrowARelicWorld existe déjà, le décor n'est
	  PAS régénéré (tu peux donc le modifier à la main dans Studio).
	- Pour les reliques : seuls les modèles ABSENTS de ReplicatedStorage/Relics
	  sont créés. Dépose ton modèle Blender avec le même nom => il est utilisé.

	Noms utilisés par le client (ne pas renommer) :
	  ThrowARelicWorld/LaunchPad, Pulley, CleaningPlatform, CanyonMouth, ThrowZone,
	  Museums/Museum<i>/Pedestal1..N, Entrance, Arch/SignBoard/Stats, Bench ; Podium/Spot1..3
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Landscape = require(script.Parent:WaitForChild("Landscape"))

local WorldBuilder = {}
local WALL_STYLE = "Canyon2" -- change => le canyon est reconstruit (Canyon2 : vrai canyon du Landscape, plus de gorge rectangulaire)
local MUSEUM_STYLE = "Rue1" -- change => les musées sont reconstruits (Rue1 : enclos ouverts le long de la rue)

local W = Config.World
local HALF_W = W.CanyonWidth / 2
local HALF_L = W.CanyonLength / 2
-- Le canyon n'est plus centré sur X = 0 : il s'ouvre vers l'ouest depuis le bord
-- des joueurs (X_MAX), le ponton et le village ne bougent pas
local CX = W.CanyonCenterX or 0
local X_MIN, X_MAX = CX - HALF_W, CX + HALF_W
local RIM = W.RimY
local BOTTOM = RIM - W.CanyonDepth

-- Dimensions du décor (placeholder, libre à toi de tout déplacer ensuite)
local PLAYER_SIDE_WIDTH = 120
local FAR_SIDE_WIDTH = 60
local CAP_LENGTH = 20
local GRASS_THICKNESS = 2
local TILE_MIN_DEPTH, TILE_MAX_DEPTH = 0.6, 2.4
local ORE_CHANCE = 0.08

local COLORS = {
	Grass = { Color3.fromRGB(106, 176, 66), Color3.fromRGB(92, 160, 56), Color3.fromRGB(120, 190, 76) },
	Dirt = Color3.fromRGB(120, 85, 55),
	Wood = Color3.fromRGB(150, 105, 65),
	DarkWood = Color3.fromRGB(105, 70, 45),
	Stone = Color3.fromRGB(150, 150, 155),
	Metal = Color3.fromRGB(80, 80, 88),
	Leaves = { Color3.fromRGB(80, 160, 50), Color3.fromRGB(110, 185, 60), Color3.fromRGB(70, 140, 45), Color3.fromRGB(140, 200, 70) },
	Trunk = Color3.fromRGB(110, 70, 40),
	MuseumFloor = Color3.fromRGB(210, 200, 185),
	MuseumWall = Color3.fromRGB(235, 225, 205),
	Pedestal = Color3.fromRGB(190, 180, 165),
}

local rng = Random.new(W.Seed)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- Crée un bloc ancré à partir de ses coins min / max
local function block(name: string, minV: Vector3, maxV: Vector3, color: Color3, parent: Instance, material: Enum.Material?)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = maxV - minV
	part.Position = (minV + maxV) / 2
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Crée un bloc ancré à partir de son centre / taille
local function cube(name: string, center: Vector3, size: Vector3, color: Color3, parent: Instance, material: Enum.Material?)
	return block(name, center - size / 2, center + size / 2, color, parent, material)
end

local function zoneForDepth(depthBelowRim: number)
	for _, zone in ipairs(Config.Zones) do
		if depthBelowRim <= zone.bandBottom then
			return zone
		end
	end
	return Config.Zones[#Config.Zones]
end

---------------------------------------------------------------------------
-- Terrain : plateaux + fond + parois en tuiles voxel colorées par zone
---------------------------------------------------------------------------
local function buildGround(parent: Folder)
	local function landMass(name: string, minXZ: Vector2, maxXZ: Vector2)
		block(name .. "Dirt", Vector3.new(minXZ.X, BOTTOM - 5, minXZ.Y), Vector3.new(maxXZ.X, RIM - GRASS_THICKNESS, maxXZ.Y), COLORS.Dirt, parent, Enum.Material.Ground)
		block(name .. "Grass", Vector3.new(minXZ.X, RIM - GRASS_THICKNESS, minXZ.Y), Vector3.new(maxXZ.X, RIM, maxXZ.Y), COLORS.Grass[1], parent, Enum.Material.Grass)
	end
	local zMin, zMax = -HALF_L - CAP_LENGTH, HALF_L + CAP_LENGTH
	landMass("PlayerSide", Vector2.new(X_MAX, zMin), Vector2.new(X_MAX + PLAYER_SIDE_WIDTH, zMax))
	landMass("FarSide", Vector2.new(X_MIN - FAR_SIDE_WIDTH, zMin), Vector2.new(X_MIN, zMax))
	landMass("CapNorth", Vector2.new(X_MIN, HALF_L), Vector2.new(X_MAX, zMax))
	landMass("CapSouth", Vector2.new(X_MIN, zMin), Vector2.new(X_MAX, -HALF_L))
	block("CanyonFloor", Vector3.new(X_MIN, BOTTOM - 5, -HALF_L), Vector3.new(X_MAX, BOTTOM, HALF_L), Config.Zones[#Config.Zones].wallColors[1], parent, Enum.Material.Slate)
end

-- Une face de paroi. `axis` = "X" (face perpendiculaire à X) ou "Z" ;
-- `facing` = +1/-1 (sens vers le vide).
--   Haut (jusqu'à StrataDepth) : tuiles voxel aux couleurs des strates du Grand
--   Canyon, bien visibles depuis le ponton.
--   Profondeurs : une dalle par zone + corniches et filons en relief (la brume
--   et la distance cachent le reste ; ça garde le nombre de pièces raisonnable).
local function buildWallFace(parent: Folder, axis: string, planeCoord: number, facing: number, spanMin: number, spanMax: number)
	local tile = W.TileSize
	local function place(name: string, s0: number, s1: number, y0: number, y1: number, protrude: number, color: Color3, material: Enum.Material)
		local center, size
		if axis == "X" then
			center = Vector3.new(planeCoord + facing * protrude / 2, (y0 + y1) / 2, (s0 + s1) / 2)
			size = Vector3.new(protrude, y1 - y0, s1 - s0)
		else
			center = Vector3.new((s0 + s1) / 2, (y0 + y1) / 2, planeCoord + facing * protrude / 2)
			size = Vector3.new(s1 - s0, y1 - y0, protrude)
		end
		return cube(name, center, size, color, parent, material)
	end

	local strataBottom = RIM - W.StrataDepth
	local row = 0
	for y = strataBottom, RIM - tile, tile do
		row += 1
		if row % 3 == 0 then
			task.wait()
		end
		for s = spanMin, spanMax - tile, tile do
			local color, material = Landscape.StrataAt(y + tile / 2)
			color = color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.08))
			place("WallTile", s, s + tile, y, y + tile, rng:NextNumber(TILE_MIN_DEPTH, TILE_MAX_DEPTH), color, material)
		end
	end

	local previousBottom = 0
	for index, zone in ipairs(Config.Zones) do
		local d0, d1 = previousBottom, zone.bandBottom
		previousBottom = d1
		if index == #Config.Zones then
			d1 = W.CanyonDepth
		end
		local y0, y1 = RIM - d1, math.min(RIM - d0, strataBottom)
		if y1 > y0 then
			place("WallSlab", spanMin, spanMax, y0, y1, 2, zone.wallColors[1], Enum.Material.Slate)
			local ledges = math.floor((spanMax - spanMin) / 35) + 1
			for _ = 1, ledges do
				local length = rng:NextInteger(1, 3) * tile
				local height = math.min(rng:NextInteger(1, 2) * tile * 0.8, y1 - y0)
				local s0 = rng:NextNumber(spanMin, spanMax - length)
				local yb = rng:NextNumber(y0, y1 - height)
				local color = pick(zone.wallColors)
				local material = Enum.Material.Slate
				if zone.oreColors and rng:NextNumber() < ORE_CHANCE * 1.5 then
					color = pick(zone.oreColors)
					material = Enum.Material.Neon
				end
				place("WallLedge", s0, s0 + length, yb, yb + height, rng:NextNumber(3, 7), color, material)
			end
		end
		if index % 3 == 0 then
			task.wait()
		end
	end
	task.wait() -- laisse respirer Studio entre deux faces
end

local function buildCanyonWalls(parent: Folder)
	local walls = Instance.new("Folder")
	walls.Name = "CanyonWalls"
	walls.Parent = parent
	buildWallFace(walls, "X", X_MAX, -1, -HALF_L, HALF_L) -- paroi côté joueur
	buildWallFace(walls, "X", X_MIN, 1, -HALF_L, HALF_L) -- paroi d'en face
	buildWallFace(walls, "Z", HALF_L, -1, X_MIN, X_MAX)
	buildWallFace(walls, "Z", -HALF_L, 1, X_MIN, X_MAX)

	-- Zone invisible d'où s'échappent les particules lors d'une remontée rare
	if parent:FindFirstChild("CanyonMouth") then
		return
	end
	local mouth = cube("CanyonMouth", Vector3.new(CX, RIM - 4, 0), Vector3.new(W.CanyonWidth - 4, 1, W.CanyonLength - 6), Color3.new(), parent)
	mouth.Transparency = 1
	mouth.CanCollide = false
	mouth.CanQuery = false
end

---------------------------------------------------------------------------
-- Décor voxel : arbres et buissons
---------------------------------------------------------------------------
local function voxelTree(parent: Instance, base: Vector3)
	local model = Instance.new("Model")
	model.Name = "VoxelTree"
	local trunkHeight = rng:NextInteger(3, 5)
	for i = 0, trunkHeight - 1 do
		cube("Trunk", base + Vector3.new(0, 1 + i * 2, 0), Vector3.new(2, 2, 2), COLORS.Trunk, model)
	end
	local crownY = base.Y + trunkHeight * 2 + 2
	for x = -1, 1 do
		for z = -1, 1 do
			for y = 0, 1 do
				local corner = math.abs(x) + math.abs(z) == 2
				if not (corner and (y == 1 or rng:NextNumber() < 0.5)) then
					cube("Leaves", Vector3.new(base.X + x * 3, crownY + y * 3, base.Z + z * 3), Vector3.new(3, 3, 3), pick(COLORS.Leaves), model, Enum.Material.Grass)
				end
			end
		end
	end
	model.Parent = parent
end

local function voxelBush(parent: Instance, base: Vector3)
	for _ = 1, rng:NextInteger(2, 4) do
		local offset = Vector3.new(rng:NextInteger(-1, 1), 0.75, rng:NextInteger(-1, 1)) * 1.5
		cube("Bush", base + offset, Vector3.new(1.5, 1.5, 1.5), pick(COLORS.Leaves), parent, Enum.Material.Grass)
	end
end

local function buildNature(parent: Folder)
	local nature = Instance.new("Folder")
	nature.Name = "Nature"
	nature.Parent = parent
	-- Positions choisies à l'écart des structures
	local treeSpots = {
		Vector3.new(110, RIM, 50), Vector3.new(95, RIM, 62), Vector3.new(120, RIM, -55),
		Vector3.new(50, RIM, 55), Vector3.new(-40, RIM, 30), Vector3.new(-55, RIM, -20),
		Vector3.new(-35, RIM, -55), Vector3.new(-60, RIM, 60), Vector3.new(125, RIM, 10),
	}
	for _, spot in ipairs(treeSpots) do
		voxelTree(nature, spot)
	end
	for _ = 1, 14 do
		local side = rng:NextNumber() < 0.6
		local x = side and rng:NextNumber(X_MAX + 4, X_MAX + PLAYER_SIDE_WIDTH - 4) or rng:NextNumber(X_MIN - FAR_SIDE_WIDTH + 4, X_MIN - 4)
		local z = rng:NextNumber(-HALF_L - CAP_LENGTH + 4, HALF_L + CAP_LENGTH - 4)
		voxelBush(nature, Vector3.new(x, RIM, z))
	end
end

---------------------------------------------------------------------------
-- Gameplay : pas de tir, grue + poulie, barrière, plateforme de nettoyage
---------------------------------------------------------------------------
local function buildStation(parent: Folder)
	local padCenter = Vector3.new(X_MAX + 6, RIM + 0.5, 0)
	cube("LaunchPad", padCenter, Vector3.new(8, 1, 8), COLORS.Wood, parent, Enum.Material.WoodPlanks)

	-- Grue : poteau + flèche au-dessus du canyon + poulie au centre
	local postX = X_MAX + 11
	cube("CranePost", Vector3.new(postX, RIM + 9, 0), Vector3.new(2, 18, 2), COLORS.DarkWood, parent, Enum.Material.Wood)
	local boomLeft = -2
	cube("CraneBoom", Vector3.new((postX + boomLeft) / 2, RIM + 17.75, 0), Vector3.new(postX - boomLeft + 1, 1.5, 1.5), COLORS.DarkWood, parent, Enum.Material.Wood)
	local pulley = Instance.new("Part")
	pulley.Name = "Pulley"
	pulley.Shape = Enum.PartType.Cylinder
	pulley.Size = Vector3.new(1, 3, 3)
	pulley.CFrame = CFrame.new(0, RIM + 15.5, 0) * CFrame.Angles(0, math.rad(90), 0) -- axe de la roue selon Z
	pulley.Color = COLORS.Metal
	pulley.Material = Enum.Material.Metal
	pulley.Anchored = true
	pulley.Parent = parent
	cube("PulleyBracket", Vector3.new(0, RIM + 16.75, 0), Vector3.new(0.6, 1.5, 1.6), COLORS.Metal, parent, Enum.Material.Metal)

	-- Plateforme de nettoyage
	cube("CleaningPlatform", Vector3.new(X_MAX + 7, RIM + 1, 16), Vector3.new(8, 2, 8), COLORS.Stone, parent, Enum.Material.Cobblestone)
	cube("Bucket", Vector3.new(X_MAX + 12, RIM + 1, 19), Vector3.new(2, 2, 2), Config.Clean.MudColor, parent, Enum.Material.Wood)
end

---------------------------------------------------------------------------
-- Musées : un enclos en bois ouvert par joueur, de part et d'autre de la rue
-- principale (axe X, z = 0). Repère local d'un enclos (« PlotFrame ») :
--   X le long de la rue, Z vers le fond de l'enclos, z = 0 sur la clôture avant.
-- L'enclos s'allonge vers le fond quand on débloque des socles (SetPlotRows).
--   Museums/Museum<i>/ Pedestal1..N, Floor, Fence, Arch (SignBoard/Stats),
--                     Entrance (point de téléportation), Bench (sur la rue)
---------------------------------------------------------------------------
local FENCE_WOOD = Color3.fromRGB(139, 94, 52)
local FENCE_DARK = Color3.fromRGB(98, 66, 38)
local FLOOR_WOOD = Color3.fromRGB(176, 128, 80)

local function plotDepth(rows: number): number
	local M = Config.Museum
	return M.FrontMargin + (math.max(rows, 1) - 1) * M.RowSpacing + M.BackMargin
end

local function maxRows(): number
	return math.ceil(Config.Museum.MaxSlots / Config.Museum.Columns)
end

-- Pièce ancrée posée dans le repère d'un enclos
local function localPart(name: string, frame: CFrame, center: Vector3, size: Vector3, color: Color3, parent: Instance, material: Enum.Material?)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = frame * CFrame.new(center)
	part.Color = color
	part.Material = material or Enum.Material.Wood
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Clôture + plancher à la profondeur voulue (appelé aussi par le serveur quand
-- le propriétaire débloque une rangée de socles)
function WorldBuilder.SetPlotRows(plot: Model, rows: number)
	local M = Config.Museum
	local frame: CFrame? = plot:GetAttribute("PlotFrame")
	if not frame then
		return
	end
	rows = math.clamp(rows, 1, maxRows())
	if plot:GetAttribute("Rows") == rows and plot:FindFirstChild("Fence") then
		return
	end
	plot:SetAttribute("Rows", rows)
	local depth = plotDepth(rows)
	local half = M.PlotWidth / 2
	local old = plot:FindFirstChild("Fence")
	if old then
		old:Destroy()
	end
	local fence = Instance.new("Folder")
	fence.Name = "Fence"

	-- plancher en planches (léger relief pour bien marquer l'enclos)
	local floor = plot:FindFirstChild("Floor") :: BasePart?
	if not floor then
		floor = localPart("Floor", frame, Vector3.zero, Vector3.one, FLOOR_WOOD, plot, Enum.Material.WoodPlanks)
	end
	floor.Size = Vector3.new(M.PlotWidth, 0.4, depth)
	floor.CFrame = frame * CFrame.new(0, 0.2, depth / 2)

	-- une travée de clôture entre deux points (poteaux + 2 lisses)
	local function span(a: Vector3, b: Vector3)
		local length = (b - a).Magnitude
		local posts = math.max(1, math.floor(length / 4.5))
		for i = 0, posts do
			local p = a:Lerp(b, i / posts)
			localPart("Post", frame, p + Vector3.new(0, 1.9, 0), Vector3.new(0.7, 3.8, 0.7), FENCE_DARK, fence)
		end
		local mid = (a + b) / 2
		local along = (b - a).Unit
		local size = Vector3.new(math.abs(along.X) * length + 0.3, 0.35, math.abs(along.Z) * length + 0.3)
		for _, h in ipairs({ 1.4, 2.9 }) do
			localPart("Rail", frame, mid + Vector3.new(0, h, 0), size, FENCE_WOOD, fence, Enum.Material.WoodPlanks)
		end
	end
	local gate = M.EntranceOffset or 3
	local gateHalf = M.EntranceWidth / 2
	span(Vector3.new(-half, 0, 0), Vector3.new(gate - gateHalf, 0, 0))
	span(Vector3.new(gate + gateHalf, 0, 0), Vector3.new(half, 0, 0))
	span(Vector3.new(-half, 0, 0), Vector3.new(-half, 0, depth))
	span(Vector3.new(half, 0, 0), Vector3.new(half, 0, depth))
	span(Vector3.new(-half, 0, depth), Vector3.new(half, 0, depth))
	fence.Parent = plot
end

---------------------------------------------------------------------------
-- Banc de développé couché sur la rue, devant l'entrée (modèles voxel
-- ReplicatedStorage/Props : BenchPress, Barbell ; disques posés par le serveur)
--   Museum<i>/Bench/ Frame, Barbell (+ Plates), LiePoint (invite), StandPoint
---------------------------------------------------------------------------
local function buildBench(museum: Model, frame: CFrame)
	local props = ReplicatedStorage:FindFirstChild("Props")
	local frameTemplate = props and props:FindFirstChild("BenchPress")
	local barTemplate = props and props:FindFirstChild("Barbell")
	if not (frameTemplate and barTemplate) then
		warn("[WorldBuilder] Modèles du banc absents de ReplicatedStorage/Props")
		return
	end
	local B = Config.Bench
	local bench = Instance.new("Model")
	bench.Name = "Bench"
	-- perpendiculaire à la rue, tête (montants) vers l'enclos, barre parallèle à la rue
	local base = frame * CFrame.new(B.AlongStreet, 0, -B.FromFence) * CFrame.Angles(0, math.rad(90), 0)

	local benchFrame = frameTemplate:Clone()
	benchFrame.Name = "Frame"
	benchFrame:PivotTo(base)
	benchFrame.Parent = bench

	local barOffset: Vector3 = frameTemplate:GetAttribute("BarOffset") or Vector3.new(-2.5, 5.25, 0)
	local padTop: number = frameTemplate:GetAttribute("PadTop") or 2.5
	local barRest = base * CFrame.new(barOffset)
	local bar = barTemplate:Clone()
	bar.Name = "Barbell"
	bar:PivotTo(barRest)
	local plates = Instance.new("Folder")
	plates.Name = "Plates"
	plates.Parent = bar
	bar.Parent = bench
	bench:SetAttribute("BarRest", barRest)

	-- allongé : dos sur le coussin, tête vers les montants, regard vers le ciel
	local headDir = base:VectorToWorldSpace(Vector3.new(-1, 0, 0))
	local liePos = base * Vector3.new(barOffset.X + B.LieShoulderBack, padTop + B.LieHeight, barOffset.Z)
	local lie = Instance.new("Part")
	lie.Name = "LiePoint"
	lie.Size = Vector3.new(2, 1, 4)
	lie.CFrame = CFrame.lookAt(liePos, liePos + Vector3.yAxis, headDir)
	lie.Anchored = true
	lie.CanCollide = false
	lie.CanTouch = false
	lie.Transparency = 1
	lie.Parent = bench

	-- où l'on se relève : côté entrée, sur la rue
	local stand = Instance.new("Part")
	stand.Name = "StandPoint"
	stand.Size = Vector3.new(2, 1, 2)
	stand.CFrame = frame * CFrame.new(B.AlongStreet + 5, 3, -B.FromFence - 2) * CFrame.Angles(0, math.pi, 0)
	stand.Anchored = true
	stand.CanCollide = false
	stand.CanQuery = false
	stand.CanTouch = false
	stand.Transparency = 1
	stand.Parent = bench

	bench.Parent = museum
end

-- Arche d'entrée en bois + grand panneau tourné vers la rue (texte : serveur)
local function buildArch(museum: Model, frame: CFrame)
	local M = Config.Museum
	local arch = Instance.new("Model")
	arch.Name = "Arch"
	local gate = M.EntranceOffset or 3
	local half = M.EntranceWidth / 2 + 0.5
	for _, side in ipairs({ -1, 1 }) do
		localPart("ArchPost", frame, Vector3.new(gate + side * half, 5.5, 0), Vector3.new(1.1, 11, 1.1), FENCE_DARK, arch)
	end
	localPart("ArchBeam", frame, Vector3.new(gate, 11.2, 0), Vector3.new(M.EntranceWidth + 3.2, 1, 1.4), FENCE_WOOD, arch)
	local board = localPart("SignBoard", frame, Vector3.new(gate, 14.4, -0.1), Vector3.new(17, 5.6, 0.6), Color3.fromRGB(86, 56, 32), arch, Enum.Material.WoodPlanks)
	localPart("SignTrim", frame, Vector3.new(gate, 17.3, -0.1), Vector3.new(17.6, 0.5, 0.8), Color3.fromRGB(242, 193, 78), arch, Enum.Material.Metal)

	-- panneau : face avant (-Z local) = vers la rue
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Stats"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local function line(name: string, order: number, height: number, color: Color3)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.LayoutOrder = order
		label.Size = UDim2.new(0.94, 0, height, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0
		label.Text = ""
		label.Parent = gui
		return label
	end
	line("Title", 1, 0.34, Color3.fromRGB(255, 230, 150)).Text = "MUSÉE LIBRE"
	line("Value", 2, 0.2, Color3.fromRGB(140, 255, 120))
	line("Best", 3, 0.2, Color3.fromRGB(255, 255, 255))
	line("Odds", 4, 0.16, Color3.fromRGB(255, 220, 120))
	gui.Parent = board

	-- lanternes de part et d'autre de l'arche
	for _, side in ipairs({ -1, 1 }) do
		local lantern = localPart("Lantern", frame, Vector3.new(gate + side * half, 9.6, -0.9), Vector3.new(0.9, 1.1, 0.9), Color3.fromRGB(255, 207, 122), arch, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 180, 90)
		light.Range = 14
		light.Brightness = 1.2
		light.Parent = lantern
	end
	arch.Parent = museum
end

local function buildMuseumPlot(parent: Folder, index: number, frame: CFrame)
	local M = Config.Museum
	local museum = Instance.new("Model")
	museum.Name = "Museum" .. index
	museum:SetAttribute("PlotFrame", frame)

	-- Socles : 3 par rangée, rangées vers le fond. Tous créés (MaxSlots) ;
	-- le serveur cache ceux qui sont au-delà de la clôture.
	for i = 1, M.MaxSlots do
		local col = (i - 1) % M.Columns
		local row = math.floor((i - 1) / M.Columns)
		local x = (col - (M.Columns - 1) / 2) * M.ColumnSpacing
		local z = M.FrontMargin + row * M.RowSpacing
		localPart("Pedestal" .. i, frame, Vector3.new(x, 1.5, z), Vector3.new(3.4, 2.6, 3.4), Color3.fromRGB(224, 201, 160), museum, Enum.Material.Sandstone)
	end

	WorldBuilder.SetPlotRows(museum, math.ceil(M.Slots / M.Columns))
	buildArch(museum, frame)
	buildBench(museum, frame)

	-- Point d'arrivée de « Mon musée » : dans la rue, devant l'entrée, tourné vers l'enclos
	local gate = M.EntranceOffset or 3
	local entrance = localPart("Entrance", frame, Vector3.new(gate, 3, -M.EntranceDistance), Vector3.new(2, 1, 2), Color3.new(), museum)
	entrance.Transparency = 1
	entrance.CanCollide = false
	entrance.CanQuery = false
	entrance.CanTouch = false

	-- pivot du modèle = centre de l'enclos à sa taille maximale (sert de cible au regard)
	museum.WorldPivot = frame * CFrame.new(0, 0, plotDepth(maxRows()) / 2)
	museum.Parent = parent
	return museum
end

-- Retire la végétation (et le décor du village) qui gênerait un enclos, son banc ou le podium
local function clearAround(world: Folder, frame: CFrame, minLocal: Vector3, maxLocal: Vector3)
	local landscape = world:FindFirstChild("Landscape")
	local containers = { world:FindFirstChild("Nature") }
	if landscape then
		table.insert(containers, landscape:FindFirstChild("Props"))
		table.insert(containers, landscape:FindFirstChild("Village"))
	end
	for _, container in ipairs(containers) do
		for _, child in ipairs(container and container:GetChildren() or {}) do
			local position = child:IsA("Model") and child:GetPivot().Position or (child :: BasePart).Position
			local p = frame:PointToObjectSpace(position)
			if p.X >= minLocal.X and p.X <= maxLocal.X and p.Z >= minLocal.Z and p.Z <= maxLocal.Z then
				child:Destroy()
			end
		end
	end
end

-- Podium du top 3 du serveur, au bout de la rue, tourné vers le spawn (-X).
-- Spot1..3 = dessus des marches ; les statues sont posées par le serveur.
local function buildPodium(world: Folder)
	local M = Config.Museum
	local old = world:FindFirstChild("Podium")
	if old then
		old:Destroy()
	end
	local podium = Instance.new("Model")
	podium.Name = "Podium"
	local origin = Vector3.new(M.PodiumPosition.X, RIM, M.PodiumPosition.Z)
	-- repère : X local = vers les spectateurs (-X monde), Z local = gauche/droite
	local frame = CFrame.lookAt(origin, origin + Vector3.new(-1, 0, 0))
	clearAround(world, frame, Vector3.new(-14, 0, -10), Vector3.new(14, 0, 12))
	local steps = {
		{ rank = 1, x = 0, height = 4.5, color = Color3.fromRGB(242, 193, 78) },
		{ rank = 2, x = 7, height = 3, color = Color3.fromRGB(200, 204, 214) },
		{ rank = 3, x = -7, height = 2, color = Color3.fromRGB(205, 127, 50) },
	}
	localPart("Base", frame, Vector3.new(0, 0.3, 0), Vector3.new(23, 0.6, 9), FENCE_DARK, podium, Enum.Material.WoodPlanks)
	for _, s in ipairs(steps) do
		-- frame regarde vers -X monde : -Z local = vers les spectateurs, X local = leur droite
		localPart("Step" .. s.rank, frame, Vector3.new(s.x, 0.6 + s.height / 2, 0), Vector3.new(6.6, s.height, 6.6), Color3.fromRGB(122, 82, 48), podium, Enum.Material.WoodPlanks)
		localPart("Trim" .. s.rank, frame, Vector3.new(s.x, 0.6 + s.height - 0.15, 0), Vector3.new(6.9, 0.35, 6.9), s.color, podium, Enum.Material.Metal)
		local plate = localPart("Number" .. s.rank, frame, Vector3.new(s.x, 0.6 + s.height / 2, -3.35), Vector3.new(3, 2, 0.2), s.color, podium, Enum.Material.Metal)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(60, 40, 20)
		label.Text = tostring(s.rank)
		label.Parent = gui
		gui.Parent = plate
		local spot = localPart("Spot" .. s.rank, frame, Vector3.new(s.x, 0.6 + s.height + 0.1, 0), Vector3.new(1, 0.2, 1), s.color, podium)
		spot.Transparency = 1
		spot.CanCollide = false
		spot.CanQuery = false
		spot.CanTouch = false
	end
	-- fronton « TOP 3 DU SERVEUR »
	for _, side in ipairs({ -1, 1 }) do
		localPart("BannerPost", frame, Vector3.new(side * 11, 7, 3.6), Vector3.new(1, 14, 1), FENCE_DARK, podium)
	end
	local banner = localPart("Banner", frame, Vector3.new(0, 15.5, 3.6), Vector3.new(24, 4, 0.6), Color3.fromRGB(86, 56, 32), podium, Enum.Material.WoodPlanks)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 110)
	label.TextStrokeTransparency = 0
	label.Text = "🏆 LES PLUS RICHES DU SERVEUR 🏆"
	label.Parent = gui
	gui.Parent = banner
	podium.Parent = world
end

local function buildMuseums(world: Folder)
	local M = Config.Museum
	local legacy = world:FindFirstChild("Museum")
	if legacy then
		legacy:Destroy()
	end
	local museums = Instance.new("Folder")
	museums.Name = "Museums"
	museums:SetAttribute("Style", MUSEUM_STYLE)
	museums.Parent = world
	local index = 0
	-- côté nord (z < 0) puis côté sud (z > 0) ; l'enclos regarde la rue
	for _, side in ipairs({ -1, 1 }) do
		for _, x in ipairs(M.PlotColumnsX) do
			index += 1
			local frame = CFrame.new(x, RIM, side * M.StreetHalfWidth) * CFrame.Angles(0, side == 1 and 0 or math.pi, 0)
			-- enclos à sa taille max + banc sur la rue (marge : les grands cactus débordent)
			clearAround(world, frame, Vector3.new(-M.PlotWidth / 2 - 4, 0, -M.StreetHalfWidth + 1), Vector3.new(M.PlotWidth / 2 + 4, 0, plotDepth(maxRows()) + 8))
			buildMuseumPlot(museums, index, frame)
			task.wait() -- laisse respirer Studio entre deux enclos
		end
	end
	buildPodium(world)
end

---------------------------------------------------------------------------
-- Zone de lancer : volume invisible + disque lumineux sur le ponton
---------------------------------------------------------------------------
local function buildThrowZone(world: Folder)
	local pad = world:FindFirstChild("LaunchPad")
	if not pad then
		return
	end
	local size = Config.ThrowZone.Size
	local zone = cube("ThrowZone", pad.Position + Vector3.new(0, pad.Size.Y / 2 + size.Y / 2, 0), size, Color3.new(), world)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false

	local marker = Instance.new("Part")
	marker.Name = "ThrowZoneMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.1, math.min(size.X, size.Z) - 1, math.min(size.X, size.Z) - 1)
	marker.CFrame = CFrame.new(pad.Position + Vector3.new(0, pad.Size.Y / 2 + 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 200, 60)
	marker.Transparency = 0.45
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Parent = world

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(14, 3)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	billboard.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🧲 Entre ici pour lancer !"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = marker
end

---------------------------------------------------------------------------
-- Reliques placeholder : petits modèles voxel colorés
---------------------------------------------------------------------------
local function buildRelicPlaceholder(relic): Model
	local _, rarityIndex = Config.GetRarity(relic.rarity)
	local rarity = Config.Rarities[rarityIndex]
	local model = Instance.new("Model")
	model.Name = relic.id

	local scale = 1 + (rarityIndex - 1) * 0.12
	local function relicPart(name: string, offset: Vector3, size: Vector3, color: Color3, material: Enum.Material?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size * scale
		part.CFrame = CFrame.new(offset * scale)
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end

	local base = relicPart("Base", Vector3.new(0, 0, 0), Vector3.new(2, 1.6, 2), relic.color)
	relicPart("Top", Vector3.new(0, 1.2, 0), Vector3.new(1.2, 0.8, 1.2), relic.color:Lerp(Color3.new(1, 1, 1), 0.35))
	-- Ornements : plus la rareté est haute, plus il y en a (et ils brillent)
	local ornaments = rarityIndex - 1
	for i = 1, ornaments do
		local angle = (i / math.max(ornaments, 1)) * math.pi * 2
		local material = rarity.isRare and Enum.Material.Neon or Enum.Material.SmoothPlastic
		relicPart("Ornament", Vector3.new(math.cos(angle) * 1.1, 0.4, math.sin(angle) * 1.1), Vector3.new(0.5, 0.5, 0.5), rarity.color, material)
	end
	model.PrimaryPart = base
	return model
end

function WorldBuilder.BuildRelics()
	local folder = ReplicatedStorage:FindFirstChild("Relics")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Relics"
		folder.Parent = ReplicatedStorage
	end
	for _, relic in ipairs(Config.Relics) do
		if not folder:FindFirstChild(relic.id) then
			buildRelicPlaceholder(relic).Parent = folder
		end
	end
end

function WorldBuilder.BuildWorld()
	if workspace:FindFirstChild("ThrowARelicWorld") then
		return -- déjà construit (ou modifié à la main) : on n'y touche pas
	end
	-- Le dossier est construit hors du DataModel puis parenté par morceaux légers
	local world = Instance.new("Folder")
	world.Name = "ThrowARelicWorld"
	world.Parent = workspace

	buildGround(world)
	buildCanyonWalls(world)
	world:SetAttribute("CanyonDepth", W.CanyonDepth)
	world:SetAttribute("WallStyle", WALL_STYLE)
	buildStation(world)
	buildNature(world)

	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.Position = Vector3.new(X_MAX + 30, RIM + 0.5, 0)
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate.Color = Color3.fromRGB(80, 120, 60)
	end
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.3
		atmosphere.Haze = 1
		atmosphere.Color = Color3.fromRGB(200, 220, 255)
		atmosphere.Parent = Lighting
	end
end

-- Barrière en bois le long du bord côté joueurs (ouverte au ponton et à l'atelier)
-- + mur invisible derrière (on ne saute pas dans le canyon)
local RIM_FENCE_GAPS = { { -9, 9 }, { 8, 25 } } -- z : ponton, atelier
local function inFenceGap(z: number): boolean
	for _, gap in ipairs(RIM_FENCE_GAPS) do
		if z >= gap[1] and z <= gap[2] then
			return true
		end
	end
	return false
end

local function buildRimFence(world: Folder)
	local old = world:FindFirstChild("Fence")
	if old then
		old:Destroy()
	end
	local fence = Instance.new("Model")
	fence.Name = "Fence"
	-- la barrière suit le bord sinueux du canyon (Config.CanyonAt), côté joueurs
	local zLimit = 370
	local previous: Vector3? = nil
	for z = -zLimit, zLimit, 6 do
		local east = Config.CanyonAt(z)
		local post = Vector3.new(east + 1, RIM, z)
		if inFenceGap(z) then
			previous = nil
		else
			cube("FencePost", post + Vector3.new(0, 1.5, 0), Vector3.new(1, 3, 1), COLORS.Wood, fence, Enum.Material.Wood)
			if previous then
				for _, h in ipairs({ 1.2, 2.4 }) do
					local a, b = previous + Vector3.new(0, h, 0), post + Vector3.new(0, h, 0)
					local rail = cube("FenceRail", (a + b) / 2, Vector3.new(0.5, 0.5, (b - a).Magnitude), COLORS.Wood, fence, Enum.Material.Wood)
					rail.CFrame = CFrame.lookAt((a + b) / 2, b)
				end
				local a, b = previous + Vector3.new(0, 6, 0), post + Vector3.new(0, 6, 0)
				local wall = cube("RimBarrier", (a + b) / 2, Vector3.new(1, 12, (b - a).Magnitude + 0.5), Color3.new(), fence)
				wall.CFrame = CFrame.lookAt((a + b) / 2, b)
				wall.Transparency = 1
				wall.CanQuery = false
			end
			previous = post
		end
	end
	fence.Parent = world
end

-- Signature de la forme du canyon : si elle change, tout est reconstruit
local function shapeSignature(): string
	return ("%d|%d|%d|%d|%s"):format(W.CanyonEastRim, W.CanyonRegionX0, W.CanyonRegionZ, W.CanyonDepth, WALL_STYLE)
end

-- Remodelage : le canyon lui-même est construit par Landscape (v3). Ici : on
-- retire l'ancienne gorge rectangulaire, on garde le sol du village, on pose
-- le fond, l'embouchure (particules des remontées rares) et la barrière.
local function reshapeCanyon(world: Folder)
	for _, name in ipairs({ "CanyonWalls", "CanyonFloor", "CanyonMouth", "Fence",
		"PlayerSideDirt", "PlayerSideGrass", "FarSideDirt", "FarSideGrass",
		"CapNorthDirt", "CapNorthGrass", "CapSouthDirt", "CapSouthGrass" }) do
		local old = world:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	-- sol du village (x 15..135) jusqu'au fond, comme avant
	local east = W.CanyonEastRim
	block("PlayerSideDirt", Vector3.new(east, BOTTOM - 5, -370), Vector3.new(east + PLAYER_SIDE_WIDTH, RIM - GRASS_THICKNESS, 370), COLORS.Dirt, world, Enum.Material.Ground)
	local grass = block("PlayerSideGrass", Vector3.new(east, RIM - GRASS_THICKNESS, -370), Vector3.new(east + PLAYER_SIDE_WIDTH, RIM, 370), COLORS.Grass[1], world, Enum.Material.Sand)
	grass.Color = Color3.fromHex("cfa57a")
	-- fond de la faille, sous tout le canyon
	block("CanyonFloor", Vector3.new(W.CanyonRegionX0, BOTTOM - 5, -W.CanyonRegionZ), Vector3.new(east, BOTTOM, W.CanyonRegionZ),
		Config.Zones[#Config.Zones].wallColors[1], world, Enum.Material.Slate)
	-- embouchure : au-dessus de la faille, face au ponton
	local _, axis, _, slot = Config.CanyonAt(0)
	local mouth = cube("CanyonMouth", Vector3.new(axis, RIM - 4, 0), Vector3.new(slot * 2, 1, 160), Color3.new(), world)
	mouth.Transparency = 1
	mouth.CanCollide = false
	mouth.CanQuery = false
	buildRimFence(world)
	world:SetAttribute("CanyonShape", shapeSignature())
	world:SetAttribute("CanyonDepth", W.CanyonDepth)
	world:SetAttribute("WallStyle", WALL_STYLE)
end

-- Brume : nappes translucides empilées dans le canyon. Reconstruite si les
-- réglages Config.World.Fog* changent (signature stockée en attribut).
local function fogSignature(): string
	return ("%d|%d|%.2f|%s|%s|%s|%d|%d|%d|%d"):format(W.FogStartDepth, W.FogSpacing, W.FogTransparency,
		W.FogColorTop:ToHex(), W.FogColorBottom:ToHex(), tostring(W.FogWisps), W.CanyonDepth, W.CanyonEastRim, W.CanyonRegionX0, W.CanyonRegionZ)
end

local function buildCanyonFog(world: Folder)
	local old = world:FindFirstChild("CanyonFog")
	if old then
		old:Destroy()
	end
	local fog = Instance.new("Folder")
	fog.Name = "CanyonFog"
	fog.Parent = world
	local lastDepth = W.CanyonDepth - 10
	local count = math.max(1, math.floor((lastDepth - W.FogStartDepth) / W.FogSpacing) + 1)
	for index = 0, count - 1 do
		local depth = W.FogStartDepth + index * W.FogSpacing
		local t = count > 1 and index / (count - 1) or 0
		local layer = cube("FogLayer", Vector3.new((W.CanyonRegionX0 + W.CanyonEastRim) / 2, RIM - depth, 0), Vector3.new(W.CanyonEastRim - W.CanyonRegionX0 - 1, 0.4, W.CanyonRegionZ * 2 - 1),
			W.FogColorTop:Lerp(W.FogColorBottom, t), fog)
		layer.Transparency = W.FogTransparency
		layer.CanCollide = false
		layer.CanQuery = false
		layer.CanTouch = false
		layer.CastShadow = false
		if W.FogWisps then
			local wisps = Instance.new("ParticleEmitter")
			wisps.Name = "Wisps"
			wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
			wisps.Color = ColorSequence.new(layer.Color)
			wisps.LightEmission = 0
			wisps.LightInfluence = 1
			wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 22) })
			wisps.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75),
				NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1),
			})
			wisps.Lifetime = NumberRange.new(8, 12)
			wisps.Rate = index == 0 and 40 or 6 -- la 1re nappe (dans la gorge intérieure) fume beaucoup
			wisps.Speed = NumberRange.new(0.5, 1.5)
			wisps.SpreadAngle = Vector2.new(180, 180)
			wisps.Rotation = NumberRange.new(0, 360)
			wisps.RotSpeed = NumberRange.new(-8, 8)
			wisps.Parent = layer
		end
		if index % 5 == 4 then
			task.wait()
		end
	end
	-- volutes de brume au-dessus de la gorge intérieure, devant le ponton (les nappes
	-- géantes répartissent leurs particules sur tout le canyon : trop clairsemées ici)
	for _, z in ipairs({ -240, -80, 80, 240 }) do
		local _, axis, _, slot = Config.CanyonAt(z)
		local source = cube("GorgeMist", Vector3.new(axis, RIM - W.FogStartDepth + 4, z), Vector3.new(slot * 2 + 30, 1, 160), W.FogColorTop, fog)
		source.Transparency = 1
		source.CanCollide = false
		source.CanQuery = false
		source.CanTouch = false
		local mist = Instance.new("ParticleEmitter")
		mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
		mist.Color = ColorSequence.new(W.FogColorTop)
		mist.LightInfluence = 1
		mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 30) })
		mist.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.65),
			NumberSequenceKeypoint.new(0.7, 0.65), NumberSequenceKeypoint.new(1, 1),
		})
		mist.Lifetime = NumberRange.new(10, 16)
		mist.Rate = 3
		mist.Speed = NumberRange.new(0.5, 2)
		mist.SpreadAngle = Vector2.new(180, 30)
		mist.Rotation = NumberRange.new(0, 360)
		mist.RotSpeed = NumberRange.new(-6, 6)
		mist.Parent = source
	end
	world:SetAttribute("FogSignature", fogSignature())
end

-- La Baseplate (sol par défaut) traverserait le canyon : on découpe le trou
-- du canyon dans chaque morceau existant (Baseplate ou Baseplate1..N)
local function cutBaseplate()
	local holeMin = Vector3.new(W.CanyonRegionX0, 0, -W.CanyonRegionZ)
	local holeMax = Vector3.new(W.CanyonEastRim, 0, W.CanyonRegionZ)
	local pieces = {}
	for _, part in ipairs(workspace:GetChildren()) do
		if part:IsA("BasePart") and part.Name:match("^Baseplate%d*$") then
			table.insert(pieces, part)
		end
	end
	local counter = 0
	for _, part in ipairs(pieces) do
		local minV, maxV = part.Position - part.Size / 2, part.Position + part.Size / 2
		local overlaps = maxV.Y > BOTTOM and minV.X < holeMax.X and maxV.X > holeMin.X and minV.Z < holeMax.Z and maxV.Z > holeMin.Z
		if overlaps then
			local boxes = {
				{ Vector3.new(minV.X, minV.Y, minV.Z), Vector3.new(math.max(minV.X, holeMin.X), maxV.Y, maxV.Z) },
				{ Vector3.new(math.min(maxV.X, holeMax.X), minV.Y, minV.Z), Vector3.new(maxV.X, maxV.Y, maxV.Z) },
				{ Vector3.new(math.max(minV.X, holeMin.X), minV.Y, minV.Z), Vector3.new(math.min(maxV.X, holeMax.X), maxV.Y, math.max(minV.Z, holeMin.Z)) },
				{ Vector3.new(math.max(minV.X, holeMin.X), minV.Y, math.min(maxV.Z, holeMax.Z)), Vector3.new(math.min(maxV.X, holeMax.X), maxV.Y, maxV.Z) },
			}
			for _, box in ipairs(boxes) do
				local size = box[2] - box[1]
				if size.X > 0.5 and size.Z > 0.5 then
					counter += 1
					local piece = part:Clone()
					piece:ClearAllChildren()
					piece.Name = "BaseplateCut" .. counter
					piece.Size = size
					piece.Position = (box[1] + box[2]) / 2
					piece.Parent = workspace
				end
			end
			part:Destroy()
		end
	end
	-- noms propres : Baseplate1..N
	local index = 0
	for _, part in ipairs(workspace:GetChildren()) do
		if part:IsA("BasePart") and part.Name:match("^Baseplate") then
			index += 1
			part.Name = "Baseplate" .. index
		end
	end
end

-- Ajoute aux mondes existants les éléments arrivés après coup
-- (sans toucher au reste, que tu as peut-être modifié à la main)
function WorldBuilder.Upgrade()
	local world = workspace:FindFirstChild("ThrowARelicWorld")
	if not world then
		return
	end
	if not world:FindFirstChild("ThrowZone") then
		buildThrowZone(world)
	end
	-- Musées construits avant l'amélioration « Places au musée » (6 socles)
	local museums = world:FindFirstChild("Museums")
	local first = museums and museums:FindFirstChild("Museum1")
	if museums and (not (first and first:FindFirstChild("Pedestal" .. Config.Museum.MaxSlots))
		or museums:GetAttribute("Style") ~= MUSEUM_STYLE) then
		museums:Destroy()
		museums = nil
	end
	if not museums then
		buildMuseums(world)
	end
	local reshape = world:GetAttribute("CanyonShape") ~= shapeSignature()
	if reshape then
		reshapeCanyon(world)
	end
	if world:GetAttribute("FogSignature") ~= fogSignature() then
		buildCanyonFog(world)
	end
	cutBaseplate()
	-- Les pièces non ancrées sous cette hauteur sont détruites par Roblox :
	-- elle doit rester sous le fond du canyon
	if workspace.FallenPartsDestroyHeight > BOTTOM - 100 then
		pcall(function()
			workspace.FallenPartsDestroyHeight = BOTTOM - 200
		end)
	end
	-- Paysage Grand Canyon, village, lumière (module Landscape)
	Landscape.Build(world)
	Landscape.BuildStation(world) -- chevalement de mine (versionné à part)
end

function WorldBuilder.Build()
	WorldBuilder.BuildRelics()
	WorldBuilder.BuildWorld()
	WorldBuilder.Upgrade()
end

return WorldBuilder

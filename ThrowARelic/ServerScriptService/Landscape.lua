--[[
	Landscape (ModuleScript)
	Emplacement : ServerScriptService/Landscape

	Décor « Grand Canyon voxel » :
	  - plateau désertique (côté joueurs) et village de l'Ouest
	  - LE canyon où l'on lance : sinueux, il s'élargit et se resserre
	    (Config.CanyonAt), en terrasses comme le vrai (falaises du bord, pentes,
	    plateau de Tonto, falaise de Redwall, gorge intérieure) ; au fond, une
	    faille étroite plonge dans la brume vers les zones profondes. Pas d'eau.
	  - mesas à l'horizon, buttes dans le canyon
	  - props voxel (ReplicatedStorage/Props, modélisés dans Blender) dispersés
	  - lumière de coucher de soleil + effets (bloom, rayons, nuages)

	Idempotent : tout est dans Workspace/ThrowARelicWorld/Landscape, reconstruit
	seulement si Landscape.VERSION change (attribut LandscapeVersion).
	Le puits de lancer (x ±15, z ±50) et ses pièces nommées ne sont pas touchés.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local Landscape = {}
Landscape.VERSION = 4 -- v4 : vrai canyon sinueux en terrasses + faille profonde (plus d'eau), bord à pic

local W = Config.World
local RIM = W.RimY
local GORGE_Z = 370 -- masses de terre du village (WorldBuilder) jusqu'à |z| = 370
local hex = Color3.fromHex

---------------------------------------------------------------------------
-- Réglages du paysage
---------------------------------------------------------------------------
local CELL = 10 -- taille d'une colonne de la carte de hauteur (studs)
local LAYER = 10 -- hauteur d'une strate voxel
local REGION_X1 = W.CanyonEastRim -- le canyon s'arrête au bord du village
local REGION_X0 = W.CanyonRegionX0
local REGION_Z0, REGION_Z1 = -W.CanyonRegionZ, W.CanyonRegionZ
local RIVER_LEVEL = 30 -- (ancien lit de rivière : sert de repère pour les props des terrasses)
local SLOT = -100000 -- hauteur « sans fond » : la faille profonde
local PLATEAU_EXTENT = 2600 -- le plateau s'étend jusqu'à l'horizon

-- Strates du Grand Canyon (du fond vers le bord), par altitude absolue
local STRATA = {
	{ top = 40, colors = { hex("3d3436"), hex("4a3f42") }, material = Enum.Material.Slate }, -- schiste de Vishnu
	{ top = 60, colors = { hex("7b5a3c"), hex("86644a") }, material = Enum.Material.Sandstone }, -- grès de Tapeats
	{ top = 90, colors = { hex("7f8466"), hex("8c8a68") }, material = Enum.Material.Slate }, -- schiste de Bright Angel
	{ top = 130, colors = { hex("a94b32"), hex("b5553a") }, material = Enum.Material.Limestone }, -- calcaire Redwall
	{ top = 160, colors = { hex("b8613b"), hex("c46e44") }, material = Enum.Material.Sandstone }, -- groupe Supai
	{ top = 180, colors = { hex("9c4530"), hex("a84f36") }, material = Enum.Material.Sandstone }, -- schiste Hermit
	{ top = 190, colors = { hex("e3cfa3"), hex("ead8ae") }, material = Enum.Material.Sandstone }, -- grès Coconino
	{ top = 200, colors = { hex("d2ae80"), hex("ddb98a") }, material = Enum.Material.Sandstone }, -- Toroweap
	{ top = math.huge, colors = { hex("e7d6b5"), hex("efe0c2") }, material = Enum.Material.Limestone }, -- calcaire Kaibab
}
local DESERT = { hex("cfa57a"), hex("c4966a"), hex("d8b48a") }

-- Couleur / matériau d'une strate pour une altitude (utilisé aussi pour le haut du puits)
function Landscape.StrataAt(y: number): (Color3, Enum.Material)
	for _, band in ipairs(STRATA) do
		if y < band.top then
			local shade = band.colors[(math.floor(y / LAYER) % 2) + 1]
			return shade, band.material
		end
	end
	local last = STRATA[#STRATA]
	return last.colors[1], last.material
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local MAX_PART = 2000 -- Roblox limite une pièce à 2 048 studs par côté

local function block(name: string, minV: Vector3, maxV: Vector3, color: Color3, material: Enum.Material, parent: Instance)
	local size = maxV - minV
	if size.X > MAX_PART or size.Y > MAX_PART or size.Z > MAX_PART then
		-- trop grand : découpé en morceaux
		local nx, ny, nz = math.ceil(size.X / MAX_PART), math.ceil(size.Y / MAX_PART), math.ceil(size.Z / MAX_PART)
		local step = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
		local first
		for i = 0, nx - 1 do
			for j = 0, ny - 1 do
				for k = 0, nz - 1 do
					local a = minV + step * Vector3.new(i, j, k)
					local piece = block(name, a, a + step, color, material, parent)
					first = first or piece
				end
			end
		end
		return first
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = maxV - minV
	part.Position = (minV + maxV) / 2
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

---------------------------------------------------------------------------
-- Carte de hauteur du canyon
---------------------------------------------------------------------------
-- Profil en travers du canyon (comme la photo du Grand Canyon) :
-- (s = 0 au bord de la faille, 1 au bord du plateau ; altitude)
local PROFILE = {
	{ 0, 45 }, -- haut de la gorge intérieure (schiste sombre)
	{ 0.14, 58 },
	{ 0.2, 70 }, -- plateau de Tonto (pentes verdâtres)
	{ 0.4, 78 },
	{ 0.45, 132 }, -- grande falaise rouge (Redwall)
	{ 0.53, 140 },
	{ 0.64, 156 }, -- pentes en marches (Supai)
	{ 0.72, 166 },
	{ 0.8, 176 },
	{ 0.95, 186 },
	{ 0.985, 200 }, -- falaise claire du bord (Coconino / Kaibab), à pic jusqu'au plateau
	{ 1, 200 },
}
local function profileAt(s: number): number
	if s <= 0 then
		return PROFILE[1][2]
	end
	for i = 2, #PROFILE do
		local a, b = PROFILE[i - 1], PROFILE[i]
		if s <= b[1] then
			return a[2] + (b[2] - a[2]) * (s - a[1]) / (b[1] - a[1])
		end
	end
	return PROFILE[#PROFILE][2]
end

-- Mesas à l'horizon (au-delà du bord ouest) et buttes isolées sur le plateau de Tonto
local function makeMesas(rng: Random)
	local mesas = {}
	for _ = 1, 16 do
		local z = rng:NextNumber(REGION_Z0 + 60, REGION_Z1 - 60)
		local _, axis, half = Config.CanyonAt(z)
		local x = axis - half - rng:NextNumber(70, 520)
		if x > REGION_X0 + 40 then
			table.insert(mesas, { x = x, z = z, r = rng:NextNumber(35, 90), top = RIM + rng:NextInteger(2, 9) * LAYER })
		end
	end
	for _ = 1, 7 do
		local z = rng:NextNumber(REGION_Z0 + 100, REGION_Z1 - 100)
		if math.abs(z) > 140 then -- jamais dans l'axe du lancer
			local _, axis, half, slot = Config.CanyonAt(z)
			local side = rng:NextNumber() < 0.5 and -1 or 1
			local d = slot + (half - slot) * rng:NextNumber(0.24, 0.36)
			table.insert(mesas, { x = axis + side * d, z = z, r = rng:NextNumber(16, 28), top = rng:NextInteger(15, 19) * LAYER })
		end
	end
	return mesas
end

local function heightAt(x: number, z: number, mesas): number
	if x >= REGION_X1 then
		return RIM
	end
	local _, axis, half, slot = Config.CanyonAt(z)
	local d = math.abs(x - axis)
	local h
	if d < slot then
		return SLOT -- la faille : pas de fond (les zones profondes)
	end
	local s = (d - slot) / math.max(1, half - slot)
	-- irrégularités : les falaises ne sont pas droites, les deux rives diffèrent un peu
	s += math.noise(x / 90, z / 90, 3.7) * 0.07 + math.noise(x / 30, z / 30, 9.1) * 0.03
	if x < axis then
		s *= 0.94
	end
	if s >= 1 then
		h = RIM
	else
		h = profileAt(s)
	end
	for _, m in ipairs(mesas) do
		local dist = math.sqrt((x - m.x) ^ 2 + (z - m.z) ^ 2)
		if dist < m.r then
			local tier = dist < m.r * 0.55 and m.top or (dist < m.r * 0.8 and m.top - 20 or m.top - 50)
			h = math.max(h, tier)
		end
	end
	return math.max(math.floor(h / LAYER + 0.5) * LAYER, 40)
end

-- Construit les strates visibles : seules les cellules exposées (dessus ou
-- côté découvert) sont créées, fusionnées en rectangles par couche.
local function buildCanyon(parent: Folder, rng: Random)
	local canyon = folder("GrandCanyon", parent)
	local nx = math.floor((REGION_X1 - REGION_X0) / CELL)
	local nz = math.floor((REGION_Z1 - REGION_Z0) / CELL)
	local buttes = makeMesas(rng)
	local heights = table.create(nx * nz, 0)
	local function idx(i, k)
		return (k - 1) * nx + i
	end
	local maxH = 0
	for k = 1, nz do
		for i = 1, nx do
			local x = REGION_X0 + (i - 0.5) * CELL
			local z = REGION_Z0 + (k - 0.5) * CELL
			local h = heightAt(x, z, buttes)
			heights[idx(i, k)] = h
			maxH = math.max(maxH, h)
		end
	end
	local function hAt(i, k)
		if i > nx then
			return RIM -- plateau côté joueurs
		elseif i < 1 then
			return RIM + 10 -- plateaux lointains à l'ouest
		elseif k < 1 or k > nz then
			return RIM -- plateaux lointains au nord / sud
		end
		return heights[idx(i, k)]
	end

	local partCount = 0
	for layer = 0, math.floor(maxH / LAYER) - 1 do
		local y0 = layer * LAYER
		local y1 = y0 + LAYER
		-- cellules pleines ET visibles dans cette couche
		local visible = {}
		for k = 1, nz do
			for i = 1, nx do
				local h = heights[idx(i, k)]
				if h >= y1 then
					local exposed = h == y1 or hAt(i + 1, k) < y1 or hAt(i - 1, k) < y1 or hAt(i, k + 1) < y1 or hAt(i, k - 1) < y1
					if exposed then
						visible[idx(i, k)] = true
					end
				end
			end
		end
		-- fusion gloutonne en rectangles
		local color, material = Landscape.StrataAt(y0 + 1)
		for k = 1, nz do
			for i = 1, nx do
				if visible[idx(i, k)] then
					local w = 1
					while i + w <= nx and visible[idx(i + w, k)] do
						w += 1
					end
					local d = 1
					local grow = true
					while grow and k + d <= nz do
						for ii = i, i + w - 1 do
							if not visible[idx(ii, k + d)] then
								grow = false
								break
							end
						end
						if grow then
							d += 1
						end
					end
					for kk = k, k + d - 1 do
						for ii = i, i + w - 1 do
							visible[idx(ii, kk)] = nil
						end
					end
					local minV = Vector3.new(REGION_X0 + (i - 1) * CELL, y0, REGION_Z0 + (k - 1) * CELL)
					local maxV = Vector3.new(REGION_X0 + (i - 1 + w) * CELL, y1, REGION_Z0 + (k - 1 + d) * CELL)
					block("Strata", minV, maxV, color, material, canyon)
					partCount += 1
				end
			end
		end
		task.wait() -- une couche à la fois
	end
	return heights, nx, nz, partCount
end

-- Parois de la faille sous y = 0 (jusqu'au fond du canyon) : une dalle par
-- tronçon de bord, découpée en quelques bandes de profondeur aux couleurs des
-- zones traversées (la brume cache le reste)
local function zoneColorAt(depthBelowRim: number, rng: Random): Color3
	for _, zone in ipairs(Config.Zones) do
		if depthBelowRim <= zone.bandBottom then
			return zone.wallColors[rng:NextInteger(1, #zone.wallColors)]
		end
	end
	local last = Config.Zones[#Config.Zones]
	return last.wallColors[1]
end

local function buildSlot(parent: Folder, heights, nx: number, nz: number, rng: Random)
	local slotFolder = folder("Faille", parent)
	local bottom = RIM - W.CanyonDepth
	local bands = {}
	local step = 160
	local y = 0
	while y > bottom do
		table.insert(bands, { y1 = y, y0 = math.max(bottom, y - step) })
		y -= step
	end
	local function isSlot(i, k)
		if i < 1 or i > nx or k < 1 or k > nz then
			return false
		end
		return heights[(k - 1) * nx + i] == SLOT
	end
	local count = 0
	-- faces perpendiculaires à X : roche en i, faille en i+dir ; tronçons fusionnés le long de z
	for _, dir in ipairs({ -1, 1 }) do
		for i = 1, nx do
			local k = 1
			while k <= nz do
				if not isSlot(i, k) and isSlot(i + dir, k) then
					local k1 = k
					while k1 + 1 <= nz and not isSlot(i, k1 + 1) and isSlot(i + dir, k1 + 1) do
						k1 += 1
					end
					local faceX = REGION_X0 + (dir > 0 and i or (i - 1)) * CELL
					local z0, z1 = REGION_Z0 + (k - 1) * CELL, REGION_Z0 + k1 * CELL
					for _, band in ipairs(bands) do
						local color = zoneColorAt(RIM - (band.y0 + band.y1) / 2, rng)
						local x0 = dir > 0 and faceX - 3 or faceX
						block("SlotWall", Vector3.new(x0, band.y0, z0), Vector3.new(x0 + 3, band.y1, z1), color, Enum.Material.Slate, slotFolder)
						count += 1
						if rng:NextNumber() < 0.12 then -- filon lumineux
							local oy = rng:NextNumber(band.y0 + 4, band.y1 - 8)
							local oz = rng:NextNumber(z0, math.max(z0, z1 - 6))
							local zone = Config.Zones[math.clamp(math.floor((RIM - oy) / 50), 1, #Config.Zones)]
							local ore = zone.oreColors and zone.oreColors[1] or color:Lerp(Color3.new(1, 1, 1), 0.4)
							local ox = dir > 0 and faceX - 1 or faceX - 1
							block("SlotOre", Vector3.new(ox, oy, oz), Vector3.new(ox + 2, oy + 4, oz + 6), ore, Enum.Material.Neon, slotFolder)
						end
					end
					k = k1 + 1
				else
					k += 1
				end
			end
		end
		task.wait()
	end
	-- faces perpendiculaires à Z (là où la faille se décale d'une rangée à l'autre)
	for _, dir in ipairs({ -1, 1 }) do
		for k = 1, nz do
			for i = 1, nx do
				if not isSlot(i, k) and isSlot(i, k + dir) then
					local faceZ = REGION_Z0 + (dir > 0 and k or (k - 1)) * CELL
					local x0, x1 = REGION_X0 + (i - 1) * CELL, REGION_X0 + i * CELL
					local z0 = dir > 0 and faceZ - 3 or faceZ
					for _, band in ipairs(bands) do
						block("SlotWall", Vector3.new(x0, band.y0, z0), Vector3.new(x1, band.y1, z0 + 3), zoneColorAt(RIM - (band.y0 + band.y1) / 2, rng), Enum.Material.Slate, slotFolder)
						count += 1
					end
				end
			end
			if k % 30 == 0 then
				task.wait()
			end
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Plateau désertique (rive des joueurs) + plateaux lointains
---------------------------------------------------------------------------
local function buildPlateaus(parent: Folder, rng: Random)
	local ground = folder("Plateau", parent)
	local top, base = RIM, RIM - 50
	local sand = DESERT[1]
	-- côté joueurs, autour des masses de terre du village (x 15..135, |z| < GORGE_Z)
	block("East", Vector3.new(135, base, -PLATEAU_EXTENT), Vector3.new(PLATEAU_EXTENT, top, PLATEAU_EXTENT), sand, Enum.Material.Sand, ground)
	block("North", Vector3.new(REGION_X1, base, GORGE_Z), Vector3.new(135, top, PLATEAU_EXTENT), sand, Enum.Material.Sand, ground)
	block("South", Vector3.new(REGION_X1, base, -PLATEAU_EXTENT), Vector3.new(135, top, -GORGE_Z), sand, Enum.Material.Sand, ground)
	-- au-delà du canyon voxel (nord / sud) : plateau à la hauteur du bord
	block("CanyonNorthEnd", Vector3.new(REGION_X0, 0, REGION_Z1), Vector3.new(REGION_X1, RIM, PLATEAU_EXTENT), Landscape.StrataAt(RIM + 5), Enum.Material.Limestone, ground)
	block("CanyonSouthEnd", Vector3.new(REGION_X0, 0, -PLATEAU_EXTENT), Vector3.new(REGION_X1, RIM, REGION_Z0), Landscape.StrataAt(RIM + 5), Enum.Material.Limestone, ground)
	-- au-delà du grand canyon (rive nord) et à ses extrémités, jusqu'à l'horizon
	local kaibab = Landscape.StrataAt(RIM + 5)
	block("FarWest", Vector3.new(-PLATEAU_EXTENT, 0, -PLATEAU_EXTENT), Vector3.new(REGION_X0, RIM + 10, PLATEAU_EXTENT), kaibab, Enum.Material.Limestone, ground)
	-- taches de terre rouge / sable pâle pour casser l'uniformité
	for _ = 1, 140 do
		local x = rng:NextNumber(-60, 700)
		local z = rng:NextNumber(-700, 700)
		local inVillage = x > -25 and x < 150 and math.abs(z) < 75
		if not inVillage and x > REGION_X1 + 4 then
			local sx, sz = rng:NextInteger(2, 6) * 4, rng:NextInteger(2, 6) * 4
			local patch = block("Patch", Vector3.new(x, top, z), Vector3.new(x + sx, top + 0.2, z + sz),
				DESERT[rng:NextInteger(1, #DESERT)]:Lerp(hex("b5653a"), rng:NextNumber(0, 0.35)), Enum.Material.Sand, ground)
			patch.CanCollide = false
		end
	end
	-- rochers voxel en saillie près du bord
	for _ = 1, 40 do
		local x = rng:NextNumber(-70, 400)
		local z = rng:NextNumber(-600, 600)
		if not (x > -25 and x < 150 and math.abs(z) < 75) and x > REGION_X1 + 4 then
			local s = rng:NextInteger(1, 3) * 2
			local color = Landscape.StrataAt(RIM + 5)
			block("Outcrop", Vector3.new(x, top, z), Vector3.new(x + s * 2, top + s, z + s * 2), color:Lerp(hex("b5653a"), 0.25), Enum.Material.Limestone, ground)
		end
	end
	task.wait()
end

-- Le dessus d'origine (herbe) devient du sable ; anciens arbres verts retirés
local function desertify(world: Folder)
	for _, name in ipairs({ "PlayerSideGrass", "FarSideGrass", "CapNorthGrass", "CapSouthGrass" }) do
		local part = world:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = DESERT[1]
			part.Material = Enum.Material.Sand
		end
	end
	local nature = world:FindFirstChild("Nature")
	if nature then
		nature:Destroy()
	end
	for _, piece in ipairs(workspace:GetChildren()) do
		if piece:IsA("BasePart") and piece.Name:match("^Baseplate") then
			piece.Color = hex("5a3a2a")
		end
	end
end

---------------------------------------------------------------------------
-- Props voxel (Blender) : végétation, rochers, décor de l'Ouest
---------------------------------------------------------------------------
local propsFolder = ReplicatedStorage:FindFirstChild("Props")

local function placeProp(name: string, position: Vector3, yaw: number, scale: number, parent: Instance): Model?
	local template = propsFolder and propsFolder:FindFirstChild(name)
	if not template then
		return nil
	end
	local model = template:Clone()
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	model.Parent = parent
	return model
end

-- Zones à garder libres sur le plateau (puits, station, village des musées, spawn)
local function isBlocked(x: number, z: number): boolean
	if x < REGION_X1 + 4 then
		return true -- le canyon (ses props sont posés sur les terrasses par une autre boucle)
	end
	if x > -25 and x < 30 and math.abs(z) < 78 then
		return true -- puits + barrière + plateforme
	end
	if x > 30 and x < 170 and math.abs(z) < 72 then
		return true -- village (musées, spawn, chemins)
	end
	return false
end

local VEGETATION = {
	{ "Sagebrush", 30, 0.8, 1.6 }, { "BoulderB", 14, 0.8, 1.5 }, { "BoulderA", 9, 0.8, 1.8 },
	{ "Saguaro", 10, 0.9, 1.4 }, { "SaguaroTall", 7, 0.9, 1.3 }, { "Juniper", 10, 0.9, 1.6 },
	{ "JuniperSmall", 9, 0.8, 1.4 }, { "PricklyPear", 8, 0.8, 1.3 }, { "BarrelCactus", 8, 0.8, 1.4 },
}
local function pickWeighted(rng: Random, list)
	local total = 0
	for _, e in ipairs(list) do
		total += e[2]
	end
	local roll = rng:NextNumber(0, total)
	for _, e in ipairs(list) do
		roll -= e[2]
		if roll <= 0 then
			return e
		end
	end
	return list[1]
end

local function scatterProps(parent: Folder, rng: Random, heights, nx: number, nz: number)
	local props = folder("Props", parent)
	-- plateau : plus dense près du village, plus clairsemé au loin
	local placed = 0
	local tries = 0
	while placed < 260 and tries < 2000 do
		tries += 1
		local radius = rng:NextNumber(40, 650) ^ 1 * (rng:NextNumber() < 0.6 and 0.5 or 1)
		local angle = rng:NextNumber(0, math.pi * 2)
		local x = 40 + math.cos(angle) * radius
		local z = math.sin(angle) * radius * 1.3
		if x > -72 and not isBlocked(x, z) then
			local e = pickWeighted(rng, VEGETATION)
			if placeProp(e[1], Vector3.new(x, RIM, z), rng:NextNumber(0, math.pi * 2), rng:NextNumber(e[3], e[4]), props) then
				placed += 1
			end
		end
		if tries % 100 == 0 then
			task.wait()
		end
	end
	-- terrasses du canyon : genévriers, armoise, rochers sur les replats
	local canyonProps = { { "Juniper", 10, 1.2, 2.2 }, { "JuniperSmall", 8, 1, 2 }, { "Sagebrush", 10, 1.2, 2.2 }, { "BoulderA", 6, 1.5, 3 } }
	local count = 0
	tries = 0
	while count < 170 and tries < 3000 do
		tries += 1
		local i, k = rng:NextInteger(2, nx - 1), rng:NextInteger(2, nz - 1)
		local h = heights[(k - 1) * nx + i]
		local flat = heights[(k - 1) * nx + i + 1] == h and heights[(k - 1) * nx + i - 1] == h
		if h > RIVER_LEVEL + 20 and flat then
			local x = REGION_X0 + (i - 0.5) * CELL + rng:NextNumber(-6, 6)
			local z = REGION_Z0 + (k - 0.5) * CELL + rng:NextNumber(-6, 6)
			local e = pickWeighted(rng, canyonProps)
			if placeProp(e[1], Vector3.new(x, h, z), rng:NextNumber(0, math.pi * 2), rng:NextNumber(e[3], e[4]), props) then
				count += 1
			end
		end
		if tries % 150 == 0 then
			task.wait()
		end
	end
end

-- Décor du village de l'Ouest autour de la station (positions choisies)
local function buildVillageProps(parent: Folder)
	local village = folder("Village", parent)
	local y = RIM
	local spots = {
		{ "Wagon", Vector3.new(52, y, -26), math.rad(20), 1 },
		{ "MineCart", Vector3.new(30, y, -9), math.rad(90), 1 },
		{ "Barrel", Vector3.new(31, y, 22), 0, 1 },
		{ "Barrel", Vector3.new(34, y, 23), math.rad(30), 0.9 },
		{ "Crate", Vector3.new(33, y, 26.5), math.rad(15), 1 },
		{ "Crate", Vector3.new(29, y, -14), math.rad(40), 1.1 },
		{ "Barrel", Vector3.new(27, y, -15), 0, 1 },
		{ "Signpost", Vector3.new(58, y, 6), math.rad(-90), 1.2 },
		{ "CowSkull", Vector3.new(24, y, 34), math.rad(70), 1 },
		{ "Sagebrush", Vector3.new(60, y, -10), 0, 1.2 },
		{ "BarrelCactus", Vector3.new(40, y, 30), 0, 1 },
		{ "Saguaro", Vector3.new(38, y, -66), math.rad(30), 1.2 },
		{ "PricklyPear", Vector3.new(36, y, 40), math.rad(60), 1.1 },
		{ "Crate", Vector3.new(44, y, 60), 0, 1 },
		{ "Barrel", Vector3.new(41, y, 58), 0, 1 },
	}
	for _, s in ipairs(spots) do
		placeProp(s[1], s[2], s[3], s[4], village)
	end
end

---------------------------------------------------------------------------
-- Point de lancer (petit ponton) et atelier de nettoyage
--   Garde les pièces lues par le code : Pulley (logique, invisible),
--   LaunchPad et ThrowZone (déplacés sur le ponton en surplomb).
---------------------------------------------------------------------------
Landscape.STATION_VERSION = 3 -- v2 : petit ponton (lancer à la main) + atelier de nettoyage
local WOOD = hex("8b5e34")
local WOOD_DARK = hex("5e3d22")
local IRON = hex("3b3b40")

local function beam(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material, parent: Instance)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = Vector3.new(thickness, thickness, (b - a).Magnitude)
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function lantern(position: Vector3, parent: Instance)
	local lamp = block("Lantern", position - Vector3.new(0.45, 0.6, 0.45), position + Vector3.new(0.45, 0.6, 0.45), hex("ffcf7a"), Enum.Material.Neon, parent)
	lamp.CanCollide = false
	block("LanternCap", position + Vector3.new(-0.6, 0.6, -0.6), position + Vector3.new(0.6, 0.9, 0.6), IRON, Enum.Material.Metal, parent).CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = hex("ffb45a")
	light.Range = 16
	light.Brightness = 1.3
	light.Shadows = false
	light.Parent = lamp
end

function Landscape.BuildStation(world: Folder)
	if world:GetAttribute("StationVersion") == Landscape.STATION_VERSION then
		return
	end
	-- anciens éléments : grue, chevalement, jambes en A, lanternes du village, disque jaune
	for _, name in ipairs({ "CranePost", "CraneBoom", "PulleyBracket", "Headframe", "Pier", "Workshop", "ThrowZoneMarker" }) do
		local old = world:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local landscape = world:FindFirstChild("Landscape")
	local oldStation = landscape and landscape:FindFirstChild("Station")
	if oldStation then
		oldStation:Destroy()
	end
	local village = landscape and landscape:FindFirstChild("Village")
	if village then
		for _, child in ipairs(village:GetChildren()) do
			if child.Name == "LanternPost" or child.Name == "Lantern" then
				child:Destroy()
			end
		end
	end

	-------------------------------------------------------------------
	-- Petit ponton : on lance l'aimant à la main au-dessus du trou
	-------------------------------------------------------------------
	local pier = folder("Pier", world)
	local deckY = RIM + 1
	block("PierWalk", Vector3.new(13.5, RIM, -2), Vector3.new(19.5, deckY, 2), WOOD, Enum.Material.WoodPlanks, pier)
	block("PierJoist", Vector3.new(9.5, RIM - 1, -2.2), Vector3.new(19, RIM, -1.6), WOOD_DARK, Enum.Material.Wood, pier)
	block("PierJoist", Vector3.new(9.5, RIM - 1, 1.6), Vector3.new(19, RIM, 2.2), WOOD_DARK, Enum.Material.Wood, pier)
	beam("PierStrut", Vector3.new(15, RIM - 7, 0), Vector3.new(10.5, RIM - 1, 0), 0.6, WOOD_DARK, Enum.Material.Wood, pier)
	local pad = world:FindFirstChild("LaunchPad")
	if pad then
		pad.Size = Vector3.new(5, 1, 5)
		pad.Position = Vector3.new(11.5, RIM + 0.5, 0)
		pad.Color = WOOD
		pad.Material = Enum.Material.WoodPlanks
	end
	-- cordes en guise de rambardes (côtés + bout), poteaux bas
	local ROPE = hex("c9a46a")
	for _, z in ipairs({ -2.3, 2.3 }) do
		for _, x in ipairs({ 9.3, 13.6, 18 }) do
			block("RopePost", Vector3.new(x - 0.25, deckY, z - 0.25), Vector3.new(x + 0.25, deckY + 2.4, z + 0.25), WOOD_DARK, Enum.Material.Wood, pier)
		end
		beam("Rope", Vector3.new(9.3, deckY + 2, z), Vector3.new(18, deckY + 2, z), 0.18, ROPE, Enum.Material.Fabric, pier)
	end
	beam("Rope", Vector3.new(9.3, deckY + 2, -2.3), Vector3.new(9.3, deckY + 2, 2.3), 0.18, ROPE, Enum.Material.Fabric, pier)
	-- rouleau de corde sur le ponton + lanterne à l'entrée
	local coil = Instance.new("Part")
	coil.Name = "RopeCoil"
	coil.Shape = Enum.PartType.Cylinder
	coil.Size = Vector3.new(0.6, 1.6, 1.6)
	coil.CFrame = CFrame.new(17.2, deckY + 0.3, 1.2) * CFrame.Angles(0, 0, math.rad(90))
	coil.Color = ROPE
	coil.Material = Enum.Material.Fabric
	coil.Anchored = true
	coil.Parent = pier
	block("LanternPost", Vector3.new(19.6, RIM, 2.6), Vector3.new(20.1, RIM + 5, 3.1), WOOD_DARK, Enum.Material.Wood, pier)
	lantern(Vector3.new(19.85, RIM + 5.6, 2.85), pier)
	-- petit panneau
	local board = block("PierSignBoard", Vector3.new(19.5, RIM + 3, -3.6), Vector3.new(19.9, RIM + 4.4, -0.9), WOOD, Enum.Material.WoodPlanks, pier)
	block("PierSignPost", Vector3.new(19.55, RIM, -2.5), Vector3.new(19.85, RIM + 3, -2.2), WOOD_DARK, Enum.Material.Wood, pier)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.PixelsPerStud = 50
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = hex("ffe2a8")
	label.TextStrokeTransparency = 0.2
	label.Text = "🧲 LANCER"
	label.Parent = gui
	gui.Parent = board

	-- zone de lancer = la plateforme du bout (petite : un pas en arrière suffit pour sortir)
	local zone = world:FindFirstChild("ThrowZone")
	if zone and pad then
		zone.Size = Vector3.new(5, 8, 5)
		zone.Position = pad.Position + Vector3.new(0, pad.Size.Y / 2 + 4, 0)
		for i = 0, 9 do -- cercle discret peint sur la plateforme
			local angle = i / 10 * math.pi * 2
			local seg = block("ZoneRing", Vector3.zero, Vector3.new(0.9, 0.06, 0.25), hex("ffb347"), Enum.Material.Neon, pier)
			seg.CFrame = CFrame.new(pad.Position + Vector3.new(math.cos(angle) * 1.8, pad.Size.Y / 2 + 0.04, math.sin(angle) * 1.8))
				* CFrame.Angles(0, -angle + math.pi / 2, 0)
			seg.Transparency = 0.35
			seg.CanCollide = false
			seg.CanQuery = false
		end
	end
	-- repère logique invisible au-dessus du trou (le client y vise le lancer)
	local pulley = world:FindFirstChild("Pulley")
	if pulley then
		pulley.Size = Vector3.new(1, 2, 2)
		pulley.CFrame = CFrame.new(0, RIM + 9, 0)
		pulley.Transparency = 1
		pulley.CanCollide = false
		pulley.CanQuery = false
	end

	-------------------------------------------------------------------
	-- Atelier de nettoyage : établi sous un auvent rayé
	-------------------------------------------------------------------
	local shop = folder("Workshop", world)
	local platform = world:FindFirstChild("CleaningPlatform")
	local center = Vector3.new(22, RIM, 16)
	if platform then
		-- plateau de l'établi (la relique se pose dessus)
		platform.Size = Vector3.new(7, 1, 4.6)
		platform.Position = center + Vector3.new(0, 2.5, 0)
		platform.Color = hex("a8784a")
		platform.Material = Enum.Material.WoodPlanks
		for _, dx in ipairs({ -3, 3 }) do
			for _, dz in ipairs({ -1.8, 1.8 }) do
				block("BenchLeg", center + Vector3.new(dx - 0.3, 0.2, dz - 0.3), center + Vector3.new(dx + 0.3, 2, dz + 0.3), WOOD_DARK, Enum.Material.Wood, shop)
			end
		end
		-- tissu de travail sur l'établi
		block("Cloth", center + Vector3.new(-1.6, 3, -1.2), center + Vector3.new(1.6, 3.06, 1.2), hex("d9c7a3"), Enum.Material.Fabric, shop).CanCollide = false
	end
	local bucket = world:FindFirstChild("Bucket")
	if bucket then
		bucket.Size = Vector3.new(1.6, 1.8, 1.6)
		bucket.Position = center + Vector3.new(4.6, 1.1, -3)
		bucket.Color = hex("6e4a26")
	end
	-- plancher
	block("Floor", center + Vector3.new(-6, 0, -6), center + Vector3.new(8, 0.3, 7), WOOD, Enum.Material.WoodPlanks, shop)
	-- poteaux + auvent en toile rayée
	local roofY = RIM + 10
	for _, p in ipairs({ { -5.5, -5.5 }, { 7.5, -5.5 }, { -5.5, 6.5 }, { 7.5, 6.5 } }) do
		block("Post", center + Vector3.new(p[1] - 0.4, 0, p[2] - 0.4), center + Vector3.new(p[1] + 0.4, 10, p[2] + 0.4), WOOD_DARK, Enum.Material.Wood, shop)
	end
	block("RoofBeam", center + Vector3.new(-6.2, 9.6, -6.2), center + Vector3.new(8.2, 10.2, -5.4), WOOD_DARK, Enum.Material.Wood, shop)
	block("RoofBeam", center + Vector3.new(-6.2, 9.6, 6.2), center + Vector3.new(8.2, 10.2, 7), WOOD_DARK, Enum.Material.Wood, shop)
	local stripes = { hex("c0392b"), hex("f3e5c8") }
	for i = 0, 7 do
		local x0 = -6.5 + i * 1.875
		local canvas = Instance.new("Part")
		canvas.Name = "Awning"
		canvas.Anchored = true
		canvas.Size = Vector3.new(1.875, 0.2, 14)
		canvas.CFrame = CFrame.new(center + Vector3.new(x0 + 0.94, 10.6, 0.5)) * CFrame.Angles(math.rad(6), 0, 0)
		canvas.Color = stripes[i % 2 + 1]
		canvas.Material = Enum.Material.Fabric
		canvas.CastShadow = true
		canvas.Parent = shop
	end
	-- lambrequin festonné à l'avant de l'auvent
	for i = 0, 14 do
		block("Valance", center + Vector3.new(-6.5 + i, 9.2, 7.4), center + Vector3.new(-5.6 + i, 9.9, 7.6), stripes[i % 2 + 1], Enum.Material.Fabric, shop).CanCollide = false
	end
	-- abreuvoir + pompe à eau (fond de l'atelier)
	local trough = center + Vector3.new(0, 0.3, -4.5)
	block("Trough", trough + Vector3.new(-3.5, 0, -0.9), trough + Vector3.new(3.5, 1.6, 0.9), WOOD_DARK, Enum.Material.Wood, shop)
	local water = block("TroughWater", trough + Vector3.new(-3.2, 1.2, -0.6), trough + Vector3.new(3.2, 1.45, 0.6), hex("4fa3c7"), Enum.Material.Glass, shop)
	water.Transparency = 0.25
	water.Reflectance = 0.2
	water.CanCollide = false
	local pump = trough + Vector3.new(-4.4, 0, 0)
	block("PumpBody", pump + Vector3.new(-0.4, 0, -0.4), pump + Vector3.new(0.4, 3.4, 0.4), IRON, Enum.Material.Metal, shop)
	beam("PumpSpout", pump + Vector3.new(0, 3, 0), pump + Vector3.new(1.2, 2.7, 0), 0.35, IRON, Enum.Material.Metal, shop)
	beam("PumpHandle", pump + Vector3.new(0, 3.4, 0), pump + Vector3.new(-1.2, 4.1, 0), 0.2, IRON, Enum.Material.Metal, shop)
	local spout = block("Drip", pump + Vector3.new(1.1, 2.5, -0.1), pump + Vector3.new(1.3, 2.6, 0.1), IRON, Enum.Material.Metal, shop)
	local drip = Instance.new("ParticleEmitter")
	drip.Color = ColorSequence.new(hex("bfe6ff"))
	drip.Size = NumberSequence.new(0.12)
	drip.Lifetime = NumberRange.new(0.5, 0.6)
	drip.Rate = 3
	drip.Speed = NumberRange.new(0)
	drip.Acceleration = Vector3.new(0, -20, 0)
	drip.Parent = spout
	-- mur d'outils côté canyon (brosses, étagère, bocaux)
	local wallX = center.X - 6
	block("ToolWall", Vector3.new(wallX - 0.3, RIM, center.Z - 5), Vector3.new(wallX + 0.3, RIM + 8, center.Z + 6), WOOD, Enum.Material.WoodPlanks, shop)
	block("Shelf", Vector3.new(wallX + 0.3, RIM + 5, center.Z - 3), Vector3.new(wallX + 1.3, RIM + 5.2, center.Z + 3), WOOD_DARK, Enum.Material.Wood, shop)
	local jars = { hex("7fd3f7"), hex("f4d03f"), hex("a3d977"), hex("e59866"), hex("c39bd3") }
	for i, color in ipairs(jars) do
		local jar = block("Jar", Vector3.new(wallX + 0.5, RIM + 5.2, center.Z - 3 + i), Vector3.new(wallX + 1.1, RIM + 6.1, center.Z - 2.4 + i), color, Enum.Material.Glass, shop)
		jar.Transparency = 0.3
	end
	for i = 0, 2 do -- brosses accrochées
		local z = center.Z - 1 + i * 1.4
		block("BrushHandle", Vector3.new(wallX + 0.3, RIM + 3, z - 0.15), Vector3.new(wallX + 0.6, RIM + 4.4, z + 0.15), hex("b07a45"), Enum.Material.Wood, shop)
		block("BrushHead", Vector3.new(wallX + 0.3, RIM + 2.4, z - 0.35), Vector3.new(wallX + 0.8, RIM + 3, z + 0.35), hex("e8d9a8"), Enum.Material.Fabric, shop)
	end
	-- enseigne
	local sign = block("WorkshopSign", Vector3.new(wallX + 0.3, RIM + 6.6, center.Z - 3.5), Vector3.new(wallX + 0.5, RIM + 8, center.Z + 4.5), hex("6e4a26"), Enum.Material.WoodPlanks, shop)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Right
	signGui.PixelsPerStud = 40
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.LuckiestGuy
	signLabel.TextScaled = true
	signLabel.TextColor3 = hex("ffe2a8")
	signLabel.Text = "🗝 OUVERTURE DES COFFRES"
	signLabel.Parent = signGui
	signGui.Parent = sign
	-- lanterne suspendue sous l'auvent
	local hang = Vector3.new(-4.2, 0, -4.2) -- au fond, hors du champ de la caméra de nettoyage
	beam("LanternChain", center + hang + Vector3.new(0, 9.6, 0), center + hang + Vector3.new(0, 8.4, 0), 0.12, IRON, Enum.Material.Metal, shop)
	lantern(center + hang + Vector3.new(0, 7.8, 0), shop)

	world:SetAttribute("StationVersion", Landscape.STATION_VERSION)
end

-- Station de la grue habillée en bois de chercheur d'or
local function dressStation(world: Folder, parent: Folder)
	local station = folder("Station", parent)
	local post = world:FindFirstChild("CranePost")
	if post then
		local p = post.Position
		local bottom = RIM
		-- jambes en A de part et d'autre du poteau
		for _, side in ipairs({ -1, 1 }) do
			local foot = Vector3.new(p.X + 3, bottom, p.Z + side * 6)
			local head = Vector3.new(p.X, bottom + 16, p.Z)
			local leg = Instance.new("Part")
			leg.Name = "CraneLeg"
			leg.Anchored = true
			leg.Size = Vector3.new(1.2, (head - foot).Magnitude, 1.2)
			leg.CFrame = CFrame.lookAt((foot + head) / 2, head) * CFrame.Angles(math.rad(90), 0, 0)
			leg.Color = hex("6b4a2e")
			leg.Material = Enum.Material.Wood
			leg.Parent = station
		end
	end
	local platform = world:FindFirstChild("CleaningPlatform")
	if platform then
		platform.Color = hex("8b5e34")
		platform.Material = Enum.Material.WoodPlanks
	end
	local bucket = world:FindFirstChild("Bucket")
	if bucket then
		bucket.Color = hex("6e4a26")
	end
end

---------------------------------------------------------------------------
-- Lumière : coucher de soleil doré
---------------------------------------------------------------------------
local function ensure(className: string, parent: Instance, name: string?)
	local inst = parent:FindFirstChildOfClass(className)
	if not inst then
		inst = Instance.new(className)
		if name then
			inst.Name = name
		end
		inst.Parent = parent
	end
	return inst
end

function Landscape.ApplyLighting()
	Lighting.ClockTime = 17.85
	Lighting.GeographicLatitude = 36
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(105, 78, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(165, 120, 100)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 176, 110)
	Lighting.ColorShift_Bottom = Color3.fromRGB(90, 50, 60)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ShadowSoftness = 0.3

	local atmosphere = ensure("Atmosphere", Lighting)
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(255, 186, 140)
	atmosphere.Decay = Color3.fromRGB(190, 100, 80)
	atmosphere.Glare = 0.5
	atmosphere.Haze = 1.8

	local bloom = ensure("BloomEffect", Lighting, "SunsetBloom")
	bloom.Intensity = 0.5
	bloom.Size = 28
	bloom.Threshold = 1.4

	local rays = ensure("SunRaysEffect", Lighting, "SunsetRays")
	rays.Intensity = 0.1
	rays.Spread = 0.7

	local grading = Lighting:FindFirstChild("SunsetGrading") or Instance.new("ColorCorrectionEffect")
	grading.Name = "SunsetGrading"
	grading.Brightness = 0.02
	grading.Contrast = 0.1
	grading.Saturation = 0.12
	grading.TintColor = Color3.fromRGB(255, 238, 220)
	grading.Parent = Lighting

	local clouds = ensure("Clouds", workspace.Terrain)
	clouds.Cover = 0.45
	clouds.Density = 0.55
	clouds.Color = Color3.fromRGB(255, 205, 180)
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function Landscape.Build(world: Folder)
	if world:GetAttribute("LandscapeVersion") == Landscape.VERSION then
		return
	end
	local old = world:FindFirstChild("Landscape")
	if old then
		old:Destroy()
	end
	local rng = Random.new(W.Seed + 7)
	local root = folder("Landscape", world)
	desertify(world)
	buildPlateaus(root, rng)
	workspace.Terrain:Clear() -- plus d'eau au fond du canyon
	local heights, nx, nz, count = buildCanyon(root, rng)
	count += buildSlot(root, heights, nx, nz, rng)
	scatterProps(root, rng, heights, nx, nz)
	buildVillageProps(root)
	dressStation(world, root)
	Landscape.ApplyLighting()
	world:SetAttribute("LandscapeVersion", Landscape.VERSION)
	world:SetAttribute("StationVersion", nil) -- le chevalement est reposé par-dessus
	Landscape.BuildStation(world)
	return count
end

return Landscape

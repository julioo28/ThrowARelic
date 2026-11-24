-- ======================================================================
-- Chemins de terre battue entre les lieux du village + bordures décorées
-- (fleurs, cailloux, herbes) + petits détails dispersés. Versionné à part :
-- PATHS_VERSION / attribut PathsVersion. Tout dans ThrowARelicWorld/Paths.
-- Léger pour mobile : décorations sans collision, sans ombre, sans requête.
-- ======================================================================
Landscape.PATHS_VERSION = 1

local PATH_Y = 200 -- dessus du sol du village
local PATH_COLOR = hex("ad7f50")
local PATH_EDGE = hex("bd915f")
local PATH_RUT = hex("94693f")

-- tracés : liste de points (x, z) + largeur
local PATHS = {
	{ w = 10, pts = { { 23, 0 }, { 146, 0 } } }, -- rue principale, du ponton au podium
	{ w = 5, pts = { { 34, 4 }, { 36, 10 }, { 33, 15 } } }, -- vers l'atelier des coffres
	{ w = 4, pts = { { 44, -4 }, { 48, -14 }, { 52, -21 } } }, -- vers le chariot
}
for _, x in ipairs({ 69, 96.5, 124 }) do -- entrées des enclos sud (z < 0)
	table.insert(PATHS, { w = 6, pts = { { x, -4 }, { x, -15.5 } } })
end
for _, x in ipairs({ 75, 102.5, 130 }) do -- entrées des enclos nord (z > 0)
	table.insert(PATHS, { w = 6, pts = { { x, 4 }, { x, 15.5 } } })
end
local PLAZA = { x0 = 140, x1 = 172, z0 = -9, z1 = 9 } -- place du podium

local function flat(name, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material, parent: Instance)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- distance d'un point (x, z) au chemin le plus proche, moins sa demi-largeur (< 0 = sur le chemin)
local function pathDistance(x: number, z: number): number
	local best = math.huge
	for _, path in ipairs(PATHS) do
		for i = 1, #path.pts - 1 do
			local a, b = path.pts[i], path.pts[i + 1]
			local abx, abz = b[1] - a[1], b[2] - a[2]
			local t = math.clamp(((x - a[1]) * abx + (z - a[2]) * abz) / (abx * abx + abz * abz), 0, 1)
			local dx, dz = x - (a[1] + abx * t), z - (a[2] + abz * t)
			best = math.min(best, math.sqrt(dx * dx + dz * dz) - path.w / 2)
		end
	end
	local px = math.max(PLAZA.x0 - x, 0, x - PLAZA.x1)
	local pz = math.max(PLAZA.z0 - z, 0, z - PLAZA.z1)
	best = math.min(best, math.sqrt(px * px + pz * pz) - (px == 0 and pz == 0 and 1 or 0))
	return best
end

local EDGE_DECO = {
	{ "EdgeStone", 30 }, { "Pebbles", 12 }, { "PebblesRed", 6 }, { "GrassDry", 14 }, { "GrassGreen", 10 },
	{ "FlowerRed", 6 }, { "FlowerYellow", 7 }, { "FlowerPurple", 5 }, { "FlowerWhite", 5 }, { "FlowerOrange", 5 },
}
local PATCHES = { -- petits massifs dispersés : un type dominant par massif
	{ { "FlowerYellow", "FlowerOrange", "GrassGreen" }, 4 },
	{ { "FlowerPurple", "FlowerWhite", "GrassGreen" }, 4 },
	{ { "FlowerRed", "FlowerYellow", "GrassDry" }, 3 },
	{ { "GrassDry", "GrassDry", "Pebbles" }, 5 },
	{ { "Pebbles", "PebblesRed", "EdgeStone" }, 4 },
	{ { "Agave", "GrassDry", "PebblesRed" }, 3 },
	{ { "Bones", "GrassDry", "Pebbles" }, 1 },
}

function Landscape.BuildPaths(world: Folder)
	if world:GetAttribute("PathsVersion") == Landscape.PATHS_VERSION then
		return 0
	end
	local old = world:FindFirstChild("Paths")
	if old then
		old:Destroy()
	end
	local root = folder("Paths", world)
	local ground = folder("Ground", root)
	local deco = folder("Deco", root)
	local rng = Random.new(1124)
	local count = 0

	-- occupation : on évite bancs, arches, musées, ponton, atelier, podium
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { root, world:FindFirstChild("PlayerSideGrass"), world:FindFirstChild("Landscape") }
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { root }
	local placed = {}
	local function free(pos: Vector3, radius: number): boolean
		for _, p in ipairs(placed) do
			if (p - pos).Magnitude < radius + 0.9 then
				return false
			end
		end
		return #workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, 2, 0)), Vector3.new(radius * 2, 3.6, radius * 2), overlap) == 0
	end
	local function groundAt(x: number, z: number): number?
		local hit = workspace:Raycast(Vector3.new(x, 260, z), Vector3.new(0, -80, 0), ray)
		if hit and hit.Position.Y > 199.4 and hit.Position.Y < 200.6 and hit.Instance:IsA("BasePart") and hit.Instance.Size.Y > 0.15 then
			return hit.Position.Y
		end
		return nil
	end
	local function put(name: string, x: number, z: number, scale: number, radius: number): boolean
		local y = groundAt(x, z)
		if not y then
			return false
		end
		local pos = Vector3.new(x, y, z)
		if not free(pos, radius) then
			return false
		end
		local m = placeProp(name, pos, rng:NextNumber(0, math.pi * 2), scale, deco)
		if m then
			table.insert(placed, pos)
			count += 1
			return true
		end
		return false
	end

	-- 1. surface des chemins : bande centrale + morceaux irréguliers sur les bords
	for _, path in ipairs(PATHS) do
		local w = path.w
		for i = 1, #path.pts - 1 do
			local a = Vector3.new(path.pts[i][1], PATH_Y, path.pts[i][2])
			local b = Vector3.new(path.pts[i + 1][1], PATH_Y, path.pts[i + 1][2])
			local len = (b - a).Magnitude
			local cf = CFrame.lookAt((a + b) / 2, b) -- -Z le long du segment, X en travers
			flat("Path", cf * CFrame.new(0, 0.05, 0), Vector3.new(w, 0.1, len), PATH_COLOR, Enum.Material.Ground, ground)
			if w >= 8 then -- ornières de roues sur la rue
				for _, off in ipairs({ -2.2, 2.2 }) do
					flat("Rut", cf * CFrame.new(off, 0.11, 0), Vector3.new(0.9, 0.02, len - 2), PATH_RUT, Enum.Material.Ground, ground)
				end
			end
			-- bords irréguliers
			local d = 0
			while d < len do
				local step = rng:NextNumber(1.6, 3.2)
				for _, side in ipairs({ -1, 1 }) do
					local bulge = rng:NextNumber(-0.5, 0.7)
					if math.abs(bulge) > 0.15 then
						local wid = 1.2 + math.abs(bulge)
						flat("PathEdge", cf * CFrame.new(side * (w / 2 + bulge - wid / 2 + 0.6), 0.04, -len / 2 + d + step / 2),
							Vector3.new(wid, 0.08, step), bulge > 0 and PATH_EDGE or PATH_COLOR, Enum.Material.Ground, ground)
					end
				end
				d += step
			end
		end
		-- jonctions arrondies
		for _, p in ipairs(path.pts) do
			local disc = flat("PathJoint", CFrame.new(p[1], PATH_Y + 0.05, p[2]) * CFrame.Angles(0, 0, math.rad(90)),
				Vector3.new(0.1, w, w), PATH_COLOR, Enum.Material.Ground, ground)
			disc.Shape = Enum.PartType.Cylinder
		end
	end
	-- place du podium (dalles de pierre claires autour)
	flat("Plaza", CFrame.new((PLAZA.x0 + PLAZA.x1) / 2, PATH_Y + 0.05, 0), Vector3.new(PLAZA.x1 - PLAZA.x0, 0.1, PLAZA.z1 - PLAZA.z0),
		PATH_COLOR, Enum.Material.Ground, ground)
	for x = PLAZA.x0 + 1, PLAZA.x1 - 1, 2.6 do
		for _, z in ipairs({ PLAZA.z0 + 0.8, PLAZA.z1 - 0.8 }) do
			flat("PlazaStone", CFrame.new(x + rng:NextNumber(-0.2, 0.2), PATH_Y + 0.12, z) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0),
				Vector3.new(2.2, 0.14, 1.3), hex(rng:NextNumber() < 0.5 and "c9b89a" or "b5a483"), Enum.Material.Slate, ground)
		end
	end

	-- 2. bordures décorées le long des chemins
	local total = 0
	for _, e in ipairs(EDGE_DECO) do
		total += e[2]
	end
	local function pickEdge()
		local r = rng:NextNumber(0, total)
		for _, e in ipairs(EDGE_DECO) do
			r -= e[2]
			if r <= 0 then
				return e[1]
			end
		end
		return EDGE_DECO[1][1]
	end
	for _, path in ipairs(PATHS) do
		for i = 1, #path.pts - 1 do
			local a = Vector3.new(path.pts[i][1], 0, path.pts[i][2])
			local b = Vector3.new(path.pts[i + 1][1], 0, path.pts[i + 1][2])
			local dir = (b - a).Unit
			local across = Vector3.new(-dir.Z, 0, dir.X)
			local len = (b - a).Magnitude
			local d = 1.5
			while d < len - 1 do
				for _, side in ipairs({ -1, 1 }) do
					if rng:NextNumber() < 0.8 then
						local p = a + dir * (d + rng:NextNumber(-0.6, 0.6)) + across * side * (path.w / 2 + rng:NextNumber(0.9, 1.6))
						if pathDistance(p.X, p.Z) > 0.6 then
							put(pickEdge(), p.X, p.Z, rng:NextNumber(0.8, 1.15), 0.8)
						end
					end
				end
				d += rng:NextNumber(2.4, 3.4)
			end
		end
	end
	-- bordure de pierres autour de la place du podium (côté rue laissé ouvert)
	for x = PLAZA.x0 + 2, PLAZA.x1 - 1, 3 do
		for _, z in ipairs({ PLAZA.z0 - 1.2, PLAZA.z1 + 1.2 }) do
			put(rng:NextNumber() < 0.6 and "EdgeStone" or pickEdge(), x, z, 1, 0.8)
		end
	end

	-- 3. massifs dispersés dans le village et autour (densité qui baisse avec la distance)
	local total2 = 0
	for _, p in ipairs(PATCHES) do
		total2 += p[2]
	end
	local patches = 0
	local tries = 0
	while patches < 95 and tries < 2000 do
		tries += 1
		local far = rng:NextNumber() < 0.35
		local x = far and rng:NextNumber(20, 260) or rng:NextNumber(20, 180)
		local z = far and rng:NextNumber(-220, 220) or rng:NextNumber(-80, 80)
		local inPlot = x > 55 and x < 145 and math.abs(z) > 6 and math.abs(z) < 53
		if not inPlot and pathDistance(x, z) > 2.5 then
			local r = rng:NextNumber(0, total2)
			local kind = PATCHES[1][1]
			for _, p in ipairs(PATCHES) do
				r -= p[2]
				if r <= 0 then
					kind = p[1]
					break
				end
			end
			local n = rng:NextInteger(3, 6)
			local okAny = false
			for k = 1, n do
				local ang = rng:NextNumber(0, math.pi * 2)
				local rad = rng:NextNumber(0.5, 3.5)
				local px, pz = x + math.cos(ang) * rad, z + math.sin(ang) * rad
				if pathDistance(px, pz) > 1 then
					local name = kind[(k == 1) and 1 or rng:NextInteger(1, #kind)]
					okAny = put(name, px, pz, rng:NextNumber(0.85, 1.25), 0.7) or okAny
				end
			end
			if okAny then
				patches += 1
			end
		end
	end

	-- 4. bottes de foin et petits détails autour des lieux
	for _, spot in ipairs({ { 38, 22 }, { 40, 24.5 }, { 147, 12 }, { 166, -12 }, { 58, -9 }, { 142, 13 } }) do
		put("HayBale", spot[1], spot[2], 1.1, 1.6)
	end

	world:SetAttribute("PathsVersion", Landscape.PATHS_VERSION)
	return count
end


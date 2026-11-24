-- Installe les coffres voxel (asset TAM_Chests) dans ReplicatedStorage/Chests.
-- Chaque coffre : Model « Chest_<rareté> » (corps) contenant un Model « Lid » (couvercle),
-- attributs Hinge (Vector3, charnière relative au pivot) et LidLocal (CFrame du couvercle
-- fermé relatif au pivot). Pivot = centre du coffre fermé ; devant = -Z (LookVector).
-- À exécuter en Edit (MCP execute_luau). Variable ASSET = id de l'asset.
local InsertService = game:GetService("InsertService")
local Rep = game:GetService("ReplicatedStorage")

local TIER = { Commun = 0, PeuCommun = 1, Rare = 2, Epique = 3, Legendaire = 4, Mythique = 5, Secret = 6, Divin = 7, Cosmique = 8 }
-- couleur d'accent (gemmes) par rareté : rendue en Neon dès Rare
local ACCENT = { Commun = "3A3A3A", PeuCommun = "8EE07A", Rare = "7FC4FF", Epique = "D68CFF", Legendaire = "FF6A3D",
	Mythique = "FF9BB5", Secret = "1FFFE6", Divin = "FFEC8C", Cosmique = "B8F0FF" }
local METAL = { F2C14E = true, FFF1A8 = true, C8CCD6 = true, B8BCC4 = true, ["5F6368"] = true }

local folder = Rep:FindFirstChild("Chests") or Instance.new("Folder")
folder.Name = "Chests"
folder.Parent = Rep

local container = InsertService:LoadAsset(ASSET)
local root = container:FindFirstChildWhichIsA("Model") or container
local out = {}

local function prepare(model: Model, rarity: string)
	local tier = TIER[rarity] or 0
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local hex = part.Name:match("_(%x%x%x%x%x%x)_%d+$")
			if hex then
				hex = hex:upper()
				part.Color = Color3.fromHex(hex)
				if tier >= 2 and hex == ACCENT[rarity] then
					part.Material = Enum.Material.Neon
				elseif METAL[hex] then
					part.Material = Enum.Material.Metal
				else
					part.Material = Enum.Material.SmoothPlastic
				end
			end
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

for rarity, tier in pairs(TIER) do
	local body = root:FindFirstChild("Chest_" .. rarity)
	local lid = root:FindFirstChild("Chest_" .. rarity .. "Lid")
	if body and lid then
		prepare(body, rarity)
		prepare(lid, rarity)
		lid.Name = "Lid"
		lid.Parent = body
		-- taille : un peu plus gros pour les raretés hautes
		local size = body:GetExtentsSize()
		local targetWidth = 3.6 + tier * 0.35
		body:ScaleTo(body:GetScale() * targetWidth / size.X)
		-- pivot du coffre = centre du coffre fermé, axes du monde
		local cf, extents = body:GetBoundingBox()
		local pivot = CFrame.new(cf.Position)
		-- PrimaryPart = plus grosse pièce du CORPS (pas du couvercle, qui bouge)
		local bestBody, vol = nil, -1
		for _, part in ipairs(body:GetChildren()) do
			if part:IsA("BasePart") then
				local v = part.Size.X * part.Size.Y * part.Size.Z
				if v > vol then
					bestBody, vol = part, v
				end
			end
		end
		body.PrimaryPart = bestBody
		bestBody.PivotOffset = bestBody.CFrame:ToObjectSpace(pivot)
		-- couvercle : pivot au centre, charnière = arrière (+Z) en bas du couvercle
		local lcf, lsize = lid:GetBoundingBox()
		lid.WorldPivot = CFrame.new(lcf.Position)
		local hinge = Vector3.new(lcf.Position.X, lcf.Position.Y - lsize.Y / 2, lcf.Position.Z + lsize.Z / 2)
		body:SetAttribute("Hinge", hinge - pivot.Position)
		body:SetAttribute("LidLocal", pivot:ToObjectSpace(lid.WorldPivot))
		body:SetAttribute("Rarity", rarity)
		local old = folder:FindFirstChild(body.Name)
		if old then
			old:Destroy()
		end
		body.Parent = folder
		table.insert(out, ("%s %.1fx%.1fx%.1f"):format(body.Name, extents.X, extents.Y, extents.Z))
	else
		table.insert(out, "MANQUE " .. rarity)
	end
end
container:Destroy()
return out

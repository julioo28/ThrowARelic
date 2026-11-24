-- Installe les modèles voxel des trouvailles (lots Open Cloud) dans ReplicatedStorage/Relics.
-- À exécuter en Edit (MCP execute_luau). Variable BATCHES = liste d'asset ids à traiter.
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local Rep = game:GetService("ReplicatedStorage")

local catalog = HttpService:JSONDecode(HttpService:GetAsync("http://127.0.0.1:34999/Assets/Relics/catalog.json"))
local byId = {}
for _, item in ipairs(catalog) do byId[item.id] = item end

local TIER = { Commun = 0, PeuCommun = 1, Rare = 2, Epique = 3, Legendaire = 4, Mythique = 5, Secret = 6, Divin = 7, Cosmique = 8 }

local folder = Rep:FindFirstChild("Relics")
local done, missing = 0, {}

local function install(model: Model, item)
	local tier = TIER[item.rarity] or 0
	local accent = string.upper(item.accent)
	local biggest, biggestVol = nil, -1
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local hex = part.Name:match("_(%x%x%x%x%x%x)_%d+$")
			if hex then
				part.Color = Color3.fromHex(hex)
				local neon = tier >= 5 and string.upper(hex) == accent
				part.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = true
			local vol = part.Size.X * part.Size.Y * part.Size.Z
			if vol > biggestVol then biggest, biggestVol = part, vol end
		end
	end
	model.Name = item.id
	model.PrimaryPart = biggest
	local size = model:GetExtentsSize()
	local target = 2.2 + tier * 0.25
	local maxDim = math.max(size.X, size.Y, size.Z)
	if maxDim > 0 then model:ScaleTo(model:GetScale() * target / maxDim) end
	-- pivot au centre de la boîte englobante (les scripts posent avec PivotTo)
	local bbox = model:GetBoundingBox()
	if biggest then biggest.PivotOffset = biggest.CFrame:ToObjectSpace(CFrame.new(bbox.Position)) end
	model:SetAttribute("Voxel", true)
	local old = folder:FindFirstChild(item.id)
	if old then old:Destroy() end
	model.Parent = folder
	done += 1
end

for _, assetId in ipairs(BATCHES) do
	local container = InsertService:LoadAsset(assetId)
	local root = container:FindFirstChildWhichIsA("Model") or container
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Model") then
			local item = byId[child.Name]
			if item then install(child, item) else table.insert(missing, child.Name) end
		end
	end
	container:Destroy()
end

return { installed = done, unknown = missing, total = #folder:GetChildren() }

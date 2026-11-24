-- Installe les props détaillés v2 (asset TAM_PropsV2, généré par tools/voxel_props_v2.py)
-- dans ReplicatedStorage/Props/<Nom>, puis remplace sur place les copies déjà posées dans
-- Workspace/ThrowARelicWorld/Landscape (Props, Village) en gardant position, rotation et échelle.
-- À exécuter en Edit (MCP execute_luau). Pivot = centre du pied, échelle 1 (Landscape et
-- AmbienceController appellent ScaleTo avec une valeur ABSOLUE).
local ASSET = 83186667019374
local METAL = { ["3A3A3A"] = true, ["6E6E74"] = true, ["4A4A50"] = true, ["2E2E2E"] = true, A8A8B0 = true }
local GOLD = { F2C14E = true, FFE38A = true }

local Props = game:GetService("ReplicatedStorage"):WaitForChild("Props")
local container = game:GetService("InsertService"):LoadAsset(ASSET)
local root = container:FindFirstChild("Saguaro", true).Parent -- l'import FBX imbrique TAM_PropsV2 deux fois
local out = {}
local installed = {}

for _, src in ipairs(root:GetChildren()) do
	if src:IsA("Model") then
		local model = Instance.new("Model")
		model.Name = src.Name
		for _, part in ipairs(src:GetDescendants()) do
			if part:IsA("BasePart") then
				local hex = part.Name:match("_(%x%x%x%x%x%x)_%d+$")
				if hex then
					hex = hex:upper()
					part.Color = Color3.fromHex(hex)
					part.Material = (METAL[hex] and Enum.Material.Metal) or Enum.Material.SmoothPlastic
					if GOLD[hex] then
						part.Material = Enum.Material.Metal
						part.Reflectance = 0.15
					end
				end
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Parent = model
			end
		end
		-- pied au sol, centré en (0, 0, 0)
		local cf, size = model:GetBoundingBox()
		local base = Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
		for _, part in ipairs(model:GetChildren()) do
			part.Position -= base
		end
		model.WorldPivot = CFrame.new()
		local old = Props:FindFirstChild(model.Name)
		if old then
			model:SetAttribute("AssetIdV1", old:GetAttribute("AssetId"))
			old:Destroy()
		end
		model:SetAttribute("AssetId", ASSET)
		model.Parent = Props
		installed[model.Name] = model
		local s = model:GetExtentsSize()
		table.insert(out, ("%s : %d pièces, %.1f x %.1f x %.1f"):format(model.Name, #model:GetChildren(), s.X, s.Y, s.Z))
	end
end
container:Destroy()

-- remplacement des copies posées dans le décor
local landscape = workspace:FindFirstChild("ThrowARelicWorld") and workspace.ThrowARelicWorld:FindFirstChild("Landscape")
local replaced = 0
if landscape then
	for _, folderName in ipairs({ "Props", "Village" }) do
		local folder = landscape:FindFirstChild(folderName)
		if folder then
			for i, old in ipairs(folder:GetChildren()) do
				local template = old:IsA("Model") and installed[old.Name]
				if template then
					local new = template:Clone()
					local scale = old:GetScale()
					if math.abs(scale - 1) > 1e-3 then
						new:ScaleTo(scale)
					end
					new:PivotTo(old:GetPivot())
					new.Parent = folder
					old:Destroy()
					replaced += 1
				end
				if i % 50 == 0 then
					task.wait()
				end
			end
		end
	end
end
table.insert(out, ("copies remplacées dans le décor : %d"):format(replaced))
return table.concat(out, "\n")

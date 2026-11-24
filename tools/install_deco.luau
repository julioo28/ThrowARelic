-- Installe les petites décorations (asset TAM_Deco, généré par tools/voxel_deco.py) dans
-- ReplicatedStorage/Props/<Nom> : FlowerRed/Yellow/Purple/White/Orange, Pebbles, PebblesRed,
-- EdgeStone, GrassDry, GrassGreen, Agave, HayBale, Bones. À exécuter en Edit (MCP execute_luau).
-- Pivot = centre du pied, échelle 1. Pièces sans collision ni ombre (léger sur mobile).
local ASSET = 95176090957658

local Props = game:GetService("ReplicatedStorage"):WaitForChild("Props")
local container = game:GetService("InsertService"):LoadAsset(ASSET)
local root = container:FindFirstChild("FlowerRed", true).Parent
local out = {}
for _, src in ipairs(root:GetChildren()) do
	if src:IsA("Model") then
		local model = Instance.new("Model")
		model.Name = src.Name
		for _, part in ipairs(src:GetDescendants()) do
			if part:IsA("BasePart") then
				local hex = part.Name:match("_(%x%x%x%x%x%x)_%d+$")
				if hex then
					part.Color = Color3.fromHex(hex)
				end
				part.Material = Enum.Material.SmoothPlastic
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Parent = model
			end
		end
		local cf, size = model:GetBoundingBox()
		local base = Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
		for _, part in ipairs(model:GetChildren()) do
			part.Position -= base
		end
		model.WorldPivot = CFrame.new()
		model:SetAttribute("AssetId", ASSET)
		local old = Props:FindFirstChild(model.Name)
		if old then
			old:Destroy()
		end
		model.Parent = Props
		local s = model:GetExtentsSize()
		table.insert(out, ("%s : %d pièces, %.1f x %.1f x %.1f"):format(model.Name, #model:GetChildren(), s.X, s.Y, s.Z))
	end
end
container:Destroy()
return table.concat(out, "\n")

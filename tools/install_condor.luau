-- Installe l'aigle voxel (asset TAM_Condor_v2, généré par tools/voxel_eagle.py) dans
-- ReplicatedStorage/Props/Condor. À exécuter en Edit (MCP execute_luau).
-- Les pièces des ailes gardent l'attribut Wing = "L" / "R" ; le modèle porte les épaules
-- (ShoulderL / ShoulderR, en studs AVANT mise à l'échelle) : AmbienceController fait battre
-- chaque aile autour de son épaule (multiplier par model:GetScale()).
-- Devant = +Z (bec), dessus = +Y.
local ASSET = 105667266627487
local BASE_WIDTH = 15 -- envergure en studs (AmbienceController applique ensuite ScaleTo(1.6))

local Props = game:GetService("ReplicatedStorage"):WaitForChild("Props")
local container = game:GetService("InsertService"):LoadAsset(ASSET)
local src = container:FindFirstChild("Condor", true)

local model = Instance.new("Model")
model.Name = "Condor"
local biggest, vol = nil, -1
for _, part in ipairs(src:GetChildren()) do
	if part:IsA("BasePart") then
		local hex = part.Name:match("_(%x%x%x%x%x%x)_%d+$")
		part.Color = Color3.fromHex(hex)
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = true
		if part.Name:find("^CondorWingL") then
			part:SetAttribute("Wing", "L")
		elseif part.Name:find("^CondorWingR") then
			part:SetAttribute("Wing", "R")
		else
			local v = part.Size.X * part.Size.Y * part.Size.Z
			if v > vol then
				biggest, vol = part, v
			end
		end
		part.Parent = model
	end
end
-- pivot = origine Blender (centre du corps)
model.PrimaryPart = biggest
biggest.PivotOffset = biggest.CFrame:ToObjectSpace(CFrame.new())
-- épaules (Blender (±4, 2, 1) -> Roblox : x inversé, y Blender = z Roblox, z Blender = y Roblox)
local width = model:GetExtentsSize().X
model:SetAttribute("ShoulderL", Vector3.new(4, 1, 2))
model:SetAttribute("ShoulderR", Vector3.new(-4, 1, 2))
model:SetAttribute("AssetId", ASSET)
model:ScaleTo(BASE_WIDTH / width)

local old = Props:FindFirstChild("Condor")
if old then
	old:Destroy()
end
model.Parent = Props
container:Destroy()
return ("Condor installé : %d pièces, taille %s, échelle %.3f"):format(#model:GetChildren(), tostring(model:GetExtentsSize()), model:GetScale())

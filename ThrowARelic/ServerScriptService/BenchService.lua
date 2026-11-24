--[[
	BenchService (ModuleScript)
	Emplacement : ServerScriptService/BenchService

	Banc de développé couché devant chaque musée (construit par WorldBuilder :
	Museum<i>/Bench/ Frame, Barbell/Plates, LiePoint, StandPoint).

	- Invite « S'entraîner » sur le banc : seul le propriétaire du musée peut s'y allonger.
	- Allongé : le serveur ancre le personnage sur le coussin. Chaque répétition
	  (remote Train) est limitée en cadence, donne Config.GetRepGain(puissance)
	  et incrémente l'attribut « Reps » du banc : tous les clients animent alors
	  les bras et la barre (affichage local, voir ClientController).
	- Les disques de la barre suivent la puissance du propriétaire (Config.Bench.Plates).
	- On se relève avec le remote BenchLeave (bouton / saut), à la mort ou au départ.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local BenchService = {}

type Deps = {
	museums: Folder,
	ownerOf: (plotIndex: number) -> Player?,
	plotOf: (player: Player) -> number?,
	getPower: (player: Player) -> number?,
	addPower: (player: Player, amount: number) -> (),
	canTrain: (player: Player) -> boolean,
}

local deps: Deps
local lifting: { [Player]: { bench: Model, lastRep: number } } = {}

local function benchOf(plotIndex: number?): Model?
	local plot = plotIndex and deps.museums:FindFirstChild("Museum" .. plotIndex)
	return plot and plot:FindFirstChild("Bench") :: Model?
end

---------------------------------------------------------------------------
-- Disques
---------------------------------------------------------------------------
local plateWidths: { [string]: number } = {}
local function plateWidth(template: Model): number
	local width = plateWidths[template.Name]
	if not width then
		-- le moyeu dépasse de 0,5 de chaque côté : il chevauche le disque voisin
		width = math.max(0.5, template:GetExtentsSize().Z - 1)
		plateWidths[template.Name] = width
	end
	return width
end

function BenchService.SetPlates(plotIndex: number, power: number)
	local bench = benchOf(plotIndex)
	local bar = bench and bench:FindFirstChild("Barbell")
	local folder = bar and bar:FindFirstChild("Plates")
	local props = ReplicatedStorage:FindFirstChild("Props")
	if not (bench and folder and props) then
		return
	end
	local tier = Config.GetPlateTier(power)
	if bench:GetAttribute("PlateTier") == tier then
		return
	end
	bench:SetAttribute("PlateTier", tier)
	folder:ClearAllChildren()
	-- toujours posés par rapport à la position de repos (les clients recalent les
	-- nouveaux disques si leur barre est en plein mouvement)
	local barRest: CFrame = bench:GetAttribute("BarRest") or bar:GetPivot()
	for _, side in ipairs({ -1, 1 }) do
		local offset = 3.5 -- face extérieure de la butée
		for _, name in ipairs(Config.Bench.Plates[tier].plates) do
			local template = props:FindFirstChild(name)
			if template then
				local width = plateWidth(template)
				local plate = template:Clone()
				plate:PivotTo(barRest * CFrame.new(0, 0, side * (offset + width / 2)))
				for _, part in ipairs(plate:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
						part.CanTouch = false
					end
				end
				plate.Parent = folder
				offset += width + 0.05
			end
		end
	end
end

---------------------------------------------------------------------------
-- S'allonger / se relever
---------------------------------------------------------------------------
local function characterParts(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and humanoid.Health > 0 and root then
		return humanoid, root
	end
	return nil, nil
end

function BenchService.Leave(player: Player)
	local state = lifting[player]
	if not state then
		return
	end
	lifting[player] = nil
	local bench = state.bench
	bench:SetAttribute("Lifter", nil)
	player:SetAttribute("OnBench", nil)
	local lie = bench:FindFirstChild("LiePoint")
	local prompt = lie and lie:FindFirstChild("TrainPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = true
	end
	local humanoid, root = characterParts(player)
	if root then
		local stand = bench:FindFirstChild("StandPoint") :: BasePart?
		root.Anchored = false
		if stand then
			root.CFrame = stand.CFrame
		end
	end
	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function mount(player: Player, plotIndex: number)
	if lifting[player] then
		return
	end
	if deps.ownerOf(plotIndex) ~= player then
		return -- pas ton banc
	end
	if not deps.canTrain(player) then
		return
	end
	local bench = benchOf(plotIndex)
	local lie = bench and bench:FindFirstChild("LiePoint") :: BasePart?
	local humanoid, root = characterParts(player)
	if not (bench and lie and humanoid and root) or bench:GetAttribute("Lifter") then
		return
	end
	lifting[player] = { bench = bench, lastRep = 0 }
	humanoid.AutoRotate = false
	humanoid.Sit = false
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = lie.CFrame
	bench:SetAttribute("Lifter", player.UserId)
	player:SetAttribute("OnBench", true)
	local prompt = lie:FindFirstChild("TrainPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = false
	end
end

-- Une répétition (remote Train). Renvoie le gain, ou nil si refusée.
function BenchService.Rep(player: Player): number?
	local state = lifting[player]
	if not state then
		return nil
	end
	local now = os.clock()
	if now - state.lastRep < Config.Bench.RepCooldown - Config.Player.TrainTolerance then
		return nil
	end
	state.lastRep = now
	local gain = Config.GetRepGain(deps.getPower(player) or 0)
	deps.addPower(player, gain)
	state.bench:SetAttribute("Reps", (state.bench:GetAttribute("Reps") or 0) + 1)
	return gain
end

function BenchService.IsLifting(player: Player): boolean
	return lifting[player] ~= nil
end

---------------------------------------------------------------------------
-- Mise en place
---------------------------------------------------------------------------
local function setupPrompt(plotIndex: number)
	local bench = benchOf(plotIndex)
	local lie = bench and bench:FindFirstChild("LiePoint")
	if not lie or lie:FindFirstChild("TrainPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TrainPrompt"
	prompt.ActionText = "S'entraîner"
	prompt.ObjectText = "Développé couché"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Bench.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = lie
	prompt.Triggered:Connect(function(player)
		mount(player, plotIndex)
	end)
end

function BenchService.Init(dependencies: Deps)
	deps = dependencies
	local index = 1
	while deps.museums:FindFirstChild("Museum" .. index) do
		setupPrompt(index)
		BenchService.SetPlates(index, Config.Player.StartingPower)
		index += 1
	end

	local leaveEvent = ReplicatedStorage.Remotes:FindFirstChild("BenchLeave") or Instance.new("RemoteEvent")
	leaveEvent.Name = "BenchLeave"
	leaveEvent.Parent = ReplicatedStorage.Remotes
	leaveEvent.OnServerEvent:Connect(BenchService.Leave)

	local function watchCharacter(player: Player)
		player.CharacterRemoving:Connect(function()
			BenchService.Leave(player)
		end)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid.Died:Connect(function()
					BenchService.Leave(player)
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		watchCharacter(player)
	end
	Players.PlayerRemoving:Connect(BenchService.Leave)
end

-- Musée libéré : on remet la barre de départ
function BenchService.ResetPlot(plotIndex: number)
	local bench = benchOf(plotIndex)
	if bench then
		local lifter = bench:GetAttribute("Lifter")
		for player, state in pairs(lifting) do
			if state.bench == bench or player.UserId == lifter then
				BenchService.Leave(player)
			end
		end
	end
	BenchService.SetPlates(plotIndex, Config.Player.StartingPower)
end

return BenchService

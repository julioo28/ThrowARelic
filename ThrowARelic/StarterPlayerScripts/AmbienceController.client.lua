--[[
	AmbienceController (LocalScript)
	Emplacement : StarterPlayer/StarterPlayerScripts/AmbienceController

	Vie du décor « Grand Canyon », 100 % local (aucun impact serveur) :
	  - condors qui planent en cercles au-dessus du canyon
	  - virevoltants (tumbleweeds) qui traversent le plateau de temps en temps
	  - tourbillons de poussière (dust devils) sur le plateau
	Utilise les props voxel de ReplicatedStorage/Props (Condor, Tumbleweed).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local props = ReplicatedStorage:WaitForChild("Props", 30)
if not props then
	return
end

local RIM = Config.World.RimY
local rng = Random.new()

local ambience = Instance.new("Folder")
ambience.Name = "Ambience"
ambience.Parent = workspace

---------------------------------------------------------------------------
-- Condors : cercles lents, légère inclinaison dans le virage, battements rares
---------------------------------------------------------------------------
local condors = {}
local condorTemplate = props:FindFirstChild("Condor")
if condorTemplate then
	local circles = {
		{ center = Vector3.new(-260, RIM + 70, -120), radius = 90, speed = 0.12, phase = 0 },
		{ center = Vector3.new(-420, RIM + 40, 160), radius = 130, speed = -0.09, phase = 2 },
		{ center = Vector3.new(-120, RIM + 110, 60), radius = 70, speed = 0.15, phase = 4 },
		{ center = Vector3.new(-45, RIM + 38, -30), radius = 45, speed = -0.13, phase = 1 }, -- au-dessus de la gorge, devant le ponton
	}
	for _, circle in ipairs(circles) do
		local model = condorTemplate:Clone()
		model:ScaleTo(1.6)
		model.Parent = ambience
		table.insert(condors, { model = model, circle = circle })
	end
end

---------------------------------------------------------------------------
-- Virevoltants : traversent le plateau en roulant et en rebondissant
---------------------------------------------------------------------------
local weedTemplate = props:FindFirstChild("Tumbleweed")
local weeds = {}
local nextWeed = os.clock() + 4

local function spawnWeed()
	if not weedTemplate or #weeds >= 3 then
		return
	end
	local model = weedTemplate:Clone()
	model:ScaleTo(rng:NextNumber(1, 1.6))
	-- pivot au centre de la boule pour qu'elle roule sur elle-même
	local center, size = model:GetBoundingBox()
	model.WorldPivot = center
	local radius = size.Y / 2
	local z = rng:NextNumber(-300, 300)
	local fromX = rng:NextNumber(-60, 40)
	model.Parent = ambience
	table.insert(weeds, {
		model = model,
		start = Vector3.new(fromX, RIM + radius, z),
		velocity = Vector3.new(rng:NextNumber(14, 22), 0, rng:NextNumber(-6, 6)),
		born = os.clock(),
		life = rng:NextNumber(14, 22),
		spin = 0,
	})
end

---------------------------------------------------------------------------
-- Tourbillons de poussière : colonne de particules qui dérive puis s'éteint
---------------------------------------------------------------------------
local nextDevil = os.clock() + 8

local function spawnDustDevil()
	local base = Vector3.new(rng:NextNumber(160, 420), RIM + 1, rng:NextNumber(-350, 350))
	local holder = Instance.new("Part")
	holder.Name = "DustDevil"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(4, 1, 4)
	holder.Position = base
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = "rbxasset://textures/particles/smoke_main.dds"
	swirl.Color = ColorSequence.new(Color3.fromRGB(214, 170, 125))
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	swirl.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.6), NumberSequenceKeypoint.new(1, 1),
	})
	swirl.Lifetime = NumberRange.new(2.5, 3.5)
	swirl.Rate = 30
	swirl.Speed = NumberRange.new(8, 14)
	swirl.EmissionDirection = Enum.NormalId.Top
	swirl.SpreadAngle = Vector2.new(12, 12)
	swirl.RotSpeed = NumberRange.new(-200, 200)
	swirl.Rotation = NumberRange.new(0, 360)
	swirl.Acceleration = Vector3.new(0, 2, 0)
	swirl.Parent = holder
	holder.Parent = ambience
	local drift = Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
	local born = os.clock()
	local life = rng:NextNumber(10, 16)
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local age = os.clock() - born
		holder.Position += drift * dt
		if age > life - 2 then
			swirl.Rate = 0
		end
		if age > life then
			conn:Disconnect()
			holder:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- Chevalement : la roue et le tambour du treuil tournent quand le câble défile
-- (vitesse lue sur l'aimant le plus rapide : le tien ou celui d'un autre joueur)
---------------------------------------------------------------------------
local world = workspace:WaitForChild("ThrowARelicWorld")
local headframe = world:FindFirstChild("Headframe") -- (retiré : plus de chevalement, code inactif)
local sheave = headframe and headframe:FindFirstChild("Sheave")
local winch = headframe and headframe:FindFirstChild("Winch")
local drum = winch and winch:FindFirstChild("Drum")
local sheaveBase = sheave and sheave:GetPivot()
local drumBase = drum and drum.CFrame
local SHEAVE_RADIUS, DRUM_RADIUS = 4, 1.2
local sheaveAngle, drumAngle = 0, 0
local lastHeights: { [Instance]: number } = {}

local function magnetBodies()
	local bodies = {}
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "Magnet" and child:IsA("Model") and child.PrimaryPart then
			table.insert(bodies, child.PrimaryPart)
		end
	end
	local others = workspace:FindFirstChild("OtherThrows")
	if others then
		for _, d in ipairs(others:GetDescendants()) do
			if d.Name == "Body" and d:IsA("BasePart") and d.Parent and d.Parent.Name == "Magnet" then
				table.insert(bodies, d)
			end
		end
	end
	return bodies
end

local function spinMachinery(dt: number)
	if not (sheave or drum) or dt <= 0 then
		return
	end
	local speed = 0 -- studs/s de câble (signé : > 0 = descente)
	local seen = {}
	for _, body in ipairs(magnetBodies()) do
		seen[body] = true
		local y = body.Position.Y
		local last = lastHeights[body]
		if last then
			local v = (last - y) / dt
			if math.abs(v) > math.abs(speed) then
				speed = v
			end
		end
		lastHeights[body] = y
	end
	for body in pairs(lastHeights) do
		if not seen[body] then
			lastHeights[body] = nil
		end
	end
	speed = math.clamp(speed, -400, 400)
	if sheave then
		sheaveAngle += speed * dt / SHEAVE_RADIUS
		sheave:PivotTo(sheaveBase * CFrame.Angles(sheaveAngle, 0, 0))
	end
	if drum then
		drumAngle += speed * dt / DRUM_RADIUS * 0.25
		drum.CFrame = drumBase * CFrame.Angles(drumAngle, 0, 0)
	end
end

---------------------------------------------------------------------------
-- Boucle d'animation
---------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	spinMachinery(dt)
	for _, condor in ipairs(condors) do
		local c = condor.circle
		local angle = now * c.speed + c.phase
		local pos = c.center + Vector3.new(math.cos(angle) * c.radius, math.sin(now * 0.3 + c.phase) * 4, math.sin(angle) * c.radius)
		-- direction tangente au cercle ; inclinaison vers l'intérieur du virage
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * math.sign(c.speed)
		local bank = math.rad(18) * math.sign(c.speed)
		local flap = math.sin(now * 6 + c.phase) * math.rad(4) * (math.sin(now * 0.4 + c.phase) > 0.85 and 1 or 0)
		condor.model:PivotTo(CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(flap, 0, bank))
	end

	if now >= nextWeed then
		nextWeed = now + rng:NextNumber(6, 12)
		spawnWeed()
	end
	for index = #weeds, 1, -1 do
		local weed = weeds[index]
		local age = now - weed.born
		if age > weed.life then
			weed.model:Destroy()
			table.remove(weeds, index)
		else
			local pos = weed.start + weed.velocity * age
			local hop = math.abs(math.sin(age * 3.1)) * 1.6
			weed.spin += dt * weed.velocity.Magnitude * 0.6
			local dir = weed.velocity.Unit
			weed.model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, hop, 0), pos + Vector3.new(0, hop, 0) + dir) * CFrame.Angles(-weed.spin, 0, 0))
		end
	end

	if now >= nextDevil then
		nextDevil = now + rng:NextNumber(14, 26)
		spawnDustDevil()
	end
end)

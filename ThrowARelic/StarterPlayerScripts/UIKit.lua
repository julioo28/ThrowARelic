--[[
	UIKit (ModuleScript)
	Emplacement : StarterPlayer/StarterPlayerScripts/UIKit  (requis par ClientController)

	Boîte à outils d'interface « simulateur Roblox » façon western :
	  - texte cartoon (Luckiest Guy, gros contour noir)
	  - boutons en dégradé épais : grossissent au survol, s'enfoncent au clic,
	    reflet qui balaie, sons
	  - VFX d'interface : rayons qui tournent, étincelles qui scintillent,
	    pièces qui jaillissent, confettis, texte qui s'envole, apparition en rebond
	  - vitrines 3D (ViewportFrame) avec un modèle qui tourne
	Tout est local au joueur et n'a aucun effet sur le jeu.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local K = {}

K.Ink = Color3.fromRGB(26, 14, 5)
K.White = Color3.new(1, 1, 1)
K.Font = Enum.Font.LuckiestGuy
K.BodyFont = Enum.Font.FredokaOne

-- Palette : { haut, bas } des dégradés
K.Colors = {
	Green = { Color3.fromRGB(126, 227, 86), Color3.fromRGB(46, 158, 31) },
	Teal = { Color3.fromRGB(79, 230, 208), Color3.fromRGB(19, 142, 126) },
	Orange = { Color3.fromRGB(255, 192, 74), Color3.fromRGB(226, 85, 47) },
	Red = { Color3.fromRGB(255, 122, 92), Color3.fromRGB(201, 36, 36) },
	Purple = { Color3.fromRGB(208, 140, 255), Color3.fromRGB(123, 59, 214) },
	Blue = { Color3.fromRGB(91, 192, 255), Color3.fromRGB(42, 111, 216) },
	Gold = { Color3.fromRGB(255, 226, 122), Color3.fromRGB(229, 162, 28) },
	Wood = { Color3.fromRGB(154, 106, 68), Color3.fromRGB(90, 56, 32) },
	Grey = { Color3.fromRGB(180, 180, 188), Color3.fromRGB(122, 122, 132) },
	Cream = { Color3.fromRGB(255, 246, 222), Color3.fromRGB(243, 217, 164) },
	Dark = { Color3.fromRGB(58, 36, 20), Color3.fromRGB(26, 14, 5) },
}

---------------------------------------------------------------------------
-- Construction de base
---------------------------------------------------------------------------
function K.new(className: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function K.corner(radius: number?)
	return K.new("UICorner", { CornerRadius = radius and UDim.new(0, radius) or UDim.new(0, 16) })
end

function K.round()
	return K.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function K.stroke(thickness: number?, color: Color3?)
	return K.new("UIStroke", {
		Thickness = thickness or 4, Color = color or K.Ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function K.gradient(top: Color3, bottom: Color3, rotation: number?)
	return K.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 })
end

-- Texte cartoon : lettres pleines + gros contour noir (UIStroke contextuel)
function K.text(props: { [string]: any })
	local maxSize = props.MaxTextSize or 40
	local outline = props.Outline or math.clamp(math.floor(maxSize / 9), 2, 6)
	props.MaxTextSize = nil
	props.Outline = nil
	local label = K.new("TextLabel", {
		BackgroundTransparency = 1, Font = props.Font or K.Font, TextScaled = true,
		TextColor3 = props.TextColor3 or K.White, Text = props.Text or "",
	})
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	K.new("UITextSizeConstraint", { MaxTextSize = maxSize, Parent = label })
	K.new("UIStroke", {
		Thickness = outline, Color = K.Ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round, Parent = label,
	})
	label.Parent = props.Parent
	return label
end

---------------------------------------------------------------------------
-- Sons d'interface (Config.Sounds : UIHover, UIClick, UIOpen, UIBuy, UIError, UICoin, UIPop, UIWhoosh, UIDing)
---------------------------------------------------------------------------
function K.sound(key: string, volume: number?, pitch: number?)
	local def = Config.Sounds[key]
	if not def or def.id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = volume or def.volume
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- Animations
---------------------------------------------------------------------------
function K.tween(inst: Instance, duration: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function K.scaleOf(inst: GuiObject): UIScale
	local scale = inst:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = K.new("UIScale", { Parent = inst })
	end
	return scale
end

-- Apparition en rebond (fenêtres, cartes, titres)
function K.pop(inst: GuiObject, from: number?, duration: number?)
	local scale = K.scaleOf(inst)
	scale.Scale = from or 0.4
	K.tween(scale, duration or 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Petit coup (achat, gain) : grossit puis revient
function K.punch(inst: GuiObject, amount: number?)
	local scale = K.scaleOf(inst)
	scale.Scale = 1 + (amount or 0.18)
	K.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Tremblement horizontal (refus, erreur)
function K.shake(inst: GuiObject)
	local base = inst.Position
	task.spawn(function()
		for i = 1, 6 do
			inst.Position = base + UDim2.fromOffset((i % 2 == 0 and 1 or -1) * (8 - i), 0)
			task.wait(0.03)
		end
		inst.Position = base
	end)
end

---------------------------------------------------------------------------
-- Boucle d'animation partagée (rayons, étincelles, vitrines 3D, reflets)
---------------------------------------------------------------------------
local spinners = {} -- { inst, speed }
local twinkles = {} -- { frame, phase, speed }
local showcases = {} -- vitrines 3D
local shines = {} -- reflets qui balaient
local function visible(inst: GuiObject): boolean
	local gui = inst:FindFirstAncestorOfClass("ScreenGui")
	if not (gui and gui.Enabled) then
		return false
	end
	local node: Instance? = inst
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for i = #spinners, 1, -1 do
		local s = spinners[i]
		if not s.inst.Parent then
			table.remove(spinners, i)
		elseif visible(s.inst) then
			s.inst.Rotation = (s.inst.Rotation + s.speed * dt) % 360
		end
	end
	for i = #twinkles, 1, -1 do
		local t = twinkles[i]
		if not t.frame.Parent then
			table.remove(twinkles, i)
		elseif visible(t.frame) then
			local k = (math.sin(now * t.speed + t.phase) + 1) / 2
			t.scale.Scale = 0.35 + 0.85 * k
			t.frame.Rotation = 45 + math.sin(now * t.speed * 0.5 + t.phase) * 20
		end
	end
	for i = #showcases, 1, -1 do
		local s = showcases[i]
		if not s.viewport.Parent then
			table.remove(showcases, i)
		elseif visible(s.viewport) then
			s.boost = math.max(0, s.boost - dt * 1.5)
			s.angle += dt * (s.speed * (s.hover and 3 or 1) + s.boost * 10)
			local hop = math.sin((1 - s.boost) * math.pi) * s.boost * s.hopHeight
			local bob = math.sin(now * 2 + s.phase) * s.bob
			s.model:PivotTo(CFrame.new(0, hop + bob, 0) * CFrame.Angles(s.tilt, s.angle, 0))
		end
	end
	for i = #shines, 1, -1 do
		local s = shines[i]
		if not s.bar.Parent then
			table.remove(shines, i)
		elseif s.enabled and visible(s.bar) then
			local t = ((now + s.phase) % s.period) / 0.6
			s.bar.Position = UDim2.new(-0.5 + math.min(t, 1) * 2, 0, 0.5, 0)
			s.bar.Visible = t <= 1
		else
			s.bar.Visible = false
		end
	end
end)

-- Rayons de soleil qui tournent derrière un objet (Frame carré centré)
function K.rays(parent: Instance, color: Color3?, count: number?, speed: number?, transparency: number?)
	local holder = K.new("Frame", {
		Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = parent,
	}, { K.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	local n = count or 14
	for i = 1, n do
		-- chaque rayon part du centre vers le haut ; son pivot plein cadre le fait tourner autour du centre
		local pivot = K.new("Frame", {
			Name = "RayPivot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = (i - 1) * 360 / n, Parent = holder,
		})
		local ray = K.new("Frame", {
			Name = "Ray", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.13, 0.5), BackgroundColor3 = color or K.White, BorderSizePixel = 0, Parent = pivot,
		})
		K.new("UIGradient", {
			Rotation = 90, Parent = ray, -- 0 = bout du rayon (haut), 1 = centre
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, transparency or 0.55), NumberSequenceKeypoint.new(1, 0.9),
			}),
		})
	end
	table.insert(spinners, { inst = holder, speed = speed or 18 })
	return holder
end

-- Étincelles (losanges) qui scintillent à des positions données (en échelle 0-1)
function K.sparkles(parent: Instance, spots: { { number } }, color: Color3?, zIndex: number?)
	for i, spot in ipairs(spots) do
		local size = spot[3] or 14
		local frame = K.new("Frame", {
			Name = "Sparkle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spot[1], spot[2]),
			Size = UDim2.fromOffset(size, size), BackgroundColor3 = color or K.White, BorderSizePixel = 0,
			Rotation = 45, ZIndex = zIndex or 8, Parent = parent,
		})
		local scale = K.new("UIScale", { Parent = frame })
		table.insert(twinkles, { frame = frame, scale = scale, phase = i * 1.7, speed = 3 + (i % 3) })
	end
end

-- Reflet qui balaie un bouton / une carte de temps en temps
function K.shine(parent: GuiObject, period: number?)
	parent.ClipsDescendants = true
	local bar = K.new("Frame", {
		Name = "Shine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.5, 0.5),
		Size = UDim2.new(0.16, 0, 1, 0), Rotation = 0, BackgroundColor3 = K.White, -- (un élément pivoté ne serait pas rogné)
		BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = (parent.ZIndex or 1) + 3, Visible = false, Parent = parent,
	})
	local entry = { bar = bar, period = period or 3, phase = math.random() * 3, enabled = true }
	table.insert(shines, entry)
	return entry
end

-- Vitrine 3D : un modèle qui tourne dans un ViewportFrame
function K.showcase(viewport: ViewportFrame, template: Model, opts)
	opts = opts or {}
	local model = template:Clone()
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local _, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = math.max(size.X, size.Y, size.Z) * (opts.zoom or 1.9)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, distance * (opts.height or 0.35), distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Ambient = opts.ambient or Color3.fromRGB(190, 170, 150)
	viewport.LightColor = Color3.fromRGB(255, 244, 228)
	viewport.LightDirection = Vector3.new(-1, -1.5, -0.8)
	local entry = {
		viewport = viewport, model = model, angle = math.random() * math.pi * 2, speed = opts.speed or 0.6,
		boost = 0, hover = false, tilt = opts.tilt or 0, bob = opts.bob or 0, hopHeight = opts.hop or 2,
		phase = math.random() * 6,
	}
	table.insert(showcases, entry)
	return entry
end

---------------------------------------------------------------------------
-- Boutons
---------------------------------------------------------------------------
-- Rend n'importe quel GuiButton « vivant » : survol = grossit + son, clic = s'enfonce + son
function K.animateButton(button: GuiButton, opts)
	opts = opts or {}
	local scale = K.scaleOf(button)
	local hovering = false
	button.AutoButtonColor = false
	button.MouseEnter:Connect(function()
		hovering = true
		K.tween(scale, 0.15, { Scale = opts.hoverScale or 1.06 }, Enum.EasingStyle.Back)
		K.sound("UIHover", nil, 0.95 + math.random() * 0.1)
		if opts.onHover then
			opts.onHover(true)
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		K.tween(scale, 0.15, { Scale = 1 })
		if opts.onHover then
			opts.onHover(false)
		end
	end)
	button.MouseButton1Down:Connect(function()
		K.tween(scale, 0.08, { Scale = 0.9 })
	end)
	button.MouseButton1Up:Connect(function()
		K.tween(scale, 0.25, { Scale = hovering and (opts.hoverScale or 1.06) or 1 }, Enum.EasingStyle.Back)
	end)
	if opts.clickSound ~= false then
		button.Activated:Connect(function()
			K.sound(opts.clickSound or "UIClick")
		end)
	end
end

-- Gros bouton dégradé avec contour, reflet, ombre portée et libellé cartoon
function K.button(props)
	-- Le bouton est un conteneur transparent ; dedans : l'ombre, puis la face colorée
	-- par-dessus (un enfant est toujours dessiné au-dessus de son parent).
	local colors = props.Colors or K.Colors.Green
	local z = props.ZIndex or 1
	local radius = props.Radius or 18
	local button = K.new("TextButton", {
		Name = props.Name or "Button", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(200, 64), Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(), ZIndex = z, LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	K.new("Frame", { -- ombre portée
		Name = "Shadow", Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, props.Depth or 6),
		BackgroundColor3 = K.Ink, BackgroundTransparency = 0.15, ZIndex = z, Parent = button,
	}, { K.corner(radius) })
	local face = K.new("Frame", {
		Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.White, ZIndex = z + 1, Parent = button,
	}, { K.corner(radius), K.stroke(props.Stroke or 4), K.gradient(colors[1], colors[2]) })
	K.new("Frame", { -- reflet du haut
		Name = "Gloss", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.new(1, -8, 0.42, 0),
		BackgroundColor3 = K.White, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = z + 2, Parent = face,
	}, { K.corner(math.max(4, radius - 4)), K.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.2, 1) }) })
	if props.Shine ~= false then -- reflet qui balaie, dans un calque rogné
		local clip = K.new("Frame", {
			Name = "ShineClip", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true,
			ZIndex = z + 2, Parent = face,
		}, { K.corner(radius) })
		K.shine(clip, props.ShinePeriod or 3.2)
	end
	local label
	if props.Text then
		label = K.text({
			Name = "Label", Text = props.Text, AnchorPoint = Vector2.new(0.5, 0.5), Position = props.TextPosition or UDim2.fromScale(0.5, 0.5),
			Size = props.TextSize or UDim2.fromScale(0.86, 0.62), MaxTextSize = props.MaxTextSize or 30, ZIndex = z + 4, Parent = button,
		})
	end
	K.animateButton(button, props.Animate)
	return button, label
end

-- Recolore un bouton créé par K.button
function K.recolor(button: GuiObject, colors)
	local face = button:FindFirstChild("Face")
	local gradient = (face or button):FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
end

---------------------------------------------------------------------------
-- VFX ponctuels
---------------------------------------------------------------------------
-- Pièces qui jaillissent d'un point (en pixels) puis retombent en tournant
function K.coinBurst(gui: ScreenGui, at: Vector2, count: number?)
	for i = 1, count or 12 do
		local coin = K.new("Frame", {
			Name = "Coin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(at.X, at.Y),
			Size = UDim2.fromOffset(22, 22), BackgroundColor3 = K.White, ZIndex = 60, Parent = gui,
		}, { K.round(), K.stroke(2), K.gradient(K.Colors.Gold[1], K.Colors.Gold[2]) })
		local angle = math.rad(math.random(200, 340))
		local power = math.random(90, 190)
		local dx, dy = math.cos(angle) * power, math.sin(angle) * power
		local start = os.clock()
		local life = 0.9 + math.random() * 0.3
		task.spawn(function()
			while os.clock() - start < life do
				local t = os.clock() - start
				coin.Position = UDim2.fromOffset(at.X + dx * t * 1.4, at.Y + dy * t * 1.4 + 420 * t * t)
				coin.Size = UDim2.fromOffset(22 * math.abs(math.cos(t * 9)) + 4, 22)
				coin.BackgroundTransparency = math.max(0, (t - life + 0.25) * 4)
				RunService.RenderStepped:Wait()
			end
			coin:Destroy()
		end)
	end
	K.sound("UICoin")
end

-- Confettis qui tombent sur tout l'écran
function K.confetti(gui: ScreenGui, count: number?, palette: { Color3 }?)
	local colors = palette or { Color3.fromRGB(255, 228, 92), Color3.fromRGB(79, 230, 208), Color3.fromRGB(255, 107, 107),
		Color3.fromRGB(201, 139, 255), Color3.fromRGB(126, 227, 86), K.White }
	for i = 1, count or 50 do
		local piece = K.new("Frame", {
			Name = "Confetti", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(math.random(), 0, -0.05, 0),
			Size = UDim2.fromOffset(math.random(7, 12), math.random(12, 20)), BackgroundColor3 = colors[i % #colors + 1],
			BorderSizePixel = 0, Rotation = math.random(0, 360), ZIndex = 55, Parent = gui,
		}, { K.corner(3) })
		local x0 = piece.Position.X.Scale
		local fall = 1.8 + math.random() * 1.4
		local delay = math.random() * 0.5
		local sway = (math.random() - 0.5) * 0.12
		task.spawn(function()
			task.wait(delay)
			local start = os.clock()
			while os.clock() - start < fall do
				local t = (os.clock() - start) / fall
				piece.Position = UDim2.new(x0 + math.sin(t * 8) * sway, 0, -0.05 + t * 1.1, 0)
				piece.Rotation += 6
				RunService.RenderStepped:Wait()
			end
			piece:Destroy()
		end)
	end
end

-- Texte qui s'envole et s'efface (gain d'argent, puissance...)
function K.floatText(gui: ScreenGui, text: string, color: Color3, at: UDim2, size: number?)
	local label = K.text({
		Name = "FloatText", Text = text, TextColor3 = color, AnchorPoint = Vector2.new(0.5, 0.5), Position = at,
		Size = UDim2.fromOffset(260, size or 40), MaxTextSize = size or 34, ZIndex = 58, Rotation = math.random(-8, 8), Parent = gui,
	})
	K.pop(label, 0.4, 0.3)
	K.tween(label, 1.1, { Position = at - UDim2.fromOffset(0, 70) }, Enum.EasingStyle.Quad)
	task.delay(0.7, function()
		K.tween(label, 0.4, { TextTransparency = 1 })
		local outline = label:FindFirstChildOfClass("UIStroke")
		if outline then
			K.tween(outline, 0.4, { Transparency = 1 })
		end
	end)
	task.delay(1.2, function()
		label:Destroy()
	end)
end

return K

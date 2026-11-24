--[[
	ClientController (LocalScript)
	Emplacement : StarterPlayer/StarterPlayerScripts/ClientController

	AFFICHAGE UNIQUEMENT : interface, jauge, animations, caméra, sons.
	Toute décision (rareté, argent, puissance) vient du serveur.

	Sections :
	  1. Références & constantes d'UI
	  2. Construction de l'interface (mobile : gros boutons)
	  3. Utilitaires (tween, sons, caméra, particules)
	  4. Jauge de timing
	  5. Séquence de lancer : A descente, B attente, C/D remontée
	  6. Nettoyage + révélation + vendre/exposer
	  7. HUD, annonces, panneau debug
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RelicsFolder = ReplicatedStorage:WaitForChild("Relics")
local ChestsFolder = ReplicatedStorage:WaitForChild("Chests")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local world = workspace:WaitForChild("ThrowARelicWorld")
local pulleyPart = world:WaitForChild("Pulley")
local launchPad = world:WaitForChild("LaunchPad")
local cleaningPlatform = world:WaitForChild("CleaningPlatform")
local throwZone = world:WaitForChild("ThrowZone")
local canyonMouth = world:WaitForChild("CanyonMouth")

-- Lancers des autres joueurs (local) : retiré du workspace pendant ta cinématique
local otherThrowsFolder = Instance.new("Folder")
otherThrowsFolder.Name = "OtherThrows"
otherThrowsFolder.Parent = workspace

---------------------------------------------------------------------------
-- 1. Constantes d'interface (style uniquement ; le gameplay est dans Config)
---------------------------------------------------------------------------
local UI = {
	Font = Enum.Font.FredokaOne,
	White = Color3.new(1, 1, 1),
	Dark = Color3.fromRGB(25, 25, 35),
	Panel = Color3.fromRGB(30, 30, 45),
	Orange = Color3.fromRGB(255, 140, 40),
	Blue = Color3.fromRGB(60, 140, 255),
	Green = Color3.fromRGB(70, 190, 90),
	Red = Color3.fromRGB(220, 70, 70),
	Purple = Color3.fromRGB(150, 90, 220),
	Mud = Config.Clean.MudColor,
	Corner = UDim.new(0, 14),
	Margin = 16,
	ToastTime = 2,
	MaxTextSize = 42,
}

local busy = false -- verrou local (miroir du verrou serveur)
local fmt = Config.FormatNumber -- 12 500 -> "12,5 k"

-- Amélioration « Câble » d'un joueur : multiplicateur de vitesse (chute, attente, remontée)
local function cableSpeed(who: Player): number
	return Config.GetSpeedMultiplier(who:GetAttribute("UpgradeCable") or 0)
end

-- Durée de remontée normale (plafonnée : le canyon est très profond), avant ralentis de rareté
local function ascentBaseDuration(distance: number, speed: number): number
	local anim = Config.Anim
	return math.clamp(distance / anim.AscentSpeed, anim.AscentMinDuration, anim.AscentMaxDuration) / speed
end

---------------------------------------------------------------------------
-- 2. Interface
---------------------------------------------------------------------------
local function create(className: string, props: { [string]: any }, children: { Instance }?)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function corner()
	return create("UICorner", { CornerRadius = UI.Corner })
end

local function stroke(thickness: number?)
	return create("UIStroke", { Thickness = thickness or 3, Color = UI.Dark, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function textMax(size: number?)
	return create("UITextSizeConstraint", { MaxTextSize = size or UI.MaxTextSize })
end

local function bigButton(name: string, text: string, color: Color3, parent: Instance)
	return create("TextButton", {
		Name = name, Parent = parent, Text = text, Font = UI.Font, TextScaled = true,
		TextColor3 = UI.White, BackgroundColor3 = color, AutoButtonColor = true,
		Size = UDim2.fromScale(1, 0.3),
	}, { corner(), stroke(), textMax(), create("UIPadding", { PaddingLeft = UDim.new(0.06, 0), PaddingRight = UDim.new(0.06, 0), PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0) }) })
end

local K = require(script.Parent:WaitForChild("UIKit"))
local C = K.Colors

local gui = create("ScreenGui", {
	Name = "ThrowARelicUI", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
})

-- Échelle selon la taille d'écran : tout est dessiné pour 760 px de haut,
-- puis réduit sur téléphone / agrandi sur grand écran (UIScale sur les conteneurs)
local responsiveScales = {}
local function responsive(frame: GuiObject): GuiObject
	table.insert(responsiveScales, create("UIScale", { Name = "Responsive", Parent = frame }))
	return frame
end
local function updateResponsive()
	local height = camera.ViewportSize.Y
	local s = math.clamp(height / 760, 0.5, 1.15)
	for _, scale in ipairs(responsiveScales) do
		scale.Scale = s
	end
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsive)

-- Modèles 3D (Blender) affichés dans l'interface
local shopModels = ReplicatedStorage:WaitForChild("ShopModels", 10)
local function uiModel(name: string): Model?
	return shopModels and shopModels:FindFirstChild(name) :: Model?
end

---------------------------------------------------------------------------
-- HUD : devises en haut à gauche (grosse icône qui déborde + bouton +)
---------------------------------------------------------------------------
local topBar = responsive(create("Frame", {
	Name = "TopBar", Parent = gui, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(320, 150), BackgroundTransparency = 1,
}))
local function currencyPill(name: string, y: number, colors, symbol: string)
	local holder = create("Frame", { Name = name .. "Pill", Parent = topBar, Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(310, 70), BackgroundTransparency = 1 })
	create("Frame", {
		Name = "Bar", Parent = holder, Position = UDim2.fromOffset(36, 10), Size = UDim2.fromOffset(236, 50), BackgroundColor3 = K.White,
	}, { K.round(), K.stroke(4), K.gradient(C.Dark[1], C.Dark[2]) })
	local value = K.text({
		Name = name, Parent = holder, Position = UDim2.fromOffset(80, 13), Size = UDim2.fromOffset(178, 42), MaxTextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "0", ZIndex = 2,
	})
	local icon = create("Frame", {
		Name = "Icon", Parent = holder, Size = UDim2.fromOffset(68, 68), BackgroundColor3 = K.White, ZIndex = 3,
	}, { K.round(), K.stroke(5), K.gradient(colors[1], colors[2]) })
	K.text({ Name = "Symbol", Parent = icon, Size = UDim2.fromScale(1, 1), Text = symbol, MaxTextSize = 38, ZIndex = 4 })
	return holder, value, icon
end
local moneyPill, moneyLabel, moneyIcon = currencyPill("Money", 0, C.Gold, "$")
local _, powerLabel, powerIcon = currencyPill("Power", 78, C.Red, "💪")
local moneyPlus = K.button({
	Name = "Plus", Parent = moneyPill, Position = UDim2.fromOffset(262, 14), Size = UDim2.fromOffset(42, 42), Colors = C.Green,
	Text = "+", Radius = 12, MaxTextSize = 30, Shine = false, Depth = 4, ZIndex = 3,
})

---------------------------------------------------------------------------
-- Boutons d'action : 2 x 2 à gauche (le pouce droit reste libre pour sauter)
---------------------------------------------------------------------------
local actionPanel = responsive(create("Frame", {
	Name = "Actions", Parent = gui, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 40),
	Size = UDim2.fromOffset(240, 256), BackgroundTransparency = 1,
}, { create("UIGridLayout", { CellSize = UDim2.fromOffset(112, 120), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder }) }))

local actionShowcases = {}
local function actionButton(name: string, label: string, colors, modelName: string, order: number)
	local cell = create("Frame", { Name = name .. "Cell", Parent = actionPanel, BackgroundTransparency = 1, LayoutOrder = order })
	local ref = {}
	local button = K.button({
		Name = name, Parent = cell, Size = UDim2.fromOffset(108, 108), Colors = colors, Radius = 26, Stroke = 5, Depth = 7, ZIndex = 2,
		Animate = { onHover = function(on) if ref.show then ref.show.hover = on end end },
	})
	local viewport = create("ViewportFrame", {
		Name = "Icon", Parent = button, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(86, 80), BackgroundTransparency = 1, ZIndex = 5,
	})
	local template = uiModel(modelName)
	if template then
		ref.show = K.showcase(viewport, template, { speed = 0.5, zoom = 1.8, tilt = 0.12 })
		actionShowcases[name] = ref.show
	end
	K.text({
		Name = "Label", Parent = button, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -8, 0, 24), Text = label, MaxTextSize = 19, ZIndex = 6,
	})
	local badge = create("Frame", {
		Name = "Badge", Parent = button, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 12, 0, -12),
		Size = UDim2.fromOffset(34, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = K.White, Visible = false, ZIndex = 7,
	}, { K.round(), K.stroke(3), K.gradient(C.Red[1], C.Red[2]), create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	local badgeText = K.text({ Name = "Text", Parent = badge, Size = UDim2.new(0, 18, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "!", MaxTextSize = 18, ZIndex = 8, TextScaled = false, TextSize = 18 })
	return button, badge, badgeText
end
local bookButton, bookBadge, bookBadgeText = actionButton("Book", "COLLECTION", C.Teal, "Book", 1)
local shopButton, shopBadge = actionButton("Shop", "BOUTIQUE", C.Orange, "Magnet", 2)
local museumButton = actionButton("Museum", "MUSÉE", C.Purple, "Museum", 3)
-- les pastilles « ! » / « NOUVEAU » rebondissent doucement
RunService.RenderStepped:Connect(function()
	local bounce = math.abs(math.sin(os.clock() * 4)) * -5
	for _, badge in ipairs({ shopBadge, bookBadge }) do
		badge.Position = UDim2.new(1, 12, 0, -12 + bounce)
	end
end)

---------------------------------------------------------------------------
-- Fenêtres (boutique, collection) : parchemin, bandeau rayé, titre penché
---------------------------------------------------------------------------
local function makeWindow(name: string, title: string, colors)
	local holder = responsive(create("Frame", {
		Name = name, Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromOffset(940, 560), BackgroundTransparency = 1, Visible = false, ZIndex = 20,
	}))
	local body = create("Frame", { Name = "Body", Parent = holder, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20 })
	local panel = create("Frame", {
		Name = "Panel", Parent = body, Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.White, ZIndex = 20,
	}, { K.corner(30), K.stroke(7), K.gradient(C.Cream[1], C.Cream[2]) })
	-- ombre de la fenêtre
	create("Frame", { Name = "Shadow", Parent = body, Position = UDim2.fromOffset(0, 12), Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.Ink, BackgroundTransparency = 0.35, ZIndex = 19 }, { K.corner(30) })
	-- planches discrètes
	for i = 1, 6 do
		create("Frame", { Name = "Plank", Parent = panel, Position = UDim2.new(0, 10, 0, 100 + i * 70), Size = UDim2.new(1, -20, 0, 2), BackgroundColor3 = Color3.fromRGB(201, 165, 110), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 20 })
	end
	-- bandeau d'en-tête rayé
	local header = create("Frame", {
		Name = "Header", Parent = panel, Size = UDim2.new(1, 0, 0, 88), BackgroundColor3 = K.White, ClipsDescendants = true, ZIndex = 21,
	}, { K.corner(26), K.gradient(colors[1], colors[2]) })
	create("Frame", { Name = "HeaderBottom", Parent = header, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = colors[2], BorderSizePixel = 0, ZIndex = 21 })
	for i = 0, 15 do
		create("Frame", { Name = "Stripe", Parent = header, Position = UDim2.fromOffset(i * 70 - 40, -40), Size = UDim2.fromOffset(26, 180), Rotation = 30, BackgroundColor3 = K.White, BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = 22 })
	end
	create("Frame", { Name = "HeaderLine", Parent = panel, Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = K.Ink, BorderSizePixel = 0, ZIndex = 22 })
	local headerContent = create("Frame", { Name = "HeaderContent", Parent = panel, Size = UDim2.new(1, 0, 0, 88), BackgroundTransparency = 1, ZIndex = 23 })
	-- titre penché qui déborde, avec des rayons derrière
	local titleRays = create("Frame", { Name = "TitleRays", Parent = body, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(150, -6), Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1, ZIndex = 18 })
	K.rays(titleRays, Color3.fromRGB(255, 228, 92), 14, 14, 0.5)
	local titleLabel = K.text({
		Name = "Title", Parent = holder, Position = UDim2.fromOffset(-34, -62), Size = UDim2.fromOffset(440, 86), Text = title,
		MaxTextSize = 70, Outline = 7, Rotation = -6, ZIndex = 30, TextXAlignment = Enum.TextXAlignment.Left,
	})
	-- croix rouge qui chevauche le coin
	local close = K.button({
		Name = "Close", Parent = holder, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(66, 66),
		Colors = C.Red, Text = "X", MaxTextSize = 38, Radius = 18, Stroke = 5, Shine = false, ZIndex = 31,
	})
	close.Rotation = -6
	close.Activated:Connect(function()
		holder.Visible = false
	end)
	local list = create("ScrollingFrame", {
		Name = "List", Parent = panel, Position = UDim2.fromOffset(22, 106), Size = UDim2.new(1, -44, 1, -126),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8, ScrollBarImageColor3 = Color3.fromRGB(139, 94, 52),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 22,
	}, { create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	-- ouverture : la fenêtre jaillit
	holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if holder.Visible then
			K.pop(body, 0.55, 0.38)
			K.pop(titleLabel, 0.3, 0.5)
			K.sound("UIOpen")
		end
	end)
	return holder, list, panel, headerContent, titleLabel
end

local shopWindow, shopList, shopPanel, shopHeader = makeWindow("ShopWindow", "BOUTIQUE", C.Orange)
local bookWindow, bookList, _, _, bookTitle = makeWindow("BookWindow", "COLLECTION", C.Teal)

---------------------------------------------------------------------------
-- Jauge VERTICALE au centre : zone PARFAIT dorée, l'aimant sert de curseur
---------------------------------------------------------------------------
local gaugeFrame = responsive(create("Frame", {
	Name = "Gauge", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromOffset(84, 430), BackgroundTransparency = 1, Visible = false, ZIndex = 10,
}))
local gaugeBody = create("Frame", { Name = "Body", Parent = gaugeFrame, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10 })
local gaugeScale = create("UIScale", { Parent = gaugeBody })
local zoneRays = create("Frame", { Name = "ZoneRays", Parent = gaugeBody, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(240, 240), BackgroundTransparency = 1, ZIndex = 9 })
K.rays(zoneRays, Color3.fromRGB(255, 228, 92), 14, 22, 0.45)
create("Frame", { -- halo doré derrière la zone parfaite
	Name = "Halo", Parent = gaugeBody, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 34, Config.Gauge.PerfectWindow * 2, 34), BackgroundColor3 = Color3.fromRGB(255, 228, 92), BackgroundTransparency = 0.45, ZIndex = 10,
}, { K.corner(22) })
local tube = create("Frame", {
	Name = "Tube", Parent = gaugeBody, Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.White, ZIndex = 11,
}, {
	K.round(), K.stroke(6),
	create("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 74)), ColorSequenceKeypoint.new(0.28, Color3.fromRGB(255, 196, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(123, 234, 92)), ColorSequenceKeypoint.new(0.72, Color3.fromRGB(255, 196, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 74)),
	}) }),
})
create("Frame", { Name = "Gloss", Parent = tube, Position = UDim2.new(0, 12, 0, 24), Size = UDim2.new(0, 18, 1, -48), BackgroundColor3 = K.White, BackgroundTransparency = 0.6, ZIndex = 12 }, { K.round() })
for i = 1, 9 do
	create("Frame", { Name = "Tick", Parent = tube, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, i / 10, 0), Size = UDim2.fromOffset(20, 4), BackgroundColor3 = K.Ink, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 12 })
end
local perfectWindow = create("Frame", { -- fenêtre "PARFAIT"
	Name = "PerfectWindow", Parent = tube, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, Config.Gauge.PerfectWindow * 2), BackgroundColor3 = K.White, ZIndex = 13,
}, { K.gradient(Color3.fromRGB(255, 246, 176), Color3.fromRGB(255, 210, 63)), K.stroke(3, K.White) })
local perfectLabel = K.text({
	Name = "PerfectLabel", Parent = gaugeBody, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, 16, 0.5, 0),
	Size = UDim2.fromOffset(150, 40), Text = "PARFAIT", TextColor3 = Color3.fromRGB(255, 228, 92), MaxTextSize = 30, Rotation = -8,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 14,
})
K.sparkles(gaugeBody, { { 1.6, 0.42, 18 }, { -0.7, 0.55, 14 }, { 2.4, 0.56, 12 }, { -0.4, 0.4, 10 } }, Color3.fromRGB(255, 243, 160), 14)
local gaugeNeedle = create("Frame", {
	Name = "Needle", Parent = gaugeBody, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.new(1.7, 0, 0, 12), BackgroundColor3 = K.White, ZIndex = 15,
}, { K.round(), K.stroke(4) })
local needleMagnet = create("ViewportFrame", {
	Name = "Magnet", Parent = gaugeNeedle, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, 2, 0.5, 0),
	Size = UDim2.fromOffset(62, 62), BackgroundTransparency = 1, ZIndex = 16,
})
if uiModel("Magnet") then
	K.showcase(needleMagnet, uiModel("Magnet") :: Model, { speed = 2.2, zoom = 1.6 })
end
local gaugeLabel = K.text({
	Name = "Hint", Parent = gaugeFrame, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 18),
	Size = UDim2.fromOffset(480, 44), Text = "TOUCHE AU BON MOMENT !", MaxTextSize = 32, ZIndex = 14,
})
-- Bouton pour quitter le ponton sans lancer (sinon la jauge repart en boucle)
local leaveButton = K.button({
	Name = "Leave", Parent = gaugeFrame, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 72),
	Size = UDim2.fromOffset(176, 52), Colors = C.Wood, Text = "PARTIR", MaxTextSize = 26, Shine = false, ZIndex = 16,
})
-- Capteur : on tape n'importe où dans les 70 % droits de l'écran pour figer la jauge.
-- Le tiers gauche reste libre pour le joystick mobile (on peut sortir de la zone).
local tapCatcher = create("TextButton", {
	Name = "TapCatcher", Parent = gui, Position = UDim2.fromScale(0.3, 0), Size = UDim2.fromScale(0.7, 1),
	BackgroundTransparency = 1, Text = "", Visible = false, ZIndex = 0,
})

---------------------------------------------------------------------------
-- Nettoyage (appui maintenu) : planche de bois qui se remplit d'eau
---------------------------------------------------------------------------
local cleanButton = K.button({
	Name = "Clean", Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34),
	Size = UDim2.fromOffset(440, 86), Colors = C.Wood, Radius = 24, Stroke = 5, Shine = false, ZIndex = 5,
	Animate = { clickSound = false, hoverScale = 1.03 },
})
cleanButton.Visible = false
local cleanClip = create("Frame", { Name = "FillClip", Parent = cleanButton, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 7 }, { K.corner(24) })
local cleanFill = create("Frame", {
	Name = "Water", Parent = cleanClip, Size = UDim2.fromScale(0, 1), BackgroundColor3 = K.White, BorderSizePixel = 0, ZIndex = 7,
}, { K.gradient(Color3.fromRGB(150, 230, 255), Color3.fromRGB(48, 150, 210)) })
K.text({ Name = "Label", Parent = cleanButton, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -40, 0.6, 0), Text = "🗝 MAINTIENS POUR OUVRIR", MaxTextSize = 30, ZIndex = 9 })

---------------------------------------------------------------------------
-- Révélation : rayons de rareté, relique 3D qui flotte, ruban, valeur, boutons
---------------------------------------------------------------------------
local revealDim = create("Frame", { Name = "RevealDim", Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 7, 10), BackgroundTransparency = 1, Visible = false, ZIndex = 1, Active = false })
local revealCard = responsive(create("Frame", {
	Name = "Reveal", Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(720, 560), BackgroundTransparency = 1, Visible = false, ZIndex = 30,
}))
local revealBody = create("Frame", { Name = "Body", Parent = revealCard, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30 })
local revealScale = create("UIScale", { Parent = revealBody }) -- animation d'apparition
local revealRaysHolder = create("Frame", { Name = "RaysHolder", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 168), Size = UDim2.fromOffset(620, 620), BackgroundTransparency = 1, ZIndex = 30 })
local revealRays = K.rays(revealRaysHolder, K.White, 18, 16, 0.45)
local revealGlow = create("Frame", { Name = "Glow", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 168), Size = UDim2.fromOffset(260, 260), BackgroundColor3 = K.White, BackgroundTransparency = 0.55, ZIndex = 31 }, { K.round() })
local revealViewport = create("ViewportFrame", { Name = "Relic", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 168), Size = UDim2.fromOffset(250, 250), BackgroundTransparency = 1, ZIndex = 32 })
K.sparkles(revealBody, { { 0.34, 0.2, 26 }, { 0.66, 0.16, 20 }, { 0.68, 0.46, 22 }, { 0.32, 0.46, 16 }, { 0.5, 0.06, 14 } }, nil, 37)
local revealTitle = K.text({
	Name = "Title", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(620, 92),
	Text = "", MaxTextSize = 84, Outline = 8, Rotation = -5, ZIndex = 36, Visible = false,
})
local revealTitleGradient = create("UIGradient", {
	Parent = revealTitle, Enabled = false,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 230, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 160)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 80, 255)),
	}),
})
-- ruban avec le nom de la relique (couleur de la rareté)
local ribbonTails = {}
for _, side in ipairs({ -1, 1 }) do
	ribbonTails[side] = create("Frame", {
		Name = "RibbonTail", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * 300, 0, 330),
		Size = UDim2.fromOffset(80, 56), BackgroundColor3 = K.White, ZIndex = 33,
	}, { K.corner(8), K.stroke(5), K.gradient(Color3.fromRGB(90, 34, 144), Color3.fromRGB(60, 20, 100)) })
end
local ribbon = create("Frame", {
	Name = "Ribbon", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 318),
	Size = UDim2.fromOffset(560, 74), BackgroundColor3 = K.White, ZIndex = 34,
}, { K.corner(14), K.gradient(Color3.fromRGB(181, 123, 232), Color3.fromRGB(106, 44, 168)) })
local revealStroke = K.stroke(6)
revealStroke.Parent = ribbon
local revealName = K.text({ Name = "Name", Parent = ribbon, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -30, 0.7, 0), MaxTextSize = 38, ZIndex = 35 })
local revealInfo = K.text({ Name = "Info", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 362), Size = UDim2.fromOffset(560, 26), MaxTextSize = 22, ZIndex = 35 })
-- probabilité d'avoir CET objet : « 1 SUR 25 000 » en grand + pourcentage
local revealOdds = K.text({ Name = "Odds", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 390), Size = UDim2.fromOffset(600, 38), MaxTextSize = 34, Outline = 5, TextColor3 = Color3.fromRGB(255, 228, 92), Rotation = -2, ZIndex = 36 })
local revealValue = K.text({ Name = "Value", Parent = revealBody, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 428), Size = UDim2.fromOffset(460, 52), MaxTextSize = 50, Outline = 6, TextColor3 = Color3.fromRGB(140, 240, 122), ZIndex = 35 })
local sellButton, sellLabel = K.button({
	Name = "Sell", Parent = revealBody, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -10, 0, 486), Size = UDim2.fromOffset(270, 66),
	Colors = C.Green, Text = "VENDRE", MaxTextSize = 28, Radius = 22, Stroke = 5, ZIndex = 36,
})
local exposeButton, exposeLabel = K.button({
	Name = "Expose", Parent = revealBody, Position = UDim2.new(0.5, 10, 0, 486), Size = UDim2.fromOffset(270, 66),
	Colors = C.Teal, Text = "EXPOSER", MaxTextSize = 28, Radius = 22, Stroke = 5, ZIndex = 36,
})

---------------------------------------------------------------------------
-- Messages courts, annonces serveur, flash plein écran
---------------------------------------------------------------------------
local toastLabel = K.text({
	Name = "Toast", Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.16, 0), Size = UDim2.fromScale(0.8, 0.075),
	Text = "", MaxTextSize = 40, Outline = 5, Visible = false, ZIndex = 45,
})
local announceLabel = K.text({
	Name = "Announce", Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.25, 0), Size = UDim2.fromScale(0.9, 0.09),
	BackgroundColor3 = K.Ink, BackgroundTransparency = 0.25, Text = "", MaxTextSize = 44, Outline = 5, Visible = false, ZIndex = 44,
})
create("UICorner", { CornerRadius = UDim.new(0, 18), Parent = announceLabel })
create("UIPadding", { PaddingLeft = UDim.new(0.02, 0), PaddingRight = UDim.new(0.02, 0), Parent = announceLabel })
local flashFrame = create("Frame", {
	Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.White, BackgroundTransparency = 1, ZIndex = 50, Active = false,
})
-- Bandes noires "cinéma" (haut / bas), repliées hors cinématique
local letterboxTop = create("Frame", {
	Name = "LetterboxTop", Parent = gui, Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0, ZIndex = 40, Active = false,
})
local letterboxBottom = create("Frame", {
	Name = "LetterboxBottom", Parent = gui, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 40, Active = false,
})
updateResponsive()

---------------------------------------------------------------------------
-- 3. Utilitaires
---------------------------------------------------------------------------
-- Tween d'un alpha 0 -> 1, qui appelle onStep(alpha) à chaque frame. Bloquant.
-- C'est le moteur de toutes les trajectoires (arc, descente, remontée).
local function tweenAlpha(duration: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, onStep: (number) -> ())
	local value = Instance.new("NumberValue")
	local conn = value.Changed:Connect(onStep)
	onStep(0)
	local tween = TweenService:Create(value, TweenInfo.new(duration, style, direction), { Value = 1 })
	tween:Play()
	tween.Completed:Wait()
	conn:Disconnect()
	value:Destroy()
	onStep(1)
end

local function tween(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function playSound(key: string, parent: Instance?, volumeOverride: number?, looped: boolean?): Sound?
	local def = Config.Sounds[key]
	if not def or def.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = volumeOverride or def.volume
	sound.Looped = looped or false
	sound.RollOffMaxDistance = 1000
	sound.Parent = parent or gui
	sound:Play()
	if not sound.Looped then
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		Debris:AddItem(sound, 15)
	end
	return sound
end

local toastToken = 0
local function toast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or UI.White
	toastLabel.Visible = true
	K.pop(toastLabel, 0.5, 0.3)
	K.sound("UIPop")
	task.delay(UI.ToastTime, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

local function bezier(a: Vector3, control: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(control, t):Lerp(control:Lerp(b, t), t)
end

local function rarityDef(id: string)
	return (Config.GetRarity(id))
end

-- Émetteur de particules générique (désactivé par défaut)
local function makeEmitter(parent: Instance, color: Color3, props: { [string]: any }?)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(8, 18)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Rate = 0
	emitter.Enabled = false
	for key, value in pairs(props or {}) do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	return emitter
end

-- Burst de particules ponctuel à une position (impact, révélation...)
local function burstAt(position: Vector3, color: Color3, count: number, props: { [string]: any }?, parent: Instance?)
	local holder = create("Part", {
		Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1, Size = Vector3.new(1, 1, 1),
		Position = position, Parent = parent or workspace,
	})
	local emitter = makeEmitter(holder, color, props)
	emitter:Emit(count)
	Debris:AddItem(holder, 4)
end

---------------------------------------------------------------------------
-- Caméra scriptée : suit un point (focus) depuis une position de base
---------------------------------------------------------------------------
local Cam = {
	active = false,
	basePosition = Vector3.zero, -- position voulue de la caméra (fixe)
	baseFn = nil :: (() -> Vector3)?, -- si défini, position voulue dynamique (plongée)
	focus = function(): Vector3 return Vector3.zero end,
	shake = 0, -- intensité continue (studs)
	kick = 0, -- pic de tremblement qui décroît
	smoothed = CFrame.identity, -- CFrame lissé SANS tremblement
	sharpness = nil :: number?, -- réactivité ponctuelle (sinon Config.Camera.FollowSharpness)
	roll = 0, -- inclinaison de la caméra (radians)
	clampToCanyon = false, -- sous le bord, la caméra reste entre les parois
}
local shakeRandom = Random.new()

RunService.RenderStepped:Connect(function(dt)
	if not Cam.active then
		return
	end
	local focus = Cam.focus()
	local base = Cam.baseFn and Cam.baseFn() or Cam.basePosition
	local desired = CFrame.lookAt(base, focus)
	local alpha = 1 - math.exp(-dt * (Cam.sharpness or Config.Camera.FollowSharpness))
	Cam.smoothed = Cam.smoothed:Lerp(desired, alpha)
	if Cam.clampToCanyon then
		-- le lissage ne doit jamais faire traverser une paroi
		local p = Cam.smoothed.Position
		if p.Y < Config.World.RimY + 2 then
			local column = Cam.column or p
			local flat = Vector3.new(p.X - column.X, 0, p.Z - column.Z)
			local radius = Config.Camera.SlotRadius
			if flat.Magnitude > radius then
				flat = flat.Unit * radius
			end
			Cam.smoothed = CFrame.new(Vector3.new(column.X, p.Y, column.Z) + flat) * Cam.smoothed.Rotation
		end
	end
	Cam.kick = math.max(0, Cam.kick - dt * 2)
	local intensity = Cam.shake + Cam.kick
	local shakeOffset = CFrame.identity
	if intensity > 0 then
		shakeOffset = CFrame.new(shakeRandom:NextNumber(-1, 1) * intensity, shakeRandom:NextNumber(-1, 1) * intensity, 0)
	end
	camera.CFrame = Cam.smoothed * CFrame.Angles(0, 0, Cam.roll) * shakeOffset
end)

local function cameraStart(basePosition: Vector3, focus: () -> Vector3)
	camera.CameraType = Enum.CameraType.Scriptable
	Cam.smoothed = camera.CFrame
	Cam.basePosition = basePosition
	Cam.baseFn = nil
	Cam.focus = focus
	Cam.active = true
end

local function cameraStop()
	Cam.active = false
	Cam.baseFn = nil
	Cam.shake = 0
	Cam.kick = 0
	Cam.sharpness = nil
	Cam.roll = 0
	Cam.clampToCanyon = false
	Cam.column = nil
	-- Retour à la caméra normale : derrière le joueur, avec du recul. La caméra
	-- Roblox garde sinon le zoom de la cinématique (collée dans le joueur, vers le ciel).
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local behind = root.CFrame * CFrame.new(0, Config.Camera.ReturnHeight, Config.Camera.ReturnDistance)
		camera.CFrame = CFrame.lookAt(behind.Position, root.Position + Vector3.new(0, 1.5, 0))
	end
	camera.CameraType = Enum.CameraType.Custom
	local minZoom = player.CameraMinZoomDistance
	player.CameraMinZoomDistance = math.max(minZoom, Config.Camera.ReturnDistance)
	task.delay(0.2, function()
		player.CameraMinZoomDistance = minZoom
	end)
	tween(camera, 0.4, { FieldOfView = Config.Camera.ThrowFOV })
end

---------------------------------------------------------------------------
-- Mode cinématique : plus aucun bouton à l'écran, bandes noires
---------------------------------------------------------------------------
local cinematicOn = false
local savedCoreGui: { [Enum.CoreGuiType]: boolean } = {}
local savedTouchControls = true

local function setCinematic(on: boolean)
	if on == cinematicOn then
		return
	end
	cinematicOn = on
	local debugPanel = gui:FindFirstChild("Debug")
	topBar.Visible = not on
	if debugPanel then
		debugPanel.Visible = not on
	end
	if on then
		actionPanel.Visible = false
		shopWindow.Visible = false
		bookWindow.Visible = false
		-- chat, liste des joueurs, sac, émotes... (on mémorise pour tout rendre ensuite)
		for _, coreType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
			if coreType ~= Enum.CoreGuiType.All then
				savedCoreGui[coreType] = StarterGui:GetCoreGuiEnabled(coreType)
			end
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		savedTouchControls = GuiService.TouchControlsEnabled
		GuiService.TouchControlsEnabled = false -- joystick et bouton de saut mobiles
	else
		for coreType, enabled in pairs(savedCoreGui) do
			pcall(function()
				StarterGui:SetCoreGuiEnabled(coreType, enabled)
			end)
		end
		GuiService.TouchControlsEnabled = savedTouchControls
	end
	local height = on and Config.Camera.LetterboxHeight or 0
	tween(letterboxTop, 0.5, { Size = UDim2.fromScale(1, height) }, Enum.EasingStyle.Quint)
	tween(letterboxBottom, 0.5, { Size = UDim2.fromScale(1, height) }, Enum.EasingStyle.Quint)
end

---------------------------------------------------------------------------
-- Personnage : verrouillage pendant le lancer
---------------------------------------------------------------------------
local savedWalkSpeed, savedJumpPower, savedJumpHeight

local function getCharacterParts()
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") or root
	return humanoid, root, hand
end

local function lockCharacter(locked: boolean)
	local humanoid, root = getCharacterParts()
	if not (humanoid and root) then
		return
	end
	if locked then
		savedWalkSpeed, savedJumpPower, savedJumpHeight = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight
		humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 0, 0, 0
		-- Place le joueur sur le pas de tir, face à la poulie
		local standAt = launchPad.Position + Vector3.new(0, launchPad.Size.Y / 2 + 3, 0)
		local lookAt = Vector3.new(pulleyPart.Position.X, standAt.Y, pulleyPart.Position.Z)
		root.CFrame = CFrame.lookAt(standAt, lookAt)
	else
		humanoid.WalkSpeed = savedWalkSpeed or humanoid.WalkSpeed
		humanoid.JumpPower = savedJumpPower or humanoid.JumpPower
		humanoid.JumpHeight = savedJumpHeight or humanoid.JumpHeight
	end
end

---------------------------------------------------------------------------
-- Zone de lancer (point unique partagé)
---------------------------------------------------------------------------
local function isInThrowZone(): boolean
	local _, root = getCharacterParts()
	if not root then
		return false
	end
	local localPosition = throwZone.CFrame:PointToObjectSpace(root.Position)
	local half = throwZone.Size / 2
	return math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z
end

---------------------------------------------------------------------------
-- Masquage des autres joueurs pendant ta cinématique (local uniquement)
---------------------------------------------------------------------------
local othersHidden = false
local lastHideRefresh = 0

local function applyOthersVisibility()
	local modifier = othersHidden and 1 or 0
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other ~= player and other.Character
		if character then
			for _, item in ipairs(character:GetDescendants()) do
				if item:IsA("BasePart") or item:IsA("Decal") then
					item.LocalTransparencyModifier = modifier
				end
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.DisplayDistanceType = othersHidden and Enum.HumanoidDisplayDistanceType.None
					or Enum.HumanoidDisplayDistanceType.Viewer
			end
		end
	end
end

local function setOthersHidden(hidden: boolean)
	-- les aimants des autres dans TON canyon pendant ta plongée : toujours masqués
	-- (les animations continuent hors du workspace et réapparaissent à jour)
	otherThrowsFolder.Parent = if hidden then nil else workspace
	if not Config.Multiplayer.HideOthersDuringThrow then
		return
	end
	othersHidden = hidden
	applyOthersVisibility()
end

-- Rafraîchit le masquage (joueur qui arrive, réapparaît, accessoire qui charge)
RunService.Heartbeat:Connect(function()
	if othersHidden and os.clock() - lastHideRefresh >= Config.Multiplayer.HideRefresh then
		lastHideRefresh = os.clock()
		applyOthersVisibility()
	end
end)

---------------------------------------------------------------------------
-- 4. Jauge de timing : renvoie la position figée (0..1, 0.5 = centre),
--    ou nil si le joueur est sorti de la zone (lancer annulé)
---------------------------------------------------------------------------
local cancelGauge: (() -> ())? = nil -- défini tant que la jauge tourne
local waitForExit = false -- « Partir » : pas de nouvelle jauge tant qu'on n'est pas sorti du cercle

leaveButton.Activated:Connect(function()
	if not cancelGauge then
		return
	end
	waitForExit = true
	cancelGauge()
	playSound("Throw", nil, 0.3)
	-- on ramène le joueur au début du ponton, face au village
	local _, root = getCharacterParts()
	if root then
		local rim = Config.World.RimY
		root.CFrame = CFrame.lookAt(Vector3.new(21, rim + 3, 0), Vector3.new(40, rim + 3, 0))
	end
end)

local function runGauge(): number?
	gaugeFrame.Visible = true
	tapCatcher.Visible = true
	gaugeLabel.Text = "Touche l'écran au bon moment !"
	gaugeLabel.TextColor3 = UI.White
	-- apparition : la jauge "pousse" depuis le centre
	gaugeScale.Scale = 0.3
	tween(gaugeScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	-- on peut marcher pendant la jauge (pour sortir de la zone) mais pas sauter :
	-- sur PC, Espace sert à figer la jauge
	local humanoid = getCharacterParts()
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	local startTime = os.clock()
	local position = 0
	local stopped = Instance.new("BindableEvent")
	cancelGauge = function()
		stopped:Fire(true)
	end
	local stepConn = RunService.RenderStepped:Connect(function()
		-- onde triangle : 0 -> 1 -> 0 ...
		local t = ((os.clock() - startTime) / Config.Gauge.SweepTime) % 2
		position = t <= 1 and t or 2 - t
		gaugeNeedle.Position = UDim2.fromScale(0.5, 1 - position) -- 0 = en bas, 1 = en haut
		if not isInThrowZone() then
			stopped:Fire(true) -- sorti de la zone : annulé
		end
	end)
	local tapConn = tapCatcher.MouseButton1Down:Connect(function()
		stopped:Fire(false)
	end)
	local keyConn = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			stopped:Fire(false)
		end
	end)
	local cancelled = stopped.Event:Wait()
	cancelGauge = nil
	stepConn:Disconnect()
	tapConn:Disconnect()
	keyConn:Disconnect()
	stopped:Destroy()
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	if cancelled then
		gaugeFrame.Visible = false
		tapCatcher.Visible = false
		return nil
	end

	local perfect = math.abs(position - 0.5) <= Config.Gauge.PerfectWindow
	gaugeLabel.Text = perfect and "⭐ PARFAIT ! ⭐" or "Lancé !"
	gaugeLabel.TextColor3 = perfect and Color3.fromRGB(255, 225, 90) or UI.White
	-- le curseur "claque" à sa place
	gaugeNeedle.Size = UDim2.new(2.3, 0, 0, 18)
	tween(gaugeNeedle, 0.25, { Size = UDim2.new(1.7, 0, 0, 12) }, Enum.EasingStyle.Back)
	if perfect then
		gaugeScale.Scale = 1.15
		tween(gaugeScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		K.punch(perfectLabel, 0.6)
		K.sound("UIDing")
		local at = perfectWindow.AbsolutePosition + perfectWindow.AbsoluteSize / 2
		K.coinBurst(gui, at, 10)
	else
		K.sound("UIClick")
	end
	task.wait(Config.Gauge.ResultDisplayTime)
	gaugeFrame.Visible = false
	tapCatcher.Visible = false
	return position
end

---------------------------------------------------------------------------
-- 5. Séquence de lancer
---------------------------------------------------------------------------
-- Construit l'aimant (Model local) : corps ancré + pointes soudées
local function buildMagnet()
	local model = Instance.new("Model")
	model.Name = "Magnet"
	local body = create("Part", {
		Name = "Body", Size = Vector3.new(2.4, 1.4, 1), Color = Color3.fromRGB(210, 40, 40), Material = Enum.Material.SmoothPlastic,
		Anchored = true, CanCollide = false, CanQuery = false, Parent = model,
	})
	for _, side in ipairs({ -1, 1 }) do
		local tip = create("Part", {
			Name = "Tip", Size = Vector3.new(0.8, 0.8, 1), Color = Color3.fromRGB(190, 190, 200), Material = Enum.Material.Metal,
			Anchored = false, CanCollide = false, CanQuery = false, Massless = true,
			CFrame = body.CFrame * CFrame.new(side * 0.8, -1.1, 0), Parent = model,
		})
		create("WeldConstraint", { Part0 = body, Part1 = tip, Parent = tip })
	end
	local cableAttachment = create("Attachment", { Name = "Cable", Position = Vector3.new(0, 0.7, 0), Parent = body })
	model.PrimaryPart = body
	model.Parent = workspace
	return model, body, cableAttachment
end

-- Traînée derrière l'aimant pendant la chute (sensation de vitesse)
local function makeDropTrail(body: BasePart): Trail
	local a0 = create("Attachment", { Name = "TrailA", Position = Vector3.new(-1, 0, 0), Parent = body })
	local a1 = create("Attachment", { Name = "TrailB", Position = Vector3.new(1, 0, 0), Parent = body })
	return create("Trail", {
		Attachment0 = a0, Attachment1 = a1, FaceCamera = true, Lifetime = Config.Anim.DropTrailLifetime,
		Color = ColorSequence.new(UI.White), LightEmission = 0.4, MinLength = 0.1,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }),
		Parent = body,
	})
end

-- Corde 3D : une chaîne de petits cylindres tressés (deux tons) entre deux
-- attachments, recalculée à chaque image. Elle pend quand elle est lâche et se
-- tend quand on lui donne une largeur « tendue ». Mêmes propriétés que l'ancien
-- câble (Width0/Width1 : tension, CurveSize0/1 : vibration, Parent, Destroy).
local function makeCable(a0: Attachment, a1: Attachment)
	local anim = Config.Anim
	local count = anim.RopeSegments
	local model = Instance.new("Model")
	model.Name = "Rope"
	local segments = {}
	for i = 1, count do
		local part = Instance.new("Part")
		part.Name = "RopeSegment"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Fabric
		part.Color = i % 2 == 0 and anim.RopeColor or anim.RopeColorDark
		part.Size = Vector3.new(1, anim.RopeThickness, anim.RopeThickness)
		part.Parent = model
		segments[i] = part
	end
	model.Parent = workspace
	local props = { Width0 = anim.CableWidth, Width1 = anim.CableWidth, CurveSize0 = 0, CurveSize1 = 0 }
	local points = table.create(count + 1)
	local conn = RunService.RenderStepped:Connect(function()
		if not (a0.Parent and a1.Parent) then
			return
		end
		local p0, p1 = a0.WorldPosition, a1.WorldPosition
		local delta = p1 - p0
		local length = delta.Magnitude
		if length < 0.05 then
			return
		end
		-- mou : la corde pend (moins quand elle est presque verticale), sauf si elle est tendue
		local tense = props.Width0 < anim.CableWidth - 0.01
		local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
		local sag = tense and 0 or math.min(anim.RopeMaxSag, horizontal * anim.RopeSag)
		local side = delta:Cross(Vector3.yAxis)
		side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
		local wobble = props.CurveSize0 or 0
		for i = 0, count do
			local t = i / count
			local bulge = 4 * t * (1 - t)
			points[i + 1] = p0 + delta * t - Vector3.new(0, sag * bulge, 0) + side * (wobble * bulge)
		end
		for i = 1, count do
			local a, b = points[i], points[i + 1]
			local d = (b - a).Magnitude
			local part = segments[i]
			part.Size = Vector3.new(d + anim.RopeThickness * 0.6, anim.RopeThickness, anim.RopeThickness)
			if d > 0.001 then
				part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
			end
		end
	end)
	local rope = {}
	function rope:Destroy()
		conn:Disconnect()
		model:Destroy()
	end
	setmetatable(rope, {
		__index = function(_, key)
			if key == "Parent" then
				return model.Parent
			end
			return props[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				model.Parent = value
			else
				props[key] = value
			end
		end,
	})
	return rope
end

-- Le butin remonté : un COFFRE fermé (look selon la rareté) qui contient la
-- relique. Elle n'apparaît qu'à l'ouverture, à l'atelier (non parenté).
local function cloneMuddyRelic(relicId: string, rarity)
	local haul = Instance.new("Model")
	haul.Name = "Haul"
	haul:SetAttribute("RelicId", relicId)
	local template = ChestsFolder:FindFirstChild("Chest_" .. rarity.id) or ChestsFolder:FindFirstChild("Chest_Commun")
	local chest: Model
	if template then
		chest = template:Clone()
	else
		warn("[Client] Coffre introuvable pour", rarity.id)
		chest = Instance.new("Model")
		create("Part", { Size = Vector3.new(3, 2, 2), Parent = chest })
	end
	chest.Name = "Chest"
	chest.Parent = haul
	haul.PrimaryPart = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart", true)
	for _, part in ipairs(haul:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.Massless = true
		end
	end
	-- contour à la couleur de la rareté (les rares se trahissent dès la remontée)
	local glow = create("Highlight", {
		Name = "Mud", FillTransparency = 1, OutlineColor = rarity.color,
		OutlineTransparency = rarity.isRare and 0 or 1, DepthMode = Enum.HighlightDepthMode.Occluded, Parent = haul,
	})
	return haul, glow
end

-- Couvercle du coffre : angle (radians) autour de la charnière (arrière, en haut)
local function setChestLid(haul: Model, angle: number)
	local chest = haul:FindFirstChild("Chest")
	local lid = chest and chest:FindFirstChild("Lid")
	local hinge: Vector3? = chest and chest:GetAttribute("Hinge")
	local lidLocal: CFrame? = chest and chest:GetAttribute("LidLocal")
	if not (lid and hinge and lidLocal) then
		return
	end
	local hingeCF = CFrame.new(hinge)
	lid:PivotTo(chest:GetPivot() * hingeCF * CFrame.Angles(angle, 0, 0) * hingeCF:Inverse() * lidLocal)
end

-- Accroche la relique boueuse sous l'aimant
local function attachRelic(relicId: string, body: BasePart, rarity)
	local relic, mud = cloneMuddyRelic(relicId, rarity)
	local size = relic:GetExtentsSize()
	relic:PivotTo(body.CFrame * CFrame.new(0, -(1.6 + size.Y / 2), 0))
	for _, part in ipairs(relic:GetDescendants()) do
		if part:IsA("BasePart") then
			create("WeldConstraint", { Part0 = body, Part1 = part, Parent = part })
		end
	end
	relic.Parent = workspace
	return relic, mud
end

-- Position de repos d'une relique sur la plateforme de nettoyage
local function restPositionFor(relic: Model): Vector3
	local size = relic:GetExtentsSize()
	return cleaningPlatform.Position + Vector3.new(0, cleaningPlatform.Size.Y / 2 + size.Y / 2 + 0.2, 0)
end

---------------------------------------------------------------------------
-- Sons en couches
---------------------------------------------------------------------------
local function soundVolume(key: string): number
	local def = Config.Sounds[key]
	return def and def.volume or 1
end

-- Joue une liste de sons ensemble (sons "2D" : même volume quelle que soit la caméra)
local function playSounds(keys: { string }?)
	for _, key in ipairs(keys or {}) do
		playSound(key)
	end
end

-- Démarre des boucles à volume 0 puis les fait monter (fondu d'entrée)
local function startLoops(keys: { string }?)
	local layers = {}
	for _, key in ipairs(keys or {}) do
		local sound = playSound(key, nil, 0, true)
		if sound then
			tween(sound, Config.Anim.LoopFadeIn, { Volume = soundVolume(key) }, Enum.EasingStyle.Sine)
			table.insert(layers, sound)
		end
	end
	return layers
end

-- progress 0..1 : les boucles montent en hauteur (effet "riser")
local function setLoopsProgress(layers, progress: number)
	for _, sound in ipairs(layers) do
		sound.PlaybackSpeed = 1 + Config.Anim.LoopPitchRise * progress
	end
end

local function stopLoops(layers, fade: number)
	for _, sound in ipairs(layers) do
		tween(sound, fade, { Volume = 0 })
		Debris:AddItem(sound, fade + 0.05)
	end
	table.clear(layers)
end

---------------------------------------------------------------------------
-- Effets visuels partagés : flash, onde de choc, faisceau vers le ciel
---------------------------------------------------------------------------
local function screenFlash(color: Color3)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 0
	tween(flashFrame, Config.Anim.FlashDuration, { BackgroundTransparency = 1 })
	playSound("Flash")
end

-- Disque lumineux horizontal qui s'étend et s'efface (plusieurs, décalés)
local function shockwave(center: Vector3, color: Color3, count: number, parent: Instance?)
	for index = 1, count do
		task.delay((index - 1) * Config.Anim.ShockwaveStagger, function()
			local ring = create("Part", {
				Name = "Shockwave", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = color,
				Size = Vector3.new(0.3, 1, 1), Transparency = 0.35, Anchored = true, CanCollide = false, CanQuery = false,
				CastShadow = false, CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), Parent = parent or workspace,
			})
			local size = Config.Anim.ShockwaveSize
			tween(ring, Config.Anim.ShockwaveDuration, { Size = Vector3.new(0.3, size, size), Transparency = 1 }, Enum.EasingStyle.Quart)
			Debris:AddItem(ring, Config.Anim.ShockwaveDuration + 0.1)
		end)
	end
end

-- Faisceau qui jaillit vers le ciel À PARTIR de basePos (jamais devant l'action)
local function skyBeamAt(basePos: Vector3, color: Color3, hold: number, parent: Instance?)
	local height = Config.Anim.SkyBeamHeight
	local width = Config.Anim.SkyBeamWidth
	local beam = create("Part", {
		Name = "SkyBeam", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = color,
		Size = Vector3.new(height, 0.2, 0.2), Transparency = 0.15, Anchored = true, CanCollide = false, CanQuery = false,
		CastShadow = false, CFrame = CFrame.new(basePos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = parent or workspace,
	})
	tween(beam, Config.Anim.SkyBeamRise, { Size = Vector3.new(height, width, width) }, Enum.EasingStyle.Back)
	task.delay(hold, function()
		tween(beam, 1, { Size = Vector3.new(height, 0.2, 0.2), Transparency = 1 })
		Debris:AddItem(beam, 1.1)
	end)
end

---------------------------------------------------------------------------
-- Effets de remontée rare : lueur, particules, colonne de lumière, sons
---------------------------------------------------------------------------
local function startRareEffects(body: BasePart, rarity, tier: number, bottomPos: Vector3)
	local params = rarity.ascent
	local effects = {}
	effects.light = create("PointLight", { Color = rarity.color, Brightness = 0, Range = params.lightRange, Shadows = false, Parent = body })
	tween(effects.light, 0.6, { Brightness = params.lightBrightness })

	effects.orb = create("Part", {
		Name = "GlowOrb", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = rarity.color,
		Size = Vector3.one * Config.Anim.GlowOrbSize * (1 + tier * 0.25), Transparency = 1,
		Anchored = false, CanCollide = false, CanQuery = false, Massless = true, CastShadow = false,
		CFrame = body.CFrame * CFrame.new(0, -2.5, 0), Parent = body.Parent,
	})
	create("WeldConstraint", { Part0 = body, Part1 = effects.orb, Parent = effects.orb })
	tween(effects.orb, 0.6, { Transparency = 0.75 })

	effects.sparkles = makeEmitter(body, rarity.color, {
		Rate = params.particleRate / 3, LightEmission = 1, Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
	})
	effects.sparkles.Enabled = true

	-- particules qui s'échappent du canyon
	effects.mouth = makeEmitter(canyonMouth, rarity.color, {
		Rate = params.particleRate, LightEmission = 1, Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(15, 15), EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 4, 0),
	})
	effects.mouth.Enabled = true

	-- Colonne de lumière du fond jusqu'à l'aimant : la lueur MONTE avec lui
	effects.columnAnchor = create("Part", {
		Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1, Size = Vector3.one,
		Position = bottomPos, Parent = workspace,
	})
	local columnWidth = Config.Anim.LightColumnWidth * (1 + tier * 0.15)
	create("Beam", {
		Attachment0 = create("Attachment", { Parent = effects.columnAnchor }),
		Attachment1 = create("Attachment", { Name = "Column", Position = Vector3.new(0, -1, 0), Parent = body }),
		Width0 = columnWidth * 0.3, Width1 = columnWidth, Color = ColorSequence.new(rarity.color),
		LightEmission = 1, LightInfluence = 0, FaceCamera = true,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.95), NumberSequenceKeypoint.new(1, 0.3) }),
		Parent = effects.columnAnchor,
	})

	effects.sting = playSound(params.sting, nil, soundVolume(params.sting) * params.stingVolume)
	effects.loops = startLoops(params.loops)
	return effects
end

local function setEffectsTimeScale(effects, scale: number)
	for _, key in ipairs({ "sparkles", "mouth" }) do
		if effects[key] then
			effects[key].TimeScale = scale
		end
	end
end

local function stopRareEffects(effects)
	if not effects then
		return
	end
	stopLoops(effects.loops, Config.Anim.SilenceFade)
	if effects.mouth then
		effects.mouth.Enabled = false
		Debris:AddItem(effects.mouth, 4)
	end
	if effects.columnAnchor then
		effects.columnAnchor:Destroy()
	end
end

-- Position caméra en plongée : au-dessus/à côté de l'aimant, sans sortir des parois
local function diveCameraPosition(target: Vector3, offset: Vector3?): Vector3
	local wanted = target + (offset or Config.Camera.DiveOffset)
	if wanted.Y > Config.World.RimY + 2 then
		return wanted
	end
	-- dans la faille : la caméra reste près de la colonne de descente (sinon elle rentre dans la roche)
	local column = Cam.column or target
	local flat = Vector3.new(wanted.X - column.X, 0, wanted.Z - column.Z)
	local radius = Config.Camera.SlotRadius
	if flat.Magnitude > radius then
		flat = flat.Unit * radius
	end
	return Vector3.new(column.X, wanted.Y, column.Z) + flat
end

---------------------------------------------------------------------------
-- B. Attente au fond (+ tension pour les raretés avec `tease`)
---------------------------------------------------------------------------
local waitRandom = Random.new()

local function runWait(rarity, body: BasePart, cableDown: Beam, bottomPos: Vector3, pulleyPos: Vector3)
	local anim = Config.Anim
	local tease = rarity.tease or 0
	-- le câble raccourcit l'attente normale, jamais la tension des raretés
	local waitTime = waitRandom:NextNumber(anim.WaitMin, anim.WaitMax) / cableSpeed(player) + tease * anim.TeaseExtraWait

	-- La caméra reste au fond avec l'aimant et s'en rapproche lentement (tension)
	local pushIn = 0
	Cam.sharpness = nil
	Cam.roll = 0
	Cam.baseFn = function()
		local offset = Config.Camera.WaitOffset * (1 - Config.Camera.WaitPushIn * pushIn)
		return diveCameraPosition(bottomPos, offset)
	end
	Cam.focus = function()
		return body.Position
	end
	tween(camera, 1.2, { FieldOfView = Config.Camera.WaitFOV }, Enum.EasingStyle.Sine)

	-- grondement qui enfle pendant l'attente
	local rumble = nil
	if tease > 0 then
		rumble = playSound("TensionRumble", nil, 0, true)
		if rumble then
			tween(rumble, waitTime, { Volume = soundVolume("TensionRumble") * tease }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
	-- reflets de la couleur de rareté (Mythique, Secret)
	local glow = rarity.teaseGlow and create("PointLight", { Color = rarity.color, Brightness = 0, Range = 16, Shadows = false, Parent = body }) or nil

	local start = os.clock()
	local nextTug = start + anim.TeaseTugInterval
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		local progress = math.clamp(t / waitTime, 0, 1)
		pushIn = progress
		-- câble : vibre librement, puis se tend (vibration amortie, câble plus fin)
		local slack = 1 - tease * progress
		local amplitude = anim.CableVibrationAmplitude * (0.5 + 0.5 * math.sin(t * 3)) * slack
		cableDown.CurveSize0 = math.sin(t * anim.CableVibrationFrequency * math.pi * 2) * amplitude
		cableDown.CurveSize1 = -cableDown.CurveSize0
		if tease <= 0 then
			return
		end
		local width = anim.CableWidth + (anim.RareCableTenseWidth - anim.CableWidth) * progress * tease
		cableDown.Width0, cableDown.Width1 = width, width
		Cam.shake = anim.TeaseShake * tease * progress
		-- secousses : quelque chose tire au fond, de plus en plus vite
		if os.clock() >= nextTug then
			nextTug = os.clock() + anim.TeaseTugInterval * (1 - 0.5 * progress)
			local depth = anim.TeaseTugDepth * tease * (0.5 + progress)
			body.CFrame = CFrame.new(bottomPos - Vector3.new(0, depth, 0))
			tween(body, anim.TeaseTugInterval * 0.6, { CFrame = CFrame.new(bottomPos) }, Enum.EasingStyle.Back)
			Cam.kick = math.max(Cam.kick, 0.15 * tease)
		end
		if glow then
			local flicker = (0.5 + 0.5 * math.sin(t * 11)) ^ 2
			glow.Brightness = anim.TeaseGlowMax * progress * flicker
		end
	end)
	task.wait(waitTime)
	conn:Disconnect()
	body.CFrame = CFrame.new(bottomPos)
	cableDown.CurveSize0, cableDown.CurveSize1 = 0, 0
	Cam.shake = 0
	if glow then
		glow:Destroy()
	end
	return rumble
end

---------------------------------------------------------------------------
-- Séquence complète A -> D. Renvoie la relique posée sur la plateforme.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Animation de lancer du personnage (procédurale : on fait pivoter l'épaule
-- droite et la taille, aucun asset d'animation nécessaire, R15 et R6).
--   1. armé : le bras passe derrière la tête, le buste se tourne et recule
--   2. lancer : le bras fouette vers l'avant, le buste se penche => on lâche l'aimant
--   3. retour en douceur à la pose normale
-- Bloque jusqu'au moment où l'aimant est lâché ; le retour continue en fond.
---------------------------------------------------------------------------
-- Accès à la "C0" d'une articulation : Motor6D classique, ou AnimationConstraint
-- (nouvelles articulations d'avatar Roblox : C0 en lecture seule, on passe par Attachment0)
local function jointAccess(joint: Instance?): ((() -> CFrame)?, ((CFrame) -> ())?)
	if not joint then
		return nil, nil
	end
	if joint:IsA("Motor6D") then
		local motor = joint :: Motor6D
		return function()
			return motor.C0
		end, function(cf: CFrame)
			motor.C0 = cf
		end
	end
	if joint:IsA("AnimationConstraint") and (joint :: any).Attachment0 then
		local attachment = (joint :: any).Attachment0 :: Attachment
		return function()
			return attachment.CFrame
		end, function(cf: CFrame)
			if attachment.Parent then
				attachment.CFrame = cf
			end
		end
	end
	return nil, nil
end

local function playThrowPose(onFrame: (() -> ())?)
	local anim = Config.Anim
	local humanoid = getCharacterParts()
	local character = player.Character
	if not (humanoid and character) then
		return
	end
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local shoulderJoint: Instance?, waistJoint: Instance?
	if r15 then
		local upperArm = character:FindFirstChild("RightUpperArm")
		shoulderJoint = upperArm and upperArm:FindFirstChild("RightShoulder")
		local upperTorso = character:FindFirstChild("UpperTorso")
		waistJoint = upperTorso and upperTorso:FindFirstChild("Waist")
	else
		local torso = character:FindFirstChild("Torso")
		shoulderJoint = torso and torso:FindFirstChild("Right Shoulder")
	end
	local getShoulder, setShoulder = jointAccess(shoulderJoint)
	local getWaist, setWaist = jointAccess(waistJoint)
	if not (getShoulder and setShoulder) then
		return
	end
	local shoulderBase = getShoulder()
	local waistBase = getWaist and getWaist()
	local function apply(armAngle: number, lean: number, twist: number)
		if r15 then
			setShoulder(shoulderBase * CFrame.Angles(armAngle, 0, 0))
		else
			setShoulder(shoulderBase * CFrame.Angles(0, 0, armAngle))
		end
		if setWaist and waistBase then
			setWaist(waistBase * CFrame.Angles(lean, twist, 0))
		end
	end
	local function restore()
		pcall(setShoulder, shoulderBase)
		if setWaist and waistBase then
			pcall(setWaist, waistBase)
		end
	end
	-- angles (radians) : bras autour de l'axe X de l'épaule (R15) / Z (R6) ; taille : (penché, torsion)
	local windArm, windLean, windTwist = math.rad(anim.ThrowWindupArm), math.rad(-12), math.rad(28)
	local throwArm, throwLean, throwTwist = math.rad(anim.ThrowReleaseArm), math.rad(16), math.rad(-22)
	-- Une pose ratée ne doit jamais bloquer le lancer : on remet le personnage d'aplomb et on continue
	local ok, err = pcall(function()
		-- 1. armé
		tweenAlpha(anim.ThrowWindupTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(a)
			apply(windArm * a, windLean * a, windTwist * a)
			if onFrame then
				onFrame()
			end
		end)
		-- 2. lancer (rapide)
		tweenAlpha(anim.ThrowSnapTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
			apply(windArm + (throwArm - windArm) * a, windLean + (throwLean - windLean) * a, windTwist + (throwTwist - windTwist) * a)
			if onFrame then
				onFrame()
			end
		end)
	end)
	if not ok then
		warn("[Client] Pose de lancer ignorée :", err)
		restore()
		return
	end
	-- 3. retour en fond
	task.spawn(function()
		pcall(tweenAlpha, anim.ThrowRecoverTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
			apply(throwArm * (1 - a), throwLean * (1 - a), throwTwist * (1 - a))
		end)
		restore()
	end)
end

---------------------------------------------------------------------------
-- Probabilité qui grimpe pendant la remontée : 1 SUR 1, 1 SUR 2, 1 SUR 5,
-- 1 SUR 10… jusqu'à la vraie valeur, avec un palier de chance qui s'allume.
-- Plus c'est rare, plus il y a d'étapes (et plus la remontée est longue).
---------------------------------------------------------------------------
local startOddsClimb: (odds: number?, duration: number) -> () -> ()
do
	local oddsFrame = create("Frame", {
		Name = "OddsClimb", Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(700, 140), BackgroundTransparency = 1, Visible = false, ZIndex = 40,
	})
	local oddsValue = K.text({
		Name = "Value", Parent = oddsFrame, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(700, 78), Text = "1 SUR 1", MaxTextSize = 66, Outline = 6, ZIndex = 41,
	})
	local oddsTier = K.text({
		Name = "Tier", Parent = oddsFrame, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(700, 52), Text = "", MaxTextSize = 44, Outline = 5, ZIndex = 41, Rotation = -3,
	})
	local oddsGradient = create("UIGradient", { Enabled = false, Parent = oddsTier })
	local oddsToken = 0

	local function oddsTierFor(oneIn: number)
		local found = nil
		for index, tier in ipairs(Config.OddsClimb.Tiers) do
			if oneIn >= tier.min then
				found = index
			end
		end
		return found
	end

	-- Lance le compteur ; renvoie la fonction à appeler à l'arrivée (affiche la vraie valeur)
	function startOddsClimb(odds: number?, duration: number): () -> ()
		oddsToken += 1
		local token = oddsToken
		if typeof(odds) ~= "number" or odds <= 0 then
			return function() end
		end
		local cfg = Config.OddsClimb
		local target = math.max(1, math.floor(1 / odds + 0.5))
		local steps = {}
		local base = 1
		while #steps < 40 do
			local stop = false
			for _, m in ipairs({ 1, 2, 5 }) do
				local value = base * m
				if value >= target then
					stop = true
					break
				end
				table.insert(steps, value)
			end
			if stop then
				break
			end
			base *= 10
		end
		local shownTier = 0
		local rainbowConn: RBXScriptConnection? = nil
		local function show(value: number, final: boolean)
			oddsValue.Text = (Config.FormatOdds(1 / value))
			local tierIndex = oddsTierFor(value)
			local tier = tierIndex and cfg.Tiers[tierIndex]
			oddsValue.TextColor3 = tier and tier.color or UI.White
			if tierIndex and tierIndex ~= shownTier then
				shownTier = tierIndex
				oddsTier.Text = tier.text
				oddsTier.TextColor3 = tier.color
				oddsGradient.Enabled = tier.rainbow == true
				if tier.rainbow and not rainbowConn then
					oddsGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
						ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 140)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
					})
					oddsTier.TextColor3 = UI.White
					rainbowConn = RunService.RenderStepped:Connect(function()
						oddsGradient.Offset = Vector2.new((os.clock() * 0.6) % 2 - 1, 0)
					end)
				end
				K.pop(oddsTier, 1.6, 0.3)
				K.sound("UIDing", 0.7, 0.9 + tierIndex * 0.08)
			end
			K.pop(oddsValue, final and 1.7 or 1.18, final and 0.35 or 0.12)
			K.sound("UIPop", 0.45, math.min(2, 0.8 + #tostring(value) * 0.09))
		end
		oddsTier.Text = ""
		oddsFrame.Visible = true
		oddsFrame.Position = UDim2.new(0.5, 0, 0, 96)
		local finished = false
		task.spawn(function()
			local interval = math.clamp(duration / math.max(1, #steps), cfg.StepMin, cfg.StepMax)
			for _, value in ipairs(steps) do
				if token ~= oddsToken or finished then
					return
				end
				show(value, false)
				task.wait(interval)
			end
		end)
		return function()
			if finished or token ~= oddsToken then
				return
			end
			finished = true
			show(target, true)
			local tierIndex = oddsTierFor(target)
			if tierIndex and tierIndex >= cfg.ShakeFromTier then
				Cam.kick = 0.3
			end
			task.delay(cfg.HoldAfter, function()
				if token ~= oddsToken then
					return
				end
				tween(oddsFrame, 0.35, { Position = UDim2.new(0.5, 0, 0, -160) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				task.delay(0.4, function()
					if token == oddsToken then
						oddsFrame.Visible = false
					end
					if rainbowConn then
						rainbowConn:Disconnect()
					end
				end)
			end)
		end
	end
end

-- Point de chute d'un lancer : landing = Vector2(0..1 = plus ou moins loin, -1..1 = gauche/droite)
-- tiré par le serveur (identique chez tous les joueurs). Renvoie la « poulie » au-dessus.
local function landingPulley(landing: Vector2?): Vector3
	local T = Config.Throw
	local l = typeof(landing) == "Vector2" and landing or Vector2.new(0.5, 0)
	-- le long du canyon (gauche / droite du ponton), puis en travers DANS la faille profonde
	local z = pulleyPart.Position.Z + math.clamp(l.Y, -1, 1) * T.LandingSpread
	local _, axis, _, slot = Config.CanyonAt(z)
	local across = (math.clamp(l.X, 0, 1) * 2 - 1) * math.max(0, slot - T.SlotMargin)
	return Vector3.new(axis + across, pulleyPart.Position.Y, z)
end

---------------------------------------------------------------------------
-- Élan au lasso : le bras se lève, l'aimant tourne au bout de la corde au-dessus
-- de la tête, de plus en plus vite (onSpin(progression 0..1) le place à chaque
-- image), puis le bras fouette vers l'avant. Le retour à la pose normale continue en fond.
---------------------------------------------------------------------------
local function playLassoPose(spinTime: number, onSpin: (number) -> ())
	local anim, T = Config.Anim, Config.Throw
	local humanoid = getCharacterParts()
	local character = player.Character
	local r15 = humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
	local shoulderJoint, waistJoint
	if character then
		if r15 then
			local upperArm = character:FindFirstChild("RightUpperArm")
			shoulderJoint = upperArm and upperArm:FindFirstChild("RightShoulder")
			local upperTorso = character:FindFirstChild("UpperTorso")
			waistJoint = upperTorso and upperTorso:FindFirstChild("Waist")
		else
			local torso = character:FindFirstChild("Torso")
			shoulderJoint = torso and torso:FindFirstChild("Right Shoulder")
		end
	end
	local getShoulder, setShoulder = jointAccess(shoulderJoint)
	local getWaist, setWaist = jointAccess(waistJoint)
	local shoulderBase = getShoulder and getShoulder()
	local waistBase = getWaist and getWaist()
	local function apply(arm: number, lean: number, twist: number)
		if setShoulder and shoulderBase then
			if r15 then
				setShoulder(shoulderBase * CFrame.Angles(arm, 0, 0))
			else
				setShoulder(shoulderBase * CFrame.Angles(0, 0, arm))
			end
		end
		if setWaist and waistBase then
			setWaist(waistBase * CFrame.Angles(lean, twist, 0))
		end
	end
	local function restore()
		if setShoulder and shoulderBase then
			pcall(setShoulder, shoulderBase)
		end
		if setWaist and waistBase then
			pcall(setWaist, waistBase)
		end
	end
	local raise, release = math.rad(T.LassoArm), math.rad(anim.ThrowReleaseArm)
	local lean0, leanRelease, twistRelease = math.rad(-8), math.rad(18), math.rad(-20)
	local ok, err = pcall(function()
		-- 1. le bras se lève
		tweenAlpha(T.LassoRaiseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(a)
			apply(raise * a, lean0 * a, 0)
			onSpin(0)
		end)
		-- 2. l'aimant tourne au-dessus de la tête (le bras accompagne le mouvement)
		local t0 = os.clock()
		while os.clock() - t0 < spinTime do
			local elapsed = os.clock() - t0
			local progress = elapsed / spinTime
			apply(raise + math.sin(elapsed * 13) * math.rad(7), lean0 + math.sin(elapsed * 6) * math.rad(3), math.sin(elapsed * 6.5) * math.rad(12))
			onSpin(progress)
			RunService.RenderStepped:Wait()
		end
		-- 3. le bras fouette vers l'avant : on lâche
		tweenAlpha(anim.ThrowSnapTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
			apply(raise + (release - raise) * a, lean0 + (leanRelease - lean0) * a, twistRelease * a)
			onSpin(1)
		end)
	end)
	if not ok then
		warn("[Client] Élan ignoré :", err)
		restore()
		return
	end
	task.spawn(function()
		pcall(tweenAlpha, anim.ThrowRecoverTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
			apply(release * (1 - a), leanRelease * (1 - a), twistRelease * (1 - a))
		end)
		restore()
	end)
end

local function playThrowSequence(result)
	local anim = Config.Anim
	local zone = Config.Zones[result.zoneIndex]
	local rarity = rarityDef(result.rarityId)
	local _, rarityTier = Config.GetRarity(result.rarityId)
	local _, _, hand = getCharacterParts()

	local magnet, body, magnetAttachment = buildMagnet()
	local T = Config.Throw
	local pierPulley = pulleyPart.Position
	-- l'aimant tombe à un endroit différent à chaque lancer (plus loin, plus près, à gauche, à droite)
	local pulleyPos = landingPulley(result.landing)
	local hangPos = pulleyPos - Vector3.new(0, anim.PulleyHangOffset, 0)
	Cam.column = hangPos
	local function handPos()
		return hand and hand.Position or launchPad.Position + Vector3.new(0, 4, 0)
	end
	body.CFrame = CFrame.new(handPos())

	-- le personnage se tourne vers son point de chute
	local _, root = getCharacterParts()
	if root then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(hangPos.X, root.Position.Y, hangPos.Z))
	end

	-- La corde relie la main à l'aimant dès l'élan
	local handAttachment = create("Attachment", { Name = "RelicCable", Parent = hand or launchPad })
	local throwCable = makeCable(handAttachment, magnetAttachment)

	-- CAMÉRA DE CÔTÉ, à hauteur du joueur : on le voit prendre son élan. Elle tourne
	-- doucement vers l'avant et se rapproche pendant que l'aimant prend de la vitesse.
	local sideStart = os.clock()
	local function playerFrame(): CFrame
		return root and root.CFrame or CFrame.new(launchPad.Position + Vector3.new(0, 3, 0))
	end
	local function sideCamera(): Vector3
		local frame = playerFrame()
		local t = math.clamp((os.clock() - sideStart) / (T.LassoTime + T.LassoRaiseTime), 0, 1)
		local angle = math.rad(T.SideAngle + T.SideOrbit * t)
		local distance = T.SideDistance - T.SideDolly * t
		local direction = frame.LookVector * math.cos(angle) + frame.RightVector * math.sin(angle)
		return frame.Position + direction * distance + Vector3.new(0, T.SideHeight, 0)
	end
	local function playerFocus(): Vector3
		local frame = playerFrame()
		return frame.Position + Vector3.new(0, T.SideFocusHeight, 0) + frame.LookVector * T.SideLookAhead
	end
	cameraStart(sideCamera(), playerFocus)
	Cam.baseFn = sideCamera
	Cam.sharpness = T.SideSharpness
	tween(camera, 0.4, { FieldOfView = T.WindupFOV })

	-- ÉLAN AU LASSO : l'aimant tourne au-dessus de la tête, de plus en plus vite
	local windupGlow = makeEmitter(body, Color3.fromRGB(255, 225, 140), {
		Rate = 20, LightEmission = 1, Speed = NumberRange.new(0.5, 2), Lifetime = NumberRange.new(0.2, 0.5),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
	})
	local lassoTrail = makeDropTrail(body)
	local lastTurn = nil
	playLassoPose(T.LassoTime, function(progress: number)
		local frame = playerFrame()
		local center = handPos() + Vector3.new(0, T.LassoHeight, 0)
		local theta = math.pi / 2 - 2 * math.pi * T.LassoTurns * (1 - progress ^ 1.7) -- finit devant le joueur
		local radius = T.LassoRadius * math.min(1, 0.25 + progress * 3)
		local offset = frame.RightVector * (math.cos(theta) * radius) + frame.LookVector * (math.sin(theta) * radius)
			+ Vector3.new(0, math.sin(theta) * T.LassoTilt, 0)
		body.CFrame = CFrame.new(center + offset) * CFrame.Angles(0, -theta, 0)
		local turn = math.floor(theta / (2 * math.pi))
		if lastTurn and turn ~= lastTurn then
			K.sound("UIWhoosh", 0.3 + 0.45 * progress, 0.7 + 0.6 * progress) -- « vouf » à chaque tour
		end
		lastTurn = turn
		windupGlow.Rate = 20 + 90 * progress
	end)
	lassoTrail.Enabled = false
	Debris:AddItem(lassoTrail, 0.5)
	local startPos = body.Position

	------------------------------------------------------------------
	-- A. LANCER : grand arc -> point de chute, puis chute verticale sur la corde
	------------------------------------------------------------------
	playSound("Throw", body)
	K.sound("UIWhoosh", 0.9, 0.85)
	-- lâcher : gerbe d'étincelles, onde sur le ponton, petite secousse
	burstAt(startPos, Color3.fromRGB(255, 225, 140), 28, {
		LightEmission = 1, Speed = NumberRange.new(8, 22), SpreadAngle = Vector2.new(50, 50), Drag = 3,
		Lifetime = NumberRange.new(0.3, 0.7), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
	})
	shockwave(launchPad.Position + Vector3.new(0, 0.7, 0), Color3.fromRGB(255, 230, 170), 1)
	Cam.kick = 0.35
	windupGlow.Rate = 90 -- traînée d'étincelles pendant le vol
	local flightTrail = makeDropTrail(body)

	local outward = (Vector3.new(hangPos.X, 0, hangPos.Z) - Vector3.new(startPos.X, 0, startPos.Z))
	local flightDistance = outward.Magnitude
	local flightDir = flightDistance > 0.1 and outward.Unit or Vector3.new(-1, 0, 0)
	local sideDir = flightDir:Cross(Vector3.yAxis)
	local flightTime = T.FlightTimeBase + flightDistance * T.FlightTimePerStud
	local control = (startPos + hangPos) / 2 + Vector3.new(0, T.ArcHeightBase + flightDistance * T.ArcHeightPerStud, 0)
	-- la caméra reste un instant sur le côté (on voit le lâcher), puis part derrière l'aimant
	local shoulderAtRelease = sideCamera()
	local flightBlend = 0
	Cam.sharpness = T.FlightSharpness
	Cam.baseFn = function()
		local chase = body.Position - flightDir * T.ChaseBack + Vector3.new(0, T.ChaseUp, 0) + sideDir * T.ChaseSide
		return shoulderAtRelease:Lerp(chase, flightBlend)
	end
	Cam.focus = function()
		return body.Position + flightDir * 3
	end
	tween(camera, flightTime, { FieldOfView = T.FlightFOV }, Enum.EasingStyle.Sine)
	tweenAlpha(flightTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
		flightBlend = math.clamp((a - T.SideHoldShare) / (1 - T.SideHoldShare) * 1.6, 0, 1)
		body.CFrame = CFrame.new(bezier(startPos, control, hangPos, a))
			* CFrame.Angles(a * math.pi * 2 * T.FlightSpins, 0, a * math.pi * 2 * anim.ArcSpins)
		Cam.roll = math.rad(T.FlightRoll) * math.sin(a * math.pi)
	end)
	Cam.roll = 0
	windupGlow.Rate = 0
	Debris:AddItem(windupGlow, 1)
	flightTrail.Enabled = false
	Debris:AddItem(flightTrail, 0.5)

	-- Le câble passe maintenant par la poulie : main -> poulie -> aimant
	-- Lancer à la main : la corde reste tendue de la main du joueur à l'aimant
	-- (plus de poulie ; « Pulley » n'est qu'un repère invisible au-dessus du trou)
	local cableDown = throwCable

	local bottomPos = Vector3.new(hangPos.X, Config.World.RimY - zone.depth, hangPos.Z)
	local descentDuration = (hangPos.Y - bottomPos.Y) / (zone.descentSpeed * cableSpeed(player))

	-- A bis. POURSUITE : la caméra bascule par-dessus le bord et plonge avec
	-- l'aimant. Elle traîne un peu derrière (il accélère et la distance), la
	-- focale s'élargit avec la vitesse et la caméra s'incline légèrement.
	local camCfg = Config.Camera
	Cam.clampToCanyon = true
	Cam.sharpness = camCfg.ChaseSharpness
	Cam.baseFn = function()
		return diveCameraPosition(body.Position, camCfg.ChaseOffset)
	end
	Cam.focus = function()
		return body.Position - Vector3.new(0, camCfg.ChaseLookAhead, 0)
	end
	local trail = makeDropTrail(body)
	local fogY = Config.World.RimY - Config.World.FogStartDepth
	local fogCrossed = false
	tweenAlpha(descentDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
		body.CFrame = CFrame.new(hangPos:Lerp(bottomPos, a)) * CFrame.Angles(0, a * math.pi * 2 * anim.DropSpins, 0)
		if not fogCrossed and body.Position.Y < fogY then
			fogCrossed = true
			burstAt(body.Position, Config.World.FogColorTop, 36, {
				LightEmission = 0.2, Speed = NumberRange.new(6, 16), SpreadAngle = Vector2.new(80, 80), Drag = 2,
				Lifetime = NumberRange.new(0.8, 1.5), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			})
			K.sound("UIWhoosh", 0.5, 0.6)
		end
		local speed = math.sqrt(a) -- Quad In : vitesse proportionnelle au temps écoulé
		camera.FieldOfView = camCfg.ThrowFOV + (camCfg.ChaseFOV - camCfg.ThrowFOV) * speed
		Cam.roll = math.rad(camCfg.ChaseRoll) * speed
	end)
	trail.Enabled = false
	Debris:AddItem(trail, 0.5)
	Cam.roll = 0
	tween(camera, 0.5, { FieldOfView = camCfg.ThrowFOV }, Enum.EasingStyle.Back)

	-- Impact : poussière / éclaboussure + son
	burstAt(bottomPos - Vector3.new(0, 1, 0), zone.impactColor, anim.ImpactParticles, {
		Acceleration = Vector3.new(0, -30, 0), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(60, 60), LightEmission = 0,
	})
	playSound(zone.impactSound, body)
	Cam.kick = 0.3

	------------------------------------------------------------------
	-- B. ATTENTE (tension qui monte si c'est rare)
	------------------------------------------------------------------
	local waitRumble = runWait(rarity, body, cableDown, bottomPos, pulleyPos)
	Remotes.AscentStart:FireServer() -- les autres joueurs voient la remontée commencer

	------------------------------------------------------------------
	-- C / D. REMONTÉE
	------------------------------------------------------------------
	local relic, mud = attachRelic(result.relicId, body, rarity)
	local distance = hangPos.Y - bottomPos.Y
	local baseDuration = ascentBaseDuration(distance, cableSpeed(player))
	-- compteur de probabilité calé sur la durée prévue de la remontée
	local ascentEstimate = baseDuration
	if rarity.isRare then
		local params = rarity.ascent
		ascentEstimate = baseDuration * params.slowFactor + params.chunks * anim.RareChunkPause
			+ (rarity.slowMotion and (anim.SlowMotionFreeze + anim.SlowMotionDuration) or 0)
	end
	local finishOdds = startOddsClimb(result.odds, ascentEstimate * Config.OddsClimb.DurationShare)
	local reel = playSound("Reel", body, nil, true)
	local effects = nil
	local colorCorrection = nil

	local function setHeight(y: number)
		body.CFrame = CFrame.new(hangPos.X, y, hangPos.Z)
	end

	-- La caméra est au fond : elle remonte avec la relique, puis ressort au
	-- bord (ExitOffset) pour la voir jaillir du canyon
	local diving = true
	Cam.baseFn = function()
		return diveCameraPosition(body.Position)
	end
	Cam.focus = function()
		return body.Position
	end
	tween(camera, 0.8, { FieldOfView = Config.Camera.ThrowFOV })
	local exitViewY = hangPos.Y - Config.Camera.ExitViewDistance
	local function updateCameraForHeight(y: number)
		if diving and y >= exitViewY then
			diving = false
			Cam.baseFn = nil
			Cam.basePosition = pulleyPos + Config.Camera.ExitOffset
		end
	end

	if not rarity.isRare then
		-- C. Normale : rapide et régulière
		tweenAlpha(baseDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, function(a)
			local currentY = bottomPos.Y + distance * a
			setHeight(currentY)
			updateCameraForHeight(currentY)
		end)
	else
		-- D. Rare : câble tendu, remontée lente par à-coups, sons en couches
		local params = rarity.ascent
		effects = startRareEffects(body, rarity, rarityTier, bottomPos)
		if waitRumble then -- fondu enchaîné avec les boucles de remontée
			stopLoops({ waitRumble }, anim.LoopFadeIn)
		end
		for _, cable in ipairs({ cableDown }) do
			cable.Width0 = anim.RareCableTenseWidth
			cable.Width1 = anim.RareCableTenseWidth
		end
		Cam.shake = params.shake
		if reel then
			reel.PlaybackSpeed = 1 / math.sqrt(params.slowFactor) -- treuil qui force
		end

		local frozen = false
		local tenseStart = os.clock()
		local tenseConn = RunService.RenderStepped:Connect(function()
			if frozen then
				return
			end
			local jitter = math.sin((os.clock() - tenseStart) * 60) * anim.RareCableJitter
			cableDown.CurveSize0 = jitter
			cableDown.CurveSize1 = -jitter
		end)

		-- Secret : les à-coups s'arrêtent juste sous le bord pour l'arrêt sur image
		local slowDistance = rarity.slowMotion and anim.SlowMotionDistance or 0
		local chunksTargetY = rarity.slowMotion and (Config.World.RimY - slowDistance / 2) or hangPos.Y
		local chunkTravel = (chunksTargetY - bottomPos.Y) / params.chunks
		local chunkDuration = baseDuration * params.slowFactor / params.chunks
		local y = bottomPos.Y
		for index = 1, params.chunks do
			-- silence total juste avant la sortie (Légendaire, Mythique)
			if index == params.chunks and params.silence > 0 then
				task.delay(math.max(0, chunkDuration - params.silence), function()
					stopLoops(effects.loops, anim.SilenceFade)
					if reel then
						reel.Volume = 0
					end
					Cam.shake = 0
				end)
			end
			local fromY = y
			tweenAlpha(chunkDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
				local currentY = fromY + chunkTravel * a
				setHeight(currentY)
				setLoopsProgress(effects.loops, (currentY - bottomPos.Y) / distance)
				updateCameraForHeight(currentY)
			end)
			y = fromY + chunkTravel
			if index < params.chunks then
				Cam.kick = params.shake * anim.RareChunkKick -- à-coup
				task.wait(anim.RareChunkPause)
			end
		end

		-- Secret : ARRÊT SUR IMAGE en silence, puis RALENTI avec battements de cœur
		if rarity.slowMotion then
			frozen = true
			stopLoops(effects.loops, anim.SilenceFade)
			if effects.sting then
				tween(effects.sting, anim.SilenceFade, { Volume = 0 })
			end
			if reel then
				reel.Volume = 0
			end
			Cam.shake = 0
			Cam.baseFn = nil
			Cam.basePosition = pulleyPos + Config.Camera.ExitOffset
			setEffectsTimeScale(effects, anim.SlowMotionParticleScale)
			colorCorrection = create("ColorCorrectionEffect", { Parent = Lighting })
			tween(colorCorrection, 0.2, { Saturation = -0.8, Contrast = 0.3, Brightness = -0.05 })
			tween(camera, anim.SlowMotionFreeze, { FieldOfView = Config.Camera.SlowMotionFOV }, Enum.EasingStyle.Sine)
			task.wait(anim.SlowMotionFreeze)

			local beating = true
			task.spawn(function()
				while beating do
					playSound("Heartbeat")
					Cam.kick = 0.12
					task.wait(anim.SlowMotionDuration / 3)
				end
			end)
			local fromY = y
			tweenAlpha(anim.SlowMotionDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.In, function(a)
				setHeight(fromY + slowDistance * a)
			end)
			beating = false
			y = fromY + slowDistance
			-- dernier jaillissement jusqu'à la poulie
			tweenAlpha(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
				setHeight(y + (hangPos.Y - y) * a)
			end)
			setEffectsTimeScale(effects, 1)
		end
		tenseConn:Disconnect()
		cableDown.CurveSize0, cableDown.CurveSize1 = 0, 0

		--------------------------------------------------------------
		-- SORTIE : explosion sonore, onde de choc, faisceau, flash
		--------------------------------------------------------------
		local arrival = rarity.arrival
		playSounds(arrival.sounds)
		Cam.shake = 0
		Cam.kick = params.shake * anim.ArrivalKick
		-- l'onde part du bord du canyon, au ras du sol (la caméra la voit de dessus)
		shockwave(Vector3.new(hangPos.X, Config.World.RimY + 0.5, hangPos.Z), rarity.color, arrival.shockwaves)
		burstAt(hangPos, rarity.color, params.particleRate, {
			LightEmission = 1, Speed = NumberRange.new(15, 35), SpreadAngle = Vector2.new(180, 180), Drag = 3,
			Lifetime = NumberRange.new(0.8, 1.6),
		})
		if rarity.skyBeam then
			skyBeamAt(hangPos + Vector3.new(0, 3, 0), rarity.color, anim.SkyBeamHold)
		end
		screenFlash(rarity.color)
		if colorCorrection then
			-- les couleurs reviennent d'un coup, sursaturées, puis se calment
			colorCorrection.Saturation = 0.8
			colorCorrection.Contrast = 0.2
			colorCorrection.TintColor = rarity.color:Lerp(UI.White, 0.7)
			tween(camera, 0.5, { FieldOfView = Config.Camera.ThrowFOV }, Enum.EasingStyle.Back)
			tween(colorCorrection, 2, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = UI.White })
			Debris:AddItem(colorCorrection, 2.1)
		end
	end
	if reel then
		reel:Destroy()
	end

	finishOdds() -- la vraie probabilité tombe à la sortie
	-- Petit rebond à l'arrivée
	local bounce = anim.ArrivalBounceHeight
	tweenAlpha(anim.ArrivalBounceDuration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
		setHeight(hangPos.Y + bounce * a)
	end)
	tweenAlpha(anim.ArrivalBounceDuration, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out, function(a)
		setHeight(hangPos.Y + bounce * (1 - a))
	end)
	if rarity.isRare then
		task.wait(anim.ArrivalHold) -- on laisse admirer la relique qui brille
	end

	-- Le treuil ramène l'aimant (et son coffre) jusqu'au ponton
	local pierHang = pierPulley - Vector3.new(0, anim.PulleyHangOffset, 0)
	if (body.Position - pierHang).Magnitude > 2 then
		local fromPos = body.Position
		local reelControl = (fromPos + pierHang) / 2 + Vector3.new(0, T.ReelBackArc, 0)
		Cam.baseFn = nil
		Cam.basePosition = pierPulley + Config.Camera.ExitOffset
		Cam.focus = function()
			return body.Position
		end
		K.sound("UIWhoosh", 0.7, 1.15)
		tweenAlpha(T.ReelBackTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
			body.CFrame = CFrame.new(bezier(fromPos, reelControl, pierHang, a))
		end)
	end

	-- Flash, puis la relique est posée sur la plateforme de nettoyage
	screenFlash(UI.White)
	stopRareEffects(effects)
	for _, weld in ipairs(relic:GetDescendants()) do
		if weld:IsA("WeldConstraint") then
			weld:Destroy()
		end
	end
	for _, part in ipairs(relic:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	local restPosition = restPositionFor(relic)
	relic:PivotTo(CFrame.new(restPosition))
	magnet:Destroy()
	cableDown:Destroy()
	handAttachment:Destroy()

	Cam.clampToCanyon = false
	Remotes.AscentDone:FireServer()
	return relic, mud, restPosition, effects
end

---------------------------------------------------------------------------
-- 5 bis. Lancers des AUTRES joueurs : version allégée (pas de caméra, pas de
-- son "2D", pas de relique). Le serveur relaie : start (lancer), ascent
-- (début de remontée chez le lanceur) et done (relique arrivée / départ).
---------------------------------------------------------------------------
local otherThrows: { [number]: any } = {}

local function endOtherThrow(userId: number)
	local state = otherThrows[userId]
	if not state then
		return
	end
	otherThrows[userId] = nil
	state.ended = true
	for _, item in ipairs(state.extra) do
		item:Destroy()
	end
	state.container:Destroy()
end

-- Durée de remontée estimée, calquée sur celle du lanceur
local function otherAscentDuration(rarity, distance: number, speed: number): number
	local anim = Config.Anim
	local base = ascentBaseDuration(distance, speed)
	if not rarity.isRare then
		return base
	end
	local params = rarity.ascent
	local duration = base * params.slowFactor + (params.chunks - 1) * anim.RareChunkPause
	if rarity.slowMotion then
		duration += anim.SlowMotionFreeze + anim.SlowMotionDuration
	end
	return duration
end

local function runOtherThrow(thrower: Player, state, zoneIndex: number, rarityId: string, landing: Vector2?)
	local anim = Config.Anim
	local zone = Config.Zones[zoneIndex]
	local rarity = rarityDef(rarityId)
	if not (zone and rarity) then
		return
	end
	local container = state.container
	local magnet, body, magnetAttachment = buildMagnet()
	magnet.Parent = container
	local pulleyPos = landingPulley(landing)
	local hangPos = pulleyPos - Vector3.new(0, anim.PulleyHangOffset, 0)
	local character = thrower.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart"))
	local startPos = hand and hand.Position or launchPad.Position + Vector3.new(0, 4, 0)
	body.CFrame = CFrame.new(startPos)

	-- Les câbles sont rangés dans le conteneur (masqué avec lui)
	local function cable(a0: Attachment, a1: Attachment)
		local beam = makeCable(a0, a1)
		beam.Parent = container
		return beam
	end
	local handAttachment = create("Attachment", { Name = "OtherCable", Parent = hand or launchPad })
	table.insert(state.extra, handAttachment)

	-- Arc main -> poulie
	local throwCable = cable(handAttachment, magnetAttachment)
	playSound("Throw", body)
	local control = (startPos + hangPos) / 2 + Vector3.new(0, anim.ArcHeight, 0)
	tweenAlpha(anim.ArcDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(a)
		body.CFrame = CFrame.new(bezier(startPos, control, hangPos, a)) * CFrame.Angles(0, 0, a * math.pi * 2 * anim.ArcSpins)
	end)
	if state.ended then
		return
	end
	-- lancer à la main : la corde reste entre la main et l'aimant (throwCable)

	-- Chute
	local bottomPos = Vector3.new(hangPos.X, Config.World.RimY - zone.depth, hangPos.Z)
	tweenAlpha((hangPos.Y - bottomPos.Y) / (zone.descentSpeed * cableSpeed(thrower)), Enum.EasingStyle.Quad, Enum.EasingDirection.In, function(a)
		body.CFrame = CFrame.new(hangPos:Lerp(bottomPos, a)) * CFrame.Angles(0, a * math.pi * 2 * anim.DropSpins, 0)
	end)
	if state.ended then
		return
	end
	burstAt(bottomPos - Vector3.new(0, 1, 0), zone.impactColor, anim.ImpactParticles, {
		Acceleration = Vector3.new(0, -30, 0), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(60, 60), LightEmission = 0,
	}, container)
	playSound(zone.impactSound, body)

	-- Attente au fond jusqu'au signal du lanceur
	local deadline = os.clock() + Config.Server.AscentTimeout
	while not state.ascending and not state.ended and os.clock() < deadline do
		task.wait()
	end
	if state.ended or not state.ascending then
		return
	end

	-- Remontée (lueur + étincelles si c'est rare : tout le serveur le voit)
	if rarity.isRare then
		local params = rarity.ascent
		create("PointLight", { Color = rarity.color, Brightness = params.lightBrightness, Range = params.lightRange, Shadows = false, Parent = body })
		makeEmitter(body, rarity.color, {
			Rate = params.particleRate / 3, LightEmission = 1, Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		}).Enabled = true
	end
	local distance = hangPos.Y - bottomPos.Y
	tweenAlpha(otherAscentDuration(rarity, distance, cableSpeed(thrower)),Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
		body.CFrame = CFrame.new(hangPos.X, bottomPos.Y + distance * a, hangPos.Z)
	end)
	if state.ended then
		return
	end
	state.arrived = true

	-- Sortie : effets posés dans le dossier commun (ils survivent à la fin du lancer)
	if rarity.isRare then
		burstAt(hangPos, rarity.color, rarity.ascent.particleRate, {
			LightEmission = 1, Speed = NumberRange.new(15, 35), SpreadAngle = Vector2.new(180, 180), Drag = 3,
			Lifetime = NumberRange.new(0.8, 1.6),
		}, otherThrowsFolder)
		shockwave(Vector3.new(hangPos.X, Config.World.RimY + 0.5, hangPos.Z), rarity.color, rarity.arrival.shockwaves, otherThrowsFolder)
		if rarity.skyBeam then
			skyBeamAt(hangPos + Vector3.new(0, 3, 0), rarity.color, anim.SkyBeamHold, otherThrowsFolder)
		end
		playSound("ArrivalBoom", body)
	end
	-- "done" déjà reçu pendant la remontée : on termine maintenant
	task.delay(state.endAfterArrival and 0.6 or 6, function()
		if otherThrows[thrower.UserId] == state then
			endOtherThrow(thrower.UserId)
		end
	end)
end

Remotes:WaitForChild("OtherThrow").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.userId) ~= "number" then
		return
	end
	local userId = payload.userId
	if payload.kind == "start" then
		endOtherThrow(userId)
		local thrower = Players:GetPlayerByUserId(userId)
		if not thrower then
			return
		end
		local container = Instance.new("Model")
		container.Name = "Throw_" .. userId
		container.Parent = otherThrowsFolder
		local state = { container = container, extra = {}, ascending = false, arrived = false, ended = false, endAfterArrival = false }
		otherThrows[userId] = state
		-- filet de sécurité si "done" n'arrive jamais
		task.delay(Config.Server.AscentTimeout + 30, function()
			if otherThrows[userId] == state then
				endOtherThrow(userId)
			end
		end)
		task.spawn(function()
			local ok, err = pcall(runOtherThrow, thrower, state, payload.zoneIndex, payload.rarityId, payload.landing)
			if not ok then
				warn("[Client] Lancer d'un autre joueur interrompu :", err)
				if otherThrows[userId] == state then
					endOtherThrow(userId)
				end
			end
		end)
	elseif payload.kind == "ascent" then
		local state = otherThrows[userId]
		if state then
			state.ascending = true
		end
	elseif payload.kind == "done" then
		local state = otherThrows[userId]
		if state and state.ascending and not state.arrived then
			state.endAfterArrival = true -- on laisse la relique sortir du canyon
		else
			endOtherThrow(userId)
		end
	end
end)

---------------------------------------------------------------------------
-- 6. Nettoyage, révélation, vente / exposition
---------------------------------------------------------------------------
-- Révélation : la relique saute, burst, ondes de choc, sons, faisceau
local function revealRelic(relic: Model, restPosition: Vector3, rarity)
	local anim = Config.Anim
	local reveal = rarity.reveal
	task.spawn(function()
		tweenAlpha(anim.RevealPopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			local height = math.sin(a * math.pi) * anim.RevealPopHeight
			relic:PivotTo(CFrame.new(restPosition + Vector3.new(0, height, 0)) * CFrame.Angles(0, a * math.pi * 4, 0))
		end)
	end)
	burstAt(restPosition, rarity.color, reveal.burst, {
		LightEmission = 1, Speed = NumberRange.new(8, 22), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Lifetime = NumberRange.new(0.8, 1.8),
	})
	if rarity.isRare then
		burstAt(restPosition, UI.White, math.floor(reveal.burst / 3), {
			LightEmission = 1, Speed = NumberRange.new(20, 40), SpreadAngle = Vector2.new(180, 180), Drag = 4,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		})
		screenFlash(rarity.color)
		Cam.kick = 0.4
	end
	shockwave(cleaningPlatform.Position + Vector3.new(0, cleaningPlatform.Size.Y / 2 + 0.2, 0), rarity.color, reveal.shockwaves)
	playSounds(reveal.sounds)
	if rarity.skyBeam then
		skyBeamAt(restPosition + Vector3.new(0, 3, 0), rarity.color, anim.RevealBeamDuration)
	end
end

-- Ouverture du coffre à l'atelier (remplace le nettoyage) : appui maintenu, le
-- coffre tremble, le couvercle s'entrouvre et laisse filtrer la lumière ; au bout,
-- il saute, les pièces jaillissent et la relique sort en tournant.
-- Renvoie (validé par le serveur, modèle de la relique sortie du coffre).
local function runCleaning(haul: Model, glow: Highlight, restPosition: Vector3, rarity)
	local camPos = cleaningPlatform.Position + Config.Camera.CleanOffset
	Cam.baseFn = nil
	Cam.basePosition = camPos
	Cam.focus = function()
		return restPosition
	end
	tween(camera, 0.6, { FieldOfView = Config.Camera.ThrowFOV })

	for _, weld in ipairs(haul:GetDescendants()) do
		if weld:IsA("WeldConstraint") then
			weld:Destroy()
		end
	end
	for _, part in ipairs(haul:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	-- serrure face à la caméra
	local facing = CFrame.lookAt(restPosition, Vector3.new(camPos.X, restPosition.Y, camPos.Z))
	haul:PivotTo(facing)
	setChestLid(haul, 0)

	local _, tier = Config.GetRarity(rarity.id)
	local holder = haul.PrimaryPart or haul:FindFirstChildWhichIsA("BasePart", true)
	local inner = create("PointLight", { Color = rarity.color:Lerp(UI.White, 0.35), Range = 12, Brightness = 0, Shadows = false, Parent = holder })
	local leak = makeEmitter(holder, rarity.color:Lerp(Color3.fromRGB(255, 225, 130), 0.5), {
		Rate = 0, LightEmission = 1, Speed = NumberRange.new(2, 7), Acceleration = Vector3.new(0, 4, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 1.1), SpreadAngle = Vector2.new(60, 60),
	})

	cleanButton.Visible = true
	cleanFill.Size = UDim2.fromScale(0, 1)
	local holding = false
	local progress = 0
	local creak: Sound? = nil

	local function isPress(input: InputObject)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	local conns = {}
	-- MouseButton1Down couvre souris ET tactile
	table.insert(conns, cleanButton.MouseButton1Down:Connect(function()
		holding = true
	end))
	table.insert(conns, cleanButton.MouseButton1Up:Connect(function()
		holding = false
	end))
	-- relâcher n'importe où arrête l'ouverture (doigt qui glisse hors du bouton)
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			holding = false
		end
	end))

	local done = Instance.new("BindableEvent")
	local maxCrack = math.rad(Config.Clean.LidCrackAngle)
	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		local hold = Config.GetCleanDuration(player:GetAttribute("UpgradeClean") or 0)
		if holding then
			progress = math.min(1, progress + dt / hold)
		else
			progress = math.max(0, progress - dt * Config.Clean.ReleaseDecay / hold)
		end
		if holding and not creak then
			creak = playSound("TensionRumble", nil, 0.35, true)
		elseif not holding and creak then
			creak:Destroy()
			creak = nil
		end
		if creak then
			creak.PlaybackSpeed = 0.8 + progress * 0.7
		end
		-- le coffre tremble de plus en plus, le couvercle s'entrouvre
		local t = os.clock()
		local shake = holding and (0.03 + 0.14 * progress) or 0.01 * progress
		local offset = Vector3.new(math.sin(t * 47) * shake, math.abs(math.sin(t * 31)) * shake * 0.6, math.cos(t * 53) * shake)
		haul:PivotTo(facing * CFrame.new(offset) * CFrame.Angles(0, 0, math.sin(t * 38) * shake * 0.35))
		local rattle = holding and math.rad(math.sin(t * 34) * 2.5 * progress) or 0
		setChestLid(haul, maxCrack * progress + math.max(0, rattle))
		inner.Brightness = progress * 4 * (1 + tier * 0.3)
		leak.Rate = holding and (8 + 70 * progress) * (1 + tier * 0.15) or 0
		cleanFill.Size = UDim2.fromScale(progress, 1)
		if progress >= 1 then
			done:Fire()
		end
	end))
	done.Event:Wait()
	for _, conn in ipairs(conns) do
		conn:Disconnect()
	end
	done:Destroy()
	if creak then
		creak:Destroy()
	end
	leak.Rate = 0
	Debris:AddItem(leak, 2)
	cleanButton.Visible = false

	-- Validation serveur (il vérifie que le temps d'ouverture est respecté)
	local validated = false
	for _ = 1, 10 do
		validated = Remotes.CleanDone:InvokeServer()
		if validated then
			break
		end
		task.wait(0.3)
	end

	-- OUVERTURE : le couvercle saute, pièces d'or et lumière
	haul:PivotTo(facing)
	local chestSize = haul:GetExtentsSize()
	task.spawn(function()
		tweenAlpha(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
			setChestLid(haul, maxCrack + (math.rad(Config.Clean.LidOpenAngle) - maxCrack) * a)
		end)
	end)
	K.sound("UIPop", 1, 0.7)
	playSound("ArrivalBoom", nil, 0.6)
	inner.Brightness = 10 + tier * 4
	inner.Range = 18
	tween(inner, 1.5, { Brightness = 3 + tier })
	local chestTop = restPosition + Vector3.new(0, chestSize.Y / 2, 0)
	burstAt(chestTop, Color3.fromRGB(255, 205, 60), 30 + tier * 18, {
		LightEmission = 0.6, Speed = NumberRange.new(10, 24), SpreadAngle = Vector2.new(35, 35), Acceleration = Vector3.new(0, -45, 0),
		Lifetime = NumberRange.new(0.8, 1.4), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.3) }),
	})
	Cam.kick = 0.25

	-- La relique sort du coffre en tournant et s'élève au-dessus
	local relicId = haul:GetAttribute("RelicId")
	local template = RelicsFolder:FindFirstChild(relicId)
	local relic: Model
	if template then
		relic = template:Clone()
	else
		relic = Instance.new("Model")
		create("Part", { Size = Vector3.new(2, 2, 2), Parent = relic })
	end
	for _, part in ipairs(relic:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	local extents = relic:GetExtentsSize()
	local largest = math.max(extents.X, extents.Y, extents.Z)
	if largest > 0 then
		relic:ScaleTo(relic:GetScale() * (chestSize.X * Config.Clean.RelicScaleOfChest) / largest)
	end
	local relicSize = relic:GetExtentsSize()
	create("Highlight", {
		Name = "Mud", FillTransparency = 1, OutlineColor = rarity.color,
		OutlineTransparency = rarity.isRare and 0 or 1, DepthMode = Enum.HighlightDepthMode.Occluded, Parent = relic,
	})
	glow.OutlineTransparency = 1
	local inside = restPosition + Vector3.new(0, -relicSize.Y * 0.2, 0)
	local hover = chestTop + Vector3.new(0, relicSize.Y / 2 + Config.Clean.RelicHoverHeight, 0)
	relic:PivotTo(CFrame.new(inside))
	relic.Parent = haul
	Cam.focus = function()
		return hover
	end
	tweenAlpha(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
		relic:PivotTo(CFrame.new(inside:Lerp(hover, a)) * CFrame.Angles(0, a * math.pi * 2, 0))
	end)
	revealRelic(relic, hover, rarity)
	return validated, relic
end

local function showReveal(result, rarity, relic: Model)
	local anim = Config.Anim
	local reveal = rarity.reveal
	-- Ruban, titre et rayons à la couleur de la rareté
	local light = rarity.color:Lerp(UI.White, 0.35)
	local dark = rarity.color:Lerp(Color3.new(0, 0, 0), 0.35)
	revealName.Text = result.relicName
	ribbon:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(light, dark)
	for _, tail in pairs(ribbonTails) do
		tail:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(dark, dark:Lerp(Color3.new(0, 0, 0), 0.3))
	end
	revealStroke.Color = K.Ink
	for _, ray in ipairs(revealRays:GetDescendants()) do
		if ray:IsA("Frame") and ray.Name == "Ray" then
			ray.BackgroundColor3 = light
		end
	end
	revealGlow.BackgroundColor3 = light
	revealTitle.Visible = true
	revealTitle.Text = reveal.title or (rarity.name:upper() .. " !")
	revealTitle.TextColor3 = reveal.rainbow and UI.White or light
	revealTitleGradient.Enabled = reveal.rainbow == true
	local zone = Config.GetZone(Config.GetRelic(result.relicId) and Config.GetRelic(result.relicId).zone or "")
	revealInfo.Text = ("%s%s%s"):format(result.isNew and "NOUVEAU !  ·  " or "", rarity.name:upper(), zone and ("  ·  " .. zone.name:upper()) or "")
	revealInfo.TextColor3 = result.isNew and Color3.fromRGB(255, 228, 92) or UI.White
	revealOdds.Visible = false -- la probabilité s'affiche pendant la remontée (compteur qui grimpe)
	sellLabel.Text = ("VENDRE +%s $"):format(fmt(result.value))
	local used = player:GetAttribute("MuseumUsed") or 0
	local slots = player:GetAttribute("MuseumSlots") or Config.Museum.Slots
	exposeLabel.Text = ("EXPOSER  %d/%d"):format(used, slots)
	K.recolor(exposeButton, used < slots and C.Teal or C.Grey)

	-- La relique flotte et tourne en 3D au centre
	for _, child in ipairs(revealViewport:GetChildren()) do
		child:Destroy()
	end
	local template = RelicsFolder:FindFirstChild(result.relicId)
	if template then
		K.showcase(revealViewport, template, { speed = 0.9, zoom = 1.6, bob = 0.3, height = 0.25 })
	end

	-- Tout surgit : voile, carte (rebond), titre qui claque, confettis
	revealDim.Visible = true
	revealDim.BackgroundTransparency = 1
	tween(revealDim, 0.3, { BackgroundTransparency = 0.45 })
	revealScale.Scale = 0.2
	revealCard.Visible = true
	tween(revealScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	K.pop(revealTitle, 2.2, 0.35)
	K.sound("UIDing")
	if rarity.isRare then
		K.confetti(gui, rarity.slowMotion and 120 or 60)
	end
	local countTime = anim.RevealCountUpTime * (rarity.isRare and 1 or 0.4)
	task.spawn(function()
		tweenAlpha(countTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			revealValue.Text = ("%s $"):format(fmt(result.value * a))
		end)
		K.punch(revealValue, 0.2)
		local center = revealValue.AbsolutePosition + revealValue.AbsoluteSize / 2
		K.coinBurst(gui, center, rarity.isRare and 18 or 8)
	end)

	-- Contour qui pulse (rare) / arc-en-ciel (Secret)
	local highlight = relic:FindFirstChild("Mud")
	local pulseStart = os.clock()
	local pulseConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - pulseStart
		if rarity.isRare then
			revealStroke.Thickness = 6 + 2 * math.sin(t * 6)
		end
		if reveal.rainbow then
			local hue = Color3.fromHSV((t * 0.4) % 1, 0.8, 1)
			revealStroke.Color = hue
			revealTitleGradient.Rotation = (t * 120) % 360
			if highlight then
				highlight.OutlineColor = hue
			end
		end
	end)

	-- attend Vendre ou Exposer. Un clic ne compte que s'il a COMMENCÉ sur le
	-- bouton après le délai : le doigt qui relâche le bouton "Nettoyer" juste
	-- en dessous ne vend/expose donc jamais par erreur.
	local readyAt = os.clock() + anim.RevealButtonsDelay
	local armed = { [sellButton] = false, [exposeButton] = false }
	local armConns = {}
	for button in pairs(armed) do
		table.insert(armConns, button.MouseButton1Down:Connect(function()
			armed[button] = os.clock() >= readyAt
		end))
	end
	local choice = Instance.new("BindableEvent")
	local pending = false
	local sellConn = sellButton.Activated:Connect(function()
		if pending or not armed[sellButton] then return end
		pending = true
		local ok, gained = Remotes.Sell:InvokeServer()
		if ok then
			K.sound("UIBuy")
			local center = sellButton.AbsolutePosition + sellButton.AbsoluteSize / 2
			K.coinBurst(gui, center, 20)
			choice:Fire()
		end
		pending = false
	end)
	local exposeConn = exposeButton.Activated:Connect(function()
		if pending or not armed[exposeButton] then return end
		pending = true
		local ok, message = Remotes.Expose:InvokeServer()
		toast(message, ok and UI.Blue or UI.Red)
		if ok then
			choice:Fire()
		end
		pending = false
	end)
	choice.Event:Wait()
	sellConn:Disconnect()
	exposeConn:Disconnect()
	pulseConn:Disconnect()
	for _, conn in ipairs(armConns) do
		conn:Disconnect()
	end
	choice:Destroy()
	revealStroke.Thickness = 6
	revealCard.Visible = false
	revealDim.Visible = false
end

local nextAutoThrow = 0 -- la jauge ne repart pas avant ce moment

local function finishThrow()
	cameraStop()
	setCinematic(false)
	lockCharacter(false)
	setOthersHidden(false)
	actionPanel.Visible = true
	nextAutoThrow = os.clock() + Config.ThrowZone.RestartDelay
	busy = false
end

-- La relique quitte la plateforme (vendue ou partie au musée)
local function fadeOutRelic(relic: Model)
	for _, part in ipairs(relic:GetDescendants()) do
		if part:IsA("BasePart") then
			tween(part, 0.4, { Transparency = 1 })
		end
	end
	Debris:AddItem(relic, 0.5)
end

local function startThrow()
	if busy then
		return
	end
	busy = true

	local gaugePosition = runGauge()
	if not gaugePosition then
		busy = false -- sorti de la zone (ou bouton « Partir ») pendant la jauge
		return
	end
	setCinematic(true) -- plus aucun bouton jusqu'à l'arrivée de la relique
	lockCharacter(true)
	setOthersHidden(true)
	local ok, result = pcall(function()
		return Remotes.RequestThrow:InvokeServer(gaugePosition)
	end)
	if not ok or not result or not result.ok then
		toast(result and result.reason or "Erreur réseau", UI.Red)
		finishThrow()
		return
	end

	local zone = Config.Zones[result.zoneIndex]
	toast(("%sZone %d/%d : %s  (puissance %s)"):format(result.perfect and "⭐ PARFAIT ! " or "", result.zoneIndex, #Config.Zones, zone.name, fmt(result.effectivePower)))

	local rarity = rarityDef(result.rarityId)
	local success, relic, mud, restPosition = pcall(playThrowSequence, result)
	if not success then
		warn("[Client] Animation interrompue :", relic)
		Remotes.AscentDone:FireServer()
		finishThrow()
		return
	end
	setCinematic(false) -- la relique est sur la plateforme : retour de l'interface
	actionPanel.Visible = false -- (les actions reviennent après Vendre / Exposer)
	local _, shown = runCleaning(relic, mud, restPosition, rarity)
	showReveal(result, rarity, shown or relic)
	fadeOutRelic(relic)
	finishThrow()
end

-- Relique laissée en plan à la dernière session : elle attend, boueuse,
-- sur la plateforme de nettoyage
local function resumePending(result)
	while busy do
		task.wait(0.2)
	end
	busy = true
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart")
	actionPanel.Visible = false
	lockCharacter(true)
	setOthersHidden(true)

	local rarity = rarityDef(result.rarityId)
	local relic, mud = cloneMuddyRelic(result.relicId, rarity)
	for _, part in ipairs(relic:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	local restPosition = restPositionFor(relic)
	relic:PivotTo(CFrame.new(restPosition))
	relic.Parent = workspace
	cameraStart(cleaningPlatform.Position + Config.Camera.CleanOffset, function()
		return restPosition
	end)
	toast("🗝 Ton coffre t'attendait !", UI.Orange)

	local _, shown = runCleaning(relic, mud, restPosition, rarity)
	showReveal(result, rarity, shown or relic)
	fadeOutRelic(relic)
	finishThrow()
end

---------------------------------------------------------------------------
-- 7. HUD, boutons, annonces, debug
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Boutique d'améliorations : grille de grosses cartes colorées.
-- Chaque carte : rayons qui tournent + objet 3D (Blender) qui tourne,
-- étincelles, crans de niveau, effet, prix dans une pastille verte.
-- Survol = la carte grossit et l'objet accélère ; achat = pluie de pièces.
---------------------------------------------------------------------------
local function upgradeEffect(id: string, level: number): string
	if id == "Magnet" then
		return ("x%.2f"):format(Config.GetLuckMultiplier(level))
	elseif id == "Cable" then
		return ("x%.1f"):format(Config.GetSpeedMultiplier(level))
	elseif id == "Clean" then
		return ("%.2f s"):format(Config.GetCleanDuration(level))
	elseif id == "Museum" then
		return ("%d socles"):format(Config.GetMuseumSlots(level))
	end
	return ""
end

local CARD_COLORS = { Power = C.Red, Magnet = C.Blue, Cable = C.Orange, Clean = C.Teal, Museum = C.Purple }
local CARD_TITLES = { Power = "PUISSANCE", Magnet = "AIMANT", Cable = "CÂBLE", Clean = "OUVERTURE", Museum = "MUSÉE" }
local shopCards = {}

-- en-tête : onglets + solde
do
	local tabs = create("Frame", { Name = "Tabs", Parent = shopHeader, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 300, 0.5, 0), Size = UDim2.fromOffset(420, 46), BackgroundTransparency = 1, ZIndex = 24 },
		{ create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }) })
	for i, def in ipairs({ { "AMÉLIORATIONS", C.Teal, true }, { "BOOSTS", C.Gold, false }, { "TRÉSORS", C.Purple, false } }) do
		local tab = create("Frame", {
			Name = def[1], Parent = tabs, Size = UDim2.fromOffset(i == 1 and 190 or 104, 42), BackgroundColor3 = K.White, LayoutOrder = i, ZIndex = 24,
			BackgroundTransparency = def[3] and 0 or 0.15,
		}, { K.round(), K.stroke(4), K.gradient(def[2][1], def[2][2]) })
		K.text({ Parent = tab, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -16, 0.66, 0), Text = def[1], MaxTextSize = 20, ZIndex = 25 })
		if not def[3] then
			K.text({ Parent = tab, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(80, 18), Text = "BIENTÔT", MaxTextSize = 13, TextColor3 = Color3.fromRGB(255, 228, 92), Rotation = 6, ZIndex = 26 })
		end
	end
end
local wallet = create("Frame", {
	Name = "Wallet", Parent = shopHeader, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0), Size = UDim2.fromOffset(150, 46),
	BackgroundColor3 = K.Ink, BackgroundTransparency = 0.45, ZIndex = 24,
}, { K.round() })
create("Frame", { Name = "Coin", Parent = wallet, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = K.White, ZIndex = 25 },
	{ K.round(), K.stroke(3), K.gradient(C.Gold[1], C.Gold[2]) })
local walletLabel = K.text({ Name = "Amount", Parent = wallet, Position = UDim2.fromOffset(46, 6), Size = UDim2.new(1, -54, 1, -12), Text = "0", MaxTextSize = 26, TextColor3 = Color3.fromRGB(255, 228, 92), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 25 })

-- la liste devient une grille de cartes
shopList:FindFirstChildOfClass("UIListLayout"):Destroy()
create("UIGridLayout", {
	Parent = shopList, CellSize = UDim2.fromOffset(164, 318), CellPadding = UDim2.fromOffset(12, 12),
	HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
})
create("UIPadding", { Parent = shopList, PaddingTop = UDim.new(0, 14) })
-- astuce en bas
local shopTip = create("Frame", {
	Name = "Tip", Parent = shopPanel, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(620, 40),
	BackgroundColor3 = K.White, ZIndex = 24,
}, { K.round(), K.stroke(4), K.gradient(C.Wood[1], C.Wood[2]) })
K.text({ Parent = shopTip, Position = UDim2.fromOffset(14, 7), Size = UDim2.fromOffset(90, 26), Text = "ASTUCE", MaxTextSize = 20, TextColor3 = Color3.fromRGB(255, 228, 92), ZIndex = 25 })
create("TextLabel", {
	Parent = shopTip, Position = UDim2.fromOffset(110, 6), Size = UDim2.new(1, -124, 1, -12), BackgroundTransparency = 1, Font = K.BodyFont, TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 243, 214), TextXAlignment = Enum.TextXAlignment.Left, Text = "Le Câble raccourcit chaque lancer : plus de reliques par minute !", ZIndex = 25,
}, { textMax(18) })

local function refreshShop()
	local money = player:GetAttribute("Money") or 0
	local power = player:GetAttribute("Power") or 0
	walletLabel.Text = fmt(money)
	local anyAffordable = false
	for id, card in pairs(shopCards) do
		local def = Config.Upgrades[id]
		local cost: number?
		local level = 0
		if id == "Power" then
			cost = Config.GetPowerCost(power)
			card.effect.Text = ("+%s"):format(fmt(Config.GetPowerGain(power)))
			card.pips.Visible = false
		else
			level = player:GetAttribute("Upgrade" .. id) or 0
			cost = Config.GetUpgradeCost(id, level)
			card.effect.Text = cost and ("%s → %s"):format(upgradeEffect(id, level), upgradeEffect(id, level + 1)) or upgradeEffect(id, level)
			for i, pip in ipairs(card.pipList) do
				pip.Visible = i <= def.maxLevel
				pip.BackgroundColor3 = i <= level and Color3.fromRGB(255, 228, 92) or K.White
				pip.BackgroundTransparency = i <= level and 0 or 0.6
			end
		end
		local affordable = cost ~= nil and money >= cost
		anyAffordable = anyAffordable or (affordable and id ~= "Power")
		card.priceLabel.Text = cost and fmt(cost) or "MAX"
		K.recolor(card.price, cost == nil and C.Gold or (affordable and C.Green or C.Grey))
		card.stamp.Visible = cost == nil
		card.badge.Visible = affordable and id ~= "Power"
		card.shine.enabled = affordable
	end
	shopBadge.Visible = anyAffordable
end

local function buildCard(id: string, order: number)
	local colors = CARD_COLORS[id] or C.Blue
	local cell = create("Frame", { Name = id, Parent = shopList, BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 22 })
	local card = create("Frame", {
		Name = "Card", Parent = cell, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(160, 300),
		BackgroundTransparency = 1, ZIndex = 22,
	})
	local cardScale = create("UIScale", { Parent = card })
	create("Frame", { Name = "Shadow", Parent = card, Position = UDim2.fromOffset(0, 7), Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.Ink, BackgroundTransparency = 0.1, ZIndex = 22 }, { K.corner(22) })
	local face = create("Frame", { Name = "Face", Parent = card, Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.White, ZIndex = 23, ClipsDescendants = true },
		{ K.corner(22), K.stroke(5), K.gradient(colors[1], colors[2]) })
	create("Frame", { Name = "Gloss", Parent = face, Size = UDim2.new(1, 0, 0, 80), BackgroundColor3 = K.White, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 24 },
		{ create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.3, 1) }) })
	local raysHolder = create("Frame", { Name = "RaysHolder", Parent = face, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.fromOffset(156, 156), BackgroundTransparency = 1, ZIndex = 24 })
	K.rays(raysHolder, K.White, 14, 20, 0.5)
	local viewport = create("ViewportFrame", {
		Name = "Showcase", Parent = face, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.fromOffset(140, 140),
		BackgroundTransparency = 1, ZIndex = 25,
	})
	local showcase = uiModel(id) and K.showcase(viewport, uiModel(id) :: Model, { speed = 0.7, zoom = 1.7, bob = 0.25 })
	K.sparkles(face, { { 0.14, 0.1, 14 }, { 0.84, 0.16, 11 }, { 0.8, 0.42, 9 } }, Color3.fromRGB(255, 243, 160), 26)
	K.text({ Name = "Name", Parent = face, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 164), Size = UDim2.new(1, -12, 0, 30), Text = CARD_TITLES[id] or id, MaxTextSize = 24, ZIndex = 27 })
	local pips = create("Frame", { Name = "Pips", Parent = face, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 200), Size = UDim2.fromOffset(140, 10), BackgroundTransparency = 1, ZIndex = 27 },
		{ create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	local pipList = {}
	for i = 1, 10 do
		pipList[i] = create("Frame", { Name = "Pip", Parent = pips, Size = UDim2.fromOffset(11, 9), BackgroundColor3 = K.White, BackgroundTransparency = 0.6, LayoutOrder = i, ZIndex = 27 },
			{ K.corner(3), K.stroke(1.5) })
	end
	local effect = K.text({ Name = "Effect", Parent = face, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 216), Size = UDim2.new(1, -14, 0, 24), Text = "", MaxTextSize = 18, Font = K.BodyFont, Outline = 2, ZIndex = 27 })
	local shine = K.shine(face, 3)
	local price, priceLabel = K.button({
		Name = "Price", Parent = card, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 250), Size = UDim2.fromOffset(136, 40),
		Colors = C.Green, Text = "", MaxTextSize = 22, TextPosition = UDim2.new(0.58, 0, 0.5, 0), TextSize = UDim2.new(0.66, 0, 0.66, 0),
		Radius = 16, Stroke = 4, Depth = 4, Shine = false, ZIndex = 28,
		Animate = { clickSound = false, onHover = function(on)
			if showcase then showcase.hover = on end
			K.tween(cardScale, 0.18, { Scale = on and 1.05 or 1 }, Enum.EasingStyle.Back)
			card.Rotation = on and -2 or 0
		end },
	})
	create("Frame", { Name = "Coin", Parent = price, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = K.White, ZIndex = 33 },
		{ K.round(), K.stroke(2), K.gradient(C.Gold[1], C.Gold[2]) })
	local stamp = K.text({ Name = "Stamp", Parent = card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(130, 46), Text = "MAX", MaxTextSize = 40, Outline = 5, TextColor3 = Color3.fromRGB(255, 228, 92), Rotation = -14, ZIndex = 34, Visible = false })
	local badge = create("Frame", { Name = "Badge", Parent = card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = K.White, ZIndex = 34, Visible = false },
		{ K.round(), K.stroke(4), K.gradient(C.Red[1], C.Red[2]) })
	K.text({ Parent = badge, Size = UDim2.fromScale(1, 1), Text = "!", MaxTextSize = 24, ZIndex = 35 })
	shopCards[id] = { card = card, effect = effect, pips = pips, pipList = pipList, price = price, priceLabel = priceLabel, stamp = stamp, badge = badge, shine = shine }

	local pending = false
	price.Activated:Connect(function()
		if pending then
			return
		end
		pending = true
		local ok, message = Remotes.BuyUpgrade:InvokeServer(id)
		if ok then
			K.sound("UIBuy")
			local center = price.AbsolutePosition + price.AbsoluteSize / 2
			K.coinBurst(gui, center, 14)
			K.punch(card, 0.12)
			if showcase then
				showcase.boost = 1 -- bond + tour rapide
			end
			K.floatText(gui, message, Color3.fromRGB(140, 240, 122), UDim2.fromOffset(center.X, center.Y - 60), 30)
		else
			K.sound("UIError")
			K.shake(card)
			toast(message, UI.Red)
		end
		pending = false
	end)
end

for order, id in ipairs(Config.UpgradeOrder) do
	buildCard(id, order)
end

---------------------------------------------------------------------------
-- Livre de collection : 25 zones x 10 reliques, inconnues en « ??? »
---------------------------------------------------------------------------
local collection: { [string]: boolean } = {}
local collectionLoaded = false
local bookBuilt = false
local bookCells: { [string]: TextLabel } = {}
local bookHeaders: { [string]: TextLabel } = {}

-- Sections du livre : les 25 zones + « Cosmos » (Divin / Cosmique, toutes zones)
local bookZones = table.clone(Config.Zones)
table.insert(bookZones, { id = "Cosmos", name = "Cosmos · Divin & Cosmique (toutes zones)" })
local zoneItemCount: { [string]: number } = {}
for _, relic in ipairs(Config.Relics) do
	zoneItemCount[relic.zone] = (zoneItemCount[relic.zone] or 0) + 1
end

local function buildBook()
	bookBuilt = true
	for zoneIndex, zone in ipairs(bookZones) do
		local section = create("Frame", {
			Name = zone.id, Parent = bookList, Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, LayoutOrder = zoneIndex, ZIndex = 22,
		}, { create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
		bookHeaders[zone.id] = create("TextLabel", {
			Parent = section, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Font = UI.Font, TextScaled = true,
			TextColor3 = Color3.fromRGB(74, 46, 26), TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, ZIndex = 23,
		}, { textMax(28) })
		local grid = create("Frame", {
			Parent = section, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			LayoutOrder = 1, ZIndex = 22,
		}, { create("UIGridLayout", {
			CellSize = UDim2.new(0.19, 0, 0, 40), CellPadding = UDim2.new(0.0125, 0, 0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
		}) })
		local order = 0
		for _, relic in ipairs(Config.Relics) do
			if relic.zone == zone.id then
				order += 1
				bookCells[relic.id] = create("TextLabel", {
					Name = relic.id, Parent = grid, LayoutOrder = order, BackgroundColor3 = UI.Dark, Font = UI.Font,
					TextScaled = true, TextColor3 = UI.White, TextStrokeTransparency = 0.3, Text = "???", ZIndex = 23,
				}, { corner(), textMax(18), create("UIPadding", {
					PaddingLeft = UDim.new(0.05, 0), PaddingRight = UDim.new(0.05, 0), PaddingTop = UDim.new(0.1, 0), PaddingBottom = UDim.new(0.1, 0),
				}) })
			end
		end
	end
end

local function refreshBook()
	if not bookBuilt then
		return
	end
	local total = 0
	local perZone: { [string]: number } = {}
	for _, relic in ipairs(Config.Relics) do
		local cell = bookCells[relic.id]
		local found = collection[relic.id] == true
		if found then
			total += 1
			perZone[relic.zone] = (perZone[relic.zone] or 0) + 1
		end
		local rarity = rarityDef(relic.rarity)
		cell.Text = found and relic.name or "???"
		cell.BackgroundColor3 = found and rarity.color:Lerp(UI.Dark, 0.55) or UI.Dark
		cell.TextColor3 = found and UI.White or rarity.color:Lerp(UI.Dark, 0.3)
	end
	local power = player:GetAttribute("Power") or 0
	for zoneIndex, zone in ipairs(bookZones) do
		local count = perZone[zone.id] or 0
		local totalInZone = zoneItemCount[zone.id] or 0
		local complete = count >= totalInZone and totalInZone > 0
		local locked = zone.requiredPower ~= nil and zoneIndex > 1 and zone.requiredPower > power * Config.Gauge.PerfectBonus
		local prefix = zone.requiredPower and (zoneIndex .. ". ") or "✨ "
		bookHeaders[zone.id].Text = ("%s%s%s  (%d/%d)%s"):format(locked and "🔒 " or "", prefix, zone.name, count, totalInZone,
			(complete and zone.requiredPower) and ("  ✅ +%d %%"):format(math.floor(Config.Collection.ZoneBonus * 100 + 0.5)) or "")
		bookHeaders[zone.id].TextColor3 = complete and Color3.fromRGB(196, 132, 18) or (locked and Color3.fromRGB(150, 140, 130) or Color3.fromRGB(74, 46, 26))
	end
	bookTitle.Text = ("COLLECTION %d/%d"):format(total, #Config.Relics)
end

local function openBook()
	if not bookBuilt then
		buildBook()
	end
	if not collectionLoaded then
		local ok, ids = pcall(function()
			return Remotes.GetCollection:InvokeServer()
		end)
		if ok and typeof(ids) == "table" then
			for _, id in ipairs(ids) do
				collection[id] = true
			end
			collectionLoaded = true
		end
	end
	refreshBook()
	bookBadge.Visible = false
	bookWindow.Visible = true
end

local function toggleShop()
	bookWindow.Visible = false
	shopWindow.Visible = not shopWindow.Visible
	refreshShop()
end
shopButton.Activated:Connect(toggleShop)
moneyPlus.Activated:Connect(function()
	if not shopWindow.Visible then
		toggleShop()
	end
end)
bookButton.Activated:Connect(function()
	shopWindow.Visible = false
	if bookWindow.Visible then
		bookWindow.Visible = false
	else
		openBook()
	end
end)

-- Nouvelle relique trouvée / zone complétée (envoyé par le serveur au nettoyage)
Remotes.CollectionUpdate.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end
	collection[data.relicId] = true
	refreshBook()
	bookBadgeText.Text = "NOUVEAU"
	bookBadge.Visible = not bookWindow.Visible
	task.delay(1.5, function() -- après le "pop" de la révélation
		toast(("📖 Nouvelle relique ! (%d/%d)"):format(data.count or 0, data.total or #Config.Relics), UI.Green)
	end)
	if data.zoneCompleted then
		task.delay(3, function()
			announceLabel.Text = ("🏆 Zone complète : %s ! +%d %% de valeur"):format(data.zoneCompleted, math.floor(Config.Collection.ZoneBonus * 100 + 0.5))
			announceLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
			announceLabel.Visible = true
			task.delay(Config.Server.AnnouncementDuration, function()
				announceLabel.Visible = false
			end)
		end)
	end
end)

-- Compteurs animés : le chiffre défile vers la nouvelle valeur ; un gain
-- notable fait « sauter » l'icône et s'envoler un « +X »
local shownMoney, shownPower = nil, nil
local moneyTween = 0
local function animateCounter(label: TextLabel, from: number, to: number, suffix: string)
	moneyTween += 1
	local token = moneyTween
	task.spawn(function()
		tweenAlpha(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			if token == moneyTween then
				label.Text = fmt(from + (to - from) * a) .. suffix
			end
		end)
	end)
end
local function refreshHud()
	local money = player:GetAttribute("Money") or 0
	local power = player:GetAttribute("Power") or 0
	if shownMoney == nil or money < shownMoney or money - shownMoney < 1 then
		moneyLabel.Text = fmt(money)
	else
		local gain = money - shownMoney
		animateCounter(moneyLabel, shownMoney, money, "")
		if gain >= math.max(10, shownMoney * 0.01) then -- (le revenu du musée ne déclenche pas d'effet)
			K.punch(moneyIcon, 0.25)
			local at = moneyLabel.AbsolutePosition + moneyLabel.AbsoluteSize / 2
			K.floatText(gui, "+" .. fmt(gain), Color3.fromRGB(140, 240, 122), UDim2.fromOffset(at.X + 40, at.Y + 30), 28)
		end
	end
	shownMoney = money
	if shownPower and power > shownPower then
		K.punch(powerIcon, 0.2)
	end
	powerLabel.Text = fmt(power)
	shownPower = power
	refreshShop() -- garde aussi la pastille « ! » du bouton Boutique à jour
end
for _, attribute in ipairs({ "Money", "Power", "PowerCost", "UpgradeMagnet", "UpgradeCable", "UpgradeClean", "UpgradeMuseum" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshHud)
end
refreshHud()

-- Lancer automatique : entrer dans la zone (ou y rester après une relique) lance la jauge
local wasInZone = false
RunService.Heartbeat:Connect(function()
	local inZone = isInThrowZone()
	if inZone and not wasInZone then
		nextAutoThrow = math.max(nextAutoThrow, os.clock() + Config.ThrowZone.EnterDelay)
	end
	wasInZone = inZone
	if waitForExit and not inZone then
		waitForExit = false
	end
	if inZone and not busy and not waitForExit and os.clock() >= nextAutoThrow
		and player:GetAttribute("DataLoaded") and not player:GetAttribute("HasPending") then
		task.spawn(startThrow)
	end
end)

-- "Mon musée" : téléportation devant l'entrée de son musée
museumButton.Activated:Connect(function()
	-- la jauge tourne (joueur resté dans la zone) : on l'annule pour partir
	if cancelGauge then
		cancelGauge()
		local deadline = os.clock() + 0.5
		while busy and os.clock() < deadline do
			task.wait()
		end
	end
	if busy then
		return
	end
	if player:GetAttribute("OnBench") then
		Remotes.BenchLeave:FireServer()
		local deadline = os.clock() + 1
		while player:GetAttribute("OnBench") and os.clock() < deadline do
			task.wait()
		end
	end
	local index = player:GetAttribute("MuseumIndex") or 0
	local museums = world:FindFirstChild("Museums")
	local museum = museums and museums:FindFirstChild("Museum" .. index)
	local entrance = museum and museum:FindFirstChild("Entrance")
	local _, root = getCharacterParts()
	if not (entrance and root) then
		toast("Aucun musée attribué", UI.Red)
		return
	end
	local lookAt = museum:GetPivot().Position
	root.CFrame = CFrame.lookAt(entrance.Position, Vector3.new(lookAt.X, entrance.Position.Y, lookAt.Z))
end)

Remotes.RestorePending.OnClientEvent:Connect(function(result)
	task.spawn(resumePending, result)
end)


-- Annonces serveur (Légendaire et plus)
local announceToken = 0
Remotes.Announce.OnClientEvent:Connect(function(data)
	local rarity = rarityDef(data.rarityId)
	if not rarity then
		return
	end
	announceToken += 1
	local token = announceToken
	local isSecret = rarity.slowMotion
	local oddsText = ""
	if typeof(data.odds) == "number" then
		oddsText = "  ·  " .. (Config.FormatOdds(data.odds))
	end
	if isSecret then
		announceLabel.Text = ("✨ %s !!! %s a remonté %s%s ✨"):format(rarity.name:upper(), data.playerName, data.relicName, oddsText)
	else
		announceLabel.Text = ("🎉 %s a remonté %s (%s)%s !"):format(data.playerName, data.relicName, rarity.name, oddsText)
	end
	announceLabel.TextColor3 = rarity.color
	announceLabel.Visible = true
	announceLabel.Size = UDim2.fromScale(0.6, 0.06)
	tween(announceLabel, 0.4, { Size = UDim2.fromScale(isSecret and 0.95 or 0.9, isSecret and 0.12 or 0.09) }, Enum.EasingStyle.Back)
	task.delay(Config.Server.AnnouncementDuration, function()
		if token == announceToken then
			announceLabel.Visible = false
		end
	end)
end)

Remotes.Notify.OnClientEvent:Connect(function(message)
	toast(message)
end)

---------------------------------------------------------------------------
-- Banc de développé couché (un devant chaque musée, voir BenchService)
--   Allongé sur SON banc : chaque tap / Espace = une répétition (remote Train,
--   cadence vérifiée par le serveur). Bouton « Se lever » pour partir.
--   Bras + barre animés localement pour TOUS les bancs à chaque changement de
--   l'attribut « Reps » (incrémenté par le serveur) : chacun voit les autres soulever.
---------------------------------------------------------------------------
do
	local BenchCfg = Config.Bench
	local BenchLeaveEvent = Remotes:WaitForChild("BenchLeave")

	local benchHint = K.text({
		Name = "BenchHint", Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(600, 46), Text = "TOUCHE L'ÉCRAN POUR SOULEVER !", MaxTextSize = 34, ZIndex = 14,
	})
	benchHint.Visible = false
	local benchTap = create("TextButton", {
		Name = "BenchTap", Parent = gui, Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Text = "", Visible = false, ZIndex = 0,
	})
	local benchLeave = K.button({
		Name = "BenchLeave", Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34),
		Size = UDim2.fromOffset(210, 58), Colors = C.Wood, Text = "SE LEVER", MaxTextSize = 26, Shine = false, ZIndex = 16,
	})
	benchLeave.Visible = false

	-- Bras d'un personnage allongé (R15 : épaules + coudes ; Motor6D ou AnimationConstraint)
	local function liftJoints(character: Model)
		local joints = {}
		for _, side in ipairs({ { "Right", 1 }, { "Left", -1 } }) do
			local upper = character:FindFirstChild(side[1] .. "UpperArm")
			local lower = character:FindFirstChild(side[1] .. "LowerArm")
			local getS, setS = jointAccess(upper and upper:FindFirstChild(side[1] .. "Shoulder"))
			local getE, setE = jointAccess(lower and lower:FindFirstChild(side[1] .. "Elbow"))
			if getS and setS then
				table.insert(joints, { sign = side[2], setS = setS, baseS = getS(), setE = setE, baseE = getE and getE() })
			end
		end
		return joints
	end

	type BenchState = { token: number, joints: { any }? }
	local benchStates: { [Model]: BenchState } = {}

	-- a = 0 : bras tendus vers le ciel, barre en haut ; a = 1 : barre sur la poitrine
	local function applyLift(bench: Model, state: BenchState, a: number)
		local theta = math.rad(BenchCfg.RepArmAngle) * a
		for _, j in ipairs(state.joints or {}) do
			pcall(function()
				-- bras levés « devant » (= vers le ciel une fois allongé), écartés de theta,
				-- avant-bras repliés pour rester verticaux sous la barre
				j.setS(j.baseS * CFrame.Angles(0, -j.sign * theta, 0) * CFrame.Angles(math.rad(90), 0, 0))
				if j.setE and j.baseE then
					j.setE(j.baseE * CFrame.Angles(0, 0, -j.sign * theta))
				end
			end)
		end
		local bar = bench:FindFirstChild("Barbell") :: Model?
		local rest: CFrame? = bench:GetAttribute("BarRest")
		if bar and rest then
			bar:PivotTo(rest - Vector3.new(0, BenchCfg.RepDrop * a, 0))
		end
	end

	local function restoreLift(bench: Model, state: BenchState)
		for _, j in ipairs(state.joints or {}) do
			pcall(j.setS, j.baseS)
			if j.setE and j.baseE then
				pcall(j.setE, j.baseE)
			end
		end
		state.joints = nil
		local bar = bench:FindFirstChild("Barbell") :: Model?
		local rest: CFrame? = bench:GetAttribute("BarRest")
		if bar and rest then
			bar:PivotTo(rest)
		end
	end

	local function animateRep(bench: Model)
		local state = benchStates[bench]
		if not (state and state.joints) then
			return
		end
		state.token += 1
		local token = state.token
		task.spawn(function()
			tweenAlpha(BenchCfg.RepDownTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, function(a)
				if state.token == token and state.joints then
					applyLift(bench, state, a)
				end
			end)
			tweenAlpha(BenchCfg.RepUpTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
				if state.token == token and state.joints then
					applyLift(bench, state, 1 - a)
				end
			end)
		end)
	end

	local function watchBench(bench: Model, plotIndex: number)
		local state: BenchState = { token = 0, joints = nil }
		benchStates[bench] = state
		local function onLifter()
			state.token += 1
			restoreLift(bench, state)
			local userId = bench:GetAttribute("Lifter")
			local lifter = userId and Players:GetPlayerByUserId(userId)
			local character = lifter and lifter.Character
			if character then
				state.joints = liftJoints(character)
				applyLift(bench, state, 0)
			end
		end
		bench:GetAttributeChangedSignal("Lifter"):Connect(onLifter)
		bench:GetAttributeChangedSignal("Reps"):Connect(function()
			animateRep(bench)
		end)
		-- Disques ajoutés par le serveur (posés à la position de repos) : on les recale
		-- sur la barre si elle est en plein mouvement chez nous
		local bar = bench:WaitForChild("Barbell", 10)
		local plates = bar and bar:WaitForChild("Plates", 10)
		if plates then
			plates.ChildAdded:Connect(function(plate)
				task.defer(function()
					local rest: CFrame? = bench:GetAttribute("BarRest")
					if rest and plate:IsA("Model") and plate.Parent then
						plate:PivotTo(bar:GetPivot() * rest:ToObjectSpace(plate:GetPivot()))
					end
				end)
			end)
		end
		-- L'invite « S'entraîner » n'apparaît que sur MON banc
		local lie = bench:WaitForChild("LiePoint", 10)
		local prompt = lie and lie:WaitForChild("TrainPrompt", 10) :: ProximityPrompt?
		if prompt then
			local function refreshPrompt()
				if (player:GetAttribute("MuseumIndex") or 0) ~= plotIndex then
					prompt.Enabled = false
				end
			end
			prompt:GetPropertyChangedSignal("Enabled"):Connect(refreshPrompt)
			player:GetAttributeChangedSignal("MuseumIndex"):Connect(function()
				-- on ne peut pas réactiver localement une invite désactivée par le serveur :
				-- elle l'est seulement quand quelqu'un est allongé dessus
				prompt.Enabled = (player:GetAttribute("MuseumIndex") or 0) == plotIndex and bench:GetAttribute("Lifter") == nil
			end)
			refreshPrompt()
		end
		onLifter()
	end

	task.spawn(function()
		local museums = world:WaitForChild("Museums")
		local index = 1
		while true do
			local plot = museums:WaitForChild("Museum" .. index, 5)
			if not plot then
				break
			end
			local bench = plot:WaitForChild("Bench", 5)
			if bench then
				task.spawn(watchBench, bench, index)
			end
			index += 1
		end
	end)

	-- Mes répétitions
	local lastRep = 0
	local function doRep()
		if not player:GetAttribute("OnBench") then
			return
		end
		local now = os.clock()
		if now - lastRep < BenchCfg.RepCooldown then
			return
		end
		lastRep = now
		Remotes.Train:FireServer()
		K.sound("UIPop", 0.5, 0.8 + math.random() * 0.2)
		local gain = Config.GetRepGain(player:GetAttribute("Power") or 0)
		K.floatText(gui, "+" .. Config.FormatNumber(gain) .. " 💪", Color3.fromRGB(255, 140, 110),
			UDim2.new(0.5, math.random(-120, 120), 0.4, math.random(-30, 30)), 32)
	end
	benchTap.Activated:Connect(doRep)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Space and player:GetAttribute("OnBench") then
			doRep()
		end
	end)
	benchLeave.Activated:Connect(function()
		BenchLeaveEvent:FireServer()
	end)

	local function refreshOnBench()
		local on = player:GetAttribute("OnBench") == true
		benchHint.Visible = on
		benchTap.Visible = on
		benchLeave.Visible = on
		local humanoid = getCharacterParts()
		if humanoid then
			-- Espace sert à soulever : pas de saut pendant qu'on est allongé
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not on)
		end
		if on then
			benchHint.Size = UDim2.fromOffset(420, 34)
			tween(benchHint, 0.35, { Size = UDim2.fromOffset(600, 46) }, Enum.EasingStyle.Back)
		end
	end
	player:GetAttributeChangedSignal("OnBench"):Connect(refreshOnBench)
	refreshOnBench()
end

-- Panneau debug : visible uniquement dans Studio (le serveur revérifie)
if RunService:IsStudio() then
	local panel = create("Frame", {
		Name = "Debug", Parent = gui, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -UI.Margin, 0.5, 0), -- à droite : la gauche est aux boutons d'action
		Size = UDim2.fromScale(0.16, 0.7), BackgroundColor3 = UI.Dark, BackgroundTransparency = 0.3,
	}, {
		create("UISizeConstraint", { MaxSize = Vector2.new(190, 520), MinSize = Vector2.new(120, 300) }),
		corner(),
		create("UIListLayout", { Padding = UDim.new(0.01, 0), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
		create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }),
	})
	local title = create("TextLabel", {
		Parent = panel, Size = UDim2.fromScale(0.92, 0.07), BackgroundTransparency = 1, Font = UI.Font, TextScaled = true,
		TextColor3 = UI.White, Text = "DEBUG", LayoutOrder = 0,
	})
	local forcedLabel = create("TextLabel", {
		Parent = panel, Size = UDim2.fromScale(0.92, 0.06), BackgroundTransparency = 1, Font = UI.Font, TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 230, 120), Text = "Prochain : aléatoire", LayoutOrder = 1,
	})
	local order = 2
	local function debugButton(text: string, color: Color3, callback: () -> ())
		local button = create("TextButton", {
			Parent = panel, Size = UDim2.fromScale(0.92, 0.075), BackgroundColor3 = color, Font = UI.Font, TextScaled = true,
			TextColor3 = UI.White, Text = text, LayoutOrder = order,
		}, { create("UICorner", { CornerRadius = UDim.new(0, 8) }), textMax(22) })
		order += 1
		button.Activated:Connect(callback)
	end
	debugButton("Aléatoire", UI.Panel, function()
		Remotes.Debug:InvokeServer("ForceRarity", nil)
	end)
	for _, id in ipairs({ "Commun", "Rare", "Epique", "Legendaire", "Mythique", "Secret", "Divin", "Cosmique" }) do
		local rarity = rarityDef(id)
		debugButton("Forcer : " .. rarity.name, rarity.color:Lerp(UI.Dark, 0.35), function()
			Remotes.Debug:InvokeServer("ForceRarity", id)
		end)
	end
	debugButton("Argent x2", UI.Green, function()
		Remotes.Debug:InvokeServer("AddMoney")
	end)
	debugButton("Puissance x2", UI.Blue, function()
		Remotes.Debug:InvokeServer("AddPower")
	end)
	debugButton("Débloquer", UI.Red, function()
		Remotes.Debug:InvokeServer("Unlock")
		revealCard.Visible = false
		cleanButton.Visible = false
		gaugeFrame.Visible = false
		tapCatcher.Visible = false
		finishThrow()
	end)
	local function refreshForced()
		local forced = player:GetAttribute("ForcedRarity")
		local rarity = forced and forced ~= "" and rarityDef(forced)
		forcedLabel.Text = rarity and ("Prochain : " .. rarity.name) or "Prochain : aléatoire"
	end
	player:GetAttributeChangedSignal("ForcedRarity"):Connect(refreshForced)
	refreshForced()
	title.Text = "DEBUG (Studio)"
end

-- Tout est branché : le serveur peut maintenant nous rendre une relique en attente
Remotes.ClientReady:FireServer()

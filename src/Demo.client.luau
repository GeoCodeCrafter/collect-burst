local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CollectBurst = require(ReplicatedStorage:WaitForChild("CollectBurst"))

local COLOR = Color3.fromRGB(170, 90, 255)
local ORE_AT = Vector3.new(0, 0, -14)
local ORE_VALUE = 30
-- it takes a few hits: each early hit spills a little, the last one breaks it and drops the rest
local HITS = 3
local HIT_VALUE = 4
-- the glowing weak point on the rock: hit it for a crit worth 3x (2x on the breaking hit)
local CRIT_COLOR = Color3.fromRGB(80, 200, 255)
local CRIT_BONUS = 3
local ROCK_SIZE = 4.5

-- your assets go in ReplicatedStorage.CollectBurstAssets, all optional:
--   Rock (Model or MeshPart), Gem (Model or MeshPart), Chunk (a part, or a model of rocks to pick from),
--   Pickup and Break (Sounds), Icon (a Decal. without one the Gem itself is used as a 3D icon)
local assets = ReplicatedStorage:FindFirstChild("CollectBurstAssets")
local function asset(name)
	return assets and assets:FindFirstChild(name)
end

local pickup = asset("Pickup")
if not pickup then
	pickup = Instance.new("Sound")
	pickup.SoundId = "rbxasset://sounds/volume_slider.ogg"
	pickup.Volume = 0.5
end
local iconImage = asset("Icon") and asset("Icon").Texture
-- what drops is a chunk of the rock's own amethyst. the cut gem and a drawn diamond both read like a
-- kids game, so the counter shows the same amethyst, rendered in 3D
local rockAsset = asset("Rock")
local dropTemplate = (rockAsset and rockAsset:FindFirstChild("Crystals")) or asset("Gem")
local iconModel = not iconImage and dropTemplate or nil
local VIOLET = Color3.fromRGB(196, 160, 255)
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local FONT_LIGHT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)

local function play(sound, speed)
	if not sound then
		return
	end
	local s = sound:Clone()
	s.PlaybackSpeed = speed
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 3)
end

-- counter in the top right
local gui = Instance.new("ScreenGui")
gui.Name = "Counter"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- no box behind it: a small cut-gem mark, a caption and the number, like a proper game HUD
local counter = Instance.new("Frame")
counter.AnchorPoint = Vector2.new(1, 0)
counter.Position = UDim2.new(1, -36, 0, 64)
counter.Size = UDim2.fromOffset(170, 56)
counter.BackgroundTransparency = 1
counter.Parent = gui
local scale = Instance.new("UIScale", counter)

local icon, rim
if iconModel then
	icon = CollectBurst.icon3d(iconModel)
	icon.Size = UDim2.fromOffset(34, 34)
	rim = Instance.new("UIStroke")
elseif iconImage then
	icon = Instance.new("ImageLabel")
	icon.Image = iconImage
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(24, 24)
	rim = Instance.new("UIStroke")
else
	-- thin light outline round a violet fill that fades down, turned 45 so it reads as a cut stone
	icon = Instance.new("Frame")
	icon.Rotation = 45
	icon.Size = UDim2.fromOffset(16, 16)
	icon.BackgroundColor3 = Color3.new(1, 1, 1)
	icon.BorderSizePixel = 0
	local fill = Instance.new("UIGradient", icon)
	fill.Color = ColorSequence.new(Color3.fromRGB(226, 206, 255), Color3.fromRGB(88, 38, 168))
	fill.Rotation = 45
	rim = Instance.new("UIStroke", icon)
	rim.Color = Color3.fromRGB(240, 232, 255)
	rim.Thickness = 1
	rim.Transparency = 0.3
end
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.new(0, 12, 0, 36)
icon.Parent = counter
local restRotation = icon.Rotation
local rimRest = rim.Transparency

local caption = Instance.new("TextLabel")
caption.BackgroundTransparency = 1
caption.Position = UDim2.fromOffset(32, 4)
caption.Size = UDim2.new(1, -32, 0, 14)
caption.FontFace = FONT_LIGHT
caption.TextSize = 13
caption.TextColor3 = VIOLET
caption.TextTransparency = 0.15
caption.TextXAlignment = Enum.TextXAlignment.Left
caption.Text = "AMETHYST"
caption.Parent = counter

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.fromOffset(32, 18)
label.Size = UDim2.new(1, -32, 0, 36)
label.FontFace = FONT
label.TextSize = 34
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = "0"
label.Parent = counter
local labelShadow = Instance.new("UIStroke", label)
labelShadow.Thickness = 1
labelShadow.Transparency = 0.75

-- "+30" under the counter, counts up as the gems land then floats off
local POPUP_AT = UDim2.new(1, -36, 0, 122)
local popup = Instance.new("TextLabel")
popup.AnchorPoint = Vector2.new(1, 0)
popup.Position = POPUP_AT
popup.Size = UDim2.fromOffset(138, 26)
popup.BackgroundTransparency = 1
popup.FontFace = FONT
popup.TextSize = 22
popup.TextColor3 = VIOLET
popup.TextXAlignment = Enum.TextXAlignment.Right
popup.TextTransparency = 1
popup.Text = ""
popup.Parent = gui
local popupStroke = Instance.new("UIStroke", popup)
popupStroke.Thickness = 2
popupStroke.Transparency = 1
local popupScale = Instance.new("UIScale", popup)

-- crit streak: weak-point hits in a row stack a multiplier (x2, x3, up to x4), any normal hit resets it.
-- it carries over from one rock to the next
local combo = 0
local comboLabel = Instance.new("TextLabel")
comboLabel.AnchorPoint = Vector2.new(1, 0)
comboLabel.Position = UDim2.new(1, -36, 0, 150)
comboLabel.Size = UDim2.fromOffset(220, 34)
comboLabel.BackgroundTransparency = 1
comboLabel.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
comboLabel.TextSize = 30
comboLabel.TextColor3 = CRIT_COLOR
comboLabel.TextXAlignment = Enum.TextXAlignment.Right
comboLabel.Rotation = -4
comboLabel.TextTransparency = 1
comboLabel.Text = ""
comboLabel.Parent = gui
local comboStroke = Instance.new("UIStroke", comboLabel)
comboStroke.Thickness = 3
comboStroke.Color = Color3.fromRGB(20, 14, 30)
comboStroke.Transparency = 1
local comboScale = Instance.new("UIScale", comboLabel)

local function comboMult()
	return math.clamp(combo, 1, 4)
end

local function updateCombo()
	if combo >= 2 then
		-- streak going up: pops in big and settles
		comboLabel.Text = "CRIT x" .. comboMult()
		comboLabel.TextTransparency = 0
		comboStroke.Transparency = 0
		comboScale.Scale = 1.5
		TweenService:Create(comboScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	elseif comboLabel.TextTransparency < 1 then
		-- streak broken: drops away and fades
		local out = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(comboLabel, out, { TextTransparency = 1 }):Play()
		TweenService:Create(comboStroke, out, { Transparency = 1 }):Play()
		TweenService:Create(comboScale, out, { Scale = 0.7 }):Play()
	end
end

local total, shown, haul = 0, 0, 0
local fades = {}
local back = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- the number rolls up to the real total instead of jumping
RunService.RenderStepped:Connect(function(dt)
	shown += (total - shown) * math.min(1, dt * 14)
	if math.abs(total - shown) < 0.5 then
		shown = total
	end
	label.Text = tostring(math.round(shown))
end)

local function arrive(worth, n, count)
	total += worth
	scale.Scale = 1.08 + 0.02 * worth
	TweenService:Create(scale, back, { Scale = 1 }):Play()
	icon.Rotation = restRotation + 8 * worth
	TweenService:Create(icon, back, { Rotation = restRotation }):Play()
	-- the mark's outline flashes bright and settles back
	rim.Transparency = 0
	TweenService:Create(rim, TweenInfo.new(0.3), { Transparency = rimRest }):Play()
	-- pitch climbs as the haul comes in
	play(pickup, 0.9 + 0.6 * n / count)

	for _, t in fades do
		t:Cancel()
	end
	table.clear(fades)
	if n == 1 then
		haul = 0
	end
	haul += worth
	popup.Text = "+" .. haul
	popup.Position = POPUP_AT
	popup.TextTransparency = 0
	popupStroke.Transparency = 0
	popupScale.Scale = 1.2
	TweenService:Create(popupScale, back, { Scale = 1 }):Play()
	if n == count then
		local out = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4)
		fades = {
			TweenService:Create(popup, out, { Position = POPUP_AT - UDim2.fromOffset(0, 24), TextTransparency = 1 }),
			TweenService:Create(popupStroke, out, { Transparency = 1 }),
		}
		for _, t in fades do
			t:Play()
		end
	end
end

-- stand-in rock until there's a real one in CollectBurstAssets
local function placeholderRock()
	local ore = Instance.new("Model")
	local rock = Instance.new("Part")
	rock.Size = Vector3.new(4, 3.5, 4)
	rock.Material = Enum.Material.Slate
	rock.Color = Color3.fromRGB(95, 90, 88)
	rock.Parent = ore
	ore.PrimaryPart = rock
	local half = rock.Size / 2
	for _ = 1, 6 do
		local r = function(k)
			return (math.random() * 2 - 1) * k
		end
		local side = math.random(1, 5)
		local s = if side % 2 == 0 then 1 else -1
		local o = if side == 5
			then Vector3.new(r(half.X * 0.7), half.Y, r(half.Z * 0.7))
			elseif side <= 2 then Vector3.new(half.X * s, r(half.Y * 0.6), r(half.Z * 0.7))
			else Vector3.new(r(half.X * 0.7), r(half.Y * 0.6), half.Z * s)
		local chunk = Instance.new("Part")
		chunk.CanCollide = false
		chunk.Size = Vector3.one * (0.6 + math.random() * 0.5)
		chunk.Material = Enum.Material.Neon
		chunk.Color = COLOR
		chunk.CFrame = CFrame.new(o) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = ore
	end
	return ore
end

-- puts the crit spot somewhere on the rock's surface on the side facing you, replacing the old one:
-- a cyan disc with a ring pulsing out of it and a little light
local function placeWeakPoint(ore)
	local old = ore:FindFirstChild("WeakPoint")
	if old then
		old:Destroy()
	end
	local cf, box = ore:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ore }
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local toward = if root then (root.Position - cf.Position) * Vector3.new(1, 0, 1) else Vector3.zAxis
	toward = if toward.Magnitude > 0.1 then toward.Unit else Vector3.zAxis
	for _ = 1, 25 do
		local swing = CFrame.Angles(0, (math.random() - 0.5) * math.pi * 1.1, 0)
		local dir = (swing:VectorToWorldSpace(toward) + Vector3.new(0, math.random() * 0.7, 0)).Unit
		local from = cf.Position + dir * (math.max(box.X, box.Y, box.Z) + 2)
		local hit = workspace:Raycast(from, cf.Position - from, params)
		if hit then
			local point = Instance.new("Model")
			point.Name = "WeakPoint"
			local function disc(name, size, transparency)
				local d = Instance.new("Part")
				d.Name = name
				d.Shape = Enum.PartType.Cylinder
				d.Size = Vector3.new(0.06, size, size)
				d.Material = Enum.Material.Neon
				d.Color = CRIT_COLOR
				d.Transparency = transparency
				d.Anchored = true
				d.CanCollide = false
				d.CastShadow = false
				-- a cylinder's round face points along its X, so turn X to face out of the surface
				d.CFrame = CFrame.lookAt(hit.Position + hit.Normal * 0.06, hit.Position + hit.Normal * 2) * CFrame.Angles(0, math.rad(90), 0)
				d.Parent = point
				return d
			end
			local core = disc("Core", 0.9, 0.05)
			local ring = disc("Ring", 0.9, 0.45)
			local glow = Instance.new("PointLight")
			glow.Color = CRIT_COLOR
			glow.Brightness = 1.4
			glow.Range = 5
			glow.Parent = core
			TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), {
				Size = Vector3.new(0.06, 1.9, 1.9),
				Transparency = 1,
			}):Play()
			point.Parent = ore
			return
		end
	end
end

local function spawnOre()
	local ore = CollectBurst.asModel(asset("Rock") or placeholderRock())
	ore.Name = "Ore"
	CollectBurst.fit(ore, ROCK_SIZE)
	ore:PivotTo(CFrame.new(ORE_AT) * CFrame.Angles(0, math.random() * math.pi, 0))
	-- sit it on whatever ground is actually there. terrain rounds to its own grid, so assuming y=0
	-- buried the rock up to its crystals
	local down = RaycastParams.new()
	down.FilterType = Enum.RaycastFilterType.Exclude
	down.FilterDescendantsInstances = { ore, Players.LocalPlayer.Character }
	-- the ground is built on the server, so give it a few seconds to reach us before placing the rock
	local ground
	for _ = 1, 50 do
		-- from just above the spot, not the sky: in the cave a ray from the sky lands on the roof
		ground = workspace:Raycast(ORE_AT + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), down)
		if ground then
			break
		end
		task.wait(0.1)
	end
	local groundY = if ground then ground.Position.Y else ORE_AT.Y
	local cf, size = ore:GetBoundingBox()
	ore:PivotTo(ore:GetPivot() + Vector3.new(0, groundY - 0.15 - (cf.Position.Y - size.Y / 2), 0))
	-- the amethyst throws a little violet light onto the stone around it
	local crystals = ore:FindFirstChild("Crystals")
	if crystals then
		local glow = Instance.new("PointLight")
		glow.Color = COLOR
		glow.Brightness = 0.8
		glow.Range = 7
		glow.Shadows = false
		glow.Parent = crystals
	end
	ore:SetAttribute("BaseScale", ore:GetScale())
	ore:SetAttribute("Hits", HITS)
	ore.Parent = workspace

	-- hits left: three small marks above the rock, a spent one goes dim
	local _, box = ore:GetBoundingBox()
	local pips = Instance.new("BillboardGui")
	pips.Name = "Pips"
	pips.Size = UDim2.fromOffset(56, 8)
	pips.StudsOffsetWorldSpace = Vector3.new(0, box.Y / 2 + 1.2, 0)
	pips.LightInfluence = 0
	pips.Parent = ore.PrimaryPart
	local row = Instance.new("UIListLayout", pips)
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0, 4)
	for i = 1, HITS do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.Size = UDim2.fromOffset(14, 4)
		pip.BackgroundColor3 = VIOLET
		pip.BorderSizePixel = 0
		pip.LayoutOrder = i
		Instance.new("UICorner", pip).CornerRadius = UDim.new(1, 0)
		pip.Parent = pips
	end

	placeWeakPoint(ore)
	CollectBurst.popIn(ore)
	return ore
end

local ore = spawnOre()
local busy = false

UserInputService.InputBegan:Connect(function(input, processed)
	local click = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	if processed or busy or not click then
		return
	end
	local m = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(m.X, m.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 200)
	if hit and hit.Instance:IsDescendantOf(ore) then
		local hitsLeft = ore:GetAttribute("Hits") or 1
		local cf, box = ore:GetBoundingBox()
		local at = cf.Position
		local function spill(value, from)
			CollectBurst.drop(from, value, {
				target = icon,
				color = COLOR,
				gem = dropTemplate,
				collector = function()
					local character = Players.LocalPlayer.Character
					return character and character:FindFirstChild("HumanoidRootPart")
				end,
				onArrive = arrive,
			})
		end

		-- did it land on the glowing weak point?
		local weak = ore:FindFirstChild("WeakPoint")
		local core = weak and weak:FindFirstChild("Core")
		local crit = core ~= nil and (hit.Instance:IsDescendantOf(weak) or (hit.Position - core.Position).Magnitude < core.Size.Y * 0.8)
		combo = if crit then combo + 1 else 0
		updateCombo()
		local mult = if crit then comboMult() else 1

		if hitsLeft > 1 then
			-- an early hit: a tink, the rock wobbles, chips and dust and a little amethyst come off where you hit
			ore:SetAttribute("Hits", hitsLeft - 1)
			local pip = ore.PrimaryPart:FindFirstChild("Pips") and ore.PrimaryPart.Pips:FindFirstChild("Pip" .. hitsLeft)
			if pip then
				TweenService:Create(pip, TweenInfo.new(0.2), { BackgroundTransparency = 0.8 }):Play()
			end
			-- a crit is a sharper, higher tink with a ding on top
			local tink = asset("Break")
			if tink then
				local s = tink:Clone()
				s.Volume = tink.Volume * (if crit then 0.8 else 0.55)
				s.PlaybackSpeed = (if crit then 1.95 else 1.5) + math.random() * 0.15
				s.Parent = SoundService
				s:Play()
				Debris:AddItem(s, 3)
			end
			if crit then
				-- the ding climbs with the streak
			play(pickup, 1.8 + 0.12 * math.min(combo, 6))
			end
			local value = HIT_VALUE * (if crit then CRIT_BONUS else 1) * mult
			CollectBurst.hit(ore, asset("Chunk"), hit.Position, hit.Normal, if crit then 2 else 1)
			spill(value, hit.Position + hit.Normal * 0.6)
			CollectBurst.number(hit.Position + hit.Normal * 1.2, "+" .. value, if crit then CRIT_COLOR else Color3.new(1, 1, 1), crit)
			-- the weak point jumps somewhere new after every hit
			placeWeakPoint(ore)
			-- a short gap between swings so spam-clicking doesn't skip the wobble
			busy = true
			task.delay(0.22, function()
				busy = false
			end)
			return
		end

		busy = true
		local value = (ORE_VALUE - HIT_VALUE * (HITS - 1)) * (if crit then 2 else 1) * mult
		play(asset("Break"), 1)
		if crit then
			-- the ding climbs with the streak
			play(pickup, 1.8 + 0.12 * math.min(combo, 6))
		end
		CollectBurst.number(hit.Position + hit.Normal * 1.2, "+" .. value, if crit then CRIT_COLOR else Color3.fromRGB(255, 226, 110), true)
		CollectBurst.crumble(ore, asset("Chunk"), function()
			spill(value, at)
			task.delay(2.5, function()
				ore = spawnOre()
				busy = false
			end)
		end)
	end
end)

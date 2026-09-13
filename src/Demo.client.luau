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
	ore.Parent = workspace
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
		busy = true
		local at = ore:GetBoundingBox().Position
		play(asset("Break"), 1)
		CollectBurst.crumble(ore, asset("Chunk"), function()
			CollectBurst.drop(at, ORE_VALUE, {
				target = icon,
				color = COLOR,
				gem = dropTemplate,
				icon = iconImage,
				iconModel = iconModel,
				collector = function()
					local character = Players.LocalPlayer.Character
					return character and character:FindFirstChild("HumanoidRootPart")
				end,
				onArrive = arrive,
			})
			task.delay(2.5, function()
				ore = spawnOre()
				busy = false
			end)
		end)
	end
end)

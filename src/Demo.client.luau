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
local iconModel = not iconImage and asset("Gem") or nil

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

local counter = Instance.new("Frame")
counter.AnchorPoint = Vector2.new(1, 0)
counter.Position = UDim2.new(1, -24, 0, 70)
counter.Size = UDim2.fromOffset(150, 50)
counter.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
counter.BackgroundTransparency = 0.2
counter.Parent = gui
Instance.new("UICorner", counter).CornerRadius = UDim.new(0, 12)
local scale = Instance.new("UIScale", counter)
local rim = Instance.new("UIStroke", counter)
rim.Color = COLOR
rim.Thickness = 2
rim.Transparency = 1

local icon
if iconModel then
	icon = CollectBurst.icon3d(iconModel)
	icon.Size = UDim2.fromOffset(38, 38)
elseif iconImage then
	icon = Instance.new("ImageLabel")
	icon.Image = iconImage
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(30, 30)
else
	icon = Instance.new("Frame")
	icon.Rotation = 45
	icon.BackgroundColor3 = COLOR
	icon.BorderSizePixel = 0
	icon.Size = UDim2.fromOffset(20, 20)
end
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.new(0, 28, 0.5, 0)
icon.Parent = counter
local restRotation = icon.Rotation

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.fromOffset(52, 0)
label.Size = UDim2.new(1, -62, 1, 0)
label.Font = Enum.Font.GothamBold
label.TextSize = 28
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = "0"
label.Parent = counter

-- "+30" under the counter, counts up as the gems land then floats off
local POPUP_AT = UDim2.new(1, -24, 0, 126)
local popup = Instance.new("TextLabel")
popup.AnchorPoint = Vector2.new(1, 0)
popup.Position = POPUP_AT
popup.Size = UDim2.fromOffset(150, 30)
popup.BackgroundTransparency = 1
popup.Font = Enum.Font.GothamBlack
popup.TextSize = 26
popup.TextColor3 = COLOR
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
	rim.Transparency = 0.2
	TweenService:Create(rim, TweenInfo.new(0.3), { Transparency = 1 }):Play()
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
	-- sit it on the ground whatever shape it is
	local cf, size = ore:GetBoundingBox()
	ore:PivotTo(ore:GetPivot() + Vector3.new(0, ORE_AT.Y - (cf.Position.Y - size.Y / 2), 0))
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
				gem = asset("Gem"),
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

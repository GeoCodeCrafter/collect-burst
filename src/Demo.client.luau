local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CollectBurst = require(ReplicatedStorage:WaitForChild("CollectBurst"))

local GOLD = Color3.fromRGB(255, 196, 40)
local ORE_AT = Vector3.new(0, 2.5, -14)

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

local icon = Instance.new("Frame")
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.new(0, 28, 0.5, 0)
icon.Size = UDim2.fromOffset(20, 20)
icon.Rotation = 45
icon.BackgroundColor3 = GOLD
icon.BorderSizePixel = 0
icon.Parent = counter

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.fromOffset(50, 0)
label.Size = UDim2.new(1, -60, 1, 0)
label.Font = Enum.Font.GothamBold
label.TextSize = 28
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = "0"
label.Parent = counter

local gold = 0
local pop = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function arrive()
	gold += 1
	label.Text = tostring(gold)
	scale.Scale = 1.25
	TweenService:Create(scale, pop, { Scale = 1 }):Play()
end

-- a grey rock with gold stuck to its sides and top
local function spawnOre()
	local ore = Instance.new("Model")
	ore.Name = "Ore"
	local rock = Instance.new("Part")
	rock.Anchored = true
	rock.Size = Vector3.new(4, 3.5, 4)
	rock.Material = Enum.Material.Slate
	rock.Color = Color3.fromRGB(95, 90, 88)
	rock.CFrame = CFrame.new(ORE_AT) * CFrame.Angles(0, math.random() * math.pi, 0)
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
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.Size = Vector3.one * (0.6 + math.random() * 0.5)
		chunk.Material = Enum.Material.Neon
		chunk.Color = GOLD
		chunk.CFrame = rock.CFrame * CFrame.new(o) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = ore
	end

	ore.Parent = workspace
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
		local at = ore:GetPivot().Position
		local broken = ore
		CollectBurst.crack(broken, function()
			broken:Destroy()
			CollectBurst.shake(2, 0.3)
			CollectBurst.burst(at + Vector3.new(0, 1, 0), 14, GOLD, icon, arrive)
			task.delay(1.2, function()
				ore = spawnOre()
				busy = false
			end)
		end)
	end
end)

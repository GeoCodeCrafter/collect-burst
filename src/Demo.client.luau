local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CollectBurst = require(ReplicatedStorage:WaitForChild("CollectBurst"))

local ORE_AT = Vector3.new(0, 0, -14)
local ROCK_SIZE = 9
-- it takes a few hits: each early hit spills a little, the last one breaks it and drops the rest
local HITS = 3
-- the glinting weak point on the rock: hit it for a crit worth 3x (2x on the breaking hit)
local CRIT_COLOR = Color3.fromRGB(255, 214, 120)
local CRIT_BONUS = 3

-- your assets go in ReplicatedStorage.CollectBurstAssets, all optional:
--   Rock (Model or MeshPart, with a Crystals part for amethyst), Variants (more rocks), Chunk (rubble),
--   Ores/<Coal|Iron|Gold|Diamond> (clusters set into the rock), Pickup and Break (Sounds)
local assets = ReplicatedStorage:FindFirstChild("CollectBurstAssets")
local function asset(name)
	return assets and assets:FindFirstChild(name)
end

-- what a rock can hold. rarer ores turn up less and are worth more. amethyst grows as crystals in the
-- rock itself, the others are clusters set into the stone
local ORES = {
	{ key = "Coal", label = "COAL", color = Color3.fromRGB(176, 176, 186), value = 20, weight = 40, clusters = 6 },
	{ key = "Iron", label = "IRON", color = Color3.fromRGB(222, 150, 108), value = 30, weight = 28, clusters = 5 },
	{ key = "Amethyst", label = "AMETHYST", color = Color3.fromRGB(196, 160, 255), value = 45, weight = 18 },
	{ key = "Gold", label = "GOLD", color = Color3.fromRGB(255, 206, 84), value = 70, weight = 10, clusters = 5 },
	{ key = "Diamond", label = "DIAMOND", color = Color3.fromRGB(176, 232, 255), value = 120, weight = 4, clusters = 4 },
}
local ORE_BY_KEY = {}
for i, ore in ORES do
	ore.index = i
	ORE_BY_KEY[ore.key] = ore
end

local function clustersFor(ore)
	local folder = asset("Ores") and asset("Ores"):FindFirstChild(ore.key)
	return if folder then folder:GetChildren() else {}
end

-- what flies into the counter for each ore
local function dropFor(ore)
	if ore.key == "Amethyst" then
		local rock = asset("Rock")
		return (rock and rock:FindFirstChild("Crystals")) or asset("Gem")
	end
	return clustersFor(ore)[1]
end

-- only offer ores whose models are actually there
local function pickOre()
	local pool, total = {}, 0
	for _, ore in ORES do
		if ore.key == "Amethyst" or #clustersFor(ore) > 0 then
			table.insert(pool, ore)
			total += ore.weight
		end
	end
	local roll = math.random() * total
	for _, ore in pool do
		roll -= ore.weight
		if roll <= 0 then
			return ore
		end
	end
	return pool[#pool]
end

local pickup = asset("Pickup")
if not pickup then
	pickup = Instance.new("Sound")
	pickup.SoundId = "rbxasset://sounds/volume_slider.ogg"
	pickup.Volume = 0.5
end
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

-- ---- HUD: a resource list in the top right, a row for each ore the first time you mine it
local gui = Instance.new("ScreenGui")
gui.Name = "Counter"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local list = Instance.new("Frame")
list.AnchorPoint = Vector2.new(1, 0)
list.Position = UDim2.new(1, -36, 0, 70)
list.Size = UDim2.fromOffset(170, 420)
list.BackgroundTransparency = 1
list.Parent = gui
local layout = Instance.new("UIListLayout", list)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 4)

local back = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local rows = {}

local function rowFor(ore)
	if rows[ore.key] then
		return rows[ore.key]
	end
	local r = { total = 0, shown = 0, haul = 0, fades = {} }
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(170, 52)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = ore.index
	frame.Parent = list
	r.scale = Instance.new("UIScale", frame)

	local template = dropFor(ore)
	if template then
		r.icon = CollectBurst.icon3d(template)
		r.icon.Size = UDim2.fromOffset(34, 34)
	else
		r.icon = Instance.new("Frame")
		r.icon.Rotation = 45
		r.icon.Size = UDim2.fromOffset(16, 16)
		r.icon.BackgroundColor3 = ore.color
		r.icon.BorderSizePixel = 0
	end
	r.icon.AnchorPoint = Vector2.new(0.5, 0.5)
	r.icon.Position = UDim2.new(0, 14, 0, 32)
	r.icon.Parent = frame
	r.rest = r.icon.Rotation

	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.fromOffset(34, 2)
	caption.Size = UDim2.new(1, -34, 0, 14)
	caption.FontFace = FONT_LIGHT
	caption.TextSize = 13
	caption.TextColor3 = ore.color
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Text = ore.label
	caption.Parent = frame

	r.label = Instance.new("TextLabel")
	r.label.BackgroundTransparency = 1
	r.label.Position = UDim2.fromOffset(34, 16)
	r.label.Size = UDim2.new(1, -34, 0, 34)
	r.label.FontFace = FONT
	r.label.TextSize = 32
	r.label.TextColor3 = Color3.new(1, 1, 1)
	r.label.TextXAlignment = Enum.TextXAlignment.Left
	r.label.Text = "0"
	r.label.Parent = frame
	local shadow = Instance.new("UIStroke", r.label)
	shadow.Thickness = 1
	shadow.Transparency = 0.75

	-- "+30" to the left of the row, counts up as the drops land then floats off
	r.popup = Instance.new("TextLabel")
	r.popup.AnchorPoint = Vector2.new(1, 0.5)
	r.popup.Position = UDim2.new(0, -6, 0, 32)
	r.popup.Size = UDim2.fromOffset(120, 26)
	r.popup.BackgroundTransparency = 1
	r.popup.FontFace = FONT
	r.popup.TextSize = 22
	r.popup.TextColor3 = ore.color
	r.popup.TextXAlignment = Enum.TextXAlignment.Right
	r.popup.TextTransparency = 1
	r.popup.Text = ""
	r.popup.Parent = frame
	r.popupStroke = Instance.new("UIStroke", r.popup)
	r.popupStroke.Thickness = 2
	r.popupStroke.Transparency = 1
	r.popupScale = Instance.new("UIScale", r.popup)
	r.popupAt = r.popup.Position

	r.scale.Scale = 0.2
	TweenService:Create(r.scale, back, { Scale = 1 }):Play()
	rows[ore.key] = r
	return r
end

-- every number rolls up to its real total instead of jumping
RunService.RenderStepped:Connect(function(dt)
	for _, r in rows do
		r.shown += (r.total - r.shown) * math.min(1, dt * 14)
		if math.abs(r.total - r.shown) < 0.5 then
			r.shown = r.total
		end
		r.label.Text = tostring(math.round(r.shown))
	end
end)

local function arriveFor(ore)
	local r = rowFor(ore)
	return function(worth, n, count)
		r.total += worth
		r.scale.Scale = 1.08 + 0.02 * math.min(worth, 5)
		TweenService:Create(r.scale, back, { Scale = 1 }):Play()
		r.icon.Rotation = r.rest + 8 * math.min(worth, 5)
		TweenService:Create(r.icon, back, { Rotation = r.rest }):Play()
		-- pitch climbs as the haul comes in
		play(pickup, 0.9 + 0.6 * n / count)

		for _, t in r.fades do
			t:Cancel()
		end
		table.clear(r.fades)
		if n == 1 then
			r.haul = 0
		end
		r.haul += worth
		r.popup.Text = "+" .. r.haul
		r.popup.Position = r.popupAt
		r.popup.TextTransparency = 0
		r.popupStroke.Transparency = 0
		r.popupScale.Scale = 1.2
		TweenService:Create(r.popupScale, back, { Scale = 1 }):Play()
		if n == count then
			local out = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4)
			r.fades = {
				TweenService:Create(r.popup, out, { Position = r.popupAt - UDim2.fromOffset(0, 18), TextTransparency = 1 }),
				TweenService:Create(r.popupStroke, out, { Transparency = 1 }),
			}
			for _, t in r.fades do
				t:Play()
			end
		end
	end
end

-- crit streak: weak-point hits in a row stack a multiplier (x2, x3, up to x4), any normal hit resets it.
-- it carries over from one rock to the next
local combo = 0
local comboLabel = Instance.new("TextLabel")
comboLabel.AnchorPoint = Vector2.new(1, 0)
comboLabel.Position = UDim2.new(1, -36, 0, 30)
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

-- ---- rocks
-- stand-in rock until there's a real one in CollectBurstAssets
local function placeholderRock()
	local ore = Instance.new("Model")
	local rock = Instance.new("Part")
	rock.Size = Vector3.new(4, 3.5, 4)
	rock.Material = Enum.Material.Slate
	rock.Color = Color3.fromRGB(95, 90, 88)
	rock.Parent = ore
	ore.PrimaryPart = rock
	return ore
end

-- the main rock or one of its variants, picked at random each time one grows back
local function pickRock()
	local pool = {}
	if asset("Rock") then
		table.insert(pool, asset("Rock"))
	end
	if asset("Variants") then
		for _, v in asset("Variants"):GetChildren() do
			table.insert(pool, v)
		end
	end
	return if #pool > 0 then pool[math.random(#pool)] else nil
end

-- sets clusters of an ore into the rock's surface, facing out of the stone and about a third sunk in
local function setOre(model, ore)
	local pool = clustersFor(ore)
	if #pool == 0 then
		return
	end
	local cf, box = model:GetBoundingBox()
	local k = math.max(box.X, box.Z) / 4.5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local spots = {}
	for _ = 1, 80 do
		if #spots >= ore.clusters then
			break
		end
		local a = math.random() * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0.15 + math.random() * 0.9, math.sin(a)).Unit
		local from = cf.Position + dir * (math.max(box.X, box.Y, box.Z) + 2)
		local hit = workspace:Raycast(from, cf.Position - from, params)
		if hit and hit.Normal.Y > -0.2 and hit.Instance.Name ~= "OreCluster" then
			local clear = true
			for _, s in spots do
				if (s - hit.Position).Magnitude < 1.7 * k then
					clear = false
				end
			end
			if clear then
				table.insert(spots, hit.Position)
				local c = pool[math.random(#pool)]:Clone()
				c.Name = "OreCluster"
				c.Anchored = true
				c.CanCollide = false
				c.Size *= (0.9 + math.random() * 0.6) * k / math.max(c.Size.X, c.Size.Y, c.Size.Z)
				local up = hit.Normal
				local right = up:Cross(Vector3.new(math.random() - 0.5, 0.1, math.random() - 0.5)).Unit
				c.CFrame = CFrame.fromMatrix(hit.Position + up * c.Size.Y * 0.15, right, up)
				c.Parent = model
			end
		end
	end
end

-- puts the crit spot somewhere on the rock's surface on the side facing you, replacing the old one
local function placeWeakPoint(model)
	local old = model:FindFirstChild("WeakPoint")
	if old then
		old:Destroy()
	end
	local cf, box = model:GetBoundingBox()
	-- the spot scales with the rock so it stays the same share of it
	local k = math.max(box.X, box.Z) / 4.5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
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
			-- the disc is invisible, it's only there to be clicked. what you see is a rust-style glint:
			-- a warm twinkle on the stone with tiny sparks spitting out of it and falling
			local core = Instance.new("Part")
			core.Name = "Core"
			core.Shape = Enum.PartType.Cylinder
			core.Size = Vector3.new(0.06, 0.9 * k, 0.9 * k)
			core.Transparency = 1
			core.Anchored = true
			core.CanCollide = false
			core.CastShadow = false
			-- a cylinder's round face points along its X, so turn X to face out of the surface
			core.CFrame = CFrame.lookAt(hit.Position + hit.Normal * 0.06, hit.Position + hit.Normal * 2) * CFrame.Angles(0, math.rad(90), 0)
			core.Parent = point
			local twinkle = Instance.new("ParticleEmitter")
			twinkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			twinkle.Color = ColorSequence.new(Color3.new(1, 1, 1), CRIT_COLOR)
			twinkle.LightEmission = 1
			twinkle.LightInfluence = 0
			twinkle.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2 * k),
				NumberSequenceKeypoint.new(0.4, 0.55 * k),
				NumberSequenceKeypoint.new(1, 0),
			})
			twinkle.Lifetime = NumberRange.new(0.18, 0.35)
			twinkle.Rate = 22
			twinkle.Speed = NumberRange.new(0.1, 0.6)
			twinkle.SpreadAngle = Vector2.new(180, 180)
			twinkle.Rotation = NumberRange.new(0, 360)
			twinkle.RotSpeed = NumberRange.new(-180, 180)
			twinkle.ZOffset = 0.3
			twinkle.Parent = core
			local sparks = Instance.new("ParticleEmitter")
			sparks.Texture = "rbxasset://textures/particles/fire_sparks_main.dds"
			sparks.Color = ColorSequence.new(CRIT_COLOR, Color3.fromRGB(255, 140, 50))
			sparks.LightEmission = 1
			sparks.LightInfluence = 0
			sparks.Size = NumberSequence.new(0.07 * k, 0)
			sparks.Lifetime = NumberRange.new(0.25, 0.45)
			sparks.Rate = 7
			sparks.Speed = NumberRange.new(3, 6)
			-- the disc's X points out of the stone, so the sparks spit outwards and then drop
			sparks.EmissionDirection = Enum.NormalId.Right
			sparks.SpreadAngle = Vector2.new(35, 35)
			sparks.Acceleration = Vector3.new(0, -25, 0)
			sparks.Parent = core
			local glow = Instance.new("PointLight")
			glow.Color = CRIT_COLOR
			glow.Brightness = 0.9
			glow.Range = 4 * k
			glow.Parent = core
			point.Parent = model
			return
		end
	end
end

local function spawnOre()
	local ore = pickOre()
	local model = CollectBurst.asModel(pickRock() or placeholderRock())
	model.Name = "Ore"
	model:SetAttribute("OreType", ore.key)
	CollectBurst.fit(model, ROCK_SIZE)
	model:PivotTo(CFrame.new(ORE_AT) * CFrame.Angles(0, math.random() * math.pi, 0))
	-- sit it on whatever ground is actually there. terrain rounds to its own grid, so assuming y=0
	-- buried the rock up to its crystals
	local down = RaycastParams.new()
	down.FilterType = Enum.RaycastFilterType.Exclude
	down.FilterDescendantsInstances = { model, Players.LocalPlayer.Character }
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
	local cf, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - 0.15 - (cf.Position.Y - size.Y / 2), 0))

	local crystals = model:FindFirstChild("Crystals")
	if ore.key == "Amethyst" then
		-- the amethyst throws a little violet light onto the stone around it
		if crystals then
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(170, 90, 255)
			glow.Brightness = 0.8
			glow.Range = 7
			glow.Shadows = false
			glow.Parent = crystals
		end
	elseif crystals then
		crystals:Destroy()
	end

	model:SetAttribute("BaseScale", model:GetScale())
	model:SetAttribute("Hits", HITS)
	model.Parent = workspace
	if ore.key ~= "Amethyst" then
		setOre(model, ore)
	end

	-- the ore's name and three hit marks above the rock, a spent mark goes dim
	local _, box = model:GetBoundingBox()
	local tag = Instance.new("BillboardGui")
	tag.Name = "Pips"
	tag.Size = UDim2.fromOffset(160, 30)
	tag.StudsOffsetWorldSpace = Vector3.new(0, box.Y / 2 + 1.4, 0)
	tag.LightInfluence = 0
	tag.Parent = model.PrimaryPart
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 18)
	name.FontFace = FONT
	name.TextSize = 16
	name.TextColor3 = ore.color
	name.Text = ore.label
	name.Parent = tag
	local nameStroke = Instance.new("UIStroke", name)
	nameStroke.Transparency = 0.5
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(0, 22)
	row.Size = UDim2.new(1, 0, 0, 6)
	row.BackgroundTransparency = 1
	row.Parent = tag
	local line = Instance.new("UIListLayout", row)
	line.FillDirection = Enum.FillDirection.Horizontal
	line.HorizontalAlignment = Enum.HorizontalAlignment.Center
	line.Padding = UDim.new(0, 4)
	for i = 1, HITS do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.Size = UDim2.fromOffset(14, 4)
		pip.BackgroundColor3 = ore.color
		pip.BorderSizePixel = 0
		pip.LayoutOrder = i
		Instance.new("UICorner", pip).CornerRadius = UDim.new(1, 0)
		pip.Parent = row
	end

	placeWeakPoint(model)
	CollectBurst.popIn(model)
	return model
end

local current = spawnOre()
local busy = false

UserInputService.InputBegan:Connect(function(input, processed)
	local click = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	if processed or busy or not click then
		return
	end
	local m = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(m.X, m.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 200)
	if not (hit and hit.Instance:IsDescendantOf(current)) then
		return
	end
	local model = current
	local ore = ORE_BY_KEY[model:GetAttribute("OreType")] or ORES[3]
	local hitValue = math.max(1, math.floor(ore.value * 0.13))
	local hitsLeft = model:GetAttribute("Hits") or 1
	local cf = model:GetBoundingBox()
	local at = cf.Position
	local function spill(value, from)
		CollectBurst.drop(from, value, {
			target = rowFor(ore).icon,
			color = ore.color,
			gem = dropFor(ore),
			collector = function()
				local character = Players.LocalPlayer.Character
				return character and character:FindFirstChild("HumanoidRootPart")
			end,
			onArrive = arriveFor(ore),
		})
	end

	-- did it land on the weak point?
	local weak = model:FindFirstChild("WeakPoint")
	local core = weak and weak:FindFirstChild("Core")
	local crit = core ~= nil and (hit.Instance:IsDescendantOf(weak) or (hit.Position - core.Position).Magnitude < core.Size.Y * 0.8)
	combo = if crit then combo + 1 else 0
	updateCombo()
	local mult = if crit then comboMult() else 1

	if hitsLeft > 1 then
		-- an early hit: a tink, the rock wobbles, chips and dust and a little ore come off where you hit
		model:SetAttribute("Hits", hitsLeft - 1)
		local tag = model.PrimaryPart:FindFirstChild("Pips")
		local pip = tag and tag:FindFirstChild("Pip" .. hitsLeft, true)
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
		local value = hitValue * (if crit then CRIT_BONUS else 1) * mult
		CollectBurst.hit(model, asset("Chunk"), hit.Position, hit.Normal, if crit then 2 else 1)
		spill(value, hit.Position + hit.Normal * 0.6)
		CollectBurst.number(hit.Position + hit.Normal * 1.2, "+" .. value, if crit then CRIT_COLOR else Color3.new(1, 1, 1), crit)
		-- the weak point jumps somewhere new after every hit
		placeWeakPoint(model)
		-- a short gap between swings so spam-clicking doesn't skip the wobble
		busy = true
		task.delay(0.22, function()
			busy = false
		end)
		return
	end

	busy = true
	local value = (ore.value - hitValue * (HITS - 1)) * (if crit then 2 else 1) * mult
	play(asset("Break"), 1)
	if crit then
		play(pickup, 1.8 + 0.12 * math.min(combo, 6))
	end
	CollectBurst.number(hit.Position + hit.Normal * 1.2, "+" .. value, if crit then CRIT_COLOR else ore.color, true)
	CollectBurst.crumble(model, asset("Chunk"), function()
		spill(value, at)
		task.delay(2.5, function()
			current = spawnOre()
			busy = false
		end)
	end)
end)

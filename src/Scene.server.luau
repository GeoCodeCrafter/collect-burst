-- the showcase set: a small crystal cave. solid rock carved into a domed chamber, a shaft in the roof
-- letting one beam of sun down near the ore, amethyst growing out of the walls, and two lanterns as
-- the warm key light. everything is built here so the repo reproduces the same scene
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ORE_AT = Vector3.new(0, 0, -14)
local CENTER = Vector3.new(0, 0, -8)
local RADIUS = 30
local rng = Random.new(7)

-- ---- lighting: dark and cool inside, the sun only gets in down the shaft
Lighting.ClockTime = 12.5
Lighting.GeographicLatitude = 8 -- sun nearly overhead so it comes straight down the shaft
Lighting.Brightness = 3
Lighting.ExposureCompensation = 0.2
Lighting.Ambient = Color3.fromRGB(10, 8, 16)
Lighting.OutdoorAmbient = Color3.fromRGB(22, 20, 32)
Lighting.ColorShift_Top = Color3.fromRGB(255, 228, 190)
Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
Lighting.EnvironmentDiffuseScale = 0.25
Lighting.EnvironmentSpecularScale = 1
Lighting.ShadowSoftness = 0.08
Lighting.GlobalShadows = true

local function effect(class, props)
	local e = Lighting:FindFirstChildOfClass(class) or Instance.new(class)
	for k, v in props do
		e[k] = v
	end
	e.Parent = Lighting
	return e
end

-- a faint violet dust in the air, so the far walls fall off into darkness
effect("Atmosphere", {
	Density = 0.22,
	Offset = 0,
	Color = Color3.fromRGB(40, 32, 58),
	Decay = Color3.fromRGB(20, 14, 30),
	Glare = 0,
	Haze = 0.6,
})
effect("ColorCorrectionEffect", {
	Brightness = 0,
	Contrast = 0.2,
	Saturation = 0.1,
	TintColor = Color3.fromRGB(240, 238, 255),
})
-- only the lantern glass is bright enough to bloom. a lower threshold turned every gem into a white blob
effect("BloomEffect", { Intensity = 0.5, Size = 24, Threshold = 1.6 })
effect("SunRaysEffect", { Intensity = 0.12, Spread = 0.7 })
-- the blur only starts past the walls, the first go had it swallowing the wall crystals
effect("DepthOfFieldEffect", { Enabled = true, FarIntensity = 0.2, FocusDistance = 20, InFocusRadius = 34, NearIntensity = 0 })

-- ---- the cave, carved out of solid rock
local base = workspace:FindFirstChild("Baseplate")
if base then
	base.Transparency = 1
	base.CanCollide = false
	base.CastShadow = false
end
local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
if spawn then
	spawn.Transparency = 1
	for _, d in spawn:GetChildren() do
		if d:IsA("Decal") then
			d.Transparency = 1
		end
	end
end

local terrain = workspace.Terrain
terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(62, 58, 66))
terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(78, 72, 76))
terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(46, 40, 38))
-- a big block of rock, then the chamber scooped out of it
terrain:FillBlock(CFrame.new(CENTER + Vector3.new(0, 14, 0)), Vector3.new(RADIUS * 2 + 40, 64, RADIUS * 2 + 40), Enum.Material.Slate)
terrain:FillBall(CENTER + Vector3.new(0, 6, 0), RADIUS, Enum.Material.Air)
-- lumpy walls: bulges pushed out round the edge, a few boulders pushed back in
for i = 1, 9 do
	local a = i / 9 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
	local p = CENTER + Vector3.new(math.cos(a) * RADIUS * 0.85, rng:NextNumber(2, 10), math.sin(a) * RADIUS * 0.85)
	terrain:FillBall(p, rng:NextNumber(7, 12), Enum.Material.Air)
end
for _ = 1, 7 do
	local a = rng:NextNumber(0, math.pi * 2)
	local p = CENTER + Vector3.new(math.cos(a) * RADIUS * 0.8, 0, math.sin(a) * RADIUS * 0.8)
	terrain:FillBall(p, rng:NextNumber(3, 6), Enum.Material.Rock)
end
-- flat floor at y=0
terrain:FillBlock(CFrame.new(CENTER + Vector3.new(0, -6, 0)), Vector3.new(RADIUS * 2 + 20, 12, RADIUS * 2 + 20), Enum.Material.Ground)
-- the shaft in the roof, a little off to the side of the ore so the beam lands next to it
terrain:FillCylinder(CFrame.new(ORE_AT + Vector3.new(5, 34, 3)), 40, 4, Enum.Material.Air)

-- ---- amethyst growing out of the walls, some of it glowing
local assets = ReplicatedStorage:WaitForChild("CollectBurstAssets", 10)
local crystalTemplate = assets and assets:FindFirstChild("Rock") and assets.Rock:FindFirstChild("Crystals")
local set = Instance.new("Folder")
set.Name = "CaveSet"
set.Parent = workspace
if crystalTemplate then
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { terrain }
	-- terrain collision is built a moment after it's written. rays fired straight away went through the
	-- walls and not one crystal got placed, so wait until a test ray actually hits a wall
	for _ = 1, 100 do
		if workspace:Raycast(CENTER + Vector3.new(0, 5, 0), Vector3.new(RADIUS + 20, 0, 0), params) then
			break
		end
		task.wait(0.1)
	end
	local placed = 0
	for _ = 1, 60 do
		if placed >= 14 then
			break
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local dir = Vector3.new(math.cos(a), rng:NextNumber(-0.25, 0.35), math.sin(a)).Unit
		local from = CENTER + Vector3.new(0, 5, 0)
		local hit = workspace:Raycast(from, dir * (RADIUS + 20), params)
		if hit and (hit.Position - ORE_AT).Magnitude > 9 then
			local up = hit.Normal
			local right = up:Cross(Vector3.new(rng:NextNumber(-1, 1), 0.3, rng:NextNumber(-1, 1))).Unit
			local c = crystalTemplate:Clone()
			c.Anchored = true
			c.CanCollide = false
			-- big enough to read from the middle of the cave, and every other one glows so they show in the dark
			c.Size *= rng:NextNumber(5, 9) / math.max(c.Size.X, c.Size.Y, c.Size.Z)
			c.CFrame = CFrame.fromMatrix(hit.Position + up * c.Size.Y * 0.2, right, up)
			c.Parent = set
			if placed % 2 == 0 then
				local glow = Instance.new("PointLight")
				glow.Color = Color3.fromRGB(160, 80, 255)
				glow.Brightness = 1.8
				glow.Range = 18
				glow.Parent = c
			end
			placed += 1
		end
	end
end

-- ---- two lanterns on wooden posts either side of the ore: the warm key light
local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = set
	return p
end
for _, side in { -1, 1 } do
	local at = ORE_AT + Vector3.new(side * 6.5, 0, 2.5)
	part({ Size = Vector3.new(0.5, 6, 0.5), CFrame = CFrame.new(at + Vector3.new(0, 3, 0)), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(92, 64, 42) })
	part({ Size = Vector3.new(1.6, 0.35, 0.35), CFrame = CFrame.new(at + Vector3.new(-side * 0.6, 5.8, 0)), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(92, 64, 42) })
	local hang = at + Vector3.new(-side * 1.2, 5.0, 0)
	part({ Size = Vector3.new(0.7, 0.12, 0.7), CFrame = CFrame.new(hang + Vector3.new(0, 0.55, 0)), Material = Enum.Material.Metal, Color = Color3.fromRGB(40, 36, 34) })
	part({ Size = Vector3.new(0.7, 0.12, 0.7), CFrame = CFrame.new(hang - Vector3.new(0, 0.55, 0)), Material = Enum.Material.Metal, Color = Color3.fromRGB(40, 36, 34) })
	local glass = part({ Size = Vector3.new(0.5, 0.95, 0.5), CFrame = CFrame.new(hang), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 170, 80), CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 176, 100)
	light.Brightness = 2.2
	light.Range = 20
	light.Shadows = true
	light.Parent = glass
end

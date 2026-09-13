local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CollectBurst = {}

local GRAVITY = Vector3.new(0, -80, 0)
local GEM_SIZE = 1.2
-- how big a gem is by what it's worth
local WORTH_SCALE = { [1] = 0.75, [2] = 1, [5] = 1.35, [10] = 1.6, [25] = 1.95 }
-- fortnite-style rarity by worth. anything above common stands a beam of light up off the ground
local RARITY = {
	[1] = { color = Color3.fromRGB(190, 190, 190) },
	[2] = { color = Color3.fromRGB(96, 210, 60), beam = true },
	[5] = { color = Color3.fromRGB(60, 150, 255), beam = true },
	[10] = { color = Color3.fromRGB(190, 80, 255), beam = true },
	[25] = { color = Color3.fromRGB(255, 176, 40), beam = true },
}
-- how far in front of the camera a gem ends up when it "hits" the counter
local HUD_DEPTH = 3

local fx = Instance.new("Folder")
fx.Name = "CollectBurstFx"
fx.Parent = workspace

-- a soft puff of rock dust where something hit. roblox ships the smoke texture. no light emission, so it
-- stays dust in a dark scene instead of blooming into a glowing blob
local function dustPuff(at, normal, count, scale)
	local host = Instance.new("Part")
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.one * 0.1
	host.CFrame = CFrame.lookAt(at, at + normal) * CFrame.Angles(-math.pi / 2, 0, 0)
	host.Parent = fx
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(138, 118, 102), Color3.fromRGB(92, 80, 72))
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * scale), NumberSequenceKeypoint.new(1, 2.2 * scale) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(2 * scale, 5 * scale)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Drag = 4
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = host
	e:Emit(count)
	task.delay(1.5, function()
		host:Destroy()
	end)
end

local function bezier(a, b, c, t)
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

-- splits `value` into gems worth 5, 2 and 1 so a big haul is a few chunky ones and a spray of small ones
local function split(value)
	local out = {}
	local left = value
	while left > 0 do
		-- the odd epic and the rare legendary are what make every hit worth watching
		local w = if left >= 25 and math.random() < 0.03 then 25
			elseif left >= 10 and math.random() < 0.1 then 10
			elseif left >= 5 and math.random() < 0.4 then 5
			elseif left >= 2 and math.random() < 0.5 then 2
			else 1
		table.insert(out, w)
		left -= w
	end
	return out
end

-- anything can be a gem or a rock: a Part, a MeshPart or a whole Model. parts get wrapped so
-- everything else can just use Model:PivotTo and Model:ScaleTo
function CollectBurst.asModel(template)
	local clone = template:Clone()
	local model = clone
	if not clone:IsA("Model") then
		model = Instance.new("Model")
		clone.Parent = model
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return model
end

-- store assets come in at any size, this makes the biggest side `size` studs
function CollectBurst.fit(model, size)
	local _, s = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * size / math.max(s.X, s.Y, s.Z))
end

-- a ViewportFrame with the model in it, lit from the top left so the facets read. for a HUD icon
-- that's the real thing rather than a drawing of it
function CollectBurst.icon3d(template)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(95, 85, 115)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -1.4, -0.8)
	local model = CollectBurst.asModel(template)
	model:PivotTo(CFrame.Angles(math.rad(15), math.rad(35), 0))
	local cf, size = model:GetBoundingBox()
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local dist = math.max(size.X, size.Y, size.Z) / 2 / math.tan(math.rad(15)) * 1.1
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, 0, dist), cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- grows a model in from nothing with a little overshoot, back to whatever scale it had
function CollectBurst.popIn(model, duration)
	duration = duration or 0.35
	local base = model:GetScale()
	local t = 0
	local conn
	model:ScaleTo(base * 0.01)
	conn = RunService.RenderStepped:Connect(function(dt)
		t = math.min(t + dt / duration, 1)
		-- back-out: shoots past 1 and settles
		local s = 1 + 2.7 * (t - 1) ^ 3 + 1.7 * (t - 1) ^ 2
		model:ScaleTo(base * math.max(0.01, s))
		if t >= 1 then
			conn:Disconnect()
		end
	end)
end

-- the rock squashes a touch, then shrinks away while chunks of it tumble onto the ground and fade.
-- `chunk` is optional: a part, or a model/folder of rocks to pick from at random. calls `onDone`
-- once the rock is gone
function CollectBurst.crumble(model, chunk, onDone)
	local cf, size = model:GetBoundingBox()
	-- rubble and dust scale with the rock, a big rock breaks into big pieces
	local k = math.max(size.X, size.Z) / 4.5
	dustPuff(cf.Position, Vector3.yAxis, 18, 1.6 * k)
	local sources = {}
	if chunk then
		if chunk:IsA("BasePart") then
			sources = { chunk }
		else
			for _, d in chunk:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(sources, d)
				end
			end
		end
	end

	for _ = 1, 7 do
		local c
		local target = (0.5 + math.random() * 0.6) * k
		if #sources > 0 then
			c = sources[math.random(#sources)]:Clone()
			for _, k in c:GetChildren() do
				if not k:IsA("SurfaceAppearance") then
					k:Destroy()
				end
			end
			c.Size *= target / math.max(c.Size.X, c.Size.Y, c.Size.Z)
		else
			c = Instance.new("Part")
			c.Size = Vector3.one * target
			c.Material = Enum.Material.Slate
			c.Color = Color3.fromRGB(95, 90, 88)
		end
		c.Anchored = false
		c.CanCollide = true
		c.CanTouch = false
		c.CFrame = cf
			* CFrame.new((math.random() - 0.5) * size.X * 0.6, (math.random() - 0.3) * size.Y * 0.5, (math.random() - 0.5) * size.Z * 0.6)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		c.Parent = fx
		c.AssemblyLinearVelocity = Vector3.new(math.random() - 0.5, 0.4 + math.random() * 0.6, math.random() - 0.5) * 16
		c.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16
		task.delay(1.1 + math.random() * 0.5, function()
			local fade = TweenService:Create(c, TweenInfo.new(0.4), { Transparency = 1 })
			fade.Completed:Connect(function()
				c:Destroy()
			end)
			fade:Play()
		end)
	end

	local base = model:GetScale()
	local t = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t = math.min(t + dt / 0.16, 1)
		local s = if t < 0.35 then 1 - 0.08 * t / 0.35 else 0.92 * (1 - (t - 0.35) / 0.65)
		model:ScaleTo(base * math.max(0.01, s))
		if t >= 1 then
			conn:Disconnect()
			model:Destroy()
			if onDone then
				onDone()
			end
		end
	end)
end

-- one pick hit: the rock dips, springs back past its size and settles, and a few chips and some dust
-- come off where it was hit. `at` and `normal` are that spot and the face's direction, from the click's
-- raycast. leave them out and the chips come off the top. the wobble always settles back to the size it
-- spawned at, even if you hit it again mid-wobble
function CollectBurst.hit(model, chunk, at, normal, power)
	local cf, size = model:GetBoundingBox()
	at = at or (cf.Position + Vector3.new(0, size.Y * 0.35, 0))
	normal = normal or Vector3.yAxis
	-- power 2 is a crit: twice the chips and dust and a harder wobble
	power = power or 1
	local k = math.max(size.X, size.Z) / 4.5
	dustPuff(at, normal, math.floor(10 * power), (0.8 + 0.2 * power) * k)
	local sources = {}
	if chunk then
		if chunk:IsA("BasePart") then
			sources = { chunk }
		else
			for _, d in chunk:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(sources, d)
				end
			end
		end
	end
	for _ = 1, 3 * power do
		local target = (0.22 + math.random() * 0.25) * k
		local c
		if #sources > 0 then
			c = sources[math.random(#sources)]:Clone()
			for _, k in c:GetChildren() do
				if not k:IsA("SurfaceAppearance") then
					k:Destroy()
				end
			end
			c.Size *= target / math.max(c.Size.X, c.Size.Y, c.Size.Z)
		else
			c = Instance.new("Part")
			c.Size = Vector3.one * target
			c.Material = Enum.Material.Slate
			c.Color = Color3.fromRGB(95, 90, 88)
		end
		c.Anchored = false
		c.CanCollide = true
		c.CanTouch = false
		-- chips come off the spot that was hit and fly out from that face, with a bit of lift
		c.CFrame = CFrame.new(at + normal * (c.Size.Y * 0.6)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		c.Parent = fx
		local spread = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.9
		c.AssemblyLinearVelocity = (normal + spread + Vector3.new(0, 0.6, 0)).Unit * (11 + math.random() * 6)
		c.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		task.delay(0.7 + math.random() * 0.4, function()
			local fade = TweenService:Create(c, TweenInfo.new(0.35), { Transparency = 1 })
			fade.Completed:Connect(function()
				c:Destroy()
			end)
			fade:Play()
		end)
	end

	local base = model:GetAttribute("BaseScale") or model:GetScale()
	model:SetAttribute("BaseScale", base)
	local token = (model:GetAttribute("HitToken") or 0) + 1
	model:SetAttribute("HitToken", token)
	local t = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		-- a newer hit takes over the wobble, and a rock that's been broken stops here
		if model:GetAttribute("HitToken") ~= token or not model.Parent then
			conn:Disconnect()
			return
		end
		t = math.min(t + dt / 0.3, 1)
		-- dips straight away, springs back past its size, settles
		model:ScaleTo(base * (1 - 0.07 * (0.7 + 0.3 * power) * math.exp(-6 * t) * math.cos(t * 18)))
		if t >= 1 then
			model:ScaleTo(base)
			conn:Disconnect()
		end
	end)
end

-- a fortnite-style number popping off a hit: chunky and outlined, pops big, settles, drifts up and fades
function CollectBurst.number(at, text, color, big)
	local host = Instance.new("Part")
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.one * 0.1
	host.CFrame = CFrame.new(at)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 80)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = host
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	label.Text = text
	label.TextSize = if big then 56 else 40
	label.TextColor3 = color
	label.Rotation = -6
	label.Parent = bb
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if big then 4 else 3
	stroke.Color = Color3.fromRGB(20, 14, 30)
	stroke.Parent = label
	local pop = Instance.new("UIScale")
	pop.Scale = 0.2
	pop.Parent = label
	host.Parent = fx
	TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local drift = Vector3.new((math.random() - 0.5) * 1.6, 3, (math.random() - 0.5) * 1.6)
	TweenService:Create(host, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = host.CFrame + drift }):Play()
	task.delay(0.55, function()
		local out = TweenInfo.new(0.35)
		TweenService:Create(label, out, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, out, { Transparency = 1 }):Play()
		task.delay(0.4, function()
			host:Destroy()
		end)
	end)
end

-- a loot beam standing up off the ground under a gem, in its rarity colour
local function lootBeam(color, height)
	local host = Instance.new("Part")
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.one * 0.1
	local a0 = Instance.new("Attachment")
	a0.Parent = host
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, height, 0)
	a1.Parent = host
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Width0 = 0
	beam.Width1 = 0
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = host
	host.Parent = fx
	TweenService:Create(beam, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Width0 = 0.7, Width1 = 0.25 }):Play()
	return host
end

local function placeholderGem(color)
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.9, 0.9, 0.9)
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	return p
end

local function addTrail(part, color)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.14
	trail.LightEmission = 0.4
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.45, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Enabled = false
	trail.Parent = part
	return trail
end

-- a small glint when a gem hits the ground. kept dim: in a dark scene bright sparkles bloom into blobs
local function addSparkle(part, color)
	local a = Instance.new("Attachment")
	a.Parent = part
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 0.25
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Lifetime = NumberRange.new(0.2, 0.35)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 6
	e.Rate = 0
	e.Parent = a
	return e
end

-- `value` worth of gems pop out of `origin`, bounce on the ground, then get pulled into whatever
-- `opts.collector()` returns (usually the player's root part). when a gem reaches it, the gem itself
-- keeps flying, up into `opts.target` (a GuiObject) on screen, shrinking as it goes, so it looks
-- like the real thing lands in the counter.
-- opts: target, collector, color, gem (template, optional), onArrive(worth, n, total)
function CollectBurst.drop(origin, value, opts)
	local camera = workspace.CurrentCamera
	local gui = opts.target:FindFirstAncestorOfClass("ScreenGui")
	local inset = if gui.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local worths = split(value)
	local gems = {}
	for i, worth in worths do
		local model = CollectBurst.asModel(opts.gem or placeholderGem(opts.color))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = true
			elseif d:IsA("Light") then
				d:Destroy()
			end
		end
		CollectBurst.fit(model, GEM_SIZE * WORTH_SCALE[worth])
		local _, size = model:GetBoundingBox()
		model.Parent = fx
		table.insert(gems, {
			model = model,
			base = model:GetScale(),
			worth = worth,
			r = size.Y / 2,
			trail = addTrail(model.PrimaryPart, if RARITY[worth].beam then RARITY[worth].color else opts.color),
			sparkle = addSparkle(model.PrimaryPart, opts.color),
			pos = origin,
			vel = Vector3.new((math.random() - 0.5) * 22, 20 + math.random() * 12, (math.random() - 0.5) * 22),
			spin = 2 + math.random() * 3,
			tilt = Vector3.new(math.random() * 0.6, 0, math.random() * 0.6),
			age = 0,
			-- they sit on the ground for a beat, then get pulled in one after another
			-- long enough on the ground for the loot beams to read
			magnetAt = 1.5 + i * 0.05,
			speed = 0,
		})
	end

	local arrived = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local root = opts.collector and opts.collector()
		params.FilterDescendantsInstances = { fx, root and root.Parent }
		local alive = 0
		for _, g in gems do
			if g.done then
				continue
			end
			alive += 1
			g.age += dt
			local extraSpin = 0

			if g.flying then
				-- the last leg: from where it was picked up to a point just in front of the camera,
				-- lined up with the counter. ease in, so it speeds up and snaps into the HUD
				g.t = math.min(g.t + dt / g.dur, 1)
				local hud = opts.target.AbsolutePosition + opts.target.AbsoluteSize / 2 + inset
				local ray = camera:ViewportPointToRay(hud.X, hud.Y)
				local to = ray.Origin + ray.Direction * HUD_DEPTH
				local e = g.t * g.t
				g.pos = bezier(g.from, g.from + Vector3.new(0, 4, 0), to, e)
				g.model:ScaleTo(g.base * (1 - 0.8 * e))
				extraSpin = 8 * e
				if g.t >= 1 then
					g.model:Destroy()
					g.model = nil
					g.done = true
					arrived += 1
					if opts.onArrive then
						opts.onArrive(g.worth, arrived, #gems)
					end
					continue
				end
			elseif g.age < g.magnetAt or not root then
				-- bouncing: fall, and when the ground is under it, bounce with less each time
				g.vel += GRAVITY * dt
				local step = g.vel * dt
				local hit = workspace:Raycast(g.pos, Vector3.new(0, math.min(step.Y, 0) - g.r, 0), params)
				g.pos += step
				if hit and g.pos.Y - g.r < hit.Position.Y then
					g.pos = Vector3.new(g.pos.X, hit.Position.Y + g.r, g.pos.Z)
					local impact = math.abs(g.vel.Y)
					-- harder landings throw a few more glints, resting on the ground throws none
					if impact > 14 then
						g.sparkle:Emit(math.clamp(math.floor(impact / 8), 1, 4))
					end
					local up = impact * 0.4
					g.vel = Vector3.new(g.vel.X * 0.55, if up < 4 then 0 else up, g.vel.Z * 0.55)
					if up < 4 and not g.landedAt then
						g.landedAt = g.age
						local rarity = RARITY[g.worth]
						if rarity.beam then
							g.beamHost = lootBeam(rarity.color, 3 + g.worth * 0.2)
						end
					end
				end
			else
				-- magnet: speeds up towards you
				g.trail.Enabled = true
				if g.beamHost then
					g.beamHost:Destroy()
					g.beamHost = nil
				end
				local d = root.Position - g.pos
				g.speed = math.min(g.speed + 140 * dt, 100)
				if d.Magnitude < 2 or d.Magnitude < g.speed * dt then
					g.flying = true
					g.from = g.pos
					g.t = 0
					g.dur = 0.38 + math.random() * 0.14
				else
					g.pos += d.Unit * g.speed * dt
				end
			end

			if g.beamHost then
				g.beamHost.CFrame = CFrame.new(g.pos - Vector3.new(0, g.r, 0))
			end
			-- once it's settled it floats up off the ground and bobs until it gets pulled in
			local bob = if g.landedAt and not g.trail.Enabled then 0.15 * (1 - math.cos((g.age - g.landedAt) * 7)) else 0
			g.model:PivotTo(CFrame.new(g.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(g.tilt.X, g.age * (g.spin + extraSpin), g.tilt.Z))
		end
		if alive == 0 then
			conn:Disconnect()
		end
	end)
end

return CollectBurst

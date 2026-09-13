local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CollectBurst = {}

local GRAVITY = Vector3.new(0, -80, 0)
local GEM_SIZE = 1.2
-- how big a gem is by what it's worth
local WORTH_SCALE = { [1] = 0.75, [2] = 1, [5] = 1.35 }
local ICON_PX = { [1] = 22, [2] = 28, [5] = 36 }

local fx = Instance.new("Folder")
fx.Name = "CollectBurstFx"
fx.Parent = workspace

local function bezier(a, b, c, t)
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

-- splits `value` into gems worth 5, 2 and 1 so a big haul is a few chunky ones and a spray of small ones
local function split(value)
	local out = {}
	local left = value
	while left > 0 do
		local w = if left >= 5 and math.random() < 0.4 then 5 elseif left >= 2 and math.random() < 0.5 then 2 else 1
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

-- a ViewportFrame with the model in it, lit and angled so you see the facets. used for the counter
-- icon and the pieces flying into it, so they're the actual gem instead of a flat picture
function CollectBurst.icon3d(template)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(190, 190, 200)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -1, -1)
	local model = CollectBurst.asModel(template)
	model:PivotTo(CFrame.Angles(math.rad(20), math.rad(30), 0))
	local cf, size = model:GetBoundingBox()
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local dist = math.max(size.X, size.Y, size.Z) / 2 / math.tan(math.rad(15)) * 1.15
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
		local target = 0.5 + math.random() * 0.6
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

local function placeholderGem(color)
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.9, 0.9, 0.9)
	p.Material = Enum.Material.Neon
	p.Color = color
	return p
end

local function addTrail(part, color)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.18
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Enabled = false
	trail.Parent = part
	return trail
end

-- a little glint when a gem hits the ground. roblox ships this texture so there's nothing to upload
local function addSparkle(part, color)
	local a = Instance.new("Attachment")
	a.Parent = part
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.Lifetime = NumberRange.new(0.25, 0.45)
	e.Speed = NumberRange.new(3, 7)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 6
	e.Rate = 0
	e.Parent = a
	return e
end

-- `value` worth of gems pop out of `origin`, bounce on the ground, then get pulled into whatever
-- `opts.collector()` returns (usually the player's root part). when a gem reaches it, it jumps onto
-- the screen and flies into `opts.target` (a GuiObject).
-- opts: target, collector, color, gem (template, optional), icon (image id, optional),
--       iconModel (template to show as a 3D icon, optional), onArrive(worth, n, total)
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
			end
		end
		CollectBurst.fit(model, GEM_SIZE * WORTH_SCALE[worth])
		local _, size = model:GetBoundingBox()
		model.Parent = fx
		table.insert(gems, {
			model = model,
			worth = worth,
			r = size.Y / 2,
			trail = addTrail(model.PrimaryPart, opts.color),
			sparkle = addSparkle(model.PrimaryPart, opts.color),
			pos = origin,
			vel = Vector3.new((math.random() - 0.5) * 22, 20 + math.random() * 12, (math.random() - 0.5) * 22),
			spin = 2 + math.random() * 3,
			age = 0,
			-- they sit on the ground for a beat, then get pulled in one after another
			magnetAt = 0.95 + i * 0.04,
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

			if g.icon then
				g.t += dt / g.dur
				local k = math.min(g.t, 1)
				local to = opts.target.AbsolutePosition + opts.target.AbsoluteSize / 2
				local at = bezier(g.from, g.ctrl, to, k * k)
				local s = ICON_PX[g.worth] * (1.2 - 0.4 * k)
				g.icon.Position = UDim2.fromOffset(at.X, at.Y)
				g.icon.Size = UDim2.fromOffset(s, s)
				g.icon.Rotation += 360 * dt
				if g.t >= 1 then
					g.icon:Destroy()
					g.done = true
					arrived += 1
					if opts.onArrive then
						opts.onArrive(g.worth, arrived, #gems)
					end
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
					-- harder landings throw more sparkles, resting on the ground throws none
					if impact > 12 then
						g.sparkle:Emit(math.clamp(math.floor(impact / 5), 2, 8))
					end
					local up = impact * 0.4
					g.vel = Vector3.new(g.vel.X * 0.55, if up < 4 then 0 else up, g.vel.Z * 0.55)
					if up < 4 and not g.landedAt then
						g.landedAt = g.age
					end
				end
			else
				-- magnet: speeds up towards you
				g.trail.Enabled = true
				local d = root.Position - g.pos
				g.speed = math.min(g.speed + 140 * dt, 100)
				if d.Magnitude < 1.5 or d.Magnitude < g.speed * dt then
					-- picked up: swap the gem for a 2D piece at the same spot on screen
					local screen = camera:WorldToViewportPoint(g.pos)
					local icon
					if opts.iconModel then
						icon = CollectBurst.icon3d(opts.iconModel)
					elseif opts.icon then
						icon = Instance.new("ImageLabel")
						icon.Image = opts.icon
						icon.BackgroundTransparency = 1
					else
						icon = Instance.new("Frame")
						icon.Rotation = 45
						icon.BackgroundColor3 = opts.color
						icon.BorderSizePixel = 0
						local stroke = Instance.new("UIStroke")
						stroke.Color = Color3.new(1, 1, 1)
						stroke.Thickness = 1.5
						stroke.Parent = icon
					end
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.Parent = gui
					g.model:Destroy()
					g.model = nil
					g.icon = icon
					g.from = Vector2.new(screen.X, screen.Y) - inset
					g.ctrl = g.from + Vector2.new((math.random() - 0.5) * 160, -80 - math.random() * 80)
					g.t = 0
					g.dur = 0.35 + math.random() * 0.15
					icon.Position = UDim2.fromOffset(g.from.X, g.from.Y)
				else
					g.pos += d.Unit * g.speed * dt
				end
			end

			if g.model then
				-- once it's settled it floats up off the ground and bobs until it gets pulled in
				local bob = if g.landedAt and not g.trail.Enabled then 0.15 * (1 - math.cos((g.age - g.landedAt) * 7)) else 0
				g.model:PivotTo(CFrame.new(g.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, g.age * g.spin, 0.35))
			end
		end
		if alive == 0 then
			conn:Disconnect()
		end
	end)
end

return CollectBurst

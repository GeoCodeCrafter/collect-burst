local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CollectBurst = {}

local GRAVITY = Vector3.new(0, -80, 0)
-- how big a gem is compared to the template, by what it's worth
local WORTH_SCALE = { [1] = 0.75, [2] = 1, [5] = 1.35 }
local ICON_PX = { [1] = 18, [2] = 22, [5] = 30 }

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

-- grows a model in from nothing with a little overshoot
function CollectBurst.popIn(model, duration)
	duration = duration or 0.35
	local t = 0
	local conn
	model:ScaleTo(0.01)
	conn = RunService.RenderStepped:Connect(function(dt)
		t = math.min(t + dt / duration, 1)
		-- back-out: shoots past 1 and settles
		local s = 1 + 2.7 * (t - 1) ^ 3 + 1.7 * (t - 1) ^ 2
		model:ScaleTo(math.max(0.01, s))
		if t >= 1 then
			conn:Disconnect()
		end
	end)
end

-- the rock squashes a touch, then shrinks away while chunks of it tumble onto the ground and fade.
-- `chunk` is optional, a BasePart to use for the bits. calls `onDone` once the rock is gone
function CollectBurst.crumble(model, chunk, onDone)
	local cf, size = model:GetBoundingBox()
	for _ = 1, 6 do
		local c
		if chunk then
			c = (if chunk:IsA("BasePart") then chunk else chunk:FindFirstChildWhichIsA("BasePart", true)):Clone()
			c.Size *= 0.7 + math.random() * 0.5
		else
			c = Instance.new("Part")
			c.Size = Vector3.one * (0.5 + math.random() * 0.6)
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

	local t = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t = math.min(t + dt / 0.16, 1)
		local s = if t < 0.35 then 1 - 0.08 * t / 0.35 else 0.92 * (1 - (t - 0.35) / 0.65)
		model:ScaleTo(math.max(0.01, s))
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

-- `value` worth of gems pop out of `origin`, bounce on the ground, then get pulled into whatever
-- `opts.collector()` returns (usually the player's root part). when a gem reaches it, it jumps onto
-- the screen and flies into `opts.target` (a GuiObject).
-- opts: target, collector, color, gem (template, optional), icon (image id, optional),
--       onArrive(worth, n, total) runs as each one lands on the counter
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
		model:ScaleTo(WORTH_SCALE[worth])
		local _, size = model:GetBoundingBox()
		model.Parent = fx
		table.insert(gems, {
			model = model,
			worth = worth,
			r = size.Y / 2,
			trail = addTrail(model.PrimaryPart, opts.color),
			pos = origin,
			vel = Vector3.new((math.random() - 0.5) * 22, 20 + math.random() * 12, (math.random() - 0.5) * 22),
			spin = 2 + math.random() * 3,
			age = 0,
			-- they sit on the ground for a beat, then get pulled in one after another
			magnetAt = 0.8 + i * 0.04,
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
					local up = math.abs(g.vel.Y) * 0.4
					g.vel = Vector3.new(g.vel.X * 0.55, if up < 4 then 0 else up, g.vel.Z * 0.55)
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
					if opts.icon then
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
				g.model:PivotTo(CFrame.new(g.pos) * CFrame.Angles(0, g.age * g.spin, 0.35))
			end
		end
		if alive == 0 then
			conn:Disconnect()
		end
	end)
end

return CollectBurst

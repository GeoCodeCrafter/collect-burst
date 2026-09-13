local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CollectBurst = {}

local GRAVITY = Vector3.new(0, -60, 0)
local CRACK_TIME = 0.18

local function bezier(a, b, c, t)
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

-- shakes and swells `model` for a split second while it goes white, then calls `onBreak`.
-- that little wind-up before the burst is most of what makes it feel heavy
function CollectBurst.crack(model, onBreak)
	local pivot = model:GetPivot()
	local flash = Instance.new("Highlight")
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 1
	flash.OutlineTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Parent = model

	local t = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local k = math.min(t / CRACK_TIME, 1)
		local j = 0.3 * k
		model:ScaleTo(1 + 0.12 * k)
		model:PivotTo(pivot * CFrame.new((math.random() - 0.5) * j, (math.random() - 0.5) * j, (math.random() - 0.5) * j))
		flash.FillTransparency = 1 - 0.85 * k
		if k >= 1 then
			conn:Disconnect()
			onBreak()
		end
	end)
end

-- a short camera kick that fades out. strength is in degrees
function CollectBurst.shake(strength, duration)
	local t = 0
	local name = "CollectBurstShake" .. math.random(1e9)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt)
		t += dt
		local k = 1 - t / duration
		if k <= 0 then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local a = strength * k * k
		workspace.CurrentCamera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * a), math.rad((math.random() - 0.5) * a), 0)
	end)
end

-- `count` pieces pop out of `origin` in the world, hang there for a moment, then fly across the screen
-- into `target` (any GuiObject). `onArrive` runs once per piece as it lands, bump your counter there
function CollectBurst.burst(origin, count, color, target, onArrive)
	local camera = workspace.CurrentCamera
	local gui = target:FindFirstAncestorOfClass("ScreenGui")
	local inset = if gui.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()

	-- white puff where it broke
	local puff = Instance.new("Part")
	puff.Shape = Enum.PartType.Ball
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.CanTouch = false
	puff.Material = Enum.Material.Neon
	puff.Color = Color3.new(1, 1, 1)
	puff.Size = Vector3.one * 2
	puff.Position = origin
	puff.Parent = workspace
	local grow = TweenService:Create(puff, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 7,
		Transparency = 1,
	})
	grow.Completed:Connect(function()
		puff:Destroy()
	end)
	grow:Play()

	local pieces = {}
	for _ = 1, count do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Size = Vector3.one * (0.4 + math.random() * 0.4)
		part.Parent = workspace
		local dir = Vector3.new(math.random() - 0.5, 0.6 + math.random(), math.random() - 0.5).Unit
		table.insert(pieces, {
			part = part,
			pos = origin,
			vel = dir * (18 + math.random() * 14),
			spin = Vector3.new(math.random(), math.random(), math.random()) * 12,
			age = 0,
			hang = 0.35 + math.random() * 0.25,
		})
	end

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local alive = 0
		for _, p in pieces do
			if p.done then
				continue
			end
			alive += 1
			p.age += dt

			if p.part then
				p.vel = (p.vel + GRAVITY * dt) * (1 - 2 * dt)
				p.pos += p.vel * dt
				p.part.CFrame = CFrame.new(p.pos) * CFrame.Angles(p.spin.X * p.age, p.spin.Y * p.age, p.spin.Z * p.age)
				if p.age >= p.hang then
					-- swap the 3D piece for a 2D one at the same spot on screen, then fly that to the target
					local screen = camera:WorldToViewportPoint(p.pos)
					local icon = Instance.new("Frame")
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.Size = UDim2.fromOffset(16, 16)
					icon.Rotation = 45
					icon.BackgroundColor3 = color
					icon.BorderSizePixel = 0
					icon.Parent = gui
					p.part:Destroy()
					p.part = nil
					p.icon = icon
					p.from = Vector2.new(screen.X, screen.Y) - inset
					p.ctrl = p.from + Vector2.new((math.random() - 0.5) * 300, -120 - math.random() * 120)
					p.t = 0
					p.dur = 0.45 + math.random() * 0.2
					icon.Position = UDim2.fromOffset(p.from.X, p.from.Y)
				end
			else
				p.t += dt / p.dur
				local to = target.AbsolutePosition + target.AbsoluteSize / 2
				-- ease in so it speeds up into the counter
				local at = bezier(p.from, p.ctrl, to, math.min(p.t, 1) ^ 2)
				p.icon.Position = UDim2.fromOffset(at.X, at.Y)
				p.icon.Rotation += 540 * dt
				if p.t >= 1 then
					p.icon:Destroy()
					p.done = true
					if onArrive then
						onArrive()
					end
				end
			end
		end
		if alive == 0 then
			conn:Disconnect()
		end
	end)
end

return CollectBurst

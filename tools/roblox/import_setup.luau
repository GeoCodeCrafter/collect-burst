-- run in the command bar after File > Import 3D of assets/collect_burst_assets.fbx. sorts the import into
-- ReplicatedStorage.CollectBurstAssets: Rock (four textured quarters + Crystals), Variants (V01..V10, same
-- layout), Chunk, Gem. whatever was there before is kept in ServerStorage.OldStoreAssets
local rs = game:GetService("ReplicatedStorage")
local ss = game:GetService("ServerStorage")

local imported
for _, m in workspace:GetDescendants() do
	if m:IsA("Model") and m:FindFirstChild("RockA", true) and m:FindFirstChild("Gem", true) then
		imported = m
		break
	end
end
if not imported then
	return "no imported model found (looking for one with RockA and Gem in it)"
end
local function part(name)
	local p = imported:FindFirstChild(name, true)
	return p and (if p:IsA("BasePart") then p else p:FindFirstChildWhichIsA("BasePart", true))
end
for _, d in imported:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		d:Destroy()
	end
end

local f = rs:FindFirstChild("CollectBurstAssets") or Instance.new("Folder")
f.Name = "CollectBurstAssets"
f.Parent = rs
local old = ss:FindFirstChild("OldStoreAssets") or Instance.new("Folder")
old.Name = "OldStoreAssets"
old.Parent = ss
for _, n in { "Rock", "Gem", "Chunk", "Variants" } do
	local x = f:FindFirstChild(n)
	if x then
		x.Parent = old
	end
end

-- a rock is its four quarters plus its crystals, pivoting upright at the middle
local function buildRock(name, prefix)
	local model = Instance.new("Model")
	model.Name = name
	for _, letter in { "A", "B", "C", "D" } do
		local p = part(prefix .. "Rock" .. letter)
		if p then
			p.Name = "Rock" .. letter
			p.Parent = model
		end
	end
	local crystals = part(prefix .. "Crystals")
	if crystals then
		crystals.Name = "Crystals"
		crystals.Parent = model
	end
	model.PrimaryPart = model:FindFirstChild("RockA")
	return model
end

local out = {}
local rock = buildRock("Rock", "")
rock.Parent = f
table.insert(out, "Rock: " .. #rock:GetChildren() .. " parts")

local variants = Instance.new("Folder")
variants.Name = "Variants"
variants.Parent = f
for v = 1, 10 do
	local tag = string.format("V%02d", v)
	local m = buildRock(tag, tag .. "_")
	if m.PrimaryPart then
		m.Parent = variants
	end
end
table.insert(out, "Variants: " .. #variants:GetChildren())

local chunk = Instance.new("Model")
chunk.Name = "Chunk"
local c1 = part("Chunk1")
if c1 then
	c1.Parent = chunk
end
chunk.Parent = f
local gem = part("Gem")
if gem then
	gem.Material = Enum.Material.Glass
	gem.Color = Color3.fromRGB(150, 70, 235)
	gem.Reflectance = 0.4
	gem.Parent = f
end

-- the importer leaves each part's PivotOffset rotated 90 for blender's Z-up, and a model with a PrimaryPart
-- uses that part's offset (WorldPivot is ignored), which tipped the rock on its side. reset them all, put
-- each rock's pivot upright at its middle, and keep every mesh at full detail
for _, d in f:GetDescendants() do
	if d:IsA("BasePart") then
		d.PivotOffset = CFrame.new()
		d.Anchored = true
	end
	if d:IsA("MeshPart") then
		pcall(function()
			d.RenderFidelity = Enum.RenderFidelity.Precise
		end)
	end
end
for _, m in { rock, table.unpack(variants:GetChildren()) } do
	if m.PrimaryPart then
		m.PrimaryPart.PivotOffset = m.PrimaryPart.CFrame:Inverse() * CFrame.new(m:GetBoundingBox().Position)
	end
end

local sa = rock:FindFirstChild("RockA") and rock.RockA:FindFirstChildWhichIsA("SurfaceAppearance")
table.insert(out, "RockA textures: " .. (if sa then "PBR" else "MISSING"))
imported:Destroy()
return table.concat(out, " | ")

-- after Import 3D of collect_burst_assets.fbx: move the meshes into CollectBurstAssets and set materials
local rs = game:GetService("ReplicatedStorage")
local ss = game:GetService("ServerStorage")

local imported
for _, m in workspace:GetDescendants() do
	if m:IsA("Model") and m:FindFirstChild("Rock", true) and m:FindFirstChild("Gem", true) and m:FindFirstChild("Chunk1", true) then
		imported = m
		break
	end
end
if not imported then
	return "no imported model found"
end
local function part(name)
	local p = imported:FindFirstChild(name, true)
	return p and (if p:IsA("BasePart") then p else p:FindFirstChildWhichIsA("BasePart", true))
end

local out = {}
for _, d in imported:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		d:Destroy()
	end
end

local f = rs:FindFirstChild("CollectBurstAssets") or Instance.new("Folder")
f.Name = "CollectBurstAssets"
f.Parent = rs
-- keep the old store picks around rather than deleting them
local old = ss:FindFirstChild("OldStoreAssets") or Instance.new("Folder")
old.Name = "OldStoreAssets"
old.Parent = ss
for _, n in { "Rock", "Gem", "Chunk" } do
	local x = f:FindFirstChild(n)
	if x then
		x.Parent = old
	end
end

local AMETHYST = Color3.fromRGB(150, 70, 235)
local function glass(p, transparency)
	p.Material = Enum.Material.Glass
	p.Color = AMETHYST
	p.Transparency = transparency
	p.Reflectance = 0.15
	local sa = p:FindFirstChildWhichIsA("SurfaceAppearance")
	if sa then
		sa:Destroy()
	end
end

local rock, crystals = part("Rock"), part("Crystals")
local rockModel = Instance.new("Model")
rockModel.Name = "Rock"
rock.Parent = rockModel
if crystals then
	-- crystals now bring their own baked colour/roughness. keep that instead of flat glass
	if not crystals:FindFirstChildWhichIsA("SurfaceAppearance") then
		glass(crystals, 0)
		crystals.Reflectance = 0.4
	end
	crystals.Parent = rockModel
end
rockModel.PrimaryPart = rock
rockModel.Parent = f

local gem = part("Gem")
-- see-through glass has nothing to show through in an empty scene, so the facets vanish.
-- solid with some shine catches light on each facet
glass(gem, 0)
gem.Reflectance = 0.4
gem.Name = "Gem"
gem.Parent = f

local chunk = Instance.new("Model")
chunk.Name = "Chunk"
for i = 1, 3 do
	local c = part("Chunk" .. i)
	if c then
		c.Parent = chunk
	end
end
chunk.Parent = f

for _, p in { rock, gem, crystals } do
	if p then
		table.insert(out, string.format("%s %s tris~%s surface=%s", p.Name, p.ClassName, "?", p:FindFirstChildWhichIsA("SurfaceAppearance") and "PBR textures" or (p:IsA("MeshPart") and p.TextureID ~= "" and "colour texture only" or "none")))
	end
end
local c1 = chunk:FindFirstChildWhichIsA("BasePart")
table.insert(out, "chunks " .. #chunk:GetChildren() .. " surface=" .. (c1 and c1:FindFirstChildWhichIsA("SurfaceAppearance") and "PBR textures" or "none"))
-- the importer leaves each part's PivotOffset rotated 90 for blender's Z-up. a model with a PrimaryPart
-- uses that part's offset (WorldPivot is ignored), so placing it upright tipped the rock onto its side
for _, d in f:GetDescendants() do
	if d:IsA("BasePart") then
		d.PivotOffset = CFrame.new()
	end
end
rock.PivotOffset = rock.CFrame:Inverse() * CFrame.new(rockModel:GetBoundingBox().Position)
imported:Destroy()
return table.concat(out, " | ")
